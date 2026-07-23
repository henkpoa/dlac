--[[
    dlac/check.lua -- /dl check: the wiring-health readout (Henrik's 2026-07-23
    ruling: self-checks that answer "is dlac doing what it should?" belong IN
    dlac; packet-level forensics stay in dlacprobe).

    The field case that begat it: a friend's laptop synced the ADDON tree but
    the LAC side never loaded the engine -- GUI + lockstyle preview (addon
    state) worked, lockstyle apply ('/dl ls apply', engine state) fell into a
    void, and nothing said WHY. The engine cannot report its own absence, so
    THIS side (the addon state, which always hears a typed /dl) prints the
    wiring readout and names the one line the engine must add to it: a missing
    "[dlac] check (engine): alive" line IS the diagnosis.

    Addon half (3 lines):
      1. addon version -- the addon tree's engine file version (require
         'dlac\\dispatch', the inert addon-state copy) -- whether the seeded
         copies in <char>\dlac\ byte-match the tree (the seeder's steady state;
         STALE here means dlac.lua's 5s seed watch is not doing its job).
      2. the job file's shim state (setupui's classifier -- the clean-shim
         standard says 'ok' is the only good answer).
      3. the engine version last stamped into modestate.lua, and the
         missing-engine-line interpretation.
    Engine half (dispatch.lua 'check'): one "alive" line -- live version, job,
    profile. Liveness + identity only, no deep state.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- The four library files the seeder tracks (dlac.lua seedCharFolder): compare
-- addon-tree bytes against the seeded copy. gear.lua is user data, not listed.
local SEEDED = { 'utils.lua', 'dispatch.lua', 'chatfmt.lua', 'profiles.lua' };

-- ---------------------------------------------------------------------------
-- pure seams (headless-tested, CHK*)
-- ---------------------------------------------------------------------------

-- files = { { name=, addon=bytes|nil, seeded=bytes|nil }, ... } -> 'current'
-- or 'STALE: a, b'. An unreadable tree copy or a missing seeded copy both
-- count stale -- either way the steady state ("seeded == tree") is broken.
function M._seededState(files)
    local bad = {};
    for _, f in ipairs(files or {}) do
        if f.addon == nil or f.addon ~= f.seeded then bad[#bad + 1] = f.name; end
    end
    if #bad == 0 then return 'current'; end
    return 'STALE: ' .. table.concat(bad, ', ');
end

-- setupui.jobSetupState() word -> what to say (and what to DO about it).
function M._shimWord(st)
    if st == 'ok'      then return 'clean dlac shim'; end
    if st == 'wired'   then return 'NOT the clean shim (old dlac wiring) -> run Setup'; end
    if st == 'ffxilac' then return 'an ffxi-lac profile -> run Setup (it migrates your sets)'; end
    if st == 'none'    then return 'not dlac-wired -> run Setup (it migrates your sets)'; end
    if st == 'nofile'  then return 'MISSING -> run Setup'; end
    return 'unknown (no job / not logged in?)';
end

-- info = { addonVer, fileV, seeded, shim, stampV } -> the three addon-half
-- lines (no '[dlac] ' prefix -- report() adds it). Line 3 carries the
-- interpretation that makes an ABSENT engine line a verdict instead of a
-- shrug -- the whole reason this command exists.
function M._lines(info)
    info = info or {};
    local stampWord = (info.stampV ~= nil) and ('last stamped v' .. tostring(info.stampV))
                      or 'NEVER stamped in (no modestate)';
    return {
        string.format('check (addon): dlac %s -- engine file v%s -- seeded copies: %s',
            tostring(info.addonVer or '?'), tostring(info.fileV or '?'),
            tostring(info.seeded or 'unknown (not logged in?)')),
        string.format('check (addon): job file: %s', M._shimWord(info.shim)),
        string.format('check (addon): engine %s -- a "[dlac] check (engine): alive" line must appear'
            .. ' with this readout; if it is MISSING, LuaAshitacast is not running the dlac engine:'
            .. ' run Setup (dlac header), then Reload LAC.', stampWord),
    };
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

local function slurp(p)
    local f = io.open(p, 'rb'); if f == nil then return nil; end
    local d = f:read('*a'); f:close(); return d;
end

function M.report()
    local info = {};
    pcall(function() info.addonVer = addon ~= nil and addon.version or nil; end);
    local dsp = try('dlac\\dispatch');
    info.fileV = (dsp ~= nil) and dsp.VERSION or nil;
    local base = charBase();
    if base ~= nil then
        pcall(function()
            local addonDir = AshitaCore:GetInstallPath() .. 'addons\\dlac\\';
            local files = {};
            for _, f in ipairs(SEEDED) do
                files[#files + 1] = { name = f, addon = slurp(addonDir .. f), seeded = slurp(base .. 'dlac\\' .. f) };
            end
            info.seeded = M._seededState(files);
        end);
        -- The engine handshake: dispatch (LAC state) stamps __version into
        -- modestate.lua on every load/self-swap (the Reload-LAC nag's source).
        pcall(function()
            local chunk = loadfile(base .. 'dlac\\modestate.lua');
            if chunk == nil then return; end
            local ok, t = pcall(chunk);
            if ok and type(t) == 'table' then info.stampV = tonumber(t.__version); end
        end);
    end
    local su = try('dlac\\ui\\setupui');
    if su ~= nil and type(su.jobSetupState) == 'function' then
        local ok, st = pcall(su.jobSetupState);
        if ok then info.shim = st; end
    end
    for _, l in ipairs(M._lines(info)) do print('[dlac] ' .. l); end
end

-- '/dl check' in the ADDON state. e.blocked only quiets the game parser --
-- the LAC state's dispatch handler still sees the command (the /dl ls apply
-- precedent) and answers with its engine line.
ashita.events.register('command', 'dlac-check', function(e)
    local raw = string.lower(e.command);
    if raw:match('^/dl%s+check%s*$') == nil and raw:match('^/dlac%s+check%s*$') == nil then return; end
    e.blocked = true;
    M.report();
end);

return M;
