# Floating equipment and AscensionXI catalog refresh

Release candidate `2026.09.16a` adds saved box transparency to floating equipment.
In Equipped, Floating equipment sits beside Lock gear. When enabled, the next
row shows Transparency and Size, each with a 120-pixel slider. Transparency
fades button backgrounds and slot labels, including pin/move colors, while
icons, lock crosses and hover tooltips retain their opacity. The setting defaults
to zero and is stored in the character's existing uiflags.lua.

The owner accepted the appearance in the installed client. The final equal-width
adjustment was checked in code; repeat the in-game check after reloading DLAC.

The AscensionXI pack was regenerated from server main
`c2acaf1f74` using its normal catalog-and-icons command:

```powershell
python tools/dlac-pack/gen_pack.py --out C:/repos/dlac-floating-release/servers/ascensionxi --game 'C:/AscensionXI/Game/FINAL FANTASY XI'
```

The refresh adds Emperor Hairpin +1 (26565), its stats and PNG. Totals are
15,420 catalog records and 27 icon overrides. Existing hand-maintained pack
modules remain intact. Source DATs and the game install are read-only inputs.

Merge the DLAC PR first, then finalize the paired AscensionXI launcher catalog
PR against merged DLAC main using `python tools/addon-catalog.py bump dlac`
and `python tools/addon-catalog.py verify`. Its human merge starts the staging
DAT-channel workflow. Production channel promotion is a separate human step.
No deployment has been performed. Rollback restores the previous addon pin
and matching resolved file list; character settings need no migration.

Verification: all nine CI Lua suites passed, including 7,499 core checks and
1,575 UI checks; AscensionXI pack lint passed 31 checks. The server generator
passed all 11 Python tests. New-item rendering has not been playtested.
