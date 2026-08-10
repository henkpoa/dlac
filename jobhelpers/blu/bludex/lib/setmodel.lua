--[[
    bludex/lib/setmodel.lua -- the set being edited and everything computable
    from it: point/MP totals, aggregated stat bonuses, and the trait ladder
    evaluation (the same math as the server's blueutils CalculateTraits: sum
    trait weights per category across set spells, highest tier with
    points <= total is active).

    Pure logic; no AshitaCore, no imgui.

    THE TIMELINE MODEL (design settled 2026-08-08, docs/timeline-sets-plan.md):
    a set is no longer a flat spell list -- each of the 20 slots holds a
    CHAIN, a level-ordered stack of entries, and the entry with the highest
    activation level at or below the current level is what the slot wears:

        { name     = 'Leveling',
          builtFor = 75,          -- budget enforcement floor (75 = endgame set)
          chains   = { [1..20] = { { id = 603, from = 4 },      -- Wild Oats
                                   { id = 529, from = 18 },     -- Bludgeon
                                   { id = 0,   from = 45 } } }, -- empty marker
          ids      = {20},        -- DERIVED resolveAtLevel(75) mirror, kept so
                                  -- older readers still see a usable flat set
          backups  = { { ts, name, builtFor, chains }, ... } }  -- cap 5

    resolveAtLevel collapses a set to the flat 20-id array the whole engine
    below this line already speaks (usedPoints/stats/traitEval/sortedLayout/
    applyDiff) -- nothing under the resolution line ever learns chains exist.
    A flat set is the degenerate case: one entry per chain, activating at the
    spell's own level -- exactly how the client treats a flat set today, so
    migration is lossless.

    Slot INDEX carries the unlock bracket: slots 1-6 open at level 1, each
    later pair at 11/21/31/41/51/61/71 (bracketFloor agrees with slotsAtLevel
    at every level -- the smoke suite pins it). A chain is inert below its
    slot's floor whatever its entries say.

    THE THREE KINDS (design settled 2026-08-10, docs/set-types-plan.md): the
    timeline is one of three systems a saved set can be, chosen at creation:

        { kind='flat',     name, ids={20} }
        { kind='levels',   name, ids={20 base build},
                           builds={ {level,ids}.. }, rule=nil|'restore'|.. }
        { kind='timeline', name, builtFor, chains, ids mirror, backups }

    kindOf answers for any table (explicit kind, else inferred by shape);
    the editing surface and resolveAtLevel dispatch on it, so everything
    downstream keeps speaking flat 20-id arrays and never learns which
    system it is talking to. A v1 set stays FLAT -- the v2 adopt used to
    build chains for it; the v3 adopt stamps kinds and converts nothing.
]]--

local M = {};

M.BACKUP_CAP = 5;       -- backups kept per saved set, newest first

-- ---------------------------------------------------------------------------
-- THE TWO KINDS (Henrik 2026-08-10, second field round: "a level set list
-- is basically a flat list but additional level sync opportunity" -- so
-- flat and Lvl Subsets are ONE kind now). The merged kind keeps the
-- 'levels' key -- every stored levels set, sets3 line, share line and
-- backup reads unchanged -- and wears the label 'Flat': a set with no
-- level builds IS the flat set it always was, and any set can grow them.
-- 'flat' remains a valid decode alias everywhere (old stores, old share
-- lines, old backups) and normalizes here.
-- ---------------------------------------------------------------------------
M.KINDS = { 'levels', 'timeline' };
M.KIND_LABELS = { flat = 'Flat', levels = 'Flat', timeline = 'Slotlist' };

-- The one authority on what a set table IS. An explicit kind wins ('flat'
-- normalizing to the merged kind); otherwise the shape speaks: chains ->
-- timeline, everything else -> the merged flat/levels kind.
function M.kindOf(set)
    if type(set) ~= 'table' then return 'levels'; end
    if set.kind == 'timeline' then return 'timeline'; end
    if set.kind == 'levels' or set.kind == 'flat' then return 'levels'; end
    if set.chains ~= nil then return 'timeline'; end
    return 'levels';
end

-- ---------------------------------------------------------------------------
-- construction, cloning, migration
-- ---------------------------------------------------------------------------

local function emptyChains()
    local c = {};
    for i = 1, 20 do c[i] = {}; end
    return c;
end

local function copyChains(chains)
    local c = {};
    for i = 1, 20 do
        c[i] = {};
        for j, e in ipairs(chains and chains[i] or {}) do
            c[i][j] = { id = e.id, from = e.from };
        end
    end
    return c;
end

local function zeroIds()
    local ids = {};
    for i = 1, 20 do ids[i] = 0; end
    return ids;
end

local function copyIds(ids)
    local c = {};
    for i = 1, 20 do c[i] = tonumber(ids and ids[i]) or 0; end
    return c;
end

-- A fresh set of a KIND ('flat' aliases the merged kind). No kind (or
-- 'timeline') builds the timeline shape, so every pre-kinds caller keeps
-- getting what it always got.
function M.new(name, kind)
    name = name or 'New Set';
    if kind == 'flat' or kind == 'levels' then
        return { kind = 'levels', name = name, ids = zeroIds(), builds = {} };
    end
    return {
        kind = 'timeline',
        name = name,
        builtFor = 75,
        chains = emptyChains(),
        ids = zeroIds(),
    };
end

function M.clone(set, name)
    local kind = M.kindOf(set);
    if kind == 'levels' then
        local c = M.new(name or (set.name .. ' copy'), 'levels');
        c.ids = copyIds(set.ids);
        for _, t in ipairs(set.builds or {}) do
            c.builds[#c.builds + 1] = { level = t.level, ids = copyIds(t.ids) };
        end
        c.rule = set.rule;
        return c;
    end
    local c = M.new(name or (set.name .. ' copy'));
    c.builtFor = set.builtFor or 75;
    c.chains = copyChains(set.chains);
    for i = 1, 20 do c.ids[i] = set.ids and set.ids[i] or 0; end
    if set.backups ~= nil then
        c.backups = {};
        for i, b in ipairs(set.backups) do
            c.backups[i] = { ts = b.ts, name = b.name,
                builtFor = b.builtFor or 75, chains = copyChains(b.chains) };
        end
    end
    -- a set that never went through upgrade() clones as-is; the clone is
    -- upgraded the same way the original would be
    if set.chains == nil then c.chains = nil; end
    return c;
end

-- Chains from a flat id list: spells sorted ascending by level (ties by id,
-- unknown levels last) into slots 1..n, one entry each, activating at the
-- spell's own level. This IS today's engine behavior for a flat set -- the
-- sorted apply layout decides which spells a low level keeps -- so the
-- migration is faithful, including the level-8 spell that lands in slot 7
-- and therefore activates at 11 (at level 8 only six slots exist).
function M.buildChains(ids, book)
    local list = {};
    for i = 1, 20 do
        local id = ids and ids[i] or 0;
        if id ~= 0 then list[#list + 1] = id; end
    end
    table.sort(list, function(a, b)
        local la = (book and book.spells[a] and book.spells[a].level) or 999;
        local lb = (book and book.spells[b] and book.spells[b].level) or 999;
        if la ~= lb then return la < lb; end
        return a < b;
    end);
    local chains = emptyChains();
    for i, id in ipairs(list) do
        if i > 20 then break; end
        local s = book and book.spells[id] or nil;
        chains[i] = { { id = id, from = (s and s.level) or 1 } };
    end
    return chains;
end

-- A v2 set straight from a flat id list (blusets import, Read current).
function M.fromIds(name, ids, book)
    local set = M.new(name);
    set.chains = M.buildChains(ids, book);
    M.syncLegacyIds(set, book);
    return set;
end

-- Upgrade a stored set in place to the KIND model (v3): stamp the kind its
-- shape says it is, then tidy that kind's own fields. Returns true when it
-- changed anything. NOTHING is converted -- a v1 flat set stays flat (the
-- v2 adopt used to build chains for it; that stopped with the kinds). The
-- one rebuild kept: a decoded timeline whose chains are all empty while
-- its ids are not (the ids are then the truth and the chains the artifact).
function M.upgrade(set, book)
    local changed = false;
    if set.kind ~= M.kindOf(set) then
        set.kind = M.kindOf(set);      -- 'flat' folds into the merged kind
        changed = true;
    end
    if set.kind == 'levels' then
        if set.builds == nil then changed = true; end
        M.normalizeGroup(set);
        -- THE LEVEL ORDER IS ADOPTED, ONCE (Henrik 2026-08-10, fifth
        -- round). A stored flat build kept whatever order it was typed in
        -- while the apply sorted it anyway, so the order carried no
        -- meaning worth keeping -- and the new slot list would have read
        -- the wrong drop order off it. Base and every band, idempotent
        -- after the first pass.
        if M.sortFlat(set, book) then changed = true; end
        for _, t in ipairs(set.builds or {}) do
            if M.sortFlat(t, book) then changed = true; end
        end
        return changed;
    end
    local chainCount = 0;
    for i = 1, 20 do
        if #(set.chains[i] or {}) > 0 then chainCount = chainCount + 1; end
    end
    local idCount = 0;
    for i = 1, 20 do
        if (set.ids and set.ids[i] or 0) ~= 0 then idCount = idCount + 1; end
    end
    if chainCount == 0 and idCount > 0 then
        set.chains = M.buildChains(set.ids, book);
        set.builtFor = 75;
        M.syncLegacyIds(set, book);
        return true;
    end
    -- make sure the shape is complete (a store decode arrives without the
    -- ids mirror -- re-derive it here)
    -- ALWAYS 75 (Henrik 2026-08-10, sixth round: "it should always be built
    -- for 75"). The field stays -- the wire format and the dlac store both
    -- carry it, and a stored set must keep its shape -- but nothing sets it
    -- to anything else any more, and an older set that carries a lower
    -- floor is pinned here. Budget enforcement is the whole curve now.
    if set.builtFor ~= 75 then set.builtFor = 75; changed = true; end
    for i = 1, 20 do
        if set.chains[i] == nil then set.chains[i] = {}; changed = true; end
    end
    if set.ids == nil then
        M.syncLegacyIds(set, book);
        changed = true;
    end
    return changed;
end

-- ---------------------------------------------------------------------------
-- the bracket rule and resolution
-- ---------------------------------------------------------------------------

-- The level at which a slot exists at all: slots 1-6 from level 1, each
-- later pair at 11/21/31/41/51/61/71. Must agree with slotsAtLevel at every
-- level (the smoke suite sweeps the pair).
function M.bracketFloor(slot)
    if slot <= 6 then return 1; end
    return math.ceil((slot - 6) / 2) * 10 + 1;
end

-- The bracket groups for the editor: { { floor, slots = {..} }, ... }
function M.brackets()
    local out = { { floor = 1, slots = { 1, 2, 3, 4, 5, 6 } } };
    for p = 0, 6 do
        out[#out + 1] = { floor = p * 10 + 11, slots = { 7 + p * 2, 8 + p * 2 } };
    end
    return out;
end

-- Collapse ANY set to the flat 20-id array for a level. Everything
-- downstream (points, stats, traits, sortedLayout, applyDiff) takes this.
-- Per kind:
--   levels    the band's own build when it has one, else the base build
--             (groupPick carries the full rule, empty-base fallback
--             included) -- a set with no builds answers its base ids
--             verbatim at every level, the flat behavior it always had
--   timeline  per chain, the entry with the highest activation at or below
--             the level wins (an empty marker wins as 0); a chain below its
--             slot's floor is inert
function M.resolveAtLevel(set, level, book)
    level = level or 75;
    local kind = M.kindOf(set);
    if kind == 'levels' then
        return M.groupIds(set, M.groupPick(set, level));
    end
    local chains = set.chains;
    if chains == nil then
        -- a set that never went through upgrade(): resolve the flat ids the
        -- same way the migration would have laid them out
        chains = M.buildChains(set.ids or {}, book);
    end
    local out = {};
    for slot = 1, 20 do
        out[slot] = 0;
        if M.bracketFloor(slot) <= level then
            local pick = nil;
            for _, e in ipairs(chains[slot] or {}) do
                if e.from <= level then pick = e; else break; end
            end
            if pick ~= nil then out[slot] = pick.id or 0; end
        end
    end
    return out;
end

-- Keep the legacy flat mirror (set.ids) equal to the level-75 resolution,
-- so every reader that still speaks ids sees a usable flat set.
function M.syncLegacyIds(set, book)
    set.ids = M.resolveAtLevel(set, 75, book);
end

-- The active range of one chain entry: lo..hi inclusive, floored by the
-- slot's bracket, ended by the next entry (or 75). lo > hi = a DEAD entry
-- that is never active (prevented at edit time, tolerated at read time).
function M.entryRange(set, slot, idx)
    local chain = set.chains and set.chains[slot] or nil;
    local e = chain and chain[idx] or nil;
    if e == nil then return nil, nil; end
    local floor = M.bracketFloor(slot);
    local lo = math.max(e.from, floor);
    local hi = 75;
    local nxt = chain[idx + 1];
    if nxt ~= nil then hi = math.max(nxt.from, floor) - 1; end
    return lo, hi;
end

-- Every level range where this spell is active, across all chains:
-- { { slot, idx, lo, hi }, ... } -- dead entries excluded.
function M.activeRanges(set, id)
    local out = {};
    if set.chains == nil or id == 0 then return out; end
    for slot = 1, 20 do
        for idx, e in ipairs(set.chains[slot]) do
            if e.id == id then
                local lo, hi = M.entryRange(set, slot, idx);
                if lo ~= nil and lo <= hi then
                    out[#out + 1] = { slot = slot, idx = idx, lo = lo, hi = hi };
                end
            end
        end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- chain editing -- every mutation validates, then keeps the ids mirror true
-- ---------------------------------------------------------------------------

-- Can this entry join the chain? id = 0 adds an EMPTY MARKER (the slot goes
-- deliberately vacant from that level). Returns ok, reason. from = nil
-- defaults a spell to its own level. THE TWO GUARDS the timeline needs:
--   * no spell may be active at two places at once -- the new entry's range
--     is checked against every other placement of the same spell;
--   * no edit may leave any entry DEAD (never active) -- the neighbor an
--     insert shadows is checked, not just the newcomer.
function M.canAddEntry(set, slot, id, from, book)
    if set.chains == nil then return false, 'set not upgraded'; end
    if slot < 1 or slot > 20 then return false, 'no such slot'; end
    local chain = set.chains[slot];
    local floor = M.bracketFloor(slot);
    if id ~= 0 then
        local s = book.spells[id];
        if s == nil then return false, 'unknown spell'; end
        if not s.castable then return false, 'not castable at 75'; end
        if s.unbridled then return false, 'Unbridled spells cannot be set'; end
        if not book.learned(id) then return false, 'not learned'; end
        if s.setPoints == nil then return false, 'set cost unknown'; end
        from = from or s.level or 1;
        if s.level ~= nil and from < s.level then
            return false, ('cannot activate before its level (%d)'):format(s.level);
        end
    else
        if from == nil then return false, 'an empty marker needs a level'; end
        if #chain == 0 then return false, 'the slot is already empty'; end
    end
    if from < 1 or from > 75 then return false, 'level must be 1-75'; end

    -- the sorted insert position; equal activation levels cannot coexist
    local pos = #chain + 1;
    for i, e in ipairs(chain) do
        if e.from == from then
            return false, ('another entry already activates at Lv.%d'):format(from);
        end
        if e.from > from then pos = i; break; end
    end
    if id == 0 then
        local prev = chain[pos - 1];
        if prev == nil then return false, 'the slot is already empty there'; end
        if prev.id == 0 then
            return false, ('already empty from Lv.%d'):format(prev.from);
        end
        local nxt = chain[pos];
        if nxt ~= nil and nxt.id == 0 then
            return false, ('already empty from Lv.%d on'):format(nxt.from);
        end
    end

    -- simulate the insert: nobody in the chain may end up dead
    local sim = {};
    for i = 1, pos - 1 do sim[i] = chain[i]; end
    sim[pos] = { id = id, from = from };
    for i = pos, #chain do sim[i + 1] = chain[i]; end
    local newLo, newHi = nil, nil;
    for i, e in ipairs(sim) do
        local lo = math.max(e.from, floor);
        local hi = 75;
        if sim[i + 1] ~= nil then hi = math.max(sim[i + 1].from, floor) - 1; end
        if i == pos then newLo, newHi = lo, hi; end
        if lo > hi then
            if i == pos then
                if from < floor then
                    return false, ('never active here (the slot unlocks at Lv.%d)'):format(floor);
                end
                return false, ('replaced at Lv.%d before it ever activates'):format(hi + 1);
            end
            local nm = 'the empty marker';
            if e.id ~= 0 then
                nm = (book.spells[e.id] and book.spells[e.id].name) or ('#' .. e.id);
            end
            return false, ('%s would never be active in this slot'):format(nm);
        end
    end

    -- the one-place-at-a-time rule: the new range against every OTHER
    -- placement of the same spell (ranges inside this chain are disjoint by
    -- construction -- only other slots can collide)
    if id ~= 0 then
        for _, r in ipairs(M.activeRanges(set, id)) do
            if r.slot ~= slot and newLo <= r.hi and r.lo <= newHi then
                return false, ('already active at Lv.%d-%d in another slot'):format(r.lo, r.hi);
            end
        end
    end
    return true;
end

-- Drop leading empty markers (a chain starts empty anyway) and collapse
-- consecutive ones (the second says nothing the first did not).
local function normalizeChain(chain)
    while chain[1] ~= nil and chain[1].id == 0 do table.remove(chain, 1); end
    local i = 2;
    while chain[i] ~= nil do
        if chain[i].id == 0 and chain[i - 1].id == 0 then
            table.remove(chain, i);
        else
            i = i + 1;
        end
    end
end

function M.addEntry(set, slot, id, from, book)
    local ok, reason = M.canAddEntry(set, slot, id, from, book);
    if not ok then return false, reason; end
    if id ~= 0 and from == nil then
        local s = book.spells[id];
        from = (s and s.level) or 1;
    end
    local chain = set.chains[slot];
    local pos = #chain + 1;
    for i, e in ipairs(chain) do
        if e.from > from then pos = i; break; end
    end
    table.insert(chain, pos, { id = id, from = from });
    normalizeChain(chain);
    M.syncLegacyIds(set, book);
    return true;
end

-- Remove one entry. THE EXTENSION GUARD: removing an entry stretches its
-- predecessor's range over the removed span, and if that predecessor is a
-- spell that also lives elsewhere, the stretch can make it active in two
-- places at once -- the edit is rejected with the collision named, never
-- silently absorbed (docs/timeline-sets-plan.md 2.4).
function M.removeEntry(set, slot, idx, book)
    local chain = set.chains and set.chains[slot] or nil;
    local e = chain and chain[idx] or nil;
    if e == nil then return false, 'no such entry'; end
    local floor = M.bracketFloor(slot);
    local prev = chain[idx - 1];
    if prev ~= nil and prev.id ~= 0 then
        local nxt = chain[idx + 1];
        local newHi = 75;
        if nxt ~= nil then newHi = math.max(nxt.from, floor) - 1; end
        local prevLo = math.max(prev.from, floor);
        if prevLo <= newHi then
            for _, r in ipairs(M.activeRanges(set, prev.id)) do
                if not (r.slot == slot and r.idx == idx - 1)
                    and prevLo <= r.hi and r.lo <= newHi then
                    local nm = (book and book.spells[prev.id] and book.spells[prev.id].name)
                        or ('#' .. tostring(prev.id));
                    return false, ('%s would then be active twice (already Lv.%d-%d elsewhere)'):format(nm, r.lo, r.hi);
                end
            end
        end
    end
    table.remove(chain, idx);
    normalizeChain(chain);
    M.syncLegacyIds(set, book);
    return true;
end

-- Clear one whole chain. Always safe: nothing extends when a chain simply
-- disappears, and no other slot's ranges move.
function M.clearChain(set, slot, book)
    if set.chains == nil or set.chains[slot] == nil then return; end
    set.chains[slot] = {};
    M.syncLegacyIds(set, book);
end

-- Move ONE entry to a new activation level, in place (the slot editor,
-- 2026-08-10): take it out, validate the landing like any add, and put it
-- back EXACTLY where it was when the landing is refused -- an edit either
-- succeeds whole or changes nothing. Returns ok, why.
function M.setEntryLevel(set, slot, idx, from, book)
    local chain = set.chains and set.chains[slot] or nil;
    local e = chain and chain[idx] or nil;
    if e == nil then return false, 'no such entry'; end
    if from == e.from then return true; end
    local old = { id = e.id, from = e.from };
    table.remove(chain, idx);
    local ok, why = M.canAddEntry(set, slot, old.id, from, book);
    if ok then
        return M.addEntry(set, slot, old.id, from, book);
    end
    local pos = #chain + 1;
    for i, x in ipairs(chain) do
        if x.from > old.from then pos = i; break; end
    end
    table.insert(chain, pos, old);
    M.syncLegacyIds(set, nil);
    return false, why;
end

function M.clear(set)
    if M.kindOf(set) == 'timeline' and set.chains ~= nil then
        set.chains = emptyChains();
    end
    -- non-timeline: only the ids being edited (a levels draft's band, a
    -- flat set's list) -- never a levels entry's other builds
    for i = 1, 20 do set.ids[i] = 0; end
end

-- A flat set: at most one entry per chain, no empty markers, every entry at
-- its spell's own level -- the degenerate case the editor shows without
-- timeline chrome (most endgame sets stay this shape forever).
function M.isFlat(set, book)
    if set.chains == nil then return true; end
    for slot = 1, 20 do
        local chain = set.chains[slot];
        if #chain > 1 then return false; end
        local e = chain[1];
        if e ~= nil then
            if e.id == 0 then return false; end
            local s = book and book.spells[e.id] or nil;
            if s ~= nil and s.level ~= nil and e.from ~= s.level then return false; end
        end
    end
    return true;
end

-- Deep equality of what the player authored, per kind. Backups and the
-- derived ids mirror are bookkeeping, not authorship.
local function idsEqual(a, b)
    for i = 1, 20 do
        if (a and a[i] or 0) ~= (b and b[i] or 0) then return false; end
    end
    return true;
end

function M.equal(a, b)
    local kind = M.kindOf(a);
    if kind ~= M.kindOf(b) then return false; end
    if tostring(a.name) ~= tostring(b.name) then return false; end
    if kind == 'levels' then
        if not idsEqual(a.ids, b.ids) then return false; end
        if a.rule ~= b.rule then return false; end
        local ba, bb = a.builds or {}, b.builds or {};
        if #ba ~= #bb then return false; end
        for i = 1, #ba do
            if ba[i].level ~= bb[i].level then return false; end
            if not idsEqual(ba[i].ids, bb[i].ids) then return false; end
        end
        return true;
    end
    if (a.builtFor or 75) ~= (b.builtFor or 75) then return false; end
    local ca = a.chains or {};
    local cb = b.chains or {};
    for slot = 1, 20 do
        local x, y = ca[slot] or {}, cb[slot] or {};
        if #x ~= #y then return false; end
        for i = 1, #x do
            if x[i].id ~= y[i].id or x[i].from ~= y[i].from then return false; end
        end
    end
    return true;
end

-- ---------------------------------------------------------------------------
-- backups -- pushed on every destructive replace (save-over, read-current,
-- convert), newest first, capped. ts is injected so this stays clock-free
-- and testable. A backup is KIND-SHAPED (2026-08-10): it banks the source's
-- authorship as its kind holds it -- and restoring one whose kind differs
-- from the set's FLIPS the set back, which is what makes a lossy
-- conversion undoable. A pre-kinds stored backup has chains and no kind
-- tag; kindOf reads it as timeline, which is what it always was.
-- ---------------------------------------------------------------------------
function M.pushBackup(set, source, ts)
    set.backups = set.backups or {};
    local kind = M.kindOf(source);
    local b = { ts = ts, kind = kind, name = source.name };
    if kind == 'timeline' then
        b.builtFor = source.builtFor or 75;
        b.chains = copyChains(source.chains);
    else
        b.ids = copyIds(source.ids);
        if kind == 'levels' then
            b.builds = {};
            for _, t in ipairs(source.builds or {}) do
                b.builds[#b.builds + 1] = { level = t.level, ids = copyIds(t.ids) };
            end
            b.rule = source.rule;
        end
    end
    table.insert(set.backups, 1, b);
    while #set.backups > M.BACKUP_CAP do table.remove(set.backups); end
end

-- Restore backup i IN PLACE, pushing the current state as a backup first --
-- so a restore is itself undoable. The set keeps its current NAME (names
-- are identity keys: activeSetName restores by them) and its ring; every
-- other field becomes the backup's, ITS kind's fields included -- the
-- other kinds' fields are cleared, never left to shadow. Returns true.
function M.restoreBackup(set, i, book, ts)
    local b = set.backups and set.backups[i] or nil;
    if b == nil then return false; end
    M.pushBackup(set, set, ts);
    -- 'flat' backups (pre-merge, 2026-08-10) restore as the merged kind
    local kind = (b.kind == 'timeline' or b.chains ~= nil) and 'timeline' or 'levels';
    set.kind = kind;
    if kind == 'timeline' then
        set.builds, set.rule = nil, nil;
        set.builtFor = b.builtFor or 75;
        set.chains = copyChains(b.chains);
        M.syncLegacyIds(set, book);
    else
        set.chains, set.builtFor = nil, nil;
        set.ids = copyIds(b.ids);
        set.builds = {};
        for _, t in ipairs(b.builds or {}) do
            set.builds[#set.builds + 1] = { level = t.level, ids = copyIds(t.ids) };
        end
        set.rule = b.rule;
    end
    return true;
end

-- ---------------------------------------------------------------------------
-- THE LEVELS KIND (built 2026-08-06, back from history 2026-08-10): a build
-- per level band under one name, the base build the fallback everywhere no
-- band is built. THE RUNGS: the server's two set rules -- how many slots
-- and how many base points -- both step every ten levels from 1, so one
-- build serves a whole band: a set made for Lv.41 is the same set at 50.
-- Eight rungs, each named for the level its band opens at. 71 is the last:
-- 71-75 share a base, and the Assimilation merits land inside it, at 75.
-- ---------------------------------------------------------------------------
M.LEVELS = { 1, 11, 21, 31, 41, 51, 61, 71 };
M.TOP    = 71;

-- The rung a level belongs to: 40 -> 31, 75 -> 71, 1 -> 1. nil off BLU.
function M.rungFor(level)
    if level == nil or level < 1 then return nil; end
    local r = math.floor((level - 1) / 10) * 10 + 1;
    if r > M.TOP then r = M.TOP; end
    return r;
end

-- The top level a rung's band reaches: 41 -> 50, 71 -> 75 (the cap). A build
-- may hold any spell its band can cast, not only what the rung level can --
-- points and slots are flat across a band, spell levels are not.
function M.bandTop(level)
    if level == nil or level >= M.TOP then return 75; end
    return level + 9;
end

-- Slots this build may fill: its band's server slot count. A level-less one
-- is the flat shape, and keeps all 20.
function M.slotMax(set)
    if set == nil or set.level == nil then return 20; end
    return M.slotsAtLevel(set.level);
end

function M.countIds(ids)
    local n = 0;
    for i = 1, 20 do if (ids[i] or 0) ~= 0 then n = n + 1; end end
    return n;
end

-- The level a build actually becomes usable at: the highest spell level in
-- it. nil when it holds nothing the data knows a level for.
function M.usableFrom(ids, book)
    local top = nil;
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.level and (top == nil or s.level > top) then top = s.level; end
    end
    return top;
end

local function sortBuilds(entry)
    table.sort(entry.builds, function(a, b) return (a.level or 0) < (b.level or 0); end);
end

-- Bring a saved levels entry to shape WITHOUT converting anything. All this
-- does is give it an empty build list and tidy any builds it does have --
-- levels snapped to real rungs, duplicates dropped -- so a hand-edited
-- settings file cannot surprise anything downstream.
--
-- An EMPTY build is kept: bands are added on purpose (groupAdd) and one you
-- added but have not filled yet is a real thing, not a leftover.
-- Idempotent: the UI runs it over every entry it draws.
function M.normalizeGroup(entry)
    if type(entry) ~= 'table' then return entry; end
    entry.ids = copyIds(entry.ids);
    if not M.RULE_KEYS[entry.rule] then entry.rule = nil; end   -- back to derived
    local seen, keep = {}, {};
    for _, t in ipairs(entry.builds or {}) do
        local lvl = M.rungFor(tonumber(t.level) or 0);
        if lvl ~= nil and type(t.ids) == 'table' and not seen[lvl] then
            seen[lvl] = true;
            keep[#keep + 1] = { level = lvl, ids = copyIds(t.ids) };
        end
    end
    entry.builds = keep;
    sortBuilds(entry);
    return entry;
end

function M.groupBuild(entry, level)
    for _, t in ipairs((entry and entry.builds) or {}) do
        if t.level == level then return t; end
    end
    return nil;
end

-- A build's ids, always 20 long -- level nil is the base build, and an
-- unbuilt rung answers all zeros rather than nil.
function M.groupIds(entry, level)
    local src = (level == nil) and entry or M.groupBuild(entry, level);
    return copyIds(src and src.ids);
end

-- Write a build back, empty or not: emptying a band is not the same as not
-- having one, and only groupRemove takes a band away.
function M.groupPut(entry, level, ids)
    local copy = copyIds(ids);
    if level == nil then entry.ids = copy; return; end
    entry.builds = entry.builds or {};
    for _, t in ipairs(entry.builds) do
        if t.level == level then t.ids = copy; return; end
    end
    entry.builds[#entry.builds + 1] = { level = level, ids = copy };
    sortBuilds(entry);
end

-- BANDS ARE ADDED ON PURPOSE (Henrik 2026-08-06). Offering all eight under
-- every set reads as eight things you are behind on; a set has the levels
-- you said it has, and none to begin with. Returns true when this added one.
function M.groupAdd(entry, level)
    -- nil is the base build, which every set already has, and a level that
    -- is not a band start is not a band at all
    if level == nil or M.rungFor(level) ~= level then return false; end
    if M.groupBuild(entry, level) ~= nil then return false; end
    entry.builds = entry.builds or {};
    entry.builds[#entry.builds + 1] = { level = level, ids = zeroIds() };
    sortBuilds(entry);
    return true;
end

function M.groupRemove(entry, level)
    for i, t in ipairs((entry and entry.builds) or {}) do
        if t.level == level then table.remove(entry.builds, i); return true; end
    end
    return false;
end

-- THE LEVEL-CHANGE RULE BELONGS TO THE SET (Henrik 2026-08-07): "Solo
-- follows my level" is a fact about Solo. Unset, the rule is DERIVED from
-- the set's shape -- restore while it is flat, switch once it has levels --
-- so the default follows what you build; a stored pick stands. NOTE: nothing
-- arms these yet in the kinds era -- the levels watcher is the next slice
-- (docs/set-types-plan.md 5) -- but the model keeps the vocabulary so
-- stored rules survive the round trip.
M.RULE_KEYS = { restore = true, switch = true, manual = true };

function M.ruleOf(entry)
    if type(entry) ~= 'table' then return 'restore'; end
    if M.RULE_KEYS[entry.rule] then return entry.rule; end
    return (#(entry.builds or {}) > 0) and 'switch' or 'restore';
end

function M.setRule(entry, rule)
    if type(entry) ~= 'table' or not M.RULE_KEYS[rule] then return false; end
    entry.rule = rule;
    return true;
end

-- The bands not yet added, ascending -- what the Add list offers.
function M.groupFree(entry)
    local out = {};
    for _, lvl in ipairs(M.LEVELS) do
        if M.groupBuild(entry, lvl) == nil then out[#out + 1] = lvl; end
    end
    return out;
end

-- The rungs that HAVE a build, ascending, empty ones included (the base
-- build is not one of them).
function M.groupLevels(entry)
    local out = {};
    for _, t in ipairs((entry and entry.builds) or {}) do out[#out + 1] = t.level; end
    table.sort(out);
    return out;
end

-- The highest built rung, or nil when only the base build exists.
function M.groupTop(entry)
    local lv = M.groupLevels(entry);
    return lv[#lv];
end

-- The build to use AT a level -- the one rule the levels kind turns on
-- (Henrik 2026-08-06):
--
--   the band's OWN build when there is one; otherwise THE BASE BUILD.
--
-- The base build is the set's backup, and it stays the answer everywhere no
-- band build has been made. It does NOT fill forward: a Lv.31 build is for
-- Lv.31-40 and nowhere else, so walking out of a sync goes back to the base
-- set rather than dragging a level-31 build to 75. Copy it up a band if you
-- want it to keep serving (setsui's Copy).
--
-- Returns the rung, or nil for the base build. The one exception is the set
-- with an EMPTY base build: there is no backup to fall back on, so the
-- nearest build below answers rather than nothing at all.
-- A band that was added but never filled is NOT a build to pick: it means
-- "I will get to this", not "wear nothing here".
function M.groupPick(entry, level)
    local rung = M.rungFor(level);
    if rung == nil then return nil; end
    local own = M.groupBuild(entry, rung);
    if own ~= nil and M.countIds(own.ids) > 0 then return rung; end
    if M.countIds((entry and entry.ids) or {}) > 0 then return nil; end
    local best = nil;
    for _, t in ipairs((entry and entry.builds) or {}) do
        if M.countIds(t.ids) > 0 and t.level <= rung
            and (best == nil or t.level > best) then best = t.level; end
    end
    if best == nil then
        for _, t in ipairs((entry and entry.builds) or {}) do
            if M.countIds(t.ids) > 0 and (best == nil or t.level < best) then
                best = t.level;
            end
        end
    end
    return best;
end

-- THE FLAT ORDER, in one place: spell level ascending, ties by id, and an
-- id the data does not know sorted LAST rather than dropped. Every flat
-- placement speaks it -- copyInto, sortedLayout on the way to the game, and
-- sortFlat on the stored array itself.
local function byLevel(book)
    return function(a, b)
        local sa = book and book.spells[a] or nil;
        local sb = book and book.spells[b] or nil;
        local la = (sa and sa.level) or 999;
        local lb = (sb and sb.level) or 999;
        if la ~= lb then return la < lb; end
        return a < b;
    end;
end

-- Copy a build's spells into another band, keeping what that band can
-- actually hold: nothing above the level it can cast, lowest levels first,
-- until its slots run out.
--
-- The POINT budget is deliberately NOT enforced. Coming in over budget is
-- the workflow -- you see the red meter and cut what you can spare, which
-- is a judgement only the player can make; a copy that quietly dropped the
-- spells it happened to like least would take that away and look tidy
-- doing it.
--
-- Returns ids{20}, report { taken, tooHigh, noSlot }.
function M.copyInto(ids, level, book)
    local slots = (level == nil) and 20 or M.slotsAtLevel(level);
    local top = M.bandTop(level);
    local pick, tooHigh = {}, 0;
    for i = 1, 20 do
        local id = ids[i] or 0;
        if id ~= 0 then
            local s = book.spells[id];
            if s ~= nil and s.level ~= nil and s.level > top then
                tooHigh = tooHigh + 1;
            else
                pick[#pick + 1] = id;
            end
        end
    end
    table.sort(pick, byLevel(book));
    local out = {};
    for i = 1, 20 do out[i] = pick[i] or 0; end
    local taken = #pick;
    if taken > slots then
        for i = slots + 1, 20 do out[i] = 0; end
        taken = slots;
    end
    return out, { taken = taken, tooHigh = tooHigh, noSlot = #pick - taken };
end

-- COPY ANOTHER SET'S SPELLS INTO THIS ONE (Henrik 2026-08-10, sixth round:
-- "make it a copy from button instead... obviously it will only be able to
-- copy the top level of spells, but should save people some time").
--
-- The source arrives already flattened -- resolveAtLevel at 75, its
-- TOP-LEVEL plan, which is the one reading that means the same thing
-- whatever kind it came from. A slotlist's per-level authorship cannot
-- survive that flattening and is not pretended to: what crosses is the set
-- of spells, and the target's own kind decides how they land.
--
-- REPLACES, never merges. "Copy from" means make this look like that; a
-- merge would need a rule for collisions nobody asked for. The caller does
-- the confirming.
--
-- Returns { taken, tooHigh, noSlot, refused }:
--   tooHigh   above what this band can cast (a levels draft's ceiling)
--   noSlot    ran out of slots
--   refused   the model said no for any other reason (unlearned, unbridled)
function M.copyFrom(set, srcIds, book)
    if M.kindOf(set) ~= 'timeline' then
        -- the id-array path already knows this job: sorted by level, the
        -- band's ceilings applied, the rest reported
        local ids, rep = M.copyInto(srcIds, set.level, book);
        for i = 1, 20 do set.ids[i] = ids[i]; end
        rep.refused = 0;
        return rep;
    end
    -- A SLOTLIST takes one spell per slot, each activating at its own level
    -- -- the only honest placement from a flat reading: nothing in a 20-id
    -- list says when anything should take over from anything else. Chains
    -- are yours to build from here.
    M.clear(set);
    local pick = {};
    for i = 1, 20 do
        local id = srcIds[i] or 0;
        if id ~= 0 then pick[#pick + 1] = id; end
    end
    table.sort(pick, byLevel(book));
    local rep = { taken = 0, tooHigh = 0, noSlot = 0, refused = 0 };
    for _, id in ipairs(pick) do
        local slot = M.freeSlot(set);
        if slot == nil then
            rep.noSlot = rep.noSlot + 1;
        elseif M.addEntry(set, slot, id, nil, book) then
            rep.taken = rep.taken + 1;
        else
            rep.refused = rep.refused + 1;
        end
    end
    return rep;
end

-- One build of a levels set as an editable DRAFT -- the shape the Sets tab
-- edits and every computation takes (no chains, so every editing op below
-- runs its id-array path; level carries the band ceilings into canAdd).
-- `book` is optional and only buys the level sort: OPENING a build is the
-- one choke point every band build passes through on its way to the editor,
-- whatever wrote it (copyInto, a draft save, a hand-edited settings file,
-- an old store entry), so the list can never read out of order. Without a
-- book the ids are left exactly as found -- guessing an order from ids
-- alone would be worse than none.
function M.draft(entry, level, book)
    local d = { kind = 'levels', draft = true, name = entry.name,
                level = level, ids = M.groupIds(entry, level) };
    if book ~= nil then M.sortFlat(d, book); end
    return d;
end

-- ---------------------------------------------------------------------------
-- SHARE TEXT (2026-08-10, the dlac friend-share flow scaled to one set):
-- a set as ONE pasteable line -- BDXSET1|kind|name|payload|crc4 -- with no
-- tabs anywhere, so chat, Discord and clipboards carry it whole. The
-- checksum catches a truncated or mangled paste BEFORE the tolerant decode
-- could quietly import half a set. Backups never travel: the text is the
-- set's authorship, not its history.
--
-- Payloads (all built from ',', ';', '@', '~', '=' -- never '|' or tabs):
--   flat      id,id,...                                    (20 csv)
--   levels    base-csv[~rule=key][~41=csv][~71=csv]...
--   timeline  builtFor~chains    (chains: ';'-joined slots of 'id@from')
-- The name percent-encodes '%', '|', '~' and whitespace-breakers.
-- ---------------------------------------------------------------------------

local function shareEncName(s)
    return (tostring(s):gsub('[%%|~\t\r\n]', function(c)
        return ('%%%02X'):format(c:byte());
    end));
end

local function shareDecName(s)
    return (tostring(s):gsub('%%(%x%x)', function(h)
        return string.char(tonumber(h, 16));
    end));
end

local function shareCrc(s)
    local n = 0;
    for i = 1, #s do n = (n * 31 + s:byte(i)) % 65536; end
    return ('%04x'):format(n);
end

local function shareEncIds(ids)
    local parts = {};
    for i = 1, 20 do parts[i] = tostring(tonumber(ids and ids[i]) or 0); end
    return table.concat(parts, ',');
end

local function shareDecIds(s)
    local ids, i = zeroIds(), 0;
    for tok in tostring(s or ''):gmatch('[^,]+') do
        i = i + 1;
        if i > 20 then break; end
        ids[i] = tonumber(tok) or 0;
    end
    return ids;
end

local function shareEncChains(chains)
    local slots = {};
    for i = 1, 20 do
        local parts = {};
        for _, e in ipairs(chains and chains[i] or {}) do
            parts[#parts + 1] = ('%d@%d'):format(tonumber(e.id) or 0, tonumber(e.from) or 1);
        end
        slots[i] = table.concat(parts, ',');
    end
    return table.concat(slots, ';');
end

local function shareDecChains(s)
    local chains = emptyChains();
    local slot = 0;
    for tok in (tostring(s or '') .. ';'):gmatch('(.-);') do
        slot = slot + 1;
        if slot > 20 then break; end
        for entry in tok:gmatch('[^,]+') do
            local id, from = entry:match('^(%-?%d+)@(%-?%d+)$');
            id, from = tonumber(id), tonumber(from);
            if id ~= nil and from ~= nil and from >= 1 and from <= 75 then
                chains[slot][#chains[slot] + 1] = { id = id, from = from };
            end
        end
        table.sort(chains[slot], function(a, b) return a.from < b.from; end);
    end
    return chains;
end

function M.shareText(set)
    local kind = M.kindOf(set);
    local payload;
    if kind == 'timeline' then
        payload = tostring(tonumber(set.builtFor) or 75) .. '~' .. shareEncChains(set.chains);
    elseif kind == 'levels' then
        local parts = { shareEncIds(set.ids) };
        if M.RULE_KEYS[set.rule or ''] then
            parts[#parts + 1] = 'rule=' .. tostring(set.rule);
        end
        for _, t in ipairs(set.builds or {}) do
            parts[#parts + 1] = ('%d=%s'):format(tonumber(t.level) or 71, shareEncIds(t.ids));
        end
        payload = table.concat(parts, '~');
    else
        payload = shareEncIds(set.ids);
    end
    local body = kind .. '|' .. shareEncName(set.name) .. '|' .. payload;
    return 'BDXSET1|' .. body .. '|' .. shareCrc(body);
end

-- The paste side. Tolerates the line arriving wrapped in chat framing
-- ('Mindie: BDXSET1|...') and trailing whitespace; refuses a damaged or
-- truncated body by checksum, with a reason a person can act on.
-- Returns set, nil -- or nil, why.
function M.parseShare(text)
    local body, sum = tostring(text or ''):match('BDXSET1|(.+)|(%x%x%x%x)%s*$');
    if body == nil then return nil, 'not a bludex set share (no BDXSET1 line)'; end
    if shareCrc(body) ~= sum:lower() then
        return nil, 'the text is damaged - copy and paste the WHOLE line';
    end
    local kind, nameEnc, payload = body:match('^(%a+)|(.-)|(.*)$');
    if kind == nil then return nil, 'the share line is malformed'; end
    local name = shareDecName(nameEnc);
    if name == '' then name = 'Imported'; end
    if kind == 'flat' then
        local set = M.new(name, 'flat');
        set.ids = shareDecIds(payload);
        return set;
    end
    if kind == 'levels' then
        local set = M.new(name, 'levels');
        local first = true;
        for tok in (payload .. '~'):gmatch('(.-)~') do
            if first then
                set.ids = shareDecIds(tok);
                first = false;
            else
                local rule = tok:match('^rule=(%a+)$');
                local lvl, csv = tok:match('^(%d+)=(.*)$');
                if rule ~= nil and M.RULE_KEYS[rule] then
                    set.rule = rule;
                elseif lvl ~= nil then
                    set.builds[#set.builds + 1] = {
                        level = tonumber(lvl), ids = shareDecIds(csv),
                    };
                end
            end
        end
        M.normalizeGroup(set);
        return set;
    end
    if kind == 'timeline' then
        local bf, chains = payload:match('^(%d+)~(.*)$');
        if bf == nil then return nil, 'the timeline payload is malformed'; end
        local set = M.new(name, 'timeline');
        local n = tonumber(bf) or 75;
        if n < 1 or n > 75 then n = 75; end
        set.builtFor = n;
        set.chains = shareDecChains(chains);
        M.syncLegacyIds(set, nil);
        return set;
    end
    return nil, ('unknown set kind "%s" - a newer bludex made this?'):format(kind);
end

-- ---------------------------------------------------------------------------
-- flat readers -- every one takes a v2 set (reads its ids mirror = the
-- level-75 resolution) OR a plain 20-id array (a resolveAtLevel result),
-- so level-aware callers pass the resolution for the level they preview
-- ---------------------------------------------------------------------------

local function flatIds(setOrIds)
    return setOrIds.ids or setOrIds;
end

function M.count(set)
    -- spells assigned anywhere in the set (all chains, empty markers not
    -- counted); a flat array counts its nonzero slots
    if set.chains ~= nil then
        local n = 0;
        for slot = 1, 20 do
            for _, e in ipairs(set.chains[slot]) do
                if e.id ~= 0 then n = n + 1; end
            end
        end
        return n;
    end
    local ids = flatIds(set);
    local n = 0;
    for i = 1, 20 do if (ids[i] or 0) ~= 0 then n = n + 1; end end
    return n;
end

-- Membership for the codex green tint: assigned ANYWHERE in the timeline,
-- active at the current level or not (the assignment is what the player
-- needs to see). Returns the slot index or nil.
function M.contains(set, id)
    if set.chains ~= nil then
        for slot = 1, 20 do
            for _, e in ipairs(set.chains[slot]) do
                if e.id == id then return slot; end
            end
        end
        return nil;
    end
    local ids = flatIds(set);
    for i = 1, 20 do if ids[i] == id then return i; end end
    return nil;
end

function M.freeSlot(set)
    if set.chains ~= nil then
        for slot = 1, 20 do
            if #set.chains[slot] == 0 then return slot; end
        end
        return nil;
    end
    -- id-array path: a levels draft only owns its band's slots (slotMax);
    -- a flat set (level nil) keeps all 20
    local ids = flatIds(set);
    for i = 1, M.slotMax(set) do if (ids[i] or 0) == 0 then return i; end end
    return nil;
end

function M.usedPoints(setOrIds, book)
    local ids = flatIds(setOrIds);
    local n = 0;
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.setPoints then n = n + s.setPoints; end
    end
    return n;
end

function M.usedMP(setOrIds, book)
    local ids = flatIds(setOrIds);
    local n = 0;
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.mpCost then n = n + s.mpCost; end
    end
    return n;
end

-- Can this spell go into the set at all? Returns ok, reason. Dispatches on
-- kind:
--   timeline    the convenience add -- a NEW chain in the lowest free slot
--               (floors ascend with the index, so the first free slot is
--               also the earliest-activating home it can have); deliberate
--               stacking onto an existing chain is addEntry with an
--               explicit slot. Reasons match canAddEntry + whole-set gates.
--   flat/draft  the id-array add. A LEVELS DRAFT adds its band's three
--               ceilings over a flat set (set.level): the slot count, the
--               budget the caller passes for that rung, and the highest
--               spell level its band can cast (a Lv.41 plan reaches 50, so
--               a Lv.62 spell has no business in it).
function M.canAdd(set, id, book, budgetMax)
    local s = book.spells[id];
    if s == nil then return false, 'unknown spell'; end
    if M.contains(set, id) then return false, 'already in set'; end
    if M.kindOf(set) == 'timeline' and set.chains ~= nil then
        -- a slotlist assigns PER SLOT (Henrik 2026-08-10, from the field:
        -- the convenience add put spells in slots nobody chose) -- the
        -- codex/traits rows refuse by name and point at the Sets tab
        return false, 'a Slotlist assigns per slot - mark a slot in the Sets tab';
    end
    if not s.castable then return false, 'not castable at 75'; end
    if s.unbridled then return false, 'Unbridled spells cannot be set'; end
    if not book.learned(id) then return false, 'not learned'; end
    if s.setPoints == nil then return false, 'set cost unknown'; end
    local top = M.bandTop(set.level);
    if s.level ~= nil and s.level > top then
        return false, ('needs Lv.%d - this set stops at %d'):format(s.level, top);
    end
    if M.freeSlot(set) == nil then
        local n = M.slotMax(set);
        if n < 20 then return false, ('no free slot (Lv.%d has %d)'):format(set.level, n); end
        return false, 'no free slot';
    end
    if budgetMax and budgetMax > 0
        and M.usedPoints(set, book) + s.setPoints > budgetMax then
        return false, 'over the point budget';
    end
    return true;
end

function M.add(set, id, book, budgetMax)
    local ok, reason = M.canAdd(set, id, book, budgetMax);
    if not ok then return false, reason; end
    set.ids[M.freeSlot(set)] = id;
    M.sortFlat(set, book);             -- level order, always (see sortFlat)
    return true;
end

-- Remove a spell wherever it is assigned (every entry of it, all chains).
-- The extension guard cannot trip: with every placement of the spell gone,
-- no stretch can collide with one. Legacy flat arrays keep the old zero-out.
function M.removeId(set, id)
    if set.chains ~= nil then
        for slot = 1, 20 do
            local chain = set.chains[slot];
            local i = 1;
            while chain[i] ~= nil do
                if chain[i].id == id then table.remove(chain, i);
                else i = i + 1; end
            end
            normalizeChain(chain);
        end
        -- a removal can EXPOSE a predecessor at 75, so the mirror must be
        -- re-derived, not just zeroed (resolveAtLevel needs no book when
        -- chains exist)
        M.syncLegacyIds(set, nil);
        return;
    end
    local i = M.contains(set, id);
    if i then
        set.ids[i] = 0;
        M.compactFlat(set);            -- no gap in the level-ordered list
    end
end

function M.removeSlot(set, i)
    if set.chains ~= nil then
        if i >= 1 and i <= 20 then set.chains[i] = {}; set.ids[i] = 0; end
        return;
    end
    if i >= 1 and i <= 20 then
        set.ids[i] = 0;
        M.compactFlat(set);
    end
end

-- The APPLY layout (field 2026-08-04: the game's own set list should read
-- in level order): the given LEARNED spells sorted ascending by spell level
-- (ties by id) into slots 1..n, zeros after. This is exactly what applyDiff
-- sends and what the Apply-dirty compare measures -- low spells sit in the
-- low slots a level-down spares. Takes a flat 20-id array (for a timeline
-- set: resolveAtLevel first).
function M.sortedLayout(ids, book)
    local pick = {};
    for i = 1, 20 do
        local id = ids[i] or 0;
        if id ~= 0 and book.spells[id] ~= nil and book.learned(id) then
            pick[#pick + 1] = id;
        end
    end
    table.sort(pick, byLevel(book));
    local T = {};
    for i = 1, 20 do T[i] = pick[i] or 0; end
    return T;
end

-- WHAT A LEVEL WILL REFUSE of a plan (Henrik 2026-08-10, sixth round). Two
-- ways a spell bounces off the game: it is over the level's own ceiling, or
-- it landed past the slots that level has. Measured against sortedLayout,
-- which is what an apply actually sends -- low spells first, so the refusals
-- are always the tail.
--
-- Returns ids{}, need -- `need` is the level at which ALL of them would fit
-- (the highest bar among them), nil when nothing is refused. That is the
-- level worth waiting for, and the one a sync-end check compares against.
function M.refusedAtLevel(ids, level, book)
    local layout = M.sortedLayout(ids, book);
    local slots = M.slotsAtLevel(level);
    local out, need = {}, nil;
    for i = 1, 20 do
        local id = layout[i] or 0;
        if id ~= 0 then
            local s = book.spells[id];
            local bar = nil;
            -- the level ceiling first: a spell too high for here needs its
            -- OWN level, which is a higher bar than its slot's floor
            if s ~= nil and s.level ~= nil and s.level > level then
                bar = s.level;
            elseif i > slots then
                bar = M.bracketFloor(i);
            end
            if bar ~= nil then
                out[#out + 1] = id;
                if need == nil or bar > need then need = bar; end
            end
        end
    end
    return out, need;
end

-- THE STORED ARRAY IN THE SAME ORDER (Henrik 2026-08-10, fifth round:
-- "always sort the spells in level order... so people know what spells will
-- be gotten in what order if you level sync down"). sortedLayout has always
-- sorted a flat set on the way OUT; the editor showed insertion order, so
-- the list you read was not the list the game got. A flat build has no
-- per-slot authorship to protect -- only a SLOTLIST does -- so the array
-- itself is kept sorted and the two finally agree.
--
-- Low levels sit in the low slots, and slots close from the top down as you
-- sync, so the list reads bottom-up as the drop order.
--
-- Unlike sortedLayout this NEVER DROPS: an unlearned spell keeps its place,
-- and an id the data does not know sorts last instead of vanishing (Read
-- current has to stay an honest mirror of the client). Returns true when
-- something actually moved.
function M.sortFlat(set, book)
    if set == nil or set.chains ~= nil or set.ids == nil then return false; end
    local pick = {};
    for i = 1, 20 do
        local id = set.ids[i] or 0;
        if id ~= 0 then pick[#pick + 1] = id; end
    end
    table.sort(pick, byLevel(book));
    local moved = false;
    for i = 1, 20 do
        local want = pick[i] or 0;
        if (set.ids[i] or 0) ~= want then moved = true; end
        set.ids[i] = want;
    end
    return moved;
end

-- Close the holes, order untouched -- what a REMOVAL needs. Dropping one
-- entry from a sorted list leaves it sorted, so this needs no book and
-- cannot reorder a set behind the player's back.
function M.compactFlat(set)
    if set == nil or set.chains ~= nil or set.ids == nil then return false; end
    local pick = {};
    for i = 1, 20 do
        local id = set.ids[i] or 0;
        if id ~= 0 then pick[#pick + 1] = id; end
    end
    local moved = false;
    for i = 1, 20 do
        local want = pick[i] or 0;
        if (set.ids[i] or 0) ~= want then moved = true; end
        set.ids[i] = want;
    end
    return moved;
end

-- THE LAYOUT AN APPLY SENDS, per kind (field 2026-08-10, Henrik's slotlist
-- round). Flat and levels builds keep the sorted-placement law -- low
-- spells sit in the low slots a level-down spares. A TIMELINE set's slots
-- are AUTHORSHIP: the Assign pane put Foot Kick in slot 11 on purpose, and
-- the sorted re-shuffle was both moving it home to slot 1 AND making two
-- levels' plans compare equal whenever they differed only by position --
-- so after a level change, Apply refused with "already up to date".
-- Positions hold; unlearned spells zero out IN PLACE, never compacted.
function M.applyLayout(set, ids, book)
    if M.kindOf(set) ~= 'timeline' then return M.sortedLayout(ids, book); end
    local T = {};
    for i = 1, 20 do
        local id = ids[i] or 0;
        if id ~= 0 and book.spells[id] ~= nil and book.learned(id) then
            T[i] = id;
        else
            T[i] = 0;
        end
    end
    return T;
end

-- The server's set-slot count for a BLU level (blueutils GetTotalSlots):
-- 6 slots through level 10, +2 every 10 levels after, capped at 20.
function M.slotsAtLevel(level)
    if level == nil or level < 1 then return 0; end
    local n = math.floor((level - 1) / 10) * 2 + 6;
    if n < 6 then n = 6; end
    if n > 20 then n = 20; end
    return n;
end

-- The server's BASE set-point budget for a BLU level, verbatim from
-- blueutils.cpp GetTotalBlueMagicPoints:
--     clamp(((level - 1) / 10) * 5 + 10, 0, 55)
-- 10 through Lv10, +5 every ten levels: 10/15/20/25/30/35/40/45 at the
-- bracket tops, 45 at the level-75 cap.
--
-- This is the BASE ONLY. Everything above it is character-specific and
-- cannot be derived: Assimilation merits (server-side, level >= 75 ONLY --
-- merits do not apply under a sync) and, on CatsEyeXI, a custom bonus for
-- spells learned that applies at EVERY level. Those are measured live --
-- see blu.learnedBonus / blu.meritPts / blu.expectedCap.
function M.baseCapAtLevel(level)
    if level == nil or level < 1 then return 0; end
    local n = math.floor((level - 1) / 10) * 5 + 10;
    if n < 0 then n = 0; end
    if n > 55 then n = 55; end
    return n;
end

-- ---------------------------------------------------------------------------
-- the band sweep -- the whole-curve point validation (plan 2.6):
-- at every level where anything changes (bracket steps, entry activations,
-- builtFor, 75), the resolved set's points against the budget for that
-- level. Returns merged violation bands:
--     { { lo, hi, over, provisional, enforced }, ... }
-- budgetFn(level) -> cap or nil; nil falls back to the BASE rule and marks
-- the band PROVISIONAL -- the base is a LOWER bound of the true budget, so
-- a provisional band may not be a real violation and must never hard-block.
-- enforced = the band lies at/above the set's builtFor level (bands are
-- never merged across that boundary, so the flag is band-wide).
-- ---------------------------------------------------------------------------
function M.bandViolations(set, book, budgetFn)
    -- the sweep is timeline math (builtFor, chains, the breakpoint walk);
    -- the other kinds carry their own meters and are never hard-blocked
    if M.kindOf(set) ~= 'timeline' then return {}; end
    local bf = set.builtFor or 75;
    local bpset = { [1] = true, [75] = true };
    for _, t in ipairs({ 11, 21, 31, 41, 51, 61, 71 }) do bpset[t] = true; end
    if bf >= 1 and bf <= 75 then bpset[bf] = true; end
    if set.chains ~= nil then
        for slot = 1, 20 do
            local floor = M.bracketFloor(slot);
            for _, e in ipairs(set.chains[slot]) do
                local lo = math.max(e.from, floor);
                if lo >= 1 and lo <= 75 then bpset[lo] = true; end
            end
        end
    end
    local bps = {};
    for l in pairs(bpset) do bps[#bps + 1] = l; end
    table.sort(bps);

    local out = {};
    for i, L in ipairs(bps) do
        local hi = (bps[i + 1] ~= nil) and (bps[i + 1] - 1) or 75;
        if hi >= L then
            local pts = M.usedPoints(M.resolveAtLevel(set, L, book), book);
            local cap = budgetFn and budgetFn(L) or nil;
            local provisional = false;
            if cap == nil then cap = M.baseCapAtLevel(L); provisional = true; end
            local over = pts - cap;
            if over > 0 then
                local last = out[#out];
                if last ~= nil and last.hi + 1 == L
                    and last.provisional == provisional
                    and (last.lo >= bf) == (L >= bf) then
                    last.hi = hi;
                    if over > last.over then last.over = over; end
                    if over < last.overMin then last.overMin = over; end
                else
                    out[#out + 1] = {
                        lo = L, hi = hi, over = over, overMin = over,
                        provisional = provisional, enforced = (L >= bf),
                    };
                end
            end
        end
    end
    return out;
end

-- The bands that BLOCK Apply: enforced (at/above builtFor) and not
-- provisional (the budget for the level is actually known).
function M.enforcedViolations(set, book, budgetFn)
    local out = {};
    for _, b in ipairs(M.bandViolations(set, book, budgetFn)) do
        if b.enforced and not b.provisional then out[#out + 1] = b; end
    end
    return out;
end

-- One violation band as the message the plan specifies verbatim. A merged
-- band's overage can vary inside it (the budget steps per bracket); when it
-- does, the message says 'up to' rather than overstating the whole range.
function M.bandText(b)
    local range = (b.lo == b.hi) and ('At level %d'):format(b.lo)
        or ('Between level %d and %d'):format(b.lo, b.hi);
    local amount = tostring(b.over);
    if b.overMin ~= nil and b.overMin ~= b.over then amount = 'up to ' .. amount; end
    local s = ('%s, you are %s point(s) above threshold'):format(range, amount);
    if b.provisional then s = s .. ' (assuming +0 learned bonus)'; end
    return s;
end

-- ---------------------------------------------------------------------------
-- display math (unchanged)
-- ---------------------------------------------------------------------------

-- 'DUAL_WIELD' -> 'Dual Wield', 'MND' stays 'MND' (<=4 chars = stat acronym)
function M.prettyStat(s)
    if #s <= 4 and not s:find('_') then return s; end
    return (s:lower():gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b)
        return a:upper() .. b;
    end));
end

-- Aggregate always-on stat bonuses from the set's spells:
-- returns sorted array of { stat = 'STR', value = 5 }.
-- Takes a set (its 75 mirror) or a flat resolveAtLevel array.
function M.stats(setOrIds, book)
    local ids = flatIds(setOrIds);
    local sum, order = {}, {};
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.mods then
            for _, m in ipairs(s.mods) do
                if sum[m.stat] == nil then
                    sum[m.stat] = 0;
                    order[#order + 1] = m.stat;
                end
                sum[m.stat] = sum[m.stat] + m.value;
            end
        end
    end
    local out = {};
    for _, stat in ipairs(order) do
        if sum[stat] ~= 0 then out[#out + 1] = { stat = stat, value = sum[stat] }; end
    end
    return out;
end

-- Trait evaluation for the set. Returns sorted array of:
--   { cat, name, weight,           -- total weight the set feeds this category
--     tier,                        -- the active tier table or nil (below tier 1)
--     tierText,                    -- 'Dual Wield +10' style, or nil
--     nextPoints, nextText }       -- what the next tier needs, nil at cap
-- Takes a set (its 75 mirror) or a flat resolveAtLevel array.
-- THE TIERS BY LEVEL (Henrik 2026-08-10: "a summary what tiers are active
-- for what levels according to the slotlist"): sweep 1..75, resolve the
-- set at each level, evaluate the ladders, and fold each category's tier
-- curve into spans -- { { cat, name, spans = { { tier, text, lo, hi } } } },
-- name-sorted. A gap in activity splits a span; the whole answer is what
-- the Traits tab lists under a slotlist.
function M.tierTimeline(set, book)
    local out, byCat = {}, {};
    for L = 1, 75 do
        for _, ev in ipairs(M.traitEval(M.resolveAtLevel(set, L, book), book)) do
            if ev.tier ~= nil then
                local info = book.traits.categories[ev.cat];
                local tn = 0;
                if info then
                    for ti, t in ipairs(info.tiers) do
                        if t == ev.tier then tn = ti; break; end
                    end
                end
                local rec = byCat[ev.cat];
                if rec == nil then
                    rec = { cat = ev.cat, name = ev.name, spans = {} };
                    byCat[ev.cat] = rec;
                    out[#out + 1] = rec;
                end
                local last = rec.spans[#rec.spans];
                if last ~= nil and last.hi == L - 1 and last.tier == tn then
                    last.hi = L;
                else
                    rec.spans[#rec.spans + 1] = { tier = tn, text = ev.tierText, lo = L, hi = L };
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name; end);
    return out;
end

function M.traitEval(setOrIds, book)
    local ids = flatIds(setOrIds);
    local weights, order = {}, {};
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.trait then
            local c = s.trait.category;
            if weights[c] == nil then weights[c] = 0; order[#order + 1] = c; end
            weights[c] = weights[c] + (s.trait.weight or 0);
        end
    end
    local out = {};
    for _, cat in ipairs(order) do
        local info = book.traits.categories[cat];
        local total = weights[cat];
        local active, nextTier = nil, nil;
        if info then
            for _, tier in ipairs(info.tiers) do
                if total >= tier.points then
                    active = tier;
                elseif nextTier == nil then
                    nextTier = tier;
                end
            end
        end
        local function tierText(tier)
            if tier == nil then return nil; end
            local parts = {};
            for _, m in ipairs(tier.mods) do
                parts[#parts + 1] = ('%s %+d'):format(M.prettyStat(m.stat), m.value);
            end
            return table.concat(parts, ', ');
        end
        out[#out + 1] = {
            cat = cat,
            name = (info and info.name) or ('Trait ' .. cat),
            weight = total,
            tier = active,
            tierText = tierText(active),
            nextPoints = nextTier and nextTier.points or nil,
            nextText = tierText(nextTier),
        };
    end
    table.sort(out, function(a, b) return a.name < b.name; end);
    return out;
end

return M;
