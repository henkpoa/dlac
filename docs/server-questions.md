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

## 4. Unidentified CatsEyeXI custom mods — OPEN

Customs live at 2000+ and aren't in LSB's `modifier.h`. Identified so far by matching
in-game text: `2000` SURVEYOR, `2006` EXCAVATION_RESULT, `2016` CONSERVE_INGREDIENT.
Still unknown:

| mod | carriers | note |
|---|---|---|
| 2004 | Ebisu Fishing Rod (=10), Ebisu F. Rod +1 (=15), Halieutica (=50), Mariners Boots/Tunica, Brigands Eyepatch | fishing; value scales, so it's a real stat |
| 2005 | Halieutica (=5), Mariners Boots/Tunica, Brigands Eyepatch | fishing; travels with 2004 |
| 2017 | Artisans Ring +1 (28566, =3) | its text is fully explained by SYNTH_SUCCESS_RATE + the ANTI_HQ set, so 2017 has no visible effect |

**Question:** what are these three? A name each is enough — dlac derives the rest.

**What dlac does meanwhile:** leaves them in `tools/api_cache/ignored_mods.txt`, so they
are dropped from the catalog rather than guessed at.

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

**What dlac does meanwhile:** the optimizer never proposes the pair — Range and Ammo are
picked jointly, and ammo with no corresponding ranged weapon forces Range empty
(`gear/gearoptim.lua`, tests H9–H14). This is a workaround, not a fix: a hand-built set
can still hit it.
