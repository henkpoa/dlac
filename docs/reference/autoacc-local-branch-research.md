# AutoAcc: local branch findings

Research date: 2026-09-28. Scope: archived CatsEyeXI implementation and the current AscensionXI client integration seam. This is source research, not an implementation or a claim about live server formulas.

## Source identity

- Archive repository: `C:/catseyexi/catseyexi-client/Ashita/addons/dlac`.
- `feature/autoacc`: `445dd5386cd9eceddfef070cca6e4f55c30e9154`.
- `hidden-features`: `9244b00f41edb81ce2388eb2e2e79f071731a5ff`.
- `accwatch.lua` is identical on both branches: Git blob `15802df917bd0a72c410ee0e4a062d22dfa8b782`.
- Current AscensionXI HEAD: `29019ed42106f34db43bdcaab2b9464ab5d2a49a`. Current-file references below describe the working tree inspected on the research date; it already contained unrelated modifications, including `gear/gearoracle.lua` and `ui/gearui.lua`. No existing file was edited by this research.

Archived citations use `A:path:line` for `feature/autoacc` and `H:path:line` for `hidden-features`. Retrieve an exact archived source with `git -C C:/catseyexi/catseyexi-client/Ashita/addons/dlac show 445dd5386cd9eceddfef070cca6e4f55c30e9154:path`. No checkout was performed. No `AGENTS.md` was present at either repository root or the inspected ancestor directories.

## What the feature actually does

AutoAcc is a **per-piece rule**. A typed candidate competes in its own pool; the ordinary candidate supplies its fallback. The flattened marker stores removal priority, a baked accuracy value, item name and fallback. When measured accuracy exceeds the estimated cap requirement, the resolver releases typed pieces in descending removal priority; equal priorities use descending accuracy and then slot name. Pieces without a fallback or positive baked accuracy stay on. Unknown, invalid or stale measurements also retain the typed pieces. This is not a global search for maximum damage. [A:dispatch.lua:1337–1448; current `utils.lua:504–507`, `560–566`, `633–645`.]

The UI bakes **only the item's Accuracy stat plus its owned augment Accuracy** on Commit. It does not bake the accuracy difference between the typed piece and fallback. The UI tells the player to recommit after re-augmenting. [A:ui/gearui.lua:2235–2244, 3304.]

The writer publishes `seq`, `valid`, integer `capGap`, wall-clock `at` and display `mob` name to `accstate.lua`. The resolver converts a new sequence into an all-typed-pieces-worn budget by taking `-capGap + sum(previously released accuracy)`, then freezes that budget until the next sequence. This was intended to avoid oscillation when a later measurement sees the already-swapped outfit. The stale cutoff is 900 seconds. [A:accwatch.lua:211–224; A:dispatch.lua:1353–1358, 1372–1374, 1422–1447.]

`hidden-features` loads `accwatch` in its module list and exposes AutoAcc in the gear editor. Its watcher has not gained a new telemetry mechanism relative to `feature/autoacc`. [H:dlac.lua:345–347; H:ui/gearui.lua:4058–4068; identical watcher blob above.]

## The CatsEyeXI workarounds, precisely

| Workaround | Actual source behavior | Why a server-owned feed replaces it |
| --- | --- | --- |
| Generated monster model | `tools/acc_calc.py` downloads public server SQL/C++/Lua data and transcribes formulas; its header explicitly excludes per-spawn script mods, private modules and monster food/buffs. `report` looks up zone plus normalized monster name. | Read effective stats from the actual live entity, including private and scripted changes. |
| Inferred exact level | Passive `/check` replies and widescan populate an entity-index-to-level cache. The watcher injects a monster `/check` on engage/retarget; NM checks do not supply a useful level, so the old path relies on widescan or ranges. | Send the server's current entity level and identity directly. |
| Estimated evasion | `evaAt` linearly interpolates the static range endpoints. `/check` high/neutral/low-evasion text narrows learned bounds, then clamps the model into them. An exact level therefore does **not** make evasion exact. | Send effective evasion; no bracket inference or generated family curves. |
| Custom-monster name mapping | Cross-zone name matching, manual per-character family assignments and a hardcoded Ventures family map synthesize a monster entry using family evasion curves. | Any current battle entity can supply its own stats without a client table entry. |
| Self `/checkparam` | Each accepted engage/retarget injects self `0x0DD` Kind 2 before the target `0x0DD` Kind 0. Self message 712 supplies main-hand accuracy. The code assumes the response order makes the self measurement arrive before the target report. | Send one coherent matchup snapshot, or explicitly revision-related player and target snapshots. |
| Chat suppression and timeout | Matching reply messages are blocked during one-second windows. A missing check reply falls back after 0.8 seconds to whatever is cached. | Dedicated protocol messages eliminate chat-message correlation and cached timeout guesses. |
| Local combat rules | Main-hand skill selects 95% for two-handed or 99% otherwise; requirement is estimated EVA + 40/48, with signed 4 Accuracy per level everywhere. Comments explicitly describe overriding the published server's zone/sign interpretation by a live ruling. | Server combat code must own caps and applicable correction, rather than exporting another client formula copy. |
| File bridge | `accstate.lua` bridges addon and legacy LuaAshitacast states. | The native engine can consume a shared in-memory service; persistence is unnecessary for live combat truth. |

Sources, in table order: A:tools/acc_calc.py:2–25, 35–56 and A:accwatch.lua:394–430; A:accwatch.lua:517–535, 555–583; A:accwatch.lua:119–123, 147–175, 430–449; A:accwatch.lua:226–350, 394–428; A:accwatch.lua:542–553, 587–631; A:accwatch.lua:543–545, 576–578, 640–650; A:accwatch.lua:49–61, 450–478; A:accwatch.lua:180–187, 211–224 and current `CONTEXT.md:245–252`.

## Concrete correctness gaps to avoid carrying forward

These are deductions from the cited code, not live reproduction results.

1. **Updates are not dynamic enough.** The watcher subscribes to check/widescan replies, outgoing attack/retarget and a pending-request timeout. It has no accuracy invalidation for equipment, food, buffs, debuffs, skill gains or target stat changes. A manual self checkparam updates `M.myAcc` but returns without publishing a new `capGap`. Automatic checks are debounced for five seconds against the last target. [A:accwatch.lua:522–585, 587–598, 640–650.]

2. **A valid feed does not establish the current matchup.** The published record has only a monster display name, not zone/session/entity/spawn identity or equipment revision; the consumer does not compare even that name to the current target. Zone-in clears level cache and pending state, but does not invalidate the published cap gap or cached player accuracy. The consumer accepts a missing timestamp and otherwise permits fifteen minutes of age. A previous target's budget can therefore remain usable while the next measurement is outstanding. [A:accwatch.lua:211–219, 523; A:dispatch.lua:1422–1425.]

3. **Baked item Accuracy is not the cost of a swap.** A replacement can itself provide Accuracy, DEX, skill or set bonuses; weapon replacement can change the combat regime. The decision reads only `c.acc`, subtracts it from the budget and never evaluates the fallback's effective stats. This can be overconservative or inaccurate depending on the effects omitted. Merely replacing estimated EVA with exact EVA leaves this defect intact. [A:ui/gearui.lua:2235–2244; A:dispatch.lua:1381–1400.]

4. **Bookkeeping is by name, not slot or item instance.** `_accRemoved[lower(name)]` collapses two copies of the same ring into one entry even if both candidates spend budget. Updates clear only names appearing in the current candidate set, so a removed item absent from a later set can remain in the sum. Moreover, this ledger records a resolver decision, not a server-confirmed worn outfit. A telemetry update cannot safely assume these entries describe the equipment whose accuracy was measured. [A:dispatch.lua:1372, 1391–1395, 1428–1431, 1435–1446.]

5. **The old result covers main-hand melee only.** It learns message 712, selects a cap from the main weapon and emits one scalar gap. It does not establish off-hand, ranged, weapon-skill, special-attack, attack/defense ratio or pDIF semantics. Those require explicit new server protocol contexts rather than reinterpreting the old scalar. [A:accwatch.lua:91–116, 450–478, 542–553.]

## Current AscensionXI integration boundaries

The native client still contains the dormant resolver and marker foundation at [`dispatch.lua:2728`](../../dispatch.lua), with the same frozen-budget design at lines 2763–2838. `equipResolved` calls `accResolveSet` at line 3757. The current editor preserves existing typed fields but only offers None/Dual Wield; its old AutoAcc explanation remains in comments. [Current `ui/gearui.lua:4375–4406`.]

**Preserve the per-piece meaning.** Current architecture explicitly rules that AutoAcc is not a standalone Arbiter claimant: it resolves candidates inside whichever floor or claimant supplies the set. An older changelog suggesting “AutoAcc next” as a claimant is superseded by this ruling. Keep ordinary fallback selection, deterministic user removal priority, and conservative retention when an authoritative answer is unavailable. Replace the measurement and swap-cost mechanisms. [Current `docs/architecture.md:496–500`; `docs/adr/0012-claim-arbiter.md:79–81`; `dispatch.lua:2772–2791`.]

The Gear Oracle is the existing client door for identity, worn items, eligibility and effective stat lookup. `stats` includes effective level stats and caller-provided augments; `setStats` delegates whole-composition evaluation including set bonuses. This is useful for presenting and assembling candidate outfits, but it is not proof of server-authoritative hit rate or pDIF under a hypothetical outfit. Exact decisions need either a verified shared combat model or a server-owned bounded candidate-evaluation operation using the same combat functions as actual attacks. [Current `gear/gearoracle.lua:120–154`, `171–177`, `204–217`, `251–274`, `369–378`; `docs/architecture.md:87`.]

Use the existing combat/engage services where their semantics fit instead of resurrecting duplicate outgoing packet parsing. `feature/combat` supplies the standing combat beat; `feature/engagewatch` owns attack/retarget edges. Neither description establishes that ordinary cursor selection is server-visible, so the new subscription protocol must cover that explicitly. A newly accepted snapshot/result should mark default resolution dirty for a safe native-engine opportunity, respecting player-action phase, actual equipment acknowledgements and revision identity. Do not directly call `dispatch.kickDefault()` on receipt: it dispatches immediately and bypasses the native engine's normal player-action guard. [Current `docs/architecture.md:101`; `CONTEXT.md:130`; `dispatch.lua:4092`; `feature/equipengine.lua:699–736`.]

## Research conclusion

The useful inheritance is the user's rule: “wear this accuracy piece until this matchup no longer needs it; then use this slot's normal candidate, in my removal order.” The public-data model, hidden checks, bracket learning, name mappings, baked per-item cost, name-keyed released ledger and long-lived file feed are all replaceable infrastructure. Authoritative live snapshots solve the knowledge problem; evaluating the effective change from the actual outfit to a proposed outfit solves the remaining decision problem. Both are required for an accurate implementation. The cited code supports these conclusions without importing any CatsEyeXI combat constants into AscensionXI.
