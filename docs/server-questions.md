# Open questions for the CatsEyeXI server team

Things dlac found in the live API / server source that look like server-side bugs or
undocumented intent. **None of these block anything** — each one already has a decision
baked into the crawler or the addon, listed under *What dlac does meanwhile*. This file
exists so the workarounds can be **deleted** once a question is answered, instead of
quietly becoming permanent.

Nothing here is urgent. Raise them whenever there's a natural opening with the team.

Status key: **OPEN** = never asked · **ASKED** = raised, awaiting reply · **CLOSED** = answered (delete the workaround, then the entry)

---

## 1. Surveyor (mod 2000) on the Plain set is double its own item text — OPEN

The Plain set stores exactly **twice** what its description claims. The HELM hats, which
carry the same mod, agree with theirs.

| Item | ids | DB (mod 2000) | Item text |
|---|---|---|---|
| Harv. Sun Hat, Excavators Shades, Lumberjacks Beret, Miners Helmet | 25557–25560 | 1 | `"Surveyor"+1` ✅ |
| Plain Hose / Boots / Gloves / Tunica | 25897, 25964, 25984, 26533 | 2 | `Surveyor+1` ❌ |
| Plain Hose / Boots / Gloves / Tunica **+1** | 25898, 25965, 25985, 26534 | 4 | `Surveyor+2` ❌ |

**Question:** is the DB doubled, or was the Plain set buffed and the DAT description never
updated? The hats being consistent points at the Plain set as the outlier.

**What dlac does meanwhile:** trusts the text and halves the Plain set back to +1/+2
(Henrik's call, 2026-07-15), via the `MOD_STRIP`/`MOD_ADD` per-item fixups in
`tools/apicrawl.py` + `tools/apiscan.py`.

**On an answer:** either way the fixup gets deleted — if the text is right, the DB gets
corrected first; if the DB is right, we drop the fixup and show 2/4.

---

## 2. The `73` on every HELM "result" mod — OPEN

Mods **513** `HARVESTING_RESULT`, **514** `LOGGING_RESULT`, **515** `MINING_RESULT` and
**2006** `EXCAVATION_RESULT` store the value **73** on *every* item that carries them (17
items: the Field/Worker/Plain sets, Brigand's Shovel). Not 70, not 75, and never anything
else — which reads more like a shared magic constant or a copy-paste than a tuned rate.

**Question:** what is 73? A percent chance, a flag the code only null-checks, or leftover?

**What dlac does meanwhile:** collapses the family to a flat `HELM = 1` marker, since an
identical value across all carriers compares nothing.

**On an answer:** if it's a real per-item rate, surface the actual value per verb instead
of one flag.

---

## 3. The four HELM hats promise a result bonus they carry no mod for — OPEN

`Harv. Sun Hat` (25557), `Excavators Shades` (25558), `Lumberjacks Beret` (25559),
`Miners Helmet` (25560) each carry **only** `DEF 1` + `Surveyor 1`. Their text promises
*"Occasionally increases harvesting/excavation/logging/mining results"* — but unlike the
Field/Worker/Plain gear, none of them has a 513/514/515/2006 mod.

**Question:** is that effect scripted server-side by item id, or was it never wired up?

**What dlac does meanwhile:** shows Surveyor but no HELM marker on them — i.e. reports the
DB, and does not invent an effect from description text.

---

## 4. Unidentified CatsEyeXI custom mods — 2004/2005 ANSWERED, 2017 OPEN

Customs live at 2000+ and aren't in LSB's `modifier.h`. Identified so far by matching
in-game / wiki text: `2000` SURVEYOR, `2006` EXCAVATION_RESULT, `2016`
CONSERVE_INGREDIENT, and — closed 2026-07-18 via
https://www.bg-wiki.com/ffxi/CatsEyeXI_Content/Ventures ("Expert Angler" on the
Mariners fishing-VP gear, values matching the live DB exactly):

- **`2004` = Fatigue Limit +%** (Mariners Tunica/Boots =10, their +1 =20 — wiki says
  +10%; Ebisu =10, Ebisu +1 =15, Halieutica =50, Brigands Eyepatch =20)
- **`2005` = Golden Arrow Rate +%** (Mariners =1, +1 =2 — wiki says +1%; Halieutica =5,
  Eyepatch =2)

Still unknown:

| mod | carriers | note |
|---|---|---|
| 2017 | Artisans Ring +1 (28566, =3) | its text is fully explained by SYNTH_SUCCESS_RATE + the ANTI_HQ set, so 2017 has no visible effect |

**Question:** what is 2017? A name is enough — dlac derives the rest.

**What dlac does meanwhile:** 2004/2005 stay out of the catalog (crawl-time mapping is
Henrik's call at the next apicrawl); the fishing panel shows them as "Expert Angler"
tooltips from fishdb's `gearBonus`, and the fish ladders use them as tiebreakers.
2017 stays in `tools/api_cache/ignored_mods.txt` — dropped, not guessed at.

---

## 5. Ranged delay adds ammo delay without checking compatibility — OPEN (likely a real bug)

`CBattleEntity::GetRangedWeaponDelay` (`src/map/entities/battleentity.cpp`):

```cpp
if (PRange && PRange->getDamage() != 0) {
    delay = PRange->getBaseDelay();
    if (PAmmo && forTPCalc) {
        delay += PAmmo->getBaseDelay();   // <-- no compatibility check
    }
}
```

`PAmmo` is *any* `CItemWeapon` in the ammo slot. It is never checked against the ranged
weapon's skill, so an unfirable stat stick still contributes its delay to ranged TP —
and every stat stick carries **delay 999** (Cinderstone, Morion Tathlum, Coiste Bodhar;
real ammo is 120–276). A bow + Cinderstone is therefore `bowDelay + 999` for TP purposes,
on a pair that cannot fire a shot.

**Question:** intended? On retail the pair simply can't fire, so the delay never applies.
A skill check against the ranged weapon (or reusing the `getDamage() != 0` guard the
sibling branch already has) would match.

**What dlac does meanwhile:** dlac never *wears* the pair, so the 999-delay can't bite through it.
Two layers: the optimizer never proposes it (Range and Ammo are picked jointly; a stat stick forces
Range empty — `gear/gearoptim.lua`, tests H9–H14), and the equip engine handles a hand-built pair —
a stat stick reserves the Range slot server-side (`item_equipment.rslot`), so
`dispatch.trinketRangeDrop` keeps the higher-Level of {trinket, ranged weapon} and drops the other,
matching the server so nothing flaps (ADR 0010; tests TR*). The underlying question — whether adding
ammo delay to ranged TP with no compatibility check is intended — is still **OPEN** for the team.

---

## 6. Oneiros Grip latent fires at 50% MP, the repo SQL says 75 — OPEN

`sql/item_latents.sql` (stable) row for Oneiros Grip:

```sql
INSERT INTO `item_latents` VALUES (18811,369,1,4,75);  -- Refresh MP <= 75%
```

Latent id 4 = `MP_UNDER_PERCENT`, param **75** — but the live server breaks at **50%**,
tick-verified on TWO shapes (Mindie, 2026-07-18): Hume WHM75/**SCH**37, `health.maxmp`
714 (614 formula + 100 merits) → Refresh ticks at **357**, gone at 358 (357/714 =
exactly 50.0%; equality firing confirms the `<=` comparison); Hume WHM75/**BLM**37,
maxmp 752 → ticks at **376**, gone at 377. The threshold MOVING with the subjob also
rules out a flat-value re-tune — it is genuinely a percent, and it is 50. 75% would
break at 535/564 respectively; nothing else fits. The denominator itself matched the
source exactly (gear, food, and the SCH Max MP Boost trait all excluded — they ride
`health.modmp`), so the divergence is isolated to the percent parameter.

**Question:** is the live `item_latents` row tuned to 50 (a balance decision the repo
seed never got), or is the seed's 75 the intent and live drifted?

**What dlac does meanwhile:** the Auto Oneiros Grip automation aims at the MEASURED
rule — `floor(maxmp × 50/100)`, boundary inclusive (`dispatch.lua` v67, the one
`* 50 / 100` line in the `dlac:autooneiros` resolver).

**On an answer:** if 75 is intent and the DB gets fixed, flip that line back to 75
(tests AO1–AO4 pin the numbers to re-aim).

---

## 7. The E-Box (Ephemeral Box) has no per-item deposit action — OPEN (feature dependency)

The trove `0x1A4` protocol — the E-Box wire protocol dlac's `eboxclient` speaks (the
authoritative source is the `trove` Ashita addon, `trove/utils/packet.lua`) — has a
per-item **withdraw** (`WITHDRAW` = 2) plus queries (`GET_SUMMARY` = 4 / `GET_CATEGORY`
= 5 / `SEARCH` = 6) for the field Ephemeral Box, but **no per-item deposit** for it. The
only `DEPOSIT` in the whole protocol is `VAULT_DEPOSIT` = 16 — the **town Mog Vault**
(city zones only; `trove/plugins/vault.lua` `TOWN_ZONES`), a different store. Depositing
to the field E-Box today is only via a **trade** to the box or the **`!box store`**
command, neither of which is a clean per-item packet an addon can drive the way Fetch
drives a withdraw.

**Question / ask:** could a C2S per-item **deposit** action be added to the E-Box
protocol, mirroring `WITHDRAW` = 2 (item id + quantity, from an inventory slot)?

**What dlac does meanwhile:** nothing — the planned E-Box Restock **"Dump" button**
(one-click deposit of job consumables back to the box after an outing, before switching
jobs) is **PARKED** until such an action exists (Henrik, 2026-07-24). No workaround
carried; delete this entry and build the button once deposit lands.
