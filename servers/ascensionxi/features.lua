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
    October 4: Chocobo (the Digging tab and its Gear Helpers row) enabled,
    fed by the pack's digging module.
    October 5: AutoAcc (its Gear Helpers row and readout), fed by the pack's
    telemetry module. Turn it off here if its field round finds a fault.
    October 10: the Job Helpers tab, with DNC Status as its only helper (fed
    by the pack's dncstatus module). The `jobhelpers` list names the helper
    folders this server loads; /dl jh names the ones it leaves out.
]]--
return {
    tabs = {
        gearhelpers = true,
        jobhelpers  = true,
    },
    menu = {
        lockstyle = true,
        macrobook = true,
        hobbybar  = true,
        teleports = true,
        nm        = false,
        wishlist  = false,
    },
    -- Also controls the shared hobby bar. Add helpers as they are enabled.
    helpers = { helm = true, choco = true, autoacc = true },
    jobhelpers = { ['dnc-status'] = true },
};
