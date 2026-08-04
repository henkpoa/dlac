# Writing a Job helper module — authoring guide

**Audience:** the author (human or AI) of a **Job helper** module for dlac — a drop-in folder
that performs a job's own actions for the player (pet commands, ability use) in the situations
they configured. This is the reference for the module contract *as shipped*: everything here is
checked against the code in `feature/jobhelpers.lua` (the loader), `feature/modapi.lua` (the module
API), `feature/modcfg.lua` (settings), `ui/panelkit.lua` (the Panel kit), `feature/actionseq.lua`
(acting), and the first real module, `jobhelpers/bst/bst-helper/`. You should not need to read
dlac's source to build a working module.

**If you read nothing else:** copy `docs/templates/example-helper/`, and know that `S` (§6) is the
one table you ask for everything.

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
| **The module contract** (`api = 2`, folder anatomy, hooks, containment) | ✅ **Shipped** — issue #137, ADR [0028](../adr/0028-job-helper-modules.md). |
| **The module API** (`S` — one table for every service, the clock, the act doors) | ✅ **Shipped** — `feature/modapi.lua`. |
| **Declared settings**, stored by the framework | ✅ **Shipped** — `feature/modcfg.lua`. |
| **The Panel widget kit** (`ctx.ui`) | ✅ **Shipped** — `ui/panelkit.lua`. |
| **The Action sequencer** and the shared `JobHelper` claimant row | ✅ **Shipped** — issue #138, ADR [0030](../adr/0030-module-owns-initiation.md). |
| **Combat state + edges**, **pet vitals** + the pet-loss edge, **ability recasts** | ✅ **Shipped** — issues #139 / #140 / #141, plus `feature/combat.lua`. |
| **The `window` hook** (a module float at the framework's draw site) | ✅ **Shipped** — ADR [0028](../adr/0028-job-helper-modules.md) amendment 2026-08-04. |
| **Hot-plugging**, capability tiers, sandboxing | ❌ **Not coming.** Modules appear on addon (re)load; the door is documentation and contracts, not walls (ADR 0028). |

---

## Start here — the shortest path to a working module

**Copy the template.** It is a working helper, and it is the fastest correct start:

```
copy  docs\templates\example-helper\    (init.lua + rule.lua + README.md)
  to  addons\dlac\jobhelpers\<job>\<your-module>\
```

Then:

1. **Pick your folder name.** The job folder groups; the **module folder is your identity and
   your unit of approval**. Lower-case, hyphenated: `jobhelpers\bst\bst-helper\`.
2. **Change the four `CHANGE ME` spots** in `init.lua`: `label`, `jobs`, the `config` keys, and
   the ability. The minimum that loads is
   `{ api = 2, label = '...', jobs = { 'BST' }, panel = function(ctx) end }`.
3. **`/addon reload dlac`.** There is no hot-plug. Your module appears as one row under its job's
   section on the **Job Helpers** tab; `/dl check` counts it. If it was refused, you get one loud
   chat line naming your folder and the reason (§4).
4. **Ask `S` for everything** (§6) — the services, the clock, your settings, the act doors. It is
   the one table you were handed, and the one surface that will keep working.
5. **Declare your settings** (§5) and let the framework store them. Never in Profiles, never in
   the framework's own file, and never a copy of the storage policy.
6. **Act only through an Action sequence** when the act needs gear or ammo worn first (§6.2) —
   never equip anything yourself (§7.1).
7. **Read §7 before you ship.** Those five rules are what make a module approvable and what keep
   one broken module from being everybody's problem.

**One paragraph on what `S` is, because it changes how the rest of this reads.** Under `api = 1`
a module reached the services by hardcoded path string — `require('dlac\\feature\\petvitals')` —
and carried its own copy of the monotonic clock, its own loud-line emitter, its own activity
block, and its own 190-line settings store. That was not sloppiness; it is what "reach the
services by path" costs. `S` is a curated, versioned namespace the loader mints per module, so
you ask for **answers in your own vocabulary** (`S.item.own('Carrot Broth')`) instead of
assembling them out of dlac's internals. It is **not a sandbox** — ADR 0028 settled that, and you
can still `require` anything. It is the part that is documented, tested, and stable.

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
            fight.lua             <- your behaviors, one file each
            reward.lua
            resummon.lua
            jugs.lua              <- your data (rosters, mappings)
```

Two files is the whole minimum (`init.lua` plus one rule); one is legal if your Panel is all you
have. There is **no `config.lua`** any more — you declare your settings on the contract table and
the framework stores them (§5).

Rules the loader actually enforces:

- **A module is a FOLDER, never a loose file.** The scan is exactly two levels deep
  (`jobhelpers\<job>\<module>\`) and a name containing a `.` is treated as a file and skipped.
  (This is also why the template ships under `docs\templates\` — a folder directly under
  `jobhelpers\` would load as a *job*.)
- **`init.lua` is the entry point**, resolved as
  `require('dlac\\jobhelpers\\<job>\\<module>\\init')`.
- **Load your own files with `S.sibling('reward')`**, never by path. Under `api = 1` the shipped
  module hardcoded `dlac\jobhelpers\bst\bst-helper\config` in four files, in a framework whose
  first law is that the folder name is the identity — so renaming the folder assigned a new id
  and broke every internal require. `S.sibling` resolves against the identity the loader actually
  gave you, which is what finally makes a rename safe.
- **Identity is the MODULE folder name**, assigned by the loader and handed back as `S.id`. Your
  table does **not** declare an id, and one carrying its own cannot masquerade as another module.
  The name on disk is the authority a GM reads.
- **Module names are unique addon-wide.** The same module name under a second job folder is a
  collision: the first (job-sorted) wins, the second is refused loudly.
- **The job folder says where you FILE, not where you ACT.** Your `jobs` list decides where you
  act and show. A multi-job module files under its primary job's folder and appears under each
  job it declares.

---

## 2. The contract — the table `init.lua` returns

```lua
return {
    api    = 2,                        -- REQUIRED. must equal the running dlac's API
    label  = 'BST Helper',             -- REQUIRED. the one string players see
    jobs   = { 'BST' },                -- REQUIRED. declared MAIN jobs, non-empty
    config = { keys = {}, defaults = {} },  -- optional. what you store (§5)
    commands = { summon = { run = function(S) end } },  -- optional. named actions (§2.7)
    init   = function(S) end,          -- optional. arm standing behaviors, once, at load
    panel  = function(ctx) end,        -- REQUIRED. render your Panel
    status = function(ctx) end,        -- optional. one short line beside the Panel title
    window = function(ctx) end,        -- optional. a floating window (§2.8)
    open   = function(S) end,          -- optional. "open this helper" (§2.9)
};
```

Anything else on the table is ignored by the loader and is yours to use.

### 2.1 `api` — and what a mismatch does

`api` must **equal** `feature/modapi.M.API` exactly (re-exported as `jobhelpers.API`); the current
value is **2**. Not "at least", not "compatible with" — equal. A mismatch is a **loud refusal**:
your module does not load, one chat line says so, and `/dl check` lists it among the load failures.

That is the entire version gate. There are no capability tiers, no allowlist and no sandbox
(ADR 0028: "visibility and contracts, not walls"). It exists so that a module built for a
different dlac fails **visibly** after an update instead of misbehaving quietly. When the number
moves, read this guide again and bump yours deliberately.

The version now lives with the **module API** rather than with the loader, because what a module
actually depends on is the service surface — `api = 1`'s gate could only say "your table has the
right keys", which was never the thing that broke. Adding a new entry to `S` is not a break;
changing what one means, or removing it, is.

| `api` | What a module was handed |
|---|---|
| `1` | `init(deps)` with `{ host, jobhelpers }`. Every other service reached by hardcoded `require` path; every module carrying its own clock, emitter, activity block and settings store. |
| `2` | `init(S)` — the curated module API (§6), an optional declared `config` block the framework stores (§5), and the Panel widget kit on `ctx.ui` (§6.9). |

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

**The sub-job switch is the framework's, not yours.** The floating quick menu lists the current
main job's helpers and — for helpers whose *Sub job* switch is on (Panel header, default **on**)
— the current sub job's too. That switch gates **menu visibility only**; the activity predicate
stays main-job, matching the approved envelope. Declare nothing for it.

### 2.4 `init(S)` — arm your standing behaviors

Runs **once**, at addon load, from the loader — deliberately not from a render, because a helper
must act whether or not its Panel is open. This is where you subscribe (§6).

`S` is your **module API** (§6): identity, the one clock, every service, the act doors, your
settings store, the widget kit. It is built per module and closed over your identity, so you
cannot ask a question as somebody else — and neither can anyone ask as you.

**A throw here refuses your whole module.** The loader pcalls `init` and treats a throw as a load
failure. So: guard every subscription separately, and never let one unreachable service cost you
the rest of your behaviors.

```lua
init = function(S)
    for _, name in ipairs({ 'fight', 'reward', 'resummon' }) do
        pcall(function()
            local rule = S.sibling(name);          -- your own files, by bare name
            if rule ~= nil and type(rule.init) == 'function' then rule.init(S); end
        end);
    end
end,
```

### 2.5 `panel(ctx)` — your configuration surface

```lua
ctx = {
    ui     = <the Panel widget kit, bound to the host's handle>,   -- use this
    S      = <your module API, the same table init got>,
    imgui  = <the host's raw imgui handle>,                        -- escape hatch
    id     = <your folder name>,
    record = { id, job, label, jobs, mod, cfg, S },
    activity = <the live activity record>,
}
```

**Use `ctx.ui`.** It is `ui/panelkit` with the host's handle already applied, and it carries the
guards, the measured widths, the vertical stacking and the panel-text standard that dlac learned
in the field — see §6.9 for why each of those exists. `ctx.imgui` is there for something the kit
does not cover; if you find yourself needing it often, that is a missing kit entry.

Whichever you use, it must be the **host's** handle: the smoke suite renders every tab against a
stub binding, and a module that required its own `imgui` would get the wrong instance. (In any
file that is *not* handed a handle, `imgui` is **not a global** — hard rule 2.)

Your Panel draws *inside* an already-open child region. Do not call `imgui.Begin`/`End`, do not
open a window, do not register a tab.

**Why a Panel cannot open a window** — load-bearing, not taste, and it has two legs:

1. **The containment promise is scoped to the Panel.** §4's guarantee — a throwing `panel` costs
   you your Panel and nothing else — is implemented *around* the Panel region (the render pcall,
   with gearui's `tabGuard` as the frame-level recovery above it). A window your Panel opened
   itself sits outside that machinery: a throw between your own `Begin`/`End` leaves a torn stack
   that is the whole frame's problem — exactly what PRD user story 6 says a module must never be
   able to cause. The rule is what makes the guarantee provable **by contract** instead of by
   auditing every module's window discipline by hand.
2. **dlac already has a law for floating windows, paid for in the field** (architecture.md,
   *"Floating windows — many openers, ONE draw site"*): two `Begin` calls on one window name in a
   frame silently merge their bodies (the floatgear S50 class), a plain `Begin` window is always
   drawn *under* an open popup, and a real float must be drawn from the one site **above** the
   main-window visibility gate or it blinks out whenever the player closes the main box or
   switches tabs. A window drawn from inside a Panel render gets none of that.

The sanctioned path is the **`window` hook (§2.8)**: the framework draws it at the floats' one
draw site, wrapped in the same containment, and your window behaves like every other dlac float.

### 2.6 `status(ctx)` — the short line beside the Panel title

Optional. Same `ctx`. Draw **one** short item: `Reward ready`, `Reward 12s`. It renders on the
Panel header line, not in the row — the list answers *what is installed and armed*, the Panel
answers *what is it doing*.

### 2.7 `commands` — named actions, and the keys that fire them

Optional. A **named action a player can fire by hand** — and therefore bind a key to.

```lua
commands = {
    summon = {
        label = 'Summon now',                     -- what a button/bind is called
        help  = 'summon your jug pet with the Summon set on',
        key   = 'summonKey',                      -- one of YOUR config keys, holding the bind
        run   = function(S, args) return doIt(); end,
    },
},
```

Every action is reachable as **`/dl jobhelper <module> <action>`**, or `/dl jh` for short.
`/dl jh` alone lists the installed modules; `/dl jh <module>` lists its actions and shows which key
each holds. The module name is the folder name, which is already unique addon-wide — the loader
refuses a second folder of that name under another job — so the command needs no job level.

**You do not bind keys.** Name one of your own declared `config` keys in `key` and the framework
does the rest: it installs the bind while the player is on your job with your row pill on, releases
it when they change job, and refuses (loudly, naming the holder) a key another feature already
has. The owner id and the command string are the framework's, for the same reason `S.act.request`
fills in your module id — so a module cannot claim a key as somebody else. See ADR 0032.

`key` must name a **declared `string`** config key or the module is refused at load, like any other
bad declaration. `run` returns falsey to mean "I refused"; say why yourself, in one line — a key
that did nothing and said nothing is indistinguishable from a broken bind.

**A named action is a DELIBERATE press.** It is not gated on your rule switches, and it should not
be: the switch governs what happens *without* the player. The framework checks only that they are
on your job.

### 2.8 `window(ctx)` — a floating window, drawn at the framework's one draw site

Optional (added 2026-08-04; the first consumer is Bludex's Spell Info window). Declare it when
your module has a window that must behave like dlac's other floats — independent of the main box,
alive while the player plays.

```lua
window = function(ctx)
    if not myWindowOpen then return; end      -- SELF-GATE: draw nothing when closed
    -- Begin/End your window here, guarded; ctx is the same shape panel gets
end,
```

The division of labor is the float law every first-party window already lives by (*"any surface
may OPEN a floating window; exactly one place may DRAW it"*):

- **You own the open flag.** Any of your surfaces (your Panel, a rule, a command) may set it;
  only the hook draws. Draw nothing when it is off — the hook is called every frame.
- **The framework owns the site and the gates it can prove.** Your hook is called from gearui's
  float draw site (so your window survives the main window closing and never rides tab
  visibility), inside dlac's theme bracket, and only while your row pill is on. Job/town/dead
  gating stays *yours* if your window wants it — an info window on the wrong job is your call,
  not the framework's.
- **Containment is stricter than the Panel's.** A throw is blamed once and your window hook is
  **silenced for the rest of the session** — a float has no container to draw a red notice in,
  and a hook that tore its own `Begin`/`End` once must not be handed a second frame to tear
  another. So: `End` on every path where `Begin` succeeded, pcall your own body, and treat a
  session-silenced window as the bug report it is.
- **One window per module.** A module that wants a second window wants a design conversation
  first (the icon-tray precedent: two little boxes doing the same kind of job became one).

### 2.9 `open(S)` — what "open this helper" means for your module

Optional (added 2026-08-04). The floating quick menu carries a **Job helpers** cascade for the
player's current main/sub jobs; choosing a helper calls its `open` hook. Declare it when your
module has its own surface to present — Bludex opens its floating window:

```lua
open = function(S) myWindowOpen = true; end,
```

Without the hook, the framework's fallback is the **Panel jump**: your Panel is selected on the
Job Helpers tab and the main window opens there (the `openAutomation` shape). A deliberate menu
pick is like a named action (§2.7): it is not gated on your rule switches, only on the pill —
a silenced helper is not offered in the menu at all.

---

## 3. Lifecycle

```
addon load
  → UI host + main GUI are up (so services are populated and the tab lands right of Gear Helpers)
  → scan jobhelpers\<job>\<module>\        (folders only, sorted, deduped by module name)
  → require <module>\init                   → a throw here = refused, contained
  → validate the contract table             → a bad shape  = refused, contained
                                              (including your `config` declaration)
  → open your settings store, build your S
  → init(S)                                 → a throw here = refused, contained
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
| A malformed `config` block (a key with no type, a default for a key you never declared, a default of the wrong type) | One loud line naming the key and what was wrong. Ledger entry, no load — a settings declaration that does not say what it stores is far cheaper to hear about at load than to discover in the field when a value turns out never to have persisted. |
| Duplicate module name under a second job folder | The second is refused loudly, naming the folder that already owns the name. |
| `init` throws | One loud line: `init threw (...)`. The whole module is dropped — the other modules are untouched. |
| `panel` throws at render time | Your Panel is replaced by a red one-line notice and your name is printed **once** per session; the tab, the other modules' rows and the frame all survive. |
| `status` throws at render time | Contained the same way — one line, once — and the Panel below it still renders. |
| `window` throws at render time | One line, once, and the hook is **silenced for the session** — a float has no container for a red notice, and a torn `Begin`/`End` must not recur (§2.8). Everything else survives. |

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

**You declare what you store. The framework owns how.**

```lua
-- on the contract table
config = {
    keys     = { fight = 'string', rewardArmed = 'boolean', rewardThreshold = 'number' },
    defaults = { fight = 'off',    rewardArmed = false,     rewardThreshold = 50 },
    -- file = 'jobhelper-bst.lua',    -- optional; defaults to jobhelper-<your folder>.lua
},
```

...and the loader hands you a live store as **`S.cfg`**:

```lua
S.cfg.get('fight')              -- the stored value, or your declared default
S.cfg.set('fight', 'follow')    -- true when it is now in effect
S.cfg.forget()                  -- drop the in-memory copy (character switch)
S.cfg.path()                    -- the file this store writes, or nil pre-login
```

Scalars only — `string`, `number`, `boolean`. A setting that wants a table is a setting that wants
a design conversation, not a serializer.

**Why this is the framework's job.** The api-1 reference implementation was 193 lines, of which
about forty were BST's (the key list and the defaults) and the rest was serialize / normalize /
load-once / write-on-mutation — the Statefile policy, identical for every module that will ever
exist. This guide's honest advice used to be "copy it", and copy-paste is a poor way to distribute
a *policy*: the next module inherits today's version of it forever, and a fix has to be applied N
times by N authors.

The policy you get, which you no longer have to implement or remember:

- **Format-versioned** (`fmt = 1`) and **declared keys of the declared type only**: anything else
  on disk is dropped on the way in, so a hand-edit, a torn write, or a key from a newer dlac
  cannot survive silently into an older one.
- **Written on mutation only.** A character who never touches your switches never grows the file,
  and an unchanged value never touches the disk.
- **Loaded once per character**, re-keyed on the character directory.
- **Never caches the pre-login `nil`.** Before login the directory is unknown: reads answer your
  declared default and writes return `false`, and both are retried on the next call (hard rule 11).
- **Sorted output**, so an unchanged config re-serializes byte-identical.
- **Your own file**, one per module — `<char>\dlac\jobhelper-<your-id>.lua`. That is a
  separability requirement, not a storage preference: one file per module is part of what makes a
  module removable, and therefore part of what makes it approvable on its own.

Two things it will never touch:

| File | Owner | Holds |
|---|---|---|
| `<char>\dlac\jobhelpers.lua` | the **framework** | every module's row pill, the per-job section order, the per-job `JobHelper` Claim Priority anchor. **Never write this yourself.** |
| Profiles | the gear engine | sets, triggers, lockstyle boxes. Module state lives beside the character's other dlac files, never inside a Profile. |

Nothing here is engine-seeded, so a settings change never involves `dispatch.M.VERSION`.

**Default your acting behaviors OFF.** A helper that issues commands — and especially one that
spends an item — never arms itself. The player arms it; the row pill only ever silences. They are
different switches with different jobs.

**Clamp on the way IN.** A slider is one `set` per frame while it is dragged. Round to the
granularity you actually keep and the mutation-only store turns a whole drag into one write per
distinct value.

---

## 6. `S` — the module API

One table, handed to your `init` and available on `ctx.S`. Everything a module needs is on it, and
the entries are named for the **question you are asking**, not for the dlac service that answers
it. That is the difference that matters in practice: you write `S.item.own('Carrot Broth')`, not
"`ownedcache.counts()` is keyed by item id, so keep your own name-to-id table".

Two consequences, both deliberate:

- **The right answer is the only reachable one.** `S.player.level()` returns the level the *engine
  will gear at* — the `/dl set level main` override, then the SYNC-aware level. There is no way to
  reach raw `MainJobLevel` from here, because reaching it is a bug that already cost a live field
  round: under level sync a picker chose a food tier above the cap, the equip was refused, and the
  sequence died in a verify timeout instead of falling a rung. A comment cannot prevent that. An
  absent function can.
- **dlac's internals stay free to move.** Most entries are plain references to existing service
  functions — this is a curated namespace, not a translation layer — so it cannot drift from what
  it names, and a refactor behind it is not your problem.

**It is not a sandbox.** ADR 0028 settled that: dlac ships as readable Lua in one Lua state, so a
wall would buy attribution, not prevention. You can `require` anything. What `S` gives you is the
surface that is *documented, versioned by `api`, covered by tests, and will keep working*. Reach
past it and you own the breakage — and that is the signal that `S` is missing an entry, which is a
bug report, not a scolding (§6.8). The full reasoning, and the alternatives that were rejected, is
ADR [0031](../adr/0031-module-api-is-a-front-door.md).

If you would rather know *where it comes from* before reading what is on it, skip to §6.10 — it is
a plain table from a factory, built once per module at load.

### 6.0 The whole surface, at a glance

```lua
-- identity + plumbing (§6.1)
S.id  S.job  S.api  S.label  S.jobs
S.sibling('reward')          -- one of YOUR files, by bare name
S.now()                      -- the one monotonic clock
S.say.good/warn/err(line)    -- the only route to chat
S.cfg                        -- your settings store (§5), or nil if you declared none
S.keys.boundTo('summon')     -- the key one of your actions holds right now, or nil
S.keys.holder('^F3')         -- who has that key: { owner, label, command } or nil
S.ui                         -- the widget kit, unbound (ctx.ui is the bound one, §6.9)
S.service(path)              -- the escape hatch (§6.8)

-- am I acting? (§6.3)
S.me.acting()                -- { active, reason, label }
S.me.order()                 -- your tie-break priority for a contended sequence
S.me.enabled()               -- your row pill

-- the player
S.player.job()  S.player.subJob()  S.player.status()
S.player.level()             -- THE gear level; see above
S.player.zoning()  S.player.loggingOut()

-- combat (§6.4)
S.combat.subscribe(name, cb) -- the per-beat state record
S.combat.state()             -- the same record, read now
S.combat.onEdge(name, cb)    -- the raw engage/retarget edge
S.combat.lastEdge()

-- the pet (§6.5)
S.pet.get()                  -- { present, hpp, tp, name, status }
S.pet.subscribe(name, cb)    -- the same record, per beat
S.pet.onLoss(name, cb)       -- the classified loss edge: gone, and WHY
S.pet.lastLoss()  S.pet.signals()
S.pet.nameAuthority(fn)      -- tell the classifier which pet names are yours
S.pet.food()  S.pet.foodRefusal(pick)

-- abilities (§6.6)
S.ability.ready(nameOrSig)   -- -> ready, remainingSeconds

-- items and gear (§6.7)
S.item.own(name)             -- how many can I EQUIP right now
S.item.stored(name)          -- owned anywhere, including storage
S.item.worn(slot)            -- what is in this slot now
S.item.info(name)            -- the catalog / owned record
S.sets.names()               -- this character's static set names
S.sets.slotsOf(name)         -- a named set as { SlotKey = itemName }

-- doing things (§6.2)
S.act.request{ label, claim, need, command, timeout }   -- an Action sequence
S.act.busy()  S.act.status()
S.cmd('/pet "Fight" <t>')    -- a bare command, no gear precondition
```

Every entry is contained: a service that failed to load degrades **that one answer** and never
throws into your module. Every one of them also has a documented direction for "I could not tell",
and the direction is always the safe one — see each section.

### 6.1 Identity and plumbing

```lua
S.id       -- 'bst-helper'   the folder name; the loader's answer, not yours to declare
S.job      -- 'bst'          the JOB FOLDER you filed under (not where you act -- that is `jobs`)
S.sibling('reward')          -- require one of your own files, by bare name
S.now()                      -- monotonic seconds
S.say.err('Reward: you are not carrying any pet food.')
```

**`S.sibling` is the reason a rename is safe.** It resolves against the identity the loader
actually assigned, so nothing inside your module ever spells its own path.

**`S.now()` is the one clock, and using it is not a style preference.** It is the cmdqueue frame
counter (the addon's steady tick), falling back to `os.clock`. Measure every lockout and every
debounce against it — never `os.time`, and never a second clock of your own. `os.clock` is process
CPU time on some builds, and two clocks compared against each other is a bug that only shows up in
the field.

**`S.say` is the only route to chat.** Success is silent; a refusal is one line naming the blocker
(§7.2). Never `print`, never a `/echo` through the command door.

### 6.2 Acting — a sequence, or a bare command

**If your act needs something WORN first, open an Action sequence.** Read the *Action sequence*
entry in CONTEXT.md first, then:

```lua
local res = S.act.request({
    label   = 'Reward',                      -- the ACT's name; appears in refusals and /dl why
    claim   = { Ammo = 'Pet Food Theta' },   -- slot -> item; dressed BEST-EFFORT
    need    = { Ammo = 'Pet Food Theta' },   -- MUST verify worn or nothing fires
    command = '/ja "Reward" <me>',
    timeout = 4,                             -- seconds; gear not landing in time ABORTS
});
-- res.ok == true  -> the sequence is live
-- res.ok == false -> res.reason ('busy' | 'bad-request' | 'service'),
--                    res.holderLabel names the module that is mid-act
```

`module` and `order` are filled in **from your identity** — you cannot request as somebody else,
and you cannot get your own priority wrong.

The lifecycle is `claimed → verified worn → fired → released`, or `refused(reason)` /
`aborted(reason)`. What that buys you, and what it costs you:

- **Never-fire-bare.** The command fires only after every `need` slot reads worn, and exactly once.
- **`need` should be the CONSUMED or PRECONDITION slot alone.** Reward eats what is worn in Ammo;
  Call Beast reads the jug worn in Ammo. Everything else is costume — claimed-but-not-needed slots
  dress best-effort, so a senior claimant taking one costs you that slot and refuses nothing, while
  every extra *needed* slot is one more way for the whole act to be refused.
- **Release restores the gear.** Dropping the claim kicks a dispatch and the next arbitration
  re-dresses the slots. You never restore anything yourself.
- **You ride the shared `JobHelper` claimant row**, ranked by default directly below Locks: above
  every standing Gear helper, below Locks, Naked and Free equip. A senior claimant holding a slot
  you *need* is a loud refusal, never a bare fire. That ranking is the player's to drag.
- **One sequence is live at a time, addon-wide, and a started one is never preempted.** `busy` is a
  **hold**, not a failure — and holding attempted nothing, so it must not arm your lockout.

**If your act needs nothing worn, use the command door.**

```lua
S.cmd('/pet "Fight" <t>');
```

Do not open a sequence for a bare command; you would be taking the one shared claim slot for
nothing. Two facts the queue exists for: two commands issued in the **same frame** arrive
*reversed* in other Lua states, and an addon state never hears its own queued commands back. So if
two of yours must arrive in a known order, give them different frames.

**`<t>` resolves when the command EXECUTES**, not when you decided. That is exactly right for a
beat that just read the target, and exactly wrong for a decision made 800 ms ago. This is not a
hypothetical: it is what failed the BST Fight switch's second live round (§6.4).

### 6.3 Am I acting? — the one gate

```lua
local act = S.me.acting();
-- { active = bool, reason = 'off'|'job'|'zoning'|'dead'|'town'|nil, label = 'In town' }
```

The ONE gate every Job helper consults — never write a second copy of these rules. The precedence
is fixed, and it is also the order to **report** in, so the most specific true statement wins:

```
off (the pill)  →  wrong main job  →  zoning  →  dead  →  in town  →  active
```

An unknown read (a job that has not settled, an unreadable town answer) never manufactures a
reason: the module stays "active" on an unreadable world. Your own gates then decide which way
*their* nils go — and for anything that issues a command or spends an item, `active` must be
**positively true** before you act:

```lua
if state.active ~= true then return { act = false, reason = state.reason or 'inactive' }; end
```

`~= true`, not `== false`. This is the single most common way a helper misbehaves, so every rule in
the codebase is written this way: **a read you could not make is never permission to act.**

`S.me.order()` is your tie-break priority when two modules of the current job contend for the
sequencer in the same step — your row's position in that job's section, as the player dragged it.
Higher wins. It is a fact about the *module*, so all of your rules share one answer; you never
invent a number (and `S.act.request` fills it in for you anyway).

### 6.4 Combat — one service, two shapes

```lua
S.combat.subscribe('fight', function(c) ... end)
-- c = { engaged, targetIndex, targetName, targetChanged, changedBy, swung, at }
S.combat.state()                -- the same record, read NOW (no `targetChanged`: see below)
S.combat.onEdge('rule', function(edge) ... end)
-- edge = { kind = 'engage'|'retarget', index, serverId, name, at }
```

The **beat** (0.4 s, the engine's own dispatch cadence) carries the state a standing rule gates on.
The **edge** is the moment. You do not have to choose which is authoritative, because the service
already did: `targetChanged` on the beat is answered by the **retarget packet** whenever one
arrived (`changedBy == 'edge'`) and by its own poll otherwise (`changedBy == 'poll'`).

**Why it is built that way — do not re-derive this.** The BST Fight switch was built edge-driven
and failed two live rounds on this server. Round 1: the client sends `0x0F`-then-`0x02` pairs on a
fresh attack, so a target-only debounce key swallowed the engage as stutter. Round 2: the
*captured-entity confirm* refused every send. It was rewritten on the field-proven **poll** shape
— every beat, ask "engaged + pet idle + target?", then issue — where the pet-idle gate is
simultaneously the spam brake **and the retry**.

Read that history precisely, because the useful lesson is narrower than "edges don't work":

- What round 2 indicted was using the packet's captured entity as the command's **target**. Fire
  `<t>` and the problem disappears.
- What the poll bought, and an edge cannot, is the **retry**: a refused command leaves the world
  unchanged, so the next beat tries again, where an edge fires once and a server refusal is lost.
- What the edge buys, and a poll cannot, is **precision about a change**: a poll cannot see an
  A→B→A switch inside one beat, and cannot distinguish a real target change from an entity index
  the server recycled. The edge carries the server id.

So: gate on the beat, and trust `targetChanged`. `targetIndex` / `targetName` are for **display and
change detection** — never build a command out of them.

`state()` deliberately answers `targetChanged = false`: "changed since when?" has no meaning
outside the beat that measured it. If you need the change signal, subscribe.

### 6.5 The pet

```lua
S.pet.get()                     -- { present, hpp, tp, name, status } -- reads NOW
S.pet.subscribe('reward', function(v) ... end)   -- the same record, per beat, with `at`
S.pet.onLoss('resummon', function(edge) ... end) -- your pet is gone, and WHY
```

Two laws travel with the answer, and both are load-bearing:

- **Dead pet = no pet.** A pet at 0 HP% is not a pet any consumer may act on.
- **Presence is two-state on purpose.** "No pet" and "the read could not be made" answer
  *identically*, because every consumer issues a command or spends an item, and a read we cannot
  make is not permission to do either. Individual vitals stay nil-able: a present pet whose HP could
  not be read is reported honestly — refuse on the nil, never guess.

Measure your lockout against the beat's own `at` stamp, so the decision and the vitals it read
describe the same moment. (`get()` has no cache and no stamp: it reads now.)

**The loss edge** carries *why*. **Death is confirmed, never assumed:** only the pet-falls chat
line and a vanish after a low last-seen HP% prove one; an observed outgoing Leave, zoning and
logging out each *suppress*, and are checked first; everything else is `unknown`, which confirms
nothing and lets nothing act. The asymmetry is deliberate — a missed resummon costs a player
nothing, a wrongly-assumed one costs them a jug.

**The service owns the rule; you own the list.** Jug-vs-charm is decided by *name*, through an
authority you inject:

```lua
S.pet.nameAuthority(function(name) return myRoster.isJugPet(name); end)   -- true / false / nil
```

`nil` means "cannot tell", and an unknown pet is not yours. The next module's roster will be its
own — never push your data into a service's own tables.

`S.pet.food()` is the **pet-food ladder**: the highest tier this character can both wear and is
carrying, read off the bags. There is deliberately no list UI and no tier setting — the best food
you are carrying is the right food, always. Carrying none is a loud refusal, and
`S.pet.foodRefusal(pick)` is the sentence for it.

### 6.6 Abilities

```lua
local ready, remaining = S.ability.ready('Divine Seal');
local ready, remaining = S.ability.ready({ name = 'Reward', timerId = 103 });   -- if you know the slot
```

A name is enough, and **the live reader is wired for you**. That second part is not a convenience:
the underlying core is pure, so calling the raw service without a reader has nothing to measure and
silently answers READY — an api-1 footgun this guide had to warn about in prose, and now cannot
happen. A declared `timerId` wins when you have one; otherwise the slot resolves **by name**
through the client's own ability resource, because live game memory outranks every other source
(hard rule 9) and an ability this server renumbered still resolves.

**UNKNOWN READS READY.** A recast we cannot measure must never be the reason a player cannot press
a button, and the sequencer's own verify-worn is the real safety net. Use this to **grey out** a
button and to hold a rule **silently** — never to manufacture a refusal you did not measure.

### 6.7 Items, gear and named sets

```lua
S.item.own('Carrot Broth')     -- how many can I EQUIP right now  (0 when it cannot answer)
S.item.stored('Carrot Broth')  -- owned anywhere, including storage
S.item.worn('Ammo')            -- what is in that slot now, by name, or nil
S.item.info('Carrot Broth')    -- { Id, Name, Level, Jobs, Slot, Stats, ... } or nil
S.sets.names()                 -- { 'Idle', 'Reward', ... }  -- the player's DYNAMIC sets
S.sets.slotsOf('Reward')       -- { Head = 'Beast Helm', Body = 'Beast Jackcoat' }
```

**Ask by name.** The underlying availability map is keyed by item id, which is why every api-1
module that asked this question carried its own name-to-id table.

**`own` is the number that decides whether an act can happen** (equippable bags); `stored` is for
*explaining* why it cannot. `own` answers **0** when it cannot see the item — an item we cannot see
is an item not carried, which refuses rather than firing an act bare. That is the safe direction,
chosen on purpose.

**`names` is the Dynamic library — the sets the player builds in the Sets tab**, which are the only
ones this character's engine gears from. It answered the *static* sets until 2026-07-30, and that
was a bug with a field report attached: the statics are the pre-profiles job file's flattened
leftovers plus whatever a pre-migration backup still holds — the Copy-from helper's **import
sources**, not a live library — so a migrated character's Reward picker listed sets they had not
edited in months and none of the ones they use. One namespace, and it is the one they can see.

**`slotsOf` exists so you never parse the sets format**, and it answers with the piece the ENGINE
would equip: a Dynamic set is a *ladder* per slot (level rungs, mode gates, Sub pairing, virtual
entries), and `slotsOf` hands back the head rung the last flatten chose at the live level. A module
that walked the ladder itself would drift from the engine the first time a rung was level-gated.
The raw walk survives underneath as the degraded path (pre-login, headless), where an entry may be
a plain string or a table carrying `Name` / `name` / `item` depending on how the set was authored or
imported — the sets format's business, not yours.

The result of `slotsOf` is already the right shape to hand to `S.act.request` as a `claim` — but
**copy it before you edit it**. It is yours to read, not to mutate: the sequencer keeps a claim for
the life of the sequence, and whether `slotsOf` allocated that table fresh is not a promise you
should be leaning on. (The BST Helper leaned on it for exactly one afternoon; a test caught it.)

### 6.7b Keys — two reads, and no writes

```lua
S.keys.boundTo('summon')   -- the key that action holds NOW, as the player typed it, or nil
S.keys.holder('^F3')       -- { owner, label, command } | nil  -- who has this key
```

You never register or release a key: declare `commands[action].key` (§2.7) and the framework
installs the group. These two exist so a Panel can render a key field **honestly** — a key you
STORED and a key you HOLD are different facts, and the gap between them (somebody else has it) is
the one worth printing. Ask `holder` before you save a key the player typed: the registry refuses a
second claim, so a Panel that does not ask lets them save a key that will never fire.

### 6.8 The escape hatch

```lua
local x = S.service('dlac\\feature\\something');   -- nil when unreachable
```

For a first-party service that has no `S` entry yet — a job-specific ladder, a calculator, anything
domain-shaped that a generic API should not carry. It is a real, legitimate tool; it is also
**unsupported**: what you reach through it may move or change shape without an `api` bump.

Named `S.service` rather than left to a bare `require` for exactly one reason: it is obvious in a
diff and in a code review that a module reached past the front door, and that is a conversation
worth having — usually ending in a new `S` entry.

### 6.9 The Panel — `ctx.ui`

Your Panel is handed the **widget kit**, already bound to the host's imgui handle:

```lua
panel = function(ctx)
    local ui, S = ctx.ui, ctx.S;
    ui.section('Fight', TIP_FIGHT, function()
        local picked = ui.choice('fight_' .. S.id, {
            values = fight.MODES, labels = fight.MODE_LABEL, helps = fight.MODE_HELP,
        }, fight.mode());
        if picked ~= nil then fight.setMode(picked); end

        ui.ruleStatus({
            armed     = (fight.mode() ~= 'off'),
            activity  = S.me.acting(),
            offText   = 'Fight is off -- pet commands stay entirely yours.',
            armedText = 'Armed: ' .. fight.MODE_LABEL[fight.mode()] .. '.',
            last      = lastLine(fight),
        });
    end);
end,
```

The kit:

| Call | What it is |
|---|---|
| `ui.section(label, tip, body)` | Header + hover explanation, your body, a rule underneath. |
| `ui.header(label, tip)` | Just the header. |
| `ui.toggle(id, label, value, tip)` | Checkbox. Returns the **new** value, or `nil` if untouched. |
| `ui.choice(id, opts, current)` | An exclusive choice as a lit/unlit button group. Returns the picked value or `nil`. |
| `ui.slider(id, value, min, max, fmt, tip)` | Returns the new value or `nil`, plus whether it drew. |
| `ui.combo(id, current, rows, labelOf, tip, noneLabel)` | Dropdown over any list. Returns the picked row or `nil`. |
| `ui.button(id, label, tip, w, h)` | Returns `true` on click. |
| `ui.pill(on, id, tipOn, tipOff)` | The green/red on-off pill. Returns `true` when toggled. |
| `ui.ruleStatus(spec)` | The two lines every standing rule owes the player — see below. |
| `ui.ok/warn/err/dim(text)`, `ui.text(col, s)`, `ui.disabled(s)` | The house palette. |
| `ui.space()`, `ui.rule()`, `ui.sameLine(gap)` | Layout. |
| `ui.COL` | `{ head, dim, ok, warn, err, lit }`. |

**Every control returns the new value only when the player changed it**, so an untouched frame
writes nothing — which is what makes the mutation-only settings store cheap.

**Why a kit and not a list of conventions.** Each of these encodes a lesson that cost something to
learn, and prose transmits lessons only to authors who read carefully and remember:

- **Presence proves nothing** (hard rule 2). `BeginPopupContextItem` is bound in this Ashita install
  and does not work. So a widget is used only where dlac already drives it in the field, and every
  call is guarded. A binding without a widget degrades to text, never to an error.
- **`RadioButton` is called nowhere in dlac**, so a small exclusive choice is a lit/unlit `Button`
  pair. That is what `ui.choice` is.
- **A hardcoded width has clipped a trailing character in the field more than once.** `ui.choice`
  and `ui.widthFor` **measure** the widest label.
- **The right-hand Panel child is whatever is left of a window whose minimum is 480**, so exclusive
  choices **stack** vertically by default; three side by side wanted ~520px and clipped.
- **The panel-text standard**: never hang an explanatory paragraph off a label — it clips at the
  panel edge. The label is underlined and the explanation lives in its hover. That is
  `ui.section` / `ui.header`.
- **Every imgui text call is a `printf` format string**, so a `%` in your text is a *conversion*.
  The Reward rule's `below 51% pet HP` reached the field as `below 51F4A60263et HP` — `% p` read as
  `%p`, a heap address printed, the `p` eaten (2026-07-29). The kit **escapes** every string it
  draws and every tooltip it attaches (`panelkit.esc`), so write percent signs plainly in `ui.dim`,
  `ui.ok`, `ui.warn`, `ui.err`, `ui.disabled`, `ui.header` and `ui.ruleStatus`. If you ever call
  `ctx.imgui.Text*` yourself, escaping is **yours** — use `ctx.ui.esc(s)`.
- **Stack discipline**: every `Push` pops on every path, every `BeginCombo` that returned true ends.
  The frame-level recovery in `uihost` is the host's guard against a torn frame; the kit is what
  keeps it from being needed.

`ui.ruleStatus` deserves its own note, because the **colour split is the load-bearing part**:

```lua
ui.ruleStatus({
    armed     = <your rule's own switch>,
    activity  = S.me.acting(),
    blocked   = <your own blocker, or nil>,      -- checked BEFORE the activity gate
    offText   = 'The rule is off -- ...',
    armedText = 'Armed: below 50% pet HP.',
    last      = <your decisionText(lastDecision()), or nil>,
    lastLabel = 'Last beat',
})
```

- **dim** — the rule is off. Not a problem; the player turned it off.
- **warn** — something the *player can fix* is blocking it: wrong job, town, dead, zoning, no jug
  picked. Orange means "look at me".
- **ok** — armed and acting.
- **dim**, underneath — what the last evaluation decided.

What must **not** be warn is *the rule working*: "no pet out", "above the threshold", "waiting out
the lockout" happen on most beats, and colouring them orange would cry wolf all session. They
belong in the dim `last` line. This is precedence, not decoration, which is why it lives in the kit
rather than in each Panel.

**Do not add UI outside your Panel and your declared `window` hook (§2.8).** No tabs, no ad-hoc
windows, no chrome. The window hook IS the promised second surface, arrived 2026-08-04; anything
further will come the same way — through the framework, never from a render hook.

**Report state in the Panel, not in chat.** A rule that evaluates every beat has nothing to say on
most beats; only an *attempt* is news.

### 6.10 Where `S` comes from — how it is declared and instantiated

You never construct it, but knowing how it is built answers most "can I…?" questions, so:

**It is a plain Lua table from a factory function.** No class, no metatable, no inheritance —
`modapi.build(rec)` in `feature/modapi.lua` returns a fresh table per module:

```lua
function M.build(rec)
    local id  = tostring(rec.id or '?');       -- captured by every closure below
    local job = tostring(rec.job or '');

    local S = { api = M.API, id = id, job = job, label = rec.label, jobs = rec.jobs };

    local function who(name) return 'jobhelper:' .. id .. ':' .. tostring(name or 'main'); end
    S.who = who;

    S.me = {};
    function S.me.acting()
        return ask('dlac\\feature\\jobhelpers', 'activity',
                   { active = false, reason = nil, label = '?' }, id);   -- `id` from the closure
    end
    -- ...S.player, S.combat, S.pet, S.ability, S.item, S.sets, S.act...

    S.cfg = rec.cfg;                            -- the store the loader already opened
    S.ui  = svc('dlac\\ui\\panelkit');
    return S;
end
```

**When, in the load sequence:**

```
dlac.lua              jh.load(deps)
  ↓
jobhelpers.load()     scan jobhelpers\<job>\<module>\, record the job of each id
  ↓  per candidate folder:
loadAll()             require <module>\init          → the contract table
                      _validate(id, mod)             → rec = { id, label, jobs, mod }
                      rec.job  = M._jobOf[id]
                      rec.cfg  = M._openCfg(rec)     → modcfg.open(id, mod.config)
                      rec.S    = M._buildApi(rec)    → modapi.build(rec)
                      pcall(rec.mod.init, rec.S)     → YOUR init(S)
                      M.modules[#M.modules+1] = rec  → S now lives on the record
  ↓  later, every frame your Panel is open:
jobhelpersui          ctx = { ..., S = rec.S, ui = panelkit.bind(imgui) }
```

Five things follow, and they are the practical answers:

- **`S.cfg` is live before your `init` runs.** The store is opened one line earlier, so reading
  settings inside `init` is fine.
- **It is built once and reused.** The same table goes to `init` and to every subsequent Panel
  render. Stashing it in a module-level `local _S = S` is the normal pattern and is the same table
  your Panel sees — that is how a rule file reaches its settings without being handed anything.
- **The closure over `id` is the whole correctness story.** `S.me.acting()` passes `id` from the
  closure, not from an argument, so there is nothing to get wrong: a module cannot ask as another
  module, cannot declare its own identity, and cannot collide on a subscription key.
- **Nothing is resolved at build time except `S.cfg` and `S.ui`.** Every service entry `require`s
  at *call* time through two contained helpers (`svc` / `ask`). So load order does not matter, a
  missing service degrades exactly one answer, and you never need a `pcall` around an `S` call.
- **Subscription bookkeeping is module-level, not per-table.** `modapi` keeps one record of every
  subscription keyed by module id, which is what lets `modapi.dropAll(id)` undo a module's beats.

**Building one yourself** — for a test, or to poke at it:

```lua
local ma = require('dlac\\feature\\modapi');
local S  = ma.build({ id = 'x-helper', job = 'whm', label = 'X', jobs = { 'WHM' } });
```

For driving a *rule* headlessly, prefer the suite's `fakeApi` (§9): `S` is duck-typed, so a fake is
just a table carrying the fields your rule touches — plus recorders for what it did.

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
injectable reads, headless tests — add its row to architecture.md's Central-services table, and
then **add its entry to `S`** so the next module finds it without reading source. Not to keep a
private copy.

The corollary is what `S` is for: if a question you need has no entry, say so. A missing entry is a
gap in the front door, and filling it is cheap — most entries are one line pointing at a service
that already exists. Working around it with a private copy is the thing this rule exists to
prevent, and reaching past `S` with `S.service()` is the honest middle step while the entry is
being added (§6.8).

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
  is refused loudly. You do not have to do anything about this: `S.act.request` fills `order` in
  from your identity, and `S.me.order()` is there if you want to show it. Never invent a priority
  number of your own.
- **Section order is a fact about the module, not about your rule.** All of your rules share one
  answer by construction — that is why the framework owns it, and why a module cannot get it
  wrong or claim somebody else's.

Design for it: a rule that *must* act right now cannot, if another module is mid-act, and that is
the correct outcome. Serialization is what makes "one claim, one send per dispatch" true, and it
is what stops two helpers dressing the same slot for two different acts in the same beat.

---

## 8. A complete module, end to end

**It ships in the repo, and it works:** `docs\templates\example-helper\`. Copy the folder to
`jobhelpers\<job>\<your-module>\`, change the four `CHANGE ME` spots, reload. It is held to the
same bar as a real module — the suite loads it, runs it through the real contract validator, and
drives its rule against every law in §7 (`TPL*` in `tests\run_tests.lua`), so it cannot rot into
an example that no longer loads.

```
docs\templates\example-helper\
    init.lua      the contract table: api, label, jobs, config, init, panel, status
    rule.lua      one standing behaviour in the house shape
    README.md     the two-minute version of this guide
```

**The house shape, which is what to actually copy:**

```lua
decide(signal, state)   -- PURE. Signal + state in, decision out. No services, no clock,
                        -- no world. Every acceptance criterion is one check against a
                        -- synthetic state.
liveState()             -- Assembles that state from S. ALL the world-touching lives here.
onBeat(signal)          -- Joins them: one signal -> one decision -> at most one act.
init(S)                 -- Subscribes. Called from your init.lua hook.
```

Keeping `decide` pure is the whole trick, and it is not an aesthetic preference. It is what makes
"an unreadable world is not permission", "one attempt per window" and "busy is a hold, not a
failure" provable in tests that run in milliseconds with no game — which is the difference between
believing your helper is safe and knowing it.

**For a bigger reference, read the shipped module:** `jobhelpers\bst\bst-helper\`. It is the same
shape at scale — three rules in three files, its own data table, one Panel — and it is where to
look for the two things the template does not show:

| You want to see | Look at |
|---|---|
| An act with an equip **precondition** (claim, verify worn, fire, release) | `reward.lua` — `buildRequest` + `request` |
| A rule driven by an **event** rather than a beat, with a queue | `resummon.lua` — `decideLoss` / `queueDecide` |
| Injecting your own **data** into a service's rule | `resummon.lua` `init` → `S.pet.nameAuthority` |
| A Panel with three sections on the widget kit | `init.lua` — `panel` |
| Module-owned data with per-row provenance | `jugs.lua` |

---

## 9. Testing your module

dlac's suites run headless on Lua 5.4 with no Ashita, no imgui and no character; write to the
Lua 5.1 / LuaJIT intersection so the same code loads in-game.

- **`lua tests\run_tests.lua`** — the logic suite. Add every file of your module to the `JOBHELP`
  roster in the guard block (entries are module paths relative to `jobhelpers\`, without the
  extension: `'bst/bst-helper/reward'`). Then test your **pure deciders**: state in, decision out,
  one check per acceptance criterion.
- **`lua tests\smoke_ui.lua`** — the stub-imgui render suite. It draws every registered tab with a
  stub binding and asserts a **balanced imgui stack**. A Panel that pushes without popping fails
  here, which is the cheapest place to find it.
- **`luac -p <file>`** on every touched file — the fast syntax gate.

**Driving a whole rule headlessly is one fake.** Because every service, the clock, the settings
store and both act doors arrive on `S`, the suite has a single helper — `fakeApi` in
`tests\run_tests.lua` — that stands in for the module API. It **records** what a rule did (`sent`
for bare commands, `acts` for sequence requests, `lines` for chat) and lets a test drive what the
world says back:

```lua
local S = fakeApi({ id = 'my-helper', job = 'whm',
                    siblings = { rule = rule },        -- what S.sibling() resolves
                    vals     = { armed = true },       -- the settings store's contents
                    acting   = { active = true },      -- the activity gate
                    pet      = { present = true, hpp = 30 },
                    stock    = 3, clock = 100 });
rule.init(S);
rule.onBeat({ engaged = true, targetIndex = 5, at = 100 });
check('one beat issues one command', #S.sent, 1);
```

Each door is a plain field, so a test can retarget any single one of them
(`S.act.request = function(r) ... end`) — including pointing it at the **real** sequencer to prove
a refusal actually lands, which is how the BST suite proves "the button and the rule refuse
identically" rather than asserting it.

Under `api = 1` this took six `package.loaded` stubs per section and the rule found them by
hardcoded path; a rule that passed proved only that your stubs matched your guesses. Now a rule
that passes is provably calling the real surface.

Test **at the seams**, never module-private state: decisions, resolutions, lifecycle transitions,
rendered output, chat lines. The framework's own loader fixtures (a good module, a wrong-`api`
module, a throwing module) live in the suite and show how a module is driven with no filesystem.

---

## 10. Gotchas, in the order they will bite you

1. **Your `api` must equal the running dlac's**, exactly. `2` today.
2. **Load your own files with `S.sibling('rule')`, never by path.** Identity is the folder name;
   a hardcoded path means renaming the folder breaks your module while the loader happily accepts
   the new name.
3. **Gate with `~= true`, not `== false`.** An unreadable world answers `nil`, and a read you could
   not make is never permission to act. This is the most common way a helper misbehaves.
4. **Pre-login is `nil` everywhere** — the character directory, the job, the world. `S.cfg` already
   handles it (defaults on read, `false` on write, retried next call). Do the same in your own
   reads: never cache the nil and never latch on it.
5. **`S.pet.get()` answers `present = false` for "no pet" AND for "I could not tell".** On purpose.
   Do not act on either.
6. **A throw in `init` costs you the whole module**; a throw in `panel` costs you only the Panel.
   Guard each subscription separately.
7. **Two same-frame commands arrive reversed** in other Lua states. Give them different frames.
8. **`<t>` resolves when the command executes**, not when you decided. Never build a command out of
   a `targetIndex` you are holding — that is what failed the Fight switch's second field round.
9. **`busy` is a hold, not a failure**, and a hold that attempted nothing must not arm your
   lockout. Same for a measured cooldown, which is additionally silent.
10. **The row pill defaults ON and your behaviors default OFF.** Different switches with different
    jobs; do not collapse them.
11. **A drag on a slider is one `set` per frame** unless you clamp on the way in. Clamp to the
    granularity you actually store and the mutation-only store does the rest.
12. **`pairs()` order is undefined.** Any order you depend on must be explicit — the sequencer's
    own tie-break is deterministic for exactly this reason.
13. **`S.ability.ready` answers READY when it cannot measure.** Use it to grey out a button, never
    to manufacture a refusal.
14. **Bumping `dispatch.M.VERSION` is not yours to do** — it is the engine handshake and matters
    when seeded-file behavior changes. Module settings never touch it.

---

## 11. What dlac will not do for you

- **Sandbox you.** No restricted `_ENV`, no capability tiers, no allowlist. dlac ships as readable
  Lua, so a wall buys attribution, not prevention (ADR 0028). What you get instead is visibility:
  a loud refusal, a ledger entry, a contained frame — and a contract in this document.
  `S` is a **front door, not a wall**: it is the surface that is documented, versioned and tested,
  and the reason to use it is that it will keep working, not that anything stops you leaving it.
- **Hot-plug you.** Reload the addon.
- **Preserve your data across an uninstall.** The framework remembers the player's pill, section
  order and Claim Priority position; your own config file is yours to keep or remove.
- **Give you a second sequence, a second claim row, or a way past the Arbiter.** One live
  sequence, one shared `JobHelper` row, and Locks / Naked / Free equip outrank you by design.
- **Approve you.** One folder, one approval request. That conversation is between the module and
  the server's staff — dlac's own approval does not extend to what your module does.
