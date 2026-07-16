# Domain docs

How the engineering skills consume dlac's domain documentation.

## Before exploring, read these (binding)

- **`CONTEXT.md`** (repo root) — the controlled vocabulary. Use these terms; avoid the
  listed `_Avoid_` synonyms.
- **`docs/adr/`** — decision records; read the ones touching your area (0006 "builder
  plans, engine decides" and 0007 "resolve only when ready" bite hardest).
- dlac-specific and equally binding: **`docs/HANDOFF.md`** (start-here + hard rules),
  **`docs/architecture.md`** (module map), and **`docs/history.md`** (session journal —
  read the dead-ends before proposing anything).

Single-context repo: one `CONTEXT.md` + `docs/adr/` at the root.

## Use the glossary's vocabulary

When naming a domain concept (issue title, proposal, test name), use the term as defined
in `CONTEXT.md`; don't drift to the `_Avoid_` synonyms. A concept missing from the
glossary is a signal — either invented language (reconsider) or a real gap (note it for
`/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an ADR, surface it explicitly rather than silently overriding.
