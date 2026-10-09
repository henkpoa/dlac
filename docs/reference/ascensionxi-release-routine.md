# Shipping DLAC to AscensionXI players

Shipping DLAC to AscensionXI takes two PRs. The DLAC PR puts the regenerated
AscensionXI catalog on dlac main. The AXI PR pins that DLAC commit, and merging
it puts the new DLAC on **staging**. Moving staging to prod is a separate human
step.

This is the DLAC side of AXI's "Shipping any DLAC change: two linked PRs", in
`documentation/custom/launcher-addons.md` in the AscensionXI repo. That file is
the authority for AXI mechanics. If it changes, correct this one.

## 1. DLAC PR: regenerate the catalog

Catalogue every item with AXI's own generator. Don't hand-edit the catalog.

1. Update an AXI checkout to `main` (or to the commit whose items should ship).
2. Make a DLAC worktree from `origin/main` on a new branch. Using a worktree
   keeps the checkout the game plays out of it.
3. From the AXI checkout, run:

   ```powershell
   python -m unittest discover -s tools/dlac-pack -v
   python tools/dlac-pack/gen_pack.py --out <dlac worktree>/servers/ascensionxi --game "C:/AscensionXI/Game/FINAL FANTASY XI"
   ```

   The generator rewrites `manifest.lua`, `data/`, `itemicons.lua` and
   `assets/items/`. It leaves the hand-maintained `features.lua`, `detect.lua`,
   `modules.lua` and `modules/` alone.
4. Bump `addon.version` in `dlac.lua` (`YYYY.MM.DD` plus a letter). That is the version
   players see in `/dl check`.
5. Check it, in the DLAC worktree:

   ```powershell
   lua tests/pack_lint.lua ascensionxi
   lua tests/run_tests.lua
   lua tests/smoke_ui.lua
   git diff --stat
   ```

   Read the catalog diff: the added, changed and removed records should be
   exactly what the server changed.
6. Commit the whole pack, PNGs included. Name the AXI commit in the message.
   Add an entry to [ascensionxi-catalog-refresh.md](ascensionxi-catalog-refresh.md).
7. Open the PR into dlac `main` and merge it. Nothing reaches players yet.

## 2. AXI PR: pin the merged DLAC

On an AXI branch from `main`:

```powershell
# set the dlac entry's "version" in client/addons/catalog.json to the new addon.version
python tools/addon-catalog.py bump dlac
python tools/addon-catalog.py verify
```

- `bump dlac` pins dlac main's **current head**, so run it after the DLAC PR has
  merged. If the PR was opened earlier, bump again before merging.
- `bump` never updates the entry's `version`; set that by hand. As of
  2026-10-09, AXI main pins `504d7ec` (`2026.10.07a`), yet the entry still says
  `2026.10.05d`.
- Never hand-edit the resolved hashes. `bump` re-resolves them.
- Add a short `documentation/custom/dlac-<topic>-release.md` covering the
  version, what changed, what to check on staging, and rollback. Then open the PR.

Merging the AXI PR runs the **AscensionXI DAT channel** workflow. That builds
`datchannel:sha-<first 12 hex of the AXI merge commit>` and points staging at
it. On a Staging launcher profile with addon updates on, `/dl check` should report the
new version.

## 3. Staging to prod (human)

Prod changes only when a human runs **AscensionXI deploy (prod)** with the
staging tag as `channel_tag`. The deploy refuses any tag that staging is not serving, and
`channel_tag=keep` leaves prod's DLAC alone. For a DLAC-only release, set
`image_tag` to the tag prod already runs, so it's a DAT swap that doesn't
touch game sessions. AXI `dat-channel-swap-isolation.md` lists the inputs.

## Worth knowing

- **Merging into dlac main ships nothing.** The launcher installs the commit
  pinned in AXI `client/addons/catalog.json`, and that pin is baked into each
  channel's image. Staging and prod serve their own pins.
- **A channel ships as a whole.** Promoting a staging tag to prod also ships every
  other `client/` change at that AXI commit: DATs, Nexus and other addon pins.
- **Ship server data and its catalog together.** When the catalog mirrors a server
  change (new items, changed stats, retired bonuses), promote both to prod in
  the same deploy. If the server PR merged first, its DATs are on staging with
  the old pin. Promote the newer channel from the pin PR instead.
- **Git installs are held.** The launcher never writes a `dlac` folder that is a
  Git working copy, so such an install doesn't show what staging serves.
- **Rollback:** revert the AXI pin PR, which builds a new staging channel, then
  promote that channel.

## Sources (AscensionXI repo)

- `documentation/custom/launcher-addons.md`: "Shipping any DLAC change".
- `tools/addon-catalog.py`: `bump`, `resolve`, `verify`.
- `tools/dlac-pack/README.md`: what the generator reads and writes.
- `.github/workflows/ascensionxi-datchannel.yml`: AXI merge to staging.
- `.github/workflows/ascensionxi-deploy-prod.yml`: `channel_tag` and the staging
  check (`resolve_pin`).
- `documentation/custom/dat-channel-swap-isolation.md`: DAT-only prod inputs.
