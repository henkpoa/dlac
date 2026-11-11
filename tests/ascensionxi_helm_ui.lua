-- AXI-26: real HELM snapshots in the existing bar/badge, with CEXI isolation.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local checks = 0;
local function check(name, got, expected)
    checks = checks + 1;
    assert(got == expected, string.format('%s: got %s, expected %s', name, tostring(got), tostring(expected)));
end
local texts, visible = {}, true;
local imgui = setmetatable({}, { __index = function() return function() return false; end; end });
imgui.Begin = function() return visible; end;
imgui.TextColored = function(_, text) texts[#texts + 1] = text; end;
imgui.TextUnformatted = function(text) texts[#texts + 1] = text; end;
imgui.GetWindowPos = function() return 10, 20; end;
package.loaded.imgui = imgui;
local pack = require('dlac\\gear\\serverpack');
local function selectPack(name)
    pack._reset();
    pack._configLoader = function() return { server = name }; end;
    pack.init();
end
selectPack('ascensionxi');
ashita = { events = { register = function() end } };
local service = require('dlac\\servers\\ascensionxi\\modules\\helm\\init');
local status = service.points;
local now, sends, request = 0, 0, nil;
status._clock = function() return now; end;
status._send = function(packet) sends = sends + 1; request = packet; return true; end;
local category = 'Excavation';
package.loaded['dlac\\feature\\helmwatch'] = {
    getGather = function() return category; end,
    isAutoHelm = function() return false; end,
    numericGathering = function() return pack.active() == 'ascensionxi'; end,
    bonuses = function() return { extraRoll = 60, breakReduction = 30 }; end,
    pointsFor = function() return 321; end,
    rating = function() return 4, 1, false; end,
};
package.loaded['dlac\\ui\\helmui'] = {
    texture = function() return nil; end,
    renderPoints = function() status.touch(); end,
};
package.loaded['dlac\\ui\\craftbar'] = { onOffSwitch = function() return false; end };
local active = { key = 'helm', name = 'HELM', detail = category };
local off = 0;
package.loaded['dlac\\feature\\idleexcl'] = {
    getActive = function() return active; end,
    deactivate = function() off = off + 1; end,
};
local host = require('dlac\\ui\\uihost');
host.provide({ ui = {} });
local bar = require('dlac\\ui\\helmbar');
local badge = require('dlac\\ui\\idlefloat');
local function draw(surface)
    texts = {};
    if surface == 'bar' then bar.renderContent(300); else badge.render(); end
    return table.concat(texts, '\n');
end
local function contains(name, text, wanted) check(name, text:find(wanted, 1, true) ~= nil, true); end
local function p16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function p32(n) return p16(n % 65536) .. p16(math.floor(n / 65536)); end
local function deliver(raw)
    local token = ''; for i = 13, 16 do token = token .. string.char(request[i]); end
    local reply = '\224\15\0\0' .. string.char(0x80, request[6], 0, 0)
        .. p16(1) .. p16(0) .. token .. p32(204);
    for _, value in ipairs(raw) do reply = reply .. p16(value); end
    check('real snapshot accepted', status.onPacket(reply), true);
end

status.reset();
contains('badge waits instead of inventing zero', draw('badge'), 'Excavation --');
check('badge alone requests the snapshot', sends, 1);
contains('bar waits for the same snapshot', draw('bar'), 'Skill: Excavation --');
check('both surfaces share one request', sends, 1);
deliver({ 0, 427, 1000, 199 });
local expected = { Harvesting = '0.0', Excavation = '42.7', Logging = '100.0', Mining = '19.9' };
for name, value in pairs(expected) do
    category, active.detail = name, name;
    contains(name .. ' bar decimal', draw('bar'), 'Skill: ' .. name .. ' ' .. value);
    contains(name .. ' badge decimal', draw('badge'), name .. ' ' .. value);
end
category, active.detail = 'Excavation', 'Excavation';
now = 4; draw('badge'); draw('bar'); check('no per-frame polling', sends, 1);
now = 5; draw('badge'); check('badge-only refresh at five seconds', sends, 2);
deliver({ 0, 428, 1000, 199 });
contains('skill-up appears on badge', draw('badge'), 'Excavation 42.8');
contains('skill-up appears on bar', draw('bar'), 'Skill: Excavation 42.8');
contains('gear bonus retained', draw('bar'), 'Extra rolls: +60%');
contains('tool-break bonus retained', draw('bar'), 'Tool break: -30 pp');
status.reset(true);
contains('zoning clears old character skill', draw('badge'), 'Excavation --');
check('zoning settle sends nothing', sends, 2);
now = 10; draw('badge'); check('badge resumes after settle', sends, 3);
deliver({ 0, 429, 1000, 199 });
now = 15; active.badge = false;
check('hidden badge draws nothing', draw('badge'), ''); check('hidden badge does not poll', sends, 3);
active.badge = true; visible = false;
draw('badge'); check('collapsed badge does not poll', sends, 3);
visible = true; active.key = 'craft'; active.detail = 'Woodworking';
contains('other hobby detail unchanged', draw('badge'), 'Woodworking');
check('other hobby does not poll HELM', sends, 3);
active.key = 'helm'; active.detail = 'Excavation';
imgui.SmallButton = function() return true; end;
draw('badge'); check('existing Off button still works', off, 1);
imgui.SmallButton = function() return false; end;

-- CEXI mounts no provider. Even a stale AXI provider cannot poll or show skill.
selectPack('cexi');
check('CEXI has no gathering skill provider', pack.service('gathering'), nil);
local before = sends;
local cexiBar, cexiBadge = draw('bar'), draw('badge');
contains('CEXI venture label retained', cexiBar, 'Excavation VP:');
contains('CEXI venture points retained', cexiBar, '321');
check('CEXI has no decimal skill row', cexiBar:find('Skill:', 1, true), nil);
contains('CEXI badge category retained', cexiBadge, 'Excavation');
check('CEXI has no unknown skill placeholder', cexiBadge:find('--', 1, true), nil);
check('CEXI rendering sends no AXI requests', sends, before);
pack.provide('gathering', service);
now = 100;
check('stale AXI provider is explicitly gated', service.compactSkill('Excavation'), nil);
check('stale provider does not change badge', draw('badge'), cexiBadge);
check('stale provider sends nothing on CEXI', sends, before);
pack._reset();
check('neutral pack does not expose skill', service.compactSkill('Excavation'), nil);
check('neutral pack sends nothing', sends, before);
print(string.format('OK -- %d HELM compact UI checks passed', checks));
