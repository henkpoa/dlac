-- Run from the addon root: lua tests/padnav.lua
-- Controller navigation (feature/padnav.lua, ticket AXI-119): the input door,
-- the capture, the release rules and the uiflags round trip. No Ashita, no
-- ImGui -- the io seam is replaced.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);

local n = 0;
local function check(label, got, want)
    n = n + 1;
    if got ~= want then
        error(string.format('%s: got %s, want %s', label, tostring(got), tostring(want)), 2);
    end
end

local pad = require('dlac\\feature\\padnav');

-- The seam: a recording ImGui, a clock we own.
local fed, flags, tabs, navActive, clock, newBinding = {}, false, {}, true, 0, true;
pad.io.newBinding = function() return newBinding; end
pad.io.key = function(name) return name; end
pad.io.feed = function(key, down) fed[#fed + 1] = key .. (down and '+' or '-'); return true; end
pad.io.setFlags = function(want) flags = want; end
pad.io.navActive = function() return navActive; end
pad.io.now = function() return clock; end
pad.io.cycleTab = function(dir) tabs[#tabs + 1] = dir; end
pad.say = function() end

local ui, visible = {}, false;
local host = { ui = ui, popup = function() end,
               visible = function() return visible; end,
               setVisible = function(v) visible = v; end };

local function fresh()
    pad._reset();
    fed, flags, tabs, navActive, clock, newBinding = {}, false, {}, true, 0, true;
    for k in pairs(ui) do ui[k] = nil; end
    visible = false;
end
local function combo() pad.applySaved('on=1;combo=d58+d59'); end
local function press(t) return pad.onButton(t, true); end
local function lift(t) return pad.onButton(t, false); end
local function open() press('d58'); press('d59'); lift('d59'); lift('d58'); pad.tick(host); end
-- One dlac window's Begin, as lib\imguicompat reports it. `focus` is what
-- ImGui would answer: true = focused, 'self' = a HUD piece focused itself,
-- 'popup' = the focus is in a popup opened under it, false = not focused.
local focusNow, focusAsked = false, 0;
local function focusSeam(flags)
    if focusNow == 'self' then return true; end
    if focusNow == 'popup' then return flags == 1; end      -- the focus is in a popup under it
    return focusNow == true;
end
pad.io.windowFocused = focusSeam;
pad.io.focusNext = function() focusAsked = focusAsked + 1; end
pad.io.hideCursor = function() end
local hudHidden = false;
pad.io.hudHidden = function() return hudHidden; end
local function draw(name, focus, openT)
    focusNow = focus or false;
    pad.windowHook(false, name, openT);
    pad.windowHook(true, name, openT);
end
local HOST = '##dlac_padhost';
local MAIN, HOBBY, LOCK = 'dlac Gear###ffxi_lac_gearui', 'dlac Hobbies##dlac_hobbybar', 'dlac Lockstyle###dlac_lockstyle';

-- 1. Off, unbound or unsupported: every press reaches the game.
fresh();
check('PN1 off: a press passes', press('d49'), false);
check('PN2 off: its release passes', lift('d49'), false);
pad.applySaved('on=1');
check('PN3 on but no combo: passes', press('d58'), false); lift('d58');
fresh(); combo(); newBinding = false;
check('PN4 unsupported binding: not supported', pad.supported(), false);
press('d58');
check('PN5 unsupported: the combo press passes', press('d59'), false);
check('PN6 unsupported: the pad is not taken', pad.active(), false);

-- 2. The combo takes the pad; the hold button's release still reaches the game.
fresh(); combo();
check('PN7 the hold press passes (the game has it)', press('d58'), false);
check('PN8 the combo press is blocked', press('d59'), true);
check('PN9 the pad is ours', pad.active(), true);
check('PN10 the nav flags are set', flags, true);
check('PN11 the combo release is blocked', lift('d59'), true);
check('PN12 the hold release PASSES -- the game saw its press', lift('d58'), false);

-- 3. Nothing was on screen: the quick menu is asked for. A window up: focus it.
pad.tick(host);
check('PN13 no window up: open the quick menu', pad._st.openQuick, true);
check('PN14 ...and no focus request', ui._padFocus, nil);
fresh(); combo(); visible = true; open();
check('PN15 main window up: focus it', ui._padFocus, true);
check('PN16 ...and no quick menu', pad._st.openQuick, false);

-- 4. Ours: d-pad and binds are fed and blocked; unbound buttons are blocked too.
fresh(); combo(); open(); fed = {};
check('PN17 d-pad down is blocked', pad.onDpadAngle(18000), true);
check('PN18 ...and fed', fed[1], 'ImGuiKey_GamepadDpadDown+');
check('PN19 centring is blocked', pad.onDpadAngle(65535), true);
check('PN20 ...and released', fed[2], 'ImGuiKey_GamepadDpadDown-');
pad.onDpadAngle(4500);
check('PN21 a diagonal is two directions', fed[3] .. fed[4], 'ImGuiKey_GamepadDpadUp+ImGuiKey_GamepadDpadRight+');
pad.onDpadAngle(9000);
check('PN22 sliding off a diagonal releases one', fed[5], 'ImGuiKey_GamepadDpadUp-');
pad.onDpadAngle(-1); fed = {};
check('PN23 confirm (default d49) is blocked', press('d49'), true);
check('PN24 ...and fed', fed[1], 'ImGuiKey_GamepadFaceDown+');
lift('d49');
check('PN25 an unbound button is still blocked', press('d60'), true);
check('PN26 ...and feeds nothing', #fed, 2);
lift('d60');
press('d53'); lift('d53'); press('d52'); lift('d52');
check('PN27 next / previous tab', tabs[1] .. ',' .. tabs[2], '1,-1');

-- 5. The hold button's own job waits for its release, so the closing combo
--    does not also fire it.
fresh(); pad.applySaved('on=1;combo=d52+d59');
press('d52'); press('d59'); lift('d59'); lift('d52'); pad.tick(host);
check('PN28 held with L1 as the hold button', pad.active(), true);
press('d52');
check('PN29 the hold press alone switches nothing yet', #tabs, 0);
lift('d52');
check('PN30 ...its release does', tabs[1], -1);
press('d52');
check('PN31 the closing combo is blocked', press('d59'), true);
check('PN32 ...gives the pad back', pad.active(), false);
check('PN33 ...and does not switch a tab', #tabs, 1);
check('PN34 the nav flags are cleared', flags, false);

-- 6. The combo closes what the pad session opened, and only that.
fresh(); combo(); open();
press('d58'); press('d59'); pad.tick(host);
check('PN35 combo close: the quick menu is told to close', ui._tpClose, 2);
check('PN36 the main window was not up: stays shut', visible, false);
pad.tick(host); pad.tick(host);
check('PN37 the close request expires', ui._tpClose, nil);
fresh(); combo(); visible = true; open();
press('d58'); press('d59'); pad.tick(host);
check('PN38 the main window was up before: left up', visible, true);
fresh(); combo(); open(); visible = true;        -- opened from the quick menu
press('d58'); press('d59'); pad.tick(host);
check('PN39 a main window the session opened is closed', visible, false);

-- 7. Held keys are let go when the pad goes back.
fresh(); combo(); open(); fed = {};
press('d49'); press('d58'); press('d59');
check('PN40 a key still down is released to ImGui', fed[#fed], 'ImGuiKey_GamepadFaceDown-');

-- 8. Nothing focused: the pad goes back by itself, after the grace, screen untouched.
--    "Focused" is a dlac window's own focus: ImGui's NavActive stays true on
--    another addon's window and must not hold the pad.
fresh(); combo(); clock = 10; open(); visible = true;
navActive = true; pad.tick(host);
check('PN41 idle: still ours inside the grace', pad.active(), true);
clock = 10 + pad.IDLE_S + 0.01; pad.tick(host);
check('PN42 idle past the grace: released (NavActive or not)', pad.active(), false);
pad.tick(host);
check('PN43 an idle release closes nothing', visible, true);
check('PN44 ...and asks no menu to close', ui._tpClose, nil);
fresh(); combo(); clock = 5; open();
draw(MAIN, true); clock = 5.3; pad.tick(host);
clock = 5.5; pad.tick(host);
check('PN45 focus coming back restarts the grace', pad.active(), true);
-- A focused dlac window holds the pad for as long as it is focused.
fresh(); combo(); open();
for i = 1, 5 do draw(MAIN, true); clock = i; pad.tick(host); end
check('PN81 a focused dlac window holds the pad', pad.active(), true);
-- A HUD piece (no title) holds nothing by itself; a popup under it does.
fresh(); combo(); open();
for i = 1, 3 do draw('##dlac_tray', 'self'); clock = i; pad.tick(host); end
check('PN82 focus resting on a HUD piece: released', pad.active(), false);
fresh(); combo(); open();
for i = 1, 3 do draw(HOST, 'popup'); clock = i; pad.tick(host); end
check('PN83 the quick menu under the pad host holds the pad', pad.active(), true);
check('PN84 window keys', pad._winKey(MAIN) .. ' ' .. pad._winKey(HOBBY) .. ' ' .. pad._winKey('##dlac_tray') .. ' ' .. pad._winKey('Plain'),
      'ffxi_lac_gearui dlac_hobbybar dlac_tray Plain');

-- 8b. The quick menu closes (a row was used, or Back): a window that was
--     already up gets the focus back and does NOT hold the pad; a window the
--     row opened does.
local quickFrame = pad.quickDrawn;      -- what drawHost reports each frame
fresh(); combo(); draw(HOBBY, false); pad.tick(host); open();
draw(HOBBY, false); draw(HOST, 'popup'); quickFrame(true); clock = 1; pad.tick(host);
check('PN85a the open quick menu holds the pad', pad.active(), true);
draw(HOBBY, false); draw(HOST, 'popup'); quickFrame(true); clock = 1.5; pad.tick(host);
draw(HOBBY, true); quickFrame(false); clock = 2; pad.tick(host);      -- row used: focus falls back
draw(HOBBY, true); clock = 3; pad.tick(host);
draw(HOBBY, true); clock = 4; pad.tick(host);
check('PN85 focus back on a window that was already up: released', pad.active(), false);
fresh(); combo(); draw(HOBBY, false); pad.tick(host); open();
draw(HOBBY, false); draw(HOST, 'popup'); quickFrame(true); clock = 1; pad.tick(host);
-- The row is used: the menu draws one last time, and the window it opened is
-- drawn LATER IN THAT SAME FRAME (the frame order of ui\gearui).
draw(HOBBY, false); draw(HOST, 'popup'); quickFrame(true); draw(LOCK, true); clock = 1.1; pad.tick(host);
draw(HOBBY, false); quickFrame(false); draw(LOCK, true); clock = 1.3; pad.tick(host);
draw(HOBBY, false); draw(LOCK, true); clock = 9; pad.tick(host);
check('PN86 a window the row opened holds the pad', pad.active(), true);
draw(LOCK, false); draw(HOBBY, true); clock = 10; pad.tick(host);
draw(LOCK, false); draw(HOBBY, true); clock = 11; pad.tick(host);
check('PN87 ...after which the older window can hold it too', pad.active(), true);

-- 8c. The closing combo shuts the windows the session opened -- not the ones
--     up before it, and never the hobby bar.
fresh(); combo(); draw(MAIN, false); pad.tick(host); open();
local lockOpen, mainOpen, hobbyOpen = { true }, { true }, { true };
draw(MAIN, true, mainOpen); draw(LOCK, false, lockOpen); draw(HOBBY, false, hobbyOpen); pad.tick(host);
press('d58'); press('d59'); pad.tick(host);
draw(MAIN, false, mainOpen); draw(LOCK, false, lockOpen); draw(HOBBY, false, hobbyOpen);
check('PN88 combo close: the lockstyle window the session opened is shut', lockOpen[1], false);
check('PN89 ...the window that was up before stays', mainOpen[1], true);
check('PN90 ...and so does the hobby bar', hobbyOpen[1], true);
lockOpen[1] = true;
draw(LOCK, false, lockOpen);
check('PN91 the close is asked once', lockOpen[1], true);
lift('d59'); lift('d58');
-- A window that never drew again must not be shut when it is opened later.
fresh(); combo(); open();
draw(LOCK, true, lockOpen); pad.tick(host);
press('d58'); press('d59');
for _ = 1, 5 do pad.tick(host); end
draw(LOCK, false, lockOpen);
check('PN92 a stale close request expires', lockOpen[1], true);
-- An idle release closes no window.
fresh(); combo(); open();
draw(LOCK, true, lockOpen); clock = 1; pad.tick(host);
clock = 2; pad.tick(host); clock = 3; pad.tick(host);
draw(LOCK, false, lockOpen);
check('PN93 an idle release shuts nothing', lockOpen[1] == true and pad.active() == false, true);

-- 8d. Next window (default: button 4 on a DirectInput pad, Y on XInput).
fresh(); combo(); draw(MAIN, false); draw(HOBBY, false); pad.tick(host); visible = true; open();
draw(MAIN, true); draw(HOBBY, false); pad.tick(host);
focusAsked = 0;
check('PN94 the button is blocked', press('d51'), true); lift('d51');
draw(MAIN, true); draw(HOBBY, false);
check('PN95 the next window is asked to take the focus', focusAsked, 1);
pad.tick(host);
draw(MAIN, false); draw(HOBBY, true); pad.tick(host);
press('d51'); lift('d51'); focusAsked = 0;
pad.windowHook(false, HOBBY); pad.windowHook(false, MAIN);
check('PN96 ...and it wraps back to the first', focusAsked, 1);
fresh(); combo(); draw(MAIN, false); pad.tick(host); visible = true; open();
draw(MAIN, true); pad.tick(host);
check('PN97 one window only: nothing to step to', pad.cycleWindow(), false);
fresh(); combo(); draw(HOBBY, false); pad.tick(host); open();
draw(HOBBY, false); quickFrame(true); pad.tick(host);
press('d51'); lift('d51'); pad.tick(host);
check('PN98 from the quick menu: the menu is told to close', ui._tpClose, 2);
draw(HOBBY, true); quickFrame(false); clock = 1; pad.tick(host);
draw(HOBBY, true); clock = 5; pad.tick(host);
check('PN99 ...and the window stepped to holds the pad', pad.active(), true);
check('PN100 XInput default', (function() fresh(); pad.applySaved('on=1;combo=x6+x7'); return pad.tokenName(pad.bindOf('win')); end)(), 'Y');

-- 8f. The game's interface is hidden (Scroll Lock): the pad goes back at once,
--     whatever claims the focus.
fresh(); combo(); open();
draw(MAIN, true); pad.tick(host);
hudHidden = true; draw(MAIN, true); pad.tick(host);
check('PN108 interface hidden: released at once', pad.active(), false);
hudHidden = false;

-- 8g. /dl pad state names the holder, the windows and the last button's job.
fresh(); combo(); draw(MAIN, false); draw(HOBBY, false); pad.tick(host); visible = true; open();
draw(MAIN, true); draw(HOBBY, false); pad.tick(host);
press('d51'); lift('d51');
check('PN109 the state line', pad.stateLine(),
      'controller state -- dlac has it; focused: ffxi_lac_gearui; windows: ffxi_lac_gearui, dlac_hobbybar; last button: button 4 (d51) = win');

-- 8e. A binding that cannot answer "is this window focused" falls back to
--     ImGui's NavActive, as before.
fresh(); combo(); open();
pad.io.windowFocused = function() return nil; end
draw(MAIN, true); navActive = true; clock = 1; pad.tick(host); clock = 9; pad.tick(host);
check('PN101 no focus query: NavActive holds the pad', pad.active(), true);
navActive = false; clock = 10; pad.tick(host); clock = 11; pad.tick(host);
check('PN102 ...and its loss releases it', pad.active(), false);
pad.io.windowFocused = focusSeam;

-- 9. Capture: hold one, press another; a lone press binds a single button.
-- Capture works with the switch off, and binding the combo switches it on.
fresh();
pad.beginCapture('combo');
press('d55'); press('d48');
check('PN45a the combo is captured with the switch off', pad.export(), 'on=1;combo=d55+d48');
check('PN45b ...which turned the switch on', pad.enabled(), true);
fresh(); pad.applySaved('on=1');
pad.beginCapture('combo');
check('PN46 capture blocks the pad', press('d58'), true);
check('PN47 first button noted', pad.capture().first, 'd58');
lift('d58');
check('PN48 letting go starts over', pad.capture().first, nil);
press('d58'); press('d59');
check('PN49 the combo is captured', pad.comboName(), 'hold button 11, press button 12');
check('PN50 capture is over', pad.capture(), nil);
pad.tick(host);
check('PN51 a new bind is saved', ui._flagsDirty, true);
lift('d59'); lift('d58');
pad.beginCapture('ok');
pad.onDpadAngle(0);
check('PN52 the d-pad cannot be a bind', pad.capture() ~= nil, true);
pad.onDpadAngle(-1);
press('d51');
check('PN53 confirm rebound', pad.bindOf('ok'), 'd51');
lift('d51');
pad.clear('ok');
check('PN54 cleared: back to the default', pad.bindOf('ok'), 'd49');
-- A button held when capture starts was the game's: its release still passes.
fresh(); pad.applySaved('on=1');
press('d70'); pad.beginCapture('ok');
check('PN55 a pre-held button releases to the game mid-capture', lift('d70'), false);

-- 10. Defaults follow the interface the combo came from.
fresh(); pad.applySaved('on=1;combo=x6+x7');
check('PN56 XInput combo: confirm is A', pad.tokenName(pad.bindOf('ok')), 'A');
check('PN57 XInput names', pad.comboName(), 'hold L3, press R3');

-- 11. The uiflags round trip, and garbage in.
fresh(); pad.applySaved('on=1;combo=d58+d59;ok=d51;next=d55');
check('PN58 export', pad.export(), 'on=1;combo=d58+d59;ok=d51;next=d55');
pad.applySaved('on=1;combo=d58+d58;ok=dU;back=zz;bogus=1');
check('PN59 a combo of one button is refused', pad.combo(), nil);
check('PN60 a d-pad bind is refused', pad.bindOf('ok'), 'x12');
check('PN61 a malformed token is refused', pad.export(), 'on=1');
pad.applySaved('');
check('PN62 empty = off', pad.enabled(), false);

-- 12. Switching it off mid-session gives the pad back.
fresh(); combo(); open();
pad.setEnabled(false);
check('PN63 off: released', pad.active(), false);

-- 13. Flattening: only while the pad is ours, only the listed panels.
fresh(); combo();
check('PN64 pad at rest: nothing is flattened', pad.flatten('##ffxilac_setleft'), false);
open();
check('PN65 the Sets panel', pad.flatten('##ffxilac_setleft'), true);
check('PN66 a slot grid (suffix)', pad.flatten('##sets_grid'), true);
check('PN67 an add row (prefix + id)', pad.flatten('##addrow_12345_3'), true);
check('PN68 an unlisted panel', pad.flatten('##ffxilac_stats'), false);
pad._st.flattenAll = true;
check('PN69 the field switch flattens everything', pad.flatten('##ffxilac_stats'), true);

-- 14. The compat shim's flag helper and hook.
local compat = require('dlac\\lib\\imguicompat');
check('PN70 flag added', compat._withFlag(1, 256), 257);
check('PN71 flag already set', compat._withFlag(257, 256), 257);
check('PN72 the hook is installed', compat.navFlatten, pad.flatten);

-- 15. The tab step wraps and needs an open tab.
package.loaded.imgui = setmetatable({ BeginTabItem = function(label) return label == 'B'; end,
                                      EndTabItem = function() end },
                                    { __index = function() return function() return false; end; end });
package.loaded['dlac\\ui\\uihost'] = nil;
local uihost = require('dlac\\ui\\uihost');
for _, l in ipairs({ 'A', 'B', 'C' }) do
    uihost.register({ name = l, tabs = { { label = l, render = function() end } } });
end
check('PN73 no open tab yet: no step', uihost.cycleTab(1), false);
uihost.renderTabs(function() end);
check('PN74 the open tab is seen', uihost.openTab(), 'B');
uihost.cycleTab(1);
check('PN75 next', uihost.pendingTab(), 'C');
uihost.cycleTab(-1);
check('PN76 previous', uihost.pendingTab(), 'A');

-- 16. Moving the cursor by hand: the widget that receives it ignores a press
--     for two frames, then answers again.
fresh();
check('PN77 nothing moved: a press counts', pad.pressAllowed(), true);
pad.tick(host);
pad.focusHere();
check('PN78 the frame the cursor moved: ignored', pad.pressAllowed(), false);
pad.tick(host); pad.tick(host);
check('PN79 two frames on: still ignored', pad.pressAllowed(), false);
pad.tick(host);
check('PN80 the third frame: a press counts again', pad.pressAllowed(), true);

-- 17. The compat shim's Begin wrapper: the hook hears every window before and
--     after, and the arguments reach ImGui exactly as given.
do
    local argc, heard = {}, {};
    local fake = { ImageWithBg = function() end,
                   Begin = function(...) argc[#argc + 1] = select('#', ...); return true; end };
    package.loaded.imgui = fake;
    compat.installed, compat.wrapped = false, false;
    check('PN103 the shim wraps a new binding', compat.install(), true);
    compat.navWindow = function(after, name, open)
        heard[#heard + 1] = (after and 'post:' or 'pre:') .. name .. (open and '+' or '');
    end
    check('PN104 Begin still answers', fake.Begin('W##k'), true);
    fake.Begin('W##k', { true }, 0);
    check('PN105 the argument count is untouched', argc[1] .. ',' .. argc[2], '1,3');
    check('PN106 the hook hears before and after', table.concat(heard, ' '), 'pre:W##k post:W##k pre:W##k+ post:W##k+');
    compat.navWindow = nil;
    fake.Begin('W##k');
    check('PN107 no hook: straight through', argc[3], 1);
    compat.navWindow = pad.windowHook;
end

print(('padnav: %d checks passed'):format(n));
