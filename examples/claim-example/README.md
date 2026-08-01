# claim-example — a third-party addon claiming gear through dlac

A complete, runnable Ashita addon that asks dlac to wear specific gear in specific slots.
It is the worked example for **[integration-guide §7](../../docs/reference/integration-guide.md)**
(the contract) and for **`addons/dlac/lib/dlacclaim.lua`** (the client shim it uses).

**Audience: whoever is writing the integration — human or AI.** If that is you, read this
file, then `claim-example.lua` top to bottom. Between them they contain everything needed
to build a correct integration without reading dlac's source.

---

## Run it

```
copy this folder to  <Ashita>\addons\claim-example\
/addon load claim-example
/dl claims on                        <- the PLAYER's switch; nothing works without it
/claimex hello                       <- is dlac there, is the switch on
/claimex claim head Walahra Turban
/dl why                              <- the "Other addons" row won (or lost) the slot
/claimex release
```

> The canonical copy of this example lives in the dlac repo, at
> `addons/dlac/examples/claim-example/`. Ashita only loads addons from
> `<Ashita>\addons\<name>\<name>.lua`, so running it means copying the folder there.
> If you edit the repo copy, copy it across again — there is no link between them.

---

## The model, in one page

**dlac decides and equips your gear itself**, and every Ashita addon runs in its own Lua
state. Two consequences shape everything:

1. **You cannot just equip the item.** dlac would take it back off on its next decision,
   and the two of you would fight, every frame, forever.
2. **You cannot call dlac's functions.** Separate states. All communication is Ashita's
   `plugin_event` broadcast (or files on disk).

So instead you **file a Claim**: *"I would like these slots to hold these items."* dlac
merges your claim with everything else contending for those slots — the player's pins, slot
locks, ammo rule, MP batteries, craft/fishing gear, and their trigger sets — and a priority
order **the player controls** settles every contested slot.

A Claim is literally `{ [SlotKey] = itemName }`. That is the whole data model. `'remove'`
as the item claims the slot **held empty**.

### Where you sit

You ship at the **`External` rank — directly above the player's Triggers floor**. You dress
over their trigger sets and under everything they configured themselves, until *they* drag
"Other addons" higher in **Gear Helpers → Claim Priority**. That is deliberate: a foreign
addon should not silently outrank a player's own settings, and moving it is a decision only
they can make.

Every external addon shares that one row. Between yourselves, higher `prio` wins a
contested slot, ties broken by `id` ascending.

---

## The five things that will bite you

### 1. The player owns a switch, and it is not the stream's

Nothing works until they type `/dl claims on` or tick *"Let other addons claim gear"* in
Menu → Settings. `/dl stream on` (the read-only gear feed) does **not** enable this —
reading someone's gear and dressing them are different consents.

The switch is **saved**; the **claims are not**. A logout clears every claim and leaves the
permission standing.

`hello` is answered **even while the switch is off**, precisely so your UI can say
*"dlac is here, claims are off"* instead of failing silently. Silence means dlac is not
loaded — that is the only silent case.

### 2. Your claim is a lease

A claim carries a TTL (10 s default, 300 max) and must be renewed. `pump()` does it for
you; call it every frame. **Stop pumping — crash, unload, forget — and dlac drops your
claim and restores the player's gear.**

This is not a permission wall. It exists because an addon in another state can *vanish*,
and gear stuck on with nobody to blame is the worst possible outcome for the player. Try
`/claimex die` to watch it work.

### 3. Being accepted is not being worn

`claim` returning `ok` means *your opinion was recorded*, not *the item is on*. The Arbiter
then settles the slot and you may lose it. Two ways, and they want **opposite** responses:

| You lost to | What it means | What fixes it |
|---|---|---|
| A dlac claimant (`Pins`, `MaxMP`, `Locks`, `Naked`, …) | The player ranked that feature above external addons | The player drags "Other addons" up. **Not yours to fix.** |
| Another addon's `id` | A peer outranked you on `prio` | Raise your `prio` — this never appears in the player's list |

`onVerdict` tells you which, per slot; `d.held == true` is the all-clear. Being shadowed by
a peer is **not** a refusal: your claim stays live and takes the slot the instant the winner
releases or lapses.

### 4. Claim, never Commit

There is no writer here for sets, triggers, modes or lockstyle boxes, and there will not be
one. A claim is temporary and touches none of the player's files.

### 5. dlac never asks you anything

Your claim is a **standing table**, read from cache on every gear decision — dlac does not
call out to your addon mid-decision and does not wait for you. Your crash or your slow
frame can never become the player's gear bug.

The consequence, stated plainly: **a reactive claim is one action late.** You learn an
action happened *after* the gear for it was chosen. If you want gear on for an action,
claim it *before* the action.

---

## The law worth carrying into your own addon

> **At every point where something takes a slot, ask: how would the losing addon find out?**

This channel's first field round produced three bugs, and all three were the same failure
wearing different clothes — *the addon believing it held a slot it did not*:

- the inbound listener did not exist until dlac's first gear decision, so an addon that
  claimed before that was answered by nobody;
- the verdict join matched slot keys case-sensitively, so a claimant that spelled slots the
  other way was reported as **no winner at all** rather than the wrong one;
- a claim shadowed by another external addon was never reported, because that contest is
  settled before the Arbiter sees anything.

None of them was findable by checking whether the gear was right. The gear was right every
time. Handle `onVerdict` and `onExpired`, and never read silence as *"I still hold it"*.

---

## What each command demonstrates

| Command | What it proves |
|---|---|
| `hello` | Presence and permission are separate, and both are knowable |
| `claim <slot> <item>` | The happy path; slot keys are case-insensitive on the way in |
| `empty <slot>` | You can claim a slot **held empty**, not just claim an item into it |
| `drop` / `release` | A claim replaces the previous one; release is the polite exit |
| `status` | Every holder, including your peers |
| `who a\|b`, `prio` | Two external addons contending, and the loser being told |
| `die` / `live` | The lease — a crash, without needing to crash |
| `bad` | Every refusal is a **named sentence**, never silence |

---

## Files

| File | What it is |
|---|---|
| `claim-example.lua` | This addon. Commented as a walkthrough; steps 1–4 are marked. |
| `../../lib/dlacclaim.lua` | The client shim you load. Read its header for the API. |
| `../../docs/reference/integration-guide.md` | The full contract — §7 is claims, §1–§6 are the read-only half (gear stream, queries, static data). |

If you need something the protocol does not offer, say which and why. The surface
deliberately sends complete records rather than curated fields, so most new needs turn out
to be something already on the wire.
