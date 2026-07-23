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
    return 'debug topics: ls [seconds] (alias: lockstyle) -- snapshot, then a 30-120s capture window'
        .. ' (default 45): do the failing thing DURING it; the report lands in addons\\dlac\\debug\\'
        .. ' as a sendable .txt when it closes. Wiring health: /dl check.';
end

-- The capture-window length (pure, tests DBT*): seconds arg clamped 30-120,
-- default 45. TWIN of the engine's clamp in dispatch's debug branch -- the
-- same command opens both windows, so the two must always agree.
function M._dur(word)
    local n = tonumber(word);
    if n == nil then return 45; end
    return math.max(30, math.min(120, n));
end

-- How old (seconds) an engine handoff stamp may be and still belong to THIS
-- run. Both states answer in the same command frame; 10s absorbs nothing but
-- a slow disk, while yesterday's handoff can never impersonate today's.
local FRESH_S = 10;

-- ---------------------------------------------------------------------------
-- pure seams (headless-tested, DBF*)
-- ---------------------------------------------------------------------------

-- Assemble the transfer file's text. engineRaw = the handoff file's bytes
-- (first line = os.time() stamp, rest = the engine's lines); nil or a stale
-- stamp writes the diagnosis INTO the file instead of an engine half; the
-- literal `false` marks the PROVISIONAL write (the file lands the moment the
-- command runs -- field 2026-07-23, "no txt file": the final write waits out
-- the capture window, so an early look found nothing) and its pending note
-- doubles as the tick's own tripwire.
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
    if engineRaw == false then
        out[#out + 1] = 'PENDING -- this is the provisional report, written the moment the command ran;'
            .. ' the finished one (engine half + captured events) OVERWRITES this file when the'
            .. ' window closes. If this line is still here well after, the deliver tick never'
            .. ' fired -- send the file anyway, that fact is the finding.';
    elseif stamp == nil then
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

-- Write one report file; returns the path (or nil + a printed failure).
local function writeOut(base, text, label, word)
    local path = nil;
    local ok, err = pcall(function()
        local dir = debugDir();
        if dir == nil then error('install path unavailable', 0); end
        if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(dir); end
        local p = dir .. base .. '-' .. charName() .. '.txt';
        local f = io.open(p, 'wb');
        if f == nil then error('cannot open for write: ' .. p, 0); end
        f:write(text); f:close();
        path = p;
        print('[dlac] ' .. tostring(label) .. ': ' .. word .. ' -> ' .. p);
    end);
    if not ok then
        pcall(function() print('[dlac] ' .. tostring(label) .. ': report write FAILED -- ' .. tostring(err)); end);
    end
    return path;
end

-- Book the transfer-file write: label for the header/chat, fileBase for the
-- filename, the addon half's lines, and the engine handoff filename to merge
-- (nil = no engine half expected). The PROVISIONAL report writes RIGHT NOW
-- (the file exists the moment the command runs -- an early folder check
-- finds it, and its pending note is the tick's tripwire); the finished one
-- overwrites it at the delay. Default delay 1.2s lets the engine's same-
-- frame handoff land first; a capture window passes opts.delay = window + 4s
-- (the engine flushes at window end on a 0.4s tick, so +4s reads it fresh,
-- inside the 10s gate) and opts.append = a fn the final write calls for the
-- addon-side timeline lines.
function M.deliver(label, fileBase, addonLines, handoffName, opts)
    local ver = nil;
    pcall(function() ver = addon ~= nil and addon.version or nil; end);
    opts = opts or {};
    writeOut(fileBase, M._mergeSections(label, addonLines, false, os.time(), ver), label,
        string.format('report file created (finalizes in ~%ds)', math.ceil(tonumber(opts.delay) or 1.2)));
    _pend = { label = label, base = fileBase, lines = addonLines, handoff = handoffName,
              ver = ver, append = opts.append, dueAt = os.clock() + (tonumber(opts.delay) or 1.2) };
end

-- The finalize pass: overwrite the provisional with the merged report. All
-- failures print themselves (silence has no author -- the very lesson this
-- section exists to teach).
ashita.events.register('d3d_present', 'dlac-debug-deliver', function()
    if _pend == nil or os.clock() < _pend.dueAt then return; end
    local p = _pend; _pend = nil;
    -- Capture-window runs append their timeline at the WRITE moment (the
    -- window just closed; the log is complete now, not at booking time).
    if p.append ~= nil then
        local ok2, extra = pcall(p.append);
        if ok2 and type(extra) == 'table' then
            for _, l in ipairs(extra) do p.lines[#p.lines + 1] = l; end
        end
    end
    local engineRaw = nil;
    if p.handoff ~= nil then
        pcall(function()
            local base = charBase();
            if base ~= nil then engineRaw = readAll(base .. 'dlac\\' .. p.handoff); end
        end);
    end
    writeOut(p.base, M._mergeSections(p.label, p.lines, engineRaw, os.time(), p.ver),
        p.label, 'report finalized -- send this file');
end);

local PRINTERS = {
    -- rest = everything after 'debug' ('ls 60' -> the 60 is the window).
    ls = function(rest)
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
        -- The capture window (v106): snapshot printed, now WATCH. The player
        -- does the failing thing during the window; both states log what
        -- they see (the engine opened its own window off this same command),
        -- and the report writes at window end + 4s with both timelines.
        local dur = M._dur(rest ~= nil and rest:match('^%S+%s+(%S+)') or nil);
        pcall(function() m.debugCapture(dur); end);
        print(string.format('[dlac] debug ls: capturing for %ds -- click Apply (do the failing thing) NOW.'
            .. ' The report writes itself when the window closes.', dur));
        M.deliver('debug ls', 'dlac-debug-ls', lines, 'debug-ls-engine.txt', {
            delay = dur + 4.0,
            append = function()
                local ev = {};
                pcall(function() ev = m.debugCaptureLog(); end);
                local out = { '', string.format('== captured events, addon side (%ds window) ==', dur) };
                if #ev == 0 then
                    out[#out + 1] = '(no lockstyle events observed by the addon state during the window)';
                else
                    for _, l in ipairs(ev) do out[#out + 1] = l; end
                end
                return out;
            end,
        });
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
    PRINTERS[topic](rest);
end);

return M;
