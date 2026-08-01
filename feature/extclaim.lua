--[[
    dlac/feature/extclaim.lua -- EXTERNAL CLAIMS: the WRITE half of the
    Integration surface (2026-08-01). The read half is feature\integration.lua;
    the consumer contract is docs\reference\integration-guide.md section 7.

    A SEPARATE ADDON -- its own Lua state, its own folder, NOT a dlac module --
    files a Claim over Ashita's plugin_event bus, and dlac's Arbiter settles it
    against every other claimant by the player's own rank order. The whole
    feature is one sentence: an external claim is an ordinary Claim that happens
    to have arrived over the wire.

    WHY THIS IS SMALL. A Claim in dlac is already just `{ [SlotKey] = itemName }`
    (gear\arbiter.lua, the CLAIM RECORD SHAPE note), and a claimant joins the
    Arbiter with TWO things and no new arm: one rank row and one CLAIMANTS row.
    Everything a player expects -- who wins a contested slot, the Locks veto, the
    Disabled ceiling, /dl why attribution, the Arbiter Monitor, the Claim
    Priority drag -- falls out of that for free. So this module is not an equip
    path. It is a MAILBOX with a lease: it receives claims, merges them, and
    hands ONE table to the row in dispatch.lua. It never equips anything itself.

    THE THREE LAWS THIS ADDS (everything else is inherited):

      1. PUSH, NEVER PULL. dlac never asks an external addon anything mid-decision
         and never waits for one. A claim is a STANDING table, exactly like
         AutoAmmo's or Craft's -- read from cache on every dispatch. The cost is
         that a REACTIVE external claim is one action late (you learn an action
         happened from the dispatch anchor, after the gear already moved); the
         gain is that a third party's Lua is never on the equip path, and its
         crash or its slow frame can never become dlac's gear bug. The
         one-directional dependency ruling (design\integration-surface.md), kept
         literal: dlac never depends on a plugin.

      2. EVERY CLAIM IS A LEASE. Every in-state claimant dies when dlac dies; an
         external one does not. An addon that crashes, unloads, or simply forgets
         would otherwise hold your gear hostage forever, and the player would have
         no idea which addon to blame. So a claim carries a TTL (default 10 s,
         max 300) and must be renewed. Nothing here is a permission wall -- the
         lease exists because the holder can vanish, not because it might
         misbehave.

      3. CLAIM, NEVER COMMIT. Session-only, never written to disk, no writer for
         sets/triggers/modes/lockstyle. The existing ruling ("a plugin may Claim,
         only the player may Commit") applies unchanged.

    THE SWITCH is a sibling of /dl stream, deliberately not the same one: reading
    your gear and dressing you are different consents, and a misbehaving claimant
    has to be killable without also killing a damage parser's feed.

    IT IS PERSISTED (Henrik's call, 2026-08-01), and the split is the point: the
    PERMISSION is a preference -- you set "I allow this" once, it rides in
    uiflags like every other Setting -- while the CLAIMS THEMSELVES stay session
    state and die with the world, exactly as they did. Nothing an addon holds
    survives a logout; only your answer to the question does. That is what makes
    leaving it on reasonable rather than a slow leak of control: every claim is
    still leased, still named in Claim Priority, still killable with one command.
    Measured cost of leaving it on with nobody claiming: ~0.25 us/frame, 0.0015%
    of a 60fps frame (the HANDOFF card carries the whole table).

    House shape: the CORE IS PURE -- canonSlots / merge / handle take a plain
    store table and an injected `now` and return plain tables, so the whole
    protocol drives headless with no stubs (tests EX*). The live glue (the
    plugin_event door, the emit, the expiry pump) is the thin edge below.
]]--

local M = {};

-- The wire protocol version. Bump ONLY on a breaking change; new keys are
-- additive and never break a consumer that ignores what it does not know (the
-- same contract the read half publishes).
M.PROTOCOL = 1;

-- The inbound door and the two lease numbers. A TTL is clamped, never refused:
-- an addon asking for a week gets 300 s and is TOLD so in the ack, which is a
-- better failure than a silent rejection it has to guess at.
M.EVENT      = 'dlac_claim';
M.TTL_DEFAULT = 10;
M.TTL_MIN     = 1;
M.TTL_MAX     = 300;

-- A bound on the mailbox. Not a permission tier -- a memory bound, so a looping
-- addon generating fresh ids cannot grow the store without limit. The refusal
-- names the cap, so a legitimate 9th addon is a conversation, not a mystery.
M.MAX_CLAIMANTS = 8;

M.on     = false;   -- THE session switch (never persisted)
M._store = {};      -- id -> { id, label, prio, slots, expires, reply, at }
M._by    = {};      -- Slot -> id, from the last merge (verdict routing)
M._shadow = nil;    -- loserId -> { slot -> winnerId }, from the last merge
M._lastLost = {};   -- id -> signature of the last contest notice sent (dedupe)

-- The clock, injectable for tests. os.clock is the house precedent for a short
-- wall-ish window (integration's confirm settle rides it).
M._clock = function() return os.clock(); end

-- ---------------------------------------------------------------------------
-- The slot vocabulary. The arbiter owns it; this only builds the
-- case-insensitive lookup, because an external author WILL send 'head'.
-- ---------------------------------------------------------------------------
local CANON = nil;
local function canonMap()
    if CANON ~= nil then return CANON; end
    local out = {};
    local ok = pcall(function()
        local ARB = require('dlac\\gear\\arbiter');
        for _, s in ipairs(ARB.LAC_SLOTS_CANON) do out[string.lower(s)] = s; end
    end);
    if not ok or next(out) == nil then
        -- The arbiter is the one authority; this fallback exists only so a
        -- broken/partial install still answers a query instead of throwing.
        local L = { 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck', 'Ear1', 'Ear2',
                    'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet' };
        for _, s in ipairs(L) do out[string.lower(s)] = s; end
    end
    CANON = out;
    return CANON;
end

-- ---------------------------------------------------------------------------
-- normSlots -- the ONE validator (pure). Returns (slots, err).
--
-- Refusals are NAMED, never silent: an unknown slot key or a non-string item is
-- the single most likely mistake an integrating author makes, and a claim that
-- vanishes without a word looks exactly like dlac being broken (hard rule 12 --
-- a total failure must not look like a typo).
--
-- 'remove' passes through as-is: it is dlac's own empty-the-slot convention, so
-- an external addon can claim a slot EMPTY exactly like a trigger can.
-- ---------------------------------------------------------------------------
function M.normSlots(t)
    if type(t) ~= 'table' then return nil, 'slots must be a table of { Slot = "Item Name" }'; end
    local map, out, n = canonMap(), {}, 0;
    for k, v in pairs(t) do
        local key = map[string.lower(tostring(k))];
        if key == nil then
            return nil, string.format('unknown slot "%s" (Main Sub Range Ammo Head Neck Ear1 Ear2 Body Hands Ring1 Ring2 Back Waist Legs Feet)', tostring(k));
        end
        if type(v) ~= 'string' or v == '' then
            return nil, string.format('slot %s: item must be a non-empty string (or "remove" to hold it empty)', key);
        end
        if #v > 64 then
            return nil, string.format('slot %s: item name too long', key);
        end
        out[key] = v;
        n = n + 1;
    end
    if n == 0 then return nil, 'empty claim -- send at least one slot, or use what = "release"'; end
    return out, nil;
end

-- ---------------------------------------------------------------------------
-- merge -- every live claim into ONE table (pure). Returns (slots, by, shadow).
--
-- Contention BETWEEN external addons is settled here, before the Arbiter ever
-- sees it, because they share one rank row: higher `prio` wins the slot, and a
-- tie breaks on the id, ascending. Deterministic on purpose -- a pairs() walk
-- would make "which addon owns Head" depend on hash order and change between
-- sessions (hard rule 8).
--
-- `shadow` = { [loserId] = { [slot] = winnerId } } -- WHO LOST TO WHOM, and it
-- is not bookkeeping. A shadowed claim is ACCEPTED (correctly: the moment the
-- winner releases or its lease lapses, the loser takes the slot with no
-- round trip) -- so without this the loser is told "ok", holds a live lease,
-- believes it is wearing something, and is never told otherwise. That is the
-- same silence the verdict push exists to end, arriving from the one direction
-- the Arbiter cannot see, because this contest is settled before the Arbiter is
-- handed anything. Field-found 2026-08-01 (Henrik: *"When I claim on A ... then
-- try to claim on b, it says ok ... But don't win over A"*).
--
-- Expired records are skipped, not deleted: deletion is the pump's job, so this
-- stays pure and a test can drive the clock past a lease without side effects.
-- ---------------------------------------------------------------------------
-- Never mutated. The idle path hands this back instead of allocating a fresh
-- empty table on every dispatch -- see the ZERO-WHEN-IDLE note on M.claim.
local EMPTY = {};
M._EMPTY = EMPTY;

function M.merge(store, now)
    -- The overwhelmingly common case, once the switch is left on: nobody is
    -- claiming. Answer before allocating anything at all.
    if store == nil or next(store) == nil then return nil, EMPTY, nil; end
    local ids = {};
    for id, r in pairs(store) do
        if type(r) == 'table' and type(r.slots) == 'table'
           and (r.expires == nil or r.expires > now) then
            ids[#ids + 1] = id;
        end
    end
    if ids[1] == nil then return nil, EMPTY, nil; end
    table.sort(ids);                                   -- the tie-break, made explicit
    local slots, by, shadow = {}, {}, nil;
    local function note(loser, slot, winner)
        shadow = shadow or {};
        shadow[loser] = shadow[loser] or {};
        shadow[loser][slot] = winner;
    end
    for _, id in ipairs(ids) do
        local r = store[id];
        local p = tonumber(r.prio) or 0;
        for slot, item in pairs(r.slots) do
            local cur = by[slot];
            if cur == nil then
                slots[slot], by[slot] = item, id;
            elseif p > (tonumber(store[cur].prio) or 0) then
                note(cur, slot, id);                   -- the sitting holder is displaced
                slots[slot], by[slot] = item, id;
            else
                note(id, slot, cur);
            end
        end
    end
    -- Re-point every shadow at the FINAL winner. A slot can change hands twice
    -- in one walk (A holds it, B takes it, C takes it from B), and the first
    -- loser's note still names the intermediate holder -- which is a name that
    -- was never actually worn. One pass over `by` fixes it; naming a loser as
    -- the winner is worse than saying nothing.
    if shadow ~= nil then
        for _, m in pairs(shadow) do
            for slot in pairs(m) do m[slot] = by[slot] or m[slot]; end
        end
    end
    if next(slots) == nil then return nil, {}, shadow; end
    return slots, by, shadow;
end

-- ---------------------------------------------------------------------------
-- handle -- the verb router (pure). Returns (answer, changed).
--
-- `changed` tells the caller whether the merged claim may have moved, which is
-- what the retrace signature keys on: a claim dlac cannot SEE change is a claim
-- that never gets applied, and that failure is invisible (the CLAIMANT_SIG_ORDER
-- leg in dispatch.lua is the other half of this).
--
-- Every verb answers. An unknown verb answers with an error, never silence --
-- the same rule the read half's queries follow.
-- ---------------------------------------------------------------------------
function M.handle(store, q, now)
    if type(q) ~= 'table' then return { v = 1, ok = false, err = 'bad request' }, false; end
    local what = tostring(q.what or '');
    local id   = (type(q.id) == 'string' and q.id ~= '') and q.id or nil;

    if what == 'hello' then
        -- Discovery. An integrating addon calls this first and learns three
        -- things it cannot guess: that dlac is here, that the switch is on, and
        -- what the protocol is. Answered even when the switch is OFF -- see the
        -- door below -- so "dlac is present but not accepting" is a state a
        -- consumer can render instead of failing silently.
        return { v = 1, what = 'hello', ok = true,
                 data = { protocol = M.PROTOCOL, on = M.on == true,
                          dlac = (type(addon) == 'table') and addon.version or nil,
                          ttlDefault = M.TTL_DEFAULT, ttlMax = M.TTL_MAX,
                          claimant = 'External', maxClaimants = M.MAX_CLAIMANTS } }, false;
    end

    if id == nil then
        return { v = 1, what = what, ok = false,
                 err = 'every request needs id = "<your addon>" (it is your claim\'s identity and your lease)' }, false;
    end

    if what == 'release' then
        local had = store[id] ~= nil;
        store[id] = nil;
        return { v = 1, what = 'release', ok = true, data = { released = had } }, had;
    end

    if what == 'heartbeat' then
        local r = store[id];
        if r == nil then
            -- NOT an error the caller has to special-case: a lease that lapsed
            -- while the addon was busy is an ordinary race. Say so plainly and
            -- let it re-claim.
            return { v = 1, what = 'heartbeat', ok = false, err = 'no live claim (expired or never filed) -- send what = "claim" again' }, false;
        end
        r.expires = now + r.ttl;
        return { v = 1, what = 'heartbeat', ok = true, data = { expiresIn = r.ttl } }, false;
    end

    if what == 'status' then
        local mine = store[id];
        local holders = {};
        for oid, r in pairs(store) do
            if type(r) == 'table' and (r.expires == nil or r.expires > now) then
                local n = 0;
                for _ in pairs(r.slots or {}) do n = n + 1; end
                holders[#holders + 1] = { id = oid, label = r.label, prio = r.prio, slots = n };
            end
        end
        table.sort(holders, function(a, b) return tostring(a.id) < tostring(b.id); end);
        return { v = 1, what = 'status', ok = true,
                 data = { mine = mine and { slots = mine.slots, prio = mine.prio,
                                            expiresIn = math.max(0, (mine.expires or now) - now) } or nil,
                          holders = holders, on = M.on == true } }, false;
    end

    if what ~= 'claim' then
        return { v = 1, what = what, ok = false,
                 err = 'unknown what (v1 accepts: hello, claim, release, heartbeat, status)' }, false;
    end

    -- claim: REPLACES this id's whole table. Not a merge -- one claimant, one
    -- claim, exactly like every in-state claimant rebuilds its table each
    -- dispatch. A merge would need a per-slot release verb and would leave
    -- stale slots behind forever after a crash.
    local slots, err = M.normSlots(q.slots);
    if slots == nil then
        return { v = 1, what = 'claim', ok = false, err = err }, false;
    end
    if store[id] == nil then
        local n = 0;
        for _ in pairs(store) do n = n + 1; end
        if n >= M.MAX_CLAIMANTS then
            return { v = 1, what = 'claim', ok = false,
                     err = string.format('too many external claimants (%d) -- release one first', M.MAX_CLAIMANTS) }, false;
        end
    end
    local ttl = tonumber(q.ttl) or M.TTL_DEFAULT;
    local clamped = nil;
    if ttl < M.TTL_MIN then ttl, clamped = M.TTL_MIN, true; end
    if ttl > M.TTL_MAX then ttl, clamped = M.TTL_MAX, true; end
    store[id] = {
        id      = id,
        label   = (type(q.label) == 'string' and q.label ~= '') and q.label or id,
        prio    = tonumber(q.prio) or 0,
        slots   = slots,
        ttl     = ttl,
        expires = now + ttl,
        reply   = (type(q.reply) == 'string' and q.reply ~= '') and q.reply or nil,
        at      = now,
    };
    return { v = 1, what = 'claim', ok = true,
             data = { slots = slots, ttl = ttl, ttlClamped = clamped,
                      expiresIn = ttl, prio = store[id].prio } }, true;
end

-- ---------------------------------------------------------------------------
-- expire -- drop lapsed leases (pure-ish: mutates the store it is handed).
-- Returns the array of ids that lapsed, so the caller can tell each one.
-- ---------------------------------------------------------------------------
function M.expire(store, now)
    local gone = nil;
    for id, r in pairs(store or {}) do
        if type(r) == 'table' and r.expires ~= nil and r.expires <= now then
            gone = gone or {};
            gone[#gone + 1] = { id = id, reply = r.reply };
        end
    end
    for _, g in ipairs(gone or {}) do store[g.id] = nil; end
    if gone ~= nil then table.sort(gone, function(a, b) return tostring(a.id) < tostring(b.id); end); end
    return gone;
end

-- ---------------------------------------------------------------------------
-- The live edge. Everything below touches Ashita; everything above does not.
-- ---------------------------------------------------------------------------

-- The one send door -- injectable so headless tests collect instead of raise.
M._raise = function(name, bytesTbl)
    AshitaCore:GetPluginManager():RaiseEvent(name, bytesTbl);
end

-- ONE serializer for the whole integration surface: the read half owns it and
-- this borrows it, rather than growing a second copy that drifts.
local function ser(v)
    local s = nil;
    pcall(function() s = 'return ' .. require('dlac\\feature\\integration')._ser(v); end);
    return s;
end

local function emit(channel, tbl)
    if type(channel) ~= 'string' or channel == '' then return false; end
    local src = ser(tbl);
    if src == nil then return false; end
    local b = {};
    for i = 1, #src do b[i] = string.byte(src, i); end
    return pcall(function() M._raise(channel .. '_r', b); end);
end
M._emit = emit;

-- The CLAIM the dispatch row reads, rebuilt each call from the live store. Nil
-- when nothing is claimed -- a nil claim is how a claimant says "no opinion",
-- and the row must not hand back an empty table (it would count as ACTIVE).
-- ZERO WHEN IDLE. Both of these run on EVERY dispatch -- the registry asks
-- active() in the ensure pass and claim() in the build pass -- and the dispatch
-- that runs constantly is Default. So the switch being left on must cost
-- nothing while nobody is claiming, or "leave it on" becomes a thing a player
-- has to think about. Neither allocates on the empty path, and active() does
-- not merge at all: it answers the question it was actually asked.
function M.claim()
    if not M.on or next(M._store) == nil then
        M._by, M._shadow = EMPTY, nil;
        return nil;
    end
    local slots, by, shadow = M.merge(M._store, M._clock());
    M._by = by or EMPTY;
    M._shadow = shadow;     -- who lost to whom AMONG the external addons
    return slots;
end

function M.active()
    if not M.on then return false; end
    local store = M._store;
    if next(store) == nil then return false; end
    local now = M._clock();
    for _, r in pairs(store) do
        if type(r) == 'table' and type(r.slots) == 'table'
           and (r.expires == nil or r.expires > now) and next(r.slots) ~= nil then
            return true;
        end
    end
    return false;
end

-- How many addons hold a live lease, and how many slots they hold between them.
function M.holders()
    local now, n, nslots = M._clock(), 0, 0;
    for _, r in pairs(M._store) do
        if type(r) == 'table' and (r.expires == nil or r.expires > now) then
            n = n + 1;
            for _ in pairs(r.slots or {}) do nslots = nslots + 1; end
        end
    end
    return n, nslots;
end

-- The /dl prio + Claim Priority row text. Names the ADDONS, because "some other
-- addon is dressing you" is only useful if the player can see WHICH.
function M.statusText()
    if not M.on then return 'off (/dl claims on)'; end
    local now = M._clock();
    local names = {};
    for id, r in pairs(M._store) do
        if type(r) == 'table' and (r.expires == nil or r.expires > now) then
            names[#names + 1] = tostring(r.label or id);
        end
    end
    if #names == 0 then return 'on -- no addon is claiming'; end
    table.sort(names);
    local _, nslots = M.holders();
    return string.format('claiming %d slot%s for %s', nslots, nslots == 1 and '' or 's',
        table.concat(names, ', '));
end

-- ---------------------------------------------------------------------------
-- THE VERDICT PUSH (the honest half). A claim that was accepted and then lost
-- its slot to a senior claimant is the one outcome an external addon cannot
-- work out for itself -- it would have to diff the worn stream against its own
-- claim and guess. So the dispatch row tells us who beat us, and we tell the
-- addon, ONCE per change (a per-dispatch notice on the Default tick would be a
-- flood, and a flood is how a useful signal gets filtered out and ignored).
--
-- Covers claim-vs-claim contests, which is what `built` holds. A slot withheld
-- by the Locks veto or the Disabled ceiling shows up as "claimed but not worn"
-- on the read half instead; documented, not hidden.
-- ---------------------------------------------------------------------------
function M.noteVerdict(lost)
    if not M.on then return; end
    local byId = {};
    -- Losses to one of DLAC's claimants: the winning slot's owner is the one who
    -- put it in the merged claim, so route by the owner map.
    for slot, winner in pairs(lost or {}) do
        local id = M._by[slot];
        if id ~= nil then
            byId[id] = byId[id] or {};
            byId[id][slot] = winner;
        end
    end
    -- Losses to ANOTHER EXTERNAL ADDON, which the Arbiter never sees because the
    -- merge settled them first. Same notice, same dedupe -- from the addon's
    -- side "something else is wearing that slot" is one fact, and it should not
    -- have to learn about it two different ways.
    for id, slots in pairs(M._shadow or {}) do
        byId[id] = byId[id] or {};
        for slot, winner in pairs(slots) do byId[id][slot] = winner; end
    end
    -- Anyone previously told they lost, who now holds everything again, gets the
    -- all-clear -- otherwise the last thing an addon ever heard is a refusal it
    -- has since recovered from.
    for id in pairs(M._lastLost) do
        if byId[id] == nil then byId[id] = {}; end
    end
    for id, slots in pairs(byId) do
        local keys = {};
        for slot, winner in pairs(slots) do keys[#keys + 1] = slot .. '=' .. tostring(winner); end
        table.sort(keys);
        local sig = table.concat(keys, ',');
        if M._lastLost[id] ~= sig then
            M._lastLost[id] = (sig ~= '') and sig or nil;
            local r = M._store[id];
            if r ~= nil and r.reply ~= nil then
                emit(r.reply, { v = 1, what = 'verdict', ok = true,
                                data = { lost = slots, held = (sig == '') } });
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The inbound door. Deliberately answers `hello` even while the switch is OFF:
-- a consumer has to be able to tell "dlac is not installed" from "dlac is here
-- and the player has not turned claims on", or its own UI cannot say anything
-- useful. Every other verb is gated.
-- ---------------------------------------------------------------------------
function M._onEvent(e)
    local name = nil;
    pcall(function() name = e.name; end);
    if tostring(name or '') ~= M.EVENT then return; end
    local raw = nil;
    pcall(function() raw = e.data; end);            -- a STRING on receive (probed 2026-07-28)
    if type(raw) ~= 'string' or raw == '' then return; end
    local chunk = (loadstring or load)(raw);
    if chunk == nil then return; end
    local ok, q = pcall(chunk);
    if not ok or type(q) ~= 'table' then return; end
    local reply = (type(q.reply) == 'string' and q.reply ~= '') and q.reply or nil;
    if reply == nil then return; end                -- no return address, no conversation

    local what = tostring(q.what or '');
    if not M.on and what ~= 'hello' then
        emit(reply, { v = 1, what = what, ok = false, err = 'external claims are off',
                      data = { on = false, hint = 'the player enables them with /dl claims on (Menu > Settings)' } });
        return;
    end

    local ans, changed = M.handle(M._store, q, M._clock());
    emit(reply, ans);
    if changed then
        M._by = {};
        M._shadow = nil;
        M._lastLost = {};
    end
end

-- The pump: expire lapsed leases, tell their owners, and die with the world.
-- One frame, no allocation while the store is empty.
M._worldAt = 0;          -- next due time for the world check (throttle)
M.WORLD_S  = 1.0;        -- how often to ask; a logout is not a per-frame question

function M._pump()
    -- The world check is a require + a call, and it answers "did you log out",
    -- which cannot become true between two frames in any way that matters. Ask
    -- it once a second, the same 1/sec throttle the engine's own reads use --
    -- the difference is invisible to the player and it is most of what this
    -- pump costs while the switch is simply left on.
    local now = M._clock();
    local due = (now >= (M._worldAt or 0));
    -- The persisted answer is restored on this same beat, BEFORE the on-gate:
    -- the whole point of persisting it is that the player does not re-enable it
    -- every login, so the restore cannot sit behind "only run while enabled".
    if due and not M._flagRead then M._readFlag(); end
    if not M.on then
        if due then M._worldAt = now + (tonumber(M.WORLD_S) or 1.0); end
        return;
    end
    if due then
        M._worldAt = now + (tonumber(M.WORLD_S) or 1.0);
        local okd, dsp = pcall(require, 'dlac\\dispatch');
        local gone = false;
        if okd and type(dsp) == 'table' then
            local okw, v = pcall(dsp.worldAbsentOutlasted);
            gone = (okw and v == true);
        end
        if gone then
            -- Logout. Every CLAIM dies here, like every other session claim in
            -- dlac -- but the SWITCH survives, because it is a saved preference
            -- now and not a per-session consent (2026-08-01). Nothing an addon
            -- holds crosses a logout; only your answer to the question does.
            -- The holders are told first, and `on = true` rides the notice so
            -- they know the door is still open and they may claim again rather
            -- than assuming the player revoked them.
            for _, r in pairs(M._store) do
                if type(r) == 'table' and r.reply ~= nil then
                    emit(r.reply, { v = 1, what = 'expired', ok = true,
                                    data = { reason = 'logout', on = true } });
                end
            end
            M._store, M._by, M._shadow, M._lastLost = {}, {}, nil, {};
            return;
        end
    end
    if next(M._store) == nil then return; end
    local lapsed = M.expire(M._store, now);
    for _, g in ipairs(lapsed or {}) do
        M._lastLost[g.id] = nil;
        if g.reply ~= nil then
            emit(g.reply, { v = 1, what = 'expired', ok = true,
                            data = { reason = 'lease lapsed', on = true } });
        end
    end
end

-- ---------------------------------------------------------------------------
-- THE PERSISTED PERMISSION (2026-08-01). `syncflags.flags.extclaim` is the same
-- uiflags store every other Setting rides; absent reads as OFF, so no install
-- changes behavior and the answer is opt-in exactly as before -- it just stops
-- being asked again every login.
--
-- Written on every setOn (rare -- a checkbox or a command) and read ONCE per
-- session, when the flags first become readable. Read-once is what lets M.on
-- stay the live truth afterwards: a re-read each frame would undo /dl claims off
-- the moment it was typed.
-- ---------------------------------------------------------------------------
M.FLAG = 'extclaim';
M._flagRead = false;     -- has the persisted answer been applied this session?

local function flagsStore()
    local ok, sf = pcall(require, 'dlac\\gear\\syncflags');
    if ok and type(sf) == 'table' and type(sf.flags) == 'table' then return sf; end
    return nil;
end

local function writeFlag(v)
    pcall(function()
        local sf = flagsStore();
        if sf == nil then return; end
        sf.flags[M.FLAG] = (v == true);
        if type(sf.saveUiFlags) == 'function' then sf.saveUiFlags(); end
    end);
end

-- Apply the saved answer, once. Returns true when it has been settled, so the
-- caller stops asking. A nil key is settled too: nothing was ever saved, and
-- OFF is already what M.on says.
function M._readFlag()
    if M._flagRead then return true; end
    local sf = flagsStore();
    if sf == nil then return false; end          -- not loaded yet; ask again later
    local v = sf.flags[M.FLAG];
    if v == nil then return false; end           -- no answer stored (or flags not landed)
    M._flagRead = true;
    if (v == true) ~= M.on then M.setOn(v == true); end
    return true;
end

-- The switch. Turning it OFF drops every claim on the floor and says so -- an
-- addon whose claim the player killed must not be left believing it still holds
-- gear. `data.on` rides every expiry push so a consumer never has to infer the
-- switch state from the reason string.
function M.setOn(v)
    v = (v == true);
    if v == M.on then return M.on; end
    M.on = v;
    M._flagRead = true;        -- an explicit answer supersedes the stored one
    writeFlag(v);
    if not v then
        for _, r in pairs(M._store) do
            if type(r) == 'table' and r.reply ~= nil then
                emit(r.reply, { v = 1, what = 'expired', ok = true,
                                data = { reason = 'player turned external claims off', on = false } });
            end
        end
        M._store, M._by, M._shadow, M._lastLost = {}, {}, nil, {};
    end
    return M.on;
end

-- /dl claims on|off|list (bare = status). Acks are ONE line (the command-ack law).
function M.command(args)
    local a2 = args and args[2] and string.lower(args[2]) or nil;
    if a2 == 'on' then
        M.setOn(true);
        print('[dlac] external claims ON and saved -- other addons may claim gear slots; they rank on the "Other addons" row (/dl prio). Claims themselves die on logout.');
    elseif a2 == 'off' then
        M.setOn(false);
        print('[dlac] external claims off (saved) -- every held claim released.');
    elseif a2 == 'list' then
        local now = M._clock();
        local rows = {};
        for id, r in pairs(M._store) do
            if type(r) == 'table' and (r.expires == nil or r.expires > now) then
                local ks = {};
                for slot, item in pairs(r.slots or {}) do ks[#ks + 1] = slot .. '=' .. tostring(item); end
                table.sort(ks);
                rows[#rows + 1] = string.format('  %s (prio %d, %ds left)  ->  %s',
                    tostring(r.label or id), tonumber(r.prio) or 0,
                    math.max(0, math.floor((r.expires or now) - now)), table.concat(ks, ', '));
            end
        end
        table.sort(rows);
        if #rows == 0 then
            print('[dlac] external claims: ' .. (M.on and 'on -- nobody is claiming.' or 'off.'));
        else
            print('[dlac] external claims:');
            for _, line in ipairs(rows) do print(line); end
        end
    else
        print(string.format('[dlac] external claims: %s -- /dl claims on|off|list (session switch; lets other addons claim gear slots).',
            M.on and M.statusText() or 'off'));
    end
end

-- Live registration: the INBOUND DOOR ONLY. There is deliberately no
-- d3d_present handler here -- dlac.lua's frame beat calls M._pump, the same
-- shape actionseq / engagewatch / combat use. Two reasons, and the second is
-- the one that bites: a module the ENGINE requires lazily (this one first
-- loads on a dispatch) should not be what installs a frame handler, and a
-- listener that only came into existence after dlac's first gear decision
-- would silently ignore any addon that claimed before then -- answered by
-- nobody, with nothing to see. dlac.lua requires this module on frame one, so
-- the door is open from the start of the session.
-- (Headless: absent ashita just skips -- tests drive M._onEvent / M._pump.)
pcall(function()
    ashita.events.register('plugin_event', 'dlac_extclaim', function(e)
        pcall(M._onEvent, e);
    end);
end);

return M;
