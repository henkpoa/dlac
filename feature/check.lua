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

-- (The seeded-copies comparison died in the purge, Phase 3 with #131: there
-- are no seeds -- the addon folder is the one code home.)

-- A healthy catalog carries ~14.9k items; far fewer means the file lost its
-- tail (the classic interrupted-sync shape -- it still PARSES, so only a
-- count catches it).
local CATALOG_MIN = 10000;

-- ---------------------------------------------------------------------------
-- pure seams (headless-tested, CHK*)
-- ---------------------------------------------------------------------------

-- (M._seededState and M._shimWord died with the seeds and the shim-centric
-- job-file model -- purge Phase 3. The sets truth is the PROFILE sets file.)

-- The issue hunt (pure): everything the addon side can PROVE wrong. States it
-- cannot distinguish from a fresh install (empty gear.lua, legacy storage,
-- pre-login unknowns) are reported in the lines but never called issues.
function M._issues(info)
    info = info or {};
    local I = {};
    local sv, fv = tonumber(info.stampV), tonumber(info.fileV);
    if sv ~= nil and fv ~= nil and sv ~= fv then
        if sv < fv then
            I[#I + 1] = string.format('engine stamp v%d BEHIND engine file v%d -> /dl reload', sv, fv);
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
    -- The native baseline (2026-08-05): auto-setup retries every beat and says
    -- its one line once, so by the time a player runs /dl check the chat is long
    -- gone. An incomplete baseline is a PROVABLE problem -- name the gate and
    -- the seeder's reason, which together are the whole diagnosis.
    local bl = info.baseline;
    if type(bl) == 'table' and bl.complete ~= true then
        local s = string.format('native baseline INCOMPLETE for %s -- missing %s',
            tostring(bl.job or '?'), tostring(bl.missing or '(unknown)'));
        if type(bl.why) == 'table' and #bl.why > 0 then s = s .. ' -- ' .. table.concat(bl.why, '; '); end
        I[#I + 1] = s;
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
    local setsWord = info.setsWord or 'unknown (no job / not logged in?)';
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
    local L = {
        string.format('check (addon): dlac %s -- engine file v%s',
            tostring(info.addonVer or '?'), tostring(info.fileV or '?')),
        string.format('check (addon): sets file: %s', setsWord),
        string.format('check (addon): modules: %s', modWord),
        string.format('check (addon): data: catalog %s -- gear.lua %s -- profile %s',
            catWord, gearWord, profWord),
        string.format('check (addon): engine %s -- a "[dlac] check (engine): alive" line must appear'
            .. ' with this readout; if it is MISSING, the engine is not armed in this state'
            .. ' (tripwire? /dl engine explains) -- /dl reload reloads dlac.', stampWord),
    };
    -- The baseline line EARNS its place: it appears only when the baseline is
    -- actually broken, so a healthy install keeps its six lines and the reader
    -- never learns to skip a row that is always green.
    local bl = info.baseline;
    if type(bl) == 'table' and bl.complete ~= true then
        local s = string.format('check (addon): native baseline for %s: MISSING %s',
            tostring(bl.job or '?'), tostring(bl.missing or '(unknown)'));
        if type(bl.why) == 'table' and #bl.why > 0 then
            s = s .. ' -- seeder said: ' .. table.concat(bl.why, '; ');
        end
        if bl.at ~= nil then s = s .. ' (last tried ' .. tostring(bl.at) .. ')'; end
        L[#L + 1] = s;
    end
    L[#L + 1] = verdict;
    return L;
end

-- ---------------------------------------------------------------------------
-- live glue (Ashita only)
-- ---------------------------------------------------------------------------

-- The live gather, split out of report() (2026-08-03) so /dl report can put
-- the SAME health readout at the top of its bundle without capturing print.
-- One implementation, two doors -- the check/ls precedent.
function M.gather()
    local info = {};
    pcall(function() info.addonVer = addon ~= nil and addon.version or nil; end);
    local dsp = try('dlac\\dispatch');
    info.fileV = (dsp ~= nil) and dsp.VERSION or nil;
    -- The engine handshake: dispatch stamps __version into the NATIVE home's
    -- modestate.lua on every load (purge Phase 3: the reader finally reads
    -- where the writer writes -- #131's split, closed).
    pcall(function()
        local prof = try('dlac\\profiles');
        local d = prof ~= nil and prof.dataDir() or nil;
        if d == nil then return; end
        local chunk = loadfile(d .. 'modestate.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then info.stampV = tonumber(t.__version); end
    end);
    -- The sets truth: the ACTIVE profile's sets file for the current job.
    pcall(function()
        local prof = try('dlac\\profiles');
        if prof == nil then return; end
        local job = nil;
        pcall(function() job = gData.GetPlayer().MainJob; end);
        if type(job) ~= 'string' or job == '' or job == '?' then return; end
        if prof.hasSetsFile(job) then
            info.setsWord = tostring(prof.setsPath(job)) .. ' (present)';
        else
            info.setsWord = 'none yet for ' .. job .. ' (build sets in the Sets tab; auto-setup seeds the base four)';
        end
    end);
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
    -- The native baseline, asked of the SAME function auto-setup gates on, so
    -- the readout and the retry loop can never disagree. Plus whatever the last
    -- seed attempt said about WHY -- the half that used to exist only as a chat
    -- line nobody still had by the time they asked for help.
    pcall(function()
        local su = try('dlac\\ui\\setupui');
        if su == nil or type(su.nativeBaselineComplete) ~= 'function' then return; end
        local job = nil;
        pcall(function() job = gData.GetPlayer().MainJob; end);
        if type(job) ~= 'string' or job == '' or job == '?' then return; end
        local complete, missing = su.nativeBaselineComplete(job);
        local fail = su.lastSeedFail;
        info.baseline = {
            job = job, complete = complete, missing = missing,
            why = (type(fail) == 'table' and fail.job == job) and fail.why or nil,
            at  = (type(fail) == 'table' and fail.job == job) and fail.at or nil,
        };
    end);
    return info;
end

function M.report()
    local lines = M._lines(M.gather());
    for _, l in ipairs(lines) do print('[dlac] ' .. l); end
    -- The file rule (Henrik 07-23): every check/debug run lands as ONE
    -- transferable .txt. feature/debug.lua owns the writer + the engine-half
    -- merge (the 'check' engine branch writes debug-check-engine.txt).
    local dbg = try('dlac\\feature\\debug');
    if dbg ~= nil and type(dbg.deliver) == 'function' then
        -- delay 3s (not the 1.2 default): when the engine answers via the
        -- REQUEST file instead of the command (its 1s watch + the write),
        -- the handoff can land ~2s out -- the finalize must read past it.
        pcall(dbg.deliver, 'check', 'dlac-check', lines, 'debug-check-engine.txt', { delay = 3.0 });
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
    -- And the ENGINE REQUEST (v108): our e.blocked can starve the engine of
    -- this very command when it sits later in Ashita's chain (the friend's
    -- reload order) -- the request file reaches it regardless.
    pcall(function()
        local dbg = try('dlac\\feature\\debug');
        if dbg ~= nil and type(dbg.heard) == 'function' then dbg.heard('/dl check (addon handler)'); end
        if dbg ~= nil and type(dbg.requestEngine) == 'function' then dbg.requestEngine('check'); end
    end);
    M.report();
end);

return M;
