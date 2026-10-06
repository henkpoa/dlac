-- lua tests/ascensionxi_autoacc_ui.lua   (from the dlac repo root)
-- The accuracy box (servers/ascensionxi/modules/telemetry/monitor.lua)
-- against an imgui-shaped stub: every state renders whole, Begin pairs with
-- End, every drawn string is percent-safe, the table shows the server's own
-- numbers, explanations live in the hovers of underlined labels while the
-- screen keeps one short line per thing, nothing a player reads names the
-- service's internals, an open box keeps the session wanted, and the Gear
-- Helpers row's status line follows the client and the model.
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

-- The stub records every string drawn, which hover belongs to which item and
-- which items helpLabel underlined. A lone '%' would be a format bug.
local texts, tips, tipFor, underlined, depth = {}, {}, {}, {}, { win = 0 };
local last, press, beginFlags, sizeCalls = nil, nil, nil, 0;
local nop = function() end;
local IM = {
    TextColored = function(_, s) last = tostring(s); texts[#texts + 1] = last; end,
    SameLine = nop, Separator = nop, Dummy = nop,
    IsItemHovered = function() return true; end,
    SetTooltip = function(s) tips[#tips + 1] = tostring(s); if last ~= nil then tipFor[last] = tostring(s); end end,
    SmallButton = function(label) last = label; return press ~= nil and label:find(press, 1, true) ~= nil; end,
    SetNextWindowSize = function() sizeCalls = sizeCalls + 1; end,
    Begin = function(_, _, flags) beginFlags = flags; depth.win = depth.win + 1; return true; end,
    End = function() depth.win = depth.win - 1; end,
    GetItemRectMin = function() return 0, 0; end,
    GetItemRectMax = function() return 10, 10; end,
    GetColorU32 = function() return 0; end,
    GetWindowDrawList = function() return { AddLine = function() if last ~= nil then underlined[last] = true; end end }; end,
};
ImGuiWindowFlags_AlwaysAutoResize = 64;
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
local function tv05Frame() return assert(wire.decodeSnapshot(wire.incoming(V['TV-05']).payload)); end
local tv05 = tv05Frame();

local clientState, rep = {}, {};
local wants = 0;
local targetName = 'Greater Colibri';
monitor._client = { state = function() return clientState; end };
monitor._want = function() wants = wants + 1; end;
monitor._targetName = function(frame) return frame.targetIndex == tv05.targetIndex and targetName or nil; end;
monitor._autoacc = { report = function() return rep; end, _clock = function() return 10.4; end,
                     _vectorOf = function(id) return { name = 'Item ' .. id .. ' 100%' }; end };

-- Everything a player read in the renders since the last reset, for UI-10.
local seenTexts, seenTips = {}, {};

local function percentSafe(list)
    for _, s in ipairs(list) do
        local stripped = s:gsub('%%%%', '');
        if stripped:find('%', 1, true) then return s; end
    end
    return true;
end
local function longest(list)
    local n = 0;
    for _, s in ipairs(list) do if #s > n then n = #s; end end
    return n;
end
local function drawn() return table.concat(texts, '|'); end
local function has(fragment) return drawn():find(fragment, 1, true) ~= nil; end
local function drew(s)
    for _, t in ipairs(texts) do if t == s then return true; end end
    return false;
end
local function tipHas(item, fragment)
    local t = tipFor[item];
    return t ~= nil and t:find(fragment, 1, true) ~= nil;
end
local function anyTip(fragment)
    for _, t in ipairs(tips) do if t:find(fragment, 1, true) then return true; end end
    return false;
end
local function render(fn)
    texts, tips, tipFor, underlined, last = {}, {}, {}, {}, nil;
    beginFlags, sizeCalls = nil, 0;
    local ok, err = pcall(fn or monitor.drawBody);
    check('render ok ' .. tostring(err), ok, true);
    check('percent-safe texts', percentSafe(texts), true);
    check('percent-safe tips', percentSafe(tips), true);
    for _, s in ipairs(texts) do seenTexts[#seenTexts + 1] = s; end
    for _, s in ipairs(tips) do seenTips[#seenTips + 1] = s; end
end

-- UI-01: nothing yet; the box itself is demand.
clientState, rep = { phase = 'settling', why = 'waiting for an AutoAcc piece' }, {};
wants = 0;
render();
check('UI-01 an open box wants the session', wants, 1);
check('UI-01 one word on top', texts[1], 'Starting');
check('UI-01 underlined, what it does in its hover', underlined['Starting'] and tipHas('Starting', 'Connecting to the server'), true);
check('UI-01 no table', has('Cap at'), false);
check('UI-01 the AutoAcc header is underlined', underlined['AutoAcc'], true);
check('UI-01 no piece yet, how in the hover', drew('no piece') and tipHas('no piece', 'Gear Rule: AutoAcc'), true);
local level, text = monitor.status();
check('UI-01 row level', level, 0);
check('UI-01 row text', text, 'no AutoAcc piece worn');

-- UI-02: live, a usable frame: the table is the server's numbers, and every
-- explanation is a hover.
clientState = { phase = 'live', laneState = wire.laneState.LIVE, stats = { pushes = 4, accepted = 4 } };
rep = { usable = true, bases = 2, frame = tv05, frameAt = 10.0, formulaOk = true, gearOk = true,
        decision = { release = { Ring1 = 'Rajas Ring' },
                     typed = { Ring1 = "Toreador's Ring", Neck = 'Peacock Amulet' },
                     why = { Ring1 = 'released for Rajas Ring', Neck = 'needed for the cap', Zzz = 'odd 100% slot' } },
        unverified = { [14674] = 'accMod: the server adds 12, dlac 10' }, mispredicted = {} };
render();
local target = 'Greater Colibri, Lv ' .. tv05.targetLevel;
local main, ranged = tv05.contexts[1], tv05.contexts[3];
local mainToCap = formula.accToCap(main, formula.effective(tv05, main, main.liveAcc));
local rangedToCap = formula.accToCap(ranged, formula.effective(tv05, ranged, ranged.liveAcc));
check('UI-02 the target by name and level', drew(target), true);
check('UI-02 the age in its hover', tipHas(target, 'Updated 0.4 s ago.'), true);
check('UI-02 usable numbers say nothing more', tipHas(target, 'waiting'), false);
check('UI-02 ACC cell', has('|' .. main.liveAcc .. '|'), true);
check('UI-02 EVA cell', has('|' .. main.targetEva .. '|'), true);
check('UI-02 level cell', has('|' .. ('%+d'):format(main.levelCorrection) .. '|'), true);
check('UI-02 hit cell, escaped', has('|' .. math.floor(main.thresholdBp / 100) .. '%%|'), true);
check('UI-02 cap-at cell', has(('|%d|'):format(main.liveAcc + mainToCap)), true);
check('UI-02 main hand spare', has(('%d spare'):format(-mainToCap)), true);
check('UI-02 the vectors: 11 spare at the cap of ACC 372', has('11 spare') and has('|372|'), true);
check('UI-02 off hand short', has('needs 50'), true);
check('UI-02 ranged is for reference, in its hover', tipHas(('needs %d'):format(rangedToCap), 'AutoAcc decides on melee only'), true);
check('UI-02 the off hand has no hover', tipFor['needs 50'], nil);
check('UI-02 food in the ACC hover, escaped', tipHas('ACC', 'Your food adds ' .. tv05.foodAccPct .. '%% ACC, up to ' .. tv05.foodAccCap), true);
check('UI-02 the headers are underlined', underlined['ACC'] and underlined['Cap at'], true);
check('UI-02 Hand has nothing to explain', underlined['Hand'], nil);
check('UI-02 a released slot shows its normal pick', drew('Rajas Ring'), true);
check('UI-02 and why, in its hover', tipFor['Rajas Ring'], "Rajas Ring is on: you reach the cap without Toreador's Ring.");
check('UI-02 a needed piece shows itself', drew('Peacock Amulet'), true);
check('UI-02 and why', tipFor['Peacock Amulet'], 'Peacock Amulet is on: you need it to reach the cap.');
check('UI-02 rows are not underlined', underlined['Rajas Ring'], nil);
check('UI-02 slot order: Neck before Ring1', drawn():find('Neck', 1, true) < drawn():find('Ring1', 1, true), true);
check('UI-02 an unknown slot is still drawn', drew('Zzz'), true);
check('UI-02 an unknown reason is not shown', has('odd 100') or anyTip('odd 100'), false);
check('UI-02 kept on, one short label', drew('1 kept on') and underlined['1 kept on'], true);
check('UI-02 which, in its hover', tipHas('1 kept on', 'Item 14674 100%%'), true);
for _, gone in ipairs({ 'Telemetry', 'Checks', 'agree', 'released for', 'needed for', 'food', 'Effects', 'Prediction', 'Engage' }) do
    check('UI-02 not on screen: ' .. gone, has(gone), false);
end
check('UI-02 no line is a paragraph', longest(texts) <= 40, true);
level, text = monitor.status();
check('UI-02 row level', level, 1);
check('UI-02 row text', text, 'live -- 1 piece released');

-- UI-03: the prediction check, in the AutoAcc hover, in a sentence.
local rows = { [0] = { acc = 376, threshold = 9500, measuredAcc = 376, measuredThreshold = 9500 } };
rep.prediction = { verdict = 'waiting', release = { Ring1 = 'Rajas Ring' }, rows = {} };
render();
check('UI-03 the hover explains AutoAcc', tipHas('AutoAcc', 'only while you need the accuracy'), true);
check('UI-03 waiting', tipHas('AutoAcc', 'Your last swap: waiting for the server to confirm'), true);
rep.prediction = { verdict = 'matched', release = { Ring1 = 'Rajas Ring' }, rows = rows };
render();
check('UI-03 matched', tipHas('AutoAcc', "Your last swap: the server confirmed DLAC's numbers."), true);
check('UI-03 no numbers', tipHas('AutoAcc', '376') or tipHas('AutoAcc', 'measured'), false);
rep.prediction = { verdict = 'mismatch', release = { Ring1 = 'Rajas Ring' },
                   rows = { [0] = { acc = 376, threshold = 9500, measuredAcc = 373, measuredThreshold = 9400 } } };
rep.mispredicted = { [15543] = 'a release predicted wrongly' };
render();
check('UI-03 wrong, in the hover', tipHas('AutoAcc', "didn't match DLAC's, so those pieces stay on"), true);
check('UI-03 kept on counts it', drew('2 kept on') and tipHas('2 kept on', 'Item 15543 100%%'), true);
check('UI-03 gear mismatch names outfit-wide input totals', tipHas('2 kept on', 'ACC total: server adds 12; DLAC counts 10'), true);
check('UI-03 kept-on explains outfit mismatch', tipHas('2 kept on', 'after a gear total disagreed with the server'), true);
check('UI-03 gear mismatch does not blame an individual piece', tipHas('2 kept on', 'Each reported total covers the outfit, not an individual piece'), true);
check('UI-03 swap mismatch uses player wording', tipHas('2 kept on', 'the server returned different accuracy numbers after a swap'), true);
rep.prediction = { verdict = 'not checked', why = 'something besides the gear changed', release = {}, rows = {} };
render();
check('UI-03 a swap not checked says nothing', tipHas('AutoAcc', 'last swap') or tipHas('AutoAcc', 'besides'), false);
rep.prediction, rep.mispredicted = nil, {};

-- UI-04: holding on a trigger; the hover and the row say so.
rep.trigger = 'a new target';
render();
check('UI-04 holding, in the hover', tipHas('AutoAcc', 'Every piece stays on for a moment (a new target).'), true);
check('UI-04 not on screen', has('a new target'), false);
level, text = monitor.status();
check('UI-04 row', text, 'holding -- a new target');
rep.trigger = 'an odd 100% reason';
level, text = monitor.status();
check('UI-04 the row is a format string: escaped', text, 'holding -- an odd 100%% reason');
rep.trigger = nil;

-- UI-04b: the rows follow the equipment order whatever order pairs() gives
-- (it changes from run to run): all sixteen slots, and an unknown one last.
local ORDER = { 'Head', 'Neck', 'Ear1', 'Ear2', 'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet',
                'Main', 'Sub', 'Range', 'Ammo' };
local every = { release = {}, typed = {}, why = { Zzz = 'needed for the cap' } };
local isSlot = { Zzz = true };
for _, s in ipairs(ORDER) do every.why[s], every.typed[s], isSlot[s] = 'needed for the cap', s .. ' piece', true; end
rep = { usable = true, bases = 1, frame = tv05, frameAt = 10.0, decision = every };
render();
local order = {};
for _, t in ipairs(texts) do if isSlot[t] then order[#order + 1] = t; end end
check('UI-04b the equipment order', table.concat(order, ' '), table.concat(ORDER, ' ') .. ' Zzz');

-- UI-05: a failed check is the one loud thing, and it never prints the
-- check's own reason.
rep = { usable = false, why = 'gear check: 100% wrong', mismatch = '100% wrong', formulaOk = true, gearOk = false,
        frame = tv05, frameAt = 10.0, unverified = {} };
render();
check('UI-05 flagged', drew('Check failed') and underlined['Check failed'], true);
check('UI-05 in a sentence', tipHas('Check failed', "DLAC's numbers don't match the server's"), true);
check('UI-05 not the check\'s reason', anyTip('gear check') or anyTip('100%'), false);
check('UI-05 the target hover says AutoAcc waits', tipHas(target, "waiting for the server's numbers"), true);
level, text = monitor.status();
check('UI-05 row level', level, 0);
check('UI-05 row text', text, "waiting for the server's numbers");
rep = { usable = false, why = 'formula check: ctx 0 accuracy 384, the server says 383', formulaOk = false,
        frame = tv05, frameAt = 10.0 };
render();
check('UI-05 a failed formula check is flagged too', drew('Check failed'), true);
check('UI-05 without its numbers', anyTip('ctx') or anyTip('384'), false);
rep = { usable = false, why = 'the frame names an outfit dlac did not see', formulaOk = true, gearOk = false,
        frame = tv05, frameAt = 10.0 };
render();
check('UI-05 not usable yet is not a failure', drew('Check failed'), false);
check('UI-05 the target hover says AutoAcc waits', tipHas(target, "waiting for the server's numbers"), true);

-- UI-06: no table without a live frame, a live session, and the hands that apply.
local idle = tv05Frame();
idle.laneState = wire.laneState.IDLE;
rep = { usable = false, why = 'the lane is not live (state 0)', frame = idle, frameAt = 10.0 };
render();
check('UI-06 no target', drew('No target') and tipHas('No target', 'Engage a monster'), true);
check('UI-06 no table', has('Cap at'), false);
clientState = { phase = 'hello', stats = {} };
rep = { usable = true, bases = 1, frame = tv05, frameAt = 10.0 };
render();
check('UI-06 restarting', texts[1], 'Starting');
check('UI-06 a stale frame shows no table', has('Cap at'), false);
clientState = { phase = 'live', laneState = wire.laneState.LIVE, stats = {} };
local oneHand = tv05Frame();
oneHand.contexts[2].applicability = wire.applicability.NO_WEAPON;
rep = { usable = true, bases = 1, frame = oneHand, frameAt = 10.0 };
render();
check('UI-06 a hand that does not apply has no row', has('Off hand'), false);
check('UI-06 it is named in the Hand hover', underlined['Hand'] and tipHas('Hand', 'Off hand: no weapon'), true);
check('UI-06 the others stay', has('Main hand') and has('Ranged'), true);
local flashed = tv05Frame();
flashed.flashPenalty = 20;
rep = { usable = true, bases = 1, frame = flashed, frameAt = 10.0 };
render();
check('UI-06 Flash, flagged', drew('Flash -20') and tipHas('Flash -20', 'until it wears off'), true);
targetName = 'Odd 50% Mob';
rep = { usable = true, bases = 1, frame = tv05, frameAt = 10.0 };
render();
check('UI-06 a name with a percent, escaped', drew('Odd 50%% Mob, Lv ' .. tv05.targetLevel), true);
targetName = 'Greater Colibri';

-- UI-07: a disarmed engine (the Tripwire) says so first, and the row is off.
native = false;
rep = { usable = true, bases = 1, frame = tv05, frameAt = 10.0 };
render();
check('UI-07 the warning first', texts[1], 'Engine disarmed');
check('UI-07 why, in its hover', tipHas('Engine disarmed', 'LuaAshitacast'), true);
level, text = monitor.status();
check('UI-07 row', text, 'off -- the engine is disarmed');
native = true;

-- UI-08: dormant (a server without telemetry): said plainly, not why.
clientState = { phase = 'dormant', why = 'no telemetry on this server' };
level, text = monitor.status();
check('UI-08 row', text, 'off -- the server is not sending numbers');
render();
check('UI-08 the box says so', drew('Unavailable') and tipHas('Unavailable', "isn't sending accuracy numbers"), true);
check('UI-08 not the client\'s reason', anyTip('no telemetry on this server'), false);
check('UI-08 no table', has('Cap at'), false);

-- UI-09: the floating window sizes itself, pairs Begin with End and closes;
-- the panel's button opens it.
monitor.visible = false;
render(monitor.render);
check('UI-09 nothing while closed', depth.win == 0 and beginFlags == nil, true);
monitor.visible = true;
render(monitor.render);
check('UI-09 Begin paired with End', depth.win, 0);
check('UI-09 the window fits its content', beginFlags, ImGuiWindowFlags_AlwaysAutoResize);
check('UI-09 and nothing sets its size', sizeCalls, 0);
monitor.visible = false;
press = 'Open window';
render(monitor.panel);
check('UI-09 the panel opens the window', monitor.visible, true);
check('UI-09 the panel header explains itself', underlined['Accuracy and AutoAcc'] and tipHas('Accuracy and AutoAcc', 'only while you need it'), true);
check('UI-09 the button names the command', tipHas('Open window##aamon', '/dl accuracy'), true);
press = nil;
check('UI-09 toggle closes', monitor.toggle(), false);

-- UI-11: every reason the model gives (autoacc.decide) reaches the hover in
-- a player's words, and the model still gives each of them.
local f = assert(io.open('servers/ascensionxi/modules/telemetry/autoacc.lua', 'rb'));
local modelSource = f:read('*a'); f:close();
local REASONS = {
    { 'the full set does not reach the cap', "you don't reach the cap even with it" },
    { 'only the standing Default set releases', 'only swaps pieces in your standing set' },
    { 'weapon slots stay', 'weapons always stay on' },
    { 'no fallback', 'nothing else to wear' },
    { 'its enchantment would be lost', 'end its enchantment' },
    { 'it lowers max HP while an HP latent is worn', 'lower your max HP' },
    { 'unverified', "didn't match DLAC's" },
    { 'a release of it was predicted wrongly', "didn't match DLAC's" },
    { 'inside an Onslaught run', 'Onslaught run' },
    { 'it covers another slot', 'two slots' },
    { 'augmented', 'augmented copy' },
    { 'an equip script dlac does not model', 'special equip effect' },
    { 'not in the catalog', "doesn't know this piece" },
    { 'the slot is not the piece', 'Something else is in this slot.' },
    { 'an accuracy latent (HP>75%)', 'depends on a condition', 'an accuracy latent (' },
    { 'held until the next frame: a new target', 'for a moment (a new target)', 'held until the next frame: ' },
    { 'formula check: ctx 0 accuracy 384, the server says 383', "waiting for the server's numbers", 'formula check: ' },
    { 'the lane is not live (state 0)', "waiting for the server's numbers", 'the lane is not live (state ' },
    { 'Rajas Ring differs from the frame outfit and is unverified', "waiting for the server's numbers",
      'differs from the frame outfit and is ' },
    { 'the outfits are not known yet', "waiting for the server's numbers" },
    { 'no frame speaks for this outfit', "waiting for the server's numbers" },
};
for _, r in ipairs(REASONS) do
    rep = { usable = true, bases = 1, frame = tv05, frameAt = 10.0,
            decision = { release = {}, typed = { Head = 'Head piece' }, why = { Head = r[1] } } };
    render();
    check('UI-11 ' .. r[1], tipHas('Head piece', r[2]), true);
    check('UI-11 the model says "' .. (r[3] or r[1]) .. '"', modelSource:find(r[3] or r[1], 1, true) ~= nil, true);
end

-- UI-10: across every render above, nothing a player read named the
-- service's internals (owner: "You don't need to give out super detailed
-- server statistics").
local INTERNALS = { 'frame', 'lane', 'rev ', 'ctx', 'state ', 'session', 'Telemetry', 'telemetry', 'formula check',
                    'gear check', 'basis', 'unverified', 'predicted', 'measured', '0x', 'received', 'accepted' };
for _, word in ipairs(INTERNALS) do
    local leaked = nil;
    for _, list in ipairs({ seenTexts, seenTips }) do
        for _, s in ipairs(list) do if s:find(word, 1, true) then leaked = s; break; end end
        if leaked then break; end
    end
    check('UI-10 no "' .. word .. '" ' .. tostring(leaked), leaked, nil);
end

print(('ascensionxi_autoacc_ui: %d passed, %d failed'):format(pass, fail));
if fail > 0 then os.exit(1); end
