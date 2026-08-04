--[[
    bludex/ui/host.lua -- the window shell: blue theme, header with the live
    point budget, the tab row (lit/unlit buttons -- BeginTabBar is not
    field-proven in this install), and per-frame ctx wiring for the tabs.

    Frame discipline: each tab renders inside pcall; a tab error draws as text
    instead of tearing the frame. Style pushes pop on every path.
]]--

local ROOT = (...):sub(1, -#('ui\\host') - 1);       -- relocatable require base
local kit      = require(ROOT .. 'ui\\kit');
local filetex  = require(ROOT .. 'ui\\filetex');
local spellsui = require(ROOT .. 'ui\\spellsui');
local setsui   = require(ROOT .. 'ui\\setsui');
local traitsui = require(ROOT .. 'ui\\traitsui');

local M = {};

M.state = nil;

local function freshState(sets)
    return {
        open = { false, },
        tab = 'Codex',
        selectedId = nil,
        detailOpen = { false, },
        detailFocus = nil,
        editingSet = sets.new('Set 1'),
        activeSet = nil,
        addNote = nil,
        applyNote = nil,
        nameBuf = { '' },
        addBuf = { '' },
        openCat = {},
        filters = {
            text = { '' },
            category = {}, element = {}, spellType = {}, trait = {}, learned = {},
            sort = {},
        },
    };
end

function M.init(deps)
    M.deps = deps;                      -- { im, book, blu, sets, cfg, save }
    M.state = freshState(deps.sets);
    -- restore the last active saved set (matched by name -- indices shift
    -- when sets are deleted), exactly as if it had been clicked
    local want = deps.cfg.activeSetName;
    if want ~= nil and want ~= '' then
        for i, entry in ipairs(deps.cfg.sets) do
            if entry.name == want then
                M.state.activeSet = i;
                M.state.editingSet = deps.sets.clone(entry, entry.name);
                break;
            end
        end
    end
end

function M.toggle()
    if M.state then
        M.state.open[1] = not M.state.open[1];
        -- every open re-asks the server for job data (field-confirmed cure
        -- for the stale points/set structs)
        if M.state.open[1] and M.deps then M.deps.blu.refreshIfOnBlu(); end
    end
end

function M.isOpen()
    return M.state and M.state.open[1] or false;
end

local function budgetMax(deps)
    local max = deps.blu.points();
    if max then return max; end
    if deps.cfg.budgetOverride and deps.cfg.budgetOverride > 0 then
        return deps.cfg.budgetOverride;
    end
    return nil;
end

local TABS = { 'Codex', 'Sets', 'Traits' };

-- The job/level watch and auto-restore, run once per frame whether or not
-- anything renders: a level change invalidates the BLU structs like a fresh
-- login (refresh fires inside the watch), and -- if the setting is on --
-- any spells the change stripped from the last-applied set get re-added.
-- Two delayed checks so the 0x061 answer has landed before we compare.
-- The standalone render calls this itself; an EMBEDDING host (dlac's BLU
-- helper) calls it directly every frame, even while its panel is hidden.
function M.tick()
    local deps = M.deps;
    if deps == nil then return; end
    if deps.blu.watchJobState() then
        local now = os.clock();
        M.restoreChecks = { now + 2.0, now + 8.0 };
    end
    if M.restoreChecks ~= nil then
        local due = M.restoreChecks[1];
        if due ~= nil and os.clock() >= due then
            table.remove(M.restoreChecks, 1);
            if #M.restoreChecks == 0 then M.restoreChecks = nil; end
            if deps.cfg.autoRestore == true then
                local last = deps.cfg.lastApplied;
                if last ~= nil and last.ids ~= nil then
                    deps.blu.restoreMissing(last.ids, deps.book);
                end
            end
        end
    end
end

-- body theme: what embedded rendering needs (child panels + the blue
-- Selectable/combo highlight -- the default theme's Header is RED); the
-- standalone window adds its own chrome on top. Both return the push count.
local function pushBodyTheme(im)
    if not (kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor')) then return 0; end
    im.PushStyleColor(3,  { 0.06, 0.09, 0.15, 0.97 });     -- ChildBg
    im.PushStyleColor(24, { 0.16, 0.34, 0.62, 0.85 });     -- Header
    im.PushStyleColor(25, { 0.20, 0.42, 0.74, 0.85 });     -- HeaderHovered
    im.PushStyleColor(26, { 0.24, 0.48, 0.80, 1.00 });     -- HeaderActive
    return 4;
end

local function pushWindowTheme(im)
    if not (kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor')) then return 0; end
    im.PushStyleColor(2,  { 0.055, 0.075, 0.125, 0.97 });  -- WindowBg
    im.PushStyleColor(11, { 0.10, 0.18, 0.34, 1.00 });     -- TitleBgActive
    im.PushStyleColor(10, { 0.07, 0.11, 0.20, 1.00 });     -- TitleBg
    return 3 + pushBodyTheme(im);
end

-- the per-frame ctx handed to every tab (and to the detail float)
local function tabCtx(im, st, deps, embedded)
    return {
        im = im, book = deps.book, blu = deps.blu, sets = deps.sets,
        cfg = deps.cfg, save = deps.save, state = st,
        embedded = embedded == true,
        -- true once an embedding host's sanctioned float surface has run:
        -- the codex then routes Spell Info there instead of its in-panel pane
        floatWindow = deps.floatWindow == true,
        budgetMax = function() return budgetMax(deps); end,
    };
end

-- header + tab row + the active tab: everything between Begin and End,
-- shared verbatim by the standalone window and the embedded flavor.
-- `embedded` reaches the tabs through ctx: a dlac Job helper Panel may not
-- open windows itself, so the codex either uses the host's float surface
-- (renderDetailFloat below) or falls back to an in-panel pane.
local function renderBody(im, st, deps, embedded)
    -- header: logo + budget
    local logo = filetex.ui('logo-64');
    if logo ~= nil and kit.isFn(im, 'Image') then
        pcall(im.Image, logo, { 22, 22 });
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
    end
    kit.ctext(im, kit.COL.head, 'BLUDEX');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    -- the header meters are the EDITING set against the budget -- the
    -- planning numbers needed while adding from the codex. Live-vs-
    -- planned shows per-slot in the Sets tab (dimming).
    local max = budgetMax(deps);
    kit.meter(im, '   Set:', deps.sets.usedPoints(st.editingSet, deps.book), max, ' pts');
    kit.tip(im, max ~= nil
        and 'Points used by the set you are editing /\nyour total from the game client (CatsEyeXI bonuses included).'
        or 'Points used by the set you are editing.\nThe total appears when you are on BLU (or set budgetOverride).');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.meter(im, '   Slots:', deps.sets.count(st.editingSet), 20, '');
    if deps.blu.onBlu() and (deps.blu.points()) == nil then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   (live points: reading...)');
        kit.tip(im, 'The client has not filled the points struct yet.\n'
            .. 'Bludex is requesting the data from the server (the same\n'
            .. '0x061 ask the native menus send). If it stays stuck:\n'
            .. '/bludex refresh re-asks, /bludex debug shows details.');
        deps.blu.nudgePoints();
    elseif not deps.blu.onBlu() then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   (not on BLU)');
    end

    -- tab row
    local w = kit.measure(im, TABS, 90);
    for _, t in ipairs(TABS) do
        if kit.litButton(im, t, st.tab == t, w, 26) then st.tab = t; end
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
    end
    if kit.isFn(im, 'NewLine') then im.NewLine(); end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    local ctx = tabCtx(im, st, deps, embedded);
    local tabfn = (st.tab == 'Sets' and setsui.render)
        or (st.tab == 'Traits' and traitsui.render)
        or spellsui.render;
    local tok, terr = pcall(tabfn, ctx);
    if not tok then
        kit.ctext(im, kit.COL.err, 'tab error: ' .. tostring(terr));
    end
    -- The Spell Info window serves EVERY tab (codex and traits rows both
    -- open it), so it draws once here after the active tab -- except in the
    -- embedded-Panel fallback, where a Panel may not open windows (the
    -- codex's in-panel pane covers it there).
    if not ctx.embedded then
        local dok, derr = pcall(spellsui.detailWindow, ctx);
        if not dok then
            kit.ctext(im, kit.COL.err, 'detail error: ' .. tostring(derr));
        end
    end
end

-- the floating Bludex window itself (Begin/End + chrome), shared by the
-- standalone render and the dlac float surface
local function renderWindow(im, st, deps)
    if not kit.isFn(im, 'Begin') or not kit.isFn(im, 'End') then return; end
    local pushed = pushWindowTheme(im);
    if kit.isFn(im, 'SetNextWindowSizeConstraints') then
        -- 920 wide fits the measured filter row; below that the Reset button clips
        pcall(im.SetNextWindowSizeConstraints, { 920, 520 }, { 4096, 4096 });
    end
    local visible = false;
    local ok = pcall(function()
        visible = im.Begin('Bludex##bdxmain', st.open);
    end);
    if ok and visible then
        renderBody(im, st, deps, false);
    end
    if ok then im.End(); end
    if pushed > 0 then im.PopStyleColor(pushed); end
end

-- the standalone flavor (the bludex addon's own d3d_present hook)
function M.render()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil then return; end
    M.tick();
    if not st.open[1] then return; end
    renderWindow(deps.im, st, deps);
end

-- Open the window outright (the toggle flips; a launcher wants OPEN).
-- Same open-refresh as toggle: field-confirmed cure for stale structs.
function M.open()
    if M.state == nil then return; end
    if not M.state.open[1] then
        M.state.open[1] = true;
        if M.deps then M.deps.blu.refreshIfOnBlu(); end
    end
end

-- The WHOLE Bludex window through an embedding host's float surface (dlac's
-- `window` hook): the full codex/sets/traits experience in its own window,
-- alive independent of the host's main box. Self-gates on st.open -- the
-- host's Panel is the launcher. Marks the float surface live even while
-- closed, so the Panel knows the launcher flavor applies (and the Spell
-- Info window rides along exactly as in standalone, embedded = false).
-- Ticking stays with the host's beat subscription, not here.
function M.renderWindowFloat()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil or deps.im == nil then return; end
    deps.floatWindow = true;
    if not st.open[1] then return; end
    renderWindow(deps.im, st, deps);
end

-- The Spell Info window ALONE, for an embedding host's sanctioned float
-- surface (dlac's `window` contract hook, ADR 0028 amendment 2026-08-04):
-- the codex list stays in the Panel; the detail window draws from the
-- host's float site, so it survives the host's main window closing. It
-- self-gates -- spellsui.detailWindow returns unless a spell was clicked
-- open. Marks the float surface live so the embedded codex stops offering
-- its in-panel fallback pane.
function M.renderDetailFloat()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil or deps.im == nil then return; end
    deps.floatWindow = true;
    local im = deps.im;
    local pushed = pushWindowTheme(im);      -- a float owns its window chrome
    pcall(spellsui.detailWindow, tabCtx(im, st, deps, true));
    if pushed > 0 then im.PopStyleColor(pushed); end
end

-- The embedded flavor for a hosting addon's own window (dlac's BLU helper):
-- no Begin/End, no window chrome -- the body draws into whatever window or
-- child is current. The host addon calls M.init once, M.tick() every frame
-- (visible or not), and this when its panel shows. See INTEGRATION.md.
function M.renderEmbedded()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil then return; end
    local im = deps.im;
    local pushed = pushBodyTheme(im);
    local ok, err = pcall(renderBody, im, st, deps, true);
    if not ok then
        kit.ctext(im, kit.COL.err, 'bludex error: ' .. tostring(err));
    end
    if pushed > 0 then im.PopStyleColor(pushed); end
end

return M;
