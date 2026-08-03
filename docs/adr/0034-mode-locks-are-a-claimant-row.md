# A mode lock is a claimant row, not a trigger special case

Henrik, 2026-08-03: *"It is a very common problem when building sets that you want
to 100% lock a piece over every set once a mode is active. REGARDLESS what happens,
this piece MUST ALWAYS stay on. I have a caster mode where I switch weapons all the
time to adapt to elemental damages, refresh as well as resting. But when I am in
melee mode, I NEVER want the weapons to be touched."*

Today the only way to say that is to teach **every rule in the file** to keep its
hands off Main/Sub — a `mode = Weapon:Melee` gate on every weapon-touching rule, and
one you have to remember again for every rule you add afterwards. The thing being
expressed is a property of the **mode**, so it belongs on the mode.

## The decisions

**A mode definition carries its locks, keyed by the `mode` CONDITION string.**

```lua
Modes = {
    ["Weapon"] = { values = { "Melee", "Caster" },
                   locks = { ["Weapon:Melee"] = { Main = "MeleeWpn", Sub = "MeleeWpn" } } },
    ["DT"]     = { locks = { ["DT"] = { Body = "DTSet" } } },
}
```

The key repeats the mode's own name, which is redundant, and buys two things worth
more than the redundancy. The activity test becomes `M.modeActive(key)` — the same
tested primitive the rules use, rather than a second dialect of *"is this mode on"*.
And a hand-editor reads the key without having to know which mode's table they are
looking at.

Storing it **inside the definition** is what makes the ADR 0019 cascade free: delete
the mode, or drop a cycle value, and its locks go with it, because they are the same
table. A separate store would have been a third reference home for that cascade to
remember — and ADR 0019 exists precisely because the second one got forgotten once.

**It is an ordinary claimant (`ModeLock`), not a floor special case.** Henrik's
phrasing was *"on a trigger level"*, and a floor-internal override would have matched
it. A rank row is behaviourally identical for everything except the other claimants,
and it costs less code: the Arbiter Monitor grid, the `/dl why` contest, the Priority
list, the decision ring and the fall-down-its-own-ladder behaviour all arrive with no
new code in any of them, because they are all driven by the registry.

It also converts the one genuine open question — *should a mode lock beat an armed
craft bench?* — from a ruling into a drag. The answer ships as **directly above
`External`**: above every trigger rule and above a foreign addon's claim (it is the
player's own explicit "never touch this"), below every activity they armed themselves
this session. Arming the craft bench is a deliberate act too, and the one that
happened later. A player who disagrees drags the row.

**Claims on EVERY event.** Pins' and Naked's reason: a lock that let go during a cast
would not be a lock, and surviving the Midcast rule is the exact case it exists for.

**A lock naming a set with no entry for its slot claims NOTHING.** There is no answer
to give, so the trigger floor keeps the slot. That is a lock which silently does
nothing — this feature's whole failure mode — so the Mode Locks window flags it in
red at edit time, which is the only place it can still be fixed. Blanking the slot
instead would be worse: it would strip a piece to honour an instruction the player
never actually gave.

**Two active modes CAN name one slot,** because a `DT` toggle and a `Weapon` cycle are
independent flags. Henrik's ruling (2026-08-03, after the first cut shipped): *"first
come, first serve — the one who took the slot lock first should get it, the rest stand
in queue basically."*

The first cut resolved this by sorted condition. Deterministic, but the alphabet is not
fairness: `DT` beating a Weapon cycle that had held the slot for an hour is exactly the
arbitrary answer that ruling rejects. So modes carry an **activation clock** — one
counter per mode name, stamped when its flag last *changed* — and the plan walks
conditions in that order.

Three properties, each of which is a decision:

- **Stamped on change, never on re-assertion.** A macro that re-asserts a mode every
  pull must not send it to the back of the queue. Cleared when the mode goes off,
  because turning it back on genuinely *is* taking the slot again.
- **A cycle value change re-stamps.** The lock is keyed by condition, so
  `Weapon:Melee` → `Weapon:Caster` really is a different lock taking the slots.
- **The queue needs no state.** The plan is rebuilt every dispatch, so when the holder's
  mode goes off the next in line simply wins the next walk. Nothing remembers a queue,
  and nothing has to be re-armed — which is the only reason "the rest stand in queue"
  can be true without a queue existing.

Equal stamps still break alphabetically (two flags restored from one mirror, or seated
by one trigger load): deterministic first, fair second, because a `pairs()` coin flip
landing differently on two dispatches with nothing changed is a worse bug than an
arbitrary-but-repeatable winner.

The clock rides the modestate mirror as `__seq`. Without that the Mode Locks window —
which computes the same plan in the other Lua state — would order a contested slot
alphabetically while the engine ordered it by the clock, and name the wrong winner.
Every flag write goes through one seam (`M.modeSet`) so the stamp cannot be forgotten at
one of the six assignment sites.

## Consequences

Three surfaces now say who holds a slot — the Mode Locks window, the Trigger Monitor
and the Priority row — and all three ask `dispatch.modeLockPlan` through triggersui's
one addon-state door. A second copy of *"who holds this slot"* is exactly how two
windows start disagreeing.

The Trigger Monitor gains a `locks` line and a `MODE LOCK holds Main,Sub` suffix on a
fired rule whose set names a held slot. That monitor's altitude is what the trigger
layer **proposed**, and a locked slot is precisely a proposal that will not be
honoured — so it belongs there, not only in the Arbiter Monitor.

**The queue has to be visible where the player already is** (Henrik: *"where do I see the
queue for the mode lock?"*). It shipped in exactly one place — the Mode Locks window,
which is the surface you are *least* likely to be looking at while playing. Both monitors
named only the winner, so a slot doing something surprising gave no hint that another
active mode was waiting behind it: the same invisibility the loser list existed to
prevent, moved one level up.

So the queue **rides the decision record** (`contest.mlq`, captured at ensure time through
the one door `modeLockLive`, which stashes it beside the plan). The Arbiter Monitor renders
stashed records — pinned historical ones included — and deriving the queue live there would
show *today's* answer under a decision from ten minutes ago. Same law as the ladders and
the reserve verdict: the queue that decided is the queue you read.

It is also a **signature leg**, for the rank-order leg's reason (v152): a mode that queues
moves no gear and no claim, so without it the trace and `/dl why` would keep saying nobody
waits until something unrelated happened to move.

It deliberately does **not** enter the decision fingerprint. The ring appends on a moved
*outcome*, and a queue-only record with zero changed slots is the v163 symptom, not a
feature — so a queue that forms while nothing moves reaches `/dl why` immediately and
reaches the ring on the next real decision.

Mode locks deliberately do **not** ride the Mode library (`gear/modeslibrary.lua`).
A library entry is job-independent; set names are not. Stamping `Weapon` onto another
job would carry set names that job has never heard of — the cross-job breakage ADR
0019 already worried about, in a form the cascade cannot clean up.

**But "does not travel" must not mean "gets eaten".** `applyStamp` rebuilds the target
definition from the plan, so on the first cut a stamp silently deleted the receiving
job's locks — including on **Append**, the branch whose entire promise is *"no value
disappears, so no reference can break"*. Locks belong to the **job**, not to the entry:
they are carried across the stamp untouched. The one exception is an **Overwrite that
kills a cycle value** — that value's locks go with it, which is the ADR 0019 cascade in
the single place it is *not* free, because here the definition survives with a shorter
value list instead of being deleted outright (`ML44a`–`ML44f`).

**Profile export/import already carries them,** with no change: `filterTriggersRaw` takes
the whole `Modes` table, and locks live inside it.

**A mode lock is a set reference, and the export form now knows it.** `triggerRefs` only
walked handler rules, so exporting Modes without Sets shipped locks pointing at sets the
receiver does not have — no warning, no disabled row, the exact silent-dead-data class
that analysis exists to prevent. It reports `modeSets` as its **own** answer rather than
folding into `sets`, and the gate lands on the **Modes** row, not Triggers: a lock travels
with the Modes section and Triggers need not be selected at all, so gating Triggers would
have disabled something unrelated while leaving the real hole open. Same strength as a
rule's `set =` — disabled, not warned (Henrik's call): a dead rule merely fails to fire,
while a dead lock holds nothing and reads as the feature being broken. When a blocked
Modes row is *also* what the triggers need, the Triggers row names **Sets** — the root
fix — instead of pointing at a row that is itself pointing back (`PX9a`–`PX9g`).
