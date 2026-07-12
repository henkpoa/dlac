--[[
    dlac/dispatch.lua — the trigger dispatch engine.
    Design: docs/design/trigger-system.md  (ADR 0002 data-driven dispatch,
    ADR 0003 overlay semantics, ADR 0004 automations land here in M2).

    Runs inside LuaAshitacast's Lua state: profiles call utils.dispatch('<Handler>')
    as the LAST line of each Handle* function, and this module reads the per-job
    trigger data file, matches the live action/player against each rule's `when`,
    and EquipSets every match in ascending priority (later overlays earlier per slot).

    Trigger file:  <char>\dlac\triggers\<JOB>.lua   (a `return {...}` module)
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

    Every gData / gFunc / io read is pcall-guarded: a broken trigger file or a nil
    manager can never take down a cast or profile loading (it just no-ops + reports).
]]--

local M = {};

-- Engine version handshake: bump on EVERY behavioral change to this file. The
-- LAC-state copy stamps its version into the modestate mirror; the GUI compares
-- against the addon-state copy and shows "Reload LAC" when LAC is running stale
-- code (the seeded file only re-requires when LuaAshitacast itself reloads).
M.VERSION = 22;   -- 22: hot-swap sandbox survives profile path-building (concat on stubs)

-- Colored [dlac] chat output (chatfmt); plain print when unavailable. The shadowed
-- `print` re-heads "[dlac] ..."-prefixed lines with the colored header.
local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local print = (_cfok and type(_cfmt.print) == 'function') and _cfmt.print or print;
local function printwarn(s) if _cfok then _cfmt.warn(s); else print('[dlac] ' .. s); end end
local function printerr(s)  if _cfok then _cfmt.err(s);  else print('[dlac] ' .. s); end end

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

local EVENTS = { 'Default', 'Precast', 'Midcast', 'Ability', 'Item', 'Weaponskill', 'Preshot', 'Midshot' };
local EVENT_CANON = {};
for _, e in ipairs(EVENTS) do EVENT_CANON[string.lower(e)] = e; end
M.EVENTS = EVENTS;
function M.canonEvent(e) return EVENT_CANON[string.lower(tostring(e))]; end

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

-- triggers\<JOB>.lua for the CURRENT main job (trigger files are per-job: they
-- reference set names, and set names live in <JOB>.lua). nil pre-login.
local function triggersPath()
    local dir = charDir();
    if dir == nil then return nil; end
    local job;
    pcall(function() job = gData.GetPlayer().MainJob; end);
    if type(job) ~= 'string' or job == '' or job == '?' then return nil; end
    return dir .. 'triggers\\' .. job .. '.lua';
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

local MATCHERS = {
    any             = function() return true; end,
    status          = function(v, ctx) return ctx.player ~= nil and ci(ctx.player.Status, v); end,
    moving          = function(v, ctx) return ctx.player ~= nil and ((ctx.player.IsMoving == true) == (v == true)); end,
    mode            = function(v) return M.modeActive(v); end,
    name            = function(v, ctx) return ctx.action ~= nil and ci(ctx.action.Name, v); end,
    contains        = function(v, ctx) return nameContains(ctx, v); end,   -- substring: 'Madrigal' hits Blade+Sword
    family          = function(v, ctx) return nameContains(ctx, v); end,   -- legacy alias of contains
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
local function normalize(t)
    local out, warns = {}, {};
    for k, v in pairs(t) do
        local ev = EVENT_CANON[string.lower(tostring(k))];
        if ev == nil then
            local lk = string.lower(tostring(k));
            if lk ~= 'setoptions' and lk ~= 'modes' then   -- sibling sections, not handlers
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
                    local when, parts, dead = {}, {}, false;
                    for ck, cv in pairs(r.when) do
                        local lk = string.lower(tostring(ck));
                        if TIER[lk] == nil then
                            warns[#warns + 1] = string.format('%s rule %d: unknown condition %q — rule dropped', ev, i, tostring(ck));
                            dead = true;
                            break;
                        end
                        when[lk] = cv;
                        parts[#parts + 1] = lk .. '=' .. tostring(cv);
                    end
                    if not dead then
                        local prio = tonumber(r.priority);
                        if prio == nil then
                            prio = 10;
                            for lk in pairs(when) do
                                if TIER[lk] > prio then prio = TIER[lk]; end
                            end
                        end
                        table.sort(parts);
                        list[#list + 1] = {
                            when  = when,
                            set   = (r.set ~= nil) and tostring(r.set) or nil,
                            equip = (type(r.equip) == 'table') and r.equip or nil,
                            prio  = prio,
                            ord   = #list + 1,
                            label = (#parts > 0) and table.concat(parts, '+') or 'any',
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
local function resolveVirtual(marker, ctx)
    local a = ensureAutoLoaded();
    if a == nil then return nil, 'no autogear manifest (Automations > Rescan owned gear)'; end
    local el = ctx.action and ctx.action.Element;
    if type(el) ~= 'string' or ci(el, 'Non-Elemental') then el = nil; end
    local lvl = playerLevel(ctx);
    local mk = string.lower(tostring(marker));
    -- canonical new names + the original spellings (existing sets keep working)
    if mk == 'dlac:autoiridescence' then mk = 'dlac:autostaff'; end
    if mk == 'dlac:elementalobi'    then mk = 'dlac:autoobi';   end
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

local function equipResolved(s, ctx)
    local out, notes = nil, nil;
    local anyLocks = (next(M.locks) ~= nil);
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
    for slot, v in pairs(s) do
        if anyLocks and M.locks[string.lower(tostring(slot))] == true then
            if out == nil then
                out = {};
                for k2, v2 in pairs(s) do out[k2] = v2; end
            end
            out[slot] = nil;                           -- locked: the engine leaves it alone
            notes = notes or {};
            notes[#notes + 1] = string.format('%s=LOCKED (kept as worn)', tostring(slot));
        elseif type(v) == 'string' and string.lower(string.sub(v, 1, 5)) == 'dlac:' then
            if out == nil then
                out = {};
                for k2, v2 in pairs(s) do out[k2] = v2; end
            end
            local marker, fallback = v, nil;
            local p = string.find(v, '|', 1, true);
            if p ~= nil then marker, fallback = string.sub(v, 1, p - 1), string.sub(v, p + 1); end
            local nm, why = resolveVirtual(marker, ctx);
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
    pcall(function() gFunc.EquipSet(out or s); end);
    local note = '';
    if notes ~= nil then
        table.sort(notes);
        note = '  [' .. table.concat(notes, ', ') .. ']';
    end
    return note, (out or s);   -- the table actually equipped (for slot attribution)
end

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
end

-- ---------------------------------------------------------------------------
-- Dispatch
-- ---------------------------------------------------------------------------
local function buildCtx(event)
    local ctx = { event = event };
    pcall(function() ctx.player = gData.GetPlayer(); end);
    if event ~= 'Default' then
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

local _unknownSetWarned = {};   -- once per set name per session: matched-but-missing is LOUD
local function equipSetByName(name, ctx)
    local s;
    pcall(function()
        local prof = rawget(_G, 'gProfile');
        if type(prof) == 'table' and type(prof.Sets) == 'table' then s = prof.Sets[name]; end
    end);
    if type(s) ~= 'table' then
        -- A trigger MATCHED but its target set is absent from this job's profile
        -- (field case: a Midshot rule pointing at a set never committed on WAR --
        -- the silent skip cost an hour of ghost-hunting). Warn once per name;
        -- the per-frame skip itself stays quiet (traced in /dl why).
        if not _unknownSetWarned[tostring(name)] then
            _unknownSetWarned[tostring(name)] = true;
            print(string.format('[dlac] trigger matched, but set "%s" does not exist in this profile -- create it in the Sets tab and Commit, then Reload LAC.', tostring(name)));
        end
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
function M.dispatch(event)
    if not inLac() then return; end
    pcall(function()
        event = EVENT_CANON[string.lower(tostring(event))] or event;
        local rules = ensureLoaded();
        local list = rules and rules[event] or nil;
        if list == nil or #list == 0 then return; end

        local ctx = buildCtx(event);
        local hits = {};
        for _, r in ipairs(list) do
            if matches(r, ctx) then hits[#hits + 1] = r; end
        end

        if #hits == 0 then
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
        sig = event .. ':' .. table.concat(sig, ',') .. '|' .. table.concat(lk, ',');
        local old = _trace[event];
        local retrace = (old == nil) or (old.sig ~= sig) or (event ~= 'Default');
        local lines = retrace and {} or old.lines;

        -- Apply in order, attributing each SLOT to its final writer -- with partial
        -- sets (weapon-only, DT-only, ...) this is what proves the overlay: every
        -- slot lists the rule that actually owns it this dispatch.
        local slotSrc = retrace and {} or nil;
        for _, r in ipairs(hits) do
            if r.set ~= nil then
                local found, note, tbl = equipSetByName(r.set, ctx);
                if retrace then
                    lines[#lines + 1] = string.format('%s  ->  set %s  (prio %d)%s%s',
                        r.label, r.set, r.prio, found and '' or '  [NOT FOUND in profile Sets]', note or '');
                    if type(tbl) == 'table' then
                        for slot in pairs(tbl) do
                            if string.sub(tostring(slot), 1, 2) ~= '__' then slotSrc[slot] = r.set; end
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
                    conds[#conds + 1] = (PRETTY_KEY[lk] or tostring(k)) .. ' = ' .. luaValue(v);
                end
                table.sort(conds);
                local action;
                if r.set ~= nil then
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
-- Handlers:   Default, Precast, Midcast, Ability, Item, Weaponskill, Preshot, Midshot
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
    local _tickAt, _tickJob = 0, nil;
    ashita.events.register('d3d_present', 'dlac-dispatch-tick', function()
        pcall(function()
            if os.clock() < _tickAt then return; end
            _tickAt = os.clock() + 0.4;
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
            st.HandleEquipEvent('HandleDefault', 'auto');
        end);
    end);

    ashita.events.register('command', 'dlac-dispatch', function(e)
        local start = argStart(string.lower(e.command));
        if start == nil then return; end
        local args = {};
        for a in string.gmatch(string.sub(e.command, start), '%S+') do args[#args + 1] = a; end
        local sub = args[1] and string.lower(args[1]) or nil;
        if sub ~= 'mode' and sub ~= 'why' and sub ~= 'triggers' and sub ~= 'env' and sub ~= 'lock' and sub ~= 'sets' then return; end
        e.blocked = true;

        if sub == 'sets' then
            if string.lower(tostring(args[2] or '')) ~= 'reload' then
                print('[dlac] usage: /dl sets reload   (hot-swap the committed sets, no LAC reload)');
                return;
            end
            -- Hot-swap the PLAN without a LAC reload. gProfile.Sets is just a live
            -- table in THIS Lua state -- "Reload LAC" was only ever about the FILE
            -- changing under it (field insight: ffxi-lac loops that mutated set
            -- objects took effect immediately). A set Commit rewrote <JOB>.lua;
            -- re-read it here and replace .Dynamic in place, then re-flatten.
            local prof = rawget(_G, 'gProfile');
            if type(prof) ~= 'table' or type(prof.Sets) ~= 'table' then
                print('[dlac] sets reload: no profile loaded.');
                return;
            end
            local fresh, ferr = readJobSets();
            if fresh == nil or type(fresh.Dynamic) ~= 'table' then
                print('[dlac] sets hot-swap failed (' .. tostring(ferr) .. ') -- click Reload LAC instead.');
                return;
            end
            -- flattened outputs of dynamic sets that no longer exist must die too
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
            print(string.format('[dlac] sets hot-swapped (%d dynamic set(s)) -- live now, no LAC reload needed.', n));
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
