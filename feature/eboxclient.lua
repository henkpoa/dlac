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
M.BOX_NAME   = 'Ephemeral Box';
M.BOX_RANGE  = 5;     -- yalms -- FIELD-PINNED (Henrik 2026-07-20; eboxammo EB9)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
M.cat = {};              -- [ahCat] = { at = clock, items = { [id] = qty } }
M.counts = {};           -- flat merged view { [id] = qty } across every cached category
M.summary = nil;         -- last GET_SUMMARY result: array of { ahCat, count, qty }
M.searchResults = nil;   -- last SEARCH result: array of { id, qty, ahCat, name }
M.searchAt = 0;
M.lockedReason = nil;    -- nil | 'cw' (not a Crystal Warrior) | 'locked' (box not unlocked)
M.lockedMsg = nil;
M.status = nil;          -- last withdraw result line (the panel shows it briefly)
M.statusErr = false;
M.statusAt = 0;
M.busy = false;          -- a withdraw (single or batch) is in flight

local _pending = nil;    -- our in-flight LIST request: { kind, cat, staging }
local _lastReqAt = -1e9; -- clock of the last auto-query sent (min-gap)
local _batchRemaining = 0;  -- WITHDRAW ACKs we are still waiting on
local _busyUntil = 0;

-- clock, injectable for the headless tests
function M._now() return os.clock(); end

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
function M.categoryFresh(ahCat, maxAge)
    local c = M.cat[ahCat];
    if c == nil then return false; end
    return (M._now() - c.at) < (tonumber(maxAge) or M.STALE);
end

-- Mark every cached category stale (after a withdraw the box changed).
local function staleAll()
    for _, c in pairs(M.cat) do c.at = -1e9; end
end

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------

-- Split out as the headless seam (tests EBC*): begins an in-flight LIST request
-- WITHOUT touching the wire. kind = 'category' | 'search' | 'summary'.
function M._beginRequest(kind, ahCat)
    _pending = { kind = kind, cat = ahCat, staging = {} };
end

local function canQuery()
    if not M.isCW() then return false; end
    if M.lockedReason ~= nil then return false; end   -- the server already said no
    if _pending ~= nil then return false; end         -- one request in flight
    if (M._now() - _lastReqAt) < M.MIN_GAP then return false; end   -- rate cap
    return true;
end

-- Fetch one category's counts if it is stale and the throttle allows. Returns
-- true when a request actually went out. The proximity gate lives in the
-- caller (query only near a box) -- see M.nearBox.
function M.ensureCategory(ahCat, maxAge)
    if ahCat == nil then return false; end
    if M.categoryFresh(ahCat, maxAge) then return false; end
    if not canQuery() then return false; end
    M._beginRequest('category', ahCat);
    _lastReqAt = M._now();
    local p = makePkt(ACT_GET_CATEGORY);
    p[11] = ahCat;   -- u8 @0x0A
    sendRaw(p);
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

-- Search the box by name (the add-picker). Caller debounces the typing; we add
-- the min-gap on top. Returns true when the request went out.
function M.search(query)
    query = tostring(query or '');
    if query == '' then return false; end
    if not canQuery() then return false; end
    M._beginRequest('search');
    _lastReqAt = M._now();
    local p = makePkt(ACT_SEARCH);
    wStr(p, 0x10, query, 31);
    sendRaw(p);
    return true;
end

-- Whole-box category summary (per-category totals). Not on AutoAmmo/Restock's
-- critical path, but the one client owns the whole protocol.
function M.getSummary()
    if not canQuery() then return false; end
    M._beginRequest('summary');
    _lastReqAt = M._now();
    sendRaw(makePkt(ACT_GET_SUMMARY));
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
end

-- Withdraw exactly qty of one item (box-clamped). One-at-a-time gate.
function M.withdraw(itemId, qty)
    if not M.isCW() or M.isBusy() then return false; end
    itemId = math.floor(tonumber(itemId) or 0);
    qty = M._clampQty(qty, M.boxCount(itemId));
    if itemId <= 0 or qty <= 0 then return false; end
    _batchRemaining = 1;
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
    local fire = {};
    for _, pull in ipairs(pulls) do
        local id  = math.floor(tonumber(pull.id) or 0);
        local qty = M._clampQty(pull.qty, M.boxCount(id));
        if id > 0 and qty > 0 then fire[#fire + 1] = { id = id, qty = qty }; end
    end
    if #fire == 0 then return 0; end
    _batchRemaining = #fire;
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
    end
    return M.busy;
end

-- Headless seam (tests EBC*): stage N in-flight withdraw ACKs without the wire,
-- so the ACK-batch path can be driven where isCW() is false.
function M._beginBatch(n)
    _batchRemaining = math.floor(tonumber(n) or 0);
    M.busy = _batchRemaining > 0;
    _busyUntil = M._now() + M.BUSY_HOLD;
end

-- Manual rescan (the panel's button): poke the entity watcher and stale the
-- counts so the next ensureCategory re-requests.
function M.rescan()
    if _ewok then pcall(_ew.poke, M.BOX_NAME); end
    staleAll();
end

-- ---------------------------------------------------------------------------
-- One inbound 0x1A4. Returns true when WE consumed it (the caller blocks it).
-- ---------------------------------------------------------------------------
function M._onPacket(data)
    local action = u8(data, 0x04);

    if action == ACT_CLEAR then
        if _pending == nil then return false; end
        _pending.staging = {};
        return true;
    end

    if action == ACT_ITEM then
        if _pending == nil then return false; end   -- someone else's stream
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
        if _pending == nil then return false; end
        if u8(data, 0x05) ~= 0 then return false; end   -- source 0 = ebox; others elsewhere
        local kind, staging = _pending.kind, _pending.staging;
        if kind == 'category' then
            local items = {};
            for _, row in ipairs(staging) do items[row.id] = row.qty; end
            M.cat[_pending.cat] = { at = M._now(), items = items };
            rebuildFlat();
        elseif kind == 'search' then
            M.searchResults = staging;   -- array of { id, qty, ahCat, name }
            M.searchAt = M._now();
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
        _pending = nil;
        return true;
    end

    if action == ACT_ACK then
        if u8(data, 0x05) ~= ACT_WITHDRAW or _batchRemaining <= 0 then return false; end
        local success = u8(data, 0x06);
        local msg = zstr(data, 0x10, 31);
        if success == 1 then
            setStatus((msg ~= '') and msg or 'withdrawn -- check your bags', false);
        else
            setStatus((msg ~= '') and msg or 'withdraw refused', true);
        end
        _batchRemaining = _batchRemaining - 1;
        if _batchRemaining <= 0 then
            _batchRemaining = 0;
            M.busy = false;
            staleAll();   -- the box changed: next ensureCategory re-counts
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
        _pending = nil;
        _batchRemaining = 0;
        M.busy = false;
        return true;
    end

    return false;
end

-- ---------------------------------------------------------------------------
-- Proximity, via the CENTRAL entity watcher (lib/entwatch). E-Boxes are
-- DYNAMICALLY spawned NPCs named "Ephemeral Box"; entwatch owns every scan
-- idiom the field rounds paid for (trimmed/ci names, rendered bit, the full
-- 0x000-0x8FF range).
-- ---------------------------------------------------------------------------
local _ewok, _ew = pcall(require, 'dlac\\lib\\entwatch');
_ewok = _ewok and type(_ew) == 'table';

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
        if e.id ~= PKT_1A4 then return; end
        local ok, consumed = pcall(M._onPacket, e.data_modified or e.data);
        if ok and consumed == true then e.blocked = true; end
    end);
end);

return M;
