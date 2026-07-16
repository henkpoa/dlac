# 0009 — Trigger Groups: a named action-list matcher, generalizing modes

Blue Mage (and any spell-heavy job) wants the same gear for many spells that share a stat
scaling, but scaling is **not** a matchable dimension — spell data carries no STR/DEX/MND/INT
field, and `contains` only matches name substrings — so today it takes one Midcast trigger per
spell. We add a **Group**: a named, untyped list of action names stored per Job entry in a
`Groups` section of the trigger file (beside `Modes`), matched by a new `when = { group }`
condition that fires when the current action's name is in the list. It is deliberately built as
a *generalization of the existing `mode` matcher* — the only condition that already treats a
list value as OR — not as a new subsystem; the mode storage, serializer, and builder popup are
the blueprint.

## Decisions

- **Specificity tier 45** — just below exact `name` (50) and above `contains` (40). A broad
  group rule is therefore overridden by a per-spell `name` rule (group = baseline, name =
  exception) and still beats substring / skill rules.
- **Untyped list of names, stored per job.** A Group holds bare action names (spells and/or
  abilities); the Handler context scopes where it can match, so no per-type machinery. It lives
  with the job's triggers, not the profile — a BLU group is a BLU thing.
- **`when.group` may itself be a list (OR)**, exactly as `mode` already allows.
- **Membership is built from a searchable spell/ability browse-list** (the job's learnable
  actions, ungated) plus free-name entry — the same browse capability open issue #12 needs for
  ordinary triggers, so it is built once and shared.

## Considered and rejected

- **Make `name` accept a list inline** — no new entity, but the list is neither named nor
  reusable: you retype it per trigger and re-edit every trigger when the spell pool changes.
- **A `scaling` matcher** — would need a curated STR/DEX/MND field on every spell; the server
  data has none, and a player-authored group is more honest and also expresses heterogeneous
  groupings the data could never encode.
