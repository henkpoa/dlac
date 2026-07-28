# The Integration surface — how other addons read dlac

> Status: **DESIGNED, not built** (2026-07-28). Product rulings are Henrik's, marked
> **[RULING]**. The parked plugin-folder design is section 10 — it is deliberately
> *not* the recommendation.
>
> Origin: Henrik asked how realistic a plugin folder would be (2026-07-27/28). The
> grilling walked it down to the actual customer — a second player building a damage
> **parser** as its own Ashita addon, who needs dlac's gear truth correlated **live**
> and writes nothing — and the answer turned out to be a much smaller thing than a
> plugin system.

---

## 1. Why this exists (and why it is not a plugin folder)

**Ashita gives every addon its own Lua state.** That single fact is why dlac once seeded
files into LuaAshitacast's folder and coordinated by disk, and why ADR 0014's law is
*never cross the bus*. An addon that wants dlac's live data has, by default, only files
and the command chain — the exact channel this project spent months proving unreliable
(`e.blocked` halts later addons, and `/addon reload` order **is** chain order).

There are only three honest ways out:

| | Mechanism | Cost |
|---|---|---|
| A | **Static data on disk** — `data\*.lua` are plain `return {…}` tables anyone can `loadfile` | zero; already true today |
| B | **The integration surface** — `plugin_event` push + pull, this document | small, contained, no third-party code in dlac's state |
| C | **A plugin folder** — third-party Lua inside dlac's own state | large; section 10 |

**B is the recommendation.** It serves the known customer *better* than C (he keeps the
addon he already has, and iterates without waiting on a dlac release), and it avoids every
hard problem C creates: no sandbox, no capability tiers, no dormant plugin conditions
inside player trigger files, no plugin rank rows in `arbstate`, no frozen internals.

### The reframe that got us here

The first design was a written *snapshot* of the current composition. That is the wrong
instrument, and the reason is worth keeping:

> **By the time a damage packet arrives, the composition has usually already moved on.**
> dlac decides gear at Precast, sends 0x050/0x051, then re-injects the blocked action; the
> server resolves it and the 0x028 comes back hundreds of milliseconds later — by which
> time the 0.4 s tick has re-dressed to idle. A consumer that answers *"what is worn?"*
> when damage lands attributes the weaponskill to the idle set, **intermittently, as a
> function of server latency.**

So the unit is not a snapshot and not a poll. It is a **labelled event**: what dlac
decided, stamped with the action that caused it, joined by label and sequence — never by
arrival order.

### The precedent

`addons\luashitacast\integration.lua` already does exactly this shape on this channel: it
answers *"what gear do you know about"* to other addons via
`AshitaCore:GetPluginManager():RaiseEvent`, with a caller-supplied `ReturnEventPrefix` as
the reply channel. We copy the convention rather than invent one.

---

## 2. What became possible this week

Both of the hard inputs are by-products of the ADR 0027 program (2026-07-27/28):

- **v150 — ONE PLAN, ONE SEND.** Every `equipResolved` pass merges into `ctx.planOut` and
  the dispatch sends **once** (`dispatch.lua`, `engineEquipSet(ctx.planOut)`). *"'the final
  plan' exists as a VALUE for the first time."* Before this, the composition was smeared
  across N sends and the equipengine buffer was the hidden merger — there was nothing to
  publish.
- **v143 — `/dl why <slot>`.** The trace stashes a **structured contest** per slot (every
  claimant in rank order, the winner, the verdict's word, the source ladder), not just
  rendered lines. That is the provenance payload, already computed.

The change trigger is the plan's own content (§5.4). The retrace **signature** (`_trace` keyed
`event → { time, action, sig, lines, contest }`) is the nearby-but-different question — *"did
the reasoning change"* — and is useful only as a pre-filter.

**Consequence: no engine change and no `M.VERSION` bump.** The surface is an
**addon-side observer** over values the engine already publishes. ADR 0014 holds
unamended — *the Engine equips gear and reports on its own equipping, nothing else*; a
streaming exporter is not the engine's job.

---

## 3. The switch **[RULING]**

Henrik, 2026-07-28: *"with a command and settings option, should not survive a log off."*

- **`/dl stream on|off`** (bare = status), plus a row in the Menu's **Settings** panel.
- **Session only.** Never written to disk, never restored.
- Default **off** — not for cost (see below), but because 99% of players will never
  need it.

**This is not a Setting**, in the CONTEXT.md sense: a Setting is *remembered* (`uiflags.lua`,
owned by `gear\syncflags`). This one is a **Session switch** (new glossary term, section 9)
— the class dlac already has several of: naked, slot locks, free equip, the locked set,
every floating window's open flag. The Settings row must say *(this session)* on its face,
or players will reasonably expect it to persist.

### The lifetime trap, which has already cost this project a field round

An Ashita addon **survives a logout** (a relog is not a fresh Lua state). So "dies on log
off" is not automatic — it must be dropped explicitly. And the naive drop is wrong:

> **The world read goes 0/nil during a ZONE LOAD exactly as it does at character select.**

That is v146's ruling (*"ZONES SURVIVE"*, Henrik): `M.worldWatch` no longer drops on
absence alone, only on **outlasting** a zone (`WORLD_GONE_S = 60 s`) or on a live job
change. A stream switch that dropped on absence would die on **every zone line**.

**Decision:** the observer reuses that law and that constant from its one home — never a
second timer with a second number. If the engine exposes no read-only seam for "the world
has been gone too long", add one (a pure boolean, no behavior) rather than mirroring the
logic. A job change must **not** drop the stream: a job change is data the consumer wants
(`invalidate`), not a reason to stop talking.

### Cost, honestly

Smaller than it sounds. `gearui` already folds worn totals through the same evaluator
**every frame** the Equipped panel is open. A fold plus a string build on *composition
change* — a few times a second at worst — is noise beside that. There is therefore **no
subscribe protocol in v1**: the switch is the gate, the consumer just filters `e.name`.
(A TTL subscribe handshake, entwatch's sleep-after-no-interest shape, is the natural v2
if always-on emission ever proves wasteful.)

---

## 4. Transport

Both directions ride `plugin_event`:

```lua
-- send
AshitaCore:GetPluginManager():RaiseEvent('dlac_worn', payload)
-- receive
ashita.events.register('plugin_event', 'dlac_integration', function (e) … e.name … end)
```

**Payload = the bytes of a Lua-source string** (`return { … }`), which the consumer
`load()`s. Rationale: both ends are Lua; every dlac serializer already emits exactly this
shape; and **adding a field can never break a consumer** — he ignores keys he does not
know. No ffi, no `struct`, no JSON encoder (dlac has none, and Lua source is strictly
better for a Lua reader).

`RaiseEvent` is a **broadcast** — there is no addressing, so "subscribing" is just
filtering `e.name`, and dlac cannot know who is listening. Hence the switch.

**PROBED AND RESOLVED (2026-07-28** — evprobe + dlacprobe 2.3, Henrik's field run; the
throwaway pair lives outside dlac, probe code never ships in the addon):

- **Send: a byte table.** `RaiseEvent` REFUSES a plain string (a sol2 type error on the
  spot) — LAC's `:totable()` convention is the only one.
- **Receive: `e.data`, already a STRING** — the bytes arrive reassembled; `e.size`
  carries the length. **`e` is userdata**, so consumers read named fields and never
  iterate `pairs(e)`.
- **A state hears its own RaiseEvent** (unlike its own QueueCommand — the cmdqueue fact
  does not transfer). Filter your own names anywhere you both speak and listen.

Size is not a concern: LAC's own struct on this channel is ~1 MB.

---

## 5. Push — the stream

One envelope, one `kind`, drained FIFO on `d3d_present`:

```lua
return {
  v = 1, seq = 41, kind = 'worn', dropped = 0,
  at = 1774…,                                  -- stamped at DECISION time
  source = 'plan',                             -- 'plan' (a decision) | 'worn' (a memory read)
  snapshot = false,                            -- true = state dump, NOT a change event
  char = 'Mindie', charId = 29909, dlac = '2026.07.28a', engine = 151,
  event = 'Weaponskill', action = "Rudra's Storm",
  actionId = 143, actionCategory = 0x07,       -- THE JOIN KEY -- see 5.1
  targetIndex = 0x1A3, targetId = 0x…,
  job = 'THF', jobLevel = 75, sub = 'NIN', subLevel = 37,
  worn = { … }, ctx = { … },                   -- v1 payload
  by = { … }, totals = { … },                  -- DEFERRED, see the scope ruling
}
```

### 5.1 The join key **[CONSUMER RULING]**

The parser author asked (2026-07-28) whether `seq` shares a namespace with anything in the
game's own packet traffic, or whether the intended join is `action` name + label + timestamp
proximity. The honest answer to the first half is **no** — `seq` is internal to this stream,
monotonic per session, related to nothing on the wire. But the intended join is **better
than name-plus-time**, and the reason is a happy accident of how the native engine works:

`feature\equipengine.lua:133-140` already decodes the **blocked outgoing 0x01A** into
`{ target, category, actionId }` before re-injecting it. So at decision time dlac holds the
action's **numeric id** and category (`0x03` Spell, `0x07` Weaponskill, `0x09` Ability,
`0x10` Ranged) — the same identity the incoming 0x028 carries back. Publishing them turns
the consumer's join from string matching into integer matching: no localisation, no
apostrophe hazard (the API drops possessives — a real dlac bug class), no ambiguity between
similarly named actions.

Two honest caveats, both to be stated in the consumer guide:

- **`targetIndex` from 0x01A is an entity *index*, not a server id** — the classic FFXI
  confusion. dlac publishes the raw index and, when it can resolve one, the id and name
  alongside it. A consumer joining an index against an id gets silence.
- **Identity is not uniqueness.** Two Rudra's Storms in a row share an id and target, and a
  `Default` envelope has no action at all (`actionId = nil`). So the recipe stays *search
  backwards for the most recent matching envelope* — the numeric key removes the guessing
  from "matching", not the need to search.

### 5.2 v1 payload scope **[CONSUMER RULING]**

The parser author, 2026-07-28: *"we only need `worn` and `ctx` (all of ctx, including
day/weather/element and moon phase) plus the envelope metadata. You can skip effort on `by`
and `totals` for now — not needed at launch. May come back to ask about `totals` later if we
build a stat sanity-check layer, but don't build for that yet."*

**[RULING] Henrik overrode the `totals` half the same day:** *"Give him everything that is
being worn and total stats at any given time anything has changed."* So **v1 ships `worn` +
`ctx` + `totals` + metadata**, and only **`by` is deferred**. The fold is already performed
every frame the Equipped panel is open, so the cost is a string build; shipping it means the
consumer never has to come back for it, and an unwanted key is free to ignore.

- `by` deferred is **purely additive** — a new key in the same envelope, which is the whole
  point of "complete records, never curated fields."
- The `stats` query (§7) still exists for *hypothetical* compositions. `totals` on the stream
  answers "what did he actually have on"; the query answers "what would this other set give".

### 5.3 A set name is not a composition — this is why the stream ships items **[RULING]**

Henrik, 2026-07-28: *"We are simply not just building sets here. You can have one set trying
to claim some slots at a trigger level, then other sets from other automations trying to do
the same thing… On my WAR, I have different modes and everything that affects what my sets
do, so sets doesn't always do the same. What my friend needs is simply not just 'hey, I
trigger switched to this set now when I WS'd' — might not be enough."*

He is right, and it is the single most important shape constraint on this surface. `WS_Default`
does not name a composition: what it resolves to depends on **active modes** (which change
which rules match at all), the character's **level** (dynamic sets flatten per level, and a
level sync re-flattens), **ladder outcomes** (an unowned or ineligible rung falls to the
next), and **every claimant above the floor** (AutoAmmo, MaxMP, craft/HELM/fishing/chocobo
gear, pins, locks, free equip). Two identical `WS_Default` casts an hour apart can be
different sixteen items.

**Therefore the envelope never reports a set name as the answer.** It reports the **resolved
items, per slot** — and the totals folded from those items. Set and rule names appear only
inside `by`, as provenance *about* an answer that is already concrete.

The corollary for the `modes` field: modes must be in `ctx`, because a consumer analysing a
session wants to group by them (*"my numbers in Melee mode versus Caster mode"*) even though
the composition already accounts for them. `dispatch.activeModes()` is the reader.

`by` deferred is a genuine loss of the surface's most distinctive data (it is the only place
"which rule at which priority won this slot" exists), so keep building it into the
observer's *internals* even while it stays off the wire — it costs nothing and it is what
`/dl why` already computes.

### Kinds

| kind | Fires when | Carries |
|---|---|---|
| `worn` | the composition genuinely changed — **two triggers, see 5.4** | the whole envelope above |
| `dispatch` | an action went through the pipeline and **gear did not move** (a moved outcome emits `worn` instead — one anchor per action, never both) | envelope metadata + `actionId`/`actionCategory`/target + `ctx` — **no rule trace in v1**, see below |
| `invalidate` | job change, Commit, inventory moved, profile switch | which `rev`s advanced |
| `confirm` | a few hundred ms after a `worn` — see below | the actual worn read vs the plan |

`dispatch` exists because of the second contract in section 6: if a weaponskill's set
resolves identically to what is already on, **no `worn` event fires** — correctly — and a
consumer listening only to `worn` is blind to the fact that the weaponskill happened at all.

**Refined 2026-07-28 (Henrik's correlation question):** `dispatch` is the **anchor**
kind — its job is the *join*, not the reasoning. Without it, a no-change action leaves
the consumer joining against *silence* (sound, but an inference); with it, every action
he sees in his own packets gets a positive envelope naming the same numeric `actionId`,
and his join collapses to one uniform rule: *find the anchor; the composition is either
inside it (`worn`) or is the newest `worn` before it (`dispatch`)*. Carrying `ctx` on the
anchor is deliberate — TP at the WS moment is exactly what a damage parser wants. Two
consequences of the same no-flooding law that shaped the monitor's log:

- **One anchor per action.** `worn` when the composition moved, `dispatch` when it did
  not — never both for the same action (a `dispatch` beside a `worn` is the same data
  twice).
- **No rule-match trace in v1.** The trace exports the shape of live trigger internals,
  which we refactor freely; it stays off the wire until the consumer names a concrete
  use, then arrives as additive keys — exactly the `by` treatment.

### 5.4 What triggers a push — corrected 2026-07-28

Henrik's *"at any given time anything has changed"* is a stricter requirement than my first
answer (the retrace signature), and the difference matters:

| Trigger | Answers | Emit |
|---|---|---|
| **the final plan's content changed** (`ctx.planOut`, v150) | *did the outcome change* | `worn`, `source = 'plan'`, with provenance |
| **the worn equipment changed and dlac did not cause it** | *did reality change* | `worn`, `source = 'worn'`, no provenance |

The retrace **signature** answers *"did the reasoning change"* — close, but not the same
question, and it exists only per event. Since v150 the plan exists as a value, so hashing
`ctx.planOut` answers the outcome question directly: it catches a ladder fall that produces a
different item under identical claims, and stays quiet when the reasoning churns without
changing what is worn. Keep the signature as a cheap pre-filter if profiling ever asks for
one; the plan's content is the authority.

The second row is what makes the promise literal. A player hand-equipping a ring in a
**free-equip** slot, an item breaking, or the server stripping a piece changes the totals with
no dispatch at all — and a consumer that missed it computes confidently wrong stats. Detection
is a 16-id compare hung off the signal dlac already watches (`ui\gearui.lua` `packet_in`
0x020/0x01D → `sf.invDirty`), sharing the `confirm` compare. `source` then tells the consumer
which kind of truth it is holding.

### `confirm`, and why it is not optional decoration

The stream reports **what dlac decided**. The server can refuse an equip (level, job,
cutscene, mid-action, a slot reserved by a piece it stripped). A plan is *intent*, not
fact. Without a confirmation the consumer silently treats one as the other — hard rule 12
on the wire. `confirm` re-reads the worn state after the round trip and reports the delta,
or nothing if the plan landed whole.

Note the ordering trap it avoids: reading worn memory **at** decision time answers with
the *previous* composition, because the client has not yet applied our packets. The plan
is the only correct source at t=0; the worn read is the only correct source at t+Δ.

---

## 6. The two contracts

**1. Stamped at decision time; joined by label and `seq`, never by arrival order.**
dlac's dispatch runs on the **network thread**; the pump is on the main thread. A consumer
could therefore see a damage packet before our push of the composition that caused it,
even though we decided first. Because every envelope carries the causing action and a
decision-time stamp, arrival order is irrelevant. (Immediate same-thread raising is a
one-line option if a real case ever needs it. Do not build it speculatively.)

**2. No event means nothing changed.** The absence of a `worn` envelope is a positive
statement: the last one still describes reality.

**And the mechanics that make it a stream rather than a mirror:**

- **FIFO, drained fully each pump — never last-value-wins.** Precast and Midcast can land
  in one frame; a mirror eats one silently. This is the law that produced `lib\cmdqueue`
  (*two same-frame events arrive reversed or not at all unless you buffer and drain*).
- **`seq` monotonic + a `dropped` counter.** The queue caps (64 suggested); overflow drops
  oldest and reports it in the next envelope. A gap in `seq` means *re-pull a snapshot* —
  the only honest hand-off after a stall.

---

## 6.5 Cold start and re-sync **[CONSUMER RULING]**

Two more questions from the parser author, and both expose a spec hole worth closing before
anything is built.

**"If we load mid-session, do we get an initial state envelope, or start blind?"** Never
blind — but note *why* it needs two mechanisms. dlac cannot detect a consumer loading
(`RaiseEvent` is a broadcast; there is no subscribe, §4), so it cannot greet anyone. Instead:

1. **On `/dl stream on`, dlac immediately emits a snapshot envelope.** Covers the player
   flipping the switch mid-fight while the consumer is already listening.
2. **The `worn` query answers at any time.** That is the consumer's bootstrap: ask once at
   load. They should *not* hand-roll their own worn-item read — theirs would carry no `ctx`,
   no decoded augments, and none of dlac's decode of the packed equipment index.

**"What does a gap look like, and what do we get back?"** A gap is either signal, and they
answer different failures: **`dropped > 0`** in a received envelope is dlac's own queue
having overflowed (we know we lost some), while a **discontinuity in `seq`** catches
everything else — a consumer handler that threw, a late load, a lost broadcast. Both mean
*re-pull*, never interpolate.

The reply is **a fresh full `worn` envelope** with the current `seq`. Which forces the two
fields added in §5:

- **`snapshot = true`.** A re-sync envelope is *not* a gear-change event. Without the flag, a
  consumer logging gear changes records a phantom change every time it re-syncs — a silent
  data-quality bug in someone else's product caused by our shape. The flag is one boolean and
  it is not optional.
- **`source = 'plan' | 'worn'`.** At rest — freshly logged in, no dispatch yet — there is no
  plan to publish, so a snapshot is built from the client's worn memory instead. That is the
  *more* accurate source at rest, but it carries no provenance, and the consumer deserves to
  know which one it is holding rather than inferring it from the absence of `by`.

Pull replies always arrive on the caller's own reply channel (§7), never on `dlac_worn` — so
a re-sync can never be mistaken for a live event even before `snapshot` is read.

## 7. Pull — the queries

Caller supplies its own reply channel, LAC's convention:

```lua
'dlac_query'    → return { reply = 'ffxiparse', what = 'sets', job = 'THF' }
'ffxiparse_r'   → return { v = 1, what = 'sets', rev = 17, data = { … } }
```

| `what` | Answers | Source |
|---|---|---|
| `worn` | the current composition, as a `worn` envelope | the last plan + worn read |
| `gear` | the owned-gear record | `gear.lua` via the oracle |
| `sets` | a job's set names, or one set resolved with totals | `profilesets` / `oracle.setStats` |
| `item` | any item: catalog record + owned state + augments | `catalogindex`, `ownedcache`, `augments` |
| `stats` | **folded totals for a composition the caller invents** | `oracle.setStats` |

`stats` is the hypothetical door, and it is read-only. It matters because without it the
consumer must reimplement level scaling, augment folding and set-bonus tiers — precisely
the deduction drift `gear\gearoracle` was built to end (ADR 0013). ~10 lines over an
existing door.

Every reply carries a **`rev`** so consumers cache `gear`/`sets` once and re-ask only on
`invalidate`.

---

## 8. What is in the data, and what is not

**The composition (`worn`), per slot.** Id, name, and the record (`Level`, `Jobs`, `Type`,
`OneHanded`, `RSlot`, `AmmoType`) from `catalogindex`; **decoded augments** — stat deltas
*and* readable labels — from `feature\augments`, the only decoder for CatsEyeXI's private
augment ids anywhere; per-item **level-scaled** effective stats via `levelstats.effective`;
and the owned/available/stored verdict from `ownedcache`.

**The totals.** `oracle.setStats` → `geareffects.comboStats`: every stat, level-scaled,
augments folded, **plus active set bonuses** from `data\gearsets.lua` (126 sets,
value-at-count tiers, level-gated — not summable increments, so nobody reproduces this by
accident). Pet-channel stats ride **alongside, never folded in** (`oracle.petStats`, from
`item_mods_pet`, which the live API never serializes at all).

**The provenance (`by`) — the part nothing else on the client can know.** Per slot: the
**set** that dressed it; the **rule** that matched, with its conditions, `priority`,
specificity tier and which **case** matched (v125); the **claimant** that won it and over
whom (`arbExplain`: *"Ammo: AutoAmmo (rank 3) over MaxMP (rank 4)"*); reserved-slot
verdicts and, since v139, whether a piece was refused and **fell** to its next ladder rung
and why; resolved **virtual entries** (which staff AutoStaff picked, at what Iridescence
tier; whether AutoObi fired on the day/weather net); and any slot held by locks, free
equip or naked.

**The world (`ctx`), at decision time.** HP/MP/TP, status, moving; active buffs; **day +
weather element and the obi's signed favourability net** (directly relevant to magic
damage); zone + in-town; target; pet + pet status; game mode (`CW`/`Wings`/`ACE`); moon
phase; merit MP. All from the `nativedata` providers dlac already reads every dispatch.

**Two deliberate refusals.**

- **Complete records, never curated fields.** Curated fields are what would make every new
  idea of the consumer's cost a dlac release — the failure mode that killed the
  push-protocol-only design.
- **No diffs.** He can diff `seq` N against N−1. A diff protocol is a second thing to get
  wrong.

**What dlac cannot give, plainly: damage math.** The pDIF pipeline, WS first-hit accuracy
and the mob-EVA/accuracy chain exist here as *documented research* and on a parked branch
(`feature\autoacc`, `share\mob-stats\`), not as shipped code on `dev`. dlac ships gear
truth, decision truth and world context — the correlation keys. The damage model stays the
consumer's.

---

## 9. Vocabulary

Two CONTEXT.md terms land with this design: **Integration surface** and **Session
switch**. The second is a gap the glossary already had — `Setting` is defined as
*remembered*, and dlac is full of switches that deliberately are not (naked, locks, free
equip, the locked set, window open flags). Henrik's *"should not survive a log off"* is
what made naming it necessary.

Not added: any plugin vocabulary. The glossary describes what exists; section 10 does not
exist yet.

---

## 10. PARKED — the plugin folder

Designed, argued to a conclusion, **not built**. Recorded so it is not re-derived. Revive
it the day someone needs something genuinely in-state: **a tab inside dlac's own window**,
or **a gear claimant**. The parser needed neither.

**Mechanically it is easy, and the host contract already exists.** `ui\uihost.lua` is
already trove's plugin model minus discovery (`register{name, tabs, window, invalidate}` +
`host.provide`/`host.services`), and `addons\trove\` proves runtime discovery works in this
client — 20 plugins, up to 82 KB. Discovery needs no shell: `ashita.fs.get_dir(path, '.*',
false)` (mask is a **regex**, third arg is **recursive**, returns nil for a missing
directory), and `profiles.listLuaFiles` is already that seam. The v40 objection — *popen
spawns console windows* — no longer applies.

**Scope, as Henrik ruled it:** full — read, own UI, own commands, own storage, register a
gear **Claimant**, and extend the trigger language.

**Rulings from the 2026-07-27/28 grilling:**

- **[RULING] No capability tiers, no sandbox, no maintainer allowlist.** *"We don't need to
  control what the plugins do, they are dependant on us, so if they crash, it is what it
  is."* A restricted `_ENV` (`loadfile` + `setfenv`) was designed and rejected. The
  liability position is explicit and Henrik's: *"That's like blaming the tool maker that
  someone was killed with a hammer."* One honest line in the docs, no walls.
  - The consequence to accept: dlac's doors are enforced by source guards
    (`tests\run_tests.lua` GRD1–GRD5) which can **never** police third-party files. For
    plugins the door is documentation plus whatever the API makes *easier* than
    hand-rolling.
  - The tier design also considered a hardcoded digest list of privileged characters
    ("hidden superadmin"). Verdict: buildable, and it buys **attribution, not
    prevention** — dlac ships as readable Lua, so a bypass is a text edit, not a hash
    break. If revived: FNV-1a over `name..serverId..SALT` (no crypto library is reachable;
    plain `string.byte` arithmetic keeps it headless on 5.1 *and* 5.4), one seam
    `tierFor(name, serverId)`, a guard asserting only digests ever ship — and **hide the
    identities, publish the mechanism**, because an unexplained secret list of privileged
    accounts has the *shape* of a backdoor to a GM reading the source.
- **Error containment stays, and is not a capability wall.** A plugin error inside an ImGui
  render tears the ImGui stack — the visible result is *dlac's window vanishing*, not the
  plugin failing. Hence `uihost`'s `tabGuard` and trove's per-entry-point pcalls. A broken
  plugin prints its own name and loses its own tab; that is what makes "it is what it is"
  land on the plugin instead of on dlac.
- **[RULING] The dependency is one-directional. dlac never depends on a plugin.**
- **A plugin may Claim. Only the player may Commit.** Henrik's instinct — *"it shouldn't be
  able to edit the actual profile, send in temporary stuff only"* — is already the
  architecture: not one of dlac's own claimants writes a set file (Pins are session-only;
  naked/locks/free equip/locked set die on job change; MaxMP, AutoAmmo, Craft, HELM,
  Fishing, Chocobo are standing claims re-applied every dispatch), and the Wishlist ruling
  was the same call (*"keep set files clean"* — the feature offers **Apply**, the player
  presses it). So the API ships **no writer** for sets, triggers, lockstyle boxes, modes or
  another feature's statefile. A legitimate set-writing plugin **stages into the Sets tab's
  working set** and the player's own Commit performs the write — the "Copy from static"
  shape. A contract, not a wall.
- **Plugins are folders, not loose files**, the moment anyone writes a real one (a second
  file needs a resolver).
- **Diagnosability, banked cheaply:** `/dl check` lists loaded plugins, and one switch
  disables all of them for a session, so a field report can be made plugin-free in one
  command.

### The unsolved half: data outlives the plugin

Full scope means player data names plugin things — a trigger condition, a virtual slot
entry, an `arbstate` rank row — and a shared **Blueprint** can carry a condition the
recipient has never installed. Policy: **preserve dormant, loudly marked** (forced by hard
rule 10, *player data is never deleted*, and hard rule 12, *a total failure must not look
like a typo*; precedent: a rule naming a missing Group or set is surfaced, not deleted).

Where that already holds, for free:

- **The engine fails closed.** `legMatches`: `local f = MATCHERS[lk]; if f == nil or not
  f(cv, ctx) then andOk = false; break; end` — an unknown condition never matches.
- **Serialization already round-trips it.** `serCondList` emits `(PRETTY_KEY[lk] or
  tostring(k))`, and `gear\blueprintsmodel.lua:171` carries the identical fallback. Both
  are *luck* — the fallbacks exist for other reasons — so the policy needs a **test**, not
  a hope.
- Missing: anyone **telling the player**. A `needs plugin: X` marker on the rule and a line
  in `/dl why` is the whole remaining job.

Where it does **not** hold, and this is real data loss today:

- `gear\arbiter.lua` `arbOrder`: `if known[n] and not seen[n] and not ARB_PINNED[n]` —
  `known` comes from `ARB_ORDER_DEFAULT` alone, so an unrecognised row is **dropped**, and
  once `arbwatch` writes the order back it is gone from disk. Uninstall a claimant plugin
  and the player's drag position is lost silently. That filter is deliberate (it stops a
  hand-mangled file injecting garbage), so the fix is precise: **unknown rows stay in the
  file, never in the walk.**
- A plugin Claimant's default rank is **directly above the Triggers floor** — never above
  dlac's own claimants unless the player drags it there.

---

## 11. Build order, when it is time

1. **The probe** — the `plugin_event` payload field name. Nothing else is designable
   without it.
2. **The observer + the switch** — `feature\integration.lua` (LAC's own filename),
   `/dl stream on|off`, the session-lifetime rule from section 3, `worn` + `ctx` +
   metadata only (§5.2), including `actionId`/`actionCategory` (§5.1) and the
   `snapshot`/`source` fields (§6.5) — those three are cheap now and expensive to retrofit
   into a consumer that already shipped against their absence.
2b. **The `worn` query**, immediately after — it is the consumer's only bootstrap and their
   only re-sync (§6.5), so the stream is not usable without it.
3. **ONE DECISION RECORD, THREE RENDERERS — build this before the wire.** (Corrected
   2026-07-28 after Henrik's *"the trigger monitor still works"* + *"in the end it's the
   arbiter who knows what's going to happen per slot first and why, right?"* — both right,
   and the second one changes the plan.)

   Two records are built in the same breath today, and only one of them is authoritative:

   | | Built at | Holds | Rendered by |
   |---|---|---|---|
   | `_fired` (5-line ring) | retrace, from `hits` | `rule.label -> set name` — what the **trigger layer proposed** | the Trigger Monitor |
   | `_trace[event].contest` | retrace (v143) | `{ explain = arbExplain(claims, order, floor), … }` — the **whole arbitration**, per slot, structured | `/dl why` + `/dl why <slot>` |

   Since ADR 0012 the trigger overlay is only the **floor**: every claimant above it can
   overwrite any slot. So the monitor shows *proposals, not outcomes* — it can print
   `Idle -> IdleSet` while Body actually went to the Craft claim's apron. That is a real
   limitation of the monitor, not of the stream, and it is the reason the stream's subject
   must be the **arbitration result**, never fired rules.

   The record `/dl why` already stashes *is* the stream's payload. So publish it once and
   have all three read it — chat, window, wire — which is this codebase's own law applied
   (mpBands: *"ONE context serves the engine AND `/dl plan` — the plan IS the behavior,
   never render a rival"*). If the record is right, the wire is trivial; if the wire gets
   its own builder, there are two answers to "what happened this dispatch" within a month.
   Keep `by` **inside the record** from day one even though the parser deferred it off the
   wire (§5.2) — the internal renderers need it.

   **[RULING] 2026-07-28: the Trigger Monitor stays exactly as it is** — *"trigger monitor
   can still be trigger monitor, because you still wanna know specifically what happens at a
   trigger level"* — and the arbitration view is a **NEW Arbiter Monitor** (the final name,
   Henrik's, 2026-07-28 — earlier drafts here said "Dispatch Monitor"), a separate
   window populated from the same record. Better than deepening the old one in both
   directions: the trigger-level view keeps its narrow, useful honesty (this is what the
   floor proposed), and the new window can be shaped around the question it actually answers
   (*which claimant won each slot, and why*) instead of inheriting a fired-rule log's layout.
   Two renderers of two different altitudes, one record underneath.

3b. **Free cleanup while in there** (not the stream's job, but it is the same code):
   the monitor works today via its **disk fallback**, not its live feed. The engine's
   `/dlacmonev` push (`dispatch.lua:6640`) cannot be heard in one Lua state — a state never
   hears its own `QueueCommand` — so `trig._firedLive` never latches and `trigFiredState()`
   re-reads `firedstate.lua` on a 1-second throttle (`ui\triggersui.lua:828-832`). Invisible
   for a 5-line log, which is why nobody noticed. In one state the ring can be read
   **directly**, deleting both the dead command path and the file round-trip.
4. `dispatch` + `invalidate` kinds; then `confirm`.
5. The five queries, `rev`s last.

**Headless coverage** (no Ashita needed for any of it): envelope construction from a fixture
plan; FIFO drain **order** with two same-frame events; `seq` continuity and `dropped` on
overflow; query dispatch and unknown-`what` handling; the switch's lifetime (absent world
under and over the grace window, job change **not** dropping it); and payload round-trip
(`load()` of what we emit equals what we serialized).

## 12. To relay to the parser's author

- **Static data is yours today**, no dlac involvement: `loadfile` on
  `addons\dlac\data\catalog.lua` (every item's base stats), `gearsets.lua` (set bonuses),
  `petmods.lua`, `statdefs.lua`, `levelscaling.lua`, `latentstats.lua`.
- **Does he want the `dispatch` kind?** It puts dlac's rule-matching trace on the wire —
  richer, and a bigger surface to keep stable. Section 5 argues he does.
- **Join on `actionId` + `seq`, never on "current".** Section 6, contract 1, and §5.1. This is
  the one way to get subtly wrong numbers that look right.

---

## 13. RESUME HERE — handover, updated 2026-07-28 (second session, Henrik managing)

**The record and the Arbiter Monitor are BUILT** — engine v152, addon `2026.07.28g`/`h`
(commits `5c1874b` engine + `f645d25` window), tests DR1–DR8 + smoke AM1–AM8 green both
runtimes. **Awaiting Henrik's field round.** What landed:

- **The DECISION RING** (`dispatch.lua`, `M.getDecisions()`, cap 50, session-only): one
  record per dispatch whose OUTCOME moved — the plan snapshot (display names, taken
  before the one send retires `ctx.planOut`), the stashed contest, the source ladders
  *as they were asked* (a pinned old record must not re-derive), and a defensive ctx
  snapshot (job/levels, HPP/MPP/TP, status, day/weather/moon, modes, buffs, pet).
  Append law is Henrik's *"only push changes"*: fingerprint = resolved items + each
  slot's **winning claimant** (`M.decisionFp`, pure). The rank order is a retrace-sig
  leg now (the `|ao` leg) — without it a dragged row kept stale `/dl why` attribution
  and the ring missed winner changes under identical items.
- **The Arbiter Monitor** (`ui\arbmonui.lua`): the 4x4 equip-screen grid of the viewed
  decision, cells chip-coloured by the winning claimant, hover = the full
  `/dl why <slot>` answer *of that record*, a "decided under" ctx line, and the
  decision log — click a line to pin the grid to that moment, Live snaps back.
  Openers: Menu → Settings (under Trigger monitor) + a checkbox atop Automations →
  Claim Priority; persists as uiflags `arbmon`.
- **The `dispatch` kind refined** (§5): v1 is a slim **anchor** — metadata + numeric
  join key + `ctx`, no rule trace — and an action gets exactly ONE anchor (`worn` when
  gear moved, `dispatch` when not, never both).

### Next, in §11's order — updated same day, third session

1. ~~**The probe**~~ **DONE** (§4 — resolved: send byte table, receive `e.data` string,
   `e` userdata, self-hear yes).
2. ~~**`feature\integration.lua`**~~ **BUILT** (engine v153, addon `2026.07.28k`): the
   observer pumps the decision ring FIFO on `d3d_present` into `dlac_worn` envelopes
   (v1 scope: worn + ctx + totals + metadata, `actionId`/`actionCategory`/`targetIndex`
   captured into the record at decision time); `/dl stream on|off` + a Menu Settings row
   ("this session" on its face); snapshot-on-enable (§6.5); lifetime =
   `M.worldAbsentOutlasted` — a new read-only engine seam over the worldWatch timestamp
   (bookkeeping now runs unarmed; job changes deliberately invisible to it). Tests
   WW1–3 + IN1–IN9.
3. ~~**The `worn` query**~~ **BUILT** (same commit): `dlac_query` → `{ reply, what =
   'worn' }` answers on `<reply>_r` with a full snapshot envelope; unknown `what`
   answers with `err`, never silence. **The switch gates the whole channel, queries
   included** — off means dlac is silent here (the guide's "tolerate no reply" reading,
   made explicit).
4. **Open:** `dispatch` (the anchor — needs the no-change action signal; see §5) +
   `invalidate`, then `confirm`; then the remaining four queries, `rev`s last.
   **All of it awaits Henrik's field round + the consumer's first real connection.**

The stream reads the SAME ring the monitor renders — the record was proven by eye
before it shipped to someone else's product, which was the whole point of building the
window first.

### Open, not blocking

- **§11 item 3b — the Trigger Monitor's plumbing cleanup** (read the `_fired` ring
  directly in one state; delete the dead `/dlacmonev` push + the file round-trip).
  Deliberately not done with the monitor: zero user-visible gain against field risk in
  a confirmed-working feature. Its face changes nothing either way.
- **Relay to the parser's author** (§12, updated): the guide is usable TODAY for Part 1
  (static data); ask him to (a) report the payload field name if his side probes it
  first, and (b) name a concrete use for the rule-match trace if he ever wants it on
  `dispatch` — otherwise it stays off the wire.
- **The parked plugin folder** (§10) stays parked. Revive only for something genuinely
  in-state: a tab inside dlac's own window, or a gear claimant.

### Do not re-derive these — each one cost something today

- **The Trigger Monitor is not broken.** Its `/dlacmonev` push genuinely cannot be heard in
  one Lua state, but `firedstate.lua` + a 1 Hz re-read carries it (§11 item 3b). The old
  `architecture.md` bullet described the dead half and read like a dead feature. Fixed — but
  the standing lesson is **field observation beats a doc section**, most of all in a file
  whose own header says it awaits a rewrite.
- **A set name is not a composition** (§5.3). Any future export, monitor or log that says
  "switched to set X" is reporting an intention, not an outcome.
- **The change trigger is the plan's content, not the retrace signature** (§5.4) — and gear
  can move with no dispatch at all.
- **`plugin_event`'s receive-side payload field name is still unverified.** Probe before
  building anything on it; the consumer may settle it first.

