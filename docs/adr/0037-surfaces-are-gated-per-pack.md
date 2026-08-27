# 0037 — Surfaces are gated per server pack, and the player holds the override

Accepted 2026-08-26. Adds `lib/featuregate.lua`, `serverpack.features()`, the optional
hand-maintained `servers/<id>/features.lua`, a tab filter in `ui/uihost.renderTabs`, a row
filter in `ui/menuui`, and a **Features** section under Menu > Settings persisted in
`uiflags.lua`. Extends ADR 0035 (server packs); changes nothing about what loads or equips.

## Context

dlac grew up on CatsEyeXI with every tab and menu row always present. On a younger pack
most of those surfaces are noise or untested there — Henrik's ruling for AscensionXI
(2026-08-26): *"initially I only want the gear part to work (Equipped, All equips, sets
and triggers, nothing else)"* — and he wants a profile/settings switch to turn features
and tabs on and off as they get proven.

Three shapes were considered. Gating inside each module (every module re-answers "do I
exist here?" — the exact per-module drift ADR 0035 exists to prevent). Declaring it in
the manifest (the natural home, but manifests are GENERATED — `gen_pack.py` would clobber
the hand edit, and "this surface is now field-tested here" is a human judgement, not a
data regeneration). Or a separate hand-maintained pack file behind the serverpack seam.

## Decision

**A surface exists if the character says so; else if the pack says so; else yes.**

1. `servers/<id>/features.lua` — optional, hand-maintained, read ONLY through
   `serverpack.features()` (no other module may compose a `servers\` path — ADR 0035's
   law). Only an explicit `false` disables; absent file/section/key = ON, so `cexi`
   (which ships no file) keeps every surface it has always had.
2. `lib/featuregate.lua` owns the rosters (six tabs, six menu rows) and the layering.
   Its two laws: **an unknown label is never hidden** (uihost registering a tab the
   roster does not name must not vanish it silently), and **the way back ON is never
   gateable** (Settings, Level override and the debug rows sit outside the roster).
3. Consumers subtract, never require: `uihost.renderTabs` filters registered tabs,
   `menuui` filters its rows; a missing or broken featuregate means everything renders.
4. The character's flips live in Menu > Settings > Features and persist in `uiflags.lua`
   (`featson`/`featsoff` token lists) — a **Setting** in the CONTEXT.md sense: it changes
   what the GUI shows, never what the engine equips. Only differences from the pack
   default are stored, so a pack widening its defaults later reaches every character who
   never chose.
5. Gating hides the SURFACE only. No module is unloaded, no watcher stops, the engine
   never reads any of this.

## Consequences

* AscensionXI ships gear-only out of the box (Gear Helpers + Job Helpers tabs and all six
  extra menu rows off), and flipping one on when it is proven is a one-line pack edit —
  or one player's tick, immediately, without waiting for the pack.
* Pre-2026-08-26 `uiflags.lua` files lack the keys and read as "no flips" — every
  existing install keeps the behaviour it had.
* A jump (`host.selectTab`) aimed at a hidden tab expires with ADR 0033's give-up chat
  line. Acceptable: the doors to hidden surfaces are themselves hidden, so it takes a
  typed command to get there.
* Pinned headless: run_tests `FGT0–FGT24` (layering, round-trip, the shipped AscensionXI
  defaults, roster/label agreement) and `SPK30–SPK33` (`features()` answers post-init
  without latching — hard rule 11's shape).

## Records

`lib/featuregate.lua`, `gear/serverpack.lua` (`features()`),
`docs/reference/server-pack-contract.md` ("features.lua"), `servers/ascensionxi/features.lua`,
`docs/history.md`.
