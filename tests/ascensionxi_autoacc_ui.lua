-- lua tests/ascensionxi_autoacc_ui.lua   (from the dlac repo root)
-- The accuracy box (servers/ascensionxi/modules/telemetry/monitor.lua)
-- against an imgui-shaped stub: every state renders whole, Begin pairs with
-- End, every drawn string is percent-safe, the table shows the server's own
-- numbers, an open box keeps the session wanted, and the Gear Helpers row's
-- status line follows the client and the model.
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
local nop = function() end;
local IM = {
    TextColored = function(_, s) texts[#texts + 1] = tostring(s); end,
    SameLine = nop, Separator = nop, Dummy = nop,
    IsItemHovered = function() return true; end,
    SetTooltip = function(s) tips[#tips + 1] = tostring(s); end,
    SmallButton = function(label) buttons[#buttons + 1] = label; return press ~= nil and label:find(press, 1, true) ~= nil; end,
    SetNextWindowSize = nop,
    Begin = function() depth.win = depth.win + 1; return true; end,
    End = function() depth.win = depth.win - 1; end,
};
package.loaded['imgui'] = IM;
package.loaded['dlac\\ui\\uihost'] = { services = {} };   -- the fallback palette
local native = true;
package.loaded['dlac\\feature\\equipengine'] = { nativeOn = function() return native; end };

local wire = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\wire');
local formula = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\formula');
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
local wants = 0;
monitor._client = { state = function() return clientState; end };
monitor._want = function() wants = wants + 1; end;
monitor._targetName = function(frame) return frame.targetIndex == tv05.targetIndex and 'Greater Colibri' or nil; end;
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
local function has(fragment) return drawn():find(fragment, 1, true) ~= nil; end
local function render(fn)
    texts, tips, buttons = {}, {}, {};
    local ok, err = pcall(fn or monitor.drawBody);
    check('render ok ' .. tostring(err), ok, true);
    check('percent-safe texts', percentSafe(texts), true);
    check('percent-safe tips', percentSafe(tips), true);
end

-- UI-01: nothing yet; the box itself is demand.
clientState, rep = { phase = 'settling', why = 'waiting for an AutoAcc piece' }, {};
wants = 0;
render();
check('UI-01 an open box wants the session', wants, 1);
check('UI-01 says it waits', has('waiting for an AutoAcc piece'), true);
check('UI-01 asks for a fight', has('Engage a monster'), true);
check('UI-01 explains AutoAcc', has('Gear Rule: AutoAcc'), true);
local level, text = monitor.status();
check('UI-01 row level', level, 0);
check('UI-01 row text', text, 'no AutoAcc piece worn');

-- UI-02: live, a usable frame: the table is the server's numbers.
clientState = { phase = 'live', laneState = wire.laneState.LIVE, stats = { pushes = 4, accepted = 4 } };
rep = { usable = true, bases = 2, frame = tv05, frameAt = 10.0,
        decision = { release = { Ring1 = 'Rajas Ring' },
                     why = { Ring1 = 'released for Rajas Ring', Neck = 'needed for the cap', Zzz = 'odd 100% slot' } },
        unverified = { [14674] = 'accMod' }, mispredicted = {} };
render();
local main = tv05.contexts[1];
local mainToCap = formula.accToCap(main, formula.effective(tv05, main, main.liveAcc));
check('UI-02 the target by name', has('Greater Colibri, level ' .. tv05.targetLevel), true);
check('UI-02 the frame age', has('0.4 s ago'), true);
check('UI-02 the checks agree', has('agree with the server (2 frames)'), true);
check('UI-02 ACC cell', has('|' .. main.liveAcc .. '|'), true);
check('UI-02 EVA cell', has('|' .. main.targetEva .. '|'), true);
check('UI-02 level cell', has('|' .. ('%+d'):format(main.levelCorrection) .. '|'), true);
check('UI-02 hit cell, escaped', has('|' .. math.floor(main.thresholdBp / 100) .. '%%|'), true);
check('UI-02 cap-at cell', has(('|%d|'):format(main.liveAcc + mainToCap)), true);
check('UI-02 main hand spare', has(('%d spare'):format(-mainToCap)), true);
check('UI-02 the vectors: 11 spare at the cap of ACC 372', has('11 spare') and has('|372|'), true);
check('UI-02 off hand short', has('needs 50'), true);
check('UI-02 food', has('food adds ' .. tv05.foodAccPct .. '%% ACC, up to ' .. tv05.foodAccCap), true);
check('UI-02 the release', has('released for Rajas Ring'), true);
check('UI-02 slot order: Neck before Ring1', drawn():find('Neck', 1, true) < drawn():find('Ring1', 1, true), true);
check('UI-02 an unknown slot still drawn, escaped', has('odd 100%% slot'), true);
check('UI-02 kept on', has('1 piece'), true);
level, text = monitor.status();
check('UI-02 row level', level, 1);
check('UI-02 row text', text, 'live -- 1 piece released');

-- UI-03: the prediction check, every verdict.
local rows = { [0] = { acc = 376, threshold = 9500, measuredAcc = 376, measuredThreshold = 9500 } };
rep.prediction = { verdict = 'waiting', release = { Ring1 = 'Rajas Ring' }, rows = {} };
render();
check('UI-03 waiting', has('waiting for the server to measure Ring1 to Rajas Ring'), true);
rep.prediction = { verdict = 'matched', release = { Ring1 = 'Rajas Ring' }, rows = rows };
render();
check('UI-03 matched', has('matched the server for Ring1 to Rajas Ring'), true);
check('UI-03 the numbers', has('Main hand: ACC 376 predicted, 376 measured; hit 95%%, 95%%'), true);
rep.prediction = { verdict = 'mismatch', release = { Ring1 = 'Rajas Ring' },
                   rows = { [0] = { acc = 376, threshold = 9500, measuredAcc = 373, measuredThreshold = 9400 } } };
rep.mispredicted = { [15543] = 'a release predicted wrongly' };
render();
check('UI-03 wrong, loudly', has('WRONG for Ring1 to Rajas Ring'), true);
check('UI-03 the wrong numbers', has('ACC 376 predicted, 373 measured'), true);
check('UI-03 kept on counts it', has('2 pieces'), true);
rep.prediction = { verdict = 'not checked', why = 'something besides the gear changed', release = {}, rows = {} };
render();
check('UI-03 not checked', has('not checked: something besides the gear changed'), true);
rep.prediction, rep.mispredicted = nil, {};

-- UI-04: holding on a trigger; the row says so.
rep.trigger = 'a new target';
render();
check('UI-04 holding drawn', has('a new target'), true);
level, text = monitor.status();
check('UI-04 row', text, 'holding -- a new target');
rep.trigger = nil;

-- UI-05: a frame that did not pass, and an odd reason with a percent in it.
rep = { usable = false, why = 'gear check: 100% wrong', frame = tv05, frameAt = 10.0, unverified = {} };
render();
check('UI-05 the reason, escaped', has('gear check: 100%% wrong'), true);
level, text = monitor.status();
check('UI-05 row level', level, 0);
check('UI-05 row text escaped', text, 'live -- gear check: 100%% wrong');

-- UI-06: a frame that is not LIVE shows no table.
local idle = assert(wire.decodeSnapshot(wire.incoming(V['TV-05']).payload));
idle.laneState = wire.laneState.IDLE;
rep = { usable = false, why = 'the lane is not live (state 0)', frame = idle, frameAt = 10.0 };
render();
check('UI-06 asks for a fight', has('Engage a monster'), true);
check('UI-06 no table', has('Cap at'), false);

-- UI-07: a disarmed engine (the Tripwire) says so first, and the row is off.
native = false;
rep = { usable = true, bases = 1, frame = tv05, frameAt = 10.0 };
render();
check('UI-07 the warning', texts[1]:find('engine is disarmed', 1, true) ~= nil, true);
level, text = monitor.status();
check('UI-07 row', text, 'off -- the engine is disarmed');
native = true;

-- UI-08: dormant (a server without telemetry).
clientState = { phase = 'dormant', why = 'no telemetry on this server' };
level, text = monitor.status();
check('UI-08 row', text, 'off -- no telemetry on this server');

-- UI-09: the floating window pairs Begin with End, closes, and the panel's
-- button opens it.
monitor.visible = false;
render(monitor.render);
check('UI-09 nothing while closed', depth.win, 0);
monitor.visible = true;
render(monitor.render);
check('UI-09 Begin paired with End', depth.win, 0);
monitor.visible = false;
press = 'Open as a floating window';
render(monitor.panel);
check('UI-09 the panel opens the window', monitor.visible, true);
press = nil;
check('UI-09 toggle closes', monitor.toggle(), false);

print(('ascensionxi_autoacc_ui: %d passed, %d failed'):format(pass, fail));
if fail > 0 then os.exit(1); end
