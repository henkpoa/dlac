--[[
    dlac/debug.lua -- the /dl debug section (Henrik, 2026-07-23: "make a
    proper dl debug section"). One router, topic-per-feature state readouts,
    each in the two-halves pattern /dl check established: this ADDON-state
    module prints a feature's addon half, the engine's 'debug' branch
    (dispatch.lua) prints its half, and only KNOWN topics answer there --
    the usage/topic list has exactly one printer (here).

    Scope law (Henrik's 07-23 ruling, the /dl check session): these are
    "is it doing what it should?" state readouts -- liveness, resolved paths,
    the decision inputs a feature would act on. Packet captures, event spies
    and timing probes stay in dlacprobe. When a field case needs a readout,
    add a TOPIC here (+ its engine branch when the feature has engine state)
    instead of a bespoke per-feature command.

    THE FILE RULE (Henrik, same day): every debug/check run also lands as ONE
    transferable text file -- addons\dlac\debug\<base>-<Char>.txt, overwritten
    per run (support wants THE latest, not an archive) -- so a player can
    attach it instead of screenshotting chat. The two halves live in two Lua
    states with no shared memory, so the file is assembled by HANDOFF: the
    engine branch writes its lines (stamped with os.time()) to
    <char>\dlac\debug-<topic>-engine.txt in the same command frame; ~1.2s
    later this module's tick reads that handoff, judges freshness by the
    stamp, and writes the combined report. A MISSING or STALE engine half is
    written into the file in those words -- the file carries the absence-is-
    the-diagnosis property everywhere the chat lines do.

    Topics:
      ls (alias: lockstyle) -- lockstyle.M.debugLines() addon-side (boxes
          file/tier, marked box, unsaved-edits warning, v47 gate verdict,
          keep/town/guard state, the guard's observed 0x053 traffic);
          engine-side the apply pipeline as a DRY RUN plus the engine's own
          last-real-send record ('/dl debug ls <box>' picks a box exactly
          like apply).
    /dl check delivers through here too (feature/check.lua calls M.deliver).
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- alias -> canonical topic. Aliases are free; a canonical topic needs a
-- PRINTERS entry below (and an engine branch when the feature has one).
M.ALIAS = { ls = 'ls', lockstyle = 'ls' };

-- Pure (headless-tested, DBT*): first word after 'debug' -> canonical topic
-- or nil (unknown/absent -> the usage line).
function M._topic(word)
    return M.ALIAS[string.lower(tostring(word or ''))];
end

function M._usage()
    return 'debug topics: ls (alias: lockstyle) -- lockstyle state, addon + engine halves,'
        .. ' written to addons\\dlac\\debug\\ as a sendable .txt. Wiring health: /dl check.';
end

-- How old (seconds) an engine handoff stamp may be and still belong to THIS
-- run. Both states answer in the same command frame; 10s absorbs nothing but
-- a slow disk, while yesterday's handoff can never impersonate today's.
local FRESH_S = 10;

-- ---------------------------------------------------------------------------
-- pure seams (headless-tested, DBF*)
-- ---------------------------------------------------------------------------

-- Assemble the transfer file's text. engineRaw = the handoff file's bytes
-- (first line = os.time() stamp, rest = the engine's lines) or nil; a nil or
-- stale handoff writes the diagnosis INTO the file instead of an engine half.
function M._mergeSections(label, addonLines, engineRaw, nowEpoch, addonVer)
    local out = {
        string.format('dlac %s -- written %s -- addon %s', tostring(label),
            os.date('%Y-%m-%d %H:%M:%S', nowEpoch), tostring(addonVer or '?')),
        '',
        '== addon half ==',
    };
    for _, l in ipairs(addonLines or {}) do out[#out + 1] = l; end
    out[#out + 1] = '';
    out[#out + 1] = '== engine half ==';
    local stamp, rest = nil, nil;
    if type(engineRaw) == 'string' then
        stamp = tonumber(engineRaw:match('^(%d+)'));
        rest = engineRaw:match('^%d+[^\n]*\n(.*)$');
    end
    if stamp == nil then
        out[#out + 1] = 'ENGINE HALF MISSING -- the engine never wrote its handoff: LuaAshitacast is not'
            .. ' running the dlac engine (run Setup, then Reload LAC). That IS the diagnosis.';
    elseif math.abs(nowEpoch - stamp) > FRESH_S then
        out[#out + 1] = string.format('ENGINE HALF STALE (written %ds ago, not this run) -- the engine did not'
            .. ' answer THIS command: LuaAshitacast is not running a current dlac engine'
            .. ' (run Setup, then Reload LAC).', nowEpoch - stamp);
    else
        for l in tostring(rest or ''):gmatch('[^\n]+') do out[#out + 1] = l; end
    end
    out[#out + 1] = '';
    return table.concat(out, '\n');
end

-- Filenames carry the character (support juggles several players' files):
-- letters/digits only, 'unknown' pre-login.
function M._safeName(n)
    n = tostring(n or ''):gsub('%W', '');
    return (n ~= '') and n or 'unknown';
end

-- ---------------------------------------------------------------------------
-- live glue (Ashita only)
-- ---------------------------------------------------------------------------

local function charBase()
    local base = nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name  = party:GetMemberName(0);
        local id    = party:GetMemberServerId(0);
        if name == nil or name == '' or id == nil or id == 0 then return; end
        base = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\', AshitaCore:GetInstallPath(), name, id);
    end);
    return base;
end

local function charName()
    local n = nil;
    pcall(function() n = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0); end);
    return M._safeName(n);
end

local function readAll(p)
    if p == nil then return nil; end
    local f = io.open(p, 'rb'); if f == nil then return nil; end
    local d = f:read('*a'); f:close(); return d;
end

-- The report drop, created at LOAD: the folder's very existence proves the
-- NEW addon state is live. Field case 2026-07-23 (Henrik): "it is not
-- creating the debug folder" -- the addon half does not hot-swap (only the
-- engine self-swaps), so an addon state loaded before this module existed
-- can never write it; after /addon reload dlac the folder appears at load,
-- before any command runs.
local function debugDir()
    local d = nil;
    pcall(function() d = AshitaCore:GetInstallPath() .. 'addons\\dlac\\debug\\'; end);
    return d;
end
pcall(function()
    local d = debugDir();
    if d ~= nil and ashita and ashita.fs and ashita.fs.create_directory then
        ashita.fs.create_directory(d);
    end
end);

-- One pending delivery at a time (a re-run before the tick fires just
-- replaces it -- latest wins).
local _pend = nil;

-- Book the transfer-file write: label for the header/chat, fileBase for the
-- filename, the addon half's lines, and the engine handoff filename to merge
-- (nil = no engine half expected). The ~1.2s delay lets the engine's same-
-- frame handoff write land first; see the header note.
function M.deliver(label, fileBase, addonLines, handoffName)
    local ver = nil;
    pcall(function() ver = addon ~= nil and addon.version or nil; end);
    _pend = { label = label, base = fileBase, lines = addonLines, handoff = handoffName,
              ver = ver, dueAt = os.clock() + 1.2 };
end

-- The write is pcall-wrapped but NEVER silently: a failure prints itself
-- (silence has no author -- the very lesson this section exists to teach).
ashita.events.register('d3d_present', 'dlac-debug-deliver', function()
    if _pend == nil or os.clock() < _pend.dueAt then return; end
    local p = _pend; _pend = nil;
    local ok, err = pcall(function()
        local engineRaw = nil;
        if p.handoff ~= nil then
            local base = charBase();
            if base ~= nil then engineRaw = readAll(base .. 'dlac\\' .. p.handoff); end
        end
        local text = M._mergeSections(p.label, p.lines, engineRaw, os.time(), p.ver);
        local dir = debugDir();
        if dir == nil then error('install path unavailable', 0); end
        if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(dir); end
        local path = dir .. p.base .. '-' .. charName() .. '.txt';
        local f = io.open(path, 'wb');
        if f == nil then error('cannot open for write: ' .. path, 0); end
        f:write(text); f:close();
        print('[dlac] ' .. tostring(p.label) .. ': report written -> ' .. path .. ' -- send this file.');
    end);
    if not ok then
        pcall(function()
            print('[dlac] ' .. tostring(p.label) .. ': report write FAILED -- ' .. tostring(err));
        end);
    end
end);

local PRINTERS = {
    ls = function()
        local m = try('dlac\\feature\\lockstyle');
        if m == nil or type(m.debugLines) ~= 'function' then
            print('[dlac] debug ls (addon): lockstyle module not loaded.');
            return;
        end
        local ok, lines = pcall(m.debugLines);
        if not ok or type(lines) ~= 'table' then
            print('[dlac] debug ls (addon): readout failed (' .. tostring(lines) .. ').');
            return;
        end
        for _, l in ipairs(lines) do print('[dlac] debug ls (addon): ' .. l); end
        M.deliver('debug ls', 'dlac-debug-ls', lines, 'debug-ls-engine.txt');
    end,
};

-- '/dl debug [topic]' in the ADDON state. e.blocked only quiets the game
-- parser -- the LAC state's dispatch handler still sees the command (the
-- /dl ls apply precedent) and adds its engine half for known topics.
ashita.events.register('command', 'dlac-debug', function(e)
    local raw = string.lower(e.command);
    local rest = nil;
    if raw:match('^/dlac?%s+debug%s*$') ~= nil then rest = '';
    else rest = raw:match('^/dlac?%s+debug%s+(.*)$'); end
    if rest == nil then return; end
    e.blocked = true;
    local topic = M._topic(rest:match('^(%S+)'));
    if topic == nil then print('[dlac] ' .. M._usage()); return; end
    PRINTERS[topic]();
end);

return M;
