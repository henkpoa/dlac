--[[
    dlac.lua — Ashita v4 addon entry point for "dynamic LuaAshitacast".

    dlac runs as a normal Ashita addon (so it can live under /addons and be server-
    approved). It reads player + inventory through AshitaCore and drives gear via
    LuaAshitacast's /lac commands, so it works *alongside* LAC without having to live
    inside a profile.

    The library modules still use the profile-style "dlac\\X" require prefix, so we add
    <install>/addons/?.lua to package.path -- that makes require("dlac\\X") resolve to
    addons/dlac/X.lua here in the addon's Lua state. X carries the folder, so
    require("dlac\\ui\\gearui") lands on addons/dlac/ui/gearui.lua.

    LAYOUT (docs/architecture.md "Repository layout"): the addon root is what LAC sees --
    this entry point plus the five seeded engine files (utils, dispatch, chatfmt, profiles,
    gear) that the seeder below copies into <char>\dlac\ and LAC loads in its own state.
    Those five must stay flat: require("dlac\\utils") is published API in every user
    profile. Everything only the addon loads lives in ui\ / data\ / gear\ / feature\ / lib\.

    WIP: the GUI still reads a little data from LuaAshitacast globals (gData = player
    job/level, gProfile.Sets = the Sets tab). Those are being decoupled to AshitaCore +
    <JOB>.lua file reads so the addon is fully standalone. Until that lands, some tabs
    are only fully populated when a LAC profile is also loaded.
]]--

addon.name    = 'dlac';
addon.author  = 'Mindie';
addon.version = '2026.07.23t';  -- date of the last shipped change (Ashita prints it at
                                -- load) -- bump alongside every commit that changes behavior
addon.desc    = 'Build gear sets and view live stats with level scaling (for LuaAshitacast).';

-- Load BEACON ('/dl check' field round, 2026-07-23): written by PLAIN io at
-- the very top of load, before anything else can fail. Its absence after an
-- /addon reload = THIS file did not execute (load error -- Ashita prints it
-- in red -- or a different install); its version line names the code that
-- DID load; the module loop appends its ledger at the bottom of the file.
-- It also exercises the exact write path the debug reports use.
pcall(function()
    local p = AshitaCore:GetInstallPath() .. 'addons\\dlac\\debug\\';
    if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(p); end
    local f = io.open(p .. 'load-report.txt', 'w');
    if f ~= nil then
        f:write(('dlac %s loading at %s\n'):format(addon.version, os.date('%Y-%m-%d %H:%M:%S')));
        f:close();
    end
end);

require('common');

-- Resolve the profile-style "dlac\\X" requires to addons/dlac/X.lua in the addon state.
pcall(function()
    package.path = package.path .. ';' .. AshitaCore:GetInstallPath() .. 'addons\\?.lua';
end);

-- Load THIS character's gear from their config folder, so the GUI shows your
-- real gear instead of the bundled empty template. Preloads package.loaded so every
-- module's require("dlac\\gear") returns it. Falls back to the template if none found.
-- Candidate order: the native home (config\addons\dlac\<char>\ -- live when the
-- native-engine flag is on), then the legacy LuaAshitacast homes.
pcall(function()
    local party = AshitaCore:GetMemoryManager():GetParty();
    local name  = party:GetMemberName(0);
    local id    = party:GetMemberServerId(0);
    if name == nil or name == '' or id == nil then return; end
    local candidates = {};
    pcall(function()
        local prof = require('dlac\\profiles');
        if prof.nativeMode() then
            local d = prof.dataDir();
            if d ~= nil then candidates[#candidates + 1] = d .. 'gear.lua'; end
        end
    end);
    local base = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\', AshitaCore:GetInstallPath(), name, id);
    candidates[#candidates + 1] = base .. 'dlac\\gear.lua';       -- legacy home
    candidates[#candidates + 1] = base .. 'ffxi-lac\\gear.lua';   -- a pre-migration profile
    for _, p in ipairs(candidates) do
        local chunk = loadfile(p);
        if chunk ~= nil then
            local ok, g = pcall(chunk);
            if ok and type(g) == 'table' then
                package.loaded['dlac\\gear'] = g;   -- routine: no chat line (see the banner)
                break;
            end
        end
    end
end);

-- Make the dlac library resolvable from your LuaAshitacast <JOB>.lua profiles WITHOUT a
-- fragile per-profile bootstrap line. LAC adds the profile folder to its own package.path,
-- so a copy of utils.lua (+ gear.lua) in <char>\dlac\ makes require("dlac\\utils") resolve
-- there -- the exact first path LAC searches. Library files are written only when their
-- BYTES differ from the seeded copy (the 5s watch below re-runs this, so unconditional
-- writes would grind the disk for nothing); gear.lua is seeded only when absent, so your
-- scanned inventory is never overwritten.
-- Returns true once the character is known (so the pre-login watch below can tell).
local function seedCharFolder()
    local seeded = false;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name  = party:GetMemberName(0);
        local id    = party:GetMemberServerId(0);
        if name == nil or name == '' or id == nil then return; end
        local addonDir = AshitaCore:GetInstallPath() .. 'addons\\dlac\\';
        local dstDir   = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\dlac\\', AshitaCore:GetInstallPath(), name, id);
        if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(dstDir); end
        local function slurp(p) local f = io.open(p, 'rb'); if f == nil then return nil; end local d = f:read('*a'); f:close(); return d; end
        local function spit(p, d) local f = io.open(p, 'wb'); if f == nil then return; end f:write(d); f:close(); end
        for _, f in ipairs({ 'utils.lua', 'dispatch.lua', 'chatfmt.lua', 'profiles.lua' }) do   -- library: track the addon copy
            local d = slurp(addonDir .. f);
            if d ~= nil and d ~= slurp(dstDir .. f) then spit(dstDir .. f, d); end
        end
        if slurp(dstDir .. 'gear.lua') == nil then           -- your data: seed the empty template only if absent
            local g = slurp(addonDir .. 'gear.lua');
            if g ~= nil then spit(dstDir .. 'gear.lua', g); end
        end
        -- routine seeding: no chat line (see the banner)
        seeded = true;
    end);
    return seeded;
end

-- The addon normally loads at Ashita boot -- BEFORE login -- so neither the gear preload
-- above nor this seeding can find a character; both silently no-op. The seeding runs again
-- every ~5s FOREVER (not just until the character is known): the addon directory is a git
-- checkout, and a `git pull` while the game runs used to strand the seeded copies until a
-- manual /addon reload -- the one missing hop in the update chain. With the watch, a pull
-- propagates addon -> seeded copy on its own, and the engine's content-keyed self-swap
-- (dispatch.lua v102) carries it the last hop into LAC's running state -- no manual step.
-- Compare-before-write above keeps the steady state read-only. (The in-memory gear preload
-- is deliberately NOT retried here: by then the modules below have already captured the
-- shared gear table, so swapping package.loaded would split them apart -- gearui re-reads
-- the real gear.lua IN PLACE on its own first-login hook, before the first auto-sync.)
--
-- NATIVE MODE (feature/native-engine): seeding serves the LAC state, which the
-- native engine replaces -- so the watch flips to storage auto-migration
-- instead: the first login after the flag turns on copies this character's
-- legacy data into config\addons\dlac\<char>\ (profiles.engineAutoMigrate --
-- copy only, legacy files stay put; settles to two file probes per beat).
local function maintainStorage()
    local isNative = false;
    pcall(function()
        local prof = require('dlac\\profiles');
        if prof.nativeMode() then
            isNative = true;
            prof.engineAutoMigrate(print);
        end
    end);
    if not isNative then seedCharFolder(); end
end
maintainStorage();
local _seedAt = 0;
ashita.events.register('d3d_present', 'dlac-seed-watch', function()
    if os.clock() < _seedAt then return; end
    _seedAt = os.clock() + 5.0;
    maintainStorage();
end);

-- LuaAshitacast supplies gData inside a profile; a standalone addon doesn't.
-- Provide the shim from feature\nativedata -- FULL LAC-parity providers
-- (player/action/pet/environment/equipment, sig-scan weather + vanatime),
-- which the native engine's dispatch reads and which upgrade the GUI's old
-- zero-stubs (live day/weather for the optimizer bonus) for free. Falls back
-- to a minimal stub if nativedata cannot load. Only defined when the real
-- gData is absent (i.e. always, in the addon state).
if rawget(_G, 'gData') == nil then
    local installed = false;
    pcall(function()
        local nd = require('dlac\\feature\\nativedata');
        local t = nd.build();
        if type(t) == 'table' and type(t.GetPlayer) == 'function' then
            _G.gData = t;
            installed = true;
        end
    end);
    if not installed then
        local JOB = { [1]='WAR',[2]='MNK',[3]='WHM',[4]='BLM',[5]='RDM',[6]='THF',[7]='PLD',[8]='DRK',
                      [9]='BST',[10]='BRD',[11]='RNG',[12]='SAM',[13]='NIN',[14]='DRG',[15]='SMN',[16]='BLU',
                      [17]='COR',[18]='PUP',[19]='DNC',[20]='SCH',[21]='GEO',[22]='RUN' };
        _G.gData = {
            GetPlayer = function()
                local t = { MainJob='?', MainJobSync=0, SubJob=nil, SubJobSync=0, Status=0, IsMoving=false };
                pcall(function()
                    local p = AshitaCore:GetMemoryManager():GetPlayer();
                    if p == nil then return; end
                    t.MainJob      = JOB[p:GetMainJob()] or '?';
                    t.MainJobSync  = p:GetMainJobLevel() or 0;
                    t.SubJob       = JOB[p:GetSubJob()];
                    t.SubJobSync   = p:GetSubJobLevel() or 0;
                    t.MainJobLevel = t.MainJobSync;
                    t.SubJobLevel  = t.SubJobSync;
                end);
                return t;
            end,
            GetWeather             = function() return 0; end,   -- best-effort (optimizer day/weather bonus)
            GetDay                 = function() return 0; end,
            GetElementalOpposition = function() return nil; end,
            GetAugment             = function() return nil; end,
        };
    end
    -- routine (always the case in addon mode): no chat line
end

-- Load the library. Each module registers its own /dl command(s); gearui also registers
-- the GUI render hook. Guarded so one module failing can't take the addon down.
-- Paths are folder-qualified (see the LAYOUT note at the top of this file): only the
-- seeded engine sits flat at the addon root, everything else lives under ui\ / gear\ /
-- feature\. Built by concat, so these names are invisible to a literal require() grep.
-- Module-load LEDGER: every require result of this loop, recorded for
-- '/dl check' (its "modules: N/M loaded" line + issue verdict -- a corrupt or
-- half-synced tree shows up as NAMED failures instead of one scrolled-away
-- chat line). Stashed under a virtual package name so feature\check.lua can
-- read it at command time (the gear-preload package.loaded precedent -- no
-- such file exists on disk, and none may be created).
local ledger = { total = 0, failed = {} };
package.loaded['dlac\\loadledger'] = ledger;
local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
ledger.total = ledger.total + 1;
if not _cfok then ledger.failed[#ledger.failed + 1] = { mod = 'chatfmt', err = tostring(_cfmt) }; end
for _, mod in ipairs({ 'gear', 'feature\\augments', 'gear\\gearoptim', 'gear\\gearimport',
                       'gear\\gearexport', 'feature\\useitem', 'feature\\craftwatch',
                       'ui\\craftbar', 'feature\\helmwatch', 'ui\\helmbar',
                       'feature\\fishwatch', 'ui\\fishbar', 'feature\\meritwatch',
                       'feature\\check', 'feature\\debug', 'feature\\lockstyle',
                       'feature\\equipengine', 'feature\\engine', 'ui\\gearui' }) do
    local ok, err = pcall(require, 'dlac\\' .. mod);
    ledger.total = ledger.total + 1;
    if not ok then
        ledger.failed[#ledger.failed + 1] = { mod = mod, err = tostring(err) };
        local m = string.format('failed to load %s: %s', mod, tostring(err));
        if _cfok then _cfmt.err(m); else print('[dlac] ' .. m); end
    end
end

-- The beacon's second half: the ledger, appended once the loop is done. A
-- module failure is now readable OFF DISK (addons\dlac\debug\load-report.txt)
-- even when its chat line scrolled away or chat itself is the broken thing.
pcall(function()
    local f = io.open(AshitaCore:GetInstallPath() .. 'addons\\dlac\\debug\\load-report.txt', 'a');
    if f ~= nil then
        f:write(('modules: %d total, %d failed\n'):format(ledger.total, #ledger.failed));
        for _, e in ipairs(ledger.failed) do
            f:write(('FAILED %s: %s\n'):format(tostring(e.mod), tostring(e.err)));
        end
        f:write('load complete\n');
        f:close();
    end
end);

-- GUI keybind: CTRL+K toggles the window (same mechanism as the modes' GUI-managed
-- binds). Bound on load, released on unload so no bind outlives the addon.
pcall(function()
    AshitaCore:GetChatManager():QueueCommand(-1, '/bind ^k /dl ui');
end);
ashita.events.register('unload', 'dlac-unbind', function()
    pcall(function() AshitaCore:GetChatManager():QueueCommand(-1, '/unbind ^k'); end);
end);

-- No load banner (inform by printing as little as possible): Ashita itself
-- reports the addon load, and the /bind above already echoes the CTRL+K bind.
