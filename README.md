# dlac — dynamic LuaAshitacast

A companion for **LuAshitacast** (Final Fantasy XI on Ashita v4) that helps you
**build gear sets** and **view your live stats, with level scaling**.

## What it does

- **Set builder GUI** (`/dl ui`) — browse your gear, build and edit sets, and commit
  them into your job profiles.
- **Level-scaling sets** — each slot is a list of candidates; dlac equips the best one
  for your current level, so a single set scales as you level up.
- **Live stats panel** — your worn-set totals (base **plus item augments**), with
  per-slot detail and hover tooltips.
- **Augment-aware** — reads item augments straight from the client and folds them into
  your stats, so what you see matches what you're actually wearing.

## Getting started

dlac runs *alongside* LuaAshitacast — it drives the profiles LAC already loads, so you
need a working LuaAshitacast install first (your
`config\addons\luashitacast\<Char>_<id>\` folder with your job profiles). dlac can't do
anything without it.

1. **Install** — drop the `dlac` folder into `Ashita\addons\`, then load it with
   `/addon load dlac` (add that line to your Ashita boot script to load it every time).
2. **Open the GUI** — `/dl ui`.
3. **Set up the job you're on.** If the current job isn't wired for dlac yet, a red banner
   and a red **Setup** button (top-right) say so. Click **Setup** — it handles every case:
   - an existing **ffxi-lac** profile is converted to dlac in place (your original is
     backed up as `<JOB>.lua.flbak`);
   - a job with **no profile yet** gets a fresh dlac starter profile (empty sets you fill
     in from the GUI);
   - an existing **custom** (non-ffxi-lac) profile is left untouched — copy
     [`PROFILE_TEMPLATE.lua`](PROFILE_TEMPLATE.lua) as your starting point instead.
4. **Reload LAC** — click **Reload LAC**. LAC caches your sets when it loads, so a Setup
   (or any set edit) only takes effect after a reload. That job is now driven by dlac.
5. **Import your gear** — **Scan → Stage → Commit** reads the gear you own out of the game
   into your `gear.lua`, so the builder shows exactly what you have.

Repeat steps 3–4 for each job you want on dlac. Your gear and profiles stay in your
LuaAshitacast config folder; the addon folder only holds the framework and item catalog.

## Commands

`/dl` (or `/dlac`):

| Command | Does |
|---|---|
| `/dl ui` | Open/close the gear + set builder window |
| `/dl scan` / `stage` / `commit` | Read your owned gear from the game into `gear.lua` |
| `/dl weight` / `best` | Stat-weight helpers for set building |
| `/dl recalc` / `r` | Rebuild sets / reload |

## Requirements

- Ashita v4 with **LuAshitacast**.

## Status

Work in progress.

## License

MIT — see [LICENSE](LICENSE). dlac works alongside LuaAshitacast but does not bundle it.
