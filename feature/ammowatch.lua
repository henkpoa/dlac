--[[
    dlac/feature/ammowatch.lua -- AutoAmmo config state (docs/design/auto-ammo.md).

    The GUI's half of the Ammo-slot automation: this module OWNS
    <char>\dlac\ammostate.lua and every mutation of it; the dispatch ENGINE
    (v73) reads that file and decides the slot per event -- count-verified
    picks, the special-bullet protection sweep, the 'remove' ladder end. No
    packets, no heartbeat, no equipping from here: the engine re-reads counts
    live at decision time, so the config only changes when the player edits it.

    UNLIKE craft/helm/fish, `enabled` PERSISTS across sessions -- those are
    activity pills (an overlay must not glue itself on at login); this is a
    protection system, and a protection that silently disarms at login is how
    the Rare/Ex bullet dies. The `jobs` map is the blast radius limiter: the
    engine ignores every event when the current main job isn't ticked.

    Entry shape (array order = the engine's fallback priority):
      { name = <client item name>, id = <item id>, type = <catalog AmmoType>,
        ranged = bool, ws = bool,
        special = false | { unlimited = bool, quickdraw = bool, freews = bool } }
    Special is exclusive: ticking it clears ranged/ws (the engine also never
    treats a special entry as a normal pick -- belt and braces).

    Pure helpers are headless-testable; the only Ashita touch is charDir.
]]--

local M = {};

-- <char>\dlac\ dir: the one addon-side copy (lib\statefile). nil pre-login.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir
    or function() return nil; end;
M._charDir = charDir;   -- test seam

M.enabled = false;
M.jobs = {};        -- { COR = true, ... } main-job abbreviations
M.list = {};        -- the ammo entry array, priority order
M._at = 0;          -- enable stamp (the engine-side arbitration convention)
local _stateLoaded = false;

local function statePath()
    local dir = charDir();
    return dir and (dir .. 'ammostate.lua') or nil;
end

-- Serializer, pure (tests AW*): stable multi-line output, %q for names.
function M._serialize(enabled, at, jobs, list)
    local L = {
        '-- dlac AutoAmmo state -- written by the GUI (Automations > AutoAmmo).',
        '-- The dispatch engine (v73+) reads this per second; edit via the GUI.',
        'return {',
        string.format('    enabled = %s,', tostring(enabled == true)),
        string.format('    at = %d,', tonumber(at) or 0),
    };
    local jk = {};
    for j, on in pairs(jobs or {}) do
        if on == true and type(j) == 'string' then jk[#jk + 1] = j; end
    end
    table.sort(jk);
    local jp = {};
    for _, j in ipairs(jk) do jp[#jp + 1] = string.format('[%q] = true', j); end
    L[#L + 1] = '    jobs = { ' .. table.concat(jp, ', ') .. ' },';
    L[#L + 1] = '    ammo = {';
    for _, e in ipairs(list or {}) do
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
                '        { name = %q, id = %d, type = %q, ranged = %s, ws = %s, special = %s },',
                e.name, tonumber(e.id) or 0, tostring(e.type or ''),
                tostring(e.ranged == true), tostring(e.ws == true), sp);
        end
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
        f:write(M._serialize(M.enabled, M._at, M.jobs, M.list));
        f:close();
    end);
end
M._saveState = saveState;   -- test seam

function M.loadState()
    if _stateLoaded then return; end
    local dir = charDir();
    if dir == nil then return; end        -- pre-login: retry next call
    _stateLoaded = true;
    pcall(function()
        local chunk = loadfile(dir .. 'ammostate.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if not ok or type(t) ~= 'table' then return; end
        -- EVERYTHING restores, enabled included (the header's why).
        M.enabled = (t.enabled == true);
        M._at = tonumber(t.at) or 0;
        M.jobs = {};
        if type(t.jobs) == 'table' then
            for j, on in pairs(t.jobs) do
                if on == true and type(j) == 'string' then M.jobs[j] = true; end
            end
        end
        M.list = {};
        if type(t.ammo) == 'table' then
            for _, e in ipairs(t.ammo) do
                if type(e) == 'table' and type(e.name) == 'string' then
                    M.list[#M.list + 1] = {
                        name = e.name, id = tonumber(e.id) or 0,
                        type = tostring(e.type or ''),
                        ranged = (e.ranged == true), ws = (e.ws == true),
                        special = (type(e.special) == 'table') and {
                            unlimited = (e.special.unlimited == true),
                            quickdraw = (e.special.quickdraw == true),
                            freews    = (e.special.freews == true),
                        } or false,
                    };
                end
            end
        end
    end);
end

-- ---------------------------------------------------------------------------
-- Mutators (each writes through; the engine sees the file within a second).
-- ---------------------------------------------------------------------------

-- job: current main-job abbrev; ticked on first enable so a fresh config
-- guards the job it was set up on without a second step.
function M.setEnabled(on, job)
    M.enabled = (on == true);
    if M.enabled then
        M._at = os.time();
        if type(job) == 'string' and job ~= '' and next(M.jobs) == nil then
            M.jobs[job] = true;
        end
    end
    saveState();
end

function M.setJob(job, on)
    if type(job) ~= 'string' or job == '' then return; end
    M.jobs[job] = (on == true) or nil;
    saveState();
end

local function validIdx(i) return type(i) == 'number' and i >= 1 and i <= #M.list; end

-- rec: { Name, Id, AmmoType } (a catalogindex flat record).
function M.addAmmo(rec)
    if type(rec) ~= 'table' or type(rec.Name) ~= 'string' then return false; end
    for _, e in ipairs(M.list) do
        if string.lower(e.name) == string.lower(rec.Name) then return false; end
    end
    M.list[#M.list + 1] = { name = rec.Name, id = tonumber(rec.Id) or 0,
                            type = tostring(rec.AmmoType or ''),
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

return M;
