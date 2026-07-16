--[[
    dlac/dispatch.lua — the trigger dispatch engine.
    Design: docs/design/trigger-system.md  (ADR 0002 data-driven dispatch,
    ADR 0003 overlay semantics, ADR 0004 automations land here in M2).

    Runs inside LuaAshitacast's Lua state: profiles call utils.dispatch('<Handler>')
    as the LAST line of each Handle* function, and this module reads the per-job
    trigger data file, matches the live action/player against each rule's `when`,
    and EquipSets every match in ascending priority (later overlays earlier per slot).

    Trigger file:  <char>\dlac\profiles\<active>\triggers\<JOB>.lua, falling back
    to the legacy <char>\dlac\triggers\<JOB>.lua   (a `return {...}` module)
        <Handler> = { { when = { <conditions> }, set = 'SetName' | equip = { Waist = 'Karin Obi' },
                        priority = <optional> }, ... }
    Hot-reloaded: the file is re-checked at most once per second (content compare),
    so a GUI commit or hand edit applies on the next action — no /lac reload.

    The dlac ADDON's Lua state also requires this module (through utils); there it is
    inert — no gFunc means no command handler, no mode state, and dispatch() no-ops.

    Commands (LAC state only; prefix /dl or /dlac):
        /dl mode <name> [on|off|toggle]   flip a mode flag (session-only; no args lists)
        /dl why                            trace of the last dispatch per handler
        /dl triggers reload|init|path      force re-read / seed a starter file / show path
        /dl sets reload                    hot-swap the committed sets (no LAC reload)
        /dl profile [use|new|clone|migrate]  the profile storage layer (profiles.lua)

    Every gData / gFunc / io read is pcall-guarded: a broken trigger file or a nil
    manager can never take down a cast or profile loading (it just no-ops + reports).
]]--

-- HOT-SWAP HANDSHAKE: when the engine self-swap (see the LAC tick near the end
-- of this file) re-executes this file, it hands over the CANONICAL module table
-- -- the one require() gave utils and the profiles -- through _G.__dlacEngineRoot.
-- Populating that same table means every held reference runs the new code with
-- no re-require. On a normal require the global is absent: ordinary fresh table.
local M = rawget(_G, '__dlacEngineRoot') or {};

-- LAC-LOAD generation stamp: `or` keeps it across engine SELF-swaps (same module
-- table, same Lua state) but a Reload LAC builds a fresh state -> fresh stamp.
-- Mirrored into modestate.lua, it is exactly the "has LAC actually been
-- reloaded?" signal the GUI's red Reload-LAC button watches -- including
-- reloads the user runs by command. (os.clock() disambiguates two loads
-- inside the same os.time() second.)
M._loadStamp = M._loadStamp or string.format('%d:%.3f', os.time(), os.clock());

-- Engine version handshake: bump on EVERY behavioral change to this file. The
-- LAC-state copy stamps its version into the modestate mirror; the GUI compares
-- against the addon-state copy and shows "Reload LAC" when LAC is running stale
-- code. From v32 the engine self-swaps when the seeded file's version moves, so
-- the banner should only persist when a swap FAILED (or pre-v32 code is live).
M.VERSION = 51;   -- 51: Trigger Groups (G1) -- new `group` matcher (specificity tier 45) + Groups section load/serialize (ADR 0009). 50: the v46-49 /dl instdiag diagnostic is out (field-confirmed on both characters); the fix it found stays -- M.jobReady + the job-keyed latch. See ADR 0007
                  -- 49: THE LOGIN BUG. At login GetMainJob() reads 0 (=None), which gData stringifies to "NON" -- not '' and not '?', so the auto-install took it for a real job, found no sets\NON.lua, installed nothing and LATCHED for the session: every trigger then matched and silently equipped nothing (v35 skips a missing set in silence). Fixed at both ends -- M.jobReady rejects a not-ready job, and the latch records WHICH job it answered for, so a settling read re-fires the guard
                  -- 44: PINNED slots -- pinstate.lua forces a named item into a slot at TOP priority (above the craft overlay), scoped to All or to named triggers; the engine WEARS the pin, so nothing removes it
                  -- 43: reserved slots (RSlot) resolved at equip time -- a Body that takes Head away (Ryl.Ftm. Tunic) drops the reserved slot instead of flapping with the server forever; worn pieces reserve too
-- 42: lockstyle apply builds the 0x053 itself (server reads ItemNo+EquipKind only -- bags never scanned; all 9 slots sent, unnamed frozen to worn gear); preview = locally injected GRAP_LIST 0x051; the v39 equip-preview overlay (lspreview.lua reader) is gone from the engine
                  -- 41: lockstyle boxes live in the JOB ENTRY (profiles\<Name>\lockstyles\<JOB>.lua; reads fall back v40 profile file, then global)
                  -- 35: matched-but-missing set no longer chat-warns (Triggers tab shows it in red)
                  -- 34: modestate __loadstamp -- the GUI's red Reload-LAC button watches it clear
                  -- 33: profile storage layer (dlac\profiles\<name>\; auto-install on load/job change; /dl profile)
                  -- 32: engine self-swap (dispatch.lua hot-reloads like the trigger file)
                  -- 31: craft-gear OVERLAY on Default (engine equips craft gear; craftstate.lua)
                  -- 30: AutoCraft goal reads manifest craftGoal (single silent variable, no mode)

-- Colored [dlac] chat output (chatfmt); plain print when unavailable. The shadowed
-- `print` re-heads "[dlac] ..."-prefixed lines with the colored header.
local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local print = (_cfok and type(_cfmt.print) == 'function') and _cfmt.print or print;
local function printwarn(s) if _cfok then _cfmt.warn(s); else print('[dlac] ' .. s); end end
local function printerr(s)  if _cfok then _cfmt.err(s);  else print('[dlac] ' .. s); end end

-- The profile storage layer (profiles.lua, seeded next to this file). Guarded:
-- a stale char folder without it degrades to the legacy layout everywhere.
local _pok, _prof = pcall(require, 'dlac\\profiles');
_pok = _pok and type(_prof) == 'table';

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
M.modes = {};   -- mode state: lower(name) -> true (toggle) or 'Value' (cycle).
                -- DLAC-OWNED: written to modestate.lua on every change and read BACK
                -- when the engine loads, so flags survive a Reload LAC exactly like
                -- they survive a dlac reload -- ONE lifetime rule instead of two
                -- Lua-state lifetimes. maxmp drops itself on a job change (tick).
M.modesRev = 0; -- bumped on every mode change: utils.rebuildSets re-flattens the
                -- Dynamic sets when it moves (mode-gated entries pick differently).
M.locks = {};   -- session-only SLOT LOCKS: lower(lac slot name) -> true. A locked slot is
                -- stripped from every set/inline payload the engine equips, so nothing
                -- dispatch-driven can overwrite a manual equip. /dl lock drives it; the
                -- Equipped tab's "Lock when equipped" sends that command. Mirrored to
                -- modestate.lua (__locks) for GUI display; reset on LAC reload like modes.
local saveModeState;   -- defined in the mode section below; used by the trigger loader

-- The 16 lac slot names (also the /dl lock vocabulary; 'all' fans out to every one).
local LAC_SLOTS = { 'main', 'sub', 'range', 'ammo', 'head', 'neck', 'ear1', 'ear2',
                    'body', 'hands', 'ring1', 'ring2', 'back', 'waist', 'legs', 'feet' };
local LAC_SLOT_OK = {};
for _, s in ipairs(LAC_SLOTS) do LAC_SLOT_OK[s] = true; end

-- PetAction is DLAC-SYNTHESIZED. No LuaAshitacast version calls a pet handler:
-- the upstream tutorial's HandlePetAction is a DIY pattern ("this function will
-- not be called by LuaAshitacast, you'll have to call it yourself" -- profiles
-- were meant to poll gData.GetPetAction from HandleDefault). The engine tick IS
-- that pattern, centralized: it dispatches once per pet-action start.
local EVENTS = { 'Default', 'Precast', 'Midcast', 'Ability', 'Item', 'Weaponskill', 'Preshot', 'Midshot', 'PetAction' };
local EVENT_CANON = {};
for _, e in ipairs(EVENTS) do EVENT_CANON[string.lower(e)] = e; end
M.EVENTS = EVENTS;
function M.canonEvent(e) return EVENT_CANON[string.lower(tostring(e))]; end

-- "NON" IS NOT A JOB, and this is the check that says so. Field-caught 07-15
-- (Hunklor, /dl instdiag):
--     latches=tick 1: job=NON hasSets=false | tick 17: job=SAM hasSets=true
-- gData resolves the main job through the resource manager --
-- GetString('jobs.names_abbr', GetMainJob()) -- so at login, when the player block
-- is not ready yet, GetMainJob() reads 0 (= None) and that stringifies to "NON".
-- "NON" is neither '' nor '?', so a guard testing only those took it for a real
-- job: the profile auto-install went looking for sets\NON.lua, found nothing,
-- installed nothing, and LATCHED -- permanently, because the latch did not record
-- which job it had answered for. The read settles ~6.4s later (16 ticks) and
-- nobody looks again: you play a whole session on an empty .Dynamic with every
-- trigger silently equipping nothing. Nobody has a NON.lua, so this bit every
-- migrated character equally.
--
-- Gate on the ID, not the string -- 0 is the authoritative "not ready" signal, and
-- readJobSets already did exactly this. The name check stays as belt-and-braces:
-- the id and the resolved string come from two different reads.
function M.jobReady(jobId, jobName)
    if jobId == nil or jobId == 0 then return false; end
    if type(jobName) ~= 'string' then return false; end
    if jobName == '' or jobName == '?' or jobName == 'NON' then return false; end
    return true;
end

local _trig  = { path = nil, raw = nil, rules = nil, lastCheck = -1, err = nil };
local _boundKeys = {};   -- bind key -> queued /bind command (mode keybinds queue ONCE per session)
local _trace = {};   -- event -> { time, action, sig, lines = {...} }

-- Only the copy of this module living in LuaAshitacast's state may equip, own mode
-- state, or answer commands. The dlac addon state has no gFunc, so it stays inert.
local function inLac() return rawget(_G, 'gFunc') ~= nil; end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function ci(a, b)   -- case-insensitive string equality (nil-safe)
    return type(a) == 'string' and type(b) == 'string' and string.lower(a) == string.lower(b);
end

local function readFile(p)
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end
local function writeFile(p, t)
    local f = io.open(p, 'w'); if f == nil then return false; end
    f:write(t); f:close(); return true;
end

-- <char>\dlac\ config dir: LuaAshitacast's gState when inside a profile, else the
-- party manager (same pattern as setmanager/gearoptim). nil if not logged in.
local function charDir()
    local name, id;
    if gState ~= nil and gState.PlayerName ~= nil and gState.PlayerId ~= nil then
        name, id = gState.PlayerName, gState.PlayerId;
    else
        pcall(function()
            local party = AshitaCore:GetMemoryManager():GetParty();
            name = party:GetMemberName(0);
            id   = party:GetMemberServerId(0);
            if name == '' then name = nil; end
        end);
    end
    if name == nil or id == nil then return nil; end
    return string.format('%sconfig\\addons\\luashitacast\\%s_%u\\dlac\\', AshitaCore:GetInstallPath(), name, id);
end

-- The CURRENT main job's trigger file, profile-aware. Reads fall back per file:
-- the active profile's triggers\<JOB>.lua when it exists, else the legacy
-- dlac\triggers\<JOB>.lua; when NEITHER exists yet, the path where writes should
-- land (profile storage once it exists, legacy before). nil pre-login.
local function triggersPath()
    local dir = charDir();
    if dir == nil then return nil; end
    local job;
    pcall(function() job = gData.GetPlayer().MainJob; end);
    if type(job) ~= 'string' or job == '' or job == '?' then return nil; end
    local lp = dir .. 'triggers\\' .. job .. '.lua';
    if _pok then
        local pp = _prof.triggersPath(job);
        if pp ~= nil then
            if readFile(pp) ~= nil then return pp; end
            if readFile(lp) ~= nil then return lp; end
            return _prof.storageExists() and pp or lp;
        end
    end
    return lp;
end
M.triggersPath = triggersPath;

-- ---------------------------------------------------------------------------
-- Matchers (v1 condition vocabulary — design doc table). Keyed by lowercased
-- condition name; each takes (value, ctx) and must return true to pass. All the
-- conditions in one `when` AND together; separate Triggers overlay (ADR 0003).
-- ---------------------------------------------------------------------------

-- Day/weather opposition: the element that BEATS yours penalizes your spell on its
-- day / in its weather (Fire<Water<Thunder<Earth<Wind<Ice<Fire; Light<->Dark).
-- LAC has no gData.GetElementalOpposition, so we carry the wheel ourselves.
local OPPOSED = {
    fire = 'Water', ice = 'Fire', wind = 'Ice', earth = 'Wind',
    thunder = 'Earth', water = 'Thunder', light = 'Dark', dark = 'Light',
};

-- Net day+weather sign for one element: +1 per matching day/weather, -1 per opposing
-- one. Also powers the /dl env diagnostic.
local function netForElement(el)
    local n = 0;
    if type(el) ~= 'string' then return n; end
    local opp = OPPOSED[string.lower(el)];
    pcall(function()
        local env = gData.GetEnvironment();
        if env == nil then return; end
        if ci(env.DayElement, el)      then n = n + 1;
        elseif ci(env.DayElement, opp) then n = n - 1; end
        if ci(env.WeatherElement, el)      then n = n + 1;
        elseif ci(env.WeatherElement, opp) then n = n - 1; end
    end);
    return n;
end

-- The current action's net sign, cached on ctx (computed at most once per dispatch).
local function netDayWeather(ctx)
    if ctx.dw ~= nil then return ctx.dw; end
    ctx.dw = netForElement(ctx.action and ctx.action.Element);
    return ctx.dw;
end

-- Debuff song families (Bard Song + one of these words in the name = Debuff;
-- any other Bard Song = Buff). Extend as CatsEyeXI adds custom songs.
local DEBUFF_SONGS = { 'requiem', 'lullaby', 'elegy', 'finale', 'threnody', 'virelai', 'nocturne' };

local function nameContains(ctx, word)
    local nm = ctx.action and ctx.action.Name;
    if type(nm) ~= 'string' or type(word) ~= 'string' then return false; end
    return string.find(string.lower(nm), string.lower(word), 1, true) ~= nil;
end

-- Public mode-condition check, shared by the trigger matcher AND set-entry gating
-- (utils.BuildDynamicSets: per-item `mode = '...'` wrappers). 'Weapon:Melee' -> the
-- cycle mode holds that value; a bare name -> toggle ON (or any cycle value).
-- A LIST of conditions is OR: active while ANY entry matches (two values of one
-- cycle can never be active together, so OR is the only coherent list reading).
-- `modes` defaults to the live session state; the GUI passes the modestate.lua
-- mirror instead (it lives in a different Lua state).
function M.modeActive(cond, modes)
    modes = modes or M.modes;
    if type(cond) == 'table' then
        for _, c in ipairs(cond) do
            if M.modeActive(c, modes) then return true; end
        end
        return false;
    end
    local s = tostring(cond);
    local p = string.find(s, ':', 1, true);
    if p ~= nil then
        local cur = modes[string.lower(string.sub(s, 1, p - 1))];
        return type(cur) == 'string' and ci(cur, string.sub(s, p + 1));
    end
    return modes[string.lower(s)] ~= nil;
end

-- Public group-condition check (ADR 0009), the group analogue of M.modeActive.
-- A Group is a named, untyped list of action names stored per Job entry beside
-- Modes; the condition fires when the current action's name is a member of the
-- named group. `cond` may be a single group name or a LIST of names (OR) --
-- exactly the one-of semantics `mode` has. Both group names and member names
-- match case-insensitively. `groups` defaults to the loaded job's Groups
-- (`_trig.groups`, raw `{ Name = { 'Action', ... } }`); tests pass one explicit.
function M.groupMatch(cond, actionName, groups)
    groups = groups or _trig.groups;
    if type(cond) == 'table' then
        for _, c in ipairs(cond) do
            if M.groupMatch(c, actionName, groups) then return true; end
        end
        return false;
    end
    if type(groups) ~= 'table' or type(actionName) ~= 'string' then return false; end
    for name, members in pairs(groups) do
        if ci(name, cond) and type(members) == 'table' then
            for _, m in ipairs(members) do
                if ci(m, actionName) then return true; end
            end
        end
    end
    return false;
end

local MATCHERS = {
    any             = function() return true; end,
    status          = function(v, ctx) return ctx.player ~= nil and ci(ctx.player.Status, v); end,
    moving          = function(v, ctx) return ctx.player ~= nil and ((ctx.player.IsMoving == true) == (v == true)); end,
    mode            = function(v) return M.modeActive(v); end,
    name            = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Name, v); end,
    contains        = function(v, ctx) return nameContains(ctx, v); end,   -- substring: 'Madrigal' hits Blade+Sword
    family          = function(v, ctx) return nameContains(ctx, v); end,   -- legacy alias of contains
    group           = function(v, ctx) return ctx.action ~= nil and M.groupMatch(v, ctx.action.Name); end,
    skill           = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Skill, v); end,
    magictype       = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Type, v); end,
    abilitytype     = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Type, v); end,
    element         = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Element, v); end,
    dayweatherbonus = function(v, ctx)
        if v == true  then return netDayWeather(ctx) > 0;  end
        if v == false then return netDayWeather(ctx) <= 0; end
        return netDayWeather(ctx) >= (tonumber(v) or 1);
    end,
    songtype        = function(v, ctx)
        if ctx.action == nil or not ci(ctx.action.Type, 'Bard Song') then return false; end
        local debuff = false;
        for _, w in ipairs(DEBUFF_SONGS) do
            if nameContains(ctx, w) then debuff = true; break; end
        end
        if ci(v, 'Debuff') then return debuff; end
        if ci(v, 'Buff')   then return not debuff; end
        return false;
    end,
};

-- Specificity tier per condition -> the DEFAULT priority when a rule sets none
-- (ADR 0003). A rule's default is the MAX tier among its conditions ("the most
-- specific field governs"): skill+name defaults like a name rule. `moving` sits
-- above the statuses so Movement overlays Idle when both match (idle + moving).
-- Band 60 is reserved for Automations (M2, ADR 0004).
local TIER = {
    any = 10,
    status = 20, skill = 20, abilitytype = 20,
    moving = 25,
    magictype = 30, element = 30, songtype = 30, dayweatherbonus = 30,
    contains = 40, family = 40,
    group = 45,   -- baseline for many spells that share gear; a per-spell `name` (50) overrides it, and it beats contains/skill (ADR 0009)
    name = 50,
    mode = 100,
};

-- Display-case spelling per (lowercased) condition key -- what the serializer writes
-- and the GUI shows. Matching is case-insensitive either way.
local PRETTY_KEY = {
    any = 'any', status = 'status', moving = 'moving', mode = 'mode',
    skill = 'skill', magictype = 'magicType', abilitytype = 'abilityType',
    element = 'element', songtype = 'songType', contains = 'contains',
    family = 'family', name = 'name', dayweatherbonus = 'dayWeatherBonus',
    group = 'group',
};
M.PRETTY_KEY = PRETTY_KEY;

-- The default priority a rule with this `when` would get (specificity, ADR 0003).
-- Exposed so the GUI can show the effective number next to an "auto" priority.
function M.defaultPriority(when)
    local p = 10;
    if type(when) == 'table' then
        for k in pairs(when) do
            local t = TIER[string.lower(tostring(k))];
            if t ~= nil and t > p then p = t; end
        end
    end
    return p;
end

-- ---------------------------------------------------------------------------
-- Trigger file: load, validate, normalize. Kept rules carry lowercased condition
-- keys, a resolved priority, their file order (tie-break), and a display label.
-- ---------------------------------------------------------------------------
-- The display label for a rule's conditions ("name=slow ii", "skill=singing",
-- "any"). ONE definition, used by normalize here AND by the GUI when it builds
-- pin scope keys -- the two Lua states must spell a label identically or a
-- scoped pin would never match. A condition value may be a LIST (when.mode can
-- hold several modes), and tostring() on a table yields its ADDRESS: different
-- in each state, and different again after every reload. Serialize lists by
-- value instead, sorted, so the label is stable everywhere.
local function condVal(v)
    if type(v) ~= 'table' then return tostring(v); end
    local parts = {};
    for _, x in ipairs(v) do parts[#parts + 1] = tostring(x); end
    table.sort(parts);
    return table.concat(parts, ',');
end
function M.ruleLabel(when)
    local parts = {};
    for k, v in pairs(when or {}) do
        parts[#parts + 1] = string.lower(tostring(k)) .. '=' .. condVal(v);
    end
    table.sort(parts);
    return (#parts > 0) and table.concat(parts, '+') or 'any';
end

local function normalize(t)
    local out, warns = {}, {};
    for k, v in pairs(t) do
        local ev = EVENT_CANON[string.lower(tostring(k))];
        if ev == nil then
            local lk = string.lower(tostring(k));
            if lk ~= 'setoptions' and lk ~= 'modes' and lk ~= 'groups' then   -- sibling sections, not handlers
                warns[#warns + 1] = string.format('unknown handler section %q (expected %s or Modes)',
                    tostring(k), table.concat(EVENTS, '/'));
            end
        elseif type(v) == 'table' then
            local list = out[ev] or {};
            for i, r in ipairs(v) do
                if type(r) ~= 'table' or type(r.when) ~= 'table'
                   or (r.set == nil and type(r.equip) ~= 'table') then
                    warns[#warns + 1] = string.format('%s rule %d: malformed (needs when = {...} plus set= or equip=)', ev, i);
                else
                    local when, dead = {}, false;
                    for ck, cv in pairs(r.when) do
                        local lk = string.lower(tostring(ck));
                        if TIER[lk] == nil then
                            warns[#warns + 1] = string.format('%s rule %d: unknown condition %q — rule dropped', ev, i, tostring(ck));
                            dead = true;
                            break;
                        end
                        when[lk] = cv;
                    end
                    if not dead then
                        local prio = tonumber(r.priority);
                        if prio == nil then
                            prio = 10;
                            for lk in pairs(when) do
                                if TIER[lk] > prio then prio = TIER[lk]; end
                            end
                        end
                        -- set = 'Name' or an ORDERED list { 'Base', 'Overlay' } --
                        -- normalized to a `sets` array either way.
                        local sets = nil;
                        if type(r.set) == 'table' then
                            for _, sn in ipairs(r.set) do
                                if type(sn) == 'string' and sn ~= '' then
                                    sets = sets or {};
                                    sets[#sets + 1] = sn;
                                end
                            end
                        elseif r.set ~= nil then
                            sets = { tostring(r.set) };
                        end
                        list[#list + 1] = {
                            when  = when,
                            sets  = sets,
                            equip = (type(r.equip) == 'table') and r.equip or nil,
                            prio  = prio,
                            ord   = #list + 1,
                            label = M.ruleLabel(when),
                        };
                    end
                end
            end
            out[ev] = list;
        end
    end
    return out, warns;
end

-- Load (or re-load) the current job's trigger file. Throttled to one content check
-- per second; between checks the cached rules are used, so per-frame dispatch never
-- touches the disk. On a parse/run error the PREVIOUS good rules are kept and the
-- error is printed once (per content change) + surfaced in /dl why.
local function ensureLoaded()
    local now = os.time();
    if _trig.rules ~= nil and now == _trig.lastCheck then return _trig.rules; end
    _trig.lastCheck = now;

    local path = triggersPath();
    if path == nil then return _trig.rules; end
    if path ~= _trig.path then   -- job change / first resolve -> drop the cache
        _trig.path, _trig.raw, _trig.rules, _trig.err = path, nil, nil, nil;
    end

    local raw = readFile(path);
    if raw == nil then           -- no trigger file (yet) -> nothing to dispatch
        _trig.raw, _trig.rules, _trig.err = nil, nil, nil;
        return nil;
    end
    if raw == _trig.raw then return _trig.rules; end
    _trig.raw = raw;

    local chunk, cerr = (loadstring or load)(raw, '@' .. path);
    if chunk == nil then
        _trig.err = 'trigger file does not parse: ' .. tostring(cerr);
        printerr(_trig.err .. '  (keeping the previous rules)');
        return _trig.rules;
    end
    local ok, t = pcall(chunk);
    if not ok or type(t) ~= 'table' then
        _trig.err = 'trigger file did not return a table' .. (ok and '' or (': ' .. tostring(t)));
        printerr(_trig.err .. '  (keeping the previous rules)');
        return _trig.rules;
    end

    local rules, warns = normalize(t);
    _trig.rules, _trig.err = rules, nil;
    -- Modes section: cycle-mode definitions + optional keybinds.
    --   Modes = { Weapon = { values = { 'Melee', 'Ranged', 'Caster' }, bind = '^F3' },
    --             DT = { bind = 'F9' } }          (array shorthand = values)
    _trig.modeDefs = {};
    local md = t.Modes or t.modes;
    if type(md) == 'table' then
        for nm, def in pairs(md) do
            if type(nm) == 'string' and type(def) == 'table' then
                local values = nil;
                local src = (type(def.values) == 'table') and def.values or def;
                for _, v in ipairs(src) do
                    if type(v) == 'string' then values = values or {}; values[#values + 1] = v; end
                end
                _trig.modeDefs[string.lower(nm)] = {
                    name = nm, values = values,
                    bind = (type(def.bind) == 'string') and def.bind or nil,
                };
            end
        end
    end
    -- Groups section (ADR 0009): a named, untyped list of action names per Job
    -- entry, beside Modes. Matched by the `group` condition. Stored raw
    -- ({ Name = { 'Action', ... } }); M.groupMatch does the case-insensitive
    -- membership test. Sanitized to string names -> string-member arrays.
    _trig.groups = {};
    local gr = t.Groups or t.groups;
    if type(gr) == 'table' then
        for nm, mem in pairs(gr) do
            if type(nm) == 'string' and type(mem) == 'table' then
                local members = {};
                for _, a in ipairs(mem) do
                    if type(a) == 'string' and a ~= '' then members[#members + 1] = a; end
                end
                _trig.groups[nm] = members;
            end
        end
    end
    -- A cycle mode ALWAYS has a value: default to its first on load / new definition.
    for ln, def in pairs(_trig.modeDefs) do
        if def.values ~= nil then
            local cur = M.modes[ln];
            local valid = false;
            if type(cur) == 'string' then
                for _, v in ipairs(def.values) do
                    if ci(v, cur) then valid = true; break; end
                end
            end
            if not valid then M.modes[ln] = def.values[1]; end
        end
        -- GUI-managed keybind: applied here so profiles need no OnLoad bind code.
        -- ONCE per key+command per session: this loader re-parses on every
        -- '/dl triggers reload' -- which the automations rescan pings after every
        -- inventory sync -- and unconditional re-binding here spammed /bind
        -- continuously (field report). A key re-queues only when its command
        -- CHANGES (another job's mode claiming the same key still rebinds).
        if def.bind ~= nil then
            local bindCmd = string.format('/bind %s /dl mode %s', def.bind, def.name);
            if _boundKeys[def.bind] ~= bindCmd then
                _boundKeys[def.bind] = bindCmd;
                pcall(function() AshitaCore:GetChatManager():QueueCommand(-1, bindCmd); end);
            end
        end
    end
    -- NO stale-value purge here (v16 had one; field-FALSIFIED on WHM): mode
    -- DEFINITIONS are per-job trigger data but their VALUES are session-global
    -- by design -- "WHM Weapons" is defined in BRD's file and gates WHM's sets,
    -- so a job change must not clear it. A DELETED mode still dies: the GUI's
    -- delete flow queues '/dl mode <name> off' after its commit.
    pcall(saveModeState);
    for _, w in ipairs(warns) do printwarn('triggers: ' .. w); end
    -- Successful loads are SILENT on purpose: this runs on every profile load /
    -- zone / GUI edit, and the per-load "triggers loaded: N rule(s)" line was
    -- pure chat noise. Errors and warnings above still speak up.
    return _trig.rules;
end

-- ---------------------------------------------------------------------------
-- Automations (ADR 0004): auto elemental staff / auto obi, priority band 60.
-- The GUI derives a per-character manifest (<char>\dlac\autogear.lua) from your
-- bags -- option toggles + the best owned staff/obi per element + whether you own
-- an Iridescence weapon -- and this engine hot-reloads it like the trigger file.
-- v1 Iridescence rule: OWNING one disables staff swapping entirely (it lives in
-- your sets already); obis are independent and stay governed by day/weather.
-- ---------------------------------------------------------------------------
local _auto = { raw = nil, data = nil, lastCheck = -1 };

local function ensureAutoLoaded()
    if M._autoOverride ~= nil then return M._autoOverride; end   -- headless test seam
    local now = os.time();
    if now == _auto.lastCheck then return _auto.data; end
    _auto.lastCheck = now;
    local dir = charDir();
    if dir == nil then return _auto.data; end
    local raw = readFile(dir .. 'autogear.lua');
    if raw == nil then _auto.raw, _auto.data = nil, nil; return nil; end   -- no manifest -> off
    if raw == _auto.raw then return _auto.data; end
    _auto.raw = raw;
    local chunk = (loadstring or load)(raw, '@autogear.lua');
    if chunk ~= nil then
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then
            _auto.data = t;
            -- Old boolean-format manifest: we can't know the universal weapon's name, so
            -- staff swapping stays suppressed. Tell the player how to fix it (once per change).
            if t.universal == nil and t.iridescence == true then
                printwarn('autogear.lua is an old format (staff swapping is OFF) -- open the GUI: Triggers tab > Automations > "Rescan owned gear".');
            end
        end
    end
    return _auto.data;
end

-- Virtual slot entries ("slot functions", ADR 0004 4th revision): a set slot may
-- hold a marker string instead of an item -- 'dlac:AutoStaff' (Main) equips the best
-- Iridescence staff for this cast, 'dlac:AutoObi' (Waist) the matching elemental obi
-- on a positive day/weather sign. Resolved HERE at equip time from the autogear
-- manifest; an unresolvable marker DROPS its slot, so LAC leaves what you're wearing.

-- The character's current effective level (honours the /dl set level main override).
-- Unknown -> 75, so a missing player read never blocks resolution.
local function playerLevel(ctx)
    local sl = rawget(_G, 'staticMainLevel');
    if type(sl) == 'number' and sl > 0 then return sl; end
    local lv = ctx.player and ctx.player.MainJobSync;
    if type(lv) == 'number' and lv > 0 then return lv; end
    return 75;
end

-- A manifest entry is usable when its recorded level fits the character. Entries
-- without a level (legacy manifests) count as usable -- Rescan adds levels.
local function usableAt(entryLevel, lvl)
    return entryLevel == nil or (tonumber(entryLevel) or 0) <= lvl;
end

-- Best staff by tiered Iridescence (CatsEyeXI): per-element staves carry it for their
-- own element only (NQ +1 / HQ +2); universal weapons for every element (Iridal +1,
-- Chatoyant / Foreshadow +1 = +2). Higher tier wins; ties go to the universal (no
-- cross-element swapping, and it needs no element at all). LEVEL-GATED: anything
-- above the character's current level is not a candidate at all.
local function resolveStaff(a, el, lvl)
    if a.iridescence == true then return nil; end   -- legacy boolean manifest: suppress (Rescan regenerates)
    local uniName, uniTier = nil, 0;
    if type(a.universal) == 'table' and type(a.universal.name) == 'string'
       and usableAt(a.universal.level, lvl) then
        uniName, uniTier = a.universal.name, tonumber(a.universal.tier) or 1;
    elseif type(a.iridescence) == 'string' then        -- legacy manifest: name, assume +2
        uniName, uniTier = a.iridescence, 2;
    end
    local elName, elTier = nil, 0;
    if el ~= nil and type(a.staff) == 'table' then
        local s = a.staff[el];
        if type(s) == 'table' and type(s.name) == 'string' and usableAt(s.level, lvl) then
            elName, elTier = s.name, tonumber(s.tier) or 1;
        elseif type(s) == 'string' then                -- legacy manifest: best-owned name
            elName, elTier = s, 2;
        end
    end
    if uniName ~= nil and uniTier >= elTier then return uniName; end
    return elName;
end

-- Marker -> item name for this cast, or nil + reason (for /dl why).
-- `slot` (the set's slot key, e.g. 'Neck'/'Ring1') is needed by per-slot
-- markers (dlac:AutoCraft); staff/obi ignore it (Main/Waist by convention).
local function resolveVirtual(marker, ctx, slot)
    local a = ensureAutoLoaded();
    if a == nil then return nil, 'no autogear manifest (Automations > Rescan owned gear)'; end
    local el = ctx.action and ctx.action.Element;
    if type(el) ~= 'string' or ci(el, 'Non-Elemental') then el = nil; end
    local lvl = playerLevel(ctx);
    local mk = string.lower(tostring(marker));
    -- canonical new names + the original spellings (existing sets keep working)
    if mk == 'dlac:autoiridescence' then mk = 'dlac:autostaff'; end
    if mk == 'dlac:elementalobi'    then mk = 'dlac:autoobi';   end
    if mk == 'dlac:autocraft' then
        -- Craft automation (docs/design/craft-automation.md): the manifest's
        -- craft section holds per-slot ladders per craft and goal. The ACTIVE
        -- craft is the dlac-owned 'craft' cycle value -- published by
        -- craftwatch on synth detection (or manually: /dl mode craft Alchemy);
        -- ctx.craftOverride lets the addon-side equip path resolve before the
        -- command-bus mode write lands. Goal: 'craftgoal' mode, 'nq' or 'hq'
        -- (default hq). Per Henrik: gear STAYS ON when the mode clears --
        -- the next ordinary trigger event redresses you (no flashing).
        local craftV = ctx.craftOverride or M.modes['craft'];
        if type(craftV) ~= 'string' then return nil, 'craft mode off (/dl mode craft <Skill>)'; end
        local goal = 'hq';                             -- goals: hq (default) / nq / skillup
        -- ONE goal variable (Henrik): the manifest's craftGoal field, written
        -- silently by the GUI picker and hot-reloaded here -- the mode system
        -- is no longer consulted (its narration spammed chat and desynced
        -- between the two Lua states).
        local g = ctx.goalOverride or a.craftGoal;
        if type(g) == 'string' then
            local lg = string.lower(g);
            if lg == 'nq' or lg == 'skillup' then goal = lg; end
        end
        local slotKey = string.lower(tostring(slot or ''));
        local bySlot = (type(a.craft) == 'table') and a.craft[slotKey] or nil;
        local perCraft = nil;
        if type(bySlot) == 'table' then
            perCraft = bySlot[craftV];
            if perCraft == nil then                      -- tolerate caps drift in the mode value
                for k, v in pairs(bySlot) do
                    if ci(tostring(k), tostring(craftV)) then perCraft = v; break; end
                end
            end
        end
        -- Strictly per-goal: hq gear under an nq goal (or vice versa) would
        -- FIGHT the goal, so a missing ladder is unresolved, not substituted.
        local chain = (type(perCraft) == 'table') and perCraft[goal] or nil;
        if type(chain) ~= 'table' then
            return nil, string.format('no %s craft gear for %s (%s)', slotKey, tostring(craftV), goal);
        end
        for _, r in ipairs(chain) do                     -- ladder is best-first
            if type(r) == 'table' and type(r.name) == 'string' and usableAt(r.level, lvl) then
                return r.name;
            end
        end
        return nil, string.format('no usable %s rung at Lv%d', slotKey, lvl);
    end
    if mk == 'dlac:autostaff' then
        local nm = resolveStaff(a, el, lvl);
        if nm == nil then
            return nil, (el == nil) and 'no usable universal staff (elementless action)'
                                     or ('no usable staff for ' .. el .. ' at Lv' .. lvl);
        end
        return nm;
    end
    if mk == 'dlac:autoobi' then
        if el == nil then return nil, 'no element'; end
        -- Elemental obi for this element first; else the universal obi (Hachirin-no-obi
        -- -- on CatsEyeXI the only obi). Both level-gated; the day/weather gate is
        -- evaluated per cast for the SPELL's element either way.
        local nm, olvl = nil, nil;
        local o = (type(a.obi) == 'table') and a.obi[el] or nil;
        if type(o) == 'table' and type(o.name) == 'string' then nm, olvl = o.name, o.level;
        elseif type(o) == 'string' then nm = o; end     -- legacy manifest: name only
        if nm ~= nil and not usableAt(olvl, lvl) then nm, olvl = nil, nil; end
        if nm == nil then
            local u = a.obiUniversal;
            if type(u) == 'table' and type(u.name) == 'string' and usableAt(u.level, lvl) then
                nm = u.name;
            end
        end
        if nm == nil then return nil, 'no usable obi for ' .. el .. ' at Lv' .. lvl; end
        if netDayWeather(ctx) <= 0 then return nil, 'day/weather not positive'; end
        return nm;
    end
    return nil, 'unknown marker';
end
M._resolveVirtual = resolveVirtual;   -- addon-side craft equip + headless tests

-- Equip a set table, resolving virtual entries and honouring SLOT LOCKS. Sets that
-- need neither pass through untouched (zero copies); otherwise a shallow copy carries
-- the changes. BuildDynamicSets encodes the slot's regular best-by-level pick as a
-- fallback ('dlac:AutoStaff|Maple Wand'): an unresolvable virtual equips the fallback
-- -- so being under-leveled for every iridescence weapon / obi never blocks the slot
-- -- and only with no fallback at all is the slot dropped (LAC leaves what's worn).
-- LOCKED slots (/dl lock, the Equipped tab's "Lock when equipped") are stripped
-- outright: the engine never sends gear into them, so a manual equip stays put.
-- Returns a trace note ('' when nothing was virtual/locked).
-- ---------------------------------------------------------------------------
-- Max-MP hold (mode 'maxmp'): keep a worn piece while swapping it out would
-- WASTE unspent MP. Generic and slot-local: however the MP gear got on (resting
-- set, trigger, manual equip), it stays until the player has spent the surplus
-- its MP grants over the incoming piece; then the slot releases naturally.
-- Weapons are exempt (Main/Sub/Range swaps are TP-sensitive). Piece MP values
-- ride the autogear manifest (the engine never loads the catalog); the worn
-- item is read from equipment memory. Design: docs/design/maxmp-mode.md.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- THE central equip-eligibility check. Wearability is MAIN job only (field-
-- verified on CatsEyeXI: RDM/WHM cannot wear Hlr. Bliaut +1 -- ADR/history) and
-- the level gate is the main level. Every consumer -- gearui pickers, gearoptim,
-- the automation manifests -- delegates here; utils re-exports it for profiles.
-- ---------------------------------------------------------------------------
function M.jobCanEquip(jobs, job)
    if jobs == nil then return true; end               -- no restriction
    if type(jobs) ~= 'table' or #jobs == 0 then return true; end
    for _, j in ipairs(jobs) do
        if j == 'All' then return true; end
        if job ~= nil and job ~= '' and j == job then return true; end
    end
    return false;
end

function M.canWear(rec, job, level)
    if type(rec) ~= 'table' then return false; end
    if (tonumber(rec.Level) or 0) > (tonumber(level) or 0) then return false; end
    return M.jobCanEquip(rec.Jobs, job);
end

local MP_HOLD_EXEMPT = { main = true, sub = true, range = true };
local SLOT_EQUIP_ID = { main = 0, sub = 1, range = 2, ammo = 3, head = 4, body = 5,
                        hands = 6, legs = 7, feet = 8, neck = 9, waist = 10,
                        ear1 = 11, ear2 = 12, ring1 = 13, ring2 = 14, back = 15 };

-- The pure rule (headless-tested): hold while current MP is AT OR ABOVE what the
-- pool would hold with the incoming piece worn instead. The boundary is >= on
-- purpose: a battery equipped at a FULL pool sits exactly on it (cur == newMax -
-- delta), and releasing there would drop the piece before any recovery landed.
-- Release requires spending strictly past the surplus.
function M.mpHoldNeeded(wornMP, targetMP, curMP, maxMP)
    local delta = (wornMP or 0) - (targetMP or 0);
    if delta <= 0 then return false; end
    return (curMP or 0) >= (maxMP or 0) - delta;
end

-- Pick the battery to wear from a manifest ladder (sorted best-first). Rungs
-- exist because rung 1 may be gear the character has yet to grow into -- the
-- pick is the best rung wearable at the CURRENT level. A legacy single-entry
-- manifest counts as a one-rung ladder.
function M.mpPick(cands, level)
    if type(cands) ~= 'table' then return nil; end
    if cands.name ~= nil then cands = { cands }; end   -- legacy fmtver-1 shape
    for _, c in ipairs(cands) do
        if type(c) == 'table' and type(c.name) == 'string'
           and (tonumber(c.level) or 0) <= (tonumber(level) or 0) then
            return c;
        end
    end
    return nil;
end

-- Non-weapon slots MP-EQUIP may write even when the dispatched set doesn't
-- address them (lowercase key -> canonical LAC set key).
local MP_SLOT_CANON = { ammo = 'Ammo', head = 'Head', neck = 'Neck', ear1 = 'Ear1',
                        ear2 = 'Ear2', body = 'Body', hands = 'Hands', ring1 = 'Ring1',
                        ring2 = 'Ring2', back = 'Back', waist = 'Waist', legs = 'Legs',
                        feet = 'Feet' };

local function wornItemName(slotKey)
    local nm = nil;
    pcall(function()
        local id = SLOT_EQUIP_ID[string.lower(tostring(slotKey))];
        if id == nil then return; end
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local eitem = inv:GetEquippedItem(id);
        if eitem == nil or eitem.Index == 0 then return; end
        local item = inv:GetContainerItem(math.floor(eitem.Index / 256) % 256, eitem.Index % 256);
        if item == nil or item.Id == nil or item.Id == 0 then return; end
        local res = AshitaCore:GetResourceManager():GetItemById(item.Id);
        if res ~= nil and res.Name ~= nil then nm = res.Name[1]; end
    end);
    return nm;
end

local function playerMP()
    local cur, max = nil, nil;
    pcall(function() cur = gData.GetPlayer().MP; end);
    pcall(function() max = AshitaCore:GetMemoryManager():GetPlayer():GetMPMax(); end);
    return tonumber(cur), tonumber(max);
end

local _mpCd = {};   -- slot -> os.time() before which a released battery must not re-equip
                    -- (breaks the equip/release churn at the exact spent boundary)

-- ---------------------------------------------------------------------------
-- Open-menu name (diagnostic, shown by /dl env). Standard FFXiMain menu
-- pattern, tCrossBar/HXUI lineage. NOTE: a v14 build PAUSED swaps while the
-- equipment screen was open, on the retail ghost-gear lore -- field-FALSIFIED
-- on CatsEyeXI (/lac equip works fine with the window up; the menu lock is
-- client-side and injected packets bypass it). The real "stops working in the
-- equipment window" cause was dispatch starvation: LAC only parses
-- HandleDefault while OUTGOING packets flow -- fixed by the engine tick (see
-- the d3d_present registration in the command section).
-- ---------------------------------------------------------------------------
local pGameMenu = nil;
pcall(function()
    pGameMenu = ashita.memory.find('FFXiMain.dll', 0, '8B480C85C974??8B510885D274??3B05', 16, 0);
end);

local function menuName()
    local nm = '';
    pcall(function()
        if pGameMenu == nil or pGameMenu == 0 then return; end
        local sub = ashita.memory.read_uint32(pGameMenu);
        if sub == nil or sub == 0 then return; end
        local val = ashita.memory.read_uint32(sub);
        if val == nil or val == 0 then return; end
        local hdr = ashita.memory.read_uint32(val + 4);
        if hdr == nil or hdr == 0 then return; end
        local s = ashita.memory.read_string(hdr + 0x46, 16);
        if type(s) == 'string' then nm = (string.gsub(s, '\x00', '')); end
    end);
    return nm;
end
M.menuName = menuName;   -- craftwatch reads it to equip while the synth window is OPEN
                         -- (before you confirm -- injected equips bypass the menu lock)

-- ---------------------------------------------------------------------------
-- Type automation: AutoAcc (Henrik 2026-07-14). Set entries typed AutoAcc
-- flatten to 'dlac:AutoAcc:<prio>:<acc>:<Name>|<fallback>' (utils.BuildDynamicSets).
-- accwatch (addon state) measures the cap gap per engage and publishes it to
-- <char>\dlac\accstate.lua; THIS state hot-reads it and, while the player is
-- OVER the hit cap, RELEASES AutoAcc pieces -- highest removal priority first,
-- only while the piece's baked ACC fits inside the measured surplus -- wearing
-- the slot's fallback (its normal best pick) instead. Feedback loop: the next
-- engage measures ACC with the released pieces off, so the budget rebuilds as
-- measured surplus + sum(released accs) and the decision self-corrects (harder
-- mob -> the pieces come back on). Invalid/stale/missing state (unknown mob,
-- watch off, no measurement yet) -> every AutoAcc piece stays worn: the set
-- behaves exactly as if nothing were typed.
-- NOTE (main): the WRITER (accwatch.lua + accdata.lua) ships on
-- feature/autoacc pending GM approval -- on main nothing writes accstate.lua,
-- so this machinery is dormant foundation: markers always resolve to "worn".
-- ---------------------------------------------------------------------------
local _accfile = { raw = nil, data = nil, lastCheck = -1 };
local ACC_STALE_S = 900;   -- measurements older than 15 min are not acted on

local function ensureAccState()
    if M._accStateOverride ~= nil then return M._accStateOverride; end   -- headless test seam
    local now = os.time();
    if now == _accfile.lastCheck then return _accfile.data; end
    _accfile.lastCheck = now;
    local dir = charDir();
    if dir == nil then return _accfile.data; end
    local raw = readFile(dir .. 'accstate.lua');
    if raw == nil then _accfile.raw, _accfile.data = nil, nil; return nil; end
    if raw == _accfile.raw then return _accfile.data; end
    _accfile.raw = raw;
    local chunk = (loadstring or load)(raw, '@accstate.lua');
    if chunk ~= nil then
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then _accfile.data = t; else _accfile.data = nil; end
    end
    return _accfile.data;
end

-- 'dlac:AutoAcc:<prio>:<acc>:<Name>' -> prio, acc, name (nil unless it parses).
-- The name is the LAST field on purpose: item names never need escaping then.
local function parseAccMarker(mk)
    if type(mk) ~= 'string' then return nil; end
    if string.lower(string.sub(mk, 1, 13)) ~= 'dlac:autoacc:' then return nil; end
    local prio, acc, name = string.match(string.sub(mk, 14), '^(%-?%d+):(%-?%d+):(.+)$');
    if name == nil then return nil; end
    return tonumber(prio), tonumber(acc), name;
end
M._parseAccMarker = parseAccMarker;   -- headless tests

M._accRemoved = {};    -- lower(name) -> baked ACC of every piece currently RELEASED
local _accSeq = nil;   -- last accstate.seq folded into the budget
local _accBudget = 0;  -- the all-worn surplus, frozen once per measurement

-- The pure removal rule (headless-tested): given one set's candidates and the
-- frozen budget, release by DESCENDING removal priority while the baked ACC
-- fits. A candidate with no fallback or no ACC is never released (nothing
-- better to wear / nothing to gain). Ties break on higher acc, then slot name
-- -- deterministic, so every dispatch of a fight agrees with the last one.
function M._accDecide(cands, budget)
    local order = {};
    for i, c in ipairs(cands) do order[i] = c; end
    table.sort(order, function(a, b)
        if (a.prio or 0) ~= (b.prio or 0) then return (a.prio or 0) > (b.prio or 0); end
        if (a.acc or 0) ~= (b.acc or 0) then return (a.acc or 0) > (b.acc or 0); end
        return tostring(a.slot) < tostring(b.slot);
    end);
    local pick, released = {}, {};
    local b = budget;
    for _, c in ipairs(order) do
        if c.fallback ~= nil and (c.acc or 0) > 0 and c.acc <= b then
            pick[c.slot] = c.fallback;
            released[string.lower(c.name)] = c.acc;
            b = b - c.acc;
        else
            pick[c.slot] = c.name;
        end
    end
    return pick, released;
end

-- Decisions for one set table: { [slot] = item name } covering every AutoAcc
-- marker in it (the piece itself, or its fallback when released); nil when the
-- set carries none. Locked slots are skipped (the lock branch strips them).
local function accResolveSet(s)
    local cands = nil;
    for slot, v in pairs(s) do
        if type(v) == 'string' and M.locks[string.lower(tostring(slot))] ~= true then
            local marker, fallback = v, nil;
            local p = string.find(v, '|', 1, true);
            if p ~= nil then marker, fallback = string.sub(v, 1, p - 1), string.sub(v, p + 1); end
            local prio, acc, name = parseAccMarker(marker);
            if name ~= nil then
                cands = cands or {};
                cands[#cands + 1] = { slot = slot, prio = prio or 1, acc = acc or 0,
                                      name = name, fallback = fallback };
            end
        end
    end
    if cands == nil then return nil; end
    local st = ensureAccState();
    local usable = type(st) == 'table' and st.valid == true
               and type(st.capGap) == 'number'
               and (tonumber(st.at) == nil or os.time() - st.at < ACC_STALE_S);
    if not usable then
        -- No trustworthy measurement -> AutoAcc stands down: wear every piece.
        local pick = {};
        for _, c in ipairs(cands) do
            pick[c.slot] = c.name;
            M._accRemoved[string.lower(c.name)] = nil;
        end
        return pick;
    end
    if st.seq ~= _accSeq then
        -- Fresh measurement: rebuild the budget ONCE per seq. capGap was
        -- measured with the currently-released pieces OFF, so the all-worn
        -- surplus is the measured surplus plus everything already released.
        _accSeq = st.seq;
        local sum = 0;
        for _, a in pairs(M._accRemoved) do sum = sum + a; end
        _accBudget = -(tonumber(st.capGap) or 0) + sum;
    end
    local pick, released = M._accDecide(cands, _accBudget);
    for _, c in ipairs(cands) do
        M._accRemoved[string.lower(c.name)] = released[string.lower(c.name)];
    end
    return pick;
end
M._accResolveSet = accResolveSet;   -- headless tests
function M._accReset()              -- headless tests: fresh-session state
    M._accRemoved = {}; _accSeq = nil; _accBudget = 0;
end

-- ---------------------------------------------------------------------------
-- Reserved slots (RSlot). Some pieces take another slot away while worn: the
-- Ryl.Ftm. Tunic is a Body that reserves Head; robes reserve Hands; a boomerang
-- (Range) reserves Ammo; suits reserve most of the body. It is the server's
-- item_equipment.rslot, carried per item in gear.lua (the engine's only item
-- source -- it has no catalog) and stamped there by the scan / `/dl fix`.
--
-- Equipping into a reserved slot is not a partial failure the server tolerates:
-- it strips the piece straight back, dlac sees the slot is wrong and re-equips,
-- and the two flap forever. Dropping the reserved slot is the only stable state.
--
-- Bit order matches the client's slot order. Tested arithmetically (no `bit`
-- library): dispatch also runs headless on 5.4, where `bit` does not exist and
-- `&` would not parse under LuaJIT.
local RSLOT_ORDER = {
    { 0x0001, 'Main'  }, { 0x0002, 'Sub'   }, { 0x0004, 'Range' }, { 0x0008, 'Ammo'  },
    { 0x0010, 'Head'  }, { 0x0020, 'Body'  }, { 0x0040, 'Hands' }, { 0x0080, 'Legs'  },
    { 0x0100, 'Feet'  }, { 0x0200, 'Neck'  }, { 0x0400, 'Waist' }, { 0x0800, 'Ear1'  },
    { 0x1000, 'Ear2'  }, { 0x2000, 'Ring1' }, { 0x4000, 'Ring2' }, { 0x8000, 'Back'  },
};
local function hasBit(mask, b) return math.floor(mask / b) % 2 == 1; end

-- Which slots of a RESOLVED set are reserved out from under it.
--   set    -- the resolved slot->name plan; ONLY these slots can be dropped
--   lookup -- itemName -> RSlot mask or nil (injected; tests drive it directly)
--   worn   -- SlotKey -> the name you are wearing there, or nil. Optional, and the
--             reason this is not a pure set-vs-itself check: the Tunic already on
--             your back reserves Head from a set that only writes Head. A slot the
--             set DOES write is judged by the plan, not by what it replaces.
-- Returns { [SlotKey] = reserverName } or nil when nothing is reserved.
--
-- The reserver wins and the reserved slot is dropped -- matching the server, which
-- clears that slot anyway the moment the reserver goes on. Slots are walked in a
-- fixed order, so mutual reservations (a boomerang reserves Ammo; a pebble in Ammo
-- reserves Range) always resolve the same way instead of by pairs() luck, and a
-- slot already dropped never reserves anything itself (Body takes Legs, so the Legs
-- piece must not go on to take Feet).
function M.reservedDrops(set, lookup, worn)
    local keyOf = {};   -- lowercase slot -> the set's actual key, whatever its case
    for slot, v in pairs(set) do
        if type(v) == 'string' then keyOf[string.lower(tostring(slot))] = slot; end
    end
    local name = {};    -- what each slot will actually hold once this set lands
    for _, e in ipairs(RSLOT_ORDER) do
        local ls = string.lower(e[2]);
        if keyOf[ls] ~= nil then
            name[ls] = set[keyOf[ls]];
        elseif worn ~= nil then
            local ok, w = pcall(worn, e[2]);
            if ok and type(w) == 'string' then name[ls] = w; end
        end
    end
    local gone, dropped = {}, nil;
    for _, e in ipairs(RSLOT_ORDER) do
        local ls = string.lower(e[2]);
        if name[ls] ~= nil and not gone[ls] then
            local mask = tonumber(lookup(name[ls])) or 0;
            if mask > 0 then
                for _, r in ipairs(RSLOT_ORDER) do
                    local rls = string.lower(r[2]);
                    if rls ~= ls and keyOf[rls] ~= nil and not gone[rls] and hasBit(mask, r[1]) then
                        gone[rls] = true;
                        dropped = dropped or {};
                        dropped[keyOf[rls]] = name[ls];
                    end
                end
            end
        end
    end
    return dropped;
end

-- RSlot by item name, from the gear manifest. Resolved lazily: in LAC's state the
-- require finds the character's real gear.lua. Guarded -- a missing/old manifest
-- means every lookup is nil, and the engine behaves exactly as it did before.
local _gearMod = nil;
local function rslotOf(name)
    if _gearMod == nil then
        _gearMod = false;
        pcall(function() _gearMod = require('dlac\\gear') or false; end);
    end
    local m = nil;
    pcall(function()
        local rec = _gearMod and _gearMod.NameToObject and _gearMod.NameToObject[name] or nil;
        if rec ~= nil then m = tonumber(rec.RSlot); end
    end);
    return m;
end

local function equipResolved(s, ctx)
    local out, notes = nil, nil;
    local anyLocks = (next(M.locks) ~= nil);
    -- Slots a PINNED item takes away (RSlot). reservedDrops cannot catch this on
    -- its own: it judges ONE table at a time, and the pin lands in its own pass,
    -- so the SET's pass never learns that the pin's Body is about to reserve the
    -- Head it is happily equipping. Left alone that is the v43 flap all over
    -- again -- set equips Head, pin equips the reserver, server strips Head,
    -- forever. ctx.pinReserved is a stateless hold computed per dispatch from the
    -- pin table; unpin and the slot dispatches normally on the very next pass.
    local pinRes = (type(ctx) == 'table') and ctx.pinReserved or nil;
    -- Max-MP context (only while the mode is on and the manifest carries MP data).
    local mpMap, mpBest, curMP, maxMP = nil, nil, nil, nil;
    if M.modes['maxmp'] ~= nil then
        local a = ensureAutoLoaded();
        if a ~= nil and type(a.mp) == 'table' then
            curMP, maxMP = playerMP();
            if curMP ~= nil and maxMP ~= nil then
                mpMap = a.mp;
                if type(a.mpBest) == 'table' then mpBest = a.mpBest; end
            end
        elseif not M._mpWarned then
            -- The mode is ON but the engine has no battery data: say so ONCE
            -- instead of silently doing nothing (the classic dead-mode symptom).
            M._mpWarned = true;
            print('[dlac] maxmp is ON but the gear manifest has no MP data yet -- open Triggers > Automations (it self-heals) or relog, then act again.');
        end
    end
    -- AutoAcc (Type automation) decisions for this set; nil when it carries no
    -- dlac:AutoAcc markers. Resolved before the generic virtual branch below.
    local accPick = accResolveSet(s);
    for slot, v in pairs(s) do
        if anyLocks and M.locks[string.lower(tostring(slot))] == true then
            if out == nil then
                out = {};
                for k2, v2 in pairs(s) do out[k2] = v2; end
            end
            out[slot] = nil;                           -- locked: the engine leaves it alone
            notes = notes or {};
            notes[#notes + 1] = string.format('%s=LOCKED (kept as worn)', tostring(slot));
        elseif pinRes ~= nil and pinRes[string.lower(tostring(slot))] ~= nil then
            if out == nil then
                out = {};
                for k2, v2 in pairs(s) do out[k2] = v2; end
            end
            out[slot] = nil;               -- a pinned piece takes this slot away
            notes = notes or {};
            notes[#notes + 1] = string.format('%s=RESERVED by pinned %s',
                tostring(slot), tostring(pinRes[string.lower(tostring(slot))]));
        elseif accPick ~= nil and accPick[slot] ~= nil then
            if out == nil then
                out = {};
                for k2, v2 in pairs(s) do out[k2] = v2; end
            end
            out[slot] = accPick[slot];
            notes = notes or {};
            local mkOnly = v;
            local pb = string.find(v, '|', 1, true);
            if pb ~= nil then mkOnly = string.sub(v, 1, pb - 1); end
            local _, cacc, cname = parseAccMarker(mkOnly);
            if cname ~= nil and accPick[slot] ~= cname then
                notes[#notes + 1] = string.format('AutoAcc=%s RELEASED (acc+%d redundant) -> %s',
                    cname, cacc or 0, accPick[slot]);
            else
                notes[#notes + 1] = string.format('AutoAcc=%s', tostring(accPick[slot]));
            end
        elseif type(v) == 'string' and string.lower(string.sub(v, 1, 5)) == 'dlac:' then
            if out == nil then
                out = {};
                for k2, v2 in pairs(s) do out[k2] = v2; end
            end
            local marker, fallback = v, nil;
            local p = string.find(v, '|', 1, true);
            if p ~= nil then marker, fallback = string.sub(v, 1, p - 1), string.sub(v, p + 1); end
            local nm, why = resolveVirtual(marker, ctx, slot);
            out[slot] = nm or fallback;                -- nil fallback drops the slot
            notes = notes or {};
            if nm ~= nil then
                notes[#notes + 1] = string.format('%s=%s', marker, nm);
            elseif fallback ~= nil then
                notes[#notes + 1] = string.format('%s=fallback %s (%s)', marker, fallback, tostring(why));
            else
                notes[#notes + 1] = string.format('%s=skipped (%s)', marker, tostring(why));
            end
        elseif mpMap ~= nil and type(v) == 'string'
               and not MP_HOLD_EXEMPT[string.lower(tostring(slot))] then
            local lslot = string.lower(tostring(slot));
            local worn = wornItemName(slot);
            local wornMP = (worn ~= nil) and (mpMap[string.lower(worn)] or 0) or 0;
            local tgtMP  = mpMap[string.lower(v)] or 0;
            if worn ~= nil and string.lower(worn) ~= string.lower(v)
               and M.mpHoldNeeded(wornMP, tgtMP, curMP, maxMP) then
                if out == nil then
                    out = {};
                    for k2, v2 in pairs(s) do out[k2] = v2; end
                end
                out[slot] = nil;                       -- keep the MP battery until it's spent
                notes = notes or {};
                notes[#notes + 1] = string.format('%s=MP-HOLD %s (+%d MP unspent)',
                    tostring(slot), worn, wornMP - tgtMP);
            else
                if worn ~= nil and wornMP > tgtMP and string.lower(worn) ~= string.lower(v) then
                    _mpCd[lslot] = os.time() + 15;     -- battery released: no instant re-equip
                end
                -- Upgrade: a full pool means recovery would be capped -- wear the
                -- slot's best battery instead of the set piece so refresh/resting/
                -- sublimation land into the larger pool. The hold above then owns it.
                local c = (mpBest ~= nil) and M.mpPick(mpBest[lslot], playerLevel(ctx)) or nil;
                if c ~= nil
                   and (worn == nil or string.lower(c.name) ~= string.lower(worn))
                   and (c.mp or 0) > math.max(wornMP, tgtMP)
                   and curMP >= maxMP
                   and os.time() >= (_mpCd[lslot] or 0) then
                    if out == nil then
                        out = {};
                        for k2, v2 in pairs(s) do out[k2] = v2; end
                    end
                    out[slot] = c.name;
                    notes = notes or {};
                    notes[#notes + 1] = string.format('%s=MP-EQUIP %s (+%d MP)',
                        tostring(slot), c.name, (c.mp or 0) - math.max(wornMP, tgtMP));
                end
            end
        end
    end
    -- MP-EQUIP covers slots the set does NOT address too: an unwritten ring or
    -- neck slot is exactly where a battery is freest to sit. Full pool only,
    -- locked and weapon slots never. (Nothing else ever writes such a slot, so
    -- the battery simply stays worn until you or a set replace it -- there is
    -- no MP to waste by leaving it on.)
    if mpBest ~= nil and curMP ~= nil and maxMP ~= nil and curMP >= maxMP then
        local covered = {};
        for slot in pairs(s) do covered[string.lower(tostring(slot))] = true; end
        for lslot, canon in pairs(MP_SLOT_CANON) do
            if mpBest[lslot] ~= nil and not covered[lslot] and M.locks[lslot] ~= true then
                local c = M.mpPick(mpBest[lslot], playerLevel(ctx));
                local worn = wornItemName(lslot);
                local wornMP = (worn ~= nil) and (mpMap[string.lower(worn)] or 0) or 0;
                if c ~= nil and (worn == nil or string.lower(c.name) ~= string.lower(worn))
                   and (c.mp or 0) > wornMP
                   and os.time() >= (_mpCd[lslot] or 0) then
                    if out == nil then
                        out = {};
                        for k2, v2 in pairs(s) do out[k2] = v2; end
                    end
                    out[canon] = c.name;
                    notes = notes or {};
                    notes[#notes + 1] = string.format('%s=MP-EQUIP %s (+%d MP)',
                        lslot, c.name, (c.mp or 0) - wornMP);
                end
            end
        end
    end
    -- Craft Sub guard: hold a Main that pairs badly with the craft overlay's Sub
    -- (see craftMainGuard). Post-pass on the FINAL names so it also covers a Main
    -- that a virtual (dlac:AutoStaff) or AutoAcc resolved above.
    if ctx ~= nil and ctx.craftMainGuard ~= nil then
        for slot, v in pairs(out or s) do
            if string.lower(tostring(slot)) == 'main' and type(v) == 'string'
               and ctx.craftMainGuard(v) then
                if out == nil then
                    out = {};
                    for k2, v2 in pairs(s) do out[k2] = v2; end
                end
                out[slot] = nil;
                notes = notes or {};
                notes[#notes + 1] = string.format('Main=%s HELD (pairs badly with the craft Sub)', tostring(v));
                break;
            end
        end
    end
    -- Reserved-slot pass (see RSLOT_ORDER). LAST, on the FINAL names: only here are
    -- the overlay, the virtuals, AutoAcc and MP-EQUIP all resolved. It has to be
    -- here rather than at build time -- two individually legal sets can overlay into
    -- an illegal pair (a Body from one trigger, a Head from another), and MP-EQUIP
    -- writes slots no set ever named. A set is a plan; conflicts are the engine's
    -- call (ADR 0006).
    local drops = M.reservedDrops(out or s, rslotOf, wornItemName);
    if drops ~= nil then
        for slot, by in pairs(drops) do
            if out == nil then
                out = {};
                for k2, v2 in pairs(s) do out[k2] = v2; end
            end
            out[slot] = nil;
            notes = notes or {};
            notes[#notes + 1] = string.format('%s=RESERVED by %s (kept as worn)', tostring(slot), tostring(by));
        end
    end
    pcall(function() gFunc.EquipSet(out or s); end);
    local note = '';
    if notes ~= nil then
        table.sort(notes);
        note = '  [' .. table.concat(notes, ', ') .. ']';
    end
    return note, (out or s);   -- the table actually equipped (for slot attribution)
end
M._equipResolved = equipResolved;   -- test seam (craft Sub guard post-pass)

-- Flip a slot lock. slot: one of LAC_SLOTS or 'all'; state nil = toggle. Returns the
-- new state (for 'all': the state applied), or nil for an unknown slot name.
function M.setLock(slot, state)
    slot = string.lower(tostring(slot or ''));
    if slot == 'all' then
        if state == nil then state = (next(M.locks) == nil); end   -- toggle: all on if none on
        for _, s in ipairs(LAC_SLOTS) do M.locks[s] = (state == true) or nil; end
        saveModeState();
        return state == true;
    end
    if not LAC_SLOT_OK[slot] then return nil; end
    if state == nil then state = not (M.locks[slot] == true); end
    M.locks[slot] = (state == true) or nil;
    saveModeState();
    return M.locks[slot] == true;
end

-- Force a re-read on the next dispatch (the GUI pings /dl triggers reload on commit).
-- Clears only the content caches (triggers + autogear) -- current rules stay live as
-- the fallback, so a forced reload of a broken file degrades exactly like an organic
-- one (keep + report).
function M.reloadTriggers()
    _trig.raw, _trig.lastCheck = nil, -1;
    _auto.raw, _auto.lastCheck = nil, -1;
    _accfile.raw, _accfile.lastCheck = nil, -1;
end

-- ---------------------------------------------------------------------------
-- Dispatch
-- ---------------------------------------------------------------------------
local function buildCtx(event)
    local ctx = { event = event };
    pcall(function() ctx.player = gData.GetPlayer(); end);
    if event == 'PetAction' then
        -- the PET's action (Blood Pact / Ready move / pet spell) -- same shape
        -- as GetAction (Name/Skill/Element/Type), so the matchers just work
        pcall(function() ctx.action = gData.GetPetAction(); end);
    elseif event ~= 'Default' then
        pcall(function() ctx.action = gData.GetAction(); end);
    end
    return ctx;
end

local function matches(rule, ctx)
    for lk, cv in pairs(rule.when) do
        local f = MATCHERS[lk];
        if f == nil or not f(cv, ctx) then return false; end
    end
    return true;
end

-- One-line description of the acted-on thing, for /dl why.
local function actionLabel(ctx)
    local a = ctx.action;
    if a ~= nil then
        local bits = {};
        for _, k in ipairs({ 'Skill', 'Type', 'Element' }) do
            if type(a[k]) == 'string' then bits[#bits + 1] = a[k]; end
        end
        local tail = (#bits > 0) and (' [' .. table.concat(bits, '/') .. ']') or '';
        return string.format('%q%s', tostring(a.Name), tail);
    end
    if ctx.player ~= nil then
        return string.format('status=%s moving=%s', tostring(ctx.player.Status), tostring(ctx.player.IsMoving));
    end
    return '?';
end

local function equipSetByName(name, ctx)
    local s;
    pcall(function()
        local prof = rawget(_G, 'gProfile');
        if type(prof) == 'table' and type(prof.Sets) == 'table' then s = prof.Sets[name]; end
    end);
    if type(s) ~= 'table' then
        -- A trigger MATCHED but its target set is absent from this job's profile
        -- (field case: a Midshot rule pointing at a set never committed on WAR --
        -- the silent skip cost an hour of ghost-hunting). NO chat warn (Henrik:
        -- inform by printing as little as possible) -- the visibility lives in
        -- the Triggers tab now: a red banner + per-row [missing] markers against
        -- profilesets.liveSetNames. The skip itself stays traced in /dl why.
        return false, '', nil;
    end
    local note, tbl = equipResolved(s, ctx);
    return true, note, tbl;
end

local function inlineSummary(equip)
    local parts = {};
    for slot, item in pairs(equip) do parts[#parts + 1] = tostring(slot) .. '=' .. tostring(item); end
    table.sort(parts);
    return table.concat(parts, ', ');
end

-- The engine entry point. Never throws; a failure inside just skips this dispatch.
-- ---------------------------------------------------------------------------
-- Craft-gear overlay (Henrik's design: don't fight the engine, BE the engine).
-- craftwatch (addon state) writes <char>\dlac\craftstate.lua {craft,goal,enabled};
-- when enabled, the engine overlays the resolved craft gear on TOP of whatever
-- Default equipped -- so the craft pieces are simply what the engine wears, and
-- nothing reverts them. Disable -> no overlay -> normal Default returns.
-- ---------------------------------------------------------------------------
local _craft = { raw = nil, data = nil, lastCheck = -1 };
local function ensureCraftState()
    local now = os.time();
    if now == _craft.lastCheck then return _craft.data; end
    _craft.lastCheck = now;
    local dir = charDir();
    if dir == nil then return _craft.data; end
    local raw = readFile(dir .. 'craftstate.lua');
    if raw == nil then _craft.raw, _craft.data = nil, nil; return nil; end
    if raw == _craft.raw then return _craft.data; end
    _craft.raw = raw;
    local chunk = (loadstring or load)(raw, '@craftstate.lua');
    if chunk ~= nil then
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then _craft.data = t; else _craft.data = nil; end
    end
    return _craft.data;
end

-- Proper-case slot keys for gFunc.EquipSet (resolveVirtual lowercases for the
-- manifest lookup). Ammo excluded: crafting never wants an ammo swap.
local CRAFT_OVERLAY_SLOTS = { 'Main', 'Sub', 'Range', 'Head', 'Neck', 'Ear1', 'Ear2',
                             'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet' };

-- The craft equip table for a given craft-state, or nil when off. Split out so
-- tests can pass an explicit state instead of the on-disk file.
local function craftOverlayFor(cs, ctx)
    if type(cs) ~= 'table' or cs.enabled ~= true
       or type(cs.craft) ~= 'string' or cs.craft == '' then return nil; end
    local goal = (cs.goal == 'nq' or cs.goal == 'skillup') and cs.goal or 'hq';
    local equip = nil;
    for _, slot in ipairs(CRAFT_OVERLAY_SLOTS) do
        local nm = resolveVirtual('dlac:AutoCraft', { craftOverride = cs.craft, goalOverride = goal }, slot);
        if type(nm) == 'string' then equip = equip or {}; equip[slot] = nm; end
    end
    return equip;
end
M._craftOverlayFor = craftOverlayFor;   -- test seam

-- (There was a craftOverlay(ctx) wrapper here that paired ensureCraftState with
-- craftOverlayFor. M.dispatch now reads the state itself -- it has to decide
-- whether there is anything to do BEFORE building the context -- so the wrapper
-- would just be a second, hidden read of the same cache.)

-- ---------------------------------------------------------------------------
-- PINNED slots (v44) -- "equip item, lock slot so nothing removes it" (Henrik).
-- Same shape as the craft overlay, and for the same reason: don't fight the
-- engine, BE the engine. pinwatch (addon state) writes <char>\dlac\pinstate.lua
--
--     return { Ring1 = { item = "Rajas Ring", scope = "All" },
--              Head  = { item = "Uk'uxkaj Cap", scope = { "Fast Cast" } } }
--
-- and the engine WEARS those names at top priority -- above the craft overlay,
-- on EVERY event, not just Default (a pin that lost its slot mid-cast would not
-- be a pin). Unpin -> no overlay -> the normal set returns on the next dispatch.
--
-- Deliberately NOT the /dl lock route: a lock only makes the engine ignore the
-- slot, so anything else that strips the piece wins and the state leaks when a
-- session ends abnormally. A pin is recomputed from the file every dispatch --
-- nothing to restore, nothing to leak.
--
-- `scope` is "All" (every dispatch) or a list of trigger LABELS: the pin then
-- applies only on a dispatch where one of those triggers actually matched.
-- ---------------------------------------------------------------------------
local _pin = { raw = nil, data = nil, lastCheck = -1 };
local function ensurePinState()
    local now = os.time();
    if now == _pin.lastCheck then return _pin.data; end
    _pin.lastCheck = now;
    local dir = charDir();
    if dir == nil then return _pin.data; end
    local raw = readFile(dir .. 'pinstate.lua');
    if raw == nil then _pin.raw, _pin.data = nil, nil; return nil; end
    if raw == _pin.raw then return _pin.data; end
    _pin.raw = raw;
    local chunk = (loadstring or load)(raw, '@pinstate.lua');
    if chunk == nil then
        -- A torn/corrupt write must DROP the pins, not keep the last good ones.
        -- _pin.raw is already the corrupt text, so the raw-compare above would
        -- short-circuit every later call and the stale pins would stay glued on
        -- with nothing able to clear them -- including pinwatch's clear-on-load.
        _pin.data = nil;
        return nil;
    end
    local ok, t = pcall(chunk);
    if ok and type(t) == 'table' then _pin.data = t; else _pin.data = nil; end
    return _pin.data;
end

-- Scope entries are "<Event>|<rule label>" -- the rule label ALONE is ambiguous
-- ('any' is the label of every unconditional rule, so a Precast 'any' and a
-- Midcast 'any' would be indistinguishable and one pin would silently cover
-- both). M.pinScopeKey is the single place that spelling is defined; the GUI
-- builds its menu entries with the same function, so the two states can never
-- drift on the format.
function M.pinScopeKey(event, label) return tostring(event) .. '|' .. tostring(label); end

-- Does this pin's scope cover this dispatch? "All" (or a missing scope -- a
-- hand-written file) covers everything; a list covers only the dispatches where
-- one of the named triggers actually matched. An unknown key simply never
-- matches: a pin scoped to a trigger you later edited or deleted goes QUIET
-- rather than falling back to forcing gear on every dispatch.
local function pinInScope(scope, hits, event)
    if scope == nil or scope == 'All' then return true; end
    if type(scope) ~= 'table' then return false; end
    for _, want in ipairs(scope) do
        for _, r in ipairs(hits or {}) do
            if M.pinScopeKey(event, r.label) == want then return true; end
        end
    end
    return false;
end
M._pinInScope = pinInScope;   -- test seam

-- The pin equip table for a given pin-state, or nil when nothing is in scope.
-- Split out so tests can pass an explicit state instead of the on-disk file.
local function pinOverlayFor(ps, hits, event)
    if type(ps) ~= 'table' then return nil; end
    local equip = nil;
    for slot, p in pairs(ps) do
        -- Tolerate both shapes: { item = "X", scope = ... } and a bare "X".
        local name  = (type(p) == 'table') and p.item or p;
        local scope = (type(p) == 'table') and p.scope or 'All';
        if type(name) == 'string' and name ~= '' and pinInScope(scope, hits, event) then
            equip = equip or {};
            equip[slot] = name;
        end
    end
    return equip;
end
M._pinOverlayFor = pinOverlayFor;   -- test seam

-- Slots the PINNED pieces take away while worn (their RSlot mask), as
-- { [lowercase slot] = <the pinned item that reserves it> }, or nil.
--
-- Why this is not reservedDrops' job: that pass judges ONE table at a time, on
-- its final names. The pin lands in its OWN equipResolved, so when the set's
-- pass runs, nothing tells it that the pin's Ryl.Ftm. Tunic is about to reserve
-- the Head it just equipped -- and the pin's own pass cannot drop a Head its
-- table never named. The set would re-equip Head every frame and the server
-- would strip it every frame: the v43 flap, reached through the overlay. So the
-- reservation becomes a stateless HOLD instead (the ratified pattern), computed
-- fresh each dispatch and gone the moment the pin is.
--
-- A pin never reserves ANOTHER pin's slot: you asked for both, so both land and
-- the server arbitrates -- exactly as it would for a set naming an illegal pair.
local function pinReservedSlots(pEquip)
    if type(pEquip) ~= 'table' then return nil; end
    local out = nil;
    for _, name in pairs(pEquip) do
        local mask = rslotOf(name);
        if mask ~= nil then
            for _, pair in ipairs(RSLOT_ORDER) do
                if hasBit(mask, pair[1]) and pEquip[pair[2]] == nil then
                    out = out or {};
                    out[string.lower(pair[2])] = name;
                end
            end
        end
    end
    return out;
end
M._pinReservedSlots = pinReservedSlots;   -- test seam

-- Craft Sub-vs-Main guard (Henrik, field case: the overlay's Kupo Shield vs a
-- scythe in the Default set). When the overlay owns SUB but brings no MAIN, a
-- set Main that cannot PAIR with that Sub (2H/H2H vs a shield -- utils'
-- subSlotAllowed, the shared pairing rule, decides) must be HELD out of the
-- dispatch: equipping it knocks the craft Sub off and the two slots then knock
-- each other off on every pass. equipResolved applies the hold, so it is
-- stateless -- the moment the overlay clears, Main dispatches normally again;
-- nothing to re-enable, nothing to leak if a craft ends abnormally. (The
-- '/lac disable main' route is a known dead end: it blocks /lac equip and
-- somebody has to remember the re-enable.)
-- Returns guard(mainName) -> true when that Main must be held, or nil when the
-- overlay shape needs no guard / utils is not loaded in this state.
local function craftMainGuard(cEquip)
    if cEquip == nil or cEquip.Sub == nil or cEquip.Main ~= nil then return nil; end
    local g = nil;
    pcall(function()
        local u = package.loaded['dlac\\utils'];   -- loaded first in the LAC state; no require (circular)
        if type(u) ~= 'table' or u.resolveGearName == nil or u.subSlotAllowed == nil then return; end
        local subRec = u.resolveGearName(cEquip.Sub);
        if type(subRec) ~= 'table' then return; end
        g = function(mainName)
            local mrec = u.resolveGearName(mainName);
            if type(mrec) ~= 'table' then return false; end   -- unknown name: leave it alone
            return u.subSlotAllowed(subRec, mrec, {}) ~= true;
        end
    end);
    return g;
end
M._craftMainGuard = craftMainGuard;   -- test seam

-- (v39's equip-based preview plan lived here until v42: the engine wore the
-- working lockstyle via a Default overlay. Gone whole -- the preview paints
-- the LOOK now (feature/lookpreview.lua) and never touches gear. lockstyle.lua
-- still one-shot retires stale lspreview.lua files for anyone whose LAC state
-- runs an older seeded copy of this file.)

-- ---------------------------------------------------------------------------
-- Lockstyle APPLY, engine-built (v42). gFunc.LockStyle scanned your bags to
-- fill container/index fields and silently no-op'd when its scan came up empty
-- -- but the SERVER never reads those fields. Its handler (CatsEyeXI
-- src/map/packets/c2s/0x053_lockstyle.cpp, read 2026-07-15) takes ItemNo +
-- EquipKind per entry and validates only that the item exists in the item DB
-- and fits the slot. Ownership and job are judged later, at style-resolution
-- (charutils.cpp UpdateArmorStyle / hasValidStyle):
--   * HasItem(char, id)          -- owned in ANY container, Mog Safe included
--   * canEquipItemOnAnyJob(char) -- SOME job of yours, at its CURRENT level,
--                                   could equip it; on failure the armor slot
--                                   silently KEEPS ITS OLD STYLE
--   * weapon slots additionally need the equipped weapon's category to match
-- styleItems also PERSIST server-side per slot: a packet that omits a slot
-- leaves whatever an earlier apply put there (cross-box bleed). So a box is
-- only authoritative if we send all nine visual slots every time -- named ones
-- by id, 'remove' as 0 (style 0 renders the slot EMPTY; that is the server's
-- own semantics, matching the GUI's 'hide'), and unnamed ones frozen to the
-- currently equipped item, so "no pick" means "look like what I actually wear"
-- instead of naked or stale.
-- ---------------------------------------------------------------------------
local LS_KINDS = { { k = 0, s = 'Main' },  { k = 1, s = 'Sub' },  { k = 2, s = 'Range' },
                   { k = 3, s = 'Ammo' },  { k = 4, s = 'Head' }, { k = 5, s = 'Body' },
                   { k = 6, s = 'Hands' }, { k = 7, s = 'Legs' }, { k = 8, s = 'Feet' } };
local LS_JOBS = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG',
                  'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
M._LS_JOBS = LS_JOBS;

-- Mirror of the server's canEquipItemOnAnyJob: true when ANY of the character's
-- jobs (jobLevels: abbr -> level) meets the item's job+level requirement.
-- Unknown records pass -- this only predicts; the server decides.
function M._lsStyleGate(rec, jobLevels)
    if type(rec) ~= 'table' then return true; end
    local req = tonumber(rec.Level) or 0;
    if type(rec.Jobs) ~= 'table' or #rec.Jobs == 0 then return true; end
    for _, j in ipairs(rec.Jobs) do
        if j == 'All' then
            for _, l in pairs(jobLevels or {}) do
                if (tonumber(l) or 0) >= req then return true; end
            end
            return false;
        end
        if (tonumber((jobLevels or {})[j]) or 0) >= req then return true; end
    end
    return false;
end

-- The 0x053 bytes (pure -- headless-tested). resolveId(name) -> item id or nil;
-- equippedId(slot) -> the worn item's id (freeze-current for unnamed slots).
-- Returns the packet plus what happened per slot.
function M._lockstylePacket(set, resolveId, equippedId)
    local pkt = {};
    for i = 1, 136 do pkt[i] = 0; end
    pkt[1] = 0x53; pkt[2] = 0x88;   -- header u16 = id | (size/2) << 9
    pkt[5] = 9;                     -- Count: all visual slots, every time
    pkt[6] = 3;                     -- Mode: Set
    pkt[7] = 1;                     -- Flags (what the client sends)
    local sent, frozen, missing = {}, {}, {};
    for n, e in ipairs(LS_KINDS) do
        local o = 0x08 + (n - 1) * 8;   -- lockstyleitem_t: ItemIndex, EquipKind,
        pkt[o + 2] = e.k;               -- Category, pad, ItemNo u16 -- index and
                                        -- category are ignored server-side
        local nm = (type(set) == 'table') and set[e.s] or nil;
        local id = 0;
        if type(nm) == 'string' and nm ~= '' and nm ~= 'remove' then
            id = tonumber(resolveId ~= nil and resolveId(nm) or nil) or 0;
            if id > 0 then sent[e.s] = nm; else missing[#missing + 1] = nm; end
        elseif nm == nil then
            id = tonumber(equippedId ~= nil and equippedId(e.s) or nil) or 0;
            if id > 0 then frozen[e.s] = id; end
        end
        pkt[o + 5] = id % 256;
        pkt[o + 6] = math.floor(id / 256) % 256;
    end
    return pkt, { sent = sent, frozen = frozen, missing = missing };
end

-- Lockstyle box selection (pure -- headless-tested): parsed lockstyles.lua
-- table + optional box number -> (slot->name table, box name, box index), or
-- (nil, why). Explicit n wins; else the file's marked box (active); else 1.
-- Only string values ride: gFunc.LockStyle itself filters non-visual slots
-- and understands the literal 'remove' (lockstyle the slot EMPTY).
function M._lockstyleFrom(t, n)
    if type(t) ~= 'table' or type(t.slots) ~= 'table' then return nil, 'no lockstyle sets saved yet'; end
    n = tonumber(n) or tonumber(t.active) or 1;
    local e = t.slots[n];
    if type(e) ~= 'table' or type(e.set) ~= 'table' then return nil, string.format('lockstyle box %d is empty', n); end
    local out, any = {}, false;
    for slot, v in pairs(e.set) do
        if type(v) == 'string' and v ~= '' then out[slot] = v; any = true; end
    end
    if not any then return nil, string.format('lockstyle box %d has no items', n); end
    return out, ((type(e.name) == 'string' and e.name ~= '') and e.name or ('box ' .. n)), n;
end

function M.dispatch(event)
    if not inLac() then return; end
    pcall(function()
        event = EVENT_CANON[string.lower(tostring(event))] or event;
        -- While the PET's action is in flight, HOLD Default: the pet gear a
        -- PetAction rule equipped must survive until the action completes
        -- (upstream parity -- LAC clears gState.PetAction on the completion
        -- packet; the Completion timestamp is the backstop). Petless: no effect.
        if event == 'Default' then
            local held = false;
            pcall(function()
                local st = rawget(_G, 'gState');
                local pa = (st ~= nil) and st.PetAction or nil;
                if pa ~= nil and (pa.Completion == nil or os.clock() < pa.Completion) then held = true; end
            end);
            if held then return; end
        end
        local rules = ensureLoaded();
        local list = rules and rules[event] or nil;
        local hasRules = (list ~= nil and #list > 0);

        -- Bail only when there is genuinely NOTHING to do. This used to return on
        -- the rule list alone -- which quietly made BOTH overlays dead on any
        -- event the profile has no rules for, including the "a plain profile
        -- still gets craft gear" case the craft overlay's own comment promised.
        -- An "All" pin has to hold on a profile with no triggers at all, so the
        -- overlays must be consulted HERE, ahead of the early return. Both reads
        -- are the 1/sec-throttled cached ones, so this stays cheap on the Default
        -- dispatch that runs every frame.
        local pinState   = ensurePinState();
        local hasPins    = (type(pinState) == 'table' and next(pinState) ~= nil);
        local craftState = (event == 'Default') and ensureCraftState() or nil;
        local craftOn    = (type(craftState) == 'table' and craftState.enabled == true
                            and type(craftState.craft) == 'string' and craftState.craft ~= '');
        if not hasRules and not hasPins and not craftOn then return; end

        local ctx = buildCtx(event);
        local hits = {};
        if hasRules then
            for _, r in ipairs(list) do
                if matches(r, ctx) then hits[#hits + 1] = r; end
            end
        end

        -- Craft overlay applies on Default even with NO trigger match, and always
        -- LAST (top priority) below -- but under the pin.
        local cEquip = craftOn and craftOverlayFor(craftState, ctx) or nil;

        -- Pins apply on EVERY event (a pin that lost its slot mid-cast would not
        -- be a pin). Scoped pins need `hits` to know whether their trigger fired,
        -- so this reads it above.
        local pEquip = pinOverlayFor(pinState, hits, event);

        -- A pinned piece that takes a slot away has to stop everything BELOW it
        -- from equipping into that slot (see pinReservedSlots -- otherwise the
        -- set and the server flap over it forever).
        ctx.pinReserved = pinReservedSlots(pEquip);

        -- Pin beats craft (it is applied after it), so a craft Sub that cannot
        -- pair with a PINNED Main has to go: left in, craft would re-equip it
        -- every pass and the pinned Main would knock it straight off again --
        -- the v37 flap seen from the other side.
        if pEquip ~= nil and pEquip.Main ~= nil and cEquip ~= nil and cEquip.Sub ~= nil then
            local pg = craftMainGuard({ Sub = cEquip.Sub });
            if pg ~= nil and pg(pEquip.Main) then cEquip.Sub = nil; end
        end

        -- The Sub-vs-Main guard (v37). A PINNED Sub with no pinned Main must
        -- survive everything BELOW it -- the set's Main and the craft overlay's
        -- alike -- so the pin becomes the guard's source in that case; otherwise
        -- the craft overlay keeps it exactly as before. Stateless either way:
        -- unpin, and the held Main dispatches normally on the next pass.
        local guardSrc = (pEquip ~= nil and pEquip.Sub ~= nil and pEquip.Main == nil)
                         and pEquip or cEquip;
        ctx.craftMainGuard = (guardSrc ~= nil) and craftMainGuard(guardSrc) or nil;

        if #hits == 0 and cEquip == nil and pEquip == nil then
            if event ~= 'Default' then   -- Default runs every frame; only action events trace a miss
                _trace[event] = { time = os.date('%H:%M:%S'), action = actionLabel(ctx),
                                  sig = '', lines = { '(no trigger matched)' } };
            end
            return;
        end

        -- Overlay: ascending priority, file order on ties (ADR 0003).
        table.sort(hits, function(a, b)
            if a.prio ~= b.prio then return a.prio < b.prio; end
            return a.ord < b.ord;
        end);

        -- Equip every hit. Trace strings are rebuilt only when the matched-rule
        -- signature changes (Default dispatches per frame -- keep the GC quiet).
        local sig = {};
        for _, r in ipairs(hits) do sig[#sig + 1] = r.ord; end
        local lk = {};
        for s in pairs(M.locks) do lk[#lk + 1] = s; end   -- lock changes must retrace too
        table.sort(lk);
        local cSig = '';                                  -- craft overlay changes must retrace too
        if cEquip ~= nil then
            local ck = {};
            for slot, item in pairs(cEquip) do ck[#ck + 1] = slot .. '=' .. item; end
            table.sort(ck);
            cSig = table.concat(ck, ',');
        end
        local pSig = '';                                  -- pin changes must retrace too
        if pEquip ~= nil then
            local pk = {};
            for slot, item in pairs(pEquip) do pk[#pk + 1] = slot .. '=' .. item; end
            table.sort(pk);
            pSig = table.concat(pk, ',');
        end
        sig = event .. ':' .. table.concat(sig, ',') .. '|' .. table.concat(lk, ',')
              .. '|' .. cSig .. '|' .. pSig;
        local old = _trace[event];
        local retrace = (old == nil) or (old.sig ~= sig) or (event ~= 'Default');
        local lines = retrace and {} or old.lines;

        -- Apply in order, attributing each SLOT to its final writer -- with partial
        -- sets (weapon-only, DT-only, ...) this is what proves the overlay: every
        -- slot lists the rule that actually owns it this dispatch.
        local slotSrc = retrace and {} or nil;
        for _, r in ipairs(hits) do
            if r.sets ~= nil then
                -- A rule may wear SEVERAL sets: applied IN ORDER, later overlaying
                -- earlier per slot -- the same law as between rules ("cast Madrigal
                -- -> the WindSkill base, then the Madrigal overlay on top").
                for si, sn in ipairs(r.sets) do
                    local found, note, tbl = equipSetByName(sn, ctx);
                    if retrace then
                        lines[#lines + 1] = string.format('%s  ->  set %s%s  (prio %d)%s%s',
                            r.label, sn, (#r.sets > 1) and string.format(' [%d/%d]', si, #r.sets) or '',
                            r.prio, found and '' or '  [NOT FOUND in profile Sets]', note or '');
                        if type(tbl) == 'table' then
                            for slot in pairs(tbl) do
                                if string.sub(tostring(slot), 1, 2) ~= '__' then slotSrc[slot] = sn; end
                            end
                        end
                    end
                end
            elseif r.equip ~= nil then
                local note, tbl = equipResolved(r.equip, ctx);
                if retrace then
                    lines[#lines + 1] = string.format('%s  ->  equip { %s }  (prio %d)%s',
                        r.label, inlineSummary(r.equip), r.prio, note or '');
                    if type(tbl) == 'table' then
                        for slot in pairs(tbl) do
                            if string.sub(tostring(slot), 1, 2) ~= '__' then slotSrc[slot] = r.label; end
                        end
                    end
                end
            end
        end
        -- Craft overlay LAST: it owns every craft slot this dispatch, on top of
        -- whatever Default resolved (the whole point -- the engine wears the
        -- craft gear, so nothing reverts it).
        if cEquip ~= nil then
            equipResolved(cEquip, ctx);
            if retrace then
                local ks = {};
                for slot in pairs(cEquip) do ks[#ks + 1] = tostring(slot); end
                table.sort(ks);
                lines[#lines + 1] = 'craft gear (overlay)  ->  ' .. table.concat(ks, ', ');
            end
        end
        -- Pins LAST of all: above the craft overlay, above every trigger. This is
        -- the whole mechanism -- last writer wins the slot, so a pinned piece is
        -- simply what the engine wears and nothing can take it back off.
        if pEquip ~= nil then
            equipResolved(pEquip, ctx);
            if retrace then
                local ks = {};
                for slot, item in pairs(pEquip) do ks[#ks + 1] = tostring(slot) .. '=' .. tostring(item); end
                table.sort(ks);
                lines[#lines + 1] = 'PINNED  ->  ' .. table.concat(ks, ', ');
            end
        end

        if retrace and #hits > 1 then                    -- who won each slot (overlap visibility)
            local parts = {};
            for slot, src in pairs(slotSrc) do parts[#parts + 1] = tostring(slot) .. '<-' .. tostring(src); end
            if #parts > 0 then
                table.sort(parts);
                lines[#lines + 1] = 'slots: ' .. table.concat(parts, ', ');
            end
        end

        _trace[event] = { time = os.date('%H:%M:%S'), action = actionLabel(ctx), sig = sig, lines = lines };
    end);
end

-- Trace access for /dl why and (later) the GUI "Explain last action" view.
function M.getTrace() return _trace; end

-- ---------------------------------------------------------------------------
-- Trigger file read/write for the GUI (the format lives HERE, next to the parser).
-- The GUI edits a plain rule table and serializeTriggers turns it back into the
-- canonical file text; readTriggersRaw hands the GUI the current file's table.
-- ---------------------------------------------------------------------------

-- Raw (un-normalized) rule table from a trigger file path: table | nil, err.
function M.readTriggersRaw(path)
    if path == nil then return nil, 'no path'; end
    local raw = readFile(path);
    if raw == nil then return nil, 'no file'; end
    local chunk, cerr = (loadstring or load)(raw, '@' .. path);
    if chunk == nil then return nil, 'does not parse: ' .. tostring(cerr); end
    local ok, t = pcall(chunk);
    if not ok or type(t) ~= 'table' then
        return nil, 'did not return a table' .. (ok and '' or (': ' .. tostring(t)));
    end
    return t;
end

local function luaValue(v)
    if type(v) == 'string' then return string.format('%q', v); end
    return tostring(v);
end

-- A condition value may be a single scalar OR a LIST (OR): `mode` and `group`
-- both accept `{ 'A', 'B' }`. Serialize a list as `{ "A", "B" }` (order kept),
-- so list conditions round-trip instead of stringifying to a table address.
local function condLiteral(v)
    if type(v) ~= 'table' then return luaValue(v); end
    local q = {};
    for _, x in ipairs(v) do q[#q + 1] = luaValue(x); end
    return '{ ' .. table.concat(q, ', ') .. ' }';
end

-- data = { [Handler] = { { when = {k=v}, set='X' | equip={Slot='Item'}, priority=n? }, ... } }
-- Handlers emit in canonical order; conditions in sorted display-case spelling.
-- Deterministic output -> clean diffs; comments are NOT preserved (GUI-owned file).
function M.serializeTriggers(data)
    local L = {
        '-- dlac triggers -- written by the dlac GUI (Triggers tab); safe to hand-edit,',
        '-- but the GUI rewrites this file on Commit (comments are not preserved).',
        '-- Hot-reloaded: changes apply on the next action, no /lac reload needed.',
        '-- Format & conditions: docs/design/trigger-system.md in the dlac addon.',
        'return {',
    };
    for _, ev in ipairs(EVENTS) do
        local list = (type(data) == 'table') and data[ev] or nil;
        if type(list) == 'table' and #list > 0 then
            L[#L + 1] = '    ' .. ev .. ' = {';
            for _, r in ipairs(list) do
                local conds = {};
                for k, v in pairs(r.when or {}) do
                    local lk = string.lower(tostring(k));
                    conds[#conds + 1] = (PRETTY_KEY[lk] or tostring(k)) .. ' = ' .. condLiteral(v);
                end
                table.sort(conds);
                local action;
                if type(r.set) == 'table' then          -- ordered multi-set rule
                    local q = {};
                    for _, sn in ipairs(r.set) do q[#q + 1] = luaValue(tostring(sn)); end
                    action = 'set = { ' .. table.concat(q, ', ') .. ' }';
                elseif r.set ~= nil then
                    action = 'set = ' .. luaValue(tostring(r.set));
                else
                    local slots = {};
                    for slot, item in pairs(r.equip or {}) do
                        slots[#slots + 1] = tostring(slot) .. ' = ' .. luaValue(tostring(item));
                    end
                    table.sort(slots);
                    action = 'equip = { ' .. table.concat(slots, ', ') .. ' }';
                end
                local prio = (tonumber(r.priority) ~= nil) and (', priority = ' .. tostring(r.priority)) or '';
                L[#L + 1] = string.format('        { when = { %s }, %s%s },',
                    table.concat(conds, ', '), action, prio);
            end
            L[#L + 1] = '    },';
        end
    end
    -- Modes section (cycle definitions + keybinds) -- carried through serialization so
    -- a Commit never wipes it (sibling of the handler sections, like the rules).
    local md = (type(data) == 'table') and (data.Modes or data.modes) or nil;
    if type(md) == 'table' then
        local names = {};
        for nm, def in pairs(md) do
            if type(nm) == 'string' and type(def) == 'table' then names[#names + 1] = nm; end
        end
        table.sort(names);
        if #names > 0 then
            L[#L + 1] = '    Modes = {';
            for _, nm in ipairs(names) do
                local def = md[nm];
                local bits = {};
                local src = (type(def.values) == 'table') and def.values or def;
                local vals = {};
                for _, v in ipairs(src) do
                    if type(v) == 'string' then vals[#vals + 1] = string.format('%q', v); end
                end
                if #vals > 0 then bits[#bits + 1] = 'values = { ' .. table.concat(vals, ', ') .. ' }'; end
                if type(def.bind) == 'string' then bits[#bits + 1] = string.format('bind = %q', def.bind); end
                if #bits > 0 then
                    L[#L + 1] = string.format('        [%q] = { %s },', nm, table.concat(bits, ', '));
                end
            end
            L[#L + 1] = '    },';
        end
    end
    -- Groups section (ADR 0009) -- carried through serialization so a Commit
    -- never wipes it (sibling of the handler sections, like Modes). Group names
    -- sorted for a stable diff; member order preserved as the player authored it.
    local gr = (type(data) == 'table') and (data.Groups or data.groups) or nil;
    if type(gr) == 'table' then
        local names = {};
        for nm, mem in pairs(gr) do
            if type(nm) == 'string' and type(mem) == 'table' then names[#names + 1] = nm; end
        end
        table.sort(names);
        if #names > 0 then
            L[#L + 1] = '    Groups = {';
            for _, nm in ipairs(names) do
                local q = {};
                for _, a in ipairs(gr[nm]) do
                    if type(a) == 'string' then q[#q + 1] = string.format('%q', a); end
                end
                L[#L + 1] = string.format('        [%q] = { %s },', nm, table.concat(q, ', '));
            end
            L[#L + 1] = '    },';
        end
    end
    L[#L + 1] = '};';
    L[#L + 1] = '';
    return table.concat(L, '\n');
end

-- ---------------------------------------------------------------------------
-- Mode state, DLAC-OWNED. modestate.lua is written on every change (the GUI --
-- a different Lua state -- reads it for display) and read BACK by
-- loadModeState when the engine loads, so a Reload LAC no longer silently
-- wipes flags a dlac reload would have kept. Slot locks stay session-only
-- (mirrored for display, never restored -- a lock is a "right now" decision).
-- ---------------------------------------------------------------------------
saveModeState = function()
    M.modesRev = (M.modesRev or 0) + 1;   -- BEFORE the guarded write: the rebuild
                                          -- signal must fire even if the mirror can't
    pcall(function()
        local dir = charDir();
        if dir == nil then return; end
        local parts = { string.format('["__version"] = %d,', M.VERSION) };   -- engine handshake
        pcall(function()   -- which job these flags belong to: another job never inherits them
            parts[#parts + 1] = string.format('["__job"] = %d,',
                AshitaCore:GetMemoryManager():GetPlayer():GetMainJob() or 0);
        end);
        parts[#parts + 1] = string.format('["__at"] = %d,', os.time());   -- freshness (restore window)
        parts[#parts + 1] = string.format('["__loadstamp"] = %q,', tostring(M._loadStamp));   -- LAC-load generation
        local lk = {};
        for s in pairs(M.locks) do lk[#lk + 1] = string.format('[%q] = true,', s); end
        table.sort(lk);
        parts[#parts + 1] = '["__locks"] = { ' .. table.concat(lk, ' ') .. ' },';   -- slot locks
        for m, v in pairs(M.modes) do
            if v == true then parts[#parts + 1] = string.format('[%q] = true,', m);
            elseif type(v) == 'string' then parts[#parts + 1] = string.format('[%q] = %q,', m, v); end
        end
        table.sort(parts);
        writeFile(dir .. 'modestate.lua',
            '-- dlac mode state (dlac-owned; read back on engine load, GUI reads for display)\nreturn { '
            .. table.concat(parts, ' ') .. ' }\n');
    end);
end

local function loadModeState()
    pcall(function()
        local dir = charDir();
        if dir == nil then return; end
        local chunk = loadfile(dir .. 'modestate.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if not ok or type(t) ~= 'table' then return; end
        -- Flags are restored only for the job that set them (the __job stamp) and
        -- only when RECENT (an hour) -- healing a mid-session Reload LAC without
        -- resurrecting last Tuesday's DT-mode at login. Anything else starts clean.
        local jid = nil;
        pcall(function() jid = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
        if type(t.__job) ~= 'number' or jid == nil or jid == 0 or t.__job ~= jid then return; end
        if type(t.__at) ~= 'number' or os.time() - t.__at > 3600 then return; end
        for k, v in pairs(t) do
            local ks = tostring(k);
            if string.sub(ks, 1, 2) ~= '__' and (v == true or type(v) == 'string') then
                M.modes[string.lower(ks)] = v;   -- cycle values re-validate on trigger load
            end
        end
    end);
end

-- Toggle modes flip true/off. CYCLE modes (defined in the trigger file's Modes section)
-- always hold one of their values: no arg -> advance to the next value (wrapping);
-- a string arg -> jump straight to that value (case-insensitive). Returns the new state.
function M.setMode(name, state)
    if type(name) ~= 'string' or name == '' then return false; end
    local ln = string.lower(name);
    local def = _trig.modeDefs and _trig.modeDefs[ln] or nil;
    if def ~= nil and def.values ~= nil then
        local cur, curIdx = M.modes[ln], 0;
        for i, v in ipairs(def.values) do
            if type(cur) == 'string' and ci(v, cur) then curIdx = i; break; end
        end
        if type(state) == 'string' then                -- jump to a named value
            for _, v in ipairs(def.values) do
                if ci(v, state) then M.modes[ln] = v; saveModeState(); return v; end
            end
            return M.modes[ln];                        -- unknown value: unchanged
        end
        local nxt = def.values[(curIdx % #def.values) + 1];
        M.modes[ln] = nxt;
        saveModeState();
        return nxt;
    end
    -- No LOCAL definition below here (definitions are per-job trigger data;
    -- VALUES are session-global). An explicit value jump works from any job --
    -- the command layer already peeled off on/off/toggle, so a string is
    -- always an intended cycle value: trust it.
    if type(state) == 'string' then
        M.modes[ln] = state;
        saveModeState();
        return state;
    end
    -- And a bare flip must not toggle-corrupt a cycle VALUE defined elsewhere
    -- into a boolean (field case: ^F6 "WHM Weapons" -- defined in BRD's
    -- triggers -- pressed on WHM would kill every WHM set gated on it).
    if state == nil and type(M.modes[ln]) == 'string' then
        print(string.format('[dlac] mode "%s" holds cycle value "%s" but THIS job\'s triggers don\'t define the cycle -- jump directly (/dl mode %s <value>), define it here (Triggers > Modes), or /dl mode %s off.',
            name, M.modes[ln], name, name));
        return M.modes[ln];
    end
    if state == nil then state = not (M.modes[ln] == true); end   -- toggle
    M.modes[ln] = (state == true) or nil;
    saveModeState();
    return M.modes[ln] == true;
end

function M.activeModes()
    local out = {};
    for m, v in pairs(M.modes) do
        out[#out + 1] = (v == true) and m or (m .. '=' .. tostring(v));
    end
    table.sort(out);
    return out;
end

-- ---------------------------------------------------------------------------
-- Starter trigger file (also written by the GUI Setup button via M.starterTriggersText).
-- Mirrors the classic HandleDefault branching so a fresh profile behaves out of the box.
-- ---------------------------------------------------------------------------
M.starterTriggersText = [[
-- dlac triggers -- written by dlac (Setup / the Triggers tab); safe to hand-edit.
-- Hot-reloaded: edits apply on the next action. No /lac reload needed.
--
-- Shape:  <Handler> = { { when = { <conditions> }, set = 'SetName', priority = n }, ... }
--         action is  set = 'Name'  (a set in your <JOB>.lua)  or  equip = { Waist = 'Karin Obi' }.
-- Handlers:   Default, Precast, Midcast, Ability, Item, Weaponskill, Preshot, Midshot,
--             PetAction (fires when YOUR PET starts an action -- Blood Pact / Ready move /
--             pet spell; your gear holds until it completes. dlac provides this event itself).
-- Conditions: status/moving/mode | any/skill/magicType/element/songType/family/name/dayWeatherBonus
--             | abilityType.  All conditions in one `when` must hold; every matching rule
--             applies, lowest priority first (later overlays earlier per slot).
-- Priority defaults by specificity: any 10 < status/skill 20 < class/element 30 < family 40
--             < exact name 50 < mode 100.  See docs/design/trigger-system.md in the dlac addon.
return {
    Default = {
        { when = { status = 'Engaged' }, set = 'Tp_Default' },
        { when = { status = 'Resting' }, set = 'Resting' },
        { when = { moving = true },      set = 'Movement' },
        { when = { status = 'Idle' },    set = 'Idle' },
    },
};
]];

-- Write the starter file for the current job if none exists. Returns ok, message.
function M.initTriggers()
    local dir = charDir();
    local path = triggersPath();
    if dir == nil or path == nil then return false, 'not logged in (no character/job).'; end
    if readFile(path) ~= nil then return false, 'already exists: ' .. path; end
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then
            ashita.fs.create_directory(dir .. 'triggers\\');
        end
    end);
    if _pok and _prof.storageExists() then pcall(function() _prof.ensureStorage(); end); end
    if not writeFile(path, M.starterTriggersText) then return false, 'could not write ' .. path; end
    M.reloadTriggers();
    return true, 'wrote starter triggers: ' .. path;
end

-- Re-read the current job's <JOB>.lua SANDBOXED and return its `sets` table --
-- the '/dl sets reload' hot-swap's reader. The sandbox is profilesets.lua's
-- field-proven trick, hardened for THIS Lua state: here the real gFunc/gState/
-- AshitaCore exist, so they (and other side-effect globals) are explicitly
-- stubbed -- re-running the profile must not equip, bind, queue or print.
-- Gear refs resolve through the real require, so the fresh entries point into
-- the same gear tables the old ones did.
local function readJobSets()
    local dir = charDir();
    if dir == nil then return nil, 'not logged in'; end
    local base = string.sub(dir, 1, #dir - 5);   -- strip the trailing 'dlac\'
    local abbr = nil;
    pcall(function()
        local j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob();
        if j ~= nil and j ~= 0 then abbr = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', j); end
    end);
    if abbr == nil or abbr == '' then return nil, 'job unknown'; end
    local chunk = loadfile(base .. abbr .. '.lua');
    if chunk == nil then return nil, 'could not open ' .. abbr .. '.lua'; end
    -- The stub also survives STRING-BUILDING: migrated profiles start with
    -- package.path = package.path .. AshitaCore:GetInstallPath() .. '...' --
    -- with AshitaCore stubbed that line must degrade to '', not error (field
    -- case: 'attempt to concatenate a table value' at WHM.lua:1). `package`
    -- is blocked too, so the sandboxed run can't append junk to the REAL path.
    local STUB; STUB = setmetatable({}, {
        __index = function() return STUB; end,
        __call = function() return STUB; end,
        __concat = function() return ''; end,
        __tostring = function() return ''; end,
    });
    local BLOCK = { gFunc = true, gState = true, gEquip = true, gSetDisplay = true, gProfile = true,
                    gSettings = true, AshitaCore = true, ashita = true, print = true, coroutine = true,
                    package = true };
    local env = setmetatable({}, {
        __index = function(_, k)
            if BLOCK[k] then return STUB; end
            local g = rawget(_G, k);
            if g ~= nil then return g; end
            return STUB;
        end,
        __newindex = function(t, k, v) rawset(t, k, v); end,
    });
    if setfenv ~= nil then setfenv(chunk, env); end
    local ok, ret = pcall(chunk);
    local s = nil;
    if ok and type(ret) == 'table' and type(ret.Sets) == 'table' then s = ret.Sets;
    elseif type(rawget(env, 'sets')) == 'table' then s = rawget(env, 'sets'); end
    if type(s) ~= 'table' then
        return nil, 'no sets table' .. (ok and '' or (': ' .. tostring(ret)));
    end
    return s, nil;
end

-- The sets source, profile-first: the active profile's sets\<JOB>.lua when it
-- exists, else the legacy job-file sandbox read above. Third return names the
-- source ('profile' / nil) for chat lines.
local function readSetsSource()
    if _pok then
        local job = nil;
        pcall(function() job = gData.GetPlayer().MainJob; end);
        if type(job) == 'string' and job ~= '' and job ~= '?' and _prof.hasSetsFile(job) then
            local dyn, derr = _prof.readSetsFile(job);
            if dyn == nil then return nil, derr; end
            return { Dynamic = dyn }, nil, 'profile';
        end
    end
    return readJobSets();
end

-- Install a fresh Sets table into the live gProfile -- the '/dl sets reload'
-- hot-swap core, shared with the profile auto-install and '/dl profile use':
-- kill flattened outputs of dynamic sets that no longer exist, swap .Dynamic in
-- place (gProfile.Sets is a live table in THIS state -- no LAC reload needed),
-- re-flatten, re-dispatch Default. Returns true, setCount | false, why.
local function installSets(fresh)
    local prof = rawget(_G, 'gProfile');
    if type(prof) ~= 'table' or type(prof.Sets) ~= 'table' then return false, 'no profile loaded'; end
    if type(prof.Sets.Dynamic) == 'table' then
        for name in pairs(prof.Sets.Dynamic) do
            if fresh.Dynamic[name] == nil then prof.Sets[name] = nil; end
        end
    end
    prof.Sets.Dynamic = fresh.Dynamic;
    M.modesRev = (M.modesRev or 0) + 1;   -- the rebuild signal utils watches
    pcall(function()
        local u = package.loaded['dlac\\utils'];
        if u ~= nil and type(u.rebuildSets) == 'function' then u.rebuildSets(prof.Sets); end
    end);
    pcall(function() M.dispatch('Default'); end);
    local n = 0;
    for _ in pairs(fresh.Dynamic) do n = n + 1; end
    return true, n;
end

-- Loud courtesy check before an install replaces file-authored sets: any name in
-- the incoming Dynamic that the loaded profile ALSO defines as a plain (static)
-- set gets silently shadowed by the flatten -- say so once per profile load.
local function warnShadowedStatics(fresh)
    local prof = rawget(_G, 'gProfile');
    if type(prof) ~= 'table' or type(prof.Sets) ~= 'table' then return; end
    local dynNow = (type(prof.Sets.Dynamic) == 'table') and prof.Sets.Dynamic or {};
    local hit = {};
    for name in pairs(fresh.Dynamic) do
        if prof.Sets[name] ~= nil and dynNow[name] == nil then hit[#hit + 1] = tostring(name); end
    end
    if #hit == 0 then return; end
    table.sort(hit);
    printwarn('profile dynamic set(s) shadow static set(s) of the same name in your job file: '
        .. table.concat(hit, ', ') .. ' -- the profile version wins; rename one to keep both.');
end

-- ---------------------------------------------------------------------------
-- Commands: /dl mode | why | triggers | sets reload   (registered in the LAC
-- state only, where the mode flags and traces live; the addon copy is silent).
-- ---------------------------------------------------------------------------
local function argStart(raw)
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then return 7; end
    if raw == '/dl'   or string.sub(raw, 1, 4) == '/dl '   then return 5; end
    return nil;
end

if inLac() then
    loadModeState();        -- dlac-owned flags: restore (same job only) BEFORE the first mirror
    pcall(saveModeState);   -- then mirror whatever we start with for the GUI

    -- LAC only parses HandleDefault while OUTGOING packets flow (packethandlers.lua
    -- drives it from HandleOutgoingPacket) -- stand still with a menu open and the
    -- dispatches starve, which read as "maxmp stops the moment the equipment window
    -- opens" (the window itself blocks nothing: field-verified, /lac equip works
    -- with it up). Drive the SAME flow on a throttled frame tick so Default
    -- dispatching is packet-independent. The tick also watches the main job: a job
    -- change drops maxmp immediately, before it can battery the new job's gear.
    -- Upstream parity for LEGACY profiles too: while the pet's action is in
    -- flight, HandleDefault must not run AT ALL -- a hand-written profile
    -- equips sets.Idle unconditionally and stomps the PetAction gear (field
    -- case: Yinyang Robe in Idle.Body erased the pact piece the moment it was
    -- worn). The engine-side hold only covers dlac dispatches, so LAC's own
    -- entry point is wrapped ONCE; the tick's calls flow through it as well.
    pcall(function()
        local st = rawget(_G, 'gState');
        if st ~= nil and type(st.HandleEquipEvent) == 'function' and st._dlacPetHold ~= true then
            local orig = st.HandleEquipEvent;
            st.HandleEquipEvent = function(ev, style)
                if ev == 'HandleDefault' then
                    local pa = st.PetAction;
                    if pa ~= nil and (pa.Completion == nil or os.clock() < pa.Completion) then return; end
                end
                return orig(ev, style);
            end;
            st._dlacPetHold = true;
        end
    end);

    -- ENGINE SELF-SWAP: hot-reload this file the way the trigger data reloads.
    -- The addon's seeder refreshes <char>\dlac\dispatch.lua on every dlac
    -- (re)load, but LAC's require cache keeps running the OLD code until a full
    -- Reload LAC -- the one reload the version banner still asks for. Instead:
    -- every ~2s the tick parses the seeded file's version assignment; when it
    -- differs from the running version, the file is re-executed INTO THIS SAME
    -- MODULE TABLE (the __dlacEngineRoot handshake at the top of the file), so
    -- utils' captured reference and the profiles' shims run the new code with
    -- no re-require. The re-run re-registers both event handlers (unregister-
    -- first makes the replace deterministic), skips the pet-hold wrap
    -- (_dlacPetHold guard), and re-runs loadModeState + saveModeState -- a swap
    -- inherits Reload-LAC semantics exactly: modes survive via the modestate
    -- mirror (whose re-stamp also clears the GUI banner), slot locks reset.
    -- Failure degrades to today's behavior: a syntax error is caught by
    -- loadstring BEFORE anything executes; a runtime error mid-execution rolls
    -- the version stamp back to the old one (the mixed state IS old-with-holes;
    -- the banner must stay up) and the broken CONTENT is remembered on the
    -- SHARED table (M._swapFailedRaw -- a half-swapped generation may already
    -- be running the new tick), so a broken build is tried once per edit, not
    -- every 2 seconds, and a same-version fix still gets its retry.
    local _swapAt = 0;
    local function trySelfSwap()
        if os.clock() < _swapAt then return; end
        _swapAt = os.clock() + 2.0;
        local dir = charDir();
        if dir == nil then return; end
        local path = dir .. 'dispatch.lua';
        local raw = readFile(path);
        if raw == nil or raw == M._swapFailedRaw then return; end
        local v = tonumber(string.match(raw, 'M%.VERSION%s*=%s*(%d+)'));
        if v == nil or v == M.VERSION then return; end
        local chunk, cerr = (loadstring or load)(raw, '@' .. path);
        if chunk == nil then
            M._swapFailedRaw = raw;
            printerr(string.format('engine hot-swap: v%d does not parse (%s) -- staying on v%d.',
                v, tostring(cerr), M.VERSION));
            return;
        end
        local old = M.VERSION;
        rawset(_G, '__dlacEngineRoot', M);
        local ok, err = pcall(chunk);
        rawset(_G, '__dlacEngineRoot', nil);
        if not ok then
            M._swapFailedRaw = raw;
            M.VERSION = old;        -- the partial run may have claimed v already
            pcall(saveModeState);   -- ...and stamped it: re-stamp old, keep the banner honest
            printerr(string.format('engine hot-swap v%d -> v%d FAILED mid-load (%s) -- click Reload LAC.',
                old, v, tostring(err)));
            return;
        end
        M._swapFailedRaw = nil;
        print(string.format('[dlac] engine hot-swapped v%d -> v%d -- no Reload LAC needed (modes kept, slot locks reset).',
            old, v));
    end

    -- A self-swap re-runs these registrations; unregister-first makes the
    -- replace deterministic whatever Ashita's same-alias behavior is (pcall:
    -- on the FIRST load there is nothing to unregister).
    pcall(function() ashita.events.unregister('d3d_present', 'dlac-dispatch-tick'); end);
    local _tickAt, _tickJob, _tickPet = 0, nil, nil;
    -- The JOB is part of the identity -- see M.jobReady / ADR 0007. (v46-v49 carried
    -- a /dl instdiag dump and tick counters here; it is what found the bug and it is
    -- in git history -- cb2fbe2..40288e3 -- if this class of thing ever returns.)
    local _instProf, _instAct, _instJob = nil, nil, nil;   -- gProfile identity + profile name + JOB we resolved for
    ashita.events.register('d3d_present', 'dlac-dispatch-tick', function()
        pcall(function()
            if os.clock() < _tickAt then return; end
            _tickAt = os.clock() + 0.4;
            trySelfSwap();   -- engine hot-reload check (own ~2s gate inside)
            local j = nil;
            pcall(function() j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
            if j ~= nil and j ~= 0 then
                if _tickJob ~= nil and j ~= _tickJob and M.modes['maxmp'] ~= nil then
                    M.modes['maxmp'] = nil;
                    saveModeState();
                    print('[dlac] maxmp: off (job changed).');
                end
                _tickJob = j;
            end
            local st = rawget(_G, 'gState');
            if rawget(_G, 'gProfile') == nil or st == nil then return; end
            if st.PlayerAction ~= nil or type(st.HandleEquipEvent) ~= 'function' then return; end
            -- NEVER drive HandleDefault while ZONING: LAC's own flow pauses with
            -- the packet stream, but this tick doesn't -- and a legacy profile
            -- that equips unconditionally then dies inside LAC's equip.lua
            -- ("attempt to index local 'equippedItem'": GetEquippedItem is nil
            -- mid-zone; field case: BRD with hand-written HandleDefault).
            local zoning = false;
            pcall(function()
                local pl = AshitaCore:GetMemoryManager():GetPlayer();
                if pl ~= nil and pl.GetIsZoning ~= nil then
                    local z = pl:GetIsZoning();
                    if z == true or (type(z) == 'number' and z ~= 0) then zoning = true; end
                end
            end);
            if not zoning then
                -- belt + braces: probe the EXACT read that crashes equip.lua
                local probe = nil;
                pcall(function() probe = AshitaCore:GetMemoryManager():GetInventory():GetEquippedItem(0); end);
                if probe == nil then zoning = true; end
            end
            if zoning then return; end
            -- PROFILE AUTO-INSTALL: a fresh gProfile (LAC load / job change --
            -- LAC builds a new profile table each load) or an active-pointer
            -- flip means the live .Dynamic is not the active profile's data.
            -- Install only when profile storage HAS a sets file for this job:
            -- unmigrated characters keep LAC's file-loaded sets, exactly as
            -- before. This is how "LAC picks the job file, dlac picks the
            -- profile" composes: the job resolves the file INSIDE the profile.
            local gprof = rawget(_G, 'gProfile');
            local act = _pok and _prof.activeName() or nil;
            -- The JOB is part of the identity, and leaving it out is the field bug
            -- (Hunklor, 07-15: SAM/DNC logged in with Dynamic=0 and latched=YES,
            -- while hasSetsFile('SAM') read true seconds later). gData's MainJob is
            -- a MEMORY read and settles on its own schedule -- LAC picks gProfile
            -- from the 0x0A packet's job instead, so at login the two disagree for
            -- a moment. The tick would resolve for whatever job it saw FIRST, latch
            -- on gProfile+profile-name alone, and never look again -- and gProfile
            -- does not change when the job read merely catches up. A latch must
            -- therefore remember WHICH JOB it answered for.
            local job = nil;
            if j ~= nil and j ~= 0 then
                pcall(function() job = gData.GetPlayer().MainJob; end);
            end
            if M.jobReady(j, job) then
                if gprof ~= _instProf or act ~= _instAct or job ~= _instJob then
                    -- "Has this job a profile sets file?" is also UNANSWERABLE until
                    -- the character dir resolves (charBase -> gState.PlayerName/
                    -- PlayerId, else the party fallback): hasSetsFile then reads
                    -- false meaning "can't tell yet", indistinguishable from "legacy
                    -- job, nothing to install". Latching on THAT answer kills the
                    -- install for the whole session -- only a fresh gProfile retries
                    -- (Reload LAC or a job change), so a plain login and play-the-
                    -- same-job silently runs on an empty .Dynamic, every trigger
                    -- matching and equipping nothing, because equipSetByName skips a
                    -- missing set in silence (v35). Latent since the storage move
                    -- (v33), masked for two days by dev reload/job-flip habits.
                    -- Latch only once the question was actually ANSWERED -- every
                    -- other reader in this engine already retries; this was the sole
                    -- latch.
                    local answerable = (not _pok) or (_prof.setsPath(job) ~= nil);
                    if _pok and _prof.hasSetsFile(job) then
                        local dyn, derr = _prof.readSetsFile(job);
                        if type(dyn) == 'table' then
                            local fresh = { Dynamic = dyn };
                            warnShadowedStatics(fresh);
                            local okI, n = installSets(fresh);
                            if okI then
                                print(string.format('[dlac] profile "%s": %d dynamic set(s) installed for %s.',
                                    tostring(act), n, job));
                            end
                        else
                            printerr('profile sets not installed: ' .. tostring(derr));
                        end
                    end
                    -- Answered: latch (legacy jobs too -- probe once per load, not per
                    -- tick). Unanswerable: leave it, and the next tick (0.4s) retries.
                    if answerable then _instProf, _instAct, _instJob = gprof, act, job; end
                end
            end
            -- PET actions: synthesized here (see EVENTS) -- dispatch ONCE per
            -- action start; the Default hold in M.dispatch keeps the pet gear
            -- on until the action completes.
            local pa = st.PetAction;
            if pa ~= nil then
                local key = tostring(pa.Id or '?') .. '@' .. tostring(pa.Completion or 0);
                if key ~= _tickPet then
                    _tickPet = key;
                    -- gFunc.EquipSet only LANDS when LAC brackets the call with
                    -- ClearBuffer/ProcessBuffer -- it does that around its own
                    -- handler invocations, so the tick must bracket its own
                    -- dispatch the same way or the equips sit in the buffer and
                    -- evaporate (field case: /dl why showed the PetAction match,
                    -- nothing swapped).
                    pcall(function()
                        local eq = rawget(_G, 'gEquip');
                        if eq ~= nil and type(eq.ClearBuffer) == 'function' and type(eq.ProcessBuffer) == 'function' then
                            eq.ClearBuffer();
                            local cc = st.CurrentCall;
                            st.CurrentCall = 'PetAction';   -- LAC's debug prints name the caller
                            pcall(function() M.dispatch('PetAction'); end);
                            st.CurrentCall = cc or 'N/A';
                            eq.ProcessBuffer('auto');
                        else
                            M.dispatch('PetAction');
                        end
                    end);
                end
            else
                _tickPet = nil;
            end
            st.HandleEquipEvent('HandleDefault', 'auto');
        end);
    end);

    pcall(function() ashita.events.unregister('command', 'dlac-dispatch'); end);
    ashita.events.register('command', 'dlac-dispatch', function(e)
        local start = argStart(string.lower(e.command));
        if start == nil then return; end
        local args = {};
        for a in string.gmatch(string.sub(e.command, start), '%S+') do args[#args + 1] = a; end
        local sub = args[1] and string.lower(args[1]) or nil;
        -- WHITELIST FIRST, branch second: a new subcommand needs adding HERE as well as
        -- below, or it returns in silence and looks like the command does not exist
        -- (v46's /dl instdiag, an hour lost to exactly this).
        if sub ~= 'mode' and sub ~= 'why' and sub ~= 'triggers' and sub ~= 'env' and sub ~= 'lock' and sub ~= 'sets' and sub ~= 'profile' and sub ~= 'ls' then return; end
        e.blocked = true;

        if sub == 'ls' then
            -- Lockstyle sets (v38; per-profile v40; JOB ENTRY v41; engine-built
            -- packet v42): the GUI (lockstyle.lua, addon state) edits the boxes;
            -- THIS side applies by building the 0x053 itself (_lockstylePacket
            -- above -- gFunc.LockStyle is gone, see the note there). gFunc
            -- presence still gates the handler to the LAC state: the same
            -- command fires in the ADDON state too (gearui/triggersui require
            -- dispatch there); one state, one printer.
            local g = rawget(_G, 'gFunc');
            if g == nil then return; end
            if string.lower(tostring(args[2] or '')) ~= 'apply' then
                print('[dlac] usage: /dl ls apply [box]   (GUI: the armor button in the dlac header)');
                return;
            end
            local dir = charDir();
            if dir == nil then print('[dlac] lockstyle: not logged in.'); return; end
            -- boxes are per JOB ENTRY (v41): resolve the current job's file --
            -- the SAME resolver the GUI uses (profiles.lua), so both states
            -- pick one file (falls back v40 per-profile file, then global)
            local job;
            pcall(function() job = gData.GetPlayer().MainJob; end);
            if type(job) ~= 'string' or job == '' or job == '?' then job = nil; end
            local lsPath = (_pok and job ~= nil and _prof.readLockstylesPath(job) or nil) or (dir .. 'lockstyles.lua');
            local raw = readFile(lsPath);
            if raw == nil then print('[dlac] lockstyle: no lockstyle sets saved yet (armor button in the dlac header).'); return; end
            local t = nil;
            local chunk = (loadstring or load)(raw, '@lockstyles.lua');
            if chunk ~= nil then local okc, v = pcall(chunk); if okc then t = v; end end
            local set, why, box = M._lockstyleFrom(t, tonumber(args[3]));
            if set == nil then print('[dlac] lockstyle: ' .. tostring(why)); return; end
            -- Build the 0x053 ourselves (v42). The LAC state's require resolves
            -- dlac\gear to the char folder's REAL gear.lua -- names in the boxes
            -- came from it, so NameToObject is the exact reverse map.
            local gr = nil;
            pcall(function() gr = require('dlac\\gear'); end);
            local function resolveId(name)
                local id = nil;
                pcall(function()
                    local rec = gr and gr.NameToObject and gr.NameToObject[name] or nil;
                    if rec ~= nil then id = tonumber(rec.Id); end
                end);
                if id == nil then
                    pcall(function()
                        local r = AshitaCore:GetResourceManager():GetItemByName(name, 2)
                               or AshitaCore:GetResourceManager():GetItemByName(name, 0);
                        if r ~= nil then id = tonumber(r.Id); end
                    end);
                end
                return id;
            end
            local function equippedId(slot)
                local id = nil;
                pcall(function()
                    local eq = gData.GetEquipment();
                    local it = eq ~= nil and eq[slot] or nil;
                    if it ~= nil and it.Item ~= nil then id = tonumber(it.Item.Id); end
                end);
                return id;
            end
            local pkt, r = M._lockstylePacket(set, resolveId, equippedId);
            -- Predict the server's SILENT job gate so "nothing changed" has a
            -- name: a piece failing canEquipItemOnAnyJob leaves the OLD style
            -- on that slot, with no message from the server at all.
            local lv = {};
            pcall(function()
                local pl = AshitaCore:GetMemoryManager():GetPlayer();
                for i, ab in ipairs(M._LS_JOBS) do lv[ab] = tonumber(pl:GetJobLevel(i)) or 0; end
            end);
            for slot, nm in pairs(r.sent) do
                local rec = gr and gr.NameToObject and gr.NameToObject[nm] or nil;
                if rec ~= nil and not M._lsStyleGate(rec, lv) then
                    print(string.format('[dlac] lockstyle: %s will KEEP ITS OLD LOOK -- "%s" needs %s Lv%d,'
                        .. ' and no job of yours is there yet (server: one of YOUR jobs must be able to wear it).',
                        slot, nm, table.concat(type(rec.Jobs) == 'table' and rec.Jobs or { '?' }, '/'),
                        tonumber(rec.Level) or 0));
                end
            end
            -- Weapon styles only take over the same category (hasValidStyle);
            -- warn when the style's type visibly disagrees with what is worn.
            for _, ws in ipairs({ 'Main', 'Range' }) do
                local nm = r.sent[ws];
                if nm ~= nil then
                    local st, et = nil, nil;
                    pcall(function()
                        local srec = gr and gr.NameToObject and gr.NameToObject[nm] or nil;
                        st = srec ~= nil and srec.Type or nil;
                        local eq = gData.GetEquipment();
                        local en = eq ~= nil and eq[ws] ~= nil and eq[ws].Name or nil;
                        local erec = en ~= nil and gr and gr.NameToObject and gr.NameToObject[en] or nil;
                        et = erec ~= nil and erec.Type or nil;
                    end);
                    if st ~= nil and et ~= nil and st ~= et then
                        print(string.format('[dlac] lockstyle: %s style "%s" (%s) will NOT show over your'
                            .. ' equipped %s -- weapon styles need the same category (server rule).',
                            ws, nm, tostring(st), tostring(et)));
                    end
                end
            end
            for _, nm in ipairs(r.missing) do
                print(string.format('[dlac] lockstyle: "%s" did not resolve to an item id -- its slot will show EMPTY.', nm));
            end
            local oks = pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0x053, pkt); end);
            if not oks then print('[dlac] lockstyle: packet send failed.'); return; end
            local n = 0;
            for _ in pairs(r.sent) do n = n + 1; end
            print(string.format('[dlac] lockstyle "%s" (box %d) sent -- %d styled slot%s; unnamed slots hold your'
                .. ' current gear\'s look.', tostring(why), box, n, n == 1 and '' or 's'));
            return;
        end

        if sub == 'sets' then
            if string.lower(tostring(args[2] or '')) ~= 'reload' then
                print('[dlac] usage: /dl sets reload   (hot-swap the committed sets, no LAC reload)');
                return;
            end
            -- Hot-swap the PLAN without a LAC reload. gProfile.Sets is just a live
            -- table in THIS Lua state -- "Reload LAC" was only ever about the FILE
            -- changing under it (field insight: ffxi-lac loops that mutated set
            -- objects took effect immediately). A Commit rewrites the profile sets
            -- file (or, legacy, <JOB>.lua); re-read and install (installSets).
            local fresh, ferr, src = readSetsSource();
            if fresh == nil or type(fresh.Dynamic) ~= 'table' then
                print('[dlac] sets hot-swap failed (' .. tostring(ferr) .. ') -- click Reload LAC instead.');
                return;
            end
            local okI, n = installSets(fresh);
            if okI ~= true then print('[dlac] sets reload: ' .. tostring(n)); return; end
            _instProf, _instAct = rawget(_G, 'gProfile'), (_pok and _prof.activeName() or nil);
            print(string.format('[dlac] sets hot-swapped (%d dynamic set(s)%s) -- live now, no LAC reload needed.',
                n, (src == 'profile' and _pok) and (' from profile "' .. _prof.activeName() .. '"') or ''));
            return;
        end

        if sub == 'profile' then   -- the profile storage layer (profiles.lua)
            if not _pok then
                print('[dlac] profile: profiles.lua is missing from <char>\\dlac\\ -- reload the dlac addon to reseed it.');
                return;
            end
            local a2 = args[2] and string.lower(args[2]) or nil;
            local job = nil;
            pcall(function() job = gData.GetPlayer().MainJob; end);
            if type(job) ~= 'string' or job == '' or job == '?' then job = nil; end

            if a2 == nil or a2 == 'status' or a2 == 'list' then
                local act = _prof.activeName();
                print('[dlac] active profile: ' .. act
                    .. (_prof.storageExists() and '' or '   (no profile storage yet -- legacy layout; see /dl profile migrate)'));
                if job ~= nil then
                    print(string.format('[dlac]   %s sets:     %s', job,
                        _prof.hasSetsFile(job) and tostring(_prof.setsPath(job)) or ('legacy (' .. job .. '.lua sets.Dynamic)')));
                    print(string.format('[dlac]   %s triggers: %s', job, tostring(triggersPath())));
                end
                local names = _prof.listProfiles();
                if names ~= nil and #names > 0 then print('[dlac]   profiles on disk: ' .. table.concat(names, ', ')); end
                print('[dlac] usage: /dl profile use <name> | new <name> | clone <newname> | migrate [go]');
                return;
            end

            if a2 == 'use' and args[3] ~= nil then
                local nm = _prof.sanitizeName(args[3]);
                if nm == nil then print('[dlac] profile use: bad name (letters/digits/_/- only).'); return; end
                local okA, aerr = _prof.setActive(nm);
                if not okA then print('[dlac] profile use: ' .. tostring(aerr)); return; end
                _prof.ensureStorage(nm);
                M.reloadTriggers();   -- trigger path changed -> re-read now, not in 1s
                local fresh = select(1, readSetsSource());
                if fresh ~= nil and type(fresh.Dynamic) == 'table' then
                    warnShadowedStatics(fresh);
                    local okI, n = installSets(fresh);
                    if okI == true then
                        print(string.format('[dlac] profile "%s" active -- %d dynamic set(s) installed, triggers reloaded. No LAC reload needed.', nm, n));
                    else
                        print(string.format('[dlac] profile "%s" active -- sets install: %s', nm, tostring(n)));
                    end
                else
                    print(string.format('[dlac] profile "%s" active -- no sets for this job yet (build them in the Sets tab).', nm));
                end
                _instProf, _instAct = rawget(_G, 'gProfile'), _prof.activeName();
                return;
            end

            if a2 == 'new' and args[3] ~= nil then
                local nm = _prof.sanitizeName(args[3]);
                if nm == nil then print('[dlac] profile new: bad name (letters/digits/_/- only).'); return; end
                _prof.ensureStorage(nm);
                print(string.format('[dlac] profile "%s" created (empty). Activate it with: /dl profile use %s', nm, nm));
                return;
            end

            if a2 == 'clone' and args[3] ~= nil then
                local src = _prof.activeName();
                local n, cerr = _prof.cloneProfile(src, args[3]);
                if n == nil then print('[dlac] profile clone: ' .. tostring(cerr)); return; end
                print(string.format('[dlac] cloned "%s" -> "%s" (%d file(s)). Activate with: /dl profile use %s', src, args[3], n, tostring(args[3])));
                return;
            end

            if a2 == 'migrate' then
                local go = args[3] ~= nil and string.lower(args[3]) == 'go';
                local done = _prof.migrate(go, print);
                if go and done ~= nil and done > 0 then
                    print('[dlac] reloading LuaAshitacast so the clean shim takes over...');
                    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/addon reload luashitacast'); end);
                end
                return;
            end

            print('[dlac] usage: /dl profile [status] | use <name> | new <name> | clone <newname> | migrate [go]');
            return;
        end

        if sub == 'lock' then   -- slot locks: the engine stops equipping into them
            local slot = args[2] and string.lower(args[2]) or nil;
            if slot == nil then
                local out = {};
                for s in pairs(M.locks) do out[#out + 1] = s; end
                table.sort(out);
                print('[dlac] locked slots: ' .. ((#out > 0) and table.concat(out, ', ') or '(none)')
                    .. '   (/dl lock <slot|all> [on|off|toggle])');
                return;
            end
            local a3 = args[3] and string.lower(args[3]) or nil;
            local state = nil;                       -- default: toggle
            if a3 == 'on' then state = true; elseif a3 == 'off' then state = false; end
            local res = M.setLock(slot, state);
            if res == nil then
                print('[dlac] unknown slot: ' .. slot .. '  (main/sub/range/ammo/head/neck/ear1/ear2/body/hands/ring1/ring2/back/waist/legs/feet or all)');
            else
                print(string.format('[dlac] lock %s %s -- the engine %s equip into %s',
                    slot, res and 'ON' or 'OFF', res and 'will NOT' or 'may again',
                    (slot == 'all') and 'any slot' or ('the ' .. slot .. ' slot')));
            end
            return;
        end

        if sub == 'env' then   -- day/weather as the engine sees it (the obi's decision input)
            local env = nil;
            pcall(function() env = gData.GetEnvironment(); end);
            if env == nil then print('[dlac] env unavailable (not logged in?).'); return; end
            print(string.format('[dlac] day: %s (element %s)   weather: %s (element %s)',
                tostring(env.Day), tostring(env.DayElement), tostring(env.Weather), tostring(env.WeatherElement)));
            local parts = {};
            for _, el in ipairs({ 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark' }) do
                local n = netForElement(el);
                if n ~= 0 then parts[#parts + 1] = string.format('%s %+d', el, n); end
            end
            print('[dlac] net signs: ' .. ((#parts > 0) and table.concat(parts, ', ') or '(all neutral)')
                .. '   -- dlac:AutoObi equips only when its spell\'s element is positive');
            local mn = menuName();
            print('[dlac] open menu: ' .. ((mn ~= '') and ('"' .. mn .. '"') or '(none)'));
            return;
        end

        if sub == 'mode' then
            if args[2] == nil then
                local act = M.activeModes();
                print('[dlac] active modes: ' .. ((#act > 0) and table.concat(act, ', ') or '(none)')
                    .. '   (/dl mode <name> [on|off|toggle])');
                return;
            end
            ensureLoaded();                          -- cycle definitions live in the trigger file
            -- Mode names may contain SPACES ("WHM Weapons"). Resolve by longest
            -- arg-join that names a KNOWN mode (definition or live flag); whatever
            -- follows is the state. Unknown names: a trailing on/off/toggle splits
            -- off, otherwise the whole tail is the (new toggle's) name.
            local function knownMode(nm)
                local lnm = string.lower(nm);
                return (_trig.modeDefs ~= nil and _trig.modeDefs[lnm] ~= nil) or (M.modes[lnm] ~= nil);
            end
            local name, stateStr = nil, nil;
            for cut = #args, 2, -1 do
                local cand = table.concat(args, ' ', 2, cut);
                if knownMode(cand) then
                    name = cand;
                    if cut < #args then stateStr = table.concat(args, ' ', cut + 1); end
                    break;
                end
            end
            if name == nil then
                local last = string.lower(args[#args]);
                if #args > 2 and (last == 'on' or last == 'off' or last == 'toggle') then
                    name, stateStr = table.concat(args, ' ', 2, #args - 1), last;
                else
                    name = table.concat(args, ' ', 2);
                end
            end
            local state = nil;                       -- default: toggle / cycle to next
            if stateStr ~= nil then
                local l3 = string.lower(stateStr);
                if l3 == 'on' then state = true;
                elseif l3 == 'off' then state = false;
                elseif l3 == 'toggle' then state = nil;
                else state = stateStr; end           -- cycle mode: jump straight to this value
            end
            local ln = string.lower(name);
            local before = M.modes[ln];
            local res = M.setMode(name, state);
            if res ~= before then
                -- Make the flip visible NOW instead of at the next game event:
                -- re-flatten the Dynamic sets (mode-gated entries pick differently)
                -- and re-run the Default dispatch so the equip follows the mode.
                pcall(function()
                    local u = package.loaded['dlac\\utils'];
                    local prof = rawget(_G, 'gProfile');
                    if u ~= nil and type(u.rebuildSets) == 'function'
                       and prof ~= nil and type(prof.Sets) == 'table' then
                        u.rebuildSets(prof.Sets);
                    end
                end);
                pcall(function() M.dispatch('Default'); end);
            end
            local function disp(v)
                if v == true then return 'ON'; end
                if v == nil or v == false then return 'off'; end
                return tostring(v);
            end
            local def = _trig.modeDefs and _trig.modeDefs[ln] or nil;
            local shown = (def ~= nil and def.name) or name;
            print(string.format('[dlac] %s: %s -> %s', shown, disp(before), disp(res)));
            return;
        end

        if sub == 'why' then
            local any = false;
            for _, ev in ipairs(EVENTS) do
                local tr = _trace[ev];
                if tr ~= nil then
                    any = true;
                    print(string.format('[dlac] %s  (%s)  %s', ev, tr.time, tr.action or ''));
                    for _, l in ipairs(tr.lines) do print('    ' .. l); end
                end
            end
            if _trig.err ~= nil then print('[dlac] trigger file error: ' .. _trig.err); end
            if not any then print('[dlac] why: nothing dispatched yet (do something, then ask again).'); end
            return;
        end

        -- sub == 'triggers'
        local a2 = args[2] and string.lower(args[2]) or nil;
        if a2 == 'reload' then
            M.reloadTriggers();
            -- silent: the GUI queues this after trigger edits; the re-read is
            -- automatic on the next action either way (errors still print).
        elseif a2 == 'init' then
            local ok, msg = M.initTriggers();
            print('[dlac] triggers init: ' .. tostring(msg));
        else
            print('[dlac] triggers file: ' .. tostring(triggersPath())
                .. ((_trig.err ~= nil) and ('   [error: ' .. _trig.err .. ']') or ''));
            print('[dlac] usage: /dl triggers reload | init | path');
        end
    end);
end

return M;
