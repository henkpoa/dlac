--[[
    dlac/feature/padnav.lua -- controller navigation (ticket AXI-119).

    A two-button combo (hold one, press another) hands the controller to dlac:
    the buttons stop reaching the game and drive ImGui's own gamepad
    navigation instead, so every dlac window is walkable with the d-pad. The
    same combo hands the controller back.

        padnav.onButton(token, down) -> block     the one input door
        padnav.tick(host)                         once per frame (flags, release)
        padnav.drawHost(host)                     the quick menu's pad-side host
        padnav.beginCapture(which) / capture()    the Settings "Bind" buttons
        padnav.export() / applySaved(s)           the uiflags round trip

    HOW THE PAD REACHES US. Ashita raises one event per button on both of its
    controller interfaces, and `e.blocked = true` hides that press from the
    game:
        xinput_button   e.button = bit position (0-3 d-pad, 4 Start, 5 Back,
                        6/7 L3/R3, 8/9 LB/RB, 12-15 A B X Y), e.state 1 / 0
        dinput_button   e.button = DIJOFS offset: under 32 an AXIS (sticks,
                        trigger travel), 32 the d-pad as an ANGLE in e.state
                        (0 / 9000 / 18000 / 27000, diagonals between, -1 or
                        65535 centred), 48 and up the buttons, e.state 128 / 0
    XInput ids are the same on every pad. DirectInput ids are the pad maker's,
    so nothing here hardcodes one: every bind is CAPTURED from a real press.
    A PlayStation pad arrives as DirectInput even with the game's XInput box
    ticked (field, 2026-11-17).

    Every input becomes a TOKEN -- 'x12', 'd49', 'dU' -- so the logic below
    never asks which interface it came from.

    HOW IMGUI GETS IT. ImGui 1.87+ takes key events: io:AddKeyEvent(
    ImGuiKey_GamepadDpadUp, down), with ConfigFlags.NavEnableGamepad and
    BackendFlags.HasGamepad set. Ashita 4.3 keeps both flags when an addon
    writes them and honours the events (field, same day). The flags are global
    to ImGui, so other addons' windows become walkable too while we hold the
    pad. The older ImGui (1.80, CatsEyeXI's Ashita) has no AddKeyEvent;
    supported() is false there and the whole module stays inert.

    A PRESS THE GAME SAW MUST BE RELEASED TO THE GAME. The combo's hold button
    goes down BEFORE we own the pad, so the game has it. Blocking its release
    would leave the game holding that button forever (a stuck macro palette).
    `game[token]` remembers every press we let through; its release always
    passes, whatever mode we are in.

    DirectInput axes are NOT blocked: the game would keep the last value it
    saw, and a stick tilted at the moment of the combo would run the character
    until the pad came back. XInput is polled, so there the sticks are zeroed
    (xinput_state's state_modified).

    Pure at load; every Ashita / ImGui touch is call-time behind M.io, so the
    core drives headlessly (tests\padnav.lua).
]]--

local M = {};

M.VERSION = 1;

-- ImGuiKey values of ImGui 1.92 -- the fallback for a MIXED install (new
-- Ashita.dll, old addons\libs\imgui.lua), where the lib file's globals are
-- missing. Only read when the binding itself is the new one.
local KEY_FALLBACK = {
    ImGuiKey_GamepadFaceRight = 635, ImGuiKey_GamepadFaceDown  = 637,
    ImGuiKey_GamepadDpadLeft  = 638, ImGuiKey_GamepadDpadRight = 639,
    ImGuiKey_GamepadDpadUp    = 640, ImGuiKey_GamepadDpadDown  = 641,
};
local ACTION_KEY = {
    up = 'ImGuiKey_GamepadDpadUp',     down  = 'ImGuiKey_GamepadDpadDown',
    left = 'ImGuiKey_GamepadDpadLeft', right = 'ImGuiKey_GamepadDpadRight',
    ok = 'ImGuiKey_GamepadFaceDown',   back  = 'ImGuiKey_GamepadFaceRight',
};
local NAV_GAMEPAD = 2;     -- ImGuiConfigFlags_NavEnableGamepad
local HAS_GAMEPAD = 1;     -- ImGuiBackendFlags_HasGamepad

-- Directions are fixed; everything else is a bind.
local DIRECTION = { x0 = 'up', x1 = 'down', x2 = 'left', x3 = 'right',
                    dU = 'up', dD = 'down', dL = 'left', dR = 'right' };
-- What a bind falls back to until the player captures one, by interface. The
-- XInput row is the standard; the DirectInput row is the PlayStation layout
-- (Cross, Circle, L1, R1) and only a starting guess for any other pad.
local DEFAULTS = {
    x = { ok = 'x12', back = 'x13', prev = 'x8',  next = 'x9',  win = 'x15' },
    d = { ok = 'd49', back = 'd50', prev = 'd52', next = 'd53', win = 'd51' },
};
M.BINDS = { 'ok', 'back', 'prev', 'next', 'win' };
M.BIND_LABEL = { combo = 'Open / close', ok = 'Confirm', back = 'Back',
                 prev = 'Previous tab', next = 'Next tab', win = 'Next window' };

-- Windows the closing combo never shuts, even when the pad session opened
-- them. Empty: the hobby bar was here in 21a, and Henrik could not close it
-- from the pad (2026-11-21). A bar that was up BEFORE the session still
-- stays, which is the case Dyce asked for.
M.KEEP_OPEN = {};

local FOCUS_CHILD   = 1;   -- ImGuiFocusedFlags_ChildWindows
local FOCUS_NOPOPUP = 8;   -- ImGuiFocusedFlags_NoPopupHierarchy

local XNAME = { [0] = 'D-pad up', [1] = 'D-pad down', [2] = 'D-pad left', [3] = 'D-pad right',
                [4] = 'Start', [5] = 'Back', [6] = 'L3', [7] = 'R3', [8] = 'LB', [9] = 'RB',
                [12] = 'A', [13] = 'B', [14] = 'X', [15] = 'Y' };
local DNAME = { dU = 'D-pad up', dD = 'D-pad down', dL = 'D-pad left', dR = 'D-pad right' };

-- How long the pad may sit with nothing focused before it goes back to the
-- game. Long enough to cover the frames between the combo and the menu
-- appearing, short enough that a closed menu is not felt.
M.IDLE_S = 0.4;

local st = {
    enabled  = false,
    combo    = nil,      -- { hold = token, press = token }
    binds    = {},       -- ok / back / prev / next -> token (nil = the default)
    on       = false,    -- do we hold the pad right now?
    phys     = {},       -- token -> true while physically down
    game     = {},       -- token -> true: its press went to the game
    pending  = nil,      -- the hold button, pressed while we own the pad
    fed      = {},       -- ImGui key -> true while we hold it down
    capture  = nil,      -- { which = 'combo' | bind, first = token }
    dirty    = false,    -- a bind changed; the frame beat saves it
    idleAt   = nil,      -- when nothing was focused, first seen
    openQuick = false,   -- the host should open the quick menu
    mainWasVisible = false,
    flagsSet = false,
    flattenAll = false,
    dpad     = {},       -- DirectInput d-pad: direction token -> true
    wins     = {},       -- walkable dlac windows begun since the last tick, in order
    winsPrev = {},       -- ...and the full list of the frame before
    baseline = {},       -- window key -> true: up when this pad session began
    focusFrame = nil,    -- the frame a dlac window last had the focus
    focusKey = nil,      -- ...and which one
    focusWant = nil,     -- window key to focus (the Next window button)
    quickOpen = false,   -- the quick menu this session opened is on screen
    quickKnown = nil,    -- window key -> true: was up when the quick menu closed
    closeWant = nil,     -- window key -> true: shut it at its next Begin
};
M._st = st;

-- ---------------------------------------------------------------------------
-- the io seam (replaced wholesale by the tests)
-- ---------------------------------------------------------------------------
M.io = {};

M.io.now = function() return os.clock(); end

M.io.imgui = function()
    local ok, m = pcall(require, 'imgui');
    return (ok and type(m) == 'table') and m or nil;
end

-- Is the binding the one that takes key events? The compat shim already
-- answers "new or old"; a headless state has neither and says no.
M.io.newBinding = function()
    local ok, c = pcall(require, 'dlac\\lib\\imguicompat');
    return ok and type(c) == 'table' and c.wrapped == true;
end

M.io.key = function(name)
    local v = rawget(_G, name);
    if type(v) == 'number' then return v; end
    return KEY_FALLBACK[name];
end

M.io.feed = function(key, down)
    local im = M.io.imgui();
    if im == nil then return false; end
    return (pcall(function() im.GetIO():AddKeyEvent(key, down); end));
end

M.io.navActive = function()
    local im = M.io.imgui();
    if im == nil then return false; end
    local ok, v = pcall(function() return im.GetIO().NavActive; end);
    return ok and v == true;
end

-- Is the window being drawn (the one just begun) the focused one? nil when
-- the binding cannot say, and the caller falls back to navActive.
M.io.windowFocused = function(flags)
    local im = M.io.imgui();
    if im == nil then return nil; end
    local ok, v = pcall(function() return im.IsWindowFocused(flags); end);
    if not ok then return nil; end
    return v == true;
end

-- The game's own hide-the-interface key (Scroll Lock): nothing of ours is on
-- screen, so nothing of ours may keep the pad.
M.io.hudHidden = function()
    local ok, v = pcall(function() return require('dlac\\feature\\gamehud').hidden(); end);
    return ok and v == true;
end

M.io.focusNext = function()
    local im = M.io.imgui();
    if im ~= nil then pcall(function() im.SetNextWindowFocus(); end); end
end

-- The highlight must not stay behind on a window the pad no longer drives.
M.io.hideCursor = function()
    local im = M.io.imgui();
    if im ~= nil then pcall(function() im.SetNavCursorVisible(false); end); end
end

-- Set or clear ONLY the two bits we own, so a flag another addon set stays.
M.io.setFlags = function(want)
    local im = M.io.imgui();
    if im == nil then return; end
    pcall(function()
        local io = im.GetIO();
        local cfg, bk = io.ConfigFlags, io.BackendFlags;
        local hasCfg = (cfg % (NAV_GAMEPAD * 2)) >= NAV_GAMEPAD;
        local hasBk  = (bk  % (HAS_GAMEPAD * 2)) >= HAS_GAMEPAD;
        if want then
            if not hasCfg then io.ConfigFlags = cfg + NAV_GAMEPAD; st.ownCfg = true; end
            if not hasBk  then io.BackendFlags = bk + HAS_GAMEPAD; st.ownBk = true; end
        else
            if st.ownCfg and hasCfg then io.ConfigFlags = cfg - NAV_GAMEPAD; end
            if st.ownBk  and hasBk  then io.BackendFlags = bk - HAS_GAMEPAD; end
            st.ownCfg, st.ownBk = nil, nil;
        end
    end);
end

-- Previous / next tab belongs to the focused window: the hobby bar steps its
-- hobbies, everything else steps the main window's tabs.
M.io.cycleTab = function(dir, key)
    pcall(function()
        if key == 'dlac_hobbybar' then require('dlac\\ui\\hobbybar').cycle(dir);
        else require('dlac\\ui\\uihost').cycleTab(dir); end
    end);
end

M.say = function(line)
    local said = false;
    pcall(function()
        local cf = require('dlac\\chatfmt');
        if type(cf) == 'table' and type(cf.print) == 'function' then cf.print('[dlac] ' .. line); said = true; end
    end);
    if not said then pcall(function() print('[dlac] ' .. tostring(line)); end); end
end

-- ---------------------------------------------------------------------------
-- capability, binds, names
-- ---------------------------------------------------------------------------
function M.supported()
    if M.io.newBinding() ~= true then return false; end
    return M.io.key('ImGuiKey_GamepadDpadUp') ~= nil;
end

function M.enabled() return st.enabled == true; end
function M.setEnabled(v)
    st.enabled = (v == true);
    if not st.enabled then M.release(); end
end
function M.active() return st.on == true; end
function M.combo() return st.combo; end

-- The token a bind answers to: the captured one, else the default of the
-- interface the combo was captured on.
function M.bindOf(which)
    if st.binds[which] ~= nil then return st.binds[which]; end
    local src = (st.combo ~= nil) and st.combo.press:sub(1, 1) or 'x';
    return (DEFAULTS[src] or DEFAULTS.x)[which];
end

function M.tokenName(tok)
    if type(tok) ~= 'string' then return 'not set'; end
    if DNAME[tok] ~= nil then return DNAME[tok]; end
    local src, n = tok:match('^([xd])(%d+)$');
    n = tonumber(n);
    if src == 'x' then return XNAME[n] or ('button ' .. n); end
    if src == 'd' then return 'button ' .. tostring(n - 47); end   -- DIJOFS_BUTTON0 = 48
    return tok;
end

function M.comboName()
    if st.combo == nil then return 'not set'; end
    return 'hold ' .. M.tokenName(st.combo.hold) .. ', press ' .. M.tokenName(st.combo.press);
end

local function actionOf(tok)
    if DIRECTION[tok] ~= nil then return DIRECTION[tok]; end
    for _, which in ipairs(M.BINDS) do
        if M.bindOf(which) == tok then return which; end
    end
    return nil;
end

-- ---------------------------------------------------------------------------
-- taking and giving back the pad
-- ---------------------------------------------------------------------------
local function focusHeld()
    return st.focusFrame ~= nil and st.focusFrame >= (st.frame or 0) - 1;
end

-- THE NEXT WINDOW BUTTON: the cursor steps to the next open dlac window (the
-- hobby bar, the lockstyle window, the main window), wrapping. From the quick
-- menu it closes the menu and lands on the first one.
function M.cycleWindow()
    local list = st.winsPrev;
    if #list == 0 then return false; end
    local at = 0;
    if focusHeld() then
        for i, k in ipairs(list) do
            if k == st.focusKey then at = i; end
        end
    end
    local to = list[(at % #list) + 1];
    if at ~= 0 and to == st.focusKey then return false; end    -- the only window
    st.focusWant, st.focusWantUntil = to, (st.frame or 0) + 5;
    st.quickKnown = nil;
    if st.quickOpen then st.closeQuick = true; end
    return true;
end

local function feedAction(action, down)
    local name = ACTION_KEY[action];
    if name == nil then
        local key = focusHeld() and st.focusKey or nil;
        if down and action == 'prev' then M.io.cycleTab(-1, key); end
        if down and action == 'next' then M.io.cycleTab(1, key); end
        if down and action == 'win' then M.cycleWindow(); end
        return;
    end
    local key = M.io.key(name);
    if key == nil then return; end
    if down and (action == 'up' or action == 'down' or action == 'left' or action == 'right') then
        st.lastDir = action;      -- where the cursor is heading (tooltip placement)
    end
    if down then st.fed[key] = true; else st.fed[key] = nil; end
    M.io.feed(key, down);
end

function M.take(host)
    if st.on or not st.enabled or not M.supported() then return false; end
    st.on, st.pending, st.idleAt = true, nil, nil;
    st.focusFrame, st.focusKey, st.focusWant = nil, nil, nil;
    st.quickOpen, st.quickKnown, st.closeQuick = false, nil, nil;
    st.baseline = {};
    for _, k in ipairs(st.winsPrev) do st.baseline[k] = true; end
    for _, k in ipairs(st.wins) do st.baseline[k] = true; end
    M.io.setFlags(true);
    st.takeHost = true;       -- the next tick reads what was on screen
    return true;
end

-- closeWindows: the combo closes what the pad session opened; a pad that
-- simply fell idle leaves the screen alone.
function M.release(closeWindows)
    if not st.on then return false; end
    st.on, st.pending, st.idleAt, st.openQuick = false, nil, nil, false;
    for key in pairs(st.fed) do M.io.feed(key, false); end
    st.fed = {};
    M.io.setFlags(false);
    M.io.hideCursor();
    st.closeOnRelease = (closeWindows == true);
    -- Every window that came up during the session (the lockstyle window
    -- from the quick menu, say) is shut at its next Begin, as if its own x
    -- had been clicked.
    if closeWindows == true then
        local want, any = {}, false;
        for _, list in ipairs({ st.winsPrev, st.wins }) do
            for _, k in ipairs(list) do
                if not st.baseline[k] and not M.KEEP_OPEN[k] then want[k] = true; any = true; end
            end
        end
        if any then st.closeWant, st.closeUntil = want, (st.frame or 0) + 3; end
    end
    st.focusWant, st.quickOpen, st.quickKnown, st.closeQuick = nil, false, nil, nil;
    return true;
end

-- ---------------------------------------------------------------------------
-- WHICH dlac WINDOW HAS THE FOCUS (lib\imguicompat's Begin wrapper reports
-- every dlac window through M.windowHook)
-- ---------------------------------------------------------------------------
-- ImGui's own io.NavActive is true whenever ANY window is focused, another
-- addon's included: after a Teleports row was used the focus fell to whatever
-- window was next and the pad never came back (Vellhart, Dyce, 2026-11-17 to
-- 11-21). So the pad is held on dlac's own windows only.
--
-- A window's key is its ImGui id: the part after '###', else after '##',
-- else the whole name. A window with no title ('##dlac_tray', the gauges, the
-- pad host) is a HUD piece: the focus resting on it holds nothing, but a
-- popup opened under it (the quick menu) does.
local function winKey(name)
    local k = name:match('###(.+)$') or name:match('##(.+)$');
    return k or name;
end
M._winKey = winKey;

local function winBegin(name)
    if not st.on or st.focusWant == nil or type(name) ~= 'string' then return; end
    if winKey(name) == st.focusWant then M.io.focusNext(); end
end

local function winBegun(name, open)
    if type(name) ~= 'string' then return; end
    local key = winKey(name);
    if st.closeWant ~= nil and st.closeWant[key] then
        st.closeWant[key] = nil;
        if type(open) == 'table' then open[1] = false; end
        return;
    end
    if not st.enabled then return; end
    local hud = (name:sub(1, 2) == '##');
    if not hud then st.wins[#st.wins + 1] = key; end
    if not st.on or st.noFocusApi then return; end
    local focused = M.io.windowFocused(FOCUS_CHILD);
    if focused == nil then st.noFocusApi = true; return; end
    if focused and hud then
        focused = (M.io.windowFocused(FOCUS_CHILD + FOCUS_NOPOPUP) ~= true);
    end
    if not focused then return; end
    -- A window that was already up when the quick menu closed got the focus
    -- BACK, it was not chosen: the pick is done and the pad goes home.
    if st.quickKnown ~= nil then
        if st.quickKnown[key] then return; end
        st.quickKnown = nil;
    end
    st.focusFrame, st.focusKey = (st.frame or 0), key;
end

-- ---------------------------------------------------------------------------
-- TOOLTIPS OUT OF THE WAY (Henrik, 2026-11-21)
-- ---------------------------------------------------------------------------
-- ImGui hangs a tooltip just under the item the controller's cursor is on:
-- going down a list, it covers the row you are about to reach. So it goes on
-- the side you came from -- moving down, above the item; moving up, below;
-- moving right, to the left; moving left, to the right. Where that side has
-- no room on screen, ImGui's own placement is kept. Only the item under the
-- controller's cursor is touched; a mouse hover keeps following the mouse.
M.TIP_GAP = 8;

-- PURE. r = { x0, y0, x1, y1 } of the item; w, h the tooltip; dw, dh the
-- screen. Returns x, y, pivotX, pivotY -- or nil for "leave it to ImGui".
function M.tooltipSpot(dir, r, w, h, dw, dh)
    local gap = M.TIP_GAP;
    local function inX(x) return math.max(0, math.min(x, dw - w)); end
    local function inY(y) return math.max(0, math.min(y, dh - h)); end
    if dir == 'down' then
        if r[2] - gap - h < 0 then return nil; end
        return inX(r[1]), r[2] - gap, 0, 1;
    elseif dir == 'up' then
        if r[4] + gap + h > dh then return nil; end
        return inX(r[1]), r[4] + gap, 0, 0;
    elseif dir == 'right' then
        if r[1] - gap - w < 0 then return nil; end
        return r[1] - gap, inY(r[2]), 1, 0;
    elseif dir == 'left' then
        if r[3] + gap + w > dw then return nil; end
        return r[3] + gap, inY(r[2]), 0, 0;
    end
    return nil;
end

local function pair(a, b)                 -- a binding answers x, y or one table
    if type(a) == 'table' then return a.x or a[1], a.y or a[2]; end
    return a, b;
end

-- { x0, y0, x1, y1 } of the last item, its focus, the text's size, the screen.
M.io.tipFacts = function(text)
    local im = M.io.imgui();
    if im == nil or im.IsItemFocused() ~= true then return nil; end
    local x0, y0 = pair(im.GetItemRectMin());
    local x1, y1 = pair(im.GetItemRectMax());
    local w, h = 220, 120;                -- BeginTooltip: no text, a fair guess
    if type(text) == 'string' then w, h = pair(im.CalcTextSize(text)); end
    local dw, dh = pair(im.GetIO().DisplaySize);
    if type(x0) ~= 'number' or type(y1) ~= 'number' or type(w) ~= 'number' or type(h) ~= 'number'
       or type(dw) ~= 'number' or type(dh) ~= 'number' then return nil; end
    return { x0, y0, x1, y1 }, w + 18, h + 14, dw, dh;      -- + the tooltip's own padding
end

M.io.tipPlace = function(x, y, px, py)
    local im = M.io.imgui();
    if im ~= nil then im.SetNextWindowPos({ x, y }, ImGuiCond_Always or 1, { px, py }); end
end

-- lib\imguicompat calls this just before every SetTooltip / BeginTooltip.
function M.tooltipHook(text)
    if not st.on or st.lastDir == nil then return; end
    pcall(function()
        local r, w, h, dw, dh = M.io.tipFacts(text);
        if r == nil then return; end
        local x, y, px, py = M.tooltipSpot(st.lastDir, r, w, h, dw, dh);
        if x ~= nil then M.io.tipPlace(x, y, px, py); end
    end);
end

-- after = false just before the window's Begin, true just after it.
function M.windowHook(after, name, open)
    if not st.enabled and st.closeWant == nil then return; end
    if after then pcall(winBegun, name, open); else pcall(winBegin, name); end
end

-- ---------------------------------------------------------------------------
-- capture (the Settings "Bind" buttons)
-- ---------------------------------------------------------------------------
function M.beginCapture(which)
    if which ~= 'combo' and M.BIND_LABEL[which] == nil then return false; end
    M.release();
    st.capture = { which = which };
    return true;
end
function M.cancelCapture() st.capture = nil; end
function M.capture() return st.capture; end

function M.clear(which)
    if which == 'combo' then st.combo = nil; M.release(); else st.binds[which] = nil; end
    st.dirty = true;
end

local function captureStep(tok, down)
    local c = st.capture;
    if c.which == 'combo' then
        if down then
            if c.first == nil then c.first = tok;
            elseif tok ~= c.first then
                st.combo = { hold = c.first, press = tok };
                st.capture, st.dirty = nil, true;
                -- Binding the combination IS asking for the feature: a combo
                -- that does nothing because a tick was missed reads as broken
                -- (field, 2026-11-17).
                st.enabled = true;
            end
        elseif tok == c.first then
            c.first = nil;                       -- let go before the second press
        end
    elseif down and DIRECTION[tok] == nil then   -- the d-pad stays the d-pad
        st.binds[c.which] = tok;
        st.capture, st.dirty = nil, true;
    end
    return true;
end

-- ---------------------------------------------------------------------------
-- THE INPUT DOOR. Returns true when the event must not reach the game.
-- ---------------------------------------------------------------------------
function M.onButton(tok, down)
    if type(tok) ~= 'string' then return false; end
    if down then st.phys[tok] = true; st.lastTok = tok; else st.phys[tok] = nil; end

    -- A release whose press the game saw always goes to the game.
    if not down and st.game[tok] then
        st.game[tok] = nil;
        if st.capture ~= nil then captureStep(tok, false); end
        return false;
    end

    if st.capture ~= nil then return captureStep(tok, down); end

    local c = st.combo;
    local isCombo = down and c ~= nil and tok == c.press and st.phys[c.hold] == true;

    if not st.on then
        if isCombo and M.take() then return true; end
        if down then st.game[tok] = true; end
        return false;
    end

    -- We hold the pad: nothing below reaches the game.
    if isCombo then
        st.pending = nil;
        M.release(true);
        return true;
    end
    if c ~= nil and tok == c.hold then
        -- The hold button may be half of the closing combo, so its own job
        -- (a tab switch, say) waits for the release.
        if down then st.pending = tok;
        elseif st.pending == tok then
            st.pending = nil;
            local a = actionOf(tok);
            if a ~= nil then feedAction(a, true); feedAction(a, false); end
        end
        return true;
    end
    local a = actionOf(tok);
    if a ~= nil then feedAction(a, down); end
    return true;
end

-- DirectInput's d-pad is one ANGLE; turn a change into per-direction presses.
-- Blocked only when every direction it touched was ours to block.
local ANGLE = { [0] = { 'dU' }, [4500] = { 'dU', 'dR' }, [9000] = { 'dR' }, [13500] = { 'dR', 'dD' },
                [18000] = { 'dD' }, [22500] = { 'dD', 'dL' }, [27000] = { 'dL' }, [31500] = { 'dL', 'dU' } };
function M.onDpadAngle(angle)
    local now = {};
    for _, t in ipairs(ANGLE[angle] or {}) do now[t] = true; end
    local block, touched = true, false;
    for _, t in ipairs({ 'dU', 'dR', 'dD', 'dL' }) do
        if (st.dpad[t] == true) ~= (now[t] == true) then
            touched = true;
            if not M.onButton(t, now[t] == true) then block = false; end
        end
    end
    st.dpad = now;
    if not touched then return st.on or st.capture ~= nil; end
    return block;
end

-- ---------------------------------------------------------------------------
-- the frame beat
-- ---------------------------------------------------------------------------
-- host = { ui = <gearui's ui table>, visible = fn, setVisible = fn, popup = fn }
function M.tick(host)
    st.frame = (st.frame or 0) + 1;
    if type(host) ~= 'table' or type(host.ui) ~= 'table' then return; end
    local ui = host.ui;
    if st.dirty then st.dirty = false; ui._flagsDirty = true; end

    -- The quick menu's close request lives for one full frame, then goes.
    if ui._tpClose ~= nil then
        ui._tpClose = ui._tpClose - 1;
        if ui._tpClose <= 0 then ui._tpClose = nil; end
    end

    st.winsPrev, st.wins = st.wins, {};
    if st.closeWant ~= nil and st.frame > (st.closeUntil or 0) then st.closeWant = nil; end
    if st.focusWant ~= nil and st.frame > (st.focusWantUntil or 0) then st.focusWant = nil; end
    if st.closeQuick then st.closeQuick = nil; ui._tpClose = 2; end

    if st.takeHost then
        st.takeHost = nil;
        st.mainWasVisible = (host.visible() == true);
        if st.mainWasVisible then ui._padFocus = true;      -- walk the window that is up
        else st.openQuick = true; end                       -- nothing up: the quick menu
    end

    if st.closeOnRelease ~= nil then
        if st.closeOnRelease == true then
            ui._tpClose = 2;
            if not st.mainWasVisible then host.setVisible(false); end
        end
        st.closeOnRelease = nil;
    end

    if not st.on then return; end
    if M.io.hudHidden() then M.release(false); return; end
    M.io.setFlags(true);          -- cheap, and survives anything that resets them
    -- No dlac window is focused: the menu closed (a row was used, or Back
    -- cancelled it), the window was shut, the interface is hidden. The pad
    -- goes back by itself. (IDLE_S also covers the frames between the combo
    -- and the menu drawing, and between a menu row and the window it opens.)
    local held;
    if st.noFocusApi then held = M.io.navActive(); else held = focusHeld(); end
    if held then
        st.idleAt = nil;
    else
        local now = M.io.now();
        if st.idleAt == nil then st.idleAt = now;
        elseif now - st.idleAt >= M.IDLE_S then M.release(false); end
    end
end

-- The quick menu needs a window to open under when neither the main window
-- nor the floating button is on screen. An empty, invisible one.
function M.drawHost(host)
    if not st.enabled or type(host) ~= 'table' or type(host.popup) ~= 'function' then return; end
    local im = M.io.imgui();
    if im == nil then return; end
    local flags = 0;
    for _, name in ipairs({ 'ImGuiWindowFlags_NoTitleBar', 'ImGuiWindowFlags_NoResize',
                            'ImGuiWindowFlags_NoMove', 'ImGuiWindowFlags_NoScrollbar',
                            'ImGuiWindowFlags_NoSavedSettings', 'ImGuiWindowFlags_NoBackground',
                            'ImGuiWindowFlags_NoNav', 'ImGuiWindowFlags_NoFocusOnAppearing',
                            'ImGuiWindowFlags_NoBringToFrontOnFocus', 'ImGuiWindowFlags_NoMouseInputs' }) do
        local v = rawget(_G, name);
        if type(v) == 'number' then flags = flags + v; end
    end
    pcall(im.SetNextWindowSize, { 1, 1 });
    if im.Begin('##dlac_padhost', { true }, flags) then
        if st.openQuick then
            st.openQuick = false;
            -- Never dragged: the popup would open at the mouse, wherever that
            -- was left. Open it mid-screen; a remembered spot still wins.
            if type(host.ui._tpMenuPos) ~= 'table' then
                pcall(function()
                    local ds = im.GetIO().DisplaySize;
                    local w = ds.x or ds[1]; local h = ds.y or ds[2];
                    im.SetNextWindowPos({ w * 0.5, h * 0.35 }, ImGuiCond_Appearing or 8, { 0.5, 0 });
                end);
            end
            im.OpenPopup('##dlac_teleports');
        end
        -- Is the quick menu on screen? Its body raises ui._tpDrawn. The frame
        -- it goes away, every window already up is noted: the focus falling
        -- back onto one of those is the end of the pick, not a new target.
        host.ui._tpDrawn = nil;
        pcall(host.popup);
        M.quickDrawn(host.ui._tpDrawn == true);
    end
    im.End();
    if st.on then pcall(M.drawBadge, im); end
end

-- Called once a frame with "the quick menu drew". While it is up, the windows
-- of the frame BEFORE are remembered; the frame it is gone, those are the
-- ones whose focus does not count. The frame before, and not this one: a row
-- opens its window in the very frame it closes the menu, and that window is
-- drawn after the menu, so a list taken now would hold the window the player
-- just asked for and the pad would leave it (field, 2026-11-21: the main
-- window, the hobby bar and lockstyle all opened without the pad).
function M.quickDrawn(drawn)
    if st.on and drawn then
        st.quickOpen = true;
        st.quickSeen = st.winsPrev;
    elseif st.quickOpen then
        st.quickOpen = false;
        if st.on and st.focusWant == nil then
            st.quickKnown = {};
            for _, k in ipairs(st.quickSeen or {}) do st.quickKnown[k] = true; end
        end
        st.quickSeen = nil;
    end
end

-- WHO HAS THE CONTROLLER. A small label at the top of the screen for as long
-- as the buttons are dlac's and not the game's (Dyce, 2026-11-17: nothing on
-- screen said so).
function M.drawBadge(im)
    local flags = 0;
    for _, name in ipairs({ 'ImGuiWindowFlags_NoTitleBar', 'ImGuiWindowFlags_NoResize',
                            'ImGuiWindowFlags_NoMove', 'ImGuiWindowFlags_NoScrollbar',
                            'ImGuiWindowFlags_NoSavedSettings', 'ImGuiWindowFlags_AlwaysAutoResize',
                            'ImGuiWindowFlags_NoNav', 'ImGuiWindowFlags_NoFocusOnAppearing',
                            'ImGuiWindowFlags_NoMouseInputs' }) do
        local v = rawget(_G, name);
        if type(v) == 'number' then flags = flags + v; end
    end
    pcall(function()
        local ds = im.GetIO().DisplaySize;
        local w = ds.x or ds[1];
        im.SetNextWindowPos({ w * 0.5, 6 }, ImGuiCond_Always or 1, { 0.5, 0 });
    end);
    if im.Begin('##dlac_padbadge', { true }, flags) then
        im.TextColored({ 0.45, 0.85, 1.0, 1.0 }, 'Controller: dlac');
        im.TextDisabled(M.badgeLine());
    end
    im.End();
end

function M.badgeLine()
    return M.comboName() .. ' to hand it back';
end

-- ---------------------------------------------------------------------------
-- the panels the pad walks straight through (lib\imguicompat asks per child)
-- ---------------------------------------------------------------------------
-- ImGui's navigation treats every child panel as a box to enter and leave.
-- A flattened child is walked as if its contents sat in the parent. Listed
-- by id prefix or suffix; '/dl pad flatten all' flattens every dlac child
-- for a field look at the rest.
M.FLATTEN_PREFIX = { '##ffxilac_setleft', '##ffxilac_slotlist', '##setrow_',
                     '##ffxilac_addlist', '##addrow_' };
M.FLATTEN_SUFFIX = { '_grid' };

function M.flatten(id)
    if not st.on or type(id) ~= 'string' then return false; end
    if st.flattenAll then return true; end
    for _, p in ipairs(M.FLATTEN_PREFIX) do
        if id:sub(1, #p) == p then return true; end
    end
    for _, s in ipairs(M.FLATTEN_SUFFIX) do
        if id:sub(-#s) == s then return true; end
    end
    return false;
end

-- The compat shim's BeginChild asks through this hook (it is nil, and costs
-- one comparison, on an install where this module never loaded).
pcall(function()
    local compat = require('dlac\\lib\\imguicompat');
    compat.navFlatten = M.flatten;
    compat.navWindow = M.windowHook;
    compat.navTooltip = M.tooltipHook;
end);

-- MOVING THE CURSOR BY HAND. ImGui's cursor sits on a widget id: remove the
-- row under it and the cursor falls back to the top of the window. A caller
-- that knows where it should go calls focusHere() just before that widget,
-- and gates the widget's own click on pressAllowed(). The gate is two frames
-- wide and exists for one reason: if a binding ever treated "focus this" as
-- "press this", a list that hands its cursor to the next row would empty (or
-- fill) itself in one press.
function M.focusHere()
    st.guardUntil = (st.frame or 0) + 2;
    local im = M.io.imgui();
    if im ~= nil and im.SetKeyboardFocusHere ~= nil then pcall(im.SetKeyboardFocusHere, 0); end
end
function M.pressAllowed()
    return (st.frame or 0) > (st.guardUntil or -1);
end

-- A list that should be under the cursor the moment its popup opens calls
-- this right after its first row.
function M.defaultFocusHere()
    if not st.on then return; end
    local im = M.io.imgui();
    if im ~= nil then pcall(im.SetItemDefaultFocus); end
end

-- One line for /dl pad state: who has the pad, which dlac window holds it,
-- which windows Next window can reach, and the last button with its job.
function M.stateLine()
    local list = (#st.wins >= #st.winsPrev) and st.wins or st.winsPrev;
    local last = 'none';
    if st.lastTok ~= nil then
        last = M.tokenName(st.lastTok) .. ' (' .. st.lastTok .. ') = ' .. (actionOf(st.lastTok) or 'nothing');
    end
    return ('controller state -- %s; focused: %s; windows: %s; last button: %s%s'):format(
        st.on and 'dlac has it' or 'the game has it',
        focusHeld() and tostring(st.focusKey) or 'none',
        (#list > 0) and table.concat(list, ', ') or 'none',
        last,
        st.noFocusApi and '; no focus query on this binding' or '');
end

-- ---------------------------------------------------------------------------
-- uiflags round trip:  "on=1;combo=d58+d59;ok=d49;back=d50"
-- ---------------------------------------------------------------------------
local function validTok(t) return type(t) == 'string' and (t:match('^[xd]%d+$') ~= nil or DNAME[t] ~= nil); end

function M.export()
    local parts = { 'on=' .. (st.enabled and '1' or '0') };
    if st.combo ~= nil then parts[#parts + 1] = 'combo=' .. st.combo.hold .. '+' .. st.combo.press; end
    for _, which in ipairs(M.BINDS) do
        if st.binds[which] ~= nil then parts[#parts + 1] = which .. '=' .. st.binds[which]; end
    end
    return table.concat(parts, ';');
end

function M.applySaved(s)
    if type(s) ~= 'string' then return; end
    st.enabled, st.combo, st.binds = false, nil, {};
    for k, v in s:gmatch('([%a]+)=([^;]*)') do
        if k == 'on' then st.enabled = (v == '1');
        elseif k == 'combo' then
            local h, p = v:match('^([^+]+)%+([^+]+)$');
            if validTok(h) and validTok(p) and h ~= p then st.combo = { hold = h, press = p }; end
        elseif M.BIND_LABEL[k] ~= nil and validTok(v) and DIRECTION[v] == nil then
            st.binds[k] = v;
        end
    end
end

-- Test reset.
function M._reset()
    st.enabled, st.combo, st.binds, st.on = false, nil, {}, false;
    st.phys, st.game, st.pending, st.fed, st.capture = {}, {}, nil, {}, nil;
    st.dirty, st.idleAt, st.openQuick, st.takeHost, st.closeOnRelease = false, nil, false, nil, nil;
    st.flattenAll, st.dpad, st.ownCfg, st.ownBk = false, {}, nil, nil;
    st.frame, st.guardUntil = nil, nil;
    st.wins, st.winsPrev, st.baseline = {}, {}, {};
    st.focusFrame, st.focusKey, st.focusWant, st.focusWantUntil = nil, nil, nil, nil;
    st.quickOpen, st.quickKnown, st.closeQuick, st.quickSeen = false, nil, nil, nil;
    st.closeWant, st.closeUntil, st.noFocusApi, st.mainWasVisible = nil, nil, nil, false;
    st.lastTok, st.lastDir = nil, nil;
end

-- ---------------------------------------------------------------------------
-- Ashita wiring (skipped headless: no `ashita` global)
-- ---------------------------------------------------------------------------
pcall(function()
    local ffi = require('ffi');
    pcall(function()
        ffi.cdef[[
            typedef struct { uint16_t wButtons; uint8_t bLeftTrigger; uint8_t bRightTrigger;
                             int16_t sThumbLX; int16_t sThumbLY; int16_t sThumbRX; int16_t sThumbRY;
                           } DLAC_XINPUT_GAMEPAD;
            typedef struct { uint32_t dwPacketNumber; DLAC_XINPUT_GAMEPAD Gamepad; } DLAC_XINPUT_STATE;
        ]];
    end);

    ashita.events.register('xinput_button', 'dlac-padnav-xb', function(e)
        if not st.enabled and st.capture == nil then return; end
        if M.onButton('x' .. tostring(e.button), e.state ~= 0) then e.blocked = true; end
    end);

    ashita.events.register('dinput_button', 'dlac-padnav-db', function(e)
        if not st.enabled and st.capture == nil then return; end
        local b = e.button;
        if type(b) ~= 'number' or b < 32 then return; end        -- an axis: the game keeps it
        if b < 48 then
            if b == 32 and M.onDpadAngle(e.state) then e.blocked = true; end
            return;
        end
        if M.onButton('d' .. tostring(b), e.state ~= 0) then e.blocked = true; end
    end);

    -- The polled XInput state: buttons, triggers and sticks read as untouched
    -- while we hold the pad.
    ashita.events.register('xinput_state', 'dlac-padnav-xs', function(e)
        if not st.on or e.state_modified == nil then return; end
        pcall(function()
            local s = ffi.cast('DLAC_XINPUT_STATE*', e.state_modified);
            s.Gamepad.wButtons = 0;
            s.Gamepad.bLeftTrigger, s.Gamepad.bRightTrigger = 0, 0;
            s.Gamepad.sThumbLX, s.Gamepad.sThumbLY = 0, 0;
            s.Gamepad.sThumbRX, s.Gamepad.sThumbRY = 0, 0;
        end);
    end);

    -- /dl pad            what is bound, and whether this client can do it
    -- /dl pad state      who has the pad, the focused window, the last button
    -- /dl pad flatten all|off   field switch: walk through EVERY dlac panel
    ashita.events.register('command', 'dlac-padnav', function(e)
        local args = e.command:args();
        if #args < 2 then return; end
        local head = args[1]:lower();
        if (head ~= '/dl' and head ~= '/dlac') or args[2]:lower() ~= 'pad' then return; end
        e.blocked = true;
        if (args[3] or ''):lower() == 'flatten' then
            st.flattenAll = ((args[4] or ''):lower() == 'all');
            M.say('controller: ' .. (st.flattenAll and 'walking straight through every panel (this session).'
                                                    or 'walking through the listed panels only.'));
            return;
        end
        if not M.supported() then
            M.say('controller navigation is not available on this Ashita yet.');
            return;
        end
        -- /dl pad state: what the pad session sees right now (field debug).
        if (args[3] or ''):lower() == 'state' then
            M.say(M.stateLine());
            return;
        end
        M.say(('controller navigation %s -- open/close: %s; confirm: %s; back: %s; tabs: %s / %s; next window: %s.'):format(
            st.enabled and 'ON' or 'OFF', M.comboName(), M.tokenName(M.bindOf('ok')),
            M.tokenName(M.bindOf('back')), M.tokenName(M.bindOf('prev')), M.tokenName(M.bindOf('next')),
            M.tokenName(M.bindOf('win'))));
    end);

    ashita.events.register('unload', 'dlac-padnav-unload', function()
        M.release();
    end);
end);

return M;
