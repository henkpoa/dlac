--[[
    dlac.lua — Ashita v4 addon entry point for "dynamic LuaAshitacast".

    dlac runs as a normal Ashita addon (so it can live under /addons and be server-
    approved). It reads player + inventory through AshitaCore and drives gear via
    LuaAshitacast's /lac commands, so it works *alongside* LAC without having to live
    inside a profile.

    The library modules still use the profile-style "dlac\\X" require prefix, so we add
    <install>/addons/?.lua to package.path -- that makes require("dlac\\X") resolve to
    addons/dlac/X.lua here in the addon's Lua state.

    WIP: the GUI still reads a little data from LuaAshitacast globals (gData = player
    job/level, gProfile.Sets = the Sets tab). Those are being decoupled to AshitaCore +
    <JOB>.lua file reads so the addon is fully standalone. Until that lands, some tabs
    are only fully populated when a LAC profile is also loaded.
]]--

addon.name    = 'dlac';
addon.author  = 'Mindie';
addon.version = '0.1';
addon.desc    = 'Build gear sets and view live stats with level scaling (for LuaAshitacast).';

require('common');

-- Resolve the profile-style "dlac\\X" requires to addons/dlac/X.lua in the addon state.
pcall(function()
    package.path = package.path .. ';' .. AshitaCore:GetInstallPath() .. 'addons\\?.lua';
end);

-- Load THIS character's gear from their LuaAshitacast config folder, so the GUI shows
-- your real gear instead of the bundled empty template. Preloads package.loaded so every
-- module's require("dlac\\gear") returns it. Falls back to the template if none found.
pcall(function()
    local party = AshitaCore:GetMemoryManager():GetParty();
    local name  = party:GetMemberName(0);
    local id    = party:GetMemberServerId(0);
    if name == nil or name == '' or id == nil then return; end
    local base = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\', AshitaCore:GetInstallPath(), name, id);
    for _, sub in ipairs({ 'dlac\\gear.lua', 'ffxi-lac\\gear.lua' }) do   -- dlac first, then a pre-migration profile
        local chunk = loadfile(base .. sub);
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
-- there -- the exact first path LAC searches. utils.lua is refreshed every load (tracks the
-- addon); gear.lua is seeded only when absent, so your scanned inventory is never overwritten.
-- Returns true once the character is known (so the pre-login retry below knows when to stop).
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
        for _, f in ipairs({ 'utils.lua', 'dispatch.lua', 'chatfmt.lua', 'profiles.lua' }) do   -- library: always refresh from the addon
            local d = slurp(addonDir .. f);
            if d ~= nil then spit(dstDir .. f, d); end
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
-- above nor this seeding can find a character; both silently no-op. Retry the seeding ONCE,
-- the first frame the character is known, so the library copies land and a fresh character
-- still gets the gear.lua template. (The in-memory gear preload is deliberately NOT retried
-- here: by then the modules below have already captured the shared gear table, so swapping
-- package.loaded would split them apart -- gearui re-reads the real gear.lua IN PLACE on its
-- own first-login hook, before the first auto-sync.)
if not seedCharFolder() then
    ashita.events.register('d3d_present', 'dlac-seed-retry', function()
        if seedCharFolder() then
            ashita.events.unregister('d3d_present', 'dlac-seed-retry');
        end
    end);
end

-- LuaAshitacast supplies gData inside a profile; a standalone addon doesn't. Provide a
-- minimal gData shim from AshitaCore so the shared modules (gearui/utils/gearoptim) that
-- read player job/level work unchanged as an addon -- without this, everything reads as
-- "level 0" and no gear is usable. Only defined when the real gData is absent.
if rawget(_G, 'gData') == nil then
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
    -- routine (always the case in addon mode): no chat line
end

-- Load the library. Each module registers its own /dl command(s); gearui also registers
-- the GUI render hook. Guarded so one module failing can't take the addon down.
local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
for _, mod in ipairs({ 'gear', 'augments', 'gearoptim', 'gearimport', 'useitem', 'craftwatch', 'craftbar', 'gearui' }) do
    local ok, err = pcall(require, 'dlac\\' .. mod);
    if not ok then
        local m = string.format('failed to load %s: %s', mod, tostring(err));
        if _cfok then _cfmt.err(m); else print('[dlac] ' .. m); end
    end
end

-- GUI keybind: CTRL+K toggles the window (same mechanism as the modes' GUI-managed
-- binds). Bound on load, released on unload so no bind outlives the addon.
pcall(function()
    AshitaCore:GetChatManager():QueueCommand(-1, '/bind ^k /dl ui');
end);
ashita.events.register('unload', 'dlac-unbind', function()
    pcall(function() AshitaCore:GetChatManager():QueueCommand(-1, '/unbind ^k'); end);
end);

if _cfok then
    _cfmt.msg('loaded -- ' .. _cfmt.hl('CTRL+K') .. ' (or ' .. _cfmt.hl('/dl ui') .. ') opens the gear / set builder.');
else
    print('[dlac] loaded. Open the gear / set builder with CTRL+K  or  /dl ui   (also /dlac ui).');
end
