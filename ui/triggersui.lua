--[[
    dlac/triggersui.lua -- the Triggers tab (GUI editor for the dispatch engine's data).

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
local _lsok, lscale = pcall(require, "dlac\\data\\levelstats");
local _gmok, gm   = pcall(require, "dlac\\gear\\groupsmodel");
local _giok, gimp = pcall(require, "dlac\\gear\\groupimport");
local _gsok, gscan = pcall(require, "dlac\\gear\\groupscan");   -- Item 1: auto-import from the Lua file
-- Searchable spell/ability browse-list for the Groups member picker (G3, issue #26):
-- the pure list/search core + the two picker-DB data files it filters. Addon-state only
-- (a UI module -- never seeded into LAC), so requiring the data here is fine; all guarded,
-- a missing piece only loses the browse button (free-name entry still works).
local _apok, ap   = pcall(require, "dlac\\gear\\actionpicker");
local _spok, spellDB   = pcall(require, "dlac\\data\\spells");
local _abok, abilityDB = pcall(require, "dlac\\data\\abilities");
local hasImgui    = _iok and imgui ~= nil;
local hasDispatch = _dpok and type(dsp) == 'table';
local hasLScale   = _lsok and type(lscale) == 'table';
local hasGroups   = _gmok and type(gm) == 'table';
local hasGroupImport = _giok and type(gimp) == 'table';
local hasGroupScan   = _gsok and type(gscan) == 'table';
-- InputTextMultiline is the right widget for a paste box, but it is not used anywhere else in
-- this install -- probe it (hard rule 2: presence proves nothing, but absence is certain), and
-- degrade to a single-line box with a visible note rather than silently disabling the feature.
local hasMultiline = hasImgui and type(imgui.InputTextMultiline) == 'function';
local hasBrowse   = _apok and type(ap) == 'table'
    and _spok and type(spellDB) == 'table' and _abok and type(abilityDB) == 'table';

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
local SPELL_CONDS = {
    { key = 'skill',     kind = 'list', items = { 'Divine Magic', 'Healing Magic', 'Enhancing Magic', 'Enfeebling Magic', 'Elemental Magic', 'Dark Magic', 'Summoning', 'Ninjutsu', 'Singing', 'Blue Magic', 'Geomancy' } },
    { key = 'magicType', kind = 'list', items = { 'White Magic', 'Black Magic', 'Bard Song', 'Ninjutsu', 'Summoning', 'Blue Magic' } },
    { key = 'element',   kind = 'list', items = { 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark', 'Non-Elemental' } },
    { key = 'songType',  kind = 'list', items = { 'Buff', 'Debuff' } },
    { key = 'contains',  kind = 'text', hint = 'name contains this text: "Madrigal" matches Blade + Sword\nMadrigal; "Stone" matches every Stone tier. Stack it with skill\nvia [+ condition] for AND logic (e.g. skill=Elemental + contains=Stone).' },
    { key = 'group',     kind = 'group', hint = 'match every action in a named group -- one rule gears many\nspells that share gear. Build groups in the Groups section; a per-spell\nname rule still overrides the group.' },
    { key = 'name',      kind = 'text', hint = 'exact spell name, e.g. Slow II' },
    { key = 'dayWeatherBonus', kind = 'flag' },
    { key = 'mode',      kind = 'text', hint = 'a player-toggled mode must be ON (e.g. DT) -- stack with other\nconditions to make a rule mode-dependent' },
    { key = 'any',       kind = 'flag' },
};
local COND_DEFS = {
    Default = {
        { key = 'status', kind = 'list', items = { 'Engaged', 'Resting', 'Idle' } },
        { key = 'moving', kind = 'flag' },
        { key = 'mode',   kind = 'text', hint = 'mode name, e.g. DT' },
    },
    Precast = SPELL_CONDS,
    Midcast = SPELL_CONDS,
    Ability = {
        { key = 'abilityType', kind = 'list', items = { 'Blood Pact: Rage', 'Blood Pact: Ward', 'Corsair Roll', 'Quick Draw', 'Ready', 'Rune Enchantment' } },
        { key = 'contains', kind = 'text', hint = 'name contains this text' },
        { key = 'group',    kind = 'group', hint = 'match every ability in a named group (Groups section)' },
        { key = 'name',     kind = 'text', hint = 'exact ability name, e.g. Repair' },
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
do
    -- Precast/Midcast share one defs table (SPELL_CONDS) -- append ONCE per table.
    local seenDef = {};
    for _, defs in pairs(COND_DEFS) do
        if not seenDef[defs] then
            seenDef[defs] = true;
            defs[#defs + 1] = { key = 'player', kind = 'player', label = 'Player' };
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
    _condDrill = false,   -- no-BeginMenu fallback: Player drill-down open?
    addValText = { '' }, addValNum = { 0 }, addSet = nil, addPrio = { 0 }, _openAdd = false,
    editIdx = nil, _editEquip = nil,   -- rule-builder edit mode (replace in place)
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
    -- Import Lua Table(s) (G4, issue #30): a collapsible paste box + a pending plan awaiting the
    -- overwrite confirmation. `plan` holds the parsed groups + the created/overwritten/skipped
    -- split between the Import click and the (Overwrite &) Import Groups click.
    importText = { '' }, plan = nil,
    -- Auto-import (Item 1): the scanned candidates + their tick state (name -> bool) + notes for
    -- the skipped tables + a pending plan awaiting the overwrite confirmation.
    autoCands = nil, autoNotes = nil, autoMarks = {}, autoPlan = nil, autoScanned = false,
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

-- Build the Triggers-tab edit model from a raw trigger-file table: canonical handler
-- keys, lowercased condition keys. Commit serializes the WHOLE model back to the
-- file, so any section not carried here gets silently wiped on the next Commit --
-- that bug shipped once; keep this exported so the offline tests pin the round-trip.
-- (Legacy SetOptions sections are dropped deliberately: automation is a virtual SLOT
-- entry now -- dlac:AutoStaff / dlac:AutoObi inside the set, ADR 0004 4th revision.)
function M.fileToModel(raw)
    local data = {};
    if type(raw) ~= 'table' then return data; end
    for k, v in pairs(raw) do
        local ev = (hasDispatch and type(dsp.canonEvent) == 'function') and dsp.canonEvent(k) or nil;
        if ev ~= nil and type(v) == 'table' then
            local list = data[ev] or {};
            for _, r in ipairs(v) do
                if type(r) == 'table' and type(r.when) == 'table'
                   and (r.set ~= nil or type(r.equip) == 'table') then
                    local when = {};
                    for ck, cv in pairs(r.when) do when[string.lower(tostring(ck))] = cv; end
                    -- v54 OR group: carried through the model or Commit WIPES it
                    -- (the SetOptions/Modes lesson).
                    local whenAny = nil;
                    local rawAny = r.whenAny or r.whenany;
                    if type(rawAny) == 'table' then
                        for _, e in ipairs(rawAny) do
                            if type(e) == 'table' then
                                local ne = {};
                                for ck, cv in pairs(e) do ne[string.lower(tostring(ck))] = cv; end
                                if next(ne) ~= nil then whenAny = whenAny or {}; whenAny[#whenAny + 1] = ne; end
                            end
                        end
                    end
                    -- set: 'Name' or an ORDERED list (multi-set rule); the model
                    -- mirrors the file (string when single, array when several).
                    local sv = nil;
                    if type(r.set) == 'table' then
                        for _, sn in ipairs(r.set) do
                            if type(sn) == 'string' and sn ~= '' then sv = sv or {}; sv[#sv + 1] = sn; end
                        end
                        if sv ~= nil and #sv == 1 then sv = sv[1]; end
                    elseif r.set ~= nil then
                        sv = tostring(r.set);
                    end
                    list[#list + 1] = {
                        when = when,
                        whenAny = whenAny,
                        set = sv,
                        equip = (type(r.equip) == 'table') and r.equip or nil,
                        priority = tonumber(r.priority),
                    };
                end
            end
            data[ev] = list;
        end
    end
    -- Modes section (cycle definitions + keybinds): carried through so Commit
    -- round-trips it (same lesson as the SetOptions wipe).
    local md = raw.Modes or raw.modes;
    if type(md) == 'table' then
        local copy = {};
        for nm, def in pairs(md) do
            if type(nm) == 'string' and type(def) == 'table' then
                local e = {};
                local src = (type(def.values) == 'table') and def.values or def;
                for _, v in ipairs(src) do
                    if type(v) == 'string' then e.values = e.values or {}; e.values[#e.values + 1] = v; end
                end
                if type(def.bind) == 'string' then e.bind = def.bind; end
                if e.values ~= nil or e.bind ~= nil then copy[nm] = e; end
            end
        end
        if next(copy) ~= nil then data.Modes = copy; end
    end
    -- Groups section (ADR 0009): named action-name lists per Job entry, beside
    -- Modes. Carried through so Commit round-trips it (same SetOptions/Modes wipe
    -- lesson). The sanitize lives in groupsmodel so the carry-through is tested
    -- headless (tests TGM*); guarded so a missing module only loses the feature.
    if hasGroups then
        local gr = gm.fromRaw(raw);
        if next(gr) ~= nil then data.Groups = gr; end
    end
    return data;
end

-- Load the trigger file into the edit model (see M.fileToModel).
local function trigLoad(force)
    local path, abbr = trigFilePath();
    if path == nil then trig.data, trig.job, trig.err = nil, nil, 'not logged in / unknown job'; return; end
    if not force and trig.job == abbr and trig.data ~= nil then return; end
    trig.job, trig.data, trig.err, trig.dirty, trig._prioBuf = abbr, nil, nil, false, {};
    if not hasDispatch then trig.err = 'dispatch module unavailable'; return; end
    local raw, err = dsp.readTriggersRaw(path);
    if raw == nil then trig.err = err; return; end
    trig.data = M.fileToModel(raw);
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

-- Rule references to mode `name` ('X' or 'X:Value', alone or in a list).
-- strip=true edits trig.data in place: a rule gated ONLY on this mode is
-- removed (the mode was load-bearing); a list gate just loses the dead name.
local function modeCondRefs(name, strip)
    local out = { rules = {}, removedRules = 0, editedRules = 0 };
    local target = string.lower(tostring(name or ''));
    if target == '' or trig.data == nil then return out; end
    local function matches(m)
        local s = string.lower(tostring(m));
        return s == target or string.sub(s, 1, #target + 1) == (target .. ':');
    end
    for _, sec in ipairs(TRIG_HANDLERS) do
        local list = trig.data[sec];
        if type(list) == 'table' then
            for i = #list, 1, -1 do
                local r = list[i];
                local mc = (type(r) == 'table' and type(r.when) == 'table') and r.when.mode or nil;
                if mc ~= nil then
                    local gates = (type(mc) == 'table') and mc or { mc };
                    local kept, hit = {}, false;
                    for _, m in ipairs(gates) do
                        if matches(m) then hit = true; else kept[#kept + 1] = m; end
                    end
                    if hit then
                        out.rules[#out.rules + 1] = string.format('%s:  mode %s  ->  %s',
                            sec, modeCondText(mc),
                            (r.set ~= nil) and ('set ' .. ((type(r.set) == 'table') and table.concat(r.set, ' + ') or tostring(r.set)))
                            or 'equip { ... }');
                        if strip then
                            if #kept == 0 then
                                table.remove(list, i);
                                out.removedRules = out.removedRules + 1;
                            else
                                r.when.mode = (#kept == 1) and kept[1] or kept;
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
-- Automations (ADR 0004): auto elemental staff / auto obi. The GUI owns DERIVING
-- the manifest -- from the player's bags via deps.ownedCounts + deps.lookupByName --
-- and writes <char>\dlac\autogear.lua; the LAC-state engine hot-reloads it and
-- synthesizes band-60 rules at Midcast. Name lists are era/CatsEyeXI staples; the
-- Iridescence list is a fallback until the catalog carries the stat (issue #5).
-- ---------------------------------------------------------------------------
local ELEMENTS8 = { 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark' };
local STAFF_NQ = {
    Fire = 'Fire Staff',   Ice = 'Ice Staff',     Wind = 'Wind Staff',   Earth = 'Earth Staff',
    Thunder = 'Thunder Staff', Water = 'Water Staff', Light = 'Light Staff', Dark = 'Dark Staff',
};
local STAFF_HQ = {
    Fire = "Vulcan's Staff",  Ice = "Aquilo's Staff",   Wind = "Auster's Staff",  Earth = "Terra's Staff",
    Thunder = "Jupiter's Staff", Water = "Neptune's Staff", Light = "Apollo's Staff", Dark = "Pluto's Staff",
};
local OBI = {
    Fire = 'Karin Obi', Ice = 'Hyorin Obi', Wind = 'Furin Obi', Earth = 'Dorin Obi',
    Thunder = 'Rairin Obi', Water = 'Suirin Obi', Light = 'Korin Obi', Dark = 'Anrin Obi',
};
-- Universal obi (all elements). On CatsEyeXI the eight elemental obis don't exist --
-- Hachirin-no-obi is THE obi; the day/weather gate still applies per cast.
local OBI_UNIVERSAL = { 'Hachirin-no-obi' };
-- Universal Iridescence weapons (all elements) -> their tier. CatsEyeXI tiers:
-- elemental staves carry Iridescence for THEIR element only (NQ +1 / HQ +2);
-- these carry it for every element. Fallback list until the catalog carries the
-- Iridescence stat (issue #5); ordered check picks the highest owned tier.
local UNIVERSAL = {
    -- ordered check picks the FIRST owned: the specific +2 weapons are preferred,
    -- Chatoyant is the +2 fallback, Iridal the +1 tier.
    { name = 'Foreshadow +1',   tier = 2 },
    { name = 'Claustrum',       tier = 2 },
    { name = 'Chatoyant Staff', tier = 2 },
    { name = 'Iridal Staff',    tier = 1 },
};

-- Manifest schema version: bump when autoCommit writes NEW fields. An on-disk
-- manifest with an older fmtver self-heals (renderAutomations triggers a rescan)
-- so a dlac update never needs a manual "Rescan owned gear" click.
local AUTO_FMT = 7;   -- 2: mpBest ladders; 3: MP level-effective; 4: staves/obis job-checked; 5: craft ladders; 6: skill-up fillers in hq/nq; 7: helm ladders + hat map

local auto = { data = nil, loadedFor = nil, status = '' };

local function autoPath()
    local base = deps and deps.charBase and deps.charBase() or nil;
    return base and (base .. 'dlac\\autogear.lua') or nil;
end

local function autoLoad()
    local p = autoPath();
    if p == nil then return; end
    if auto.loadedFor == p and auto.data ~= nil then return; end
    auto.loadedFor = p;
    auto.data = {};
    pcall(function()
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then auto.data = t; end
    end);
end

-- Is this exact item name in the player's bags? (catalog/owned lookup -> Id -> count)
local function ownedRec(name)
    if deps.lookupByName == nil then return nil; end
    local rec = deps.lookupByName(name);
    if rec == nil or rec.Id == nil then return nil; end
    local oc = (deps.ownedCounts ~= nil) and deps.ownedCounts() or nil;
    if type(oc) == 'table' and (oc[rec.Id] or 0) >= 1 then return rec; end
    return nil;
end

-- Owned AND equippable by the CURRENT job -- THE automation rule (field case:
-- Foreshadow +1 sat in WHM's manifest as the universal; WHM can't wear it and
-- AutoIridescence looked dead). The manifest is per-job, so every staff/obi
-- pick passes the central eligibility check; item LEVEL is still checked live
-- by the engine at resolve time.
local function curJob()
    return (type(deps.playerJob) == 'function') and deps.playerJob() or nil;
end
local function usableRec(name, job)
    local rec = ownedRec(name);
    if rec == nil then return nil; end
    if hasDispatch and type(dsp.canWear) == 'function'
       and not dsp.canWear(rec, job, 99) then return nil; end
    return rec;
end

-- Re-derive the manifest from bags (HQ staff preferred), write it, hot-reload the engine.
-- The manifest carries GEAR DATA only; whether an automation fires is decided by the
-- SET: a dlac:AutoStaff / dlac:AutoObi virtual entry in its Main / Waist slot (Sets tab).
local function autoCommit()
    local p = autoPath();
    if p == nil then auto.status = 'not logged in.'; return; end
    -- Per-element pick: HQ staff (Iridescence +2 for its element) over NQ (+1).
    -- Every entry records its item LEVEL so the engine can skip gear the character
    -- is under-leveled for (and fall back to the slot's regular pick).
    -- Job-aware picks: gData does NOT exist in the addon state -- the job comes
    -- from Ashita memory via deps.playerJob.
    local job = curJob();
    local staff, obi, nStaff, nObi = {}, {}, 0, 0;
    for _, el in ipairs(ELEMENTS8) do
        local hq, nq = usableRec(STAFF_HQ[el], job), usableRec(STAFF_NQ[el], job);
        if hq ~= nil then staff[el] = { name = hq.Name, tier = 2, level = hq.Level or 0 }; nStaff = nStaff + 1;
        elseif nq ~= nil then staff[el] = { name = nq.Name, tier = 1, level = nq.Level or 0 }; nStaff = nStaff + 1; end
        local ob = usableRec(OBI[el], job);
        if ob ~= nil then obi[el] = { name = ob.Name, level = ob.Level or 0 }; nObi = nObi + 1; end
    end
    -- Best usable universal (highest tier first -- the list is ordered).
    local uni, uniLevel = nil, 0;
    for _, u in ipairs(UNIVERSAL) do
        local rec = usableRec(u.name, job);
        if rec ~= nil then uni = u; uniLevel = rec.Level or 0; break; end
    end
    -- Universal obi (Hachirin-no-obi): covers every element.
    local obiUni, obiUniLevel = nil, 0;
    for _, nm in ipairs(OBI_UNIVERSAL) do
        local rec = usableRec(nm, job);
        if rec ~= nil then obiUni, obiUniLevel = rec.Name, rec.Level or 0; break; end
    end
    -- Max-MP mode data: every owned piece carrying flat MP, lower(name) -> total,
    -- PLUS the best battery per equip slot (ear/ring get the top two) so the
    -- engine can EQUIP them, not just hold them. The engine can't read the
    -- catalog, so both ride this manifest.
    local mp, mpBest = {}, {};
    pcall(function()
        if type(deps.ownedList) ~= 'function' then return; end
        local counts = (type(deps.ownedCounts) == 'function') and deps.ownedCounts() or nil;
        local lvl = mainLevel();
        local bySlot = {};   -- gear-slot key -> candidates { name, mp, level }
        for _, rec in ipairs(deps.ownedList() or {}) do
            -- LEVEL-EFFECTIVE stats via THE central resolver (levelstats.effective):
            -- Tamas Ring is MP 15 on paper but 29 at Lv74. Values are a snapshot at
            -- scan-time level; the constant auto-rescans keep them fresh.
            local st = (hasLScale and type(lscale.effective) == 'function')
                and lscale.effective(rec, lvl) or rec.Stats;
            if type(st) ~= 'table' then st = nil; end
            -- Convert counts: 25 HP -> MP is +25 max MP for this mode's purposes.
            local v = (st ~= nil) and ((tonumber(st.MP) or 0) + (tonumber(st.ConvertHPtoMP) or 0)) or 0;
            if v > 0 and rec.Name ~= nil then
                local k = string.lower(rec.Name);
                if (mp[k] or 0) < v then mp[k] = v; end   -- hold map: unfiltered (worn = legal)
                -- Battery CANDIDATES use the central eligibility check (main job
                -- only; the manifest regenerates on job change) and must be in an
                -- equippable bag -- a job-illegal or stored pick would make the
                -- engine's /equip fail SILENTLY and the whole mode look dead.
                -- Job checked at level 99: the ladder may carry gear to grow into;
                -- the ENGINE picks the best rung wearable at the live level.
                local sl = tostring(rec.Slot or '');
                if sl ~= '' and sl ~= 'Main' and sl ~= 'Sub' and sl ~= 'Range'
                   and (not hasDispatch or type(dsp.canWear) ~= 'function' or dsp.canWear(rec, job, 99))
                   and (type(deps.haveInBags) ~= 'function' or deps.haveInBags(rec)) then
                    bySlot[sl] = bySlot[sl] or {};
                    local c = { name = rec.Name, mp = v, level = rec.Level or 0 };
                    table.insert(bySlot[sl], c);
                    -- A genuine duplicate (two Astral Rings) may fill BOTH paired slots.
                    if (sl == 'Ear' or sl == 'Ring') and type(counts) == 'table'
                       and rec.Id ~= nil and (counts[rec.Id] or 0) >= 2 then
                        table.insert(bySlot[sl], c);
                    end
                end
            end
        end
        -- Ladders, best first. Ear/Ring alternate into two DISJOINT ladders so
        -- one physical item can never be picked for both slots.
        local LADDER = 4;
        for sl, list in pairs(bySlot) do
            table.sort(list, function(a, b)
                if a.mp ~= b.mp then return a.mp > b.mp; end
                return a.name < b.name;
            end);
            if sl == 'Ear' or sl == 'Ring' then
                local l1, l2 = {}, {};
                for i, c in ipairs(list) do
                    local t = (i % 2 == 1) and l1 or l2;
                    if #t < LADDER then t[#t + 1] = c; end
                end
                if #l1 > 0 then mpBest[string.lower(sl) .. '1'] = l1; end
                if #l2 > 0 then mpBest[string.lower(sl) .. '2'] = l2; end
            else
                local l = {};
                for i = 1, math.min(#list, LADDER) do l[i] = list[i]; end
                mpBest[string.lower(sl)] = l;
            end
        end
    end);
    -- Craft automation data (docs/design/craft-automation.md): per SLOT, per
    -- CRAFT, per GOAL ('hq'/'nq'), a best-first ladder of owned+wearable gear.
    -- Craft-specific and universal pieces compete in ONE ladder ("the Torques
    -- in a row, then the universal"): an Artisans Torque scores for every
    -- craft, a Smiths Ring only for Smithing's nq ladder. Data-driven from
    -- catalog stats -- a catalog update + rescan picks up new server gear.
    -- Goals per Henrik: hq = raise HQ (AntiHQ gear DISQUALIFIES); nq = block
    -- HQ on purpose (crafting materials you don't want HQ'd).
    local craftBest = {};
    pcall(function()
        if type(deps.ownedList) ~= 'function' then return; end
        local CRAFTS = { 'Woodworking', 'Smithing', 'Goldsmithing', 'Clothcraft',
                         'Leathercraft', 'Bonecraft', 'Alchemy', 'Cooking' };
        local counts = (type(deps.ownedCounts) == 'function') and deps.ownedCounts() or nil;
        local lvl = mainLevel();
        local CLADDER = 3;
        local bySlot = {};   -- slotKey -> craft -> goal -> { {name, score, level}, ... }
        for _, rec in ipairs(deps.ownedList() or {}) do
            local st = (hasLScale and type(lscale.effective) == 'function')
                and lscale.effective(rec, lvl) or rec.Stats;
            local sl = tostring(rec.Slot or '');
            if type(st) == 'table' and rec.Name ~= nil and sl ~= ''
               and (not hasDispatch or type(dsp.canWear) ~= 'function' or dsp.canWear(rec, job, 99))
               and (type(deps.haveInBags) ~= 'function' or deps.haveInBags(rec)) then
                local succ  = tonumber(st.SynthSuccessRate) or 0;
                local hqr   = tonumber(st.SynthHQRate) or 0;
                local gain  = tonumber(st.SynthSkillGain) or 0;
                local mat   = tonumber(st.SynthMaterialLoss) or 0;
                local consv = tonumber(st.ConserveIngredient) or 0;
                local dup = (sl == 'Ear' or sl == 'Ring') and type(counts) == 'table'
                            and rec.Id ~= nil and (counts[rec.Id] or 0) >= 2;
                -- Skill-up items (Midras's Helm, Bonze Cape, Shapers Shawl) have
                -- no per-craft mod, so they'd only ever fill the SKILL-UP goal.
                -- Henrik wants them worn under HQ/NQ TOO -- but only as FILLERS:
                -- a real craft-skill item (Chef's Hat for HQ) must still win its
                -- slot. gain*0.3 (floored) keeps every skill-up item below the
                -- weakest craft-skill contribution (skill=1 -> 10), so it fills
                -- otherwise-empty slots and never beats real skill/HQ/anti gear.
                local gainFill = math.floor(gain * 0.3);
                for _, cr in ipairs(CRAFTS) do
                    local skill = tonumber(st[cr .. 'Skill']) or 0;
                    local anti  = tonumber(st['AntiHQ' .. cr]) or 0;
                    -- hq (Henrik): "prioritize Skill gear to break tiers" --
                    -- craft skill first, HQ+ second; anti-HQ BLOCKS the goal;
                    -- skill-up items fill empty slots (gainFill, always < skill).
                    local hqScore = (anti > 0) and 0 or (skill * 10 + hqr * 5 + succ + gainFill);
                    -- nq: the HQ block is the point; skill/success still help;
                    -- skill-up items fill empty slots (they don't affect HQ odds).
                    local nqScore = anti * 100 + skill * 3 + succ * 2 + mat + consv + gainFill;
                    -- skillup: "skill up items over skill+" -- SynthSkillGain
                    -- gear first, raw craft skill second.
                    local suScore = gain * 10 + skill * 2 + succ;
                    for goal, score in pairs({ hq = hqScore, nq = nqScore, skillup = suScore }) do
                        if score > 0 then
                            bySlot[sl] = bySlot[sl] or {};
                            bySlot[sl][cr] = bySlot[sl][cr] or {};
                            local lad = bySlot[sl][cr][goal] or {};
                            bySlot[sl][cr][goal] = lad;
                            local c = { name = rec.Name, score = score, level = rec.Level or 0 };
                            lad[#lad + 1] = c;
                            if dup then lad[#lad + 1] = c; end   -- two copies may fill both paired slots
                        end
                    end
                end
            end
        end
        for sl, crafts in pairs(bySlot) do
            for cr, goals in pairs(crafts) do
                for goal, lad in pairs(goals) do
                    table.sort(lad, function(a, b)
                        if a.score ~= b.score then return a.score > b.score; end
                        return a.name < b.name;
                    end);
                    -- Ear/Ring split into DISJOINT ladders (mpBest pattern).
                    if sl == 'Ear' or sl == 'Ring' then
                        local l1, l2 = {}, {};
                        for i, c in ipairs(lad) do
                            local t = (i % 2 == 1) and l1 or l2;
                            if #t < CLADDER then t[#t + 1] = c; end
                        end
                        for suffix, l in pairs({ ['1'] = l1, ['2'] = l2 }) do
                            if #l > 0 then
                                local key = string.lower(sl) .. suffix;
                                craftBest[key] = craftBest[key] or {};
                                craftBest[key][cr] = craftBest[key][cr] or {};
                                craftBest[key][cr][goal] = l;
                            end
                        end
                    else
                        local l = {};
                        for i = 1, math.min(#lad, CLADDER) do l[i] = lad[i]; end
                        local key = string.lower(sl);
                        craftBest[key] = craftBest[key] or {};
                        craftBest[key][cr] = craftBest[key][cr] or {};
                        craftBest[key][cr][goal] = l;
                    end
                end
            end
        end
    end);
    -- HELM gathering ladders (docs/design/helm-gear.md): per SLOT, a best-first
    -- ladder of owned+in-bags gear carrying the catalog's HELM / Surveyor stats
    -- (Surveyor-major -- fewer "nothing" results; HELM-minor -- the break-roll
    -- rating, +7.3 per point on the 33% break check), PLUS the semantic hat map
    -- (WHICH category a hat doubles is not a catalog stat -- the id block
    -- 25557-25560 is one hat per category). Stat-driven like the craft
    -- ladders: new server gear lands on the next rescan, no table to edit.
    local helmBest, helmHats = {}, {};
    pcall(function()
        if type(deps.ownedList) ~= 'function' then return; end
        local lvl = mainLevel();
        local HLADDER = 4;
        local bySlot = {};   -- slot -> { {name, score, level, helm, surv}, ... }
        for _, rec in ipairs(deps.ownedList() or {}) do
            local st = (hasLScale and type(lscale.effective) == 'function')
                and lscale.effective(rec, lvl) or rec.Stats;
            local sl = tostring(rec.Slot or '');
            if type(st) == 'table' and rec.Name ~= nil and sl ~= ''
               and (not hasDispatch or type(dsp.canWear) ~= 'function' or dsp.canWear(rec, job, 99))
               and (type(deps.haveInBags) ~= 'function' or deps.haveInBags(rec)) then
                local helm = tonumber(st.HELM) or 0;
                local surv = tonumber(st.Surveyor) or 0;
                if helm > 0 or surv > 0 then
                    bySlot[sl] = bySlot[sl] or {};
                    local lad = bySlot[sl];
                    lad[#lad + 1] = { name = rec.Name, score = surv * 10 + helm,
                                      level = rec.Level or 0, helm = helm, surv = surv };
                end
            end
        end
        for sl, lad in pairs(bySlot) do
            table.sort(lad, function(a, b)
                if a.score ~= b.score then return a.score > b.score; end
                return a.name < b.name;
            end);
            local l = {};
            for i = 1, math.min(#lad, HLADDER) do l[i] = lad[i]; end
            helmBest[string.lower(sl)] = l;
        end
        -- Owned hats only; the engine falls back to the generic head ladder
        -- (another category's hat still carries Surveyor) when one is missing.
        for g, nm in pairs({ Harvesting = 'Harv. Sun Hat', Excavation = 'Excavators Shades',
                             Logging = 'Lumberjacks Beret', Mining = 'Miners Helmet' }) do
            local rec = usableRec(nm, job);
            if rec ~= nil and (type(deps.haveInBags) ~= 'function' or deps.haveInBags(rec)) then
                local st = type(rec.Stats) == 'table' and rec.Stats or {};
                helmHats[g] = { name = rec.Name, level = rec.Level or 0,
                                surv = tonumber(st.Surveyor) or 0 };
            end
        end
    end);
    -- The crafting GOAL persisted for the trigger-set path (the manual overlay
    -- reads craftstate.lua instead). Read it from craftwatch -- NOT from
    -- CRAFT_UI, which is declared LATER in this file: referencing it here made
    -- CRAFT_UI a nil global and threw, aborting autoCommit so the manifest
    -- never regenerated (hard rule 8 -- the fmtver-5 / no-filler bug).
    local goal = 'hq';
    pcall(function()
        local cw = require('dlac\\feature\\craftwatch');
        if type(cw.getGoal) == 'function' then goal = cw.getGoal(); end
    end);
    if goal ~= 'nq' and goal ~= 'skillup' then goal = 'hq'; end
    local L = {
        '-- dlac automation manifest -- written by the GUI (Triggers tab > Automations).',
        '-- Tiered Iridescence: per-element staves (NQ +1 / HQ +2, own element only) and',
        '-- the best universal weapon (all elements). The engine picks the higher tier',
        '-- per cast; ties go to the universal. WHETHER it fires is decided by the set:',
        '-- a dlac:AutoStaff / dlac:AutoObi entry in its Main / Waist slot (Sets tab).',
        'return {',
        string.format('    fmtver = %d,', AUTO_FMT),   -- manifest schema: outdated -> auto-rescan
        string.format('    written = %q,', os.date('%Y-%m-%d %H:%M:%S')),
        string.format('    craftGoal = %q,', goal),    -- hq | nq | skillup (AutoCraft goal)
        (uni ~= nil)
            and string.format('    universal = { name = %q, tier = %d, level = %d },', uni.name, uni.tier, uniLevel)
            or  '    universal = false,',
        (obiUni ~= nil)
            and string.format('    obiUniversal = { name = %q, level = %d },', obiUni, obiUniLevel)
            or  '    obiUniversal = false,',
        '    staff = {',
    };
    for _, el in ipairs(ELEMENTS8) do
        local s = staff[el];
        if s ~= nil then
            L[#L + 1] = string.format('        %s = { name = %q, tier = %d, level = %d },', el, s.name, s.tier, s.level);
        end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    obi = {';
    for _, el in ipairs(ELEMENTS8) do
        local o = obi[el];
        if o ~= nil then
            L[#L + 1] = string.format('        %s = { name = %q, level = %d },', el, o.name, o.level);
        end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    mp = {';
    local mpKeys = {};
    for k in pairs(mp) do mpKeys[#mpKeys + 1] = k; end
    table.sort(mpKeys);
    for _, k in ipairs(mpKeys) do
        L[#L + 1] = string.format('        [%q] = %d,', k, mp[k]);
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    mpBest = {';
    local mbKeys = {};
    for k in pairs(mpBest) do mbKeys[#mbKeys + 1] = k; end
    table.sort(mbKeys);
    for _, k in ipairs(mbKeys) do
        local rungs = {};
        for _, c in ipairs(mpBest[k]) do
            rungs[#rungs + 1] = string.format('{ name = %q, mp = %d, level = %d }', c.name, c.mp, c.level);
        end
        L[#L + 1] = string.format('        %s = { %s },', k, table.concat(rungs, ', '));
    end
    L[#L + 1] = '    },';
    -- craft ladders: slotKey -> craft -> goal ('hq'/'nq') -> best-first rungs
    L[#L + 1] = '    craft = {';
    local cbKeys = {};
    for k in pairs(craftBest) do cbKeys[#cbKeys + 1] = k; end
    table.sort(cbKeys);
    for _, k in ipairs(cbKeys) do
        L[#L + 1] = string.format('        %s = {', k);
        local crs = {};
        for cr in pairs(craftBest[k]) do crs[#crs + 1] = cr; end
        table.sort(crs);
        for _, cr in ipairs(crs) do
            local parts = {};
            for _, goal in ipairs({ 'hq', 'nq', 'skillup' }) do
                local lad = craftBest[k][cr][goal];
                if lad ~= nil then
                    local rungs = {};
                    for _, c in ipairs(lad) do
                        rungs[#rungs + 1] = string.format('{ name = %q, score = %d, level = %d }',
                            c.name, c.score, c.level);
                    end
                    parts[#parts + 1] = string.format('%s = { %s }', goal, table.concat(rungs, ', '));
                end
            end
            L[#L + 1] = string.format('            %s = { %s },', cr, table.concat(parts, ', '));
        end
        L[#L + 1] = '        },';
    end
    L[#L + 1] = '    },';
    -- helm ladders: slotKey -> best-first rungs (Surveyor-major), plus the
    -- owned-hat map keyed by category (engine: dlac:AutoHelm).
    L[#L + 1] = '    helm = {';
    L[#L + 1] = '        hats = {';
    for _, g in ipairs({ 'Harvesting', 'Excavation', 'Logging', 'Mining' }) do
        local h = helmHats[g];
        if h ~= nil then
            L[#L + 1] = string.format('            %s = { name = %q, level = %d, surv = %d },',
                g, h.name, h.level, h.surv);
        end
    end
    L[#L + 1] = '        },';
    local hbKeys = {};
    for k in pairs(helmBest) do hbKeys[#hbKeys + 1] = k; end
    table.sort(hbKeys);
    for _, k in ipairs(hbKeys) do
        local rungs = {};
        for _, c in ipairs(helmBest[k]) do
            rungs[#rungs + 1] = string.format('{ name = %q, score = %d, level = %d, helm = %d, surv = %d }',
                c.name, c.score, c.level, c.helm, c.surv);
        end
        L[#L + 1] = string.format('        %s = { %s },', k, table.concat(rungs, ', '));
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '};';
    L[#L + 1] = '';
    if writeFileText(p, table.concat(L, '\n')) then
        auto.data = nil; autoLoad();   -- re-read what we just wrote
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl triggers reload'); end);
        auto.status = string.format('staves %d/8, obis %d/8%s%s -- saved, live now.', nStaff, nObi,
            (uni ~= nil) and string.format(', universal: %s (Iridescence +%d)', uni.name, uni.tier) or '',
            (obiUni ~= nil) and (', obi: ' .. obiUni .. ' (all elements)') or '');
    else
        auto.status = 'could not write ' .. p;
    end
end

-- (Flag saves regenerate the manifest via autoCommit every time -- rescanning is 16
-- name lookups, and it guarantees the manifest format/tier data is never stale.)

-- Exported for gearui's auto-sync hook: regenerate the manifest on login / job change
-- (same cadence as the gear.lua auto-sync), so the Rescan button is a manual override,
-- not a required step. Safe no-op before init / login.
function M.rescanAutogear()
    if deps == nil then return; end
    pcall(autoCommit);
    -- Same cadence as the manifest rescan (login / job change): warn about
    -- trigger-referenced gear that is parked in storage. Signature-deduped in
    -- gearcheck, so an unchanged situation stays silent.
    pcall(function() require("dlac\\gear\\gearcheck").chatWarn(false); end);
end

-- Is the on-disk manifest an older schema than this build writes? (craftwatch
-- uses this to force a regen before the engine reads stale craft ladders --
-- e.g. a fmtver-5 manifest lacks the fmtver-6 head/back skill-up fillers.)
function M.manifestStale()
    autoLoad();
    return (type(auto.data) ~= 'table') or (auto.data.fmtver ~= AUTO_FMT);
end
M.currentFmt = function() return AUTO_FMT; end

-- The Automations section (rendered under the handler sections): the manifest data +
-- rescan. The ON/OFF switches live per set (Sets tab -> Auto staff / Auto obi).
-- ---------------------------------------------------------------------------
-- Automations section, two levels: the LIST (name + KIND + a status that lights
-- up brighter the better the automation is covered; red = nothing applicable)
-- and a DETAIL box per automation (click a row; '< Automations' returns).
-- ---------------------------------------------------------------------------
local GREEN_OWNED = { 0.45, 0.90, 0.45, 1.0 };

-- status ramp, dim -> bright with coverage; 0 = red
local function levelColor(level, maxLevel)
    if level <= 0 then return { 1.00, 0.40, 0.35, 1.0 }; end
    local t = level / maxLevel;
    if t >= 0.999 then return { 0.35, 1.00, 0.45, 1.0 }; end
    if t >= 0.74  then return { 0.60, 0.90, 0.45, 1.0 }; end
    if t >= 0.49  then return { 0.85, 0.80, 0.35, 1.0 }; end
    return { 0.75, 0.62, 0.30, 1.0 };
end

local function owns(name) return ownedRec(name) ~= nil; end
local function usable(name) return usableRec(name, curJob()) ~= nil; end

-- Coverage: Iridescence 1 = any NQ elemental, 2 = any HQ elemental,
-- 3 = Iridal (+1 universal), 4 = any +2 universal. Obi: 1 elemental, 2 universal.
-- Job-aware (usable, not merely owned): the status light answers "what can THIS
-- job's automation actually do" -- an owned Foreshadow +1 must not light WHM up.
local function iridescenceLevel()
    local lv = 0;
    for _, el in ipairs(ELEMENTS8) do
        if usable(STAFF_NQ[el]) then lv = math.max(lv, 1); end
        if usable(STAFF_HQ[el]) then lv = math.max(lv, 2); end
    end
    for _, u in ipairs(UNIVERSAL) do
        if usable(u.name) then lv = math.max(lv, ((u.tier or 1) >= 2) and 4 or 3); end
    end
    return lv;
end
local function obiLevel()
    local lv = 0;
    for _, el in ipairs(ELEMENTS8) do if usable(OBI[el]) then lv = 1; break; end end
    for _, nm in ipairs(OBI_UNIVERSAL) do if usable(nm) then lv = 2; break; end end
    return lv;
end
local IRID_TXT = { [0] = 'nothing applicable', 'NQ staves', 'HQ staves', 'Iridal (+1)', 'universal +2' };
local OBI_TXT  = { [0] = 'nothing applicable', 'elemental obis', 'universal obi' };

-- One item row in a detail column: green = owned and equippable by this job,
-- red = owned but this JOB can't wear it (the automation skips it), dim = not owned.
-- synergyNote (optional): mark this item green as SYNERGIZED-INTO-ARTISANS -- you
-- must have owned every guild torque/ring to synth the Artisans piece, so owning
-- Artisans implies you had them all (Henrik).
local function autoItemLine(name, synergyNote)
    local rec = (deps.lookupByName ~= nil) and deps.lookupByName(name) or nil;
    if type(deps.renderIcon) == 'function' then deps.renderIcon(rec and rec.Id or nil, 18); end
    local owned = owns(name);
    if owned and not usable(name) then
        imgui.TextColored(COL_ERR, esc(name));
        if imgui.IsItemHovered() then
            imgui.SetTooltip(string.format('Owned -- but %s cannot equip it, so the automation skips it on this job.',
                tostring(curJob() or 'this job')));
        end
        return;
    end
    if not owned and synergyNote ~= nil then           -- implied-owned via Artisans synergy
        imgui.TextColored(GREEN_OWNED, esc(name));
        if imgui.IsItemHovered() then imgui.SetTooltip(synergyNote); end
        return;
    end
    imgui.TextColored(owned and GREEN_OWNED or COL_DIM, esc(name));
    -- The standard item card on hover, like every other gear surface.
    if rec ~= nil and imgui.IsItemHovered() and type(deps.itemTooltip) == 'function' then
        pcall(deps.itemTooltip, rec);
    end
end

local function autoColumn(title, names)
    imgui.BeginGroup();
    imgui.TextColored(COL_HEADER, title);
    for _, nm in ipairs(names) do autoItemLine(nm); end
    imgui.EndGroup();
end

-- AutoCraft panel (docs/design/craft-automation.md; layout per Henrik).
-- Names are catalog short names (the API stores them apostrophe-less); KI ids
-- from the server's own enum (scripts/enum/key_item.lua on the public repo).
-- ONE table on purpose: triggersui rides the LuaJIT 200-local chunk cap.
local CRAFT_UI = {
    order   = { 'Woodworking', 'Smithing', 'Goldsmithing', 'Clothcraft',
                'Leathercraft', 'Bonecraft', 'Alchemy', 'Cooking' },
    -- Not acquirable on CatsEyeXI (yet) -- hidden from the craft-specific
    -- lists; delete an entry here the day the server makes one obtainable.
    unobtainable = { ['Joiners Ecu'] = true, ['Smythes Ecu'] = true, ['Toreutic Ecu'] = true,
                     ['Plaiters Ecu'] = true, ['Bevelers Ecu'] = true, ['Ossifiers Ecu'] = true,
                     ['Brewers Ecu'] = true, ['Chefs Ecu'] = true },
    torque  = { Woodworking = 'Carvers Torque', Smithing = 'Smithys Torque',
                Goldsmithing = 'Goldsm. Torque', Clothcraft = 'Weavers Torque',
                Leathercraft = 'Tanners Torque', Bonecraft = 'Bone. Torque',
                Alchemy = 'Alchemst. Torque', Cooking = 'Culin. Torque' },
    nqring  = { Woodworking = 'Carpenters Ring', Smithing = 'Smiths Ring',
                Goldsmithing = 'Goldsmiths Ring', Clothcraft = 'Tailors Ring',
                Leathercraft = 'Tanners Ring', Bonecraft = 'Bonecrafters Ring',
                Alchemy = 'Alchemists Ring', Cooking = 'Chefs Ring' },
    -- Guild-point key items per craft (ids from the server's own key_item enum;
    -- ownership read from craftwatch's 0x055 tracker). Desynth (purification/
    -- ensorcellment), recipe-support skills, and the Way-of-the reward path.
    guildKI = {
        Woodworking  = { {1985,'Wood Ensorcellment'},{1986,'Lumberjack'},{1987,'Boltmaker'},{1988,'Way of the Carpenter'} },
        Smithing     = { {1992,'Metal Purification'},{1993,'Metal Ensorcellment'},{1994,'Chainwork'},{1995,'Sheeting'},{1996,'Way of the Blacksmith'} },
        Goldsmithing = { {2000,'Gold Purification'},{2001,'Gold Ensorcellment'},{2002,'Clockmaking'},{2003,'Way of the Goldsmith'} },
        Clothcraft   = { {2008,'Cloth Purification'},{2009,'Cloth Ensorcellment'},{2010,'Spinning'},{2011,'Fletching'},{2012,'Way of the Weaver'} },
        Leathercraft = { {2016,'Leather Purification'},{2017,'Leather Ensorcellment'},{2018,'Tanning'},{2019,'Way of the Tanner'} },
        Bonecraft    = { {2024,'Bone Purification'},{2025,'Bone Ensorcellment'},{2026,'Filing'},{2027,'Way of the Boneworker'} },
        Alchemy      = { {2032,'Anima Synthesis'},{2033,'Alchemic Purification'},{2034,'Alchemic Ensorcellment'},{2035,'Trituration'},{2036,'Concoction'},{2037,'Iatrochemistry'},{2038,'Miasmal Counteragent Recipe'},{2039,'Way of the Alchemist'} },
        Cooking      = { {2040,'Raw Fish Handling'},{2041,'Noodle Kneading'},{2042,'Patissier'},{2043,'Stewpot Mastery'},{2044,'Way of the Culinarian'} },
    },
    universals = { 'Kupo Shield', 'Bonze Cape', 'Shapers Shawl', 'Midrass Helm +1' },
    txt = { [0] = 'nothing applicable', 'craft-specific gear', 'Artisans (NQ)', 'Artisans +1', 'Kupo Shield' },
    selected = 'Alchemy',
    _cache = {},   -- per-craft item lists (full-catalog walk: build on demand, never per frame)
    _tex = {},     -- craft glyph textures (assets/craft/<Craft>.png), false = load failed
};

-- Set-8 craft glyphs (Henrik's pick 2026-07-13: FFXIV class icons, Miner
-- standing in for Bonecraft; PNGs ship in assets/craft/). Loaded once via
-- D3DX (statustimers' pattern); nil -> the caller falls back to item icons.
function CRAFT_UI.texture(cr)
    local t = CRAFT_UI._tex[cr];
    if t ~= nil then return (t ~= false) and t or nil; end
    CRAFT_UI._tex[cr] = false;                           -- one attempt per craft
    pcall(function()
        local ffi = require('ffi');
        local d3d8lib = require('d3d8');
        pcall(ffi.cdef,
            'HRESULT __stdcall D3DXCreateTextureFromFileA(IDirect3DDevice8* pDevice, const char* pSrcFile, IDirect3DTexture8** ppTexture);');
        local dev = d3d8lib.get_device();
        local path = string.format('%saddons\\dlac\\assets\\craft\\%s.png', AshitaCore:GetInstallPath(), cr);
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileA(dev, path, ptr) == 0 then   -- S_OK
            CRAFT_UI._tex[cr] = d3d8lib.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
        end
    end);
    local t2 = CRAFT_UI._tex[cr];
    return (t2 ~= false) and t2 or nil;
end

function CRAFT_UI.level()
    local lv = 0;
    for _, cr in ipairs(CRAFT_UI.order) do
        if owns(CRAFT_UI.torque[cr]) or owns(CRAFT_UI.nqring[cr]) then lv = 1; break; end
    end
    if owns('Artisans Torque') or owns('Artisans Ring') then lv = math.max(lv, 2); end
    if owns('Artisans Torque +1') or owns('Artisans Ring +1') then lv = math.max(lv, 3); end
    if owns('Kupo Shield') then lv = 4; end
    return lv;
end

-- Craft-specific skill+ items for one craft, from the FULL catalog (owned or
-- not -- deps.allEquipList): any item carrying <craft>Skill, excluding the
-- all-8 universals (they live in the matrix above).
function CRAFT_UI.items(cr)
    if CRAFT_UI._cache[cr] ~= nil then return CRAFT_UI._cache[cr]; end
    local out = {};
    pcall(function()
        if type(deps.allEquipList) ~= 'function' then return; end
        for _, rec in ipairs(deps.allEquipList() or {}) do
            local st = rec.Stats;
            -- skip the craft's own torque (already in the matrix) and gear the
            -- server doesn't make obtainable
            if type(st) == 'table' and rec.Name ~= nil and rec.Name ~= CRAFT_UI.torque[cr]
               and not CRAFT_UI.unobtainable[rec.Name] then
                local v = tonumber(st[cr .. 'Skill']) or 0;
                if v > 0 then
                    local nAll = 0;
                    for _, c2 in ipairs(CRAFT_UI.order) do
                        if (tonumber(st[c2 .. 'Skill']) or 0) > 0 then nAll = nAll + 1; end
                    end
                    if nAll < 8 then out[#out + 1] = { name = rec.Name, skill = v }; end
                end
            end
        end
        table.sort(out, function(a, b)
            if a.skill ~= b.skill then return a.skill > b.skill; end
            return a.name < b.name;
        end);
    end);
    CRAFT_UI._cache[cr] = out;
    return out;
end

local MP_GRID = { 'main', 'sub', 'range', 'ammo', 'head', 'neck', 'ear1', 'ear2',
                  'body', 'hands', 'ring1', 'ring2', 'back', 'waist', 'legs', 'feet' };
local MP_EXEMPT = { main = true, sub = true, range = true };

-- Resolve a manifest battery ladder to the best rung wearable at `level`
-- (mirrors the engine's dispatch.mpPick; a legacy fmtver-1 single entry
-- counts as a one-rung ladder).
local function mpPickAt(cands, level)
    if type(cands) ~= 'table' then return nil; end
    if cands.name ~= nil then cands = { cands }; end
    for _, c in ipairs(cands) do
        if type(c) == 'table' and (tonumber(c.level) or 0) <= level then return c; end
    end
    return nil;
end

-- Last frame the guild-points section rendered -- a gap >1s means the panel
-- (or the AutoCraft section) just OPENED, which triggers one fresh GP fetch.
-- Declared BEFORE renderAutomations on purpose (hard rule 8: a forward
-- reference to a later local is a silent nil global).
local _gpSectionSeen = nil;

local function renderAutomations(noHeader)
    if noHeader ~= true and not imgui.CollapsingHeader('Automations###trgsec_auto') then return; end
    autoLoad();
    -- Self-heal: an outdated-schema manifest (older dlac wrote it) regenerates
    -- itself the moment this section renders -- no manual rescan after updates.
    if auto.data ~= nil and auto.data.fmtver ~= AUTO_FMT and not auto._healed then
        auto._healed = true;
        pcall(autoCommit);
    end

    if auto.view ~= nil then                            -- DETAIL views
        if imgui.Button('< Automations##autoback', { 0, 22 }) then auto.view = nil; end
        if auto.view == 'craft' then
            -- Header controls (Henrik: right side, same row as the back button):
            -- crafting-mode picker + the auto-craft toggle.
            local cwok, cw = pcall(require, 'dlac\\feature\\craftwatch');
            cwok = cwok and type(cw) == 'table';
            -- ONE goal variable (manifest craftGoal): adopt the saved value on
            -- first render, no mode-system round-trip, no chat.
            if CRAFT_UI.goal == nil then
                local saved = (type(auto.data) == 'table') and auto.data.craftGoal or nil;
                CRAFT_UI.goal = (saved == 'nq' or saved == 'skillup') and saved or 'hq';
            end
            local GOALS = {
                { 'hq', 'HQ', 'Prioritizes craft-skill gear to break HQ tiers (then HQ+ rate).' },
                { 'nq', 'NQ', 'Wears the anti-HQ guild rings to guarantee NQ when possible\n(materials you do NOT want HQ\'d).' },
                { 'skillup', 'Skill-Up', 'Prioritizes Synth Skill+ (skill-up rate) items over raw craft skill.' },
            };
            -- On/off switch + "Show craft bar" on the right (the goal now lives
            -- ONLY on the craft bar -- removed here per Henrik). The craft
            -- glyphs below equip on click.
            local winW = imgui.GetWindowWidth();
            local on = cwok and type(cw.isEnabled) == 'function' and cw.isEnabled();
            imgui.SameLine(math.max(180, math.floor(winW / 2) - 118));   -- centered (no right-edge clip)
            imgui.TextColored(COL_DIM, 'Auto craft set:');
            imgui.SameLine(0, 6);
            local cbok, craftbar = pcall(require, 'dlac\\ui\\craftbar');
            if cbok and type(craftbar) == 'table' and type(craftbar.onOffSwitch) == 'function' then
                if craftbar.onOffSwitch(on, 'panel') and cwok then cw.setEnabled(not on); end
            else
                if imgui.Button((on and 'ON' or 'OFF') .. '##craftpanelonoff', { 46, 22 }) and cwok then cw.setEnabled(not on); end
            end
            imgui.SameLine(0, 10);
            local barOn = cwok and (cw.barVisible == true);
            if imgui.Button((barOn and 'Hide bar' or 'Show bar') .. '##craftbartoggle', { 78, 22 }) and cwok then
                cw.barVisible = not barOn;
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('The floating craft bar: on/off, the craft glyphs, and the goal.\nAlso /dl craft bar.');
            end
        end
        imgui.Spacing();
        local availW = imgui.GetContentRegionAvail();
        if type(availW) ~= 'number' or availW < 400 then availW = 800; end

        if auto.view == 'iridescence' then
            imgui.TextColored(COL_HEADER, 'AutoIridescence');
            imgui.SameLine(0, 10); imgui.TextColored(COL_DIM, 'slot automation -- dlac:AutoIridescence in a set\'s Main slot');
            imgui.Spacing();
            local nq, hq, ir1, ir2 = {}, {}, {}, {};
            for _, el in ipairs(ELEMENTS8) do nq[#nq + 1] = STAFF_NQ[el]; hq[#hq + 1] = STAFF_HQ[el]; end
            for _, u in ipairs(UNIVERSAL) do
                if (u.tier or 1) >= 2 then ir2[#ir2 + 1] = u.name; else ir1[#ir1 + 1] = u.name; end
            end
            local colW = math.max(185, math.floor(availW / 4));
            autoColumn('Elemental NQ', nq);        imgui.SameLine(colW);
            autoColumn('Elemental HQ', hq);        imgui.SameLine(colW * 2);
            autoColumn('Iridescence +1', ir1);     imgui.SameLine(colW * 3);
            autoColumn('Iridescence +2', ir2);
            imgui.Spacing();
            imgui.TextColored(COL_DIM, 'Specific +2 weapons are preferred; Chatoyant is the +2 fallback. Green = owned.');
        elseif auto.view == 'obi' then
            imgui.TextColored(COL_HEADER, 'ElementalObi');
            imgui.SameLine(0, 10); imgui.TextColored(COL_DIM, 'slot automation -- dlac:ElementalObi in a set\'s Waist slot');
            imgui.Spacing();
            local elos = {};
            for _, el in ipairs(ELEMENTS8) do elos[#elos + 1] = OBI[el]; end
            local colW = math.max(200, math.floor(availW / 2));
            autoColumn('Elemental Obis', elos);    imgui.SameLine(colW);
            autoColumn('Universal Obi', OBI_UNIVERSAL);
            imgui.Spacing();
            imgui.TextColored(COL_DIM, 'Fires only when the day/weather bonus is positive. Green = owned.');
        elseif auto.view == 'craft' then
            imgui.TextColored(COL_HEADER, 'Auto Craft Set');
            imgui.SameLine(0, 10);
            imgui.TextColored(COL_DIM, 'pick a craft + goal (here or the floating bar) -> equips your best PIECES for it. It never crafts for you.');
            imgui.Spacing();
            -- Ownership matrix (Henrik's layout): NQ|HQ pair, rule, craft-
            -- specific column -- for torques and rings; universals third.
            local colW = math.max(240, math.floor(availW / 3));
            -- Owning an Artisans piece implies you owned every guild torque/ring
            -- (they synergize into it), so mark the rest green (Henrik).
            local haveArtT = owns('Artisans Torque') or owns('Artisans Torque +1');
            local haveArtR = owns('Artisans Ring') or owns('Artisans Ring +1');
            local synT = 'Green via synergy: you own an Artisans Torque, which requires\nevery guild torque -- so you had this one.';
            local synR = 'Green via synergy: you own an Artisans Ring, which requires\nevery guild ring -- so you had this one.';
            imgui.BeginGroup();
            imgui.TextColored(COL_HEADER, 'Torques');
            autoItemLine('Artisans Torque');
            autoItemLine('Artisans Torque +1');
            imgui.TextColored(COL_DIM, '- - - - - - - -');
            for _, cr in ipairs(CRAFT_UI.order) do autoItemLine(CRAFT_UI.torque[cr], haveArtT and synT or nil); end
            imgui.EndGroup();
            imgui.SameLine(colW);
            imgui.BeginGroup();
            imgui.TextColored(COL_HEADER, 'Rings');
            autoItemLine('Artisans Ring');
            autoItemLine('Artisans Ring +1');
            imgui.TextColored(COL_DIM, '- - - - - - - -');
            for _, cr in ipairs(CRAFT_UI.order) do autoItemLine(CRAFT_UI.nqring[cr], haveArtR and synR or nil); end
            imgui.EndGroup();
            imgui.SameLine(colW * 2);
            autoColumn('Universals', CRAFT_UI.universals);
            imgui.Spacing();
            imgui.Separator();
            imgui.Spacing();
            -- Craft selector: icons only, one row left-to-right (gold box =
            -- selected, the slot-grid pattern). Item icons stand in for the
            -- synth-skill glyphs until PNG assets land; the tooltip names the
            -- craft and guild for anyone unsure.
            -- Panel icons are ONLY a section switch (Henrik): clicking one just
            -- changes which craft's items are shown below. No label -- centered,
            -- self-explanatory (8 icons * 32 + 7 gaps * 14 = 354 wide).
            local rowW = 8 * 32 + 7 * 14;
            local indent = math.max(0, math.floor((availW - rowW) / 2));
            if indent > 0 then imgui.Dummy({ 0, 0 }); imgui.SameLine(indent); end
            for i, cr in ipairs(CRAFT_UI.order) do
                local sel = (CRAFT_UI.selected == cr);
                local tex = CRAFT_UI.texture(cr);
                local drew = false;
                if tex ~= nil then
                    local okT = pcall(function()
                        local ffi = require('ffi');
                        imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { 32, 32 },
                            { 0, 0 }, { 1, 1 }, sel and { 1, 1, 1, 1 } or { 1, 1, 1, 0.45 });
                    end);
                    if not okT then
                        okT = pcall(function()
                            local ffi = require('ffi');
                            imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { 32, 32 });
                        end);
                    end
                    drew = okT;
                end
                if not drew and type(deps.renderIcon) == 'function' then   -- glyph missing: item icon
                    local rec = (deps.lookupByName ~= nil) and deps.lookupByName(CRAFT_UI.torque[cr]) or nil;
                    deps.renderIcon(rec and rec.Id or nil, 32);
                end
                if imgui.IsItemClicked() then CRAFT_UI.selected = cr; end   -- view only
                if imgui.IsItemHovered() then imgui.SetTooltip(cr .. '  -- show this craft\'s items (set the active craft on the craft bar)'); end
                if i < #CRAFT_UI.order then imgui.SameLine(0, 14); end
            end
            imgui.Spacing();
            local selCr = CRAFT_UI.selected;
            -- Guild key items for this craft (ownership from the 0x055 tracker).
            local cw2, kiSynced = nil, false;
            pcall(function()
                cw2 = require('dlac\\feature\\craftwatch');
                kiSynced = (type(cw2.kiReady) == 'function') and cw2.kiReady() or ((cw2 and cw2.kiBlocksSeen or 0) > 0);
            end);
            -- Guild points for this craft (0x113-tracked). EVERY entry into
            -- this view (section idle >1s = you just came in) asks the server
            -- for a fresh copy -- the c2s 0x10F self-request, turn-in VERIFIED
            -- 2026-07-13 -- so a GP hand-in shows here without zoning. force
            -- = skip the 5s debounce (Henrik: refresh on each visit); its 1s
            -- floor still dedupes flicker. While the view stays open the gap
            -- never exceeds a frame, so it can't re-request.
            local gp, gpReady = nil, false;
            if cw2 ~= nil then
                if _gpSectionSeen == nil or (os.clock() - _gpSectionSeen) > 1.0 then
                    pcall(function() cw2.requestGuildPoints(true); end);
                end
                _gpSectionSeen = os.clock();
                pcall(function() gpReady = (type(cw2.gpReady) == 'function') and cw2.gpReady(); end);
                pcall(function() gp = cw2.guildPointsFor(selCr); end);
            end
            imgui.TextColored(COL_HEADER, 'Guild Points: ');
            imgui.SameLine(0, 4);
            if gpReady and gp ~= nil then
                imgui.TextColored({ 0.95, 0.85, 0.45, 1.0 }, tostring(gp));
            else
                imgui.TextColored(COL_DIM, gpReady and '0' or '(open the currency menu / zone once)');
            end
            imgui.Spacing();
            imgui.TextColored(COL_HEADER, 'Guild key items:');
            if not kiSynced then imgui.SameLine(0, 6); imgui.TextColored(COL_DIM, '(zone once to sync)'); end
            local kil = CRAFT_UI.guildKI[selCr] or {};
            for i, ki in ipairs(kil) do
                local has = false;
                if cw2 ~= nil then pcall(function() has = cw2.hasKeyItem(ki[1]) == true; end); end
                local col = (not kiSynced) and COL_DIM or (has and GREEN_OWNED or COL_ERR);
                local mark = (not kiSynced) and '?' or (has and '+' or 'x');
                imgui.TextColored(col, '[' .. mark .. '] ' .. ki[2]);
                -- two per row; +30% column width so longer names never overlap
                if i % 2 == 1 and i < #kil then imgui.SameLine(300); end
            end
            imgui.Spacing();
            local its = CRAFT_UI.items(selCr);
            if #its == 0 then
                imgui.TextColored(COL_DIM, 'No ' .. selCr .. '-specific skill+ items in the catalog.');
            else
                for _, it in ipairs(its) do
                    autoItemLine(it.name);
                    imgui.SameLine(0, 8);
                    imgui.TextColored(COL_DIM, string.format('(%s +%d)', selCr, it.skill));
                end
            end
            imgui.Spacing();
            imgui.TextColored(COL_DIM, 'Green = owned; red = owned but this job can\'t wear it; dim = not owned.');
        elseif auto.view == 'helm' then
            -- The whole panel lives in ui/helmui.lua (triggersui rides the
            -- 200-local cap -- a pcall-require here adds none).
            local hok, helmui = pcall(require, 'dlac\\ui\\helmui');
            if hok and type(helmui) == 'table' and type(helmui.render) == 'function' then
                pcall(helmui.render, deps, availW);
            else
                imgui.TextColored(COL_ERR, 'helmui failed to load.');
            end
        elseif auto.view == 'maxmp' then
            imgui.TextColored(COL_HEADER, 'MaxMP');
            imgui.SameLine(0, 10); imgui.TextColored(COL_DIM, 'set automation -- /dl mode maxmp; wears batteries at a full pool, releases as spent');
            imgui.Spacing();
            local mb = (type(auto.data) == 'table' and type(auto.data.mpBest) == 'table') and auto.data.mpBest or {};
            local lvl = mainLevel();
            local total = 0;
            for i, sl in ipairs(MP_GRID) do
                local c = mpPickAt(mb[sl], lvl);
                imgui.BeginChild('##mpb_' .. sl, { 40, 40 }, true, ImGuiWindowFlags_NoScrollbar or 0);
                if c ~= nil and type(deps.renderIcon) == 'function' then
                    local rec = (deps.lookupByName ~= nil) and deps.lookupByName(c.name) or nil;
                    deps.renderIcon(rec and rec.Id or nil, 30);
                end
                imgui.EndChild();
                if imgui.IsItemHovered() then
                    if MP_EXEMPT[sl] then
                        imgui.SetTooltip(sl .. ': weapons are exempt (TP preservation).');
                    elseif c ~= nil then
                        imgui.SetTooltip(string.format('%s: %s  (MP +%d)', sl, c.name, c.mp or 0));
                    else
                        imgui.SetTooltip(sl .. ': no MP gear owned for this slot.');
                    end
                end
                if c ~= nil then total = total + (c.mp or 0); end
                if i % 4 ~= 0 then imgui.SameLine(0, 4); end
            end
            imgui.Spacing();
            imgui.TextColored((total > 0) and GREEN_OWNED or COL_ERR,
                string.format('Best case: +%d Max MP', total));
            imgui.TextColored(COL_DIM, 'Battery data maintains itself (login, job change, any inventory change).');
        end
        return;
    end

    -- LIST view: the automation table FIRST, no explanations above it (field
    -- request) -- how-it-works lives in the tooltips and detail views. The
    -- rescan shove + status sit small under the table.
    -- MaxMP is deliberately NOT listed: still unofficial, pending more field
    -- troubleshooting (/dl mode maxmp keeps working; its detail view and the
    -- manifest mp data stay intact -- re-add the row here when it graduates).
    local rows = {
        { key = 'iridescence', name = 'AutoIridescence', kind = 'slot automation (Main)',
          level = iridescenceLevel(), max = 4, txt = nil },
        { key = 'obi',         name = 'ElementalObi',    kind = 'slot automation (Waist)',
          level = obiLevel(),         max = 2, txt = nil },
        { key = 'craft',       name = 'Auto Craft Set',  kind = 'craft-gear helper (manual pick)',
          level = CRAFT_UI.level(),   max = 4, txt = nil },
        { key = 'helm',        name = 'Auto HELM Set',   kind = 'gathering-gear helper (idle only)',
          level = 0,                  max = 4, txt = nil },
    };
    rows[1].txt = IRID_TXT[rows[1].level];
    rows[2].txt = OBI_TXT[rows[2].level];
    rows[3].txt = CRAFT_UI.txt[rows[3].level];
    -- HELM coverage lives in helmui (200-local cap: pcall-require, no upvalue).
    pcall(function()
        local helmui = require('dlac\\ui\\helmui');
        rows[4].max = helmui.maxLevel or 4;
        rows[4].level, rows[4].txt = helmui.status(deps);   -- label + HELM+/Surv+ totals
    end);
    -- Column headers, same fixed offsets as the rows.
    -- Offsets widened 2026-07-17 (field report: the HELM row's Kind ran into
    -- Status): Name 190->215, Kind 470->580 (~30% more -- the themed font
    -- runs ~9.5px/char and "gathering-gear helper (idle only)" is 33 chars).
    imgui.Dummy({ 0, 0 });
    imgui.SameLine(8);   imgui.TextColored(COL_HEADER, 'Name');
    imgui.SameLine(215); imgui.TextColored(COL_HEADER, 'Kind');
    imgui.SameLine(580); imgui.TextColored(COL_HEADER, 'Status');
    imgui.Separator();
    for _, r in ipairs(rows) do
        local col = levelColor(r.level, r.max);
        imgui.PushID('autorow_' .. r.key);
        if imgui.Selectable('##sel', false, ImGuiSelectableFlags_None, { 0, 20 }) then auto.view = r.key; end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Click for details. Slot automations go INSIDE a set (add the dlac: entry\nto the slot via + Add); set automations apply everywhere via their mode.');
        end
        imgui.SameLine(8);  imgui.TextColored(col, r.name);
        imgui.SameLine(215); imgui.TextColored(COL_DIM, r.kind);
        imgui.SameLine(580); imgui.TextColored(col, r.txt or '');
        imgui.PopID();
    end
    -- No rescan button, no status line: the scan runs itself (login, job
    -- change, any inventory change, schema self-heal) and each row already
    -- reports its own state -- extra chrome earned nothing (field request).
end

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
            trig.data.Modes[nm] = { values = modeUI.values, bind = bind };
            trigSetStatus(string.format('Cycle mode "%s": wire values with the rule condition  mode = %s:<value>,  then Commit.', nm, nm), false);
        else
            if bind ~= nil then trig.data.Modes[nm] = { bind = bind };
            else trig.data.Modes[nm] = nil; end        -- toggle without a bind needs no definition
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
            local rr = modeCondRefs(nmDel, false);
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
            local rr = modeCondRefs(d.name, true);
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
};
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
                    imgui.SetTooltip('Checked against your CURRENT vitals/buffs (refreshes every second)\nwith the engine\'s own matcher. The engine re-evaluates at every dispatch.');
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
                    imgui.SetTooltip('Checked against your CURRENT vitals/buffs (refreshes every second)\nwith the engine\'s own matcher. The engine re-evaluates at every dispatch.');
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
    local editing = (trig.editIdx ~= nil);
    imgui.TextColored(COL_HEADER, (editing and 'Edit ' or 'New ') .. h .. ' rule');
    imgui.Separator();

    local defs = COND_DEFS[h] or {};

    -- 'e' on a pending row: load the condition back into the pickers and lift
    -- the row out, so a small tweak never means retype-from-scratch (Henrik).
    -- Re-add with + & or + | -- moving a condition between legs is the same
    -- motion. v53 alias spellings edit into their canonical percent params.
    local PARAM_OF = nil;
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
    else
        curLabel = (cur and (cur.label or trigPrettyKey(string.lower(cur.key)))) or '?';
    end
    if imgui.Button(curLabel .. '###trgcondbtn', { 200, 0 }) then
        trig._condDrill = false;
        imgui.OpenPopup('##trgcondmenu');
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Pick the condition type. Player cascades into the HP / MP / TP /\nbuff parameters.');
    end
    if imgui.BeginPopup('##trgcondmenu') then
        local function pickDef(di)
            trig._addDef = di; trig.addValText[1] = ''; trig._addValSel = nil; trig.addValNum[1] = 0;
        end
        if trig._condDrill and not hasMenu then
            -- Drill-down fallback: the parameter list in place, with a way back.
            imgui.TextColored(COL_HEADER, 'Player');
            if imgui.Selectable('< back##trgcback') then
                trig._condDrill = false;
            else
                imgui.Separator();
                for pi, p in ipairs(PLAYER_PARAMS) do
                    if imgui.Selectable((p.label or p.key) .. '##trgcpp' .. pi) then
                        for di, d in ipairs(defs) do
                            if d.kind == 'player' then pickDef(di); break; end
                        end
                        trig._addPlayer = pi;
                        trig._condDrill = false;
                        imgui.CloseCurrentPopup();
                    end
                    if p.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(p.hint); end
                end
            end
        else
            for di, d in ipairs(defs) do
                if d.kind == 'player' then
                    if hasMenu then
                        if imgui.BeginMenu('Player##trgcplayer') then
                            for pi, p in ipairs(PLAYER_PARAMS) do
                                if imgui.MenuItem((p.label or p.key) .. '##trgcpp' .. pi) then
                                    pickDef(di);
                                    trig._addPlayer = pi;
                                    pcall(function() imgui.CloseCurrentPopup(); end);
                                end
                                if p.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(p.hint); end
                            end
                            imgui.EndMenu();
                        end
                    else
                        if imgui.Selectable('Player  >##trgcplayer') then trig._condDrill = true; end
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
            if ck == 'player' then
                local pp = PLAYER_PARAMS[trig._addPlayer] or PLAYER_PARAMS[1];
                ckey, ck = pp.key, pp.kind;
            end
            local val;
            if ck == 'list' or ck == 'group' or ck == 'buff' then val = trig._addValSel;
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
        trig.data[h] = trig.data[h] or {};
        if editing and trig.data[h][trig.editIdx] ~= nil then
            trig.data[h][trig.editIdx] = rule;         -- replace in place (keeps file order / tie-breaks)
        else
            table.insert(trig.data[h], rule);
        end
        trig.dirty = true;
        trig.addConds = {}; trig.addSet = nil; trig.addPrio[1] = 0;
        trig.editIdx, trig._editEquip = nil, nil;
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

-- The "Import Lua Table(s)" control (G4, issue #30): a collapsible paste box that bulk-creates one
-- group per top-level key of a pasted `Name = T{...}` table. Parsing is the sandboxed pure
-- transform (groupimport.parse); collisions with an existing group require an explicit confirm
-- before overwriting (parity with "Copy from static"); a pre-import summary shows created /
-- overwritten / skipped. `groups` is the live trig.data.Groups map.
local function renderGroupImport(groups)
    if not hasGroupImport then return; end
    imgui.Spacing();
    if not imgui.CollapsingHeader('Import Lua Table(s)###grpimport') then return; end
    imgui.TextColored(COL_DIM, 'Already keep your spells grouped in a Lua table? Paste it -- one group per name.');
    imgui.TextColored(COL_DIM, "e.g.   STR_DEX = T{'Foot Kick', 'Wild Oats'},   VIT = {'Cannonball', 'Tail Slap'},");
    imgui.TextColored(COL_DIM, 'The  T  is optional; plain  {...}  works too. A nested / non-list value skips just that name.');

    if hasMultiline then
        imgui.InputTextMultiline('##grpimptext', groupUI.importText, 8192, { -1, 120 });
    else
        imgui.TextColored(COL_SCORE, '(this build has no multiline box -- keep it on ONE line; names are comma-separated)');
        imgui.PushItemWidth(-1);
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
end

-- Names that read like config/variant tables rather than spell groups -- pre-UNticked so the
-- scan's false positives (IdleVariantTable, Settings) don't import unless the player opts in.
local function looksLikeConfig(name)
    local n = tostring(name);
    return n:find('[Vv]ariant') ~= nil or n:find('[Ss]etting') ~= nil
        or n:find('[Cc]onfig') ~= nil or n:find('[Oo]ption') ~= nil or n:find('Table$') ~= nil;
end

-- The "Auto-import from my Lua file" control (Item 1): scans the character's live LuaAshitacast
-- <JOB>.lua (and its pre-profiles backup, since migration shims the live file) for group-shaped
-- tables and lists them as tick-able candidates -- pre-ticked except obvious config tables. The
-- scan is the pure groupscan.scan; import reuses the same classify / overwrite-confirm / apply as
-- the paste flow. `groups` is the live trig.data.Groups map.
local function renderGroupAutoImport(groups)
    if not hasGroupScan then return; end
    imgui.Spacing();
    if not imgui.CollapsingHeader('Auto-import from my Lua file###grpautoimp') then return; end
    imgui.TextColored(COL_DIM, 'Scan your LuaAshitacast job file for spell tables and import them as groups -- no copy-paste.');

    if imgui.Button('Scan my Lua file##grpautoscan', { 0, 24 }) then
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
    if imgui.IsItemHovered() then imgui.SetTooltip('Read your live <JOB>.lua (and its pre-profiles backup) and list every group-shaped table found.'); end

    local cands = groupUI.autoCands;
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

    -- The overwrite-confirm preview, mirroring renderGroupImport.
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

    -- Bulk fast-path: paste a whole Lua table of groups (issue #30).
    renderGroupImport(groups);
    -- Auto fast-path: scan the character's Lua file for group tables (Item 1).
    renderGroupAutoImport(groups);

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

    -- ONE section at a time: a slim nav column picks what fills the big main
    -- area -- no stacked collapsibles, no permanently-scrolling sidebar.
    trig.section = trig.section or 'Modes';
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
    for _, h in ipairs(TRIG_HANDLERS) do
        navItem(h, string.format('%s (%d)', h, #(trig.data[h] or {})));
    end
    navItem('Automations', 'Automations');
    navItem('Warnings', string.format('Warnings (%d)', warnCount));
    imgui.EndChild();
    imgui.SameLine(0, 10);

    imgui.BeginChild('##trgmain', { -1, -1 }, false);
    if trig.section == 'Modes' then
        renderModesSection(defs, modes);
    elseif trig.section == 'Groups' then
        M.renderGroups(job, level);
    elseif trig.section == 'Automations' then
        pcall(renderAutomations, true);
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
            elseif act == 'edit' then editAt = i; end
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
            trig.addFor, trig.editIdx, trig._editEquip = h, editAt, r.equip;
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
            trig._addPlayer = 1; trig.addValNum[1] = 0;
            trig._openAdd = true;
        end
        if imgui.Button('+ Add rule##trgadd_' .. h, { 0, 28 }) then
            trig.addFor = h; trig.addConds = {}; trig._addDef = 1;
            trig.addValText[1] = ''; trig._addValSel = nil; trig.addSet = nil; trig.addPrio[1] = 0;
            trig._addPlayer = 1; trig.addValNum[1] = 0;
            trig.editIdx, trig._editEquip = nil, nil;   -- fresh add, not an edit
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
