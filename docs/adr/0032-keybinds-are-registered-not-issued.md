# 0032 — Keybinds are registered, not issued

Accepted 2026-07-30. Adds the Central service `feature/keybinds.lua`. Nothing about the trigger
engine, the Arbiter or the module contract changes; what changes is that **no feature issues a
`/bind` of its own any more**.

## Context

dlac bound keys from two places, and they could not see each other:

* **Modes** — the trigger loader (`dispatch.lua`), per job file: `/bind <key> /dl mode <Name>`,
  deduped through a local `_boundKeys` map.
* **The window** — `^k` → `/dl ui`, hardcoded in `dlac.lua`, with a matching `/unbind` on unload.

`_boundKeys` was a **dedupe map, not a registry**. It existed for one field-reported reason (the
loader re-parses on every `/dl triggers reload`, which the automations rescan pings after every
inventory sync, and re-issuing the bind each time spammed `/bind`) and it answered exactly one
question: *have I already queued this key with this command?* It could not answer *is this key
taken*, *by whom*, or *with what* — so:

* A second feature wanting a key had **no way to ask**, and `/bind` in Ashita silently replaces.
  The loser of a collision does not fail; it just stops working, which is the worst failure shape
  available.
* Nothing ever **released** a key. A mode defined in BRD's trigger file kept its bind for the rest
  of the session after switching to WHM — the definitions are per job, the binds were forever.

The trigger that forced the issue: Job helpers gained named actions worth binding
(`/dl jh bst-helper summon`). Henrik, 2026-07-30: *"We need that registry, more binds will be done
in the future. If a bind exists, it needs to be able to tell where and with what and block them
from binding over it."*

## Decision

**One registry owns every key dlac binds.** `feature/keybinds.lua` holds owner → key → command,
issues the `/bind` and `/unbind` itself behind an injectable io seam, and answers `holder(key)`.

Three rules, in the order they matter:

1. **A taken key is REFUSED, and the holder is named.** The second claimant does not get the key
   and hears exactly one line saying who has it. Reported once per (owner, key) so a loader that
   re-parses thirty times a minute does not say it thirty times.
2. **Owners are namespaced strings** — `mode:weapon`, `jobhelper:bst-helper:summon`, `dlac:ui` —
   which is what makes `releaseGroup('mode:')` mean *"drop every mode bind"*. An owner holds at
   most one key; registering a second **moves** it.
3. **`syncGroup(prefix, entries)` is the per-job door.** Hand it the whole group as it should be
   right now: it releases what is gone, binds what is new, and leaves an unchanged bind entirely
   alone — the `/bind`-storm guard, preserved as a property of the registry instead of a habit
   each caller has to remember.

**Blocking here is not the gating this project rejects** (ADR 0028, and Henrik's standing position
on sandboxes and permission walls). A key is a genuinely **exclusive** resource: two owners cannot
both have F9, and the second does not merely "win" — it destroys the first silently. Refusing the
second and naming the holder is the only outcome that leaves the player able to *fix* it. Nothing
is hidden and nothing is de-powered: they retype the key on either side and it lands.

**Job-helper keys are job-scoped, and the framework installs them.** A module declares
`commands = { summon = { ..., key = 'summonKey' } }` naming one of its **own** declared config
keys; `feature/jobhelpers.pumpBinds` reads it and syncs the `jobhelper:` group once a second
against the current main job and the module's row pill. So the owner id and the command string are
the framework's — a module can no more bind as somebody else than it can request an Action sequence
as somebody else (ADR 0030) — and the key comes back to the player the moment they change job.

The gate is deliberately **job + pill, not the full activity predicate**: town, death and zoning
are the *act's* gates, and binding on them would make a key appear and vanish under the player's
fingers.

## Consequences

* `/dl binds` lists every key dlac holds, with its owner and its command.
* Mode binds now **release** on a job change. That is a behaviour change and a bug fix at once: a
  key from the job you left used to keep working, firing a mode the current job may not define.
* `dispatch.lua` keeps `_boundKeys` as the **degraded path** for a copy that cannot reach the
  registry (the seeded twin, headless), byte-identical to the old behaviour — the registry is
  required by nothing, which is what keeps engine v157 twin-safe.
* A module author never writes `/bind`. If a future feature needs a key outside a module, it
  registers with its own namespace rather than reaching for `QueueCommand`.
* Tests KB1–KB40 (the registry, driven at its io seam) and JHC14–JHC24 (the framework's install,
  including the job change and the pill).
