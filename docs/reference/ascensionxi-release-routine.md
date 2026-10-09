# Shipping DLAC to AscensionXI players

This is the standing routine for any DLAC change that AscensionXI players should
receive, whether a catalog refresh, a feature or a fix. It is the DLAC side of
AscensionXI's own procedure: "Shipping any DLAC change: two linked PRs" in AXI
`documentation/custom/launcher-addons.md`. For AXI mechanics, the AXI files named
below are the authority. If they change, correct this file.

## How a DLAC commit reaches a player

```
DLAC PR ──merge──▶ dlac main              nothing ships yet
                      │
AXI pin PR ─merge─▶ AXI main              client/addons/catalog.json pins one dlac commit
                      │  automatic: "AscensionXI DAT channel"
                      ▼
          datchannel:sha-<12> = staging   test here
                      │  human: "AscensionXI deploy (prod)", channel_tag=sha-<12>
                      ▼
          datchannel:prod                 players, on their next launcher start
```

- **Merging into dlac main ships nothing.** AXI's launcher installs dlac at the
  commit pinned in AXI `client/addons/catalog.json` (`sources.dlac.ref`) and
  downloads the files from GitHub at that commit. No install follows dlac
  main's tip.
- **The pin lives in the channel image.** A DAT channel is an image of AXI's
  whole `client/` directory, catalog included. Staging and prod therefore
  each serve their own pin, and a merged pin PR reaches staging only.
- **Staging is automatic; prod is a human step.** A merge to AXI main that touches
  `client/**` runs the **AscensionXI DAT channel** workflow. It builds
  `datchannel:sha-<first 12 hex of the AXI merge commit>` and points staging at
  it once its probe passes. Prod changes only when a human runs **AscensionXI deploy
  (prod)** with that tag as `channel_tag`. The deploy's soak gate refuses a tag that staging is
  not serving, and `channel_tag=keep` keeps prod's current DLAC.
- **A channel promotes as a whole.** Promoting a tag promotes every `client/`
  change at that AXI commit: DATs, Nexus, other addon pins and the launcher.
- **Git installs are held.** The launcher never writes a `dlac` folder that is a
  Git working copy. `launcher.log` says "addon held: dlac (a git working copy -
  never written)". Such an install updates through Git and `/addon reload dlac`,
  and so does not show what a channel serves.

Agents and maintainers prepare the work: the DLAC PR, the AXI pin PR and its release
note. A human merges both PRs and runs every release step after the merge,
including the prod deploy. Never dispatch the DAT channel or deploy workflows
yourself (AXI `CLAUDE.md`).

## 1. The DLAC PR

- Branch from `origin/main` in an isolated worktree. That keeps unrelated local
  edits, and the checkout the game is playing, out of it.
- **Generate catalog changes; never hand-edit them.** Run the generator from an AXI checkout at
  the commit whose server data the pack must mirror:

  ```powershell
  python -m unittest discover -s tools/dlac-pack -v
  python tools/dlac-pack/gen_pack.py --out <dlac worktree>/servers/ascensionxi --game "C:/AscensionXI/Game/FINAL FANTASY XI"
  ```

  The generator owns `manifest.lua`, `data/`, `itemicons.lua` and
  `assets/items/`. The hand-maintained `features.lua`, `detect.lua`,
  `modules.lua` and `modules/` survive the run. Commit the whole pack,
  PNGs included, and name the AXI source commit.
- **Add a regression test and wire it into CI.** `.github/workflows/ci.yml` names every test
  file; a new `tests/*.lua` that is not listed there never runs in CI.
- **Run the checks:** `lua tests/pack_lint.lua ascensionxi`, `lua tests/pack_lint.lua cexi`,
  `lua tests/run_tests.lua`, `lua tests/smoke_ui.lua`, plus the focused tests
  the change touches.
- **Set the version.** The commit that gets pinned must carry the `addon.version` in
  `dlac.lua` that players should see in `/dl check` (`YYYY.MM.DD` plus a
  letter). Bump it in the PR, or in a release commit before the pin.
  `dispatch.lua`'s `M.VERSION` is the engine version and moves only with engine
  behavior.
- **Record it.** A catalog refresh gets an entry in
  [ascensionxi-catalog-refresh.md](ascensionxi-catalog-refresh.md). Any other
  release goes in its own reference doc.
- **Fork PRs** show CI as `action_required` until a maintainer approves the run.
- **Use a merge commit** when the AXI PR already pins this PR's head. A squash or
  rebase merge creates a new commit, so the pinned SHA would not be on main.

## 2. The AXI pin PR

Make this change on an AXI topic branch:

```powershell
# first: set the dlac entry's "version" in client/addons/catalog.json by hand
python tools/addon-catalog.py bump dlac      # pins dlac main's current head
python tools/addon-catalog.py verify
```

- **`bump` never refreshes the entry's `version`.** It only fills one in if it
  is missing, so set it yourself to the pinned commit's `addon.version`. As of
  2026-10-09, AXI main pins `504d7ec` (`2026.10.07a`), but the entry still says
  `2026.10.05d`.
- **To pin a specific commit** rather than main's head, set `sources.dlac.ref` and
  run `python tools/addon-catalog.py resolve --only dlac`. Never hand-edit the
  resolved hashes.
- **The pinned commit must be on dlac main when the AXI PR merges.** During review,
  the AXI PR may pin the open DLAC PR's head. Re-pin and re-resolve whenever that
  PR changes. DLAC merges first, AXI second. Some AXI notes word this as "never
  pin unmerged DLAC code"; both wordings agree on that merge order.
- **Write the release note.** It goes in `documentation/custom/dlac-<topic>-release.md` and covers the version, what
  changed, the staging check, the prod inputs and the rollback.
  `dlac-2026-10-05-release.md` is the template.
- **Ride with AXI code when needed.** If the DLAC change needs AXI server or client code in the same release,
  the pin goes in that AXI PR rather than a separate one.
- **Resolve pin conflicts.** Two open AXI PRs that pin dlac conflict on the same lines. The second to
  merge keeps the newer commit, then re-runs `resolve --only dlac` and `verify`.
  See `launcher-addons.md` step 4.

## 3. Staging (automatic on merge)

- The merge runs **AscensionXI DAT channel**. Record its tag:
  `sha-<first 12 hex of the AXI merge commit>`. It names the AXI commit, not the
  DLAC one.
- If the change depends on server data (a catalog refresh, a pack module),
  check that the staging game server runs an image containing the matching
  server change.
- Test on a Staging launcher profile with addon updates on, in a client whose
  `dlac` folder is not a Git working copy. `/dl check` must report the new
  `addon.version`. Then exercise the change itself.

## 4. Prod (human)

- Review what else the staged channel carries. List the AXI `client/` changes since the tag prod
  serves: `git log --oneline <prod sha>..<staged sha> -- client/`.
- Run **AscensionXI deploy (prod)** with `channel_tag` set to the staging `sha-` tag.
  For a DLAC- or DAT-only release, use `image_tag` = the tag prod already runs,
  `website_tag=keep`, `client_image` blank and `warn_minutes` 0. Preflight should report
  `scope=swap`: downloads pause briefly, and game sessions and login stay
  untouched (AXI `dat-channel-swap-isolation.md`). When server code must ship
  too, `image_tag` is the staged server build, in the same deploy.
- Players get the new DLAC on their next launcher start. A running addon needs
  `/addon reload dlac`. Players who chose Ignore updates keep their installed
  version.

## Rollback

Revert the AXI pin PR. The revert's merge builds a new staging channel, which a
prod deploy then promotes. To go back to an earlier channel without a revert,
redeploy that tag to staging (`redeploy_tag` on the DAT channel workflow), then
promote it. Neither path changes the database or any player configuration.

## Server-coupled changes

When DLAC mirrors server data (new items, changed stats, retired bonuses), the
catalog must reach prod **in the same deploy** as the server change. Neither half
may reach prod alone:

- **Old catalog on a new server:** the planner miscounts gear that the server changed.
- **New catalog on an old server:** the planner plans for items and bonuses that don't exist yet.

So the promoted channel must carry both the new DATs and the new DLAC pin, and
the deploy's `image_tag` must contain the server change. If the server PR
merged first, its DATs sit on staging with the old pin. The follow-up pin PR
then builds a newer staging channel. Promote that one, not the earlier tag.

### Example: guild crafting headgear (October 2026)

DLAC #200 adds four guild head pieces and removes the +1 crafting bonus from
the gloves and Caduceus they replace. The same refresh also picks up Almogavar
Bow +1 and Faerie Tunic +1. AXI #834 merged on 2026-10-09 (`b311f830b3`) with the
server code and DATs but no pin. Staging therefore serves the new DATs with DLAC
`504d7ec`. The remaining steps, in order:

1. Merge DLAC #200.
2. Merge an AXI follow-up PR that sets the version, bumps, verifies and adds
   the release note.
3. Test on staging.
4. Run one prod deploy with the follow-up's channel tag and a server image
   containing #834.

## Sources (AscensionXI repo)

- `documentation/custom/launcher-addons.md`: "Shipping any DLAC change".
- `tools/addon-catalog.py`: `bump`, `resolve`, `verify`, `list`.
- `.github/workflows/ascensionxi-datchannel.yml`: the merge to staging.
- `.github/workflows/ascensionxi-deploy-prod.yml`: `channel_tag` and the soak
  gate (`resolve_pin`).
- `documentation/custom/dat-channel-swap-isolation.md`: DAT-only prod inputs.
- `deploy/README.md`: the release table. `client/launcher/README.md`:
  profiles, channels, and the environment binding of each client folder.
