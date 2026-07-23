# 0014 — Lockstyle is addon-resident; the Engine equips gear only

2026-07-23. PRD #80 (the lockstyle addon-residency pivot). Reverses the engine-move
direction of `docs/design/lockstyle-engine-move.md` (grill session, same day). Base:
engine v109 / addon 2026.07.23l, all green (both loops), field-confirmed on two machines.
This record is issue #82 — the decision, ruled; the code lands slice by slice under #80.

## Context

Lockstyle apply is the ONE player feature whose trigger crossed Ashita's command bus
between dlac's two Lua states: the GUI button and the OnLoad/keep/town pumps live in the
**Addon state**, but the executor lived in the **Engine** (dispatch.lua, seeded into
LuaAshitacast's state), reached by `/dl ls apply`. A friend's report — "everything works
BUT lockstyle: preview fine, Apply silently does nothing" — took a week of instrumented
field rounds (docs/history.md, "the silent apply", "the rest of the travel wardrobe") and
closed with three field-established laws:

1. **The command bus between states is unreliable BY DESIGN.** `e.blocked = true` stops
   LATER addons in Ashita's chain from receiving a command, and `/addon reload` order IS
   chain order. Proven from **both directions in one day**: Henrik's reload cycles
   deafened his ADDON state (engine first, blocked ahead of it — engine heard, addon
   inert); the friend's order starved his ENGINE (dlac's own blocking handlers ate the
   command before LAC received it — addon heard, engine never saw it, though his engine
   was alive the whole time, stamped in modestate). This is the friend's original silent
   apply: on his load order `/dl ls apply` died at dlac's handlers, so preview (addon-
   local) rendered and apply said nothing.
2. **Files are the reliable cross-state channel.** The check/debug handoff and request
   files (stamped with `os.time()`, watched on ticks with freshness + idle gates) worked
   in every order/hearing combination. v109 bridged apply onto this channel
   (`debug-request.txt` → the Engine's request watch → `engineApplyHalf`) and it fixed the
   friend — but a purely visual feature that equips nothing was now coupled to
   LuaAshitacast, dead entirely without it, and needing two-state debugging machinery to
   be supported. A workaround wearing the right architecture's clothes.
3. **The Engine is the reliable executor.** Everything living entirely Engine-side — every
   Automation — "always works", because it rides LAC's internal handler flow and never
   touches the bus.

Law 3 is the one that misled. Read as "put executors in the Engine," it pointed at the
engine-move design (relocate the pumps, keep-on-sub, town picks, zone guard, and last-
applied memory INTO the Engine). The grill session found the deeper law underneath it.

## Decision

The deeper law under "the Engine is the reliable executor" is **never cross the bus**.
Automations always work not because they are Engine-side, but because their trigger and
their executor sit in the *same* state and reach each other by direct call — an Automation
must live in LAC because it equips gear *through* LAC (`gFunc.EquipSet`, Engine-only).
Lockstyle equips **nothing** — since v42 it builds the 0x053 packet itself and injects via
`AshitaCore`, the process-wide SDK present in every addon state; every other dependency
(boxes file, Profiles resolver, Owned-gear name→id map, job levels, worn equipment) is
addon-native already. Its Engine residence was historical accident (it once called
`gFunc.LockStyle`), not necessity.

So the executor moves to the **trigger's** state, not to the Engine. Lockstyle becomes
100% resident in the Addon state: the apply executor (0x053 build + inject) relocates out
of the Engine into `feature/lockstyleapply.lua`, and the pumps, keep-on-sub, town picks,
zone guard, and last-applied memory — which already live in the Addon state — reach it by
**direct function call**. No lockstyle trigger crosses the state wall anymore, in either
direction. The bus problem is not bridged; it stops existing. The Engine's only remaining
lockstyle knowledge, after the two-phase hand-over completes, is nothing at all.

This sharpens the boundary to a one-line rule: **the Engine equips gear (and reports on
its own equipping) — nothing else.** Its command-surface corollary: *a `/dl` command lives
where its subject lives* — equip state in the Engine, everything else in the addon,
`check`/`debug` straddling the wall by design (architecture.md, cross-referenced with
ADR 0002).

The hand-over is **two-phase** so no mixed-generation window can silently break applies
(the exact failure this project exists to end):

- **Phase 1 (addon-only release):** the addon gains the whole executor and stops writing
  apply requests; the Engine (v109) is untouched. Every mixed old/new combination
  mid-`git pull` keeps working; no load-order quadrant double-applies (exactly one apply
  either way — the v109 Engine still handles a typed apply it happens to hear, harmless).
- **Phase 2 (engine-only release, v110, gated on field confirmation of phase 1):** pure
  deletion — the Engine drops `ls` from its command whitelist and deletes its apply
  branch, pure-core twins, send witness, request-`apply` kind, and the `debug ls` engine
  half. The latent typed-apply `lastBox` bug (see below) dies here.

A spike gates the whole plan (slice 1): prove an outgoing `AddOutgoingPacket(0x053)` from
the Addon state reaches the server. Evidence it will: lookpreview injects *incoming*
packets from this state daily, and the zone guard *blocks* outgoing 0x053s from this state,
so the outgoing stream is provably manipulable — only same-state outgoing injection
reaching the server is formally unproven. If the spike fails, fall back to the superseded
engine-move design; nothing will have broken meanwhile.

## Alternatives rejected

- **The engine-move design** (`docs/design/lockstyle-engine-move.md`) — relocate the whole
  timing story INTO the Engine so one state owns it next to the job-identity machinery.
  Correct under the shallow reading of law 3, but it keeps a visual-only feature coupled to
  LuaAshitacast (dead without a shim), needs packet events proven in the LAC state, and
  carries +400 lines of the most field-hardened code across the wall. Superseded, not
  deleted — it is the fallback if the injection spike fails.
- **Keep the v109 request-file bridge permanently** (belt-and-braces) — leaves lockstyle
  coupled to the Engine and to two-state debugging for a feature that needs neither; the
  bus failure mode stays latent behind the bridge instead of being removed.
- **Fold the executor into `feature/lockstyle.lua`** — the 200-local chunk-cap lesson
  (hard rule 1) says don't; the executor gets its own module.
- **A parity twin of the job-gate prediction** — rejected: the prediction goes through the
  Gear Oracle's one door (`anyJobCanWear`, ADR 0013), retiring a twin rather than adding
  one.

## Consequences

- **What was given up, honestly:** executor fixes now ride `/addon reload dlac`, NOT the
  Engine's content-keyed self-swap (v102) that pushes updates into a running game. This is
  the real cost — an addon-state module is stale until the player reloads. **Accepted**
  because a single-state feature *cannot have a cross-state version-mismatch bug*: there is
  no second generation to disagree with. The class of bug the self-swap defends against
  (mid-session staleness across the wall) is exactly the class that stops existing here.
  Editors can be stale harmlessly; only executors that must agree with a *peer* across the
  wall cannot — and lockstyle no longer has a peer.
- **Lockstyle works standalone** — editor, preview, and apply run with no LuaAshitacast, no
  job shim, and no Setup. A player can use dlac purely for looks. (Before, "LAC not loaded"
  meant lockstyle fully dead and, worse, presented as a lockstyle bug.)
- **A latent bug dies:** on one load order today, a typed `/dl ls apply <box>` reaches the
  Engine but the Addon state stays deaf, so keep-on-sub's `lastBox` memory never updates —
  a later subjob flip can restore the *wrong* box. With the executor and its bookkeeping in
  one state, the apply arms the guard and notes `lastBox` at the call site; the memory can
  never diverge from what was applied.
- **Command surface collapses to one claiming state.** The Addon becomes sole owner of
  `/dl ls`; phase 2 removes `ls` from the Engine whitelist, so typed commands pass through
  on every chain order (the whitelist's `e.blocked` was the deafness mechanism). Equip-
  state commands (`mode`, `why`, `plan`, `prio`, `lock`, `sets`, `profile`, `env`,
  `triggers`) stay Engine-side — their LAC dependence is subject matter, not accident.
- **One pure core, no twins.** The apply's pure core lives in exactly one module; the
  parity pins and double maintenance end. The relocated core must produce byte-identical
  0x053s (goldens-as-gate, per ADR 0013), and the job-gate prediction goes through the
  Gear Oracle (`anyJobCanWear`) — eligibility keeps its single home.
- **`/dl debug ls` becomes a one-state report** after phase 2 — the addon half plus the
  executor's own dry-run/witness lines; the file states "engine: not involved — lockstyle
  is addon-resident." The check/debug file-channel machinery (handoffs, requests, receipts)
  is untouched: it is wiring diagnostics, not lockstyle.
- **The pivot is recorded** (this ADR; the supersession banner on the engine-move design
  doc; the CONTEXT.md **Addon state** / **Engine** glossary entries) so a future reader
  holding the 2026-07-23 laws understands why lockstyle is NOT Engine-side.
