# dlacprobe drop-ins (not part of the dlac addon)

**dlacprobe is a separate, standalone Ashita addon** that lives at
`Ashita\addons\dlacprobe\` on the maintainer's machine and is deliberately **not
tracked in this repository** (the research kit; see `docs/HANDOFF.md` and
`docs/history.md`). The product rule is standing (Henrik, 2026-07-13):
**probing / diagnostic tools never ship in dlac — they go in dlacprobe.**

This folder exists only so the code for a dlacprobe hunt can be written,
reviewed, and version-controlled alongside the dlac issue that requested it. The
files here are **drop-ins for the standalone dlacprobe addon** — dlac itself never
loads, requires, or seeds anything under `dlacprobe/`.

## `dig.lua` — `/probe dig` (issue #96)

An observation-only toggle that confirms the dig-rank mask and calibrates the
first-dig timing read in the field. It **injects nothing**: it reads the client,
hexdumps incoming `0x062` skills packets, watches the dig chat lines and the
player's own outgoing dig attempts, and writes timestamped lines to
`probe_log.txt`. See the file header for the full mechanism.

The hunt follows dlacprobe's existing idioms (command dispatch, `packet_in` /
`packet_out` / `text_in` registration, timestamped `probe_log.txt` writes) and
**self-registers** its Ashita event handlers behind an `armed` flag, so wiring it
into the host addon is two lines:

1. Load the file from dlacprobe's entry point (beside the other hunts):

   ```lua
   require('dig')   -- or your hunts loader's convention
   ```

2. Add the command to dlacprobe's `/probe` help / usage block:

   ```
   /probe dig [on|off]   confirm the dig-rank mask + calibrate the first-dig timing
   ```

`/probe dig` toggles the hunt; `/probe dig on|off` sets it explicitly; `/probe
dig help` prints usage. No other change to dlacprobe is required — the file reads
the install path via `AshitaCore:GetInstallPath()` and appends to
`addons\dlacprobe\probe_log.txt`.

### Field procedure

1. `/probe dig on` — prints and logs the `GetCraftSkill(0..15)` dump with the
   index-11 (Digging) masked/readable verdict and a `GetCombatSkill` control line.
2. Zone into a diggable area (the probe logs the `0x00A` zone-in as the timing
   baseline).
3. Spam-dig. The probe logs each `0x062` (word[59] decoded MASKED/REAL), each
   free cooldown reject, and the first completed dig — pinning the rank via
   `(60 − threshold) / 5`.
4. `/probe dig off` — read `probe_log.txt`.

### Tests

The Ashita/IO-free core (`M.pure`) is headless-tested. From the repo root:

```
lua5.4 dlacprobe/tests/dig_test.lua
```

(dlacprobe is standalone, so this is not wired into dlac's `tests/run_tests.lua`.)
