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
  mode gates — via the machinery the Mode *delete* path already has
  (`modeCondRefs(data, 'X:Value', strip)`).
- **The cascade is scoped to dead values only.** A bare `mode = 'Weapon'` matches any
  value and keeps working, so it is never touched. Killing it would delete working
  rules for no reason.
- **The warning is a pre-commit list**, not a sentence: every trigger and every set
  entry that will be edited, named, before the player presses anything.
- Replacing a Mode also **clears its live flag** when the replacement drops the value
  currently active — transient runtime state, not saved data, and leaving it stranded
  makes the engine complain about a cycle value its job no longer defines on every
  dispatch (`dispatch.lua:4850`).

**Consequences.** This is the only place in dlac where importing data deletes other
data the player authored. That is deliberate — Henrik's ruling was that a replaced
cycle *must* clean up after itself rather than leave silently dead rules — but it is
also why Append is the default, why Overwrite is a separate explicit choice, and why
the pre-commit list is mandatory rather than a nicety. Toggle Modes carry no values,
so a toggle-over-toggle stamp can only ever change the keybind and never cascades.
