--[[
    dlac/feature/eboxclient.lua -- THE one client for CatsEyeXI's E-Box.

    ADR 0016 (one E-Box client): exactly ONE module speaks the custom 0x1A4
    wire protocol; every E-Box feature (AutoAmmo's counts, E-Box Restock, and
    whatever comes next) is a thin CONSUMER over the shared, throttled state
    here -- never a second speaker. This is the reusable door
    docs/design/ebox-restock.md is built on.

    The wire is the trove addon's format (trove/utils/packet.lua +
    plugins/ebox.lua), reimplemented here with plain string.byte / byte-math
    (no struct, no bit) so every path runs headless (tests EBC*), exactly as
    feature/eboxammo did for the ammo slice. eboxammo becomes an adapter over
    this module (the refactor step; its EB* tests + parity pins guard it).

    What this owns:
      * the whole protocol -- GET_SUMMARY/SUMMARY, GET_CATEGORY, SEARCH,
        WITHDRAW + ACK, LOCKED, and the CLEAR/ITEM/END_LIST stream that carries
        the lists;
      * a SHARED multi-category counts cache (M.cat[ahCat] authoritative +
        M.counts flat merged view) with per-category freshness stamps -- so
        AutoAmmo's category 15 is fetched ONCE and read by every consumer;
      * the throttle that makes the server-load NFR structural (Henrik, hard
        rule): ONE request in flight, a global min-gap between auto-queries,
        stale windows, and a proximity gate (query only near a box) -- an
        away-from-box addon costs zero packets;

    THE BOX IS A NUMBER WE ALREADY KNOW (Henrik 2026-07-25, the v2 grill --
    docs/design/ebox-restock-v2-grill-2026-07-25.md). Polling it on a timer was
    spending packets to re-learn something arithmetic can tell us: we sent the
    withdraw, so we know the id and the quantity, so we know what is left. The
    cache is therefore maintained by SUBTRACTION and invalidated by DIRTY MARKS,
    never by a clock:

      verify once on approach -> decrement on our own withdraw -> mark dirty on
      the few events arithmetic cannot see -> Rescan is the manual repair.

    What dirties it, because these are the only things that change the box behind
    our back: a withdraw the server REFUSED (our number was too high -- the ACK
    says so); a `!box ...` chat command, but only ONCE ITEMS ACTUALLY MOVE (see
    below); zoning (0x00A -- the only heartbeat that can heal a silently-too-LOW
    belief, which has no other symptom); and a foreign 0x1A4 stream that may have
    been mistaken for our answer (the party line, also below).

    A bare inventory change dirties NOTHING: your bags changing does not change
    the box. That is what makes synthing next to an E-Box cost ZERO packets.

    THE MENU RULE (Henrik, field 2026-07-25). `!box ammo` / `!box cluster` /
    `!box <item name>` do not withdraw -- they open a MENU, and he may browse for
    a minute, take one thing, take several, or cancel. So the command does not
    dirty anything either; it ARMS us, and inventory movement inside that window
    is the proof we act on. Cancel the menu and it costs exactly zero packets.
    (`!box <item name>` also matters because it withdraws without any 0x1A4 we
    could see -- our arithmetic would otherwise drift low, silently.) While a
    menu is armed we also stay OFF the wire: the menu streams lists of its own,
    which our request would happily mistake for its answer.

    Consumers pick their policy through the SAME door: pass a maxAge to
    ensureCategory for a time window (AutoAmmo's deliberate panel), or call
    verifyCategories for the dirty-only discipline (Restock's passive surfaces).
      * batch withdraw (trove crafting's executePrepare: fire one WITHDRAW per
        pull, count the ACKs down) and the box-clamp;
      * Ephemeral-Box proximity via the central lib/entwatch.

    Pending discipline (helmwatch's rule): 0x1A4 is a PARTY LINE (helmwatch's
    points, trove's panels, us). Stage list rows only while OUR request is in
    flight, and consume/e.blocked only what we asked for -- Ashita still hands
    blocked events to every other addon, so nobody is starved, and blocking
    matters because the retail client has no idea what opcode 0x1A4 is.
]]--

local M = {};

local PKT_1A4 = 0x1A4;
-- C2S (trove/utils/packet.lua C2S)
local ACT_WITHDRAW     = 2;
local ACT_GET_SUMMARY  = 4;
local ACT_GET_CATEGORY = 5;
local ACT_SEARCH       = 6;
-- S2C
local ACT_CLEAR    = 0;
local ACT_ITEM     = 1;
local ACT_END_LIST = 2;
local ACT_ACK      = 3;
local ACT_LOCKED   = 4;
local ACT_SUMMARY  = 5;

-- ---------------------------------------------------------------------------
-- Tunables
-- ---------------------------------------------------------------------------
M.STALE      = 20;    -- seconds a category's counts stay fresh before a re-fetch
M.MIN_GAP    = 1.0;   -- seconds between ANY two auto-queries (the rate cap)
M.BUSY_HOLD  = 3;     -- trove's lost-ACK safety: a dropped ACK must not wedge us
M.PEND_HOLD  = 5;     -- a LIST request whose answer never arrives must not wedge
                      -- canQuery forever (one-in-flight is a hard gate)
M.SETTLE     = 2.0;   -- seconds to let a `!box ...` chat command reach the server
                      -- before we re-count -- counting across it believes the
                      -- PRE-command box (field-tunable if the server runs slower)
-- A `!box ammo` / `!box cluster` / `!box <item>` opens a MENU (Henrik, field
-- 2026-07-25). Nothing has happened yet: he may browse for a minute, take one
-- thing, take several, or cancel. So a command ARMS us and we wait for proof --
-- an inventory change -- instead of re-counting on a timer that is guessing.
M.MENU_ARM   = 120;   -- how long a box menu may sit open before we forget it
M.MENU_BURST = 15;    -- after items DO move, keep listening: one menu, several picks
M.REPAIR_GAP = 30;    -- circuit breaker on the party-line repair (below): a busy
                      -- box menu streams lists constantly, and repairing on every
                      -- one of them is the packet spam this design exists to avoid
M.BOX_NAME   = 'Ephemeral Box';
M.BOX_RANGE  = 5;     -- yalms -- FIELD-PINNED (Henrik 2026-07-20; eboxammo EB9)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
M.cat = {};              -- [ahCat] = { at = clock, items = { [id] = qty } }
M.dirty = {};            -- [ahCat] = true -- cached but no longer believed (see the
                         -- header: refused withdraw / any `!box ...` / zone-in)
M.counts = {};           -- flat merged view { [id] = qty } across every cached category
M.summary = nil;         -- last GET_SUMMARY result: array of { ahCat, count, qty }
M.searchResults = nil;   -- last SEARCH result: array of { id, qty, ahCat, name }
M.searchFor = nil;       -- the query string those results ARE FOR (nil = none asked).
                         -- The picker compares it to what is typed, so a result set can
                         -- never silently answer for a DIFFERENT string.
M.searchAt = 0;
M.lockedReason = nil;    -- nil | 'cw' (not a Crystal Warrior) | 'locked' (box not unlocked)
M.lockedMsg = nil;
M.status = nil;          -- last withdraw result line (the panel shows it briefly)
M.statusErr = false;
M.statusAt = 0;
M.busy = false;          -- a withdraw (single or batch) is in flight

local _pending = nil;    -- our in-flight LIST request: { kind, cat, staging }
local _pendingUntil = 0; -- when to give up on it (PEND_HOLD)
local _lastReqAt = -1e9; -- clock of the last auto-query sent (min-gap)
local _batchRemaining = 0;  -- WITHDRAW ACKs we are still waiting on
local _busyUntil = 0;
local _batchCats = {};   -- [ahCat] = true -- categories the in-flight batch withdrew
                         -- from, so a REFUSAL dirties exactly those and no more
local _verifyAfter = 0;  -- no AUTO re-count before this clock: a `!box ...` we just
                         -- saw may not have reached the server yet, and counting
                         -- across it would believe the pre-command box (see markAllDirty)
local _lastCommitCat = nil;  -- the category our last stream committed under, and when:
local _lastCommitAt  = 0;    -- the party-line repair in ACT_CLEAR needs both
local _armUntil    = 0;      -- a `!box ...` menu is open: expect foreign list streams,
                             -- expect the box to change, and stay out of the way
local _lastRepairAt = -1e9;  -- REPAIR_GAP breaker
local _foreign = nil;        -- a stream we are NOT the owner of: { rows } -- traced at
                             -- its END_LIST so the field log can name the intruder

-- The CENTRAL entity watcher (lib/entwatch), required HERE rather than beside
-- M.boxDistance: M.rescan is defined earlier in the file, and a local declared
-- further down is not in scope for it -- the reference would silently compile to
-- a nil GLOBAL read and Rescan's box re-sweep would never run.
local _ewok, _ew = pcall(require, 'dlac\\lib\\entwatch');
_ewok = _ewok and type(_ew) == 'table';

-- clock, injectable for the headless tests
function M._now() return os.clock(); end

-- ---------------------------------------------------------------------------
-- Traffic trace -- "how much does this actually send, and when?" (/dl debug
-- ebox; feature/eboxtrace formats it). The whole design rests on a server-load
-- promise, and a promise nobody can watch is a hope: this is how the zero-
-- packets-while-crafting claim gets checked in the field instead of argued.
--
-- RECORDING is pure table work, so the packet thread may do it. PRINTING never
-- happens in here -- the live echo is pumped from a render-thread hook, because
-- a print from the packet thread is the dig.lua crash.
-- ---------------------------------------------------------------------------
M.TRACE_MAX = 40;
M.trace  = {};    -- ring of { at, dir = '>' sent | '<' received | '*' event, what }
M.stats  = { out = 0, inn = 0, byKind = {}, since = nil, lastOutAt = nil };
M.echo   = false; -- live chat echo (eboxtrace owns the flag and the pump)
M.echoAt = 0;     -- how far the pump has printed

function M._trace(dir, what)
    local now = M._now();
    if M.stats.since == nil then M.stats.since = now; end
    local t = M.trace;
    t[#t + 1] = { when = now, dir = dir, what = what };
    while #t > M.TRACE_MAX do
        table.remove(t, 1);
        if M.echoAt > 0 then M.echoAt = M.echoAt - 1; end   -- keep the pump's place
    end
    if dir == '>' then
        M.stats.out = M.stats.out + 1;
        M.stats.lastOutAt = now;
        local k = string.match(what, '^(%S+)') or '?';
        M.stats.byKind[k] = (M.stats.byKind[k] or 0) + 1;
    elseif dir == '<' then
        M.stats.inn = M.stats.inn + 1;
    end
end

function M.traceReset()
    M.trace = {};
    M.stats = { out = 0, inn = 0, byKind = {}, since = M._now(), lastOutAt = nil };
    M.echoAt = 0;
end

-- ---------------------------------------------------------------------------
-- The gate: Crystal Warriors only (Henrik). Affirmative 'CW' opens; nil
-- (unknown) / Wings / ACE stay shut -- the never-gate-on-nil rule points the
-- safe way: unknown = hidden. LOCKED is the belt-and-braces server answer.
-- ---------------------------------------------------------------------------
local _gmok, _gm = pcall(require, 'dlac\\feature\\gamemode');
_gmok = _gmok and type(_gm) == 'table' and type(_gm.get) == 'function';
function M.isCW()
    if not _gmok then return false; end
    local ok, mode = pcall(_gm.get);
    return ok and mode == 'CW';
end

-- ---------------------------------------------------------------------------
-- Wire helpers (string.byte only -- headless)
-- ---------------------------------------------------------------------------
local function u8(data, off) return string.byte(data, off + 1) or 0; end
local function u16(data, off) return u8(data, off) + u8(data, off + 1) * 256; end
local function u32(data, off)
    return u8(data, off) + u8(data, off + 1) * 0x100
         + u8(data, off + 2) * 0x10000 + u8(data, off + 3) * 0x1000000;
end
local function zstr(data, off, maxLen)
    local out = {};
    for i = 1, maxLen do
        local b = string.byte(data, off + i);
        if b == nil or b == 0 then break; end
        out[#out + 1] = string.char(b);
    end
    return table.concat(out);
end

local function makePkt(action)
    local p = {};
    for i = 1, 64 do p[i] = 0; end
    p[5] = action;   -- byte @0x04
    return p;
end
local function wU16(p, off, v)
    p[off + 1] = v % 256;
    p[off + 2] = math.floor(v / 256) % 256;
end
local function wU32(p, off, v)
    p[off + 1] = v % 256;
    p[off + 2] = math.floor(v / 256) % 256;
    p[off + 3] = math.floor(v / 0x10000) % 256;
    p[off + 4] = math.floor(v / 0x1000000) % 256;
end
local function wStr(p, off, s, maxLen)
    local n = math.min(#s, maxLen);
    for i = 1, n do p[off + i] = string.byte(s, i); end
end
local function sendRaw(p)
    pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(PKT_1A4, p); end);
end

-- ---------------------------------------------------------------------------
-- Cache
-- ---------------------------------------------------------------------------

-- Rebuild the flat merged view from every cached category (an item lives in
-- exactly one ahCat, so there is no real collision; a re-fetch of one category
-- replaces only its own rows). Called on each category commit.
local function rebuildFlat()
    local flat = {};
    for _, c in pairs(M.cat) do
        for id, qty in pairs(c.items) do flat[id] = qty; end
    end
    M.counts = flat;
end

-- Box count for an id: the flat merged view by default, or narrowed to one
-- category when the caller knows it (AutoAmmo -> 15; a tracked item -> its ahCat).
function M.boxCount(id, ahCat)
    id = math.floor(tonumber(id) or 0);
    if id <= 0 then return 0; end
    if ahCat ~= nil then
        local c = M.cat[ahCat];
        return (c ~= nil) and (c.items[id] or 0) or 0;
    end
    return M.counts[id] or 0;
end

-- The per-category authoritative map + its freshness (nil when never fetched).
function M.categoryCounts(ahCat)
    local c = M.cat[ahCat];
    if c == nil then return nil, nil; end
    return c.items, c.at;
end
-- Fresh = cached, BELIEVED (not dirty), and inside the caller's window. A dirty
-- category is never fresh at ANY maxAge -- that is what lets a consumer pass
-- math.huge and get "fetch once, then only when something invalidated it".
function M.categoryFresh(ahCat, maxAge)
    local c = M.cat[ahCat];
    if c == nil then return false; end
    if M.dirty[ahCat] then return false; end
    return (M._now() - c.at) < (tonumber(maxAge) or M.STALE);
end

-- Stop believing one category / everything. Pure table work (safe on the packet
-- thread). A category we have never fetched needs no mark: it is already unfresh.
--
-- Both also flag a category request that is ALREADY ON THE WIRE, because its
-- answer was computed by the server BEFORE whatever just changed the box -- so
-- committing it must not clear the mark we are raising here. Without that, a
-- `!box store` landing during a re-count leaves us believing the pre-store box,
-- which is the too-LOW belief C1 calls symptomless: the restocker just goes
-- quiet about an item the box actually has.
-- `why` is for the trace only: every re-count in this model has a reason, and
-- /dl debug ebox is where you read it back.
function M.markDirty(ahCat, why)
    if ahCat == nil then return; end
    if _pending ~= nil and _pending.kind == 'category' and _pending.cat == ahCat then
        _pending.stale = true;
    end
    if M.cat[ahCat] ~= nil then
        M.dirty[ahCat] = true;
        M._trace('*', string.format('dirty cat=%d (%s)', ahCat, tostring(why or '?')));
    end
end

-- settle = seconds to hold OFF an automatic re-count. `!box ...` is a chat
-- command: it may not have reached the server when our GET_CATEGORY does, and
-- counting across it would commit the pre-command box and mark it believed.
-- Manual Rescan passes nothing -- that click means "count now".
function M.markAllDirty(settle, why)
    if _pending ~= nil and _pending.kind == 'category' then _pending.stale = true; end
    local n = 0;
    for cat in pairs(M.cat) do M.dirty[cat] = true; n = n + 1; end
    local s = tonumber(settle) or 0;
    if s > 0 then _verifyAfter = M._now() + s; end
    M._trace('*', string.format('dirty ALL (%s)%s -- %d counted categor%s',
        tostring(why or '?'), (s > 0) and string.format(', settle %.1fs', s) or '',
        n, (n == 1) and 'y' or 'ies'));
end

-- Which cached category holds this id (an item lives in exactly one). nil when
-- we have never seen it in the box.
local function catOf(id)
    for cat, c in pairs(M.cat) do
        if c.items[id] ~= nil then return cat; end
    end
    return nil;
end

-- THE arithmetic: we asked for qty of id, so the box now holds qty fewer. No
-- packet, no re-query. Clamped at 0 -- the ACK path repairs a wrong belief.
local function debit(id, qty)
    local cat = catOf(id);
    if cat == nil then return nil; end
    local c = M.cat[cat];
    c.items[id] = math.max(0, (c.items[id] or 0) - math.max(0, math.floor(tonumber(qty) or 0)));
    M.counts[id] = c.items[id];
    return cat;
end
M._debit = debit;   -- test seam (EBC*)

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------

-- Split out as the headless seam (tests EBC*): begins an in-flight LIST request
-- WITHOUT touching the wire. kind = 'category' | 'search' | 'summary'.
function M._beginRequest(kind, ahCat)
    _pending = { kind = kind, cat = ahCat, staging = {} };
    _pendingUntil = M._now() + M.PEND_HOLD;
end

-- One-in-flight, with the lost-answer timeout applied at READ time (isBusy's
-- rule). Without it a single dropped reply wedges every future query -- and
-- under the dirty-only discipline there is no periodic poll to paper over that.
local function pendActive()
    if _pending ~= nil and M._now() > _pendingUntil then
        M._trace('*', string.format('gave up on the %s reply (PEND_HOLD)', tostring(_pending.kind)));
        _pending = nil;
    end
    return _pending ~= nil;
end

local function canQuery()
    if not M.isCW() then return false; end
    if M.lockedReason ~= nil then return false; end   -- the server already said no
    if pendActive() then return false; end            -- one request in flight
    if (M._now() - _lastReqAt) < M.MIN_GAP then return false; end   -- rate cap
    return true;
end

-- Can a consumer's button be clicked right now? (The picker's Search greys out
-- on this instead of guessing, so a refused query can never be dropped silently.)
function M.canQuery() return canQuery(); end

-- Fetch one category's counts if it is stale and the throttle allows. Returns
-- true when a request actually went out. The proximity gate lives in the
-- caller (query only near a box) -- see M.nearBox.
function M.ensureCategory(ahCat, maxAge)
    if ahCat == nil then return false; end
    if M.categoryFresh(ahCat, maxAge) then return false; end
    -- While a box MENU is open we stay off the wire entirely. Two reasons, and
    -- both were visible in the field log: the menu streams lists of its own, so
    -- our request can be answered by its traffic; and whatever we counted is
    -- about to change the moment he picks something. Rescan overrides this.
    if M._now() < _armUntil then return false; end
    if M._now() < _verifyAfter then return false; end   -- let a `!box ...` land first
    if not canQuery() then return false; end
    M._beginRequest('category', ahCat);
    _lastReqAt = M._now();
    local p = makePkt(ACT_GET_CATEGORY);
    p[11] = ahCat;   -- u8 @0x0A
    sendRaw(p);
    M._trace('>', string.format('GET_CATEGORY cat=%d (%s)', ahCat,
        (maxAge == math.huge) and 'verify' or ('maxAge ' .. tostring(maxAge or M.STALE))));
    return true;
end

-- Refresh a set of categories, one per call (the single-in-flight discipline
-- serializes them across frames). Returns true when a request went out.
function M.ensureCategories(ahCats, maxAge)
    if type(ahCats) ~= 'table' then return false; end
    local seen = {};
    for _, c in ipairs(ahCats) do
        if c ~= nil and not seen[c] then
            seen[c] = true;
            if M.ensureCategory(c, maxAge) then return true; end
        end
    end
    return false;
end

-- VERIFY (the Restock discipline): fetch a category only if we have never had
-- it or something dirtied it -- no clock, so a believed cache costs nothing
-- however long you stand at the box. Safe to call every frame: once every
-- category is verified this is a table walk and returns false.
function M.verifyCategories(ahCats)
    return M.ensureCategories(ahCats, math.huge);
end
function M.verifyCategory(ahCat)
    return M.ensureCategory(ahCat, math.huge);
end

-- Are the tracked categories all believed? (The panel prints "box ..." rather
-- than a number for a category we have not verified yet.)
function M.categoriesVerified(ahCats)
    if type(ahCats) ~= 'table' then return true; end
    for _, c in ipairs(ahCats) do
        if c ~= nil and not M.categoryFresh(c, math.huge) then return false; end
    end
    return true;
end

-- Search the box by name (the add-picker's Search BUTTON -- never typing: a
-- query costs a packet, so it goes out when the player asks for it, once).
-- Results are stamped with the string they answer for (M.searchFor) and the old
-- set is dropped at send, so nothing on screen can belong to a previous query.
function M.search(query)
    query = tostring(query or '');
    if query == '' then return false; end
    if not canQuery() then return false; end
    M._beginRequest('search');
    M.searchResults = nil;      -- the previous answer is not this question's
    M.searchFor = query;
    _lastReqAt = M._now();
    local p = makePkt(ACT_SEARCH);
    wStr(p, 0x10, query, 31);
    sendRaw(p);
    M._trace('>', string.format('SEARCH %q', query));
    return true;
end

-- Is OUR search still on the wire? (Derived from the one in-flight slot, so it
-- can never disagree with it.) The picker shows "searching..." on this instead
-- of "no matches", which was the old lie.
function M.searchBusy()
    return pendActive() and _pending.kind == 'search';
end

-- Forget the whole search (the picker's close): no stale hits on reopen.
function M.clearSearch()
    M.searchResults = nil;
    M.searchFor = nil;
    M.searchAt = 0;
end

-- Whole-box category summary (per-category totals). Not on AutoAmmo/Restock's
-- critical path, but the one client owns the whole protocol.
function M.getSummary()
    if not canQuery() then return false; end
    M._beginRequest('summary');
    _lastReqAt = M._now();
    sendRaw(makePkt(ACT_GET_SUMMARY));
    M._trace('>', 'GET_SUMMARY');
    return true;
end

-- The pure clamp (tested): never ask for more than the box holds.
function M._clampQty(qty, have)
    qty = math.floor(tonumber(qty) or 0);
    have = math.floor(tonumber(have) or 0);
    if qty < 1 or have < 1 then return 0; end
    if qty > have then return have; end
    return qty;
end

local function setStatus(msg, isErr)
    M.status, M.statusErr, M.statusAt = msg, (isErr == true), M._now();
end

-- Fire one WITHDRAW (u16 id @0x08, u32 qty @0x0C), clamped to the box count.
-- Internal: the batch counter is set by the callers below.
local function sendWithdraw(itemId, qty)
    local p = makePkt(ACT_WITHDRAW);
    wU16(p, 0x08, itemId);
    wU32(p, 0x0C, qty);
    sendRaw(p);
    M._trace('>', string.format('WITHDRAW id=%d x%d', itemId, qty));
end

-- Withdraw exactly qty of one item (box-clamped). One-at-a-time gate. The box
-- count is DEBITED as we send: we know what we asked for, so the cache stays
-- right without a single re-query (a refusal repairs it -- see the ACK path).
function M.withdraw(itemId, qty)
    if not M.isCW() or M.isBusy() then return false; end
    itemId = math.floor(tonumber(itemId) or 0);
    qty = M._clampQty(qty, M.boxCount(itemId));
    if itemId <= 0 or qty <= 0 then return false; end
    _batchRemaining = 1;
    _batchCats = {};
    local cat = debit(itemId, qty);
    if cat ~= nil then _batchCats[cat] = true; end
    M.busy = true;
    _busyUntil = M._now() + M.BUSY_HOLD;
    sendWithdraw(itemId, qty);
    return true;
end

-- Batch withdraw (trove executePrepare): pulls = { { id, qty }, ... }, each
-- pull already one stack's worth from the planner (docs/design/ebox-restock.md
-- Section 3). Fire them all, count the ACKs down. Returns the number fired.
function M.withdrawBatch(pulls)
    if not M.isCW() or M.isBusy() or type(pulls) ~= 'table' then return 0; end
    local fire, cats = {}, {};
    for _, pull in ipairs(pulls) do
        local id  = math.floor(tonumber(pull.id) or 0);
        -- Clamped against the LIVE count, which earlier pulls in this same batch
        -- have already debited: two stack-pulls of one item can never together
        -- ask for more than the box holds (the lost-items law, wiki-confirmed).
        local qty = M._clampQty(pull.qty, M.boxCount(id));
        if id > 0 and qty > 0 then
            fire[#fire + 1] = { id = id, qty = qty };
            local cat = debit(id, qty);
            if cat ~= nil then cats[cat] = true; end
        end
    end
    if #fire == 0 then return 0; end
    _batchRemaining = #fire;
    _batchCats = cats;
    M.busy = true;
    _busyUntil = M._now() + M.BUSY_HOLD;
    for _, f in ipairs(fire) do sendWithdraw(f.id, f.qty); end
    return #fire;
end

-- The panel reads busy through this so the lost-ACK timeout applies at read
-- time (no frame hook needed) -- trove's rule.
function M.isBusy()
    if M.busy and M._now() > _busyUntil then
        M.busy = false; _batchRemaining = 0;
        -- Giving up on the ACKs means the server can no longer tell us our number
        -- was wrong -- and the ACK is the ONLY repair for a send-time debit now
        -- that the 25s poll is gone. So stop believing exactly what this batch
        -- debited. Costs one re-count, only after a fetch that never completed;
        -- crafting fires no withdraws, so the zero-packet promise is untouched.
        for cat in pairs(_batchCats) do M.markDirty(cat, 'lost ACK'); end
        _batchCats = {};
    end
    return M.busy;
end

-- Headless seam (tests EBC*): stage N in-flight withdraw ACKs without the wire,
-- so the ACK-batch path can be driven where isCW() is false.
function M._beginBatch(n, cats)
    _batchRemaining = math.floor(tonumber(n) or 0);
    _batchCats = (type(cats) == 'table') and cats or {};
    M.busy = _batchRemaining > 0;
    _busyUntil = M._now() + M.BUSY_HOLD;
end

-- Deposit is NOT in the 0x1A4 protocol (trove/utils/packet.lua has WITHDRAW +
-- queries; VAULT_DEPOSIT 16 is the town Vault, a different store), so storing is
-- a CHAT command -- what trove's own Store All fires. The wiki is blunt about
-- the blast radius: "Instantly store every storable item in their inventory",
-- and the storable set is crafting mats, food, ninjutsu tools, ammo, oils --
-- i.e. what Restock just fetched. Callers must confirm before calling this.
-- We mark dirty HERE because a state never hears its own QueueCommand (the
-- `!box` watch below will not fire for us) -- bookkeep at the queue site.
--
-- SEND IT BARE. DO NOT "FIX" THIS FROM THE SERVER SOURCE (field 2026-07-26).
-- QueueCommand mode 1 is Typed, so this rides the player's DEFAULT CHAT MODE,
-- and a player reported `!box` dead while defaulted to party. The obvious
-- hardening -- pin the chat kind with `/say !box store` -- was built, shipped,
-- field-tested by Henrik and REVERTED: `/say !box …` does not work at all. It
-- has to go out with nothing in front of it. And with party as the default chat,
-- `!box` does not work either, prefix or none.
--
-- Read that against the server clone and it makes no sense, which is the point:
-- `0x0b5_chat_std.cpp:126` tests `firstChar == '!'` and calls the (chat-blind)
-- CCommandHandler BEFORE the switch on chat kind, so say/party/linkshell should
-- be identical, and `/say !box store` should produce the very same packet as
-- typing it bare in say mode. The field says otherwise on both counts, so the
-- live interception is NOT the code in that clone. The field verdict wins; the
-- source reading was wrong. Henrik's call: it is a server-side limitation, not
-- ours to work around -- "it is what it is".
function M.boxStore()
    if not M.isCW() then return false; end
    local ok = pcall(function()
        AshitaCore:GetChatManager():QueueCommand(1, '!box store');
    end);
    -- Arm, exactly as if we had seen someone else type it (a state never hears
    -- its own QueueCommand, so the `!box` watch will not fire for us). Store is
    -- instant rather than a menu, but the rule is the same and strictly better:
    -- if nothing storable was in your bags, nothing moves and we count nothing.
    M._armMenu();
    M._trace('*', 'sent chat command: !box store -- waiting for items to move');
    return ok == true;
end

-- Manual rescan (the panel's button): poke the entity watcher and stop
-- believing every category, so the next verify re-counts. THE repair path when
-- our arithmetic has drifted for a reason we could not see.
function M.rescan()
    if _ewok then pcall(_ew.poke, M.BOX_NAME); end
    _verifyAfter = 0;      -- a deliberate click outranks any settle window
    _armUntil = 0;         -- ...and any open-menu hold: he asked for a count NOW
    M.markAllDirty(nil, 'Rescan');
end

-- ---------------------------------------------------------------------------
-- The `!box ...` MENU protocol (Henrik, field 2026-07-25). A command does NOT
-- change the box: `!box ammo` / `!box cluster` / `!box <item>` open a menu, and
-- the player may browse, take one thing, take several, or cancel. Re-counting on
-- a fixed timer after the command therefore spends packets to re-learn nothing,
-- and still misses the change when it finally comes.
--
-- So a command only ARMS us, and INVENTORY MOVEMENT is the proof we wait for.
-- This is not the inventory-as-trigger rule the design rejected: bags changing
-- still never means the box changed. It means it only in the window a `!box`
-- command opened -- items appearing right after you asked the box for items is
-- the box answering. Cancel the menu and this costs exactly zero packets.
-- ---------------------------------------------------------------------------
function M.menuOpen() return M._now() < _armUntil; end

function M._armMenu()
    _armUntil = M._now() + M.MENU_ARM;
end

function M._onInventoryChange()
    local now = M._now();
    if now >= _armUntil then return false; end   -- no `!box` pending: not our business
    _armUntil = now + M.MENU_BURST;   -- same menu, more picks: keep listening briefly
    -- One withdrawal is SEVERAL inventory packets (the field log showed two
    -- marks for one pouch, either side of the "You obtain" line). The extra
    -- marks cost no packets -- dirty is a flag, and the re-count happens once --
    -- but they read like something is happening twice. So: while the settle
    -- window from this burst is still open, just let it slide while items keep
    -- arriving, and say nothing more.
    if now < _verifyAfter then
        _verifyAfter = now + M.SETTLE;
        return true;
    end
    M.markAllDirty(M.SETTLE, 'items moved after a `!box ...` command');
    return true;
end

-- ---------------------------------------------------------------------------
-- One inbound 0x1A4. Returns true when WE consumed it (the caller blocks it).
-- ---------------------------------------------------------------------------
function M._onPacket(data)
    local action = u8(data, 0x04);

    if action == ACT_CLEAR then
        if _pending == nil then
            -- AN UNSOLICITED LIST STREAM -- and the tell that the party line may
            -- just have bitten us. 0x1A4 has no request id, so a foreign stream
            -- landing while OUR GET_CATEGORY is out gets consumed as our answer
            -- and committed under our category. That cannot be PREVENTED; the
            -- repair is to stop believing the commit it could have corrupted.
            --
            -- TWO brakes, both paid for by the 07-25 field log, where this fired
            -- about once a second in a loop:
            --   * while a box MENU is open we expect this traffic -- it is the
            --     menu populating itself, not a thief -- so we do not repair;
            --   * otherwise at most one repair per REPAIR_GAP, because a repair
            --     that re-counts, gets overlapped again and re-counts again is
            --     precisely the packet spam this design exists to prevent.
            _foreign = { rows = 0 };
            if M._now() < _armUntil then
                _lastCommitCat = nil;
            elseif _lastCommitCat ~= nil and (M._now() - _lastCommitAt) < M.PEND_HOLD
                   and (M._now() - _lastRepairAt) >= M.REPAIR_GAP then
                _lastRepairAt = M._now();
                M.markDirty(_lastCommitCat, 'a foreign 0x1A4 stream overlapped our answer');
                _lastCommitCat = nil;
            else
                _lastCommitCat = nil;   -- one repair per commit, not per foreign packet
            end
            return false;               -- not ours: never block it, trove needs it
        end
        if _pending.sawClear then
            -- A SECOND CLEAR inside one request = two streams interleaved, and we
            -- cannot tell which rows are whose. Take the answer, but do not
            -- believe it: the mark survives the commit and it is asked again.
            _pending.stale = true;
            M._trace('*', 'two list streams interleaved -- this answer will not be believed');
        end
        _pending.sawClear = true;
        _pending.staging = {};
        _pendingUntil = M._now() + M.PEND_HOLD;   -- progress: the answer IS arriving
        return true;
    end

    if action == ACT_ITEM then
        if _pending == nil then
            if _foreign ~= nil then _foreign.rows = _foreign.rows + 1; end
            return false;                           -- someone else's stream
        end
        _pendingUntil = M._now() + M.PEND_HOLD;     -- a long list must not time out mid-stream
        local id = u16(data, 0x08);
        if id > 0 then
            _pending.staging[#_pending.staging + 1] = {
                id = id, ahCat = u8(data, 0x0A), qty = u32(data, 0x0C),
                name = zstr(data, 0x10, 31),
            };
        end
        return true;
    end

    if action == ACT_END_LIST then
        if _pending == nil then
            -- Name the intruder in the field log. WHOSE stream keeps landing on
            -- our slot is a question only the game can answer, and its shape --
            -- how many item rows, and the source byte the ebox tags its own
            -- lists with -- is the evidence that identifies it.
            if _foreign ~= nil then
                M._trace('<', string.format('foreign list ended: rows=%d source=%d',
                    _foreign.rows, u8(data, 0x05)));
                _foreign = nil;
            end
            return false;
        end
        if u8(data, 0x05) ~= 0 then return false; end   -- source 0 = ebox; others elsewhere
        local kind, staging = _pending.kind, _pending.staging;
        if kind == 'category' then
            local items = {};
            for _, row in ipairs(staging) do
                -- The wire carries no request id, so a row's OWN ahCat is the only
                -- correlator there is. If PEND_HOLD gave up on a slow answer and a
                -- new request has taken the slot, that old answer must never commit
                -- under the new category and be marked believed -- with no clock
                -- left in this model, a wrong-and-believed count is permanent.
                -- Tolerant on purpose: a row that does not name a category (0) is
                -- accepted, so an unexpected server shape cannot make us re-ask
                -- forever. A mismatch is CONSUMED but not committed: the category
                -- simply stays unverified and is asked again.
                if row.ahCat ~= 0 and row.ahCat ~= _pending.cat then
                    M._trace('<', string.format('LIST REJECTED: asked cat=%d, rows say cat=%d',
                        _pending.cat, row.ahCat));
                    _pending = nil;
                    return true;
                end
                items[row.id] = row.qty;
            end
            M._trace('<', string.format('LIST cat=%d rows=%d%s', _pending.cat, #staging,
                _pending.stale and ' (dirtied while in flight -- still unbelieved)' or ''));
            M.cat[_pending.cat] = { at = M._now(), items = items };
            -- Believed again -- UNLESS something dirtied it while this answer was
            -- in flight, in which case the answer predates the change.
            M.dirty[_pending.cat] = _pending.stale or nil;
            _lastCommitCat, _lastCommitAt = _pending.cat, M._now();
            rebuildFlat();
        elseif kind == 'search' then
            M.searchResults = staging;   -- array of { id, qty, ahCat, name }
            M.searchAt = M._now();
            M._trace('<', string.format('SEARCH results=%d', #staging));
        end
        -- 'summary' commits on the SUMMARY packet, not here; END_LIST just closes.
        _pending = nil;
        return true;
    end

    if action == ACT_SUMMARY then
        -- A single packet (not a stream): entryCount @0x05, then 7-byte rows at
        -- 0x08 (ahCat u8, count u16, qty u32). Only meaningful when WE asked.
        if _pending == nil or _pending.kind ~= 'summary' then return false; end
        local n = u8(data, 0x05);
        local entries = {};
        for i = 0, n - 1 do
            local off = 0x08 + i * 7;
            entries[#entries + 1] = {
                ahCat = u8(data, off), count = u16(data, off + 1), qty = u32(data, off + 3),
            };
        end
        M.summary = entries;
        M.lockedReason = nil;   -- a summary came back: we are a Crystal Warrior
        M._trace('<', string.format('SUMMARY %d categories', #entries));
        _pending = nil;
        return true;
    end

    if action == ACT_ACK then
        if u8(data, 0x05) ~= ACT_WITHDRAW or _batchRemaining <= 0 then return false; end
        local success = u8(data, 0x06);
        local msg = zstr(data, 0x10, 31);
        M._trace('<', string.format('ACK %s (%d left)%s', (success == 1) and 'ok' or 'REFUSED',
            math.max(0, _batchRemaining - 1), (msg ~= '') and (' -- ' .. msg) or ''));
        if success == 1 then
            setStatus((msg ~= '') and msg or 'withdrawn -- check your bags', false);
        else
            setStatus((msg ~= '') and msg or 'withdraw refused', true);
            -- The one case arithmetic cannot survive: the server says our number
            -- was wrong. Stop believing exactly the categories this batch touched.
            for cat in pairs(_batchCats) do M.markDirty(cat, 'withdraw refused'); end
        end
        _batchRemaining = _batchRemaining - 1;
        if _batchRemaining <= 0 then
            _batchRemaining = 0;
            M.busy = false;
            _batchCats = {};
            -- NOT stale: we debited what we asked for at send time. Re-counting a
            -- box we just did the arithmetic on is the poll this design deleted.
        end
        return true;
    end

    if action == ACT_LOCKED then
        -- Only meaningful when WE poked the box; an unsolicited LOCKED (another
        -- addon's request) must not shut our panel half down.
        if _pending == nil and _batchRemaining <= 0 then return false; end
        local reason = u8(data, 0x05);
        M.lockedMsg = zstr(data, 0x10, 31);
        M.lockedReason = (reason == 1) and 'cw' or 'locked';
        M._trace('<', 'LOCKED (' .. M.lockedReason .. ') -- every query refused from here');
        _pending = nil;
        _batchRemaining = 0;
        M.busy = false;
        return true;
    end

    return false;
end

-- ---------------------------------------------------------------------------
-- Proximity, via the CENTRAL entity watcher (lib/entwatch -- required at the top
-- of the file, see the note there). E-Boxes are DYNAMICALLY spawned NPCs named
-- "Ephemeral Box"; entwatch owns every scan idiom the field rounds paid for
-- (trimmed/ci names, rendered bit, the full 0x000-0x8FF range).
-- ---------------------------------------------------------------------------

-- Nearest box in YALMS, or nil when none is tracked in this zone. The watch is
-- (re)registered on every ask -- idempotent -- and the ask keeps the
-- callback-less watch inside entwatch's demand window.
function M.boxDistance()
    if not _ewok then return nil; end
    _ew.watch('eboxclient', M.BOX_NAME);
    return (_ew.nearest(M.BOX_NAME));
end

-- Are we close enough to interact? The proximity gate the NFR rests on: a
-- consumer only asks for counts while this is true, so an away-from-box addon
-- sends nothing.
function M.nearBox()
    local d = M.boxDistance();
    return d ~= nil and d <= M.BOX_RANGE;
end

-- Ashita glue, guarded (headless: no ashita global, nothing registers). A
-- dormant client (no consumer has sent a request) never has _pending set, so
-- _onPacket returns false for everything and this handler blocks nothing --
-- safe to load alongside eboxammo until that refactor lands (ADR 0016).
pcall(function()
    ashita.events.register('packet_in', 'dlac_eboxclient_packet_in', function(e)
        -- Zone-in: the ONE heartbeat that heals a too-LOW belief (a deposit we
        -- never saw makes the restocker go quiet, with no other symptom). Costs
        -- nothing here -- the re-count only happens if you walk up to a box.
        if e.id == 0x00A then
            _armUntil = 0;   -- whatever menu was open, it is gone
            M.markAllDirty(nil, 'zone-in 0x00A');
            return;
        end
        -- Inventory movement, but ONLY as the proof a `!box ...` menu is waiting
        -- for (see M._onInventoryChange). Outside that window this is a no-op, so
        -- crafting at a box still costs nothing. Same two ids gearui's own
        -- inventory watch uses.
        if e.id == 0x020 or e.id == 0x01D then M._onInventoryChange(); return; end
        if e.id ~= PKT_1A4 then return; end
        local ok, consumed = pcall(M._onPacket, e.data_modified or e.data);
        if ok and consumed == true then e.blocked = true; end
    end);
end);

-- The `!box` watch: every command that mutates the box goes through chat, not
-- 0x1A4 -- `!box store` (trove's Store All and typed), `!box cluster`,
-- `!box ammo`, and `!box <item name>`, which is a WITHDRAW BY NAME we would
-- otherwise never see (our arithmetic would drift low, silently). So we watch
-- the PREFIX, not one subcommand. Never blocked: it is the server's command.
pcall(function()
    ashita.events.register('command', 'dlac_eboxclient_boxwatch', function(e)
        local raw = string.lower(e.command or '');
        if raw:match('^%s*!box') ~= nil then
            -- Do NOT dirty here. The command opens a menu; nothing has changed
            -- yet, and it may never (he can cancel). Arm, and wait for items to
            -- actually move -- see M._onInventoryChange.
            M._armMenu();
            M._trace('*', 'saw ' .. raw:sub(1, 40) .. ' -- waiting for items to move');
        end
    end);
end);

return M;
