--[[
    ascensionxi/gearvault/derive.lua -- the DERIVED layout (GV1), pure.

    "Building sets IS authoring the shelf": a job's layout is a projection of
    what dlac already knows the job wants. This module computes that
    projection from plain tables -- no file, no wire, no Ashita -- so the
    suite drives every rule directly:

      * every set in the job's sets root contributes: a flattened set's slot
        strings, and EVERY candidate rung of a Dynamic set's slot lists
        (level-sync gear is the point of those lists);
      * every trigger's INLINE equip payload contributes (rule.equip and each
        case's equip); a rule's `set = 'Name'` reference contributes nothing
        of its own -- the set is already walked above;
      * `dlac:` virtual slot entries contribute NOTHING (the engine resolves
        those per cast from owned gear; shelving their whole candidate pools
        is a later slice, and the Ammo ladder is vault-ineligible anyway);
      * PAIRS: within one set, a name filling two slots (Ring1+Ring2) derives
        count 2; across sets the MAX wins -- the layout must dress the most
        demanding set;
      * augment-pinned records (AugKey ~= '') are SKIPPED and counted: their
        layout entry needs the exact 24-byte blob, which derivation cannot
        mint safely -- the vault pane's "+ Layout" button carries it instead
        (GV8's road). Unresolvable names are collected for the report.

    resolve(name) is injected: -> { id = <itemId>, aug = <boolean> } | nil.
    Output: { items = { { itemId, count } ... } (ordered by id),
              skippedAug = n, unresolved = { name ... },
              hash = a stable digest of items -- the reconcile engine's
              "did the derivation move" key }.
]]--

local M = {};

local function isVirtual(name)
    return type(name) == 'string' and name:sub(1, 5) == 'dlac:';
end

-- One gear REF -> a key + what is known about it, or nil. A ref is any of
-- the three shapes a set entry takes on disk (the committed shape is the
-- RECORD: `gear.Main.GreatAxe.Neckchopper` resolves to the gear.lua record
-- table at load -- the 2026-08-26 field round found the walker speaking
-- only strings, deriving nothing from every real set):
--   * a RECORD table (.Name, usually .Id, maybe .AugKey) -- id known here,
--     no resolution needed; AugKey ~= '' marks the augment-pinned copy;
--   * a plain string name (hand-written entries; trigger payloads);
--   * a WRAPPER { ref, dw = true, ... } -- the gear-rule shape, ref at [1].
local function refOf(v)
    if type(v) == 'string' then
        if v == '' or isVirtual(v) then return nil; end
        return { key = 'n:' .. v, name = v };
    end
    if type(v) == 'table' then
        if type(v.Name) == 'string' and v.Name ~= '' then
            if isVirtual(v.Name) then return nil; end
            local aug = (type(v.AugKey) == 'string' and v.AugKey ~= '');
            if type(v.Id) == 'number' then
                return { key = 'i:' .. v.Id .. (aug and ':a' or ''), id = v.Id, name = v.Name, aug = aug };
            end
            return { key = 'n:' .. v.Name, name = v.Name, aug = aug };
        end
        if v[1] ~= nil then return refOf(v[1]); end
    end
    return nil;
end

-- One set's contribution: ref key -> slots-it-fills count (+ the ref facts).
-- A slot's value is a DIRECT ref (string, or a record -- a table carrying
-- .Name) or a candidate LIST (any other table): the list check must come
-- from the .Name test, never from refOf's wrapper recursion, or a
-- two-candidate list would derive only its first rung.
local function walkSet(set, into, facts)
    if type(set) ~= 'table' then return; end
    for _, entry in pairs(set) do
        if type(entry) == 'string' or (type(entry) == 'table' and type(entry.Name) == 'string') then
            local r = refOf(entry);
            if r ~= nil then
                facts[r.key] = facts[r.key] or r;
                into[r.key] = (into[r.key] or 0) + 1;
            end
        elseif type(entry) == 'table' then
            -- a Dynamic slot's candidate LIST: every rung is wanted, but the
            -- slot still only wears ONE of them -- each ref counts this slot
            -- once, never more.
            local seen = {};
            for _, cand in ipairs(entry) do
                local r = refOf(cand);
                if r ~= nil and not seen[r.key] then
                    seen[r.key] = true;
                    facts[r.key] = facts[r.key] or r;
                    into[r.key] = (into[r.key] or 0) + 1;
                end
            end
        end
    end
end

-- Fold one name->count map into the global max map.
local function foldMax(counts, global)
    for name, n in pairs(counts) do
        if (global[name] or 0) < n then global[name] = n; end
    end
end

-- An equip payload's contribution (trigger rules / cases): each slot ref
-- counts its slot, same walk as a flattened set.
local function walkEquip(equip, global, facts)
    if type(equip) ~= 'table' then return; end
    local counts = {};
    walkSet(equip, counts, facts);
    foldMax(counts, global);
end

function M.derive(setsRoot, triggers, resolve)
    local wanted = {};   -- ref key -> max simultaneous count
    local facts  = {};   -- ref key -> what walkSet learned (id/name/aug)

    if type(setsRoot) == 'table' then
        for setName, set in pairs(setsRoot) do
            if setName == 'Dynamic' and type(set) == 'table' then
                for _, ds in pairs(set) do
                    local counts = {};
                    walkSet(ds, counts, facts);
                    foldMax(counts, wanted);
                end
            elseif type(set) == 'table' then
                local counts = {};
                walkSet(set, counts, facts);
                foldMax(counts, wanted);
            end
        end
    end

    if type(triggers) == 'table' then
        for _, rules in pairs(triggers) do
            if type(rules) == 'table' then
                for _, rule in ipairs(rules) do
                    if type(rule) == 'table' then
                        walkEquip(rule.equip, wanted, facts);
                        if type(rule.cases) == 'table' then
                            for _, case in ipairs(rule.cases) do
                                if type(case) == 'table' then walkEquip(case.equip, wanted, facts); end
                            end
                        end
                    end
                end
            end
        end
    end

    -- a record ref carries its id already; a name ref resolves here. Same-id
    -- refs merge (an item under two spellings / a record and a string), max
    -- count wins.
    local byId = {};
    local skippedAug, unresolved = 0, {};
    for key, count in pairs(wanted) do
        local f = facts[key] or {};
        local id, aug = f.id, (f.aug == true);
        if id == nil then
            local r = (type(resolve) == 'function') and resolve(f.name) or nil;
            if r ~= nil and type(r.id) == 'number' then
                id = r.id;
                aug = aug or (r.aug == true);
            end
        end
        if id == nil then
            unresolved[#unresolved + 1] = tostring(f.name or key);
        elseif aug then
            skippedAug = skippedAug + 1;
        else
            local e = byId[id];
            if e == nil then
                byId[id] = { itemId = id, count = count };
            elseif e.count < count then
                e.count = count;
            end
        end
    end

    local items = {};
    for _, e in pairs(byId) do items[#items + 1] = e; end
    table.sort(items, function(a, b) return a.itemId < b.itemId; end);
    table.sort(unresolved);

    local parts = {};
    for _, e in ipairs(items) do parts[#parts + 1] = e.itemId .. ':' .. e.count; end
    return {
        items      = items,
        skippedAug = skippedAug,
        unresolved = unresolved,
        hash       = table.concat(parts, ','),
    };
end

return M;
