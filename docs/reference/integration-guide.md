# Reading dlac from another addon — integration guide

**Audience:** the author (human or AI) of a *separate* Ashita v4 addon that wants dlac's
gear knowledge — what is worn, what it totals, which rule decided it — correlated live with
your own packet stream.

**Status, read this first:**

| Part | Status |
|---|---|
| **Part 1 — static data files** | ✅ **Available now.** Nothing to enable, no dlac cooperation needed. |
| **The `worn` stream + the `worn` query** | ✅ **BUILT 2026-07-28** (dlac `2026.07.28k`+). Transport verified by probe (§2.2). The player must type `/dl stream on` — off means dlac is silent on the channel, **queries included**. |
| **`dispatch` / `invalidate` / `confirm` + the other four queries** | 🔧 **Specified, not built yet.** Code written against them receives nothing until they land — additive, on the same channel. |

If you build the Part 1 half first you can make real progress before dlac's side exists.
Design docs behind this: `docs/design/integration-surface.md` in the dlac repo.

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
  seq = 41,                     -- monotonic per session. Gaps mean you missed events (§2.5)
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
- **`kind = 'invalidate'`** tells you cached query results are stale (job change, the player
  committed set/trigger edits, inventory moved) and carries the new `rev` values.
- **`kind = 'confirm'`** arrives a few hundred ms after a `worn` and reports what the client
  *actually* ended up wearing. It exists because the server can refuse an equip (level, job,
  cutscene, mid-action). **A `worn` envelope is dlac's intent; a `confirm` is fact.** If you
  are computing anything you would defend to another player, prefer `confirm` where you have
  it.

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
| `stats` | `comp = { Head = 'Walahra Turban', … }` | **folded totals for a composition you invent** — level scaling, augments and set bonuses included |

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
        if env.rev and env.rev.gear ~= rev.gear then ask('gear'); end
        return;
    end
    if env.dropped and env.dropped > 0 then ask('worn'); end   -- we lost some: resync
    ring[#ring + 1] = env;
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
8. **A `worn` envelope is intent, not fact** — prefer `confirm` when correctness matters.
9. **Do not assume the key set is closed.** Fields will be added (`by` and `totals` first).
   Ignore what you do not know; never validate by rejecting unknown keys.
10. **Stat key spelling comes from `statdefs`** (§1), not from your intuition.
11. **`at` is a decision-time stamp from dlac's clock**, not your receive time. Use it for
    ordering dlac's own events; use your own clock for your packets.
12. **You are read-only.** There is deliberately no way to make dlac equip, write a set, or
   change a trigger through this channel. If you need that, it is a different conversation
   with a different design (a dlac *plugin*, currently designed and parked).

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
