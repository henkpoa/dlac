# Trigger cases — field-test handoff (the dev→main gate)

**Status:** built, committed on `dev`, **not field-tested as a whole.** Both case
types were field-confirmed *firing* during the skeleton click-through (Henrik,
2026-07-26); this checklist is the acceptance list the completion slice owes
before `dev` promotes to `main`.
**Where:** branch `dev`. **Version:** addon `2026.07.26l` (pure addon-state UI —
**no** engine bump; `dispatch.M.VERSION` is unchanged, so no Reload-LAC dance).
**Decision record:** [ADR 0023](../adr/0023-trigger-cases-schema.md). Design:
[trigger-system.md](trigger-system.md) §"Trigger cases".
**Tests:** `run_tests.lua` and `smoke_ui.lua` green on Windows *and* WSL `lua5.4`
(the case work lives in `TE*`, `CS*`, `TC*`, `TRC*`; the completion slice added
`TE54–TE63`).

This is the whole trigger-cases PRD (#124), delivered across five slices:
schema backbone (#126), read-side display (#125), the editor skeleton (#127),
and this completion slice (#128 — copy case, "Match either instead" inside cases,
hover help, empty-case refusal, and this checklist).

Picking this back up = run §A–§F in the field, report which rows fail with the
chat line verbatim. Ordered so a failure early tells you not to bother with the
rest.

---

## The one sentence, true at both tiers

> **`&` things bind into one together-block; each `|` thing stands alone; fire if
> the together-block holds, or any `|` thing does.**

Applied to conditions inside a case, and identically to cases inside a rule. If
anything in the field reads as the two tiers behaving *differently*, that is a
bug — say so, do not rationalize it.

Vocabulary in every surface: **case**, **together-block**, **standalone
alternative** — never "group" (spell groups own that word).

---

## §A — old rules are untouched (the 99% who never open this)

| | do | expect |
|---|---|---|
| A1 | On a character with existing trigger rules, open the Triggers tab. | Every rule reads exactly as before. A rule with no added cases shows **no boxes, no dividers** — only the two new `+ & case` / `+ | case` buttons in its editor. |
| A2 | Edit a plain rule (no cases), change nothing, Save. Commit. | The `<char>\dlac\triggers\<JOB>.lua` line for that rule is **byte-identical** to before. (Diff the file, or `git diff` the char dir if it is under version control.) |
| A3 | Edit a rule that has plain standalone `|` conditions, change nothing, Save. | It re-saves as the same single-condition `|` entries — the new tier never reinterprets an old rule. |
| A4 | Hand-write a **multi-condition** `|` entry (an `AND-within-OR` group) in the file, reload, open that rule. | It loads as a **`| case` box**, not flattened to separate `|` rows, and re-saves **byte-identically**. This is the flatten-corruption fix — the editor used to silently corrupt these. |

## §B — the two shapes fire correctly

| | do | expect |
|---|---|---|
| B1 | Build `(A & B) | (C & D)`: body with A and B as `+ & condition`, then a **`+ | case`** holding C and D. Save. | `/dl why` shows the rule firing when **A & B** hold **or** when **C & D** hold — but not when only A holds. |
| B2 | Build `(A | B) & (C | D)`: body with A and B as `+ | condition`, then a **`+ & case`** holding C and D as `+ | condition`. Save. | Fires only when (A **or** B) **and** (C **or** D) hold — the `& case` **gates** the together-block. |
| B3 | A `| case` on its own (empty together-block, case 1 = OR). | Fires when the standalone case holds; it is **never** always-on when nothing holds (the OR-only law). |

## §C — `/dl why` names the matched case

| | do | expect |
|---|---|---|
| C1 | With a case-bearing rule winning a slot, run `/dl why`. | The winning line **names the matched case**: `[via together-block]`, `[via standalone <k=v>]`, or `[via case <a & b>]`. |
| C2 | Change state so a *different* case matches, `/dl why` again. | The named case **changes** with the match — it is not frozen. |
| C3 | `/dl why` on a **case-less** rule. | Names nothing — reads byte-for-byte as it always did. |

## §D — the completion-slice chrome (this slice)

| | do | expect |
|---|---|---|
| D1 | With a case existing (so the body is **case 1**, a box), click **copy** on case 1. | A new case appears duplicating the **rule body** — the body-to-case copy, a starting point for a near-identical alternative. |
| D2 | Click **copy** on an added case, then edit the duplicate. | The duplicate is fully editable and **the original is untouched** (independent copy, not a shared reference). |
| D3 | Inside a case, add the same `&` condition **type** twice (e.g. `name = test` then `name = testar`). | The second **replaces** the first and a note says so (never silent), with **Match either instead** offered — exactly as in the body. |
| D4 | Click **Match either instead** inside the case. | Both values move to that case's `|` leg; the rule now fires on either. |
| D5 | Hover the box header (`& case` / `| case`) and the AND/OR selector. | Underlined label; the hover carries the one-sentence semantics. No inline paragraphs anywhere in the new chrome. |
| D6 | Add a `+ & case` / `+ | case`, leave it empty, click **Save**. | Save is **refused** with a clear notice ("A case has no conditions yet…"). An empty case is never saved silently — this includes an empty **case 1** in box mode. |
| D7 | Eyeball every new label (case headers, `copy`, `+ & case`, `+ | case`, the AND/OR selector) under your themed font. | **Nothing clips.** Report any label cut off — the width audit is by-construction (copy sits left of the fixed right cluster) but the field is the last word. |

## §E — edge interactions

| | do | expect |
|---|---|---|
| E1 | Delete **case 1** (the body box) while other cases exist. | The next case is **promoted** into the case-1 seat, op and all. No un-deletable box. |
| E2 | Delete the **last** remaining case. | All case chrome vanishes; the rule falls back to the flat body (only the two buttons remain). |
| E3 | Delete / reorder a case-bearing rule in the rule list. | Behaves like any other rule — priority reorder and delete are unaffected by cases. |
| E4 | **Save as Blueprint** on a case-bearing rule, then stamp it onto another job (or share the text and re-import). | The cases travel **verbatim**; the round-trip is byte-stable. |
| E5 | Delete a **Mode** that a case references. | The dead-mode sweep reaches **into cases** — narrowing, emptying, and removing cases by the same rules it applies to the body. No case is left pointing at a mode that no longer exists. |

## §F — the version guard (warn, never misread) — **the data I most want**

| | do | expect |
|---|---|---|
| F1 | Save a rule that uses an `& case` or a `| case` with an internal `|` (so a `cases` list is actually emitted). Open the file. | The rule carries a `hasCases = true` guard token in its body. A `| case` of only `&` conditions serializes as the **old** multi-condition `|` form (no `cases` list, no guard) — oldest-form-first. |
| F2 | Load that same file on an **older addon version** (git-pull skew, or a shared file), and dispatch. | The older engine sees the unknown `hasCases` key and **drops the whole rule with the standard chat warning** — it must never quietly evaluate case 1 alone. Half-protected-without-knowing is the failure this guard exists to prevent. |

---

## If it is clean

`dev` → `main` is Henrik's call (branch rule: work commits directly on `dev`,
never a feature branch; `dev` promotes whole-or-not-at-all). Two player-visible
naming items are still open for his sign-off and are one-line renames now:

1. The `hasCases` guard token, visible in hand-edited trigger files.
2. The slice-1 strings — `[via together-block]`, `[via standalone …]`, the
   `| case` box header.

## Where the code is

| file | what |
|---|---|
| `ui/triggersui.lua` | the whole editor: `_loadCases` / `_buildLegs` / `_buildCases` / `_buildRuleShape` (model translation), `_copyConds` (copy case), `renderTrigAddPopup` (the popup — shared picker on top, boxes below, copy + AND/OR + delete per header). |
| `dispatch.lua` | the engine: the case walker, normalization, the `hasCases` guard, `serializeTriggers` (oldest-form-first), `matchedCase` (`/dl why`). |
| `gear/blueprintsmodel.lua` | the parity-mirror serializer — learns the `cases` form in lockstep. |
| `tests/smoke_ui.lua` | `TE*` — the pure seams and the real popup driven frame by frame (`TE54–TE63` are the completion slice: copy-case independence, match-either inside a case, blueprint round-trip). |
| `tests/run_tests.lua` | `CS*` (match seam), `TC*` (render), `TRC*` (round-trip contract, the maximal fixture). |
