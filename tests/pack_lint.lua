-- pack_lint.lua -- validate ONE server pack against the runtime contract
-- (docs/reference/server-pack-contract.md, ADR 0035).
--
--     lua tests/pack_lint.lua <packid>          (from the dlac repo root)
--
-- Not part of the CI suites: run it after regenerating a pack, before
-- committing it. It mounts the pack through the REAL seam and walks the
-- catalog through the REAL walker (gear/catalogindex.lua), so a pack that
-- passes here is a pack the addon can load.

local packid = (arg or {})[1];
if type(packid) ~= 'string' or packid == '' then
    print('usage: lua tests/pack_lint.lua <packid>');
    os.exit(2);
end

-- the smoke_ui searcher: require('dlac\\X') -> ./X.lua
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel == nil then return nil; end
    local chunk = loadfile((rel:gsub('\\', '/')) .. '.lua');
    if chunk == nil then return nil; end
    return chunk;
end);

local failures, count = {}, 0;
local function check(name, got, want)
    count = count + 1;
    if got ~= want then
        failures[#failures + 1] = string.format('%s: got %s, want %s', name, tostring(got), tostring(want));
    end
end

-- mount THE pack under test (the flag-file seam chooses it even when several ship)
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = packid }; end;
sp.init();
check('L0 the pack mounts', sp.active(), packid);
local man = sp.manifest();
check('L1 manifest is a table', type(man), 'table');
local counts = (type(man) == 'table' and type(man.counts) == 'table') and man.counts or {};

-- every declared file resolves and is a table
for _, fname in ipairs((man and man.files) or {}) do
    local t = sp.data(fname);
    check('L2 file resolves: ' .. fname, type(t), 'table');
end

-- the catalog through the ONE walker
local ci = require('dlac\\gear\\catalogindex');
check('L3 catalog available', ci.available(), true);
local list, byId, byName = ci.flat();
if counts.catalog ~= nil then
    check('L4 flat() count matches the manifest', #list == tonumber(counts.catalog), true);
end
print(('  catalog: %d flattened records (manifest says %s)'):format(#list, tostring(counts.catalog)));

-- the promoted-field contract on every record
local badField, badLevel = 0, 0;
local cap = sp.maxLevel();
for _, r in ipairs(list) do
    if type(r.Name) ~= 'string' or r.Name == '' or type(r.Id) ~= 'number'
       or type(r.Slot) ~= 'string' or type(r.Type) ~= 'string'
       or type(r.Stats) ~= 'table' or type(r.Jobs) ~= 'table' then
        badField = badField + 1;
    end
    if type(r.Level) ~= 'number' or r.Level < 0 then badLevel = badLevel + 1; end
end
check('L5 every record carries the promoted fields', badField, 0);
check('L6 every record carries a sane Level', badLevel, 0);

-- ids and names index
check('L7 byId finds a mid-catalog record', byId[list[math.floor(#list / 2)].Id] ~= nil, true);
check('L8 byName finds the same record', byName[string.lower(list[math.floor(#list / 2)].Name)] ~= nil
      or byName[list[math.floor(#list / 2)].Name] ~= nil, true);

-- retail anchors that hold on ANY 75-era LSB lineage
local function findName(nm)
    for _, r in ipairs(list) do if r.Name == nm then return r; end end
    return nil;
end
local pc = findName('Peacock Charm');
check('L9 Peacock Charm exists', pc ~= nil, true);
if pc ~= nil then
    check('L9a ...in the Neck slot', pc.Slot, 'Neck');
    check('L9b ...with its accuracy', (pc.Stats or {}).Accuracy, 10);
end
local kc = findName('Kaiser Sword');
check('L10 a Main-slot weapon nests under its category', kc == nil or kc.Category ~= nil, true);

-- zones: towns exist and Nashmau is one (the curated overlay)
local zones = sp.data('zones');
if zones ~= nil then
    local towns = 0;
    for _, z in pairs(zones) do if z.town == true then towns = towns + 1; end end
    check('L11 towns exist', towns > 20, true);
    check('L12 Nashmau overlay', (zones[53] or {}).town, true);
end

-- gear sets: contract shape (pieces/min/max/contiguous tiers)
local gs = sp.data('gearsets');
if gs ~= nil then
    local n, badShape = 0, 0;
    for _, s in pairs(gs) do
        n = n + 1;
        if type(s.pieces) ~= 'table' or type(s.min) ~= 'number'
           or type(s.max) ~= 'number' or type(s.tiers) ~= 'table' then
            badShape = badShape + 1;
        else
            for c = s.min, s.max do
                if type(s.tiers[c]) ~= 'table' then badShape = badShape + 1; break; end
            end
        end
    end
    check('L13 gear sets carry the tier contract', badShape, 0);
    if counts.gearsets ~= nil then
        check('L13a set count matches the manifest', n == tonumber(counts.gearsets), true);
    end
end

-- levelscaling / latentstats row shapes
local ls = sp.data('levelscaling');
if ls ~= nil then
    local bad = 0;
    for _, entries in pairs(ls) do
        for _, r in ipairs(entries) do
            if type(r.stat) ~= 'string' or type(r.add) ~= 'number'
               or (r.from == nil and r.below == nil) then bad = bad + 1; end
        end
    end
    check('L14 levelscaling rows carry stat/add/from|below', bad, 0);
end
local lat = sp.data('latentstats');
if lat ~= nil then
    local bad = 0;
    for _, entries in pairs(lat) do
        for _, r in ipairs(entries) do
            if type(r.stat) ~= 'string' or type(r.add) ~= 'number'
               or type(r.cond) ~= 'string' then bad = bad + 1; end
        end
    end
    check('L15 latentstats rows carry stat/add/cond', bad, 0);
end

-- pickers: list shape with Name + Jobs
for _, fname in ipairs({ 'spells', 'abilities' }) do
    local t = sp.data(fname);
    if t ~= nil then
        local bad = 0;
        for _, e in ipairs(t) do
            if type(e.Name) ~= 'string' or type(e.Jobs) ~= 'table' then bad = bad + 1; end
        end
        check('L16 ' .. fname .. ' rows carry Name+Jobs', bad, 0);
        if counts[fname] ~= nil then
            check('L16a ' .. fname .. ' count matches the manifest', #t == tonumber(counts[fname]), true);
        end
    end
end

if #failures == 0 then
    print(('OK -- pack "%s": %d checks passed'):format(packid, count));
    os.exit(0);
end
print(('FAIL -- pack "%s": %d of %d checks failed:'):format(packid, #failures, count));
for _, f in ipairs(failures) do print('  ' .. f); end
os.exit(1);
