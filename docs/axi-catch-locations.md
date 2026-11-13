# AXI Stable catch-location notes

Only servers/ascensionxi/modules/stable/view.lua changes at runtime. The server
now removes impossible capped populations, splits Pso’Xja by tower and sends
optional seventh-field entrance/capture notes. The AXI view accepts both the
legacy six-column rows and the extended rows, showing notes beside the beast.
Malformed trailing fields are rejected. CatsEyeXI and shared addon behavior
remain unchanged. Implemented in the source repository, not installed addons.

Release updated DLAC with/before the matching AscensionXI catalog PR. Older
servers remain compatible. The normal launcher build distributes this change.

Checks: tests/stable_habitats.lua, ascensionxi_stable.lua, stable_protocol.lua,
stable_gauge.lua, stable_draw.lua and server_pack_isolation.lua pass under Lua
5.4. The new parser test is included in CI. Core run_tests (8,092 checks) and smoke_ui (1,778 checks) also pass.
Game-client visual review is not claimed. To review, open AXI Stable → Diremite → Find in the wild; F-7 appears
beside the level-43–45 Diremites, while Phomiuna is absent. Pair rollback with
the server catalog change if needed.
