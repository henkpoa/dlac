--[[
    vanaheim/gearvault/derive.lua -- the DERIVED layout (GV1), pure.

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

-- One set's contribution: name -> slots-it-fills count.
local function walkSet(set, into)
    if type(set) ~= 'table' then return; end
    for _, entry in pairs(set) do
        if type(entry) == 'string' then
            if entry ~= '' and not isVirtual(entry) then
                into[entry] = (into[entry] or 0) + 1;
            end
        elseif type(entry) == 'table' then
            -- a Dynamic slot's candidate LIST: every rung is wanted, but the
            -- slot still only wears ONE of them -- each name counts this slot
            -- once, never more.
            local seen = {};
            for _, cand in ipairs(entry) do
                if type(cand) == 'string' and cand ~= '' and not isVirtual(cand) and not seen[cand] then
                    seen[cand] = true;
                    into[cand] = (into[cand] or 0) + 1;
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

-- An equip payload's contribution (trigger rules / cases): each slot string
-- counts its slot, same walk as a flattened set.
local function walkEquip(equip, global)
    if type(equip) ~= 'table' then return; end
    local counts = {};
    walkSet(equip, counts);
    foldMax(counts, global);
end

function M.derive(setsRoot, triggers, resolve)
    local wanted = {};   -- name -> max simultaneous count

    if type(setsRoot) == 'table' then
        for setName, set in pairs(setsRoot) do
            if setName == 'Dynamic' and type(set) == 'table' then
                for _, ds in pairs(set) do
                    local counts = {};
                    walkSet(ds, counts);
                    foldMax(counts, wanted);
                end
            elseif type(set) == 'table' then
                local counts = {};
                walkSet(set, counts);
                foldMax(counts, wanted);
            end
        end
    end

    if type(triggers) == 'table' then
        for _, rules in pairs(triggers) do
            if type(rules) == 'table' then
                for _, rule in ipairs(rules) do
                    if type(rule) == 'table' then
                        walkEquip(rule.equip, wanted);
                        if type(rule.cases) == 'table' then
                            for _, case in ipairs(rule.cases) do
                                if type(case) == 'table' then walkEquip(case.equip, wanted); end
                            end
                        end
                    end
                end
            end
        end
    end

    -- resolve names -> ids; merge same-id names (an item under two spellings
    -- resolves once, max count wins)
    local byId = {};
    local skippedAug, unresolved = 0, {};
    for name, count in pairs(wanted) do
        local r = (type(resolve) == 'function') and resolve(name) or nil;
        if r == nil or type(r.id) ~= 'number' then
            unresolved[#unresolved + 1] = name;
        elseif r.aug == true then
            skippedAug = skippedAug + 1;
        else
            local e = byId[r.id];
            if e == nil then
                byId[r.id] = { itemId = r.id, count = count };
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
