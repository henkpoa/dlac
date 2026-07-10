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
local hasImgui    = _iok and imgui ~= nil;
local hasDispatch = _dpok and type(dsp) == 'table';

-- Injected by gearui (M.init): charBase, jobFile, seedTriggersFile,
-- dynamicSetNames, staticSetNames, lookupByName, ownedCounts.
local deps = nil;
function M.init(d) deps = d; end

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

local TRIG_HANDLERS = { 'Default', 'Precast', 'Midcast', 'Ability', 'Item', 'Weaponskill', 'Preshot', 'Midshot' };

-- Condition metadata for the add-rule builder: per handler, the choosable condition
-- types and their value widgets. kind: 'list' = fixed dropdown, 'text' = free text,
-- 'flag' = boolean true. Vocabulary mirrors dispatch.lua's MATCHERS (v1).
local SPELL_CONDS = {
    { key = 'skill',     kind = 'list', items = { 'Divine Magic', 'Healing Magic', 'Enhancing Magic', 'Enfeebling Magic', 'Elemental Magic', 'Dark Magic', 'Summoning', 'Ninjutsu', 'Singing', 'Blue Magic', 'Geomancy' } },
    { key = 'magicType', kind = 'list', items = { 'White Magic', 'Black Magic', 'Bard Song', 'Ninjutsu', 'Summoning', 'Blue Magic' } },
    { key = 'element',   kind = 'list', items = { 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark', 'Non-Elemental' } },
    { key = 'songType',  kind = 'list', items = { 'Buff', 'Debuff' } },
    { key = 'family',    kind = 'text', hint = 'name fragment: "Minuet" matches every tier' },
    { key = 'name',      kind = 'text', hint = 'exact spell name, e.g. Slow II' },
    { key = 'dayWeatherBonus', kind = 'flag' },
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
        { key = 'family', kind = 'text', hint = 'name fragment' },
        { key = 'name',   kind = 'text', hint = 'exact ability name, e.g. Repair' },
        { key = 'any',    kind = 'flag' },
    },
    Item = {
        { key = 'name',   kind = 'text', hint = 'exact item name, e.g. Holy Water' },
        { key = 'family', kind = 'text', hint = 'name fragment' },
    },
    Weaponskill = {
        { key = 'name', kind = 'text', hint = 'exact weaponskill name' },
        { key = 'any',  kind = 'flag' },
    },
    Preshot = { { key = 'any', kind = 'flag' } },
    Midshot = { { key = 'any', kind = 'flag' } },
};

local trig = {
    data = nil, job = nil, err = nil, dirty = false,
    status = '', statusErr = false,
    addFor = nil, addConds = {}, _addDef = 1, _addValSel = nil,
    addValText = { '' }, addSet = nil, addPrio = { 0 }, _openAdd = false,
    modeName = { '' }, modeSet = nil,
    _prioBuf = {},
    _modeState = {}, _modeStateAt = -1,
};

local function trigFilePath()
    local base = deps and deps.charBase and deps.charBase() or nil;
    local abbr = nil;
    if deps and deps.jobFile then local _; _, abbr = deps.jobFile(); end
    if base == nil or abbr == nil then return nil, nil; end
    return base .. 'dlac\\triggers\\' .. abbr .. '.lua', abbr;
end

-- Load the trigger file into the edit model. Canonical handler keys; condition keys
-- are stored lowercased internally (serializeTriggers restores the display spelling).
local function trigLoad(force)
    local path, abbr = trigFilePath();
    if path == nil then trig.data, trig.job, trig.err = nil, nil, 'not logged in / unknown job'; return; end
    if not force and trig.job == abbr and trig.data ~= nil then return; end
    trig.job, trig.data, trig.err, trig.dirty, trig._prioBuf = abbr, nil, nil, false, {};
    if not hasDispatch then trig.err = 'dispatch module unavailable'; return; end
    local raw, err = dsp.readTriggersRaw(path);
    if raw == nil then trig.err = err; return; end
    local data = {};
    for k, v in pairs(raw) do
        local ev = (type(dsp.canonEvent) == 'function') and dsp.canonEvent(k) or nil;
        if ev ~= nil and type(v) == 'table' then
            local list = data[ev] or {};
            for _, r in ipairs(v) do
                if type(r) == 'table' and type(r.when) == 'table'
                   and (r.set ~= nil or type(r.equip) == 'table') then
                    local when = {};
                    for ck, cv in pairs(r.when) do when[string.lower(tostring(ck))] = cv; end
                    list[#list + 1] = {
                        when = when,
                        set = (r.set ~= nil) and tostring(r.set) or nil,
                        equip = (type(r.equip) == 'table') and r.equip or nil,
                        priority = tonumber(r.priority),
                    };
                end
            end
            data[ev] = list;
        end
    end
    trig.data = data;
end

local function trigSetStatus(msg, isErr) trig.status = msg or ''; trig.statusErr = (isErr == true); end

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

-- Mode display state: the LAC-state engine mirrors its session flags to
-- <char>\dlac\modestate.lua on every change; re-read at most once per second.
local function trigModeState()
    local now = os.time();
    if now == trig._modeStateAt then return trig._modeState; end
    trig._modeStateAt = now;
    local st = {};
    pcall(function()
        local base = deps.charBase();
        if base == nil then return; end
        local chunk = loadfile(base .. 'dlac\\modestate.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then st = t; end
    end);
    trig._modeState = st;
    return st;
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
-- Universal Iridescence weapons (all elements) -> their tier. CatsEyeXI tiers:
-- elemental staves carry Iridescence for THEIR element only (NQ +1 / HQ +2);
-- these carry it for every element. Fallback list until the catalog carries the
-- Iridescence stat (issue #5); ordered check picks the highest owned tier.
local UNIVERSAL = {
    { name = 'Chatoyant Staff', tier = 2 },
    { name = 'Foreshadow +1',   tier = 2 },
    { name = 'Claustrum',       tier = 2 },
    { name = 'Iridal Staff',    tier = 1 },
};

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

-- Re-derive the manifest from bags (HQ staff preferred), write it, hot-reload the engine.
-- The manifest carries GEAR DATA only; whether an automation fires is a per-set flag
-- (SetOptions in the trigger file, edited from the Sets tab via M.renderSetOptions).
local function autoCommit()
    local p = autoPath();
    if p == nil then auto.status = 'not logged in.'; return; end
    -- Per-element pick: HQ staff (Iridescence +2 for its element) over NQ (+1).
    local staff, obi, nStaff, nObi = {}, {}, 0, 0;
    for _, el in ipairs(ELEMENTS8) do
        local hq, nq = ownedRec(STAFF_HQ[el]), ownedRec(STAFF_NQ[el]);
        if hq ~= nil then staff[el] = { name = hq.Name, tier = 2 }; nStaff = nStaff + 1;
        elseif nq ~= nil then staff[el] = { name = nq.Name, tier = 1 }; nStaff = nStaff + 1; end
        local ob = ownedRec(OBI[el]);
        if ob ~= nil then obi[el] = ob.Name; nObi = nObi + 1; end
    end
    -- Best owned universal (highest tier first -- the list is ordered).
    local uni = nil;
    for _, u in ipairs(UNIVERSAL) do
        if ownedRec(u.name) ~= nil then uni = u; break; end
    end
    local L = {
        '-- dlac automation manifest -- written by the GUI (Triggers tab > Automations).',
        '-- Tiered Iridescence: per-element staves (NQ +1 / HQ +2, own element only) and',
        '-- the best universal weapon (all elements). The engine picks the higher tier',
        '-- per cast; ties go to the universal. WHETHER it fires is per set: SetOptions',
        '-- in triggers\\<JOB>.lua (Sets tab).',
        'return {',
        (uni ~= nil)
            and string.format('    universal = { name = %q, tier = %d },', uni.name, uni.tier)
            or  '    universal = false,',
        '    staff = {',
    };
    for _, el in ipairs(ELEMENTS8) do
        local s = staff[el];
        if s ~= nil then L[#L + 1] = string.format('        %s = { name = %q, tier = %d },', el, s.name, s.tier); end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    obi = {';
    for _, el in ipairs(ELEMENTS8) do
        if obi[el] ~= nil then L[#L + 1] = string.format('        %s = %q,', el, obi[el]); end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '};';
    L[#L + 1] = '';
    if writeFileText(p, table.concat(L, '\n')) then
        auto.data = nil; autoLoad();   -- re-read what we just wrote
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl triggers reload'); end);
        auto.status = string.format('staves %d/8, obis %d/8%s -- saved, live now.', nStaff, nObi,
            (uni ~= nil) and string.format(', universal: %s (Iridescence +%d)', uni.name, uni.tier) or '');
    else
        auto.status = 'could not write ' .. p;
    end
end

-- (Flag saves regenerate the manifest via autoCommit every time -- rescanning is 16
-- name lookups, and it guarantees the manifest format/tier data is never stale.)

-- The Automations section (rendered under the handler sections): the manifest data +
-- rescan. The ON/OFF switches live per set (Sets tab -> Auto staff / Auto obi).
local function renderAutomations()
    if not imgui.CollapsingHeader('Automations###trgsec_auto') then return; end
    autoLoad();
    imgui.PushTextWrapPos(0.0);
    imgui.TextColored(COL_DIM, 'Auto staff / auto obi are PER-SET settings: Sets tab -> pick a set -> tick "Auto staff" and/or "Auto obi". When ANY trigger equips a flagged set, the engine overlays the best Iridescence staff in Main (highest tier per cast: HQ elemental +2 / NQ +1 for the spell\'s element vs your universal weapon; ties go to the universal, which also covers elementless actions) and/or the matching obi in Waist when the day/weather bonus is positive. Priority 60: beats name-specific sets, loses to Modes.');
    imgui.PopTextWrapPos();
    if imgui.Button('Rescan owned gear##trgautorescan', { 0, 20 }) then autoCommit(); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Re-detect owned staves / obis / Iridescence weapons from your bags and save the manifest.');
    end
    if auto.status ~= '' then
        imgui.PushTextWrapPos(0.0);
        imgui.TextColored(COL_SCORE, esc(auto.status));
        imgui.PopTextWrapPos();
    end
    local d = auto.data or {};
    local function nkeys(t) local n = 0; if type(t) == 'table' then for _ in pairs(t) do n = n + 1; end end return n; end
    local uniTxt = '';
    if type(d.universal) == 'table' and type(d.universal.name) == 'string' then
        uniTxt = string.format(', universal: %s (Iridescence +%d)', d.universal.name, tonumber(d.universal.tier) or 1);
    elseif type(d.iridescence) == 'string' then
        uniTxt = ', universal: ' .. d.iridescence .. ' (old manifest -- Rescan to pick up tiers)';
    end
    imgui.TextColored(COL_DIM, string.format('detected: %d staves, %d obis%s',
        nkeys(d.staff), nkeys(d.obi), uniTxt));
end

-- ---------------------------------------------------------------------------
-- Per-set automation flags -- rendered INSIDE the Sets tab (gearui calls
-- M.renderSetOptions(setName)). Stored in the trigger file's SetOptions section;
-- saved instantly on toggle (read-modify-write of the ON-DISK rules, so unsaved
-- Triggers-tab edits are neither committed nor lost) and hot-reloaded.
-- ---------------------------------------------------------------------------
local setOptUI = { name = nil, staff = { false }, obi = { false }, status = '', err = false };

local function loadSetOptions(setName)
    if setOptUI.name == setName then return; end
    setOptUI.name, setOptUI.status, setOptUI.err = setName, '', false;
    setOptUI.staff[1], setOptUI.obi[1] = false, false;
    local path = trigFilePath();
    if path == nil or not hasDispatch then return; end
    local raw = dsp.readTriggersRaw(path);
    local so = (type(raw) == 'table') and (raw.SetOptions or raw.setOptions) or nil;
    local o = (type(so) == 'table') and so[setName] or nil;
    if type(o) == 'table' then
        setOptUI.staff[1] = (o.staff == true);
        setOptUI.obi[1]   = (o.obi == true);
    end
end

local function saveSetOptions(setName)
    local path = trigFilePath();
    if path == nil or not hasDispatch then setOptUI.status, setOptUI.err = 'no trigger file path', true; return; end
    local raw = dsp.readTriggersRaw(path);
    if type(raw) ~= 'table' then raw = {}; end
    local so = raw.SetOptions;
    if type(so) ~= 'table' then so = {}; end
    raw.SetOptions, raw.setOptions = so, nil;
    if setOptUI.staff[1] == true or setOptUI.obi[1] == true then
        so[setName] = { staff = (setOptUI.staff[1] == true), obi = (setOptUI.obi[1] == true) };
    else
        so[setName] = nil;                              -- both off -> drop the entry
    end
    local text;
    local ok = pcall(function() text = dsp.serializeTriggers(raw); end);
    if not ok or type(text) ~= 'string' then setOptUI.status, setOptUI.err = 'serialize failed', true; return; end
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then
            ashita.fs.create_directory(deps.charBase() .. 'dlac\\triggers\\');
        end
    end);
    if not writeFileText(path, text) then setOptUI.status, setOptUI.err = 'could not write ' .. path, true; return; end
    autoCommit();                                        -- regenerate the gear manifest (never stale)
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl triggers reload'); end);
    if not trig.dirty then trigLoad(true); end           -- keep the Triggers tab in sync (never clobber edits)
    setOptUI.status, setOptUI.err = 'saved -- live', false;
end

-- Two checkboxes for the Sets tab. Safe no-op without imgui/deps/a set name.
function M.renderSetOptions(setName)
    if not hasImgui or deps == nil or setName == nil or setName == '' then return; end
    loadSetOptions(setName);
    imgui.TextColored(COL_DIM, 'Automation:');
    imgui.SameLine(0, 6);
    local changed = false;
    if imgui.Checkbox('Auto staff##setopt_staff', setOptUI.staff) then changed = true; end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('When any trigger equips this set, also equip the best Iridescence staff in Main:\nhighest tier wins per cast -- HQ elemental staff +2 / NQ +1 (own element only) vs a\nuniversal weapon (Chatoyant/Foreshadow +1 = +2 all elements, Iridal Staff = +1); ties\ngo to the universal, and it also covers elementless actions (abilities).\nSaved instantly -- live, no reload.');
    end
    imgui.SameLine(0, 12);
    if imgui.Checkbox('Auto obi##setopt_obi', setOptUI.obi) then changed = true; end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('When any trigger equips this set AND the day/weather bonus for the spell\'s\nelement is positive, also equip the matching obi in Waist. Saved instantly.');
    end
    if changed then saveSetOptions(setName); end
    if setOptUI.status ~= '' then
        imgui.SameLine(0, 10);
        imgui.TextColored(setOptUI.err and COL_ERR or COL_SCORE, esc(setOptUI.status));
    end
end

-- One rule row: [x] condition -> set-dropdown  prio [n] [auto]. Returns 'remove' on delete.
local function renderTrigRuleRow(h, i, r, setNames)
    local id = h .. '_' .. tostring(i);
    local act = nil;
    if imgui.SmallButton('x##trgdel' .. id) then act = 'remove'; end
    if imgui.IsItemHovered() then imgui.SetTooltip('Remove this rule.'); end
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_USABLE, esc(condSummary(r.when)));
    imgui.SameLine(0, 8); imgui.TextColored(COL_DIM, '->'); imgui.SameLine(0, 8);
    if r.equip ~= nil then
        local parts = {};
        for slot, item in pairs(r.equip) do parts[#parts + 1] = tostring(slot) .. '=' .. tostring(item); end
        table.sort(parts);
        imgui.TextColored(COL_SCORE, esc('{ ' .. table.concat(parts, ', ') .. ' }'));
    else
        imgui.PushItemWidth(150);
        if imgui.BeginCombo('##trgset' .. id, r.set or '(pick set)') then
            for _, nm in ipairs(setNames) do
                if imgui.Selectable(nm .. '##trgso' .. id, r.set == nm) then
                    if r.set ~= nm then r.set = nm; trig.dirty = true; end
                end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
    end
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_DIM, 'prio'); imgui.SameLine(0, 3);
    local eff = r.priority
        or ((hasDispatch and type(dsp.defaultPriority) == 'function') and dsp.defaultPriority(r.when) or 10);
    local b = trig._prioBuf[id];
    if b == nil or b.was ~= eff then b = { v = { eff }, was = eff }; trig._prioBuf[id] = b; end
    imgui.PushItemWidth(52);
    if imgui.InputInt('##trgprio' .. id, b.v, 0) then
        local nv = tonumber(b.v[1]);
        if nv ~= nil and nv ~= eff then r.priority = nv; b.was = nv; trig.dirty = true; end
    end
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Priority: every matching rule applies, lowest first -- higher overlays lower.\nAuto-set from specificity; type a number to override.');
    end
    if r.priority ~= nil then
        imgui.SameLine(0, 3);
        if imgui.SmallButton('auto##trgau' .. id) then r.priority = nil; trig._prioBuf[id] = nil; trig.dirty = true; end
        if imgui.IsItemHovered() then imgui.SetTooltip('Back to the automatic (specificity) priority.'); end
    end
    return act;
end

-- Add-rule popup: build conditions (type + value, [+ condition] to AND more), pick the
-- target set, optional priority, Add.
local function renderTrigAddPopup()
    if not imgui.BeginPopup('##dlac_trigadd') then return; end
    local h = trig.addFor;
    if h == nil then imgui.EndPopup(); return; end
    imgui.TextColored(COL_HEADER, 'New ' .. h .. ' rule');
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
    if imgui.BeginCombo('##trgaddset', trig.addSet or '(pick set)') then
        for _, nm in ipairs(allSetNames()) do
            if imgui.Selectable(nm .. '##trgaso', trig.addSet == nm) then trig.addSet = nm; end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, 8); imgui.TextColored(COL_DIM, 'prio (0 = auto)'); imgui.SameLine(0, 3);
    imgui.PushItemWidth(52); imgui.InputInt('##trgaddprio', trig.addPrio, 0); imgui.PopItemWidth();
    imgui.SameLine(0, 8);
    local can = (#trig.addConds > 0) and (trig.addSet ~= nil);
    if imgui.Button('Add rule##trgaddgo', { 0, 0 }) and can then
        local when = {};
        for _, c in ipairs(trig.addConds) do when[string.lower(c.key)] = c.value; end
        local rule = { when = when, set = trig.addSet };
        if (tonumber(trig.addPrio[1]) or 0) > 0 then rule.priority = trig.addPrio[1]; end
        trig.data[h] = trig.data[h] or {};
        table.insert(trig.data[h], rule);
        trig.dirty = true;
        trig.addConds = {}; trig.addSet = nil; trig.addPrio[1] = 0;
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

    -- Modes strip: every mode referenced by a Default rule gets a live toggle button.
    local modes, mseen = {}, {};
    for _, r in ipairs(trig.data.Default or {}) do
        local m = r.when and r.when.mode;
        if type(m) == 'string' and not mseen[string.lower(m)] then
            mseen[string.lower(m)] = true; modes[#modes + 1] = m;
        end
    end
    table.sort(modes);
    imgui.TextColored(COL_DIM, 'Modes:');
    local mstate = trigModeState();
    if #modes == 0 then imgui.SameLine(0, 6); imgui.TextColored(COL_DIM, '(none yet)'); end
    for _, m in ipairs(modes) do
        imgui.SameLine(0, 6);
        local on = (mstate[string.lower(m)] == true);
        local styled = (ImGuiCol_Button ~= nil);
        if styled then
            imgui.PushStyleColor(ImGuiCol_Button, on and { 0.15, 0.55, 0.20, 1.0 } or { 0.35, 0.35, 0.40, 1.0 });
        end
        if imgui.Button(string.format('%s: %s##trgmode_%s', m, on and 'ON' or 'off', m), { 0, 22 }) then
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl mode ' .. m .. ' toggle'); end);
            trig._modeStateAt = -1;   -- pick up the new state promptly
        end
        if styled then imgui.PopStyleColor(1); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Toggle this mode (also macro-able: /dl mode ' .. m .. ').'); end
    end
    imgui.SameLine(0, 14);
    imgui.PushItemWidth(80); imgui.InputText('##trgnewmode', trig.modeName, 24); imgui.PopItemWidth();
    imgui.SameLine(0, 3);
    imgui.PushItemWidth(130);
    if imgui.BeginCombo('##trgnewmodeset', trig.modeSet or '(set)') then
        for _, nm in ipairs(allSetNames()) do
            if imgui.Selectable(nm .. '##trgnms', trig.modeSet == nm) then trig.modeSet = nm; end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, 3);
    if imgui.Button('+ Mode##trgaddmode', { 0, 22 }) then
        local nm = trig.modeName[1];
        if nm ~= nil and nm ~= '' and trig.modeSet ~= nil then
            trig.data.Default = trig.data.Default or {};
            table.insert(trig.data.Default, { when = { mode = nm }, set = trig.modeSet });
            trig.dirty = true; trig.modeName[1] = ''; trig.modeSet = nil;
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Name a mode and pick the set it overlays (priority 100 -- beats everything).\nExample: DT -> your damage-taken set. Commit to make it live.');
    end
    imgui.Separator();

    -- Handler sections: one collapsible list of rules per Handle* event.
    imgui.BeginChild('##trgsections', { -1, -1 }, false);
    local setNames = allSetNames();
    for _, h in ipairs(TRIG_HANDLERS) do
        local list = trig.data[h] or {};
        if imgui.CollapsingHeader(string.format('%s (%d)###trgsec_%s', h, #list, h)) then
            local removeAt = nil;
            for i, r in ipairs(list) do
                if renderTrigRuleRow(h, i, r, setNames) == 'remove' then removeAt = i; end
            end
            if removeAt ~= nil then
                table.remove(list, removeAt);
                trig.data[h] = list;
                trig.dirty = true;
                trig._prioBuf = {};   -- row ids shifted; rebuild the priority buffers
            end
            if imgui.Button('+ Add rule##trgadd_' .. h, { 0, 20 }) then
                trig.addFor = h; trig.addConds = {}; trig._addDef = 1;
                trig.addValText[1] = ''; trig._addValSel = nil; trig.addSet = nil; trig.addPrio[1] = 0;
                trig._openAdd = true;
            end
            imgui.Spacing();
        end
    end
    pcall(renderAutomations);   -- Automations section (auto staff / obi, ADR 0004)
    imgui.EndChild();

    if trig._openAdd then imgui.OpenPopup('##dlac_trigadd'); trig._openAdd = false; end
    renderTrigAddPopup();
end

return M;
