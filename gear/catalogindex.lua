--[[
    dlac/gear/catalogindex.lua -- Catalog access, ONE walker.

    The Catalog (data\catalog.lua, ~5MB, generated -- never fetched at runtime,
    ADR 0001) had no access module: gearui, gearimport (twice) and gearexport
    each re-implemented the nested walk ("a table with .Id and .Name is an item;
    skip NameToObject; recurse the rest") and kept private indexes. The walk,
    the lazy load policy and the indexes live HERE now.

      available()   -> is the catalog loadable? (triggers the lazy load)
      rawById(id)   -> the RAW catalog record (shared, do not mutate)
      rawIndex()    -> { [id] = raw record } -- the whole map ({} without a
                       catalog, so guarded callers behave exactly as before)
      flat()        -> list, byId, byName of FLATTENED COPIES (browse/tooltip
                       records: Slot/Category/Key derived from position; the
                       shape gearui's flattenGear always built), cached once
      flatten(src)  -> the generic flattener over ANY gear-shaped table
                       (gear.lua and catalog.lua share the structure) -- kept
                       generic so the owned table flattens through the same code

    The equip-time ENGINE still never loads the catalog (by design: gear.lua
    stamps carry what it needs -- ADR 0006/0010); this module is addon-state.
    gearexport.catalogIndex keeps its injected pure form (tests pass fixture
    catalogs through it); its production caller can migrate later if it earns it.
    Pure at load (catalog required lazily under pcall) -- headless tests CI*.
]]--

local M = {};

local _cat, _tried = nil, false;
local function cat()
    if not _tried then
        _tried = true;
        local ok, c = pcall(require, 'dlac\\data\\catalog');
        if ok and type(c) == 'table' then _cat = c; end
    end
    return _cat;
end

function M.available() return cat() ~= nil; end

-- The one nested walk: an entry has .Id and .Name; NameToObject aliases the
-- same records and would double every item -- always skipped.
local _rawById = nil;
function M.rawIndex()
    if _rawById == nil then
        _rawById = {};
        local c = cat();
        if c ~= nil then
            local function walk(t)
                for k, v in pairs(t) do
                    if type(v) == 'table' then
                        if v.Id ~= nil and v.Name ~= nil then _rawById[v.Id] = v;
                        elseif k ~= 'NameToObject' then walk(v); end
                    end
                end
            end
            walk(c);
        end
    end
    return _rawById;
end

function M.rawById(id)
    if id == nil then return nil; end
    return M.rawIndex()[id];
end

-- Flatten any gear-shaped table (gear.lua OR catalog.lua -- identical structure)
-- into a sorted record list plus by-Id / by-Name indexes. Walked exactly the way
-- gear.lua's NameToObject builder walks (a table with a .Name is an entry; anything
-- else is a container). Records are fresh copies, so per-row memo fields never
-- mutate the source table.
function M.flatten(src)
    local list, byId, byName = {}, {}, {};
    local function add(slot, category, key, e)
        local rec = {
            Name = e.Name, Level = e.Level or 0, Id = e.Id, Jobs = e.Jobs,
            Slot = slot, Category = category, Type = e.Type, Stats = e.Stats,
            Key = key,                     -- gear.lua table key, for building a commit path
            OneHanded = e.OneHanded,       -- weapon 1H vs 2H (Sub-slot pairing rules)
            AmmoType = e.AmmoType,         -- what a Range weapon fires this ammo AS (Ammo-slot
                                           -- weapon-type filter, #17); absent = Trinket
            Count = e.Count,   -- scanned copy count (>= 2 = same-weapon dual-wield)
            Model = e.Model,   -- appearance model id (catalog) -- the lockstyle look
                               -- preview resolves through THESE records (catalogById /
                               -- enrichment), so dropping it here blanks the preview
        };
        list[#list + 1] = rec;
        if rec.Id ~= nil then byId[rec.Id] = rec; end
        if type(rec.Name) == 'string' then byName[string.lower(rec.Name)] = rec; end
    end
    local function walk(slot, container, category)
        for key, v in pairs(container) do
            if type(v) == 'table' then
                if v.Name ~= nil then
                    add(slot, category, key, v);
                else
                    walk(slot, v, (category == nil) and tostring(key) or category);
                end
            end
        end
    end
    if type(src) == 'table' then
        for slot, slotVars in pairs(src) do
            if slot ~= 'NameToObject' and type(slotVars) == 'table' then
                walk(slot, slotVars, nil);
            end
        end
    end
    table.sort(list, function(a, b)
        if a.Slot ~= b.Slot then return tostring(a.Slot) < tostring(b.Slot); end
        local ca, cb = a.Category or '', b.Category or '';
        if ca ~= cb then return ca < cb; end
        if a.Level ~= b.Level then return (a.Level or 0) < (b.Level or 0); end
        return tostring(a.Name) < tostring(b.Name);
    end);
    return list, byId, byName;
end

-- The catalog's flattened form, built once. Without a catalog: empty list and
-- indexes (never nil), so browse surfaces degrade to "nothing" not errors.
local _flat, _flatById, _flatByName = nil, nil, nil;
function M.flat()
    if _flat == nil then
        _flat, _flatById, _flatByName = M.flatten(cat() or {});
    end
    return _flat, _flatById, _flatByName;
end

return M;
