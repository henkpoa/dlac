--[[
    dlac/servers/cexi/detect.lua -- how the CatsEyeXI client bundle presents
    itself (gear\serverpack.lua's detection hook, 2026-08-30).

    HAND-MAINTAINED on purpose, like features.lua: the maintainer's pack
    generator owns manifest.lua and would clobber this. Detection reads the
    Ashita boot config the launcher itself loaded -- the CEXI bundle's boot
    command names the login server (`--server server.catseyexi.com`), which
    no other install carries. This is the PACKAGER's label, not the server's
    word: a match auto-selects the pack, a miss just means the first-run
    chooser asks. Ranked below the flag file always.
]]--
return {
    -- boot = { command = '<ashita.boot command>', name = '<launcher name>' }
    match = function(boot)
        local cmd = (type(boot) == 'table') and tostring(boot.command or '') or '';
        return cmd:lower():find('catseyexi.com', 1, true) ~= nil;
    end,
};
