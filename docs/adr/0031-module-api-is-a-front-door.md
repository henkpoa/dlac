# 0031 — The module API is a front door, not a wall

Accepted 2026-07-30. Bumps the Job helper contract to **`api = 2`**. Completes the module-system
trilogy: ADR [0028](0028-job-helper-modules.md) records **what a module is** (a folder, identity is
the folder name, `api` is checked loudly, containment is structural, one folder = one unit of server
approval); ADR [0030](0030-module-owns-initiation.md) records **how a module acts** (it claims
through one shared serialized sequencer and never equips anything itself). This ADR records **how a
module reaches dlac at all** — and it exists because the answer under `api = 1` was "by hardcoded
`require` path", which cost more than it looked like it cost.

## Context

`api = 1` shipped a module-facing surface consisting of one table:

```lua
local deps = { host = host, jobhelpers = jh };   -- dlac.lua
...
pcall(rec.mod.init, opts.deps);                  -- feature/jobhelpers.lua
```

**Nothing ever used it.** The one shipped module mentioned `deps` three times, all in comments; its
`init` hook took the parameter and ignored it. Every service was reached by name instead —
`require('dlac\\feature\\petvitals')` — which is legal, works, and is what the authoring guide
correctly documented.

The bill for that arrived as duplication, and it is worth listing precisely because none of it was
carelessness — it is simply what "reach the services by path" costs, paid once per module and then
once per file inside each module:

| Duplicated in `bst-helper` | Copies |
|---|---|
| `local function req(name)` — the contained-require helper | 3 files |
| The monotonic clock (`cq.frame() / 60.0`, falling back to `os.clock`) | 3 files (5 across the addon) |
| The activity-predicate block (`require` → `.activity(id)` → unpack `active`/`reason`) | 3 rules + 3 Panel sites |
| `M._emit` — the loud-line emitter | 2 files |
| `M.sectionOrder` — delegating to the framework's answer | 2 files |
| The settings store (`KEYS`/`DEFAULTS` + serialize + normalize + load-once + write-on-mutation) | 193 lines, and the guide's advice was *"copy it"* |
| The module's **own** path, `dlac\jobhelpers\bst\bst-helper\config` | 4 files |

That last row is not duplication, it is a **contradiction**. The framework's first law is that the
folder name is the identity, assigned by the loader — and the loader had `rec.id` in hand at the
call site and passed only `deps`. So every file that ran without a render ctx carried
`local DEFAULT_ID = 'bst-helper'` as a fallback, and every sibling was loaded by absolute path.
Renaming the module folder therefore assigned a new identity *and broke every internal require*,
in a system whose entire premise is that the folder is the unit of install and of approval.

Three smaller costs followed from the same shape:

- **Subscription keys were an author's discipline.** `'jobhelper:' .. id .. ':fight'` was spelled
  out by hand at each subscribe site. Two modules picking the same rule name would have collided
  silently.
- **Nothing could be torn down.** No subscription was recorded anywhere, so there was no answer to
  "drop this module's beats".
- **Some raw services are easy to call wrongly.** `recast.readyFor(sig)` without its second
  argument has nothing to measure and answers READY — a footgun the guide had to warn about in
  prose, in a section a reader might skip.

And one wrong answer was reachable that had already cost a live field round: `MainJobLevel` instead
of the override/sync-aware level. Under level sync the pet-food ladder picked a tier above the cap,
the equip was refused, and the sequence died in a contained verify timeout instead of correctly
falling a rung. `feature/petfood` carries a HOUSE-LAW comment about it. A comment is the weakest
possible enforcement of a rule that costs a field round to break.

## Decision

**The loader mints one curated API table per module — conventionally `S` — and hands it to
`init(S)` and to every Panel render as `ctx.S`.** `feature/modapi.lua` owns it. `api` moves to
**2**, and the version constant moves with the surface (`modapi.API`, re-exported as
`jobhelpers.API`), because what a module actually depends on is the *service surface*, not the
shape of the contract table — `api = 1`'s gate could only say "your table has the right keys",
which was never the thing that broke.

**It is explicitly not a sandbox, and this ADR does not reopen that question.** ADR 0028 settled it:
dlac ships as readable Lua in one Lua state, so a wall buys attribution, not prevention —
*"visibility and contracts, not walls"*. A module can still `require` anything, and `S.service(path)`
is the documented, deliberately-visible way to do it. The distinction the decision rests on is:

> `S` is the **supported** surface — documented, versioned, tested, and it will keep working.
> Reaching past it is legal and unsupported, and it is the signal that `S` is missing an entry.

Four properties are **structural** rather than remembered, and they are the reason it is a factory
(`modapi.build(rec)`) closed over the module's identity rather than a singleton taking an `id`:

1. **Identity cannot be declared or spoofed.** `S.id` is the folder name the loader read off disk.
   Every entry that needs it takes it from the closure, so there is no argument to get wrong.
2. **Subscription keys are namespaced by construction.** `S.pet.subscribe('reward', cb)` becomes
   `jobhelper:<id>:reward`. Two modules cannot collide on a rule name.
3. **Subscriptions are recorded**, so `modapi.dropAll(id)` can undo a module's beats wholesale.
4. **An Action sequence request is stamped** with the module's own id and section order. A module
   cannot request as another, and cannot invent its own priority.

**Entries are named for the question, not the service.** `S.item.own('Carrot Broth')`, not
"`ownedcache.counts()` is keyed by item id, so keep your own name-to-id table". The point is not
ergonomics, it is that **the right answer becomes the only reachable one**: `S.player.level()`
returns the level the engine will gear at, and raw `MainJobLevel` is not reachable from the module
API at all. `S.ability.ready(name)` wires the live reader, so the READY-by-omission footgun cannot
be reproduced. Where an answer has an "I could not tell" state, the direction is documented and
always the safe one — items answer `0`, activity answers *not acting*, recasts answer READY, pet
presence answers absent.

**Most entries are plain references**, resolved lazily through two contained helpers (`svc`/`ask`).
That keeps it a curated *namespace* rather than a translation layer: it costs almost nothing, cannot
drift from what it names, and a service that failed to load degrades exactly one answer and never
throws into a module.

Three companion pieces ship with it, each removing a category of copy-paste rather than adding a
feature:

- **`feature/modcfg.lua`** — a module *declares* `config = { file?, keys, defaults }` and the
  framework owns the format (fmt-versioned, declared keys of the declared type only, mutation-only
  writes, tolerant reader, never caches the pre-login nil, sorted output). One policy, N independent
  stores. A malformed declaration is a loud load refusal, not a silently dropped write.
- **`ui/panelkit.lua`** — dlac's field-proven ImGui patterns as widgets, handed to a Panel as
  `ctx.ui` already bound to the host's handle. Six lessons that previously lived in prose become the
  default behaviour of a function: guard every widget (presence proves nothing — hard rule 2),
  lit/unlit `Button` instead of the never-used `RadioButton`, measured widths, vertically stacked
  exclusive choices, the panel-text standard, and Push/Pop balance on every path. `ruleStatus` owns
  the status precedence *and* its colour split, because "warn is only for what the player can fix"
  is a rule, not decoration.
- **`feature/combat.lua`** — one combat state service, which also resolves a standing inconsistency
  (see *Consequences*).

## Considered and rejected

**A sandbox / capability tiers / an allowlist.** Rejected in ADR 0028 and not revisited. One Lua
state and readable source mean a wall is theatre; worse, it would make the front door feel like a
restriction to be worked around instead of a service to be used.

**Leave it at raw requires and document harder.** This was the status quo, and the 888-line
authoring guide was a genuinely good attempt at it. The trouble is what the guide had to *contain*:
§8's worked example shipped `local function req(name)`, hand-assembled the three-`pcall` state
block, and spelled out subscription keys by hand — the document was teaching the boilerplate
because there was no way to remove it. A guide that has to transmit a footgun ("pass the reader or
it silently answers READY") is describing a design problem, not solving one.

**A thick wrapper / adapter layer with its own types.** Rejected as the expensive version of the
same idea. Every wrapped call is a place to drift from the service it wraps, and it would need its
own tests to prove it still agrees. The chosen shape — a namespace of mostly-references — gets
discoverability and stability without a second implementation of anything.

**Keep `deps` as the name and just fill it.** Rejected as a legibility trap: `deps` described a
dependency-injection bag, and the thing is a curated API. The two keys it did carry (`host`,
`jobhelpers`) survive on `S` for compatibility, marked legacy.

**Bump the API but keep `config.lua` per module.** Rejected: a storage *policy* distributed by
copy-paste means every module inherits the version of it that existed on the day it was written,
and a fix has to be applied N times by N authors who do not know they need it.

**Delete `feature/engagewatch`.** Considered when its edge surface was found to have zero
subscribers, and rejected on Henrik's ruling — *"I do think the dead code is preferable if we can
fix it"* — which was correct. Re-reading the field history, what the second failed round indicted
was using the packet's captured entity as the command's **target**, not the decode. See below.

## Consequences

**`api = 1` modules stop loading, loudly.** That is the version gate working as designed. The
shipped `bst-helper` is ported in the same change, and it is the only module in existence, so
nothing is stranded.

**The port is the evidence.** `bst-helper` went 2667 → 2038 lines (−629, −24%) while *gaining*
explanatory prose, with the pure deciders (`pollDecide`, `decide`, `decideLoss`, `queueDecide`)
untouched so the field-tested logic is byte-identical. Every row in the Context table above went to
zero copies except the local `cfg()` alias, which is now a two-line accessor for `S.cfg` rather
than a module. Its 350-line Panel with 47 hand-written binding guards became ~150 lines of
declarations; its 193-line `config.lua` became a 22-line declaration and was deleted.

**Testing got better as a side effect, and this is the most reusable consequence.** Because every
service, the clock, the settings store and both act doors arrive on one table, driving a whole rule
headlessly is *one fake* (`fakeApi` in `tests/run_tests.lua`) instead of six `package.loaded` stubs
per section. The difference is not convenience: under stubs, a passing rule proved only that the
stubs matched the author's guesses about which paths the rule would require. Now a passing rule is
provably calling the real surface. Each door is a plain field, so a test can retarget one of them —
including at the **real** sequencer, which is how "the button and the rule refuse identically" is
proven rather than asserted.

**The combat inconsistency is resolved, and the edge decode is load-bearing again.** `feature/combat`
publishes one record per dispatch beat and answers `targetChanged` from the **retarget packet** when
one arrived (`changedBy = 'edge'`), from its own poll otherwise. That is the field history stated
exactly: the edge is the only witness to an A→B→A switch inside one beat and the only thing that can
tell a real change from a recycled entity index, while the **beat** is the only thing that supplies
a retry — a refused command leaves the world unchanged, so the next beat tries again, where an edge
fires once and a server refusal is simply lost. Two smaller things fall out: `engagewatch` goes from
zero subscribers to exactly one (combat), and the BST Fight switch stops taking its metronome from
the *pet* service — a combat rule clocked by pet vitals, which was only ever true because that was
the sole per-beat publisher dlac shipped.

**One duplicate is knowingly left standing.** The override/sync-aware level read still exists inside
`dispatch`, `utils` and `petfood` as engine-internal copies. `S.player.level()` is the canonical
module-facing one; consolidating the other three means touching the gear engine and did not belong
in this change. Recorded here so it is a decision rather than an oversight.

**The guide gets shorter as `S` grows.** Every section that taught plumbing is now an entry with a
sentence of rationale. That is the maintenance property worth naming: adding an entry to `S` is not
a breaking change, so the door widens without a version bump, and the document shrinks toward
*reasons* and away from *recipes*.

**A missing entry is now a bug report.** If an author needs an answer that `S` does not carry, the
expected move is to say so — most entries are one line pointing at a service that already exists —
with `S.service()` as the honest interim step. Working around a gap with a private copy is the thing
hard rule 7.3 ("consume the central services") exists to prevent, and this ADR gives that rule a
place to point.
