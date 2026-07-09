# ffxi-lac tools

Self-service Python scripts that keep your gear data correct from the **CatsEyeXI
live API** (`catseyexi.com/api/item/<id>`). Run them yourself — no agent, no tokens.

**Requirements:** Python 3 (standard library only). `pip install luaparser` is
optional and adds a stronger gear.lua validation pass to apiscan.

Why the API: the public server SQL is *retail-base* and wrong for CatsEyeXI's
custom-rebalanced items. The live API returns the real values (custom jobs,
custom stats), keyed by item id. These scripts read the SQL only for the *list*
of equipment ids, then sync each with the API for the real data.

---

## `apiscan.py` — fix YOUR gear (`gear.lua`)

For every item already in gear.lua, pulls correct **jobs / level / base stats**
and reconciles them: sets/corrects the stats it manages, removes retail
pollution, and **preserves** anything it doesn't manage (special effects like
`Automaton={Refresh}`, `IronSkin`, skills, resistances, your comments). Stats are
the **augment-free base** — your personal augments stay out of the shared file.

    python apiscan.py            # DRY RUN: show what would change
    python apiscan.py --apply    # back up gear.lua, then write the changes

Typical use when you get a new item:
1. In game: `/fl scan` -> `/fl stage` -> `/fl commit`  (adds it with its Id)
2. `python apiscan.py --apply`
3. In game: `/fl r`

Backups go to `../backups/` (newest 20 kept).

---

## `apicrawl.py` — build the FULL catalog (`catalog.lua`)

Syncs **every equipment id** (`equipment_ids.txt`, taken from the server's
`item_equipment` table — 14,874 items) with the API and rebuilds `catalog.lua`,
which powers the GUI's **All Equipment** tab. **Resumable** and **rate-limited**,
so you populate slowly but surely.

    python apicrawl.py                 # sync all equipment ids (skips cached), then rebuild
    python apicrawl.py --max 500       # fetch at most 500 new ids this run
    python apicrawl.py --from 27000 --to 29500
    python apicrawl.py --build-only    # just rebuild catalog.lua from the cache (no fetching)

The API allows ~30 requests/window, so new fetches run ~1/sec — a full first
sync of all ~14.8k items is a few hours. **Ctrl+C anytime**; progress is cached
in `tools/api_cache/` (gitignored) and resumes on the next run. When you're done,
`/fl r` in game to load the bigger catalog.

---

## Files
- `equipment_ids.txt` — all equipment item ids (from the server SQL).
- `modifier_map.lua` — modid -> stat-name map (used to read the API mods).
- `api_cache/` — per-item API JSON; your local cache & crawl progress (gitignored).
