# AscensionXI: authoritative combat telemetry and AutoAcc

Research date: 2026-09-28. Status: **built on 2026-10-05 (dlac `2026.10.05b`, engine v170; AscensionXI server slice 1), awaiting the owner's live tests.** Read "Status 2026-10-05" first; the sections after it are the history of the design.

**Backend research agent:** start with the [backend research assignment](#backend-research-assignment) appended below. It defines the remaining investigation and deliverable; the operation IDs, rate budgets and APIs proposed in this document are not already implemented or agreed wire contracts.

## Status 2026-10-05: built

**What exists.** Both halves of AutoAcc v1 are written and tested headless; nothing has run in a game client yet.

- **Server** (AscensionXI, branch `claude/autoacc-telemetry`): the combat telemetry service, `modules/custom/lua/combat_telemetry.lua`, on 0x1E0 ops **0xC0–0xCF** (moved from the research's 0xB0, which Guild Work Orders took on 2026-10-04). Handoff: `documentation/custom/combat-telemetry.md` in that repo.
- **dlac** (branch `claude/axi-autoacc-v1`): the pack module `servers/ascensionxi/modules/telemetry/` (`wire.lua` codec, `client.lua` session and battle lane, `formula.lua`, `autoacc.lua` the decision, `monitor.lua` the readout, `init.lua` the Ashita glue), dispatch v170 (the decision at THE ONE SEND), the Gear Rule combo's AutoAcc choice (`ui/gearui.lua` `M._gearRuleOptions`), the Gear Helpers row and `/dl autoacc`. The transport fixes T1–T4 are their own PR (dlac #198).

**How a decision is made.** The client keeps one session and one battle lane in FOLLOW mode. Each accepted frame goes to `autoacc.noteFrame`, which checks it (LIVE, the formula composes its own live totals, no GEAR_REFILL, the outfit it names is in the ring of worn outfits, live − R equals dlac's plain + set sums) and keeps it as a **basis** when it passes. At a Default dispatch, `dispatch.M._autoAccApply` hands the composed plan (every AutoAcc piece on, Free-equip slots as worn) to `autoacc.decide`, which picks a basis, projects the plan and each release from it, and returns the slots to release with a reason per slot (`/dl why <slot>`, the trace line, the readout).

**Changes from the agreed design, all made while building it:**

1. **Bases per comparison key.** Two frames with the same server comparison key (`wire.snapshotKey`, research §4.4) differ only in the outfit, so each can speak for the other's outfit. dlac keeps every passing frame of the current key (up to 8) and decides from the newest one whose outfit differs from the plan only in modelled, verified pieces. Without this, a weapon skill's outfit frame (pushed once per new outfit) would become the only frame, and a WS outfit with one unmodelled piece would hold every AutoAcc piece on until something else changed, possibly for the whole fight. When no basis fits, dlac asks once per worn outfit for a republish (RESYNC mode 1), unless the newest frame was already taken in that outfit.
2. **The buff-loss trigger is narrowed.** Losing *any* effect used to hold every piece until the next frame, but the server sends a frame only when a published input moves, so losing Protect would have held the pieces for the rest of the fight. Now only losing an effect in `autoacc.ACC_EFFECTS` holds (food, Madrigal, Etude, Aggressor, Focus, DEX/ACC boosts, Enchantment, Aftermath, Auspice, Hunter's Roll, Building Flourish, Prowess, the trust ACC aura, the custom Monk Resonance), and a listed loss that brings no frame within `LOSS_SETTLE` (2 s) is let go with a RESYNC renew, which recovers a lost push. Any other loss keeps the decision; if it did move an input, the server's frame follows within a tick. A gained Blindness, Accuracy Down or Flash holds for as long as it is up.
3. **Demand.** The session starts only when `autoacc.decide` is first asked (a set with an AutoAcc piece is worn) and ends with STOP after 5 minutes without a question; the worn outfit is sampled only in that window. A player without AutoAcc pieces sends nothing and costs the server nothing.
4. **GEAR_REFILL first.** An Onslaught frame is set aside before the gear check, so a run never marks pieces unverified.
5. **A gear mismatch beside a verified basis** marks only the pieces that differ from that basis's outfit.
6. **The player read is reused for 0.1 s** (two reads per dispatch and the readout's every frame cost one).

**Native engine only.** The decision runs where the engine runs. Under LuaAshitacast the engine is the seeded copy in LAC's Lua state, where no pack module mounts, so `_autoAccService()` is nil and the dormant v1 budget path keeps every AutoAcc piece worn (ADR 0015: new features target the native engine). The Gear Rule tooltip and the readout say so when the Native engine is off.

**Tests** (none in `ci.yml`; adding them is a workflow change for the owner): `tests/ascensionxi_telemetry_wire.lua` (90, the server's vectors and the comparison key), `tests/ascensionxi_telemetry_client.lua` (104), `tests/ascensionxi_autoacc.lua` (87, AA-01..AA-28), `tests/ascensionxi_autoacc_dispatch.lua` (37), `tests/ascensionxi_autoacc_ui.lua` (53), smoke GR1–GR11. `run_tests.lua` 7,547 and `smoke_ui.lua` 1,639 still pass. Fifty-nine deliberate breaks across the module, dispatch and the UI were each caught.

**Owed before anyone relies on it** (the owner's client; agents never drive it): the server handoff's L1 (unblocked 0x1E0 volume with dlac unloaded) and L2–L6 (unload, STOP, reload, collision with the vault and Nexus, cadence in a fight), the Gear Vault field round for #198, then a playtest of a real set: type one ring AutoAcc, fight an even match and a tough one, and read `/dl autoacc` and `/dl why Ring1`.

**Next work:** weapon-skill decisions (§"Weapon skills" below), latent conditions (issue #41) to release more pieces, and modelling augmented copies.

## Status 2026-09-29: answered, and partly superseded

**Read this section first.** The backend research this brief asked for is [AscensionXI PR #719](https://github.com/henkpoa/AscensionXI/pull/719): the report `documentation/custom/autoacc-backend-research.md`, its wire vectors, and the §8 "Return to dlac agent" contract. The PR is research only, not yet merged. The dlac session and the #719 author then compared notes and agreed the plan below. **Nothing is built.** Henrik approved the plan on 2026-09-29; see "Owner decisions" below.

### What changed from this brief

Owner direction, 2026-09-29: *"DLAC is stat aware for all gear pieces and can do much work locally."* The server publishes what dlac cannot see, and **dlac computes every outfit itself**. So in the rest of this document:

- **Superseded:**
  - the server-side outfit evaluation ("Proposed bounded server evaluation", PLAN/PLAN_RESULT as the main path);
  - the asynchronous verdict handling in "Stability and races";
  - "no copied combat formulas" in the assignment.
  #719 keeps PLAN only as an optional, unplanned oracle.
- **Still valid:**
  - the per-piece rule (not an Arbiter claimant, removal priority, unknown means the piece stays on);
  - the transport findings;
  - the target and lane identity model;
  - the audit of the old branch in `docs/reference/autoacc-local-branch-research.md`. The frozen budget, baked `acc`, `/checkparam` injection and EVA curves are **not** ported.

### Facts #719 measured on AscensionXI (they differ from CatsEyeXI)

- Every melee hit cap is 95 %, and the floor is 20 %.
- Level correction is penalty-only: −4 ACC per level with the mob above, nothing when it is below.
- The threshold is `trunc(rate × 100)` in doubles. At ACC−EVA = −92, −36 and −34 it is one below the naive value.
- Ranged food gives one more ACC than its percentage.
- An augment that repeats a base mod counts twice (upstream `3b0655b61d`).
- Gear scaling is disabled.

dlac reads caps and correction from the server. It never hardcodes them.

### Agreed design

**A1, owner. The server publishes stats without gear (R).**
- It subtracts each worn item's mods and the set bonus in Lua. Active latents stay inside R.
- Each frame carries a per-slot "latents active" mask.
- For every input gear can move (DEX, AGI, AccMod, RaccMod, TwoHandAccMod, WSACC, SkillLevel per context), a frame carries **both** R and the live total from the same pass. It also carries the live `getACC`/`getRACC` and the live threshold per context.
- Frames are sent only for changes dlac cannot see: buffs, food, Flash, target, a new life, level, enchantments, and a latent flipping. They also go out **once per new outfit per session** (a 32-entry set), so each distinct outfit is verified once. Routine weapon-skill swaps between known outfits send nothing.

**A2, owner.** The server runs the hit-rate function only when it is about to send.

**A3, owner. A lean frame.**
- STR/VIT/INT/MND/CHR, ATT, DEF, pDIF and the composed outputs are dropped. The server stops composing the formula; dlac composes it.
- Slice 1 also adds WSACC (its no-gear part) and the Building Flourish bonus.
- Also in slice 1: FOLLOW, where the battle lane tracks the server's battle target, and QUERY.

**dlac decides synchronously at the single send** (`dispatch.lua`, `THE ONE SEND`):
- It works from the cached R. Armour slots 4–15 only, and only when the dispatch kind is Default. Weapon-skill and spell sets keep their pieces on.
- Default already fires on every outgoing chunk while no action is active (`feature/equipengine.lua`). So there is no asynchronous path and nothing to kick.
- The AutoAcc verdict must be part of the retrace signature.
- dlac keeps a ring of recent outfit hashes, so any snapshot whose outfit it can reconstruct is usable.

**The check, on every frame.** Live total − R per input is exactly the server's item-plus-set contribution for that outfit. dlac compares it with its model, and composing the formula from the live totals must reproduce the live `getACC` and threshold. A mismatch marks the pieces involved unverified, and an unverified piece is never released. The formula must reproduce the "Formula vectors" in #719's `wire-vectors.md`.

**A piece is released only when all of these hold:**
- the frame is LIVE for the current target and passes the check;
- the piece and its fallback are both modelled: no hit-rate latent rows until issue #41, not augmented, not blocking another slot, not in `EnchantedSlotMask`;
- the player is not in an Onslaught run (`GEAR_REFILL`);
- the swap does not lower max HP while an HP% hit-rate latent piece is worn.

**When the server's numbers may be stale:**
- A buff change keeps the last decision until the next frame, which arrives within about 0.7 s.
- These cases put AutoAcc pieces back on until the next frame: a new target; a level or job change; gaining Accuracy Down, Blindness or Flash; losing food or an accuracy buff.

**Weapon skills (after v1).** One-hit melee weapon skills are computed locally: the first hit gets +100 ACC, the roll is continuous, and the cap is 95 %. This follows Henrik's 07-23 ruling. The first cut excludes `accVaries` weapon skills, jump, hybrid and ranged weapon skills, and outfits with elemental, day or any-element fTP mods. Exact gorget arithmetic follows soon after.

### Owner decisions (2026-09-29)

**Approved:**

1. **The joint plan**, now folded into #719 (head `39fc504a`, §7 "Decided on 2026-09-29"). That covers A1–A3, the new-outfit frame rule, the ring and sticky rules, WSACC plus the flourish bonus, and FOLLOW in slice 1.
   - The amended SNAPSHOT is 136 fixed bytes plus 24 per context: 208 bytes for three contexts. #719 §4.3 has the tables.
   - The regenerated `wire-vectors.md` uses real items. TV-05 wears Peacock Amulet, Toreador's Ring and the enchanted Hydra Mittens. TV-06 is the frame after Toreador's Ring is released for Rajas Ring; Rajas Ring's level latents move DEX R by +3, which is the latents-in-R case.
   - Its "Formula vectors" project TV-05's R onto TV-06's live totals. These are d3's acceptance tests.
2. **The augment double count is fixed on the server:** [AscensionXI PR #723](https://github.com/henkpoa/AscensionXI/pull/723), fence `equip-mods-once-per-mod`. dlac's gear model is the plain sum. v1 still treats augmented instances as unmodelled.
3. **The rest of #719 §7:** mobs only, no server oracle, recompute at the player's `TICK` with no engine hooks, a 45 s lease renewed after 15 s idle.

**Still open:** the Onslaught buff heal. #719 recommends removing the top-up, in its own Onslaught PR. Until it lands, AutoAcc makes no decisions inside runs (`GEAR_REFILL`).

### Order

1. **In parallel, now:**
   - Server: amend #719 (s0).
   - dlac: transport fixes T1–T4, so only a matched reply resets spacing, pushes never occupy the pending slot, `abandon` exists, and modules take fair turns. This is **its own PR, because it changes Gear Vault's send timing**, so a vault field round is owed.
2. Server slice 1 (Lua only), including a GM spike command.
3. Live test L1: does the retail client tolerate unblocked `0x1E0` frames? This is the biggest unknown.
4. dlac wire client:
   - T5–T8: block the whole `0xB0–0xBF` partition inside `pcall`, send STOP on unload, seed nonces;
   - a readout;
   - live tests L2–L6.
5. dlac AutoAcc v1 (armour).
6. Weapon-skill decisions.
7. **At any time:** latent conditions (issue #41) widen what can be released.

## Result

Implement this as a server-owned combat information service over AscensionXI's existing custom packet channel. Subscribe once to the player's combat context, publish coherent snapshots when relevant state changes, and evaluate proposed gear replacements on the server. dlac keeps the user's per-piece AutoAcc rule, normal fallback and removal priority. The server owns the combat facts and calculations.

Two parts are essential:

1. **What is true now?** Effective player and target stats, hit rates, caps and attack-ratio information from the live entities and loaded combat rules.
2. **What would be true after this replacement?** Evaluate the complete proposed outfit, including fallback stats, food, skill, augments, scaling, set bonuses and applicable latents. Current ACC minus an item's printed Accuracy is not sufficient.

Do not port the old measurement or frozen-budget mechanism. The local archive audit is in [autoacc-local-branch-research.md](../reference/autoacc-local-branch-research.md). It establishes the old rule's behavior and limitations from `feature/autoacc` and `hidden-features` without checking out either branch.

## Evidence and version boundary

The addon checkout is `C:/AscensionXI/Ashita/addons/dlac`, initially at `29019ed`, with unrelated work in progress. The archived implementation is in `C:/catseyexi/catseyexi-client/Ashita/addons/dlac`.

The server checkout at `C:/repos/ascensionxi` is on an older local-shard topic branch (`5bc9cc4fb1f7316e6dbcad0868e6c6a22398895b`) with substantial unrelated modifications. **Do not implement against that checkout's apparent current files.** This research cross-checked the locally available `origin/main` at **`d17bf9a90143fe7066fb611937519b35d31416bf`**, dated September 28. The server source links below pin that revision. No fetch, server start, deployment, live packet capture or performance benchmark was performed. Runtime configuration overrides and the deployed binary still need verification.

An important example of this version difference: the older checkout lacks HELM/Ascension routing and has different pDIF level-correction placement. The pinned source is the reference for the proposal. [S1, S5]

## What the source already supports

| Finding | Consequence |
|---|---|
| Custom channel `0x1E0` already routes void storage, gear vault, HELM, Onslaught and Ascension status. `0xB0+` is documented as future space. | Extend the existing channel; do not invent another outer opcode. Confirm the reservation again when implementing. [S1] |
| Its envelope is 8 bytes; maximum payload is 500 bytes; packets are padded to 4-byte words. `VoidStorePushPacket` can push a frame without a client request. | A compact unsolicited snapshot is supported by existing transport primitives. [S2] |
| C++ ACC/RACC/ATT/DEF/EVA accessors read effective live state. ACC includes weapon skill, DEX rounding, modifiers, Enlight, merits and percentage/capped food. | Read these authorities; do not rebuild mob stats from SQL or infer effective ACC from an item catalog. [S3] |
| Melee/ranged hit-rate functions use target-relative modifiers, level correction, caps and Flash's remaining duration. | A snapshot needs an explicit attack context and effective result, not just two raw numbers. [S4] |
| pDIF functions draw random numbers and include critical, weapon, damage-limit and action-specific parameters. | Extract a deterministic description of their distribution/caps; do not call the damage roller for telemetry. [S5] |
| Native position packet `0x015` includes `facetarget` and updates `m_TargID`; engage/retarget uses the action pipeline. | Observe native events, but an explicit watched-target request covers prompt cursor/soft-target changes and identifies their purpose. [S7] |
| Equipment changes are accumulated and flushed after the received small-packet batch; character `PostTick` coalesces other updates. | Publish after completed updates, not from every modifier write in a 16-piece gear swap. [S8] |

### Mechanics that must not be assumed from CatsEyeXI

The pinned configuration disables Adoulin weapon-skill changes. The level-correction helper consequently returns true regardless of the zone list. In the hit-rate function, PCs suffer a penalty against higher-level targets but do **not** receive the old archive's positive bonus for fighting lower-level mobs. The archive's signed `4 ACC per level` shortcut must not transfer. [S4, S6]

The pre-SoA melee cap module returns 95%, consistent with the pinned expansion settings. However, the **original pDIF cap module is gated by `xi.pre(WOTG)`**, while WotG is enabled. Its original-cap table is therefore not enabled by those settings. Do not advertise a universal era pDIF cap of 2.0 merely because this is a level-75 server. Read the loaded table/function and publish the result. These are conclusions about the checked-in configuration, not measurements of the deployed process. [S6]

The standard melee wrapper floors the Lua rate to an integer percentage; weapon skills have separate first-hit and later-hit treatment. C++ also has contextual guaranteed-hit logic. Publish the unrounded formula result separately from the threshold actually used by the selected attack path. A standing AutoAcc rule should use ordinary sustained attacks, not strip accuracy because the next Sneak Attack is guaranteed to hit. A hit-rate cap is also not a promise to bypass shadows, parry, guard or other defenses. [S4, S9]

## Proposed contract

### One service, two consumers

The server service produces immutable combat snapshots and bounded loadout evaluations. The dlac AscensionXI server pack owns the wire client and publishes one in-memory combat-data service. The UI and AutoAcc consume the same record. No chat scraping, `/checkparam` injection, generated evasion tables, silent `/check`, family guessing, widescan inference or per-frame network request is needed.

The existing AutoAcc meaning remains **within-set per-piece resolution**, not a new Arbiter claimant. Locks, Pins, Free equip, higher-priority Claims, Main/Sub legality and reserved slots still govern the final plan. [D1]

### Proposed operation allocation

Reserve `0xB0-0xBF` within `0x1E0` in the channel documentation and both implementations. These IDs are proposals, not reservations made by this research.

| Op | Direction | Purpose |
|---|---|---|
| `0xB0 HELLO` | request/reply | Negotiate protocol, rules revision, supported attack contexts, projection coverage, limits and session epoch. |
| `0xB1 WATCH` | request/reply | Replace one named subscription lane (battle or preview); zero target clears that lane. Include lane ID, target server ID and index, independent client watch generation and requested fields. |
| `0xB2 PLAN` | request/reply | Register/update one bounded AutoAcc plan: exact outfit, eligible replacements, user priority and fixed-slot constraints. |
| `0xB3 RESYNC` | request/reply | Explicit recovery after reload, timeout or inconsistent revision; rate limited. |
| `0xB4 STOP` | request/reply | Release subscription/plan; cleanup also happens on logout, zone change and lease expiry. |
| `0xB8 SNAPSHOT` | server push | Full coherent state for this watch; includes invalid/no-target states. |
| `0xB9 PLAN_RESULT` | server push | Authoritative decision for the registered plan and named state revisions. |

Use the existing envelope: transport header, `op:u8`, `seq:u8`, request reserved bytes / response status and flags. Inside the payload put a protocol version and a **32-bit request nonce** for responses. The envelope's 8-bit sequence and transport sequence are not adequate long-lived state identities. Pushes use their own operation and stream revision; they must never be mistaken for acknowledgements of a pending request. [S2]

Start with **full snapshots**, not deltas. Aim to fit self + target + three ordinary attack contexts into one <=500-byte payload. If expanded detail or plan registration needs multiple frames, use a bounded transaction ID, part index/count, explicit record count and atomic assembly. Never combine half of one revision with half of another. Use explicit little-endian integer fields and fixed-point units; distinguish absent/invalid from numerical zero and define overflow behavior.

### Snapshot content

| Group | Fields / meaning |
|---|---|
| Identity | Protocol/rules version, session/zone epoch, subscription lane ID, per-lane watch generation and stream revision, player ID, target server ID + index + server spawn generation, zone and instance context. |
| Coherence | Player stats revision, target stats revision, equipment revision, environment/context revision, sample server time, validity flags and validity horizon. |
| Player | Effective level; STR/DEX/VIT/AGI/INT/MND/CHR; main/offhand ACC and ATT, RACC/RATT, DEF/EVA; active weapon skill/types. Omit inapplicable channels with validity bits. |
| Target | Actual combat level (not check-display EXP level), effective attributes, DEF/EVA and requested attack stats. Use the live spawned entity, including NMs/custom spawns. |
| Matchup, per context | Effective target-relative ACC/EVA, ordinary hit-rate floor/cap, unclamped and effective rate, final roll threshold where applicable, signed ACC-to-cap and applicability/reason flags. |
| Physical damage | Effective ATT/DEF, raw/corrected ratio, distribution bounds, nominal cap, critical context, and whether additional ATT still improves the modeled distribution. |
| Plan linkage | Accepted plan generation, authoritative loadout identity or revision linkage, result status and the decision's dependency revisions. |

Define `accuracyToCap > 0` as deficit and `< 0` as removable **effective** ACC for that attack context. This is informative; it is not permission to subtract an item's catalog Accuracy. Compute the threshold with the same rounding and cap path as combat. If a context is out of range or otherwise inapplicable, return that state rather than a misleading numerical deficit.

Distinguish `rawRatio`, `nominalPdifCap`, `distributionBounds` and `attackSaturated`. Reaching an upper bound does not necessarily saturate the lower bound or the full distribution. Normal and critical attacks, ranged attacks and weapon skills cannot share a single generic `pdifCap` answer. [S5]

### Targets and event ordering

Maintain separate meanings for **battle target**, **selected preview target** and **one-off checked target**. Checking another mob must not silently retarget the standing gear rule. Start with one active AutoAcc battle context and at most one bounded preview; no nearby-mob subscriptions or population-wide queries.

Each lane has its own watch generation and validity. PLAN binds explicitly to the battle lane. Cursor selection and one-off checks may update the preview lane only; clearing or replacing that lane cannot invalidate or replace the battle subscription. A pre-engage automatic gear context, if added, needs an explicit activation transition rather than treating any preview as permission to dress.

When engaged, confirmed server battle-target changes drive the standing context. For immediate cursor previews or pre-engage selection, dlac detects a local selection change and sends one coalesced WATCH through the shared transport. Native `0x015`, engage and `/check` processing can supply or refresh server-visible context without extra client polls. Do not assume that a cursor change sends an immediate native packet: the source proves the fields and handler, not client timing. [S7]

On receipt of a snapshot: validate sizes/version/identity, copy it into a bounded inbox, and process it on dlac's main-thread pump. Reject previous-session, previous-target, older-generation and incomplete results. Target index alone, mob name, or server ID alone across respawns is not a sufficient cache identity. A target switch invalidates the old decision immediately, even while WATCH is waiting behind another request.

Use a renewable subscription lease so addon unload/crash eventually stops pushes. For example, renew a 90-second lease after 60 seconds through normal traffic or one small renewal. This is lifecycle housekeeping, not periodic stat querying. A separate low-frequency validity heartbeat may be required if the chosen delivery/timeout contract cannot otherwise distinguish a quiet stream from a lost service; specify and budget it explicitly. Do not expire unchanged correct stats every few seconds and force repeated resyncs.

## Accurate updates without excessive work

### Dirty revisions, then one coherent publication

1. Mutation sites mark a small dirty mask / increment a revision. They do not serialize packets or run a gear search.
2. Finish equipment, status, latent and related stat recalculation for the logical update.
3. The map/zone update owner drains dirty subscribed contexts at a verified stable point. The existing equipment flush and character PostTick are candidate integration points; establish their ordering before choosing one. Do not emit an equipment snapshot from both. [S8]
4. Compute each changed target's shareable raw stats once. Compute target-relative results per subscriber/context.
5. Compare the semantic payload and publish only changes. A relevant equipment revision still needs acknowledgement even when displayed ACC is unchanged.

Keep a reverse index from watched entity to subscribers. A mob debuff invalidates its watchers, not every player or every mob in the zone. No database reads/writes are required in this hot path.

### Required invalidation coverage

| Cause | Source/hook family to audit |
|---|---|
| Equip, unequip, augments, set bonuses, level-scaled gear | Successful equipment mutation/recalculation and inventory-instance generation; bulk equip completion. |
| Buff/debuff gain, removal, dispel, expiry, potency change | Status-effect container and modifier mutation paths, including direct effect-power changes. |
| Mob evasion/defense/stat change | The same battle-entity paths used for the player; scripted phase/stat changes and respawn. |
| Level, sync, main/subjob, merits, skill-up, traits, stances | Stat/skill/trait rebuild completion, not just icon changes. |
| HP/MP/TP thresholds, drawn weapon, time/weather/zone conditions | Actual latent/conditional equipment dependencies and their activation transitions. |
| Position, facing, range, pet/party-dependent bonuses | Relevant relationship predicates; re-evaluate only subscribed contexts which depend on them. |
| Time-varying calculation without a mutation | Schedule the next semantic change/deadline, e.g. Flash; include timed projection dependencies too. |

Hooking only `addModifier` is insufficient: bulk modifier and equipment methods write the modifier map directly. Current character code also checks latents from HP/MP/TP and target changes. Audit the actual paths and introduce shared revision-marking calls where necessary. [S3, S8]

Flash is the concrete counterexample to a purely event-only implementation: `getFlashPenalty` reads remaining milliseconds and floors `remaining * 0.03`. Its effective accuracy changes even when no effect is added, removed or tick-mutated. Use a bounded timer while that dependency is active, publishing the latest value rather than every one-ACC step. Facing changes can likewise change pairwise bonuses without modifying a stat. [S4]

Initially use conservative dependency groups, then narrow them only with evidence. A low-rate server-side audit of **subscribed** contexts can detect missed invalidations during development, with diagnostics identifying the missing hook. It must not become a hidden production dependency that rescues an incomplete event model.

### Performance budgets to measure

Suggested starting configuration, **not measured guarantees**:

- At most one queued latest snapshot per subscriber; replace obsolete pending snapshots.
- Ordinary repeated changes coalesced over 100-250 ms; target changes and gear completion published at the earliest allowed stable point. Invalidations take precedence over decorative updates.
- At most 4 snapshot publications/second/player under continuously changing state; stable states send none apart from any explicitly negotiated lease/heartbeat traffic.
- One active plan, at most 16 eligible slot replacements, no inventory-wide optimization on the server. At most 17 outfit evaluations per dirty plan pass: baseline plus one trial per ordered replacement. Use deterministic tie-breaking.
- Bound CPU time per tick and plan requests per session; when over budget, retain only the latest generation and return pending/stale rather than an approximate result marked exact.

Illustrative payload arithmetic: a **256-byte whole application frame** at four updates/second for 100 subscribed players is 102,400 bytes/second, roughly 100 KiB/s, before game transport overhead, retransmissions, control messages and plan-result traffic. This is a stress-rate budget, not a measurement or expected steady-state rate. Actual encoding size and CPU profiling determine the production limit.

Repeated `/checkparam` is genuinely a heavier response than one scalar: its server handler emits multiple battle-message packets. The archive also sends `/check` on engagement. Nevertheless, an occasional old engage-only check can send fewer bytes than a frequently changing telemetry stream. Compare **equally fresh behavior** and measure bytes, calculations and extra equips before claiming a speedup. [S10]

## Correct gear decisions

### Why snapshots alone do not finish AutoAcc

The old rule stores a baked `acc` on each piece, subtracts the whole value when releasing it, and compensates at the next measurement. It does not compute the actual fallback delta, DEX/skill effects, food percentage thresholds or set changes. Its released ledger is keyed by item name and reflects intentions rather than confirmed equipment. The archive report gives exact code evidence.

Even a perfect stream of live ACC cannot answer a counterfactual by itself. Trial-equipping pieces and measuring afterwards would reproduce a workaround and generate unnecessary equipment traffic.

### Proposed bounded server evaluation

dlac resolves ordinary set candidates, slot ownership and constraints, then registers a complete effective outfit plus the small ordered list of AutoAcc substitutions. Include held/untouched slots from confirmed equipment, exact item instances and augmentation/inventory generation. Item name or item ID alone cannot distinguish two differently augmented copies.

The server validates all item references against the player's loaded inventory and projects each proposal into a **read-only combat-stat context**. Never temporarily call EquipItem/UnequipItem on the real character: those paths update modifiers, latents, pet state and item scripts. A shallow copy of CCharEntity is not an isolated simulation either. [S11]

Build the projection from a base/non-equipment state plus the complete proposed equipment, sharing item scaling and deterministic stat/conditional-effect evaluation with actual combat. The present source provides useful primitives such as `GetScaledItemModifier`, but **a complete side-effect-free outfit projection API was not established by this research**. This is the main implementation effort and must be delivered and parity-tested, not replaced with catalog subtraction under an “exact” label.

Arbitrary scripted on-equip effects cannot automatically be simulated safely. Audit the supported catalog, factor applicable deterministic effects into a shared evaluator, and mark unmodeled proposals unsupported until covered. This is explicit incomplete coverage, not a player workaround. Scope rollout by proven contexts; do not claim that every item and action is exact from day one.

Ordered decision algorithm:

1. Project the full baseline with eligible AutoAcc pieces present and all winning constraints applied.
2. If that baseline cannot meet the requested sustained hit-rate threshold, release nothing. The existing feature selects fallbacks, not a new arbitrary ACC-maximizing outfit.
3. Visit eligible substitutions in descending user Removal Priority, breaking ties by slot and instance identity.
4. Evaluate the whole outfit with this substitution added to previously accepted substitutions. Accept only if every protected attack channel still meets its threshold and the proposal is supported/legal.
5. Return the accepted slot mask, resulting outfit identity and metrics, with session/watch/plan/dependency revisions. dlac accepts it only while those inputs still match.

For dual wield protect both active hands; for H2H use the actual attack mapping and kicks as appropriate. Ranged has its own context. Start automatic behavior with sustained melee, then add ranged and individual action/weapon-skill contexts after parity coverage. Do not apply the TP-gear verdict to a WS set; first and later WS hits differ. [S9]

This algorithm is bounded and preserves the user's removal order; it is not a global DPS optimizer. Preserve the distinction between releasing ACC gear and a possible future attack/pDIF rule. The shared telemetry can support both.

### Stability and races

Keep the registered baseline and alternatives stable across the rule's own equips. Recompute from that same full baseline instead of treating the just-released outfit as the next all-worn baseline. Separate equipment-observation revisions from external decision dependencies, but only reuse a decision after confirming that the observed outfit is the expected result and all non-equipment effects remain identical. An on-equip effect that changes combat state is an external dependency, not something to ignore.

Include the final Arbiter constraints in the projection request. If a higher-priority claim changes the outfit, the old result is invalid. Integrate this as a planning/evaluation boundary; do not run an independent AutoAcc equip loop. The native engine remains the single gear writer. [D1]

**That final-composition boundary needs new work.** Today `accResolveSet` runs inside each `equipResolved`; trigger overlays resolve separately and claim applications follow before the final `ctx.planOut` is sent. A request for each individual set would budget against gear that a later overlay replaces. Add a capture/two-pass planning seam which carries surviving typed-candidate metadata through composition, resolves ownership and restrictions, and produces one complete baseline/alternative plan signature before evaluation. A cached server decision can resolve only that exact signature; the final legality/ownership pass must still agree before sending. This is a required integration change, not an API that already exists. [D1]

A fallback can itself change Main/Sub pairing, Range/Ammo compatibility or reserved slots. Baseline arbitration therefore cannot simply be frozen for every alternative. Apply a result only if rerunning legality/reservation arbitration produces exactly the projected outfit. Otherwise invalidate and resubmit under a bounded reconciliation policy, retaining ordinary candidates meanwhile. Until this joint planning seam supports changes to cross-slot legality, mark those substitutions unsupported rather than repeatedly trying incompatible outfits. [D1]

Do not block a synchronous equip/action callback waiting on a network round trip. Use a valid cached decision or the ordinary unreleased candidates and request an evaluation asynchronously. Reconcile acknowledgements and suppress identical writes. If unsupported or stale, retain normal candidate behavior and expose the reason in `/dl why`.

Mark default gear resolution dirty when a result arrives and let the native engine consume it at a safe Default opportunity. Do not call `dispatch.kickDefault()` directly from the result callback: it calls dispatch immediately, whereas `feature/equipengine.lua` gates ordinary Default work on the absence of an active player action. A delayed TP-gear verdict must never redress the player during precast, midcast, ranged or WS handling. Include action-phase/generation applicability in the client decision guard; dedicated action contexts require their own previously available decision. [D4]

An asynchronous packet cannot guarantee that the world stays unchanged between evaluation and equip. Report the exact sample/revision and re-evaluate on change. If atomic “apply only if this combat revision is still current” becomes a requirement, it needs a separate conditional server equip transaction integrated with the existing engine; ordinary 0x050/0x051 equip packets do not carry that telemetry precondition. Do not promise zero-latency or timeless accuracy.

## Transport integration details that could otherwise break this

The server's pinned `0x1E0` ingress minimum gap is **50 ms**, shared by every op on that opcode; over-limit requests are silently discarded before feature handling. The current dlac transport is more conservative: `MIN_GAP = 0.35`, one pending operation, `MAX_WAIT = 8`. All new requests must use its shared scheduling rather than open another packet injector. Treat these as current source values, not throughput targets. [S12, D2]

`transport.received(op, seq)` currently resets the send-spacing timestamp even when the reply does not match the pending request. **Do not call it for unsolicited combat snapshots.** Frequent pushes could otherwise postpone vault/HELM sends indefinitely; matching pushes could also incorrectly acknowledge a request. Separate matched replies from pushes, and add fair priority/coalescing for WATCH/PLAN so a paginated vault read cannot monopolize the channel. Preserve the opcode-wide limit. [D2]

After HELLO, only opt-in clients receive pushes. Authenticate self data from the session, not a client-supplied player ID. Validate watched target identity, same zone/instance/BattleID, spawned/selectable/visible status and permitted range. Enforce session memory/request limits and clean up reverse indexes on every lifecycle edge. Exposing NM stats is intentional under the owner's request; arbitrary off-zone/entity enumeration is unnecessary.

Install the packet consumer before requesting pushes. Block recognized custom frames before the retail handler, including malformed/unsupported frames in this owned partition, and reject them locally. Ashita exposes packet interception/blocking; the shipped vault client already follows this shape. Addon unload with an unexpired lease and packets already in flight needs a live-client test; do not assume STOP is instantaneous or that the stock client safely ignores unknown packets. [D3, S13]

## Implementation sequence and acceptance checks

1. **Pin the implementation baseline.** Create isolated server/addon worktrees from the intended current branches; re-check the channel registry, source revisions and runtime settings. Do not switch or reset either dirty shared checkout. Reserve the partition in `documentation/custom/void-storage.md` and the service contract.
2. **Build deterministic combat descriptions.** Add the server custom service under `modules/custom/`; extract/share deterministic hit-rate and pDIF calculations as needed. Keep RNG in the actual combat execution path. Follow server guidance: modules first, small fenced core hooks where required, `CORE_CHANGES.md` entries. Pure calculator extraction can need a documented core exception; do not maintain a second divergent formula merely to avoid editing the owning function.
3. **Ship opt-in readout first.** HELLO/WATCH/SNAPSHOT, revisions, no-target states, hooks and bounded timer dependencies. Add the server-pack client and a diagnostic readout. This milestone proves transport and freshness but is not the completed AutoAcc feature.
4. **Deliver outfit projection.** Validate exact inventory instances, supported conditional effects and parity against actual equips in isolated tests. Register the bounded plan and publish authoritative results.
5. **Integrate Type resolution.** Preserve per-piece UI and priorities; replace the old file feed and frozen budget with the central service. Test final outfit constraints, equipment acknowledgement and stable outcomes before enabling automation.
6. **Load-test and playtest, then normal release.** Server build/deploy and addon distribution follow their respective repo workflows. Keep the feature capability/enable flag off until both sides are compatible. No database migration is intrinsically required for transient subscriptions/plans.

Required meaningful tests:

- Calculator parity: published ordinary melee/ranged rate and execution threshold agree with the attack path for the same snapshot; level differences, era settings, food cap boundaries, offhand/H2H, Flash and target-relative modifiers.
- pDIF description parity: bounds/branches and cap/saturation semantics match deterministic controlled RNG cases; telemetry does not advance RNG or consume buffs.
- Projection parity: actual isolated equip result equals the projected supported result; include fallback ACC/DEX/skill, food rounding, two identical item IDs with different augments, set breakage, sync, stance and HP/TP latents.
- Invalidation: every dependency in the table changes the next published state; bursts coalesce; stable contexts do not resend; one target debuff updates all and only its watchers.
- Ordering: rapid A-B-A targets, target-index reuse/respawn, zoning, reload, protocol mismatch, delayed/dropped/out-of-order replies, multipart expiry and plan replacement.
- Gear behavior: surplus releases in priority order, deficit restores eligible pieces, own acknowledgements do not flap, Pins/Locks/Free equip and claim changes invalidate the right plans, rejected equips do not become “confirmed,” and a delayed PLAN_RESULT during precast/midcast/WS cannot apply Default gear.
- Isolation/budgets: malformed payloads, stale item references and invalid cross-instance targets are rejected; repeated requests cannot run unbounded projections; pushes cannot starve storage traffic.
- Human client run: select/engage/check another mob, swap gear, gain/lose food or an ACC buff, receive Flash, apply target evasion/defense changes, retarget, zone and unload/reload. Compare diagnostic snapshots to server instrumentation and inspect actual equipped results.

Measure subscriptions, dirty reasons, recomputations, deduplicated/sent frames, bytes, projection count/time, queue age, stale rejects and equip reversals. Compare equal-freshness old polling and push workloads in a representative encounter before choosing final rate budgets.

## Handoff and remaining work

Only research Markdown was added. No Lua/C++ gameplay code changed, no tests were presented as run, and no branch was checked out, merged or deployed. Rollback of this research is removal of its two added Markdown files; existing user changes are unrelated.

The next implementation task should begin with runtime rules inspection and the deterministic descriptor seam, then establish complete dirty-hook coverage. The largest unresolved engineering items are a shared, side-effect-free outfit projection that covers supported item scripts/latents without changing real equipment, and the client's whole-plan capture/constraint-revalidation seam. Other open validation items are deployed rules parity, exact wire layout, map-tick flush ordering, unknown-packet handling during unload, and measured CPU/network budgets. None requires reintroducing player-side stat mining.

## Source index

Server links are to the pinned local `origin/main` object and can be read offline with `git -C C:/repos/ascensionxi show d17bf9a90143fe7066fb611937519b35d31416bf:<path>`. GitHub links may require repository access. Claims above labeled as proposals are design recommendations, not existing APIs.

- **S1:** [Channel registry](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/documentation/custom/void-storage.md#L721), [routing](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/modules/custom/lua/void_storage.lua#L1636).
- **S2:** [Packet envelope](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/packets/c2s/0x1e0_void_storage.h), [PushFrame](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/void_store.cpp#L1048), [Lua push binding](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/void_store.cpp#L1205).
- **S3:** [Effective stat accessors and all modifier mutation paths](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/entities/battle_entity.cpp).
- **S4:** [Physical hit rates, modifiers, Flash and Signet](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/scripts/combat/physical_hit_rate.lua).
- **S5:** [Physical calculation functions, pDIF bounds and random sampling](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/scripts/combat/physical_utilities.lua).
- **S6:** [Era settings](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/settings/main.lua), [level correction](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/scripts/data/level_correction.lua), [melee cap override](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/modules/era/lua/combat/physical_hit_rate.lua), [pDIF override](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/modules/era/lua/combat/pdif_caps.lua), [xi.pre](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/modules/module_utils.lua#L91), [enabled modules](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/modules/init.txt).
- **S7:** [Native selection field](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/packets/c2s/0x015_pos.h), [position handler](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/packets/c2s/0x015_pos.cpp), [action handler](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/packets/c2s/0x01a_action.cpp).
- **S8:** [Character PostTick, equipment flush and latent checks](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/entities/char_entity.cpp), [network batch completion](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/map_networking.cpp#L485).
- **S9:** [Hit-rate wrappers](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/utils/battleutils.cpp), [swing context](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/attack.cpp#L307), [weapon-skill hit contexts](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/scripts/globals/weaponskills.lua).
- **S10:** [/check and /checkparam processing](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/packets/c2s/0x0dd_equip_inspect.cpp).
- **S11:** [EquipItem/UnequipItem side effects](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/utils/charutils.cpp), [scaled item modifier primitive](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/utils/battleutils.cpp).
- **S12:** [Network rate limit](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/settings/network.lua#L31), [opcode limiter](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/packets/c2s/rate_limiter.cpp), [dispatch before feature handling](https://github.com/henkpoa/AscensionXI/blob/d17bf9a90143fe7066fb611937519b35d31416bf/src/map/packet_system.cpp).
- **S13:** [Ashita's first-party v4 addon example: packet events and blocked flag](https://github.com/AshitaXI/example/blob/main/example.lua), [official packet-hook overview](https://docs.ashitaxi.com/features/).
- **D1:** [AutoAcc architectural boundary](../architecture.md), [Type automation vocabulary](../../CONTEXT.md), [builder/engine responsibility](../adr/0006-builder-plans-engine-decides.md), [resolution readiness](../adr/0007-resolve-only-when-ready.md), [native resolver](../../dispatch.lua), [Gear Oracle](../../gear/gearoracle.lua).
- **D2:** [Shared AscensionXI client transport](../../servers/ascensionxi/transport.lua).
- **D3:** [Existing custom packet consumer](../../servers/ascensionxi/modules/gearvault/init.lua).
- **D4:** [Native safe Default dispatch](../../feature/equipengine.lua) (`handleOutgoingChunk`, action-state guard), [direct kickDefault and final plan assembly](../../dispatch.lua) (`kickDefault`, `equipResolved`, `dispatch`).

## Backend research assignment

Added 2026-09-28 for an independent backend research agent. This section is a self-contained task brief; read the preceding design for detailed evidence and proposed behavior.

### Objective and scope

Determine the concrete server changes needed to support accurate, dynamic AutoAcc without client-side stat inference, repeated `/checkparam`, trial equipment swaps or copied combat formulas. Produce an implementation-ready backend research report, **not a deployment or completed feature**. Validate or correct this proposal against the current AscensionXI source; do not merely restate it or assume its proposed APIs exist.

The owner controls the server and explicitly wants effective player and mob data, including NMs/custom mobs. Accuracy and pDIF information must reflect the server's actual loaded rules. Performance matters: event-driven publication, bounded calculation, no database work per update, and no population-wide scans for individual subscriptions.

The addon behavior to preserve is: a player marks particular gear pieces as AutoAcc, supplies normal fallback candidates and sets a removal order. When the full resulting outfit can still meet the relevant hit-rate cap, those pieces can yield to their fallbacks. The addon owns user preferences, set composition, slot arbitration and the actual equip operation. The backend owns authoritative combat state and supported hypothetical-outfit evaluation. The backend does not need to build a general gear optimizer or take over dlac's equipment engine.

### Inputs and repository access

- **Required brief:** this file, `C:/AscensionXI/Ashita/addons/dlac/docs/design/ascensionxi-combat-telemetry-autoacc.md`.
- **Required source:** the AscensionXI backend repository, accessible locally through `C:/repos/ascensionxi` or an isolated checkout. Read its `AGENTS.md` and `CLAUDE.md` first. Its working checkout was older and dirty during the original investigation; inspect status and refs before choosing a baseline. Do not switch/reset/stash someone else's checkout.
- **Original comparison baseline:** `d17bf9a90143fe7066fb611937519b35d31416bf`, the locally available `origin/main` on September 28. Select the intended current baseline and record its SHA, date and relevant differences. The source index above provides entry points, not a requirement to implement against that old SHA forever.
- **Useful background:** `docs/reference/autoacc-local-branch-research.md` in the dlac repo. It explains why the old watcher and budget logic are unsuitable. It is optional if this design file is supplied; the archived CatsEyeXI checkout is not required for backend investigation.
- **Client contract checks, read-only if accessible:** `servers/ascensionxi/transport.lua`, `servers/ascensionxi/modules/gearvault/init.lua`, `dispatch.lua`, `feature/equipengine.lua` and `gear/gearoracle.lua` in dlac. If those files are unavailable, identify the client assumptions that need confirmation rather than inventing their APIs.

No account secrets, live player data or running production access are needed to begin. Where runtime evidence is unavailable, distinguish source/configuration conclusions from observed behavior and leave exact probe instructions. This assignment does not authorize restarting the owner's active shard or deploying changes just to obtain measurements.

### Questions the backend report must resolve

1. **Where is the calculation authority?** Trace normal melee main/offhand/H2H/kick and ranged attacks through the final hit threshold, and trace noncritical/critical pDIF. Identify loaded overrides, configuration, rounding, target-relative bonuses and action exceptions. Specify a shared deterministic descriptor API, its inputs/outputs and exact extraction points. Explain how telemetry avoids RNG draws, consuming effects or changing combat results. Keep separate action/WS contexts explicit; do not claim they are covered by the ordinary melee answer.

2. **How is a hypothetical outfit evaluated exactly?** This is the highest-risk question. Trace base stats, active non-gear modifiers, scaled item and augment modifiers, set bonuses, traits, latents and scripted equipment effects. Establish whether their provenance is retained well enough to replace equipment contributions without losing or double-counting non-equipment effects. Do not assume that copying current totals and subtracting catalog stats works. Propose concrete immutable input structures and shared evaluator functions, identify refactoring required, and provide a coverage matrix for supported, unsupported and uncertain effects. Include HP/MP maxima and threshold latents affected by the proposed outfit itself. Resolve how exact inventory instances and stale references are validated. No real-character equip/unequip or shallow entity copy may serve as simulation.

3. **What makes the snapshot stale, and when is it coherent?** Produce a hook table with exact file/function, dependency changed, revision/dirty mask and publication point. Cover singular and bulk/direct modifier writes, equipment completion, job/sync/skills/stances, player and mob effects, latent activation, geometry, time-varying Flash, target lifecycle and rules reloads. Trace network-batch and zone-tick ordering to identify the stable flush point. Distinguish target raw-stat caching from per-player matchup calculation. Show how subscribers and entity generations are cleaned up without retaining invalid pointers.

4. **What is the concrete wire contract?** Recheck `0x1E0` allocation and its ingress limiter; propose a documented partition without assuming `0xB0-0xBF` is still free. Specify field offsets, widths, signedness, units, padding, maximum sizes, version negotiation, status codes and capability bits. Define battle/preview lane identity, independent generations, request correlation, snapshot/plan dependencies, lease/heartbeat semantics, invalid states, recovery and multipart bounds. Include at least one encoded/decoded example and reusable test vectors. Resolve how unsolicited pushes coexist with storage requests and how stale/reordered frames are rejected. Identify what happens when the addon disconnects/unloads while frames remain queued; mark client behavior requiring playtest.

5. **What work is actually bounded?** Describe watcher indexing, dirty queues, target caching, per-session memory, latest-state coalescing and plan evaluation scheduling. Define which changes recompute live state, the hypothetical plan, or both. Challenge the proposed 100-250 ms / four-pushes-per-second / 17-evaluation figures: they are starting hypotheses. Give a repeatable benchmark workload and measured results if safely available; otherwise label calculations as estimates. Include many players sharing one debuffed mob, equipment bursts, Flash, rapid target changes and concurrent vault traffic. Compare equal-freshness polling, including response fan-out and equipment traffic.

6. **What is the smallest correct delivery sequence?** List exact new files/functions, shared-function changes, module registration and necessary fenced core insertions. Separate the readout milestone from full AutoAcc support; current snapshots alone are not completion. Describe parity tests, runtime probes, client dependencies and unsupported cases for each increment. Respect the backend's modules-first and core-change documentation rules. Any required extraction that changes existing combat code must have an explicit parity argument and regression plan.

### Client constraints the backend must preserve

- Plans describe the **whole composed outfit**, including higher-priority claims and held slots; never evaluate independent sets as if each were the final outfit.
- Substitution can change cross-slot legality/reservations. Return enough identity and coverage information for dlac to rerun final arbitration and verify that its actual intended outfit matches the evaluated one.
- A baseline/plan generation remains stable across its own successful equipment changes. External changes and unmodeled on-equip effects invalidate it. Avoid a current-outfit feedback loop that alternates pieces on and off.
- No network round trip may block action dispatch. An asynchronous result becomes eligible only for its matching context at the native engine's safe application point. A delayed standing-melee result must never overwrite spell/WS gear.
- Unknown/unsupported/stale is an explicit state, not a fabricated zero or approximate value advertised as exact. The client retains normal candidates while no valid decision is available.
- Do not add automatic server equipping as a shortcut. If an atomic conditional equip transaction proves necessary for a stronger guarantee, document it as a separate proposed capability and client integration change.

### Deliverable and completion criteria

Write the backend report at `documentation/custom/autoacc-backend-research.md` in an isolated backend topic worktree, or the equivalent location required by current repo guidance. Reference this design and record the inspected source SHA. Keep the research deliverable discoverable according to that repo's guidance. Do not edit the shared dlac checkout as part of backend research.

The report should contain:

- A verdict: feasible architecture, largest required refactors, and any corrections to this proposal.
- A source-cited calculation map, invalidation/hook map and projection coverage matrix.
- Proposed evaluator interfaces and the concrete versioned packet contract, including examples/test vectors.
- A bounded performance design with measurement method and a clear distinction between measured and estimated results.
- Ordered implementation slices with exact files, tests and client/backend dependencies.
- A short **Return to dlac agent** section listing the agreed/proposed fields, identity model, supported contexts, timing guarantees, pending decisions and source changes the client agent must accommodate.

Completion means the next backend implementer can start without rediscovering the authority, hooks or projection design, and the client agent can build against a precise proposed contract. If full projection cannot yet be specified, identify exactly which missing abstraction/effect blocks it and the smallest isolated investigation needed to resolve it. Do not substitute a raw-stats-only implementation and call the accuracy rule solved.

Use safe offline inspection and isolated probes where useful. Record every probe command and actual result; do not label unrun tests or inferred runtime settings as verified. Follow normal repository review procedures for the research artifact; implementation and deployment remain separate work.
