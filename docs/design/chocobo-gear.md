# Chocobo Riding-Gear System — design

Status: **IMPLEMENTED 2026-07-23** (issue #95, PRD #93). The **fourth sibling** of the
craft-gear (docs/design/craft-automation.md), HELM (docs/design/helm-gear.md) and fishing
(docs/design/fishing-gear.md) systems — and the SIMPLEST of the four.

Same philosophy: **don't fight the engine, BE the engine** — a per-char state file read by
dispatch every tick, engine wears the result as a Claim, idle-only. This slice is the whole
**gear half** of the Chocobo automation: turning it on equips your best **riding-time gear**
and the panel reports the total riding time. The dig guide (bait/route/fatigue) is out of
scope here — a later slice.

---

## 0. Scope

Chocobo riding-time gear extends how long a whistled chocobo lasts. The server computes the
ride duration as `1800 + mod*60` seconds **at whistle time** (base 30 minutes; every point of
`ChocoboRidingTime` adds one minute), so the gear only has to be worn when you whistle — it is
purely an **idle** dressing, never an action-event swap. That is the whole feature:

- wear the best owned riding-time piece per slot while idle;
- tell the player the resulting total riding time and which pieces make it up.

No target, no category, no packet protocol, no proximity — unlike the other three siblings this
one has a single fixed "best riding-time set".

**Reference set on CatsEye (best per slot):** Chocobo Wand +30 (Main), Orange Race Silks +10
(Body), Chocobo Torque +4 (Neck), Chocobo/Riders Hose +4 (Legs), Chocobo/Riders Gloves +3
(Hands), Chocobo/Riders Boots +3 (Feet) — total `30 + 54 = 84` minutes. **The Chocobo Wand is
included even though it occupies Main** (a riding-time weapon; the panel note reminds the player
to equip the set before whistling since the Wand takes their weapon slot).

## 1. The slots

`Main / Neck / Body / Hands / Legs / Feet` (issue #95). Ring/Waist/Head/Back/Ear are never
dressed — the reference riding set has no pieces there, and an idle swap in an unrelated slot
would just churn gear. Main is included on the craft/fishing precedent (their overlays already
carry Main): the ladder only ever holds riding gear, so a character without a riding weapon
never sees a Main swap.

## 2. Data — the catalog carries the stat

`ChocoboRidingTime` is already a shipped catalog stat (statdefs `Misc`, label "Chocobo Time",
minutes). No new data table, no generator: the manifest ladders are **stat-driven from the
catalog** exactly like the craft/HELM/fish ladders, so future riding gear lands automatically
on the next rescan.

## 3. Modules

| File | Role |
|---|---|
| `feature/chocowatch.lua` | state owner: writes `<char>\dlac\chocostate.lua` `{ enabled, at }`; session-only `enabled` (off at login — the craftstate rule); `/dl choco [on\|off]` |
| `ui/chocoui.lua` | the panel (§4) + the pure coverage/total-riding-time helpers (above the imgui guard, the fishui/ammoui contract) |
| `ui/automationsui.lua` | +1 Automations row (`choco`), detail delegation, autoCommit `choco` manifest block (AUTO_FMT 14 → **15**) |
| `dispatch.lua` v120 | `ensureChocoState` / `chocoStateActive` / `chocoOverlayFor` / `CHOCO_OVERLAY_SLOTS`, the `dlac:AutoChoco` resolveVirtual branch (manifest `a.choco`), a `'Chocobo'` Arbiter claim + applyClaim closure, and the floor-last `arbOrder` invariant |
| `feature/arbwatch.lua` | `Chocobo` added to the default rank (below Fishing, above the Triggers floor) |
| `ui/priorityui.lua` | `Chocobo` HINT/SOURCE/status in the Priority section |

## 4. UI — the Chocobo panel (Automations → "Chocobo")

New Automations row: `key='choco'`, name **Chocobo**, kind `riding-gear helper (idle only)`,
coverage 0..3 from `chocoui.status(deps)` (1 = a piece or two, 2 = 3..5 of the six slots,
3 = the full six-slot set), opening a detail panel.

Panel, top to bottom:

1. The on/off switch (**Set Chocobo Idle**, the craftbar pill) — session-only OFF at login.
2. **Total riding time** = `30 + summed ChocoboRidingTime` minutes, with the server-formula note
   (`1800 + mod*60` seconds at whistle time).
3. **Equipped pieces** — best owned piece per slot (icon + name + the `+ride` tag) for the six
   slots, and an `N of 6 slots covered` line.
4. The Wand/whistle note, verbatim intent: *"includes the Chocobo Wand — takes your weapon slot;
   equip the set before you whistle."*

## 5. Engine overlay + arbitration (dispatch v120)

`ensureChocoState` (1 s cached read) + `chocoStateActive` (enabled only — no auto/hold mode) +
`chocoOverlayFor`, gated `event == 'Default'` AND standing aside on Engaged/Dead (the HELM/Fishing
idle law verbatim). `CHOCO_OVERLAY_SLOTS = { Main, Neck, Body, Hands, Legs, Feet }`; every slot
resolves `dlac:AutoChoco` through the manifest `choco` ladders, best-first and level-gated at
resolve time.

**Arbitration:** Chocobo registers a **Claim** (`claims['Chocobo'] = chEquip`) with a rank row in
`ARB_ORDER_DEFAULT`, default position **below Fishing, above the Triggers floor** — it co-claims
with craft/HELM/fishing and the Arbiter's per-slot rank settles any overlap (ADR 0012). Adding the
row surfaced a latent invariant bug: `arbOrder` appended a newly-added known row (Chocobo) *after*
an existing arbstate file's `Triggers` entry, sinking the new claimant below the floor where it
could never win a slot the idle set already dresses. Fixed by pinning the **Triggers floor last**
unconditionally in `arbOrder` (and the arbwatch fallback) — a floor invariant that is correct
regardless and lets any future claimant be added cleanly.

**Manifest:** AUTO_FMT 14 → **15**; `choco` block built in automationsui's autoCommit walk —
candidates = owned gear with `Stats.ChocoboRidingTime > 0` whose slot is one of the six; score =
`ChocoboRidingTime`; sort score desc, name asc, `CHLADDER=4` rungs, level-gated at resolve time.
The manifest format bump self-heals on render (an outdated on-disk manifest rescans itself);
`dispatch.M.VERSION` 119 → 120 fires the "Reload LAC" staleness banner (seeded-file behavior
changed).

## 6. Field tests (none need a probe)

1. Row appears in the Automations list, coverage reflects owned riding gear, opens the panel.
2. Toggle on → best owned riding pieces equip across Main/Neck/Body/Hands/Legs/Feet while idle;
   toggle off → normal idle gear returns. `/dl why` names the `Chocobo` claimant per slot.
3. The panel's total riding time = `30 + summed ChocoboRidingTime`; the equipped-pieces list
   matches what the engine dressed.
4. Relog → the switch is OFF (session-only).
5. Co-claim sanity: arming Chocobo alongside craft/HELM/fishing leaves the peers armed; the
   Priority list settles overlapping slots by rank.

## 7. Open / deferred

- **The dig guide** (bait, dig-rare gear, fatigue) is the other half of the parent PRD (#93) —
  not in this slice. `DigRareAbility` / `DigBypassFatigue` already exist as catalog stats for it.
- **Player-facing names** (the row label "Chocobo", "Total riding time", the note) are the
  issue's own wording; they still want the maintainer's row-by-row sign-off before they are final.
