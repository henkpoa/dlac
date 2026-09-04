--[[
    dlac/servers/ascensionxi/detect.lua -- how the AscensionXI client bundle
    presents itself (gear\serverpack.lua's detection hook, 2026-09-03).

    HAND-MAINTAINED on purpose, like features.lua and modules.lua: gen_pack.py
    owns manifest.lua and would clobber this. Detection reads the Ashita boot
    config the launcher itself loaded -- the public AscensionXI bundle's boot
    command names the login server (`--server play.ascensionffxi.com`). The
    match is on the DOMAIN, not the host, so a future host under it (a second
    login server, a staging FQDN) detects without a code change.

    What dlac can NOT see: the DAT/image channel (dl.ascensionffxi.com) lives
    in launcher.json, which the launcher reads and Ashita never does. Dev,
    staging and LAN installs boot against a raw IP or the Tailscale host and
    do not match -- they answer the first-run chooser (or carry the flag
    file), exactly as before this file existed.

    This is the PACKAGER's label, not the server's word: a match auto-selects
    the pack, a miss just means the chooser asks. Ranked below the flag file.
]]--
return {
    -- boot = { command = '<ashita.boot command>', name = '<launcher name>' }
    match = function(boot)
        local cmd = (type(boot) == 'table') and tostring(boot.command or '') or '';
        return cmd:lower():find('ascensionffxi.com', 1, true) ~= nil;
    end,
};
