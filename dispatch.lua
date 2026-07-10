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

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
M.modes = {};   -- session-only mode state: lower(name) -> true (toggle) or 'Value' (cycle).
                -- Reset on load by design (cycle modes re-default to their first value).
local saveModeState;   -- defined in the mode section below; used by the trigger loader

local EVENTS = { 'Default', 'Precast', 'Midcast', 'Ability', 'Item', 'Weaponskill', 'Preshot', 'Midshot' };
local EVENT_CANON = {};
for _, e in ipairs(EVENTS) do EVENT_CANON[string.lower(e)] = e; end
M.EVENTS = EVENTS;
function M.canonEvent(e) return EVENT_CANON[string.lower(tostring(e))]; end

local _trig  = { path = nil, raw = nil, rules = nil, lastCheck = -1, err = nil };
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

local MATCHERS = {
    any             = function() return true; end,
    status          = function(v, ctx) return ctx.player ~= nil and ci(ctx.player.Status, v); end,
    moving          = function(v, ctx) return ctx.player ~= nil and ((ctx.player.IsMoving == true) == (v == true)); end,
    mode            = function(v, ctx)
        local s = tostring(v);
        local p = string.find(s, ':', 1, true);
        if p ~= nil then                               -- 'Weapon:Melee' -> cycle mode holds that value
            local cur = M.modes[string.lower(string.sub(s, 1, p - 1))];
            return type(cur) == 'string' and ci(cur, string.sub(s, p + 1));
        end
        return M.modes[string.lower(s)] ~= nil;        -- toggle ON (or any cycle value)
    end,
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
        print('[dlac] ' .. _trig.err .. '  (keeping the previous rules)');
        return _trig.rules;
    end
    local ok, t = pcall(chunk);
    if not ok or type(t) ~= 'table' then
        _trig.err = 'trigger file did not return a table' .. (ok and '' or (': ' .. tostring(t)));
        print('[dlac] ' .. _trig.err .. '  (keeping the previous rules)');
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
        if def.bind ~= nil then
            pcall(function()
                AshitaCore:GetChatManager():QueueCommand(-1,
                    string.format('/bind %s /dl mode %s', def.bind, def.name));
            end);
        end
    end
    pcall(saveModeState);
    for _, w in ipairs(warns) do print('[dlac] triggers: ' .. w); end
    local n = 0;
    for _, list in pairs(rules) do n = n + #list; end
    print(string.format('[dlac] triggers loaded: %d rule(s) from %s', n, path));
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
                print('[dlac] autogear.lua is an old format (staff swapping is OFF) -- open the GUI: Triggers tab > Automations > "Rescan owned gear".');
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

-- Equip a set table, resolving virtual entries. Sets without markers pass through
-- untouched (zero copies); with markers, a shallow copy carries the resolutions.
-- BuildDynamicSets encodes the slot's regular best-by-level pick as a fallback
-- ('dlac:AutoStaff|Maple Wand'): an unresolvable virtual equips the fallback -- so
-- being under-leveled for every iridescence weapon / obi never blocks the slot --
-- and only with no fallback at all is the slot dropped (LAC leaves what's worn).
-- Returns a trace note ('' when nothing was virtual).
local function equipResolved(s, ctx)
    local out, notes = nil, nil;
    for slot, v in pairs(s) do
        if type(v) == 'string' and string.lower(string.sub(v, 1, 5)) == 'dlac:' then
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

local function equipSetByName(name, ctx)
    local s;
    pcall(function()
        local prof = rawget(_G, 'gProfile');
        if type(prof) == 'table' and type(prof.Sets) == 'table' then s = prof.Sets[name]; end
    end);
    if type(s) ~= 'table' then return false, '', nil; end   -- unknown set: skip quietly (traced), no per-frame LAC error spam
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
        sig = event .. ':' .. table.concat(sig, ',');
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
-- Mode state (session-only, by design -- no persistence). The LAC state OWNS the
-- flags; a small modestate.lua mirror is written on every change so the GUI (a
-- different Lua state) can DISPLAY them. It is never read back on load -- modes
-- always start a session off.
-- ---------------------------------------------------------------------------
saveModeState = function()
    pcall(function()
        local dir = charDir();
        if dir == nil then return; end
        local parts = {};
        for m, v in pairs(M.modes) do
            if v == true then parts[#parts + 1] = string.format('[%q] = true,', m);
            elseif type(v) == 'string' then parts[#parts + 1] = string.format('[%q] = %q,', m, v); end
        end
        table.sort(parts);
        writeFile(dir .. 'modestate.lua',
            '-- dlac mode mirror (display only; the LAC state owns the flags)\nreturn { '
            .. table.concat(parts, ' ') .. ' }\n');
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

-- ---------------------------------------------------------------------------
-- Commands: /dl mode | why | triggers   (registered in the LAC state only, where
-- the mode flags and traces live; the addon state's copy stays silent).
-- ---------------------------------------------------------------------------
local function argStart(raw)
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then return 7; end
    if raw == '/dl'   or string.sub(raw, 1, 4) == '/dl '   then return 5; end
    return nil;
end

if inLac() then
    pcall(saveModeState);   -- fresh session: mirror the (empty) mode state for the GUI

    ashita.events.register('command', 'dlac-dispatch', function(e)
        local start = argStart(string.lower(e.command));
        if start == nil then return; end
        local args = {};
        for a in string.gmatch(string.sub(e.command, start), '%S+') do args[#args + 1] = a; end
        local sub = args[1] and string.lower(args[1]) or nil;
        if sub ~= 'mode' and sub ~= 'why' and sub ~= 'triggers' and sub ~= 'env' then return; end
        e.blocked = true;

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
            return;
        end

        if sub == 'mode' then
            local name = args[2];
            if name == nil then
                local act = M.activeModes();
                print('[dlac] active modes: ' .. ((#act > 0) and table.concat(act, ', ') or '(none)')
                    .. '   (/dl mode <name> [on|off|toggle])');
                return;
            end
            local a3 = args[3];
            local state = nil;                       -- default: toggle / cycle to next
            if a3 ~= nil then
                local l3 = string.lower(a3);
                if l3 == 'on' then state = true;
                elseif l3 == 'off' then state = false;
                else state = a3; end                 -- cycle mode: jump straight to this value
            end
            ensureLoaded();                          -- cycle definitions live in the trigger file
            local ln = string.lower(name);
            local before = M.modes[ln];
            local res = M.setMode(name, state);
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
            print('[dlac] triggers: will re-read on the next action.');
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
