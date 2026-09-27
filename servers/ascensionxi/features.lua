--[[
    dlac/servers/ascensionxi/features.lua -- which dlac surfaces exist on AscensionXI
    out of the box. HAND-MAINTAINED, deliberately separate from manifest.lua
    (which gen_pack.py generates and would clobber): flip a surface on here the
    day it is field-tested on this server.

    For tabs/menu, only an explicit false disables; anything unlisted defaults ON. A player
    can re-enable any of these for their character from Menu > Settings >
    Features -- this file is the default, never a wall.

    September 14: Gear Helpers and Hobby Bar enabled for HELM. The helpers
    allowlist keeps other helpers hidden until enabled for AscensionXI.
]]--
return {
    tabs = {
        gearhelpers = true,
        jobhelpers  = false,
    },
    menu = {
        lockstyle = true,
        macrobook = true,
        hobbybar  = true,
        teleports = false,
        nm        = false,
        wishlist  = false,
    },
    -- Also controls the shared hobby bar. Add helpers as they are enabled.
    helpers = { helm = true },
};
