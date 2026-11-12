# AXI-63: Stable management on any job

The AscensionXI Stable permits jug registration, active/saved roster edits and
nicknames on all jobs. Summoning and Seal Beast remain main-job BST actions in
the server. Proximity, ownership and receipt checks remain server-authoritative.

`init.lua` permits management requests off BST and sends separate `readOnly`
(zoning) and `combatEnabled` (BST) state to `view.lua`. Combat gauges and F6
clock requests stay BST-only. Zoning still blocks management requests.

The matching AscensionXI branch is `codex/axi-63-stable-all-jobs`. Its native
service and Lua wire changes are required for the server to accept the writes.
Deploy the server first, then this repository through the normal DLAC updater.
An old server safely rejects new off-job requests. No installed addon directory
was edited, and no catalog/DAT/protocol version changes are required.

Tests: `tests/stable_protocol.lua` exercises actual off-job assign, saved-roster
edit, rename, register and preset callbacks with paged responses. Existing
Stable gauge, drawing and integration tests remain applicable. AscensionXI's
`tools/bst_playtest/check_protocol.py --dlac <this checkout>` also executes the
real UI and server wire code together, including an off-job roster assignment.
The old client fails that assertion. The server handoff and native verification
are in `documentation/custom/stable-any-job.md` in AscensionXI.

Player acceptance: change to WAR after capturing a beast as BST, register its
jug at a Stable Master, edit and switch rosters and rename the companion through
DLAC. The Ready gauge must remain hidden. Return to BST and call the companion
in the field. Rollback this commit to restore the client-side restriction.
