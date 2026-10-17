-- lua tests/ascensionxi_fishing_ui.lua
-- The AscensionXI Fishing surfaces: the pure status lines and coverage, then
-- the panel, the target window and the hobby bar's Fishing tab under a
-- recording imgui stub, with the pack's own fishdb and a fake server status.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local failures, checks = 0, 0;
local function check(name, got, want)
    checks = checks + 1;
    if got ~= want then
        failures = failures + 1;
        print(string.format('FAIL %s: got %s, want %s', name, tostring(got), tostring(want)));
    end
end

-- A permissive imgui that records what is drawn and keeps the stacks honest.
local texts, tips, boxes, clickBox = {}, {}, {}, nil;
local depth = { col = 0, win = 0, id = 0, item = 0, pop = 0 };
local IM = setmetatable({}, { __index = function() return function() return false; end; end });
IM.TextUnformatted = function(t) texts[#texts + 1] = tostring(t); end;
IM.TextColored = function(_, t) texts[#texts + 1] = tostring(t); end;
IM.Text = function(t) texts[#texts + 1] = tostring(t); end;
IM.SetTooltip = function(t) tips[#tips + 1] = tostring(t); end;
IM.IsItemHovered = function() return true; end;
IM.CollapsingHeader = function() return true; end;
-- The fish search's rows: `pick` selects the row that starts with it.
local pick = nil;
IM.Selectable = function(l) return pick ~= nil and tostring(l):find(pick, 1, true) == 1; end;
IM.CalcTextSize = function(s) return #tostring(s) * 8; end;
IM.GetContentRegionAvail = function() return 760, 400; end;
IM.Checkbox = function(label, value)
    boxes[#boxes + 1] = { label = label, value = value[1] };
    if label == clickBox then value[1] = not value[1]; return true; end
    return false;
end;
IM.PushStyleColor = function() depth.col = depth.col + 1; end;
IM.PopStyleColor = function(n) depth.col = depth.col - (tonumber(n) or 1); end;
IM.Begin = function() depth.win = depth.win + 1; return true; end;
IM['End'] = function() depth.win = depth.win - 1; end;
IM.PushID = function() depth.id = depth.id + 1; end;
IM.PopID = function() depth.id = depth.id - 1; end;
IM.PushItemWidth = function() depth.item = depth.item + 1; end;
IM.PopItemWidth = function() depth.item = depth.item - 1; end;
IM.BeginPopup = function() depth.pop = depth.pop + 1; return true; end;
IM.EndPopup = function() depth.pop = depth.pop - 1; end;
ImGuiCol_Text = 0;
package.loaded['imgui'] = IM;
package.loaded['dlac\\ui\\craftbar'] = {};
package.loaded['dlac\\ui\\itemicons'] = { renderIcon = function() end };
package.loaded['dlac\\ui\\hobbybar'] = { isShown = function() return false; end, toggle = function() end };
local owned = {};
package.loaded['dlac\\gear\\ownedcache'] = {
    counts = function() return owned; end, totals = function() return owned; end,
    whereOf = function(id) return { [0] = owned[id] or 0 }; end,
};
local tmp = 'tests/_axi_fishing_ui_';
package.loaded['dlac\\lib\\statefile'] = { charDir = function() return tmp; end };

local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local snap = { points = 12345, skill = 23.4, slots = 2, rank = 3 };
local touched = 0;
local status = { touch = function() touched = touched + 1; end, value = function() return snap; end,
                 markStale = function() end };
sp.provide('fishing', { status = status, moveCatches = true });

local fw = require('dlac\\feature\\fishwatch');
local fu = require('dlac\\ui\\fishui');
local fb = require('dlac\\ui\\fishbar');
fw.loadState();
local deps = { ownedCounts = function() return owned; end, renderIcon = function() end,
               itemTooltip = function() end, lookupByName = function() return nil; end };
local function all() return table.concat(texts, '\n'); end
local function has(needle) return all():find(needle, 1, true) ~= nil; end
local function tipHas(needle)
    for _, t in ipairs(tips) do if t:find(needle, 1, true) then return true; end end
    return false;
end
local function balanced() return depth.col == 0 and depth.win == 0 and depth.id == 0 and depth.item == 0 and depth.pop == 0; end

-- Pure: the status lines.
local lines = fu.serverStatusLines(snap, 3, nil, nil);
check('FU1 points line', lines[1], 'Fishing points: 12,345');
check('FU2 skill line (rank 3 is Novice)', lines[2], 'Skill 23.4 (+3 gear = 26)  |  Novice, cap 40');
check('FU3 hook line', lines[3], 'Fish up to skill 36 can bite  |  50% skill-up chance per catch above your skill');
lines = fu.serverStatusLines(nil, 0, 23, nil);
check('FU4 waiting for the server', lines[1], 'Fishing points: waiting for the server');
check('FU5 the client skill meanwhile', lines[2], 'Skill 23');
check('FU6 nothing to hook without a skill', #fu.serverStatusLines(nil, 0, nil, nil), 1);
check('FU7 higher band', fu.serverStatusLines({ points = 0, skill = 61, rank = 6 }, 0)[3]:find('30%', 1, true) ~= nil, true);

-- Pure: coverage from Fennella's shelf.
owned = { [13808] = 1, [14071] = 1 };    -- Fsh. Tunica, Angler's Gloves
local lvl, label = fu.status(deps);
check('FU8 gear started', lvl, 1);
check('FU9 label with the worn Fish+', label, 'gear started (Fish+3)');
owned = { [26557] = 1, [13808] = 1, [14070] = 1, [14292] = 1, [14171] = 1 };
check('FU10 the Fisherman\'s set', (fu.status(deps)), 2);
owned = { [26558] = 1, [13809] = 1, [14071] = 1, [14293] = 1, [14172] = 1 };
lvl, label = fu.status(deps);
check('FU11 every piece upgraded', lvl, 3);
check('FU12 the Angler\'s set is +10', label, "Angler's set -- every piece upgraded (Fish+10)");
owned[17386] = 1;
check('FU13 a legendary rod', (fu.status(deps)), 4);

-- The panel: the AscensionXI layout, none of CatsEye's.
owned = { [13808] = 1, [14071] = 1, [17391] = 1, [17396] = 12 };
texts, tips, boxes = {}, {}, {};
local ok, err = pcall(fu.render, deps, 800);
check('FU14 the panel renders', ok, true);
if not ok then print('   ' .. tostring(err)); end
check('FU15 the panel stacks balance', balanced(), true);
check('FU16 the server polled', touched > 0, true);
for _, needle in ipairs({ 'Fishing Gear', 'Fishing points: 12,345', 'Skill 23.4 (+3 gear = 26)',
        "Fennella's shelf (Port Windurst)", "Fisherman's Cap", "Angler's Cap", "Fsh. Tunica", "Angler's Gloves",
        '5,000 points', '12,000 points + the piece', 'Also on the shelf', 'Mog Wardrobe 3 slot',
        '20,000 points each  (2 of 5 bought)', "Fisher's Voidseal", 'RODS', 'next rank test',
        'Move catches into:' }) do
    check('FU17 panel shows ' .. needle, has(needle), true);
end
for _, needle in ipairs({ 'GUILD (GP)', 'MARINERS (VP)', 'CROOKED JONES', 'GP shop', "Today's fishing ventures",
        'Key items', 'Tlahtlamah', 'Brigands' }) do
    check('FU18 panel leaves out ' .. needle, has(needle), false);
end
check('FU19 the creel note', tipHas('Twelve Moat Carp a use'), true);
check('FU20 the better-piece cascade on the gloves row', tipHas("You're awesome"), true);
local sawCase, sawSatchel, trashBox = false, false, nil;
for _, b in ipairs(boxes) do
    if b.label == 'Mog Case##fishmovepanel' then sawCase = true; end
    if b.label == 'Mog Satchel##fishmovepanel' then sawSatchel = true; end
    if b.label == 'Move trash too##fishtrashpanel' then trashBox = b; end
end
check('FU21 the Case switch', sawCase, true);
check('FU22 the Satchel switch', sawSatchel, true);
check('FU22b the trash switch', trashBox ~= nil, true);
check('FU22c ...off by default: fish only', trashBox ~= nil and trashBox.value, false);
check('FU22d the switch says what trash is', tipHas('rusty gear, kelp, shells'), true);
check('FU22e the move tooltip keeps trash out', tipHas('trash only with Move trash too'), true);
clickBox = 'Mog Case##fishmovepanel';
pcall(fu.render, deps, 800);
clickBox = nil;
check('FU23 ticking the Case switch arms it', fw.moveCase, true);
check('FU24 ...and only the Case', fw.moveSatchel, false);
check('FU24b ...saved for the character', (loadfile(tmp .. 'fishstate.lua')() or {}).moveCase, true);
check('FU24c trash still off', fw.moveTrash, false);
clickBox = 'Move trash too##fishtrashpanel';
pcall(fu.render, deps, 800);
clickBox = nil;
check('FU24d ticking Move trash too turns it on', fw.moveTrash, true);
check('FU24e ...saved for the character', (loadfile(tmp .. 'fishstate.lua')() or {}).moveTrash, true);
clickBox = 'Move trash too##fishtrashpanel';
pcall(fu.render, deps, 800);
clickBox = nil;
check('FU24f ...and off again', fw.moveTrash, false);

-- The target window: the +10 hook rule, skill-ups and points per catch.
fw.target, fw.targetName = 4401, 'Moat Carp';
fu.openTarget();
texts, tips = {}, {};
ok, err = pcall(fu.renderSearch, deps);
check('FU25 the target window renders', ok, true);
if not ok then print('   ' .. tostring(err)); end
check('FU26 target window stacks balance', balanced(), true);
check('FU27 the fish and your skill', has('skill 11 (you: 26)'), true);
check('FU28 a fish below you: no skill-ups, the points it pays',
    has('no skill-ups from this fish (your skill has reached 11)  |  pays 40 Fishing points'), true);
check('FU29 isolation counts only rivals that can bite',
    has('spots + baits -- best isolation first (rivals that can bite at your skill), click a ROW to fish it:'), true);
check('FU30 the AXI footnote', has('Items can always bite; monsters only outside cities.'), true);
check('FU31 no CatsEye sweet spot', has('sweet spot'), false);
fw.target, fw.targetName = 4305, 'Ryugu Titan';
pick = 'Ryugu Titan  (skill 150';
fu.openTarget('Ryugu');
texts, tips = {}, {};
pcall(fu.renderSearch, deps);
pick = nil;
check('FU32 a fish beyond you cannot bite yet', has('cannot bite yet: needs skill 140 with gear (you: 26)'), true);
check('FU33 ...but it would teach, 0.1-0.4 a time (#982)', has('skill-ups: 50% a catch, 0.1-0.4 each, up to 40 (your guild cap -- then take the rank test)  |  pays 80 Fishing points'), true);
fw.target, fw.targetName = 4501, 'Fat Greedie';
pick = 'Fat Greedie  (skill 24';
fu.openTarget('Fat Greedie');
texts, tips = {}, {};
pcall(fu.renderSearch, deps);
pick = nil;
check('FU33b a fish under 10 above you teaches 0.1 a time', has("skill-ups: 50% a catch, 0.1 each, up to 24 (this fish's skill)  |  pays 50 Fishing points"), true);
fw.target, fw.targetName = 4305, 'Ryugu Titan';   -- the bar checks below expect the fish that cannot bite

-- The hobby bar's Fishing tab.
texts, tips, boxes = {}, {}, {};
ok, err = pcall(fb.renderContent, 320);
check('FU34 the bar renders', ok, true);
if not ok then print('   ' .. tostring(err)); end
check('FU35 bar stacks balance', balanced(), true);
check('FU36 bar points', has('Fishing points: 12,345'), true);
check('FU37 bar skill', has('Skill 23.4 (+3 gear = 26)'), true);
check('FU38 bar warns the target cannot bite', has('Ryugu Titan cannot bite yet: needs skill 140 with gear (you: 26)'), true);
check('FU39 no VP on the bar', has('VP '), false);
local barCase, barTrash = false, false;
for _, b in ipairs(boxes) do
    if b.label == 'Mog Case##fishmovebar' then barCase = true; end
    if b.label == 'Move trash too##fishtrashbar' then barTrash = true; end
end
check('FU40 the bar carries the switches', barCase, true);
check('FU40b ...the trash switch too', barTrash, true);
fw.target, fw.targetName = 4401, 'Moat Carp';
texts = {};
pcall(fb.renderContent, 320);
check('FU41 no warning for a fish that bites', has('cannot bite yet'), false);

-- Without the server status (an older server): the shelf stays, the server
-- lines and the switches go, and nothing reads VP.
sp.provide('fishing', nil);
texts, boxes = {}, {};
ok = pcall(fu.render, deps, 800);
check('FU42 the panel renders without the service', ok, true);
check('FU43 the shelf stays', has("Fennella's shelf (Port Windurst)"), true);
check('FU44 no points line', has('Fishing points:'), false);
check('FU45 no switches', #boxes, 0);
texts = {};
pcall(fb.renderContent, 320);
check('FU46 the bar falls back without VP', has('VP '), false);
check('FU47 every stack still balances', balanced(), true);
os.remove(tmp .. 'fishstate.lua');

if failures > 0 then
    print(string.format('FAIL -- %d of %d fishing UI checks failed', failures, checks));
    os.exit(1);
end
print(string.format('OK -- %d fishing UI checks passed', checks));
