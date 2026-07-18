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

-- Test seam (the _override idiom): headless suites inject a split table in
-- place of the live bag scan. nil in production.
M._splitOverride = nil;

function M.counts()   -- AVAIL map (equip-correct: pairing, DW, automations)
    if M._splitOverride ~= nil then _ownedCounts = M._splitOverride; end
    if _ownedCounts ~= nil then return _ownedCounts.avail; end
    local split = { avail = {}, total = {} };
    pcall(function()
        local ok, mod = pcall(require, "dlac\\gear\\gearimport");
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

-- THE availability verdict (ADR 0005's two bag facts + the caller's eligibility
-- fact, combined ONCE): 'stored' beats 'locked' beats 'ok'. `usable` is the
-- caller's own job/level eligibility for its surface (nil = not asked). Panels
-- map states to their own palette -- the STATE is the shared meaning, the
-- colour stays theirs. Tests AV* pin the precedence.
function M.verdict(rec, usable)
    if M.isStored(rec) then return 'stored'; end
    if usable == false then return 'locked'; end
    return 'ok';
end

-- Human-readable holding containers for a record's owned copies, sorted --
-- 'Mog Safe, Wardrobe 2 x2' ('' when unknown). The one builder behind the
-- IN STORAGE / Held captions, so the phrasing sites stop re-aggregating bags.
function M.whereText(rec)
    if rec == nil or rec.Id == nil then return ''; end
    local w = M.whereOf(rec.Id);
    if w == nil then return ''; end
    local locs = '';
    pcall(function()
        local okm, mod = pcall(require, "dlac\\gear\\gearimport");
        if not okm or type(mod.containerName) ~= 'function' then return; end
        local parts = {};
        for cid, n in pairs(w) do
            parts[#parts + 1] = mod.containerName(cid) .. ((n > 1) and (' x' .. n) or '');
        end
        table.sort(parts);
        locs = table.concat(parts, ', ');
    end);
    return locs;
end

return M;
