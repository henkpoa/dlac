# The support report (`/dl report`) — file format

**Audience: whoever reads a player's report file, human or model.** This document
pins the layout so you can navigate one without re-deriving it, and states what
each section can and cannot tell you.

Produced by `feature/report.lua`. One file per run, overwritten:

```
addons\dlac\debug\dlac-report-<Char>.txt      the report -- this is the one to read
addons\dlac\debug\dlac-capture-<Char>.log     the raw live log, streamed as it happened
```

The `.log` is written *during* the window and folded into the report at the end.
If the report is missing but the log is there, **the client died mid-capture** —
which is itself the finding. Read the log; its tail is the last thing dlac saw.

## How it was made

`/dl report [seconds|full|stop]` (60–300s, default 300), the **[Record a report]**
button in the Arbiter Monitor, and `/dl mark <note>` for the marks. The recorder
is a session thing: it never persists, and it stops on window expiry, an explicit
stop, or addon unload.

## Sections, in order

Each begins `===== SECTION: <name> =====`. Bundled files inside the config section
are fenced `===== FILE: <label> (<n> bytes) =====` … `===== END FILE =====`.

| Section | What it holds | What it proves |
|---|---|---|
| *(header)* | char, dlac + engine version, window stamps, scope, stop reason, the privacy paragraph | which build this is; whether the window covers the incident |
| `health` | the `/dl check` readout verbatim (`check.gather` → `check._lines`) | module load failures, a truncated catalog, an engine/file version split. **Read this first** — a broken install explains most "bugs" |
| `summary` | six counters + the mark list with offsets and decision numbers | where to look. Marks are the player pointing at the moment |
| `config` | the active job's sets / triggers / lockstyles, plus every small settings file in the character data home | what dlac was *asked* to do |
| `gear digest` | every item named by the window, with id / level / jobs and **whether it is in an equippable bag right now** | why a ladder fell to `unavail` |
| `log` | pre-roll + the timeline | what dlac actually did |
| `manifest` | every dlac data file on the character with its size, bundled or not | what else exists to ask for |

## Reading the log

The log opens with `===== PRE-ROLL =====` — the decision ring, action feed and
send ring **as they already were when recording started**. dispatch keeps 50
decisions and 32 actions in memory at all times, so the minute before the button
is usually in the file. Everything after `===== LIVE =====` happened during the
window.

A decision block:

```
[12:34:56] #42 Precast -- Cure IV   (2 slots changed)
      under: WHM75/RDM37  Idle  MP 62%  Fire day / clear  modes: Town
      buffs: Refresh
    Head    Nahtirah Hat                   <- Triggers (rank 11)
            also asked: MaxMP:Zenith Crown
            fell: Chapeau -> Nahtirah Hat (Chapeau is not in a bag you can equip from)
            ladder (Precast): 1.Chapeau [x not in your bags]  2.Nahtirah Hat
```

Only slots that **changed or fell** are printed. `under:` is the world as
captured *at decision time*, not as it is now — a `weatherMatch` question is
unanswerable without it. Other line kinds: `[hh:mm:ss] SEND 0x050 <cause>`,
`[hh:mm:ss] action <event> -- NO gear change` (the anchor for "I did a thing and
gear did not move"), `***** MARK +2:14 -- <note> *****`, and dlac's own chat lines.

The vocabulary — *fell*, *reserves*, *not in a bag you can equip from*, *held
EMPTY* — is deliberately identical to `/dl why` and the Arbiter Monitor's hover.
A player quoting one and you reading the other are looking at the same sentence.

## Marks: one moment, one mark

A mark belongs to a **moment**, and the moment is the decision the ring was newest
on when it was placed — this addon's own word for an event. Each summary entry
therefore carries `at decision #N`, which is a jump: the log block headed `#N` is
what the player was looking at when they said those words. `(no decision yet)`
means gear had not moved at all, which is often itself the report.

Marking the same moment again **replaces** the note rather than adding a twin, and
the Monitor's button becomes **[Un-mark]** once the moment is flagged. The log is
append-only and never rewritten, so a replacement or a removal appends its own line
(`MARK REPLACED … (was: …)`, `MARK REMOVED (was …)`) — the timeline records that the
player changed their mind; only the summary index is deduplicated. If the mark list
and the timeline seem to disagree about how many marks there were, that is why, and
the timeline is the literal record.

## What is deliberately **not** in it

- **Raw `gear.lua`** (~264 KB of bag index) unless the player ran `/dl report full`.
  The digest carries the items that were actually involved; the manifest proves the
  file exists. If the digest scoped it wrong, ask for a named file — that is what
  the manifest is for.
- **Other jobs' sets and triggers**, unless `full`.
- **Any chat that is not dlac's own `[dlac] ` output.** No tells, no party chat.
- **File modification times.** Ashita's Lua has no stat call, so the manifest
  carries sizes only.
- Anything dropped for size. Every exclusion is a named line with its reason —
  under `NOT BUNDLED` in the config section. A silently truncated bundle that
  reads as complete is the one failure mode this format refuses.

## Scopes

| | default | `full` |
|---|---|---|
| active job's sets/triggers/lockstyles | verbatim, never size-capped | verbatim |
| other jobs | manifest only | verbatim |
| settings files in the char root | verbatim under a 32 KB per-file cap | verbatim, no per-file cap |
| seeded engine code (`dispatch.lua`, `utils.lua`, …) | never | never |
| `gear.lua` | digest | digest **and** raw |
| total budget | 768 KB | 4 MB |

The per-file cap is a scoping device for the default run, not a second ceiling
inside an explicit `full` ask. The total budget is the one hard limit either way.

The budget is a context budget, not a disk one: the file is meant to be read whole.
