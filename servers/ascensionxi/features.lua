--[[
    dlac/servers/ascensionxi/features.lua -- which dlac surfaces exist on AscensionXI
    out of the box. HAND-MAINTAINED, deliberately separate from manifest.lua
    (which gen_pack.py generates and would clobber): flip a surface on here the
    day it is field-tested on this server.

    Only an explicit false disables; anything unlisted defaults ON. A player
    can re-enable any of these for their character from Menu > Settings >
    Features -- this file is the default, never a wall.

    Initial ruling (Henrik, 2026-08-26): gear only -- Equipped, All Equipment,
    Sets and Triggers. The helpers and the CEXI-grown extras stay off until
    each is proven against AscensionXI.
]]--
return {
    tabs = {
        gearhelpers = false,
        jobhelpers  = false,
    },
    menu = {
        lockstyle = false,
        macrobook = false,
        hobbybar  = false,
        teleports = false,
        nm        = false,
        wishlist  = false,
    },
};
