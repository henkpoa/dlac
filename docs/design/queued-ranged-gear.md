# Gear for a queued ranged attack

**AscensionXI only:** `serverpack.active() == 'ascensionxi'` gates request
retention, ranged-start handling and the added zone cleanup. CEXI, unknown
and absent packs keep the original engine behavior. The focused test covers
each inactive case and switching away with an AXI request pending.

AscensionXI can hold one engaged Ranger `/ra` until existing melee/shot
recovery ends. The request equips Preshot, sends the command, then equips
Midshot as before. The server snapshots Preshot delay reductions. A long
queue can outlast DLAC's fallback and let Default resume before aim begins.

`feature/equipengine.lua` retains the latest ranged request context separately
from that fallback. The player's native category-12 start restores its Midshot
dispatch and refreshes its fallback. It sends no new action and does not repeat
Preshot. The cached context is consumed once, replaced by the next outgoing
action, and discarded on completion, interruption, item use or zoning.
A native ranged start also marks the current shot in flight. If another
request arrives before its finish, that finish preserves the successor's
context and active Midshot hold. The next native start consumes it once.
Interruption clears both. Other actors' packets cannot restore it. No custom packet or new setting.

Run `lua tests/queued_ranged.lua` from the addon root (LuaJIT supported).
It exercises serialized outgoing/incoming packets, expiry, restoration,
duplicate starts, actor isolation and cancellation. Also run
`lua tests/ascensionxi_rnggauge.lua` for the unchanged gauge protocol.

Local implementation, pending client playtest and release. Version
2026.11.26d; distribute from this source commit through AscensionXI's addon
catalog. Never patch an installed copy as source. Rollback is the previous
catalog pin. Test a queued shot after melee with both crossbows, and a long
wait with Preshot/Midshot sets configured; Midshot must be active at release.
