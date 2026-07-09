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
