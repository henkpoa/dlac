-- Headless smoke-load of the UI chunk: gearui + uihost + itemicons + equippedui
-- (+ every module they pull in). Run from the dlac addon root:
--     lua tests\smoke_ui.lua
--
-- This is a LOAD test, not a render test: it catches the two failure classes
-- imgui-less CI can catch --
--   1. the LuaJIT/Lua 200-local-per-chunk cap (a load-time crash no parser warns
--      about; gearui used to sit at exactly 200/200), and
--   2. load-order breakage in the uihost registry (services provided after a
--      module captured them, tabs missing or out of order).
-- Render paths still need an in-game check (imgui is nil here by design).

-- ---------------------------------------------------------------------------
-- environment stubs (the run_tests.lua pattern; must exist BEFORE any require)
-- ---------------------------------------------------------------------------
-- Resolve require('dlac\\ui\\X') to .\ui\X.lua regardless of where the checkout lives
-- (a plain '..\?.lua' path only works when the repo sits at Ashita\addons\dlac --
-- it broke in a git-worktree verification run). The '\' -> '/' swap keeps the folder-
-- qualified module names loadable off Windows too, where '\' is not a separator.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel == nil then return nil; end
    local chunk = loadfile((rel:gsub('\\', '/')) .. '.lua');
    if chunk == nil then return nil; end
    return chunk;
end);

-- The event stub RECORDS handlers rather than dropping them: floatgear's shift
-- tracking is a 'key' (WNDPROC) handler, and section 6 drives it directly -- the
-- transition-bit test in there is easy to get backwards and worth exercising.
local HANDLERS = {};
ashita = {
    events = {
        register = function(evt, name, fn)
            HANDLERS[evt] = HANDLERS[evt] or {};
            HANDLERS[evt][name] = fn;
        end,
        unregister = function(evt, name)
            if HANDLERS[evt] ~= nil then HANDLERS[evt][name] = nil; end
        end,
    },
};
gData = { GetPlayer = function() return nil; end };
AshitaCore = nil;                                        -- every load-time touch must be guarded

-- LuaJIT 'bit' shim for plain Lua 5.3+ (gearui hard-requires it)
package.loaded['bit'] = {
    band   = function(a, b) return a & b; end,
    bor    = function(a, b) return a | b; end,
    bxor   = function(a, b) return a ~ b; end,
    bnot   = function(a) return ~a; end,
    lshift = function(a, n) return a << n; end,
    rshift = function(a, n) return a >> n; end,
    arshift= function(a, n) return a >> n; end,
};

local failures, count = {}, 0;
local function check(name, got, want)
    count = count + 1;
    if got ~= want then
        failures[#failures + 1] = string.format('%s: got %s, want %s', name, tostring(got), tostring(want));
    end
end

-- ---------------------------------------------------------------------------
-- 1. the whole UI chunk must LOAD headlessly
-- ---------------------------------------------------------------------------
local ok, gearui = pcall(require, 'dlac\\ui\\gearui');
check('S1 gearui loads headless', ok, true);
if not ok then
    print('gearui load error: ' .. tostring(gearui));
    print(string.format('FAIL -- %d of %d checks failed', #failures, count));
    os.exit(1);
end
check('S2 gearui returns module table', type(gearui), 'table');

-- ---------------------------------------------------------------------------
-- 2. uihost registry: every tab present, in the canonical order
-- ---------------------------------------------------------------------------
local host = require('dlac\\ui\\uihost');
check('S3 equipped module registered', host.get('equipped') ~= nil, true);
check('S4 sets module registered',     host.get('sets') ~= nil, true);
check('S5 triggers module registered', host.get('triggers') ~= nil, true);

local labels = {};
for _, name in ipairs({ 'equipped', 'sets', 'triggers' }) do
    local m = host.get(name);
    if m ~= nil and type(m.tabs) == 'table' then
        for _, t in ipairs(m.tabs) do labels[#labels + 1] = t.label; end
    end
end
check('S6 tab count', #labels, 4);
check('S7 tab order 1', labels[1], 'Equipped');
check('S8 tab order 2', labels[2], 'All Equipment');
check('S9 tab order 3', labels[3], 'Sets');
check('S10 tab order 4', labels[4], 'Triggers');

-- every registered tab render must be callable
for i, l in ipairs(labels) do
    local found = false;
    for _, name in ipairs({ 'equipped', 'sets', 'triggers' }) do
        local m = host.get(name);
        if m ~= nil then
            for _, t in ipairs(m.tabs or {}) do
                if t.label == l and type(t.render) == 'function' then found = true; end
            end
        end
    end
    check('S11.' .. i .. ' tab "' .. l .. '" render is a function', found, true);
end

-- the sets module also carries the floating Stat-weights window
local setsMod = host.get('sets');
check('S13 weights window registered', setsMod ~= nil and type(setsMod.window) == 'table'
    and type(setsMod.window.render) == 'function', true);

-- The floating equipment window (floatgear). gearui requires it inside a pcall
-- that only PRINTS on failure, so without these checks a broken module would sail
-- through the whole suite as a silent no-op window.
--
-- It is deliberately NOT a uihost `window`: those render inside drawWindow, which
-- returns early when the main box is shut, and this window's whole purpose is to
-- stay up while you play. It renders from gearui's d3d_present instead (the
-- lockstyle pattern), so what must hold is that requiring it yields a render fn.
-- (S30+ -- the lockstyle section below already owns S14-S16)
local fgOk, fgMod = pcall(require, 'dlac\\ui\\floatgear');
check('S30 floatgear loads headless', fgOk, true);
check('S31 floatgear exposes render', fgOk and type(fgMod.render) == 'function', true);
check('S32 floatgear registers NO uihost window (it must outlive the main box)',
    host.get('floatgear'), nil);
-- the submenu probe must resolve to a boolean at load, never nil/error: it decides
-- cascade vs drill-down (BeginMenu itself is field-confirmed working, 07-15)
check('S33 floatgear probed the BeginMenu binding', type(fgMod.hasMenu), 'boolean');

-- Scale clamp. uiflags.lua is a plain Lua file a player can hand-edit, and the
-- loader stores gfscale RAW -- so scale() is the only thing standing between a
-- typo'd 0 and a window with no way back through the GUI.
check('S34 floatgear publishes itself for the size slider',
    host.services.floatgear ~= nil, true);
check('S35 default scale is 1.0 (matches the Equipped tab box size)', fgMod.scale(), 1.0);
host.services.ui._gfScale = 0;
check('S36 a zero scale clamps to the minimum', fgMod.scale(), fgMod.SCALE_MIN);
host.services.ui._gfScale = -5;
check('S37 a negative scale clamps to the minimum', fgMod.scale(), fgMod.SCALE_MIN);
host.services.ui._gfScale = 99;
check('S38 an absurd scale clamps to the maximum', fgMod.scale(), fgMod.SCALE_MAX);
host.services.ui._gfScale = 'wat';
check('S39 a non-number scale falls back to 1.0', fgMod.scale(), 1.0);
host.services.ui._gfScale = 1.75;
check('S40 an in-range scale passes through', fgMod.scale(), 1.75);
host.services.ui._gfScale = nil;

-- ---------------------------------------------------------------------------
-- 3. services contract: what equippedui (and future modules) capture at load
-- ---------------------------------------------------------------------------
local S = host.services;
for _, k in ipairs({
    'ui', 'COL', 'EQUIP_SLOTS', 'GEAR_OF', 'SLOT_ORDER', 'SLOT_TREE_ORDER', 'CAT_ORDER',
    'effStats', 'isUsable', 'lookupById', 'lookupByName', 'displayName',
    'buildOwned', 'buildAllEquip', 'ownedAugMap',
    'candidatesForSlot', 'subCandidatePool', 'subFilter', 'sortForDisplay',
    'parseSearch', 'itemSearchMatch',
    'getEquippedId', 'equipToSlot', 'engineLocks', 'lacSlot', 'lockMirrorDirty',
    'wornSetTotals', 'renderStatsPanel', 'renderSlotGrid', 'renderSortCombo',
    'renderItemTooltip',
}) do
    check('S12 service ' .. k, S[k] ~= nil, true);
end

-- ---------------------------------------------------------------------------
-- 4. lockstyle look preview: model-id resolution through the FULL live chain
--    (owned rec -> gearui catalogById -> flattenGear record -> catalog Model).
--    This is not a unit test on purpose: the field bug that blanked the preview
--    hid in flattenGear's record construction, which every unit-level test
--    bypassed. Uses the REAL repo catalog gearui just loaded.
-- ---------------------------------------------------------------------------
local lockstyle = require('dlac\\feature\\lockstyle');
check('S14 lockstyle _modelOf seam', type(lockstyle._modelOf), 'function');
-- an "owned" record the way gear.lua carries it: Name + Id, NO Model of its own
package.loaded['dlac\\gear'].NameToObject['Acantha Shavers'] =
    { Name = 'Acantha Shavers', Id = 18761 };
check('S15 owned item resolves a model via the catalog by Id',
    lockstyle._modelOf('Acantha Shavers'), 509);
check('S16 unknown item resolves to nil, no error', lockstyle._modelOf('No Such Thing'), nil);

-- ---------------------------------------------------------------------------
-- 6. IMGUI STACK BALANCE for the floating window (S50+) -- a RENDER test.
--
--    Why this exists: dlac shipped an EXCEPTION_ACCESS_VIOLATION in Present
--    (e85cc43) from one PopStyleVar too many -- a push added without removing an
--    older pop. A style-stack underflow is not a Lua error; it is native UB
--    inside ImGui that no pcall catches and that takes the whole client down.
--    550 green checks could not see it, because nothing here ever rendered.
--
--    So: stub imgui, re-require floatgear so it captures the stub, and drive
--    M.render for real, counting pushes against pops. This does not prove the
--    window LOOKS right -- only that it cannot corrupt ImGui's stacks, which is
--    the failure that costs Henrik a crash instead of a bug report.
-- ---------------------------------------------------------------------------
;(function()
    local depth = { var = 0, col = 0, win = 0, child = 0, popup = 0, menu = 0 };
    local popupOpen = false;
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'SetNextWindowPos', 'SetNextWindowSize', 'SetNextWindowSizeConstraints',
        'Separator', 'Text', 'TextColored', 'TextWrapped', 'SameLine', 'Dummy', 'Image',
        'PushItemWidth', 'PopItemWidth', 'OpenPopup', 'CloseCurrentPopup', 'SetTooltip',
        'PushID', 'PopID', 'ResetMouseDragDelta', 'SetWindowPos', 'SetCursorScreenPos',
        'Spacing', 'InputText', 'SetScrollHereY', 'PushTextWrapPos', 'PopTextWrapPos' }) do
        IM[n] = nop;
    end
    IM.PushStyleVar   = function() depth.var = depth.var + 1; end
    IM.PopStyleVar    = function(n) depth.var = depth.var - (tonumber(n) or 1); end
    IM.PushStyleColor = function() depth.col = depth.col + 1; end
    IM.PopStyleColor  = function(n) depth.col = depth.col - (tonumber(n) or 1); end
    IM.Begin      = function() depth.win = depth.win + 1; return true; end
    IM['End']     = function() depth.win = depth.win - 1; end
    IM.BeginChild = function() depth.child = depth.child + 1; return true; end
    IM.EndChild   = function() depth.child = depth.child - 1; end
    IM.BeginPopup = function() if popupOpen then depth.popup = depth.popup + 1; end return popupOpen; end
    IM.EndPopup   = function() depth.popup = depth.popup - 1; end
    IM.BeginMenu  = function() return false; end          -- cascade shut: the common frame
    IM.EndMenu    = function() depth.menu = depth.menu - 1; end
    for _, n in ipairs({ 'Button', 'ImageButton', 'SmallButton', 'Selectable', 'MenuItem',
        'Checkbox', 'SliderFloat', 'IsItemHovered', 'IsWindowHovered', 'IsMouseDragging',
        'IsMouseClicked', 'IsItemClicked', 'IsItemActive', 'IsMouseDown', 'IsMouseReleased' }) do
        IM[n] = function() return false; end
    end
    IM.GetIO              = function() return { KeyShift = false }; end
    IM.GetWindowPos       = function() return 10, 20; end
    IM.GetCursorScreenPos = function() return 0, 0; end
    IM.GetItemRectMin     = function() return 0, 0; end
    IM.GetMouseDragDelta  = function() return 0, 0; end
    IM.GetColorU32        = function() return 0; end
    IM.CalcTextSize       = function() return 10, 10; end
    IM.GetContentRegionAvail       = function() return 400, 400; end
    IM.GetTextLineHeightWithSpacing = function() return 14; end
    IM.GetWindowDrawList  = function()
        return { AddCircleFilled = nop, AddRectFilled = nop, AddRect = nop, AddLine = nop };
    end

    package.loaded['imgui'] = IM;
    package.loaded['dlac\\ui\\floatgear'] = nil;
    local ok, fg = pcall(require, 'dlac\\ui\\floatgear');
    check('S50 floatgear re-requires against a stub imgui', ok and type(fg.render), 'function');
    if not ok then return; end

    -- The real gearui services touch AshitaCore / d3d; swap in the few floatgear
    -- reads for fakes. renderSlotGrid stays stubbed on purpose: gearui captured
    -- the REAL (nil) imgui at its own load, so the genuine grid cannot run here --
    -- what is under test is floatgear's OWN balance, which is where the bug was.
    local Sx = host.services;
    local keep = { Sx.getPlayerInfo, Sx.buildAllEquip, Sx.getEquippedId, Sx.lookupById,
                   Sx.displayName, Sx.renderSlotGrid, Sx.candidatesForSlot };
    Sx.getPlayerInfo     = function() return 'WHM', 75; end
    Sx.buildAllEquip     = nop;
    Sx.getEquippedId     = function() return nil; end
    Sx.lookupById        = function() return nil; end
    Sx.displayName       = function() return 'X'; end
    Sx.candidatesForSlot = function() return {}; end
    Sx.renderSlotGrid    = nop;
    Sx.ui._gearFloat = true;

    local function balanced(tag)
        check(tag .. ': style VAR stack balanced',   depth.var, 0);
        check(tag .. ': style COLOR stack balanced', depth.col, 0);
        check(tag .. ': Begin/End balanced',         depth.win, 0);
        check(tag .. ': BeginPopup/EndPopup balanced', depth.popup, 0);
    end

    -- the ordinary frame: window up, menu shut. THIS is the frame that crashed.
    local rok, rerr = pcall(fg.render);
    check('S51 render runs against the stub', rok, true);
    if not rok then print('   render error: ' .. tostring(rerr)); end
    balanced('S52 popup closed');

    -- and the frame with the pin menu open (the popup + its own early returns)
    popupOpen = true;
    local rok2 = pcall(fg.render);
    check('S53 render runs with the pin menu open', rok2, true);
    balanced('S54 popup open');

    -- SHIFT+DRAG. Shift is a 'key' WNDPROC handler, not imgui IO (GetIO().KeyShift
    -- is dead outside ImGui keyboard focus -- that is what shipped broken), so
    -- drive the real handler. lparam bit 31 = transition state: 1 == key going UP.
    local keyfn = (HANDLERS['key'] or {})['dlac_floatgear_key'];
    check('S55 floatgear registered a key handler for shift', type(keyfn), 'function');
    if type(keyfn) ~= 'function' then return; end

    local moved = nil;
    IM.SetWindowPos = function(p) moved = p; end
    IM.IsWindowHovered = function() return true; end
    IM.GetMouseDragDelta = function() return 5, 7; end
    popupOpen = false;

    -- shift NOT held: a click must not move the window
    keyfn({ wparam = 0x10, lparam = 0x80000000 });   -- shift UP
    IM.IsMouseClicked = function() return true; end
    IM.IsMouseDown    = function() return true; end
    moved = nil;
    pcall(fg.render);
    check('S56 no shift: a click does not drag the window', moved, nil);
    balanced('S57 no-shift click');

    -- shift held + press: the drag latches and the window follows the delta
    keyfn({ wparam = 0x10, lparam = 0 });            -- shift DOWN
    moved = nil;
    local rok3 = pcall(fg.render);
    check('S58 render runs while shift-dragging', rok3, true);
    check('S59 shift+press moves the window by the drag delta',
        type(moved) == 'table' and moved[1] == 15 and moved[2] == 27, true);  -- 10+5, 20+7
    balanced('S60 shift-drag');

    -- the latch outlives Shift: equipmon needs it only to START, and the button
    -- fires on RELEASE, by which time the key may already be back up
    keyfn({ wparam = 0x10, lparam = 0x80000000 });   -- shift released mid-drag
    IM.IsMouseClicked = function() return false; end
    moved = nil;
    pcall(fg.render);
    check('S61 the drag survives Shift coming back up', type(moved), 'table');

    -- releasing the button ends it, and a later click no longer drags
    IM.IsMouseDown = function() return false; end
    pcall(fg.render);
    moved = nil;
    IM.IsMouseClicked = function() return true; end
    IM.IsMouseDown    = function() return true; end
    pcall(fg.render);
    check('S62 after release, a plain click does not drag', moved, nil);
    balanced('S63 drag ended');
    IM.IsMouseClicked = function() return false; end
    IM.IsMouseDown    = function() return false; end
    pcall(fg.render);

    -- window off: must draw nothing at all and touch no stack
    Sx.ui._gearFloat = false;
    pcall(fg.render);
    check('S64 a closed window opens no imgui window', depth.win, 0);
    balanced('S65 window off');

    for i, f in ipairs({ 'getPlayerInfo', 'buildAllEquip', 'getEquippedId', 'lookupById',
                         'displayName', 'renderSlotGrid', 'candidatesForSlot' }) do
        Sx[f] = keep[i];
    end
    package.loaded['imgui'] = nil;
    package.loaded['dlac\\ui\\floatgear'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- verdict
-- ---------------------------------------------------------------------------
if #failures > 0 then
    for _, f in ipairs(failures) do print('FAIL ' .. f); end
    print(string.format('FAIL -- %d of %d checks failed', #failures, count));
    os.exit(1);
end
print(string.format('OK -- %d checks passed', count));
