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
-- Groups is a SECTION inside the Triggers tab (under Modes), not a standalone tab:
-- no 'groups' host module, but triggersui exposes the section renderer.
check('S5b groups is a Triggers section, not a tab',
    host.get('groups') == nil and type(require('dlac\\ui\\triggersui').renderGroups) == 'function', true);
-- G4 (issue #30): the Import Lua Table(s) transform resolves under the addon require shim (the
-- same path triggersui uses) and parses a pasted table headlessly.
do
    local giok, gi = pcall(require, 'dlac\\gear\\groupimport');
    check('S5c groupimport resolves via require shim', giok and type(gi.parse), 'function');
    if giok then
        local g = gi.parse("STR_VIT = T{'Quad. Continuum', }");
        check('S5d groupimport parses a pasted table', type(g) == 'table' and g.STR_VIT and g.STR_VIT[1], 'Quad. Continuum');
    end
end

local labels = {};
for _, name in ipairs({ 'equipped', 'sets', 'triggers', 'automations', 'groups' }) do
    local m = host.get(name);
    if m ~= nil and type(m.tabs) == 'table' then
        for _, t in ipairs(m.tabs) do labels[#labels + 1] = t.label; end
    end
end
check('S6 tab count', #labels, 5);
check('S7 tab order 1', labels[1], 'Equipped');
check('S8 tab order 2', labels[2], 'All Equipment');
check('S9 tab order 3', labels[3], 'Sets');
check('S10 tab order 4', labels[4], 'Triggers');
check('S10b tab order 5 (Automations right of Triggers)', labels[5], 'Automations');

-- every registered tab render must be callable
for i, l in ipairs(labels) do
    local found = false;
    for _, name in ipairs({ 'equipped', 'sets', 'triggers', 'automations', 'groups' }) do
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
-- 5. lockstyle "Show gear I don't own" -- the two wires, through the REAL
--    gearui + REAL catalog. Same reason as S14-16: gearui hands these over
--    inside a pcall that prints NOTHING on failure, so a mis-referenced upvalue
--    would not crash -- the picker would just quietly never leave gear.lua and
--    every catalog row would read as "not owned". That is a silent no-op, which
--    is exactly the class this file exists to catch.
-- ---------------------------------------------------------------------------
check('S17 allEquip is wired: browse-all leaves gear.lua behind',
    #lockstyle._listFor('Body', '', true) > #lockstyle._listFor('Body', ''), true);
check('S18 browse-all still filters by slot', (function()
    for _, r in ipairs(lockstyle._listFor('Body', '', true)) do
        if r.Slot ~= 'Body' then return false; end
    end
    return true;
end)(), true);

-- Henrik's bug, pinned against the REAL shipped catalog (07-15): "you can see
-- hand, leg, feet, head pieces even though you are choosing a body piece."
--
-- CatsEyeXI's item DB carries 259 UNIMPLEMENTED rows -- jobs=0, MId=0, and `slot`
-- left at its default 32, which decodes to Body -- so 258 crossbows/bows/boots
-- landed in the Body bucket. It is fixed in BOTH layers, and both are tested
-- because they fail independently:
--   * DATA (S21): apicrawl.py now skips stub rows, so catalog.lua ships clean.
--     A re-crawl with an older apicrawl would silently put them back.
--   * PICKER (S22/S23): the look filter refuses modelless rows regardless. This
--     layer must hold even on a dirty catalog, and it also covers the 15 REAL
--     body items that have no model (Hexed gear) -- those legitimately stay in
--     the catalog for their stats but can never be styled.
local allEquip = S.buildAllEquip();
check('S21 DATA: the shipped catalog carries no unimplemented stub rows', (function()
    for _, r in ipairs(allEquip) do
        -- the stub signature: filed under Body, no model. A real modelless Body
        -- item (Hexed gear) is fine -- the giveaways are these known names.
        if r.Name == 'Gletis Crossbow' or r.Name == 'Mpacas Bow'
           or r.Name == 'Amini Bottillons +2' or r.Name == 'Pinaka' then
            return r.Name .. ' (' .. tostring(r.Slot) .. ') -- re-crawl with the current apicrawl.py';
        end
    end
    return true;
end)(), true);

local bodyAll = lockstyle._listFor('Body', '', true);
check('S22 PICKER: every offered Body piece has a look (no no-op picks)', (function()
    for _, r in ipairs(bodyAll) do
        local m = tonumber(r.Model);
        if m == nil or m == 0 then return r.Name; end   -- name, so a failure says WHICH
    end
    return true;
end)(), true);
check('S23 PICKER: nothing the server mis-files under Body is offered', (function()
    for _, r in ipairs(bodyAll) do
        if r.Name == 'Gletis Crossbow' or r.Name == 'Amini Bottillons +2' then return r.Name; end
    end
    return true;
end)(), true);
check('S24 real body pieces survived the clean-up (Amini Caban has a genuine model)', (function()
    for _, r in ipairs(bodyAll) do if r.Name == 'Amini Caban' then return true; end end
    return false;
end)(), true);
check('S25 the Body bucket is still a real library, not gutted', #bodyAll > 1400, true);

-- THE APOSTROPHE BRIDGE, end to end on real data: the catalog spells it
-- "Arhats Gi" (the API drops apostrophes) and gear.lua spells it "Arhat's Gi".
-- Ids agree -- 13795 -- so ownership must be decided by Id, and the picker must
-- store YOUR spelling or the engine cannot resolve the saved set at apply time.
package.loaded['dlac\\gear'].Body = package.loaded['dlac\\gear'].Body or {};
package.loaded['dlac\\gear'].Body.Arhat = { Name = "Arhat's Gi", Id = 13795, Level = 60 };
check('S19 ownedById is wired: a catalog row resolves to YOUR record, by Id',
    (lockstyle._ownedRec({ Name = 'Arhats Gi', Id = 13795 }) or {}).Name, "Arhat's Gi");
check('S20 gear you really do not own stays unowned',
    lockstyle._ownedRec({ Name = 'Royal Cloak', Id = 13796 }), nil);

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

    -- SHIFT+DRAG. The key read itself is a Win32 GetKeyState call and cannot run
    -- headless, so drive it through fg.shiftHeld -- what these cover is the LATCH
    -- and the click suppression, which is the logic that actually broke.
    local heldShift = false;
    fg.shiftHeld = function() return heldShift; end
    check('S55 floatgear exposes the shift seam', type(fg.shiftHeld), 'function');

    -- THE bug that killed shift+drag for five rounds, guarded white-box because it
    -- cannot be caught behaviourally here (the test stubs renderSlotGrid, so there
    -- is no BeginChild and no child window to be hovered).
    --
    -- The real grid lives in a BeginChild, so ImGui's hovered window is the CHILD
    -- and IsWindowHovered() defaults to an EXACT window match -> false forever.
    -- ChildWindows is the only flag that fixes it (libs/imgui.lua:324). If someone
    -- "simplifies" these flags, the drag dies silently and looks like a dead key.
    local hoverFlags = nil;
    local moved = nil;
    IM.SetWindowPos = function(p) moved = p; end
    IM.IsWindowHovered = function(f) hoverFlags = f; return true; end
    IM.GetMouseDragDelta = function() return 5, 7; end
    popupOpen = false;

    local CHILDWINDOWS, ALLOWACTIVE = 1, 32;   -- libs/imgui.lua bits 0 and 5
    check('S72 the drag hover test asks about CHILD windows (the grid is a BeginChild)',
        fg._HOVER_FLAGS % (CHILDWINDOWS * 2) >= CHILDWINDOWS, true);
    check('S73 ...and allows a held button (you are dragging: an item IS active)',
        math.floor(fg._HOVER_FLAGS / ALLOWACTIVE) % 2, 1);

    -- shift NOT held: a click must not move the window
    heldShift = false;
    IM.IsMouseClicked = function() return true; end
    IM.IsMouseDown    = function() return true; end
    moved = nil;
    pcall(fg.render);
    check('S56 no shift: a click does not drag the window', moved, nil);
    balanced('S57 no-shift click');

    -- shift held + press: the drag latches and the window follows the delta
    heldShift = true;
    moved = nil;
    local rok3 = pcall(fg.render);
    check('S58 render runs while shift-dragging', rok3, true);
    check('S59 shift+press moves the window by the drag delta',
        type(moved) == 'table' and moved[1] == 15 and moved[2] == 27, true);  -- 10+5, 20+7
    balanced('S60 shift-drag');

    -- the latch outlives Shift: equipmon needs it only to START, and the button
    -- fires on RELEASE, by which time the key may already be back up
    heldShift = false;                               -- released mid-drag
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

    -- KEYLESS MOVE MODE: drags with NO shift at all. This is the route that has to
    -- work when key detection does not, so it gets its own coverage -- including
    -- the trap it could easily introduce: right-click must stay live, or the menu
    -- that turns move mode OFF is unreachable and you are stranded in it.
    local rmb = nil;
    local gridOpts = nil;
    Sx.renderSlotGrid = function(_, _, _, _, _, onClick, _, _, opts)
        gridOpts = opts;
        if opts ~= nil and opts.onRightClick ~= nil then opts.onRightClick('Head'); end
        if onClick ~= nil then onClick('Head'); end     -- a LEFT click on a slot
    end
    -- turn move mode on the way the menu does
    popupOpen = true;
    IM.Selectable = function(label) return label == 'Move window'; end
    pcall(fg.render);
    IM.Selectable = function() return false; end
    popupOpen = false;

    heldShift = false;                                  -- NO shift from here on
    moved = nil; rmb = nil;
    IM.IsMouseDown = function() return true; end
    pcall(fg.render);
    check('S66 move mode drags with no shift held', type(moved), 'table');
    check('S67 move mode paints the boxes gold (the only "grabbable" cue there is)',
        type(gridOpts) == 'table' and type(gridOpts.boxColorOf) == 'function'
            and gridOpts.boxColorOf({ label = 'Head' }) ~= nil, true);
    balanced('S68 move mode');


    -- the strand test: right-click must still reach the menu while move mode is on
    Sx.renderSlotGrid = function(_, _, _, _, _, onClick, _, _, opts)
        if opts ~= nil and opts.onRightClick ~= nil then rmb = true; opts.onRightClick('Head'); end
    end
    rmb = nil;
    pcall(fg.render);
    check('S69 right-click stays live in move mode (or you cannot leave it)', rmb, true);

    -- and leaving it via "Done moving" restores normal dragging behaviour.
    -- Release first: you cannot click a menu item while still holding the button,
    -- and a latch left set here would keep dragging (which the code now also
    -- clears explicitly, belt and braces).
    IM.IsMouseDown = function() return false; end
    pcall(fg.render);
    popupOpen = true;
    IM.Selectable = function(label) return label == 'Done moving'; end
    pcall(fg.render);
    IM.Selectable = function() return false; end
    popupOpen = false;
    Sx.renderSlotGrid = function(_, _, _, _, _, onClick) if onClick then onClick('Head') end end
    moved = nil;
    IM.IsMouseDown = function() return true; end
    pcall(fg.render);
    check('S70 after "Done moving", a plain drag no longer moves the window', moved, nil);
    balanced('S71 move mode off');
    IM.IsMouseDown = function() return false; end
    pcall(fg.render);

    -- "yellow christmas lights" (Henrik): Shift is held constantly in normal play
    -- (running, macros), so it must NOT light the grid on its own -- only when it
    -- could ACTUALLY start a drag, i.e. the cursor is over the window.
    --
    -- Runs here, after S70/S71, precisely because move mode is off by then: dropped
    -- in earlier it would have had to turn move mode off itself, and S69's "right
    -- click stays live IN MOVE MODE" would then have passed while testing nothing.
    Sx.renderSlotGrid = function(_, _, _, _, _, _, _, _, opts) gridOpts = opts; end
    local function cueWith(shiftHeld, hovered)
        gridOpts = nil;
        heldShift = shiftHeld;
        IM.IsWindowHovered = function() return hovered; end
        pcall(fg.render);
        if type(gridOpts) ~= 'table' or type(gridOpts.boxColorOf) ~= 'function' then
            return 'NO-GRID';        -- distinct from nil: a stub that never ran would
        end                          -- otherwise make S74/S75 pass for free
        return gridOpts.boxColorOf({ label = 'Head' });
    end
    check('S74 shift away from the window lights NOTHING', cueWith(true, false), nil);
    check('S75 no shift over the window lights nothing',    cueWith(false, true), nil);
    check('S76 shift OVER the window shows the grab cue',   cueWith(true, true) ~= nil, true);
    heldShift = false;
    IM.IsWindowHovered = function(f) hoverFlags = f; return true; end

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
-- 7. Fishing modules load headless (imgui-less: fishui/fishbar return their
--    pure stubs; fishui's coverage/status sit ABOVE the guard on purpose so
--    the Automations row works even before any render).
-- ---------------------------------------------------------------------------
(function()
    local ok1, fishui = pcall(require, 'dlac\\ui\\fishui');
    check('S130 fishui loads headless', ok1 and type(fishui) == 'table', true);
    check('S131 fishui.maxLevel', fishui and fishui.maxLevel, 4);
    check('S132 fishui.status callable without deps',
        ok1 and select(1, fishui.status(nil)), 0);
    local ok2, fishbar = pcall(require, 'dlac\\ui\\fishbar');
    check('S133 fishbar loads headless', ok2 and type(fishbar) == 'table', true);
    local ok3, fw = pcall(require, 'dlac\\feature\\fishwatch');
    check('S134 fishwatch loads under the ui tree', ok3 and type(fw) == 'table', true);
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
