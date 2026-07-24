# Modes get a library, and replacing a cycle Mode is dlac's only cascading delete

Modes live **per job entry**, and the Triggers tab can only ever see the *current
job's* trigger file — so reusing one `DT` toggle across ten jobs meant retyping it
ten times, or copy-pasting text with a job change in the middle of every hop. That
is the same pain Blueprints solved for Triggers, so Modes get the same answer: a
**Mode library** (`<char>\dlac\modes.lua`, per character, outside Profiles,
addon-state only — the Engine never reads it), whose entries are job-independent and
are **stamped** into whichever job you happen to be on. The library file format IS
the shareable text, exactly as with Blueprints.

The decision worth recording is what stamping over an **existing** Mode does, because
a `Modes` section is a **map keyed by name**, not an array. Blueprints can
double-stamp and merely warn — two identical rules in a handler list are harmless.
Stamping a Mode whose name already exists is a genuine overwrite, and for a **cycle**
Mode that can strand every `Weapon:Caster`-style reference in the job's triggers and
in set-entry mode gates. So:

- **Append is the default and is non-destructive.** The imported values are merged
  onto the existing list (deduped, existing keybind kept). No value disappears, so no
  reference can break.
- **Overwrite is opt-in and cascades.** Values are replaced wholesale, and references
  to values that **no longer exist** are stripped from triggers and from set-entry
  mode gates — via the machinery the Mode *delete* path already has. That is **two**
  functions, not one: `modeCondRefs` (`ui/triggersui.lua:586`) covers trigger `when.mode`
  and `whenAny[].mode`; **set-entry gates are a separate store** reached only through
  `deps.modeSetRefs` (`ui/gearui.lua:2506`), with its own file and serializer. A cascade
  that reuses only the first silently leaves dead gates on gear entries — and on the Sets
  tab a dead gate renders *byte-identical* to a live-but-inactive one, so nobody would
  ever notice.
- **The cascade is scoped to dead values only.** A bare `mode = 'Weapon'` matches any
  value and keeps working, so it is never touched. Killing it would delete working
  rules for no reason.
- **The warning is a pre-commit list**, not a sentence: every trigger and every set
  entry that will be edited, named, before the player presses anything.
- Replacing a Mode also settles its **live flag** when the replacement drops the value
  currently active — transient runtime state, not saved data.

  **Correction (2026-07-24, verified against the engine after this ADR was written):**
  the original wording here claimed a stranded value "makes the engine complain … on
  every dispatch (`dispatch.lua:4850`)". That is wrong on both counts. That line lives
  inside `M.setMode`, reached from the `/dl mode` command handler (and therefore a
  keybind press) — **not from dispatch**. The real per-dispatch consequence of a
  stranded value is **silence**: `modeActive` simply returns false and the gated rules
  and gear entries stop firing with no message at all. Which makes settling it *more*
  important, not less — the failure is invisible, not noisy.

  The mechanism is also cheaper than assumed: a commit queues `/dl triggers reload`, and
  the loader's stale-cycle purge (`dispatch.lua:1046-1057`) **re-seats a cycle to
  `values[1]`** when its current value is no longer defined. So a stamp that writes the
  definition before committing gets the re-seat for free. Only a **toggle** needs the
  explicit `/dl mode <name> off`.

**Consequences.** This is the only place in dlac where importing data deletes other
data the player authored. That is deliberate — Henrik's ruling was that a replaced
cycle *must* clean up after itself rather than leave silently dead rules — but it is
also why Append is the default, why Overwrite is a separate explicit choice, and why
the pre-commit list is mandatory rather than a nicety. Toggle Modes carry no values,
so a toggle-over-toggle stamp can only ever change the keybind and never cascades.
