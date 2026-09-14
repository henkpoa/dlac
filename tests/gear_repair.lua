-- Run from the addon root: lua tests/gear_repair.lua
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
package.loaded['dlac\\gear'] = { NameToObject = {} };
ashita = { events = { register = function() end } };
local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local ci = require('dlac\\gear\\catalogindex');
local gi = require('dlac\\gear\\gearimport');
local _, catalog = ci.flat();
local template = assert(io.open('gear.lua', 'r'));
local base = template:read('*a'); template:close();
local body = [[
        RabbitCharm_1 = { -- keep this note
            Name = "Rabbit Charm +1",
            Id = 26549,
            Level = 127, -- old resource level
            Jobs = {"WAR", "THF"},
            AugKey = "roll-a",
            AugText = "DEX+1",
            Count = 2,
            Stats = { DEX = 99 }, -- preserve personal stats
        },
        FieldCap = {
            Name = "Field Cap",
            Id = 26550,
            Level = 127,
            Jobs = {"WAR"},
        },
        Unknown = {
            Name = "Unknown",
            Id = 65534,
            Level = 60,
            Jobs = {"WHM"},
        },
]];
local original = base:gsub('    Body = {\n', '    Body = {\n' .. body, 1);
local function run(text)
    local env = setmetatable({}, { __index = _G });
    local chunk, err;
    if setfenv then chunk, err = loadstring(text); if chunk then setfenv(chunk, env); end
    else chunk, err = load(text, 'gear repair fixture', 't', env); end
    return assert(assert(chunk, err)());
end
local fixed, report = gi.computeCatalogRepairs(original, catalog);
assert(fixed, report);
local g = run(fixed);
assert(g.Neck.RabbitCharm_1, 'Rabbit Charm +1 must move from Body to Neck');
assert(g.Neck.RabbitCharm_1.Level == 7 and g.Neck.RabbitCharm_1.Jobs[1] == 'All');
assert(g.Head.FieldCap and g.Head.FieldCap.Level == 1 and g.Head.FieldCap.Jobs[1] == 'All');
assert(rawget(g.Body, 'RabbitCharm_1') == nil and rawget(g.Body, 'FieldCap') == nil);
assert(g.Body.RabbitCharm_1 == g.Neck.RabbitCharm_1, 'old set reference must still resolve');
assert(g.Body.FieldCap == g.Head.FieldCap);
assert(g.NameToObject['Rabbit Charm +1'] == g.Neck.RabbitCharm_1);
assert(g.Neck.RabbitCharm_1.AugKey == 'roll-a' and g.Neck.RabbitCharm_1.Count == 2);
assert(g.Neck.RabbitCharm_1.Stats.DEX == 99);
assert(g.Body.Unknown.Level == 60 and g.Body.Unknown.Jobs[1] == 'WHM');
assert(fixed:find('-- keep this note', 1, true) and fixed:find('-- old resource level', 1, true));
assert(#ci.flatten(g) == 3, 'compatibility references must not duplicate owned gear');
assert(report.changed == 2);
local again, noChanges = gi.computeCatalogRepairs(fixed, catalog);
assert(again == fixed and noChanges.changed == 0, 'repeat repair must be a byte-identical no-op');
assert(gi.computeCatalogRepairs(original, {}) == original, 'no catalog means no guessing');

-- Legacy imports could write the exact same key twice. Identical blocks
-- must not prevent unrelated catalog corrections on every addon reload.
local duplicateBlock = [[            Spatha = {
                Name = "Spatha",
                Id = 16565,
                Level = 9,
            },
]];
local duplicated = original:gsub('    Main = {\n', function(header)
    return header .. '        Sword = {\n' .. duplicateBlock .. duplicateBlock .. '        },\n';
end, 1);
local deduped, duplicateReport = gi.computeCatalogRepairs(duplicated, catalog);
assert(deduped, duplicateReport);
assert(run(deduped).Main.Sword.Spatha.Id == 16565);
assert(run(deduped).Neck.RabbitCharm_1.Level == 7);
local _, copies = deduped:gsub('Spatha = {', '');
assert(copies == 1, 'identical shadowed entries should be removed');
assert(gi.computeCatalogRepairs(deduped, catalog) == deduped, 'reload repair should settle');
local conflicting = duplicated:gsub('Level = 9,', 'Level = 10, -- a distinct older copy', 1);
local conflictFixed, conflictReport = gi.computeCatalogRepairs(conflicting, catalog);
assert(conflictFixed, conflictReport);
assert(#conflictReport.skippedDuplicates == 1);
assert(conflictFixed:find('Level = 10, -- a distinct older copy', 1, true));
local _, conflictingCopies = conflictFixed:gsub('Spatha = {', '');
assert(conflictingCopies == 2 and run(conflictFixed).Main.Sword.Spatha.Level == 9,
    'differing duplicates keep Lua last-wins behavior');
assert(run(conflictFixed).Neck.RabbitCharm_1.Level == 7, 'unrelated repairs still proceed');

-- Existing names at the destination belong to the player. Keep both records,
-- choosing a free key for the moved one and redirecting its old reference.
local occupied = original:gsub('    Neck = {\n', [[    Neck = {
        RabbitCharm_1 = {
            Name = "Other charm",
            Id = 65532,
            Level = 30,
        },
]], 1);
local collision = run(assert(gi.computeCatalogRepairs(occupied, catalog)));
assert(collision.Neck.RabbitCharm_1.Id == 65532);
assert(collision.Neck.RabbitCharm_1_2.Id == 26549);
assert(collision.Body.RabbitCharm_1 == collision.Neck.RabbitCharm_1_2);
assert(#ci.flatten(collision) == 4);

local augmented = original:gsub('    Body = {\n', [[    Body = {
        OtherRoll = {
            Name = "Rabbit Charm +1",
            Id = 26549,
            Level = 127,
            AugKey = "roll-b",
        },
]], 1);
local rolls = run(assert(gi.computeCatalogRepairs(augmented, catalog)));
assert(rolls.Neck.OtherRoll.AugKey == 'roll-b' and rolls.Neck.RabbitCharm_1.AugKey == 'roll-a');
assert(#ci.flatten(rolls) == 4, 'augmented copies must not be merged');
local staged, stageReport = gi.spliceStaging(fixed, [[return {
    Body = {
        NewVest = {
            Name = "New Vest",
            Id = 65530,
            Level = 1,
        },
    },
};]]);
local stagedGear = run(staged);
assert(stageReport.inserted == 1 and stagedGear.Body.NewVest.Id == 65530);
assert(stagedGear.Body.RabbitCharm_1 == stagedGear.Neck.RabbitCharm_1,
    'future auto-imports must preserve compatibility references');

-- Missing slot containers are created, and a subsequent catalog relocation
-- retargets every earlier alias rather than leaving a chain to an empty slot.
local noNeck = original:gsub('    Neck = {\n    },\n', '', 1);
assert(run(assert(gi.computeCatalogRepairs(noNeck, catalog))).Neck.RabbitCharm_1);
local changedCatalog = {}; for id, c in pairs(catalog) do changedCatalog[id] = c; end
changedCatalog[26549] = { Slot = 'Head', Type = 'Head', Level = 8, Jobs = { 'THF' } };
local movedAgain = run(assert(gi.computeCatalogRepairs(fixed, changedCatalog)));
assert(movedAgain.Body.RabbitCharm_1 == movedAgain.Head.RabbitCharm_1);
assert(movedAgain.Neck.RabbitCharm_1 == movedAgain.Head.RabbitCharm_1);
assert(movedAgain.Head.RabbitCharm_1.Level == 8 and movedAgain.Head.RabbitCharm_1.Jobs[1] == 'THF');
local profiles = require('dlac\\profiles');
assert(profiles._wrapGear(movedAgain).Body.RabbitCharm_1 == movedAgain.Head.RabbitCharm_1,
    'the real saved-set loader must see compatibility references');

-- Metadata-only fixes also repair vaulted/offline ownership: no bag scan is
-- involved. Missing fields and multiline job lists remain valid Lua.
local fieldsOnly = fixed:gsub('Level = 7', 'Level = 127', 1)
    :gsub('Jobs = {"All"}', 'Jobs = {\n                "WAR",\n            }', 1);
assert(run(assert(gi.computeCatalogRepairs(fieldsOnly, catalog))).Neck.RabbitCharm_1.Level == 7);
local missing = original:gsub('            Level = 127, %-%- old resource level\n', '', 1)
    :gsub('            Jobs = {"WAR", "THF"},\n', '', 1);
local filled = run(assert(gi.computeCatalogRepairs(missing, catalog)));
assert(filled.Neck.RabbitCharm_1.Level == 7 and filled.Neck.RabbitCharm_1.Jobs[1] == 'All');
local malformed = 'gear = { this is not Lua';
assert(gi.computeCatalogRepairs(malformed, catalog) == nil);
local unusual = original:gsub('Level = 127, %-%- old resource level', 'Level = (100 + 27), -- expression', 1);
assert(gi.computeCatalogRepairs(unusual, catalog) == nil, 'refuse unrecognized field syntax without rewriting it');

-- Cataloguing a weapon in the wrong slot must create the category, retain
-- pair metadata and leave an old flat reference usable after reload.
local weaponCatalog = { [26549] = { Slot = 'Main', Category = 'GreatAxe', Type = 'GreatAxe',
    OneHanded = false, Level = 20, Jobs = { 'WAR' } } };
local weapon = run(assert(gi.computeCatalogRepairs(original, weaponCatalog)));
assert(weapon.Main.GreatAxe.RabbitCharm_1.Type == 'GreatAxe');
assert(weapon.Main.GreatAxe.RabbitCharm_1.OneHanded == false);
assert(weapon.Body.RabbitCharm_1 == weapon.Main.GreatAxe.RabbitCharm_1);

-- Exercise the actual backed-up file replacement, including refusal before
-- replacement and validation failure. Scratch filenames work on Lua 5.4 and
-- LuaJIT; no player paths are used.
local scratch = os.tmpname(); os.remove(scratch);
local gearFile = scratch .. 'gear.lua';
local sw = require('dlac\\lib\\safewrite');
local realBackup = sw.timestampBackup;
local realProfiles = package.loaded['dlac\\profiles'];
package.loaded['dlac\\profiles'] = { dataDir = function() return scratch; end,
    charRoot = function() return scratch; end };
local backups = {};
local function write(path, text)
    local f = assert(io.open(path, 'w')); assert(f:write(text)); f:close();
end
local function read(path)
    local f = assert(io.open(path, 'r')); local text = f:read('*a'); f:close(); return text;
end
sw.timestampBackup = function(_, _, text)
    local path = scratch .. 'backup' .. (#backups + 1) .. '.lua';
    write(path, text); backups[#backups + 1] = path; return path;
end;
local successfulBackup = sw.timestampBackup;
write(gearFile, original);
sw.timestampBackup = function() return nil, 'simulated backup failure'; end;
assert(gi.repairCatalog() == 0 and read(gearFile) == original);
sw.timestampBackup = successfulBackup;
local realReplace = sw.replaceLua;
sw.replaceLua = function() return nil, 'simulated write failure'; end;
assert(gi.repairCatalog() == 0 and read(gearFile) == original);
sw.replaceLua = realReplace;
local realCompute = gi.computeCatalogRepairs;
gi.computeCatalogRepairs = function() return 'gear = {}\nerror("bad trailer")\nreturn gear\n', { changed = 1 }; end;
assert(gi.repairCatalog() == 0 and read(gearFile) == original, 'validator must refuse before replacing the original');
gi.computeCatalogRepairs = realCompute;
assert(gi.repairCatalog() == 2);
assert(read(backups[#backups]) == original, 'backup must contain the untouched original');
local repairedDisk = read(gearFile);
local diskGear = run(repairedDisk);
assert(diskGear.Body.RabbitCharm_1 == diskGear.Neck.RabbitCharm_1 and diskGear.Neck.RabbitCharm_1.Level == 7);
local backupCount = #backups;
assert(gi.repairCatalog() == 0 and #backups == backupCount and read(gearFile) == repairedDisk);
sw.timestampBackup = realBackup;
package.loaded['dlac\\profiles'] = realProfiles;
os.remove(gearFile); os.remove(gearFile .. '.tmp');
for _, path in ipairs(backups) do os.remove(path); end

-- The startup hook repairs even with auto-import disabled, queues exactly one
-- addon reload, and prevents an import from racing the reload.
local realQueue = package.loaded['dlac\\lib\\cmdqueue'];
local queued, calls, refreshed = {}, {}, 0;
package.loaded['dlac\\lib\\cmdqueue'] = { issue = function(cmd) queued[#queued + 1] = cmd; end };
local sf = dofile('gear/syncflags.lua');
sf.configure({ dataDir = function() return scratch; end,
    callImport = function(kind) calls[#calls + 1] = kind; return 2; end,
    refreshGear = function() refreshed = refreshed + 1; end, ui = {} });
sf.flags.autosync = false;
sf.loadUiFlags(); sf.loadUiFlags(); sf.repairGear(); sf.doSync(); sf.tick();
assert(#calls == 1 and calls[1] == 'repairCatalog' and refreshed == 0);
assert(#queued == 1 and queued[1] == '/addon reload dlac');
local sfClean = dofile('gear/syncflags.lua');
sfClean.configure({ dataDir = function() return scratch; end,
    callImport = function(kind) assert(kind == 'repairCatalog'); return 0; end,
    refreshGear = function() refreshed = refreshed + 1; end, ui = {} });
sfClean.loadUiFlags();
assert(refreshed == 1 and #queued == 1, 'clean next load must not queue another reload');
local sfDirty = dofile('gear/syncflags.lua');
sfDirty.configure({ hasUnsavedGearEdits = function() return true; end,
    callImport = function() error('repair must not run while set edits are pending'); end });
assert(sfDirty.repairGear() == 0 and #queued == 1);
package.loaded['dlac\\lib\\cmdqueue'] = realQueue;
print('OK -- saved gear repairs and reference preservation');
