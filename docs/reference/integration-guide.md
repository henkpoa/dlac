# Reading dlac from another addon — integration guide

**Audience:** the author (human or AI) of a *separate* Ashita v4 addon that wants dlac's
gear knowledge — what is worn, what it totals, which rule decided it — correlated live with
your own packet stream.

**Status, read this first:**

| Part | Status |
|---|---|
| **Part 1 — static data files** | ✅ **Available now.** Nothing to enable, no dlac cooperation needed. |
| **The live stream — all four kinds (`worn` / `dispatch` / `invalidate` / `confirm`) — and the five queries** | ✅ **BUILT 2026-07-28** (dlac `2026.07.28l`+). Transport verified by probe (§2.2). The player must type `/dl stream on` — off means dlac is silent on the channel, **queries included**. `dispatch` anchors carry no rule-match trace yet (additive later, on a named use); `gear`/`item`/`stats` replies carry `rev = 0` in v1 (only `sets` has a real revision so far). |
| **§7 — EXTERNAL CLAIMS, the write half: your addon claims gear slots** | ✅ **BUILT + FIELD-CONFIRMED 2026-08-01** (dlac `2026.08.01k`+, engine 162). Separate switch, `/dl claims on` — **saved**, so the player answers once; the claims themselves stay session-only. Use the shipped client shim (`addons\dlac\lib\dlacclaim.lua`) rather than hand-rolling the protocol. |

If you build the Part 1 half first you can make real progress before dlac's side exists.
Design docs behind this: `docs/design/integration-surface.md` in the dlac repo.

---

## Start here — building against dlac today (2026-07-28)

What is LIVE right now: the **`worn` stream** and the **`worn` query**. Everything
else in this document is specified and arrives additively on the same channel. The
shortest path to a working connection:

1. **Read the static data first** (§1) — catalog, statdefs, gearsets. No dlac
   cooperation needed, and canonicalise your stat-key spelling via `statdefs` from
   day one.
2. **Register one `plugin_event` handler** filtering `e.name` for `dlac_worn` and for
   your own reply channel (§2.2, §4). Decoding is one line — `local t =
   (loadstring or load)(e.data)();` — because `e.data` arrives as a ready STRING
   (probe-verified; `e` is userdata, so read named fields, never `pairs(e)`).
3. **Bootstrap with the `worn` query at load** (§3): serialize
   `return { reply = "<yourprefix>", what = "worn" }` and send it **as a byte table**
   (`{ s:byte(i) }` in a loop — the binding refuses plain strings on send).
4. **Keep a ring of received envelopes** (64 is plenty) and join your combat packets
   by `actionId` + `actionCategory`, searching backwards — never "the latest
   envelope" (§2.4; that shortcut produces plausible wrong numbers as a function of
   server latency).
5. **The player must type `/dl stream on`.** The whole channel — queries included —
   is silent until they do. Receiving nothing is a configuration state, not an
   error; say "stream off?" in your UI instead of failing quietly.
6. **Report back after your first connection.** Two things dlac's maintainer wants
   to hear: do the field names and shapes serve you as-is, and do you have a
   concrete use for the rule-match trace (which trigger rule fired, at what
   priority) on the future `dispatch` anchors — it stays off the wire until you name
   one.

**What a healthy connection looks like:** one `snapshot = true` envelope the moment
the stream comes on (or your query lands); then *silence* while nothing changes; then
bursts of `worn` envelopes with monotonically rising `seq` as the player acts. If you
receive an envelope on every idle tick, something is wrong on dlac's side — report
it. If you never receive anything: the stream is off, or you are reading the wrong
field of `e`.

---

## 0. The mental model you need

dlac is an Ashita addon that **decides and equips your gear itself**. Two facts shape
everything below:

1. **Every Ashita addon runs in its own Lua state.** You cannot call dlac's functions, read
   its tables, or share memory with it. All communication is files or Ashita's
   `plugin_event` broadcast channel. (LuaAshitacast's own `addons\luashitacast\integration.lua`
   uses that channel the same way — worth reading as a precedent.)
2. **dlac decides gear *before* your action reaches the server.** It blocks the outgoing
   action packet (0x01A), resolves the composition for that action, sends the equip packets
   (0x050/0x051), then re-injects the action. The server resolves it and your damage packet
   (0x028) arrives hundreds of milliseconds later.

Consequence (2) is the single most important thing in this document: **dlac always knows
first, and by the time you see damage, the gear has usually already changed back.** See
§2.4.

---

## 0.5 How dlac decides — the Arbiter, in ninety seconds

You will interpret this data far better knowing how it is made. Every gear decision in
dlac is ONE **arbitration**:

- **The floor: Triggers.** The player writes rules ("when I use Rudra's Storm → set
  `WS_Default`"; "when the weather matches the spell's element → this obi"). Every rule
  that matches the current moment overlays, in priority order, into one proposed
  outfit — the *floor*.
- **Claimants dress over the floor.** Independent features each CLAIM slots on every
  decision: Naked (strip everything), Pins (hand-pinned pieces), Locks (frozen slots or
  a frozen set), AutoAmmo (ammo matched to the wielded ranged weapon), MaxMP (MP
  batteries by remaining-MP band), the craft/gathering/fishing/chocobo outfits, and the
  trigger floor as the bottom row. A player-draggable **rank order** (top wins) settles
  every contested slot — "which feature owns Ammo right now" is a live question with a
  per-decision answer, and the player can reorder it mid-session.
- **The ceiling: free equip.** Slots the player told dlac to keep its hands off
  entirely. Nothing dresses through them; hand-equipped gear stays put.
- **Reservations and ladders.** Some items reserve OTHER slots while worn (a robe that
  takes Head with it). A piece only wins while its claim dominates *every* slot it
  takes; beaten, it **falls** down its set's *ladder* (the ordered candidate list it
  was flattened from) to the next eligible piece — or its slot is **held EMPTY** by
  the stronger reserver. These verdicts are the `fell` / `INELIGIBLE` / `held EMPTY`
  words you will meet inside `by` when it ships (§2.7).
- **One plan, one send.** The whole arbitration produces ONE 16-slot plan, sent to the
  client once. That plan — never a set name — is what your `worn` envelope carries,
  with the totals folded from it (§2.3 explains why a set name would be a lie).
- **One record, three renderers.** The same decision record drives dlac's own
  `/dl why` chat command, its Arbiter Monitor window, and this stream. What you
  receive is byte-for-byte the truth the player can see on screen; none of the three
  re-derives.
- **"Only push changes."** A new envelope means the outcome moved — different items,
  or a different winning claimant for some slot. No envelope means the last one still
  describes reality (§2.5). This is a design law, not an optimization, and it is why
  the `dispatch` anchor exists for actions that moved nothing.

---

## 1. Static data — available today

These are plain Lua files. `loadfile` them from your own addon; they return a table. They
ship with dlac and change only when dlac updates.

```lua
local function dlacData(name)
    local p = ('%saddons\\dlac\\data\\%s.lua'):format(AshitaCore:GetInstallPath(), name);
    local chunk = loadfile(p);
    if chunk == nil then return nil; end
    local ok, t = pcall(chunk);
    return (ok and type(t) == 'table') and t or nil;
end

local catalog  = dlacData('catalog');       -- every item's base stats (~5.8 MB)
local statdefs = dlacData('statdefs');      -- canonical stat keys + labels + aliases
local gearsets = dlacData('gearsets');      -- 126 set bonuses
local scaling  = dlacData('levelscaling');  -- items whose stats grow with level
local petmods  = dlacData('petmods');       -- gear stats granted to your PET
```

**Four traps in this data, each of which has cost dlac a bug:**

- **`catalog`'s `Slot` field lies for unimplemented items.** CatsEyeXI's `item_equipment`
  table carries rows for items that do not exist yet, with `jobs = 0` and a default
  `slot = 32`, which decodes to **Body**. `jobs == 0` is the marker for junk — **not**
  `MId == 0`, which also covers ~814 *real* modelless items. Current catalogs have these
  filtered, older ones do not.
- **`gearsets` tiers are values AT a count, not cumulative increments.** The bonus for
  wearing N pieces is `tiers[min(N, max)]`, nil below `min`. Counting is per **slot** (two
  copies of a ring count twice) and is level-gated. Summing tiers gives wrong numbers.
- **`statdefs` is the authority on stat key spelling.** `PDT`/`MDT`/`DT`/`MDMG`/`MAB`/`MACC`
  are canonical; descriptive spellings are aliases. Proc stats are labelled `"... Chance"`;
  cast speed is `"Cast Time-"`. Use `statdefs` to canonicalise before you key anything.
- **`petmods` never folds into master stats.** Those values apply to your pet, not you.

Not available as data: **augment decoding** (it is code, `feature\augments.lua`, and the id
meanings come from a private server table). Worn augments arrive already decoded on the
stream — see §2.3.

---

## 2. The live stream (specified)

### 2.1 Enabling it

The stream is **off by default** and is a **session** switch — it does not survive a logout
and is never saved:

```
/dl stream on      -- start emitting
/dl stream off     -- stop
/dl stream         -- status
```

There is also a row in dlac's Menu → Settings panel. **Your addon cannot turn it on**; the
player does. Design accordingly: if you receive nothing, say so in your UI rather than
failing silently. A job change does *not* stop the stream; a logout does.

### 2.2 Transport and decoding

Ashita's `plugin_event` is a **broadcast**. dlac raises events; every addon that registers
a handler sees all of them and filters by name. There is no subscribe call.

```lua
ashita.events.register('plugin_event', 'myparser_dlac', function (e)
    if e.name ~= 'dlac_worn' then return; end
    local t = decode(e);          -- see below
    if t ~= nil then onDlacEvent(t); end
end);
```

The payload is **the bytes of a Lua source string** of the form `return { ... }`. Rebuild
the string and load it:

```lua
local function decode(e)
    local raw = e.data or e.payload or e.eventData;   -- see the PROBE note below
    if raw == nil then return nil; end
    local s = (type(raw) == 'string') and raw or nil;
    if s == nil and type(raw) == 'table' then
        local b = {};
        for i = 1, #raw do b[i] = string.char(raw[i]); end
        s = table.concat(b);
    end
    if s == nil then return nil; end
    local chunk = loadstring and loadstring(s) or load(s);
    if chunk == nil then return nil; end
    local ok, t = pcall(chunk);
    return (ok and type(t) == 'table') and t or nil;
end
```

> **PROBED AND VERIFIED (2026-07-28):** the payload arrives as **`e.data`, already a
> STRING** (the bytes reassembled for you), with **`e.size`** carrying the length. `e`
> is **userdata** — read named fields; `pairs(e)` will not work. On the SEND side the
> binding **refuses plain strings** — serialize, then send a byte table
> (`{ s:byte(1, #s) }` built in a loop). The defensive helper above still works;
> `local s = e.data` is the verified fast path. Bonus fact: a state DOES hear its own
> `RaiseEvent`, so filter your own event names anywhere you both speak and listen.

Why Lua source rather than a packed struct: both ends are Lua, dlac already serialises this
shape everywhere, and **adding a field can never break you** — ignore keys you do not know,
and never assume the set of keys is closed.

### 2.3 The envelope

**v1 scope:** `worn` + `ctx` + **`totals`** + the metadata fields. Only **`by` is deferred**.
(You asked to skip `totals` too; dlac's maintainer overrode that — *"give him everything that
is being worn and total stats at any given time anything has changed"* — because the fold
already happens every frame for dlac's own panel, so you may as well have it and never come
back for it. Ignore the key if you don't want it.) `by` is an additive key in this same
envelope, so nothing you write now needs revisiting when it appears.

**Read this before you design your schema: a set name is not a composition, and the stream
never reports one as the answer.** dlac is not just picking a set per action. `WS_Default`
resolves differently depending on your **active modes** (they change which rules match at
all), your **level** (sets flatten per level, and a level sync re-flattens), **ladder
outcomes** (an unowned or ineligible piece falls to the next candidate), and **every other
feature contesting the same slots** — ammo automation, an MP-band manager, craft/fishing/HELM
gear, pins, slot locks, free equip. Two identical `WS_Default` weaponskills an hour apart can
be different sixteen items. So the envelope always hands you **resolved items per slot plus
the folded totals**; set and rule names appear only inside `by`, as provenance *about* an
answer that is already concrete. `ctx.modes` is there so you can group by mode in analysis,
not because you need it to interpret the items.

Every event, of every kind, has this shape:

```lua
return {
  v = 1,                        -- envelope version; refuse anything with a major you don't know
  seq = 41,                     -- STREAM-side, monotonic per session ACROSS ALL KINDS.
                                --   Gaps mean you missed events, whatever their kind (§2.5)
  decisionSeq = 38,             -- worn only: the engine's own decision number (debugging)
  kind = 'worn',                -- 'worn' | 'dispatch' | 'invalidate' | 'confirm'
  dropped = 0,                  -- events discarded by queue overflow since the last envelope
  at = 1774689871.42,           -- stamped when dlac DECIDED, not when you received it
  source = 'plan',              -- 'plan' = a decision; 'worn' = read from client memory
  snapshot = false,             -- true = a state dump you asked for, NOT a gear change
  char = 'Mindie', charId = 29909,
  dlac = '2026.07.28a', engine = 151,

  event  = 'Weaponskill',       -- which dispatch point fired (see the list below)
  action = "Rudra's Storm",     -- the spell/ability/WS name, nil for idle re-dresses
  actionId = 143,               -- THE JOIN KEY: numeric action id, straight off the 0x01A
  actionCategory = 0x07,        -- 0x03 Spell | 0x07 WS | 0x09 Ability | 0x10 Ranged
  targetIndex = 0x1A3,          -- entity INDEX from the outgoing packet (not a server id!)
  targetId = 0x…,               -- resolved server id + name when dlac can resolve them
  targetName = 'Greater Colibri',
  job = 'THF', jobLevel = 75, sub = 'NIN', subLevel = 37,

  worn = {                      -- the composition dlac decided, per slot
    Main = { id = 18264, name = "Rune Chopper",
             rec = { Level = 71, Type = 'Dagger', OneHanded = true, RSlot = 0 },
             stats = { STR = 6, Accuracy = 10 },        -- level-scaled, per item
             aug   = { stats = { STR = 5 }, labels = { 'STR+5' } },
             owned = 'ok' },                            -- 'ok' | 'stored' | 'locked'
    -- … one entry per dressed slot
  },

  -- ↓↓ NOT IN v1. Documented so you know the shape it will arrive in; it is an additive
  --    key, so ignoring it now costs you nothing later.
  by = {                        -- WHY each slot looks like that — see §2.7
    Main = { set = 'WS_Default', rule = { priority = 50, tier = 50,
                                          when = { name = "Rudra's Storm" } },
             claimant = 'Triggers' },
    Ammo = { claimant = 'AutoAmmo', over = { 'MaxMP' }, rank = 3 },
  },

  totals = { STR = 62, Accuracy = 310, ['Store TP'] = 10, ['Weapon Skill Damage'] = 6,
             setBonus = { ['Adaman Set'] = { count = 3, tier = 2, stats = { Accuracy = 10 } } } },

  ctx = { hp = 1230, hpp = 100, mp = 0, tp = 1000, status = 'Engaged', moving = false,
          modes = { DT = false, Weapon = 'Melee' },   -- the player's manual switches
          buffs = { 'Sneak', 'Haste' }, day = 'Fire', weather = 'Fire',
          dayWeatherNet = { Fire = 2 }, zone = 234, inTown = false,
          target = { name = 'Greater Colibri', id = 0x… },
          pet = nil, gameMode = 'CW', moon = 42, meritMP = 60 },
}
```

A **`dispatch` anchor** is the same envelope minus the payload — no `worn`, no `totals`,
no `by` ever. What remains is exactly the join + the moment:

```lua
return {
  v = 1, seq = 42, kind = 'dispatch', dropped = 0,
  at = 1774689872.1, source = 'plan', snapshot = false,
  char = 'Mindie', charId = 29909, dlac = '2026.07.28l', engine = 154,
  event = 'Weaponskill', action = "Rudra's Storm",
  actionId = 143, actionCategory = 0x07, targetIndex = 0x1A3,
  job = 'THF', jobLevel = 75, sub = 'NIN', subLevel = 37,
  ctx = { --[[ same shape as worn's ctx: TP at the decision, buffs, day/weather... ]] },
}
```

Read it as: *"dlac saw this action, decided, and changed nothing — the newest `worn`
before me is the composition."*

**Slot keys are exactly these, in this spelling:**
`Main` `Sub` `Range` `Ammo` `Head` `Neck` `Ear1` `Ear2` `Body` `Hands` `Ring1` `Ring2`
`Back` `Waist` `Legs` `Feet`

**`event` is exactly one of:**
`Default` `Precast` `Midcast` `Ability` `Item` `Weaponskill` `Preshot` `Midshot` `PetAction`

`Default` is the idle/ambient pass — it runs on a ~0.4 s tick and is what re-dresses you
after an action. The others are action-driven.

### 2.4 THE CORRELATION RULE — read this twice

**Join events to your packets by `actionId` + `actionCategory`, searching backwards. Never
by "the most recent envelope".**

**Is `seq` a shared namespace with game packet traffic? No.** `seq` is internal to this
stream — monotonic per session, related to nothing on the wire. Use it only to detect loss
(§2.5) and to order dlac's own events.

**But you do get a real join key, not just name-plus-timestamp.** Because dlac's engine
*blocks* your outgoing action packet (0x01A) to equip before it goes out, it has already
decoded that packet when it emits the envelope: `actionId` is the same numeric spell/ability/WS
id your incoming 0x028 carries back, and `actionCategory` is the packet's own category. Join
on integers, not on `action` strings — the name path has real hazards (the item/action API
drops possessives, and similarly-named actions exist).

Two things the numeric key does **not** solve:

- **`targetIndex` is an entity *index*, not a server id.** It comes from the outgoing packet,
  where FFXI uses indices. `targetId`/`targetName` are included when dlac can resolve them —
  but if you join an index against an id you will match nothing, silently.
- **Identity is not uniqueness.** Two Rudra's Storms in a row share an id and target, and a
  `Default` (idle) envelope has **no action at all** — `actionId` is nil. So you still search
  *backwards for the most recent match*; the numeric key removes the guessing from "match",
  not the need to search.

Here is why, for one weaponskill:

| Time | What happens |
|---|---|
| t=0 | You press the WS macro. dlac blocks the outgoing 0x01A. |
| t≈0 | dlac resolves the WS composition, sends 0x050/0x051, **emits `worn` (`event='Weaponskill'`, `seq=41`)**. |
| t≈0 | The blocked 0x01A is re-injected — the server *now* learns you WS'd. |
| t+0.4 s | The idle tick re-dresses you. **dlac emits `worn` (`event='Default'`, `seq=42`).** |
| t+0.3–3 s | The server resolves the WS. **Your 0x028 damage packet arrives.** |

Note the order of the last two rows: **the idle-restore event usually arrives before your
damage packet.** If you answer "what was worn?" by reading your latest envelope when damage
lands, you will attribute the weaponskill to the *idle set* — intermittently, as a function
of server latency, producing numbers that look plausible and are wrong.

Correct approach: keep a small ring of envelopes and look **backwards** for the most recent
one whose `event`/`action` matches the action the damage belongs to.

```lua
local ring, RING = {}, 64;      -- newest last
local function remember(env) ring[#ring + 1] = env;
    if #ring > RING then table.remove(ring, 1); end end

-- when a combat-result packet for action id N (category C) arrives:
local function compositionFor(actionId, category)
    for i = #ring, 1, -1 do                       -- newest first: most recent match wins
        local e = ring[i];
        if e.kind == 'worn' and e.actionId == actionId
        and (category == nil or e.actionCategory == category) then return e, 'exact'; end
    end
    for i = #ring, 1, -1 do                       -- nothing matched: the composition simply
        if ring[i].kind == 'worn' then             -- never changed for it -- see §2.5
            return ring[i], 'carried';
        end
    end
    return nil, 'cold';                           -- we have never seen one -- see §2.6
end
```

With `dispatch` anchors (v1 ships them — see §2.5) you can make the `'carried'` case
*positive* instead of inferred: match your `actionId` against `dispatch` envelopes too,
and take the newest `worn` before that anchor.

### 2.5 Absence, gaps, and re-syncing

- **No event means nothing changed.** dlac emits `worn` only when the composition genuinely
  moved. If your WS set resolves identically to what you are already wearing, **no `worn`
  event fires** — correctly. The previous envelope still describes reality; that is the
  fallback in the snippet above.
- **Two things can move the composition, and both emit.** `source = 'plan'` means dlac
  decided (an action fired, a mode flipped, an automation claimed) and carries provenance.
  `source = 'worn'` means **your equipment changed without dlac deciding it** — you
  hand-equipped something in a slot dlac was told to keep its hands off ("free equip"), an
  item broke, or the server stripped a piece. Those change your totals with no dispatch at
  all, so they are emitted too, with no provenance to give. If you only handled `'plan'`
  events you would compute confidently wrong stats for the rest of the fight.
- **That is why `dispatch` exists — it is your ANCHOR for no-change actions.** When an
  action goes through dlac's pipeline and the composition does *not* move, you get
  `kind = 'dispatch'`: the same envelope metadata, the same numeric join key, and `ctx`
  (TP at the moment the WS was decided — worth having), just no `worn` table. An action
  gets exactly **one** anchor: a `worn` when gear moved, a `dispatch` when it did not,
  never both. So your join is uniform and never reasons from silence: search backwards
  for the anchor matching your `actionId`; if it is a `dispatch`, the composition is the
  newest `worn` before it. (v1 carries **no rule-match trace** on `dispatch` — if you
  have a concrete use for "which trigger rules matched, at what priority", say so and it
  arrives later as additive keys, the same contract as `by`.)
- **`seq` gaps and `dropped > 0` mean you lost events.** They are two signals for two
  different failures, and you want both: **`dropped > 0`** on an envelope you *did* receive
  means dlac's own queue overflowed — we know we lost some and are telling you. A
  **discontinuity in `seq`** (you had 41, next is 44) catches everything else: your handler
  threw, you loaded late, a broadcast went missing. Either one means **re-pull, never
  interpolate.**
- **What you get back on re-sync: a fresh full `worn` envelope** at the current `seq`, with
  **`snapshot = true`**. That flag matters — a re-sync envelope is *not* a gear change. If you
  log gear changes, treating a snapshot as one records a phantom change every time you
  re-sync. Also note re-sync replies arrive on **your reply channel** (`myparser_r`), never on
  `dlac_worn`, so they cannot be confused with live events even before you read the flag.
- **`source` tells you what kind of truth you're holding.** `'plan'` = what dlac decided (the
  normal case, carries provenance). `'worn'` = read from the client's equipment memory,
  which is what a snapshot falls back to when dlac has not dispatched yet this session (fresh
  login, standing still). At rest, `'worn'` is the *more* accurate answer — it just cannot
  tell you *why* anything is on.
- **`kind = 'invalidate'`** tells you cached query results are stale. v1 watches two
  things: the **sets store** (the player edited/committed sets or a level change
  re-flattened them) and the **main job**. The envelope carries `changed` (an array of
  `'sets'` / `'job'`), `rev = { sets = <n> }` and `job`. Inventory-move invalidation is
  future work, which is also why `gear`/`item` replies carry `rev = 0` for now — do not
  cache those two hard.
- **`kind = 'confirm'` is DELTA-ONLY: silence after a `worn` IS the confirmation.** It
  exists because the server can refuse an equip (level, job, cutscene, mid-action). A
  few hundred ms after a `worn`, dlac re-reads what the client *actually* wears; **only
  if reality diverged** do you get a `confirm` — `forSeq` (the `seq` of the `worn` it
  checks), `decisionSeq`, and `delta = { Slot = { planned = ..., actual = ... }, ... }`
  for exactly the slots that differ. No `confirm` within a second of a `worn` means the
  plan landed whole. Only the *newest* plan is ever checked — a plan superseded before
  its check was moot and is silently skipped. **A `worn` envelope is dlac's intent;
  apply any `confirm` delta on top of it and you hold fact.**

### 2.6 Cold start — you are never blind, but you must ask

**If you load mid-session (player already geared, maybe already fighting), you do not get an
automatic greeting.** `plugin_event` is a broadcast with no subscribe call, so dlac cannot
detect that you loaded and has nobody to greet. Two mechanisms cover it instead:

1. **Ask once at load.** Send the `worn` query (§3). You get the current composition as a
   full envelope with `snapshot = true`. This is your bootstrap — **do not hand-roll your own
   worn-item read for it.** Yours would carry no `ctx`, no decoded augments, and would need
   its own decode of the client's packed equipment index (an id/index/container decode that
   dlac keeps behind a single door precisely because hand-rolled copies drifted).
2. **The player may enable the stream after you load.** When `/dl stream on` is typed, dlac
   immediately emits a snapshot envelope — so if the switch was off when you asked, you will
   still be handed the state the moment it comes on. Handle an unsolicited `snapshot = true`
   envelope as a valid starting point at any time, not just at your own startup.

Practical shape: ask at load, tolerate no reply (stream off), and treat the first envelope of
any kind as your baseline. If the player never enables the stream, say so in your UI —
silence here is a configuration state, not an error.

### 2.7 What `by` gives you that nothing else can

`by` is the provenance of each slot, and it is unavailable from any other source on the
client:

- `set` — the name of the gear set that dressed the slot.
- `rule` — the trigger that matched: its conditions, its `priority`, its specificity tier,
  and which `case` matched if it had any.
- `claimant` / `over` / `rank` — dlac has a priority ladder of features that can dress slots
  (pins, slot locks, AutoAmmo, an MP-band manager, craft/HELM/fishing/chocobo gear, and the
  trigger overlay as the floor). This tells you which one won the slot and over whom.
- Reservation outcomes — some items take another slot away while worn (a robe reserving
  Hands, a boomerang reserving Ammo). If a piece was refused for that reason and dlac fell
  to the next candidate, `by` says so.
- Slots held by the player's own locks, by "free equip" (slots dlac was told not to touch),
  or by a strip.

For a parser this is the difference between *"he had 310 accuracy"* and *"he had 310
accuracy because his WS rule at priority 50 beat his idle rule, except Ammo, which AutoAmmo
took"*.

---

## 3. Asking for gear and gear sets (specified)

For anything not on the stream — reference data, and hypotheticals — you ask. The pattern is
LuaAshitacast's: **you supply the reply channel.**

```lua
local function ask(what, extra)
    local q = { reply = 'myparser', what = what };
    if extra then for k, v in pairs(extra) do q[k] = v; end end
    local src = serialize(q);                       -- 'return { reply = "myparser", … }'
    AshitaCore:GetPluginManager():RaiseEvent('dlac_query', toBytes(src));
end

-- replies arrive on '<reply>_r', decoded exactly like a stream envelope
ashita.events.register('plugin_event', 'myparser_reply', function (e)
    if e.name ~= 'myparser_r' then return; end
    local t = decode(e);  -- { v, what, rev, data }
end);
```

Pick a `reply` prefix unique to your addon; two consumers must not collide.

| `what` | Extra fields | `data` you get back |
|---|---|---|
| `worn` | — | one `worn` envelope for the current composition (use after a `seq` gap) |
| `gear` | — | the character's owned-gear record: id, name, level, type, and per-item augments |
| `sets` | `job` | that job's set **names**; add `set = '<name>'` for one set **resolved** to concrete items plus its `totals` |
| `item` | `id` or `name` | one item: catalog record, whether it is owned/available/stored, and augments if a copy is worn |
| `stats` | `comp = { Head = 'Walahra Turban', … }`, optional `level = <n>` | **folded totals for a composition you invent** — level scaling, augments and set bonuses included |

`stats` is the important one for analysis: it lets you ask *"what would these numbers be
with a different ring"* without reimplementing level scaling, augment folding and set-bonus
tiers. Those three are subtle enough that dlac itself centralised them behind a single door
specifically to stop its own modules from getting them subtly different.

**Every reply carries `rev`.** Cache `gear` and `sets`; re-ask only when an `invalidate`
event reports a newer `rev`. Do not poll.

A `sets` reply for one resolved set looks like:

```lua
return { v = 1, what = 'sets', rev = 17, data = {
    job = 'THF', set = 'WS_Default',
    slots  = { Main = { id = 18264, name = 'Rune Chopper', … }, … },
    totals = { STR = 62, Accuracy = 310, setBonus = { … } },
} }
```

---

## 4. A minimal consumer, end to end

```lua
local RING, ring = 64, {};
local rev = { gear = nil, sets = nil };

local function onEnv(env)
    if env.v ~= 1 then return; end                       -- unknown major: ignore, don't guess
    if env.kind == 'invalidate' then
        if env.rev and env.rev.sets ~= rev.sets then rev.sets = env.rev.sets; ask('sets'); end
        return;                                          -- (gear/item revs are v2 -- see §2.5)
    end
    if env.dropped and env.dropped > 0 then ask('worn'); end   -- we lost some: resync
    ring[#ring + 1] = env;                               -- worn AND dispatch anchors both go in
    if #ring > RING then table.remove(ring, 1); end
end

ashita.events.register('plugin_event', 'myparser_dlac', function (e)
    if e.name == 'dlac_worn' or e.name == 'dlac_dispatch'
    or e.name == 'dlac_invalidate' or e.name == 'dlac_confirm' then
        local t = decode(e); if t then onEnv(t); end
    elseif e.name == 'myparser_r' then
        local t = decode(e); if t then onReply(t); end
    end
end);
```

Everything else is your own packet handling joined against `ring` by §2.4.

---

## 5. Gotchas, in the order they will bite you

1. **The stream is off until the player types `/dl stream on`.** Show that in your UI;
   silence is a configuration state, not an error.
2. **The payload field name is unverified** (§2.2). Probe defensively.
3. **Never use "the latest envelope" at damage time** (§2.4). This is the bug that produces
   confidently wrong numbers, and it fails as a function of server latency, so it will look
   fine while you are testing on a dummy.
4. **`targetIndex` is an entity index, not a server id** (§2.4). Joining one against the other
   matches nothing, silently.
5. **`snapshot = true` is not a gear change** (§2.5). Logging it as one records phantom
   changes on every re-sync.
6. **You get no greeting on load — ask** (§2.6). And be ready for an unsolicited snapshot at
   any time, because the player can enable the stream after you start.
7. **Absence of an event is information, not a dropped packet** (§2.5).
8. **A `worn` envelope is intent, not fact** — but `confirm` is delta-only (§2.5): no
   `confirm` shortly after a `worn` means the plan landed whole. Waiting for a positive
   confirmation that never comes is the wrong loop; apply deltas when they arrive.
9. **Do not assume the key set is closed.** Fields will be added (`by` and `totals` first).
   Ignore what you do not know; never validate by rejecting unknown keys.
10. **Stat key spelling comes from `statdefs`** (§1), not from your intuition.
11. **`at` is a decision-time stamp from dlac's clock**, not your receive time. Use it for
    ordering dlac's own events; use your own clock for your packets.
12. **Everything above is read-only.** Sections 1–4 cannot make dlac do anything. If you
   want to *dress* the player, that is §7 — a different channel, a different switch, and
   still no writer for sets, triggers or modes.

---

## 6. What dlac will not give you

**Damage math.** pDIF, weaponskill first-hit accuracy behaviour, and the mob
evasion/accuracy chain are researched in the dlac repo as *documentation*, and partly
implemented on a parked branch, but they are not shipped and are not on this channel. dlac
gives you gear truth, decision truth and world context — the correlation keys. The damage
model is yours.

**Anything about other players.** dlac reads your own character.

If you need a field that is not here, say which one and why: this surface deliberately sends
**complete records rather than curated fields**, precisely so that most new needs turn out
to be something you were already being sent.

---

## 7. External claims — making dlac wear something (2026-08-01)

Everything above is dlac *telling you* things. This section is the other direction: your
addon asks dlac to **wear specific gear in specific slots**, and dlac's Arbiter settles that
against everything else contending for the same slots.

**The mental model, and it is the whole section:** a Claim in dlac is just
`{ [SlotKey] = itemName }`. Your addon becomes one more claimant on a list the player
controls, alongside their pins, slot locks, ammo rule, MP batteries and craft/fishing gear.
You are not driving dlac's equip path; you are *filing an opinion* and the player's rank
order decides what happens to it.

### 7.1 Do not hand-roll this — load the shim

```lua
local ok, mk = pcall(loadfile,
    AshitaCore:GetInstallPath() .. 'addons\\dlac\\lib\\dlacclaim.lua');
local dlac = (ok and mk ~= nil) and mk().new({ id = 'myaddon', label = 'My Addon', ttl = 10 }) or nil;

dlac.onAck     = function(t) end        -- every reply to something you sent
dlac.onVerdict = function(d) end        -- d.lost = { Slot = 'WhoBeatYou' }
dlac.onExpired = function(d) end        -- your claim is gone; d.reason says why

dlac:hello();                                            -- is dlac there, is the switch on
dlac:claim({ Head = 'Walahra Turban', Ammo = 'remove' });  -- 'remove' = hold the slot EMPTY
dlac:release();

ashita.events.register('d3d_present', 'myaddon_dlac', function() dlac:pump(); end);  -- REQUIRED
```

`lib\dlacclaim.lua` ships with dlac and is the one file in it written to be loaded from a
foreign Lua state. It owns the wire format, the byte-table send, the reply channel and the
lease renewal. The raw protocol is documented in 7.4 for the curious, but the shim is the
supported door — if the wire changes, the shim absorbs it.

### 7.2 The four things that will surprise you

**1. The player owns a switch, and it is not the stream's.** Nothing works until they type
`/dl claims on` (or tick *"Let other addons claim gear"* in Menu → Settings). Reading gear
and dressing the player are separate consents on purpose, so `/dl stream on` does **not**
enable this. `hello` is answered even while the switch is off — precisely so your UI can
say *"dlac is here, claims are off"* instead of failing silently. Never nag, and never
re-file a claim the player just turned off.

The switch is **saved** and survives logout; the **claims are not**. A logout clears every
claim and leaves the permission standing, so plan to re-file when your own conditions are
met again — not blindly at character select. You never have to guess which happened:
`data.on` on the `expired` push is the switch state, sent explicitly.

**2. Your claim is a LEASE.** Every one of dlac's own claimants dies when dlac dies; yours
does not. So a claim carries a TTL (default 10 s, max 300) and must be renewed — `pump()`
does it for you at a third of the lease. Stop pumping — crash, unload, forget — and dlac
drops your claim on its own and restores the player's gear. This is not a permission wall;
it exists because a foreign holder can *vanish*, and gear stuck with nobody to blame is the
worst outcome for the player.

**3. Being accepted is not being worn.** You ship at the **`External` rank, directly above
the player's Triggers floor** — you dress over their trigger sets and under everything they
configured themselves, until *they* drag you higher in Gear Helpers → Claim Priority. When
a senior claimant takes one of your slots you get a `verdict` push naming who beat you
(`onVerdict`), once per change rather than once per dispatch. Slots withheld by the Locks
veto or the Disabled ceiling do not appear there — they show up as *claimed but not worn*
on the `worn` stream (§2), which is the fact-check for everything in this section.

**4. Claim, never Commit.** There is no writer here for sets, triggers, modes or lockstyle
boxes, and there will not be one. A claim is session-only and touches none of the player's
files.

Two smaller ones worth knowing. **A claim REPLACES your previous one** — one claimant, one
table; send the whole thing every time.

And **several external addons can claim at once.** They share the one `External` row, so
between themselves the higher `prio` wins a contested slot, ties broken by id ascending
(deterministic, never table order). Two consequences:

- **Being shadowed by a peer is not a refusal.** Your claim is accepted and your lease is
  live; the moment the winner releases or its lease lapses you take the slot, with no round
  trip. That is why the ack says `ok`.
- **You are still told.** A slot taken by a peer arrives on the same `verdict` push as a
  slot taken by one of dlac's claimants — the value is whichever *won*, so it is either a
  dlac claimant identity (`Pins`, `MaxMP`, …) or another addon's `id`. Do not assume it is
  one or the other: they want opposite responses. Losing to a dlac claimant is the
  player's Claim Priority drag to settle; losing to a peer is `prio`, and never appears in
  that list at all.

### 7.3 What dlac deliberately does not do

**It never asks you anything.** dlac decides gear inside a blocked outgoing packet, and it
will not call out to another addon's Lua from there — your crash or your slow frame must
never become the player's gear bug. Your claim is a *standing* table read from cache on
every decision, exactly like the ammo rule's.

The consequence, stated plainly: **a reactive claim is one action late.** You learn an
action happened from the `dispatch`/`worn` anchor (§2.4), which arrives *after* the gear for
that action was already chosen. If you want gear on for an action, claim it *before* the
action — or use the claim → verify → act shape, which is what dlac's own Job helpers do.

### 7.4 The raw protocol (v1)

Inbound event `dlac_claim`, payload `return { ... }` as a byte table, replies on
`<reply>_r` — the same encoding, decoding and reply-channel convention as §2/§3.

| `what` | Fields | Answer |
|---|---|---|
| `hello` | — | `{ protocol, on, dlac, ttlDefault, ttlMax, claimant, maxClaimants }`. Answered even while the switch is off. |
| `claim` | `slots` (required), `prio`, `ttl`, `label` | `ok` + the canonicalised `slots`, the granted `ttl` and `ttlClamped` if it was clamped |
| `release` | — | `ok`, `released` |
| `heartbeat` | — | `ok`, `expiresIn` — refuses if the lease already lapsed, so re-claim |
| `status` | — | your claim + every other holder (`id`, `label`, `prio`, slot count) |

Every request needs `id` (your identity *and* your lease key) and `reply` (your channel).
Unsolicited pushes arrive on the same channel: `verdict` — `data.lost = { Slot = <winner> }`
where the winner is a dlac claimant identity **or another addon's id**, or
`data.held = true` for the all-clear — and `expired`, carrying `data.reason` (`lease
lapsed` / `logout` / the player switching claims off) and **`data.on`, the switch state**,
so permission is never something you infer from a reason string. Verdicts are pushed once
per *change*, not per decision.

Slot keys are the sixteen in §2.3 and are matched **case-insensitively** — send `head`, get
`Head`. Every refusal is a named sentence, never silence: an unknown slot names the slot,
a bad item names the slot, the claimant cap names the cap. If you get nothing back at all,
dlac is not loaded — that is the only silent case.

### 7.5 Testing yours against it

**`addons\dlac\examples\claim-example\`** ships with dlac: a complete, runnable addon built
on this exact shim, with a README written for whoever is doing the integration — human or
AI — and commands for the four things worth checking. A claim landing; a claim *losing* to
a senior claimant (and winning once the player drags the row up); the lease expiring after
`/claimex die` simulates a crash; and two external identities contending for one slot.

Copy the folder to `<Ashita>\addons\claim-example\` to run it (Ashita only loads addons
from its own `addons\` directory). Read `README.md` for the model, then the .lua top to
bottom — steps 1–4 are marked in the source. Between them they are enough to build a
correct integration without reading dlac's source at all.
