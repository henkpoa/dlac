-- lua tests/ascensionxi_autoacc_ui.lua   (from the dlac repo root)
-- The AutoAcc readout (servers/ascensionxi/modules/telemetry/monitor.lua)
-- against an imgui-shaped stub: every state renders whole, Begin pairs with
-- End, every drawn string is percent-safe, and the Gear Helpers row's status
-- line follows the client and the model.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);

local pass, fail = 0, 0;
local function check(name, got, want)
    if got == want then pass = pass + 1; return; end
    fail = fail + 1;
    print(('FAIL %s: got %s, want %s'):format(name, tostring(got), tostring(want)));
end

-- The stub records every string drawn; a lone '%' would be a format bug.
local texts, tips, depth, buttons = {}, {}, { win = 0 }, {};
local press = nil;
local IM = {
    TextColored = function(_, s) texts[#texts + 1] = tostring(s); end,
    SameLine = function() end, Separator = function() end,
    IsItemHovered = function() return true; end,
    SetTooltip = function(s) tips[#tips + 1] = tostring(s); end,
    SmallButton = function(label) buttons[#buttons + 1] = label; return press ~= nil and label:find(press, 1, true) ~= nil; end,
    SetNextWindowSize = function() end,
    Begin = function() depth.win = depth.win + 1; return true; end,
    End = function() depth.win = depth.win - 1; end,
};
package.loaded['imgui'] = IM;
package.loaded['dlac\\ui\\uihost'] = { services = {} };   -- the fallback palette
local native = true;
package.loaded['dlac\\feature\\equipengine'] = { nativeOn = function() return native; end };

local wire = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\wire');
local monitor = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\monitor');

local function readVectors(path)
    local f = assert(io.open(path, 'rb')); local text = f:read('*a'); f:close();
    local out, cur, inBlock, hex = {}, nil, false, {};
    for line in text:gmatch('[^\n]*') do
        line = line:gsub('\r$', '');
        local name = line:match('^### (TV%-[%w]+)');
        if name then cur = name;
        elseif cur and line == '```' then
            if inBlock then out[cur] = table.concat(hex); cur, inBlock, hex = nil, false, {}; else inBlock = true; end
        elseif inBlock then for b in line:sub(7):gmatch('%x%x') do hex[#hex + 1] = string.char(tonumber(b, 16)); end end
    end
    return out;
end
local V = readVectors('tests/fixtures/ascensionxi/telemetry-wire-vectors.md');
local tv05 = assert(wire.decodeSnapshot(wire.incoming(V['TV-05']).payload));

local clientState, rep = {}, {};
monitor._client = { state = function() return clientState; end };
monitor._autoacc = { report = function() return rep; end, _clock = function() return 10.4; end,
                     _vectorOf = function(id) return { name = 'Item ' .. id .. ' 100%' }; end };

local function percentSafe(list)
    for _, s in ipairs(list) do
        local stripped = s:gsub('%%%%', '');
        if stripped:find('%', 1, true) then return s; end
    end
    return true;
end
local function drawn() return table.concat(texts, '|'); end
local function render(fn)
    texts, tips, buttons = {}, {}, {};
    local ok, err = pcall(fn or monitor.drawBody);
    check('render ok ' .. tostring(err), ok, true);
    check('percent-safe texts', percentSafe(texts), true);
    check('percent-safe tips', percentSafe(tips), true);
end

-- UI-01: nothing yet.
clientState, rep = { phase = 'settling', why = 'waiting for an AutoAcc piece' }, {};
render();
check('UI-01 says it waits', drawn():find('waiting for an AutoAcc piece', 1, true) ~= nil, true);
check('UI-01 no frame', drawn():find('No frame yet', 1, true) ~= nil, true);
local level, text = monitor.status();
check('UI-01 row level', level, 0);
check('UI-01 row text', text, 'no AutoAcc piece worn');

-- UI-02: live, a usable frame, one release, one held, one unverified piece.
clientState = { phase = 'live', laneState = wire.laneState.LIVE, stats = { pushes = 4, accepted = 4 } };
rep = { usable = true, bases = 2, frame = tv05, frameAt = 10.0,
        decision = { release = { Ring1 = 'Rajas Ring' },
                     why = { Ring1 = 'released for Rajas Ring', Neck = 'needed for the cap', Zzz = 'odd 100% slot' } },
        unverified = { [14674] = 'accMod' } };
render();
local all = drawn();
check('UI-02 live lane', all:find('live, battle lane live', 1, true) ~= nil, true);
check('UI-02 frame age', all:find('0.4 s ago', 1, true) ~= nil, true);
check('UI-02 bases', all:find('2 frames for this state', 1, true) ~= nil, true);
check('UI-02 main hand spare', all:find('11 ACC spare', 1, true) ~= nil, true);
check('UI-02 off hand short', all:find('needs 50 ACC', 1, true) ~= nil, true);
check('UI-02 a rate drawn escaped', all:find('70%%', 1, true) ~= nil, true);
check('UI-02 ranged shown', all:find('Ranged', 1, true) ~= nil, true);
check('UI-02 the release', all:find('released for Rajas Ring', 1, true) ~= nil, true);
check('UI-02 slot order: Neck before Ring1', all:find('Neck', 1, true) < all:find('Ring1', 1, true), true);
check('UI-02 an unknown slot still drawn, escaped', all:find('odd 100%% slot', 1, true) ~= nil, true);
check('UI-02 unverified count', all:find('1 piece', 1, true) ~= nil, true);
level, text = monitor.status();
check('UI-02 row level', level, 1);
check('UI-02 row text', text, 'live -- 1 piece released');

-- UI-03: holding on a trigger; the row says so.
rep.trigger = 'a new target';
render();
check('UI-03 holding drawn', drawn():find('a new target', 1, true) ~= nil, true);
level, text = monitor.status();
check('UI-03 row', text, 'holding -- a new target');
rep.trigger = nil;

-- UI-04: a frame that did not pass, and an odd reason with a percent in it.
rep = { usable = false, why = 'gear check: 100% wrong', frame = tv05, frameAt = 10.0, unverified = {} };
render();
check('UI-04 the reason, escaped', drawn():find('gear check: 100%% wrong', 1, true) ~= nil, true);
level, text = monitor.status();
check('UI-04 row level', level, 0);
check('UI-04 row text escaped', text, 'live -- gear check: 100%% wrong');

-- UI-05: a disarmed engine (the Tripwire) says so first, and the row is off.
native = false;
render();
check('UI-05 the warning', texts[1]:find('engine is disarmed', 1, true) ~= nil, true);
level, text = monitor.status();
check('UI-05 row', text, 'off -- the engine is disarmed');
native = true;

-- UI-06: dormant (a server without telemetry).
clientState = { phase = 'dormant', why = 'no telemetry on this server' };
level, text = monitor.status();
check('UI-06 row', text, 'off -- no telemetry on this server');

-- UI-07: the floating window pairs Begin with End, closes, and the panel's
-- button opens it.
monitor.visible = false;
render(monitor.render);
check('UI-07 nothing while closed', depth.win, 0);
monitor.visible = true;
render(monitor.render);
check('UI-07 Begin paired with End', depth.win, 0);
monitor.visible = false;
press = 'Open as a floating window';
render(monitor.panel);
check('UI-07 the panel opens the window', monitor.visible, true);
press = nil;
check('UI-07 toggle closes', monitor.toggle(), false);

print(('ascensionxi_autoacc_ui: %d passed, %d failed'):format(pass, fail));
if fail > 0 then os.exit(1); end
