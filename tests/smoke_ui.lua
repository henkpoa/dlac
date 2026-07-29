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
-- Blueprints (issue #65, slice 1): like Groups, a SECTION inside the Triggers tab, NOT a
-- standalone uihost tab -- no 'blueprints' host module; triggersui exposes the renderer.
check('S5e blueprints is a Triggers section, not a tab',
    host.get('blueprints') == nil and type(require('dlac\\ui\\triggersui').renderBlueprints) == 'function', true);
-- The pure core resolves under the addon require shim (the same path triggersui uses) and
-- runs headless: capture a rule, stamp it into a job's data, round-trip the library text.
do
    local bpok, bpm = pcall(require, 'dlac\\gear\\blueprintsmodel');
    check('S5f blueprintsmodel resolves via require shim', bpok and type(bpm.stamp), 'function');
    if bpok then
        local lib = {};
        bpm.add(lib, 'Midcast', { when = {}, whenAny = { { buff = 'Sleep' }, { buff = 'Lullaby' } },
                                  equip = { Ear1 = 'Toxic Earring' } });
        local out = bpm.stamp(lib[1], { Default = {} });
        check('S5g stamp lands the rule in its handler', out.Midcast[1].equip.Ear1, 'Toxic Earring');
        local lib2 = bpm.parse(bpm.serialize(lib));
        check('S5h library text round-trips', lib2 and lib2[1].name, 'Sleep or Lullaby');
        -- Slice 2 (issue #66): the text-sharing seams the Blueprints section draws -- View text
        -- (one-entry blob) and the paste-import live preview (parse + classify).
        check('S5i View text serializes one entry',
            type(bpm.serializeOne) == 'function' and bpm.serializeOne(lib[1]):find('blueprints = {', 1, true) ~= nil, true);
        local prev = bpm.previewImport(bpm.serialize(lib), {});
        check('S5j import preview lists entries before commit', prev and #prev.entries, 1);
        check('S5k import preview classifies against the library', prev and #prev.created, 1);
    end
end

local labels = {};
for _, name in ipairs({ 'equipped', 'sets', 'triggers', 'automations', 'groups', 'jobhelpers' }) do
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
check('S10b tab order 5 (Gear Helpers right of Triggers)', labels[5], 'Gear Helpers');
-- Job Helpers (issue #137): NO tab while zero modules are loaded. The loader
-- has not run here, so jobhelpersui never registered -- the acceptance case.
check('S10c Job Helpers tab ABSENT with zero modules', host.get('jobhelpers') == nil, true);

-- every registered tab render must be callable
for i, l in ipairs(labels) do
    local found = false;
    for _, name in ipairs({ 'equipped', 'sets', 'triggers', 'automations', 'groups', 'jobhelpers' }) do
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
-- 2b. The Wishlist (wishlistui, ADR 0026). Same contract as floatgear: gearui
--     requires it in a pcall that only PRINTS, and it is NOT a uihost window
--     (the Menu opens it and it stays up when the main box shuts). It also owns
--     the item context-menu BODY that equippedui's All Equipment right-click
--     draws, so a load failure would silently cost that menu too.
-- ---------------------------------------------------------------------------
local wlOk, wlMod = pcall(require, 'dlac\\ui\\wishlistui');
check('S60 wishlistui loads headless', wlOk, true);
check('S61 exposes render',            wlOk and type(wlMod.render) == 'function', true);
check('S62 exposes the shared item menu body',
    wlOk and type(wlMod.renderItemMenu) == 'function', true);
check('S63 exposes open/close/toggle',
    wlOk and type(wlMod.open) == 'function' and type(wlMod.close) == 'function'
        and type(wlMod.toggle) == 'function', true);
check('S64 registers NO uihost window (it must outlive the main box)',
    host.get('wishlist'), nil);
check('S65 starts hidden',             wlMod.visible, false);
check('S66 toggle flips it',           (function() wlMod.toggle(); local v = wlMod.visible; wlMod.close(); return v; end)(), true);
-- render must be a no-op without imgui rather than a crash (imgui is nil here).
check('S67 render is inert headless',  pcall(wlMod.render), true);
check('S68 the item menu is inert headless', pcall(wlMod.renderItemMenu, { Id = 1, Name = 'X' }, 'WHM'), true);

-- entryName: a set list element arrives in three shapes once the file has run.
check('S69 bare string element',   wlMod._entryName('Dalmatica'), 'Dalmatica');
check('S70 resolved record element', wlMod._entryName({ Name = 'Dalmatica', Level = 71 }), 'Dalmatica');
check('S71 wrapper around a record',
    wlMod._entryName({ gear = { Name = 'Dalmatica' }, minLevel = 10 }), 'Dalmatica');
check('S72 wrapper around a string',
    wlMod._entryName({ gear = 'Dalmatica', maxLevel = 50 }), 'Dalmatica');
check('S73 unrecognized element',  wlMod._entryName(42), nil);

-- The FACT half: membership is read from the set, and normalized on both sides
-- so the catalog's apostrophe-less spelling matches a set that has one.
wlMod._setDyn({ WHM = {
    Idle = { Body = { { Name = "Arhat's Gi" } }, Ring1 = { 'Rajas Ring' } },
    TP   = { Body = { 'Something Else' } },
} });
check('S74 finds the slot it sits in', wlMod.whereInSet('WHM', 'Idle', "Arhat's Gi"), 'Body');
check('S75 apostrophe-blind match',    wlMod.whereInSet('WHM', 'Idle', 'Arhats Gi'), 'Body');
check('S76 absent from the set',       wlMod.whereInSet('WHM', 'TP', 'Arhats Gi'), nil);
check('S77 unknown set',               wlMod.whereInSet('WHM', 'Nope', 'Arhats Gi'), nil);
check('S78 unknown job',               wlMod.whereInSet('BLM', 'Idle', 'Arhats Gi'), nil);
check('S79 jobs with sets listed',     #wlMod.jobsWithSets() >= 1, true);
check('S80 set names sorted',          table.concat(wlMod.setNames('WHM'), ','), 'Idle,TP');

-- linkFacts pairs each stored INTENTION with the live fact; they may disagree,
-- and a link naming a set that no longer exists says so rather than reading as
-- "not added yet".
local lf = wlMod.linkFacts({ name = 'Arhats Gi', links = {
    { job = 'WHM', set = 'Idle' }, { job = 'WHM', set = 'TP' },
    { job = 'WHM', set = 'Gone' }, { job = 'RDM' },
} });
check('S81 four facts back',        #lf, 4);
check('S82 in-set link resolved',   lf[1].inSlot, 'Body');
check('S83 linked-but-absent',      lf[2].inSlot, nil);
check('S84 ...and is not "gone"',   lf[2].gone, false);
check('S85 vanished set flagged',   lf[3].gone, true);
check('S86 job-only carries no set', lf[4].set, nil);

-- slotsFor rebuilds setmanager's ordered slots array, and appending puts the new
-- name in the right slot without disturbing the rest. EQUIP_SLOTS order, and a
-- slot the equipment model does not know is CARRIED, never dropped.
wlMod._setDyn({ WHM = { Idle = {
    Body  = { 'A' }, Ring1 = { 'B' }, Main = { 'C' }, Weird = { 'D' },
} } });
local sl = wlMod._slotsFor('WHM', 'Idle');
check('S87 four slots rebuilt', #sl, 4);
check('S88 Main comes first (EQUIP_SLOTS order)', sl[1].name, 'Main');
check('S89 unknown slot carried, last',
    sl[#sl].name, 'Weird');
local sl2 = wlMod._slotsFor('WHM', 'Idle', 'Body', 'Dalmatica');
check('S90 append lands in Body', (function()
    for _, s in ipairs(sl2) do
        if s.name == 'Body' then return #s.items == 2 and s.items[2].path == '"Dalmatica"'; end
    end
    return false;
end)(), true);
local sl3 = wlMod._slotsFor('WHM', 'Idle', 'Legs', 'New Pants');
check('S91 append can create a slot, in model order', (function()
    local names = {};
    for _, s in ipairs(sl3) do names[#names + 1] = s.name; end
    -- Legs sits after Ring1 and before the unknown tail in EQUIP_SLOTS order
    return table.concat(names, ',') == 'Main,Body,Ring1,Legs,Weird';
end)(), true);
check('S92 unknown set returns nil', wlMod._slotsFor('WHM', 'Nope'), nil);

-- The slot guard. A record whose Slot never resolved ('?') must never reach the
-- set file: it would parse, commit, and be ignored by everything forever.
check('S92a a real slot is valid',   wlMod._validSlot('Ring1'), true);
check('S92b Ring is NOT a set slot', wlMod._validSlot('Ring'),  false);   -- gear-model key
check('S92c unresolved slot refused',wlMod._validSlot('?'),     false);
check('S92d nil refused',            wlMod._validSlot(nil),     false);
check('S92e applyToSet refuses a bogus slot',
    select(1, wlMod.applyToSet({ id = 1, name = 'X' }, 'WHM', 'Idle', '?')), false);

-- Column widths are MEASURED, not hardcoded. First field report on this window
-- was "SAM / Tp_Default" printing straight through the status text beside it,
-- from a fixed SameLine(140). The label and the column that holds it must be
-- computed from the same string, and the column must grow with it.
check('S92f link label, job+set',  wlMod._linkLabel({ job = 'SAM', set = 'Tp_Default' }), 'SAM / Tp_Default');
check('S92g link label, job only', wlMod._linkLabel({ job = 'RDM' }), 'RDM');
check('S92h empty set reads as job-only', wlMod._linkLabel({ job = 'RDM', set = '' }), 'RDM');
local wideW  = wlMod._linkColW({ { job = 'SAM', set = 'Tp_Default' } });
local shortW = wlMod._linkColW({ { job = 'WHM' } });
check('S92i a long label widens the column past the old fixed 140', wideW > 140, true);
check('S92j ...and past a short one',      wideW > shortW, true);
check('S92k short labels keep the floor',  shortW, 180);
-- Field round 2 (Henrik): "twice the space... so we can handle longer set names".
-- The column must leave room for a name it has NOT been shown yet, so it clears
-- its own label by a wide margin rather than merely fitting it.
check('S92l the column DOUBLES its own label',
    wideW >= (#'SAM / Tp_Default' * 10) * 2, true);
check('S92m ...and is capped so buttons stay on screen',
    wlMod._linkColW({ { job = 'SAM', set = string.rep('x', 90) } }), 360);

-- Display order: owned first (the piece that just landed is what you came for),
-- then equipment-model slot order, then name.
local rows = wlMod._sortRows({
    { entry = { name = 'Zeta' },  own = false, slot = 'Body' },
    { entry = { name = 'Alpha' }, own = false, slot = 'Main' },
    { entry = { name = 'Beta' },  own = true,  slot = 'Feet' },
    { entry = { name = 'Aardvark' }, own = false, slot = 'Body' },
});
check('S93 owned sorts first',   rows[1].entry.name, 'Beta');
check('S94 then by slot order',  rows[2].entry.name, 'Alpha');
check('S95 then by name',        rows[3].entry.name, 'Aardvark');
wlMod._setDyn({});

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
    -- ADR 0021. Needed here and not only in NKU*: those checks install their OWN
    -- stubs onto host.services, so deleting these three from gearui's provide{}
    -- would leave both suites green while the Equipped tab's Naked switch (which
    -- guards on S.engineNaked ~= nil) silently vanished.
    'engineNaked', 'setEngineNaked', 'isNative',
    -- ADR 0022, same reasoning one row down: the Equipped tab's Lock gear switch
    -- and its LOCKED readout both guard on S.engineHeld ~= nil, so dropping it
    -- from gearui's provide{} would make them vanish in silence.
    'engineHeld',
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
-- 4b. Reserved slots (RSlot) in the GUI, through the FULL live chain: the REAL
--     catalog -> gearimport.rslotFor -> dispatch.reservedDrops, called exactly
--     the way renderSetBuilder calls it. Same reasoning as S14-16 -- gearui runs
--     this inside a pcall on the render path, so a mis-referenced upvalue would
--     not crash: the builder would just quietly stop warning, which is the one
--     failure mode nobody would ever notice by playing.
--
--     Field cases, all four confirmed against the server's item_equipment.rslot:
--     Vermillion Cloak (Body) takes Head, Decennial Coat (Body) takes Hands,
--     Kupo Suit (Body) takes Legs, Decennial Hose (Legs) takes Feet.
-- ---------------------------------------------------------------------------
S.buildAllEquip();
check('S16a rsv service provided', type(S.rsv) == 'table' and type(S.rsv.dropsIn), 'function');

check('S16b Vermillion Cloak reserves Head', S.rsv.byName('Vermillion Cloak'), 16);
check('S16c Decennial Coat reserves Hands',  S.rsv.byName('Decennial Coat'), 64);
check('S16d Kupo Suit reserves Legs',        S.rsv.byName('Kupo Suit'), 128);
check('S16e Decennial Hose reserves Feet',   S.rsv.byName('Decennial Hose'), 256);
check('S16f an ordinary piece reserves nothing', S.rsv.byName('Silver Hairpin'), 0);
check('S16g an unknown name reserves nothing',   S.rsv.byName('No Such Thing'), 0);

-- the names the tooltip prints, resolved through dispatch (not a local copy)
check('S16h mask -> slot name',  S.rsv.text(16), 'Head');
check('S16i no reservation -> nil, so no line is drawn', S.rsv.text(0), nil);

-- and the builder's own call shape: pick(label) -> item name, drops keyed by slot.
local function drives(plan)
    return S.rsv.dropsIn(function(label) return plan[label]; end) or {};
end
check('S16j the reported bug: Cloak + hat -> Head is dropped',
    drives({ Body = 'Vermillion Cloak', Head = 'Silver Hairpin' }).Head, 'Vermillion Cloak');
check('S16k ... and the reserver itself still equips',
    drives({ Body = 'Vermillion Cloak', Head = 'Silver Hairpin' }).Body, nil);
check('S16l Decennial Coat takes the Hands piece',
    drives({ Body = 'Decennial Coat', Hands = 'Cotton Gloves' }).Hands, 'Decennial Coat');
check('S16m Kupo Suit takes the Legs piece',
    drives({ Body = 'Kupo Suit', Legs = 'Leather Trousers' }).Legs, 'Kupo Suit');
check('S16n Decennial Hose takes the Feet piece',
    drives({ Legs = 'Decennial Hose', Feet = 'Bronze Leggings' }).Feet, 'Decennial Hose');
-- an EMPTY reserved slot is not a conflict: nothing is being taken away.
check('S16o Cloak with no hat -> nothing to report',
    next(drives({ Body = 'Vermillion Cloak' })), nil);
check('S16p an ordinary set -> nothing to report',
    next(drives({ Head = 'Silver Hairpin', Hands = 'Cotton Gloves' })), nil);

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
-- 6b. IMGUI STACK BALANCE for the All Equipment tab + the Wishlist window
--     (S150+) -- the same RENDER test as section 6, for the surfaces the
--     wishlist added to (ADR 0026).
--
--     Worth its own section because both grew stack-discipline work this
--     session: renderBrowseRow pushes a colour per row and must pop it on every
--     path, and the tab now opens a POPUP after the tree's EndChild -- the
--     scope rule that, done wrong, leaves a popup open across frames. Neither is
--     a Lua error when it breaks; it is native UB inside ImGui.
-- ---------------------------------------------------------------------------
;(function()
    local depth = { var = 0, col = 0, win = 0, child = 0, popup = 0 };
    local drew = { checkbox = 0, popup = 0 };
    local popupOpen = true;                 -- exercise the popup body, not just the guard
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'SetNextWindowPos', 'SetNextWindowSize', 'SetNextWindowSizeConstraints',
        'Separator', 'Text', 'TextColored', 'TextWrapped', 'SameLine', 'Dummy', 'Image',
        'PushItemWidth', 'PopItemWidth', 'OpenPopup', 'CloseCurrentPopup', 'SetTooltip',
        'PushID', 'PopID', 'Spacing', 'InputText', 'SetNextItemOpen', 'TreePop',
        'Indent', 'Unindent', 'BeginGroup', 'EndGroup', 'PushTextWrapPos', 'PopTextWrapPos' }) do
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
    IM.BeginPopup = function()
        if popupOpen then depth.popup = depth.popup + 1; drew.popup = drew.popup + 1; end
        return popupOpen;
    end
    IM.EndPopup   = function() depth.popup = depth.popup - 1; end
    IM.BeginMenu  = function() return false; end          -- cascade shut: the common frame
    IM.EndMenu    = nop;
    IM.BeginCombo = function() return false; end
    IM.EndCombo   = nop;
    IM.CollapsingHeader = function() return true; end     -- OPEN, so the rows really render
    IM.TreeNode         = function() return true; end
    IM.Checkbox   = function() drew.checkbox = drew.checkbox + 1; return false; end
    for _, n in ipairs({ 'Button', 'ImageButton', 'SmallButton', 'Selectable', 'MenuItem',
        'SliderFloat', 'IsItemHovered', 'IsWindowHovered', 'IsMouseDragging',
        'IsMouseClicked', 'IsItemClicked', 'IsItemActive', 'IsMouseDown', 'IsMouseReleased' }) do
        IM[n] = function() return false; end
    end
    IM.GetIO              = function() return { KeyShift = false }; end
    IM.GetWindowPos       = function() return 10, 20; end
    IM.GetCursorScreenPos = function() return 0, 0; end
    IM.GetItemRectMin     = function() return 0, 0; end
    IM.GetColorU32        = function() return 0; end
    -- PROPORTIONAL, unlike the other sections' constant: this window derives every
    -- column from CalcTextSize, and a stub that answers 10 for everything cannot
    -- tell a working measurement from a hardcoded one. ~10px/char is the themed
    -- font's real order of magnitude.
    IM.CalcTextSize       = function(s) return #tostring(s or '') * 10, 14; end
    IM.GetContentRegionAvail        = function() return 400, 400; end
    IM.GetTextLineHeightWithSpacing = function() return 14; end
    IM.GetWindowDrawList  = function()
        return { AddCircleFilled = nop, AddRectFilled = nop, AddRect = nop, AddLine = nop };
    end

    package.loaded['imgui'] = IM;
    -- gearfmt binds imgui at ITS OWN load through pcall(require, 'imgui') -- which
    -- yields the ERROR STRING, not nil, when imgui is absent. fmt.textWrapped then
    -- indexes a string and throws, and the pcall'd drives below would swallow it.
    -- Re-require gearfmt against THIS stub (the section-9 precedent); restored at
    -- the end so later sections keep the module they were loaded with.
    local keepFmt = package.loaded['dlac\\gear\\gearfmt'];
    package.loaded['dlac\\gear\\gearfmt'] = nil;
    package.loaded['dlac\\ui\\wishlistui'] = nil;
    package.loaded['dlac\\ui\\equippedui'] = nil;
    local wok, wui = pcall(require, 'dlac\\ui\\wishlistui');
    local eok, eui = pcall(require, 'dlac\\ui\\equippedui');
    check('S150 wishlistui re-requires against a stub imgui', wok and type(wui.render), 'function');
    check('S151 equippedui re-requires against a stub imgui',
        eok and type(eui.renderAllEquipTab), 'function');
    if not (wok and eok) then
        package.loaded['imgui'] = nil;
        package.loaded['dlac\\gear\\gearfmt'] = keepFmt;
        return;
    end

    local Sx = host.services;
    local keep = { Sx.buildOwned, Sx.buildAllEquip, Sx.isUsable, Sx.renderItemTooltip };
    -- Two rows, one owned and one not, so BOTH colour branches of renderBrowseRow
    -- run in the same frame -- the orange path is new and pushes like the rest.
    local ROWS = {
        { Id = 13795, Name = "Arhat's Gi", Level = 71, Slot = 'Body' },
        { Id = 99991, Name = 'Dalmatica',  Level = 71, Slot = 'Body' },
        { Id = 99992, Name = 'Kraken Club', Level = 99, Slot = 'Main', Category = 'Club' },
    };
    Sx.buildOwned        = function() return ROWS; end
    Sx.buildAllEquip     = function() return ROWS; end
    Sx.isUsable          = function() return true; end
    Sx.renderItemTooltip = nop;

    local function balanced(tag)
        check(tag .. ': style VAR stack balanced',     depth.var, 0);
        check(tag .. ': style COLOR stack balanced',   depth.col, 0);
        check(tag .. ': Begin/End balanced',           depth.win, 0);
        check(tag .. ': BeginChild/EndChild balanced', depth.child, 0);
        check(tag .. ': BeginPopup/EndPopup balanced', depth.popup, 0);
    end

    -- Owned view (the default) -- and the popup body drawn, since BeginPopup is
    -- forced open: that is the frame where the item menu runs for real.
    Sx.ui.showAll[1] = false;
    Sx.ui.search[1]  = '';
    Sx.ui._itemMenuRec = ROWS[1];
    local okR = pcall(eui.renderAllEquipTab, 'WHM', 75);
    check('S152 All Equipment renders (owned view)', okR, true);
    balanced('S153 all-equip owned');
    check('S154 the item context menu was drawn', drew.popup > 0, true);
    -- Both ticks are on the filter row now: "Usable now" and the new one.
    check('S155 two filter checkboxes drawn', drew.checkbox >= 2, true);

    -- Unowned view: the orange branch of every row, plus the legend change.
    drew.checkbox = 0;
    Sx.ui.showAll[1] = true;
    check('S156 All Equipment renders (unowned view)', pcall(eui.renderAllEquipTab, 'WHM', 75), true);
    balanced('S157 all-equip unowned');

    -- ...and while SEARCHING, which force-opens every section (a different path
    -- through the tree, and the one that draws the most rows).
    Sx.ui.search[1] = 'a';
    check('S158 All Equipment renders while searching',
        pcall(eui.renderAllEquipTab, 'WHM', 75), true);
    balanced('S159 all-equip searching');
    Sx.ui.search[1] = '';
    Sx.ui.showAll[1] = false;

    -- The Wishlist window, empty and populated (the populated frame runs the row
    -- renderer, the link rows and the selected-row editor).
    wui.visible = true;
    check('S160 Wishlist window renders empty', pcall(wui.render), true);
    balanced('S161 wishlist empty');
    local wl = require('dlac\\feature\\wishlist');
    wl._reset();
    wl.entries = wl.fromRaw({
        [13795] = { name = 'Arhats Gi', note = 'Sky drop', links = {
            { job = 'WHM', set = 'Idle' }, { job = 'WHM', set = 'Gone' }, { job = 'RDM' } } },
        [99991] = { name = 'Dalmatica', links = {} },
    });
    wui._setDyn({ WHM = { Idle = { Body = { { Name = 'Arhats Gi' } } } } });
    check('S162 Wishlist window renders populated', pcall(wui.render), true);
    balanced('S163 wishlist populated');
    wl._reset();
    wui._setDyn({});
    wui.visible = false;

    Sx.buildOwned, Sx.buildAllEquip, Sx.isUsable, Sx.renderItemTooltip =
        keep[1], keep[2], keep[3], keep[4];
    Sx.ui._itemMenuRec = nil;
    package.loaded['imgui'] = nil;
    package.loaded['dlac\\gear\\gearfmt'] = keepFmt;
    package.loaded['dlac\\ui\\wishlistui'] = nil;
    package.loaded['dlac\\ui\\equippedui'] = nil;
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
    -- feature/eboxammo was deleted 2026-07-27 with AutoAmmo's E-Box section, and
    -- its /dl ebox entity probe moved into eboxtrace as `/dl debug ebox scan`
    -- (auto-ammo.md Section 10.8). Pin the module that inherited it.
    local ok6, ebt = pcall(require, 'dlac\\feature\\eboxtrace');
    check('S139 eboxtrace loads headless', ok6 and type(ebt) == 'table', true);
    check('S139b the moved entity probe is reachable as "scan"',
        ok6 and ebt._word('ebox scan') == 'scan' and type(ebt.scan) == 'function', true);
    local ok7, entw = pcall(require, 'dlac\\lib\\entwatch');
    check('S139c entwatch loads headless', ok7 and type(entw) == 'table', true);
    check('S139d entwatch starts with an empty registry', ok7 and #entw.debugState(), 0);
    -- Chocobo modules: the same imgui-less contract (chocoui's row status +
    -- best-per-slot math sit above its guard; chocowatch is pure file I/O).
    local ok8, chocoui = pcall(require, 'dlac\\ui\\chocoui');
    check('S139e chocoui loads headless', ok8 and type(chocoui) == 'table', true);
    check('S139f chocoui.maxLevel', chocoui and chocoui.maxLevel, 3);
    check('S139g chocoui.status callable without deps',
        ok8 and select(1, chocoui.status(nil)), 0);
    check('S139h chocoui.totalMinutes headless is the 30-minute base',
        ok8 and select(1, chocoui.totalMinutes(nil)), 30);
    local ok9, chw = pcall(require, 'dlac\\feature\\chocowatch');
    check('S139i chocowatch loads under the ui tree', ok9 and type(chw) == 'table', true);
    -- Total riding time from OWNED pieces = 30 base + summed ChocoboRidingTime,
    -- best per slot; the reference CatsEye set (Wand 30 / Silks 10 / Torque 4 /
    -- Hose 4 / Gloves 3 / Boots 3) totals 30 + 54 = 84 minutes across the 6 slots.
    if ok8 then
        local REF = {
            { Name = 'Chocobo Wand',      Slot = 'Main',  Stats = { ChocoboRidingTime = 30 } },
            { Name = 'Orange Race Silks', Slot = 'Body',  Stats = { ChocoboRidingTime = 10 } },
            { Name = 'Chocobo Torque',    Slot = 'Neck',  Stats = { ChocoboRidingTime = 4 } },
            { Name = 'Riders Hose',       Slot = 'Legs',  Stats = { ChocoboRidingTime = 4 } },
            { Name = 'Riders Gloves',     Slot = 'Hands', Stats = { ChocoboRidingTime = 3 } },
            { Name = 'Riders Boots',      Slot = 'Feet',  Stats = { ChocoboRidingTime = 3 } },
            -- a lesser Body piece: best-per-slot must keep the Silks, not this
            { Name = 'Choc. Jack Coat',   Slot = 'Body',  Stats = { ChocoboRidingTime = 5 } },
            -- riding gear in an unlisted slot never counts (Ring is not dressed)
            { Name = 'Chocobo Ring',      Slot = 'Ring',  Stats = { ChocoboRidingTime = 5 } },
        };
        local depsRef = { ownedList = function() return REF; end, haveInBags = function() return true; end };
        local minutes, slots, best = chocoui.totalMinutes(depsRef);
        check('S139j reference set totals 84 minutes (30 base + 54)', minutes, 84);
        check('S139k all six slots covered', slots, 6);
        check('S139l best-per-slot keeps the higher Body piece', best.Body and best.Body.name, 'Orange Race Silks');
        check('S139m unlisted-slot riding gear is ignored (Ring absent)', best.Ring, nil);
        check('S139n coverage level for the full set is the max (3)', chocoui.level(depsRef), 3);
    end
    -- Dig-guide scaffold helpers (issue #97): the pure rank state + ladder +
    -- general-success seams sit ABOVE the imgui guard, so they answer headless
    -- (the tab views read rankState for grey-out even before any render).
    if ok8 then
        local rs = chocoui.rankState();
        check('S139o rankState is a well-formed table', type(rs) == 'table'
            and type(rs.rank) == 'number' and type(rs.exact) == 'boolean', true);
        check('S139p a fresh char reads as a manual estimate', rs.source == 'manual' and rs.exact, false);
        check('S139q rankLadder covers 0..10 (Amateur..Expert)', (function()
            local l = chocoui.rankLadder();
            return l[0] ~= nil and l[8] ~= nil and tostring(l[9]) == 'Veteran' and tostring(l[10]) == 'Expert';
        end)(), true);
        -- clock/generalSuccess must not error headless (no client memory).
        check('S139r clock() answers a table headless', type(chocoui.clock()), 'table');
        check('S139s generalSuccess nil without a moon read', chocoui.generalSuccess(0, nil), nil);
    end
    -- By-area tab seams (issue #98): the zone list + the composed by-area rows sit
    -- ABOVE the imgui guard too. Here digcalc.db() loads the SHIPPED digdata (26
    -- zones) through the require shim, so these exercise the real composition.
    if ok8 then
        local zl = chocoui.zoneList();
        check('S139t zoneList reads the 26 enabled zones', #zl, 26);
        -- pick a real zone (id 2 = Carpenters Landing) + a max rank so nothing is
        -- gated, and a New-moon clock so mu is defined.
        local rs = { rank = 8, exact = false, label = 'Adept' };
        local clk = { moon = { percent = 0 }, dayElement = 'Fire', weatherElement = 'Fire' };
        local rows = chocoui.areaRows(2, rs, clk);
        check('S139u areaRows returns a composed view', type(rows) == 'table'
            and type(rows.name) == 'string' and type(rows.pools) == 'table', true);
        check('S139v areaRows carries the conditional drops', type(rows.conditionals), 'table');
        check('S139w each pool row is sorted by per-dig descending', (function()
            for _, pe in ipairs(rows.pools) do
                for i = 2, #pe.items do
                    if (pe.items[i - 1].perDig or 0) < (pe.items[i].perDig or 0) then return false; end
                end
            end
            return true;
        end)(), true);
        check('S139x every row carries a grey-out gate verdict', (function()
            for _, pe in ipairs(rows.pools) do
                for _, it in ipairs(pe.items) do
                    if it.gate ~= 'ok' and it.gate ~= 'locked' and it.gate ~= 'dimmed' then return false; end
                end
            end
            return true;
        end)(), true);
        -- an unknown zone id fails soft to nil, never errors.
        check('S139y areaRows on an unknown zone -> nil', chocoui.areaRows(99999, rs, clk), nil);

        -- By-item tab seams (issue #99): the searchable item index + the composed
        -- per-item sources sit above the imgui guard too, exercised against the
        -- shipped digdata (pool items PLUS the synthesised conditionals).
        local il = chocoui.itemList();
        check('S139z itemList carries pool items + the 32 conditionals', #il, 152);
        local ilByKey = {}; for _, e in ipairs(il) do ilByKey[e.key] = e; end
        -- a pool item resolves to its zone/pool sources, priced + gated.
        local plate = ilByKey['pool:3509'];   -- Plate of Heavy Metal, 22 zones
        local iv = chocoui.itemRows(plate, rs, clk);
        check('S139aa1 itemRows returns a composed pool view with sources', type(iv) == 'table'
            and iv.kind == 'pool' and type(iv.sources) == 'table' and #iv.sources > 0, true);
        check('S139aa2 every by-item source carries a grey-out gate verdict', (function()
            for _, s in ipairs(iv.sources) do
                if s.gate ~= 'ok' and s.gate ~= 'locked' and s.gate ~= 'dimmed' then return false; end
            end
            return true;
        end)(), true);
        -- a conditional crystal resolves to an all-zone view, flagged against the clock.
        local fc = ilByKey['crystal:Fire'];
        local cv = chocoui.itemRows(fc, rs, clk);
        check('S139aa3 conditional itemRows is all-zone + active under matching weather',
            cv and cv.kind == 'conditional' and cv.allZones == true and cv.active, true);
        -- a nil selection fails soft to nil, never errors.
        check('S139aa4 itemRows(nil) -> nil', chocoui.itemRows(nil, rs, clk), nil);
    end
    -- Timing rank detection (issue #100): chocowatch inverts the first-dig zone
    -- cooldown into a rank and raises the PERSISTED one-way floor, latching at
    -- max. charDir() is nil headless, so loadState/saveState are inert no-ops (the
    -- existing S139o rankState path proves that), and these exercise the wiring on
    -- the in-memory floor.
    local cwok2, cw2 = pcall(require, 'dlac\\feature\\chocowatch');
    if cwok2 and type(cw2) == 'table' and type(cw2.recordDigTiming) == 'function' then
        cw2.rankFloor = 0;
        check('CW-T1 a 20s first dig reads Adept and raises the floor',
            cw2.recordDigTiming(20) and cw2.rankFloor, 8);
        check('CW-T2 a slower (45s) dig never lowers the floor', (function()
            local r = cw2.recordDigTiming(45); return (r == false) and cw2.rankFloor;
        end)(), 8);
        check('CW-T3 reaching Expert (10s) latches max', (function()
            local r = cw2.recordDigTiming(10);
            return r == true and cw2.rankFloor == 10 and cw2._rankMaxed() == true;
        end)(), true);
        check('CW-T4 a maxed char stops detecting', cw2.recordDigTiming(15), false);
        cw2.rankFloor = 0;   -- leave module state clean for any later reader
        -- Risk-3 gate: the timing read only trusts a REAL dig this zone visit
        -- (0x063), never a foreign chat line that merely matches a dig phrase.
        if type(cw2._digGateOpen) == 'function' then
            cw2._zoneInAt, cw2._digThisZone = nil, false;
            check('CW-T5 gate shut with no zone-in', cw2._digGateOpen(), false);
            cw2._zoneInAt = 1;   -- zoned in, but no dig yet (foreign chat scenario)
            check('CW-T6 gate shut on zone-in without a dig', cw2._digGateOpen(), false);
            cw2._digThisZone = true;   -- a real 0x063 dig completed this visit
            check('CW-T7 gate opens only after a real dig', cw2._digGateOpen(), true);
            cw2._zoneInAt, cw2._digThisZone = nil, false;   -- clean up
        end
        -- resetRank (the secret /dl choco reset): wipes manual + floor + gate.
        if type(cw2.resetRank) == 'function' then
            cw2.rankManual, cw2.rankFloor = 7, 10;   -- pretend a detected/maxed state
            cw2._zoneInAt, cw2._digThisZone = 5, true;
            cw2.resetRank();
            check('CW-T8 reset wipes manual+floor and un-latches', (function()
                return cw2.rankManual == 0 and cw2.rankFloor == 0
                    and cw2._rankMaxed() == false and cw2._digGateOpen() == false;
            end)(), true);
        end
        -- Packet-based item ratchet: the 0x02D dig-obtained packet stashes an item
        -- id; the main-thread pump ratchets it against the shipped data by id (the
        -- fix for "dug an item, rank didn't move" -- text_in never saw the line).
        if type(cw2.pumpObtains) == 'function' and type(cw2.recordObtainedById) == 'function' then
            cw2.rankManual, cw2.rankFloor = 0, 0;
            -- Bag of Fruit Seeds (id 574) is diggable (rank 2 cheapest / 4 in-zone).
            check('CW-T9 recordObtainedById raises off a diggable id', (function()
                return cw2.recordObtainedById(574) and cw2.rankFloor >= 2;
            end)(), true);
            cw2.rankFloor = 0;
            check('CW-T10 a non-diggable id never ratchets', cw2.recordObtainedById(999999), false);
            -- the pump drains the queue the packet handler fills and applies it
            cw2.rankFloor = 0; cw2._obtainQueue = { 574 };
            cw2.pumpObtains();
            check('CW-T11 pumpObtains drains the queue and ratchets', (function()
                return cw2.rankFloor >= 2 and #cw2._obtainQueue == 0;
            end)(), true);
            cw2.rankManual, cw2.rankFloor = 0, 0;
        end
        -- the packet offset: item id (param0 = num[0]) = LE u16 at 0x08 (1-based
        -- 0x09/0x0A) of a 0x02A TALKNUMWORK body; id 574 must decode back to 574.
        if type(cw2._obtainIdFromPacket) == 'function' then
            local pkt = string.rep('\0', 0x08) .. string.char(574 % 256, math.floor(574 / 256));
            check('CW-T12 _obtainIdFromPacket reads param0 @ 0x08', cw2._obtainIdFromPacket(pkt), 574);
            check('CW-T13 a too-short packet -> nil', cw2._obtainIdFromPacket('\0\0'), nil);
            check('CW-T14 non-string -> nil', cw2._obtainIdFromPacket(nil), nil);
        end
    end
end)();

-- uistyle.helpLabel: the underline+hover panel-text standard (Henrik 2026-07-24)
-- -- an underlined key label that reveals its explanation on hover instead of an
-- inline paragraph. Driven by a recording mock imgui (the caller's imgui is a
-- parameter, so the helper is binding-agnostic and headless-testable).
(function()
    local usok, us = pcall(require, 'dlac\\ui\\uistyle');
    if not usok or type(us) ~= 'table' or type(us.helpLabel) ~= 'function' then
        check('US0 uistyle.helpLabel exists', false, true);
        return;
    end
    local rec = { text = nil, tip = nil, line = false };
    local dl = { AddLine = function() rec.line = true; end };
    local IM = {
        TextColored       = function(_, t) rec.text = t; end,
        GetItemRectMin    = function() return 0, 0; end,
        GetItemRectMax    = function() return 20, 10; end,
        GetWindowDrawList = function() return dl; end,
        GetColorU32       = function() return 0xFFFFFFFF; end,
        IsItemHovered     = function() return true; end,
        SetTooltip        = function(t) rec.tip = t; end,
    };
    us.helpLabel(IM, 'Total riding time:', 'Every point adds 1 minute.', { 1, 1, 1, 1 });
    check('US1 helpLabel renders the label text', rec.text, 'Total riding time:');
    check('US2 helpLabel draws the underline',    rec.line, true);
    check('US3 helpLabel shows the tip on hover',  rec.tip, 'Every point adds 1 minute.');
    -- not hovered -> no tooltip
    rec.tip = nil; IM.IsItemHovered = function() return false; end;
    us.helpLabel(IM, 'x', 'hidden', { 1, 1, 1, 1 });
    check('US4 no tooltip when not hovered', rec.tip, nil);
    -- crash-safe on a minimal binding (only TextColored -- no draw-list/hover)
    check('US5 helpLabel is crash-safe on a minimal binding',
        pcall(us.helpLabel, { TextColored = function() end }, 'y', 'z'), true);
    -- crash-safe on a nil/garbage imgui handle
    check('US6 helpLabel no-ops on a bad imgui handle',
        pcall(us.helpLabel, nil, 'y', 'z'), true);
end)();

-- ---------------------------------------------------------------------------
-- 7b. chocoui RENDER stack balance (issue #98) -- the by-area tab introduces
--     new BeginCombo/BeginTabBar/BeginTabItem pairs, exactly the class of
--     imgui-stack imbalance that crashes the client with no Lua error (the
--     floatgear S50 lesson). Stub imgui, re-require chocoui against it, drive
--     M.render with a zone SELECTED (Selectable returns true) so the pool +
--     conditional rows actually render -- AND the By item tab's item search
--     filled (issue #99) so its source rows + cross-link buttons render too --
--     and assert every stack came back to 0.
-- ---------------------------------------------------------------------------
;(function()
    local depth = { combo = 0, bar = 0, item = 0, win = 0 };
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'TextColored', 'Text', 'TextWrapped', 'SameLine', 'Spacing', 'Separator',
        'Dummy', 'Image', 'PushItemWidth', 'PopItemWidth', 'InputText', 'SetTooltip' }) do
        IM[n] = nop;
    end
    IM.BeginCombo   = function() return true; end
    IM.EndCombo     = function() depth.combo = depth.combo - 1; end
    IM.BeginTabBar  = function() depth.bar = depth.bar + 1; return true; end
    IM.EndTabBar    = function() depth.bar = depth.bar - 1; end
    IM.BeginTabItem = function() depth.item = depth.item + 1; return true; end
    IM.EndTabItem   = function() depth.item = depth.item - 1; end
    -- BeginCombo balance is only tallied when it opens; count the open here.
    local realBeginCombo = IM.BeginCombo;
    IM.BeginCombo = function(...) depth.combo = depth.combo + 1; return realBeginCombo(...); end
    IM.Button    = function() return false; end
    IM.Selectable = function() return true; end          -- pick a zone / rank / item each frame
    IM.IsItemHovered = function() return false; end
    -- fill the By item search buffer (only that field) so the match list yields
    -- a selection and the per-item source rows + cross-link buttons render.
    IM.InputText = function(label, buf)
        if label == '##chocoitemsearch' and type(buf) == 'table' then buf[1] = 'a'; end
    end
    -- floating-window API for renderSearch (the Area / Item windows)
    IM.Begin             = function() depth.win = depth.win + 1; return true; end
    IM.End               = function() depth.win = depth.win - 1; end
    IM.SetNextWindowSize = nop;

    package.loaded['imgui'] = IM;
    -- stub the two optional collaborators so render never touches files/real imgui
    package.loaded['dlac\\ui\\craftbar'] = {};            -- no onOffSwitch -> Button fallback
    package.loaded['dlac\\feature\\chocowatch'] = {
        isEnabled = function() return false; end, setEnabled = nop,
        rankManual = 0, setManualRank = nop,
        rankState = function()
            return { rank = 8, source = 'manual', exact = false, label = 'Adept', sourceLabel = 'manual' };
        end,
    };
    package.loaded['dlac\\ui\\chocoui'] = nil;
    local ok, cui = pcall(require, 'dlac\\ui\\chocoui');
    check('S139aa chocoui re-requires against a stub imgui', ok and type(cui.render), 'function');
    if ok then
        local deps = { renderIcon = nop, lookupById = function() return nil; end, itemTooltip = nop,
                       ownedList = function() return {}; end, haveInBags = function() return true; end };
        local rok, rerr = pcall(cui.render, deps, 400);
        check('S139bb render runs against the stub (zone selected)', rok, true);
        if not rok then print('   chocoui render error: ' .. tostring(rerr)); end
        check('S139cc BeginCombo/EndCombo balanced',   depth.combo, 0);
        check('S139dd BeginTabBar/EndTabBar balanced', depth.bar, 0);
        check('S139ee BeginTabItem/EndTabItem balanced', depth.item, 0);
        -- The floating search windows (Henrik 07-24): Area + Item open as separate
        -- imgui.Begin windows; every Begin must pair with an End (the floatgear
        -- rule), and both by-area/by-item content renders inside without crashing.
        if type(cui.renderSearch) == 'function' and type(cui._search) == 'table' then
            cui._search.area.open[1] = true;   -- Area window, real zone -> rows render
            cui._search.area.zoneId  = 2;      -- Carpenters' Landing
            cui._search.area.fromItem = true;  -- exercise the Back button too
            local sok1 = pcall(cui.renderSearch, deps);
            check('S139ff renderSearch runs the Area window', sok1, true);
            check('S139gg Area window Begin/End balanced', depth.win, 0);
            cui._search.area.open[1] = false;
            cui._search.item.open[1] = true;   -- Item window, search filled -> sources render
            cui._search.item.q[1]    = 'a';
            local sok2 = pcall(cui.renderSearch, deps);
            check('S139hh renderSearch runs the Item window', sok2, true);
            check('S139ii Item window Begin/End balanced', depth.win, 0);
            cui._search.item.open[1] = false;
            check('S139jj closed windows draw nothing (Begin count 0)', (function()
                depth.win = 0; pcall(cui.renderSearch, deps); return depth.win;
            end)(), 0);
            -- The OPENERS (2026-07-27). Public because the hobby bar's Chocobo tab
            -- opens these windows too -- one behaviour for both surfaces, so a
            -- bar-opened search cannot differ from a panel-opened one. The
            -- mutual exclusion is the part worth pinning: opening one search
            -- closes the other, or you get two dig windows arguing on screen.
            check('S139kk openAreaSearch opens Area', (function()
                cui._search.item.open[1] = true;
                cui.openAreaSearch();
                return cui._search.area.open[1] and not cui._search.item.open[1];
            end)(), true);
            check('S139ll openAreaSearch clears the from-Item back button',
                cui._search.area.fromItem, false);
            check('S139mm openItemSearch opens Item and closes Area', (function()
                cui.openItemSearch();
                return cui._search.item.open[1] and not cui._search.area.open[1];
            end)(), true);
            cui._search.item.open[1] = false;
            cui._search.area.open[1] = false;
        end
    end
    -- restore the real modules for any later section
    package.loaded['imgui'] = nil;
    package.loaded['dlac\\ui\\craftbar'] = nil;
    package.loaded['dlac\\feature\\chocowatch'] = nil;
    package.loaded['dlac\\ui\\chocoui'] = nil;
    require('dlac\\ui\\chocoui');
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
        -- helm: Surveyor-major scoring + the semantic hat map. The hat rides
        -- its REAL id: the map is id-PINNED (the Laevateinn rule below),
        -- because the CLIENT name carries an apostrophe the catalog drops --
        -- a name-only lookup would land the catalog spelling in the manifest
        -- and LAC could never equip it (the 07-22 Mining field bug).
        { Name = 'Field Tunica',      Id = 90030, Level = 1,  Slot = 'Body',  Jobs = { 'All' },
          Stats = { HELM = 2, Surveyor = 1 } },
        { Name = "Miner's Helmet",    Id = 25560, Level = 1,  Slot = 'Head',  Jobs = { 'All' },
          Stats = { Surveyor = 1 } },
        -- fish: FishingSkill-major; Main deliberately IN (fishing weapons);
        -- Range/Ammo deliberately OUT (rod and bait are fishstate picks).
        { Name = 'Fishermans Tunica', Id = 90040, Level = 1,  Slot = 'Body',  Jobs = { 'All' },
          Stats = { FishingSkill = 1 } },
        { Name = 'Halieutica',        Id = 90041, Level = 49, Slot = 'Main',  Jobs = { 'All' },
          Stats = { FishingSkill = 2 } },
        { Name = 'Halcyon Rod',       Id = 90042, Level = 1,  Slot = 'Range', Jobs = { 'All' },
          Stats = { FishingSkill = 10 } },
        -- choco: ChocoboRidingTime-scored; Main IS in (the Chocobo Wand takes
        -- the weapon slot and is included); Range/Ammo/Ring/Waist/Head OUT.
        { Name = 'Chocobo Wand',      Id = 90060, Level = 1,  Slot = 'Main',  Jobs = { 'All' },
          Stats = { ChocoboRidingTime = 30 } },
        { Name = 'Chocobo Torque',    Id = 90061, Level = 1,  Slot = 'Neck',  Jobs = { 'All' },
          Stats = { ChocoboRidingTime = 4 } },
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
    check('S176 helm hat map: id-PIN adopts the DB record -- the CLIENT spelling, not the catalog\'s',
        m.helm.hats and m.helm.hats.Mining and m.helm.hats.Mining.name .. '/' .. m.helm.hats.Mining.surv,
        "Miner's Helmet/1");
    check('S177 fish ladder is FishingSkill-major (x1000)',
        m.fish and m.fish.body and m.fish.body[1].name .. '/' .. m.fish.body[1].score,
        'Fishermans Tunica/1000');
    check('S178 fishing WEAPONS ride the Main fish ladder',
        m.fish.main and m.fish.main[1].name, 'Halieutica');
    check('S179 rods stay OUT of the fish ladders (fishstate owns rod+bait)', m.fish.range, nil);
    check('S179b choco ladder is ChocoboRidingTime-scored (the Wand tops Main)',
        m.choco and m.choco.main and m.choco.main[1].name .. '/' .. m.choco.main[1].score, 'Chocobo Wand/30');
    check('S179c choco Neck ladder carries the ride value on the rung',
        m.choco and m.choco.neck and m.choco.neck[1].ride, 4);
    check('S179d riding gear in an unlisted slot stays OUT (Range/Ammo/Head/Ring/Waist)',
        m.choco and m.choco.range, nil);
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
    -- source/control hints exist for EVERY row the engine can rank -- driven off
    -- the real default order, so a new claimant cannot ship with a blank hover.
    local aw = require('dlac\\feature\\arbwatch');
    check('S192 every row has a source/control hint', (function()
        for _, n in ipairs(aw.defaultOrder()) do
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
    -- DISPLAY LABELS (2026-07-28, Henrik: "I don't mind its name being that
    -- internally, but not in the GUI"). buildRows still yields the IDENTITY as
    -- r.name -- it keys the imgui id, the drag, SOURCE/HINT and arbstate's saved
    -- order -- and the renderer draws pui.label(r.name) instead. One map, in
    -- gear/arbiter, shared with the Arbiter Monitor and /dl prio + /dl why.
    check('S195b the Priority list LABELS the ammo claimant, never its identity',
        pui.label('AutoAmmo'), 'Ammo rule');
    check('S195c an unmapped claimant labels as itself', pui.label('MaxMP'), 'MaxMP');
    check('S195d buildRows still carries the IDENTITY (SOURCE/HINT/arbstate key on it)', (function()
        for _, r in ipairs(pui.buildRows(aw.defaultOrder(), {})) do
            if r.name == 'AutoAmmo' then return true; end
        end
        return false;
    end)(), true);
    -- The Arbiter Monitor names claimants in its legend chips and slot hovers --
    -- same map, so the two windows can never disagree.
    check('S195e the Arbiter Monitor shares the map', (function()
        local oka, amu = pcall(require, 'dlac\\ui\\arbmonui');
        if not oka or type(amu) ~= 'table' then return 'arbmonui failed to load'; end
        local okb, arb = pcall(require, 'dlac\\gear\\arbiter');
        return okb and arb.claimantLabel('AutoAmmo') == pui.label('AutoAmmo');
    end)(), true);
    -- buildRows: only the Triggers floor is non-draggable now (step 3 folded the
    -- Locks veto into the list). Locks drags but stays a SPECIAL row (distinct
    -- color); the six claimants drag.
    local rows = pui.buildRows(aw.defaultOrder(), {});
    check('S196 buildRows yields a row per rank', #rows, #aw.defaultOrder());
    -- Naked (ADR 0021) is an ordinary draggable row: "naked except my pins" is a
    -- drag, so the day it becomes fixed the feature loses its escape hatch.
    check('S196b Naked leads the CLAIMANTS and drags (row 1 is the ADR 0024 ceiling)', (function()
        return rows[1].name == 'Disabled' and rows[1].draggable == false
           and rows[2].name == 'Naked' and rows[2].draggable == true;
    end)(), true);
    -- The ceiling: a fixed, special row that reports how many slots it holds.
    check('S196b2 the Disabled ceiling is fixed, special, and reports its count', (function()
        local off = pui.buildRows({ 'Disabled' }, { disabled = 0 })[1];
        local on  = pui.buildRows({ 'Disabled' }, { disabled = 3 })[1];
        return off.active == false and on.active == true
           and on.special == true and on.draggable == false
           and on.status ~= off.status and on.status ~= '?' and off.status ~= '?';
    end)(), true);
    check('S196c the Naked row reports its live state', (function()
        local on  = pui.buildRows({ 'Naked' }, { naked = true })[1];
        local off = pui.buildRows({ 'Naked' }, { naked = false })[1];
        return on.active == true and off.active == false
           and on.status ~= off.status and on.status ~= '?' and off.status ~= '?';
    end)(), true);
    check('S197 Locks is a draggable veto row; only Triggers is fixed', (function()
        local byName = {};
        for _, r in ipairs(rows) do byName[r.name] = r; end
        return byName.Locks.draggable == true and byName.Locks.special == true
           and byName.Triggers.draggable == false and byName.Triggers.special == true
           and byName.AutoAmmo.draggable == true;
    end)(), true);
    -- arbwatch loads under the ui tree and its pure move rule holds headless.
    check('S198 arbwatch loads headless', type(aw), 'table');
    -- Indices follow the live default order, so they move when a row is added --
    -- find the floor rather than hardcode its position.
    local function idxOf(name)
        for i, n in ipairs(aw.defaultOrder()) do if n == name then return i; end end
    end
    check('S199 arbwatch.moveClaimant refuses to drag the Triggers floor',
        aw.moveClaimant(aw.defaultOrder(), idxOf('Triggers'), -1), nil);
    -- S199b: the Locks veto drags -- raising it one step swaps it above Pins, and
    -- it never displaces the floor. (Naked sits above both since v122.)
    check('S199b Locks drags up past Pins', (function()
        local moved = aw.moveClaimant(aw.defaultOrder(), idxOf('Locks'), -1);
        if moved == nil then return false; end
        local li, pi;
        for i, n in ipairs(moved) do if n == 'Locks' then li = i; elseif n == 'Pins' then pi = i; end end
        return li == pi - 1;
    end)(), true);
    check('S199c Locks drags down under AutoAmmo', (function()
        local moved = aw.moveClaimant(aw.defaultOrder(), idxOf('Locks'), 1);
        if moved == nil then return false; end
        local li, ai;
        for i, n in ipairs(moved) do if n == 'Locks' then li = i; elseif n == 'AutoAmmo' then ai = i; end end
        return li == ai + 1;
    end)(), true);
end)();

-- ---------------------------------------------------------------------------
-- 11. ENGINE-NATIVE SLOT LOCKS (issue #58 / PRD #57): the lock path is engine-
--     native only -- it no longer sabotages the slot at the LAC layer with
--     /lac disable, which was defeating the Arbiter's punch-through (a pin that
--     outranks Locks could never dress a /lac-disabled slot). These pin the
--     retirement at the queued-command seam -- assert the EXACT command strings
--     each UI action queues -- so the legacy dependency cannot silently return.
-- ---------------------------------------------------------------------------
(function()
    -- (a) THE LOCK ACTION -- equipToSlot's lock mode runs through the cmdqueue.
    --     gearui captured the cmdqueue MODULE TABLE at load, so mutating its
    --     enqueue records exactly what the lock action queues (the auto-equip
    --     queued-/lac-command prior art). Must queue the ENGINE lock + native
    --     /equip and NOTHING at the /lac layer.
    local cmdq = require('dlac\\lib\\cmdqueue');
    local realEnqueue = cmdq.enqueue;
    local rec = {};
    cmdq.enqueue = function(_, c) rec[#rec + 1] = c; end
    S.equipToSlot('Head', "Genbu's Kabuto", true, false, false);   -- lock, not free, not already locked
    cmdq.enqueue = realEnqueue;
    local joined = table.concat(rec, ' | ');
    check('S200 lock action queues the engine lock', string.find(joined, '/dl lock head on', 1, true) ~= nil, true);
    check('S201 lock action equips via native /equip', string.find(joined, '/equip head', 1, true) ~= nil, true);
    check('S202 lock action queues NO /lac disable (engine-native only)',
        string.find(joined, '/lac disable', 1, true), nil);
    check('S203 lock action touches the /lac layer not at all',
        string.find(joined, '/lac ', 1, true), nil);

    -- already-locked lock action: re-equips only (no re-lock spam), still no /lac.
    rec = {};
    cmdq.enqueue = function(_, c) rec[#rec + 1] = c; end
    S.equipToSlot('Head', "Genbu's Kabuto", true, false, true);
    cmdq.enqueue = realEnqueue;
    check('S204 already-locked lock re-equips only, no /lac',
        #rec == 1 and string.find(rec[1], '/equip head', 1, true) ~= nil, true);

    -- (b) FREE EQUIP + UNLOCK go through equippedui's render + AshitaCore's
    --     command queue (not the cmdqueue). Drive renderEquippedTab against a
    --     stub imgui + a recording AshitaCore -- the floatgear section's
    --     re-require pattern -- and read back the exact commands. Free equip
    --     KEEPS its global /lac pair (the scope boundary this change must not
    --     cross); unlock KEEPS /lac enable (the legacy heal).
    local nop = function() end
    local IM = setmetatable({}, { __index = function() return nop; end });
    IM.GetContentRegionAvail = function() return 620; end
    IM.BeginChild = function() return true; end
    IM.Button     = function() return false; end
    IM.Checkbox   = function() return false; end
    IM.IsItemHovered = function() return false; end
    IM.InputText  = function() return false; end
    IM.SliderFloat = function() return false; end

    local queued = {};
    local recAshita = { GetChatManager = function()
        return { QueueCommand = function(_, _, c) queued[#queued + 1] = c; end };
    end };

    -- re-require equippedui so its captured imgui is the stub (host.register
    -- replaces in place -- tab order is untouched). Stub the services its render
    -- touches (the real ones captured the nil imgui at load).
    package.loaded['imgui'] = IM;
    -- gearfmt captured an EARLIER section's stub (a fixed field list), so its
    -- wrapped-text helper dies mid-render on a name that list never had -- and the
    -- pcall'd drives below would swallow it. Re-require gearfmt against THIS
    -- block's catch-all stub so the render runs to completion; without that, an
    -- "ok" assertion on the render can never be true and the NKU* checks below
    -- (the only thing that catches a nil global in the toolbar) are untestable.
    package.loaded['dlac\\gear\\gearfmt'] = nil;
    package.loaded['dlac\\ui\\equippedui'] = nil;
    local eqOk = pcall(require, 'dlac\\ui\\equippedui');
    check('S205 equippedui re-requires against a stub imgui', eqOk, true);
    local eqmod = host.get('equipped');
    local render = eqmod and eqmod.tabs and eqmod.tabs[1] and eqmod.tabs[1].render;
    check('S206 the Equipped tab render is reachable', type(render), 'function');

    if eqOk and type(render) == 'function' then
        local Sx = host.services;
        local keep = { Sx.renderSlotGrid, Sx.renderStatsPanel, Sx.renderSortCombo,
            Sx.candidatesForSlot, Sx.sortForDisplay, Sx.getEquippedId, Sx.displayName,
            Sx.lookupById, Sx.engineLocks };
        Sx.renderSlotGrid  = nop;  Sx.renderStatsPanel = nop;  Sx.renderSortCombo = nop;
        Sx.candidatesForSlot = function() return {}; end
        Sx.sortForDisplay  = function(l) return l or {}; end
        Sx.getEquippedId   = function() return nil; end
        Sx.displayName     = function() return 'X'; end
        Sx.lookupById      = function() return nil; end
        Sx.engineLocks     = function() return {}; end

        local realAshita = AshitaCore;
        AshitaCore = recAshita;
        local u = Sx.ui;
        u.showStats = false;  u._gearFloat = false;  u.altSearch = { '' };

        -- FREE EQUIP (ADR 0024). It used to fire the global /lac disable, which
        -- under the NATIVE engine talks to a LuaAshitacast that is no longer
        -- doing the equipping -- the switch did nothing at all in the mode we
        -- ship. It now drives dlac's own ceiling through S.setEngineFreeEquip,
        -- and the box is drawn from the ENGINE MIRROR, so these drive a click
        -- rather than the retired ui._freePrev edge.
        local keptFE = { Sx.engineDisabled, Sx.setEngineFreeEquip };
        local dzState, feCalls = {}, {};
        Sx.engineDisabled     = function() return dzState; end
        Sx.setEngineFreeEquip = function(on) feCalls[#feCalls + 1] = (on == true); end
        local keptCb0 = IM.Checkbox;
        IM.Checkbox = function(label, t)
            if label == 'Free equip' then t[1] = not t[1]; return true; end
            return false;
        end
        u.eqSelected = nil;
        u.lockEquipped = { false };  u._lockPrev = false;
        queued, feCalls = {}, {};
        local okFE = pcall(render, 'WHM', 75);          -- nothing disabled -> the click ARMS
        check('S207 Free equip ON arms dlac\'s own ceiling', okFE and #feCalls == 1 and feCalls[1] == true, true);
        check('S207b and no /lac disable goes out any more (it was inert in native mode)',
            string.find(table.concat(queued, ' | '), '/lac disable', 1, true), nil);

        -- FREE EQUIP off: releases the ceiling AND the engine locks (unchanged).
        dzState = { main = true, head = true };         -- armed -> the box draws checked
        queued, feCalls = {}, {};
        pcall(render, 'WHM', 75);
        check('S208 Free equip OFF releases it', #feCalls == 1 and feCalls[1] == false, true);
        check('S209 Free equip OFF releases engine locks',
            string.find(table.concat(queued, ' | '), '/dl lock all off', 1, true) ~= nil, true);

        IM.Checkbox = keptCb0;
        dzState = {};
        Sx.engineDisabled, Sx.setEngineFreeEquip = keptFE[1], keptFE[2];

        -- THE UNLOCK ACTION: unchecking "Lock when equipped" queues the engine
        -- unlock AND the legacy /lac enable heal (a no-op for clean users, a
        -- cleanup for anyone carrying a stale disable from the old lock path).
        u.eqSelected = 'Head';
        u.freeEquip = { false };  u._freePrev = false;      -- no free-equip edge
        u.lockEquipped = { false };  u._lockPrev = true;    -- the unlock edge
        queued = {};
        pcall(render, 'WHM', 75);
        local ujoin = table.concat(queued, ' | ');
        check('S210 unlock queues the engine unlock', string.find(ujoin, '/dl lock head off', 1, true) ~= nil, true);
        check('S211 unlock queues NO /lac command (the legacy heal died in the purge)',
            string.find(ujoin, '/lac ', 1, true), nil);

        -- NKU. The Naked switch (ADR 0021), driven through the REAL render.
        -- This is the only thing that catches an unknown Lua name in that block:
        -- an unknown name is a silent nil GLOBAL, invisible to a load test, and
        -- the renders above are pcall'd -- so these assert the pcall RESULT.
        local keptN = { Sx.engineNaked, Sx.setEngineNaked, Sx.isNative };
        local nakedState, setCalls = false, {};
        Sx.engineNaked    = function() return nakedState; end
        Sx.setEngineNaked = function(on) setCalls[#setCalls + 1] = (on == true); end
        Sx.isNative       = function() return false; end
        u.eqSelected = nil;
        u.freeEquip = { false };  u._freePrev = false;
        u.lockEquipped = { false };  u._lockPrev = false;

        local okN = pcall(render, 'WHM', 75);
        check('NKU1 the Equipped toolbar renders with the Naked switch present', okN, true);

        nakedState = true;                                  -- armed: the red state line draws
        local reds = 0;
        local keptTC = IM.TextColored;
        IM.TextColored = function(_, t)
            if type(t) == 'string' and string.find(t, 'NAKED', 1, true) then reds = reds + 1; end
        end
        local okN2 = pcall(render, 'WHM', 75);
        check('NKU2 it renders while ARMED too', okN2, true);
        check('NKU2b and says so on the toolbar', reds >= 1, true);

        -- Clicking it calls the ONE door (only the naked checkbox reports a click,
        -- so Free equip and Floating equipment are not disturbed).
        local keptCb = IM.Checkbox;
        IM.Checkbox = function(label, t)
            if type(label) == 'string' and string.find(label, 'eqnaked', 1, true) then
                t[1] = false; return true;                  -- unchecking an armed switch
            end
            return false;
        end
        setCalls = {};
        local okN3 = pcall(render, 'WHM', 75);
        check('NKU3 clicking the switch renders cleanly', okN3, true);
        check('NKU3b and calls setEngineNaked(false)',
            #setCalls == 1 and setCalls[1] == false, true);

        -- Free equip owning ALL SIXTEEN slots is the state where stripping would
        -- silently do nothing -- dlac cannot unequip a slot it has been told not
        -- to touch -- so the switch must not be clickable there. Since ADR 0024
        -- this is a stated rule in BOTH engines, not LuaAshitacast's accident, and
        -- it is read from the engine mirror rather than an addon-side flag.
        setCalls = {};
        local keptDz = Sx.engineDisabled;
        Sx.engineDisabled = function()
            local all = {};
            for _, s in ipairs({ 'main', 'sub', 'range', 'ammo', 'head', 'neck', 'ear1', 'ear2',
                                 'body', 'hands', 'ring1', 'ring2', 'back', 'waist', 'legs', 'feet' }) do
                all[s] = true;
            end
            return all;
        end
        local okN4 = pcall(render, 'WHM', 75);
        check('NKU4 Free equip owning all 16 renders the switch as unavailable', okN4, true);
        check('NKU4b and it cannot be clicked into a silent no-op', #setCalls, 0);
        Sx.engineDisabled = keptDz;

        IM.Checkbox = keptCb;  IM.TextColored = keptTC;
        Sx.engineNaked, Sx.setEngineNaked, Sx.isNative = keptN[1], keptN[2], keptN[3];
        u.freeEquip = { false };  u._freePrev = false;
        nakedState = false;

        -- LSU. The Lock gear switch + LOCKED readout (ADR 0022), driven through
        -- the REAL render for the same reason NKU* exists: an unknown Lua name in
        -- that block is a silent nil GLOBAL that no load test can see, and every
        -- render above is pcall'd, so these assert the pcall RESULT.
        local keptHeld = Sx.engineHeld;
        local heldState = nil;
        Sx.engineHeld = function() return heldState; end
        u.eqSelected = nil;
        u.freeEquip = { false };  u._freePrev = false;
        u.lockEquipped = { false };  u._lockPrev = false;

        local okL = pcall(render, 'WHM', 75);
        check('LSU1 the toolbar renders with nothing locked', okL, true);

        -- Held: the readout draws. It goes through uistyle.helpLabel (underline +
        -- hover), which falls back to TextColored when the binding has no
        -- draw-list -- as this stub does -- so counting TextColored catches both.
        heldState = { name = 'Incursion T3', mode = 'set', n = 13 };
        local lockedLines = 0;
        local keptTC2 = IM.TextColored;
        IM.TextColored = function(_, t)
            if type(t) == 'string' and string.find(t, 'LOCKED:', 1, true) then
                lockedLines = lockedLines + 1;
            end
        end
        local okL2 = pcall(render, 'WHM', 75);
        IM.TextColored = keptTC2;
        check('LSU2 it renders while a set is LOCKED', okL2, true);
        check('LSU2b and names the set on the toolbar', lockedLines >= 1, true);

        -- Clicking it: armed -> release goes through the narrow door, NOT
        -- /dl lock all off (which would take the player's slot locks with it).
        local keptCb2 = IM.Checkbox;
        IM.Checkbox = function(label, t)
            if type(label) == 'string' and string.find(label, 'eqheld', 1, true) then
                t[1] = false; return true;                  -- unchecking a held switch
            end
            return false;
        end
        queued = {};
        local okL3 = pcall(render, 'WHM', 75);
        local ljoin = table.concat(queued, ' | ');
        check('LSU3 unchecking Lock gear renders cleanly', okL3, true);
        check('LSU3b ...and releases only the set',
            string.find(ljoin, '/dl lock set off', 1, true) ~= nil, true);
        check('LSU3c ...never taking the slot locks with it',
            string.find(ljoin, '/dl lock all off', 1, true), nil);

        -- Unheld -> checking it locks what you are wearing right now.
        heldState = nil;
        IM.Checkbox = function(label, t)
            if type(label) == 'string' and string.find(label, 'eqheld', 1, true) then
                t[1] = true; return true;
            end
            return false;
        end
        queued = {};
        local okL4 = pcall(render, 'WHM', 75);
        check('LSU4 checking it renders cleanly', okL4, true);
        check('LSU4b ...and queues set-current',
            string.find(table.concat(queued, ' | '), '/dl lock set-current', 1, true) ~= nil, true);

        IM.Checkbox = keptCb2;
        Sx.engineHeld = keptHeld;
        heldState = nil;

        AshitaCore = realAshita;
        for i, f in ipairs({ 'renderSlotGrid', 'renderStatsPanel', 'renderSortCombo',
            'candidatesForSlot', 'sortForDisplay', 'getEquippedId', 'displayName',
            'lookupById', 'engineLocks' }) do
            Sx[f] = keep[i];
        end
        u.eqSelected = nil;  u._lockPrev = nil;  u._freePrev = nil;
    end

    -- restore the real (nil) imgui binding for anything downstream
    package.loaded['imgui'] = nil;
    package.loaded['dlac\\gear\\gearfmt'] = nil;
    package.loaded['dlac\\ui\\equippedui'] = nil;
    pcall(require, 'dlac\\gear\\gearfmt');
    pcall(require, 'dlac\\ui\\equippedui');
end)();

-- ---------------------------------------------------------------------------
-- 12. GOLDEN-OUTPUT HARNESS (issue #72 / PRD #69 Phase 2 gate). THE safety gate
--     for the coming stat-glue migration (Oracle step 5): capture every manifest
--     stat-glue builder's EXACT output -- the MaxMP battery ladder (incl. the
--     augment fold), the HELM ladders, the fishing ladders + the fishcalc rod-
--     ranking reads, and the per-craft owned-gear walk -- from deterministic
--     synthetic fixtures, and assert it reproduces the committed goldens
--     BYTE-IDENTICALLY. When Phase 2 lands, the same fixtures must produce the
--     same goldens, so a later field failure can never be misattributed to the
--     migration. The fixtures + capture live in tests/goldenfixtures.lua; the
--     goldens in tests/golden/; (re)generate with `lua5.4 tests/gen_goldens.lua`.
-- ---------------------------------------------------------------------------
(function()
    local ok, fixtures = pcall(dofile, 'tests/goldenfixtures.lua');
    check('S220 golden harness loads', ok and type(fixtures) == 'table', true);
    if not ok then print('  goldenfixtures error: ' .. tostring(fixtures)); return; end

    local goldens = fixtures.capture();
    for _, name in ipairs({ 'autogear.golden', 'fishcalc.golden' }) do
        local got = goldens[name];
        check('S221 ' .. name .. ' captured (builder ran headless)', type(got), 'string');
        local f = io.open(fixtures.pathFor(name), 'rb');
        check('S222 ' .. name .. ' golden is committed', f ~= nil, true);
        if f ~= nil and type(got) == 'string' then
            local want = f:read('*a'); f:close();
            local same = (got == want);
            check('S223 ' .. name .. ' reproduced byte-identically', same, true);
            if not same then
                -- Name the first differing line so the failure has an address.
                local gl, wl = {}, {};
                for line in (got .. '\n'):gmatch('([^\n]*)\n') do gl[#gl + 1] = line; end
                for line in (want .. '\n'):gmatch('([^\n]*)\n') do wl[#wl + 1] = line; end
                for i = 1, math.max(#gl, #wl) do
                    if gl[i] ~= wl[i] then
                        print(string.format('  %s: first diff at line %d', name, i));
                        print('    committed: ' .. tostring(wl[i]));
                        print('    captured : ' .. tostring(gl[i]));
                        break;
                    end
                end
                print('  A stat-glue builder output MOVED. Phase 2 must be byte-identical --');
                print('  if this change is intentional, run: lua5.4 tests/gen_goldens.lua (review the diff).');
            end
        end
    end
end)();

-- ---------------------------------------------------------------------------
-- 7c. hobbybar RENDER stack balance (ADR 0017) -- the shared hobby window's
--     selector does PushStyleColor/PopStyleColor per tab (active = Button colour,
--     locked = Text colour) plus the always-paired Begin/End. A mismatch is the
--     floatgear S50 crash class: native UB inside ImGui, no Lua error, whole
--     client down. Stub imgui + idleexcl, drive M.render for each selected tab in
--     BOTH the idle and the active-lock branch, and assert every stack returns to 0.
-- ---------------------------------------------------------------------------
;(function()
    local depth = { win = 0, col = 0 };
    local btns, smalls, imgs = {}, {}, {};
    local frames = 0;   -- armed-marker rects drawn by iconTab
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'Separator', 'Text', 'TextColored', 'SameLine',
        'Dummy', 'SetTooltip', 'Spacing' }) do IM[n] = nop; end
    -- Every size this window asks for, so HB21 can prove it never asks for a
    -- ZERO one. See the LAW in hobbybar.render: a zero component re-arms ImGui's
    -- AutoFitFrames counters every frame, which keeps Begin() returning true
    -- while the window is COLLAPSED -- the minimize bug that ate the Teleports
    -- float and the main window. AlwaysAutoResize already does the sizing.
    local sizes = {};
    IM.SetNextWindowSize = function(sz) sizes[#sizes + 1] = sz; end
    IM.Begin          = function() depth.win = depth.win + 1; return true; end
    IM['End']         = function() depth.win = depth.win - 1; end
    IM.PushStyleColor = function() depth.col = depth.col + 1; end
    IM.PopStyleColor  = function(n) depth.col = depth.col - (tonumber(n) or 1); end
    IM.Button         = function(l) btns[#btns + 1] = tostring(l); return false; end
    -- The Chocobo tab's dig/panel buttons (2026-07-27) are SmallButtons; every
    -- label drawn this frame is recorded so HB14 can prove they reach the tab.
    IM.SmallButton    = function(l) smalls[#smalls + 1] = tostring(l); return false; end
    -- The icon path (2026-07-27): an ART tab draws an Image INSTEAD of a text
    -- Button, and the armed one gets a draw-list frame rather than a colour.
    IM.Image          = function(h) imgs[#imgs + 1] = h; end
    IM.IsItemClicked  = function() return false; end
    IM.GetCursorScreenPos = function() return 10, 20; end
    IM.GetWindowDrawList  = function() return { AddRect = function() frames = frames + 1; end }; end
    IM.IsItemHovered  = function() return false; end
    IM.GetContentRegionAvail = function() return 400, 400; end

    -- save what we stub, so later smoke sections see the real modules
    local NAMES = { 'dlac\\ui\\craftbar', 'dlac\\ui\\helmbar', 'dlac\\ui\\fishbar',
                    'dlac\\ui\\hobbybar', 'dlac\\feature\\chocowatch',
                    'dlac\\feature\\idleexcl', 'dlac\\ui\\filetex', 'imgui' };
    local saved = {};
    for _, k in ipairs(NAMES) do saved[k] = package.loaded[k]; end

    package.loaded['imgui'] = IM;
    for _, m in ipairs({ 'craftbar', 'helmbar', 'fishbar' }) do
        package.loaded['dlac\\ui\\' .. m] = { renderContent = nop, onOffSwitch = function() return false; end };
    end
    package.loaded['dlac\\feature\\chocowatch'] = { isEnabled = function() return false; end, setEnabled = nop };
    local activeStub = nil;   -- nil = idle; a table = that hobby is armed (lock branch)
    package.loaded['dlac\\feature\\idleexcl'] = { getActive = function() return activeStub; end };

    package.loaded['dlac\\ui\\hobbybar'] = nil;
    local ok, hb = pcall(require, 'dlac\\ui\\hobbybar');
    check('HB1 hobbybar re-requires against a stub imgui', ok and type(hb.render), 'function');
    if ok then
        local ui = host.services.ui;

        ui._hobbyBar = false;                       -- closed: draws nothing
        pcall(hb.render);
        check('HB2 closed hobby bar opens no window', depth.win, 0);

        ui._hobbyBar = true;
        activeStub = nil;                           -- idle: every tab selectable
        for _, k in ipairs({ 'craft', 'helm', 'fish', 'choco' }) do
            ui._hobbySel = k;
            smalls = {};
            check('HB3.' .. k .. ' renders selection ' .. k, pcall(hb.render), true);
            if k == 'choco' then
                -- 2026-07-27: the Chocobo tab used to end in a grey sentence
                -- telling you to go to Automations > Chocobo. These three buttons
                -- replaced the sentence -- Area/Item open chocoui's floating dig
                -- searches, Panel opens the detail view that owns the dig RANK
                -- every odds figure in those windows is computed from.
                local seen = table.concat(smalls, ' ');
                check('HB14 choco tab offers Area / Item / Panel',
                    (seen:find('Area##', 1, true) ~= nil)
                    and (seen:find('Item##', 1, true) ~= nil)
                    and (seen:find('Panel##', 1, true) ~= nil), true);
            end
        end
        check('HB4 idle: Begin/End balanced',   depth.win, 0);
        check('HB5 idle: colour stack balanced', depth.col, 0);

        -- HB21: the MINIMIZE law. A zero size here (any component) re-arms
        -- ImGui's AutoFitFrames every frame, so a COLLAPSED hobby bar keeps
        -- returning true from Begin() and keeps drawing its body -- which is
        -- what made minimizing this one window swallow the Teleports float and
        -- the main /dl window. The window is AlwaysAutoResize; it needs no size
        -- request at all, and a zero one is never correct.
        local zero = false;
        for _, sz in ipairs(sizes) do
            if type(sz) == 'table' and ((tonumber(sz[1]) or 1) <= 0 or (tonumber(sz[2]) or 1) <= 0) then
                zero = true;
            end
        end
        check('HB21 hobby bar never requests a zero window size', zero, false);

        activeStub = { key = 'helm', name = 'HELM' };   -- HELM armed...
        ui._hobbySel = 'craft';                        -- ...and we are LOOKING at Craft
        check('HB6 renders with an active hobby', pcall(hb.render), true);
        check('HB7 active: Begin/End balanced',   depth.win, 0);
        check('HB8 active: colour stack balanced', depth.col, 0);
        -- REGRESSION GUARD (2026-07-25). render used to pin the selector to the
        -- armed hobby EVERY FRAME and grey out the rest, so with Auto HELM or
        -- Chocobo on -- both persist across relogs -- the Craft tab was never
        -- drawn and the Last Synth button did not exist on screen. Exclusivity
        -- is an ARMING rule (idleexcl.guardActivate), never a LOOKING rule.
        check('HB9 render leaves the selection alone while another hobby is armed', ui._hobbySel, 'craft');
        check('HB10 isShown reports the tab you are on, not the armed one', hb.isShown('craft'), true);
        -- ART TABS (2026-07-27). Headless there is no d3d, so filetex.handle is
        -- always nil and every tab takes the TEXT path -- meaning the icon branch
        -- would ship with zero coverage. Stub the loader so exactly ONE tab has
        -- art. All four tabs SHIP art now, but the mixed row must keep working:
        -- it is what a missing or failed-to-load PNG produces, and it is how a
        -- fifth hobby would arrive. Which tab the stub hands art to is
        -- deliberately independent of what is on disk -- this asserts the
        -- BRANCH, not the asset list.
        do
            package.loaded['dlac\\ui\\filetex'] = {
                handle = function(n) return (n == 'hobby\\Chocobo') and 4242 or nil; end,
            };
            activeStub = nil;
            ui._hobbySel = 'choco';
            btns, imgs, frames = {}, {}, 0;
            check('HB15 an art tab renders', pcall(hb.render), true);
            check('HB15b art tab draws its icon', imgs[1], 4242);
            local labels = table.concat(btns, ' ');
            check('HB16 the art tab draws NO text button',
                labels:find('##hbtabchoco', 1, true), nil);
            check('HB16b the three artless tabs keep theirs', (labels:find('##hbtabcraft', 1, true) ~= nil)
                and (labels:find('##hbtabhelm', 1, true) ~= nil)
                and (labels:find('##hbtabfish', 1, true) ~= nil), true);
            check('HB17 an unarmed art tab draws no armed frame', frames, 0);
            -- Armed-ness cannot ride the button colour on an art tab (tinting art
            -- recolours the art), so it is a draw-list frame. If this stops being
            -- drawn, the armed hobby becomes invisible -- which is the one thing
            -- ADR 0017's selector exists to say.
            activeStub = { key = 'choco', name = 'Chocobo' };
            frames = 0;
            check('HB18 an ARMED art tab renders', pcall(hb.render), true);
            check('HB18b armed art tab draws its green frame', frames, 1);
            check('HB19 stacks still balanced through the icon path',
                depth.win + depth.col, 0);
            -- The hover is now the ONLY thing naming an icon tab, and Henrik
            -- asked for one plain word each ("just show simple terms"). Pin the
            -- exact four: this is the kind of string that grows a sentence back.
            local tips = {};
            IM.SetTooltip = function(t) tips[#tips + 1] = tostring(t); end
            IM.IsItemHovered = function() return true; end
            activeStub = nil;
            pcall(hb.render);
            IM.IsItemHovered = function() return false; end
            IM.SetTooltip = nop;
            check('HB20 tab hovers are the four plain terms',
                table.concat({ tips[1], tips[2], tips[3], tips[4] }, '/'),
                'Crafting/HELM/Fishing/Digging');
            package.loaded['dlac\\ui\\filetex'] = nil;
            activeStub = { key = 'helm', name = 'HELM' };
            ui._hobbySel = 'craft';
        end
        check('HB11 isShown is false for an armed-but-unviewed hobby', hb.isShown('helm'), false);
        -- The escape hatches (/dl craft bar, Automations "Show bar") route
        -- through the same seam: they used to be unable to close the bar, and
        -- craftwatch printed a false "hobby bar hidden." while opening it.
        hb.toggle('craft');
        check('HB12 toggle closes the bar it is already showing', ui._hobbyBar, false);
        hb.toggle('craft');
        check('HB13 toggle re-opens onto craft while HELM is armed', ui._hobbyBar and ui._hobbySel, 'craft');

        ui._hobbyBar = false;
    end

    for _, k in ipairs(NAMES) do package.loaded[k] = saved[k]; end
end)();

-- ---------------------------------------------------------------------------
-- 7d. craftbar RENDER for real (the repeat-synth row, 2026-07-25). Every other
--     suite STUBS craftbar.renderContent with a no-op -- including 7c above --
--     so nothing has ever executed this file's body. That is the bit-three
--     trap: an unknown Lua name is a silent nil GLOBAL, and a load-only test
--     cannot see it. So: stub imgui + craftwatch + synthrun, drive the REAL
--     renderContent in both the idle and the running branch, and assert both
--     the stack balance and that the buttons reach synthrun.
-- ---------------------------------------------------------------------------
;(function()
    local depth = { col = 0, item = 0 };
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'Separator', 'Text', 'TextColored', 'SameLine', 'Dummy',
        'SetTooltip', 'Spacing', 'Image', 'InvisibleButton' }) do IM[n] = nop; end
    IM.PushStyleColor = function() depth.col = depth.col + 1; end
    IM.PopStyleColor  = function(n) depth.col = depth.col - (tonumber(n) or 1); end
    IM.PushItemWidth  = function() depth.item = depth.item + 1; end
    IM.PopItemWidth   = function() depth.item = depth.item - 1; end
    IM.CalcTextSize   = function(s) return #tostring(s) * 8; end
    IM.IsItemHovered  = function() return true; end        -- exercise every tooltip
    IM.IsItemClicked  = function() return false; end
    IM.GetCursorScreenPos  = function() return 0, 0; end
    IM.GetWindowDrawList   = function()
        return { AddRectFilled = nop, AddCircleFilled = nop };
    end

    local clickId, editId, editVal, itemActive = nil, nil, nil, false;
    IM.Button       = function(label) return clickId ~= nil and label:find(clickId, 1, true) ~= nil; end
    IM.IsItemActive = function() return itemActive; end
    IM.InputInt     = function(label, buf)
        if editId ~= nil and label:find(editId, 1, true) ~= nil then buf[1] = editVal; return true; end
        return false;
    end

    -- craftwatch stand-in: records what the bar writes back.
    local waitVal, wrote = 30, {};
    local CW = {
        WAIT_MIN = 20, WAIT_MAX = 120,
        getCraft = function() return 'Alchemy'; end,
        isEnabled = function() return false; end,
        setEnabled = function(v) wrote.enabled = v; end,
        selectCraft = function(c) wrote.craft = c; end,
        getGoal = function() return 'hq'; end,
        setGoal = function(g) wrote.goal = g; end,
        getSynthWait = function() return waitVal; end,
        setSynthWait = function(n) waitVal = n; wrote.wait = n; return n; end,
        lastSynth = function() return { name = 'Bronze Ingot', skill = 'Smithing', lv = 8 }; end,
    };
    -- synthrun stand-in: status drives the branch, start/stop record the click.
    local runStatus, calls = nil, {};
    local SR = {
        status = function() return runStatus; end,
        start  = function(n) calls[#calls + 1] = 'start:' .. tostring(n); return true; end,
        stop   = function() calls[#calls + 1] = 'stop'; return true; end,
    };

    local NAMES = { 'imgui', 'dlac\\feature\\craftwatch', 'dlac\\feature\\synthrun', 'dlac\\ui\\craftbar' };
    local saved = {};
    for _, k in ipairs(NAMES) do saved[k] = package.loaded[k]; end
    package.loaded['imgui'] = IM;
    package.loaded['dlac\\feature\\craftwatch'] = CW;
    package.loaded['dlac\\feature\\synthrun'] = SR;
    package.loaded['dlac\\ui\\craftbar'] = nil;

    local ok, cb = pcall(require, 'dlac\\ui\\craftbar');
    check('CB1 craftbar re-requires against a stub imgui', ok and type(cb.renderContent), 'function');
    if ok then
        -- IDLE. This single call is the whole point of the section: it executes
        -- every line of the new row, so a typo'd imgui name or a nil global
        -- fails HERE instead of in the field.
        local ran, err = pcall(cb.renderContent, 460);
        check('CB2 idle renderContent runs clean', ran, true);
        if not ran then print('  CB2 error: ' .. tostring(err)); end
        check('CB3 idle: colour stack balanced', depth.col, 0);
        check('CB4 idle: item-width stack balanced', depth.item, 0);

        -- The repeat buttons reach synthrun with the right count.
        calls = {}; clickId = '##cbrep3';
        pcall(cb.renderContent, 460);
        check('CB5 the 3 button starts a batch of 3', calls[1], 'start:3');
        calls = {}; clickId = '##cbrep6';
        pcall(cb.renderContent, 460);
        check('CB6 the 6 button starts a batch of 6', calls[1], 'start:6');
        clickId = nil;

        -- RUNNING: Last Synth becomes Stop, and the number buttons go dead.
        runStatus = { done = 2, total = 6, stage = 'cool', nextIn = 12 };
        depth.col, depth.item = 0, 0;
        local ran2 = pcall(cb.renderContent, 460);
        check('CB7 running renderContent runs clean', ran2, true);
        check('CB8 running: colour stack balanced', depth.col, 0);
        check('CB9 running: item-width stack balanced', depth.item, 0);

        calls = {}; clickId = '##cblast';
        pcall(cb.renderContent, 460);
        check('CB10 Last Synth is the Stop button mid-run', calls[1], 'stop');

        -- Locked, not merely discouraged: the click is DROPPED, so a double
        -- click can never stack a second batch on the first (Henrik).
        calls = {}; clickId = '##cbrep4';
        pcall(cb.renderContent, 460);
        check('CB11 number buttons are dead while a batch runs', #calls, 0);
        clickId = nil;

        -- The wait box is not editable mid-run either.
        wrote.wait = nil; editId = '##cbwait'; editVal = 55;
        pcall(cb.renderContent, 460);
        check('CB12 the wait box is not editable mid-run', wrote.wait, nil);

        -- IDLE again: editing commits through craftwatch.
        runStatus = nil;
        pcall(cb.renderContent, 460);
        check('CB13 editing the wait box persists it', wrote.wait, 55);

        -- Top clamps on every keystroke; the FLOOR only on blur, or typing "45"
        -- would be unreachable (you would pass 4 on the way).
        wrote.wait = nil; editVal = 999;
        pcall(cb.renderContent, 460);
        check('CB14 an over-range wait clamps to the ceiling', wrote.wait, 120);
        editId = nil; itemActive = true; waitVal = 120;
        -- simulate a half-typed value sitting in the buffer while still focused
        editId = '##cbwait'; editVal = 4; wrote.wait = nil;
        pcall(cb.renderContent, 460);
        check('CB15 a low value is NOT clamped while you are still typing', wrote.wait, nil);
        editId = nil; itemActive = false;
        pcall(cb.renderContent, 460);
        check('CB16 ...and clamps up to the floor on blur', wrote.wait, 20);
    end

    for _, k in ipairs(NAMES) do package.loaded[k] = saved[k]; end
end)();

-- ---------------------------------------------------------------------------
-- 7d. menuui RENDER stack balance (2026-07-24) -- the header Menu, the level
--     override and the Settings panel are three window-scope popups drawn in one
--     pass, and Settings pushes a style colour for the SELECTED open-mode button.
--     Same crash class as HB/S50: an unpaired EndPopup or PopStyleColor is native
--     UB inside ImGui that no pcall catches. Drive renderPopups with every popup
--     shut AND with them open, and assert every stack returns to 0.
--
--     Also pins the thing the icon column exists for: with filetex handing back nil
--     (which is exactly what it does headlessly -- no d3d, no ffi), every row must
--     STILL reserve its icon cell, so dropping the PNGs in later shifts nothing.
-- ---------------------------------------------------------------------------
;(function()
    local depth = { popup = 0, col = 0, win = 0 };
    local drew  = { dummy = 0, image = 0, selectable = 0, checkbox = 0, input = 0, imagebutton = 0 };
    local popupOpen = false;
    local function nop() end
    local IM = setmetatable({}, { __index = function() return nop; end });
    IM.BeginPopup     = function() if popupOpen then depth.popup = depth.popup + 1; end return popupOpen; end
    IM.EndPopup       = function() depth.popup = depth.popup - 1; end
    IM.PushStyleColor = function() depth.col = depth.col + 1; end
    IM.PopStyleColor  = function(n) depth.col = depth.col - (tonumber(n) or 1); end
    IM.Begin          = function() depth.win = depth.win + 1; return true; end
    IM['End']         = function() depth.win = depth.win - 1; end
    IM.Selectable     = function() drew.selectable = drew.selectable + 1; return false; end
    IM.Dummy          = function() drew.dummy = drew.dummy + 1; end
    IM.Image          = function() drew.image = drew.image + 1; end
    IM.ImageButton    = function() drew.imagebutton = drew.imagebutton + 1; return false; end
    IM.Button         = function() return false; end
    IM.SmallButton    = function() return false; end
    IM.Checkbox       = function() drew.checkbox = drew.checkbox + 1; return false; end
    IM.InputText      = function() drew.input = drew.input + 1; return false; end
    IM.IsItemHovered  = function() return false; end
    IM.GetWindowWidth = function() return 900; end

    local NAMES = { 'dlac\\ui\\menuui', 'dlac\\ui\\filetex', 'dlac\\ui\\uistyle', 'imgui' };
    local saved = {};
    for _, k in ipairs(NAMES) do saved[k] = package.loaded[k]; end

    package.loaded['imgui'] = IM;
    -- filetex returns nil headless anyway; stubbing it makes that explicit and keeps
    -- the section honest if the real one ever gains a headless path.
    package.loaded['dlac\\ui\\filetex'] = { handle = function() return nil; end };
    package.loaded['dlac\\ui\\menuui'] = nil;
    local ok, mn = pcall(require, 'dlac\\ui\\menuui');
    check('MN1 menuui re-requires against a stub imgui', ok and type(mn.renderPopups), 'function');
    if ok then
        local ui = { showAll = { false } };
        local flags = { debug = false, autosync = true, viewids = false, autobuildimport = true };
        mn.configure({
            ui = ui, COL = host.services.COL, sf = { flags = flags },
            optim = { buildAtMaxLevel = true },
            callImport = nop, dumpAugs = nop, refreshGear = nop, refreshOwnedCounts = nop,
            setVisible = nop, mainJob = function() return 5; end,
        });

        -- every popup shut: the common frame
        popupOpen = false;
        check('MN2 renders with every popup shut', pcall(mn.renderPopups), true);
        check('MN3 shut: popup stack balanced', depth.popup, 0);
        check('MN4 shut: colour stack balanced', depth.col, 0);
        check('MN5 shut: no rows drawn', drew.selectable, 0);

        -- popups open, not debugging: 6 rows, each reserving an icon cell
        popupOpen = true;
        drew.selectable, drew.dummy, drew.image = 0, 0, 0;
        check('MN6 renders with popups open', pcall(mn.renderPopups), true);
        check('MN7 open: popup stack balanced', depth.popup, 0);
        check('MN8 open: colour stack balanced', depth.col, 0);
        check('MN9 open: Begin/End balanced',   depth.win, 0);
        check('MN10 seven menu rows drawn', drew.selectable, 7);   -- +wishlist (2026-07-27)
        check('MN11 every row reserved an icon cell (no PNG -> Dummy)', drew.dummy >= 6, true);
        check('MN12 no texture drawn when filetex has none', drew.image, 0);
        -- The bodies run GUARDED, so an exception inside one would otherwise be
        -- invisible to this section and ship as a blank panel. Count what each body
        -- draws LAST-ish and assert it: the Settings panel owns 8 checkboxes, the
        -- level panel owns the typed-number InputText. If either body dies early,
        -- these drop and the section fails instead of lying.
        check('MN12a Settings body ran to completion (11 checkboxes)', drew.checkbox, 11);
        check('MN12b level body drew its typed-number box', drew.input, 1);

        -- debug on: the developer quartet appears
        flags.debug = true;
        drew.selectable = 0;
        check('MN13 renders under debug', pcall(mn.renderPopups), true);
        check('MN14 debug adds the four developer rows', drew.selectable, 11);
        check('MN15 debug: popup stack balanced', depth.popup, 0);
        check('MN16 debug: colour stack balanced', depth.col, 0);
        flags.debug = false;

        -- the Settings open-mode row tints the SELECTED button: push must be popped
        ui._openMode = 'job';
        check('MN17 renders with an open-mode selected', pcall(mn.renderPopups), true);
        check('MN18 selected-mode tint balanced', depth.col, 0);

        -- activate() routes without imgui, and arms popups by flag (never nests)
        check('MN19 teleports row arms the existing popup',
            (function() mn.activate('teleports'); return ui._tpOpen; end)(), true);
        check('MN20 level row arms the level popup',
            (function() mn.activate('level'); return ui._lvlOpen; end)(), true);
        check('MN21 settings row arms the settings popup',
            (function() mn.activate('settings'); return ui._setOpen; end)(), true);

        -- the header button entry gearui's btns loop consumes. With filetex handing
        -- back nil (the headless case) it is the labelled wide text button.
        local hb = mn.headerButton();
        check('MN22 header button is declarative', type(hb.fn), 'function');
        check('MN23 header button is labelled Menu', hb.l, 'Menu');
        check('MN24 header button click arms the menu',
            (function() hb.fn(); return ui._menuOpen; end)(), true);

        -- ...and with art present it becomes a 26px SELF-DRAWN icon button. The
        -- declared width must match what is actually drawn: gearui right-aligns the
        -- header by summing b.w, so a lying width shifts the whole row.
        package.loaded['dlac\\ui\\filetex'] = { handle = function() return 4242; end };
        local hbi = mn.headerButton();
        check('MN27 art present -> self-drawn entry', type(hbi.render), 'function');
        check('MN28 art present -> icon width', hbi.w, mn._MENU_BTN_W);
        check('MN29 art present -> no text label', hbi.l, nil);
        check('MN30 icon entry still carries the tooltip', type(hbi.tip), 'string');
        drew.imagebutton = 0;
        check('MN31 icon entry renders', pcall(hbi.render), true);
        check('MN32 icon entry drew an ImageButton', drew.imagebutton, 1);
        -- the Developer heading draws its icon once, not once per row
        ui._openMode = 'never';
        flags.debug = true;
        drew.image = 0;
        check('MN33 renders debug section with art', pcall(mn.renderPopups), true);
        check('MN34 debug heading drew one icon per row + one heading', drew.image, 8);
        check('MN35 debug section: popup stack balanced', depth.popup, 0);
        flags.debug = false;
        package.loaded['dlac\\ui\\filetex'] = { handle = function() return nil; end };

        -- auto-open: fires once for 'login', and drives gearui's visibility
        local opened = 0;
        mn.configure({
            ui = ui, COL = host.services.COL, sf = { flags = flags },
            setVisible = function(v) if v then opened = opened + 1; end end,
            mainJob = function() return 5; end,
        });
        ui._openMode, ui._autoOpened, ui._autoOpenJob = 'login', nil, nil;
        mn.autoOpenTick(); mn.autoOpenTick(); mn.autoOpenTick();
        check('MN25 login mode opens exactly once', opened, 1);
        check('MN26 auto-open remembered the job', ui._autoOpenJob, 5);
    end

    for _, k in ipairs(NAMES) do package.loaded[k] = saved[k]; end
    package.loaded['imgui'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- 7e. Mode library section RENDER (ADR 0019, 2026-07-25).
--
-- This section exists because of a bug it would have caught: the first draft called
-- a helper `helpLine()` that does not exist anywhere in the repo. Loading the module
-- proves nothing about that -- an undefined global is only an error when the line
-- actually RUNS -- and S1 merely requires triggersui. So drive the real render path
-- against a stub imgui and assert it completes AND leaves every stack balanced.
-- ---------------------------------------------------------------------------
;(function()
    local depth = { popup = 0, col = 0, win = 0, child = 0 };
    local function nop() end
    local IM = setmetatable({}, { __index = function() return nop; end });
    IM.BeginPopup     = function() return false; end     -- popups shut: the common frame
    IM.EndPopup       = function() depth.popup = depth.popup - 1; end
    IM.PushStyleColor = function() depth.col = depth.col + 1; end
    IM.PopStyleColor  = function(n) depth.col = depth.col - (tonumber(n) or 1); end
    IM.Begin          = function() depth.win = depth.win + 1; return true; end
    IM['End']         = function() depth.win = depth.win - 1; end
    IM.BeginChild     = function() depth.child = depth.child + 1; return true; end
    IM.EndChild       = function() depth.child = depth.child - 1; end
    IM.Button         = function() return false; end
    IM.SmallButton    = function() return false; end
    IM.Selectable     = function() return false; end
    IM.IsItemHovered  = function() return false; end
    IM.InputText      = function() return false; end
    IM.InputTextMultiline = function() return false; end
    IM.GetContentRegionAvail = function() return 700, 400; end
    IM.CalcTextSize   = function() return 60, 14; end

    local NAMES = { 'dlac\\ui\\triggersui', 'dlac\\gear\\modeslibrary', 'imgui' };
    local saved = {};
    for _, k in ipairs(NAMES) do saved[k] = package.loaded[k]; end

    package.loaded['imgui'] = IM;
    package.loaded['dlac\\ui\\triggersui'] = nil;
    local ok, tg = pcall(require, 'dlac\\ui\\triggersui');
    check('MLU1 triggersui re-requires against a stub imgui', ok and type(tg), 'table');
    if ok then
        check('MLU2 the Mode library section is exposed', type(tg.renderModeLibrary), 'function');
        -- Unconfigured: no deps, no character, no library file. It must still render
        -- (the empty-library case) rather than error -- this is the exact call that
        -- caught the undefined helper.
        local rok, rerr = pcall(tg.renderModeLibrary, 'WAR', 75);
        check('MLU3 renders with no deps and no library', rok, true);
        if not rok then
            check('MLU3a ...error was', tostring(rerr), '(none)');
        end
        check('MLU4 colour stack balanced', depth.col, 0);
        check('MLU5 Begin/End balanced',    depth.win, 0);
        check('MLU6 child stack balanced',  depth.child, 0);
        -- Twice in a row: the second pass exercises the cached-library path.
        check('MLU7 renders again (cached path)', pcall(tg.renderModeLibrary, 'WAR', 75), true);
        check('MLU8 still balanced', depth.col + depth.win + depth.child, 0);

        -- The per-mode "save to library" entry point. It is exposed on M ON PURPOSE:
        -- renderModeBox is defined ABOVE the library code in the chunk, so calling the
        -- local directly would resolve to a nil GLOBAL -- silent until the button is
        -- pressed. Pinning that it exists on M is pinning the fix.
        check('MLU9 per-mode capture is reachable from the mode box',
            type(tg.captureModeToLibrary), 'function');
        -- Unconfigured (no character, no data dir) it must REPORT, not throw: the mode
        -- box calls it straight from a click handler inside the render pass.
        local cok, cres = pcall(tg.captureModeToLibrary, 'DT', false);
        check('MLU10 capture never throws unconfigured', cok, true);
        check('MLU11 ...it returns a status instead', (cres == 'error' or cres == 'exists' or cres == 'added'), true);

        -- TC. Trigger CASES, read-side (issue #125, slice 1/5). The rule list is
        -- now case-aware over the EXISTING schema: a multi-condition `|` entry
        -- renders as a bordered `| case` box, single-condition entries stay
        -- standalone `|` lines, and a rule with neither renders as before.
        check('TC1 caseSplit is exposed', type(tg.caseSplit), 'function');
        if type(tg.caseSplit) == 'function' then
            local singles, cases = tg.caseSplit({ { buff = 'Sleep' }, { buff = 'Lullaby' } });
            check('TC2 single-condition entries are standalones, zero cases',
                #singles == 2 and #cases == 0, true);
            local s2, c2 = tg.caseSplit({ { buff = 'Sleep' }, { buff = 'Burst', tpabove = 1000 } });
            check('TC3 a multi-condition entry becomes a | case',
                #s2 == 1 and #c2 == 1, true);
            check('TC4 keys are lowercased for standalones',
                tg.caseSplit({ { Buff = 'Sleep' } })[1].key, 'buff');
            local a0, b0 = tg.caseSplit(nil);
            check('TC5 no whenAny -> no singles, no cases', #a0 == 0 and #b0 == 0, true);
        end
        -- Drive the REAL rule-box render: the case path only RUNS on a
        -- multi-condition rule, so a load test would never catch a nil helper.
        check('TC6 renderTrigRuleBox is exposed', type(tg.renderTrigRuleBox), 'function');
        if type(tg.renderTrigRuleBox) == 'function' then
            check('TC7 renders a case-less rule (the old path)',
                pcall(tg.renderTrigRuleBox, 'Precast', 1,
                    { when = { name = 'Cure IV' }, set = 'CureSet' }, { 'CureSet' }, 190), true);
            check('TC8 renders a rule with a standalone | condition',
                pcall(tg.renderTrigRuleBox, 'Precast', 2,
                    { when = { status = 'Engaged' }, whenAny = { { tpabove = 1000 } }, set = 'TpSet' },
                    { 'TpSet' }, 190), true);
            check('TC9 renders a rule bearing a | case box',
                pcall(tg.renderTrigRuleBox, 'Precast', 3,
                    { when = { status = 'Engaged' },
                      whenAny = { { buff = 'Burst', tpabove = 1000 }, { buff = 'Sleep' } },
                      set = 'CaseSet' }, { 'CaseSet' }, 190), true);
            check('TC10 stacks stay balanced through the case boxes',
                depth.col + depth.win + depth.child, 0);
            -- issue #126: the read-side display extends to `cases`-list rules --
            -- an `& case` (together-block member) and a `| case` with an internal
            -- OR leg, both rendered with the same bordered-box visual language.
            check('TC11 renders a rule bearing an & case (internal OR rows)',
                pcall(tg.renderTrigRuleBox, 'Precast', 4,
                    { when = { magictype = 'Black Magic' },
                      cases = { { op = '&', when = {}, whenAny = { { element = 'Fire' }, { element = 'Ice' } } } },
                      set = 'NukeSet' }, { 'NukeSet' }, 190), true);
            check('TC12 renders a | case that carries an internal OR leg',
                pcall(tg.renderTrigRuleBox, 'Precast', 5,
                    { when = { status = 'Engaged' },
                      cases = { { op = '|', when = { magictype = 'Black Magic' }, whenAny = { { element = 'Fire' } } } },
                      set = 'MixSet' }, { 'MixSet' }, 190), true);
            check('TC13 renders body + | leg + & case + | case all at once',
                pcall(tg.renderTrigRuleBox, 'Precast', 6,
                    { when = { magictype = 'Black Magic' }, whenAny = { { buff = 'Sleep' } },
                      cases = { { op = '&', when = {}, whenAny = { { element = 'Fire' } } },
                                { op = '|', when = { status = 'Engaged', tpabove = 1000 } } },
                      set = 'MaxSet' }, { 'MaxSet' }, 190), true);
            check('TC14 stacks stay balanced through the cases-list boxes',
                depth.col + depth.win + depth.child, 0);
        end
    end

    for _, k in ipairs(NAMES) do package.loaded[k] = saved[k]; end
    package.loaded['imgui'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- Trigger rule builder: the & leg never eats a value in silence.
--
-- Field case (Henrik, 2026-07-25): Item rule -> name = test [+ &] -> name =
-- testar [+ &]. The second REPLACED the first with nothing said, which reads as
-- "I cannot add & conditions any more, only |". The & leg is a MAP -- one value
-- per condition type -- and two names can never both hold, so the replace is
-- right; being silent about it was not. It now reports, and offers the one-click
-- move of BOTH values into the | leg (which is the rule he actually wanted).
--
-- Both halves are covered: the pure seams, AND the real popup driven frame by
-- frame (the craftbar lesson -- a render path no test executes is a render path
-- nobody has proven; an undefined name in it stays a silent nil global).
-- ---------------------------------------------------------------------------
;(function()
    local depth = { popup = 0, col = 0 };
    local CLICK, REC = nil, {};
    local function nop() end
    local IM = setmetatable({}, { __index = function() return nop; end });
    IM.BeginPopup = function(id)
        if tostring(id) == '##dlac_trigadd' then depth.popup = depth.popup + 1; return true; end
        return false;
    end
    IM.EndPopup   = function() depth.popup = depth.popup - 1; end
    IM.PushStyleColor = function() depth.col = depth.col + 1; end
    IM.PopStyleColor  = function(n) depth.col = depth.col - (tonumber(n) or 1); end
    IM.Begin      = function() return true; end
    IM['End']     = nop;
    IM.BeginChild = function() return true; end
    IM.EndChild   = nop;
    IM.BeginCombo = function() return false; end
    IM.BeginMenu  = function() return false; end
    IM.Button      = function(l) REC[#REC + 1] = tostring(l); return tostring(l) == CLICK; end
    IM.SmallButton = function(l) REC[#REC + 1] = tostring(l); return tostring(l) == CLICK; end
    IM.Selectable  = function(l) REC[#REC + 1] = tostring(l); return tostring(l) == CLICK; end
    IM.Text        = function(t) REC[#REC + 1] = tostring(t); end
    IM.TextColored = function(_, t) REC[#REC + 1] = tostring(t); end
    IM.IsItemHovered = function() return false; end
    IM.InputText   = function() return false; end
    IM.InputInt    = function() return false; end
    IM.GetContentRegionAvail = function() return 700, 400; end
    IM.CalcTextSize = function() return 60, 14; end

    local NAMES = { 'dlac\\ui\\triggersui', 'imgui' };
    local saved = {};
    for _, k in ipairs(NAMES) do saved[k] = package.loaded[k]; end
    package.loaded['imgui'] = IM;
    package.loaded['dlac\\ui\\triggersui'] = nil;
    local ok, tg = pcall(require, 'dlac\\ui\\triggersui');
    check('TB1 triggersui re-requires against a stub imgui', ok and type(tg), 'table');
    if ok then
        check('TB2 the condition-push core is exposed', type(tg._pushCond), 'function');
        check('TB3 the OR escape is exposed',           type(tg._orBothToAny), 'function');

        local conds = {};
        check('TB4 the first & condition lands', (function()
            local note = tg._pushCond(conds, 'name', 'test', false);
            return tostring(#conds) .. '/' .. tostring(note);
        end)(), '1/nil');
        local note = tg._pushCond(conds, 'name', 'testar', false);
        check('TB5 a second value of the same type replaces (the map shape)', #conds, 1);
        check('TB6 ...and never in silence', type(note), 'string');
        check('TB7 ...naming the swap it made', note:find('test -> testar', 1, true) ~= nil, true);
        check('TB8 ...keeping the newest value', conds[1].value, 'testar');

        -- Re-adding the SAME value is a no-op, not an alarm.
        local same = { { key = 'name', value = 'test' } };
        check('TB9 re-adding an identical value says nothing', tg._pushCond(same, 'name', 'test', false), nil);

        -- An EDITED rule loads its keys lowercased off the file while the pickers
        -- spell them as the def does; the save lowercases both. A case-sensitive
        -- test let two rows of one type stack, of which the save kept one -- silently.
        local drift = { { key = 'magictype', value = 'White Magic' } };
        tg._pushCond(drift, 'magicType', 'Black Magic', false);
        check('TB10 a case-drifted key is the SAME condition type', #drift, 1);

        local ors = {};
        tg._pushCond(ors, 'buff', 'Sleep', true);
        tg._pushCond(ors, 'buff', 'Lullaby', true);
        check('TB11 the | leg still stacks duplicates', #ors, 2);

        local swapped = { { key = 'name', value = 'testar' } };
        check('TB12 the OR escape reports the move',
            tg._orBothToAny(swapped, { key = 'name', prev = 'test', cur = 'testar' }), true);
        check('TB13 ...both values survive it', #swapped, 2);
        check('TB14 ...on the | leg, in order',
            string.format('%s%s/%s%s', tostring(swapped[1].value), swapped[1].any and '|' or '&',
                                       tostring(swapped[2].value), swapped[2].any and '|' or '&'),
            'test|/testar|');
        check('TB15 a junk swap is refused', tg._orBothToAny({}, nil), false);

        -- ---- the REAL popup, frame by frame ----
        local UP = {};
        for i = 1, 250 do
            local n, v = debug.getupvalue(tg.render, i);
            if n == nil then break; end
            UP[n] = v;
        end
        local trig, popup = UP.trig, UP.renderTrigAddPopup;
        check('TB16 the builder state and its popup are reachable',
            (type(trig) == 'table') and type(popup), 'function');
        if type(trig) == 'table' and type(popup) == 'function' then
            local function frame(click)
                CLICK, REC = click, {};
                local fok, ferr = pcall(popup);
                if not fok then print('   (TB popup error: ' .. tostring(ferr) .. ')'); end
                return fok;
            end
            trig.data = {};                    -- a loaded model, as M.render guarantees
            trig.addFor, trig.addConds, trig._addDef = 'Item', {}, 1;
            trig.addValText[1] = ''; trig._addValSel = nil; trig.addValNum[1] = 0;
            trig.addSet, trig.addPrio[1] = 'Bait', 0;
            trig.addNote, trig.addSwap = nil, nil;
            trig.editIdx, trig._editEquip, trig._bpEdit = nil, nil, nil;

            trig.addValText[1] = 'test';
            check('TB17 the popup renders and the & click lands', frame('+ & condition##trgac'), true);
            check('TB18 ...one pending condition', #trig.addConds, 1);
            trig.addValText[1] = 'testar';
            check('TB19 the second & click renders', frame('+ & condition##trgac'), true);
            check('TB20 ...still one (replaced, not stacked)', #trig.addConds, 1);
            check('TB21 ...carrying a note to show', type(trig.addNote), 'string');

            check('TB22 the note frame renders', frame(nil), true);
            local sawNote, sawSwap = false, false;
            for _, l in ipairs(REC) do
                if l:find('replaced', 1, true) then sawNote = true; end
                if l:find('trgorboth', 1, true) then sawSwap = true; end
            end
            check('TB23 ...the note is on screen', sawNote, true);
            check('TB24 ...beside its escape button', sawSwap, true);

            check('TB25 the escape click renders', frame('Match either instead##trgorboth'), true);
            check('TB26 ...both values move to the | leg', #trig.addConds, 2);
            check('TB27 ...and the note is spent', trig.addNote, nil);

            frame('Add rule###trgaddgo');
            local r = trig.data.Item and trig.data.Item[1];
            check('TB28 Save writes the rule',        type(r), 'table');
            check('TB29 ...as an either-name rule',   (type(r) == 'table') and #(r.whenAny or {}), 2);
            check('TB30 ...with an empty & leg',      (type(r) == 'table') and next(r.when or {}), nil);
            check('TB31 the popup stack stayed balanced', depth.popup, 0);
            check('TB32 the colour stack stayed balanced', depth.col, 0);
        end
    end

    for _, k in ipairs(NAMES) do package.loaded[k] = saved[k]; end
    package.loaded['imgui'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- LSP. The Sets tab's Equip & Lock popup (Strict / Loose), pinned as SOURCE.
--
-- The Sets tab render has no smoke drive -- only its tab LABEL is checked (S9) --
-- so this block is the one thing standing between a typo and a button that opens
-- nothing in the field. An OpenPopup id that does not match its BeginPopup id
-- fails SILENTLY: the click registers, no menu appears, and nothing is logged.
-- A source pin cannot tell you the popup renders; it can tell you the two ids
-- agree and that both variants are still wired to a real command word.
-- ---------------------------------------------------------------------------
(function()
    local f = io.open('ui/gearui.lua', 'r');
    check('LSP0 gearui is readable', f ~= nil, true);
    if f == nil then return; end
    local src = f:read('*a'); f:close();

    local opened = src:match("OpenPopup%('(##dlac_lockmode[%w_]*)'%)");
    local begun  = src:match("BeginPopup%('(##dlac_lockmode[%w_]*)'%)");
    check('LSP1 Equip & Lock opens a popup',        opened ~= nil, true);
    check('LSP2 ...and something begins it',        begun ~= nil, true);
    check('LSP3 ...under the SAME id (a mismatch opens nothing, silently)', opened, begun);
    check('LSP4 the popup is closed',               src:find('imgui.EndPopup();', 1, true) ~= nil, true);

    -- Both variants, and the exact command words the engine whitelists. A
    -- renamed word here would queue a command /dl lock falls through in silence.
    check('LSP5 Strict is offered', src:find("Selectable('Strict##lockstrict')", 1, true) ~= nil, true);
    check('LSP6 Loose is offered',  src:find("Selectable('Loose##lockloose')", 1, true) ~= nil, true);
    check('LSP7 Strict fires the strict word', src:find("lockAs('set', 'strict')", 1, true) ~= nil, true);
    check('LSP8 Loose fires the loose word',   src:find("lockAs('set-loose', 'loose')", 1, true) ~= nil, true);
    local D = require('dlac\\dispatch');
    check('LSP9 ...and both words are real lock-set modes',
        D._lockSetModes['set'] ~= nil and D._lockSetModes['set-loose'] ~= nil, true);

    -- The hover is three lines and stays three lines (Henrik, 2026-07-26: "there
    -- is TOOOOO much text... this is minimalistic and every word matters").
    local tip = src:match("SetTooltip%('(Locks current set[^\n]-)'%s*%.%.");
    check('LSP10 the hover opens with the one-line what-it-does', tip ~= nil, true);
end)();

-- ---------------------------------------------------------------------------
-- TE. Trigger CASES, edit-side (issue #127, slice 3/5). The rule builder gains
-- two buttons (+ & case / + | case) and renders added cases as bordered boxes,
-- each hosting the IDENTICAL picker flow. Two halves, both proven: the pure
-- model seams (loadCases / buildLegs / buildCases -- the flatten-fix and the
-- oldest-form round-trip), AND the real popup driven frame by frame (add a case,
-- add conditions inside it, save, assert widget labels + stack balance -- the
-- craftbar lesson: an unrun render path is an unproven one).
-- ---------------------------------------------------------------------------
;(function()
    local depth = { popup = 0, col = 0, child = 0, win = 0 };
    local CLICK, REC = nil, {};
    local function nop() end
    local IM = setmetatable({}, { __index = function() return nop; end });
    IM.BeginPopup = function(id)
        if tostring(id) == '##dlac_trigadd' then depth.popup = depth.popup + 1; return true; end
        return false;
    end
    IM.EndPopup   = function() depth.popup = depth.popup - 1; end
    IM.PushStyleColor = function() depth.col = depth.col + 1; end
    IM.PopStyleColor  = function(n) depth.col = depth.col - (tonumber(n) or 1); end
    IM.Begin      = function() depth.win = depth.win + 1; return true; end
    IM['End']     = function() depth.win = depth.win - 1; end
    IM.BeginChild = function() depth.child = depth.child + 1; return true; end
    IM.EndChild   = function() depth.child = depth.child - 1; end
    IM.BeginCombo = function(l) REC[#REC + 1] = tostring(l); return false; end
    IM.BeginMenu  = function() return false; end
    IM.Button      = function(l) REC[#REC + 1] = tostring(l); return tostring(l) == CLICK; end
    IM.SmallButton = function(l) REC[#REC + 1] = tostring(l); return tostring(l) == CLICK; end
    IM.Selectable  = function(l) REC[#REC + 1] = tostring(l); return tostring(l) == CLICK; end
    IM.Text        = function(t) REC[#REC + 1] = tostring(t); end
    IM.TextColored = function(_, t) REC[#REC + 1] = tostring(t); end
    IM.IsItemHovered = function() return false; end
    IM.InputText   = function() return false; end
    IM.InputInt    = function() return false; end
    IM.GetContentRegionAvail = function() return 700, 400; end
    IM.CalcTextSize = function() return 60, 14; end

    local NAMES = { 'dlac\\ui\\triggersui', 'imgui' };
    local saved = {};
    for _, k in ipairs(NAMES) do saved[k] = package.loaded[k]; end
    package.loaded['imgui'] = IM;
    package.loaded['dlac\\ui\\triggersui'] = nil;
    local ok, tg = pcall(require, 'dlac\\ui\\triggersui');
    check('TE1 triggersui re-requires against a stub imgui', ok and type(tg), 'table');
    local D = require('dlac\\dispatch');
    if ok then
        check('TE2 the load seam is exposed',  type(tg._loadCases),  'function');
        check('TE3 the leg builder is exposed', type(tg._buildLegs),  'function');
        check('TE4 the case builder is exposed', type(tg._buildCases), 'function');
        check('TE5 the empty-case guard is exposed', type(tg._hasEmptyCase), 'function');

        -- ---- LOAD: the flatten-corruption fix ----
        -- A single-condition | entry stays a body | row; a MULTI-condition entry
        -- (AND-within-OR) loads as a `| case` box instead of flattening.
        local conds, cases = tg._loadCases({
            when = { name = 'Slow' },
            whenAny = { { mode = 'DT' }, { mode = 'Refresh', hpbelow = 50 } } });
        check('TE6 the & body condition loads', #conds, 2);   -- name + single-| DT row
        local sawSingle = false;
        for _, c in ipairs(conds) do if c.any and c.key == 'mode' and c.value == 'DT' then sawSingle = true; end end
        check('TE7 a single-condition | entry stays a body | row', sawSingle, true);
        check('TE8 a multi-condition | entry becomes ONE | case (not two flat rows)',
            #cases == 1 and cases[1].op, '|');
        check('TE9 ...carrying BOTH its conditions as & rows', #cases[1].conds, 2);

        -- ---- BUILD + SERIALIZE: byte-identical round-trip (the flatten fix) ----
        -- A hand-written multi-condition | rule, loaded then rebuilt through the
        -- editor's seams, must re-serialize byte-for-byte (oldest-form-first: the
        -- | case of only & rows folds back to a whenAny multi-entry, no guard).
        local orig = { Item = { { when = { name = 'Slow' },
            whenAny = { { mode = 'DT', hpbelow = 50 } }, set = 'X' } } };
        local text0 = D.serializeTriggers(orig);
        local c2, cs2 = tg._loadCases(orig.Item[1]);
        local when2, wa2 = tg._buildLegs(c2);
        local rebuilt = { Item = { { when = when2, whenAny = wa2,
            cases = tg._buildCases(cs2), set = 'X' } } };
        local text1 = D.serializeTriggers(rebuilt);
        check('TE10 a multi-condition | rule re-saves BYTE-IDENTICALLY (flatten fix)', text1, text0);
        check('TE11 ...still the oldest form -- no cases list, no guard',
            text1:find('cases', 1, true) == nil and text1:find('hasCases', 1, true) == nil, true);

        -- ---- BUILD: (A & B) | (C & D) fires per the semantics ----
        -- Body = case 1 = (Engaged & TP>1000); a | case = (BlackMagic & Fire).
        local when3, wa3 = tg._buildLegs({ { key = 'status', value = 'Engaged' },
                                           { key = 'tpabove', value = 1000 } });
        local rule3 = { when = when3, whenAny = wa3, cases = tg._buildCases({
            { op = '|', conds = { { key = 'magictype', value = 'Black Magic' },
                                  { key = 'element', value = 'Fire' } } } }) };
        check('TE12 (A&B)|(C&D): body leg fires alone',
            D._matches(rule3, { player = { Status = 'Engaged', TP = 1500 } }), true);
        check('TE13 ...the | case fires alone',
            D._matches(rule3, { action = { Type = 'Black Magic', Element = 'Fire' },
                                player = { Status = 'Idle', TP = 0 } }), true);
        check('TE14 ...neither -> no fire',
            D._matches(rule3, { action = { Type = 'Black Magic', Element = 'Ice' },
                                player = { Status = 'Idle', TP = 0 } }), false);

        -- ---- BUILD: (A | B) & (C | D) gates per the semantics ----
        -- BlackMagic & (Fire|Ice) & (Sleep|Lullaby): two & cases, each internal OR.
        local when4, wa4 = tg._buildLegs({ { key = 'magictype', value = 'Black Magic' } });
        local rule4 = { when = when4, whenAny = wa4, cases = tg._buildCases({
            { op = '&', conds = { { key = 'element', value = 'Fire', any = true },
                                  { key = 'element', value = 'Ice', any = true } } },
            { op = '&', conds = { { key = 'buff', value = 'Sleep', any = true },
                                  { key = 'buff', value = 'Lullaby', any = true } } } }) };
        check('TE15 (A|B)&(C|D): all three groups hold -> fire',
            D._matches(rule4, { action = { Type = 'Black Magic', Element = 'Fire' },
                                buffs = { sleep = true } }), true);
        check('TE16 ...one & case misses -> no fire (AND gates)',
            D._matches(rule4, { action = { Type = 'Black Magic', Element = 'Fire' },
                                buffs = {} }), false);

        -- ---- the empty-case guard (never saved silently) ----
        check('TE17 an empty case is flagged', tg._hasEmptyCase({ { op = '&', conds = {} } }), true);
        check('TE18 a filled case is not', tg._hasEmptyCase({ { op = '&', conds = { { key = 'x', value = 1 } } } }), false);
        check('TE19 buildCases drops an empty case as a last defense',
            tg._buildCases({ { op = '|', conds = {} } }), nil);

        -- ---- a combined | entry INSIDE a case splits LOUDLY ----
        -- The engine honors { whenAny = { { a, b } } } inside a case as
        -- AND-within-OR; the editor cannot represent that depth (one-tier cap)
        -- and splits it to standalone singles -- which WIDENS the rule. The & leg's
        -- law applies one tier down: the split is fine, silence would be the bug.
        local c4, cs4 = tg._loadCases({ when = { name = 'X' },
            cases = { { op = '&', whenAny = { { buff = 'Sleep', hpbelow = 25 } } } } });
        check('TE43 the combined entry splits to standalone | rows', (#cs4 == 1) and #cs4[1].conds, 2);
        check('TE44 ...and the case carries a note, never silence',
            (#cs4 == 1) and (cs4[1].note ~= nil) and (c4 ~= nil), true);

        -- ---- case 1's own op (Henrik's field read 2026-07-26) ----
        -- An empty-body rule (pure-OR) seats its first case as case 1, op and
        -- all, so the editor never shows an empty un-savable body box.
        local c5, cs5, op5 = tg._loadCases({ when = {},
            cases = { { op = '|', when = { name = 'a', hpbelow = 10 } },
                      { op = '&', when = { status = 'Engaged' } } } });
        check('TE45 an empty-body rule seats its first case as case 1 (op rides along)',
            (op5 == '|') and (#c5 == 2) and (#cs5 == 1) and cs5[1].op, '&');

        -- buildRuleShape: case 1 flipped to OR saves an EMPTY body, its rows
        -- riding the cases list as the leading | case.
        local w6, a6, cl6 = tg._buildRuleShape(
            { { key = 'name', value = 'x' }, { key = 'element', value = 'Fire', any = true } }, '|',
            { { op = '&', conds = { { key = 'status', value = 'Engaged' } } } });
        check('TE46 case 1 = OR: the saved body empties and case 1 leads the list',
            (next(w6) == nil) and (a6 == nil) and (#cl6 == 2) and cl6[1].op == '|'
            and cl6[1].when.name == 'x' and (#(cl6[1].whenAny or {}) == 1) and cl6[2].op, '&');

        -- A pure-OR rule (old whenAny-only form) must survive the case-1 seat
        -- byte-for-byte: promoted on load, re-folded oldest-form on save.
        local orig2 = { Item = { { when = {}, whenAny = { { mode = 'DT', hpbelow = 50 } }, set = 'X' } } };
        local t0 = D.serializeTriggers(orig2);
        local c7, cs7, op7 = tg._loadCases(orig2.Item[1]);
        local w7, a7, cl7 = tg._buildRuleShape(c7, op7, cs7);
        local rb7 = { Item = { { when = w7, whenAny = a7, cases = cl7, set = 'X' } } };
        check('TE47 a pure-OR rule round-trips BYTE-IDENTICALLY through the case-1 seat',
            D.serializeTriggers(rb7), t0);

        -- The engine law the OR-flip leans on: an empty together-block never
        -- fires the rule (OR-only is never always-on) -- matches() nAnd gate.
        check('TE48 the OR-only law: an empty together-block never fires the rule',
            D._matches({ when = {}, cases = { { op = '|', when = { name = 'zzz' } } } },
                { action = { Type = 'Black Magic', Element = 'Fire' },
                  player = { Status = 'Idle', TP = 0 } }), false);

        -- ---- canonical case legs (field round 2 -- Henrik's /dl why screen) ----
        -- A lone `+ |` condition inside a case must not save an empty-&-leg case
        -- ({ when = {}, whenAny = { {..} } }): identical meaning, noisier label
        -- ('any|'), a 'case (x)' /dl why name instead of 'standalone x', and a
        -- version guard the rule does not need.
        local clF = tg._buildCases({ { op = '|',
            conds = { { key = 'status', value = 'Resting', any = true } } } });
        check('TE54 a lone | condition folds into the case & leg',
            (#clF == 1) and (clF[1].whenAny == nil) and clF[1].when.status, 'Resting');
        -- Henrik's exact field rule: case 1 = OR (status=Engaged via + |), plus
        -- a | case (status=Resting via + |). Must serialize as the OLD pure-OR
        -- form -- no cases list, no guard.
        local wH, aH, clH = tg._buildRuleShape(
            { { key = 'status', value = 'Engaged', any = true } }, '|',
            { { op = '|', conds = { { key = 'status', value = 'Resting', any = true } } } });
        local tH = D.serializeTriggers({ Item = { { when = wH, whenAny = aH, cases = clH, set = 'T' } } });
        local tCanon = D.serializeTriggers({ Item = { { when = {},
            whenAny = { { status = 'Engaged' }, { status = 'Resting' } }, set = 'T' } } });
        check('TE55 the field rule (both conds via + |) folds to the old pure-OR form', tH, tCanon);
        check('TE56 ...and carries no version guard', tH:find('hasCases', 1, true) == nil, true);

        -- copyConds (issue #128): an EDITABLE duplicate. Editing the copy must
        -- never reach back into the original -- rows AND a table value (mode list)
        -- are both cloned.
        local src = { { key = 'name', value = 'test' },
                      { key = 'element', value = 'Fire', any = true },
                      { key = 'mode', value = { 'DT', 'Idle' } } };
        local dup = tg._copyConds(src);
        check('TE57 copyConds duplicates every row, op flags and all',
            (#dup == 3) and dup[1].key == 'name' and dup[1].value == 'test'
            and dup[2].any == true and dup[3].key == 'mode', true);
        dup[1].value = 'CHANGED'; dup[3].value[1] = 'GONE';
        check('TE58 the duplicate is independent -- editing it never touches the original',
            (src[1].value == 'test') and (src[3].value[1] == 'DT'), true);

        -- ---- the REAL popup, frame by frame ----
        local UP = {};
        for i = 1, 250 do
            local n, v = debug.getupvalue(tg.render, i);
            if n == nil then break; end
            UP[n] = v;
        end
        local trig, popup = UP.trig, UP.renderTrigAddPopup;
        check('TE20 the builder state and its popup are reachable',
            (type(trig) == 'table') and type(popup), 'function');
        if type(trig) == 'table' and type(popup) == 'function' then
            local function frame(click)
                CLICK, REC = click, {};
                local fok, ferr = pcall(popup);
                if not fok then print('   (TE popup error: ' .. tostring(ferr) .. ')'); end
                return fok, REC;
            end
            local function fresh()
                trig.data = {};
                trig.addFor, trig.addConds, trig.addCases, trig._addDef = 'Item', {}, {}, 1;
                trig.addBodyOp = '&';
                trig.addValText[1] = ''; trig._addValSel = nil; trig.addValNum[1] = 0;
                trig.addSet, trig.addPrio[1] = 'Bait', 0;
                trig.addNote, trig.addSwap = nil, nil;
                trig.editIdx, trig._editEquip, trig._bpEdit = nil, nil, nil;
            end
            local function sawIn(rec, needle)
                for _, l in ipairs(rec) do if l:find(needle, 1, true) then return true; end end
                return false;
            end

            -- Scenario A: build a | case with an internal OR, end to end.
            fresh();
            trig.addValText[1] = 'test';
            check('TE21 the popup renders; the body & click lands', (frame('+ & condition##trgac')), true);
            check('TE22 ...one body condition', #trig.addConds, 1);
            local _, rec2 = frame(nil);
            check('TE23 both case buttons are on screen', sawIn(rec2, '+ & case##trgaddandcase') and sawIn(rec2, '+ | case##trgaddorcase'), true);
            frame('+ | case##trgaddorcase');
            check('TE24 + | case creates a box', #trig.addCases, 1);
            check('TE25 ...of the right kind', trig.addCases[1].op, '|');
            local _, rec3 = frame(nil);
            check('TE26 the case box header + delete render', sawIn(rec3, '| case') and sawIn(rec3, 'x##trgdelcase1'), true);
            trig.addValText[1] = 'alpha';
            frame('+ & condition##trgaccase1');
            check('TE27 a condition adds INSIDE the case', #trig.addCases[1].conds, 1);
            trig.addValText[1] = 'beta';
            frame('+ | condition##trgoccase1');
            check('TE28 ...and stacks a second on the | leg', #trig.addCases[1].conds, 2);
            frame('Add rule###trgaddgo');
            local r = trig.data.Item and trig.data.Item[1];
            check('TE29 Save writes the rule',        type(r), 'table');
            check('TE30 ...body & leg is the together-block', (type(r) == 'table') and r.when.name, 'test');
            check('TE31 ...with one case', (type(r) == 'table') and r.cases and #r.cases, 1);
            check('TE32 ...a | case carrying an internal OR',
                (type(r) == 'table' and r.cases) and (r.cases[1].op == '|'
                    and r.cases[1].when.name == 'alpha' and #(r.cases[1].whenAny or {}) == 1), true);

            -- Scenario B: an empty case is refused, then saved once filled.
            fresh();
            trig.addValText[1] = 'anchor'; frame('+ & condition##trgac');
            frame('+ & case##trgaddandcase');
            check('TE33 an empty & case exists', #trig.addCases, 1);
            local _, recB = frame('Add rule###trgaddgo');
            check('TE34 Save is refused while a case is empty', trig.data.Item, nil);
            check('TE35 ...with a notice, not silence', sawIn(recB, 'A case has no conditions'), true);
            trig.addValText[1] = 'filled'; frame('+ & condition##trgaccase1');
            frame('Add rule###trgaddgo');
            check('TE36 ...once filled, it saves', (trig.data.Item and #trig.data.Item), 1);

            -- Scenario C: delete removes the box; deleting the last clears all chrome.
            fresh();
            trig.addValText[1] = 'anchor'; frame('+ & condition##trgac');
            frame('+ | case##trgaddorcase');
            check('TE37 a case exists to delete', #trig.addCases, 1);
            frame('x##trgdelcase1');
            check('TE38 delete removes the case', #trig.addCases, 0);
            local _, recC = frame(nil);
            -- The per-box delete affordance exists ONLY inside a case box, so its
            -- absence proves the box chrome is gone (the two add buttons remain,
            -- and their labels contain "| case" -- which is why we test the delete).
            check('TE39 ...and all case chrome is gone (only the two buttons remain)',
                sawIn(recC, 'x##trgdelcase') == false, true);

            -- Scenario D: the shared picker sits at the TOP, outside every
            -- container (Henrik's field read 2026-07-26: rendered between the
            -- body rows and the boxes it read as owned by case 1 forever) --
            -- picker first, then the body rows, then the body's own buttons.
            local function idxOf(rec, needle)
                for i, l in ipairs(rec) do if l:find(needle, 1, true) then return i; end end
                return nil;
            end
            fresh();
            trig.addValText[1] = 'anchor'; frame('+ & condition##trgac');
            local _, recD = frame(nil);
            local iPick = idxOf(recD, '###trgcondbtn');
            local iRow  = idxOf(recD, '= anchor');
            local iBtn  = idxOf(recD, '+ & condition##trgac');
            check('TE49 the picker renders on top, body rows next, the body buttons after',
                (iPick ~= nil and iRow ~= nil and iBtn ~= nil)
                and (iPick < iRow) and (iRow < iBtn), true);

            -- Scenario E: once boxes exist the body renders as CASE 1 -- a box
            -- with the same top-right AND/OR selection every case has -- and
            -- flipping case 1 to OR saves an empty body (the engine's OR-only
            -- law keeps it from being always-on). The stub's combos never open,
            -- so the flip itself is driven by setting the state the combo sets.
            fresh();
            trig.addValText[1] = 'anchor'; frame('+ & condition##trgac');
            frame('+ & case##trgaddandcase');
            trig.addValText[1] = 'other'; frame('+ & condition##trgaccase1');
            local _, recE = frame(nil);
            check('TE50 every box carries the AND/OR selection, case 1 included',
                sawIn(recE, '##trgcaseopbody') and sawIn(recE, '##trgcaseopcase1'), true);
            local flatBtn = false;
            for _, l in ipairs(recE) do if l == '+ & condition##trgac' then flatBtn = true; end end
            check('TE51 the flat body chrome is gone in box mode (case 1 owns its buttons)',
                (not flatBtn) and sawIn(recE, '+ & condition##trgacbody'), true);
            trig.addBodyOp = '|';
            frame('Add rule###trgaddgo');
            local rE = trig.data.Item and trig.data.Item[1];
            check('TE52 case 1 = OR saves an EMPTY body with case 1 riding the | tier',
                (type(rE) == 'table') and (next(rE.when or { x = 1 }) == nil)
                and rE.cases and #rE.cases == 2 and rE.cases[1].op == '|'
                and rE.cases[1].when.name == 'anchor' and rE.cases[2].op, '&');

            -- Scenario F: deleting case 1 promotes the next case into the seat.
            fresh();
            trig.addValText[1] = 'anchor'; frame('+ & condition##trgac');
            frame('+ | case##trgaddorcase');
            trig.addValText[1] = 'alt'; frame('+ & condition##trgaccase1');
            frame('x##trgdelbody');
            check('TE53 deleting case 1 promotes the next case into the seat, op and all',
                (#trig.addCases == 0) and (#trig.addConds == 1)
                and (trig.addConds[1].value == 'alt') and trig.addBodyOp, '|');

            -- Scenario G: copy case (issue #128). In box mode the body is case 1
            -- with its own copy affordance, so "copy the rule body into a new
            -- case" is just copying case 1; copying an added case duplicates it.
            fresh();
            trig.addValText[1] = 'anchor'; frame('+ & condition##trgac');
            frame('+ | case##trgaddorcase');            -- body becomes case 1 (a box)
            trig.addValText[1] = 'alt'; frame('+ & condition##trgaccase1');
            local _, recG = frame(nil);
            check('TE59 every box has a copy affordance, case 1 (the body) included',
                sawIn(recG, 'copy##trgcopybody') and sawIn(recG, 'copy##trgcopycase1'), true);
            frame('copy##trgcopybody');                  -- copy the rule body into a new case
            local dupB = trig.addCases[2];
            check('TE60 copying case 1 appends a new case duplicating the body',
                (#trig.addCases == 2) and (dupB ~= nil) and (dupB.op == '&')
                and (type(dupB.conds) == 'table') and (#dupB.conds == 1)
                and (dupB.conds[1].value == 'anchor'), true);
            trig.addConds[1].value = 'edited';           -- mutate the body...
            check('TE61 the duplicate is independent of the body it was copied from',
                (dupB and dupB.conds and dupB.conds[1] and dupB.conds[1].value) or nil, 'anchor');
            frame('copy##trgcopycase1');                 -- copy an added case
            local dupC = trig.addCases[3];
            check('TE62 copying an added case appends a duplicate of the right kind',
                (#trig.addCases == 3) and (dupC ~= nil) and (dupC.op == '|')
                and (type(dupC.conds) == 'table') and (dupC.conds[1] ~= nil)
                and (dupC.conds[1].value == 'alt'), true);

            -- Scenario H: the repeat-replaces note and "Match either instead"
            -- escape behave INSIDE a case exactly as in the body (issue #128).
            fresh();
            trig.addValText[1] = 'anchor'; frame('+ & condition##trgac');
            frame('+ & case##trgaddandcase');            -- body -> case 1; a fresh & case
            trig.addValText[1] = 'foo'; frame('+ & condition##trgaccase1');
            trig.addValText[1] = 'bar'; frame('+ & condition##trgaccase1');   -- same type: replaces
            check('TE63 a repeated & type inside a case replaces, and says so (not silent)',
                (#trig.addCases[1].conds == 1) and (trig.addCases[1].conds[1].value == 'bar')
                and (trig.addCases[1].note ~= nil) and (trig.addCases[1].swap ~= nil), true);
            local _, recH = frame(nil);
            check('TE64 the "Match either instead" escape renders on the case box',
                sawIn(recH, 'Match either instead##trgorbothcase1'), true);
            frame('Match either instead##trgorbothcase1');
            local hc = trig.addCases[1];
            check('TE65 the escape moves BOTH values to the case | leg, note cleared',
                (hc ~= nil) and (#hc.conds == 2) and hc.conds[1].any
                and hc.conds[2].any and (hc.note == nil), true);

            -- Scenario I: a case-bearing rule captured as a Blueprint carries its
            -- cases verbatim (issue #128 edge case: blueprint capture from the
            -- editor's case-bearing state). Build the rule, then round-trip its
            -- saved shape through loadCases -> buildRuleShape and byte-compare the
            -- serialized form -- the path a Blueprint stamp/share takes.
            fresh();
            trig.addValText[1] = 'body'; frame('+ & condition##trgac');
            frame('+ & case##trgaddandcase');
            trig.addValText[1] = 'inside'; frame('+ | condition##trgoccase1');
            trig.addValText[1] = 'more';   frame('+ | condition##trgoccase1');
            frame('Add rule###trgaddgo');
            local rI = trig.data.Item and trig.data.Item[1];
            check('TE66a the case-bearing rule saved (a Blueprint would capture this shape)',
                (type(rI) == 'table') and (type(rI.cases) == 'table') and (#rI.cases == 1), true);
            if type(rI) == 'table' then
                local before = D.serializeTriggers({ Item = { rI } });
                local cI, csI, opI = tg._loadCases(rI);
                local wI, aI, clI = tg._buildRuleShape(cI, opI, csI);
                local rebuilt = { when = wI, whenAny = aI, cases = clI, set = rI.set };
                check('TE66 a case-bearing rule round-trips byte-identically (the Blueprint path)',
                    D.serializeTriggers({ Item = { rebuilt } }), before);
            end

            check('TE40 the popup stack stayed balanced', depth.popup, 0);
            check('TE41 the colour stack stayed balanced', depth.col, 0);
            check('TE42 the child stack stayed balanced', depth.child, 0);
        end
    end

    for _, k in ipairs(NAMES) do package.loaded[k] = saved[k]; end
    package.loaded['imgui'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- AU. ammoui RENDER for real (the Range-aware type tabs, v128). Until now this
--     file's render half had NEVER been executed by any test -- S135-S137 only
--     touch the headless status contract above the imgui guard -- which is the
--     craftbar/bit-three trap exactly: an unknown Lua name is a silent nil
--     GLOBAL and a load-only test cannot see it. The tab strip pushes a style
--     colour INSIDE a loop, the S50 crash class (unbalanced push = native UB in
--     ImGui, no Lua error, whole client down), so drive the real render once per
--     weapon branch and assert every stack lands back on zero.
-- ---------------------------------------------------------------------------
;(function()
    local depth = { col = 0, id = 0, width = 0 };
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'Separator', 'Text', 'SameLine', 'Dummy',
        'SetTooltip', 'Spacing', 'Image', 'InvisibleButton' }) do IM[n] = nop; end
    -- RECORDED, not a no-op (v134): the level column and the live row say what
    -- they say in COLOUR, so a harness that throws the colour away cannot see
    -- either of them.
    local painted = {};   -- { { c = <colour>, t = <text> }, ... }
    IM.TextColored = function(c, t) painted[#painted + 1] = { c = c, t = tostring(t) }; end
    -- Which colour did this exact string come out in? ammoui's palette, by hue.
    local function hueOf(txt)
        for _, e in ipairs(painted) do
            if e.t == txt and type(e.c) == 'table' then
                local r, g = e.c[1] or 0, e.c[2] or 0;
                if r > 0.9 and g < 0.6 then return 'red'; end
                if g > 0.85 and r < 0.6 then return 'green'; end
                if r > 0.5 and r < 0.6 and g > 0.5 and g < 0.6 then return 'dim'; end
                return 'other';
            end
        end
        return nil;
    end
    IM.PushStyleColor  = function() depth.col = depth.col + 1; end
    IM.PopStyleColor   = function(n) depth.col = depth.col - (tonumber(n) or 1); end
    IM.PushID          = function() depth.id = depth.id + 1; end
    IM.PopID           = function() depth.id = depth.id - 1; end
    IM.PushItemWidth   = function() depth.width = depth.width + 1; end
    IM.PopItemWidth    = function() depth.width = depth.width - 1; end
    local btns = {};   -- every Button label this render drew
    IM.Button          = function(l) btns[#btns + 1] = tostring(l); return false; end
    IM.SmallButton     = function(l) btns[#btns + 1] = tostring(l); return false; end
    IM.Checkbox        = function(_, v) return false, v; end
    IM.InputInt        = function(_, v) return false, v; end
    IM.IsItemHovered   = function() return true; end   -- ALWAYS hovered: forces every
                                                       -- tooltip string to be built
    local function drewTab(c)
        for _, l in ipairs(btns) do
            if l:find('##ammocat_' .. c, 1, true) ~= nil then return true; end
        end
        return false;
    end

    local NAMES = { 'dlac\\ui\\ammoui', 'dlac\\gear\\gearoracle', 'imgui' };
    local saved = {};
    for _, k in ipairs(NAMES) do saved[k] = package.loaded[k]; end

    -- The worn ranged weapon is the ONE input the tab strip's green depends on.
    local worn = nil;      -- nil = empty Range slot
    local wornAmmo = nil;  -- nil = empty Ammo slot (slot 3, the green row's input)
    package.loaded['dlac\\gear\\gearoracle'] = {
        wornItem = function(slot)
            if slot == 2 then return worn; end
            if slot == 3 then return wornAmmo; end
            return nil;
        end,
    };
    package.loaded['imgui'] = IM;
    package.loaded['dlac\\ui\\ammoui'] = nil;
    local ok, aui = pcall(require, 'dlac\\ui\\ammoui');
    check('AU1 ammoui re-requires against a stub imgui', ok and type(aui.render), 'function');

    local amw = require('dlac\\feature\\ammowatch');
    if ok then
        -- A list spanning three types, so every tab is populated and the filter
        -- has something to include AND something to exclude in each branch.
        amw.jobsData = { COR = { enabled = true, at = 0, ammo = {
            { name = 'Gold Arrow',  id = 10, type = 'Archery',      pair = '25:0', ranged = true, ws = false, special = false },
            { name = 'Rusty Bolt',  id = 11, type = 'Marksmanship', pair = '26:0', ranged = true, ws = false, special = false },
            { name = 'Gold Bullet', id = 12, type = 'Marksmanship', pair = '26:1', ranged = true, ws = false,
              special = false },
            { name = 'Yoru Shuriken', id = 13, type = 'Throwing',   pair = '27:3', ranged = false, ws = false,
              special = { unlimited = true, quickdraw = false, freews = false } },
        } } };
        amw.selectJob('COR');
        local deps = { playerJob = function() return 'COR'; end,
                       ownedCounts = function() return { [10] = 99, [11] = 99, [12] = 99, [13] = 1 }; end,
                       renderIcon = nop, itemTooltip = nop,
                       lookupByName = function() return nil; end };

        local CASES = {
            { what = 'nothing equipped',      rec = nil,                                          want = nil },
            { what = 'a gun',                 rec = { Name = 'Hexagun',   Pair = '26:1' },        want = 'Bullets' },
            { what = 'a crossbow',            rec = { Name = 'Crossbow',  Pair = '26:0' },        want = 'Bolts' },
            { what = 'a bow',                 rec = { Name = 'Longbow',   Pair = '25:4' },        want = 'Arrows' },
            { what = 'a culverin',            rec = { Name = 'Culverin',  Pair = '26:2' },        want = 'Other' },
            { what = 'a harp (fires nothing)',rec = { Name = 'Maple Harp',Pair = '41:0' },        want = nil },
            { what = 'a pre-Pair manifest',   rec = { Name = 'Hexagun' },                          want = nil },
        };
        for _, c in ipairs(CASES) do
            worn = (c.rec ~= nil) and { id = 1, rec = c.rec } or nil;
            aui._resetCatSel();   -- re-derive the default selection per case
            btns = {};
            check('AU2 render survives ' .. c.what, pcall(aui.render, deps, 700), true);
            check('AU3 colour stack balanced with ' .. c.what, depth.col, 0);
            check('AU4 id stack balanced with ' .. c.what,     depth.id, 0);
            check('AU5 width stack balanced with ' .. c.what,  depth.width, 0);
            check('AU6 live tab for ' .. c.what, amw.categoryForPair(c.rec and c.rec.Pair), c.want);
            -- Proof the STRIP actually drew -- a pcall that merely returns true
            -- would also pass if render bailed before reaching the tabs at all.
            check('AU9 the three populated tabs drew with ' .. c.what,
                drewTab('Bullets') and drewTab('Bolts') and drewTab('Arrows'), true);
            -- A live type is always offered, even 'Other', or a culverin user would
            -- see no green tab anywhere.
            if c.want ~= nil then
                check('AU10 the live tab is on screen with ' .. c.what, drewTab(c.want), true);
            end
        end

        -- First open lands on what you are holding; after that the choice is YOURS
        -- even when the weapon changes (the green tab reports the change instead).
        worn = { id = 1, rec = { Name = 'Longbow', Pair = '25:4' } };
        aui._resetCatSel();
        pcall(aui.render, deps, 700);
        check('AU7 first open selects the type the worn weapon fires', aui._catSel(), 'Arrows');
        worn = { id = 1, rec = { Name = 'Hexagun', Pair = '26:1' } };
        pcall(aui.render, deps, 700);
        check('AU8 swapping weapons does NOT yank the selection', aui._catSel(), 'Arrows');

        -- AU11+. The level column and the live row (v134). Henrik's own list --
        -- Acid 15 / Blind 10 / Crossbow 1 -- read at an OVERRIDDEN level of 10,
        -- which is exactly how he found the bug. The panel must agree with the
        -- engine about which rungs are reachable, or it lies about the pick.
        amw.jobsData = { DRK = { enabled = true, at = 0, ammo = {
            { name = 'Acid Bolt',     id = 18148, type = 'Marksmanship', pair = '26:0', level = 15, ranged = true, ws = true, special = false },
            { name = 'Blind Bolt',    id = 18150, type = 'Marksmanship', pair = '26:0', level = 10, ranged = true, ws = true, special = false },
            { name = 'Crossbow Bolt', id = 17336, type = 'Marksmanship', pair = '26:0', level =  1, ranged = true, ws = true, special = false },
        } } };
        amw.selectJob('DRK');
        local ddeps = { playerJob = function() return 'DRK'; end,
                        ownedCounts = function() return { [18148] = 99, [18150] = 99, [17336] = 99 }; end,
                        renderIcon = nop, itemTooltip = nop,
                        lookupByName = function() return nil; end };
        worn     = { id = 1, rec = { Name = 'Light Crossbow +1', Pair = '26:0' } };
        wornAmmo = { id = 18150, rec = { Name = 'Blind Bolt' } };
        local savedOvr = rawget(_G, 'staticMainLevel');
        rawset(_G, 'staticMainLevel', 10);
        aui._resetCatSel();
        painted = {};
        check('AU11 render survives the level column', pcall(aui.render, ddeps, 700), true);
        check('AU12 colour stack still balanced', depth.col, 0);
        check('AU13 a rung above your level is RED', hueOf('Lv 15'), 'red');
        check('AU13b one you can wear is not', hueOf('Lv 10'), 'dim');
        check('AU13c and neither is the bottom rung', hueOf('Lv 1'), 'dim');
        check('AU14 the ammo actually in your slot is GREEN', hueOf('Blind Bolt'), 'green');
        check('AU14b a row you are not wearing is not', hueOf('Acid Bolt'), 'other');
        -- The override is the whole point: drop it and Acid Bolt is reachable again.
        rawset(_G, 'staticMainLevel', 0);
        painted = {};
        pcall(aui.render, ddeps, 700);
        check('AU15 with no override the same rung reads normal', hueOf('Lv 15'), 'dim');
        -- An entry whose level nobody can answer for must not read as blocked.
        amw.jobsData.DRK.ammo[1].level = nil;
        rawset(_G, 'staticMainLevel', 10);
        painted = {};
        pcall(aui.render, ddeps, 700);
        check('AU16 an unknown level shows as unknown, never as too high', hueOf('Lv ?'), 'dim');
        rawset(_G, 'staticMainLevel', savedOvr);

        amw.jobsData = {};
        amw.selectJob('COR');
    end

    for _, k in ipairs(NAMES) do package.loaded[k] = saved[k]; end
    package.loaded['imgui'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- 7f. FISHING RENDER for real (2026-07-27). The target picker moved out of the
--     fish panel into a floating window (fishui.renderSearch -> renderTargetBody)
--     and the hobby bar's Fishing tab became one of its openers -- the target
--     NAME is the button now. Neither body had ever been EXECUTED by a test: 7c
--     stubs fishbar.renderContent with a no-op and section 7 only reaches
--     fishui's pure status half, so ~180 moved lines had no coverage at all.
--     That is precisely the craftbar lesson of 7d. Stub imgui + fishwatch, drive
--     the REAL window and the REAL bar content, and assert the stacks balance
--     and that clicking the target name reaches the opener.
-- ---------------------------------------------------------------------------
;(function()
    local depth = { win = 0, col = 0, item = 0, id = 0, pop = 0 };
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'TextColored', 'Text', 'TextWrapped', 'SameLine', 'Spacing',
        'Separator', 'Dummy', 'Image', 'SetTooltip', 'InvisibleButton', 'TextDisabled',
        'OpenPopup' }) do IM[n] = nop; end
    -- The bar's rod/bait override popups: opened so their bodies run too (they
    -- read fishcalc's rod ranking, which is where a rename would go unnoticed).
    IM.BeginPopup = function() depth.pop = depth.pop + 1; return true; end
    IM.EndPopup   = function() depth.pop = depth.pop - 1; end
    IM.Begin             = function() depth.win = depth.win + 1; return true; end
    IM['End']            = function() depth.win = depth.win - 1; end
    IM.SetNextWindowSize = nop;
    IM.PushStyleColor    = function() depth.col = depth.col + 1; end
    IM.PopStyleColor     = function(n) depth.col = depth.col - (tonumber(n) or 1); end
    IM.PushItemWidth     = function() depth.item = depth.item + 1; end
    IM.PopItemWidth      = function() depth.item = depth.item - 1; end
    IM.PushID            = function() depth.id = depth.id + 1; end
    IM.PopID             = function() depth.id = depth.id - 1; end
    IM.CalcTextSize      = function(s) return #tostring(s) * 8; end
    IM.GetContentRegionAvail = function() return 720, 400; end
    IM.CollapsingHeader  = function() return true; end
    -- Every Selectable label this frame is recorded, so FS9b can prove the spot
    -- rows offer a FULL-ROW hit target rather than a bait-sized one.
    local sels = {};
    IM.Selectable = function(l) sels[#sels + 1] = tostring(l); return true; end   -- pick a match / a spot each frame
    IM.IsItemHovered     = function() return true; end     -- exercise every tooltip
    IM.Button            = function() return false; end
    local smalls, clickLabel = {}, nil;
    IM.SmallButton = function(l)
        smalls[#smalls + 1] = tostring(l);
        return clickLabel ~= nil and tostring(l) == clickLabel;
    end
    -- Record what the search box was handed, THEN drive it, so the seeded query
    -- from openTarget('carp') is observable.
    local seenQuery = nil;
    IM.InputText = function(label, buf)
        if label == '##fishsearch' and type(buf) == 'table' then
            seenQuery = buf[1];
            buf[1] = 'carp';
        end
    end

    local NAMES = { 'imgui', 'dlac\\ui\\fishui', 'dlac\\ui\\fishbar', 'dlac\\ui\\craftbar',
                    'dlac\\ui\\itemicons', 'dlac\\gear\\ownedcache',
                    'dlac\\feature\\fishwatch' };
    local saved = {};
    for _, k in ipairs(NAMES) do saved[k] = package.loaded[k]; end

    local fwTarget, fwEnabled = nil, false;
    package.loaded['imgui'] = IM;
    package.loaded['dlac\\ui\\craftbar'] = {};          -- no onOffSwitch -> Button fallback
    package.loaded['dlac\\ui\\itemicons'] = { renderIcon = nop };
    package.loaded['dlac\\gear\\ownedcache'] = { counts = function() return {}; end };
    package.loaded['dlac\\feature\\fishwatch'] = {
        isEnabled = function() return fwEnabled; end,
        setEnabled = function(v) fwEnabled = v; end,
        getTarget = function() return fwTarget, fwTarget and 'Moat Carp' or nil; end,
        setTarget = function(id) fwTarget = id; end,
        getRod  = function() return 17386, "Lu Shang's Fishing Rod"; end,
        getBait = function() return 17403, 'Little Worm'; end,
        rodPinned = function() return false; end, baitPinned = function() return false; end,
        playerFishSkill = function() return 40; end, playerFishRank = function() return 3; end,
        venturePoints = function() return 120; end, guildPoints = function() return 500; end,
        requestPoints = nop, requestGuildPoints = nop, openCapture = nop,
        setRod = nop, setBait = nop,
        venturesFor = function() return nil, false, nil; end,
        _clientName = function() return nil; end,
    };
    package.loaded['dlac\\ui\\fishui'] = nil;
    local ok, fui = pcall(require, 'dlac\\ui\\fishui');
    check('FS1 fishui re-requires against a stub imgui', ok and type(fui.renderSearch), 'function');
    if ok and type(fui._target) == 'table' then
        local deps = { ownedCounts = function() return { [17386] = 1, [17403] = 12 }; end,
                       renderIcon = nop, itemTooltip = nop,
                       lookupByName = function() return nil; end };

        check('FS2 a closed target window draws nothing', (function()
            depth.win = 0; pcall(fui.renderSearch, deps); return depth.win;
        end)(), 0);

        fui.openTarget('carp');
        check('FS3 openTarget opens the window', fui._target.open[1], true);
        local sok, serr = pcall(fui.renderSearch, deps);
        check('FS4 renderSearch runs the real target body', sok, true);
        if not sok then print('   fishui.renderSearch error: ' .. tostring(serr)); end
        check('FS5 target window Begin/End balanced', depth.win, 0);
        check('FS6 openTarget seeded the search box', seenQuery, 'carp');
        check('FS7 target window id stack balanced', depth.id, 0);
        check('FS8 target window item-width stack balanced', depth.item, 0);

        -- Second pass with a target set: the "current target" line, the rod
        -- verdicts and the ISOLATION rows are a different branch entirely.
        fwTarget = 4434;   -- Moat Carp
        local sok2 = pcall(fui.renderSearch, deps);
        check('FS9 renderSearch runs with an active target', sok2, true);
        -- 2026-07-27, Henrik: "I cannot target the end result without clicking on
        -- the bait, I would like to be able to click on the whole row." The row's
        -- hit target is now a full-width Selectable with a bare id, drawn BEFORE
        -- the columns; a bait-labelled one would mean the hit box shrank back to
        -- ~6 characters on a row you read left to right.
        local sawRow, sawBaitHit = false, false;
        for _, l in ipairs(sels) do
            if l == '##isorow' then sawRow = true; end
            if l:find('##bait', 1, true) then sawBaitHit = true; end
        end
        check('FS9b spot rows are clickable across the WHOLE row', sawRow, true);
        check('FS9c the bait cell is no longer the only hit target', sawBaitHit, false);
        check('FS10 stacks still balanced with a target', depth.win + depth.id + depth.item, 0);

        -- The PANEL keeps "what I own" and must no longer draw the picker.
        depth.win = 0;
        local pok, perr = pcall(fui.render, deps, 800);
        check('FS11 the panel still renders without the target section', pok, true);
        if not pok then print('   fishui.render error: ' .. tostring(perr)); end
        check('FS12 the panel opens no window of its own', depth.win, 0);

        fui._target.open[1] = false;
    end

    -- The BAR: the target name IS the opener (2026-07-27). Every other suite
    -- no-ops fishbar.renderContent, so this is the first execution of its body.
    local opened = false;
    package.loaded['dlac\\ui\\fishui'] = { openTarget = function() opened = true; end };
    package.loaded['dlac\\ui\\fishbar'] = nil;
    local bok, fbar = pcall(require, 'dlac\\ui\\fishbar');
    check('FS13 fishbar re-requires against a stub imgui', bok and type(fbar.renderContent), 'function');
    if bok then
        fwTarget = 4434;
        smalls, clickLabel = {}, nil;
        local rok, rerr = pcall(fbar.renderContent, 400);
        check('FS14 fishbar renderContent runs for real', rok, true);
        if not rok then print('   fishbar.renderContent error: ' .. tostring(rerr)); end
        check('FS15 colour stack balanced (the gold target button pushes one)', depth.col, 0);
        check('FS15b rod/bait popup stack balanced', depth.pop, 0);
        local seen = table.concat(smalls, ' ');
        check('FS16 the target NAME is a button, not a label',
            seen:find('Moat Carp##fbtgtbtn', 1, true) ~= nil, true);
        check('FS17 the bar offers the panel jump', seen:find('Panel##fbpanel', 1, true) ~= nil, true);
        -- The wire that matters: clicking the name reaches the opener. Without
        -- this the name is just a button that does nothing -- which is what the
        -- label it replaced effectively was.
        clickLabel = 'Moat Carp##fbtgtbtn';
        pcall(fbar.renderContent, 400);
        check('FS18 clicking the target name opens the target window', opened, true);
        clickLabel = nil;

        -- No target: the placeholder must be clickable too, or a fresh character
        -- has no way in from the bar at all.
        fwTarget = nil;
        smalls = {};
        pcall(fbar.renderContent, 400);
        check('FS19 "no target fish" is clickable as well',
            table.concat(smalls, ' '):find('no target fish##fbtgtbtn', 1, true) ~= nil, true);
    end

    for _, k in ipairs(NAMES) do package.loaded[k] = saved[k]; end
    package.loaded['imgui'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- 7g. ARBITER MONITOR render for real (v152, 2026-07-28). A new floating
--     window over the decision ring -- the craftbar/fishui lesson: a window
--     body must be EXECUTED once headless (the nil-global + stack-balance
--     failure class), not just loaded. Stub imgui with hover ON so every
--     tooltip builder runs, seed the REAL dispatch ring through its test seam,
--     and drive all four frames: closed, empty, live, pinned.
-- ---------------------------------------------------------------------------
;(function()
    local depth = { win = 0, col = 0, child = 0 };
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'SetNextWindowSize', 'Separator', 'Spacing', 'Text', 'TextColored',
        'SameLine', 'Dummy', 'SetTooltip', 'BeginGroup', 'EndGroup' }) do IM[n] = nop; end
    IM.Begin      = function() depth.win = depth.win + 1; return true; end
    IM['End']     = function() depth.win = depth.win - 1; end
    IM.BeginChild = function() depth.child = depth.child + 1; return true; end
    IM.EndChild   = function() depth.child = depth.child - 1; end
    IM.PushStyleColor = function() depth.col = depth.col + 1; end
    IM.PopStyleColor  = function(n) depth.col = depth.col - (tonumber(n) or 1); end
    IM.IsItemHovered  = function() return true; end       -- exercise EVERY tooltip builder
    IM.SmallButton    = function() return false; end
    IM.Selectable     = function() return false; end
    IM.GetItemRectMin = function() return 0, 0; end
    IM.GetColorU32    = function() return 0; end
    IM.GetWindowDrawList = function() return { AddRectFilled = nop }; end
    -- Responsive grid: the stub's width picks the MODE (narrow = icon-only,
    -- wide = names). Both frames are driven below.
    local availStub = 400;
    IM.GetContentRegionAvail = function() return availStub, 400; end

    local saved = { imgui = package.loaded['imgui'],
                    icons = package.loaded['dlac\\ui\\itemicons'],
                    am = package.loaded['dlac\\ui\\arbmonui'] };
    package.loaded['imgui'] = IM;
    package.loaded['dlac\\ui\\itemicons'] = { renderIcon = nop };
    package.loaded['dlac\\ui\\arbmonui'] = nil;
    local ok, am = pcall(require, 'dlac\\ui\\arbmonui');
    check('AM1 arbmonui re-requires against a stub imgui', ok and type(am.renderMonitor), 'function');
    if ok then
        local ui = { _arbMon = false };
        depth.win = 0;
        pcall(am.renderMonitor, ui);
        check('AM2 a closed monitor opens no window', depth.win, 0);

        ui._arbMon = true;
        local dspS = package.loaded['dlac\\dispatch'];
        check('AM3 the dispatch ring is reachable', dspS ~= nil and type(dspS.getDecisions) == 'function', true);
        local rok = pcall(am.renderMonitor, ui);
        check('AM4 a ring-less/empty frame renders', rok, true);
        check('AM4b Begin/End balanced', depth.win, 0);

        -- Seed the REAL ring through the engine's own test seam, then drive the
        -- full grid + legend + log with hover on everywhere. Shapes mirror the
        -- stash: explain ops, verdict maps, src, ladders ride separately.
        if dspS ~= nil and type(dspS._recordDecision) == 'function' then
            local wsCtx = { player = { MainJob = 'THF', SubJob = 'NIN', MainJobSync = 75,
                                       SubJobSync = 37, HPP = 100, MPP = 50, TP = 1000,
                                       Status = 'Engaged', IsMoving = false } };
            dspS._recordDecision('Default', {}, { Main = 'Bee Spatha', Body = 'Royal Cloak' }, {
                explain = { Main = { { name = 'Triggers', rank = 11, item = 'Bee Spatha' } },
                            Body = { { name = 'Triggers', rank = 11, item = 'Royal Cloak' } } },
                order = { 'Locks', 'Triggers' }, src = { Main = 'IdleSet', Body = 'IdleSet' },
            });
            dspS._recordDecision('Weaponskill', wsCtx, { Main = 'Rune Chopper', Ammo = 'Fire Bomblet' }, {
                explain = {
                    Main = { { name = 'Triggers', rank = 11, item = 'Rune Chopper' } },
                    Ammo = { { name = 'AutoAmmo', rank = 5, item = 'Fire Bomblet' },
                             { name = 'MaxMP',    rank = 6, item = 'nothing' } },
                    Head = { { name = 'Locks',    rank = 4, item = dspS.LOCK_HELD } },
                },
                order = { 'Locks', 'AutoAmmo', 'MaxMP', 'Triggers' },
                rep = { Body = { from = 'Royal Cloak', to = 'Scorpion Harness +1', by = 'Head' } },
                sup = {}, inel = {},
                src = { Main = 'WS_Default' },
            });
            local ring = dspS.getDecisions();
            check('AM5 the seeded ring holds records', #ring >= 2, true);

            local lok, lerr = pcall(am.renderMonitor, ui);
            check('AM6 the live grid + log frame renders (hover on, icon mode)', lok, true);
            if not lok then print('   arbmonui error: ' .. tostring(lerr)); end
            check('AM6b Begin/End balanced', depth.win, 0);
            check('AM6c child (log) balanced', depth.child, 0);

            -- wide window: the NAME-mode branch (double-space cells, names on)
            availStub = 990;
            local wok, werr = pcall(am.renderMonitor, ui);
            check('AM6d the name-mode frame renders (wide)', wok, true);
            if not wok then print('   arbmonui wide error: ' .. tostring(werr)); end
            check('AM6e stacks balanced wide', depth.win + depth.child, 0);

            ui._arbPin = ring[#ring - 1].seq;
            local pok2, perr2 = pcall(am.renderMonitor, ui);
            check('AM7 a pinned frame renders', pok2, true);
            if not pok2 then print('   arbmonui pinned error: ' .. tostring(perr2)); end
            check('AM7b stacks balanced pinned', depth.win + depth.child, 0);

            -- a pin that fell off the ring must self-heal to Live, never stick
            ui._arbPin = -999;
            pcall(am.renderMonitor, ui);
            check('AM8 a pruned pin self-heals to Live', ui._arbPin, nil);
        end
    end
    package.loaded['imgui'] = saved.imgui;
    package.loaded['dlac\\ui\\itemicons'] = saved.icons;
    package.loaded['dlac\\ui\\arbmonui'] = saved.am;
end)();

-- ---------------------------------------------------------------------------
-- Crafting Gear panel: the Ventures block (2026-07-28). The craft DETAIL view
-- had no render coverage at all -- section 8 only exercises the manifest
-- ladders -- and renderTab wraps renderAutomations in a pcall, so a fresh
-- typo'd upvalue (the silent-nil-global class) would blank the panel in the
-- field and pass every load test. So: stub imgui, re-require automationsui
-- against it, drive the REAL craft view and assert the rows/prices/hovers
-- actually reached the screen.
-- ---------------------------------------------------------------------------
;(function()
    local saved = { imgui = package.loaded['imgui'], aui = package.loaded['dlac\\ui\\automationsui'] };
    local log = {};
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'Text', 'TextWrapped', 'SameLine', 'Spacing', 'Separator', 'Dummy',
        'Image', 'PushItemWidth', 'PopItemWidth', 'BeginGroup', 'EndGroup', 'NewLine',
        'PushID', 'PopID', 'PushStyleColor', 'PopStyleColor', 'PushStyleVar', 'PopStyleVar',
        'InputText', 'EndCombo', 'Indent', 'Unindent' }) do
        IM[n] = nop;
    end
    IM.TextColored   = function(_, t) log[#log + 1] = tostring(t); end
    IM.SetTooltip    = function(t) log[#log + 1] = tostring(t); end
    IM.Button        = function() return false; end
    IM.Selectable    = function() return false; end
    IM.Checkbox      = function() return false; end
    IM.InputInt      = function() return false; end
    IM.BeginCombo    = function() return false; end
    IM.IsItemHovered = function() return true; end     -- reveal every helpLabel tip
    IM.IsItemClicked = function() return false; end
    IM.GetWindowWidth        = function() return 900; end
    IM.GetContentRegionAvail = function() return 860; end
    IM.GetCursorScreenPos    = function() return 0, 0; end
    IM.GetItemRectMin        = function() return 0, 0; end
    IM.GetItemRectMax        = function() return 20, 10; end
    IM.GetWindowDrawList     = function() return { AddLine = nop }; end
    IM.GetColorU32           = function() return 0xFFFFFFFF; end

    -- Just enough catalog for the Ventures column. A directory that does not
    -- exist keeps autoPath() non-nil (the render gate) while the manifest read
    -- fails harmlessly inside the module's own pcalls. The WRITE is stubbed out
    -- below rather than trusted to fail: rendering a stale-fmtver manifest
    -- triggers a self-healing rescan, and on a POSIX runner (the WSL lua5.4 CI
    -- parity run) this backslash path is a legal FILENAME -- the first version
    -- of this test dropped a literal `.\tests\__no_such_dir__\autogear.lua` in
    -- the repo root. A test may not write outside its own fixtures.
    local TMP = '.\\tests\\__no_such_dir__\\';
    local realOpen = io.open;
    io.open = function(p, mode)                        -- luacheck: ignore
        if type(mode) == 'string' and mode:find('[wa+]') then return nil; end
        return realOpen(p, mode);
    end;
    local CAT = {
        { Name = 'Craftkeepers Ring',    Id = 28585, Level = 1, Slot = 'Ring', Type = 'Ring',
          Jobs = { 'All' }, Stats = { SynthMaterialLoss = 1 } },
        { Name = 'Artificers Ring',      Id = 28587, Level = 1, Slot = 'Ring', Type = 'Ring',
          Jobs = { 'All' }, Stats = { SynthSuccessRate = 1 } },
        { Name = 'Craftmasters Ring',    Id = 28586, Level = 1, Slot = 'Ring', Type = 'Ring',
          Jobs = { 'All' }, Stats = { SynthHQRate = 1 } },
        { Name = 'Craftmasters Ring +1', Id = 26171, Level = 1, Slot = 'Ring', Type = 'Ring',
          Jobs = { 'All' }, Stats = { SynthHQRate = 2 } },
        { Name = 'Midrass Helm +1',      Id = 27000, Level = 1, Slot = 'Head', Type = 'Head',
          Jobs = { 'All' }, Stats = { SynthSkillGain = 3 } },
    };
    local ownedIds = { [28586] = 1 };                  -- ONLY Craftmaster's Ring
    local deps = {
        dataDir      = function() return TMP; end,
        charBase     = function() return TMP; end,
        lookupByName = function(n) for _, r in ipairs(CAT) do if r.Name == n then return r; end end return nil; end,
        lookupById   = function(id) for _, r in ipairs(CAT) do if r.Id == id then return r; end end return nil; end,
        ownedCounts  = function() return ownedIds; end,
        ownedList    = function()
            local o = {};
            for _, r in ipairs(CAT) do if (ownedIds[r.Id] or 0) > 0 then o[#o + 1] = r; end end
            return o;
        end,
        allEquipList = function() return CAT; end,
        haveInBags   = function() return true; end,
        playerJob    = function() return 'WHM'; end,
        renderIcon   = nop,
        itemTooltip  = nop,
    };

    package.loaded['imgui'] = IM;
    package.loaded['dlac\\ui\\automationsui'] = nil;
    local ok, aui = pcall(require, 'dlac\\ui\\automationsui');
    check('CV0 automationsui re-requires against a stub imgui', ok and type(aui) == 'table', true);
    if ok and type(aui) == 'table' then
        aui.init(deps);
        aui.openDetail('craft');
        local rok = pcall(aui.renderTab, 'WHM', 99);
        check('CV1 the Crafting Gear detail view renders', rok, true);
        local text = table.concat(log, '\n');
        local function said(s) return text:find(s, 1, true) ~= nil; end
        -- The view got all the way to the third column (renderTab swallows
        -- errors, so reaching the LAST row is the only honest liveness proof).
        check('CV2 the matrix headers render', said('Torques') and said('Rings') and said('Universals'), true);
        check('CV3 the Ventures section renders', said('Ventures'), true);
        for _, n in ipairs({ 'Craftkeepers Ring', 'Artificers Ring', 'Craftmasters Ring',
                             'Midrass Helm +1', 'Craftmasters Ring +1' }) do
            check('CV4 Ventures row: ' .. n, said(n), true);
        end
        -- Prices are the whole point of the block -- a row without its tag is
        -- an item the player cannot find.
        check('CV5 the 1,000-point rows are priced', said('1,000 pts'), true);
        check('CV6 Craftmaster\'s Ring is priced',   said('2,000 pts'), true);
        check('CV7 Midras\'s Helm +1 is priced',     said('3,000 pts'), true);
        check('CV8 the +1 reads as a synergy upgrade', said('synergy'), true);
        -- The hovers: where you buy them, and what the furnace wants.
        check('CV9 the Ventures hover names Populox', said('Populox, Upper Jeuno (I-11)'), true);
        check('CV10 the +1 hover names the token cost', said('3x Guild Token'), true);
        -- The column headers carry the Artisan's upgrade note, and the Rings
        -- header is the Torque text re-worded (the gsub must not leak "Torque").
        check('CV11 the Torques header explains its +1', said('Artisan\'s Torque +1: the Synergy furnace'), true);
        check('CV12 the Rings header is re-worded, not copied', said('Artisan\'s Ring +1: the Synergy furnace'), true);
        -- Coverage light: owning a Populox ring is owning craft gear. Before
        -- 2026-07-28 this read "nothing applicable" while the ladders were
        -- already equipping the ring.
        local function craftTxt()
            for _, r in ipairs(aui.listRows() or {}) do
                if r.key == 'craft' then return r.txt; end
            end
            return nil;
        end
        check('CV13 a Craftmaster\'s-only character reads as owning craft gear',
            craftTxt(), 'basic craft gear');
        ownedIds = {};
        check('CV14 ...and an empty bag still reads nothing applicable',
            craftTxt(), 'nothing applicable');
    end
    io.open = realOpen;
    package.loaded['imgui'] = saved.imgui;
    package.loaded['dlac\\ui\\automationsui'] = saved.aui;
end)();

-- ---------------------------------------------------------------------------
-- HP. Gear Helpers LIST view: the four idle hobbies answer Status with the
--     SHARED on/off pill, everything else keeps its status sentence (Henrik
--     2026-07-28). The list view had no render coverage at all -- renderTab
--     pcalls renderAutomations, so a nil-global here blanks the whole tab in the
--     field and passes every load test. Drive the real render against a stub
--     imgui and assert: which rows got a pill, that its ON state follows the
--     ARMED hobby (not the row's own coverage), that the coverage line survived
--     into the hover, and that a click reaches idleexcl.setOn.
-- ---------------------------------------------------------------------------
;(function()
    local saved = {
        imgui = package.loaded['imgui'], aui = package.loaded['dlac\\ui\\automationsui'],
        cb = package.loaded['dlac\\ui\\craftbar'], ie = package.loaded['dlac\\feature\\idleexcl'],
    };
    local log, pills, setOnLog = {}, {}, {};
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'Text', 'TextWrapped', 'SameLine', 'Spacing', 'Separator', 'Dummy',
        'Image', 'PushItemWidth', 'PopItemWidth', 'BeginGroup', 'EndGroup', 'NewLine',
        'PushID', 'PopID', 'PushStyleColor', 'PopStyleColor', 'PushStyleVar', 'PopStyleVar',
        'InputText', 'EndCombo', 'Indent', 'Unindent', 'InvisibleButton' }) do
        IM[n] = nop;
    end
    IM.TextColored   = function(_, t) log[#log + 1] = tostring(t); end
    IM.SetTooltip    = function(t) log[#log + 1] = tostring(t); end
    IM.Button        = function() return false; end
    IM.Checkbox      = function() return false; end
    IM.BeginCombo    = function() return false; end
    IM.CollapsingHeader = function() return true; end   -- every section OPEN
    IM.IsItemHovered = function() return false; end
    IM.IsItemClicked = function() return false; end
    IM.GetWindowWidth        = function() return 900; end
    IM.GetContentRegionAvail = function() return 860; end
    IM.GetCursorScreenPos    = function() return 0, 0; end
    IM.GetWindowDrawList     = function() return { AddLine = nop, AddRect = nop,
                                                   AddRectFilled = nop, AddCircleFilled = nop }; end
    IM.GetColorU32           = function() return 0xFFFFFFFF; end
    -- Selectable records the WIDTH it was asked for: the pill rows must end
    -- their click target before the switch (the overlap rule in autoRow).
    local selW = {};
    IM.Selectable = function(_, _, _, size)
        selW[#selW + 1] = (type(size) == 'table') and size[1] or nil;
        return false;
    end

    -- The pill: record every call, and "click" whichever id the test wants.
    local clickId = nil;
    package.loaded['dlac\\ui\\craftbar'] = {
        onOffSwitch = function(on, id, tipOn, tipOff)
            pills[id] = { on = on, tipOn = tostring(tipOn), tipOff = tostring(tipOff) };
            return id == clickId;
        end,
    };
    local activeStub = nil;
    package.loaded['dlac\\feature\\idleexcl'] = {
        getActive = function() return activeStub; end,
        setOn     = function(k, v) setOnLog[#setOnLog + 1] = tostring(k) .. '=' .. tostring(v); return false; end,
    };

    local TMP = '.\\tests\\__no_such_dir__\\';
    local realOpen = io.open;
    io.open = function(p, mode)                        -- luacheck: ignore
        if type(mode) == 'string' and mode:find('[wa+]') then return nil; end
        return realOpen(p, mode);
    end;
    local deps = {
        dataDir      = function() return TMP; end,
        charBase     = function() return TMP; end,
        lookupByName = function() return nil; end,
        lookupById   = function() return nil; end,
        ownedCounts  = function() return {}; end,
        ownedList    = function() return {}; end,
        allEquipList = function() return {}; end,
        haveInBags   = function() return true; end,
        playerJob    = function() return 'WHM'; end,
        renderIcon   = nop,
        itemTooltip  = nop,
        ui           = {},
    };

    package.loaded['imgui'] = IM;
    package.loaded['dlac\\ui\\automationsui'] = nil;
    local ok, aui = pcall(require, 'dlac\\ui\\automationsui');
    check('HP0 automationsui re-requires for the list view', ok and type(aui) == 'table', true);
    if ok and type(aui) == 'table' then
        aui.init(deps);
        aui.openDetail(nil);                            -- the LIST view
        local rok = pcall(aui.renderTab, 'WHM', 99);
        check('HP1 the Gear Helpers list renders', rok, true);
        -- Exactly the four idle hobbies get a switch...
        for _, k in ipairs({ 'craft', 'helm', 'fish', 'choco' }) do
            check('HP2 ' .. k .. ' Status is a pill', pills['autorow_' .. k] ~= nil, true);
        end
        -- ...and nothing else does (the three "don't touch" rows + the ammo /
        -- MaxMP rules keep their status sentence).
        for _, k in ipairs({ 'iridescence', 'obi', 'oneiros', 'ammo', 'maxmp', 'restock' }) do
            check('HP3 ' .. k .. ' Status is NOT a pill', pills['autorow_' .. k], nil);
        end
        check('HP4 nothing armed -> every pill reads off',
            (pills['autorow_craft'].on == false) and (pills['autorow_fish'].on == false), true);
        -- The status sentence the pills replaced still reaches the screen on the
        -- untouched rows.
        local text = table.concat(log, '\n');
        check('HP5 the untouched rows still print a status',
            text:find('Elemental Staff', 1, true) ~= nil, true);
        -- ...and the hobby rows' coverage moved into the hover, not the bin.
        check('HP6 the coverage line rides the pill hover',
            pills['autorow_craft'].tipOff:find('Your gear:', 1, true) ~= nil, true);
        check('HP7 the off hover says what turning it on WEARS',
            pills['autorow_fish'].tipOff:find('fishing kit', 1, true) ~= nil, true);
        -- The click target stops short of the Status column on a pill row (570),
        -- and stays full-width (0) on the others.
        local narrow, full = 0, 0;
        for _, w in ipairs(selW) do
            if w == 570 then narrow = narrow + 1; elseif w == 0 then full = full + 1; end
        end
        check('HP8 four rows shorten their click target', narrow, 4);
        check('HP9 the other rows keep the full-width one', full > 0, true);

        -- ARMED: the pill follows idleexcl, and the other three say who blocks.
        log, pills, selW = {}, {}, {};
        activeStub = { key = 'helm', name = 'HELM' };
        pcall(aui.renderTab, 'WHM', 99);
        check('HP10 the armed hobby reads ON',  pills['autorow_helm'].on, true);
        check('HP11 the others read off',       pills['autorow_craft'].on, false);
        check('HP12 the armed hover offers OFF',
            pills['autorow_helm'].tipOn:find('Click to turn off', 1, true) ~= nil, true);
        check('HP13 a blocked hover NAMES the blocker',
            pills['autorow_craft'].tipOff:find('HELM is on', 1, true) ~= nil, true);
        check('HP14 ...and says only one at a time',
            pills['autorow_craft'].tipOff:find('only one hobby at a time', 1, true) ~= nil, true);

        -- A click on an off pill asks idleexcl to arm THAT hobby (the guard --
        -- and the refusal -- stay inside the watcher; the row never bypasses it).
        log, pills = {}, {};
        clickId, activeStub = 'autorow_choco', nil;
        pcall(aui.renderTab, 'WHM', 99);
        check('HP15 clicking an off pill arms that hobby', setOnLog[#setOnLog], 'choco=true');
        -- ...and a click on the ARMED one turns it off.
        setOnLog = {};
        clickId, activeStub = 'autorow_helm', { key = 'helm', name = 'HELM' };
        pcall(aui.renderTab, 'WHM', 99);
        check('HP16 clicking the armed pill turns it off', setOnLog[#setOnLog], 'helm=false');
    end
    io.open = realOpen;
    package.loaded['imgui'] = saved.imgui;
    package.loaded['dlac\\ui\\automationsui'] = saved.aui;
    package.loaded['dlac\\ui\\craftbar'] = saved.cb;
    package.loaded['dlac\\feature\\idleexcl'] = saved.ie;
end)();

-- ---------------------------------------------------------------------------
-- Job Helpers tab (issue #137): tab appears once a module loads, to the right of
-- Gear Helpers; the real BST skeleton loads through the loader; the tab + the
-- selected module's Panel render with a BALANCED imgui stack (the crash class the
-- floatgear block guards -- a module's Panel must not corrupt ImGui's stacks).
-- ---------------------------------------------------------------------------
;(function()
    local saved = {
        imgui = package.loaded['imgui'],
        jh    = package.loaded['dlac\\feature\\jobhelpers'],
        jhui  = package.loaded['dlac\\ui\\jobhelpersui'],
        cb    = package.loaded['dlac\\ui\\craftbar'],
    };

    local depth = { var = 0, col = 0, win = 0, child = 0 };
    local function nop() end
    local IM = {};
    for _, n in ipairs({ 'SetNextWindowPos', 'SetNextWindowSize', 'Separator', 'Text',
        'TextColored', 'TextWrapped', 'TextDisabled', 'SameLine', 'Dummy', 'Spacing',
        'Indent', 'Unindent', 'PushID', 'PopID', 'SetTooltip', 'PushItemWidth',
        'PopItemWidth', 'InvisibleButton', 'SetCursorScreenPos' }) do
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
    IM.CollapsingHeader = function() return true; end        -- sections open so rows draw
    IM.Selectable       = function() return true; end        -- click: selects the module -> its Panel draws
    for _, n in ipairs({ 'Button', 'IsItemHovered', 'IsItemClicked', 'IsItemActive' }) do
        IM[n] = function() return false; end
    end
    -- Buttons are RECORDED (and one can be clicked by id): the BST Panel's Fight
    -- switch (issue #139) is three of them, drawn inside jobhelpersui's render
    -- pcall -- a typo there would blank the switch in-game and pass a load test.
    local buttons, clickId = {}, nil;
    IM.Button = function(label)
        buttons[#buttons + 1] = tostring(label);
        return clickId ~= nil and type(label) == 'string' and label:find(clickId, 1, true) ~= nil;
    end
    -- The Reward rule's two controls (issue #140) are recorded the same way: a
    -- Checkbox (the rule switch) and a SliderFloat (the pet-HP% threshold), both
    -- drivable by id so the click/drag is proven to reach the setter and not
    -- just to draw.
    local checks, sliders, tickId, dragId, dragTo = {}, {}, nil, nil, 0;
    IM.Checkbox = function(label, t)
        checks[#checks + 1] = tostring(label);
        if tickId ~= nil and type(label) == 'string' and label:find(tickId, 1, true) ~= nil then
            if type(t) == 'table' then t[1] = not t[1]; end
            return true;
        end
        return false;
    end
    IM.SliderFloat = function(label, t)
        sliders[#sliders + 1] = tostring(label);
        if dragId ~= nil and type(label) == 'string' and label:find(dragId, 1, true) ~= nil then
            if type(t) == 'table' then t[1] = dragTo; end
            return true;
        end
        return false;
    end
    IM.GetCursorScreenPos    = function() return 0, 0; end
    IM.GetContentRegionAvail = function() return 400, 400; end
    IM.GetWindowDrawList = function()
        return { AddCircleFilled = nop, AddRectFilled = nop, AddRect = nop, AddLine = nop };
    end

    package.loaded['imgui'] = IM;
    package.loaded['dlac\\feature\\jobhelpers'] = nil;   -- re-require against the stub
    package.loaded['dlac\\ui\\jobhelpersui']    = nil;
    package.loaded['dlac\\ui\\craftbar']        = nil;

    local jhok, jhui = pcall(require, 'dlac\\ui\\jobhelpersui');
    check('S320 jobhelpersui re-requires against a stub imgui', jhok and type(jhui.renderTab), 'function');
    if jhok then
        local jh = require('dlac\\feature\\jobhelpers');
        jh.modules = {};

        -- zero modules: maybeRegister is a no-op and the tab stays absent.
        check('S321 maybeRegister no-ops with zero modules', jhui.maybeRegister(host), false);
        check('S322 tab still absent', host.get('jobhelpers') == nil, true);

        -- load the REAL BST module through the loader (proves the drop-in path).
        -- The layout is jobhelpers\<job>\<module>\ (Henrik's ruling 2026-07-29),
        -- so the require seam needs the job folder seeded, as M.load does live.
        jh._jobOf = { ['bst-helper'] = 'bst' };
        jh.loadAll({ names = { 'bst-helper' }, loadModule = jh._requireModule });
        check('S323 the BST module loads as one module', jh.count(), 1);
        check('S324 identity is the MODULE folder name', jh.list()[1].id, 'bst-helper');
        check('S325 its display label', jh.list()[1].label, 'BST Helper');
        check('S326 it declares BST', table.concat(jh.list()[1].jobs, ','), 'BST');

        -- now the tab registers, to the RIGHT of Gear Helpers.
        jhui.init({});
        check('S327 maybeRegister now registers the tab', jhui.maybeRegister(host), true);
        check('S328 Job Helpers tab now present', host.get('jobhelpers') ~= nil, true);
        local labels2 = {};
        for _, name in ipairs({ 'equipped', 'sets', 'triggers', 'automations', 'groups', 'jobhelpers' }) do
            local m = host.get(name);
            if m ~= nil and type(m.tabs) == 'table' then
                for _, t in ipairs(m.tabs) do labels2[#labels2 + 1] = t.label; end
            end
        end
        check('S329 tab count is now 6', #labels2, 6);
        check('S330 Job Helpers sits right of Gear Helpers', labels2[6], 'Job Helpers');

        -- render the tab (sections + rows + the selected module's Panel) and prove
        -- the imgui stack came back balanced. gData/AshitaCore are the smoke stubs
        -- (GetPlayer -> nil), so the activity predicate reads unknown -> active.
        local function balanced(tag)
            check(tag .. ': style VAR stack balanced',   depth.var, 0);
            check(tag .. ': style COLOR stack balanced', depth.col, 0);
            check(tag .. ': Begin/End balanced',         depth.win, 0);
            check(tag .. ': BeginChild/EndChild balanced', depth.child, 0);
        end
        local rok, rerr = pcall(jhui.renderTab, 'BST', 99);
        check('S331 tab render runs against the stub', rok, true);
        if not rok then print('   jobhelpers render error: ' .. tostring(rerr)); end
        balanced('S332 tab + BST Panel');

        -- the BST Panel's three-way Fight switch actually reaches the screen
        -- (issue #139), and a click on one of its ways reaches the setter.
        local drawn = table.concat(buttons, '|');
        check('S336 the Fight switch draws its three ways',
              drawn:find('Off##bstfight_off_bst', 1, true) ~= nil
              and drawn:find('When I attack##bstfight_attack_bst', 1, true) ~= nil
              and drawn:find('Follow my target##bstfight_follow_bst', 1, true) ~= nil, true);
        check('S337 the Reward button is still there beside it',
              drawn:find('Reward now##bstreward_bst', 1, true) ~= nil, true);
        local fightOk, fight = pcall(require, 'dlac\\jobhelpers\\bst\\bst-helper\\fight');
        check('S338 the Fight core loads as a module-folder sibling', fightOk and type(fight), 'table');
        if fightOk then
            local realSet, setLog = fight.setMode, {};
            fight.setMode = function(m) setLog[#setLog + 1] = m; return true; end
            clickId = 'bstfight_follow_bst';
            pcall(jhui.renderTab, 'BST', 99);
            clickId = nil;
            check('S339 clicking a way sets that mode', setLog[#setLog], 'follow');
            fight.setMode = realSet;
        end

        -- the Reward RULE's two controls actually reach the screen (issue #140),
        -- and a tick / a drag reaches its setter. Same reasoning as S336-S339:
        -- the Panel draws inside a render pcall, so a typo here would silently
        -- blank the switch in-game and still pass every load test.
        check('S340 the Reward rule switch draws',
              table.concat(checks, '|'):find('bstrewardauto_bst', 1, true) ~= nil, true);
        check('S341 the pet-HP threshold slider draws beside it',
              table.concat(sliders, '|'):find('bstrewardthr_bst', 1, true) ~= nil, true);
        local rwOk, reward = pcall(require, 'dlac\\jobhelpers\\bst\\bst-helper\\reward');
        check('S342 the Reward rule loads as a module-folder sibling', rwOk and type(reward), 'table');
        if rwOk then
            local realArm, realThr = reward.setArmed, reward.setThreshold;
            local armLog, thrLog = {}, {};
            reward.setArmed     = function(v) armLog[#armLog + 1] = v; return true; end
            reward.setThreshold = function(v) thrLog[#thrLog + 1] = v; return true; end
            tickId = 'bstrewardauto_bst';
            pcall(jhui.renderTab, 'BST', 99);
            tickId = nil;
            check('S343 ticking the switch reaches the setter', armLog[#armLog], true);
            dragId, dragTo = 'bstrewardthr_bst', 35;
            pcall(jhui.renderTab, 'BST', 99);
            dragId = nil;
            check('S344 dragging the slider reaches the setter', thrLog[#thrLog], 35);
            reward.setArmed, reward.setThreshold = realArm, realThr;
        end

        -- the optional row-status hook is actually invoked during a row render.
        local statusCalls = 0;
        jh.modules[1].mod.status = function() statusCalls = statusCalls + 1; end
        pcall(jhui.renderTab, 'BST', 99);
        check('S335 the module row-status hook is called', statusCalls >= 1, true);

        -- a module whose Panel THROWS is contained: the render still returns and the
        -- stack stays balanced (the tab and other rows are unharmed).
        jh.modules[1].mod.panel = function() error('panel boom'); end
        local rok2 = pcall(jhui.renderTab, 'BST', 99);
        check('S333 a throwing Panel does not break the tab render', rok2, true);
        balanced('S334 after a throwing Panel');

        -- clean the shared host so the verdict-time state matches a normal run.
        jh.modules = {};
    end

    package.loaded['imgui'] = saved.imgui;
    package.loaded['dlac\\feature\\jobhelpers'] = saved.jh;
    package.loaded['dlac\\ui\\jobhelpersui']    = saved.jhui;
    package.loaded['dlac\\ui\\craftbar']        = saved.cb;
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
