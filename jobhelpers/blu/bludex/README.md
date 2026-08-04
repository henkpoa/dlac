# Bludex — Blue Mage codex + set planner (dlac Job helper module)

A browsable codex of every Blue Magic spell on CatsEyeXI's level-75 cap, a
visual set planner with live budget/slot meters and trait math, and set
application through the client's own machinery.

This folder is a **dlac Job helper** (`api = 2`) and, per the framework's
rules, **one unit of server approval** — everything it does is listed below
and legible from this folder alone.

The library inside (`lib/ ui/ data/ icons/`) is **vendored** from
https://github.com/henkpoa/bludex on every push to that repo's `main`
(see `VENDORED.md`). `init.lua` and this README are authored there too,
under `dlacmodule/`. Fix things in the bludex repo, never here. The same
library ships as a standalone Ashita addon for players who do not run dlac;
do not run both flavors at once.

## The whole envelope — what this module does

**Reads (client memory, this process only):**

- The BLU set-points struct and the live 20-slot set buffer, via signatures
  carried verbatim from the `blusets` addon (atom0s / Ashita Development
  Team, GPL-3, credited in `lib/blu.lua`).
- Spell-known state (`HasSpell`), job/level, and the addon's own textures.

**Sends (only ever these two, and no gear is ever equipped):**

1. **0x102 extended-equip packets** that set or unset Blue Magic spells —
   the same packet the game's own Set Spells menu sends, one spell per
   packet. Fired only by (a) the player clicking Apply, (b) the player's
   `/…apply` command, or (c) the **Restore on level change** rule, which
   **defaults OFF** and only ever re-adds spells the player's last applied
   set already contained (it never unsets anything). Default 'safe' mode
   sends through the client's own function, which self-paces to ~1/s; the
   opt-in 'fast' mode injects the identical packet with a player-set delay
   (floor 0.2s).
2. **A 0x061 player-info request** — the read-only "resend my stats" ask the
   native menus fire — to wake the BLU structs that private servers leave
   stale after login/level changes. Throttled (≤3 tries, 10s apart, plus
   once per Panel open / job change).

**Writes:** only its own framework store (`jobhelper-bludex.lua` beside the
character's other dlac files). No Profiles, no other module's state, no
engine files.

**Never:** Action sequences, gear claims, commands on the player's behalf,
second readers for things dlac already answers.

## Behavior defaults

- The **Restore on level change** rule defaults **off**; the player arms it.
  When armed: after a job/level change it re-adds spells stripped from the
  last applied set, lowest spell level first, and reports one line with how
  many stuck. Success cases are silent; refusals are one line naming the
  blocker.
- Everything else acts only on a click.

## Strings

All player-facing strings are **PROPOSED** pending the dlac maintainer's
sign-off (the naming law: rules are named for their condition — 'Restore',
never 'Auto-restore').

## License

GPL-3.0, inherited through the blusets port. `LICENSE` rides along in the
sync.
