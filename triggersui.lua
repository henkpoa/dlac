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
local _lsok, lscale = pcall(require, "dlac\\levelstats");
local hasImgui    = _iok and imgui ~= nil;
local hasDispatch = _dpok and type(dsp) == 'table';
local hasLScale   = _lsok and type(lscale) == 'table';

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
        local gc = require("dlac\\gearcheck");
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
        { key = 'name',     kind = 'text', hint = 'exact ability name, e.g. Repair' },
        { key = 'mode',     kind = 'text', hint = 'a player-toggled mode must be ON' },
        { key = 'any',      kind = 'flag' },
    },
    Item = {
        { key = 'name',     kind = 'text', hint = 'exact item name, e.g. Holy Water' },
        { key = 'contains', kind = 'text', hint = 'name contains this text' },
        { key = 'mode',     kind = 'text', hint = 'a player-toggled mode must be ON' },
    },
    Weaponskill = {
        { key = 'name', kind = 'text', hint = 'exact weaponskill name' },
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

local trig = {
    data = nil, job = nil, err = nil, dirty = false,
    status = '', statusErr = false,
    addFor = nil, addConds = {}, _addDef = 1, _addValSel = nil,
    addValText = { '' }, addSet = nil, addPrio = { 0 }, _openAdd = false,
    editIdx = nil, _editEquip = nil,   -- rule-builder edit mode (replace in place)
    _openModePopup = false,
    _prioBuf = {},
    _modeState = {}, _modeStateAt = -1,
};

-- Mode builder popup state (create or edit one mode: toggle / cycle, values, bind).
local modeUI = {
    name = { '' }, kind = 'toggle', values = {}, valInput = { '' },
    bind = { '' }, set = nil, editing = nil,
};

local function trigFilePath()
    local base = deps and deps.charBase and deps.charBase() or nil;
    local abbr = nil;
    if deps and deps.jobFile then local _; _, abbr = deps.jobFile(); end
    if base == nil or abbr == nil then return nil, nil; end
    return base .. 'dlac\\triggers\\' .. abbr .. '.lua', abbr;
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

local function trigSetStatus(msg, isErr) trig.status = msg or ''; trig.statusErr = (isErr == true); end

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

-- Every set name in the profile (Dynamic + static), for the target-set dropdowns.
local function allSetNames()
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
local AUTO_FMT = 5;   -- 2: mpBest ladders; 3: MP level-effective; 4: staves/obis job-checked; 5: craft ladders

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
                for _, cr in ipairs(CRAFTS) do
                    local skill = tonumber(st[cr .. 'Skill']) or 0;
                    local anti  = tonumber(st['AntiHQ' .. cr]) or 0;
                    -- hq (Henrik): "prioritize Skill gear to break tiers" --
                    -- craft skill first, HQ+ second; anti-HQ BLOCKS the goal.
                    local hqScore = (anti > 0) and 0 or (skill * 10 + hqr * 5 + succ);
                    -- nq: the HQ block is the point; skill/success still help.
                    local nqScore = anti * 100 + skill * 3 + succ * 2 + mat + consv;
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
    -- The crafting GOAL is a single manifest field (Henrik: ONE variable, one
    -- of hq/nq/skillup selected, no mode-system chatter). The engine hot-
    -- reloads this file, so a combo click propagates silently within ~1s.
    local goal = CRAFT_UI.goal or (type(auto.data) == 'table' and auto.data.craftGoal) or 'hq';
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
    pcall(function() require("dlac\\gearcheck").chatWarn(false); end);
end

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
local function autoItemLine(name)
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
    -- Key item NAMES only: the id is resolved at runtime against the CLIENT's
    -- own key-item strings (reverse GetString lookup, the points-addon idiom).
    -- Hardcoded enum ids field-failed: the public repo's modern enum numbers
    -- don't match this server's older LSB lineage.
    ki      = { Woodworking = 'Way of the Carpenter', Smithing = 'Way of the Blacksmith',
                Goldsmithing = 'Way of the Goldsmith', Clothcraft = 'Way of the Weaver',
                Leathercraft = 'Way of the Tanner', Bonecraft = 'Way of the Boneworker',
                Alchemy = 'Way of the Alchemist', Cooking = 'Way of the Culinarian' },
    _kiId   = {},   -- resolved name -> id cache (false = not found in this client)
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
            local cwok, cw = pcall(require, 'dlac\\craftwatch');
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
            local curGoal = (cwok and type(cw.getGoal) == 'function') and cw.getGoal() or CRAFT_UI.goal;
            local goalLbl = 'HQ';
            for _, gd in ipairs(GOALS) do if gd[1] == curGoal then goalLbl = gd[2]; end end
            -- "Show craft bar": the floating manual controls (center of the row).
            local winW = imgui.GetWindowWidth();
            imgui.SameLine(math.max(180, math.floor(winW / 2) - 70));
            local barOn = cwok and (cw.barVisible == true);
            local tinted = (ImGuiCol_Button ~= nil);
            if tinted then
                imgui.PushStyleColor(ImGuiCol_Button, barOn and { 0.16, 0.55, 0.24, 1.0 } or { 0.28, 0.30, 0.36, 1.0 });
            end
            if imgui.Button((barOn and 'Craft bar: shown' or 'Show craft bar') .. '##craftbartoggle', { 150, 22 }) and cwok then
                cw.barVisible = not barOn;
            end
            if tinted then imgui.PopStyleColor(1); end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Toggle the floating craft bar: click a craft to equip its gear\nBEFORE you synth, pick the goal. Same controls as below.\nAlso /dl craft bar.');
            end
            -- Goal picker on the right edge -> craftwatch (single source of truth).
            imgui.SameLine(math.max(320, winW - 234));
            imgui.TextColored(COL_DIM, 'Goal:');
            imgui.SameLine(0, 4);
            imgui.PushItemWidth(106);   -- wide enough that 'Skill-Up' clears the combo arrow
            if imgui.BeginCombo('##craftgoalsel', goalLbl) then
                for _, gd in ipairs(GOALS) do
                    if imgui.Selectable(gd[2], curGoal == gd[1]) then
                        if cwok and type(cw.setGoal) == 'function' then cw.setGoal(gd[1]); end
                        CRAFT_UI.goal = gd[1];
                        pcall(autoCommit);   -- keep the manifest craftGoal in step for the engine/trigger path
                    end
                    if imgui.IsItemHovered() then imgui.SetTooltip(gd[3]); end
                end
                imgui.EndCombo();
            end
            imgui.PopItemWidth();
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
            imgui.BeginGroup();
            imgui.TextColored(COL_HEADER, 'Torques');
            autoItemLine('Artisans Torque');
            autoItemLine('Artisans Torque +1');
            imgui.TextColored(COL_DIM, '- - - - - - - -');
            for _, cr in ipairs(CRAFT_UI.order) do autoItemLine(CRAFT_UI.torque[cr]); end
            imgui.EndGroup();
            imgui.SameLine(colW);
            imgui.BeginGroup();
            imgui.TextColored(COL_HEADER, 'Rings');
            autoItemLine('Artisans Ring');
            autoItemLine('Artisans Ring +1');
            imgui.TextColored(COL_DIM, '- - - - - - - -');
            for _, cr in ipairs(CRAFT_UI.order) do autoItemLine(CRAFT_UI.nqring[cr]); end
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
            -- Click a craft = SELECT it for viewing AND equip its gear now
            -- (same action as the floating bar). The equipped craft (from
            -- craftwatch) shows full brightness.
            local cwact = nil;
            pcall(function() cwact = require('dlac\\craftwatch').getCraft(); end);
            imgui.TextColored(COL_HEADER, 'Click a craft to equip its gear:');
            imgui.SameLine(0, 10);
            for i, cr in ipairs(CRAFT_UI.order) do
                local sel = (CRAFT_UI.selected == cr) or (cwact == cr);
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
                if imgui.IsItemClicked() then
                    CRAFT_UI.selected = cr;
                    pcall(function() require('dlac\\craftwatch').selectCraft(cr); end);   -- equips now
                end
                if imgui.IsItemHovered() then imgui.SetTooltip(cr .. '  -- click to equip this craft\'s gear'); end
                if i < #CRAFT_UI.order then imgui.SameLine(0, 14); end
            end
            imgui.Spacing();
            local selCr = CRAFT_UI.selected;
            local kiName = CRAFT_UI.ki[selCr];
            local kiId = CRAFT_UI._kiId[kiName];
            if kiId == nil then                              -- resolve once per name, client-authoritative
                kiId = false;
                pcall(function()
                    local id = AshitaCore:GetResourceManager():GetString('keyitems.names', kiName, 2);
                    if type(id) == 'number' and id >= 0 then kiId = id; end
                end);
                CRAFT_UI._kiId[kiName] = kiId;
            end
            -- Ownership from craftwatch's 0x055 tracker (the SDK HasKeyItem
            -- memory read is dead on this client -- see craftwatch.lua).
            local hasKI, kiSynced = false, false;
            pcall(function()
                local cw2 = require('dlac\\craftwatch');
                kiSynced = (type(cw2.kiReady) == 'function') and cw2.kiReady() or ((cw2.kiBlocksSeen or 0) > 0);
                if kiId ~= false then hasKI = cw2.hasKeyItem(kiId) == true; end
            end);
            if kiId == false then
                imgui.TextColored(COL_DIM, 'Key item: ' .. kiName .. ' (unknown to this client)');
            elseif not kiSynced then
                imgui.TextColored(COL_DIM, 'Key item: ' .. kiName .. ' -- zone once to sync key items.');
            else
                imgui.TextColored(hasKI and GREEN_OWNED or COL_ERR,
                    (hasKI and 'Key item: ' or 'Key item MISSING: ') .. kiName);
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Guild-point key item -- the ' .. selCr .. ' 100 reward path (trade at Nudara, Bastok Markets).');
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
    };
    rows[1].txt = IRID_TXT[rows[1].level];
    rows[2].txt = OBI_TXT[rows[2].level];
    rows[3].txt = CRAFT_UI.txt[rows[3].level];
    -- Column headers, same fixed offsets as the rows.
    imgui.Dummy({ 0, 0 });
    imgui.SameLine(8);   imgui.TextColored(COL_HEADER, 'Name');
    imgui.SameLine(190); imgui.TextColored(COL_HEADER, 'Kind');
    imgui.SameLine(470); imgui.TextColored(COL_HEADER, 'Status');
    imgui.Separator();
    for _, r in ipairs(rows) do
        local col = levelColor(r.level, r.max);
        imgui.PushID('autorow_' .. r.key);
        if imgui.Selectable('##sel', false, ImGuiSelectableFlags_None, { 0, 20 }) then auto.view = r.key; end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Click for details. Slot automations go INSIDE a set (add the dlac: entry\nto the slot via + Add); set automations apply everywhere via their mode.');
        end
        imgui.SameLine(8);  imgui.TextColored(col, r.name);
        imgui.SameLine(190); imgui.TextColored(COL_DIM, r.kind);
        imgui.SameLine(470); imgui.TextColored(col, r.txt or '');
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
    pcall(function() gc = require("dlac\\gearcheck"); end);
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
    name = { 1.00, 0.95, 0.75, 1.0 },
    any = { 0.60, 0.60, 0.65, 1.0 },
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
    local leftH  = #lines * lh;
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
    for _, ln in ipairs(lines) do
        imgui.TextColored(COND_COLORS[ln.key] or COL_USABLE, esc(ln.text));
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

    for ci, c in ipairs(trig.addConds) do
        local txt = trigPrettyKey(string.lower(c.key)) .. ((c.value == true) and '' or (' = ' .. tostring(c.value)));
        imgui.TextColored(COL_USABLE, esc(txt));
        imgui.SameLine(0, 6);
        if imgui.SmallButton('x##trgcx' .. ci) then table.remove(trig.addConds, ci); end
    end

    local defs = COND_DEFS[h] or {};
    if trig._addDef > #defs then trig._addDef = 1; end
    local cur = defs[trig._addDef];
    imgui.PushItemWidth(130);
    if imgui.BeginCombo('##trgcondtype', (cur and trigPrettyKey(string.lower(cur.key))) or '?') then
        for di, d in ipairs(defs) do
            if imgui.Selectable(trigPrettyKey(string.lower(d.key)) .. '##trgct' .. di, trig._addDef == di) then
                trig._addDef = di; trig.addValText[1] = ''; trig._addValSel = nil;
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
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
        elseif cur.kind == 'text' then
            imgui.PushItemWidth(170);
            imgui.InputText('##trgcondtext', trig.addValText, 48);
            imgui.PopItemWidth();
            if cur.hint ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(cur.hint); end
        else
            imgui.TextColored(COL_DIM, '(flag)');
        end
        imgui.SameLine(0, 6);
        if imgui.Button('+ condition##trgac', { 0, 0 }) then
            local val;
            if cur.kind == 'list' then val = trig._addValSel;
            elseif cur.kind == 'text' then val = (trig.addValText[1] ~= '') and trig.addValText[1] or nil;
            else val = true; end
            if val ~= nil then
                local replaced = false;
                for _, c in ipairs(trig.addConds) do
                    if c.key == cur.key then c.value = val; replaced = true; break; end
                end
                if not replaced then trig.addConds[#trig.addConds + 1] = { key = cur.key, value = val }; end
                trig.addValText[1] = ''; trig._addValSel = nil;
            end
        end
        if imgui.IsItemHovered() then imgui.SetTooltip('Conditions in one rule must ALL hold (AND).\nMake separate rules to overlay (e.g. Enfeebling, then +White, then Slow).'); end
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
        local when = {};
        for _, c in ipairs(trig.addConds) do when[string.lower(c.key)] = c.value; end
        local rule = { when = when };
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
    local warnCount = 0;
    pcall(function()
        local gc = require("dlac\\gearcheck");
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
                if w > colX then colX = w; end
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
            trig.addSet = (type(r.set) == 'table') and r.set[1] or r.set;   -- builder edits ONE set; extras stay on the rule
            trig.addPrio[1] = r.priority or 0;
            trig._addDef = 1; trig.addValText[1] = ''; trig._addValSel = nil;
            trig._openAdd = true;
        end
        if imgui.Button('+ Add rule##trgadd_' .. h, { 0, 28 }) then
            trig.addFor = h; trig.addConds = {}; trig._addDef = 1;
            trig.addValText[1] = ''; trig._addValSel = nil; trig.addSet = nil; trig.addPrio[1] = 0;
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
