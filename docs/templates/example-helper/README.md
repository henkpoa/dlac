# Job helper template

A **working** Job helper, kept here rather than under `jobhelpers\` because the loader
treats every folder directly under `jobhelpers\` as a *job* folder — a template living
there would load as a job called "templates".

## Use it

```
copy  docs\templates\example-helper\
  to  addons\dlac\jobhelpers\<job>\<your-module>\
```

Then, in order:

1. **`init.lua`** — change the four spots marked `CHANGE ME`: `label`, `jobs`,
   the `config` keys, and the ability in `status`.
2. **`rule.lua`** — change `M.COMMAND` / `M.ABILITY` and the body of `decide`.
3. **`/addon reload dlac`.** There is no hot-plug. Your row appears under its job's
   section on the Job Helpers tab; `/dl check` counts it. If it was refused you get
   exactly one loud chat line naming your folder and the reason.

The folder name is your **identity** and your **unit of server approval** — a GM reads
and approves your folder, not dlac's. Nothing inside the module hardcodes that name
(siblings load via `S.sibling('rule')`), so renaming the folder is safe.

## What is in the box

| File | What it is |
|---|---|
| `init.lua` | The contract table: `api`, `label`, `jobs`, `config`, `init`, `panel`, `status`. |
| `rule.lua` | One standing behavior in the house shape: a **pure** `decide`, a `liveState` that does all the world-touching, an `onBeat` that joins them, an `init` that subscribes. |

Two files is the whole minimum. `init.lua` is the only one the loader requires; split
out a file per rule and one for your data as you grow.

## The shape, and why it is that shape

- **`decide` is pure** — signal and state in, decision out, no services and no clock.
  That is what makes every rule of your helper a millisecond-long test with no game
  running, which is the difference between "I think this works" and "this is checked".
- **Positive-true gates.** `if state.active ~= true` and not `== false`. An unreadable
  world answers `nil`, and a read you could not make is never permission to act.
- **Default OFF.** Anything that issues a command — and especially anything that
  spends an item — is armed by the player, never by installation.
- **One attempt per lockout window.** A rule reads a *state*, and states persist; a
  budget is what stops one condition becoming a stream of commands and chat lines.
  Holds that attempted nothing (`busy`, `cooldown`) must not arm it.
- **Success is silent, refusals are one line.** State belongs in the Panel, not in
  chat: a rule evaluating every beat has nothing to say on most beats.

## Where to look next

- **`docs\reference\jobhelper-authoring-guide.md`** — the full contract, every service
  on the module API, the hard rules, and the gotchas in the order they will bite you.
  The comments in these two files carry its section numbers.
- **`jobhelpers\bst\bst-helper\`** — the shipped module, and the reference for a
  helper with three rules, its own data, and an act that needs gear worn first.
