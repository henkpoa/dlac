--[[
    dlac/chocowatch.lua -- Chocobo riding-gear state
    (docs/design/chocobo-gear.md; the craft/HELM/fishing fourth sibling).

    Same philosophy: don't fight the engine, BE the engine. This module WRITES
    <char>\dlac\chocostate.lua { enabled, at }; the dispatch ENGINE overlays the
    resolved riding-time gear on Default ONLY (idle-only is the requirement, not
    an accident -- riding gear must never ride into an action event) and wears
    the best owned piece per slot for Main/Neck/Body/Hands/Legs/Feet. Flip the
    switch off -> no overlay -> normal idle gear returns.

    Unlike the other three siblings this one is TINY: no target, no category, no
    packet protocol, no bar. It equips the one fixed "best riding-time set" and
    the panel reports the total riding time. `enabled` is session-only, NEVER
    restored at login (the craftstate rule -- no gear glued on at login); `at`
    is the enable stamp the Arbiter reads.

    Pure helpers are headless-testable; Ashita glue guarded at the bottom.
]]--

local M = {};

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function say(s) if _cfok and _cfmt.msg then _cfmt.msg(s); else print('[dlac] ' .. s); end end

-- <char>\dlac\ dir: the one addon-side copy (lib\statefile). nil pre-login.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir
    or function() return nil; end;
M._charDir = charDir;   -- test seam

-- ---------------------------------------------------------------------------
-- MANUAL Chocobo control (the craftwatch/helmwatch model). You flip the switch
-- from the Automations panel; this just writes chocostate.lua and the engine
-- wears the result. `enabled` is session-only ON PURPOSE (same as craft/helm/
-- fishing): no riding gear glued on at login. `at` is the enable timestamp,
-- the Arbiter's rank tiebreak key (unused today -- rank settles overlaps).
-- ---------------------------------------------------------------------------
M.enabled = false;         -- "Set Chocobo Idle": session-only; starts OFF
M._enabledAt = 0;          -- os.time() of the last enable (state-file `at`)
M._rescanned = false;      -- manifest freshness ensured once this session?
local _stateLoaded = false;

local function statePath()
    local dir = charDir();
    return dir and (dir .. 'chocostate.lua') or nil;
end
local function saveState()
    pcall(function()
        local p = statePath();
        if p == nil then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(string.format('return { enabled = %s, at = %d }\n',
            tostring(M.enabled == true), M._enabledAt or 0));
        f:close();
    end);
end
M._saveState = saveState;   -- test seam

function M.loadState()
    if _stateLoaded then return; end
    local dir = charDir();
    if dir == nil then return; end        -- pre-login: retry next call
    _stateLoaded = true;
    -- The switch is NOT restored (craftstate rule): it starts OFF each session.
    -- Nothing else lives in this file, so there is nothing to read back -- the
    -- load only exists to sync a clean OFF file for the engine at login.
    M.enabled = false;
    M._enabledAt = 0;
    saveState();
end

-- Manifest freshness (fishwatch clone): the choco ladders must exist before the
-- engine reads them.
local function ensureManifestFresh()
    local first = not M._rescanned;
    M._rescanned = true;
    pcall(function()
        local au = require('dlac\\ui\\automationsui');
        if type(au.rescanAutogear) ~= 'function' then return; end
        local stale = first;
        if not first then
            pcall(function()
                if type(au.manifestStale) == 'function' then stale = au.manifestStale(); end
            end);
        end
        if stale then au.rescanAutogear(); end
    end);
end

function M.isEnabled() M.loadState(); return M.enabled == true; end

-- The on/off switch (panel). Craft/HELM/Fishing/Chocobo CO-CLAIM (ADR 0012
-- amendment): arming Chocobo stands nothing else down -- all armed activities
-- claim and the Arbiter's rank settles every overlapping slot per slot.
function M.setEnabled(on)
    M.loadState();
    M.enabled = (on == true);
    if M.enabled then
        M._enabledAt = os.time();
        ensureManifestFresh();
    end
    saveState();
end

-- ---------------------------------------------------------------------------
-- Ashita glue
-- ---------------------------------------------------------------------------
if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    -- /dl choco [on | off | status]. The subject (an on/off riding-gear switch)
    -- lives in the addon state, so the command does too (the helm/fish
    -- precedent) -- its own blocked registration, never the dispatch whitelist.
    ashita.events.register('command', 'dlac-chocowatch-cmd', function(e)
        pcall(function()
            local raw = string.lower(e.command or '');
            local a, b = raw:match('^/dl%s+(%S+)%s*(%S*)');
            if a == nil then a, b = raw:match('^/dlac%s+(%S+)%s*(%S*)'); end
            if a ~= 'choco' and a ~= 'chocobo' then return; end
            e.blocked = true;
            if b == 'on' or b == 'off' then
                M.setEnabled(b == 'on');
                say('Chocobo idle set ' .. (M.enabled and 'ON' or 'OFF') .. '.');
                return;
            end
            -- bare /dl choco: status.
            say('chocobo: idle set = ' .. (M.isEnabled() and 'ON' or 'off')
                .. ' (session-only -- off after relog). Equips your best riding-time gear while idle.');
        end);
    end);
end

return M;
