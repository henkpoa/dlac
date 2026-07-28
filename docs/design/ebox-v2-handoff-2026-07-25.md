# E-Box Restock v2 — handoff (2026-07-25 evening)

**Pick this up here.** Built, **field-confirmed — both rounds CLOSED** (last check 07-28
22:54), on `main` since the `7231143` merge.
`addon.version 2026.07.25e`. 3420 checks green on Windows lua **and** WSL lua5.4.

- The design + the whole decision record: **`docs/design/ebox-restock-v2-grill-2026-07-25.md`**
  — read it before changing anything here. It carries the nine locked decisions, the three
  adversarial review rounds (12 defects), and the two field rounds.
- Memory: `[[ebox-v2-arithmetic-model]]`, which supersedes nothing in `[[ebox-restock-design]]`
  (that one is v1, shipped 07-24).

---

## 1. What this changed, in one paragraph

E-Box Restock used to poll the box: every 25s, and again on every inventory event. Crafting at
an Ephemeral Box — which is *the* place you craft, since the Ephemeral Moogles are the crafting
moogles — cost 200-300 packets a session, every one of them re-learning a number that had not
changed. **The box's contents are now a number we already know**: verified once on approach,
**debited locally** when we send a withdraw, and re-counted only when something we could not
compute changed it. Crafting at a box now costs **zero**.

## 2. What shipped

| File | What |
|---|---|
| `feature/eboxclient.lua` | The arithmetic model, the dirty marks, the menu rule, the party-line repair, the traffic trace |
| `feature/restockwatch.lua` | `otherBagNeed` — the yellow icon's pure question (**renamed `homeStockNeed` on 07-28**, see the grill's C2 revision: the icon asks about the Mog House, not the other field bags) |
| `feature/eboxtrace.lua` **(new)** | The `/dl debug ebox` readout |
| `feature/debug.lua` | New `ebox` topic (alias `box`) — **and a prefix fix, see §5** |
| `ui/restockui.lua` | Search button, panel rework, the 3-icon nudge, container-aware on-hand |
| `data/itembundles.lua` **(new)** | 109 bundle → contents pairings (was `ammocontainers`, 62 quiver/pouch only — widened 07-28) |
| `tests/run_tests.lua` | EBC11-26, EBT1-8, RS9-9f, AC1-6d, DBT2b-2h |

**The generator `tools/gen_itembundles.py` is NOT in the repo** — `tools/` is gitignored by
project rule, same as `gen_zones.py` and the rest. It lives on Henrik's disk and reads the
server clone at `~\scripts\catseyexi`. Re-run it if CatsEye adds ammo, tools or clusters:
`python tools/gen_itembundles.py`.

## 3. VERIFIED — do not re-litigate

**In the field (Henrik, 07-25 evening):**
- The `!box` watch fires and **there is no spam**.
- The menu rule works end to end: `!box ammo` at `18:47:05` → armed → **silent for the eight
  seconds he browsed** → fired only when items actually moved at `18:47:13`.
- ~~`/dl debug ebox` prints and reads correctly in game.~~ **WITHDRAWN 07-28 — this was a false
  positive, see §5.** It printed the *empty-ring* line; the first time it had an event to
  format it threw and Ashita unloaded the addon. Fixed in `2026.07.28s`; ~~still owed a real
  field round with traffic in the ring~~ **PAID 07-28 22:54 — the bare snapshot formatted a
  live 11-event ring spanning 1h24m (every line takes the `e.at` arithmetic path) and dlac
  stayed loaded. The header quantified the promise while it was at it: `1 packet sent, 4
  received, over 1h24m (0.0/min)`, standing 1.9 yalms from the box. And cat 35 sat dirty
  while IN RANGE with no re-count — the lazy re-count working: nobody asked for the number,
  so no packet was spent on it.**

**Headless (3420 checks, both runtimes):** the whole model — believe/dirty/re-count, debit
arithmetic and its floor, refusal-repairs-vs-success-doesn't, the settle window, PEND_HOLD,
the party-line repair and its brakes, the menu rule and its burst coalescing, search
correlation, the yellow icon's divergence rule, the container pairings.

## 4. FIELD ROUND 2 (Henrik, 2026-07-28, on `2026.07.28s`; item 5 on the evening build) — CLOSED, 5 of 5

1. ~~**Does dlac hear the `!box store` that TROVE queued?**~~ **CONFIRMED — yes, we saw it.**
   Cross-addon `command` visibility is real, so the `!box` prefix watch covers trove's four
   commands as designed. **The fallback is dead:** the tracked-item inventory heuristic is not
   needed and must not be re-added — `!box <item name>` withdrawals cannot drift us low.
2. ~~**The zero-packet promise.**~~ **CONFIRMED — the design's central claim holds.** Henrik
   tracked Wind Crystal and synthed at a box: **no packets.** This is the one that justified the
   whole v2 rewrite, and it is now measured rather than argued — with a *live* instrument
   (§5's `at`/`when` fix), so the empty log is real evidence and not a dead readout.
3. ~~**Container counting against real inventory.**~~ **CONFIRMED.** Henrik drew 2 Beetle
   Quivers and opened one: the panel reads **`198*`** — 99 loose Beetle Arrows plus 99 still
   sealed — and the star names the quiver. The loose/boxed split is right against real bags.
   (His first attempt used Wind Crystal, which had no bundle *because of the hole in §4b*.)
4. ~~**The nudge's three icons.**~~ **CONFIRMED, including the 07-28 Mog House ruling.** Henrik:
   *"properly tested and works, it will clearly state if any item is in a non field-container and
   where, and let you draw extra if you want."* The C2 revision is field-good.
5. ~~**The foreign-stream loop — INCONCLUSIVE, needs the actual numbers.**~~ **CLOSED 07-28
   evening — no loop, and the intruder is named: trove's own ebox streams.** The round's
   reasoning, kept for the record: the *loop* symptom is `dirty cat=N (a foreign 0x1A4 stream
   overlapped our answer)` at ~1/s; `rows=0` is the dangerous shape (a zero-match search, the
   E-review-2 case); and `source` mattered because the commit path requires `source == 0`
   (`eboxclient.lua:757`) while the foreign-repair path (`:702-713`, `:750-752`) triggers on
   **any** source.

   The literal lines (echo live through a deliberately noisy session: trove recipe-withdraw of
   12 Wind Crystals + 12 Arrowwood Logs, two synths, `!box cluster` twice, `!box ammo` once):
   - `21:30:29  < foreign list ended: rows=0 source=0`
   - `21:30:42  < foreign list ended: rows=0 source=0` — same second as both obtain lines
   - **zero repair lines all session** — the 07-25 ~1/s loop is dead, both brakes held
   - three clean arm → items-move → `dirty ALL` cycles, and the whole session cost **one
     packet**: `> GET_CATEGORY cat=56 (verify)` → `< LIST cat=56 rows=11`

   Reading it: `source=0` means the foreign traffic **is** the ebox module — trove's
   withdraw-response streams — so the commit/repair asymmetry never met a non-box stream in
   the field; leave that code alone. The `rows=0` streams landed while nothing was pending and
   were logged-and-ignored, which is the design working (the E-review-2 overlap stays
   theoretical, covered by the self-repair). **But the session surfaced a gap this round never
   asked about — §4c.**

### 4b. `ammocontainers` → `itembundles` — the glob was the bug (DONE 07-28, `2026.07.28t`)
Chasing "does `!box cluster` have the quiver problem too?" found that the **glob itself** was the
defect. `gen_ammocontainers.py` looked for `*_quiver.lua` / `*_pouch.lua` and found 62. The
server has **~130 items of that exact shape**, and the misses were the ones Restock tracks by
default:

- **TOOLBAGS (23)** — `toolbag_shihei` → 99 Shihei. Ninjutsu tools are in the restocker's staple
  set *and* in `!box store`'s storable set. A NIN carrying five toolbags read as **zero tools**.
- **CLUSTERS (16)** — `wind_cluster` (4106) → 12 Wind Crystal. `!box cluster` is one of the box's
  own subcommands, so this is the shape a crafter hits first — and Henrik tracks Wind Crystal.
- **CARD CASES (9)** — COR cards. Plus stone pouches, the bandolier, `rusty_bolt_case`.
- **The `+1` pouches**, dropped by a too-narrow name charset (`[a-z0-9_]+` can't match
  `sasuke_shuriken_pouch_+1` in the sql, so it resolved to nothing and was skipped as
  "not in item_basic.sql"). **A name that fails to resolve looks exactly like an item that does
  not exist** — the same silent-drop shape as the oberon id lie.

**The rule is now structural, not nominal:** any usable item whose `onItemUse` is a single
`npcUtil.giveItem` of one item in quantity > 1. **109 bundles.**

**The one judgement call — equippable minters are NOT bundles.** The same script shape sits on
gear: Annihilator → 99 Eradicating Bullet, Otoko Yukata → 99 Muteppo, Bolt Belt → 99 Bronze Bolt.
21 of those are excluded, because this table answers *"how much do I already have"* and a relic
that mints its ammo on demand is **a source, not a pile**. Counting one as a fixed 99 would
silence Restock about that ammo permanently — worse than the bug being fixed. The test is the
server's own: present in `item_equipment.sql` or `item_weapon.sql` ⇒ gear ⇒ skip. Pinned by
`AC5b`; **overturn that check if you disagree, it is the only opinion in the file.**

**A second header lie surfaced, and this one would have collided:**
`toolbag_sanjaku-tenugui.lua` claims `-- ID: 5314`, which is **toolbag_shihei's**; the sql says
5417. Keying off `item_basic.sql` (the rule the oberon/dweomer clash bought) is what kept both
rows. Pinned by `AC4b`.

### 4c. Trove ALSO injects raw 0x1A4 — the `!box` watch misses its recipe/vault flows (FOUND 07-28 evening; **RULED same night: accepted cost, no watch**)

§4.1 confirmed dlac hears the four `!box` commands trove QUEUES (`trove/plugins/ebox.lua:594`,
`:628`, `:641`, `:649` — all `QueueCommand`). But trove speaks the wire directly too:
`trove/utils/packet.lua` builds 0x1A4 (`C2S.WITHDRAW = 2`) and `sendRaw`s it via
`AddOutgoingPacket`, and the recipe-materials flow uses exactly that
(`trove/core/crafting.lua:140-143`). Henrik's 12x Wind Crystal + 12x Arrowwood Log withdraw
arrived with **no chat command** — nothing armed, nothing debited, nothing dirtied. The
crystal/log beliefs sat stale-HIGH from `21:30:42` until his own `!box cluster` dirtied ALL at
`21:31:39`.

Blast radius: a wrong panel/yellow-icon number until the next `!box` command — or until a fetch
is refused, because refusal-repairs already heals it at the moment it matters. Self-limiting and
self-correcting, but silent — and §4.1's "the fallback is dead" was argued on the premise that
all of trove's box traffic is command-visible. It is not.

The precise fix, if wanted (NOT built — Henrik's call): eboxclient registers `packet_out` for
0x1A4; an outgoing WITHDRAW we did not send ourselves → dirty ALL. Own-send discrimination gets
bookkept at the send site (`eboxclient.lua:253`) — assume our own injected sends may echo back
through our own hook. One dlacprobe minute first: confirm an `AddOutgoingPacket`-injected 0x1A4
is visible to another addon's `packet_out` at all. Do NOT resurrect the v1 inventory heuristic
for this — the wire says it plainly.

**Henrik's ruling, same night: DECLINED.** *"I don't really see the win in trying to keep track
of everything trove does, I just don't want our addon to send packets needlessly."* The mission
is dlac not spamming — not mirroring the box against all comers. The stale-high window
self-heals at every moment that matters (next `!box` command, refused fetch), so the watch
stays unbuilt. Do not re-propose it; the only thing that reopens this is field evidence of a
stale belief that did NOT self-heal.

## 5. Landmines for whoever picks this up

- **`/dl debug <topic>` was unreachable from `/dl` for its whole life.** The router matched
  `'^/dlac?%s+debug'`, and `c?` makes the *C* optional — the literal prefix was `/dla`. Fixed
  (`M._afterDebug`, DBT2c-2h). A handler that never fires is indistinguishable from a command
  that does nothing; three rounds of agent review missed it because they all called the
  functions directly instead of typing the command.
- **0x1A4 is a party line with NO request id.** trove speaks the same protocol on the same
  opcode. A foreign stream landing while our GET_CATEGORY is out is consumed as our answer. It
  **cannot be prevented** — only made self-correcting. Any future 0x1A4 work must assume someone
  else is talking.
- **Trove also INJECTS raw 0x1A4** (`utils/packet.lua` `sendRaw`; recipe + vault flows) — the
  `!box` command watch covers only its four `QueueCommand` paths. dlac registers no `packet_out`,
  so a foreign outgoing WITHDRAW is invisible and box beliefs go stale-high until the next
  `!box` command or a refused fetch. **Accepted cost by ruling — no watch (§4c).**
- **A `!box ...` command does not change the box** — it opens a *menu*, and an open menu streams
  0x1A4 lists of its own. We arm and wait for inventory movement as proof, and stay off the wire
  while armed.
- **`!box ammo` returns CONTAINERS, not ammo.** Blind Bolt → Blind Bolt Quiver (99 each, stack
  12 = 1188 per Inventory slot). Arrows *drop* the word ("Beetle Arrow" → "Beetle Quiver");
  bullets use pouches. Never string-match this — use `data/itembundles.lua`. **And never glob
  by filename either: the same trick covers toolbags, clusters and card cases (§4b).**
- **Key ammo containers off `sql/item_basic.sql`, not the scripts' `-- ID:` headers**:
  `oberon_bullet_pouch.lua` repeats dweomer's id (5822 vs the real 5823), which silently dropped
  a row from the generated table.
- **A local declared after its use is a nil GLOBAL, silently** — `M.rescan` read `_ewok`/`_ew`
  that way for its whole life, so Rescan's box re-sweep never ran. EBC22 pins it as a
  source-order check because nothing at runtime can see it.
- **A green suite on both sides of a seam does not mean the seam is joined (07-28, cost: the
  addon).** `eboxclient._trace` wrote `{ when = … }` from its first commit; `eboxtrace.lines`
  read `e.at`. `/dl debug ebox` therefore threw `arithmetic on field 'at' (a nil value)` and
  **Ashita unloaded dlac** — asking a question about traffic cost the player every dlac
  feature. It hid for three days behind two green halves that never touched: EBT3-8 format a
  *hand-built* stand-in that spells the field the formatter's way, and EBC23f/g drive the real
  trace calls but only ever inspect `dir`/`what`. Nothing handed the real ring to the real
  formatter. It then survived the 07-25 field round because the ring was **empty** — the
  `#tr == 0` branch is the one path that never touches a timestamp, which is E-review-3's own
  warning ("an empty log is what a dead instrument looks like") landing on the instrument
  itself. **EBT9/EBT9b now format the live ring left by EBC23f/g** (mutation-verified: put
  `when` back and exactly those two fail). And `/dl debug`'s router now `pcall`s the topic —
  a read-only readout must never be able to unload the addon.
- **Deleting a refresh cycle deletes what was quietly healing things.** Four of the five
  round-one review defects were transient wrong beliefs that the 25s poll used to age out and
  now never would. When you remove a poll, audit everything that was leaning on it.

## 6. Still open

- **Yellow icon option (b)** — MOVING items Mog Case → Inventory instead of buying more from the
  box. Better design (zero box stock, composes with green to land exactly `target`), blocked on
  dlac being allowed to move items between containers. **Wire format already known, do not
  re-research:** `dlacprobe.lua:1238-1258` decodes OUT `0x029` from a real capture
  (`qty u32 @0x04, from @0x08, to @0x09, fromSlot @0x0A, toSlot @0x0B`; success = 2× `0x020` +
  `0x01D`). Open question for that day: does a moved partial stack merge into an existing
  Inventory stack, or take a fresh slot the way box withdrawals do?
- ~~**Hear trove's direct withdraws (§4c)**~~ — **DECLINED 07-28**: tracking trove is not the
  mission, the mission is not sending needless packets. §4c carries the ruling and the one
  condition that would reopen it.
- **Opening a quiver from the panel.** We can count containers now but not open them; `!box ammo`
  fills your bags with quivers and the only way to use one is manually. `feature/useitem` exists
  and is the obvious seam. Not designed, not asked for — Henrik's call.
- **Deposit is still WITHDRAW-ONLY at the packet level** (server-ask #7 in
  `docs/server-questions.md`). The red icon is a `!box store` chat command, not a packet.
- ~~**`main` has none of this.**~~ **STALE — all of it is on `main`** (promoted in `7231143`,
  07-25), as are the two 07-28 rulings (`ef82f1f`) and the yellow-hover trim. `dev` and `main`
  are level.

## 7. ~~Also uncommitted, unrelated~~ — resolved

The stray `.gitignore` `share/` rule from a parallel session is gone; the tree is clean.
