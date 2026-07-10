# Picker database — spike findings & data files

Status: built 2026-07-10 (issues #10 spike + #11 generator). Data files exist and are
validated; GUI integration (#12) NOT wired yet — `abilities.lua` / `spells.lua` are
inert until the Triggers tab reads them.

## Chosen source: the CatsEyeXI server's own SQL

- The CatsEyeXI web API exposes **items only** — probed `/api/spell/*`, `/api/ability/*`,
  `/api/spells`, `/api/abilities` etc. (all 404) and the site's page routes (no
  spell/ability pages; only item search via `/api/opensearch`).
- **CatsEyeXI's server fork is public: `github.com/CatsAndBoats/catseyexi`** (branch
  `base`) — a LandSandBoat fork carrying their custom job balance. `sql/spell_list.sql`
  and `sql/abilities.sql` are therefore *authoritative*, not retail-approximate.
  Proof the distinction matters: **Pianissimo is BRD 20 here (retail: 45)**.
- Cross-check against live client data: `spell_list` says Blade Madrigal is
  Thunder-element — identical to what `gData.GetAction()` reported in-game.

## Data shapes

`spells.lua` (**536 spells**, learnable ≤ 75; trusts excluded):

```lua
{ Name = "Stone", Jobs = { BLM = 1, RDM = 4, DRK = 5, SCH = 4, GEO = 4 },
  Skill = 'Elemental Magic', MagicType = 'Black Magic', Element = 'Earth' },
```

`abilities.lua` (**469 abilities**, level ≤ 75, incl. blood pacts):

```lua
{ Name = "Pianissimo", Jobs = { BRD = 20 } },
{ Name = "Benediction", Jobs = { WHM = 1 }, MainOnly = true, SP = true },
```

- `Jobs` = acquisition level per job (CatsEyeXI values). Duplicated ids merge at the
  lowest level.
- `Skill` / `MagicType` / `Element` strings match **LuaAshitacast's vocabulary**
  (`constants.SpellSkills/SpellTypes/SpellElements`), so the GUI can prefill trigger
  conditions from a picked spell. Geomancy spells carry `Skill='Geomancy'` but no
  MagicType (LAC has none for them). `Element` is omitted when the server says none.
- Display names are client spellings (Utsusemi: Ichi, Army's Paeon, Teleport-Holla,
  Absorb-STR) via transform rules + a curated possessive map in the generator —
  extend `POSSESSIVE` there if a gap is found.

## Semantics for the GUI (#12)

- **Usable-now**: entry is usable when `Jobs[mainJob] <= mainLevel`, or
  (`not MainOnly` and `Jobs[subJob] <= subLevel`). That covers Henrik's `/SCH37 →
  Light Arts (10), Dark Arts (10), Penury (10), Sublimation (35)` example directly.
- `MainOnly` = 22 entries: the 21 SP/2hr abilities (detected by their recast
  signature: recastId 0 + recast ≥ 3600) + Call Wyvern (curated).
- GEO/RUN data exists in the files (the server SQL has it); harmless — the GUI
  filters by the player's actual jobs. 75-cap filtering: entries with *no* job
  learning them at ≤ 75 are dropped; per-job levels > 75 are dropped per job.
- Runtime caveat: trigger *matching* always uses live `gData.GetAction()` values;
  these files are picker/prefill data only. If a server-vs-client naming or element
  mismatch ever surfaces, the client wins at runtime — fix the generator map for
  display.

## Regeneration

```
cd tools
python gen_pickerdb.py            # build from cached SQL (downloads if missing)
python gen_pickerdb.py --refresh  # pull the latest CatsEyeXI SQL first
```

Stdlib-only; SQL cached in `tools/api_cache/` (gitignored). The script runs six
spot-checks (Cure WHM 1, Valor Minuet=Fire, Utsusemi: Ichi, Army's Paeon,
Pianissimo BRD, Benediction MainOnly) and exits non-zero on failure.

## Completeness

100% of the server's learnable-at-75 spell/ability rows are represented (890 spell
rows → 536 after trust/level filtering + tier merging; 605 ability rows → 469).
The only fidelity risk is display-name spelling for entries outside the transform
rules — defaults to title-case, which the browse/search UI tolerates.
