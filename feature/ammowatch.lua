--[[
    dlac/feature/ammowatch.lua -- AutoAmmo config state (docs/design/auto-ammo.md).

    The GUI's half of the Ammo-slot automation: this module OWNS
    <char>\dlac\ammostate.lua and every mutation of it; the dispatch ENGINE
    (v73+) reads that file and decides the slot per event -- count-verified
    picks, the special-bullet protection sweep, the 'remove' ladder end. No
    packets, no heartbeat, no equipping from here: the engine re-reads counts
    live at decision time, so the config only changes when the player edits it.

    PER JOB since fmt 2 (field round 2, Henrik: "all jobs can't use all ammos,
    I want this list to be seperate for all jobs seperately, where it remembers
    if you have activated it or not") -- every job keeps its OWN priority list
    AND its own persisted on/off. The old fmt-1 single list + jobs-map is
    migrated on first load: each ticked job gets its own copy of the list.

    File shape (fmt 2):
      return { fmt = 2, jobs = {
          ["RNG"] = { enabled = true, at = <stamp>, ammo = { <entries> } },
      } }
    Entry shape (array order = the engine's fallback priority):
      { name = <client item name>, id = <item id>, type = <catalog AmmoType>,
        level = <item level, 0 = unknown>, ranged = bool, ws = bool,
        special = false | { unlimited = bool, quickdraw = bool, freews = bool } }
    `level` exists for the GUI's Sort-by-level button (the engine ignores it).

    `enabled` (per job) PERSISTS across sessions -- deliberate deviation from
    the craftstate session-only rule: this is a protection system, and a
    protection that silently disarms at login is how the Rare/Ex bullet dies.
    The per-job split IS the blast-radius limiter now (it replaced the map).

    The UI drives everything through selectJob(<current main job>) each
    render; M.enabled / M.list are live proxies of the selected section.
    Pure helpers are headless-testable; the only Ashita touch is charDir.
]]--

local M = {};

-- <char>\dlac\ dir: the one addon-side copy (lib\statefile). nil pre-login.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir
    or function() return nil; end;
M._charDir = charDir;   -- test seam

M.jobsData = {};    -- [JOB] = { enabled, at, ammo = {...} }
M.job = nil;        -- the selected job (the UI's current main job)
M.enabled = false;  -- proxy of the selected section (read-only for callers)
M.list = {};        -- proxy: the selected section's ammo table itself
local _orphan = nil;      -- fmt-1 list migrated with NO job ticked: adopted by
                          -- the first job that selects in (nothing gets lost)
local _stateLoaded = false;

local function statePath()
    local dir = charDir();
    return dir and (dir .. 'ammostate.lua') or nil;
end

local function copyEntry(e)
    return {
        name = e.name, id = tonumber(e.id) or 0,
        type = tostring(e.type or ''), level = tonumber(e.level) or 0,
        ranged = (e.ranged == true), ws = (e.ws == true),
        special = (type(e.special) == 'table') and {
            unlimited = (e.special.unlimited == true),
            quickdraw = (e.special.quickdraw == true),
            freews    = (e.special.freews == true),
        } or false,
    };
end

-- Serializer, pure (tests AW*): stable multi-line output, %q for names.
function M._serialize(jobsData)
    local L = {
        '-- dlac AutoAmmo state -- written by the GUI (Automations > AutoAmmo).',
        '-- The dispatch engine (v74+) reads this per second; edit via the GUI.',
        '-- fmt 2: one section per job (each keeps its own list and on/off).',
        'return {',
        '    fmt = 2,',
        '    jobs = {',
    };
    local jk = {};
    for j in pairs(jobsData or {}) do
        if type(j) == 'string' then jk[#jk + 1] = j; end
    end
    table.sort(jk);
    for _, j in ipairs(jk) do
        local s = jobsData[j];
        L[#L + 1] = string.format('        [%q] = {', j);
        L[#L + 1] = string.format('            enabled = %s,', tostring(s.enabled == true));
        L[#L + 1] = string.format('            at = %d,', tonumber(s.at) or 0);
        L[#L + 1] = '            ammo = {';
        for _, e in ipairs(s.ammo or {}) do
            if type(e) == 'table' and type(e.name) == 'string' then
                local sp = 'false';
                if type(e.special) == 'table' then
                    local bits = {};
                    for _, b in ipairs({ 'unlimited', 'quickdraw', 'freews' }) do
                        if e.special[b] == true then bits[#bits + 1] = b .. ' = true'; end
                    end
                    sp = '{ ' .. table.concat(bits, ', ') .. ' }';
                end
                L[#L + 1] = string.format(
                    '                { name = %q, id = %d, type = %q, level = %d, ranged = %s, ws = %s, special = %s },',
                    e.name, tonumber(e.id) or 0, tostring(e.type or ''), tonumber(e.level) or 0,
                    tostring(e.ranged == true), tostring(e.ws == true), sp);
            end
        end
        L[#L + 1] = '            },';
        L[#L + 1] = '        },';
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '}';
    return table.concat(L, '\n') .. '\n';
end

local function saveState()
    pcall(function()
        local p = statePath();
        if p == nil then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(M._serialize(M.jobsData));
        f:close();
    end);
end
M._saveState = saveState;   -- test seam

local function readSection(s)
    local out = { enabled = (type(s) == 'table' and s.enabled == true),
                  at = (type(s) == 'table') and (tonumber(s.at) or 0) or 0,
                  ammo = {} };
    if type(s) == 'table' and type(s.ammo) == 'table' then
        for _, e in ipairs(s.ammo) do
            if type(e) == 'table' and type(e.name) == 'string' then
                out.ammo[#out.ammo + 1] = copyEntry(e);
            end
        end
    end
    return out;
end

-- Migration, pure (tests AW*): a loaded state table in EITHER format ->
-- jobsData, orphan. fmt-1 (single list + jobs map): every ticked job gets its
-- OWN COPY of the list (they diverge from here on -- the point of fmt 2);
-- a fmt-1 list with NO job ticked comes back as the orphan, so the first job
-- that selects in adopts it rather than losing the config.
function M._migrate(t)
    local jobsData, orphan = {}, nil;
    if type(t) ~= 'table' then return jobsData, orphan; end
    if type(t.ammo) == 'table' then   -- fmt 1
        local any = false;
        if type(t.jobs) == 'table' then
            for j, on in pairs(t.jobs) do
                if on == true and type(j) == 'string' then
                    any = true;
                    jobsData[j] = readSection({ enabled = t.enabled, at = t.at, ammo = t.ammo });
                end
            end
        end
        if not any then
            orphan = readSection({ enabled = false, at = 0, ammo = t.ammo });
        end
        return jobsData, orphan;
    end
    if type(t.jobs) == 'table' then   -- fmt 2
        for j, s in pairs(t.jobs) do
            if type(j) == 'string' and type(s) == 'table' then
                jobsData[j] = readSection(s);
            end
        end
    end
    return jobsData, orphan;
end

function M._setOrphan(o) _orphan = o; end   -- headless seam (the adoption path)

function M.loadState()
    if _stateLoaded then return; end
    local dir = charDir();
    if dir == nil then return; end        -- pre-login: retry next call
    _stateLoaded = true;
    local migrated = false;
    pcall(function()
        local chunk = loadfile(dir .. 'ammostate.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if not ok or type(t) ~= 'table' then return; end
        M.jobsData, _orphan = M._migrate(t);
        migrated = (type(t.ammo) == 'table');   -- fmt 1 on disk: rewrite as fmt 2
    end);
    if migrated then saveState(); end
end

-- ---------------------------------------------------------------------------
-- Selection + proxies. The UI calls selectJob(<current main job>) every
-- render; a job with no section reads as OFF + empty (the section is only
-- created when a mutation actually happens -- no file noise from glancing).
-- ---------------------------------------------------------------------------
local function syncProxies()
    local s = (M.job ~= nil) and M.jobsData[M.job] or nil;
    M.enabled = (s ~= nil and s.enabled == true);
    M.list = (s ~= nil) and s.ammo or {};
end

function M.selectJob(job)
    M.loadState();
    if type(job) ~= 'string' or job == '' then syncProxies(); return; end
    M.job = job;
    -- A migrated fmt-1 list that no job owned lands on the first job seen.
    if _orphan ~= nil and M.jobsData[job] == nil then
        M.jobsData[job] = _orphan;
        _orphan = nil;
        saveState();
    end
    syncProxies();
end

local function ensureSection()
    if M.job == nil then return nil; end
    local s = M.jobsData[M.job];
    if s == nil then
        s = { enabled = false, at = 0, ammo = {} };
        M.jobsData[M.job] = s;
    end
    return s;
end

-- For the panel's "other jobs" summary line: sorted { job, enabled, n }.
function M.jobSummary()
    local out = {};
    for j, s in pairs(M.jobsData) do
        out[#out + 1] = { job = j, enabled = (s.enabled == true), n = #(s.ammo or {}) };
    end
    table.sort(out, function(a, b) return a.job < b.job; end);
    return out;
end

-- ---------------------------------------------------------------------------
-- Mutators (each writes through; the engine sees the file within a second).
-- All operate on the SELECTED job's section.
-- ---------------------------------------------------------------------------
function M.setEnabled(on, job)
    if type(job) == 'string' and job ~= '' then M.selectJob(job); end
    local s = ensureSection();
    if s == nil then return; end
    s.enabled = (on == true);
    if s.enabled then s.at = os.time(); end
    syncProxies();
    saveState();
end

local function validIdx(i) return type(i) == 'number' and i >= 1 and i <= #M.list; end

-- rec: { Name, Id, AmmoType, Level } (a catalogindex flat record).
function M.addAmmo(rec)
    if type(rec) ~= 'table' or type(rec.Name) ~= 'string' then return false; end
    local s = ensureSection();
    if s == nil then return false; end
    syncProxies();
    for _, e in ipairs(s.ammo) do
        if string.lower(e.name) == string.lower(rec.Name) then return false; end
    end
    s.ammo[#s.ammo + 1] = { name = rec.Name, id = tonumber(rec.Id) or 0,
                            type = tostring(rec.AmmoType or ''),
                            level = tonumber(rec.Level) or 0,
                            ranged = false, ws = false, special = false };
    saveState();
    return true;
end

function M.removeAmmo(i)
    if not validIdx(i) then return; end
    table.remove(M.list, i);
    saveState();
end

function M.moveAmmo(i, delta)
    if not validIdx(i) then return; end
    local j = i + (tonumber(delta) or 0);
    if not validIdx(j) or i == j then return; end
    M.list[i], M.list[j] = M.list[j], M.list[i];
    saveState();
end

-- flag: 'ranged' | 'ws'. Refused on a special entry (exclusivity).
function M.setFlag(i, flag, on)
    if not validIdx(i) then return; end
    local e = M.list[i];
    if type(e.special) == 'table' then return; end
    if flag == 'ranged' then e.ranged = (on == true);
    elseif flag == 'ws' then e.ws = (on == true);
    else return; end
    saveState();
end

function M.setSpecial(i, on)
    if not validIdx(i) then return; end
    local e = M.list[i];
    if on == true then
        e.ranged, e.ws = false, false;
        if type(e.special) ~= 'table' then
            e.special = { unlimited = false, quickdraw = false, freews = false };
        end
    else
        e.special = false;
    end
    saveState();
end

-- beh: 'unlimited' | 'quickdraw' | 'freews'.
function M.setBehaviour(i, beh, on)
    if not validIdx(i) then return; end
    local e = M.list[i];
    if type(e.special) ~= 'table' then return; end
    if beh ~= 'unlimited' and beh ~= 'quickdraw' and beh ~= 'freews' then return; end
    e.special[beh] = (on == true);
    saveState();
end

-- One-shot best-first reorder: item level DESC, original order on ties
-- (table.sort alone is not stable -- the index rides along as tiebreak).
-- lvlOf(entry) -> level fills the gap for entries saved before `level`
-- existed; a learned level is backfilled onto the entry so the next sort
-- (and the file) know it.
function M.sortByLevel(lvlOf)
    local dec = {};
    for i, e in ipairs(M.list) do
        local lv = tonumber(e.level) or 0;
        if lv <= 0 and type(lvlOf) == 'function' then
            local ok, n = pcall(lvlOf, e);
            if ok then lv = tonumber(n) or 0; end
            if lv > 0 then e.level = lv; end
        end
        dec[#dec + 1] = { e = e, lv = lv, i = i };
    end
    table.sort(dec, function(a, b)
        if a.lv ~= b.lv then return a.lv > b.lv; end
        return a.i < b.i;
    end);
    local changed = false;
    for i, d in ipairs(dec) do
        if M.list[i] ~= d.e then changed = true; end
        M.list[i] = d.e;
    end
    if changed then saveState(); end
    return changed;
end

return M;
