# 0008 — Imported static priority keeps dlac's level-scaling, not LAC's first-in-list

LuaAshitacast's `_Priority` sets pick the *first* candidate in list order the player can
wear (`func.lua` `EvaluateItem`/`EvaluateLevels` — a pure level gate, no other dimension);
dlac's Dynamic Sets pick the *highest item-Level* eligible candidate, with list order
breaking only exact-Level ties. When "Copy from static" imports such a set we carry the
candidate lists **verbatim** and keep dlac's highest-Level semantics rather than
reproducing LAC's first-in-list — because the two agree for every level-descending list
(the normal idiom) and dlac's rule preserves auto-scaling to newly-acquired gear, which is
the addon's core value. The one case they diverge — a deliberately *lower*-level piece
ranked above a higher one — is surfaced with a per-slot warning on import, never changed
silently.

## Considered options

- **Bit-exact reproduction via computed min/max level bands** — deterministic, but freezes
  the set to those bands and loses auto-scaling. Rejected.
- **A second "strict order" selection mode in the flatten engine** — purest fidelity, but
  bakes a permanent second selection semantics into the core engine (VERSION bump + tests).
  Rejected as disproportionate to the benefit.

## Consequences

- The import is nearly free — the copy path already carried ordered lists through; the work
  was the redesigned target semantics + the divergence warning. Implemented (issue #15) as a
  pure transform, `gear/setimport.lua` `importStaticSet`, that returns the working candidate
  lists plus the `notBestFirst` slots; `gearui` does the full-replace into the selected set,
  the overwrite confirmation, and the per-slot warning. Best-first = candidate item-Levels
  non-increasing; equal Levels are a tie (no warning), and a virtual entry (`dlac:*`) is
  skipped rather than read as a Level-0 candidate.
- A non-level-descending `_Priority` set behaves differently than it did under LAC; the
  per-slot import warning is the required mitigation (hard rule 12: a silent behavior change
  is the failure mode, not the divergence itself).
