--[[
    dlac.lua — Ashita v4 addon entry point. dlac IS the equip engine: it reads
    player + inventory through AshitaCore and equips via its own authentic
    0x050/0x051 packets (feature\equipengine + dispatch.lua). The name is
    history — "dynamic LuaAshitacast" absorbed its host (ADR 0015) and the
    LuaShitacast purge (docs/design/lac-purge-plan.md) removed the last of it:
    one Lua state, one engine, one storage home (config\addons\dlac\<char>\).
    Old luashitacast\ trees are read-only IMPORT territory (Sets tab static /
    group imports; login auto-migration copies data in, never touches it).

    The library modules use the "dlac\\X" require prefix: <install>/addons/?.lua
    is appended to package.path, so require("dlac\\X") resolves to
    addons/dlac/X.lua. X carries the folder — require("dlac\\ui\\gearui") lands
    on addons/dlac/ui/gearui.lua. The five root files (utils, dispatch, chatfmt,
    profiles, gear) stay flat: require("dlac\\utils") is published API. GUI in
    ui\, data in data\, gear machinery in gear\, features in feature\, lib\.
]]--

addon.name    = 'dlac';
addon.author  = 'Mindie';
addon.version = '2026.07.28j';  -- date of the last shipped change (Ashita prints it at
                                -- load) -- bump alongside every commit that changes behavior
addon.desc    = 'Gear sets, triggers and live stats with level scaling -- dlac equips your gear itself.';

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
        local d = prof.dataDir();
        if d ~= nil then candidates[#candidates + 1] = d .. 'gear.lua'; end
    end);
    -- (The legacy-home candidates died in the purge: the boot reads only the
    -- native home; old trees are the IMPORTERS' territory, and auto-migration
    -- carries a straggler's gear.lua in before this matters.)
    for _, p in ipairs(candidates) do
        local present = false;
        local fh = io.open(p, 'r'); if fh ~= nil then present = true; fh:close(); end
        local chunk, lerr = loadfile(p);
        if chunk ~= nil then
            local ok, g = pcall(chunk);
            if ok and type(g) == 'table' then
                package.loaded['dlac\\gear'] = g;   -- routine: no chat line (see the banner)
                break;
            end
            -- A gear.lua that EXISTS but won't load used to fall through in
            -- silence, leaving the bundled empty template in package.loaded: the
            -- GUI shows no gear, every scan calls every item new, and nothing
            -- anywhere says a real inventory is sitting on disk one bad entry
            -- away. Never silent again.
            print('[dlac] gear.lua exists but failed to load: ' .. tostring(g));
            print('[dlac] running on an EMPTY inventory -- /dl commit names the entry at fault.');
        elseif present then
            print('[dlac] gear.lua will not parse: ' .. tostring(lerr));
            print('[dlac] running on an EMPTY inventory until it does.');
        end
    end
end);

-- (The LEGACY SEEDER lived here until the LuaShitacast purge, Phase 1 -- it
-- copied utils/dispatch/chatfmt/profiles.lua + a gear template into
-- config\addons\luashitacast\<char>\dlac\ every 5s so LAC's state could
-- require them. Nothing writes under luashitacast\ anymore: that tree is
-- read-only import/migration territory. See docs/design/lac-purge-plan.md.)

-- The storage watch: the addon loads at Ashita boot -- BEFORE login -- so the
-- gear preload above finds no character; the ~5s watch below retries FOREVER.
-- Its whole job now is the native home: the first-run decision, the one-time
-- auto-migration of legacy data INTO config\addons\dlac\<char>\ (copy only,
-- legacy files stay put), and the fresh-job auto-setup. (The LAC seeding half
-- and the LAC-alive polite ask died in the purge, Phase 1; the coexistence
-- tripwire in equipengine remains the hard backstop against a foreign engine.)
local function maintainStorage()
    -- Native, always (purge Phase 2): no first-run decision, no flag, no
    -- undecided state -- the manufactured-evidence bug family (07-23, 07-27)
    -- is structurally gone. The beat carries legacy data INTO the native home
    -- (engineAutoMigrate -- copy-only, Henrik's keep) and auto-creates a
    -- fresh job's baseline.
    pcall(function()
        local prof = require('dlac\\profiles');
        prof.engineAutoMigrate(print);
        -- FRESH-INSTALL AUTO-SETUP (issue #91): silently create this
        -- character+job's baseline when it is missing -- storage, gear
        -- inventory, base sets, starter triggers -- so a new player never
        -- touches Setup. No-ops until gearui has configured setupui and for
        -- a not-ready job; a disk failure names itself and retries. See
        -- setupui.autoSetupNative for the full gate list.
        pcall(function()
            local setup = require('dlac\\ui\\setupui');
            if type(setup.autoSetupNative) == 'function' then setup.autoSetupNative(); end
        end);
    end);
end
maintainStorage();
local _seedAt = 0;
ashita.events.register('d3d_present', 'dlac-seed-watch', function()
    -- Session-only reset for the bar-LESS Chocobo sibling: the craft/helm/fish
    -- switches get reset for free because their floating bar calls isEnabled()
    -- (-> loadState) every frame; chocoui has no bar, so a stale enabled=true from
    -- last session would let the ENGINE glue riding gear on at login before any
    -- loadState runs. Force it here (idempotent -- self-limits via chocowatch's
    -- _stateLoaded once charDir() is available), OUTSIDE the 5s throttle so it
    -- lands on the first post-login frame, before the engine's first Default read.
    pcall(function()
        local cw = require('dlac\\feature\\chocowatch');
        if type(cw) ~= 'table' then return; end
        if type(cw.loadState) == 'function' then cw.loadState(); end
        -- Drain any dig-obtained item ids the 0x02D packet handler stashed on the
        -- network thread -- ratchet + save + announce here on the MAIN thread.
        if type(cw.pumpObtains) == 'function' then cw.pumpObtains(); end
    end);
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
                       'feature\\synthrun',
                       'ui\\craftbar', 'feature\\helmwatch', 'ui\\helmbar',
                       'feature\\fishwatch', 'ui\\fishbar', 'feature\\chocowatch',
                       'feature\\meritwatch',
                       'feature\\check', 'feature\\debug', 'feature\\lockstyle',
                       'feature\\lockstyleapply', 'feature\\equipengine',
                       'feature\\engine', 'ui\\gearui' }) do
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
