--[[
    dlac/gear/arbiter.lua -- THE ARBITER: the pure decision core (ADR 0027,
    stage 3 -- docs/design/two-way-arbiter.md; grown from the ADR 0012
    registry). equipcore's sibling, and held to the same LAYERING law: PURE.
    No AshitaCore, no gData, no io, no globals -- everything here takes plain
    tables and injected reads and returns plain tables, so the whole decision
    core is drivable headless with no stubs at all.

    What lives here (moved verbatim from dispatch.lua, 2026-07-27):
      * the slot vocabulary -- LAC display order, canonical casing, and the
        RSlot bit order (rslotText renders it for every GUI surface);
      * the reservation family -- reservedDrops (single-table + worn),
        reserveFloor / reserveVerdict (v135 multi-slot dominance) and
        reserveResolve (the stage-2 FALL: verdict -> ladder -> re-verdict);
      * the rank vocabulary -- ARB_ORDER_DEFAULT, the pinned ceiling/floor
        rows, arbOrder (the restore-at-default-position law, v122), the
        LOCK_HELD veto sentinel and arbLockClaim;
      * the resolve/explain family -- arbResolve, arbCededAbove, arbExplain,
        arbWhyLines (the /dl why claimant lines);
      * arbitrate(session) -- ONE arbitration per dispatch. Stage 3's first
        slice: it owns the APPLY ORDER M.dispatch executes. Later slices grow
        it into per-slot contests returning the plan + the trace; stage 4
        hands it the ladders (ADR 0027 items 1-2).

    dispatch.lua is the shell: it feeds this module and re-exports every name
    below under its old M.* seams, so every existing caller and test keeps
    its door. New consumers should require THIS module.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- The slot vocabulary. LAC_SLOTS is LAC's display/iteration order (lac-case);
-- LAC_SLOTS_CANON the canonical casing every claim table emits. RSLOT_ORDER
-- below is the CLIENT's slot-bit order -- a different order on purpose, it is
-- the server's rslot mask layout. One home for all three: the twin that
-- drifts is the one nobody re-reads.
-- ---------------------------------------------------------------------------
M.LAC_SLOTS = { 'main', 'sub', 'range', 'ammo', 'head', 'neck', 'ear1', 'ear2',
                'body', 'hands', 'ring1', 'ring2', 'back', 'waist', 'legs', 'feet' };
M.LAC_SLOTS_CANON = { 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck', 'Ear1', 'Ear2',
                      'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet' };
local LAC_SLOTS = M.LAC_SLOTS;

-- ---------------------------------------------------------------------------
-- Reserved slots (RSlot). Some pieces take another slot away while worn: the
-- Ryl.Ftm. Tunic is a Body that reserves Head; robes reserve Hands; a boomerang
-- (Range) reserves Ammo; suits reserve most of the body. It is the server's
-- item_equipment.rslot, carried per item in gear.lua (the engine's only item
-- source -- it has no catalog) and stamped there by the scan / `/dl fix`.
--
-- Equipping into a reserved slot is not a partial failure the server tolerates:
-- it strips the piece straight back, dlac sees the slot is wrong and re-equips,
-- and the two flap forever. Dropping the reserved slot is the only stable state.
--
-- Bit order matches the client's slot order. Tested arithmetically (no `bit`
-- library): this also runs headless on 5.4, where `bit` does not exist and
-- `&` would not parse under LuaJIT.
local RSLOT_ORDER = {
    { 0x0001, 'Main'  }, { 0x0002, 'Sub'   }, { 0x0004, 'Range' }, { 0x0008, 'Ammo'  },
    { 0x0010, 'Head'  }, { 0x0020, 'Body'  }, { 0x0040, 'Hands' }, { 0x0080, 'Legs'  },
    { 0x0100, 'Feet'  }, { 0x0200, 'Neck'  }, { 0x0400, 'Waist' }, { 0x0800, 'Ear1'  },
    { 0x1000, 'Ear2'  }, { 0x2000, 'Ring1' }, { 0x4000, 'Ring2' }, { 0x8000, 'Back'  },
};
M.RSLOT_ORDER = RSLOT_ORDER;
local function hasBit(mask, b) return math.floor(mask / b) % 2 == 1; end
M.hasBit = hasBit;

-- A mask as slot names, in the order above: 16 -> 'Head', 448 -> 'Hands, Legs,
-- Feet', 0/nil -> nil. The engine owns the vocabulary because the engine owns the
-- behaviour -- the GUI prints reservations but must never keep its own copy of
-- which bit is which slot (the twin that drifts is the one nobody re-reads).
function M.rslotText(mask)
    mask = tonumber(mask) or 0;
    if mask <= 0 then return nil; end
    local out = {};
    for _, e in ipairs(RSLOT_ORDER) do
        if hasBit(mask, e[1]) then out[#out + 1] = e[2]; end
    end
    if #out == 0 then return nil; end
    return table.concat(out, ', ');
end

-- Which slots of a RESOLVED set are reserved out from under it.
--   set    -- the resolved slot->name plan; ONLY these slots can be dropped
--   lookup -- itemName -> RSlot mask or nil (injected; tests drive it directly)
--   worn   -- SlotKey -> the name you are wearing there, or nil. Optional, and the
--             reason this is not a pure set-vs-itself check: the Tunic already on
--             your back reserves Head from a set that only writes Head. A slot the
--             set DOES write is judged by the plan, not by what it replaces.
-- Returns { [SlotKey] = reserverName } or nil when nothing is reserved.
--
-- The reserver wins and the reserved slot is dropped -- matching the server, which
-- clears that slot anyway the moment the reserver goes on. Slots are walked in a
-- fixed order, so mutual reservations (a boomerang reserves Ammo; a pebble in Ammo
-- reserves Range) always resolve the same way instead of by pairs() luck, and a
-- slot already dropped never reserves anything itself (Body takes Legs, so the Legs
-- piece must not go on to take Feet).
function M.reservedDrops(set, lookup, worn)
    local keyOf = {};   -- lowercase slot -> the set's actual key, whatever its case
    for slot, v in pairs(set) do
        if type(v) == 'string' then keyOf[string.lower(tostring(slot))] = slot; end
    end
    local name = {};    -- what each slot will actually hold once this set lands
    for _, e in ipairs(RSLOT_ORDER) do
        local ls = string.lower(e[2]);
        if keyOf[ls] ~= nil then
            name[ls] = set[keyOf[ls]];
        elseif worn ~= nil then
            local ok, w = pcall(worn, e[2]);
            if ok and type(w) == 'string' then name[ls] = w; end
        end
    end
    local gone, dropped = {}, nil;
    for _, e in ipairs(RSLOT_ORDER) do
        local ls = string.lower(e[2]);
        if name[ls] ~= nil and not gone[ls] then
            local mask = tonumber(lookup(name[ls])) or 0;
            if mask > 0 then
                for _, r in ipairs(RSLOT_ORDER) do
                    local rls = string.lower(r[2]);
                    if rls ~= ls and keyOf[rls] ~= nil and not gone[rls] and hasBit(mask, r[1]) then
                        gone[rls] = true;
                        dropped = dropped or {};
                        dropped[keyOf[rls]] = name[ls];
                    end
                end
            end
        end
    end
    return dropped;
end

-- ---------------------------------------------------------------------------
-- Multi-slot DOMINANCE (Henrik's ruling, 2026-07-27) -- v135.
-- ---------------------------------------------------------------------------
-- "If an item that reserves more than one slot wins in priority, then it shall
-- claim both slots on a trigger level, where that slot will not be used... he
-- needs to check, am I dominant in both pieces according to you? If not, this
-- piece is not a candidate."
--
-- So a reserving piece is only a CANDIDATE while the claim that wants it is
-- dominant over every slot it reserves:
--   dominant     -> it wins its own slot AND claims the reserved ones, which are
--                   left unwritten (the server empties them itself, natively).
--   not dominant -> the piece is INELIGIBLE; since stage 2 it FALLS to its
--                   source ladder's next rung (reserveResolve below); with no
--                   rung to fall to, its slot is not written at all (v135).

-- The merged floor: entries in APPLY order (lowest priority first, exactly the
-- order the overlay writes them; since stage 4, claim entries follow in rank
-- order, lowest row last-but-strongest), last-writer-wins, each slot tagged
-- with the priority that won it -- and, since stage 2, with `src` (the
-- entry's set name, when it has one): the FALL needs to know whose ladder to
-- ask. Since stage 4 an entry may carry `row` (its Arbiter rank index --
-- SMALLER is stronger); entries without one compare as equals, so every
-- pre-stage-4 caller keeps its exact behavior. Pure. `__`-prefixed keys are
-- metadata, never slots; non-string values (the LOCK_HELD / DISABLED_FREE
-- sentinels) are not merge candidates and pass through untouched.
function M.reserveFloor(entries)
    local floor = {};
    for _, e in ipairs(entries or {}) do
        if type(e) == 'table' and type(e.set) == 'table' then
            local p = tonumber(e.prio) or 0;
            for slot, item in pairs(e.set) do
                if type(item) == 'string' and string.sub(tostring(slot), 1, 2) ~= '__' then
                    floor[slot] = { name = item, prio = p, src = e.src, row = e.row };
                end
            end
        end
    end
    return floor;
end

-- The STRENGTH compare (ADR 0027 item 2, ratified 2026-07-27): across rows,
-- RANK wins outright -- the same ordering the slot contest uses, asked about
-- the reserved slots; within a row, trigger priority (ADR 0003); ties favor
-- the reserver (the caller asks "does a beat b", and an equal-strength answer
-- is NO). `ord` is deliberately excluded: reordering rules in the trigger
-- file must never silently flip a reservation. Entries without a row compare
-- as equals -- the pre-stage-4 floor-only behavior, byte-for-byte.
local function stronger(a, b)
    local ra, rb = tonumber(a.row), tonumber(b.row);
    if ra ~= nil or rb ~= nil then
        ra, rb = ra or math.huge, rb or math.huge;
        if ra ~= rb then return ra < rb; end   -- smaller rank index = stronger
    end
    return (tonumber(a.prio) or 0) > (tonumber(b.prio) or 0);
end

-- The verdict over a merged floor. Two maps, both keyed by the floor's own slot
-- keys (whatever case they arrived in):
--   suppressed[T] = <reserver name>  -- T is claimed and left EMPTY
--   ineligible[S] = <the slot that beat it>  -- S's piece is not a candidate
--
-- Walked in RSLOT_ORDER, like reservedDrops, so the answer never depends on
-- pairs() luck and a chain resolves the same way every time. Two invariants that
-- look small and are not:
--   * the dominance check completes BEFORE anything is suppressed -- ONE contested
--     slot disqualifies the piece, so a piece must never suppress a slot on its
--     way out. An ineligible piece is not being worn; it reserves nothing.
--   * a slot already claimed by an earlier reserver cannot itself reserve (Body
--     takes Legs, so the Legs piece must not go on to take Feet).
function M.reserveVerdict(floor, lookup)
    if type(floor) ~= 'table' or type(lookup) ~= 'function' then return nil, nil; end
    local keyOf = {};
    for slot, e in pairs(floor) do
        if type(e) == 'table' and type(e.name) == 'string' then
            keyOf[string.lower(tostring(slot))] = slot;
        end
    end
    local suppressed, ineligible = nil, nil;
    for _, se in ipairs(RSLOT_ORDER) do
        local sk = keyOf[string.lower(se[2])];
        if sk ~= nil and (suppressed == nil or suppressed[sk] == nil) then
            local ent = floor[sk];
            local mask = tonumber(lookup(ent.name)) or 0;
            if mask > 0 then
                local beatenBy = nil;
                for _, re in ipairs(RSLOT_ORDER) do
                    local rk = keyOf[string.lower(re[2])];
                    if rk ~= nil and rk ~= sk and hasBit(mask, re[1])
                       and stronger(floor[rk], ent) then
                        beatenBy = rk;
                        break;
                    end
                end
                if beatenBy ~= nil then
                    ineligible = ineligible or {};
                    ineligible[sk] = beatenBy;
                else
                    for _, re in ipairs(RSLOT_ORDER) do
                        local rk = keyOf[string.lower(re[2])];
                        if rk ~= nil and rk ~= sk and hasBit(mask, re[1]) then
                            suppressed = suppressed or {};
                            suppressed[rk] = ent.name;
                        end
                    end
                end
            end
        end
    end
    return suppressed, ineligible;
end

-- THE FALL (ADR 0027, stage 2 -- the deferred half of the v135 ruling: "go
-- for the next available piece"). An INELIGIBLE piece no longer strands its
-- slot: its source set's LADDER is asked for the next rung, the verdict
-- re-judges the amended floor, and the loop runs to a fixed point. The two
-- directions of the multi-slot law, now both built:
--   * a refused PIECE falls -- rung by rung, each replacement re-checked, so
--     a rung that reserves a slot a higher claim owns is refused too, and a
--     rung that reserves DOMINATED slots suppresses them exactly like any
--     dominant reserver;
--   * a reserved SLOT never falls -- it is claimed empty by the dominant
--     reserver, and offering it a rung would re-derive the flap the server
--     law exists to kill (the asymmetry pinned in ADR 0027).
-- entries -- reserveFloor's input, each entry optionally carrying `src` (the
--            set NAME its table came from; nil = an inline equip, which has
--            no ladder and keeps v135's unwritten-slot behavior).
-- lookup  -- itemName -> RSlot mask (injected, as everywhere in this family).
-- ladderOf(src, slot) -> the slot's ladder ({ items = { {name=...},... } })
--            -- dispatch.candidatesFor in the live wiring; injected so tests
--            AKF* drive it with plain tables.
-- Returns (suppressed, ineligible, replaced):
--   replaced[slot] = { from, to, by } -- the ORIGINAL pick, the rung that
--   passed, and the slot that beat the original (for the trace). A slot
--   whose every offered rung failed keeps its ineligible entry and gets NO
--   replaced record -- the equip path kills it exactly as v135 did.
-- Cap: three verdict re-runs. Refusals only accumulate (each slot's tried
-- set grows monotonically), so the loop terminates on its own; the cap is
-- the backstop against a pathological reserver chain, and a slot still
-- ineligible when it trips reads INELIGIBLE in /dl why -- visible, never
-- silent.
function M.reserveResolve(entries, lookup, ladderOf)
    local floor = M.reserveFloor(entries);
    local sup, inel = M.reserveVerdict(floor, lookup);
    if inel == nil or type(ladderOf) ~= 'function' then return sup, inel, nil; end
    local replaced, tried = nil, {};
    for _ = 1, 3 do
        local changed = false;
        for slot, beatenBy in pairs(inel) do
            local e = floor[slot];
            if type(e) == 'table' and e.src ~= nil then
                if tried[slot] == nil then tried[slot] = { [e.name] = true }; end
                local from = (replaced ~= nil and replaced[slot] ~= nil)
                             and replaced[slot].from or e.name;
                local by = (replaced ~= nil and replaced[slot] ~= nil)
                             and replaced[slot].by or beatenBy;
                local lad = nil;
                local lok, got = pcall(ladderOf, e.src, slot);
                if lok then lad = got; end
                local items = (type(lad) == 'table') and lad.items or nil;
                local nxt = nil;
                if type(items) == 'table' then
                    for _, r in ipairs(items) do
                        if type(r) == 'table' and type(r.name) == 'string'
                           and not tried[slot][r.name] then
                            nxt = r.name;
                            break;
                        end
                    end
                end
                if nxt ~= nil then
                    tried[slot][nxt] = true;
                    floor[slot] = { name = nxt, prio = e.prio, src = e.src, row = e.row };
                    replaced = replaced or {};
                    replaced[slot] = { from = from, to = nxt, by = by };
                    changed = true;
                end
            end
        end
        if not changed then break; end
        sup, inel = M.reserveVerdict(floor, lookup);
        if inel == nil then break; end
    end
    -- A slot still ineligible after the loop must not read as replaced: its
    -- last offered rung failed too, so the equip path kills it (v135's
    -- behavior, INELIGIBLE note included).
    if inel ~= nil and replaced ~= nil then
        for slot in pairs(inel) do replaced[slot] = nil; end
        if next(replaced) == nil then replaced = nil; end
    end
    return sup, inel, replaced;
end

-- ---------------------------------------------------------------------------
-- The Arbiter's rank vocabulary (ADR 0012, step 1) -- ONE data-driven registry
-- that orders every Claim's application. A Claim is a feature's declared wish
-- to dress slots; the Arbiter decides, per slot, which claimant wins by the
-- user's rank order (CONTEXT.md: Claim / Arbiter).
--
-- The rank is ONE strict list per character, highest priority first, persisted
-- as the `arbstate` Statefile (GUI writer: arbwatch). 'Triggers' is the fixed
-- FLOOR the claims dress over; 'Locks' is the draggable VETO row (step 3): a
-- claimant ranked ABOVE it punches through a locked slot, one below stops.
-- MaxMP keeps its rank ROW while its equip stays woven (ADR 0027 stage 6
-- migrates it).
-- ---------------------------------------------------------------------------
-- 'Disabled' is the CEILING (ADR 0024) -- the mirror of the Triggers floor, and
-- the second fixed row. Both ends of this list are invariants rather than
-- rankings: the claims dress OVER Triggers, and NOTHING dresses THROUGH Disabled.
-- It is listed here so the Priority panel can show it (a player has to be able to
-- see why a slot is inert), never so it can be dragged.
M.ARB_ORDER_DEFAULT = { 'Disabled', 'Naked', 'Pins', 'Locks', 'AutoAmmo', 'MaxMP',
                        'Craft', 'HELM', 'Fishing', 'Chocobo', 'Triggers' };
local ARB_ORDER_DEFAULT = M.ARB_ORDER_DEFAULT;

-- The rows a player can never pick up, and that arbOrder places itself: the
-- Disabled ceiling (first) and the Triggers floor (last). arbwatch.FIXED is the
-- GUI's copy of this same set -- keep them in step.
M.ARB_PINNED = { Disabled = true, Triggers = true };
local ARB_PINNED = M.ARB_PINNED;

-- The live rank order: arbstate's `order` array sanitized against the KNOWN
-- rows -- unknown names dropped, missing known rows restored AT THEIR DEFAULT
-- POSITION, so a partial or hand-mangled (but still parseable) file yields a
-- COMPLETE strict order. A torn/missing file (ensureStateFile drops it to nil)
-- reads as the built-in default. Pure so tests can drive it directly.
--
-- WHERE A MISSING ROW LANDS IS THE WHOLE PROBLEM. Every character who has ever
-- opened the Priority section has an arbstate.lua on disk listing the rows that
-- existed THEN, so every new claimant arrives missing from real files. This used
-- to be a plain APPEND, which is right only for a row that belongs at the bottom
-- (Chocobo, v120) and silently wrong for one that belongs anywhere else: Naked
-- (ADR 0021) appended would ship at rank 9 -- under Locks, under everything --
-- and lose every slot it exists to win, for everyone except a fresh character.
-- The bug would be invisible in test and near-invisible in the field.
--
-- So: insert each missing row BEFORE the first present row that IT OUTRANKS in
-- ARB_ORDER_DEFAULT -- i.e. the first one with a LARGER default index; append
-- when there is none. (Mind the direction: a larger index is a LOWER rank, so
-- the comparison below is `>`. Write `<` and Naked, which outranks everything,
-- finds no row above it and sinks to the bottom -- the exact regression this
-- replaced.) That is one law covering all three
-- cases -- Naked prepends, Chocobo appends, and a future middle row lands in the
-- middle -- with no per-row table to keep in sync. Rows the file DOES list keep
-- the user's order absolutely; this only ever places rows the user has never
-- seen, and once the file names a row this never touches it again.
--
-- The Triggers floor stays a separate hard invariant on top: the claims dress
-- OVER it, so it is always last no matter where a hand-mangled or older file put
-- it. Both passes skip it and it is appended once at the end.
function M.arbOrder(st)
    local given = (type(st) == 'table' and type(st.order) == 'table') and st.order or nil;
    local out, seen = {}, {};
    local known, defIdx = {}, {};
    for i, n in ipairs(ARB_ORDER_DEFAULT) do known[n] = true; defIdx[n] = i; end
    if given ~= nil then
        for _, n in ipairs(given) do
            if known[n] and not seen[n] and not ARB_PINNED[n] then out[#out + 1] = n; seen[n] = true; end
        end
    end
    for _, n in ipairs(ARB_ORDER_DEFAULT) do
        if not seen[n] and not ARB_PINNED[n] then
            local at = #out + 1;                       -- default: the bottom
            for i, have in ipairs(out) do
                if (defIdx[have] or 0) > defIdx[n] then at = i; break; end
            end
            table.insert(out, at, n);
            seen[n] = true;
        end
    end
    -- The two PINNED rows, put back at the ends. Both passes above skip them, so
    -- a hand-mangled (or merely older) file cannot move either one -- which is
    -- the whole point of Disabled: "over EVERYTHING" has to survive a file that
    -- lists it in the middle, or it is a default rather than a ceiling.
    table.insert(out, 1, 'Disabled');
    out[#out + 1] = 'Triggers';
    return out;
end

-- The Locks VETO, modelled as a claim value (ADR 0012, step 3). A locked slot is
-- a Locks "claim" whose winning value is this sentinel -- "keep what is worn". In
-- the rank walk it behaves like any other claimant: a claim ranked ABOVE Locks
-- wins the slot first (punches through), a claim ranked BELOW never reaches it
-- (stops at the lock). The live engine expresses the same law by per-layer
-- lock-respect flags in equipResolved; this is the pure model the tests pin.
M.LOCK_HELD = setmetatable({}, { __tostring = function() return 'LOCK-HELD'; end });

-- Build the Locks claim table for arbResolve from a set of locked slot keys
-- ({ 'head', 'ring1', ... } or { head = true, ... }) -> { [slot] = M.LOCK_HELD }.
-- Pure; the caller passes it in as claims['Locks'].
function M.arbLockClaim(locked)
    local out = {};
    if type(locked) ~= 'table' then return out; end
    if locked[1] ~= nil then
        for _, s in ipairs(locked) do out[s] = M.LOCK_HELD; end
    else
        for s, on in pairs(locked) do if on then out[s] = M.LOCK_HELD; end end
    end
    return out;
end

-- The Arbiter's pure RESOLVE CORE (the seam the acceptance criteria pin): given
-- each active claimant's claim table (slot -> item), the rank `order` (highest
-- first, including the 'Triggers' floor row) and the trigger floor result,
-- decide per slot which claimant wins -- walk the order TOP-DOWN, the first
-- claimant with an opinion on that slot takes it ('Triggers' resolves to the
-- floor). 'Locks' is passed in `claims` as a veto table (M.arbLockClaim): a slot
-- it wins resolves to M.LOCK_HELD (keep worn), so its rank decides who punches
-- through it and who stops. Rows with no claim table (woven MaxMP) are skipped.
-- Returns winners (slot -> item or LOCK_HELD) and by (slot -> claimant).
-- Slot keys are the canonical LAC keys every producer emits, matched as-is.
function M.arbResolve(claims, order, floor)
    local src = {};                       -- claimant name -> claim table
    for name, tbl in pairs(claims or {}) do
        if type(tbl) == 'table' then src[name] = tbl; end
    end
    src['Triggers'] = floor or {};
    local slots = {};                     -- every slot any layer names
    for _, tbl in pairs(src) do
        for slot in pairs(tbl) do slots[slot] = true; end
    end
    local winners, by = {}, {};
    for slot in pairs(slots) do
        for _, name in ipairs(order or {}) do
            local tbl = src[name];
            if tbl ~= nil and tbl[slot] ~= nil then
                winners[slot], by[slot] = tbl[slot], name;
                break;
            end
        end
    end
    return winners, by;
end

-- Slots claimed by any ACTIVE claimant ranked strictly ABOVE `who` in `order`,
-- as { [lowercase slot] = winning-claimant-name }. This is how woven MaxMP
-- "never contests a slot won above me" (ADR 0012): at default order the ceded
-- set is the union of Pins' and AutoAmmo's slots, so a battery yields the Ammo
-- slot to an AutoAmmo projectile but still overrides Craft/HELM/Fishing armor
-- (both ranked below MaxMP). Pure. Reorder MaxMP above AutoAmmo and the Ammo
-- slot is no longer ceded -- the battery wins again, no LAC reload.
function M.arbCededAbove(claims, order, who)
    local rankOf = {};
    for i, n in ipairs(order or {}) do rankOf[n] = i; end
    local mine = rankOf[who];
    local ceded = {};
    if mine == nil then return ceded; end
    for name, tbl in pairs(claims or {}) do
        local r = rankOf[name];
        if r ~= nil and r < mine and type(tbl) == 'table' then
            for slot in pairs(tbl) do ceded[string.lower(tostring(slot))] = name; end
        end
    end
    return ceded;
end

-- ---------------------------------------------------------------------------
-- /dl why claimant attribution (ADR 0012, step 4). The Arbiter is the SINGLE
-- precedence authority, so the same pure resolve that decides winners also
-- EXPLAINS them. arbExplain returns, per slot, the rank-ordered list of every
-- claimant that had an opinion on it (highest rank first) -- the first is the
-- winner, the rest are who it beat. Slot matching is case-insensitive because
-- the producers disagree on case: overlay tables use proper-case LAC keys, the
-- Locks veto rides M.locks (lowercased). 'Triggers' is the floor row; 'Locks'
-- the veto. Pure -- the order-pinning tests drive it directly (AR*/LV*).
--
-- THE CLAIM RECORD SHAPE (documented here for whatever claimant comes next --
-- NOT AutoAcc: Henrik's ruling 2026-07-21 places AutoAcc at within-set
-- altitude, a per-piece Type automation releasing candidates while over the
-- hit cap, the AutoStaff/AutoObi family; the Arbiter never sees it):
-- a Claim is just `{ [SlotKey] = itemName }` -- the slots a feature wants to
-- dress, one item per slot (or the M.LOCK_HELD sentinel for the veto). A new
-- claimant joins the Arbiter with exactly TWO things and NO new arm:
--   1. one rank row  -- add its name to ARB_ORDER_DEFAULT (and arbwatch's UI);
--   2. one CLAIMANTS row (the registry above M.dispatch -- ADR 0027 stage 0):
--      ensure/active/claim/sig/apply/prioStatus in one place; the dispatch
--      loops, both bail guards, the signature legs and /dl prio iterate it.
-- Everything else -- who wins each contested slot, ceding, the Locks veto,
-- /dl why attribution -- falls out of the rank list automatically. MaxMP is the
-- worked example: it registers a claim (mpClaimFor) yet keeps its equip WOVEN,
-- because hold/release/upgrade/sticky/movement-yield are within-set resolution
-- deliberately outside the Arbiter (ADR 0012 consequences).
function M.arbExplain(claims, order, floor)
    local src = {};
    for name, tbl in pairs(claims or {}) do
        if type(tbl) == 'table' then src[name] = tbl; end
    end
    src['Triggers'] = floor or {};
    local rankOf = {};
    for i, n in ipairs(order or {}) do rankOf[n] = i; end
    -- Index each claimant's slots by lowercase key; keep a display key (prefer a
    -- proper-case one when any producer used it).
    local disp, held = {}, {};
    for name, tbl in pairs(src) do
        local m = {};
        for slot, item in pairs(tbl) do
            local ls = string.lower(tostring(slot));
            m[ls] = item;
            if disp[ls] == nil or string.find(tostring(slot), '%u') ~= nil then disp[ls] = slot; end
        end
        held[name] = m;
    end
    local out = {};
    for ls, d in pairs(disp) do
        local ops = {};
        for _, name in ipairs(order or {}) do
            local m = held[name];
            if m ~= nil and m[ls] ~= nil then
                ops[#ops + 1] = { name = name, rank = rankOf[name], item = m[ls] };
            end
        end
        if #ops > 0 then out[d] = ops; end
    end
    return out;
end

-- The /dl why claimant lines: one per slot, naming the winning claimant + rank
-- and, when contested, who it beat -- 'Ammo: AutoAmmo (rank 3) over MaxMP
-- (rank 4)'. A slot the Locks veto won reads 'stopped by Locks'; a slot only the
-- trigger floor named reads 'Triggers (floor)'. Slots emit in canonical LAC
-- order for a stable, greppable trace. Pure (headless-tested): arbExplain +
-- formatting, no engine reads.
function M.arbWhyLines(claims, order, floor)
    local attrib = M.arbExplain(claims, order, floor);
    local slotRank = {};
    for i, s in ipairs(LAC_SLOTS) do slotRank[s] = i; end
    local rows = {};
    for slot, ops in pairs(attrib) do rows[#rows + 1] = { slot = slot, ops = ops }; end
    table.sort(rows, function(a, b)
        local ra = slotRank[string.lower(tostring(a.slot))] or 99;
        local rb = slotRank[string.lower(tostring(b.slot))] or 99;
        if ra ~= rb then return ra < rb; end
        return tostring(a.slot) < tostring(b.slot);
    end);
    -- Contested / veto slots get their own line; slots the trigger floor dressed
    -- uncontested collapse into ONE trailing summary (a floor-only slot wins only
    -- when NO claim touched it -- #ops == 1 -- so nothing is lost, and idle /dl
    -- why is not buried under a dozen 'Triggers (floor)' lines).
    -- Naked collapses the same way, and for a sharper reason: it claims ALL 16, so
    -- without this every other thing /dl why exists to tell you sits under sixteen
    -- identical 'Naked (rank 1)' rows -- and /dl why is exactly what a confused
    -- naked player runs. Who it beat is still reported, deduped across the sweep.
    local lines, floorOnly, floorRank = {}, {}, nil;
    local nakedSlots, nakedRank, nakedBeat, nakedSeen = {}, nil, {}, {};
    -- Disabled (ADR 0024) collapses like Naked, and for the same reason: it can
    -- claim up to sixteen slots and /dl why is exactly what someone runs when a
    -- slot has stopped moving. It goes FIRST in the output, because when it is on
    -- it is the answer to the question that was asked.
    local disSlots, disRank, disBeat, disSeen = {}, nil, {}, {};
    for _, r in ipairs(rows) do
        local ops, win = r.ops, r.ops[1];
        if win.name == 'Triggers' then
            floorOnly[#floorOnly + 1] = tostring(r.slot);
            floorRank = win.rank;
        elseif win.name == 'Disabled' then
            disSlots[#disSlots + 1] = tostring(r.slot);
            disRank = win.rank;
            for i = 2, #ops do
                if not disSeen[ops[i].name] then
                    disSeen[ops[i].name] = true;
                    disBeat[#disBeat + 1] = string.format('%s (rank %d)', ops[i].name, ops[i].rank or 0);
                end
            end
        elseif win.name == 'Naked' then
            nakedSlots[#nakedSlots + 1] = tostring(r.slot);
            nakedRank = win.rank;
            for i = 2, #ops do
                if not nakedSeen[ops[i].name] then
                    nakedSeen[ops[i].name] = true;
                    nakedBeat[#nakedBeat + 1] = string.format('%s (rank %d)', ops[i].name, ops[i].rank or 0);
                end
            end
        else
            local rest = {};
            for i = 2, #ops do rest[#rest + 1] = string.format('%s (rank %d)', ops[i].name, ops[i].rank or 0); end
            local restStr = table.concat(rest, ', ');
            if win.name == 'Locks' then
                lines[#lines + 1] = string.format('%s: stopped by Locks (rank %d)%s',
                    tostring(r.slot), win.rank or 0,
                    (#rest > 0) and ('  [' .. restStr .. ' held off]') or '');
            else
                lines[#lines + 1] = string.format('%s: %s (rank %d)%s',
                    tostring(r.slot), win.name, win.rank or 0,
                    (#rest > 0) and ('  over ' .. restStr) or '');
            end
        end
    end
    if #nakedSlots > 0 then
        table.insert(lines, 1, string.format('NAKED (rank %d) holds %d slot%s empty: %s%s',
            nakedRank or 0, #nakedSlots, (#nakedSlots == 1) and '' or 's',
            table.concat(nakedSlots, ', '),
            (#nakedBeat > 0) and ('  over ' .. table.concat(nakedBeat, ', ')) or ''));
    end
    if #disSlots > 0 then
        table.insert(lines, 1, string.format('FREE EQUIP (ceiling, rank %d) -- dlac writes nothing to %d slot%s: %s%s',
            disRank or 0, #disSlots, (#disSlots == 1) and '' or 's',
            table.concat(disSlots, ', '),
            (#disBeat > 0) and ('  over ' .. table.concat(disBeat, ', ')) or ''));
    end
    if #floorOnly > 0 then
        lines[#lines + 1] = 'Triggers floor (rank ' .. tostring(floorRank or 0) .. ', uncontested): '
                            .. table.concat(floorOnly, ', ');
    end
    return lines;
end

-- THE Range/Ammo compatibility law, exactly as the server writes it
-- (charutils.cpp EquipItem, SLOT_RANGED and SLOT_AMMO arms):
--
--     if (a->getSkillType() != b->getSkillType() ||
--         (b->getSkillType() != SKILL_ARCHERY &&
--          a->getSubSkillType() != b->getSubSkillType()))
--         UnequipItem(<the OTHER slot>);
--
-- Read that consequence twice: the server does not refuse the equip, it STRIPS THE
-- OTHER SLOT. Push a bolt into Ammo while a gun is worn and the GUN comes off -- and
-- since dlac re-proposes both every dispatch, the pair then flaps forever. It is the
-- ADR 0010 failure arriving through the skill/subskill door instead of the rslot one.
--
-- A pair key is "<skill>:<subskill>" (26:1 = gun/bullet, 26:0 = crossbow/bolt,
-- 26:2 = culverin/shell, 27:0 = boomerang/pebble, 27:3 = shuriken, 0:10 = Animator/oil).
-- The subskill half may be ABSENT ("26"): the client resource carries Skill but no
-- subskill, so that is what a manifest written before Pair existed can still answer.
--
-- Three-valued ON PURPOSE -- true / false / nil(unknown) -- because the honest answers
-- are three. Callers must not read nil as false: an unknown pair is the fallback every
-- pre-Pair manifest and every uncrawled custom lands on, and constraining on it would
-- silently switch AutoAmmo off for those players instead of degrading to today's
-- behaviour. Pure (tests PW*).
local function splitPair(p)
    if type(p) ~= 'string' then return nil, nil; end
    local sk, ss = string.match(p, '^(%d+):(%d+)$');
    if sk ~= nil then return tonumber(sk), tonumber(ss); end
    sk = string.match(p, '^(%d+)$');
    if sk ~= nil then return tonumber(sk), nil; end   -- skill known, subskill unknown
    return nil, nil;
end
M._splitPair = splitPair;   -- test seam

M.SKILL_ARCHERY = 25;   -- the one skill the server exempts from the subskill check

function M.pairsWith(a, b)
    local ska, ssa = splitPair(a);
    local skb, ssb = splitPair(b);
    if ska == nil or skb == nil then return nil; end   -- unknown on either side
    if ska ~= skb then return false; end               -- different skill: never pairs
    -- Archery is the exemption the server writes out by hand: a Shortbow (25:0) and a
    -- Longbow (25:4) fire the same arrows. Matching subskill here would break bows.
    if ska == M.SKILL_ARCHERY then return true; end
    if ssa == nil or ssb == nil then return true; end  -- cannot PROVE a mismatch
    return ssa == ssb;
end

-- A Range/Ammo pair the server will not let coexist -- it clears one the moment both are
-- worn, so keeping both flaps forever and re-sends an equip every dispatch. Henrik,
-- 2026-07-26, on why that matters beyond the wrong gear: "that would be good, so we don't
-- spam the server."
--
-- TWO kinds of conflict, and they resolve DIFFERENTLY:
--
--  1. A stat-stick TRINKET (the Ammo item's RSlot reserves the Range slot). Henrik's
--     original rule, ADR 0010, unchanged: keep the HIGHER-LEVEL of the two and drop the
--     other. It is a real trade -- the stick is worn FOR its stats and the server forces
--     Range empty while it sits -- so the better piece deserves to win, and deciding by
--     Level is deterministic, which is what makes it settle instead of oscillate.
--
--  2. A plain PAIRING mismatch between two real pieces -- a bolt in a set with a bow.
--     Here the ammo ALWAYS yields and Range is always kept, whatever the Levels say,
--     because Henrik's rule for the Range slot is absolute: "It should NEVER force
--     ranged off, that is HANDS OFF." Keeping the higher Level here would do exactly
--     that -- a Lv25 Venom Bolt would drop a Lv5 Longbow and leave you holding ammo and
--     no weapon. The weapon is the choice; the ammo follows it. Same principle AutoAmmo
--     runs on: "That is 100 % decided on what gets put in ranged."
--
-- Which one applies is decided by the RSlot bit, and the LAW (M.pairsWith) decides
-- whether there is a conflict at all -- three-valued, so it can both CANCEL a drop the
-- stamp would have made (a compatible pair is never in conflict, whatever the stamp
-- says) and CAUSE one the stamp would have missed (case 2, which had no stamp to catch
-- it). Unknown pair data falls back to the bit alone: an old manifest behaves exactly
-- as it did before.
--
-- rslotFn(name) / levelFn(name) / pairFn(name) are injected (they read the gear
-- manifest; tests drive them).
-- Returns (droppedSlotKey, keptName, why) -- why is 'trinket' or 'mismatch', for the
-- caller's trace line -- or nil when the pair is fine.
function M.trinketRangeDrop(set, rslotFn, levelFn, pairFn)
    if type(set) ~= 'table' then return nil; end
    local rangeKey, rangeName, ammoKey, ammoName;
    for slot, v in pairs(set) do
        if type(v) == 'string' then
            local ls = string.lower(tostring(slot));
            if ls == 'range' then rangeKey, rangeName = slot, v;
            elseif ls == 'ammo' then ammoKey, ammoName = slot, v; end
        end
    end
    if rangeName == nil or ammoName == nil then return nil; end
    -- The RSlot bit is a per-ITEM stamp; the conflict is a per-PAIR fact. The stamp
    -- gets the stat sticks right and is wrong twice over: it marks the skill-0 families
    -- that pair with their own Range piece (Automaton Oil + Animator 0:10, Blank
    -- Soulplate / H.S. Soul Plate + Soultrapper 0:0 -- the 2026-07-22 oil field bug,
    -- patched by id for the four oils only), and it cannot see a mismatch between two
    -- items that both look like ordinary gear (a bolt and a bow).
    local reserves = hasBit(tonumber(rslotFn(ammoName)) or 0, 0x0004);
    -- NOT the `x and f() or nil` idiom: pairsWith returns FALSE for a proven mismatch,
    -- and `and false or nil` collapses it to nil -- which read as "unknown" and made
    -- every mismatch silently do nothing. Three-valued results need a real if.
    local compat = nil;
    if pairFn ~= nil then compat = M.pairsWith(pairFn(rangeName), pairFn(ammoName)); end
    if compat == true then return nil; end                    -- proven fine: never a conflict
    if compat ~= false and not reserves then return nil; end  -- unknown + no stamp: as before
    if reserves then
        local la = tonumber(levelFn(ammoName)) or 0;
        local lr = tonumber(levelFn(rangeName)) or 0;
        if lr > la then return ammoKey, rangeName, 'trinket'; end   -- weapon higher -> drop the stick
        return rangeKey, ammoName, 'trinket';                       -- stick higher-or-equal -> drop the weapon
    end
    return ammoKey, rangeName, 'mismatch';                    -- two real pieces: the ammo yields
end

-- Scope ruling (2026-07-20, Henrik): the keep-higher-Level contest above is a
-- WITHIN-SET rule -- it arbitrates two pieces the plan itself names. A trinket
-- that is merely WORN (yesterday's MP battery, a manual equip) must not defend
-- the Range slot from OUTSIDE the plan: the set's ranged piece wins, whatever
-- the Levels (field case: worn Rimestone Lv60 kept a Lv20 Rouser out of Range
-- forever). And because the server keeps Range CLEAR while such ammo is worn
-- (equipping the weapon alone would just be stripped back -- the ADR 0010
-- flap), winning means DISPLACING the trinket: plan Ammo = 'remove', LAC's
-- native unequip. Pure; the caller guards locks/pins and writes the plan.
--   plan     -- the resolved slot->name table. ANY Ammo entry means the plan
--               speaks for the slot itself (equip or 'remove') -- no displace.
--   wornAmmo -- the name worn in Ammo right now, or nil.
-- Returns ('Ammo', incomingRangeName) when the plan must add Ammo='remove',
-- else nil.
function M.trinketWornDisplace(plan, wornAmmo, rslotFn, pairFn)
    if type(plan) ~= 'table' or type(wornAmmo) ~= 'string' then return nil; end
    local rangeName = nil;
    for slot, v in pairs(plan) do
        local ls = string.lower(tostring(slot));
        if ls == 'ammo' then return nil; end
        if ls == 'range' and type(v) == 'string' and v ~= 'remove' then rangeName = v; end
    end
    if rangeName == nil then return nil; end                  -- nothing incoming to protect
    -- Same two-sided law as trinketRangeDrop. CANCEL: a worn ammo the incoming Range
    -- piece can actually fire is not standing in its way, whatever its RSlot stamp says
    -- (this is what stops a worn Blank Soulplate being 'remove'd the moment a
    -- Soultrapper is planned, and it makes ANIMATOR_FED's id list redundant here).
    -- CAUSE: a worn ammo the incoming weapon CANNOT fire has to go even with no stamp --
    -- a worn bolt would otherwise take the incoming bow straight back off. No Level
    -- contest on this side ever: the plan's Range piece is the player's choice, and the
    -- worn ammo is just what happened to be there.
    local reserves = hasBit(tonumber(rslotFn(wornAmmo)) or 0, 0x0004);
    local compat = nil;   -- a real if: see trinketRangeDrop on `and false or nil`
    if pairFn ~= nil then compat = M.pairsWith(pairFn(rangeName), pairFn(wornAmmo)); end
    if compat == true then return nil; end
    if compat ~= false and not reserves then return nil; end
    return 'Ammo', rangeName;
end

-- ---------------------------------------------------------------------------
-- ONE ARBITRATION PER DISPATCH (ADR 0027, stage 3 -- the first slice). The
-- session so far carries the rank order and the built claims; the plan so far
-- carries the APPLY ORDER -- the reverse rank walk that used to live inline
-- in M.dispatch (overlay is last-writer-wins, so higher rank applies LAST).
-- Stage 3's later slices grow the plan into per-slot contests + the trace
-- /dl why renders; stage 4 hands it the ladders and the cross-rank dominance
-- law (ADR 0027 items 1-2). Pure.
-- ---------------------------------------------------------------------------
function M.arbitrate(session)
    local order = (type(session) == 'table') and session.order or nil;
    local claims = (type(session) == 'table') and session.claims or nil;
    local plan = { applies = {} };
    if type(order) ~= 'table' then return plan; end
    for i = #order, 1, -1 do
        local name = order[i];
        if claims ~= nil and claims[name] ~= nil then
            plan.applies[#plan.applies + 1] = name;
        end
    end
    return plan;
end

return M;
