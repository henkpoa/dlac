# Void Restock (retired)

**Removed from DLAC on 2026-09-27 (`2026.09.27a`).** The Nexus addon in the
AscensionXI repo took over restocking from the Void
([AscensionXI #666](https://github.com/henkpoa/AscensionXI/issues/666); design
in that repo's `documentation/custom/nexus.md` §9). CatsEyeXI's **E-Box
Restock** is a different feature and is unchanged.

## What was removed

- `servers/ascensionxi/modules/voidrestock/`: the Void Storage client, the
  planner, the controller, the list editor, the tray buttons and the
  `/dl restock` command.
- `voidrestock` from `servers/ascensionxi/modules.lua`, and `restock` from the
  helpers allowlist in `servers/ascensionxi/features.lua`.
- `servers/ascensionxi/data/voidstorage.lua` and
  `scripts/export_void_storage.py`, the membership snapshot only restock read.
- `assets/void_storage.png`, the tray and quick-menu icon.
- `tests/void_restock.lua` and its CI step.

The last `main` commit with all of it is `cd6037a`.
`git show cd6037a:docs/design/void-restock.md` has the full design, the wire
notes and the playtest list, and `git show cd6037a:<path>` recovers any file.

## Kept on purpose

The AscensionXI pack's `restocknotice` module answers `/dl restock` with:
"Void Restock moved to Nexus: /nexus restock (fetch, store or stop)."
It only prints the migration notice; it has no UI, packet handlers, or pump.
Its folder must stay outside `modules/voidrestock/`, which the launcher deletes.

Each character's `void-restock.lua` in the DLAC data folder
(`profiles.dataDir()`), with its `backups\void-restock-N.lua`. DLAC no longer
reads or writes them. Nexus imports `void-restock.lua` once (its ruling A9), so
nothing in DLAC may delete or rewrite that file.

## Why delete instead of leaving it unregistered

An unregistered copy drifts from the server protocol and invites someone to
switch it back on beside Nexus. Two restock clients race: both top up the same
targets, and the old client also consumed and blocked every Void reply
(0x1E0 ops 0-5), including replies to requests it never sent.

## Updating an install

The AscensionXI launcher deletes the removed files when its DLAC pin moves (the
catalog's `remove` list). A DLAC folder that is a git checkout is not managed
by the launcher: pull it by hand, or the old restock keeps running beside
Nexus. By design (its ruling A8), Nexus warns once when it sees Void traffic it
did not send, and turns off its own restock until the next reload.
