--[[
    dlac/triggersui.lua -- the Triggers tab (GUI editor for the dispatch engine's data)
    plus the Groups section it hosts. The Automations tab and its manifest machinery
    moved to ui\automationsui.lua (2026-07-18).

    Split out of gearui.lua: LuaJIT caps a chunk at 200 local variables, and gearui's
    main chunk was already near it -- new tabs get their own module from now on.

    gearui injects its file/profile helpers once via M.init{...} (charBase, jobFile,
    seedTriggersFile, dynamicSetNames, staticSetNames) and calls M.render(job, level)
    from its Triggers tab. Everything here is defensive: no deps / no imgui / no
    dispatch module just renders a notice instead of erroring.

    Nothing in this tab requires touching a Lua file (product rule, design doc):
    rules are added/edited/removed in-tab, modes get live toggle buttons, and Commit
    rewrites <char>\dlac\triggers\<JOB>.lua via dispatch.serializeTriggers, then pings
    the LAC-state engine (/dl triggers reload) -- live immediately, no /lac reload.
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local _dpok, dsp  = pcall(require, "dlac\\dispatch");
local _gmok, gm   = pcall(require, "dlac\\gear\\groupsmodel");
local _tmok, tmodel = pcall(require, "dlac\\gear\\triggermodel");
local _giok, gimp = pcall(require, "dlac\\gear\\groupimport");
local _gsok, gscan = pcall(require, "dlac\\gear\\groupscan");   -- Item 1: auto-import from the Lua file
-- Searchable spell/ability browse-list for the Groups member picker (G3, issue #26):
-- the pure list/search core + the two picker-DB data files it filters. Addon-state only
-- (a UI module -- never seeded into LAC), so requiring the data here is fine; all guarded,
-- a missing piece only loses the browse button (free-name entry still works).
local _apok, ap   = pcall(require, "dlac\\gear\\actionpicker");
local _spok, spellDB   = pcall(require, "dlac\\data\\spells");
local _abok, abilityDB = pcall(require, "dlac\\data\\abilities");
-- Blueprints (issue #65, slice 1): the per-character library of reusable trigger rules.
-- Pure core (CRUD / stamp transform / serialize) here; the file IO + section render below.
-- Guarded like the others: a missing module only loses the Blueprints section.
local _bpok, bp   = pcall(require, "dlac\\gear\\blueprintsmodel");
local hasImgui    = _iok and imgui ~= nil;
local hasDispatch = _dpok and type(dsp) == 'table';
local hasGroups   = _gmok and type(gm) == 'table';
local hasTrigModel = _tmok and type(tmodel) == 'table';
local hasGroupImport = _giok and type(gimp) == 'table';
local hasGroupScan   = _gsok and type(gscan) == 'table';
-- InputTextMultiline is the right widget for a paste box, but it is not used anywhere else in
-- this install -- probe it (hard rule 2: presence proves nothing, but absence is certain), and
-- degrade to a single-line box with a visible note rather than silently disabling the feature.
local hasMultiline = hasImgui and type(imgui.InputTextMultiline) == 'function';
-- Clipboard for View text / Copy / Copy all (issue #66; the profilesmenu "Copy all" precedent).
-- Probe it (hard rule 2); degrade to a selectable box + a note when the build lacks it.
local hasClipboard = hasImgui and type(imgui.SetClipboardText) == 'function';
local hasBrowse   = _apok and type(ap) == 'table'
    and _spok and type(spellDB) == 'table' and _abok and type(abilityDB) == 'table';
local hasBlueprints = _bpok and type(bp) == 'table';

local function mainLevel()
    local lv = nil;
    pcall(function() lv = AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel(); end);
    return (type(lv) == 'number' and lv > 0) and lv or 99;
end

-- Injected by gearui (M.init): charBase, jobFile, seedTriggersFile,
-- dynamicSetNames, staticSetNames, lookupByName, ownedCounts.
local deps = nil;
function M.init(d)
    deps = d;
    -- Wire the trigger-gear audit (gearcheck): it needs set contents, the gear
    -- library lookup, and our trigger model. Guarded: a missing module only
    -- loses the warnings feature.
    pcall(function()
        local gc = require("dlac\\gear\\gearcheck");
        gc.configure({ setsRoot = d.setsRoot, lookupByName = d.lookupByName,
                       model = M.currentModel });
    end);
end

-- Colors (match gearui's palette).
local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_USABLE = { 1.00, 1.00, 1.00, 1.00 };
local COL_DIM    = { 0.70, 0.70, 0.70, 1.00 };
local COL_SCORE  = { 0.95, 0.85, 0.45, 1.00 };
local COL_ERR    = { 1.00, 0.45, 0.40, 1.00 };

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end
local function writeFileText(p, t)
    local f = io.open(p, 'w'); if f == nil then return false; end
    f:write(t); f:close(); return true;
end
local function readFileText(p)
    if p == nil then return nil; end
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end

local TRIG_HANDLERS = { 'Default', 'Precast', 'Midcast', 'Ability', 'Item', 'Weaponskill', 'Preshot', 'Midshot', 'PetAction' };

-- Condition metadata for the add-rule builder: per handler, the choosable condition
-- types and their value widgets. kind: 'list' = fixed dropdown, 'text' = free text,
-- 'flag' = boolean true. Vocabulary mirrors dispatch.lua's MATCHERS (v1).

-- Target condition (engine v81): WHO the action is aimed at. ONE value today --
-- the dropdown shape is the point (new answers slot in as the engine grows them).
local TARGET_ITEMS = { 'Self' };
local TARGET_HINT = 'who the action is aimed at. Self = the action targets YOU --\n'
    .. 'a self-waltz can wear VIT+CHR together (waltz potency reads the TARGET\'s\n'
    .. 'VIT beside your CHR) while waltzing someone else keeps the plain CHR set.\n'
    .. 'Stack it with contains/name: the self rule overlays the base rule.';

local SPELL_CONDS = {
    { key = 'skill',     kind = 'list', items = { 'Divine Magic', 'Healing Magic', 'Enhancing Magic', 'Enfeebling Magic', 'Elemental Magic', 'Dark Magic', 'Summoning', 'Ninjutsu', 'Singing', 'Blue Magic', 'Geomancy' } },
    { key = 'magicType', kind = 'list', items = { 'White Magic', 'Black Magic', 'Bard Song', 'Ninjutsu', 'Summoning', 'Blue Magic' } },
    { key = 'element',   kind = 'list', items = { 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark', 'Non-Elemental' } },
    { key = 'songType',  kind = 'list', items = { 'Buff', 'Debuff' } },
    { key = 'contains',  kind = 'text', hint = 'name contains this text: "Madrigal" matches Blade + Sword\nMadrigal; "Stone" matches every Stone tier. Stack it with skill\nvia [+ condition] for AND logic (e.g. skill=Elemental + contains=Stone).' },
    { key = 'group',     kind = 'group', hint = 'match every action in a named group -- one rule gears many\nspells that share gear. Build groups in the Groups section; a per-spell\nname rule still overrides the group.' },
    { key = 'name',      kind = 'text', hint = 'exact spell name, e.g. Slow II' },
    { key = 'target',    kind = 'list', items = TARGET_ITEMS, hint = TARGET_HINT },
    { key = 'dayWeatherBonus', kind = 'flag' },
    { key = 'mode',      kind = 'text', hint = 'a player-toggled mode must be ON (e.g. DT) -- stack with other\nconditions to make a rule mode-dependent' },
    { key = 'any',       kind = 'flag' },
};
local COND_DEFS = {
    Default = {
        { key = 'status', kind = 'list', items = { 'Engaged', 'Resting', 'Idle' } },
        { key = 'moving', kind = 'flag' },
        { key = 'inTown', kind = 'flag',
          hint = 'you are standing in a town -- pair with status = Idle to show off\nyour gear in the cities. The town list is server-derived (data/zones.lua):\nevery city plus Nashmau, Celennia Memorial Library, Mog Garden.' },
        { key = 'mode',   kind = 'text', hint = 'mode name, e.g. DT' },
    },
    Precast = SPELL_CONDS,
    Midcast = SPELL_CONDS,
    Ability = {
        { key = 'abilityType', kind = 'list', items = { 'Blood Pact: Rage', 'Blood Pact: Ward', 'Corsair Roll', 'Quick Draw', 'Ready', 'Rune Enchantment' } },
        { key = 'contains', kind = 'text', hint = 'name contains this text' },
        { key = 'group',    kind = 'group', hint = 'match every ability in a named group (Groups section)' },
        { key = 'name',     kind = 'text', hint = 'exact ability name, e.g. Repair' },
        { key = 'target',   kind = 'list', items = TARGET_ITEMS, hint = TARGET_HINT },
        { key = 'mode',     kind = 'text', hint = 'a player-toggled mode must be ON' },
        { key = 'any',      kind = 'flag' },
    },
    Item = {
        { key = 'name',     kind = 'text', hint = 'exact item name, e.g. Holy Water' },
        { key = 'contains', kind = 'text', hint = 'name contains this text' },
        { key = 'group',    kind = 'group', hint = 'match every item in a named group (Groups section)' },
        { key = 'mode',     kind = 'text', hint = 'a player-toggled mode must be ON' },
    },
    Weaponskill = {
        { key = 'name', kind = 'text', hint = 'exact weaponskill name' },
        { key = 'group', kind = 'group', hint = 'match every weaponskill in a named group (Groups section)' },
        { key = 'mode', kind = 'text', hint = 'a player-toggled mode must be ON' },
        { key = 'any',  kind = 'flag' },
    },
    Preshot = { { key = 'any', kind = 'flag' }, { key = 'mode', kind = 'text', hint = 'a player-toggled mode must be ON' } },
    Midshot = { { key = 'any', kind = 'flag' }, { key = 'mode', kind = 'text', hint = 'a player-toggled mode must be ON' } },
    -- Fires when YOUR PET starts an action (Blood Pact, Ready move, pet spell).
    -- NO LAC version calls a pet handler -- the upstream tutorial's
    -- HandlePetAction is a call-it-yourself pattern; dlac's engine tick does
    -- the calling, centrally. Default holds until the action completes, so
    -- Pet: stat gear stays on through it.
    PetAction = {
        { key = 'contains', kind = 'text', hint = 'pet action name contains this text, e.g. "Predator" for\nPredator Claws' },
        { key = 'name',     kind = 'text', hint = 'exact pet action name, e.g. Volt Strike' },
        { key = 'element',  kind = 'list', items = { 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark', 'Non-Elemental' } },
        { key = 'mode',     kind = 'text', hint = 'a player-toggled mode must be ON' },
        { key = 'any',      kind = 'flag' },
    },
};

-- Player-state gates (engine v54): ONE 'Player' entry per handler that
-- CASCADES into a second parameter combo (Henrik's cascading-menu revision) --
-- 12 parameters: raw + percent vitals variants, TP, and the buff pickers.
-- kind 'number' = an InputInt threshold; kind 'buff' = the searchable picker.
local PLAYER_PARAMS = {
    { key = 'playerHPBelow',        kind = 'number', hint = 'raw HP under this' },
    { key = 'playerHPAbove',        kind = 'number', hint = 'raw HP over this' },
    { key = 'playerHPPercentBelow', kind = 'number', hint = 'HP percent under this (0-100)' },
    { key = 'playerHPPercentAbove', kind = 'number', hint = 'HP percent over this (0-100)' },
    { key = 'playerMPBelow',        kind = 'number', hint = 'raw MP under this' },
    { key = 'playerMPAbove',        kind = 'number', hint = 'raw MP over this' },
    { key = 'playerMPPercentBelow', kind = 'number', hint = 'MP percent under this (0-100)' },
    { key = 'playerMPPercentAbove', kind = 'number', hint = 'MP percent over this (0-100)' },
    { key = 'tpBelow',              kind = 'number', hint = 'raw TP under this (1000 = one full shot)' },
    { key = 'tpAbove',              kind = 'number', hint = 'raw TP over this (1000 = one full shot)' },
    { key = 'buff',    label = 'Has(De)Buff',    kind = 'buff', hint = 'a status effect (buff OR debuff) must be ON you --\ngear up while Asleep, or only while Refresh is active' },
    { key = 'buffNot', label = 'HasNot(De)Buff', kind = 'buff', hint = 'a status effect must NOT be on you' },
};

-- Pet conditions (engine v63): a second cascading entry, the Player shape --
-- one 'Pet' row that cascades into these parameters. kind 'fixed' = the
-- parameter IS the value (HasPet/NoPet are two spellings of ONE key, pet =
-- true/false), so no value widget shows. The engine reads gData.GetPet(),
-- which is nil with NO pet and when the pet's HPP is 0: a dead pet counts as
-- none, and PetStatus/PetName never match petless.
local PET_PARAMS = {
    { key = 'pet',       label = 'HasPet',    kind = 'fixed', value = true,
      hint = 'a living pet is out -- avatar, jug pet, automaton, wyvern, luopan.\n(a dead pet counts as NO pet)' },
    { key = 'pet',       label = 'NoPet',     kind = 'fixed', value = false,
      hint = 'no living pet out (a dead pet counts as none)' },
    { key = 'petStatus', label = 'PetStatus', kind = 'list', items = { 'Idle', 'Engaged' },
      hint = 'what the PET is doing. status = Idle + petStatus = Engaged is the classic\n"master stands back while the pet fights" posture. Never matches petless.' },
    { key = 'petName',   label = 'PetName',   kind = 'text',
      hint = 'exact pet name, case-insensitive -- Garuda, Fire Spirit, a jug pet\'s name --\nfor avatar-specific perpetuation gear and the like. Never matches petless.' },
};
do
    -- Precast/Midcast share one defs table (SPELL_CONDS) -- append ONCE per table.
    local seenDef = {};
    for _, defs in pairs(COND_DEFS) do
        if not seenDef[defs] then
            seenDef[defs] = true;
            defs[#defs + 1] = { key = 'player', kind = 'player', label = 'Player' };
            defs[#defs + 1] = { key = 'pet', kind = 'pet', label = 'Pet' };   -- engine v63
        end
    end
end

-- Every status-effect name in the client string table (buffs.names), for the
-- buff/buffNot picker. Built once per session; ids 1..999, empties skipped.
local _buffList = nil;
local function buffChoices()
    if _buffList ~= nil then return _buffList; end
    _buffList = {};
    pcall(function()
        local resx = AshitaCore:GetResourceManager();
        local seen = {};
        for id = 1, 999 do
            local nm = resx:GetString('buffs.names', id);
            if type(nm) == 'string' then
                nm = string.gsub(nm, '%z+$', '');
                if #nm > 0 and not seen[string.lower(nm)] then
                    seen[string.lower(nm)] = true;
                    _buffList[#_buffList + 1] = nm;
                end
            end
        end
        table.sort(_buffList);
    end);
    return _buffList;
end

-- Cascading submenus for the condition chooser: probe the binding, never
-- assume (hard rule 2). floatgear field-proved BeginMenu/EndMenu in this
-- install; when absent, the drill-down fallback uses only proven APIs
-- (floatgear's own fallback shape).
local hasMenu = (imgui ~= nil)
    and (type(imgui.BeginMenu) == 'function') and (type(imgui.EndMenu) == 'function');

-- Searchable status-effect picker: the setPickCombo shape (button -> plain
-- popup with a filter box + rows -- NOT InputText-inside-BeginCombo, which
-- this imgui build mishandles). Returns the clicked name, nil otherwise.
local _buffPickQ = { '' };
local function buffPickCombo(comboId, label)
    local picked = nil;
    if imgui.Button(label .. '###' .. comboId .. '_btn', { 170, 0 }) then
        _buffPickQ[1] = '';
        imgui.OpenPopup(comboId .. '_pop');
    end
    -- Bound height: unconstrained, ~600 effects auto-size the popup to the
    -- whole window. The constraint grows a scrollbar by itself (floatgear's
    -- rule -- never a child window in a popup chain), and is safe to call
    -- even on shut frames in this binding (>= 1.77, see floatgear).
    imgui.SetNextWindowSizeConstraints({ 210, 0 }, { 280, 240 });
    if imgui.BeginPopup(comboId .. '_pop') then
        -- Cursor straight into the filter: start typing immediately
        -- (the weights add-stat picker's pattern).
        if imgui.IsWindowAppearing ~= nil and imgui.IsWindowAppearing()
           and imgui.SetKeyboardFocusHere ~= nil then imgui.SetKeyboardFocusHere(0); end
        imgui.PushItemWidth(190);
        imgui.InputText('##' .. comboId .. '_q', _buffPickQ, 48);
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then imgui.SetTooltip('Type to filter the status effects.'); end
        local q = string.lower(_buffPickQ[1] or '');
        local ok, names = pcall(buffChoices);
        local shown = 0;
        for _, nm in ipairs((ok and names) or {}) do
            if q == '' or string.find(string.lower(nm), q, 1, true) ~= nil then
                -- id carries the NAME (the '_o' shared-suffix click bug, see setPickCombo)
                if imgui.Selectable(nm .. '##' .. comboId .. '_o_' .. nm, false) then
                    picked = nm;
                    imgui.CloseCurrentPopup();
                end
                shown = shown + 1;
                if shown >= 200 and q == '' then
                    imgui.TextColored(COL_DIM, '(type to narrow the list...)');
                    break;
                end
            end
        end
        if shown == 0 then imgui.TextColored(COL_DIM, '(no match)'); end
        imgui.EndPopup();
    end
    return picked;
end

local trig = {
    data = nil, job = nil, err = nil, dirty = false,
    status = '', statusErr = false,
    addFor = nil, addConds = {}, _addDef = 1, _addValSel = nil, _addPlayer = 1,
    _addPet = 1,          -- the Pet cascade's picked parameter (engine v63)
    _condDrill = false,   -- no-BeginMenu fallback: which drill-down is open --
                          -- false closed, 'player' or 'pet' (truthy = open)
    addValText = { '' }, addValNum = { 0 }, addSet = nil, addPrio = { 0 }, _openAdd = false,
    editIdx = nil, _editEquip = nil,   -- rule-builder edit mode (replace in place)
    _bpEdit = nil,   -- when set, the rule builder edits Blueprint library entry #_bpEdit
                     -- (Save writes back to the library, not trig.data) -- issue #65
    _openModePopup = false,
    _prioBuf = {},
    _modeState = {}, _modeStateAt = -1,
    _fired = {}, _firedAt = -1,   -- the fired-trigger mirror cache (monitor window)
};

-- Mode builder popup state (create or edit one mode: toggle / cycle, values, bind).
local modeUI = {
    name = { '' }, kind = 'toggle', values = {}, valInput = { '' },
    bind = { '' }, set = nil, editing = nil,
};

-- Groups section state (issue #25, ADR 0009). newName = the create-popup buffer;
-- memberInput = a per-group typed-member buffer (keyed by group name); renaming =
-- the group whose rename popup is open, with renameBuf its buffer. status/statusErr
-- are the Groups section's own status line (independent of the Triggers tab's).
local groupUI = {
    newName = { '' }, memberInput = {}, renaming = nil, renameBuf = { '' },
    status = '', statusErr = false, _openAdd = false, _openRename = false,
    -- Import window (G4, issue #30; 07-20: a top-row button + popup, no longer a collapsible
    -- section): the paste box + a pending plan awaiting the overwrite confirmation. `plan` holds
    -- the parsed groups + the created/overwritten/skipped split between the Import click and the
    -- (Overwrite &) Import Groups click. _openImport defers the OpenPopup (the section pattern).
    importText = { '' }, plan = nil, _openImport = false,
    -- Auto-Import window (Item 1; 07-20: its top-row button RUNS the scan, then opens the picker):
    -- the scanned candidates + their tick state (name -> bool) + notes for the skipped tables + a
    -- pending plan awaiting the overwrite confirmation.
    autoCands = nil, autoNotes = nil, autoMarks = {}, autoPlan = nil, autoScanned = false,
    _openAuto = false,
    -- Browse-list picker (G3, issue #26): browseFor = the group the picker targets;
    -- browseSearch = its search box; browseMarks = a set of MARKED entries
    -- (lowercased name -> the proper-cased name to add); _list / _listJob cache the
    -- built job list so the ~1000-row scan runs once per job, not per frame.
    browseFor = nil, browseSearch = { '' }, browseMarks = {}, _openBrowse = false,
    _list = nil, _listJob = nil,
};

-- Profile-aware, and it MUST agree with the engine's triggersPath() rule
-- (dispatch.lua) or the GUI would edit one file while the engine reads another:
-- the active profile's file when it exists, else the legacy one, else wherever
-- writes should land (profile storage once it exists, legacy before).
local function trigFilePath()
    local base = deps and deps.charBase and deps.charBase() or nil;
    local abbr = nil;
    if deps and deps.jobFile then local _; _, abbr = deps.jobFile(); end
    if base == nil or abbr == nil then return nil, nil; end
    local lp = base .. 'dlac\\triggers\\' .. abbr .. '.lua';
    local pok, prof = pcall(require, 'dlac\\profiles');
    if pok and type(prof) == 'table' then
        local pp = prof.triggersPath(abbr);
        if pp ~= nil then
            if readFileText(pp) ~= nil then return pp, abbr; end
            if readFileText(lp) ~= nil then return lp, abbr; end
            return (prof.storageExists() and pp or lp), abbr;
        end
    end
    return lp, abbr;
end

-- Raw file table -> edit model lives in gear\triggermodel.lua (pure, tests TM* pin
-- the full serialize round-trip -- the wipe contract). This tab only draws it.

-- Load the trigger file into the edit model (triggermodel.fromRaw).
local function trigLoad(force)
    local path, abbr = trigFilePath();
    if path == nil then trig.data, trig.job, trig.err = nil, nil, 'not logged in / unknown job'; return; end
    if not force and trig.job == abbr and trig.data ~= nil then return; end
    trig.job, trig.data, trig.err, trig.dirty, trig._prioBuf = abbr, nil, nil, false, {};
    if not hasDispatch then trig.err = 'dispatch module unavailable'; return; end
    if not hasTrigModel then trig.err = 'triggermodel module unavailable'; return; end
    local raw, err = dsp.readTriggersRaw(path);
    if raw == nil then trig.err = err; return; end
    trig.data = tmodel.fromRaw(raw, dsp.canonEvent);
end

local function trigSetStatus(msg, isErr) trig.status = msg or ''; trig.statusErr = (isErr == true); trig.statusAt = os.clock(); end

-- Current trigger model + job, loading on demand (for gearcheck and other consumers).
function M.currentModel()
    pcall(trigLoad, false);
    if type(trig) ~= 'table' then return nil, nil; end
    return trig.data, trig.job;
end

-- Serialize + write the trigger file, then ping the LAC-state engine to hot-reload.
local function trigCommit()
    local path, abbr = trigFilePath();
    if path == nil or trig.data == nil or not hasDispatch then trigSetStatus('Nothing to commit.', true); return; end
    local text;
    local ok = pcall(function() text = dsp.serializeTriggers(trig.data); end);
    if not ok or type(text) ~= 'string' then trigSetStatus('Serialize failed.', true); return; end
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then
            ashita.fs.create_directory(deps.charBase() .. 'dlac\\triggers\\');
        end
    end);
    pcall(function()   -- the commit target may be profile storage: ensure its dirs too
        local pok, prof = pcall(require, 'dlac\\profiles');
        if pok and type(prof) == 'table' and prof.storageExists() then prof.ensureStorage(); end
    end);
    if not writeFileText(path, text) then trigSetStatus('Could not write ' .. path, true); return; end
    trig.dirty = false;
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl triggers reload'); end);
    trigSetStatus('Committed -- live now (hot-reloaded; no /lac reload needed).', false);
end

-- ---------------------------------------------------------------------------
-- Blueprints (issue #65, slice 1). The library is ONE per-character file OUTSIDE
-- Profiles (<char>\dlac\blueprints.lua) -- addon-state only, the engine never reads
-- it. bp is the pure core (CRUD / stamp / serialize); this block owns the file IO
-- (the backup->temp->validate->swap ladder, hard rule 7) and the section render.
-- Stamp routes through trigCommit -- the SAME commit path the Triggers tab uses.
-- ---------------------------------------------------------------------------
local bpUI = {
    lib = nil, path = nil, err = nil,
    status = '', statusErr = false, statusAt = 0,
    renaming = nil, renameBuf = { '' }, _openRename = false,
    delArm = nil,
    -- Text sharing (issue #66, slice 2). View text: the popup shows ONE entry's blob (viewIdx set)
    -- or the WHOLE library (viewIdx == 'all', Copy all); viewText is the cached blob. Import: a
    -- paste box with a live-parsed plan (created/collided split) awaiting the overwrite confirm.
    viewIdx = nil, viewText = '', viewBuf = { '' }, _openView = false,
    importText = { '' }, importPlan = nil, importParsedLen = -1, _openImport = false,
};
local function bpSetStatus(msg, isErr)
    bpUI.status = msg or ''; bpUI.statusErr = (isErr == true); bpUI.statusAt = os.clock();
end

-- The per-character library path (NOT profile-scoped -- a Blueprint is job- AND
-- profile-independent). nil before login / known char dir; retry, never cache the nil.
local function bpFilePath()
    local base = deps and deps.charBase and deps.charBase() or nil;
    if base == nil then return nil; end
    return base .. 'dlac\\blueprints.lua';
end

-- Load (or reload) the library. Caches by path; a char change re-reads. A missing
-- file is an empty library; a torn file loses the library (reported) until the next
-- good save self-heals it -- never a crash (the sandboxed parse).
local function bpLoad(force)
    local path = bpFilePath();
    if path == nil then return; end
    if not force and bpUI.lib ~= nil and bpUI.path == path then return; end
    bpUI.path, bpUI.err = path, nil;
    if not hasBlueprints then bpUI.lib = {}; bpUI.err = 'blueprintsmodel module unavailable'; return; end
    local text = readFileText(path);
    if text == nil then bpUI.lib = {}; return; end        -- no library yet
    local list, perr = bp.parse(text);
    if list == nil then bpUI.lib = {}; bpUI.err = perr; return; end
    bpUI.lib = list;
end

-- Persist the library through the safe-replace ladder (backup -> temp -> parse/validate
-- -> atomic swap -> restore on failure). Falls back to a guarded plain write only when
-- lib\safewrite is unreachable. Returns ok.
local function bpSave()
    local path = bpFilePath();
    if path == nil or bpUI.lib == nil then bpSetStatus('Not logged in -- cannot save Blueprints.', true); return false; end
    local text;
    local ok = pcall(function() text = bp.serialize(bpUI.lib, hasDispatch and dsp.PRETTY_KEY or nil); end);
    if not ok or type(text) ~= 'string' then bpSetStatus('Serialize failed.', true); return false; end
    local base = deps.charBase();
    local prev = readFileText(path);
    local swok, sw = pcall(require, 'dlac\\lib\\safewrite');
    if swok and type(sw) == 'table' and type(sw.replaceLua) == 'function' then
        if prev ~= nil then                                -- back up an existing library first
            pcall(function() sw.timestampBackup(base .. 'backups\\', 'blueprints-', prev); end);
        end
        local rok, rerr = sw.replaceLua(path, text, {
            origText = prev,
            validate = function(chunk)
                local vok, ret = pcall(chunk);
                return vok and type(ret) == 'table', 'library did not return a table';
            end,
        });
        if rok ~= true then bpSetStatus('Could not save Blueprints: ' .. tostring(rerr), true); return false; end
        return true;
    end
    -- fallback: ensure the dlac dir, then plain write
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then
            ashita.fs.create_directory(base .. 'dlac\\');
        end
    end);
    if not writeFileText(path, text) then bpSetStatus('Could not write ' .. path, true); return false; end
    return true;
end

-- Capture a live trigger rule into the library (Save-as-Blueprint, one click). The rule
-- is deep-copied + sanitized by the pure core, so the Blueprint detaches immediately.
local function bpCapture(handler, rule)
    if not hasBlueprints then bpSetStatus('Blueprints unavailable.', true); return; end
    bpLoad(false);
    if bpUI.lib == nil then bpSetStatus('Log in before saving a Blueprint.', true); return; end
    local okA, errA = bp.add(bpUI.lib, handler, rule);
    if not okA then bpSetStatus('Could not save Blueprint: ' .. tostring(errA), true); return; end
    if bpSave() then
        local nm = bpUI.lib[#bpUI.lib].name;
        bpSetStatus(string.format('Saved as Blueprint "%s" -- rename or stamp it in the Blueprints section.', nm), false);
    else
        table.remove(bpUI.lib);                            -- write failed: don't keep a phantom entry
    end
end

-- ---------------------------------------------------------------------------
-- Mode deletion. Field lesson (T1_Inc_Wpn on WAR): removing just the DEFINITION
-- leaves the mode alive -- rules and set-entry gates still reference it, and the
-- engine's live flag keeps it in the modestate mirror. Deleting now (a) finds
-- every reference first and offers a one-click cleanup, (b) commits immediately,
-- and (c) clears the live flag ('/dl mode X off' + the engine's stale-cycle
-- purge on trigger reload).
-- ---------------------------------------------------------------------------
local function modeCondText(mc)
    if type(mc) == 'table' then return table.concat(mc, ' | '); end
    return tostring(mc);
end

-- Rule references to a dead mode CONDITION in `data` (the trigger model):
-- `name` is a whole mode ('X' -- matches 'X' and every 'X:Value') or one exact
-- cycle value ('X:Value'). strip=true edits the model in place, honouring the
-- v54 shape -- a rule fires on (ALL of `when`) OR (ANY whenAny entry):
--   * a mode list just loses the dead name when other modes remain;
--   * a leg whose mode list EMPTIES was load-bearing on it: an & leg collapses
--     to {} (the rule lives on as OR-only), a dead | entry is removed whole;
--   * a rule with no live leg left is removed.
-- Takes the model explicitly (callers pass trig.data) so the offline tests can
-- drive it on a built table; only strip marks trig.dirty.
local function modeCondRefs(data, name, strip)
    local out = { rules = {}, removedRules = 0, editedRules = 0 };
    local target = string.lower(tostring(name or ''));
    if target == '' or type(data) ~= 'table' then return out; end
    local function matches(m)
        local s = string.lower(tostring(m));
        return s == target or string.sub(s, 1, #target + 1) == (target .. ':');
    end
    local function split(mc)   -- mode cond (string | list | nil) -> hit, kept[]
        if mc == nil then return false, nil; end
        local gates = (type(mc) == 'table') and mc or { mc };
        local kept, hit = {}, false;
        for _, m in ipairs(gates) do
            if matches(m) then hit = true; else kept[#kept + 1] = m; end
        end
        return hit, kept;
    end
    for _, sec in ipairs(TRIG_HANDLERS) do
        local list = data[sec];
        if type(list) == 'table' then
            for i = #list, 1, -1 do
                local r = list[i];
                if type(r) == 'table' and type(r.when) == 'table' then
                    local whenHit, whenKept = split(r.when.mode);
                    local anyHit, hitEntries = false, 0;
                    if type(r.whenAny) == 'table' then
                        for j = #r.whenAny, 1, -1 do
                            local e = r.whenAny[j];
                            local eHit, eKept = split((type(e) == 'table') and e.mode or nil);
                            if eHit then
                                anyHit = true; hitEntries = hitEntries + 1;
                                if strip then
                                    if #eKept == 0 then table.remove(r.whenAny, j);
                                    else e.mode = (#eKept == 1) and eKept[1] or eKept; end
                                end
                            end
                        end
                    end
                    if whenHit or anyHit then
                        local what = {};   -- described BEFORE any narrowing below
                        if whenHit then what[#what + 1] = 'mode ' .. modeCondText(r.when.mode); end
                        if anyHit then
                            what[#what + 1] = string.format('%d OR-group entr%s',
                                hitEntries, (hitEntries == 1) and 'y' or 'ies');
                        end
                        out.rules[#out.rules + 1] = string.format('%s:  %s  ->  %s',
                            sec, table.concat(what, ' + '),
                            (r.set ~= nil) and ('set ' .. ((type(r.set) == 'table') and table.concat(r.set, ' + ') or tostring(r.set)))
                            or 'equip { ... }');
                        if strip then
                            local hadAny = (type(r.whenAny) == 'table');
                            local anyLeft = hadAny and #r.whenAny or 0;
                            local whenLegDead = whenHit and #whenKept == 0;
                            -- OR-only shape: the & leg carried no conditions at all
                            local orOnly = (not whenHit) and next(r.when) == nil and hadAny;
                            if (whenLegDead and (not hadAny or anyLeft == 0))
                               or (orOnly and anyLeft == 0) then
                                table.remove(list, i);          -- no live leg left
                                out.removedRules = out.removedRules + 1;
                            else
                                if whenLegDead then r.when = {};    -- collapses to OR-only
                                elseif whenHit then
                                    r.when.mode = (#whenKept == 1) and whenKept[1] or whenKept;
                                end
                                if hadAny and anyLeft == 0 then r.whenAny = nil; end
                                out.editedRules = out.editedRules + 1;
                            end
                            trig.dirty = true;
                        end
                    end
                end
            end
        end
    end
    return out;
end
M._modeCondRefs = modeCondRefs;   -- headless test seam (dispatch's _matches idiom)

-- Set RENAME references (Henrik 2026-07-20: rename a set once, every rule
-- follows): rewrite every rule whose `set` action names `old` to `new` --
-- plain strings and multi-set lists, across every handler section including
-- Default's mode overlays. EXACT match: the engine's gProfile.Sets lookup is
-- exact, so only exact references ever worked; a case-drifted one is already
-- broken and stays visibly broken ([missing set]) instead of silently
-- changing meaning. Pure on `data` for the headless tests (RS*).
local function renameSetRefsIn(data, old, new)
    local edited = 0;
    if type(data) ~= 'table' then return edited; end
    for _, sec in ipairs(TRIG_HANDLERS) do
        local list = data[sec];
        if type(list) == 'table' then
            for _, r in ipairs(list) do
                if type(r) == 'table' then
                    if r.set == old then
                        r.set = new;
                        edited = edited + 1;
                    elseif type(r.set) == 'table' then
                        local hit = false;
                        for i, s in ipairs(r.set) do
                            if s == old then r.set[i] = new; hit = true; end
                        end
                        if hit then edited = edited + 1; end
                    end
                end
            end
        end
    end
    return edited;
end
M._renameSetRefsIn = renameSetRefsIn;   -- headless test seam

-- The Sets tab calls this right after renaming the set on disk. Returns the
-- number of rules rewritten; commits (and hot-reloads the engine's triggers)
-- only when something changed.
function M.renameSetRefs(old, new)
    pcall(trigLoad, false);
    if trig.data == nil then return 0; end
    local edited = renameSetRefsIn(trig.data, old, new);
    if edited > 0 then
        trig.dirty = true;
        trigCommit();
    end
    return edited;
end

-- Remove the definition, write the file NOW, and kill the live flag. The commit's
-- '/dl triggers reload' makes the engine purge a stale cycle value; the queued
-- 'off' (processed after the reload) clears a live toggle flag.
local function deleteModeNow(name)
    if trig.data ~= nil and trig.data.Modes ~= nil then trig.data.Modes[name] = nil; end
    trig.dirty = true;
    trigCommit();
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl mode ' .. name .. ' off'); end);
end

-- Mode display state: the LAC-state engine mirrors its session flags to
-- <char>\dlac\modestate.lua on every change; re-read at most once per second.
local function trigModeState()
    local now = os.time();
    if now == trig._modeStateAt then return trig._modeState; end
    trig._modeStateAt = now;
    local st = {};
    trig._modeStateExists = false;
    pcall(function()
        local base = deps.charBase();
        if base == nil then return; end
        local chunk = loadfile(base .. 'dlac\\modestate.lua');
        if chunk == nil then return; end
        trig._modeStateExists = true;
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then st = t; end
    end);
    trig._modeState = st;
    return st;
end

-- The monitor's LIVE event feed (engine v55): the engine queues
-- '/dlacmonev <line>' on every CHANGE of what fired; this ADDON-state handler
-- pushes it straight into the ring the frame it arrives -- streaming, not
-- polling. A repeat of the same line never re-reacts (Henrik's dedupe rule;
-- the engine's retrace gate already ensures unchanged rules don't re-send).
if ashita ~= nil and ashita.events ~= nil then
    pcall(function()
        pcall(function() ashita.events.unregister('command', 'dlac-trigmon'); end);
        ashita.events.register('command', 'dlac-trigmon', function(e)
            local raw = e.command;
            if type(raw) ~= 'string' or string.sub(raw, 1, 11) ~= '/dlacmonev ' then return; end
            e.blocked = true;
            local line = string.sub(raw, 12);
            if line == '' or trig._fired[1] == line then return; end
            table.insert(trig._fired, 1, line);
            while #trig._fired > 5 do table.remove(trig._fired); end
            trig._firedLive = true;   -- events own the ring now; file re-reads stop
        end);
    end);
end

-- The fired-trigger mirror (firedstate.lua): the RELOAD BOOTSTRAP + fallback --
-- once the first live event lands, the ring is event-owned and the file is
-- never re-read. Same 1/sec throttle discipline as trigModeState meanwhile.
local function trigFiredState()
    if trig._firedLive == true then return trig._fired; end
    local now = os.time();
    if now == trig._firedAt then return trig._fired; end
    trig._firedAt = now;
    local out = {};
    pcall(function()
        local base = deps.charBase();
        if base == nil then return; end
        local chunk = loadfile(base .. 'dlac\\firedstate.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then
            for _, s in ipairs(t) do
                if type(s) == 'string' then out[#out + 1] = s; end
            end
        end
    end);
    trig._fired = out;
    return out;
end

-- The floating Trigger Monitor (Henrik): active modes + the last 5 rules that
-- fired, newest first, STREAMED over the command bus the moment they change --
-- field-testing triggers without chasing /dl why while Precast/Midcast flash
-- past. A titled window (imgui.ini remembers where you drag it); its [X]
-- clears the toggle. Rendered from the present hook, so it survives closing
-- the main dlac window (the lockstyle/floatgear rule).
function M.renderMonitor(ui)
    if not hasImgui or ui == nil or ui._tgMon ~= true then return; end
    imgui.SetNextWindowSize({ 400, 190 }, ImGuiCond_FirstUseEver);
    local open = { true };
    if imgui.Begin('dlac Trigger Monitor##dlac_tgmon', open) then
        local st = trigModeState();
        local ms = {};
        for k, v in pairs(st) do
            if type(k) == 'string' and string.sub(k, 1, 2) ~= '__' then
                ms[#ms + 1] = (v == true) and k or (k .. ':' .. tostring(v));
            end
        end
        table.sort(ms);
        imgui.TextColored(COL_HEADER, 'modes');
        imgui.SameLine(0, 8);
        if #ms > 0 then imgui.TextColored(COL_USABLE, esc(table.concat(ms, '   ')));
        else imgui.TextColored(COL_DIM, '(none active)'); end
        imgui.Separator();
        local fired = trigFiredState();
        if #fired == 0 then
            imgui.TextColored(COL_DIM, 'nothing fired yet -- do something and watch.');
        else
            for i, s in ipairs(fired) do
                imgui.TextColored((i == 1) and COL_USABLE or COL_DIM, esc(s));
            end
        end
    end
    imgui.End();
    if not open[1] then
        ui._tgMon = false;
        ui._flagsDirty = true;
    end
end

-- Is a set-entry mode condition ('Name' / 'Name:Value') active RIGHT NOW, judged
-- against the LAC-state mirror (display truth in the addon state)? Used by the
-- Sets tab preview so mode-gated slot entries light up with the live mode.
function M.entryModeActive(cond)
    if not hasDispatch or type(dsp.modeActive) ~= 'function' then return false; end
    local ok, r = pcall(dsp.modeActive, cond, trigModeState());
    return ok and r == true;
end

-- Known mode conditions for pickers: every cycle value as 'Name:Value', plus each
-- toggle name seen in the Modes section or referenced by any rule's mode condition.
function M.modeConditions()
    local seen, out = {}, {};
    local function add(s)
        if type(s) == 'string' and s ~= '' and not seen[string.lower(s)] then
            seen[string.lower(s)] = true; out[#out + 1] = s;
        end
    end
    local data = select(1, M.currentModel());
    if type(data) ~= 'table' then return out; end
    if type(data.Modes) == 'table' then
        for nm, def in pairs(data.Modes) do
            if type(def.values) == 'table' and #def.values > 0 then
                for _, v in ipairs(def.values) do add(nm .. ':' .. v); end
            else
                add(nm);
            end
        end
    end
    for ev, list in pairs(data) do
        if ev ~= 'Modes' and type(list) == 'table' then
            for _, r in ipairs(list) do
                if type(r) == 'table' and type(r.when) == 'table' and r.when.mode ~= nil then
                    add(tostring(r.when.mode));
                end
            end
        end
    end
    table.sort(out, function(a, b) return string.lower(a) < string.lower(b); end);
    return out;
end

-- The current job's defined group names (sorted) -- the `group` condition dropdown
-- and the stale-reference check read this. Loads the model on demand.
function M.groupNames()
    local data = select(1, M.currentModel());
    if type(data) ~= 'table' or type(data.Groups) ~= 'table' then return {}; end
    if hasGroups then return gm.names(data.Groups); end
    local out = {};
    for nm in pairs(data.Groups) do if type(nm) == 'string' then out[#out + 1] = nm; end end
    table.sort(out);
    return out;
end

-- Is `name` a defined group in the current model (case-insensitive)? Drives the
-- stale-reference surfacing (a rule pointing at a missing group is marked, never a
-- silent no-op -- parity with a missing set; hard rule 12).
local function groupDefined(name)
    local data = select(1, M.currentModel());
    if type(data) ~= 'table' or type(data.Groups) ~= 'table' then return false; end
    if hasGroups then return gm.hasGroup(data.Groups, name); end
    for nm in pairs(data.Groups) do
        if type(nm) == 'string' and string.lower(nm) == string.lower(tostring(name)) then return true; end
    end
    return false;
end

local function trigPrettyKey(k)
    if hasDispatch and type(dsp.PRETTY_KEY) == 'table' and dsp.PRETTY_KEY[k] ~= nil then return dsp.PRETTY_KEY[k]; end
    return k;
end

local function condSummary(when)
    local parts = {};
    for k, v in pairs(when or {}) do
        if v == true then parts[#parts + 1] = trigPrettyKey(k);
        else parts[#parts + 1] = trigPrettyKey(k) .. '=' .. tostring(v); end
    end
    table.sort(parts);
    return (#parts > 0) and table.concat(parts, ' + ') or 'any';
end

-- Every set name a trigger may TARGET: the LIVE profile's names (Dynamic +
-- the job file's own statics). Backup-only statics are excluded on purpose --
-- they exist for "Copy from" in the Sets tab, but the engine's gProfile never
-- holds them, so targeting one equips nothing (and marks [missing] here).
local function allSetNames()
    if deps.liveSetNames ~= nil then
        local ok, live = pcall(deps.liveSetNames);
        if ok and type(live) == 'table' then return live; end
    end
    local names = deps.dynamicSetNames();
    local seen = {};
    for _, n in ipairs(names) do seen[n] = true; end
    for _, n in ipairs(deps.staticSetNames()) do
        if not seen[n] then names[#names + 1] = n; seen[n] = true; end
    end
    table.sort(names);
    return names;
end

-- A SEARCHABLE set-name picker (profiles collect many sets): a button opening
-- a plain popup with a filter box + the names -- the field-proven '+ Add'
-- pattern, NOT an InputText inside BeginCombo (this imgui build mishandled
-- that, killing clicks: field case 'can't add an overlay set'). Returns the
-- clicked name (nil otherwise). exclude = names to hide (already picked);
-- includeNone adds a '(none)' row that returns the string '(none)'.
local _setPickQ = { '' };
local function setPickCombo(comboId, label, exclude, includeNone)
    local picked = nil;
    if imgui.Button(label .. '###' .. comboId .. '_btn', { 170, 0 }) then
        _setPickQ[1] = '';
        imgui.OpenPopup(comboId .. '_pop');
    end
    if imgui.BeginPopup(comboId .. '_pop') then
        imgui.PushItemWidth(190);
        imgui.InputText('##' .. comboId .. '_q', _setPickQ, 48);
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then imgui.SetTooltip('Type to filter the sets.'); end
        local q = string.lower(_setPickQ[1] or '');
        if includeNone and (q == '' or string.find('(none)', q, 1, true) ~= nil) then
            if imgui.Selectable('(none)##' .. comboId .. '_none', false) then
                picked = '(none)';
                imgui.CloseCurrentPopup();
            end
        end
        -- guarded: an error mid-popup tears the frame and kills every click.
        -- NOTE the id: everything after '##' IS the imgui id, so it must carry
        -- the NAME -- a shared '_o' suffix gave every row the same id and only
        -- the first one took clicks (field case: 'only Ballad works').
        local ok, names = pcall(allSetNames);
        local shown = 0;
        for _, nm in ipairs((ok and names) or {}) do
            local hide = false;
            if exclude ~= nil then
                for _, x in ipairs(exclude) do if x == nm then hide = true; break; end end
            end
            if not hide and (q == '' or string.find(string.lower(nm), q, 1, true) ~= nil) then
                if imgui.Selectable(nm .. '##' .. comboId .. '_o_' .. nm, false) then
                    picked = nm;
                    imgui.CloseCurrentPopup();
                end
                shown = shown + 1;
            end
        end
        if shown == 0 then imgui.TextColored(COL_DIM, '(no match)'); end
        imgui.EndPopup();
    end
    return picked;
end

-- ---------------------------------------------------------------------------
-- Automations moved OUT (2026-07-18): the whole manifest machinery (ADR 0004 --
-- staves/obis, MaxMP batteries, craft/HELM/fish ladders) plus the Automations
-- MAIN tab now live in ui\automationsui.lua (same deps table, injected by
-- gearui). The rescan seams (rescanAutogear / manifestStale / currentFmt) went
-- with it -- craftwatch/helmwatch/fishwatch and gearui's sync hook call THAT
-- module now; nothing in this file references the automation machinery.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Gear warnings section: trigger-referenced sets whose pieces are not in an
-- equippable bag right now (gearcheck audit; cached ~2s -- ownedSplit walks
-- every container).
-- ---------------------------------------------------------------------------
local function renderGearWarnings(noHeader)
    local gc = nil;
    pcall(function() gc = require("dlac\\gear\\gearcheck"); end);
    if type(gc) ~= 'table' or type(gc.auditCached) ~= 'function' then return; end
    local warns = {};
    pcall(function() warns = gc.auditCached(2) or {}; end);
    local n = #warns;
    if noHeader ~= true then
        local flags = (n > 0 and ImGuiTreeNodeFlags_DefaultOpen ~= nil) and ImGuiTreeNodeFlags_DefaultOpen or 0;
        if not imgui.CollapsingHeader(string.format('Gear warnings (%d)###trgsec_warn', n), flags) then return; end
    end
    if imgui.Button('Re-check now##trgwarnrefresh', { 0, 20 }) then
        pcall(gc.invalidate);
        pcall(gc.chatWarn, true);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Re-audit every trigger-referenced set against your bags and print the result to chat.');
    end
    if n == 0 then
        imgui.TextColored(COL_DIM, 'Everything your triggers reference is equippable. (checked against your bags)');
        return;
    end
    imgui.PushTextWrapPos(0.0);
    for _, w in ipairs(warns) do
        local col = (w.kind == 'stored' or w.kind == 'missing') and COL_ERR or { 0.95, 0.80, 0.35, 1.0 };
        imgui.TextColored(col, '[!] ' .. esc(gc.describe(w)));
    end
    imgui.PopTextWrapPos();
end

-- ---------------------------------------------------------------------------
-- Mode builder popup: create/edit one mode with labelled fields -- toggle vs
-- cycle chosen explicitly, cycle values added ONE AT A TIME into a visible,
-- removable ordered list (no comma strings).
-- ---------------------------------------------------------------------------
-- The one Default rule a toggle's "Overlay set" owns: when = { mode = <name> }
-- and NOTHING else. Multi-condition hand-made rules never match this shape, so
-- the editor can sync its rule without touching theirs.
local function findOverlayRule(name)
    local lnm = string.lower(tostring(name or ''));
    for i, r in ipairs((trig.data and trig.data.Default) or {}) do
        -- STRING set only: a multi-set rule is not the editor-owned overlay shape
        if type(r) == 'table' and type(r.when) == 'table' and type(r.set) == 'string' then
            local mc, extra = nil, false;
            for k, v in pairs(r.when) do
                if string.lower(tostring(k)) == 'mode' then mc = v; else extra = true; end
            end
            if not extra and type(mc) == 'string' and string.lower(mc) == lnm then
                return i, r;
            end
        end
    end
    return nil, nil;
end

local function openModeEditor(m, def)
    modeUI.editing = m;
    modeUI.name[1] = m;
    modeUI.bind[1] = (def ~= nil and def.bind ~= nil) and def.bind or '';
    modeUI.set = nil;
    modeUI.valInput[1] = '';
    modeUI.values = {};
    if def ~= nil and def.values ~= nil then
        modeUI.kind = 'cycle';
        for _, v in ipairs(def.values) do modeUI.values[#modeUI.values + 1] = v; end
    else
        modeUI.kind = 'toggle';
        -- Prefill the overlay from the toggle's existing rule, so editing shows
        -- (and can change/clear) what is actually wired -- picking a set while
        -- EDITING used to be silently ignored (field report).
        local _, r = findOverlayRule(m);
        if r ~= nil then modeUI.set = r.set; end
    end
    trig._openModePopup = true;
end

local function renderModePopup()
    if not imgui.BeginPopup('##dlac_modeadd') then return; end
    local editing = (modeUI.editing ~= nil);
    imgui.TextColored(COL_HEADER, editing and ('Edit mode: ' .. modeUI.editing) or 'New mode');
    imgui.Separator();

    if not editing then
        imgui.TextColored(COL_DIM, 'Name'); imgui.SameLine(0, 8);
        imgui.PushItemWidth(140); imgui.InputText('##modenm', modeUI.name, 24); imgui.PopItemWidth();
        if imgui.IsItemHovered() then imgui.SetTooltip('e.g. DT, TH, Weapon, IdleSet'); end

        -- kind chooser: two buttons, the active one highlighted (works on every binding).
        imgui.TextColored(COL_DIM, 'Kind'); imgui.SameLine(0, 8);
        local styled = (ImGuiCol_Button ~= nil);
        local function kindBtn(label, kind)
            if styled then
                local on = (modeUI.kind == kind);
                imgui.PushStyleColor(ImGuiCol_Button, on and { 0.20, 0.42, 0.58, 1.0 } or { 0.30, 0.30, 0.34, 1.0 });
            end
            if imgui.Button(label, { 0, 0 }) then modeUI.kind = kind; end
            if styled then imgui.PopStyleColor(1); end
        end
        kindBtn('Toggle (on / off)##modekt', 'toggle');
        imgui.SameLine(0, 6);
        kindBtn('Cycle (list of values)##modekc', 'cycle');
    end

    if modeUI.kind == 'cycle' then
        imgui.TextColored(COL_DIM, 'Values -- cycles in this order; the FIRST is active at login:');
        local removeAt = nil;
        for i, v in ipairs(modeUI.values) do
            imgui.TextColored(COL_USABLE, string.format('   %d.  %s', i, esc(v)));
            imgui.SameLine(0, 10);
            if imgui.SmallButton('x##modevx' .. i) then removeAt = i; end
        end
        if removeAt ~= nil then table.remove(modeUI.values, removeAt); end
        imgui.PushItemWidth(140); imgui.InputText('##modevin', modeUI.valInput, 32); imgui.PopItemWidth();
        imgui.SameLine(0, 4);
        if imgui.Button('+ value##modevadd', { 0, 0 }) then
            local v = modeUI.valInput[1];
            if v ~= nil and v ~= '' then
                modeUI.values[#modeUI.values + 1] = v;
                modeUI.valInput[1] = '';
            end
        end
        if imgui.IsItemHovered() then imgui.SetTooltip('Type one value (e.g. Melee) and click + value. Repeat for each\n(Ranged, Caster, ...).'); end
    else
        imgui.TextColored(COL_DIM, 'Overlay set (optional)'); imgui.SameLine(0, 8);
        imgui.PushItemWidth(150);
        local ovrPick = setPickCombo('##modeset', modeUI.set or '(none)', nil, true);
        if ovrPick == '(none)' then modeUI.set = nil;
        elseif ovrPick ~= nil then modeUI.set = ovrPick; end
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Wires the classic overlay for you: a rule  mode = <name>  ->  this set\nin the DEFAULT trigger at priority 100 -- while the mode is ON it applies\nLAST, overlaying only the slots the set fills. Other events (Precast,\nMidcast, WS...) are untouched. Pick (none) to remove the rule again.');
        end
    end

    imgui.TextColored(COL_DIM, 'Keybind (optional)'); imgui.SameLine(0, 8);
    imgui.PushItemWidth(70); imgui.InputText('##modebind', modeUI.bind, 16); imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('e.g. F9, ^F3 (Ctrl+F3), !F3 (Alt+F3). Applied automatically at\nprofile load -- no OnLoad code needed.');
    end
    imgui.Separator();

    local nm = editing and modeUI.editing or modeUI.name[1];
    local can = (nm ~= nil and nm ~= '') and (modeUI.kind == 'toggle' or #modeUI.values >= 2);
    if imgui.Button((editing and 'Save mode' or 'Create mode') .. '###modego', { 0, 0 }) and can then
        local bind = (modeUI.bind[1] ~= nil and modeUI.bind[1] ~= '') and modeUI.bind[1] or nil;
        trig.data.Modes = trig.data.Modes or {};
        if modeUI.kind == 'cycle' then
            -- Values removed by this edit kill their 'Name:Value' condition
            -- everywhere it is applied (Henrik 2026-07-18: a changed cycle left
            -- dead gates on the weapons). Diff BEFORE the overwrite lands.
            local removed = {};
            if editing then
                local old = trig.data.Modes[nm];
                local keep = {};
                for _, v in ipairs(modeUI.values) do keep[string.lower(v)] = true; end
                for _, v in ipairs((old ~= nil and type(old.values) == 'table') and old.values or {}) do
                    if not keep[string.lower(v)] then removed[#removed + 1] = v; end
                end
            end
            trig.data.Modes[nm] = { values = modeUI.values, bind = bind };
            if #removed > 0 then
                -- Same cleanup + commit-now discipline as mode deletion: the
                -- reload also purges a removed value that is active right now
                -- (the engine's stale-cycle purge).
                local rem, trm, touched = 0, 0, {};
                for _, v in ipairs(removed) do
                    local rr = modeCondRefs(trig.data, nm .. ':' .. v, true);
                    rem = rem + rr.removedRules; trm = trm + rr.editedRules;
                    local sr = (deps ~= nil and type(deps.modeSetRefs) == 'function')
                        and deps.modeSetRefs(nm .. ':' .. v, true) or { touched = {} };
                    for _, s in ipairs(sr.touched or {}) do
                        local dup = false;
                        for _, t in ipairs(touched) do if t == s then dup = true; break; end end
                        if not dup then touched[#touched + 1] = s; end
                    end
                end
                table.sort(touched);
                trigCommit();
                trigSetStatus(string.format(
                    'Cycle "%s" saved; dead value gate(s) %s swept: %d rule(s) removed, %d trimmed; sets rewritten: %s%s',
                    nm, table.concat(removed, ', '), rem, trm,
                    (#touched > 0) and table.concat(touched, ', ') or '(none)',
                    (#touched > 0) and '  -- Reload LAC to apply the set changes.' or ''), false);
            else
                trigSetStatus(string.format('Cycle mode "%s": wire values with the rule condition  mode = %s:<value>,  then Commit.', nm, nm), false);
            end
        else
            -- A bind-less toggle keeps an EXPLICIT empty definition (Henrik
            -- 2026-07-20, Mindie BLU: created a plain toggle and it never
            -- showed in the Modes list -- it used to store nothing, so only a
            -- rule referencing it made it visible). serializeTriggers and
            -- triggermodel.fromRaw carry the {} through (TM20-22).
            trig.data.Modes[nm] = (bind ~= nil) and { bind = bind } or {};
            -- Overlay-set sync, on CREATE and EDIT alike: own the exact-shape
            -- rule (see findOverlayRule) -- picking a set writes/updates it,
            -- (none) removes it. Editing used to ignore the pick entirely.
            trig.data.Default = trig.data.Default or {};
            local ri, orule = findOverlayRule(nm);
            if modeUI.set == nil then
                if ri ~= nil then table.remove(trig.data.Default, ri); end
            elseif orule ~= nil then
                orule.set = modeUI.set;
            else
                table.insert(trig.data.Default, { when = { mode = nm }, set = modeUI.set });
            end
        end
        trig.dirty = true;
        modeUI.editing = nil;
        imgui.CloseCurrentPopup();
    end
    if not can then
        imgui.TextColored(COL_DIM, (modeUI.kind == 'cycle')
            and 'Needs a name and at least two values.' or 'Needs a name.');
    end
    if editing then
        imgui.SameLine(0, 12);
        if imgui.Button('Delete mode###modedel', { 0, 0 }) then
            local nmDel = modeUI.editing;
            local rr = modeCondRefs(trig.data, nmDel, false);
            local sr = (deps ~= nil and type(deps.modeSetRefs) == 'function')
                and deps.modeSetRefs(nmDel, false) or { refs = {} };
            if #rr.rules == 0 and #(sr.refs or {}) == 0 then
                deleteModeNow(nmDel);
                trigSetStatus(string.format('Deleted mode "%s" (nothing referenced it) -- live now.', nmDel), false);
            else
                -- references exist: open the movable reference window instead
                modeUI.del = { name = nmDel, rules = rr.rules, sets = sr.refs or {} };
            end
            modeUI.editing = nil;
            imgui.CloseCurrentPopup();
        end
        if imgui.IsItemHovered() then imgui.SetTooltip('Deletes the mode. If rules or set entries still reference it, a small\nwindow lists every reference first -- with a one-click "delete all".'); end
    end
    imgui.EndPopup();
end

-- The movable reference window a Delete-with-references opens. Small on purpose;
-- drag it aside and work through the list, or take the one-click cleanup:
-- rules gated ONLY on this mode are removed, list gates lose the dead name;
-- set entries gated only on it are deleted, list gates keep their other modes.
local function renderModeDeleteWindow()
    if modeUI.del == nil then return; end
    local d = modeUI.del;
    local open = { true };
    if imgui.Begin('Delete mode: ' .. d.name .. '###dlacmodedel', open, ImGuiWindowFlags_AlwaysAutoResize or 0) then
        imgui.TextColored(COL_ERR, string.format('"%s" is still referenced:', d.name));
        if #d.rules > 0 then
            imgui.TextColored(COL_HEADER, string.format('Trigger rules (%d)', #d.rules));
            for _, s in ipairs(d.rules) do imgui.TextColored(COL_DIM, '  ' .. esc(s)); end
        end
        if #d.sets > 0 then
            imgui.TextColored(COL_HEADER, string.format('Set entries (%d)', #d.sets));
            for _, r in ipairs(d.sets) do
                imgui.TextColored(COL_DIM, string.format('  %s / %s / %s%s',
                    esc(tostring(r.set)), esc(tostring(r.slot)), esc(tostring(r.item)),
                    r.gone and '' or '  (list gate: keeps its other modes)'));
            end
        end
        imgui.Spacing();
        if imgui.Button('Delete mode + ALL references##modedelall', { 0, 22 }) then
            local rr = modeCondRefs(trig.data, d.name, true);
            local sr = (deps ~= nil and type(deps.modeSetRefs) == 'function')
                and deps.modeSetRefs(d.name, true) or { touched = {} };
            deleteModeNow(d.name);
            local touched = sr.touched or {};
            trigSetStatus(string.format('Deleted "%s": %d rule(s) removed, %d trimmed; sets rewritten: %s%s',
                d.name, rr.removedRules, rr.editedRules,
                (#touched > 0) and table.concat(touched, ', ') or '(none)',
                (#touched > 0) and '  -- Reload LAC to apply the set changes.' or ''), false);
            modeUI.del = nil;
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Rules gated only on this mode are removed; a mode-list rule just loses the name.\nSet entries gated only on it are deleted; list gates keep their other modes.\nTrigger changes are live immediately; set changes need Reload LAC.');
        end
        imgui.SameLine(0, 8);
        if imgui.Button('Delete mode only##modedelonly', { 0, 22 }) then
            deleteModeNow(d.name);
            trigSetStatus(string.format('Deleted mode "%s" -- its references remain as listed.', d.name), false);
            modeUI.del = nil;
        end
        imgui.SameLine(0, 8);
        if imgui.Button('Cancel##modedelcancel', { 0, 22 }) then modeUI.del = nil; end
    end
    imgui.End();
    if not open[1] then modeUI.del = nil; end
end

-- ---------------------------------------------------------------------------
-- Rule boxes. Each Trigger renders in its OWN bordered box: conditions on the
-- left, ONE PER LINE, coloured by condition type ("method"); controls in a fixed
-- right-hand column whose X is computed per section from the longest condition
-- line, so every box in a section aligns.
-- ---------------------------------------------------------------------------

-- Distinct colour per condition type, so a rule's methods read at a glance.
local COND_COLORS = {
    status = { 0.55, 0.75, 1.00, 1.0 },  moving = { 0.55, 0.75, 1.00, 1.0 },
    intown = { 0.50, 0.82, 0.92, 1.0 },   -- location gate (v84): a teal-blue beside status/moving
    mode = { 0.80, 0.60, 1.00, 1.0 },
    skill = { 0.55, 0.85, 0.55, 1.0 },
    magictype = { 0.45, 0.80, 0.75, 1.0 }, abilitytype = { 0.45, 0.80, 0.75, 1.0 },
    element = { 0.95, 0.70, 0.45, 1.0 },  songtype = { 0.80, 0.85, 0.50, 1.0 },
    dayweatherbonus = { 0.60, 0.90, 0.90, 1.0 },
    contains = { 0.95, 0.85, 0.45, 1.0 }, family = { 0.95, 0.85, 0.45, 1.0 },
    group = { 0.55, 0.80, 1.00, 1.0 },
    name = { 1.00, 0.95, 0.75, 1.0 },
    any = { 0.60, 0.60, 0.65, 1.0 },
    -- Player-state gates (v54 + v53 aliases): vitals warm red / blue / gold,
    -- buffs violet.
    playerhpbelow = { 1.00, 0.60, 0.55, 1.0 }, playerhpabove = { 1.00, 0.60, 0.55, 1.0 },
    playerhppercentbelow = { 1.00, 0.60, 0.55, 1.0 }, playerhppercentabove = { 1.00, 0.60, 0.55, 1.0 },
    playermpbelow = { 0.55, 0.70, 1.00, 1.0 }, playermpabove = { 0.55, 0.70, 1.00, 1.0 },
    playermppercentbelow = { 0.55, 0.70, 1.00, 1.0 }, playermppercentabove = { 0.55, 0.70, 1.00, 1.0 },
    hpbelow = { 1.00, 0.60, 0.55, 1.0 }, hpabove = { 1.00, 0.60, 0.55, 1.0 },
    mpbelow = { 0.55, 0.70, 1.00, 1.0 }, mpabove = { 0.55, 0.70, 1.00, 1.0 },
    tpbelow = { 0.95, 0.85, 0.50, 1.0 }, tpabove = { 0.95, 0.85, 0.50, 1.0 },
    buff = { 0.85, 0.65, 1.00, 1.0 },    buffnot = { 0.85, 0.65, 1.00, 1.0 },
    -- Pet conditions (engine v63): the pet family reads green; petName a shade
    -- lighter (identity, like `name` vs `skill`).
    pet = { 0.50, 0.90, 0.60, 1.0 }, petstatus = { 0.50, 0.90, 0.60, 1.0 },
    petname = { 0.75, 0.95, 0.60, 1.0 },
};

-- A rule's conditions as display lines (sorted, one per line; 'any' when empty).
local function condLines(when)
    local out = {};
    for k, v in pairs(when or {}) do
        local txt = (v == true) and trigPrettyKey(k) or (trigPrettyKey(k) .. ' = ' .. tostring(v));
        out[#out + 1] = { key = k, text = txt };
    end
    table.sort(out, function(a, b) return a.key < b.key; end);
    if #out == 0 then out[1] = { key = 'any', text = 'any' }; end
    return out;
end

local function textW(s)
    local ok, w = pcall(imgui.CalcTextSize, s);
    if ok and type(w) == 'number' then return w; end
    return #tostring(s) * 7;
end

-- Width of the reserved [on now]/[off now] marker column (widest marker + gap).
local function markW() return textW('[off now]') + 14; end

-- Live readout for the v53 player-state gates: an ADDON-state ctx the ENGINE's
-- own matchers run against (dsp._matchers -- the exact dispatch logic, never a
-- re-implementation). 1s throttle; the buff matcher memoizes its buff set on
-- the ctx, so buffs also read once per second. nil when unreadable
-- (pre-login) -> no marker rather than a wrong one.
local PSTATE_KEYS = {
    playerhpbelow = true, playerhpabove = true,
    playerhppercentbelow = true, playerhppercentabove = true,
    playermpbelow = true, playermpabove = true,
    playermppercentbelow = true, playermppercentabove = true,
    tpbelow = true, tpabove = true, buff = true, buffnot = true,
    -- v53 alias spellings (percent semantics) stay markable too
    hpbelow = true, hpabove = true, mpbelow = true, mpabove = true,
    -- Pet conditions (engine v63) light too: pet-out is exactly the kind of
    -- state you want to SEE holding while you build the rule.
    pet = true, petstatus = true, petname = true,
    -- inTown (engine v84): the [on now] marker reads your live zone through the
    -- engine's own matcher (zoneOf does GetMemberZone on the addon side), so you
    -- can watch it light up as you walk into a city while building the rule.
    intown = true,
};
-- LAC's EntityStatus resolution (constants.lua:236 via ResolveString's +1):
-- raw entity status 0 Idle / 1 Engaged / 2-3 Dead / 4 Zoning / 33 Resting.
local PET_STATUS_OF = { [0] = 'Idle', [1] = 'Engaged', [2] = 'Dead', [3] = 'Dead',
                        [4] = 'Zoning', [33] = 'Resting' };
local _psAt, _psCtx = -1, nil;
local function pstateCtx()
    if os.clock() < _psAt then return _psCtx; end
    _psAt = os.clock() + 1.0;
    _psCtx = nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local hpp = party:GetMemberHPPercent(0);
        if hpp ~= nil then
            _psCtx = { player = { HPP = hpp, MPP = party:GetMemberMPPercent(0),
                                  HP = party:GetMemberHP(0), MP = party:GetMemberMP(0),
                                  TP = party:GetMemberTP(0) } };
            -- ctx.pet for the pet markers (v63): the same read LAC's
            -- gData.GetPet does (data.lua:534) -- pet index 0 or pet HPP 0 is
            -- NO pet, so a dead pet reads as none here exactly like in the
            -- engine. Inner pcall: a pet read must never cost the vitals.
            pcall(function()
                local ent = AshitaCore:GetMemoryManager():GetEntity();
                local petIndex = ent:GetPetTargetIndex(party:GetMemberTargetIndex(0));
                if petIndex ~= 0 and ent:GetHPPercent(petIndex) ~= 0 then
                    _psCtx.pet = { Name = ent:GetName(petIndex),
                                   Status = PET_STATUS_OF[ent:GetStatus(petIndex)] or 'Unknown',
                                   HPP = ent:GetHPPercent(petIndex) };
                end
            end);
        end
    end);
    return _psCtx;
end
local function pstateHolds(key, v)
    local ctx = pstateCtx();
    if ctx == nil or dsp == nil or type(dsp._matchers) ~= 'table'
       or dsp._matchers[key] == nil then return nil; end
    local ok, res = pcall(dsp._matchers[key], v, ctx);
    if not ok then return nil; end
    return res == true;
end

-- One rule box. colX = the section's aligned controls column. Returns 'remove'/'edit'/nil.
-- Bordered content boxes must never grow their own scrollbar: we size them to
-- their content and suppress the bar (a 1px estimate miss otherwise shows an
-- ugly full-height slider inside every box).
local BOX_FLAGS = ImGuiWindowFlags_NoScrollbar or 0;

-- Real per-line height (font + item spacing) -- hardcoded estimates clipped the
-- last line of taller boxes (a 4-value cycle lost its 4th value).
local function lineH()
    local lh = 21;
    pcall(function()
        local v = imgui.GetTextLineHeightWithSpacing();
        if type(v) == 'number' and v > 0 then lh = v; end
    end);
    return lh;
end

local function renderTrigRuleBox(h, i, r, setNames, colX)
    local id = h .. '_' .. tostring(i);
    local act = nil;
    local lines = condLines(r.when);
    -- | leg (v54): one display line per OR condition, grouped under the & leg.
    local orLines = {};
    for _, e in ipairs(r.whenAny or {}) do
        for k, v in pairs(e) do
            local lk = string.lower(tostring(k));
            orLines[#orLines + 1] = { key = lk, val = v,
                text = '| ' .. trigPrettyKey(lk) .. ((v == true) and '' or (' = ' .. tostring(v))) };
        end
    end
    -- The box takes exactly the height its TALLER column needs: conditions on the
    -- left; on the right the target (an inline equip payload gets one line per
    -- slot) plus the controls row. Nothing is clipped to a cap anymore.
    local parts = nil;
    if r.equip ~= nil then
        parts = {};
        for slot, item in pairs(r.equip) do parts[#parts + 1] = tostring(slot) .. ' = ' .. tostring(item); end
        table.sort(parts);
    end
    local lh = lineH();
    local leftH  = (#lines + #orLines) * lh;
    local rightH;
    if parts ~= nil then
        rightH = #parts * lh + 30;                     -- inline equip: one line per slot + controls
    else
        -- one line per TARGET SET (multi-set rules stack them, with reorder
        -- buttons riding each line) + the '+ overlay set' picker + controls row
        local nsets = (type(r.set) == 'table') and #r.set or ((r.set ~= nil) and 1 or 0);
        rightH = nsets * 22 + 26 + 30;
    end
    local boxH = math.max(leftH, rightH, 56) + 18;
    imgui.BeginChild('##trgbox' .. id, { -1, boxH }, true, BOX_FLAGS);

    imgui.BeginGroup();                                -- left column: the methods
    local andPrefix = (#orLines > 0) and '& ' or '';   -- prefixes only when both legs exist
    for _, ln in ipairs(lines) do
        imgui.TextColored(COND_COLORS[ln.key] or COL_USABLE, esc(andPrefix .. ln.text));
        -- Stale group reference: a rule pointing at a missing / renamed group
        -- matches nothing -- mark it in place (parity with a set's [missing];
        -- hard rule 12, never a silent no-op).
        if ln.key == 'group' then
            local gv = r.when and r.when.group;
            local refs = (type(gv) == 'table') and gv or ((gv ~= nil) and { gv } or {});
            local miss = false;
            for _, gnm in ipairs(refs) do if not groupDefined(gnm) then miss = true; break; end end
            if miss then
                imgui.SameLine(0, 6);
                imgui.TextColored(COL_ERR, '[missing group]');
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('No group with this name exists for this job -- the rule matches\nnothing and equips nothing. Create it in the Groups section (or fix the name).');
                end
            end
        end
        -- Player-state gate (v53): a live holds-right-now marker, so you can
        -- dial a threshold and watch it flip without leaving the tab (the
        -- [missing group] in-place-marker precedent). Display only -- the
        -- engine re-evaluates for real at every dispatch.
        if PSTATE_KEYS[ln.key] ~= nil then
            local holds = pstateHolds(ln.key, r.when and r.when[ln.key]);
            if holds ~= nil then
                -- RESERVED column at the left edge of the controls column: the
                -- markers sit straight under each other and can never clip
                -- into the set/controls side (field case: Henrik's screenshot,
                -- '[on now]' overlapping 'Default x').
                imgui.SameLine(colX - markW());
                imgui.TextColored(holds and COL_USABLE or COL_DIM,
                    holds and '[on now]' or '[off now]');
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Checked against your CURRENT vitals/buffs/pet/zone (refreshes every second)\nwith the engine\'s own matcher. The engine re-evaluates at every dispatch.');
                end
            end
        end
    end
    for _, ln in ipairs(orLines) do
        imgui.TextColored(COND_COLORS[ln.key] or COL_USABLE, esc(ln.text));
        -- The | leg gets the same live marker as the & leg: each OR condition
        -- is a single engine-matcher call, so it lights independently.
        if PSTATE_KEYS[ln.key] ~= nil then
            local holds = pstateHolds(ln.key, ln.val);
            if holds ~= nil then
                imgui.SameLine(colX - markW());   -- the reserved marker column
                imgui.TextColored(holds and COL_USABLE or COL_DIM,
                    holds and '[on now]' or '[off now]');
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Checked against your CURRENT vitals/buffs/pet/zone (refreshes every second)\nwith the engine\'s own matcher. The engine re-evaluates at every dispatch.');
                end
            end
        end
    end
    imgui.EndGroup();

    imgui.SameLine(colX);
    imgui.BeginGroup();                                -- right column: target + controls
    if parts ~= nil then
        for pi, p in ipairs(parts) do                  -- one slot per line
            imgui.TextColored(COL_DIM, (pi == 1) and '->' or '  ');
            imgui.SameLine(0, 6);
            imgui.TextColored(COL_SCORE, esc(p));
        end
    else
        -- Target sets, IN ORDER: one rule may wear several, later overlaying
        -- earlier per slot (field case: cast Madrigal -> the WindSkill base set,
        -- then the Madrigal overlay). ^ / v reorder; x removes; the combo adds.
        local slist = (type(r.set) == 'table') and r.set or ((r.set ~= nil) and { r.set } or {});
        local function writeBack()
            if #slist == 0 then r.set = nil;
            elseif #slist == 1 then r.set = slist[1];
            else r.set = slist; end
            trig.dirty = true;
        end
        local moveUp, moveDown, dropAt = nil, nil, nil;
        for si, sn in ipairs(slist) do
            imgui.TextColored(COL_DIM, (si == 1) and '->' or ' +');
            imgui.SameLine(0, 6);
            imgui.TextColored(COL_SCORE, esc(sn));
            local known = false;
            for _, nm in ipairs(setNames) do if nm == sn then known = true; break; end end
            if not known then
                -- the rule targets a set this profile doesn't define: the dispatch
                -- would match and then equip NOTHING -- say so where the rule lives
                imgui.SameLine(0, 6);
                imgui.TextColored(COL_ERR, '[missing]');
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('No set with this name exists in the profile -- the trigger will\nmatch but this entry equips nothing. Create it in the Sets tab.');
                end
            end
            if #slist > 1 then
                imgui.SameLine(0, 10);
                if imgui.SmallButton('^##trgsu' .. id .. '_' .. si) and si > 1 then moveUp = si; end
                imgui.SameLine(0, 2);
                if imgui.SmallButton('v##trgsd' .. id .. '_' .. si) and si < #slist then moveDown = si; end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Order matters: LATER sets overlay earlier ones per slot.');
                end
            end
            imgui.SameLine(0, 4);
            if imgui.SmallButton('x##trgsx' .. id .. '_' .. si) then dropAt = si; end
        end
        if moveUp ~= nil then slist[moveUp], slist[moveUp - 1] = slist[moveUp - 1], slist[moveUp]; writeBack(); end
        if moveDown ~= nil then slist[moveDown], slist[moveDown + 1] = slist[moveDown + 1], slist[moveDown]; writeBack(); end
        if dropAt ~= nil then table.remove(slist, dropAt); writeBack(); end
        imgui.TextColored(COL_DIM, (#slist == 0) and '->' or '  ');
        imgui.SameLine(0, 6);
        imgui.PushItemWidth(170);
        local addPick = setPickCombo('##trgset' .. id, (#slist == 0) and '(pick set)' or '+ overlay set', slist);
        if addPick ~= nil then
            slist[#slist + 1] = addPick;
            writeBack();
        end
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then
            imgui.SetTooltip('One rule can wear SEVERAL sets: they apply in order, later overlaying\nearlier per slot (cast Madrigal -> WindSkill base, Madrigal on top).');
        end
    end

    -- controls row: prio (dim = automatic, gold = custom) + edit + remove.
    local defP = (hasDispatch and type(dsp.defaultPriority) == 'function') and dsp.defaultPriority(r.when) or 10;
    local isAuto = (r.priority == nil);
    local eff = r.priority or defP;
    imgui.TextColored(isAuto and COL_DIM or COL_SCORE, isAuto and 'prio (auto)' or 'prio');
    imgui.SameLine(0, 4);
    local b = trig._prioBuf[id];
    if b == nil or b.was ~= eff then b = { v = { eff }, was = eff }; trig._prioBuf[id] = b; end
    imgui.PushItemWidth(52);
    if imgui.InputInt('##trgprio' .. id, b.v, 0) then
        local nv = tonumber(b.v[1]);
        if nv ~= nil and nv ~= eff then
            r.priority = (nv ~= defP) and nv or nil;   -- typing the automatic value returns to auto
            b.was = nv;
            trig.dirty = true;
        end
    end
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip(string.format('Priority: higher overlays lower; every matching rule applies.\nAutomatic from specificity = %d. Type another number to override;\ntype %d again to go back to automatic.', defP, defP));
    end
    imgui.SameLine(0, 10);
    if imgui.SmallButton('edit##trgedit' .. id) then act = 'edit'; end
    if imgui.IsItemHovered() then imgui.SetTooltip('Edit this rule in the rule builder.'); end
    if hasBlueprints then
        imgui.SameLine(0, 4);
        if imgui.SmallButton('bp##trgbp' .. id) then act = 'blueprint'; end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Save as Blueprint: capture this rule into your per-character library,\nready to stamp onto any job (Blueprints section).');
        end
    end
    imgui.SameLine(0, 4);
    if imgui.SmallButton('x##trgdel' .. id) then act = 'remove'; end
    if imgui.IsItemHovered() then imgui.SetTooltip('Remove this rule.'); end
    imgui.EndGroup();

    imgui.EndChild();
    return act;
end

-- One mode box (rule-box language, content-fit height): identity + cycle values
-- on the left (current value highlighted), live button + bind + edit on the right.
local function renderModeBox(m, def, cur, colX)
    local isCycle = (def ~= nil and def.values ~= nil);
    local lh = lineH();
    local leftH  = (1 + (isCycle and #def.values or 0)) * lh;   -- name line + one per value
    local rightH = 26 + 24;                            -- action button + bind/edit row
    local boxH = math.max(leftH, rightH, 56) + 18;
    imgui.BeginChild('##trgmbox' .. m, { -1, boxH }, true, BOX_FLAGS);

    imgui.BeginGroup();                                -- left: identity + cycle values
    imgui.TextColored(COND_COLORS.mode, esc(m));
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_DIM, isCycle and 'cycle' or 'toggle');
    if isCycle then
        for i, v in ipairs(def.values) do
            local active = ((type(cur) == 'string') and (string.lower(cur) == string.lower(v)))
                           or (cur == nil and i == 1);          -- engine defaults to the first
            imgui.TextColored(active and COL_SCORE or COL_DIM,
                string.format('  %d. %s%s', i, esc(v), active and '   <' or ''));
        end
    end
    imgui.EndGroup();

    imgui.SameLine(colX);
    imgui.BeginGroup();                                -- right: live button + bind + edit
    local styled = (ImGuiCol_Button ~= nil);
    if isCycle then
        local shown = (type(cur) == 'string') and cur or (def.values[1] or '?');
        if styled then imgui.PushStyleColor(ImGuiCol_Button, { 0.20, 0.42, 0.58, 1.0 }); end
        if imgui.Button(string.format('%s: %s##trgmode_%s', m, shown, m), { 0, 24 }) then
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl mode ' .. m); end);
            trig._modeStateAt = -1;
        end
        if styled then imgui.PopStyleColor(1); end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Advance the cycle (also: /dl mode ' .. m .. ', or the keybind).\nRules match a value with  mode = ' .. m .. ':<value>');
        end
    else
        local on = (cur ~= nil);
        if styled then
            imgui.PushStyleColor(ImGuiCol_Button, on and { 0.15, 0.55, 0.20, 1.0 } or { 0.22, 0.22, 0.27, 1.0 });
        end
        if imgui.Button(string.format('%s: %s##trgmode_%s', m, on and 'ON' or 'off', m), { 0, 24 }) then
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl mode ' .. m .. ' toggle'); end);
            trig._modeStateAt = -1;
        end
        if styled then imgui.PopStyleColor(1); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Toggle on/off (also macro-able: /dl mode ' .. m .. ').'); end
    end
    imgui.TextColored(COL_DIM, (def ~= nil and def.bind ~= nil) and ('bind: ' .. def.bind) or 'bind: (none)');
    imgui.SameLine(0, 12);
    if imgui.SmallButton('edit##trgmedit_' .. m) then openModeEditor(m, def); end
    if imgui.IsItemHovered() then imgui.SetTooltip('Edit this mode (values / keybind / delete).'); end
    -- x: delete without opening the editor (Henrik 2026-07-20). Same flow as
    -- the editor's Delete mode -- unreferenced deletes (and commits) at once,
    -- references open the cleanup window -- behind the red second-click
    -- confirm, because the delete writes the file immediately.
    imgui.SameLine(0, 6);
    if trig._modeDelArm == m then
        local red = (ImGuiCol_Button ~= nil);
        if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
        if imgui.SmallButton('sure?##trgmdel_' .. m) then
            trig._modeDelArm = nil;
            local rr = modeCondRefs(trig.data, m, false);
            local sr = (deps ~= nil and type(deps.modeSetRefs) == 'function')
                and deps.modeSetRefs(m, false) or { refs = {} };
            if #rr.rules == 0 and #(sr.refs or {}) == 0 then
                deleteModeNow(m);
                trigSetStatus(string.format('Deleted mode "%s" (nothing referenced it) -- live now.', m), false);
            else
                modeUI.del = { name = m, rules = rr.rules, sets = sr.refs or {} };
            end
        end
        if red then imgui.PopStyleColor(1); end
    else
        if imgui.SmallButton('x##trgmdel_' .. m) then trig._modeDelArm = m; end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Delete this mode -- the second (red) click confirms.\nIf rules or set entries still reference it, the reference window\nopens first (with its one-click "delete all").');
        end
    end
    imgui.EndGroup();

    imgui.EndChild();
end

local function renderModesSection(defs, modes)
    local mstate = trigModeState();
    local toggles, cycles = {}, {};
    for _, m in ipairs(modes) do
        local def = defs[m];
        if def ~= nil and def.values ~= nil then cycles[#cycles + 1] = m; else toggles[#toggles + 1] = m; end
    end

    -- aligned controls column shared by both groups (longest left line wins)
    local colX = 200;
    for _, m in ipairs(modes) do
        local w = textW(m) + 84;
        if w > colX then colX = w; end
        local def = defs[m];
        if def ~= nil and def.values ~= nil then
            for _, v in ipairs(def.values) do
                local w2 = textW('  9. ' .. v .. '   <') + 40;
                if w2 > colX then colX = w2; end
            end
        end
    end
    local avail = imgui.GetContentRegionAvail();
    if type(avail) == 'number' and colX > avail * 0.55 then colX = avail * 0.55; end

    imgui.TextColored(COL_HEADER, 'Toggles');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_DIM, 'on/off switches; rules match them with  mode = Name');
    if #toggles == 0 then imgui.TextColored(COL_DIM, '(none)'); end
    for _, m in ipairs(toggles) do renderModeBox(m, defs[m], mstate[string.lower(m)], colX); end

    imgui.Spacing();
    imgui.TextColored(COL_HEADER, 'Cycles');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_DIM, 'one active value from a list; rules match with  mode = Name:Value');
    if #cycles == 0 then imgui.TextColored(COL_DIM, '(none)'); end
    for _, m in ipairs(cycles) do renderModeBox(m, defs[m], mstate[string.lower(m)], colX); end

    imgui.Spacing();
    if imgui.Button('+ Mode...##trgaddmode', { 0, 26 }) then
        modeUI.name[1] = ''; modeUI.kind = 'toggle'; modeUI.values = {};
        modeUI.valInput[1] = ''; modeUI.bind[1] = ''; modeUI.set = nil; modeUI.editing = nil;
        trig._openModePopup = true;
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Create a mode: a simple ON/OFF toggle, or a cycle list (weapon sets etc.).');
    end
end

-- Add-rule popup: build conditions (type + value, [+ condition] to AND more), pick the
-- target set, optional priority, Add.
local function renderTrigAddPopup()
    if not imgui.BeginPopup('##dlac_trigadd') then return; end
    local h = trig.addFor;
    if h == nil then imgui.EndPopup(); return; end
    local bpEditing = (trig._bpEdit ~= nil);   -- editing a Blueprint library entry, not a job rule
    local editing = (trig.editIdx ~= nil) or bpEditing;
    local title = bpEditing and ('Edit Blueprint (' .. h .. ' rule)')
                  or ((editing and 'Edit ' or 'New ') .. h .. ' rule');
    imgui.TextColored(COL_HEADER, title);
    imgui.Separator();

    local defs = COND_DEFS[h] or {};

    -- 'e' on a pending row: load the condition back into the pickers and lift
    -- the row out, so a small tweak never means retype-from-scratch (Henrik).
    -- Re-add with + & or + | -- moving a condition between legs is the same
    -- motion. v53 alias spellings edit into their canonical percent params.
    local PARAM_OF = nil;
    local PET_OF = nil;
    local function editCond(ci)
        local c = trig.addConds[ci];
        if c == nil or type(c.value) == 'table' then return; end   -- list values: delete + re-add
        local key = string.lower(tostring(c.key));
        if PARAM_OF == nil then
            PARAM_OF = {};
            for pi, p in ipairs(PLAYER_PARAMS) do PARAM_OF[string.lower(p.key)] = pi; end
            PARAM_OF.hpbelow = PARAM_OF.playerhppercentbelow;
            PARAM_OF.hpabove = PARAM_OF.playerhppercentabove;
            PARAM_OF.mpbelow = PARAM_OF.playermppercentbelow;
            PARAM_OF.mpabove = PARAM_OF.playermppercentabove;
            -- Pet cascade (v63): 'pet' appears twice (HasPet/NoPet -- one key,
            -- two values); membership here, the entry resolves by VALUE below.
            PET_OF = {};
            for pi, p in ipairs(PET_PARAMS) do PET_OF[string.lower(p.key)] = pi; end
        end
        local defIdx, kind = nil, nil;
        if PARAM_OF[key] ~= nil then
            for di, d in ipairs(defs) do
                if d.kind == 'player' then defIdx = di; break; end
            end
            if defIdx ~= nil then
                trig._addPlayer = PARAM_OF[key];
                kind = PLAYER_PARAMS[PARAM_OF[key]].kind;
            end
        elseif PET_OF[key] ~= nil then
            for di, d in ipairs(defs) do
                if d.kind == 'pet' then defIdx = di; break; end
            end
            if defIdx ~= nil then
                local pi = PET_OF[key];
                if key == 'pet' then pi = (c.value == false) and 2 or 1; end   -- NoPet vs HasPet
                trig._addPet = pi;
                kind = PET_PARAMS[pi].kind;
            end
        else
            for di, d in ipairs(defs) do
                if string.lower(d.key) == key then defIdx = di; kind = d.kind; break; end
            end
        end
        if defIdx == nil then return; end              -- exotic key: leave the row alone
        trig._addDef = defIdx;
        trig.addValText[1] = ''; trig._addValSel = nil; trig.addValNum[1] = 0;
        if kind == 'number' then trig.addValNum[1] = tonumber(c.value) or 0;
        elseif kind == 'text' then trig.addValText[1] = tostring(c.value);
        elseif kind == 'list' or kind == 'group' or kind == 'buff' then trig._addValSel = c.value;
        end
        table.remove(trig.addConds, ci);
    end
    local function condRowButtons(ci)
        if imgui.SmallButton('e##trgce' .. ci) then editCond(ci); end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Edit: loads this condition back into the pickers --\nadjust it, then re-add with + & or + |.');
        end
        imgui.SameLine(0, 4);
        if imgui.SmallButton('x##trgcx' .. ci) then table.remove(trig.addConds, ci); end
    end

    -- Pending conditions, GROUPED: the & leg first, then the | leg (Henrik:
    -- keep them visibly separate). Prefixes only appear once both legs exist.
    local nOr = 0;
    for _, c in ipairs(trig.addConds) do if c.any then nOr = nOr + 1; end end
    for ci, c in ipairs(trig.addConds) do
        if not c.any then
            local txt = ((nOr > 0) and '& ' or '')
                .. trigPrettyKey(string.lower(c.key)) .. ((c.value == true) and '' or (' = ' .. tostring(c.value)));
            imgui.TextColored(COL_USABLE, esc(txt));
            imgui.SameLine(0, 6);
            condRowButtons(ci);
        end
    end
    for ci, c in ipairs(trig.addConds) do
        if c.any then
            local txt = '| ' .. trigPrettyKey(string.lower(c.key)) .. ((c.value == true) and '' or (' = ' .. tostring(c.value)));
            imgui.TextColored({ 0.85, 0.65, 1.00, 1.0 }, esc(txt));
            imgui.SameLine(0, 6);
            condRowButtons(ci);
        end
    end

    if trig._addDef > #defs then trig._addDef = 1; end
    local cur = defs[trig._addDef];
    -- ONE cascading condition chooser (Henrik: like the floating equipment
    -- window's pin menu, not two boxes): a 200px button opens a popup menu;
    -- the Player row CASCADES into the parameter list -- BeginMenu when the
    -- binding has it (floatgear proved it), the drill-down fallback otherwise.
    -- Picking a Player parameter lands the def AND the parameter in one click,
    -- so the value widget follows the button directly. Menu labels are raw,
    -- never esc'd (they are not format strings -- the floatgear rule).
    local curLabel;
    if cur ~= nil and cur.kind == 'player' then
        local pp = PLAYER_PARAMS[trig._addPlayer] or PLAYER_PARAMS[1];
        curLabel = pp.label or pp.key;
    elseif cur ~= nil and cur.kind == 'pet' then
        local pp = PET_PARAMS[trig._addPet] or PET_PARAMS[1];
        curLabel = pp.label or pp.key;
    else
        curLabel = (cur and (cur.label or trigPrettyKey(string.lower(cur.key)))) or '?';
    end
    if imgui.Button(curLabel .. '###trgcondbtn', { 200, 0 }) then
        trig._condDrill = false;
        imgui.OpenPopup('##trgcondmenu');
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Pick the condition type. Player and Pet cascade into their\nparameter lists (HP / MP / buffs; pet out / status / name).');
    end
    if imgui.BeginPopup('##trgcondmenu') then
        local function pickDef(di)
            trig._addDef = di; trig.addValText[1] = ''; trig._addValSel = nil; trig.addValNum[1] = 0;
        end
        if trig._condDrill and not hasMenu then
            -- Drill-down fallback: the parameter list in place, with a way
            -- back. _condDrill names the cascade ('player' or 'pet', v63).
            local isPet = (trig._condDrill == 'pet');
            local params = isPet and PET_PARAMS or PLAYER_PARAMS;
            imgui.TextColored(COL_HEADER, isPet and 'Pet' or 'Player');
            if imgui.Selectable('< back##trgcback') then
                trig._condDrill = false;
            else
                imgui.Separator();
                for pi, p in ipairs(params) do
                    if imgui.Selectable((p.label or p.key) .. '##trgcpp' .. pi) then
                        for di, d in ipairs(defs) do
                            if d.kind == (isPet and 'pet' or 'player') then pickDef(di); break; end
                        end
                        if isPet then trig._addPet = pi; else trig._addPlayer = pi; end
                        trig._condDrill = false;
                        imgui.CloseCurrentPopup();
                    end
                    if p.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(p.hint); end
                end
            end
        else
            for di, d in ipairs(defs) do
                if d.kind == 'player' or d.kind == 'pet' then
                    -- Both cascades share one shape; only the parameter list
                    -- and the picked-index slot differ (v63).
                    local isPet = (d.kind == 'pet');
                    local params = isPet and PET_PARAMS or PLAYER_PARAMS;
                    local title = isPet and 'Pet' or 'Player';
                    if hasMenu then
                        if imgui.BeginMenu(title .. '##trgc' .. d.kind) then
                            for pi, p in ipairs(params) do
                                if imgui.MenuItem((p.label or p.key) .. '##trgc' .. d.kind .. pi) then
                                    pickDef(di);
                                    if isPet then trig._addPet = pi; else trig._addPlayer = pi; end
                                    pcall(function() imgui.CloseCurrentPopup(); end);
                                end
                                if p.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(p.hint); end
                            end
                            imgui.EndMenu();
                        end
                    else
                        if imgui.Selectable(title .. '  >##trgc' .. d.kind) then trig._condDrill = d.kind; end
                    end
                else
                    local disp = d.label or trigPrettyKey(string.lower(d.key));
                    if imgui.Selectable(disp .. '##trgct' .. di) then
                        pickDef(di);
                        imgui.CloseCurrentPopup();
                    end
                    if d.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(d.hint); end
                end
            end
        end
        imgui.EndPopup();
    end
    cur = defs[trig._addDef];
    if cur ~= nil then
        imgui.SameLine(0, 6);
        if cur.kind == 'list' then
            imgui.PushItemWidth(170);
            if imgui.BeginCombo('##trgcondval', trig._addValSel or '(pick)') then
                for vi, it in ipairs(cur.items) do
                    if imgui.Selectable(it .. '##trgcv' .. vi, trig._addValSel == it) then trig._addValSel = it; end
                end
                imgui.EndCombo();
            end
            imgui.PopItemWidth();
        elseif cur.kind == 'group' then
            -- Value = a dropdown of the current job's defined groups (ADR 0009).
            -- Picking one writes  when = { group = '<name>' }. Build groups in the
            -- Groups section; with none defined the combo says so instead of a dead pick.
            local gnames = M.groupNames();
            imgui.PushItemWidth(170);
            if imgui.BeginCombo('##trgcondgrp', trig._addValSel or '(pick group)') then
                if #gnames == 0 then imgui.TextColored(COL_DIM, '(no groups yet -- create one in the Groups section)'); end
                for vi, it in ipairs(gnames) do
                    if imgui.Selectable(esc(it) .. '##trgcg' .. vi, trig._addValSel == it) then trig._addValSel = it; end
                end
                imgui.EndCombo();
            end
            imgui.PopItemWidth();
            if #gnames == 0 and imgui.IsItemHovered() then
                imgui.SetTooltip('No groups defined for this job yet. Open the Groups section to create one.');
            end
        elseif cur.kind == 'player' then
            -- Value widget ONLY: the parameter itself was picked in the
            -- cascading condition menu (one box, not two -- Henrik's revision).
            local pp = PLAYER_PARAMS[trig._addPlayer] or PLAYER_PARAMS[1];
            if pp.kind == 'buff' then
                local pick = buffPickCombo('##trgcondbuff', trig._addValSel or '(pick effect)');
                if pick ~= nil then trig._addValSel = pick; end
            else
                imgui.PushItemWidth(90);
                imgui.InputInt('##trgcondnum', trig.addValNum, 0);
                imgui.PopItemWidth();
                if pp.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(pp.hint); end
            end
        elseif cur.kind == 'pet' then
            -- The Pet cascade's value widget (v63): 'fixed' parameters
            -- (HasPet/NoPet) carry their value -- nothing to type.
            local pp = PET_PARAMS[trig._addPet] or PET_PARAMS[1];
            if pp.kind == 'list' then
                imgui.PushItemWidth(170);
                if imgui.BeginCombo('##trgcondval', trig._addValSel or '(pick)') then
                    for vi, it in ipairs(pp.items) do
                        if imgui.Selectable(it .. '##trgcpv' .. vi, trig._addValSel == it) then trig._addValSel = it; end
                    end
                    imgui.EndCombo();
                end
                imgui.PopItemWidth();
                if pp.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(pp.hint); end
            elseif pp.kind == 'text' then
                imgui.PushItemWidth(170);
                imgui.InputText('##trgcondtext', trig.addValText, 48);
                imgui.PopItemWidth();
                if pp.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(pp.hint); end
            else
                imgui.TextColored(COL_DIM, '(flag)');
                if pp.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(pp.hint); end
            end
        elseif cur.kind == 'number' then
            imgui.PushItemWidth(90);
            imgui.InputInt('##trgcondnum', trig.addValNum, 0);
            imgui.PopItemWidth();
            if cur.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(cur.hint); end
        elseif cur.kind == 'buff' then
            local pick = buffPickCombo('##trgcondbuff', trig._addValSel or '(pick effect)');
            if pick ~= nil then trig._addValSel = pick; end
            if cur.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(cur.hint); end
        elseif cur.kind == 'text' then
            imgui.PushItemWidth(170);
            imgui.InputText('##trgcondtext', trig.addValText, 48);
            imgui.PopItemWidth();
            if cur.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(cur.hint); end
        else
            imgui.TextColored(COL_DIM, '(flag)');
        end
        -- Capture the current widget's key + value; the Player cascade resolves
        -- to the SELECTED parameter's key and widget kind.
        local function addCond(isOr)
            local ckey, ck = cur.key, cur.kind;
            local fixedVal = nil;
            if ck == 'player' then
                local pp = PLAYER_PARAMS[trig._addPlayer] or PLAYER_PARAMS[1];
                ckey, ck = pp.key, pp.kind;
            elseif ck == 'pet' then
                local pp = PET_PARAMS[trig._addPet] or PET_PARAMS[1];
                ckey, ck = pp.key, pp.kind;
                fixedVal = pp.value;   -- only the 'fixed' parameters carry one
            end
            local val;
            if ck == 'fixed' then val = fixedVal;   -- pet = true/false: false is a real value
            elseif ck == 'list' or ck == 'group' or ck == 'buff' then val = trig._addValSel;
            elseif ck == 'text' then val = (trig.addValText[1] ~= '') and trig.addValText[1] or nil;
            elseif ck == 'number' then
                val = ((tonumber(trig.addValNum[1]) or 0) > 0) and trig.addValNum[1] or nil;
            else val = true; end
            if val == nil then return; end
            if not isOr then
                -- & leg: one value per key (the map shape) -- re-adding replaces.
                for _, c in ipairs(trig.addConds) do
                    if c.key == ckey and not c.any then c.value = val; return; end
                end
            end
            -- | leg: duplicates are THE POINT (buff = Sleep | buff = Lullaby).
            trig.addConds[#trig.addConds + 1] = { key = ckey, value = val, any = isOr or nil };
            trig.addValText[1] = ''; trig._addValSel = nil;
        end
        imgui.SameLine(0, 6);
        if imgui.Button('+ & condition##trgac', { 0, 0 }) then addCond(false); end
        if imgui.IsItemHovered() then imgui.SetTooltip('AND condition, all AND conditions must be true to be a match.'); end
        imgui.SameLine(0, 4);
        if imgui.Button('+ | condition##trgoc', { 0, 0 }) then addCond(true); end
        if imgui.IsItemHovered() then imgui.SetTooltip('OR condition, if ANY OR condition is true, it will be a match.'); end
    end

    imgui.Separator();
    imgui.TextColored(COL_DIM, 'equip set:'); imgui.SameLine(0, 4);
    imgui.PushItemWidth(150);
    local addSetPick = setPickCombo('##trgaddset', trig.addSet or '(pick set)');
    if addSetPick ~= nil then trig.addSet = addSetPick; end
    imgui.PopItemWidth();
    if editing and trig.addSet == nil and trig._editEquip ~= nil then
        imgui.SameLine(0, 6);
        imgui.TextColored(COL_DIM, '(keeps its inline equip)');
    end
    imgui.SameLine(0, 8); imgui.TextColored(COL_DIM, 'prio (0 = auto)'); imgui.SameLine(0, 3);
    imgui.PushItemWidth(52); imgui.InputInt('##trgaddprio', trig.addPrio, 0); imgui.PopItemWidth();
    imgui.SameLine(0, 8);
    local can = (#trig.addConds > 0) and (trig.addSet ~= nil or trig._editEquip ~= nil);
    if imgui.Button((editing and 'Save rule' or 'Add rule') .. '###trgaddgo', { 0, 0 }) and can then
        local when, whenAny = {}, nil;
        for _, c in ipairs(trig.addConds) do
            if c.any then
                whenAny = whenAny or {};
                whenAny[#whenAny + 1] = { [string.lower(c.key)] = c.value };
            else
                when[string.lower(c.key)] = c.value;
            end
        end
        local rule = { when = when };
        if whenAny ~= nil then rule.whenAny = whenAny; end
        if trig.addSet ~= nil then rule.set = trig.addSet;
        else rule.equip = trig._editEquip; end         -- editing an inline-equip rule: keep its payload
        if (tonumber(trig.addPrio[1]) or 0) > 0 then rule.priority = trig.addPrio[1]; end
        if bpEditing then
            -- Editing a Blueprint: the SAME rule editor, bound to the library entry.
            -- Writes back to the library file (never retro-edits already-stamped Triggers).
            local e = bpUI.lib and bpUI.lib[trig._bpEdit] or nil;
            if e ~= nil then
                e.rule = rule;                         -- handler + name unchanged; the rule is replaced
                if bpSave() then bpSetStatus(string.format('Blueprint "%s" updated.', e.name), false); end
            end
        else
            trig.data[h] = trig.data[h] or {};
            if trig.editIdx ~= nil and trig.data[h][trig.editIdx] ~= nil then
                trig.data[h][trig.editIdx] = rule;     -- replace in place (keeps file order / tie-breaks)
            else
                table.insert(trig.data[h], rule);
            end
            trig.dirty = true;
        end
        trig.addConds = {}; trig.addSet = nil; trig.addPrio[1] = 0;
        trig.editIdx, trig._editEquip, trig._bpEdit = nil, nil, nil;
        trig._prioBuf = {};                            -- rule objects changed; rebuild priority buffers
        imgui.CloseCurrentPopup();
    end
    if not can then imgui.TextColored(COL_DIM, 'Add at least one condition and pick a set.'); end
    imgui.EndPopup();
end

-- ---------------------------------------------------------------------------
-- Groups section (issue #25, ADR 0009). A section inside the Triggers tab, under
-- Modes, that edits the shared trigger model's Groups section: create / rename /
-- delete groups and add / remove typed members. Member entry is free-name typing
-- (the searchable browse-list picker is a later slice -- issue #12); a group NAME
-- is then referenced by a `group` trigger condition (Triggers tab). Commit writes
-- the SAME file as the Triggers tab (dispatch.serializeTriggers carries Groups),
-- so the two tabs share trig.data / trig.dirty and never stomp each other.
-- ---------------------------------------------------------------------------
local function groupSetStatus(msg, isErr) groupUI.status = msg or ''; groupUI.statusErr = (isErr == true); end

local function renderGroupAddPopup()
    if not imgui.BeginPopup('##dlac_groupadd') then return; end
    imgui.TextColored(COL_HEADER, 'New group');
    imgui.Separator();
    imgui.TextColored(COL_DIM, 'Name'); imgui.SameLine(0, 8);
    imgui.PushItemWidth(200); imgui.InputText('##grpnm', groupUI.newName, 48); imgui.PopItemWidth();
    if imgui.IsItemHovered() then imgui.SetTooltip('e.g. "STR Spells", "Cures", "Enfeebles"'); end
    imgui.Separator();
    if imgui.Button('Create group###grpaddgo', { 0, 0 }) then
        trig.data.Groups = trig.data.Groups or {};
        local ok, err = gm.add(trig.data.Groups, groupUI.newName[1]);
        if ok then
            trig.dirty = true;
            groupSetStatus('Group created -- add members by typing, then Commit.', false);
            groupUI.newName[1] = '';
            imgui.CloseCurrentPopup();
        else
            groupSetStatus(err or 'Invalid name.', true);
        end
    end
    imgui.EndPopup();
end

local function renderGroupRenamePopup()
    if not imgui.BeginPopup('##dlac_grouprename') then return; end
    imgui.TextColored(COL_HEADER, 'Rename group: ' .. esc(tostring(groupUI.renaming)));
    imgui.Separator();
    imgui.PushItemWidth(200); imgui.InputText('##grprn', groupUI.renameBuf, 48); imgui.PopItemWidth();
    imgui.Separator();
    if imgui.Button('Rename###grprngo', { 0, 0 }) then
        local ok, err = gm.rename(trig.data.Groups or {}, groupUI.renaming, groupUI.renameBuf[1]);
        if ok then
            trig.dirty = true;
            groupSetStatus('Renamed -- Commit to save. A rule still on the OLD name now shows [missing group] (Triggers tab); repoint it.', false);
            groupUI.renaming = nil;
            imgui.CloseCurrentPopup();
        else
            groupSetStatus(err or 'Invalid name.', true);
        end
    end
    imgui.SameLine(0, 8);
    if imgui.Button('Cancel###grprncancel', { 0, 0 }) then groupUI.renaming = nil; imgui.CloseCurrentPopup(); end
    imgui.EndPopup();
end

-- One group box (rule-box language): name + members on the left; typed-member
-- input + rename / delete on the right.
local function renderGroupBox(nm, groups, colX)
    local members = groups[nm];
    local lh = lineH();
    local leftH  = (1 + math.max(#members, 1)) * lh;   -- name line + one per member (>=1 for the empty note)
    local rightH = hasBrowse and (26 + 24 + 24) or (26 + 24);   -- +1 row for the Browse... button
    local boxH = math.max(leftH, rightH, 56) + 18;
    imgui.BeginChild('##grpbox_' .. nm, { -1, boxH }, true, BOX_FLAGS);

    imgui.BeginGroup();                                -- left: identity + members
    imgui.TextColored(COND_COLORS.group, esc(nm));
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_DIM, string.format('%d member%s', #members, (#members == 1) and '' or 's'));
    local removeAt = nil;
    for i, mbr in ipairs(members) do
        imgui.TextColored(COL_USABLE, '   ' .. esc(mbr));
        imgui.SameLine(0, 8);
        if imgui.SmallButton('x##grpmx_' .. nm .. '_' .. i) then removeAt = i; end
    end
    imgui.EndGroup();

    imgui.SameLine(colX);
    imgui.BeginGroup();                                -- right: add member + rename/delete
    local buf = groupUI.memberInput[nm];
    if buf == nil then buf = { '' }; groupUI.memberInput[nm] = buf; end
    imgui.PushItemWidth(160);
    imgui.InputText('##grpmin_' .. nm, buf, 48);
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then imgui.SetTooltip('Type an action name (spell / ability / weaponskill / item), then + member.'); end
    imgui.SameLine(0, 4);
    if imgui.Button('+ member##grpmadd_' .. nm, { 0, 0 }) then
        local ok, err = gm.addMember(groups, nm, buf[1]);
        if ok then buf[1] = ''; trig.dirty = true; groupSetStatus('', false);
        else groupSetStatus(err or 'Could not add member.', true); end
    end
    -- Searchable browse-list picker (G3, issue #26): opens the shared popup targeting
    -- THIS group. Free typing above stays -- the picker only adds a faster path for the
    -- job's known spells/abilities. Hidden when the browse core / data is unavailable.
    if hasBrowse then
        if imgui.Button('Browse...##grpbrowseopen_' .. nm, { 0, 0 }) then
            groupUI.browseFor = nm;
            groupUI.browseSearch[1] = '';
            groupUI.browseMarks = {};
            groupUI._openBrowse = true;
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Search this job's spells & abilities and mark several to add at once.\n(The list is not level-gated -- build ahead. Free typing above still works\nfor anything the data is missing.)");
        end
    end
    if imgui.SmallButton('rename##grprn_' .. nm) then
        groupUI.renaming = nm; groupUI.renameBuf[1] = nm; groupUI._openRename = true;
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Rename this group (members are kept).'); end
    imgui.SameLine(0, 6);
    if imgui.SmallButton('delete##grpdel_' .. nm) then
        gm.remove(groups, nm);
        groupUI.memberInput[nm] = nil;
        trig.dirty = true;
        groupSetStatus(string.format('Deleted group "%s" -- Commit to save. Rules on it now show [missing group] (Triggers tab).', nm), false);
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Delete this group. Any rule still referencing it is surfaced on the\nTriggers tab as [missing group] -- never a silent no-op.'); end
    imgui.EndGroup();

    if removeAt ~= nil then table.remove(members, removeAt); trig.dirty = true; end
    imgui.EndChild();
end

-- Write a parsed import plan into the live Groups map and report a summary. Marks the model dirty
-- (Commit still writes the file); leaves the plan on screen as the "Imported" receipt.
local function applyImportPlan(plan, groups)
    local sum = gimp.apply(groups, plan.groups);
    trig.dirty = true;
    plan.pending = false;
    local parts = {};
    if sum.created > 0 then parts[#parts + 1] = sum.created .. ' created'; end
    if sum.updated > 0 then parts[#parts + 1] = sum.updated .. ' overwritten'; end
    parts[#parts + 1] = sum.members .. ' member' .. ((sum.members == 1) and '' or 's');
    if #plan.errors > 0 then parts[#parts + 1] = #plan.errors .. ' skipped'; end
    groupSetStatus('Imported: ' .. table.concat(parts, ', ') .. ' -- Commit to save.', false);
end

-- The Import window (G4, issue #30; 07-20: opened from the top-row Import button instead of a
-- collapsible bottom section): a paste box that bulk-creates one group per top-level key of a
-- pasted `Name = T{...}` table. Parsing is the sandboxed pure transform (groupimport.parse);
-- collisions with an existing group require an explicit confirm before overwriting (parity with
-- "Copy from static"); a pre-import summary shows created / overwritten / skipped. `groups` is
-- the live trig.data.Groups map.
local function renderGroupImportPopup(groups)
    if not hasGroupImport then return; end
    imgui.SetNextWindowSizeConstraints({ 500, 0 }, { 660, 520 });
    if not imgui.BeginPopup('##dlac_grpimport') then return; end
    imgui.TextColored(COL_HEADER, 'Import Lua Table(s)');
    imgui.TextColored(COL_DIM, 'Already keep your spells grouped in a Lua table? Paste it -- one group per name.');
    imgui.TextColored(COL_DIM, "e.g.   STR_DEX = T{'Foot Kick', 'Wild Oats'},   VIT = {'Cannonball', 'Tail Slap'},");
    imgui.TextColored(COL_DIM, 'The  T  is optional; plain  {...}  works too. A nested / non-list value skips just that name.');

    if hasMultiline then
        imgui.InputTextMultiline('##grpimptext', groupUI.importText, 8192, { 490, 120 });
    else
        imgui.TextColored(COL_SCORE, '(this build has no multiline box -- keep it on ONE line; names are comma-separated)');
        imgui.PushItemWidth(490);
        imgui.InputText('##grpimptext', groupUI.importText, 8192);
        imgui.PopItemWidth();
    end

    if imgui.Button('Import##grpimpgo', { 0, 24 }) then
        local parsed, errs = gimp.parse(groupUI.importText[1]);
        if parsed == nil then
            groupUI.plan = nil;
            groupSetStatus((errs and errs[1]) or 'Could not parse the pasted text.', true);
        else
            local created, overwritten = gimp.classify(parsed, groups);
            groupUI.plan = { groups = parsed, errors = errs or {},
                             created = created, overwritten = overwritten, pending = true };
            -- No collisions -> import immediately (confirmation is only for overwrites).
            if #overwritten == 0 then applyImportPlan(groupUI.plan, groups); end
        end
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Parse the pasted table and preview what would be created / overwritten.'); end
    imgui.SameLine(0, 6);
    if imgui.Button('Clear##grpimpclr', { 0, 24 }) then
        groupUI.importText[1] = ''; groupUI.plan = nil; groupSetStatus('', false);
    end

    local plan = groupUI.plan;
    if plan ~= nil then
        imgui.Spacing();
        imgui.TextColored(COL_HEADER, plan.pending and 'Preview' or 'Imported');
        if #plan.created > 0 then
            imgui.TextColored(COL_SCORE, string.format('  create %d: %s', #plan.created, esc(table.concat(plan.created, ', '))));
        end
        if #plan.overwritten > 0 then
            imgui.TextColored(COL_ERR, string.format('  overwrite %d existing: %s', #plan.overwritten, esc(table.concat(plan.overwritten, ', '))));
        end
        if #plan.errors > 0 then
            imgui.TextColored(COL_DIM, string.format('  skip %d:', #plan.errors));
            for _, e in ipairs(plan.errors) do imgui.TextColored(COL_DIM, '     ' .. esc(e)); end
        end
        if #plan.created == 0 and #plan.overwritten == 0 then
            imgui.TextColored(COL_DIM, '  (nothing to import)');
        end
        if plan.pending then
            if ImGuiCol_Button ~= nil then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
            if imgui.Button(string.format('Overwrite %d & import###grpimpconfirm', #plan.overwritten), { 0, 24 }) then
                applyImportPlan(plan, groups);
            end
            if ImGuiCol_Button ~= nil then imgui.PopStyleColor(1); end
            if imgui.IsItemHovered() then imgui.SetTooltip('Replaces the named existing group(s) with the pasted members. Commit still saves to disk.'); end
            imgui.SameLine(0, 6);
            if imgui.Button('Cancel##grpimpcancel', { 0, 24 }) then
                groupUI.plan = nil; groupSetStatus('Import cancelled -- nothing changed.', false);
            end
        end
    end
    imgui.EndPopup();
end

-- Names that read like config/variant tables rather than spell groups -- pre-UNticked so the
-- scan's false positives (IdleVariantTable, Settings) don't import unless the player opts in.
local function looksLikeConfig(name)
    local n = tostring(name);
    return n:find('[Vv]ariant') ~= nil or n:find('[Ss]etting') ~= nil
        or n:find('[Cc]onfig') ~= nil or n:find('[Oo]ption') ~= nil or n:find('Table$') ~= nil;
end

-- The Auto-Import scan (Item 1; 07-20: fired straight from the top-row Auto-Import button, and
-- from the picker window's Rescan): read the character's live LuaAshitacast <JOB>.lua (and its
-- pre-profiles backup, since migration shims the live file) and list every group-shaped table as
-- a tick-able candidate -- pre-ticked except obvious config tables.
local function groupAutoScan()
    local text, srcs, abbr = '', 0, nil;
    if deps and deps.jobFile then
        local live; live, abbr = deps.jobFile();
        local t1 = live and readFileText(live) or nil;
        if t1 ~= nil then text = text .. '\n' .. t1; srcs = srcs + 1; end
    end
    if abbr ~= nil and deps and deps.charBase then
        local t2 = readFileText(deps.charBase() .. 'backups\\pre-profiles\\' .. abbr .. '.lua');
        if t2 ~= nil then text = text .. '\n' .. t2; srcs = srcs + 1; end
    end
    if srcs == 0 then
        groupUI.autoCands, groupUI.autoNotes, groupUI.autoPlan = nil, nil, nil;
        groupUI.autoScanned = true;
        groupSetStatus('No Lua file found to scan (looked for your job file + its pre-profiles backup).', true);
    else
        local cands, notes = gscan.scan(text);
        groupUI.autoCands, groupUI.autoNotes, groupUI.autoPlan = cands, notes, nil;
        groupUI.autoMarks, groupUI.autoScanned = {}, true;
        for _, c in ipairs(cands) do groupUI.autoMarks[c.name] = not looksLikeConfig(c.name); end
    end
end

-- The Auto-Import picker window (Item 1; 07-20: a popup, no longer a collapsible section with
-- its own Scan button -- the top-row button already scanned). The scan is the pure
-- groupscan.scan; import reuses the same classify / overwrite-confirm / apply as the paste flow.
-- `groups` is the live trig.data.Groups map.
local function renderGroupAutoImportPopup(groups)
    if not hasGroupScan then return; end
    imgui.SetNextWindowSizeConstraints({ 460, 0 }, { 640, 560 });
    if not imgui.BeginPopup('##dlac_grpautoimp') then return; end
    imgui.TextColored(COL_HEADER, 'Auto-Import from my Lua file');
    imgui.SameLine(0, 10);
    if imgui.SmallButton('Rescan##grpautoscan') then groupAutoScan(); end
    if imgui.IsItemHovered() then imgui.SetTooltip('Read your live <JOB>.lua (and its pre-profiles backup) again.'); end

    local cands = groupUI.autoCands;
    if cands == nil then
        imgui.TextColored(COL_DIM, 'No Lua file found to scan (looked for your job file + its pre-profiles backup).');
    end
    if cands ~= nil and #cands > 0 then
        imgui.Spacing();
        imgui.TextColored(COL_HEADER, string.format('Found %d table%s -- tick the ones to import:', #cands, (#cands == 1) and '' or 's'));
        local nMarked = 0;
        for i, c in ipairs(cands) do
            local ref = { groupUI.autoMarks[c.name] == true };
            if imgui.Checkbox('##grpauto_' .. i, ref) then groupUI.autoMarks[c.name] = ref[1]; end
            local marked = groupUI.autoMarks[c.name] == true;
            if marked then nMarked = nMarked + 1; end
            imgui.SameLine(0, 6);
            imgui.TextColored(marked and COL_USABLE or COL_DIM,
                string.format('%s  (%d member%s)', esc(c.name), #c.members, (#c.members == 1) and '' or 's'));
        end
        if groupUI.autoNotes ~= nil and #groupUI.autoNotes > 0 then
            imgui.Spacing();
            imgui.TextColored(COL_DIM, string.format('skipped %d:', #groupUI.autoNotes));
            for _, nt in ipairs(groupUI.autoNotes) do imgui.TextColored(COL_DIM, '   ' .. esc(nt)); end
        end
        imgui.Spacing();
        if imgui.Button(string.format('Import %d selected##grpautogo', nMarked), { 0, 24 }) then
            local picked = {};
            for _, c in ipairs(cands) do
                if groupUI.autoMarks[c.name] == true then picked[c.name] = c.members; end
            end
            if next(picked) == nil then
                groupSetStatus('Nothing ticked -- select at least one table to import.', true);
            else
                local created, overwritten = gimp.classify(picked, groups);
                groupUI.autoPlan = { groups = picked, errors = {}, created = created, overwritten = overwritten, pending = true };
                if #overwritten == 0 then applyImportPlan(groupUI.autoPlan, groups); end
            end
        end
    elseif groupUI.autoScanned and cands ~= nil then
        imgui.TextColored(COL_DIM, '  (no group-shaped tables found in your Lua file)');
    end

    -- The overwrite-confirm preview, mirroring renderGroupImportPopup.
    local plan = groupUI.autoPlan;
    if plan ~= nil then
        imgui.Spacing();
        imgui.TextColored(COL_HEADER, plan.pending and 'Preview' or 'Imported');
        if #plan.created > 0 then
            imgui.TextColored(COL_SCORE, string.format('  create %d: %s', #plan.created, esc(table.concat(plan.created, ', '))));
        end
        if #plan.overwritten > 0 then
            imgui.TextColored(COL_ERR, string.format('  overwrite %d existing: %s', #plan.overwritten, esc(table.concat(plan.overwritten, ', '))));
        end
        if plan.pending then
            if ImGuiCol_Button ~= nil then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
            if imgui.Button(string.format('Overwrite %d & import###grpautoconfirm', #plan.overwritten), { 0, 24 }) then
                applyImportPlan(plan, groups);
            end
            if ImGuiCol_Button ~= nil then imgui.PopStyleColor(1); end
            imgui.SameLine(0, 6);
            if imgui.Button('Cancel##grpautocancel', { 0, 24 }) then
                groupUI.autoPlan = nil; groupSetStatus('Auto-import cancelled -- nothing changed.', false);
            end
        end
    end
    imgui.EndPopup();
end

-- The shared spell/ability browse-list popup (G3, issue #26). ONE popup for the whole
-- Groups section, retargeted per group via groupUI.browseFor. Search narrows a combined,
-- job-filtered, UNGATED list; each row is a checkbox mark + a spell/ability marker + name.
-- A CHECKBOX (not a Selectable) keeps the popup open across marks -- the field-proven
-- multi-pick idiom (gearui's weapon-type filter), so this never depends on a
-- DontClosePopups flag. "Add N marked" commits every mark through gm.addMember (which
-- dedups case-insensitively), then closes so the section status + member list show the
-- result. Free typing in the box above stays the fallback for anything the data misses.
local function renderGroupBrowsePopup(job)
    if not imgui.BeginPopup('##dlac_groupbrowse') then return; end
    local nm = groupUI.browseFor;
    local groups = trig.data and trig.data.Groups;
    if nm == nil or type(groups) ~= 'table' or groups[nm] == nil then
        imgui.TextColored(COL_DIM, 'This group no longer exists.');
        imgui.EndPopup();
        return;
    end
    imgui.TextColored(COL_HEADER, 'Add spells / abilities to:');
    imgui.SameLine(0, 6);
    imgui.TextColored(COND_COLORS.group, esc(nm));
    imgui.SameLine(0, 12);
    imgui.TextColored(COL_DIM, string.format('(%s -- not level-gated)', tostring(job or '?')));
    imgui.Separator();

    imgui.PushItemWidth(260);
    imgui.InputText('##grpbrowsesearch', groupUI.browseSearch, 64);
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Filter by name. Commas = AND: "stone, ii" shows names carrying both.');
    end

    local list  = groupUI._list or {};
    local terms = ap.parseQuery(groupUI.browseSearch[1]);
    local inGroup = {};
    for _, m in ipairs(groups[nm]) do inGroup[string.lower(tostring(m))] = true; end

    imgui.BeginChild('##grpbrowselist', { 380, 300 }, true);
    local shown = 0;
    for _, e in ipairs(list) do
        if ap.matches(e, terms) then
            shown = shown + 1;
            local key   = string.lower(e.name);
            local label = string.format('[%s] %s', (e.kind == 'ability') and 'A' or 'S', e.name);
            if e.level and e.level > 0 then label = label .. '   Lv' .. tostring(e.level); end
            if inGroup[key] then
                imgui.TextColored(COL_DIM, '  ' .. esc(label) .. '   (in group)');
            else
                -- Mark keyed by NAME (an untyped group stores the bare name once, so the
                -- rare spell+ability twin is one mark); widget ID by ROW so the twin's two
                -- checkboxes never collide on the ImGui id stack.
                local ref = { groupUI.browseMarks[key] ~= nil };
                if imgui.Checkbox('##grpbmk_' .. shown, ref) then
                    groupUI.browseMarks[key] = ref[1] and e.name or nil;
                end
                imgui.SameLine(0, 6);
                imgui.TextColored((e.kind == 'ability') and COL_SCORE or COL_USABLE, esc(label));
            end
        end
    end
    if shown == 0 then
        imgui.TextColored(COL_DIM, (#list == 0)
            and 'No learnable spells or abilities for this job in the picker data.'
            or 'Nothing matches the search.');
    end
    imgui.EndChild();

    local n = 0; for _ in pairs(groupUI.browseMarks) do n = n + 1; end
    local canAdd = n > 0;
    if canAdd and ImGuiCol_Button ~= nil then imgui.PushStyleColor(ImGuiCol_Button, { 0.20, 0.45, 0.20, 1.0 }); end
    if imgui.Button(string.format('Add %d marked##grpbadd', n), { 0, 24 }) and canAdd then
        local added = 0;
        for _, name in pairs(groupUI.browseMarks) do
            if gm.addMember(groups, nm, name) then added = added + 1; end
        end
        groupUI.browseMarks = {};
        if added > 0 then trig.dirty = true; end
        groupSetStatus(string.format('Added %d spell/ability name(s) to "%s" -- Commit to save.', added, nm), false);
        imgui.CloseCurrentPopup();
    end
    if canAdd and ImGuiCol_Button ~= nil then imgui.PopStyleColor(1); end
    imgui.SameLine(0, 8);
    if imgui.Button('Close##grpbclose', { 0, 24 }) then imgui.CloseCurrentPopup(); end
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_DIM, string.format('%d marked', n));
    imgui.EndPopup();
end

function M.renderGroups(job, level)
    if not hasImgui then return; end
    if deps == nil then
        imgui.TextColored(COL_ERR, 'Groups section not initialized (gearui deps missing).');
        return;
    end
    if not hasDispatch then
        imgui.TextColored(COL_ERR, 'dispatch module unavailable -- the Groups section is disabled.');
        return;
    end
    if not hasGroups then
        imgui.TextColored(COL_ERR, 'groupsmodel module unavailable -- the Groups section is disabled.');
        return;
    end
    local path, abbr = trigFilePath();
    if path == nil then
        imgui.TextColored(COL_DIM, 'Log in (with a known job) to edit groups.');
        return;
    end
    trigLoad(false);
    if trig.data == nil then
        imgui.TextColored(COL_DIM, 'No trigger file for ' .. tostring(abbr) .. ' yet.');
        imgui.TextColored(COL_DIM, 'Create starter triggers on the Triggers tab first -- groups live in the same file.');
        return;
    end
    trig.data.Groups = trig.data.Groups or {};
    local groups = trig.data.Groups;

    imgui.TextColored(COL_HEADER, 'Groups');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_DIM, 'named action lists; a rule matches them with  group = Name  (Triggers tab)');

    -- Commit / Revert row (the SAME file the Triggers tab writes).
    local dirty = trig.dirty and ImGuiCol_Button ~= nil;
    if dirty then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
    if imgui.Button('Commit##grpcommit', { 0, 22 }) then trigCommit(); end
    if dirty then imgui.PopStyleColor(1); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Writes triggers\\' .. tostring(abbr) .. '.lua and hot-reloads the engine -- live immediately.');
    end
    imgui.SameLine(0, 6);
    if imgui.Button('Revert##grprevert', { 0, 22 }) then trigLoad(true); groupSetStatus('Reverted to the on-disk groups.', false); end
    local st  = (groupUI.status ~= '') and groupUI.status or trig.status;
    local se  = (groupUI.status ~= '') and groupUI.statusErr or trig.statusErr;
    if st ~= '' then
        imgui.SameLine(0, 10);
        imgui.TextColored(se and COL_ERR or COL_SCORE, esc(st));
    end

    -- Bulk fast-paths, promoted to the top row (Henrik 07-20: the collapsible
    -- sections at the bottom were easy to miss). Import opens the paste window
    -- (issue #30's flow); Auto-Import runs the Lua-file scan right away (Item
    -- 1's flow) and opens its picker.
    imgui.Spacing();
    if hasGroupImport then
        if imgui.Button('Import##grpimptop', { 0, 24 }) then
            groupUI.plan = nil;
            groupUI._openImport = true;
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Paste a Lua table of groups -- one group per  Name = {...}.');
        end
    end
    if hasGroupScan then
        if hasGroupImport then imgui.SameLine(0, 6); end
        if imgui.Button('Auto-Import##grpautotop', { 0, 24 }) then
            groupAutoScan();
            groupUI._openAuto = true;
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Scan your LuaAshitacast job file for spell tables and pick which to\nimport as groups -- no copy-paste.');
        end
    end

    imgui.Spacing();
    imgui.TextColored(COL_DIM, 'One trigger can gear many spells that share stats: build a group here, then add a');
    imgui.TextColored(COL_DIM, '"group" condition to a Precast / Midcast / Ability / Item / Weaponskill rule.');
    imgui.Spacing();

    local names = gm.names(groups);
    if #names == 0 then imgui.TextColored(COL_DIM, '(no groups yet)'); end

    -- aligned controls column shared by every box (longest left line wins)
    local colX = 220;
    for _, nm in ipairs(names) do
        local w = textW(nm) + 70;
        if w > colX then colX = w; end
        for _, mbr in ipairs(groups[nm]) do
            local w2 = textW('   ' .. mbr) + 46;
            if w2 > colX then colX = w2; end
        end
    end
    local avail = imgui.GetContentRegionAvail();
    if type(avail) == 'number' and colX > avail * 0.55 then colX = avail * 0.55; end

    for _, nm in ipairs(names) do renderGroupBox(nm, groups, colX); end

    imgui.Spacing();
    if imgui.Button('+ Group...##grpadd', { 0, 26 }) then
        groupUI.newName[1] = ''; groupUI._openAdd = true;
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Create a named group, then add member action names by typing them.');
    end

    -- The Import / Auto-Import windows (opened from the top row).
    if groupUI._openImport then imgui.OpenPopup('##dlac_grpimport'); groupUI._openImport = false; end
    renderGroupImportPopup(groups);
    if groupUI._openAuto then imgui.OpenPopup('##dlac_grpautoimp'); groupUI._openAuto = false; end
    renderGroupAutoImportPopup(groups);

    if groupUI._openAdd then imgui.OpenPopup('##dlac_groupadd'); groupUI._openAdd = false; end
    renderGroupAddPopup();
    if groupUI._openRename then imgui.OpenPopup('##dlac_grouprename'); groupUI._openRename = false; end
    renderGroupRenamePopup();

    -- Browse-list picker (G3, issue #26): cache the combined job list once per job (the
    -- ~1000-row scan must not run per frame), then open/render the shared popup.
    if hasBrowse then
        if groupUI._listJob ~= job then
            groupUI._list = ap.buildList(job, spellDB, abilityDB);
            groupUI._listJob = job;
        end
        if groupUI._openBrowse then imgui.OpenPopup('##dlac_groupbrowse'); groupUI._openBrowse = false; end
        renderGroupBrowsePopup(job);
    end
end

-- ---------------------------------------------------------------------------
-- Blueprints section (issue #65, slice 1). A nav section inside the Triggers tab
-- (the Groups precedent -- NOT a uihost tab; smoke_ui asserts non-registration).
-- Lists the per-character library with per-entry Stamp / Edit / Delete. Stamp routes
-- through trigCommit (the normal trigger commit + hot-reload); Edit reuses the
-- existing rule editor (renderTrigAddPopup), bound to the library entry.
-- ---------------------------------------------------------------------------

-- Insert the entry's rule into the CURRENT job's trigger data in its Handler and commit
-- through the normal path -- the engine hot-reloads it, no Reload LAC. Warn-but-allow when
-- an identical rule already exists (double-stamp caught, never forbidden). Dangling set /
-- Mode / Group references stamp verbatim -- the existing missing-* banners cover them.
local function bpStamp(entry)
    local _, abbr = trigFilePath();
    if abbr == nil then bpSetStatus('Log in (with a known job) to stamp.', true); return; end
    trigLoad(false);
    trig.data = trig.data or {};
    local dup = bp.identicalExists(entry, trig.data);
    trig.data = bp.stamp(entry, trig.data);            -- NEW table (detached); rule appended
    trig.dirty = true;
    trig._prioBuf = {};                                -- rule objects changed identity
    trigCommit();                                      -- serialize + /dl triggers reload
    if dup then
        bpSetStatus(string.format('Stamped "%s" onto %s %s -- an identical rule already existed there (added anyway).',
            entry.name, abbr, entry.handler), true);
    else
        bpSetStatus(string.format('Stamped "%s" onto %s %s -- live now (hot-reloaded, no Reload LAC).',
            entry.name, abbr, entry.handler), false);
    end
end

-- Bind the EXISTING rule editor to library entry #index (no second editor). Loads the rule's
-- conditions/set/priority into the builder exactly as a job-rule edit does; Save writes back
-- to the library (renderTrigAddPopup, bpEditing branch). Never retro-edits stamped Triggers.
local function bpEdit(index)
    local e = bpUI.lib and bpUI.lib[index] or nil;
    if e == nil then return; end
    trig.addFor, trig._bpEdit, trig.editIdx, trig._editEquip = e.handler, index, nil, e.rule.equip;
    trig.addConds = {};
    for k, v in pairs(e.rule.when or {}) do
        trig.addConds[#trig.addConds + 1] = { key = k, value = v };
    end
    table.sort(trig.addConds, function(a, b) return tostring(a.key) < tostring(b.key); end);
    for _, entry in ipairs(e.rule.whenAny or {}) do
        for k, v in pairs(entry) do
            trig.addConds[#trig.addConds + 1] = { key = k, value = v, any = true };
        end
    end
    trig.addSet = (type(e.rule.set) == 'table') and e.rule.set[1] or e.rule.set;
    trig.addPrio[1] = e.rule.priority or 0;
    trig._addDef = 1; trig.addValText[1] = ''; trig._addValSel = nil;
    trig._addPlayer = 1; trig._addPet = 1; trig.addValNum[1] = 0;
    trig._openAdd = true;
end

local function renderBpRenamePopup()
    if not imgui.BeginPopup('##dlac_bprename') then return; end
    local e = bpUI.lib and bpUI.lib[bpUI.renaming] or nil;
    if e == nil then imgui.EndPopup(); return; end
    imgui.TextColored(COL_HEADER, 'Rename Blueprint');
    imgui.PushItemWidth(240);
    imgui.InputText('##bprenamebuf', bpUI.renameBuf, 96);
    imgui.PopItemWidth();
    if imgui.Button('Rename##bprenamego', { 0, 0 }) then
        local ok, err = bp.rename(bpUI.lib, bpUI.renaming, bpUI.renameBuf[1]);
        if not ok then bpSetStatus(err, true);
        elseif bpSave() then bpSetStatus('Renamed.', false); bpUI.renaming = nil; imgui.CloseCurrentPopup(); end
    end
    imgui.SameLine(0, 6);
    if imgui.Button('Cancel##bprenamex', { 0, 0 }) then bpUI.renaming = nil; imgui.CloseCurrentPopup(); end
    imgui.EndPopup();
end

-- ---------------------------------------------------------------------------
-- Text sharing (issue #66, slice 2). View text / Copy (one entry), Copy all (the whole
-- library), and paste-import -- the profilesmenu "view text + Copy all" and Groups-import
-- classify/apply precedents. The shareable text is the SAME `blueprints v1` blob the library
-- file uses (bp.serialize), so a single Blueprint and the whole library render one way.
-- ---------------------------------------------------------------------------

-- Open the View-text popup for entry #idx (a one-entry blob) or the whole library (idx == 'all',
-- Copy all). Serializes ONCE, into bpUI.viewText; the popup rebuilds a copy buffer each frame.
local function bpOpenView(idx)
    local pretty = hasDispatch and dsp.PRETTY_KEY or nil;
    local text = '';
    local ok = pcall(function()
        if idx == 'all' then text = bp.serialize(bpUI.lib or {}, pretty);
        else text = bp.serializeOne((bpUI.lib or {})[idx], pretty); end
    end);
    if not ok then bpSetStatus('Could not render the Blueprint text.', true); return; end
    bpUI.viewIdx, bpUI.viewText, bpUI._openView = idx, text, true;
end

-- Put `text` on the clipboard (guarded), report via the section status line.
local function bpCopyToClipboard(text, receipt)
    if not hasClipboard then bpSetStatus('No clipboard API in this build -- select the text and Ctrl+C.', true); return; end
    pcall(function() imgui.SetClipboardText(text or ''); end);
    bpSetStatus(receipt, false);
end

-- The View-text popup: a selectable box of the blob (one entry or the whole library) with a
-- one-click Copy. A copy source, never an editor -- the buffer is rebuilt every frame.
local function renderBpViewPopup()
    if not imgui.BeginPopup('##dlac_bpview') then return; end
    local all = (bpUI.viewIdx == 'all');
    imgui.TextColored(COL_HEADER, all and 'Copy all -- the whole Blueprint library' or 'Blueprint text');
    imgui.TextColored(COL_DIM, 'Send this text to a friend -- they paste it under Blueprints > Import from text.');
    imgui.Separator();
    local txt = bpUI.viewText or '';
    bpUI.viewBuf[1] = txt;                                 -- rebuilt each frame: a copy source
    if hasMultiline then
        imgui.InputTextMultiline('##bpviewtext', bpUI.viewBuf, #txt + 64, { 540, 220 });
    else
        imgui.PushItemWidth(540);
        imgui.InputText('##bpviewtext', bpUI.viewBuf, #txt + 64);
        imgui.PopItemWidth();
    end
    if hasClipboard then
        if imgui.Button(all and 'Copy all to clipboard##bpviewcopy' or 'Copy to clipboard##bpviewcopy', { 0, 24 }) then
            bpCopyToClipboard(txt, all and 'Copied the whole library to the clipboard.' or 'Copied the Blueprint to the clipboard.');
        end
        if imgui.IsItemHovered() then imgui.SetTooltip('Puts the text on the clipboard in one click.'); end
        imgui.SameLine(0, 8);
    else
        imgui.TextColored(COL_DIM, '(no clipboard API -- select the text and Ctrl+C)');
    end
    if imgui.Button('Close##bpviewclose', { 90, 24 }) then imgui.CloseCurrentPopup(); end
    imgui.EndPopup();
end

-- Apply the pending import plan into the live library and save. Overwrite happens only on the
-- confirm path (overwrite == true); the default refuses collisions. Mirrors applyImportPlan.
local function bpApplyImport(overwrite)
    local plan = bpUI.importPlan;
    if plan == nil or bpUI.lib == nil then return; end
    local sum = bp.applyImport(bpUI.lib, plan.entries, overwrite);
    plan.pending = false;
    local parts = {};
    if sum.created > 0 then parts[#parts + 1] = sum.created .. ' created'; end
    if sum.updated > 0 then parts[#parts + 1] = sum.updated .. ' overwritten'; end
    if sum.refused > 0 then parts[#parts + 1] = sum.refused .. ' skipped (name already in your library)'; end
    if #parts == 0 then parts[#parts + 1] = 'nothing changed'; end
    if (sum.created + sum.updated) > 0 then
        if bpSave() then bpSetStatus('Imported: ' .. table.concat(parts, ', ') .. '.', false);
        else bpLoad(true); end                             -- save failed: reload the on-disk truth
    else
        bpSetStatus('Import: ' .. table.concat(parts, ', ') .. '.', sum.refused > 0);
    end
end

-- The paste-import popup: a box for a friend's Blueprint blob, live-parsed to a preview (entries
-- listed with handler + condition summary, created vs collide split) BEFORE commit. A collision
-- requires the explicit overwrite confirm (the Groups-import law); no collisions -> import at once.
local function renderBpImportPopup()
    imgui.SetNextWindowSizeConstraints({ 520, 0 }, { 680, 560 });
    if not imgui.BeginPopup('##dlac_bpimport') then return; end
    imgui.TextColored(COL_HEADER, 'Import Blueprints from text');
    imgui.TextColored(COL_DIM, 'Paste a friend\'s Blueprint text (one entry or a whole library). It parses live below.');
    imgui.TextColored(COL_DIM, 'Referenced sets / Modes / Groups you lack import fine -- the warning appears when you Stamp.');

    if hasMultiline then
        imgui.InputTextMultiline('##bpimptext', bpUI.importText, 262144, { 540, 130 });
    else
        imgui.TextColored(COL_SCORE, '(this build has no multiline box -- paste as ONE line)');
        imgui.PushItemWidth(540);
        imgui.InputText('##bpimptext', bpUI.importText, 262144);
        imgui.PopItemWidth();
    end

    -- Live parse: re-run only when the text length changed (cheap frame-to-frame).
    if bpUI.importParsedLen ~= #(bpUI.importText[1] or '') then
        bpUI.importParsedLen = #(bpUI.importText[1] or '');
        bpUI.importPlan = nil;
        local text = bpUI.importText[1] or '';
        if text:gsub('%s+', '') ~= '' then
            local prev, perr = bp.previewImport(text, bpUI.lib or {});
            if prev == nil then
                bpUI.importPlan = { err = perr or 'could not parse the pasted text' };
            else
                bpUI.importPlan = { entries = prev.entries, created = prev.created,
                                    collided = prev.collided, pending = true };
            end
        end
    end

    local plan = bpUI.importPlan;
    if plan ~= nil and plan.err ~= nil then
        imgui.Separator();
        imgui.TextColored(COL_ERR, esc('Not a Blueprint blob (yet): ' .. tostring(plan.err)));
    elseif plan ~= nil and plan.entries ~= nil then
        imgui.Separator();
        imgui.TextColored(COL_HEADER, plan.pending and string.format('Preview -- %d entr%s', #plan.entries, (#plan.entries == 1) and 'y' or 'ies') or 'Imported');
        for _, e in ipairs(plan.entries) do
            local summary = '';
            pcall(function() summary = bp.emitRule(e.rule, hasDispatch and dsp.PRETTY_KEY or nil); end);
            imgui.TextColored(COL_SCORE, esc('  ' .. tostring(e.name)));
            imgui.SameLine(0, 8);
            imgui.TextColored(COND_COLORS.mode or COL_HEADER, esc(tostring(e.handler)));
            imgui.TextColored(COL_DIM, esc('      ' .. summary));
        end
        if #plan.created > 0 then
            imgui.TextColored(COL_USABLE, string.format('create %d: %s', #plan.created, esc(table.concat(plan.created, ', '))));
        end
        if #plan.collided > 0 then
            imgui.TextColored(COL_ERR, string.format('collide %d (name already in your library): %s', #plan.collided, esc(table.concat(plan.collided, ', '))));
        end
        if plan.pending then
            if #plan.collided == 0 then
                if imgui.Button('Import##bpimpgo', { 0, 24 }) then bpApplyImport(false); end
                if imgui.IsItemHovered() then imgui.SetTooltip('Add these Blueprints to your library and save.'); end
            else
                if imgui.Button('Import new only##bpimpnew', { 0, 24 }) then bpApplyImport(false); end
                if imgui.IsItemHovered() then imgui.SetTooltip('Add only the non-colliding Blueprints; keep your existing ones.'); end
                imgui.SameLine(0, 6);
                if ImGuiCol_Button ~= nil then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
                if imgui.Button(string.format('Overwrite %d & import##bpimpover', #plan.collided), { 0, 24 }) then bpApplyImport(true); end
                if ImGuiCol_Button ~= nil then imgui.PopStyleColor(1); end
                if imgui.IsItemHovered() then imgui.SetTooltip('Replace the named existing Blueprint(s) with the pasted ones, and import the rest.'); end
            end
            imgui.SameLine(0, 6);
        end
        if imgui.Button('Clear##bpimpclr', { 0, 24 }) then
            bpUI.importText[1] = ''; bpUI.importPlan = nil; bpUI.importParsedLen = -1;
        end
    else
        imgui.Separator();
        if imgui.Button('Close##bpimpclose', { 90, 24 }) then imgui.CloseCurrentPopup(); end
    end
    imgui.EndPopup();
end

-- One library entry box: name + handler on the left, the rule text dim below; Stamp / Edit /
-- rename / delete on the right. Returns nothing (actions fire in place).
-- One Blueprint box's height: the identity/button line plus the WRAPPED rule
-- text (long inline payloads used to run off the box edge). The line count is
-- an estimate from CalcTextSize -- the real wrap is PushTextWrapPos(0.0) at the
-- box's live width; the estimate only sizes the child.
local function bpBoxHeight(ruleText, availW)
    local lh = lineH();
    local tw = nil;
    pcall(function()
        local w = imgui.CalcTextSize(ruleText);
        if type(w) == 'number' then tw = w; end
    end);
    tw = tw or (#tostring(ruleText or '') * 7);
    local wrapW = math.max(200, (availW or 740) - 18);
    local nLines = math.max(1, math.ceil(tw / wrapW));
    return math.max(lh + nLines * lh + 28, 56);
end

local function renderBlueprintBox(i, e, ruleText, boxH)
    local id = 'bp_' .. tostring(i);
    imgui.BeginChild('##bpbox' .. id, { -1, boxH }, true, BOX_FLAGS);

    -- Top line: identity, then the actions on the same line (the rule text gets
    -- the full box width below, so it can wrap instead of fighting the buttons).
    imgui.TextColored(COL_SCORE, esc(e.name));
    imgui.SameLine(0, 8);
    imgui.TextColored(COND_COLORS.mode or COL_HEADER, esc(e.handler));
    imgui.SameLine(0, 14);
    if imgui.SmallButton('Stamp onto this job##bpstamp' .. id) then bpStamp(e); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Insert this rule into the current job\'s ' .. e.handler .. ' handler\nand commit -- live immediately (no Reload LAC). The stamped Trigger\nis ordinary afterwards; editing this Blueprint will not change it.');
    end
    imgui.SameLine(0, 6);
    if imgui.SmallButton('Edit##bpedit' .. id) then bpEdit(i); end
    if imgui.IsItemHovered() then imgui.SetTooltip('Edit this Blueprint in the rule builder (the same editor as the Triggers tab).'); end
    imgui.SameLine(0, 6);
    if imgui.SmallButton('View text##bpview' .. id) then bpOpenView(i); end
    if imgui.IsItemHovered() then imgui.SetTooltip('Show this Blueprint\'s shareable text with a one-click Copy --\npaste it to a friend (they use Import from text).'); end
    if hasClipboard then
        imgui.SameLine(0, 6);
        if imgui.SmallButton('Copy##bpcopy' .. id) then
            local pretty = hasDispatch and dsp.PRETTY_KEY or nil;
            local text = '';
            pcall(function() text = bp.serializeOne(e, pretty); end);
            bpCopyToClipboard(text, string.format('Copied "%s" to the clipboard.', e.name));
        end
        if imgui.IsItemHovered() then imgui.SetTooltip('Copy this Blueprint\'s text straight to the clipboard.'); end
    end
    imgui.SameLine(0, 6);
    if imgui.SmallButton('rename##bpren' .. id) then
        bpUI.renaming = i; bpUI.renameBuf[1] = e.name; bpUI._openRename = true;
    end
    imgui.SameLine(0, 6);
    if bpUI.delArm == i then
        local red = (ImGuiCol_Button ~= nil);
        if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
        if imgui.SmallButton('confirm delete##bpdel' .. id) then
            bp.remove(bpUI.lib, i); bpUI.delArm = nil;
            if bpSave() then bpSetStatus('Blueprint deleted.', false); end
        end
        if red then imgui.PopStyleColor(1); end
        imgui.SameLine(0, 4);
        if imgui.SmallButton('keep##bpkeep' .. id) then bpUI.delArm = nil; end
    else
        if imgui.SmallButton('x##bpdel' .. id) then bpUI.delArm = i; end
        if imgui.IsItemHovered() then imgui.SetTooltip('Delete this Blueprint from your library (click again to confirm).'); end
    end

    -- The rule, wrapped at the live box edge (the gearcheck-warnings pattern).
    imgui.PushTextWrapPos(0.0);
    imgui.TextColored(COL_DIM, esc(ruleText));
    imgui.PopTextWrapPos();

    imgui.EndChild();
end

function M.renderBlueprints(job, level)
    if not hasImgui then return; end
    if deps == nil then
        imgui.TextColored(COL_ERR, 'Blueprints section not initialized (gearui deps missing).');
        return;
    end
    if not hasBlueprints then
        imgui.TextColored(COL_ERR, 'blueprintsmodel module unavailable -- the Blueprints section is disabled.');
        return;
    end
    if bpFilePath() == nil then
        imgui.TextColored(COL_DIM, 'Log in to use Blueprints (your reusable rule library).');
        return;
    end
    bpLoad(false);

    imgui.TextColored(COL_HEADER, 'Blueprints');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_DIM, 'reusable trigger rules -- job-independent, saved once, stamped onto any job');

    -- Auto-expire the status line so a lingering receipt never reads as a fresh action.
    if bpUI.status ~= '' and os.clock() - (bpUI.statusAt or 0) > 6 then bpUI.status = ''; end
    if bpUI.status ~= '' then
        imgui.TextColored(bpUI.statusErr and COL_ERR or COL_SCORE, esc(bpUI.status));
    end
    if bpUI.err ~= nil then
        imgui.TextColored(COL_ERR, esc('Library problem: ' .. tostring(bpUI.err)));
    end

    imgui.Spacing();
    imgui.TextColored(COL_DIM, 'Save any rule as a Blueprint with the "bp" button on its row (any handler).');
    imgui.TextColored(COL_DIM, 'Then Stamp it onto whatever job you are on -- the rule arrives without rebuilding it.');

    -- Section-level text sharing (issue #66): Copy all (the whole library) + Import from text.
    local lib = bpUI.lib or {};
    imgui.Spacing();
    if #lib > 0 then
        if imgui.SmallButton('Copy all (view text)##bpcopyall') then bpOpenView('all'); end
        if imgui.IsItemHovered() then imgui.SetTooltip('View the whole library as one blob with a one-click Copy all --\nshare your entire protection kit in a single paste.'); end
        if hasClipboard then
            imgui.SameLine(0, 6);
            if imgui.SmallButton('Copy all to clipboard##bpcopyallclip') then
                local pretty = hasDispatch and dsp.PRETTY_KEY or nil;
                local text = '';
                pcall(function() text = bp.serialize(lib, pretty); end);
                bpCopyToClipboard(text, string.format('Copied all %d Blueprint%s to the clipboard.', #lib, (#lib == 1) and '' or 's'));
            end
            if imgui.IsItemHovered() then imgui.SetTooltip('Put the whole library on the clipboard in one click.'); end
        end
        imgui.SameLine(0, 12);
    end
    if imgui.SmallButton('Import from text...##bpimport') then
        bpUI.importText[1] = ''; bpUI.importPlan = nil; bpUI.importParsedLen = -1; bpUI._openImport = true;
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Paste a friend\'s Blueprint text -- see what it contains before importing.'); end
    imgui.Spacing();

    if #lib == 0 then
        imgui.TextColored(COL_DIM, '(no Blueprints yet -- save a rule with its "bp" button)');
    end
    if #lib > 0 then
        -- The library scrolls in a capped child (the Sets-list pattern) so a
        -- grown collection stops eating the tab. Rule text is emitted ONCE per
        -- entry per frame and shared with the box renderer.
        local availW = 740;
        pcall(function()
            local v = imgui.GetContentRegionAvail();
            if type(v) == 'table' then v = v[1] or v.x; end
            if type(v) == 'number' and v > 100 then availW = v; end
        end);
        local texts, listH = {}, 8;
        for i, e in ipairs(lib) do
            local rt = '';
            pcall(function() rt = bp.emitRule(e.rule, hasDispatch and dsp.PRETTY_KEY or nil); end);
            texts[i] = rt;
            listH = listH + bpBoxHeight(rt, availW - 24) + 6;
        end
        imgui.BeginChild('##bplist', { -1, math.min(math.max(listH, 60), 320) }, false);
        for i, e in ipairs(lib) do
            renderBlueprintBox(i, e, texts[i], bpBoxHeight(texts[i], availW - 24));
        end
        imgui.EndChild();
    end

    if bpUI._openRename then imgui.OpenPopup('##dlac_bprename'); bpUI._openRename = false; end
    renderBpRenamePopup();
    if bpUI._openView then imgui.OpenPopup('##dlac_bpview'); bpUI._openView = false; end
    renderBpViewPopup();
    if bpUI._openImport then imgui.OpenPopup('##dlac_bpimport'); bpUI._openImport = false; end
    renderBpImportPopup();
end

function M.render(job, level)
    if not hasImgui then return; end
    if deps == nil then
        imgui.TextColored(COL_ERR, 'Triggers tab not initialized (gearui deps missing).');
        return;
    end
    if not hasDispatch then
        imgui.TextColored(COL_ERR, 'dispatch module unavailable -- the Triggers tab is disabled.');
        return;
    end
    local path, abbr = trigFilePath();
    if path == nil then
        imgui.TextColored(COL_DIM, 'Log in (with a known job) to edit triggers.');
        return;
    end
    trigLoad(false);
    renderModeDeleteWindow();   -- its own movable window; independent of any section state

    -- Floating Trigger Monitor toggle (engine v55): live modes + the last 5
    -- fired rules. Visibility persists via uiflags; the window itself
    -- remembers where you dragged it (imgui.ini).
    if deps.ui ~= nil then
        local mb = { deps.ui._tgMon == true };
        if imgui.Checkbox('Trigger monitor##tgmon', mb) then
            deps.ui._tgMon = (mb[1] == true);
            deps.ui._flagsDirty = true;
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('A small floating window: your active modes and the last 5 trigger\nrules that fired, newest first -- STREAMED live as they change.\nInvaluable when field-testing: Precast/Midcast land as history lines\nfaster than chat can scroll. Stays up when the main window closes.');
        end
    end

    if trig.data == nil then
        imgui.TextColored(COL_DIM, 'No trigger file for ' .. tostring(abbr) .. ' yet.');
        if trig.err ~= nil and trig.err ~= 'no file' then imgui.TextColored(COL_ERR, esc(tostring(trig.err))); end
        if imgui.Button('Create starter triggers##trginit', { 0, 24 }) then
            deps.seedTriggersFile(deps.charBase(), abbr);
            trigLoad(true);
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Writes the classic status rules (Engaged/Resting/Movement/Idle) as a starting point.');
        end
        return;
    end

    -- Engine staleness banner: the LAC-state engine stamps its VERSION into the
    -- modestate mirror. When it lags the addon's copy, every confusing symptom
    -- ("unknown handler section", dead keybinds, missing features) traces here --
    -- say it loudly instead of letting the user chase ghosts.
    if hasDispatch and type(dsp.VERSION) == 'number' then
        local mv = trigModeState()['__version'];
        if type(mv) == 'number' and mv < dsp.VERSION then
            imgui.TextColored(COL_ERR, string.format(
                '[!] LuaAshitacast is running an OUTDATED dlac engine (v%d; the addon has v%d) -- click "Reload LAC" (top-right).',
                mv, dsp.VERSION));
        elseif mv == nil and trig._modeStateExists == true then
            imgui.TextColored(COL_ERR,
                '[!] LuaAshitacast is running an OUTDATED dlac engine -- click "Reload LAC" (top-right).');
        end
    end

    -- Missing-set banner: rules that would MATCH and then equip NOTHING. The
    -- engine no longer chat-warns about these (inform by printing as little as
    -- possible) -- this red line + the per-row [missing] markers ARE the signal.
    do
        local have = {};
        for _, n in ipairs(allSetNames()) do have[n] = true; end
        local miss, seen = {}, {};
        for _, ev in ipairs(TRIG_HANDLERS) do
            for _, r in ipairs(trig.data[ev] or {}) do
                local slist = (type(r.set) == 'table') and r.set or ((r.set ~= nil) and { r.set } or {});
                for _, sn in ipairs(slist) do
                    sn = tostring(sn);
                    if not have[sn] and not seen[sn] then seen[sn] = true; miss[#miss + 1] = sn; end
                end
            end
        end
        if #miss > 0 then
            table.sort(miss);
            imgui.TextColored(COL_ERR, string.format(
                '[!] %d trigger target set(s) missing from this profile: %s -- those rules equip NOTHING (red [missing] below). Create them in the Sets tab.',
                #miss, esc(table.concat(miss, ', '))));
        end
    end

    -- Missing-GROUP banner: rules whose `group` condition names a group this job
    -- doesn't define (deleted / renamed / typo'd) -- they match nothing. Parity
    -- with the missing-set banner above (ADR 0009; hard rule 12).
    do
        local gmiss, gseen = {}, {};
        for _, ev in ipairs(TRIG_HANDLERS) do
            for _, r in ipairs(trig.data[ev] or {}) do
                local gv = r.when and r.when.group;
                local refs = (type(gv) == 'table') and gv or ((gv ~= nil) and { gv } or {});
                for _, gnm in ipairs(refs) do
                    gnm = tostring(gnm);
                    if not groupDefined(gnm) and not gseen[string.lower(gnm)] then
                        gseen[string.lower(gnm)] = true; gmiss[#gmiss + 1] = gnm;
                    end
                end
            end
        end
        if #gmiss > 0 then
            table.sort(gmiss);
            imgui.TextColored(COL_ERR, string.format(
                '[!] %d trigger group reference(s) not defined for this job: %s -- those rules match NOTHING (red [missing group] below). Create them in the Groups section.',
                #gmiss, esc(table.concat(gmiss, ', '))));
        end
    end

    -- Controls row: Commit (red when dirty) / Revert / Explain + status.
    local dirty = trig.dirty and ImGuiCol_Button ~= nil;
    if dirty then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
    if imgui.Button('Commit##trgcommit', { 0, 22 }) then trigCommit(); end
    if dirty then imgui.PopStyleColor(1); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Writes triggers\\' .. tostring(abbr) .. '.lua and hot-reloads the engine -- live immediately, no /lac reload.');
    end
    imgui.SameLine(0, 6);
    if imgui.Button('Revert##trgrevert', { 0, 22 }) then trigLoad(true); trigSetStatus('Reverted to the on-disk rules.', false); end
    imgui.SameLine(0, 6);
    if imgui.Button('Explain last action##trgwhy', { 0, 22 }) then
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl why'); end);
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Prints which triggers fired for the last actions to the chat log (/dl why).'); end
    -- Auto-expire after 5s so a lingering "Committed -- live now" never reads as a fresh
    -- commit on the next click (otherwise you can't tell the new commit took).
    if trig.status ~= '' and os.clock() - (trig.statusAt or 0) > 5 then trig.status = ''; end
    if trig.status ~= '' then
        imgui.SameLine(0, 10);
        imgui.TextColored(trig.statusErr and COL_ERR or COL_SCORE, esc(trig.status));
    end

    -- Section inventory (counts drive the nav labels).
    local defs = trig.data.Modes or {};
    local modes, mseen = {}, {};
    for nm in pairs(defs) do
        if not mseen[string.lower(nm)] then mseen[string.lower(nm)] = true; modes[#modes + 1] = nm; end
    end
    for _, hh in ipairs(TRIG_HANDLERS) do
        for _, r in ipairs(trig.data[hh] or {}) do
            local m = r.when and r.when.mode;
            if type(m) == 'string' then
                m = m:match('^([^:]+)') or m;                  -- 'Weapon:Melee' -> 'Weapon'
                if not mseen[string.lower(m)] then
                    mseen[string.lower(m)] = true; modes[#modes + 1] = m;
                end
            end
        end
    end
    table.sort(modes);
    local groupCount = 0;
    if type(trig.data.Groups) == 'table' then
        for _ in pairs(trig.data.Groups) do groupCount = groupCount + 1; end
    end
    local warnCount = 0;
    pcall(function()
        local gc = require("dlac\\gear\\gearcheck");
        if type(gc) == 'table' and type(gc.auditCached) == 'function' then
            warnCount = #(gc.auditCached(2) or {});
        end
    end);
    -- Blueprints library count for the nav label (per-character, loaded on demand).
    local bpCount = 0;
    if hasBlueprints then pcall(bpLoad, false); bpCount = bpUI.lib and #bpUI.lib or 0; end

    -- ONE section at a time: a slim nav column picks what fills the big main
    -- area -- no stacked collapsibles, no permanently-scrolling sidebar.
    trig.section = trig.section or 'Modes';
    -- Automations moved to its own MAIN tab (right of Triggers); a stale section
    -- value would fall through to the handler branch below and render an empty
    -- "Automations rules" list.
    if trig.section == 'Automations' then trig.section = 'Modes'; end
    imgui.BeginChild('##trgnav', { 148, -1 }, false);
    local function navItem(id, label)
        imgui.PushID('trgnav_' .. id);
        if imgui.Selectable(label, trig.section == id, ImGuiSelectableFlags_None, { 0, 19 }) then
            trig.section = id;
        end
        imgui.PopID();
    end
    navItem('Modes', string.format('Modes (%d)', #modes));
    navItem('Groups', string.format('Groups (%d)', groupCount));
    if hasBlueprints then navItem('Blueprints', string.format('Blueprints (%d)', bpCount)); end
    for _, h in ipairs(TRIG_HANDLERS) do
        navItem(h, string.format('%s (%d)', h, #(trig.data[h] or {})));
    end
    navItem('Warnings', string.format('Warnings (%d)', warnCount));
    imgui.EndChild();
    imgui.SameLine(0, 10);

    imgui.BeginChild('##trgmain', { -1, -1 }, false);
    if trig.section == 'Modes' then
        renderModesSection(defs, modes);
    elseif trig.section == 'Groups' then
        M.renderGroups(job, level);
    elseif trig.section == 'Blueprints' then
        M.renderBlueprints(job, level);
    elseif trig.section == 'Warnings' then
        pcall(renderGearWarnings, true);
    else
        local h = trig.section;
        local list = trig.data[h] or {};
        local setNames = allSetNames();
        imgui.TextColored(COL_HEADER, h .. ' rules');
        imgui.Spacing();
        -- aligned controls column for THIS section: longest condition line wins
        local colX = 190;
        for _, r in ipairs(list) do
            for _, ln in ipairs(condLines(r.when)) do
                local w = textW(ln.text) + 28;
                -- player-state lines reserve the [on now]/[off now] column, so
                -- the marker can never clip into the set/controls side
                if PSTATE_KEYS[ln.key] ~= nil then w = w + markW(); end
                if w > colX then colX = w; end
            end
            for _, e in ipairs(r.whenAny or {}) do
                for k, v in pairs(e) do
                    local lk = string.lower(tostring(k));
                    local w = textW('| ' .. trigPrettyKey(lk)
                        .. ((v == true) and '' or (' = ' .. tostring(v)))) + 28;
                    if PSTATE_KEYS[lk] ~= nil then w = w + markW(); end
                    if w > colX then colX = w; end
                end
            end
        end
        local availW = imgui.GetContentRegionAvail();
        if type(availW) == 'number' and colX > availW * 0.55 then colX = availW * 0.55; end
        local removeAt, editAt = nil, nil;
        for i, r in ipairs(list) do
            local act = renderTrigRuleBox(h, i, r, setNames, colX);
            if act == 'remove' then removeAt = i;
            elseif act == 'edit' then editAt = i;
            elseif act == 'blueprint' then bpCapture(h, r); end   -- Save as Blueprint (one click)
        end
        if removeAt ~= nil then
            table.remove(list, removeAt);
            trig.data[h] = list;
            trig.dirty = true;
            trig._prioBuf = {};   -- row ids shifted; rebuild the priority buffers
        end
        if editAt ~= nil then
            -- Pre-load the rule builder with this rule and open it in edit mode.
            local r = list[editAt];
            trig.addFor, trig.editIdx, trig._editEquip, trig._bpEdit = h, editAt, r.equip, nil;
            trig.addConds = {};
            for k, v in pairs(r.when or {}) do
                trig.addConds[#trig.addConds + 1] = { key = k, value = v };
            end
            table.sort(trig.addConds, function(a, b) return tostring(a.key) < tostring(b.key); end);
            -- | leg: one builder row per OR entry. A hand-written multi-key
            -- entry (AND-within-OR) flattens to its keys here; saving from the
            -- builder rewrites them as single-key entries.
            for _, e in ipairs(r.whenAny or {}) do
                for k, v in pairs(e) do
                    trig.addConds[#trig.addConds + 1] = { key = k, value = v, any = true };
                end
            end
            trig.addSet = (type(r.set) == 'table') and r.set[1] or r.set;   -- builder edits ONE set; extras stay on the rule
            trig.addPrio[1] = r.priority or 0;
            trig._addDef = 1; trig.addValText[1] = ''; trig._addValSel = nil;
            trig._addPlayer = 1; trig._addPet = 1; trig.addValNum[1] = 0;
            trig._openAdd = true;
        end
        if imgui.Button('+ Add rule##trgadd_' .. h, { 0, 28 }) then
            trig.addFor = h; trig.addConds = {}; trig._addDef = 1;
            trig.addValText[1] = ''; trig._addValSel = nil; trig.addSet = nil; trig.addPrio[1] = 0;
            trig._addPlayer = 1; trig._addPet = 1; trig.addValNum[1] = 0;
            trig.editIdx, trig._editEquip, trig._bpEdit = nil, nil, nil;   -- fresh add, not an edit
            trig._openAdd = true;
        end
    end
    imgui.EndChild();

    if trig._openAdd then imgui.OpenPopup('##dlac_trigadd'); trig._openAdd = false; end
    renderTrigAddPopup();
    if trig._openModePopup then imgui.OpenPopup('##dlac_modeadd'); trig._openModePopup = false; end
    renderModePopup();
end

return M;
