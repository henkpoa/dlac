--[[
    dlac/ownedcache.lua -- live owned-quantity cache (availability colouring / filters).

    Split out of gearui.lua: LuaJIT caps a chunk at 200 local variables, and gearui's
    main chunk was already at it -- cohesive helpers get their own module from now on.

    gearimport.ownedSplit() -> { avail = {id->n}, total = {id->n}, where = {id->{cid->n}} }
    in ONE bag pass. Cached; gearui drops it on Scan / Reload (resetCache) and on a
    ~4s d3d_present heartbeat, so container moves -- Safe -> Wardrobe and back --
    change availability live. Safe fallback everywhere: if the live scan returns
    nothing (inventory manager unavailable / char select), don't hide anything.
    No injected deps: gearimport is require'd lazily, exactly as gearui did.
]]--

local M = {};

local _ownedCounts = nil;   -- the cached split table

function M.counts()   -- AVAIL map (equip-correct: pairing, DW, automations)
    if _ownedCounts ~= nil then return _ownedCounts.avail; end
    local split = { avail = {}, total = {} };
    pcall(function()
        local ok, mod = pcall(require, "dlac\\gearimport");
        if ok and mod ~= nil and type(mod.ownedSplit) == 'function' then
            local s = mod.ownedSplit();
            if type(s) == 'table' and type(s.avail) == 'table' then split = s; end
        end
    end);
    _ownedCounts = split;
    return _ownedCounts.avail;
end

function M.totals()   -- owned-ANYWHERE map (visibility)
    M.counts();
    return _ownedCounts.total;
end

-- WHERE the item lives: the split's per-container map for an id ({cid -> n}, or nil
-- when unknown). Populates the cache first, so callers need no priming counts() call.
function M.whereOf(id)
    M.counts();                             -- ensure the split cache is populated
    return (_ownedCounts and _ownedCounts.where and _ownedCounts.where[id]) or nil;
end

-- Drop the cached split (Scan / Reload / the ~4s availability heartbeat).
function M.resetCache() _ownedCounts = nil; end

-- Is the record actually in your bags (owned ANYWHERE)? gear.lua is a curated DB
-- and can list items you no longer own (e.g. a base "Garrison Sallet" when you
-- only have the +1). Availability is colour; ownership gates visibility.
function M.haveInBags(rec)
    if rec == nil or rec.Id == nil then return true; end
    local oc = M.totals();   -- owned anywhere counts as owned;
    if type(oc) ~= 'table' or next(oc) == nil then return true; end   -- availability is colour
    return (oc[rec.Id] or 0) >= 1;
end

-- Owned somewhere but with NO copy in Inventory/Wardrobes: LAC can't equip it until
-- it moves. Rows render these names red; the tooltip says where things stand.
function M.isStored(rec)
    if rec == nil or rec.Id == nil then return false; end
    local tot = M.totals();
    if type(tot) ~= 'table' or (tot[rec.Id] or 0) < 1 then return false; end
    local av = M.counts();
    return type(av) == 'table' and (av[rec.Id] or 0) == 0;
end

return M;
