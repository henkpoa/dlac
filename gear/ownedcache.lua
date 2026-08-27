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

-- The per-ROLL tallies for an augment-pinned record: { total, avail, where } for
-- exactly the copies whose private-augment signature matches rec.AugKey, or nil
-- when the record carries no pin / the split has no per-roll map (an old test
-- override, the decoder missing) -- callers then fall back to the id answer, so
-- nothing is ever hidden on a shrug. AugKey == '' means the UNAUGMENTED copy:
-- whatever the id owns beyond its augmented rolls.
local function augEntry(rec)
    if rec == nil or rec.Id == nil or type(rec.AugKey) ~= 'string' then return nil; end
    M.counts();                             -- populate the split cache
    local aug = (_ownedCounts ~= nil) and _ownedCounts.aug or nil;
    if type(aug) ~= 'table' then return nil; end
    local per = aug[rec.Id];
    if rec.AugKey == '' then
        local t  = (_ownedCounts.total ~= nil) and (_ownedCounts.total[rec.Id] or 0) or 0;
        local av = (_ownedCounts.avail ~= nil) and (_ownedCounts.avail[rec.Id] or 0) or 0;
        if type(per) == 'table' then
            for _, e in pairs(per) do
                t  = t  - (e.total or 0);
                av = av - (e.avail or 0);
            end
        end
        return { total = math.max(0, t), avail = math.max(0, av) };
    end
    if type(per) ~= 'table' then return { total = 0, avail = 0 }; end
    return per[rec.AugKey] or { total = 0, avail = 0 };
end

-- Owned copies of exactly rec's roll (total, anywhere), or nil when rec is not
-- augment-pinned / the per-roll map is unavailable. gearfmt.qtyTag's dep.
function M.augCounts(rec)
    local e = augEntry(rec);
    return (e ~= nil) and e.total or nil;
end

-- Is the record actually in your bags (owned ANYWHERE)? gear.lua is a curated DB
-- and can list items you no longer own (e.g. a base "Garrison Sallet" when you
-- only have the +1). Availability is colour; ownership gates visibility.
-- An augment-pinned record asks about ITS roll: sell the Acc+3 mittens and that
-- row goes, the other roll's row stays.
function M.haveInBags(rec)
    if rec == nil or rec.Id == nil then return true; end
    local oc = M.totals();   -- owned anywhere counts as owned;
    if type(oc) ~= 'table' or next(oc) == nil then return true; end   -- availability is colour
    local ae = augEntry(rec);
    if ae ~= nil then return ae.total >= 1; end
    return (oc[rec.Id] or 0) >= 1;
end

-- Owned somewhere but with NO copy in Inventory/Wardrobes: LAC can't equip it until
-- it moves. Rows render these names red; the tooltip says where things stand.
function M.isStored(rec)
    if rec == nil or rec.Id == nil then return false; end
    local tot = M.totals();
    if type(tot) ~= 'table' or (tot[rec.Id] or 0) < 1 then return false; end
    local ae = augEntry(rec);
    if ae ~= nil then return ae.total >= 1 and ae.avail == 0; end
    local av = M.counts();
    return type(av) == 'table' and (av[rec.Id] or 0) == 0;
end

-- Owned with zero equippable copies AND every unavailable copy sitting in the
-- GEAR VAULT (the AscensionXI pack's pseudo-container, gearimport.VAULT_CID) --
-- a DIFFERENT fact from 'stored', by Henrik's field ruling (2026-08-26): in a
-- city one layout add puts it straight onto your shelf ("!vault add ... and it
-- equipped immediately"), where a Mog Safe piece always needs the bag trip.
-- Mixed homes (a copy in the Safe AND one in the vault) stay 'stored': the
-- nearest copy defines the road back. Aug-pinned records answer at id level
-- (the slice-1 fold carries no per-roll vault data), which can only ever err
-- toward 'stored' -- the duller claim.
function M.isVaulted(rec)
    if not M.isStored(rec) then return false; end
    local vcid = 99;
    pcall(function() vcid = require("dlac\\gear\\gearimport").VAULT_CID or vcid; end);
    local w = M.whereOf(rec and rec.Id);
    if w == nil then return false; end
    local vaultN = 0;
    for cid, n in pairs(w) do
        if cid ~= vcid then return false; end
        vaultN = vaultN + n;
    end
    return vaultN > 0;
end

-- THE availability verdict (ADR 0005's two bag facts + the caller's eligibility
-- fact, combined ONCE): 'vaulted' beats 'stored' beats 'locked' beats 'ok'.
-- `usable` is the caller's own job/level eligibility for its surface (nil =
-- not asked). Panels map states to their own palette -- the STATE is the
-- shared meaning, the colour stays theirs. Tests AV* pin the precedence.
function M.verdict(rec, usable)
    if M.isVaulted(rec) then return 'vaulted'; end
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
    local ae = augEntry(rec);   -- a pinned record names ITS roll's bags only
    if ae ~= nil and type(ae.where) == 'table' then w = ae.where; end
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
