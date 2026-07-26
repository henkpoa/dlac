# Trigger cases — a second `&`/`|` tier, serialized oldest-form-first behind a version guard

A trigger rule gains one optional **`cases`** list: a second tier of the exact `&`/`|` logic the rule body already speaks. The schema is **additive** (case-less rules are byte-identical forever), **oldest-form-first** (a construct is spelled in the oldest schema that can express it, so old addon versions still evaluate what they can), and any rule that *must* use the new list carries an always-true **version guard** so older engines drop it with a warning rather than mis-evaluate it. This ADR records the schema + semantics decision for slice 2/5 of PRD #124; the display (slice 1) and the editor (slice 3) are separate slices.

## Context

A rule today is one flat expression: an all-must-hold `&` leg (`when`) plus standalone `|` conditions (`whenAny`). That cannot express *OR of ANDs* (`(A & B) | (C & D)`) or *AND of ORs* (`(A | B | C) & (D | E)`) without duplicating whole rules or abusing `|` conditions (which stand alone and surprise users by firing without their siblings). The rejected alternatives — arbitrary nested boxes and an `anyOf` pseudo-condition — were eliminated with the maintainer (nested boxes for canonical-form ambiguity and editor cost; `anyOf` for readability). See PRD #124.

## Decision

**One sentence of semantics, true at both tiers:** `&` things bind into one together-block; each `|` thing stands alone; fire if the together-block holds, or any `|` thing does.

- **The rule body is case 1.** Each added **case** carries an operator (`&` or `|`) and the same two legs a body has (`when` + `whenAny`), and matches *internally* by the same sentence.
- **At the rule tier** the `&` members are the body's `&` leg + every `& case`; the standalone `|` things are the body's `whenAny` entries + every `| case`. The **empty-together-block law generalizes**: with no `&` member (an empty body leg and no `& case`) the together-block is never a hit — only the `|` things count. "OR-only is never always-on" holds at both tiers.
- **One layer, hard cap.** Cases cannot contain cases; a nested `cases` field is ignored.

**Schema (additive, oldest-form-first).** A rule gains an optional `cases = { { op = '&'|'|', when = {...}, whenAny = {...}? }, ... }`. Canonical serialization spells each construct in the oldest schema that can express it:

- A **`| case` with only `&` conditions** serializes as a multi-condition `whenAny` entry in the *existing* schema — so `(A & B) | (C & D)` is evaluated correctly by **every addon version ever shipped**.
- Only **`&` cases**, and **`| cases` with an internal `|` leg**, use the new `cases` list.

**Version guard (warn, never misread).** Any rule serialized with a surviving `cases` list also gets a guard condition — `hasCases = true` — stamped into its body. This engine registers it as an **always-true matcher at the bottom tier** (10, the specificity floor, so it never moves auto-priority) and **strips it on load** (it is a serialization artifact, never a real condition). An older engine has no such key, sees an unknown condition, and drops the whole rule with the standard chat warning. This preserves the project law: refuse a rule you cannot fully evaluate; never quietly evaluate part of it.

**Engine.** `matches` gains the case tier over a factored `legMatches` (one tier's `(all &) OR (any |)`), reused by the body and every case so the two tiers can never drift. Normalization validates each case's legs with the same registry gate and drop-with-warn as the body, drops empty cases, and strips the guard. Rule **labels** extend deterministically over cases (each as `<op>(<leg label>)`, sorted) while a case-less rule labels **byte-for-byte** as before, so existing pin-scope keys keep matching. **Auto-priority** becomes the max tier over every leg of every case (`M.defaultPriority`, the one source of truth the editor's chip also calls). `M.matchedCase` (for `/dl why`) names the winning case — `together-block`, a `standalone`, or a `case a & (x | y)`.

**Both serializers in lockstep.** The trigger-file serializer (`dispatch.serializeTriggers`) and the blueprints emitter (`blueprintsmodel.emitRule`) are a parity-pinned mirror pair; both learned the oldest-form split, the cases list, and the guard, and both share the identical per-rule body text (pinned). The edit-model translator (`triggermodel.fromRaw`) and blueprint sanitizer carry `cases` through the wipe contract and strip the guard. The dead-mode sweep and the profile-export dependency scan both walk cases with the body's ladder.

## Why oldest-form-first + a guard, rather than a plain new key

A plain `cases` key on every case-bearing rule would make *every* such rule unreadable to older addons — including `(A & B) | (C & D)`, which the shipped `whenAny` schema already evaluates perfectly. Oldest-form-first keeps the common OR-of-ANDs shape backward-compatible, and reserves the guard-triggering `cases` list for constructs genuinely no old version can express (`&` cases, `| cases` with internal OR). So a friend on last month's addon still gets your OR-of-ANDs rules working, and only *loses* (visibly, with a warning) the rules that truly need this version.

## Consequences

- Case-less rules are a pinned byte-identical invariant across matching, serialization, and labels — the 99% pay nothing.
- No migration exists because none is needed: existing rules are valid single-case rules forever.
- `hasCases` is a player-visible token in the hand-editable trigger file. Chosen for honesty (it reads as "this rule uses cases, a newer feature") and flagged for the maintainer's naming sign-off.
- No UI emits cases yet (slice 2 is the invisible backbone); the editor is slice 3. The rule list and `/dl why` render/name cases-list rules with the slice-1 visual language.

*Numbering: 0022 (`locked-set-is-a-claim`) is the highest existing ADR on dev, so this takes 0023.*
