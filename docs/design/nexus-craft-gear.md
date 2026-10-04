# Crafting gear for Nexus synths (AscensionXI)

**Status (2026-10-04):** implemented and tested headless on branch
`claude/nexus-craft-gear`, beside the matching Nexus change in the
AscensionXI repo (Nexus 1.2.4, `documentation/custom/nexus.md` §17.20). Not
yet seen in the client. Nothing ships until both PRs are merged and the
launcher's DLAC pin is bumped.

## What it does

Nexus is AscensionXI's crafting window: it starts synths itself, one after
another. Before each synth it now tells dlac which crafts the recipe needs
("Woodworking 60, Smithing 30"). dlac puts on the best crafting gear the
player owns for that recipe, weakest craft first, and answers "ready". Only
then does Nexus send the synth.

The gear then stays on (the **Nexus lock**) until the player moves, zones,
engages, dies or changes job, or until Nexus names a recipe that needs other
pieces. Repeating a recipe, or starting a new Nexus run of it, is answered at
once because the gear is already on. The owner asked for exactly this
(2026-10-04): *"lock the crafting gear until the person moves or until Nexus
says something else that needs changing, so if we spam out a lot of the same
recipe, we don't have to wait every time we create a new session"*, and for
it to be automatic: *"You don't do anything else that matters when crafting,
so it should be automatic."* It is on by default; `/dl craft nexus off` turns
it off and `/dl craft nexus` shows what is locked.

## Why Nexus has to say it first

Read in AscensionXI's server (`src/map/utils/synthutils.cpp`, October 2026):

- `startSynth` rolls the result (`calculateSynthResult`) the moment the synth
  request arrives. The craft skill each roll uses includes gear
  (`getSynthDifficulty`: recipe level minus skill minus the craft's skill mod),
  and so do Synth Success and Synth HQ. Gear put on after that counts from the
  next synth: craftwatch's TIMING TRUTH note.
- Material-loss gear (`handleSynthFail`) and skill-up gear (`doSynthSkillUp`,
  `SYNTH_SKILL_GAIN`) are read at the END of the synth, so the gear must also
  stay on until the result arrives. The lock does that.
- **Weakest first is the server's own rule.** Every craft a recipe needs makes
  its own break roll when you are under its level, and AscensionXI's
  `crafting-hq-tier-rates` fence makes the HQ chance 2% plus 1% for every whole
  level the LOWEST craft clears the recipe by (capped at 80%, plus Synth HQ
  gear). A point on the weakest craft is worth something; on any other craft it
  is worth nothing until the weakest catches up.

Ways that do not work, so nobody tries them again:

- **Watching Nexus's synth packet (0x096).** Too late: the result is rolled when
  it arrives. And Nexus's void-direct synths (the server starts them with
  materials from Void Storage) send no 0x096 at all.
- **Holding Nexus's 0x096 until dressed.** That is dlac intercepting a synth
  command, which Henrik ruled out on 07-13 after the `/lastsynth` breakage, and
  Nexus stops a run when its synth shows no sign of starting within 2 s.
- **Nexus filing an external claim** (`/dl claims`). Nexus would need to know the
  player's gear, which is dlac's job, and the player would have to switch claims
  on. Nexus sends a hint about the recipe; every gear decision stays here.

## The conversation

Ashita's `plugin_event` bus, inside the client; nothing reaches the server.
Plain `key=value;key=value` text, parsed with patterns, never run as code.

| From | Event | Message | Meaning |
|---|---|---|---|
| Nexus | `nexus_craft` | `op=hello` | Nexus loaded, or a run starts |
| Nexus | `nexus_craft` | `op=next;seq=N;crafts=Smithing:30,Woodworking:60;recipe=R;result=I;desynth=0\|1` | the next synth |
| dlac | `dlac_craft` | `op=hello;v=1;follow=1\|0` | dlac is here (answer to hello, and on its first frame) |
| dlac | `dlac_craft` | `op=ready;seq=N;state=S` | synth N may go |
| dlac | `dlac_craft` | `op=bye` | dlac unloaded |

`state` is `worn` (every picked piece is on), `partial` (some piece never went
on: a Lock, Free equip, a refused equip), `none` (no crafting gear for this
recipe), `off` (`/dl craft nexus off`) or `cleared` (the lock ended while Nexus
waited, or a newer synth replaced this one).

Nexus waits only after dlac has said hello, and never longer than 3 s; after
a timeout it stops waiting until dlac says hello again. A client without dlac,
or with a dlac older than this change, crafts exactly as before.

## How the pieces are picked (`feature/craftpick.lua`)

Pure; it takes the gear-helper manifest's new `craftItems` rows (fmtver 17:
every owned, wearable, in-bags piece with craft stats, with its numbers per
craft), the recipe's requirements, the player's skills, the goal and the level.

1. **Skill slots.** For every slot where a piece raises a craft the recipe
   needs, try every combination (a piece that another piece for the same slot
   matches or beats on every needed craft is dropped first; AscensionXI's gear
   gives about one combination for a one-craft recipe and a few thousand at
   most). The winner has the best margins sorted weakest first, compared at the
   first place they differ: the weakest craft goes as high as the gear allows,
   then the next weakest. Ties go to the goal's own stats, then fewer pieces,
   then names. Above 50,000 combinations a greedy fallback raises the weakest
   craft one piece at a time.
2. **Free slots, for the goal** (craftwatch's hq / nq / skillup;
   `/dl craft goal`): hq = Synth HQ, then success, material loss, skill-up gain;
   nq = an HQ-blocking ring for a needed craft, then success, material loss,
   conserve, skill-up gain; skillup = skill-up gain first.

A piece that blocks HQ for a needed craft is never worn under hq. Ear and ring
pairs respect how many copies you own. Ammo is never touched.

**All-craft pieces** (Kupo Shield, +1, +2; Artisan's Hat, Torque and Apron)
count for every craft a recipe needs, so on a subcraft recipe one piece raises
both crafts; the better piece of a line wins its slot (Kupo Shield +2's +3
beats +1, the plain shield and every craft ecu). Tests NC12.

**The hands never fight** (owner, 2026-10-04: the Kupo Shield "shouldn't be
battling with a 2-hander"). The pick never wears a two-handed or hand-to-hand
craft weapon (it could not keep a shield beside it) and never a Sub that is not
a shield (a grip or off-hand weapon needs a two-hander or Dual Wield). The
manifest rows carry `twoHand` / `shield` for this (`rec.OneHanded`, the Type,
`utils.classifySub`); a row without them is allowed. When the lock wears a
shield and no weapon, the main hand is reserved by the engine's existing
Sub-vs-Main guard (`craftMainGuard`, v37), which reads the same Craft claim: a
two-handed or hand-to-hand set Main is held off while the lock stands, and a
one-handed one stays. The server takes a worn two-hander or hand-to-hand weapon
off when a shield goes on (`charutils.cpp` EquipArmor, `SLOT_SUB`), so nothing
puts it back until the lock ends. Tests NC13, NX9, NX10 (the real dispatch).

## Where the lock lives (`feature/nexuslink.lua`, engine v169)

In memory only. The engine's **Craft** claimant row reads it first
(`dispatch.M._craftRowState`): while there is a lock, the row's state is
`{ enabled = true, craft = 'Nexus', nexus = { Slot = item } }` and its claim is
those picks; without one the row reads `craftstate.lua` as before. So the picks
have the Craft row's rank, Locks and Free equip win over them as over any craft
gear, and `/dl why` and `/dl prio` show them (`ON (Nexus recipe)`).

The frame beat (`dlac.lua`) handles messages, answers once every pick is worn
(`dispatch.wornName`), and checks four times a second whether the player moved
more than 0.5 yalm, zoned, engaged, died or changed job. A lock that has been
answered once answers at once from then on, so a slot that can never be dressed
costs one 2.5 s wait, not one per synth.

The follow switch is `nexus = true|false` in `craftstate.lua` (craftwatch is
still its only writer); a file without the key follows.

## Files

`feature/craftpick.lua` (new), `feature/nexuslink.lua` (new),
`feature/craftwatch.lua` (follow switch, `/dl craft nexus`, status line),
`dispatch.lua` (Craft row, v169), `ui/automationsui.lua` (`craftItems`,
fmtver 17, `M.craftItems()`), `dlac.lua` (load + frame beat),
`tests/nexuscraft.lua` (new, in CI), `tests/run_tests.lua` (NX, the guard list),
`tests/golden/autogear.golden`.

The golden was regenerated with `tests/gen_goldens.lua` and then the two
`Tamas Ring` MP lines were put back by hand: run standalone, the generator
writes 15 for that ring, while `smoke_ui` (which compares the golden after its
other sections ran) produces 29, on main as well. That difference predates this
change and is not investigated here.

## Verification (2026-10-04)

- `lua tests/run_tests.lua`: 7,547 (7,521 before; NX0-NX10e new).
- `lua tests/smoke_ui.lua`: 1,626.
- `lua tests/nexuscraft.lua`: 112 (NC1-NC13 pick, NL1-NL13 conversation and lock).
- End to end with Nexus's real link over a pretend bus: the AscensionXI repo's
  `client/addons/nexus/tests/e2e_dlac_link.lua` (run it with this checkout's
  path), 14 checks.
- A quick mutation check across both repos (30 deliberate breaks of the
  guards above, each caught). The formal sweeps wait until the owner calls the
  feature final.

## Client check (owner)

1. Craft gear in the inventory or a wardrobe (Artisan's Apron, a torque, the
   Kupo Shield). Update this checkout to the branch and Nexus to 1.2.4; then
   `/addon reload dlac` and `/addon reload nexus`.
2. Craft ×3 of a one-craft recipe in Nexus: the gear goes on before the first
   synth, Nexus's run line says "waiting: DLAC is putting on your crafting
   gear" for about a second, the next synths do not wait.
3. `/dl craft nexus` names the locked pieces. Start the same recipe again: no
   wait.
4. Take a step: the normal gear comes back.
5. A recipe with a subcraft: the weaker craft gets the one-craft pieces.
6. `/dl craft nexus off`, craft: no gear changes, no wait.

## Rollback and open items

Revert the PR; nothing persists but the `nexus` key in `craftstate.lua`, which
older builds ignore. Open: the owner's client check; whether the hidden
Crafting Gear panel should be enabled on AscensionXI (`servers/ascensionxi/
features.lua` `helpers`; the Nexus lock works without it, and `/dl craft goal`
sets the goal).
