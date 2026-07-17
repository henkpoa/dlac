# HELM Gear Automation — design

Status: **DESIGNED 2026-07-17** — implementation in progress. Fishing explicitly OUT OF SCOPE
(Henrik wants a separate automation for it; it works too differently).

The craft-gear system (docs/design/craft-automation.md) is the template. Same philosophy:
**don't fight the engine, BE the engine** — a small per-char state file, read by dispatch
every tick, engine wears the result as the last writer. HELM clones that spine with one
deliberate difference: the overlay is **idle-only by requirement** (it happens to match the
craft overlay's existing `event == 'Default'` gate exactly, so no new engine concept).

---

## 1. The progression this UI models

CatsEyeXI HELM gearing (wiki + server-source verified 2026-07-17):

1. **Field gear** (retail, cheap): Body/Hands/Legs/Feet + Field Torque + Field Rope.
   Each piece carries a hidden **+73 result mod** = +7.3 on the break roll
   (`scripts/globals/hobbies/helm/logic.lua:39-53`: `roll = rand(1,100) + mod/10`,
   break if `roll <= 33`). **Five pieces → min roll 37.5 > 33 → breakage impossible.**
   This is the real math behind "+5 removes tool breakage". Excavation stays breakable
   (its result mod 2006 is a private-module addition wired differently — As Square Enix
   Intended). Torque+Rope exist so you can hit 5 without all four armor pieces.
2. **Venture points** (per-category currency: Harvesting/Excavation/Logging/Mining pools
   are SEPARATE) buy the **Plain** pieces (3000 VP, Surveyor+1 = fewer "nothing" results)
   and the four **hats** (5000 VP, Surveyor+1 + scripted chance of double yield in that
   hat's category only; no public % — "~10%" is folklore).
3. **Plain +1** (Surveyor+2): NOT bought with VP — trade Union Commendations + the retail
   Worker piece to Alternix (Tunica x25+14375, Gloves x15+14818, Hose x20+14298,
   Boots x15+14177). Hats have no +1.

### Item matrix (ids verified in data/catalog.lua AND server sql — they agree)

| Row | Field | Plain (VP 3000) | Plain +1 | Hat (VP 5000) |
|---|---|---|---|---|
| Body | Field Tunica 14374 | Plain Tunica 26533 (Excav. VP) | 26534 | — |
| Hands | Field Gloves 14817 | Plain Gloves 25984 (Harv. VP) | 25985 | — |
| Legs | Field Hose 14297 | Plain Hose 25897 (Mining VP) | 25898 | — |
| Feet | Field Boots 14176 | Plain Boots 25964 (Logging VP) | 25965 | — |
| Neck | Field Torque 10926 | — | — | — |
| Waist | Field Rope 11769 | — | — | — |
| Head | — | — | — | Harv. Sun Hat 25557 / Excavators Shades 25558 / Lumberjacks Beret 25559 / Miners Helmet 25560 |

Hat ↔ category is a **hardcoded semantic map** (contiguous id block 25557-25560, one per
category, catalog stats can't express "which category"). Everything else is **stat-driven**
from the catalog: `Stats.HELM` (break-roll pieces) and `Stats.Surveyor` — the exact analog
of `Stats['<Craft>Skill']`. Ladders are built by catalog walk so future gear (Worker set,
Miners Pendant 13122, HELM waist oddities) lands automatically.

Catalog stat caveat (docs/server-questions.md §1): live DB stores Surveyor 2/4 where item
text says 1/2 — ladder ORDERING is unaffected (monotone), so we sort by catalog values.

## 2. UI — the HELM panel (Automations → "Auto HELM Set")

Four columns, rows height-aligned across columns (Henrik's spec, verbatim intent):

```
FIELD GEAR        PLAIN            PLAIN +1          HATS
Field Tunica      Plain Tunica     Plain Tunica +1   Harv. Sun Hat
Field Gloves      Plain Gloves     Plain Gloves +1   Excavators Shades
Field Hose        Plain Hose       Plain Hose +1     Lumberjacks Beret
Field Boots       Plain Boots      Plain Boots +1    Miners Helmet
Field Torque
Field Rope
```

- **Green = owned OR a strictly-better corresponding piece is owned** ("you're awesome"
  cascade): Plain+1 owned → Plain and Field of that slot are green too. Field
  Torque/Rope have no better variant (green only if owned). Hats ordered as the goblin
  NPC lists them: Harvesting, Excavation, Logging, Mining.
- **Dim = not owned** (and nothing better owned). Red = owned-but-stored follows the
  craft panel's color language where applicable.
- **Holy-light backlight** on top-tier owned pieces: Plain +1 column and the hats get a
  soft warm glow behind the row when OWNED (draw-list `AddRectFilled` halo, gold-white
  low-alpha, behind the text). Dopamine is a design requirement.
- Ownership via `ownedcache` counts (same green/red/dim semantics as craft panel,
  triggersui.lua:1235-1264 pattern).

Below the matrix: **category tab row** using `assets/helm/<Category>.png` (40×40, from
Henrik's SVGs — DONE), order Harvesting/Excavation/Logging/Mining. Per selected tab:
- **Venture points** for that category (see §4).
- **Today's ventures** for that category (see §5).

## 3. HELM bar + engine overlay (idle-only pin)

**Two switches (Henrik's split, 2026-07-17, engine v60):**
- **Set HELM Idle** — the manual pin: gear stays on while idle until turned off.
  Session-only, ALWAYS starts OFF at login (the craftstate rule).
- **Auto HELM** — detection-armed: a swing's 0x034 Point result auto-selects the
  category AND opens a temporary hold (`AUTO_HOLD_S` = 4s — Henrik's ruling, was
  60 → 20 → 4; re-armed by every swing); the engine wears the gear only while the
  hold runs, so normal idle gear returns ~4s after each result with no file write
  (expiry checked live per dispatch). At 4s, re-trading briskly is what keeps the
  chain dressed — a slower pace rolls undressed swings between holds.
  **Timing truth (first-synth law):** the server rolls a swing when it processes the
  trade — the 0x034 result is the first client signal, so a result-driven hold can
  never dress its own swing; every FOLLOWING swing is (equip lands ~0.5s after the
  result, the next trade is seconds later).
- **Proximity anchor (Henrik's first-swing fix):** TARGETING a "* Point" within
  `PROX_ENTER` = 6y equips the gear BEFORE the first trade. The anchor then outlives
  the target (HELMing clears it — the game's quirk): while the SAME entity is
  rendered and within `PROX_LEAVE` = 8y (hysteresis), a ~4/s memory tick keeps the
  hold refreshed (sparse state writes, ~1 per 2s); walk away or let the point
  relocate and the 4s tail drops the gear. A swing's 0x034 also (re)seats the anchor
  from its ActIndex, so the anchor self-heals mid-session without re-targeting.
  "Rendered" = RenderFlags0 bit 0x200 (the storage-move `nomadNearestSq` precedent,
  field-proven look-alike resistance) — a relocated Point lingering in the entity
  array with a stale distance drops its render bit. Memory reads only; no packets.
  **PERSISTED across sessions** until turned off — restoring it is harmless because it
  only dresses you while you actually gather. Holds never survive a login.
  Engine truth: `helmStateActive` = `enabled` OR (`auto` AND `autoUntil` in the future);
  detection bumps `at`, so a stale craft switch loses arbitration while you gather.

- `ui/helmbar.lua` — clone of craftbar: 4 category glyphs + on/off pill. Selecting a
  category + ON writes `<char>\dlac\helmstate.lua` `{ gather = 'Mining', enabled = bool }`.
  `enabled` deliberately NOT restored across sessions (same rule as craftstate — no gear
  glued on at login).
- Engine (dispatch v59): `ensureHelmState` + `helmOverlayFor`, gated to `event ==
  'Default'` like craft — **but v61 field truth: "Default" is NOT "idle"** (HandleDefault
  runs every frame, combat included), so the overlay ALSO stands aside while
  `ctx.player.Status` is Engaged or Dead — aggro means FIGHT (Henrik: you HELM in
  dangerous places). 'Event' stays dressed (the swing animation is an event — dropping
  there would churn per swing). Applied after the craft overlay, below pins.
  NOTE: the CRAFT overlay does NOT carry this status gate (crafting happens in safe
  zones; unchanged behavior) — revisit only if Henrik asks.
- **Mutual exclusivity**: enabling the HELM bar disables the craft bar and vice versa
  (written at the state files, not the engine — engine stays stateless).
- **Overlay slots: armor + accessories only** (Head/Body/Hands/Legs/Feet/Neck/Waist).
  Never Main/Sub/Ranged/Ammo — HELM tools are inventory items (Sickle 1020, Hatchet 1021,
  Pickaxe 605), and weapon swaps would burn TP for zero gain.
- Ladder resolution per slot (manifest `helm` block, AUTO_FMT 6→7): candidates from
  catalog walk, sorted Surveyor desc → HELM desc → level asc; first owned+wearable wins.
  Head slot resolves through the **active category's hat** (hardcoded map), else nothing.

## 4. Venture points — packet strategy

Server keeps per-category VP in private-module charVars; **no retail packet carries them**.
BUT: trove's custom `0x1A4` request/response protocol (trove/utils/packet.lua) is
server-authoritative and already streams a Points list — Dynamis Venture Points arrive as
group `Ventures`, label `Dynamis` (POINTS_ENTRY offsets: group@0x08 len19, label@0x1C
len23, value@0x34 i32le; request = 64-byte packet, action byte 8 @0x04).

**CONFIRMED live 2026-07-17 (Mindie's capture): the four HELM pools ARE in the stream** —
group `Ventures`, labels exactly `Harvesting` / `Excavation` / `Logging` / `Mining`
(alongside `Fishing`, `EXP`, `Battle`, `Dynamis`; other groups: CatsEyeXI, Crystal
Warrior, Dailies, Summit). pointsFor does the Ventures-group exact match first,
tolerant fallbacks kept for drift. Plan (as built):
- helmwatch sends `GET_POINTS` (debounced, on panel entry + login, like the 0x10F GP
  request) and parses ALL `POINTS_ENTRY` responses into `<char>\dlac\venturepoints.lua`.
- Debug command dumps every (group, label, value) seen → Henrik runs it once, we pin the
  exact labels.
- **Fallback** if absent from the stream: parse Alternix/Populox customMenu text —
  CatsEyeXI custom menus arrive as incoming `0x017` CHAT_STD, type 12 (MESSAGE_GMPROMPT),
  speaker `_CUSTOM_MENU`, payload `"Title""Opt1""Opt2"…` — and/or the `!ventures` reply.

## 5. Today's ventures — `!ventures helm`

- Rotate at JST midnight, one objective per tier (Low/Mid/High) per category, auto-repeat,
  progress carries over days, partial credit with a threshold. Reward 35-50 VP + EXP.
- The `!ventures` reply arrives as incoming `0x017` CHAT_STD. **Format PINNED by field
  capture 2026-07-17** (banner type 29, category lines type 13, sender = the player):
  ```
  === Today's Goblin Ventures ===
  Mining: (Low) Ordelles Caves, (Mid) Garlaige Citadel [S], (High) Grauberg [S]
  ```
  `parseVentureLine` parses category + three lazy tier captures (progress markup on
  active objectives rides along verbatim; a drifted format keeps the raw tail). The raw
  capture file stays as the debug channel. Panel button types `!ventures helm`
  (user-visible, not sneaky) and opens the 6s capture window.
- Parsed per-category objectives persist to `<char>\dlac\helmventures.lua` with the JST
  day-stamp; stale (past JST midnight) shows as "run !ventures helm to refresh".
- NOTE: packet `0x1A3` (the `ventures` addon) is the daily venture **NM hunt** rotation —
  a different system; not HELM. Don't confuse them.

## 6. Category auto-detection — FIELD-PINNED via the result event (2026-07-17)

The original guess (outgoing trade `0x036`, index @0x08) **never fired in the field**
(Ghelsba logging session, no Detected line) and was replaced wholesale. The real path,
pinned by one `/probe trade`-era capture (Ghelsba, Arrowwood Log swing):

**Incoming `0x034` EVENTNUM is the HELM result and carries everything:**
```
34 1A 8D 06 | 3F C1 08 01 | B0 02 00 00 ... | 3F 01 | 8C 00 | 64 00 | 08 00
  header      NPC UniqueNo  num[0]=688(item)   idx=319  zone=140  csid    para
```
- `num[0]` u32 @0x08 = item found (688 = Arrowwood Log; 0 = nothing; num[1] = broke)
- **ActIndex u16 @0x28 = the gathering Point NPC** (zone id @0x2A right beside it
  confirmed the alignment) → entity name → `Harvesting/Excavation/Logging/Mining Point`
  → category. No per-zone csid table; the NPC name does the semantics.

helmwatch.onEventNum handles it; with the switch ON the hat auto-follows from the next
swing. num[0]/num[1] are decoded but unused for now — a session yield tracker is a
natural later feature (items found, breaks, doubles per session).

## 7. dlacprobe shopping list (Henrik field session)

All diagnostics in dlacprobe, never dlac (hard rule). Status 2026-07-17: **ALL CLOSED.**
1. ~~`!ventures helm` capture~~ **DONE** — format pinned (§5), structured parser live.
2. ~~Alternix menu capture~~ **DROPPED** — unnecessary, VP confirmed in the 0x1A4 stream.
3. ~~Swing detection~~ **DONE** — 0x036 guess dead; the 0x034 result event is the real
   path (§6), pinned from the Ghelsba capture, real bytes in the H-tests. dlacprobe
   gained `/probe trade` (all-packet window + entity-index annotator) en route.
4. ~~0x1A4 points dump~~ **DONE** — group `Ventures`, exact category labels (§4).

## 8. File map (implementation)

| File | Role |
|---|---|
| `feature/helmwatch.lua` | state owner: helmstate/venturepoints/helmventures files, 0x1A4 send+parse, 0x017 capture+parse, trade watch, category auto-switch |
| `ui/helmbar.lua` | floating bar: 4 glyphs + on/off (craftbar clone) |
| `ui/helmui.lua` | panel: ownership matrix + category tabs + VP + today's ventures; `init(deps)` DI like trigui |
| `ui/triggersui.lua` | +1 row in Automations list (`key='helm'`), detail delegates to helmui |
| `dispatch.lua` | v59: ensureHelmState, helmOverlayFor (Default-only), HELM_OVERLAY_SLOTS, resolveVirtual `dlac:AutoHelm` |
| `assets/helm/*.png` | DONE — Harvesting/Excavation/Logging/Mining 40×40 |
| manifest `helm` block | AUTO_FMT 7, per-slot ladders + per-category head ladder |

Open questions carried in docs/server-questions.md style: Surveyor 1/2-vs-2/4 catalog
discrepancy (ordering-safe); hat double-yield % unknown (display "chance", no number).
