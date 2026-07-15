# Resolve only when the game says ready; a latch must remember what it answered

Status: ratified 2026-07-15 (engine v49), after a login bug that ate a whole session's
gear and took three theories to find. Related: ADR 0006 (the engine decides at equip
time). Field record: history.md, session *"NON is not a job"*.

## The rule

Two halves, and the bug needed **both** to survive:

1. **Ask the authoritative signal whether the game is ready — never infer readiness from
   a value's shape.** At login the client's player block is not populated yet.
   `GetMainJob()` answers **0** (= None), and gData resolves that through the resource
   manager (`GetString('jobs.names_abbr', 0)`) into the *string* **`"NON"`**.
2. **Anything that resolves once and stops must record every input it resolved against,
   and must not record an answer it never got.** Otherwise a resolve against not-ready
   state is permanent.

## Why (the field case)

The profile auto-install guarded like this:

```lua
if type(job) == 'string' and job ~= '' and job ~= '?' then   -- "NON" passes
```

`"NON"` is not `''` and not `'?'`, so it read as a perfectly good job. The tick looked
for `sets\NON.lua`, found nothing (**nobody has one** — which is why this bit every
migrated character identically), installed nothing, and **latched** — on `gProfile` +
profile name, with no record of *which job* it had answered for. ~6.4 s later
(16 ticks) the memory read settles to the real job, but `gProfile` has not changed, so
the guard never re-fires. You then play the entire session on the shim's empty
`.Dynamic`, with every trigger matching and equipping **nothing** — in silence, because
`equipSetByName` skips a missing set without a word (v35 moved that to the Triggers tab).

Note the two readings disagree *by design*: LAC picks `gProfile` from the **0x0A
packet's** job, while `gData.GetPlayer().MainJob` is a **live memory read**. At login
they are briefly different answers to the same question. `gProfile` existing does **not**
mean the job is known.

The correct check already existed twenty lines away, in `readJobSets`:

```lua
local j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob();
if j ~= nil and j ~= 0 then abbr = ...GetString('jobs.names_abbr', j); end
```

## Consequences

- **`M.jobReady(jobId, jobName)` is the one place that decides a job is real.** It gates
  on the **id** (0 is authoritative "not ready"); the `"NON"`/`''`/`'?'` name checks are
  belt-and-braces, because id and string come from two different reads. Everything that
  resolves per-job goes through it. Tests Z1–Z7 pin it — including Z7 (`WAR`, id 1, is a
  **real job**, not the sentinel: the fix must not overreach into rejecting id 1).
- **The auto-install latch is keyed on `(gProfile, profileName, job)`** and only latches
  once the question was *answerable* (`setsPath(job) ~= nil` — nil means the character
  dir has not resolved, i.e. "can't tell yet", which is **not** the same answer as
  "this job has no sets file"). Unanswerable ⇒ leave it; the next tick retries 0.4 s later.
- **A latch is a smell; justify each one.** Everything else in the engine re-reads on a
  throttle and self-heals — trigger files, craft state, pin state, the mode mirror. The
  auto-install was the **sole non-retrying reader**, and that is exactly why triggers
  recovered at login and sets never did. A new latch needs an explicit reason and must
  record its inputs.
- **Never enumerate the bad values.** `job ~= '' and job ~= '?'` was a blocklist, and
  `"NON"` was the value nobody thought of. Prefer an allowlist, or gate on the signal
  the game itself uses to mean "not ready".

## Reach

Anything read from client memory can be not-ready at login and needs the same treatment.
Known-safe today because they either check the id or tolerate a retry:

- `readJobSets` / `triggersPath` — check the id, or re-read every second.
- `charDir()` / `profiles.charBase()` — return **nil** pre-login (an honest "don't know");
  callers retry. `setsPath(job) == nil` inherits that and is the "can't tell yet" signal.
- `M.dispatch` — bails while `gProfile`/`gState` are absent and re-runs next event.

The trap is a reader that maps not-ready onto a *plausible value* instead of nil.
`GetMainJob() == 0 → "NON"` is precisely that, and it is why this cost hours: the bad
value looked exactly like good data.
