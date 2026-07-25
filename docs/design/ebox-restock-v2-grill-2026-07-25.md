# E-Box Restock v2 — grill state (2026-07-25)

Recovered from session transcript `fa805011-864a-4a2e-bde9-724336aa5ad2` after a context clear.
Grill ran 10:33–12:28. **Nothing built yet — design only.** Supersedes nothing in
`docs/design/ebox-restock.md`; that spec still describes the shipped v1.

---

## A. Why this grill started

The add-picker searches the box on a 0.3s typing pause, and that is "weird and confusing"
to use. Reading the code found three separate defects behind that feeling
(`ui/restockui.lua:351-386`, `feature/eboxclient.lua:235-245`):

1. `_addLast = buf` is assigned **before** `ec.search()` is called (line 359-360). When
   `canQuery()` refuses (in flight, or MIN_GAP 1.0s not elapsed) the search is silently
   dropped and **never retried** — the buffer now equals `_addLast`. You stop typing and
   nothing comes back.
2. `ec.searchResults` is never cleared or correlated to the current text. There is no
   in-flight signal, so `'no matches in the box'` (line 385) shows *while the request is on
   the wire*, and shows results for a **previous** query string.
3. `closeAdd()` doesn't clear `ec.searchResults` — reopening **+ Add** instantly shows last
   session's hits.

---

## B. Decisions LOCKED

### B1. Search (the add-picker)
- **Explicit Search button. No type-to-search, ever.** One query per click.
- Search results **hide items already in the list** being added to.
- Adding an item **does not close the picker** — you often add several (e.g. all the bolts).
  The manual close button already exists.

### B2. Box-quantity polling — the model changed completely
Henrik's ruling (12:24), which overrode the design we'd been building toward:

> "We can locally keep count of what is going on, we don't need to ask the e-box for how
> many items we have in inventory or our containers. So inventory changes should not in
> reality trigger any form of e-box search, as the e-box qty hasn't changed, only our local
> availability of items. … If we KNOW we drew 5 grape daifukus from an e-box pool of 25, we
> KNOW that there is 20 left. No need to poll that."

So the box cache is **a number we already know**, maintained by arithmetic:

| Event | Action | Packet cost |
|---|---|---|
| First approach to a box, unverified | Verify the tracked categories once | 1 per tracked AH category |
| Our own Fetch | `M.cat[ahCat].items[id] -= qty` at send; re-check only if the ACK reports failure | **0** |
| Any `!box …` command (see B4) | Mark **all** tracked categories dirty, re-verify once | 2-4, on a deliberate act |
| Zone-in (0x00A) | **OPEN — see C1** | 0 until you approach a box |
| Rescan button | Everything dirty, go now | manual, exists today |

**Consequences that fall out of this and are also locked:**
- **Inventory events (0x020 / 0x01D / 0x01E) are not wired to box logic at all.** On-hand is
  a free local bag scan; the box doesn't change when your bags do.
- **The 2s post-fetch settle timer is gone** — there is nothing to settle if we don't re-query.
- **Crafting at a box costs zero packets.** This was the whole point; ~22s/synth × 30 min
  next to a box was going to be 200-300 packets that cannot return new information.
- The 25s time-poll and the every-frame `ec.ensureCategories()` (`ui/restockui.lua:230`) die.
- Proximity gating stays free: `lib/entwatch.lua:246-251` is `GetMemoryManager():GetEntity()`
  + `GetRawEntity(idx)` — **100% local, zero packets.** Henrik's assumption verified.

*(Superseded en route: an earlier accepted rule accumulated dirty categories from
tracked-item inventory events behind a 2s CD. The 12:24 ruling replaced it. Also dropped
with it: the "only fetch categories with something below target, unless the panel is open"
split — with no inventory trigger there's nothing left for it to narrow.)*

### B3. The icon stack (floating nudge)
Three stacked icons near a box:

1. **Normal E-Box icon** (today's) — fetch with the current compare logic, which counts the
   field containers (Inventory 0, Satchel 5, Sack 6, Case 7). 2 Grape Daifuku in the Mog
   Case with target 12 → withdraws 10. Unchanged.
2. **Yellow icon** (`ebox_yellow.png`) — shown **only when** tracked items are sitting in
   *other* field containers but not in Inventory. Hover **reports where they are and how
   many**, so the player decides. Click pulls them into Inventory. **Fork open — see C2.**
3. **Red icon** (`ebox_red_icon-64.png`) — **always visible near a box**, fires `!box store`
   exactly like trove does. No tracking of whether anything needs depositing; this is just a
   convenient button for the command. Because the E-Box protocol has **no deposit action**
   (`trove/utils/packet.lua`: `WITHDRAW=2`, `WITHDRAW_PROMPT=3`, `GET_SUMMARY/CATEGORY/SEARCH`;
   `VAULT_DEPOSIT=16` is the *town Vault*, a different store), trove's own Store All is a
   chat command: `QueueCommand(1, '!box store')` (`trove/plugins/ebox.lua:628`).

**Assets still to copy into `assets/`:** `ebox_yellow.png`, `ebox_red_icon-64.png`
(source: `C:\Users\Henrik Johansson\OneDrive\Bilder\`).

### B4. The `!box` watch — build it, then field-test it
Henrik: *"b sounds good, we can test it. Sounds good that we make all our categories dirty
if we detect any !box store."*

Correction found after that answer: **`!box store` is not the only box-mutating command.**
Trove issues four — `!box store`, `!box cluster`, `!box ammo` (`ebox.lua:641,649`), and
**`!box <item name>`** (`ebox.lua:594`), a *withdraw by name* straight from trove's rows.
That last one changes the box with **no 0x1A4 we can see**, so our arithmetic would silently
drift low. Fix is free: watch for **any command beginning with `!box`**, not just `store`.

The unproven part: dlac already registers a `command` event (`restockui.lua:511`), and the
"a state never hears its OWN QueueCommand" rule only binds the *sending* addon — but
cross-addon visibility can't be proven without the game running. **Field test:** type
`!box store` yourself, then click trove's Store All, and see whether both re-arm the check.

### B5. GUI cleanup (panel)
- Kill the duplicated header: today line 1 reads *"E-Box Restock  keep chosen items topped
  up from the ephemeral box"* and line 2 reads *"E-Box Restock: <toggle>"*. **Remove line 1**;
  fold its explanation into the line-2 label as a `uistyle.helpLabel` underline+hover
  (verified to exist). Per [[panel-text-standard]].
- **Move "Fetch all" up under the E-Box Restock toggle** so the search UI can't push it down.
- Same treatment for Fetch all's explanatory text — into the hover, not inline.

---

## C. OPEN — the grill stopped here

### ~~C1. Zone-in (0x00A) re-verification~~ — **CLOSED 07-25: KEEP** (Henrik agreed to the recommendation below)
Every other repair signal is triggered by a failure you can *see*: a refused withdraw ACK
proves our number was too high and we mark stale on the spot. But the too-**low** case has no
symptom — we believe the box holds 0 Grape Daifuku, it actually holds 60, and the restocker
just quietly stops offering them. Looks like the feature broke.

**Recommendation: keep it.** It costs nothing until you actually walk up to a box in the new
zone (no box approached, no packets), and it's the one repair that doesn't depend on the
untested cross-addon `!box` watch. The alternative puts the feature's whole correctness on
that watch, with manual Rescan as the only recovery, and no way to tell "box is empty" from
"we lost track."

### ~~C2. What does the yellow icon do?~~ — **CLOSED 07-25: (a) now, (b) deferred**
Henrik: *"B is the best, but NOT allowed yet due to inventory / storage movement, can be
implemented later! For now, A is real."*

- **(a) SHIPS NOW** — yellow withdraws from the **box**, counting **Inventory only** as
  on-hand and ignoring the other field bags. Costs box stock; can leave you over target
  across bags (target 12, 2 in Case → 12 pulled, 14 total). Reuses the proven eboxclient
  withdraw path, slot clamp and box-cache decrement unchanged. The hover must report the
  other-bag copies so the player takes that trade knowingly.
- **(b) DEFERRED — dlac may not move items between containers yet.** Revisit when that's
  allowed; it's the better design (zero box stock, and it composes with the green icon to
  land exactly `target` in Inventory).

**Wire format for (b), already known — don't re-research it.** `dlacprobe.lua:1238-1258`
decodes **OUT 0x029** native item move from a real capture: `qty u32 @0x04`, `from u8 @0x08`,
`to u8 @0x09`, `fromSlot u8 @0x0A`, `toSlot u8 @0x0B`; logged live as
`Mog Safe[5] -> Inventory (toSlot 0x52)`; success = `2x 0x020 + 0x01D`, silence = server
reject. Open field-test question for that day: does a moved partial stack **merge** into an
existing Inventory stack, or take a fresh slot the way box withdrawals do?

### ~~C3. Search button cooldown~~ — **CLOSED 07-25: no own CD**
The button reflects `canQuery()` only (greyed while in flight or inside the existing
`MIN_GAP 1.0s`). A click is already deliberate; a second timer on top reads as a broken
button. The felt problem was the three bugs in §A, not the rate.

### ~~C4. Red button guard~~ — **CLOSED 07-25: arm-then-confirm** (broad blast radius, see §D2)
First click arms (icon brightens, tooltip → "Click again to store"), second click within ~3s
fires `!box store`, disarms on mouse-out. No dialog, no setting.

---

## D. Facts verified during the grill (don't re-derive)
- `lib/entwatch.lua:246-251` — proximity is **100% local**, zero packets.
- Zone-in marker = `packet_in` **0x00A**; already used by chocowatch, lockstyle, lookpreview,
  synthrun.
- `uistyle.helpLabel(im, text, tip, col)` exists and does underline+hover.
- **A "check" is not one packet.** 0x1A4 has no whole-box call — `GET_CATEGORY` fetches **one**
  AH category, serialized one-per-frame behind the 1s min-gap. Bolts + crystals + a food =
  **3 packets over ~3 seconds**.
- Existing inventory-change hook is `dlac-gearui-invdirty` at `ui/gearui.lua:4513-4517`
  (0x020 / 0x01D → `sf.invDirty()`), but `gear/syncflags.lua:200` returns early unless
  `sf.flags.autosync` — it's gearui's private scheduler, **not a reusable broadcast**.
  (Moot under B2, recorded so nobody hunts for it again.)
- Server clone on `stable` has **no 0x1A4 / E-Box implementation at all** — the wire-format
  authority is the local **trove** addon.
- E-Boxes sit in **safe zones** (Henrik) — no combat interruption case to design for. The
  `Ephemeral_Moogle_*` NPCs are the **crafting** moogles, which is why synth-at-box is the
  workflow that must cost zero packets.
- The `!box` command has **no handler in the server clone** (`stable`) — it's a live-server
  custom. The wiki below is the authority, not the source tree.

## D2. Wiki facts (authority for `!box`, since the source tree has none)
Sources: `bg-wiki.com/ffxi/CatsEyeXI_Commands` (§Ephemeral Box) and
`bg-wiki.com/ffxi/CatsEyeXI_Systems/Ephemeral_Box`.

- **`!box store` = "Instantly store every storable item in their inventory."** Instant, no
  prompt, within 5 yalms of a box.
- **Storable set** = base *common crafting materials*, plus, as expansions are unlocked:
  fish/rods/bait (Fishing Venture Points), **food and ninjutsu tools** (Tonberry Trouble),
  Allied Incursion materials, **ammo**, and **jug pets / pet food / automaton oil** (Allied
  Incursion). **That is almost exactly the restocker's tracked set** — so a misclicked red
  icon *undoes the restock you just did*, depositing the food/ammo/tools/oils green and
  yellow pulled. This is why C4 takes the arm-then-confirm guard.
- **Over-draw is unforgiving and wiki-confirmed:** "The Ephemeral Box does not prevent you
  from attempting to withdraw more items than you have inventory space for" — items that
  don't fit **"will fall to the floor and be lost forever,"** and the developers will not
  restore them. The planner's never-over-draw slot clamp is therefore **safety-critical**,
  not a nicety.
- Other subcommands, all covered by the `!box`-prefix watch: `!box <item>` / `!box <qty>
  <item>` (withdraw near a box), `!box ammo` (withdraw ammo as quivers/cases/boxes),
  `!box cluster` (crystals as clusters / Prismatic Cluster). Note `!box <item>` used *away*
  from a box is a stock check — a query path we don't consume.
- E-Box is **Crystal Warrior only**, quest-gated (Rusty Hammer, Northern San d'Oria, Lv40+),
  sited in the crafting guilds plus 11 other locations. Confirms the existing CW gate.

---

## E. BUILD — DONE 2026-07-25, addon.version 2026.07.25d
3358 checks green on Windows lua **and** WSL lua5.4. Not field-tested (see E5).

Two consequences of the locked decisions that the design didn't spell out, decided at build
time and recorded here because they are visible behaviour:

1. **"Only when needed" now governs the GREEN crate only.** It used to hide the whole nudge
   when nothing was fetchable. C4 says the deposit icon is *always* visible near a box, so the
   window now opens whenever master + Show-nudge + near-box hold, and the quiet setting
   suppresses the green icon inside it. With nothing to fetch you get just the red crate.
2. **Yellow's plan is a superset of green's.** It plans `target − Inventory` for *every*
   tracked item; for an item with nothing in the other bags that is identical to green's
   number, so clicking yellow also does green's job. The *icon* still only appears when the
   two plans differ, which is the rule that was agreed.

Deferred deliberately: no red/yellow equivalents in the panel (the nudge is the surface those
were specified for), and no `!box cluster` / `!box ammo` buttons.

**E1 — `feature/eboxclient.lua`: box stock is arithmetic** ✅
- `M.dirty[ahCat]`; `categoryFresh` returns false for a dirty category **at any maxAge**, which
  is what lets a consumer pass `math.huge` and get "count once, then only on invalidation".
  The old time window still works, so AutoAmmo's policy is untouched.
- New doors: `markDirty` / `markAllDirty` / `verifyCategory` / `verifyCategories` /
  `categoriesVerified` / `canQuery` / `searchBusy` / `clearSearch` / `boxStore`.
- `debit(id, qty)` at withdraw **send** time, on both `withdraw` and `withdrawBatch`; inside a
  batch each pull clamps against the count its predecessors already debited, so two stack-pulls
  of one item can't together over-ask. Batch completion **no longer stales anything**.
- `_batchCats` records the categories a batch touched; a **refused** ACK dirties exactly those.
- `M.PEND_HOLD` (5s): a LIST request whose answer never arrives no longer wedges `canQuery`
  forever. This mattered more once the periodic poll that used to paper over it was gone.
- Hooks: `packet_in` 0x00A → `markAllDirty`; `command` `^%s*!box` → `markAllDirty`, never
  blocked. `boxStore()` marks dirty at the queue site because a state never hears its own
  `QueueCommand`.
- **No inventory-event hook anywhere.**

**E2 — `ui/restockui.lua`: panel** ✅
- Search **button**; greyed via `ec.canQuery()`; `searching...` while in flight; results shown
  only when `ec.searchFor == the current text`; rows already on the target list hidden; adding
  keeps the picker open; open and close both `clearSearch()`.
- One header line via `uistyle.helpLabel`; **Fetch all** moved directly under the toggle with
  its explanation (including the never-over-draw promise) in the hover; the old footer line and
  the second header line are gone.
- `ensureCategories(cats, 25)` → `verifyCategories(cats)` at both call sites.

**E3 — nudge icon stack** ✅
- `iconButton()` helper (PNG with a labelled-button fallback); green unchanged in behaviour;
  yellow gated on `rw.otherBagNeed` and planned on Inventory-only on-hand, hover reports
  per-item location via the new per-bag scan; red always present, arm-then-confirm (3s, disarms
  on mouse-out, shows "sure?"), fires `ec.boxStore()`.

**E4b — `/dl debug ebox`: the traffic readout** ✅ (Henrik asked for it mid-build)
A design whose whole claim is "this barely sends anything" needs to be watchable, or the claim
is a hope — and it doubles as the E5-2 field test. `feature/eboxclient` keeps a bounded ring
(40 events) plus counters; `feature/eboxtrace` formats it; `feature/debug`'s router owns the
`ebox` topic (alias `box`).
- `/dl debug ebox` — how many packets, over how long, split by kind; the gates (CW? box in
  range? in flight? last send?); which categories are believed vs dirty; and the last 40
  events with ages, each dirty mark carrying **why** it happened.
- `/dl debug ebox on|off` — echo every event live as it happens. `reset` zeroes it.
- **The thread rule:** recording is pure table work, so the packet thread may do it; printing
  is pumped from `d3d_present`, because a print from the packet thread is the dig.lua crash.
- This is not packet capture ([[no-probing-in-dlac]] still stands — that lives in dlacprobe).
  dlacprobe can see an outgoing 0x1A4 but can never say *why* we sent it; only the client knows
  it was a verify rather than a re-count. Same class as `/dl check`.

**E4 — tests** ✅ EBC11–EBC16 (believe/dirty/re-count, debit arithmetic and its floor, refusal
repairs vs success doesn't, Rescan, search correlation and busy, headless gates, PEND_HOLD
release) and RS9–RS9f (otherBagNeed, and the divergence itself: field-bag plan fetches 0 where
the Inventory-only plan fetches 11). **EBC6d's expectation was inverted on purpose** — a
completed batch used to stale the counts; that was the poll this model deletes.

### E-review — five real defects, found by adversarially reviewing the build (07-25)
Four independent lenses over the diff, every claim then handed to a skeptic told to refute it:
14 claims, 5 survived. **Four of the five were created by this change**, and the theme is the
same in each: deleting the clock deleted the thing that used to quietly heal mistakes, so every
transient wrong belief became a permanent one.

1. **(high) The `PEND_HOLD` timeout I added let a late answer commit under the wrong
   category.** The 0x1A4 stream carries no request id — `_onPacket` attributes rows to whatever
   occupies the one in-flight slot. Once the timeout freed that slot and a new request took it,
   a slow reply committed as the *new* category's counts **and cleared its dirty mark**. With no
   clock left, wrong-and-believed is forever. Worse and lag-independent: `_pendingUntil` was
   never refreshed as rows arrived, so any list streaming longer than 5s was abandoned
   mid-stream and re-requested forever. Fixed by refreshing the deadline on `CLEAR`/`ITEM`, and
   by rejecting a category stream whose rows name a *different* ahCat (tolerant of ahCat 0, so
   an unexpected server shape can't cause an infinite re-ask). EBC17–EBC18.
2. **(medium) Clicking the picker's `close` threw a nil index in the same frame.** `closeAdd()`
   nils `_add`, and the new already-tracked pre-pass dereferenced it immediately after. Only
   `automationsui`'s `pcall` hid it — the panel silently stopped drawing for that frame. Fixed
   with a bail-out after the close button.
3. **(medium) `M.rescan` read `_ewok`/`_ew` as nil GLOBALS** — the entwatch require sat *below*
   it, and a local declared later isn't in scope, so it compiled to a global read
   (`GETTABUP _ENV "_ewok"`). Rescan's box re-sweep had never run; only the count half worked.
   **Pre-existing, not from this diff**, but this change promotes Rescan to THE repair path.
   Fixed by hoisting the require. EBC22 pins it as a source-order check, because nothing at
   runtime can see it — the exact hazard [[menu-settings-modelibrary]] records.
4. **(medium) A dirty mark raised while a category answer was in flight was wiped by that
   answer.** The reply predates the change that dirtied it. Reachable straight off the new red
   button: `!box store` → mark → re-count races the server's own processing of the command.
   Fixed with a `_pending.stale` flag honoured at commit, **plus** a 2s settle window
   (`M.SETTLE`) so an automatic re-count doesn't overtake a `!box ...` we just saw. Rescan
   outranks the settle — a click means count now. EBC19–EBC20d.
5. **(medium) The lost-ACK timeout left a send-time debit un-repaired and un-dirtied.** The ACK
   is the *only* repair for a debit; if it never arrives we cannot defend the number. Fixed by
   dirtying `_batchCats` when `BUSY_HOLD` fires. Costs one re-count after a fetch that never
   completed; crafting fires no withdraws, so the zero-packet promise is untouched. EBC21.

Nine claims were refuted, and three of them mattered: all three argued the **yellow icon's
visibility gate is correct as written** — B3 is the locked rule ("shown only when tracked items
are in other field containers but not in Inventory"), box stock is deliberately absent from it,
and the "shows only when its plan differs from green's" phrasing is a gloss in §E and in code
comments, not a separate requirement. The gate stands. (One refutation was fair but produced a
small improvement anyway: the yellow hover now prints the resulting total, so the deliberate
over-draw is a number rather than a caution.)

### E-review-2 — six more, from reviewing the fixes themselves
Fixes are where new defects get introduced, so the five above got their own adversarial pass.
Six survived refutation, and the biggest was a hole in a round-one fix:

1. **(high) 0x1A4 IS A PARTY LINE, and that is now permanent damage.** The `trove` addon
   speaks the same protocol on the same opcode with **no request id**. A foreign stream that
   lands while our `GET_CATEGORY` is in flight is consumed as *our* answer: a zero-match search
   in trove's Box tab commits **"this category is empty"** over real counts, and round one's
   ahCat guard cannot see it — an empty stream has no rows to check. A search for `bolt` while
   we verify ahCat 15 commits "bolts are all this category holds". v1 healed this in 25s; v2
   never does. **It cannot be prevented without a request id**, so the repair makes it
   self-correcting: an **unsolicited CLEAR** (`_pending == nil`) proves a list was on the wire
   around our commit → dirty that commit, once, if it was inside `PEND_HOLD`; and a **second
   CLEAR inside one request** proves interleaving → commit the answer but don't believe it.
   Rescan stays the backstop. EBC24–EBC24d.
2. **(medium) The deposit icon's arm survived frames that don't draw.** `_redArmAt` was only
   cleared by a not-hovered frame *inside* the drawing block, so arming it and then stepping
   out of range (or toggling the nudge off) and back within 3s left **one click firing
   `!box store`** — the exact misclick the guard exists to prevent. Cleared on all four early
   returns now.
3. **(medium) The yellow tooltip quoted an unclamped number.** `otherBagNeed`'s `want` is the
   raw Inventory shortfall and knows nothing about box stock or free slots, so it contradicted
   the planner's own list twelve lines below it in the same tooltip. It now reports what the
   click will actually pull ("pull 8 of 11").
4. **(high) EBC18 passed for the wrong reason** — it polled `canQuery()`, which short-circuits
   on the CW gate before ever reaching the timeout it claimed to pin. It never fired. One word
   (`searchBusy()`) makes it bite; verified by mutation.
5. **(medium) Nothing exercised the code that FILLS `_batchCats`** — both repair tests drove
   the `_beginBatch` seam, so deleting the production line that builds that table left the
   suite fully green. EBC21pre/EBC21b now go through the real `withdraw`/`withdrawBatch`.
6. Plus the empty-stream corner that round one explicitly left open, closed by (1).

### E-review-3 — the instrument had no instrument
A third pass over the party-line repair and the new trace surface. The repair itself survived
attack: measured at **0 sends in 10s with no foreign traffic** (the zero-packet promise intact),
~10 in 10s while something else queries the box every 0.3s (bounded by `MIN_GAP`, ~30% of the
foreign addon's own rate), and **1 in the tail** once that stops. One finding survived:

**(medium) EBC23 pinned the `_trace` arithmetic, not the instrumentation.** Every production
trace call in eboxclient could be deleted individually with the suite fully green — the same
seam-not-path defect as `_batchCats` in round two. It matters more here than it looks: the
readout **is** the E5-2 field test, and that test passes by showing an *empty log* — which is
exactly what a silently dead instrument shows. A false PASS on the design's central claim.
EBC23f/EBC23g now drive a real send, a real inbound commit, a real withdraw and a real dirty
mark, and demand each one appear; verified to fail when any single trace call is removed.

### F. FIELD ROUND 1 (Henrik, 2026-07-25 evening) — v2026.07.25e
The `!box` watch works and there is no spam. Three things came back, and two were the same bug.

**F1. `!box ammo` opens a MENU, so a timer-based re-count is guessing.** Henrik: *"I get a
menu, so it can really take however long for me to choose something there (if anything, I might
cancel). So setting a flag with a CD to scan the category doesn't really do much other than
unnecessary checks."* Correct — the command changes nothing; the *pick* does, whenever it comes.
**New rule: a `!box ...` command ARMS, and inventory movement inside that window is the proof.**
Cancel the menu and it costs zero packets; take three things and the burst window (`MENU_BURST`
15s) covers them. This is not the inventory-as-trigger rule the design rejected — bags changing
still never means the box changed. It means it only inside a window a `!box` command opened.
`boxStore()` uses the same arm, which is strictly better than the old settle: if nothing in your
bags was storable, nothing moves and we count nothing.

**F2. The repair loop Henrik circled** — `dirty cat=56 (a foreign 0x1A4 stream overlapped our
answer)` firing about once a second. Same root cause as F1: **an open box menu streams lists of
its own**, and every one of them looked like a thief. Two brakes: no repair at all while a menu
is armed, and outside that at most one per `REPAIR_GAP` (30s). We also now stay **off the wire
entirely while a menu is open** — our request would happily be answered by the menu's traffic.
And the log now NAMES the intruder (`foreign list ended: rows=N source=S`) so the next field
round can say whose stream it actually is instead of guessing.

**F3. `!box ammo` returns QUIVERS, which do not exist in the box or in our catalog.** Henrik:
a Blind Bolt withdrawal comes back as a Blind Bolt Quiver — a server-side conversion where a
99-stack becomes 1 item stacking to 12, so one Inventory slot holds 12×99 bolts. Verified: the
catalog has **no ammo-container items** (`Quiver` matches only gear like *Yoichi's Quiver*; the
only pouches are relic bullet pouches) — same class as the custom, dlac-invisible Yoru
(id 22999). **Consequence: a tracked ammo item's on-hand does not see quivers, so the restocker
will keep offering to fetch bolts you are already carrying 1188 of.** OPEN — needs Henrik's
call, see G1.

### G. ~~OPEN~~ — G1 CLOSED same day
**G1. Quiver-aware ammo — DONE.** Henrik's naming ruled out string-matching: *"Blind Bolt" →
"Blind Bolt Quiver"* appends, *"Beetle Arrow" → "Beetle Quiver"* **drops the word Arrow**, and
bullets use pouches — while our catalog abbreviates the containers on top of that
(*"Quelling B. Quiver"*). But the server knows exactly, because a container is a USABLE item
whose script hands you its contents:

```lua
-- scripts/items/blind_bolt_quiver.lua   -- ID: 5334
itemObject.onItemUse = function(target)
    npcUtil.giveItem(target, { { xi.item.BLIND_BOLT, 99 } })
end
```

`tools/gen_ammocontainers.py` reads all 74 `*_quiver.lua` / `*_pouch.lua`, resolves `xi.item.*`
through `scripts/enum/item.lua`, and writes **`data/ammocontainers.lua`** — 62 containers,
`[containerId] = { id = ammoId, qty = 99, name }`. Four were correctly skipped (bead/silt/
heavy-metal pouch and old_quiver give random or multiple things, not ammo).

**A server bug fell out of it:** `oberon_bullet_pouch.lua`'s header says `-- ID: 5822`, which is
*dweomer's* id — `item_basic.sql` says 5823. Trusting the script headers produced a table with
a duplicate key that silently dropped a row (62 written, 61 loaded). The generator now keys off
`item_basic.sql`, reports the disagreement, and **refuses to write a table with a duplicate id**
rather than lose a row quietly.

**How it counts (the part that needed a judgement call):** a container counts toward
*"do I have enough"* — so green stops offering to fetch bolts you own 1188 of — but **never**
toward *"is it in my Inventory"*. You cannot shoot a quiver; the fix for an empty Inventory is
to open one, not to withdraw from the box, so folding containers into the per-bag view would
make the yellow icon offer a pointless box withdrawal. The panel shows `have x210*`, and the
star's hover breaks it down: *"12 loose, plus 2 Blind Bolt Quiver worth 198 more."* Tests AC1–AC6d.

**E5 — field tests Henrik runs**
1. Does dlac's `command` handler see the `!box store` that **trove** queued? (Type it yourself
   first, then click trove's Store All.) If trove's doesn't register, the fallback is the
   tracked-item inventory heuristic, narrowly scoped.
2. Synth at a box for a few minutes with crystals tracked → confirm **zero** 0x1A4 traffic.

Version bump per [[addon-version-date-bump]].
