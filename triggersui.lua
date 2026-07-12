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

local TRIG_HANDLERS = { 'Default', 'Precast', 'Midcast', 'Ability', 'Item', 'Weaponskill', 'Preshot', 'Midshot' };

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
                            (r.set ~= nil) and ('set ' .. tostring(r.set)) or 'equip { ... }');
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
local AUTO_FMT = 3;   -- 2: mpBest ladders + Convert counted; 3: MP values level-effective (Tamas)

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
-- The manifest carries GEAR DATA only; whether an automation fires is decided by the
-- SET: a dlac:AutoStaff / dlac:AutoObi virtual entry in its Main / Waist slot (Sets tab).
local function autoCommit()
    local p = autoPath();
    if p == nil then auto.status = 'not logged in.'; return; end
    -- Per-element pick: HQ staff (Iridescence +2 for its element) over NQ (+1).
    -- Every entry records its item LEVEL so the engine can skip gear the character
    -- is under-leveled for (and fall back to the slot's regular pick).
    local staff, obi, nStaff, nObi = {}, {}, 0, 0;
    for _, el in ipairs(ELEMENTS8) do
        local hq, nq = ownedRec(STAFF_HQ[el]), ownedRec(STAFF_NQ[el]);
        if hq ~= nil then staff[el] = { name = hq.Name, tier = 2, level = hq.Level or 0 }; nStaff = nStaff + 1;
        elseif nq ~= nil then staff[el] = { name = nq.Name, tier = 1, level = nq.Level or 0 }; nStaff = nStaff + 1; end
        local ob = ownedRec(OBI[el]);
        if ob ~= nil then obi[el] = { name = ob.Name, level = ob.Level or 0 }; nObi = nObi + 1; end
    end
    -- Best owned universal (highest tier first -- the list is ordered).
    local uni, uniLevel = nil, 0;
    for _, u in ipairs(UNIVERSAL) do
        local rec = ownedRec(u.name);
        if rec ~= nil then uni = u; uniLevel = rec.Level or 0; break; end
    end
    -- Universal obi (Hachirin-no-obi): covers every element.
    local obiUni, obiUniLevel = nil, 0;
    for _, nm in ipairs(OBI_UNIVERSAL) do
        local rec = ownedRec(nm);
        if rec ~= nil then obiUni, obiUniLevel = rec.Name, rec.Level or 0; break; end
    end
    -- Max-MP mode data: every owned piece carrying flat MP, lower(name) -> total,
    -- PLUS the best battery per equip slot (ear/ring get the top two) so the
    -- engine can EQUIP them, not just hold them. The engine can't read the
    -- catalog, so both ride this manifest.
    local mp, mpBest = {}, {};
    pcall(function()
        if type(deps.ownedList) ~= 'function' then return; end
        -- gData does NOT exist in the addon state -- the job comes from Ashita
        -- memory via deps.playerJob (nil job would pass only Jobs={'All'} gear).
        local job = (type(deps.playerJob) == 'function') and deps.playerJob() or nil;
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
    local L = {
        '-- dlac automation manifest -- written by the GUI (Triggers tab > Automations).',
        '-- Tiered Iridescence: per-element staves (NQ +1 / HQ +2, own element only) and',
        '-- the best universal weapon (all elements). The engine picks the higher tier',
        '-- per cast; ties go to the universal. WHETHER it fires is decided by the set:',
        '-- a dlac:AutoStaff / dlac:AutoObi entry in its Main / Waist slot (Sets tab).',
        'return {',
        string.format('    fmtver = %d,', AUTO_FMT),   -- manifest schema: outdated -> auto-rescan
        string.format('    written = %q,', os.date('%Y-%m-%d %H:%M:%S')),
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

-- Coverage: Iridescence 1 = any NQ elemental, 2 = any HQ elemental,
-- 3 = Iridal (+1 universal), 4 = any +2 universal. Obi: 1 elemental, 2 universal.
local function iridescenceLevel()
    local lv = 0;
    for _, el in ipairs(ELEMENTS8) do
        if owns(STAFF_NQ[el]) then lv = math.max(lv, 1); end
        if owns(STAFF_HQ[el]) then lv = math.max(lv, 2); end
    end
    for _, u in ipairs(UNIVERSAL) do
        if owns(u.name) then lv = math.max(lv, ((u.tier or 1) >= 2) and 4 or 3); end
    end
    return lv;
end
local function obiLevel()
    local lv = 0;
    for _, el in ipairs(ELEMENTS8) do if owns(OBI[el]) then lv = 1; break; end end
    for _, nm in ipairs(OBI_UNIVERSAL) do if owns(nm) then lv = 2; break; end end
    return lv;
end
local IRID_TXT = { [0] = 'nothing applicable', 'NQ staves', 'HQ staves', 'Iridal (+1)', 'universal +2' };
local OBI_TXT  = { [0] = 'nothing applicable', 'elemental obis', 'universal obi' };

-- One item row in a detail column: icon + name, green when owned, dim when not.
local function autoItemLine(name)
    local rec = (deps.lookupByName ~= nil) and deps.lookupByName(name) or nil;
    if type(deps.renderIcon) == 'function' then deps.renderIcon(rec and rec.Id or nil, 18); end
    imgui.TextColored(owns(name) and GREEN_OWNED or COL_DIM, esc(name));
end

local function autoColumn(title, names)
    imgui.BeginGroup();
    imgui.TextColored(COL_HEADER, title);
    for _, nm in ipairs(names) do autoItemLine(nm); end
    imgui.EndGroup();
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

    -- LIST view
    imgui.PushTextWrapPos(0.0);
    imgui.TextColored(COL_DIM, 'Slot automations live INSIDE a set (add the dlac: entry to the slot via + Add); set automations apply across every set via their mode. Click an automation for details.');
    imgui.PopTextWrapPos();
    local written = (type(auto.data) == 'table' and type(auto.data.written) == 'string') and auto.data.written or nil;
    imgui.TextColored(COL_DIM, 'Gear data maintains itself (login, job change, any inventory change'
        .. (written ~= nil and (') -- last scan: ' .. written) or ')'));
    imgui.SameLine(0, 10);
    if imgui.SmallButton('rescan now##trgautorescan') then autoCommit(); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Normally never needed -- the scan runs automatically. This is a\ntroubleshooting shove: re-detect staves / obis / MP batteries right now.');
    end
    if auto.status ~= '' then
        imgui.PushTextWrapPos(0.0);
        imgui.TextColored(COL_SCORE, esc(auto.status));
        imgui.PopTextWrapPos();
    end
    imgui.Spacing();

    local mpTotal = 0;
    if type(auto.data) == 'table' and type(auto.data.mpBest) == 'table' then
        local lvl = mainLevel();
        for _, cands in pairs(auto.data.mpBest) do
            local c = mpPickAt(cands, lvl);
            if c ~= nil then mpTotal = mpTotal + (tonumber(c.mp) or 0); end
        end
    end
    local rows = {
        { key = 'iridescence', name = 'AutoIridescence', kind = 'slot automation (Main)',
          level = iridescenceLevel(), max = 4, txt = nil },
        { key = 'obi',         name = 'ElementalObi',    kind = 'slot automation (Waist)',
          level = obiLevel(),         max = 2, txt = nil },
        { key = 'maxmp',       name = 'MaxMP',           kind = 'set automation (/dl mode maxmp)',
          level = (mpTotal > 0) and 1 or 0, max = 1,
          txt = (mpTotal > 0) and string.format('+%d Max MP', mpTotal) or 'nothing applicable' },
    };
    rows[1].txt = IRID_TXT[rows[1].level];
    rows[2].txt = OBI_TXT[rows[2].level];
    for _, r in ipairs(rows) do
        local col = levelColor(r.level, r.max);
        imgui.PushID('autorow_' .. r.key);
        if imgui.Selectable('##sel', false, ImGuiSelectableFlags_None, { 0, 20 }) then auto.view = r.key; end
        imgui.SameLine(8);  imgui.TextColored(col, r.name);
        imgui.SameLine(190); imgui.TextColored(COL_DIM, r.kind);
        imgui.SameLine(470); imgui.TextColored(col, r.txt or '');
        imgui.PopID();
    end
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
        if imgui.BeginCombo('##modeset', modeUI.set or '(none)') then
            if imgui.Selectable('(none)##modesetnone', modeUI.set == nil) then modeUI.set = nil; end
            -- guarded: an error between BeginCombo/EndCombo (profilesets can throw
            -- pre-login) would tear the frame and kill every click in the popup
            local ok, names = pcall(allSetNames);
            for _, nm in ipairs((ok and names) or {}) do
                if imgui.Selectable(nm .. '##modeso', modeUI.set == nm) then modeUI.set = nm; end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Creates the rule "mode = <name> -> this set" (priority 100) for you --\nthe classic DT-style overlay. Leave (none) to wire rules yourself.');
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
            if not editing and modeUI.set ~= nil then
                trig.data.Default = trig.data.Default or {};
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
    local rightH = ((parts ~= nil) and (#parts * lh) or 26) + 30;   -- target + controls row
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
        imgui.TextColored(COL_DIM, '->');
        imgui.SameLine(0, 6);
        imgui.PushItemWidth(170);
        if imgui.BeginCombo('##trgset' .. id, r.set or '(pick set)') then
            for _, nm in ipairs(setNames) do
                if imgui.Selectable(nm .. '##trgso' .. id, r.set == nm) then
                    if r.set ~= nm then r.set = nm; trig.dirty = true; end
                end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
        -- the rule targets a set this profile doesn't define: the dispatch would
        -- match and then equip NOTHING -- say so where the rule lives
        if r.set ~= nil then
            local known = false;
            for _, nm in ipairs(setNames) do if nm == r.set then known = true; break; end end
            if not known then
                imgui.SameLine(0, 6);
                imgui.TextColored(COL_ERR, '[missing]');
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('No set with this name exists in the profile -- the trigger will\nmatch but equip nothing. Create the set in the Sets tab and Commit.');
                end
            end
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
    if imgui.BeginCombo('##trgaddset', trig.addSet or '(pick set)') then
        -- guarded like the mode popup's combo: an error between BeginCombo/EndCombo
        -- tears the frame and kills every click in the popup
        local ok, names = pcall(allSetNames);
        for _, nm in ipairs((ok and names) or {}) do
            if imgui.Selectable(nm .. '##trgaso', trig.addSet == nm) then trig.addSet = nm; end
        end
        imgui.EndCombo();
    end
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
            trig.addSet = r.set;
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
