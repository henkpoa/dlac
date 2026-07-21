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
    'renderItemTooltip', 'setLabelOf',
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

-- Set display labels through the REAL catalog + shipped gearsets (the Salvage
-- field bug, Henrik 07-18: "Ares' Cuirass +4" -- the old first-piece "+N"
-- fallback read as an HQ item). Family labels must survive short-name /
-- possessive drift, +1 families must stay distinct from base, and NO label may
-- ever take the "<piece> +N" form again.
check('S41 base Salvage family label', S.setLabelOf(3), 'Ares set');
check('S42 +1 family keeps the quality mark', S.setLabelOf(81), 'Ares +1 set');
check('S43 short-name family resolves by majority', S.setLabelOf(78), 'Mdk. +1 set');
check('S44 every set label is a pair or a "... set" -- never an HQ-item shape', (function()
    local gsD = require('dlac\\data\\gearsets');
    for sid in pairs(gsD) do
        local l = S.setLabelOf(sid);
        if not (string.sub(l, -4) == ' set' or string.find(l, ' + ', 1, true) ~= nil) then
            return sid .. ': ' .. l;   -- name the offender
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
    -- AutoAmmo modules: the same imgui-less contract (ammoui's row status
    -- sits above its guard, ammowatch is pure file I/O + mutators).
    local ok4, ammoui = pcall(require, 'dlac\\ui\\ammoui');
    check('S135 ammoui loads headless', ok4 and type(ammoui) == 'table', true);
    check('S136 ammoui.maxLevel', ammoui and ammoui.maxLevel, 1);
    check('S137 ammoui.status callable without deps',
        ok4 and select(1, ammoui.status(nil)), 0);
    local ok5, amw = pcall(require, 'dlac\\feature\\ammowatch');
    check('S138 ammowatch loads under the ui tree', ok5 and type(amw) == 'table', true);
    local ok6, ebx = pcall(require, 'dlac\\feature\\eboxammo');
    check('S139 eboxammo loads headless', ok6 and type(ebx) == 'table', true);
    check('S139b headless is never a Crystal Warrior (affirmative-only gate)',
        ok6 and ebx.isCW(), false);
    local ok7, entw = pcall(require, 'dlac\\lib\\entwatch');
    check('S139c entwatch loads headless', ok7 and type(entw) == 'table', true);
    check('S139d entwatch starts with an empty registry', ok7 and #entw.debugState(), 0);
end)();

-- ---------------------------------------------------------------------------
-- 8. Automations machinery: its own module since 2026-07-18 (the noted
--    triggersui 200-local relief, extraction complete). The seams that
--    craftwatch/helmwatch/fishwatch and gearui's sync hook call must live on
--    automationsui -- and must be GONE from triggersui: a zombie forwarder
--    would split the manifest cache into two modules' copies, and the two
--    could disagree about staleness.
-- ---------------------------------------------------------------------------
(function()
    local ok, aui = pcall(require, 'dlac\\ui\\automationsui');
    check('S140 automationsui loads headless', ok and type(aui) == 'table', true);
    if not ok then return; end
    check('S141 rescanAutogear seam', type(aui.rescanAutogear), 'function');
    check('S142 manifestStale seam', type(aui.manifestStale), 'function');
    check('S143 currentFmt seam', type(aui.currentFmt), 'function');
    check('S144 manifest fmt is current (>= 8: fish ladders)',
        type(aui.currentFmt()) == 'number' and aui.currentFmt() >= 8, true);
    check('S145 renderTab entry point', type(aui.renderTab), 'function');
    -- headless no-deps safety: every entry point is a safe no-op before init/login
    check('S146 rescanAutogear is a safe no-op headless', pcall(aui.rescanAutogear), true);
    check('S147 manifestStale headless says stale (no manifest readable)',
        select(2, pcall(aui.manifestStale)), true);
    check('S148 renderTab is a safe no-op headless', pcall(aui.renderTab), true);
    -- the migration is COMPLETE: no automation seams left behind on triggersui
    local tui = require('dlac\\ui\\triggersui');
    check('S149 triggersui no longer carries rescanAutogear', tui.rescanAutogear, nil);
    check('S150 triggersui no longer carries manifestStale', tui.manifestStale, nil);
    check('S151 triggersui no longer carries renderAutomationsTab', tui.renderAutomationsTab, nil);
end)();

-- ---------------------------------------------------------------------------
-- 9. The manifest WRITER, end to end (headless): fake bags in -> autogear.lua
--    out -> re-read and assert every automation family's decisive rule. This
--    is the coverage the extraction unlocked: autoCommit lived buried in
--    triggersui behind gearui's live deps, so the fmtver-5 class of bug (the
--    writer silently aborting inside its pcall and the manifest never
--    regenerating) had no net under it. automationsui.init takes ANY deps
--    table -- so feed it a curated inventory where each pick is hand-checkable.
-- ---------------------------------------------------------------------------
(function()
    local ok, aui = pcall(require, 'dlac\\ui\\automationsui');
    if not ok then return; end   -- S140 already failed loudly
    local sep = package.config:sub(1, 1);
    local root = 'tests' .. sep .. 'tmp_autogear' .. sep;
    if sep == '\\' then os.execute('mkdir "tests\\tmp_autogear\\dlac" >nul 2>&1');
    else os.execute('mkdir -p "tests/tmp_autogear" >/dev/null 2>&1'); end

    -- One decisive case per family. We play BLM at 99 (mainLevel headless = 99).
    local INV = {
        -- iridescence: HQ beats NQ (Fire); NQ-only = tier 1 (Ice); the JOB GATE
        -- (Terra's is WHM-only on a BLM manifest -- the Foreshadow field case);
        -- universal pecking order (owned Chatoyant +2 outranks owned Iridal +1).
        { Name = 'Fire Staff',        Id = 90001, Level = 51, Slot = 'Main',  Jobs = { 'All' } },
        { Name = "Vulcan's Staff",    Id = 90002, Level = 51, Slot = 'Main',  Jobs = { 'All' } },
        { Name = 'Ice Staff',         Id = 90003, Level = 51, Slot = 'Main',  Jobs = { 'All' } },
        { Name = "Terra's Staff",     Id = 90004, Level = 51, Slot = 'Main',  Jobs = { 'WHM' } },
        { Name = 'Chatoyant Staff',   Id = 90005, Level = 75, Slot = 'Main',  Jobs = { 'All' } },
        { Name = 'Iridal Staff',      Id = 90006, Level = 71, Slot = 'Main',  Jobs = { 'All' } },
        { Name = 'Karin Obi',         Id = 90007, Level = 71, Slot = 'Waist', Jobs = { 'All' } },
        { Name = 'Hachirin-no-obi',   Id = 90008, Level = 71, Slot = 'Waist', Jobs = { 'All' } },
        -- maxmp: paired-slot dup (x2 -> BOTH ring ladders), ConvertHPtoMP
        -- counted, and a weapon battery (hold map yes, mpBest NO -- TP rule).
        { Name = 'Astral Ring',       Id = 90010, Level = 10, Slot = 'Ring',  Jobs = { 'All' },
          Stats = { MP = 12 } },
        { Name = 'Uggalepih Pendant', Id = 90011, Level = 70, Slot = 'Neck',  Jobs = { 'All' },
          Stats = { ConvertHPtoMP = 25 } },
        { Name = 'Mana Club',         Id = 90012, Level = 40, Slot = 'Main',  Jobs = { 'All' },
          Stats = { MP = 10 } },
        -- maxmp augments (fmt 12, field 07-21): the OWNED copy's augment MP
        -- and Refresh fold into mp/rf -- Hlr. Bliaut +1 reads 35+18=53 MP
        -- (and beats a flat 50), Clr. Bliaut +1 reads Refresh 1+1=2.
        { Name = 'Hlr. Bliaut +1',    Id = 90013, Level = 70, Slot = 'Body',  Jobs = { 'All' },
          Stats = { MP = 35 } },
        { Name = 'Clr. Bliaut +1',    Id = 90014, Level = 74, Slot = 'Body',  Jobs = { 'All' },
          Stats = { MP = 29, Refresh = 1 } },
        { Name = "Bunzi's Robe",      Id = 90015, Level = 74, Slot = 'Body',  Jobs = { 'All' },
          Stats = { MP = 50 } },
        -- maxmp movement yield (fmt 14): Movement+ pieces ride the mv map so
        -- the engine can let them beat a battery while MOVING.
        { Name = 'Pegasus Collar',    Id = 90016, Level = 60, Slot = 'Neck',  Jobs = { 'All' },
          Stats = { MovementSpeed = 12 } },
        -- craft: a real skill item, an anti-HQ item (BLOCKS the hq goal, tops
        -- nq), and a skill-up item (fills hq at gainFill, tops skillup).
        { Name = 'Chefs Hat',         Id = 90020, Level = 1,  Slot = 'Head',  Jobs = { 'All' },
          Stats = { CookingSkill = 1 } },
        { Name = 'Chefs Ring',        Id = 90021, Level = 1,  Slot = 'Ring',  Jobs = { 'All' },
          Stats = { AntiHQCooking = 1 } },
        { Name = 'Bonze Cape',        Id = 90022, Level = 1,  Slot = 'Back',  Jobs = { 'All' },
          Stats = { SynthSkillGain = 4 } },
        -- helm: Surveyor-major scoring + the semantic hat map (exact name).
        { Name = 'Field Tunica',      Id = 90030, Level = 1,  Slot = 'Body',  Jobs = { 'All' },
          Stats = { HELM = 2, Surveyor = 1 } },
        { Name = 'Miners Helmet',     Id = 90031, Level = 1,  Slot = 'Head',  Jobs = { 'All' },
          Stats = { Surveyor = 1 } },
        -- fish: FishingSkill-major; Main deliberately IN (fishing weapons);
        -- Range/Ammo deliberately OUT (rod and bait are fishstate picks).
        { Name = 'Fishermans Tunica', Id = 90040, Level = 1,  Slot = 'Body',  Jobs = { 'All' },
          Stats = { FishingSkill = 1 } },
        { Name = 'Halieutica',        Id = 90041, Level = 49, Slot = 'Main',  Jobs = { 'All' },
          Stats = { FishingSkill = 2 } },
        { Name = 'Halcyon Rod',       Id = 90042, Level = 1,  Slot = 'Range', Jobs = { 'All' },
          Stats = { FishingSkill = 10 } },
    };
    local byName, byId, counts = {}, {}, {};
    for _, r in ipairs(INV) do
        byName[r.Name] = r;
        byId[r.Id] = r;
        counts[r.Id] = (r.Name == 'Astral Ring') and 2 or 1;
    end
    -- The id-PIN trap (Henrik 07-21): relic stages share one display name.
    -- byName resolves 'Laevateinn' to the BASE stage (18974, NOT owned); the
    -- owned copy is the Lv75 stage 18994, reachable only through lookupById.
    -- The pinned UNIVERSAL entry must adopt it (tier 3 tops the ladder) --
    -- an unpinned name lookup would test ownership of 18974 and miss.
    local LAEV_BASE = { Name = 'Laevateinn', Id = 18974, Level = 73, Slot = 'Main', Jobs = { 'BLM' } };
    local LAEV_75   = { Name = 'Laevateinn', Id = 18994, Level = 75, Slot = 'Main', Jobs = { 'BLM' } };
    byName[LAEV_BASE.Name] = LAEV_BASE;
    byId[LAEV_BASE.Id] = LAEV_BASE; byId[LAEV_75.Id] = LAEV_75;
    counts[LAEV_75.Id] = 1;
    aui.init({
        charBase = function() return root; end,
        lookupByName = function(n) return byName[n]; end,
        lookupById = function(id) return byId[id]; end,
        ownedCounts = function() return counts; end,
        ownedList = function() return INV; end,
        allEquipList = function() return INV; end,
        haveInBags = function() return true; end,
        playerJob = function() return 'BLM'; end,
    });
    -- Private augments on the OWNED copies (fmt 12): the builder folds these
    -- through augments.ownedAugStats -- stubbed here keyed by item id.
    package.loaded['dlac\\feature\\augments'] = {
        ownedAugStats = function()
            return { [90013] = { MP = 18 }, [90014] = { Refresh = 1 } };
        end,
    };
    aui.rescanAutogear();

    local mpath = root .. 'dlac\\autogear.lua';
    local chunk = loadfile(mpath);
    check('S160 rescan wrote a loadable manifest', chunk ~= nil, true);
    if chunk == nil then return; end
    local m = chunk();
    check('S161 fmtver matches currentFmt', m.fmtver, aui.currentFmt());
    check('S162 manifestStale is false right after the write', aui.manifestStale(), false);
    check('S163 HQ staff beats NQ', m.staff and m.staff.Fire and m.staff.Fire.name .. '/' .. m.staff.Fire.tier,
        "Vulcan's Staff/2");
    check('S164 NQ-only element is tier 1', m.staff.Ice and m.staff.Ice.tier, 1);
    check('S165 JOB GATE: a WHM-only staff stays OFF a BLM manifest (the Foreshadow case)',
        m.staff.Earth, nil);
    check('S166 universal pecking order: the id-PINNED +3 relic tops +2',
        type(m.universal) == 'table' and m.universal.name .. '/' .. m.universal.tier, 'Laevateinn/3');
    check('S166b universals LADDER rides the manifest in preference order (v82/fmt 10)',
        type(m.universals) == 'table' and #m.universals == 3
        and table.concat({ m.universals[1].name, m.universals[2].name, m.universals[3].name }, '>'),
        'Laevateinn>Chatoyant Staff>Iridal Staff');
    check('S166c id-PIN adopts the OWNED Lv75 stage, not the byName base (Level proves the record)',
        m.universals[1].level, 75);
    check('S167 elemental obi picked', m.obi and m.obi.Fire and m.obi.Fire.name, 'Karin Obi');
    check('S168 universal obi picked', type(m.obiUniversal) == 'table' and m.obiUniversal.name,
        'Hachirin-no-obi');
    check('S169 mp hold map: lowercased + ConvertHPtoMP counted',
        (m.mp['uggalepih pendant'] or 0) .. '/' .. (m.mp['astral ring'] or 0) .. '/' .. (m.mp['mana club'] or 0),
        '25/12/10');
    check('S169b augment MP folds into the hold map (35+18)',
        m.mp['hlr. bliaut +1'], 53);
    check('S169c augment Refresh folds into rf (1 native + 1 aug)',
        m.rf and m.rf['clr. bliaut +1'], 2);
    check('S169d the augmented copy TOPS the body ladder (53 beats the flat 50)',
        m.mpBest.body and m.mpBest.body[1].name .. '/' .. m.mpBest.body[1].mp, 'Hlr. Bliaut +1/53');
    check('S169e the rung carries its refresh',
        (function()
            for _, r in ipairs(m.mpBest.body or {}) do
                if r.name == 'Clr. Bliaut +1' then return r.rf; end
            end
        end)(), 2);
    check('S169f movement map built (fmt 14)', m.mv and m.mv['pegasus collar'], 12);
    check('S169g movement piece with no MP stays OUT of the ladders',
        (function()
            for _, r in ipairs(m.mpBest.neck or {}) do
                if r.name == 'Pegasus Collar' then return 'in ladder'; end
            end
            return 'out';
        end)(), 'out');
    check('S169h movement-yield setting defaults off and serializes', m.mpMoveYield, false);
    check('S170 an x2 battery fills BOTH ring ladders',
        m.mpBest.ring1 and m.mpBest.ring1[1].name == 'Astral Ring'
        and m.mpBest.ring2 and m.mpBest.ring2[1].name == 'Astral Ring', true);
    check('S171 weapon batteries stay OUT of mpBest (TP preservation)', m.mpBest.main, nil);
    check('S172 craft skill gear tops its slot hq ladder',
        m.craft.head and m.craft.head.Cooking and m.craft.head.Cooking.hq
        and m.craft.head.Cooking.hq[1].name .. '/' .. m.craft.head.Cooking.hq[1].score, 'Chefs Hat/10');
    check('S173a anti-HQ gear tops the nq goal',
        m.craft.ring1 and m.craft.ring1.Cooking and m.craft.ring1.Cooking.nq
        and m.craft.ring1.Cooking.nq[1].name .. '/' .. m.craft.ring1.Cooking.nq[1].score, 'Chefs Ring/100');
    check('S173b ...and is BLOCKED from the hq goal', m.craft.ring1.Cooking.hq, nil);
    check('S174a skill-up gear fills hq at gainFill (never beats real skill gear)',
        m.craft.back and m.craft.back.Cooking and m.craft.back.Cooking.hq
        and m.craft.back.Cooking.hq[1].name .. '/' .. m.craft.back.Cooking.hq[1].score, 'Bonze Cape/1');
    check('S174b ...and tops the skillup goal at full weight',
        m.craft.back.Cooking.skillup and m.craft.back.Cooking.skillup[1].score, 40);
    check('S175 helm ladder is Surveyor-major (surv*10 + helm)',
        m.helm and m.helm.body and m.helm.body[1].name .. '/' .. m.helm.body[1].score, 'Field Tunica/12');
    check('S176 helm hat map: exact-name owned hat lands with its Surveyor',
        m.helm.hats and m.helm.hats.Mining and m.helm.hats.Mining.name .. '/' .. m.helm.hats.Mining.surv,
        'Miners Helmet/1');
    check('S177 fish ladder is FishingSkill-major (x1000)',
        m.fish and m.fish.body and m.fish.body[1].name .. '/' .. m.fish.body[1].score,
        'Fishermans Tunica/1000');
    check('S178 fishing WEAPONS ride the Main fish ladder',
        m.fish.main and m.fish.main[1].name, 'Halieutica');
    check('S179 rods stay OUT of the fish ladders (fishstate owns rod+bait)', m.fish.range, nil);
    check('S180 craftGoal is always one of the three goals',
        m.craftGoal == 'hq' or m.craftGoal == 'nq' or m.craftGoal == 'skillup', true);

    os.remove(mpath);
    if sep == '\\' then
        os.execute('rmdir "tests\\tmp_autogear\\dlac" >nul 2>&1');
        os.execute('rmdir "tests\\tmp_autogear" >nul 2>&1');
    else
        os.execute('rm -rf "tests/tmp_autogear" >/dev/null 2>&1');
    end
end)();

-- ---------------------------------------------------------------------------
-- 10. The Arbiter Priority section (ADR 0012, step 2 / issue #49): priorityui is
--     its OWN module (the helmui/fishui pattern -- keeps automationsui's local
--     budget clear), rendered from the Automations list view. Same imgui-less
--     contract: the pure display seams (SOURCE/HINT/statusText/buildRows) sit
--     above the render guard, and arbwatch (the arbstate writer) loads headless.
-- ---------------------------------------------------------------------------
(function()
    local ok, pui = pcall(require, 'dlac\\ui\\priorityui');
    check('S190 priorityui loads headless', ok and type(pui) == 'table', true);
    if not ok then return; end
    -- render lives BELOW the imgui guard (nil headless, like fishui/ammoui); the
    -- pure display seams above it are what the smoke can exercise.
    check('S191 priorityui exposes the pure display seams', type(pui.buildRows), 'function');
    -- source/control hints exist for all six claimants + the two special rows.
    check('S192 every row has a source/control hint', (function()
        for _, n in ipairs({ 'Pins', 'Locks', 'AutoAmmo', 'MaxMP', 'Craft', 'HELM', 'Fishing', 'Triggers' }) do
            if type(pui.SOURCE[n]) ~= 'string' or pui.SOURCE[n] == '' then return n; end
            if type(pui.HINT[n]) ~= 'string' or pui.HINT[n] == '' then return n .. ' (hint)'; end
        end
        return true;
    end)(), true);
    -- statusText reflects live claim state (a claiming row is not "idle/off").
    check('S193 armed craft reads as claiming', pui.statusText('Craft', { craft = true }), 'claiming: armed');
    check('S194 AutoAmmo stands down while fishing is live',
        pui.statusText('AutoAmmo', { ammo = { on = true }, fishing = true }), 'standing down: fishing live');
    check('S195 the Triggers floor is always on', pui.statusText('Triggers', {}), 'floor -- always on');
    -- buildRows marks the two special rows non-draggable, the six claimants draggable.
    local aw = require('dlac\\feature\\arbwatch');
    local rows = pui.buildRows(aw.defaultOrder(), {});
    check('S196 buildRows yields all eight rows in order', #rows, 8);
    check('S197 Locks + Triggers are non-draggable special rows', (function()
        local byName = {};
        for _, r in ipairs(rows) do byName[r.name] = r; end
        return byName.Locks.draggable == false and byName.Locks.special == true
           and byName.Triggers.draggable == false and byName.Triggers.special == true
           and byName.AutoAmmo.draggable == true;
    end)(), true);
    -- arbwatch loads under the ui tree and its pure move rule holds headless.
    check('S198 arbwatch loads headless', type(aw), 'table');
    check('S199 arbwatch.moveClaimant refuses to drag the Triggers floor',
        aw.moveClaimant(aw.defaultOrder(), 8, -1), nil);
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
