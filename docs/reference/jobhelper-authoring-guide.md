# Writing a Job helper module — authoring guide

**Audience:** the author (human or AI) of a **Job helper** module for dlac — a drop-in folder
that performs a job's own actions for the player (pet commands, ability use) in the situations
they configured. This is the reference for the module contract *as shipped*: everything here is
checked against the code in `feature/jobhelpers.lua`, `feature/actionseq.lua` and the first real
module, `jobhelpers/bst/bst-helper/`. You should not need to read dlac's source to build a
working module.

**Sibling document:** [integration-guide.md](integration-guide.md) — how a *separate* addon reads
dlac from its own Lua state. That is the other side of the wall. A Job helper is **not** that:
it is first-party dlac code, running **inside** dlac's Lua state, with direct calls to everything
below.

**Vocabulary.** Every bolded term below is defined once, in [CONTEXT.md](../../CONTEXT.md), and
deliberately not restated here — **Job helper**, **Gear helper**, **Action sequence**,
**Engage/target edge**, **Pet vitals**, **Pet-loss edge**, **Retry lockout**, **Claim**,
**Arbiter**, **Ladder**, **Statefile**, **Setting**, **Free equip**, **Naked**. Read that file
first; this guide assumes those meanings exactly and will not survive being read with synonyms
substituted.

| Part | Status |
|---|---|
| **The module contract** (`api = 1`, folder anatomy, hooks, containment) | ✅ **Shipped** — issue #137, ADR [0028](../adr/0028-job-helper-modules.md). |
| **The Action sequencer** and the shared `JobHelper` claimant row | ✅ **Shipped** — issue #138, ADR [0030](../adr/0030-module-owns-initiation.md). |
| **Engage/target edges**, **pet vitals** + the pet-loss edge, **ability recasts** | ✅ **Shipped** — issues #139 / #140 / #141. Rows in architecture.md's *Central services* table. |
| **Hot-plugging**, capability tiers, sandboxing | ❌ **Not coming.** Modules appear on addon (re)load; the door is documentation and contracts, not walls (ADR 0028). |

---

## Start here — the shortest path to a working module

1. **Pick your folder.** `addons\dlac\jobhelpers\<job>\<module>\` — the job folder groups, the
   **module folder is your identity and your unit of approval**. Lower-case, hyphenated:
   `jobhelpers\bst\bst-helper\`.
2. **Write `init.lua`** returning the contract table (§2). The minimum that loads is
   `{ api = 1, label = '...', jobs = { 'BST' }, panel = function(ctx) end }`.
3. **`/addon reload dlac`.** There is no hot-plug. Your module appears as one row under its job's
   section on the **Job Helpers** tab; `/dl check` counts it. If it was refused, you get one loud
   chat line naming your folder and the reason (§4).
4. **Store your settings in your own per-character file** (§5) — never in Profiles, never in the
   framework's file.
5. **Consume the central services** (§6) rather than opening a rival scanner, reader or client.
6. **Act only through an Action sequence** when the act needs gear or ammo worn first (§6.1) —
   never equip anything yourself (§7.1).
7. **Read §7 before you ship.** Those five rules are what make a module approvable and what keep
   one broken module from being everybody's problem.

**What a healthy module looks like from the outside:** a row with a pill on the Job Helpers tab;
a Panel that explains itself; *silence* in chat while everything works; exactly one line when it
refuses to act, naming the blocker; and nothing at all happening when the player is on another
job, in town, dead, zoning, or has the pill off.

---

## 0. What a Job helper is — and what it is not

dlac's base story is that it **only equips gear**: a **Gear helper** picks equipment, the player
still casts, crafts, fishes and digs. A **Job helper** is the deliberate counterpart — it *acts*.
The two must never be conflated, because the "only equips gear" line is what the Gear Helpers
wording promises a GM, and it stays true only because every action-performing behavior lives in a
module rather than in dlac core.

That is also why modules exist at all, and it is the one thing to understand before writing one:

> **One module folder = one row on the Job Helpers tab = one unit of server approval.**

CatsEyeXI staff approve action-performing addons **individually** — the precedent is the approved
Pup-Helper addon. Your folder is what a GM reads, evaluates and approves; it is not a
sub-feature of dlac's approval, and dlac's approval is not yours. Practical consequences:

- **Everything your module does must be legible from your folder alone.** A reviewer should not
  have to read dlac to see what commands you issue and when.
- **Keep the folder separable.** Your data, your settings file, your rules. If removing your
  folder leaves anything behind that still acts, the boundary is broken.
- **Do not widen your envelope quietly.** A module approved as "sends the pet in" that later also
  spends items is a different approval request. New acts, new request.

### The naming law — binding on authors

Player-facing text names **helpers and rules**, never "Auto \<activity\>". The word *automation*
was retired as user-facing wording on 2026-07-28 after a GM read "Auto \<activity\>" as *the addon
performs the activity for you*. That reading is now literally true for Job helpers, which makes
the naming law tighter here, not looser: name what the rule *is*, not what it does for you.

| ❌ Never | ✅ Instead |
|---|---|
| `Auto Reward`, `AutoPet`, `Auto Fight` | `Reward`, `Fight`, `Resummon` — the act's own name |
| "Automatically rewards your pet" | "Reward my pet when it drops low" — the player's rule, in their words |
| A switch labelled "Automation" | A switch labelled for its condition |

The split that makes this workable is the same one the Arbiter uses: an **identity** (internal,
persisted, never shown — your folder name) versus a **display label** (`label`, the only string a
player sees). Internal names may be anything; `label` and every string in your Panel are held to
the law. See architecture.md, *"Naming: display labels vs internal names"*.

**Player-visible strings need the maintainer's sign-off.** Propose them; do not treat your first
draft as final. dlac's own BST Helper shipped its strings marked PROPOSED for exactly this reason.

---

## 1. Folder anatomy

```
addons\dlac\jobhelpers\
    bst\                          <- the JOB folder: it groups, and nothing more
        bst-helper\               <- the MODULE folder: identity + unit of approval
            init.lua              <- REQUIRED. returns the contract table
            config.lua            <- your per-character settings (§5)
            fight.lua             <- your behaviors, one file each
            reward.lua
            resummon.lua
            jugs.lua              <- your data (rosters, mappings)
```

Rules the loader actually enforces:

- **A module is a FOLDER, never a loose file.** The scan is exactly two levels deep
  (`jobhelpers\<job>\<module>\`) and a name containing a `.` is treated as a file and skipped.
- **`init.lua` is the entry point**, resolved as
  `require('dlac\\jobhelpers\\<job>\\<module>\\init')`. Note the double backslashes — that is
  dlac's module-path convention (architecture.md, *Repository layout*), and your own files load
  the same way: `require('dlac\\jobhelpers\\bst\\bst-helper\\reward')`.
- **Identity is the MODULE folder name**, assigned by the loader. Your table does **not** declare
  an id, and one carrying its own cannot masquerade as another module. The name on disk is the
  authority a GM reads.
- **Module names are unique addon-wide.** The same module name under a second job folder is a
  collision: the first (job-sorted) wins, the second is refused loudly.
- **The job folder says where you FILE, not where you ACT.** Your `jobs` list decides where you
  act and show. A multi-job module files under its primary job's folder and appears under each
  job it declares.

---

## 2. The contract — the table `init.lua` returns

```lua
return {
    api    = 1,                        -- REQUIRED. must equal the running dlac's API
    label  = 'BST Helper',             -- REQUIRED. the one string players see
    jobs   = { 'BST' },                -- REQUIRED. declared MAIN jobs, non-empty
    init   = function(deps) end,       -- optional. arm standing behaviors, once, at load
    panel  = function(ctx) end,        -- REQUIRED. render your Panel
    status = function(ctx) end,        -- optional. one short line beside the Panel title
};
```

Anything else on the table is ignored by the loader and is yours to use.

### 2.1 `api` — and what a mismatch does

`api` must **equal** `feature/jobhelpers.M.API` exactly; the current value is **1**. Not "at
least", not "compatible with" — equal. A mismatch is a **loud refusal**: your module does not
load, one chat line says so, and `/dl check` lists it among the load failures.

That is the entire version gate. There are no capability tiers, no allowlist and no sandbox
(ADR 0028: "visibility and contracts, not walls"). It exists so that a module built for a
different dlac fails **visibly** after an update instead of misbehaving quietly. When the number
moves, read this guide again and bump yours deliberately.

### 2.2 `label` — the display label

A non-empty string. It is the row label, the Panel title, and the name in any refusal a player
reads. It is held to the naming law (§0) and to the maintainer's sign-off.

### 2.3 `jobs` — where you act

A non-empty array of job abbreviations (`{ 'BST' }`, `{ 'PUP', 'BST' }`). These are **main jobs**:
the activity predicate compares against the player's main job, matching the approved Pup-Helper
envelope. A module whose job is not the current one shows as **inactive** rather than vanishing,
so a player can always tell "installed but dormant" from "not installed".

A module declaring several jobs appears under **each** of them: same row, same pill, one shared
switch state.

### 2.4 `init(deps)` — arm your standing behaviors

Runs **once**, at addon load, from the loader — deliberately not from a render, because a helper
must act whether or not its Panel is open. This is where you subscribe to services (§6).

`deps` is the shared-services table: `{ host = <ui/uihost>, jobhelpers = <feature/jobhelpers> }`.
Everything else you need, you `require` by name — the services in §6 are plain modules in the
same Lua state.

**A throw here refuses your whole module.** The loader pcalls `init` and treats a throw as a load
failure. So: guard every subscription separately, and never let one unreachable service cost you
the rest of your behaviors.

```lua
init = function(deps)
    pcall(function()
        local fight = require('dlac\\jobhelpers\\bst\\bst-helper\\fight');
        if fight ~= nil and type(fight.init) == 'function' then fight.init('bst-helper'); end
    end);
    pcall(function()
        local reward = require('dlac\\jobhelpers\\bst\\bst-helper\\reward');
        if reward ~= nil and type(reward.init) == 'function' then reward.init('bst-helper'); end
    end);
end,
```

### 2.5 `panel(ctx)` — your configuration surface

`ctx = { imgui = <the host's imgui handle>, id = <your folder name>, record = { id, label, jobs,
mod }, deps = <the shared-services table> }`.

**Use `ctx.imgui`, not your own require.** The Panel renders under whatever binding — or test stub
— the host holds; a module requiring its own handle gets the wrong instance in the smoke suite.
(In any file that is *not* handed a handle, `imgui` is **not a global**: `require('imgui')` it —
hard rule 2.)

Your Panel draws *inside* an already-open child region. Do not call `imgui.Begin`/`End`, do not
open a window, do not register a tab. UI standards in §6.7.

### 2.6 `status(ctx)` — the short line beside the Panel title

Optional. Same `ctx`, plus `activity` (the live activity record, §6.6). Draw **one** short item:
`Reward ready`, `Reward 12s`. It renders on the Panel header line, not in the row — the list
answers *what is installed and armed*, the Panel answers *what is it doing*.

---

## 3. Lifecycle

```
addon load
  → UI host + main GUI are up (so services are populated and the tab lands right of Gear Helpers)
  → scan jobhelpers\<job>\<module>\        (folders only, sorted, deduped by module name)
  → require <module>\init                   → a throw here = refused, contained
  → validate the contract table             → a bad shape  = refused, contained
  → init(deps)                              → a throw here = refused, contained
  → survivors join the registry, in scan order
  → the Job Helpers tab registers — ONLY if at least one module loaded
  → every frame the tab is open: status(ctx) / panel(ctx) for the selected module
  → every beat you subscribed to: your own callbacks (tab open or not)
```

- **No hot-plugging.** Drop a folder in and `/addon reload dlac`. There is no folder watch and
  there will not be one.
- **The tab exists only while ≥ 1 module is loaded.** Zero modules, no tab — the base addon stays
  uncluttered for players who installed nothing.
- **Load order is alphabetical** (job folder, then module folder). Do not depend on it.
- **The row pill defaults ON**; a freshly dropped-in module runs, and the player *silences* it
  rather than arming it. Your own **behaviors** are the opposite: default them **off** (§5).

---

## 4. Containment — what dlac guarantees, and what it expects of you

A broken module must never tear down a player's gear engine or main window (PRD user story 6).
The guarantees, all structural:

| What breaks | What happens |
|---|---|
| Wrong `api` | One loud line: `Job helper <id> refused: api <x>, this dlac speaks api 1`. Ledger entry, no load. |
| `init.lua` missing, unparsable, or returning a non-table | One loud line naming the folder and the reason. Ledger entry, no load. |
| A malformed contract (no `label`, empty `jobs`, no `panel`, a non-function hook) | One loud line naming the missing piece. Ledger entry, no load. |
| Duplicate module name under a second job folder | The second is refused loudly, naming the folder that already owns the name. |
| `init` throws | One loud line: `init threw (...)`. The whole module is dropped — the other modules are untouched. |
| `panel` throws at render time | Your Panel is replaced by a red one-line notice and your name is printed **once** per session; the tab, the other modules' rows and the frame all survive. |
| `status` throws at render time | Contained the same way — one line, once — and the Panel below it still renders. |

Every failure also lands in the **same load ledger** `/dl check` reads, namespaced
`jobhelper:<id>` — so "my tab is missing" is diagnosable in seconds, and a failure is readable off
disk in `addons\dlac\debug\load-report.txt` even if the chat line scrolled away.

What dlac expects back:

- **Be loud when a whole behavior no-ops** (hard rule 12: *a total failure and a typo must not
  look identical*). Silence is for success only.
- **Degrade, do not throw.** A service that failed to load, a pre-login `nil`, a binding that does
  not carry a widget — each is a contained branch, never an error. Every `require` and every
  AshitaCore touch in a module is call-time and under `pcall`, so the module also loads clean in
  the headless suites.
- **Never latch a question you could not answer** (hard rule 11). An unreadable world is not a
  fact; retry it next beat.

---

## 5. Storing settings

Two files, and the split matters:

| File | Owner | Holds |
|---|---|---|
| `<char>\dlac\jobhelpers.lua` | the **framework** (`feature/jobhelpers`) | every module's row pill (`enabled`), the per-job section order (`order`), the per-job `JobHelper` Claim Priority anchor (`rank`). **Never write this yourself.** |
| `<char>\dlac\jobhelper-<name>.lua` | **you** | your behavior settings — switches, thresholds, picks. One file, named for your module; the shipped BST Helper's is `jobhelper-bst.lua`. |

One config file per module is part of what makes a module separable, and therefore part of what
makes it approvable on its own.

The shape is the **Statefile** convention as the ammo-config precedent uses it — a plain write with
a tolerant reader, *not* the atomic `gear.lua` ladder:

- **Format-versioned** (`fmt = 1`) and **declared keys only**: anything else on disk is dropped, so
  a key from a newer dlac cannot survive silently into an older one.
- **Written on mutation only.** A character who never touches your switches never grows the file.
- **Loaded once per character**, re-keyed on the character directory; pre-login the directory is
  `nil` — read the default and *retry later*, never cache the nil.
- **A torn or older file is normalized away**, not repaired: unreadable keys read as their default.
- **`<char>\dlac\` is found through the one resolver**, `lib/statefile.charDir()`. Keep it
  injectable (`M._charDir`) so your tests can point it at a scratch directory.
- **Never inside Profiles.** Profiles hold sets, triggers and lockstyle boxes; module state lives
  beside the character's other dlac files.
- **Nothing here is engine-seeded**, so a settings change never involves `dispatch.M.VERSION`.

`jobhelpers/bst/bst-helper/config.lua` is the copyable reference implementation, and it is short:
`M.KEYS` (name → type), `M.DEFAULTS`, `M.get(key)`, `M.set(key, value)`, a pure `_serialize` and a
tolerant `_normalize`.

**Default your acting behaviors OFF.** A helper that issues commands — and especially one that
spends an item — never arms itself. The player arms it; the row pill only ever silences.

---

## 6. The services you may consume

These are dlac's **central services**: one exported question each, injectable reads, headless
tests. Consuming them is not a convenience — it is a hard rule (§7.3). The full table, with the
rules that bite, is in [architecture.md](../architecture.md), *"Central services — ask these,
never re-derive"*.

| You need | Ask | Module |
|---|---|---|
| To act with gear or ammo worn first | `actionseq.request(req)` | `feature/actionseq.lua` |
| "Did I just engage / re-target, and exactly what?" | `engagewatch.subscribe(who, cb)` / `.lastEdge()` | `feature/engagewatch.lua` |
| "Is a pet out, and how is it doing?" | `petvitals.subscribe(who, cb)` / `.get()` | `feature/petvitals.lua` |
| "My pet is gone — why?" | `petvitals.subscribeLoss(who, cb)` | `feature/petvitals.lua` |
| "Is this ability off cooldown?" | `recast.readyFor(sig, reader)` | `feature/recast.lua` |
| To issue a game command | `cmdqueue.issue(cmd)` | `lib/cmdqueue.lua` |
| "Am I acting right now, and if not why?" | `jobhelpers.activity(id)` | `feature/jobhelpers.lua` |
| Any gear question (worn, eligibility, identity) | `gearoracle.*` | `gear/gearoracle.lua` |
| "How many of item N do I own / can I equip?" | `ownedcache.counts()` / `.totals()` | `gear/ownedcache.lua` |
| Where this character's dlac state lives | `statefile.charDir()` | `lib/statefile.lua` |

**Which signal does a standing rule run on?** dlac publishes two today, both pumped every frame
from `dlac.lua`'s `d3d_present` whatever your job: the **engage/target edges** (event-shaped —
"the player just attacked / re-targeted", §6.2) and the **pet-vitals beat** (state-shaped, 0.4 s,
§6.3 — the only per-beat publisher dlac ships). Pick the one your rule actually asks about: a rule
that reads a *state* ("my pet is hurt") wants a beat, a rule that reacts to a *moment* wants an
edge. If your rule needs a general beat that is neither, that is a new central service (§7.3), not
a timer you keep to yourself.

### 6.1 The Action sequencer — how a module acts

Read the **Action sequence** entry in CONTEXT.md first. In code:

```lua
local actionseq = require('dlac\\feature\\actionseq');
local res = actionseq.request({
    module  = id,                            -- your module id (ctx.id)
    label   = 'Reward',                      -- the ACT's name; appears in refusals and /dl why
    order   = jobhelpers.sectionOrder(id),   -- your tie-break priority (see below)
    claim   = { Ammo = 'Carrot Broth' },     -- slot -> item name; a named Set's slots ∪ specifics
    need    = { Ammo = 'Carrot Broth' },     -- the slots that MUST verify worn (defaults to claim)
    command = '/ja "Reward" <me>',           -- fired ONCE, only after every `need` slot verified
    timeout = 4,                             -- seconds; the gear not landing in time ABORTS
});
-- res.ok == true  -> the sequence is live
-- res.ok == false -> res.reason ('busy' | 'bad-request'), res.holderLabel names the live module
```

The lifecycle is `claimed → verified worn → fired → released`, or `refused(reason)` /
`aborted(reason)`. What that buys you, and what it costs you:

- **Never-fire-bare.** The command fires only after every `need` slot reads worn, and exactly once.
  If you do not need a slot verified, leave it out of `need`: claimed-but-not-needed slots dress
  **best-effort**, so a senior claimant taking one costs you that slot and refuses nothing.
- **`need` should be the *consumed* or *precondition* slot alone.** Reward eats what is worn in
  Ammo; Call Beast and Bestial Loyalty read the jug worn in Ammo. Everything else is costume.
  Every extra needed slot is one more chance for a senior claimant to refuse the whole sequence.
- **Success is SILENT.** A refusal or an abort is **one** chat line naming the blocker (§7.2).
- **Release restores the gear.** Dropping the claim kicks a dispatch and the next arbitration
  re-dresses the slots — you never restore anything yourself.
- **You ride the shared `JobHelper` claimant row**, ranked by default directly below Locks: above
  every standing Gear helper, below Locks, Naked and Free equip. A senior claimant holding a slot
  you *need* is a loud refusal, never a bare fire. That ranking is the player's to drag.
- **One sequence is live at a time, and a started one is never preempted.** A request arriving
  while one runs is refused with `reason = 'busy'`, naming the holder. Two requests contending in
  the *same* step resolve by the current job's **module order** — the row order of that job's
  section on the tab — and the loser is refused loudly. Ask
  `jobhelpers.sectionOrder(id)` for your number; higher wins.

**When you do *not* need a sequence:** a command that needs nothing worn — `/pet "Fight" <t>` —
just goes through `cmdqueue.issue` (§6.5). Do not open a sequence to fire a bare command; you
would be taking the one shared claim slot for nothing.

### 6.2 Engage/target edges — `feature/engagewatch.lua`

```lua
local ew = require('dlac\\feature\\engagewatch');
ew.subscribe('jobhelper:' .. id .. ':<rule>', function(edge) ... end);   -- keyed by name
ew.unsubscribe('jobhelper:' .. id .. ':<rule>');
local e = ew.lastEdge();   -- { kind = 'engage'|'retarget', index, serverId, name, at } | nil
```

The one decoder of the two battle edges — never register a second reader for them. The entity
comes **from the packet** and travels with the edge; do not re-read the target at consumption
time, because by then it has moved on. A per-target 5-second debounce means the same entity
notifies at most once a window while a different one notifies immediately. Subscribers are
`pcall`'d, so one throwing consumer never costs another its notification.

**Field lesson, do not re-derive it:** the BST Fight switch was built edge-driven and *failed two
live rounds* on this server (the client sends `0x0F`-then-`0x02` pairs on a fresh attack; the
captured-entity confirm then refused every send). It was rewritten on the field-proven **poll**
shape — every pet-vitals beat, ask "engaged + pet idle + target?", then issue — where the pet-idle
gate is simultaneously the spam brake and the retry. See history.md, *"Fight goes poll-driven"*.
Edges remain the right answer for *"what exactly did the player just attack"*; they were the wrong
answer for *"should the pet be sent in"*.

### 6.3 Pet vitals and the pet-loss edge — `feature/petvitals.lua`

```lua
local pv = require('dlac\\feature\\petvitals');
pv.subscribe('jobhelper:' .. id .. ':<rule>', function(v) ... end);  -- v = { present, hpp, tp, name, status } + `at`
local v = pv.get();                                                  -- same record, no cache, no `at`: reads NOW
pv.subscribeLoss('jobhelper:' .. id .. ':<rule>', function(edge) ... end);
```

The beat is `TICK_S = 0.4 s` — the engine's own dispatch cadence — and the service reads nothing at
all while nothing is subscribed. The published beat record carries the beat's own stamp `at`;
measure your **Retry lockout** against *that*, so the decision and the vitals it read describe the
same moment. (`get()` has no cache and no stamp: it reads now.)

Two laws travel with the answer, and both are load-bearing:

- **Dead pet = no pet.** A pet at 0 HP% is not a pet any consumer may act on.
- **Presence is two-state on purpose.** "No pet" and "the read could not be made" answer
  identically, because every consumer issues a command or spends an item, and a read we cannot
  make is not permission to do either. Individual vitals stay nil-able: a present pet whose HP
  could not be read is reported honestly — refuse on the nil, never guess.

The **pet-loss edge** carries *why* your pet is gone. **Death is confirmed, never assumed:** only
the pet-falls chat line and a vanish after a low last-seen HP% prove one; an observed outgoing
Leave, zoning and logging out each *suppress*, and are checked first; everything else is
`unknown`, which confirms nothing and lets nothing act. The asymmetry is deliberate — a missed
resummon costs a player nothing, a wrongly-assumed one costs them a jug.

**The service owns the rule; you own the list.** Jug-vs-charm is decided by *name*, through an
authority you inject:

```lua
pv.lossCtx.isJugPet = function(name) return myRoster.isJugPet(name); end
```

The next module's roster will be its own. Never push your data into a service's own tables.

### 6.4 Ability recasts — `feature/recast.lua`

```lua
local rc = require('dlac\\feature\\recast');
local MY_SIG = { name = 'Divine Seal', label = 'Divine Seal' };     -- resolved by NAME, live memory
local ready, remaining = rc.readyFor(MY_SIG, rc.liveRemaining);    -- PASS THE READER
local ready, remaining = rc.rewardReady();                          -- the shipped signatures wire it for you
```

A signature is `{ id?, timerId?, name?, label? }`. A declared `timerId` wins; otherwise the slot is
resolved **by name** through the client's own ability resource — live game memory outranks every
other source (hard rule 9), so an ability this server renumbered still resolves.

**`readyFor` takes the reader as its second argument, and it is not optional in practice:** the
core is pure, so `readyFor(sig)` with no reader has nothing to measure and answers READY. Pass
`rc.liveRemaining` in live code (the `rewardReady` / `callBeastReady` / `bestialLoyaltyReady`
wrappers do exactly that) and a fake in your tests.

**UNKNOWN reads READY.** A recast we cannot measure must never be the reason a player cannot press
a button, and the sequencer's own verify-worn is the real safety net — this gate is a courtesy.
Use it to *gray out* a button and to hold a rule *silently*; never to manufacture a refusal you
did not measure. A failed resolution is not latched: it is retried on the next ask.

### 6.5 Issuing a command — `lib/cmdqueue.lua`

```lua
local cq = require('dlac\\lib\\cmdqueue');
cq.issue('/pet "Fight" <t>');     -- THE central door for an auto-issued command
```

Every helper that auto-issues a command goes through this one function — never a per-module
wrapper, never a raw `QueueCommand` from inside a packet or render context. It queues on the frame
clock, so the command leaves on the next tick, on the **main thread**.

Two facts the queue exists for: two `QueueCommand`s issued in the *same frame* arrive **reversed**
in other Lua states, and an addon state never hears its own queued commands back. Commands are
therefore **spaced by frames** — `enqueue(delayFrames, cmd)` — and a tick flushes everything that
has come due, in insertion order. If two of your commands must arrive in a known order, give them
*different frames*; do not rely on the flush to space them for you.

Targets resolve at **execution** time. `<t>` means "whatever the player's target is when the
command runs" — which is exactly right for a poll that just read that target, and exactly wrong
for an edge captured 800 ms ago.

### 6.6 The module-activity predicate — `feature/jobhelpers.lua`

```lua
local jh = require('dlac\\feature\\jobhelpers');
local act = jh.activity(id);   -- { active = bool, reason = 'off'|'job'|'town'|'dead'|'zoning'|nil, label = '...' }
```

The ONE gate every Job helper consults — never a second copy of these rules. Precedence is fixed
and is also the reporting order, so the most specific true statement wins:

```
off (the pill)  →  wrong main job  →  zoning  →  dead  →  in town  →  active
```

An unknown read (a job that has not settled, an unreadable town answer) never manufactures a
reason: the module stays "active" on an unreadable world. Your own gates then decide which way
*their* nils go — and for anything that issues a command or spends an item, `active` must be
**positively true** before you act.

### 6.7 UI standards

- **The panel-text standard.** Never hang an explanatory paragraph off a label — it clips at the
  panel edge, and the window's minimum width is 480. Use the shared help-label convention: the
  label underlined, the explanation in its hover.

  ```lua
  local us = require('dlac\\ui\\uistyle');
  us.helpLabel(imgui, 'Reward', 'Tops your pet up with the best food you carry...', COL_HEAD);
  ```

- **Probe the binding before using an ImGui API — presence proves nothing** (hard rule 2).
  `BeginPopupContextItem` is bound in this install and does not work. Prefer widgets dlac already
  drives in the field: `Button`, `Checkbox`, `Selectable`, `SliderFloat`, `InputInt`,
  `BeginCombo`/`EndCombo`, `CollapsingHeader`. `RadioButton` is called nowhere in dlac — the lit /
  unlit `Button` pair is the proven substitute for a small exclusive choice.
- **Measure your widest label** (`CalcTextSize`) instead of hardcoding a width, and **stack**
  mutually exclusive choices vertically. A hardcoded width has clipped a trailing character in the
  field more than once.
- **Guard every widget.** `if type(imgui.Checkbox) == 'function' then ... end` — a binding without
  it degrades to text, never to an error.
- **Keep the imgui stack balanced.** Every `Push*` pops, every `BeginCombo` that returned true
  ends. The frame-level recovery above you is the host's guard; do not spend it.
- **Do not add UI outside your Panel.** No tabs, no windows, no chrome. If dlac ever grows a
  surface for modules, it will arrive through `uihost` (hard rule 1: the 200-local UI-chunk cap
  means UI registers through the host, never as new `gearui` locals).
- **Report state in the Panel, not in chat.** A rule that evaluates every beat has nothing to say
  most beats; only an *attempt* is news.

---

## 7. The hard rules

Five. They are what make a module approvable, containable and a good citizen; a module that
breaks one is a bug even if it works.

### 7.1 Claim, do not commit

A Job helper **never writes the player's state**. Not sets, not triggers, not lockstyles, not
another feature's settings, not `gear.lua`, not Profiles. You do not equip anything, either: you
*claim* through an Action sequence and let the **Arbiter** decide, per slot, whether you get it.

The reasons are not stylistic. The Arbiter is the single decision point for what gets worn; a
module that equips behind its back produces gear nobody can explain from `/dl why`, and it
punches through **Locks**, **Naked** and **Free equip** — the three things a player has explicitly
told dlac to respect. A blocked sequence **refuses**; it does not push harder.

Corollary: the only files you write are your own per-character config (§5). Anything else is
another owner's, and dlac's file-write safety pattern (backup → temp → validate → atomic swap)
belongs to the modules that own those files.

### 7.2 One-line acks

**Success is silent. A refusal or an abort is exactly one chat line, naming the blocker.**

A module acts on states, and states persist — a hurt pet is still hurt on the next beat. Without a
budget, one condition becomes a stream of commands and a stream of chat lines. The budget is the
**Retry lockout**: after any *attempt* — fired, refused or aborted alike — the rule holds for the
window before it may try again, so a player hears about a blocker at most once per window whatever
the bar does in between.

What must **not** arm the lockout, because nothing was attempted: a sequence already running, and
an ability still on cooldown. The cooldown hold is additionally **silent** — it mirrors a greyed
out button, and a greyed out button says nothing.

And the counterweight, because "quiet" is not the goal (hard rule 12): when a whole behavior
no-ops, **be loud**. A silently skipped act is indistinguishable from a broken one.

### 7.3 Consume the central services

Never open a rival scanner, reader or client. Not a second pet read, not a second packet reader
for an edge that already has a decoder, not a second E-Box client, not a second entity scan, not
your own worn-gear decode.

This is the rule with the longest field bill attached to it. Each service in §6 encodes lessons
that cost live rounds to learn — the packet's own entity versus a re-read one, two-state presence,
unknown-reads-ready, the debounce window, the network-thread/main-thread split. A local
re-implementation is a bug waiting for the field round that already happened; and where the read
is a shared server resource, a second client is also a courtesy problem for the server operator.

If the answer you need does not exist yet, the move is to *build the service* (generic plumbing in
`lib/`, game-domain answers in `feature/`), give it the house shape — one exported question,
injectable reads, headless tests — and add its row to architecture.md's Central-services table.
Not to keep a private copy.

### 7.4 Module independence on shared jobs

A job section may hold **several** modules — different authors' helpers for the same job coexist,
and nothing competes for a "job slot". Therefore:

- **Never read, write, wrap or disable another module.** No cross-module requires, no reaching
  into another module's config file, no assumptions about what else is installed.
- **Do not assume you are alone on the tab, in your section, or first in it.** Your section
  position is the *player's* order, drag-reordered and remembered per job.
- **Your rules gate on your own settings and the shared activity predicate** — never on another
  module's state.
- **Uninstalling you must be complete.** Removing the folder removes the behavior; the framework
  keeps only the player's pill / order / rank rows, dormant, so reinstalling later finds the
  position they gave you.

The one place modules legitimately interact is the sequencer, and there they interact through the
framework rather than with each other (§7.5).

### 7.5 The sequencer serializes — one live sequence, section order breaks ties

**Exactly one Action sequence is live at a time, addon-wide.** Not one per module, not one per
job — one.

- A **started sequence is never preempted.** A request arriving while one runs is refused,
  `reason = 'busy'`, naming the holder. Your rule must treat busy as a *hold*, not as a failure —
  and holding on busy attempts nothing, so it must not arm your lockout.
- **Simultaneous contenders resolve by the current job's module order** — the row order of that
  job's section on the Job Helpers tab, which is the player's drag order. Higher wins; the loser
  is refused loudly. Ask `jobhelpers.sectionOrder(id)` and put the answer in `order`; do not
  invent your own priority number.
- **Section order is a fact about the module, not about your rule.** All of your rules share one
  answer by construction — that is why the framework owns it.

Design for it: a rule that *must* act right now cannot, if another module is mid-act, and that is
the correct outcome. Serialization is what makes "one claim, one send per dispatch" true, and it
is what stops two helpers dressing the same slot for two different acts in the same beat.

---

## 8. A complete module, end to end

`addons\dlac\jobhelpers\whm\example-helper\init.lua`:

```lua
-- The contract table. Identity is the FOLDER name ('example-helper'); this table
-- deliberately declares no id of its own.
local MODULE_ID = 'example-helper';

local function req(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

return {
    api   = 1,
    label = 'Example Helper',          -- PROPOSED: player-facing, awaits sign-off
    jobs  = { 'WHM' },

    -- Arm standing behaviors ONCE, at load. Contained separately, so one broken
    -- service never costs the others -- and never throws, because a throw here
    -- refuses the whole module.
    init = function(deps)
        pcall(function()
            local rule = req('dlac\\jobhelpers\\whm\\example-helper\\rule');
            if rule ~= nil and type(rule.init) == 'function' then rule.init(MODULE_ID); end
        end);
    end,

    -- The Panel: draws INSIDE the tab's child region. Use ctx.imgui, guard every
    -- widget, keep the stack balanced.
    panel = function(ctx)
        local imgui = ctx and ctx.imgui;
        if imgui == nil then return; end
        local id   = (ctx and ctx.id) or MODULE_ID;
        local rule = req('dlac\\jobhelpers\\whm\\example-helper\\rule');
        if rule == nil then
            if type(imgui.TextColored) == 'function' then
                imgui.TextColored({ 1.0, 0.45, 0.40, 1.0 }, 'This helper could not load its rule.');
            end
            return;
        end

        -- The panel-text standard: label underlined, explanation on hover.
        local us = req('dlac\\ui\\uistyle');
        if us ~= nil then
            us.helpLabel(imgui, 'Example rule',
                'What this rule does, in the player\'s words -- never "Auto <activity>".',
                { 0.60, 0.75, 1.00, 1.00 });
        end

        -- The arming switch. Defaults OFF: a helper that acts never arms itself.
        if type(imgui.Checkbox) == 'function' then
            local buf = { rule.armed() };
            if imgui.Checkbox('Do the thing when it is time##ex_' .. id, buf) then
                rule.setArmed(buf[1]);
            end
        end

        -- Report state HERE, not in chat: the rule runs on every signal, and only
        -- an attempt is news.
        local jh  = req('dlac\\feature\\jobhelpers');
        local act = (jh ~= nil) and jh.activity(id) or nil;
        if type(imgui.TextColored) == 'function' then
            if type(act) == 'table' and act.active ~= true then
                imgui.TextColored({ 1.00, 0.72, 0.30, 1.00 },
                    'Not acting: ' .. tostring(act.label or 'inactive') .. '.');
            else
                imgui.TextColored({ 0.55, 0.90, 0.55, 1.00 }, 'Armed.');
            end
        end
    end,

    -- One short item beside the Panel title. Optional; contained by the tab.
    status = function(ctx)
        local imgui = ctx and ctx.imgui;
        if imgui == nil or type(imgui.TextColored) ~= 'function' then return; end
        imgui.TextColored({ 0.70, 0.70, 0.70, 1.00 }, 'ready');
    end,
};
```

`...\example-helper\rule.lua` — the behavior, with the decision kept pure. It runs on the **engage
edge**, which any module can subscribe to whatever its job; a pet-flavored rule would subscribe to
the pet-vitals beat instead (§6.3), which is the only per-beat publisher dlac ships today.

```lua
local M = {};

M.LOCKOUT_S = 30;                       -- the retry lockout: one ATTEMPT per window
local _id, _last, _lastAttemptAt = 'example-helper', nil, nil;

local function req(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

local function cfg() return req('dlac\\jobhelpers\\whm\\example-helper\\config'); end

function M.armed()
    local c = cfg();
    return (c ~= nil) and (c.get('armed') == true) or false;
end

function M.setArmed(on)
    local c = cfg();
    if c == nil then return false; end
    return c.set('armed', on == true);
end

-- PURE: signal + state in, decision out. No AshitaCore, no clock, no require --
-- so every rule below is a headless check.
function M.decide(edge, state)
    state = (type(state) == 'table') and state or {};
    if state.armed ~= true then return { act = false, reason = 'off' }; end
    if type(edge) ~= 'table' or edge.kind ~= 'engage' then
        return { act = false, reason = 'not-my-signal' };
    end
    -- POSITIVELY true: an unreadable world is not permission to act.
    if state.active ~= true then return { act = false, reason = state.reason or 'inactive' }; end

    local now  = tonumber(state.now) or 0;
    local last = tonumber(state.lastAttemptAt);
    if last ~= nil then
        local since = now - last;
        if since >= 0 and since < (tonumber(state.lockout) or M.LOCKOUT_S) then
            return { act = false, reason = 'lockout' };
        end
    end
    -- Nothing below here ATTEMPTS anything, so neither arms the lockout.
    if state.busy == true then return { act = false, reason = 'busy' }; end
    return { act = true };
end

-- One signal -> one decision -> at most one act.
function M.onEdge(edge, id)
    local st = { armed = M.armed(), lastAttemptAt = _lastAttemptAt, now = 0 };
    pcall(function()
        local jh  = require('dlac\\feature\\jobhelpers');
        local act = jh.activity(id or _id);
        st.active, st.reason = (act.active == true), act.reason;
    end);
    pcall(function()
        local as = require('dlac\\feature\\actionseq');
        st.busy = as.active();
    end);
    pcall(function()
        local cq = require('dlac\\lib\\cmdqueue');
        st.now = cq.frame() / 60.0;                     -- the shared monotonic clock
    end);

    local d = M.decide(edge, st);
    _last = d;
    if d.act ~= true then return d; end
    _lastAttemptAt = st.now;                            -- the lockout arms on the ATTEMPT
    M.act(id or _id);
    return d;
end

-- The act. A command that needs nothing WORN goes through the central door; an
-- act with an equip precondition opens an Action sequence instead (guide 6.1).
function M.act(id)
    local cq = req('dlac\\lib\\cmdqueue');
    if cq == nil then
        local cf = req('dlac\\chatfmt');
        if cf ~= nil then cf.err('Example Helper: the command queue is unavailable.'); end
        return false;
    end
    return cq.issue('/ja "Divine Seal" <me>');
end

function M.lastDecision() return _last; end

-- Subscribe in the module's init hook, so the rule works with the tab closed.
-- Subscriptions are keyed by NAME: a reload replaces rather than doubles, and the
-- module can drop its own wholesale. Both pumps run every frame in dlac.lua's
-- d3d_present, so either signal reaches you on any job.
function M.init(id)
    if type(id) == 'string' and id ~= '' then _id = id; end
    local ok = false;
    pcall(function()
        local ew = require('dlac\\feature\\engagewatch');
        ok = ew.subscribe('jobhelper:' .. _id .. ':rule', function(e) M.onEdge(e, _id); end);
    end);
    return ok;
end

return M;
```

`...\example-helper\config.lua` is `jobhelpers/bst/bst-helper/config.lua` with your own `M.FILE`,
`M.KEYS` and `M.DEFAULTS` — copy it; the format, the tolerant reader and the mutation-only write
are the parts that matter.

---

## 9. Testing your module

dlac's suites run headless on Lua 5.4 with no Ashita, no imgui and no character; write to the
Lua 5.1 / LuaJIT intersection so the same code loads in-game.

- **`lua tests\run_tests.lua`** — the logic suite. Add every file of your module to the `JOBHELP`
  roster in the guard block — entries are module paths *relative to `jobhelpers\`*, without the
  extension (`'bst/bst-helper/reward'`), and the rosters are hand-maintained by design. Then test
  your **pure deciders**: state in, decision out. Every acceptance criterion of a rule should be
  one check against a synthetic world.
- **`lua tests\smoke_ui.lua`** — the stub-imgui render suite. It draws every registered tab with a
  stub binding and asserts a **balanced imgui stack**. A Panel that pushes without popping fails
  here, which is the cheapest place to find it.
- **`luac -p <file>`** on every touched Lua file — the fast syntax gate.

Test **at the seams**, never module-private state: decisions, resolutions, lifecycle transitions,
rendered output, chat lines. The framework's own loader fixtures (a good module, a wrong-`api`
module, a throwing module) live in the suite and show how a module is driven with no filesystem.

---

## 10. Gotchas, in the order they will bite you

1. **Your `api` must equal the running dlac's**, exactly. `1` today.
2. **`imgui` is not a global.** Use `ctx.imgui` in your hooks; `require('imgui')` anywhere else.
3. **Pre-login is `nil` everywhere** — the character directory, the job, the world. Read a
   default, retry next call, never cache the nil and never latch on it.
4. **`gData.GetPet()` answers `nil` for "no pet" and for "I could not tell".** So does the vitals
   service, on purpose. Do not act on either.
5. **A throw in `init` costs you the whole module**; a throw in `panel` costs you only the Panel.
   Guard each subscription separately.
6. **Two same-frame commands arrive reversed** in other Lua states. Space them by frames through
   `cmdqueue`.
7. **`<t>` resolves when the command executes**, not when you decided. If your decision is older
   than a beat, it may target the wrong mob.
8. **The row pill defaults ON and your behaviors default OFF.** They are different switches with
   different jobs; do not collapse them.
9. **A drag on a slider is one write per frame** unless you clamp on the way in. The config store
   writes on mutation only — clamp to the granularity you actually store.
10. **`pairs()` order is undefined.** Any order you depend on must be explicit — the sequencer's
    own tie-break is deterministic for exactly this reason.
11. **Bumping `dispatch.M.VERSION` is not yours to do** — it is the engine handshake and matters
    when seeded-file behavior changes. Module settings never touch it.

---

## 11. What dlac will not do for you

- **Sandbox you.** No restricted `_ENV`, no capability tiers, no allowlist. dlac ships as readable
  Lua, so a wall buys attribution, not prevention (ADR 0028). What you get instead is visibility:
  a loud refusal, a ledger entry, a contained frame — and a contract in this document.
- **Hot-plug you.** Reload the addon.
- **Preserve your data across an uninstall.** The framework remembers the player's pill, section
  order and Claim Priority position; your own config file is yours to keep or remove.
- **Give you a second sequence, a second claim row, or a way past the Arbiter.** One live
  sequence, one shared `JobHelper` row, and Locks / Naked / Free equip outrank you by design.
- **Approve you.** One folder, one approval request. That conversation is between the module and
  the server's staff — dlac's own approval does not extend to what your module does.
