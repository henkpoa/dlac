--[[
    dlac/check.lua -- /dl check: the GENERAL HEALTH readout (Henrik's
    2026-07-23 rulings: self-checks that answer "is dlac doing what it
    should?" belong IN dlac, packet-level forensics stay in dlacprobe; and
    "dl check is a good command IF it checks the general health of dl and can
    REPORT ISSUES" -- so this is not a stamp recital, it hunts problems and
    names them in a verdict).

    The field case that begat it: a friend's laptop synced the addon tree but
    the LAC side never loaded the engine -- GUI + lockstyle preview (addon
    state) worked, lockstyle apply (engine state) fell into a void, and
    nothing said WHY. The engine cannot report its own absence, so THIS side
    (the addon state, which always hears a typed /dl) prints the health
    readout and names the one line the engine must add: a missing
    "[dlac] check (engine): alive" line IS the diagnosis.

    Addon half (6 lines):
      1. addon version -- the addon tree's engine file version -- whether the
         seeded copies in <char>\dlac\ byte-match the tree (the seeder's
         steady state).
      2. the job file's shim state (setupui's classifier).
      3. the module-load ledger (dlac.lua records every require of the load
         loop): a corrupt/half-synced tree shows up HERE as named failures.
      4. data sanity: catalog present + item count (a truncated sync shows as
         a small count), gear.lua entry count vs the empty template, active
         profile.
      5. the engine version last stamped into modestate (__version handshake)
         plus the missing-engine-line interpretation.
      6. the VERDICT: 'NO ISSUES addon-side' or the numbered issue list
         (stale seeded copies, non-shim job file, engine/file version
         disagreement -- and which side is behind, module load failures,
         unreadable/truncated catalog).
    Engine half (dispatch.lua 'check'): one "alive" line -- live version,
    job, profile. Liveness + identity only; per-feature state lives under
    /dl debug <topic>.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- The four library files the seeder tracks (dlac.lua seedCharFolder): compare
-- addon-tree bytes against the seeded copy. gear.lua is user data, not listed.
local SEEDED = { 'utils.lua', 'dispatch.lua', 'chatfmt.lua', 'profiles.lua' };

-- A healthy catalog carries ~14.9k items; far fewer means the file lost its
-- tail (the classic interrupted-sync shape -- it still PARSES, so only a
-- count catches it).
local CATALOG_MIN = 10000;

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

-- The issue hunt (pure): everything the addon side can PROVE wrong. States it
-- cannot distinguish from a fresh install (empty gear.lua, legacy storage,
-- pre-login unknowns) are reported in the lines but never called issues.
function M._issues(info)
    info = info or {};
    local I = {};
    if type(info.seeded) == 'string' and info.seeded:find('STALE', 1, true) == 1 then
        I[#I + 1] = 'seeded engine copies STALE -> /addon reload dlac (or restart the game)';
    end
    if info.shim ~= nil and info.shim ~= 'ok' and info.shim ~= 'nojob' then
        I[#I + 1] = 'job file is not the clean dlac shim -> run Setup';
    end
    local sv, fv = tonumber(info.stampV), tonumber(info.fileV);
    if sv ~= nil and fv ~= nil and sv ~= fv then
        if sv < fv then
            I[#I + 1] = string.format('engine stamp v%d BEHIND engine file v%d -> Reload LAC', sv, fv);
        else
            I[#I + 1] = string.format('engine stamp v%d AHEAD of engine file v%d -- the addon tree is stale -> update/sync dlac, then /addon reload dlac', sv, fv);
        end
    end
    local mods = info.modules;
    if type(mods) == 'table' and type(mods.failed) == 'table' and #mods.failed > 0 then
        local names = {};
        for _, f in ipairs(mods.failed) do names[#names + 1] = tostring(f.mod); end
        I[#I + 1] = string.format('%d module(s) FAILED to load: %s (corrupt/partial files?)', #names, table.concat(names, ', '));
    end
    if info.catalogTried == true and info.catalogN == nil then
        I[#I + 1] = 'catalog UNREADABLE (data\\catalog.lua missing or corrupt)';
    elseif tonumber(info.catalogN) ~= nil and tonumber(info.catalogN) < CATALOG_MIN then
        I[#I + 1] = string.format('catalog has only %d items (~14.9k expected) -- truncated sync?', tonumber(info.catalogN));
    end
    return I;
end

-- info -> the six addon-half lines (no '[dlac] ' prefix -- report() adds it).
-- Line 5 carries the interpretation that makes an ABSENT engine line a
-- verdict instead of a shrug; line 6 is the issue verdict.
function M._lines(info)
    info = info or {};
    local stampWord = (info.stampV ~= nil) and ('last stamped v' .. tostring(info.stampV))
                      or 'NEVER stamped in (no modestate)';
    local mods = info.modules;
    local modWord = '?';
    if type(mods) == 'table' and tonumber(mods.total) ~= nil then
        local nf = (type(mods.failed) == 'table') and #mods.failed or 0;
        modWord = string.format('%d/%d loaded', mods.total - nf, mods.total);
        if nf > 0 then
            local parts = {};
            for _, f in ipairs(mods.failed) do
                parts[#parts + 1] = string.format('%s (%s)', tostring(f.mod),
                    tostring(f.err or '?'):gsub('%s+', ' '):sub(1, 90));
            end
            modWord = modWord .. ' -- FAILED: ' .. table.concat(parts, ', ');
        end
    end
    local catWord = (info.catalogN ~= nil) and (tostring(info.catalogN) .. ' items')
                    or (info.catalogTried == true and 'UNREADABLE' or '?');
    local gearWord = (tonumber(info.gearN) ~= nil and tonumber(info.gearN) > 0)
                     and (tostring(info.gearN) .. ' entries')
                     or 'EMPTY template (fresh/pre-login; /dl sync indexes your bags)';
    local profWord = (info.profName ~= nil) and ('"' .. tostring(info.profName) .. '"') or '(legacy storage)';
    local issues = M._issues(info);
    local verdict;
    if #issues == 0 then
        verdict = 'verdict: NO ISSUES addon-side -- pair with the engine line.';
    else
        verdict = string.format('verdict: %d ISSUE%s -- %s', #issues, (#issues == 1) and '' or 'S',
            table.concat(issues, '; '));
    end
    return {
        string.format('check (addon): dlac %s -- engine file v%s -- seeded copies: %s',
            tostring(info.addonVer or '?'), tostring(info.fileV or '?'),
            tostring(info.seeded or 'unknown (not logged in?)')),
        string.format('check (addon): job file: %s', M._shimWord(info.shim)),
        string.format('check (addon): modules: %s', modWord),
        string.format('check (addon): data: catalog %s -- gear.lua %s -- profile %s',
            catWord, gearWord, profWord),
        string.format('check (addon): engine %s -- a "[dlac] check (engine): alive" line must appear'
            .. ' with this readout; if it is MISSING, LuaAshitacast is not running the dlac engine:'
            .. ' run Setup (dlac header), then Reload LAC.', stampWord),
        verdict,
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
    -- The load ledger dlac.lua stashes under a virtual package name (the
    -- gear-preload precedent): every module require of the load loop, with
    -- the failures' errors.
    local led = try('dlac\\loadledger');
    if led ~= nil and tonumber(led.total) ~= nil then info.modules = led; end
    -- Catalog through its ONE door (catalogindex; GRD law -- never require
    -- the catalog directly). rawIndex() builds/caches the byId map the GUI
    -- uses anyway; its size is the item count a truncated file cannot fake.
    pcall(function()
        local ci = try('dlac\\gear\\catalogindex');
        if ci == nil then return; end
        info.catalogTried = true;
        if not ci.available() then return; end
        local n = 0;
        for _ in pairs(ci.rawIndex()) do n = n + 1; end
        info.catalogN = n;
    end);
    pcall(function()
        local gr = try('dlac\\gear');
        if gr == nil or type(gr.NameToObject) ~= 'table' then return; end
        local n = 0;
        for _ in pairs(gr.NameToObject) do n = n + 1; end
        info.gearN = n;
    end);
    pcall(function()
        local prof = try('dlac\\profiles');
        if prof ~= nil and type(prof.activeName) == 'function' then info.profName = prof.activeName(); end
    end);
    local lines = M._lines(info);
    for _, l in ipairs(lines) do print('[dlac] ' .. l); end
    -- The file rule (Henrik 07-23): every check/debug run lands as ONE
    -- transferable .txt. feature/debug.lua owns the writer + the engine-half
    -- merge (the 'check' engine branch writes debug-check-engine.txt).
    local dbg = try('dlac\\feature\\debug');
    if dbg ~= nil and type(dbg.deliver) == 'function' then
        pcall(dbg.deliver, 'check', 'dlac-check', lines, 'debug-check-engine.txt');
    end
end

-- '/dl check' in the ADDON state. e.blocked only quiets the game parser --
-- the LAC state's dispatch handler still sees the command (the /dl ls apply
-- precedent) and answers with its engine line.
ashita.events.register('command', 'dlac-check', function(e)
    local raw = string.lower(e.command);
    if raw:match('^/dl%s+check%s*$') == nil and raw:match('^/dlac%s+check%s*$') == nil then return; end
    e.blocked = true;
    -- Receipt + the fallback-quieting stamp (feature/debug.lua): proof on
    -- disk that this state heard the command (07-23: it provably did not).
    pcall(function()
        local dbg = try('dlac\\feature\\debug');
        if dbg ~= nil and type(dbg.heard) == 'function' then dbg.heard('/dl check (addon handler)'); end
    end);
    M.report();
end);

return M;
