# Trigger logic is data, evaluated by the seeded library — never code generated into job files

dlac and LuaAshitacast run in separate Lua states; only code required *by the profile* (the seeded `dlac\utils` library) can call `gFunc.EquipSet`. To connect sets to game events, each `<JOB>.lua` handler gets a one-time, one-line shim — `utils.dispatch('Midcast')` etc., appended at the end — and all trigger behavior lives in a per-job **data file** (`<char>\dlac\triggers\<JOB>.lua`, a `return {...}` module like gearweights.lua) that the GUI writes and the dispatch engine reads.

We rejected generating `if/elseif` handler bodies into the job file: splicing logic (vs. setmanager's data blocks) is fragile against hand edits, every change would need a LAC reload, and modes/priorities need runtime state that generated branches can't hold — it converges on an engine duplicated into every job file anyway.

Consequences:
- Job files are touched once (Setup/migration) and stay logic-free; the truth about triggers is the data file + GUI. A debug view (`/dl why`: what matched, what equipped) is the readability escape hatch.
- Trigger edits hot-reload (the engine re-reads the data file on change) — no `/lac reload` loop.
- `dispatch` runs *last* in each handler, and LAC's `EquipSet` merges per-slot with later calls winning, so dlac triggers override hand-written handler code for any slot they touch. Deliberate: migrated profiles keep working, dlac wins where configured.
