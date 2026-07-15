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

ashita = { events = { register = function() end, unregister = function() end } };
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
local fgOk, fgMod = pcall(require, 'dlac\\ui\\floatgear');
check('S14 floatgear loads headless', fgOk, true);
check('S15 floatgear exposes render', fgOk and type(fgMod.render) == 'function', true);
check('S16 floatgear registers NO uihost window (it must outlive the main box)',
    host.get('floatgear'), nil);
-- the submenu probe must resolve to a boolean at load, never nil/error: it decides
-- cascade vs drill-down, and BeginMenu is unproven in this binding
check('S17 floatgear probed the BeginMenu binding', type(fgMod.hasMenu), 'boolean');

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
-- verdict
-- ---------------------------------------------------------------------------
if #failures > 0 then
    for _, f in ipairs(failures) do print('FAIL ' .. f); end
    print(string.format('FAIL -- %d of %d checks failed', #failures, count));
    os.exit(1);
end
print(string.format('OK -- %d checks passed', count));
