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
| `health` | the `/dl check` readout verbatim (`check.gather` → `check._lines`) + the report's own engine verdict | module load failures, a truncated catalog, an engine/file version split. **Read this first** — a broken install explains most "bugs" |
| `summary` | six counters + the mark list with offsets and decision numbers | where to look. Marks are the player pointing at the moment |
| `config` | the active job's sets / triggers / lockstyles, plus every small settings file in the character data home | what dlac was *asked* to do |
| `gear digest` | two lists — what the window involved, and what the job's sets *ask for* but never used — with id / level / jobs, live bag availability, and an **`ABOVE YOUR LEVEL`** flag | why a ladder fell to `unavail`, and why a set that looks fine did nothing |
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

### `(left as worn)` and the header breakdown

The ring counts a slot as *changed* when it was in the previous plan and is
absent from this one. So a decision that placed **nothing** still reports a
count, and its rows read `(left as worn)`:

```
[16:33:35] #2 Weaponskill -- "Double Thrust"   (7 slots changed -- 0 placed, 7 left as worn)
      note: the (left as worn) slots below got nothing from this decision -- either
      its set does not name them, or nothing it names qualified (level, job, or you
      do not own it). What you had on stayed on. See the gear digest.
```

`0 placed` is the tell: the set produced nothing and the previous gear stayed on.
**Go straight to the digest's second list** — the usual cause is that every piece
in that set is above the player's level. The breakdown appears only when `placed`
and `changed` differ, so ordinary decisions keep a one-line header.

`(kept)` means something different and still exists: nobody claimed the slot at
all. `(left as worn)` means this decision tried and placed nothing.

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

## The gear digest's two lists

**`items this window actually involved`** — everything the decisions named:
plans, ladders, and every claimant's offer.

**`other gear your active job's sets ask for`** — everything referenced by the
bundled sets file that the window never touched. This list exists because the
first one has a blind spot that cost a whole reading: gear filtered out at
**flatten time** — wrong level, wrong job, not owned — never reaches a plan or a
ladder, so the window cannot name it and no decision record can carry a refusal
for it. That is precisely the gear you need when a set appears to do nothing.

Both lists flag entries above the job level dlac was **deciding under** during the
window (a level sync counts; the level is read off the decision records, not live,
so a sync that lapsed before the report was written cannot rewrite the answer):

```
  Jaridah Khud     id 16063  lv 55   NOT in an equippable bag  ABOVE YOUR LEVEL (26)  jobs ...
```

Set files reference gear as Lua paths (`gear.Head.Faceguard_1`), so the report
resolves each path against the real gear table to get the display name —
`"Faceguard +1"`. A path that resolves to nothing is silently skipped: it is not
an item, and gear the player never indexed shows up in the first list's
"not in gear.lua at all" note instead.

## The engine verdict

The health readout tells the reader that a `[dlac] check (engine): alive` line
must accompany it. **In this file it never can** — `check._lines` returns the
addon half only, and the engine prints its line from its own branch, to chat. The
report therefore states its own equivalent underneath, off the engine file version
and the `modestate` stamp: agreement proves an armed engine of the right version,
and disagreement names which side is behind. Do not read the missing chat line as
a dead engine.

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
