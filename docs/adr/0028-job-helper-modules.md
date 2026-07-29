# 0028 — Job helper modules: drop-in folders, one folder = one approval

dlac deliberately performs **no actions** — Gear helpers only pick equipment, the player still
casts/crafts/fishes (CONTEXT.md **Gear helper**; the naming law that turned "Auto <activity>" into
"<thing> Gear" exists to keep that promise legible to a GM). But some jobs need the addon to *act*:
a BST wants the pet sent on engage and Reward fired below a pet-HP threshold. CatsEyeXI staff
approve action-performing addons **individually** (precedent: the approved Pup-Helper). If
action-performing behavior were baked into dlac core, every addition would re-open the approval
question for the whole addon, and the "only equips gear" line would stop being true.

So action-performing behavior lives in **Job helper modules** (issue #137, PRD #135): the first-party
revival of the parked plugin-folder design (`docs/design/integration-surface.md` §10), which was argued
to a conclusion and left parked until something needed to live in-state. This is that something.

## Decisions

- **A module is a FOLDER, never a loose file.** `addons\dlac\jobhelpers\<id>\init.lua` returns a
  contract table `{ api, label, jobs, init?, panel, status? }`. The folder is the unit of server
  approval — one folder = one row on the **Job Helpers** tab = one approval request — so approval is
  sought per helper, never re-litigated for the whole addon. A second file in a module needs a
  resolver anyway; folders were the §10 ruling the moment anyone wrote a real one.
- **Identity is the folder name, never a self-declared id.** The name on disk is the authority a GM
  reads; a module carrying its own `id` cannot masquerade as another.
- **`api` is checked at load, and a mismatch is a LOUD refusal.** A module built for a different dlac
  fails visibly instead of misbehaving quietly (PRD user story 9). It is the *only* version gate —
  no capability tiers, no sandbox, no allowlist (§10's explicit ruling: "we don't need to control
  what the plugins do, they depend on us"). The door is documentation, not walls.
- **Containment is structural, not a capability wall.** A wrong `api`, a throwing `init`, or a
  malformed folder gets ONE loud chat line and one entry in the SAME load ledger `/dl check` already
  reads — never a crash, never collateral damage to the other modules or the tab. At render time,
  every call into a module's hooks is pcall-wrapped and the frame-level imgui-stack recovery is
  uihost's `tabGuard`: a broken module loses its own Panel and prints its own name (hard rules 6, 12).
- **No hot-plugging.** Modules are scanned ONCE at addon load, after the UI host and main GUI are up.
  Drop a folder in and `/addon reload dlac`; the tab registers only while ≥ 1 module loaded, so the
  base addon stays uncluttered for everyone else.
- **The tab is display-only grouping over a flat list** (the Gear Helpers pattern): per-job
  `CollapsingHeader` sections, one row per module per declared job, a multi-job module under each with
  one shared switch. The row pill is the module's master switch; row order within a section is that
  job's module priority, drag-reordered and remembered per job — it becomes the **Action sequence**
  tie-breaker when the sequencer slice lands.
- **Config is a per-character statefile**, format-versioned, sections written on mutation only,
  beside the character's other dlac files (never inside Profiles) — the ammo-config precedent.

## Deferred (recorded so the boundary is explicit)

- **The sequencer's "module owns initiation, never reactive" stance** — an instant ability's action
  packet leaves before any equip it triggers could land, so a module must OWN initiation — is the
  load-bearing design stance of PRD #135. It belongs in an ADR, but it is recorded WITH the Action
  sequencer when that slice is built; #137 ships only the module system, the tab, and the BST
  skeleton. Central services (engage/target edges, pet vitals, ability recasts) and the shared
  `JobHelper` arbiter claimant are likewise separate slices.

## Considered and rejected

- **Bake BST behavior into core.** Re-opens whole-addon approval on every action feature and breaks
  the "only equips gear" story — the reasons the module boundary exists.
- **A restricted `_ENV` sandbox (`loadfile` + `setfenv`) / capability tiers / a maintainer allowlist.**
  Designed and rejected in the §10 grilling: dlac ships as readable Lua, so a bypass is a text edit,
  not a hash break — walls buy attribution, not prevention. Visibility and contracts, not walls.
- **Hot-plugging without a reload.** A watch on the folder adds a moving part for a case a reload
  already covers; modules appear on addon (re)load, full stop.
