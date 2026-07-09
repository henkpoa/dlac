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
addon.author  = 'henkpoa';
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
                package.loaded['dlac\\gear'] = g;
                print('[dlac] loaded your gear from ' .. sub);
                break;
            end
        end
    end
end);

-- Load the library. Each module registers its own /dl command(s); gearui also registers
-- the GUI render hook. Guarded so one module failing can't take the addon down.
for _, mod in ipairs({ 'gear', 'augments', 'gearoptim', 'gearimport', 'gearui' }) do
    local ok, err = pcall(require, 'dlac\\' .. mod);
    if not ok then print(string.format('[dlac] failed to load %s: %s', mod, tostring(err))); end
end

print('[dlac] loaded. Open the gear / set builder with  /dl ui   (also /dlac ui).');
