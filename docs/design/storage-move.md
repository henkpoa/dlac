# Storage move — right-click "Move To →" (research + design)

Status: research complete (incl. nomad-moogle follow-up, section F), design proposed,
**not implemented**.
Date: 2026-07-10.
Scope: right-click an item in the gear GUI → "Move To →" submenu → pick a destination
container → dlac sends the native item-move packet. Allowed only where the game itself
allows it (Mog House, and CatsEyeXI's Provenance hub with restrictions).

Server source examined: GitHub `CatsAndBoats/catseyexi`, branch `base` (default branch;
`stable`, `mods`, and `staging` were spot-checked and agree on every fact cited below).
Client prior art examined: the local Ashita v4 install at
`C:\catseyexi\catseyexi-client\Ashita` plus public Windower/Ashita addons.

## Verdict (TL;DR)

**Feasible and safely gateable.** The CatsEyeXI server (all public branches) runs the
modern LandSandBoat 0x029 handler which **fully validates container access
server-side** — it does not trust the client. Storage (container 2) is only accepted
when you are inside your **own Mog House**, exactly matching Henrik's rule. In
Provenance (zone 222) the server currently rejects Safe, Safe 2, Storage, and Locker
(the zone lacks the `MISC_MOGMENU` flag), and accepts Inventory, Satchel, Sack, Case,
and all Wardrobes. Direct container→container moves are supported — **no
hop-through-Inventory is required**. Invalid moves are silently dropped server-side
(console warning only, no kick, no rubber-band, no item risk). The client can detect
"in Mog House" reliably (proven memory flag used by luashitacast on this very client,
plus a packet-derived cross-check) and detect Provenance by zone id 222.

Nomad-moogle follow-up (section F): access is **(a) zone-wide, not
interaction-scoped**. Every native Nomad Moogle zone carries `MISC_MOGMENU` in
`zone_settings.misc`; the 0x029 validator checks only that zone flag (plus own-MH),
never any interaction/menu state. Talking to the moogle merely makes the server send
s2c **0x02E `GP_SERV_COMMAND_OPENMOGMENU`** (header-only) telling the client to open
its local mog menu — detectable, but irrelevant to what the server accepts. The mog
menu session is *not* a server event: the earlier PacketGuard concern does **not**
apply to it (re-verified in F.4 — only real scripted events/cutscenes block 0x029).

---

## A. The move mechanism

### A.1 Packet: outgoing 0x029 `GP_CLI_COMMAND_ITEM_MOVE`

Defined on the fork at `src/map/packets/c2s/0x029_item_move.h` (which itself cites
https://github.com/atom0s/XiPackets/tree/main/world/client/0x0029):

```cpp
GP_CLI_PACKET(GP_CLI_COMMAND_ITEM_MOVE,
              uint32_t ItemNum;    // quantity to move
              uint8_t  Category1;  // source container id
              uint8_t  Category2;  // destination container id
              uint8_t  ItemIndex1; // source slot index
              uint8_t  ItemIndex2; // destination slot index (0x52 = "server picks")
);
```

Total packet size **12 bytes (0x0C)**. Byte layout (offsets from packet start):

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0x00 | u16 | header: `id:9 \| size:7` | id = 0x029, size = 0x06 (units of 2 bytes: 12/2) |
| 0x02 | u16 | sync counter | filled in by Ashita's packet manager |
| 0x04 | u32 | `ItemNum` | quantity (little-endian) |
| 0x08 | u8 | `Category1` | from-container |
| 0x09 | u8 | `Category2` | to-container |
| 0x0A | u8 | `ItemIndex1` | from-slot |
| 0x0B | u8 | `ItemIndex2` | to-slot; **always send 0x52** (see below) |

Header struct: `src/map/packets/c2s/base.h` (`GP_CLI_HEADER`, `id:9 / size:7 / sync`).
Registration: `src/map/packet_system.cpp:270` —
`PacketSize[0x029] = 0x06; PacketParser[0x029] = &ValidatedPacketHandler<GP_CLI_COMMAND_ITEM_MOVE>;`
The size is checked on receipt (`src/map/map_networking.cpp:472`); a wrong size field
logs "Bad packet size" and the packet is skipped.

**`ItemIndex2` semantics** (from `0x029_item_move.cpp:188`): a value `< 82` is treated
as "unite/merge into the stack at that exact slot"; anything `>= 82` means "server
picks the first free slot" via `CItemContainer::InsertItem`. The retail client sends
`0x52` (82 = 80 max slots + 2). **Always send 0x52** — an accidental low value could
trigger the stack-merge path.

**`ItemNum` semantics**: if `ItemNum` < the stack's quantity, the server *splits* the
stack (`charutils::AddItem` to destination + `UpdateItem` on source). If equal, it
moves the whole stack (or merges when `ItemIndex2 < 82`). For gear (non-stackable)
send the item's exact `Count` (normally 1).

### A.2 Sending from an Ashita v4 addon

`AshitaCore:GetPacketManager():AddOutgoingPacket(id, table)` — C++ signature
`void AddOutgoingPacket(uint16_t id, uint32_t len, uint8_t* data)` at
`C:\catseyexi\catseyexi-client\Ashita\plugins\sdk\Ashita.h:1503`; the Lua binding takes
`(id, byteTable)` and derives the length. The table contains the **full packet
including the 4-byte header**; Ashita fills the sync counter. Sketch:

```lua
local qty = item.Count;  -- u32 little-endian
local p = {
    0x29, 0x06, 0x00, 0x00,                                    -- id, size, sync(x2)
    bit.band(qty, 0xFF), bit.band(bit.rshift(qty, 8), 0xFF),
    bit.band(bit.rshift(qty, 16), 0xFF), bit.band(bit.rshift(qty, 24), 0xFF),
    fromContainer, toContainer, fromSlot, 0x52,
};
AshitaCore:GetPacketManager():AddOutgoingPacket(0x29, p);
```

Local prior art for the send idiom (no local addon builds 0x029 itself):
`addons\autojoin\autojoin.lua:343` (explicit header bytes),
`addons\sellit\sellit.lua:62-64` (`struct.pack(...):totable()`),
`addons\luashitacast\equip.lua:417-421` (0x50 equip packet built by container/index).

### A.3 Public prior art (verified by fetching the sources)

- **Windower Organizer** (`Windower/Lua`, `addons/organizer/items.lua:395`) injects
  exactly this 12-byte layout: `string.char(0x29,6,0,0)..'I':pack(count)..
  string.char(from_bag,dest_bag,index,dest_slot)` with `dest_slot = 0x52` default.
  It routes everything through Inventory (`items:route`, line 157: "Cannot move
  between two bags that are not inventory bags") — a **Windower-side convention,
  not a packet/server requirement** (see A.4). Safety: bag enabled+space via
  `get_bag_info`, mog-house gating via `get_info().mog_house` or a nearby
  Nomad/Pilgrim Moogle scan, Storage excluded at nomads, skips item statuses
  5/19/25 (equipped / equipped-linkshell / bazaar), wardrobe accepts gear only.
- **ThornyFFXI/Porter** (`prep.lua:125-129`):
  `struct.pack('LLBBBB', 0, 1, container, 0, index, 0x52)` →
  `AddOutgoingPacket(0x29, ...)` (zeroed header also works — Ashita takes the id
  argument). Skips Flags 5/19/25; container gating identical to luashitacast's.
- **seekey13/XIIM** `modules/moveit.lua:256-271` and **tirem/XIUI**
  `modules/satchel/packets.lua:61-97`: same layout; XIUI's
  `find_first_empty_slot_index` returns `fixed_max + 2` = 82 — the origin of 0x52.
- **Windower packet docs** (`addons/libs/packets/fields.lua:387-394`): "This byte is
  0x52 when moving items between bags."

### A.4 Direct moves vs Inventory hops — **direct is supported**

The server handler (`0x029_item_move.cpp`) places no "one side must be Inventory"
restriction: `validate()` only requires **both** `Category1` and `Category2` to be in
the character's currently-valid container set, plus per-item rules (B.2). Mog Safe →
Wardrobe in a Mog House is a single legal packet. **Requirement 4 answer: no
Inventory hop is needed; no intermediate Inventory-space check is required.** (The
only forced routes involve the Recycle Bin, which this feature does not touch.)

---

## B. Server-side validation — the critical question

**The server validates everything; it does not trust the client.** All quotes from
`src/map/packets/c2s/0x029_item_move.cpp` on `CatsAndBoats/catseyexi@base` (identical
file present on `stable`, `mods`, `staging`).

### B.1 Container access (`validContainers`, lines 47-107)

```cpp
// Always available:
std::set allowedContainers = { LOC_INVENTORY, LOC_MOGCASE, LOC_WARDROBE, LOC_WARDROBE2 };

// Retail allows injecting into Safe from anywhere in a zone with a Nomad Moogle.
if (PChar->loc.zone->CanUseMisc(MISC_MOGMENU) || PChar->m_moghouseID == PChar->id)
{
    allowedContainers.insert(LOC_MOGSAFE);
    if (PChar->profile.mhflag & 0x20)          // Mog House 2F unlocked
        allowedContainers.insert(LOC_MOGSAFE2);
}

if (charutils::hasMogLockerAccess(PChar))
    allowedContainers.insert(LOC_MOGLOCKER);

// Storage only allowed if in your OWN Mog House.
if (PChar->m_moghouseID == PChar->id)
    allowedContainers.insert(LOC_STORAGE);

// Satchel, Sack, Wardrobe 3-8: allowed anywhere IF unlocked (container size > 0).
```

- `MISC_MOGMENU = 0x0020` (`src/map/zone.h:479`, "Ability to communicate with Nomad
  Moogle (menu access mog house)") — a static per-zone flag from
  `sql/zone_settings.sql` column `misc`.
- `m_moghouseID == PChar->id` is set only when entering your own Mog House
  (`src/map/packets/c2s/0x05e_maprect.cpp:212`: zoneline with `m_toZone == 0` →
  `PChar->m_moghouseID = PChar->id`); `inMogHouse()` is `m_moghouseID != 0`
  (`src/map/entities/charentity.cpp:781-784`).
- `hasMogLockerAccess` (`src/map/utils/charutils.cpp:6568`): requires an unexpired
  Mog Locker contract (charvar `mog-locker-expiry-timestamp`), and access-type "All
  areas" additionally requires `CanUseMisc(MISC_MOGMENU)` or own Mog House.

### B.2 Per-item rules (`isValidMovement`, lines 110-145)

Rejects: missing item, `ITEM_LOCKED` subtype, Gil; Recycle-Bin routes except
Locker↔Bin/Bin→Inventory; non-equipment into any Wardrobe ("Only equipment and
weapons can be moved to the wardrobe"). The `process()` stage additionally rejects
`quantity - reserve < ItemNum` (reserved = e.g. mid-trade).

### B.3 What failure looks like

`src/map/packet_system.cpp:216-237` (`ValidatedPacketHandler`): if `validate()` fails,
the server logs `Invalid GP_CLI_COMMAND_ITEM_MOVE packet from <name>: <errors>` and
**silently drops the packet** — no reply, no disconnect, no client-visible effect.
If `validate()` passes but the destination turns out to be full at `process()` time
(lines 248-265), the server re-sends every slot of the destination container
(`GP_SERV_COMMAND_ITEM_ATTR`) plus `GP_SERV_COMMAND_ITEM_SAME` to resync the client,
logs an error, and does not move the item.

### B.4 The resulting access matrix (this fork)

Container ids from `src/map/item_container.h:30-51` (identical to dlac's
`CONTAINER_NAMES` in `gearimport.lua:355-362`):

| id | Container | Anywhere | Own Mog House | Zone with MISC_MOGMENU | **Provenance (222) today** |
|----|-----------------|----------|---------------|------------------------|-----------------------------|
| 0 | Inventory | yes | yes | yes | **yes** |
| 1 | Mog Safe | no | yes | yes | **no** |
| 2 | **Storage** | no | **yes** | **no** | **no — server-enforced** |
| 3 | Temporary | never | never | never | no |
| 4 | Mog Locker | no | yes¹ | yes¹ | **no** |
| 5 | Mog Satchel | yes² | yes² | yes² | **yes²** |
| 6 | Mog Sack | yes² | yes² | yes² | **yes²** |
| 7 | Mog Case | yes | yes | yes | **yes** |
| 8,10-16 | Wardrobes 1-8 | yes² | yes² | yes² | **yes²** |
| 9 | Mog Safe 2 | no | yes³ | yes³ | **no** |
| 17 | Recycle Bin | special | special | special | out of scope |

¹ with unexpired Locker contract. ² if unlocked (server: `GetSize() > 0`; client
mirror: `GetContainerCountMax(id) > 0`). ³ if Mog House 2F unlocked (`mhflag & 0x20`).

### B.5 Provenance specifically

`sql/zone_settings.sql:266` (fork, all branches):

```sql
INSERT INTO `zone_settings` VALUES (222,0,'127.0.0.1',54230,'Provenance',56,56,56,56,0,0.00,4096);
```

`misc = 4096 = 0x1000 = MISC_LOS_PLAYER_BLOCK` only. **`MISC_MOGMENU` (0x0020) is NOT
set** (stock LSB has 4224 = 0x1080, also without MOGMENU — CatsEyeXI did not add it).
`scripts/zones/Provenance/Zone.lua` and `IDs.lua` are near-empty stubs; no
Provenance-specific module exists under `modules/` on any public branch, and
`modules/init.txt` enables only `custom/commands/` and one test-NPC script.
`sql/npc_list.sql` for zone 222 contains eight generic hidden "Moogle" NPCs at (0,0,0)
(the standard per-zone Mog House moogles) — the visible hub moogle Henrik describes is
not in the public repo (live-DB customization; see Open questions).

**Consequences:**

- **Storage in Provenance: rejected by the server** (needs `m_moghouseID == id`).
  Henrik's rule 2 is enforced natively — we mirror it, we don't have to invent it.
- Safe, Safe 2, and Locker are **also** rejected in Provenance today (no
  `MISC_MOGMENU`). This is stricter than Henrik assumed. If CatsEyeXI wants
  Safe/Safe2/Locker movable at the Provenance moogle, the server fix is one value:
  `misc` 4096 → 4128 (adds 0x0020). Storage would *still* be excluded there — the
  server's Storage rule ignores `MISC_MOGMENU` entirely. Worth requesting; the
  client design below auto-adapts either way via `MogZoneFlag` (C.3).
- What works in Provenance today: Inventory ↔ Satchel/Sack/Case/Wardrobes 1-8.

---

## C. "Am I allowed right now?" — client-side detection

### C.1 In Mog House (primary: proven memory flag)

Ashita v4 has **no SDK "in mog house" API** (`IPlayer::GetResidence()` at
`Ashita.h:1135` is the residence *nation area* id, not a live flag). The working
method ships with this very client in luashitacast — dlac's own companion:

`addons\luashitacast\state.lua:22,39,44` resolves a signature in FFXiMain.dll:

```lua
gState.pZoneFlags = ashita.memory.find('FFXiMain.dll', 0,
    '8B8C24040100008B90????????0BD18990????????8B15????????8B82', 0, 0);
gState.pZoneOffset = ashita.memory.read_uint32(gState.pZoneFlags, 0x09);
gState.pZoneFlags  = ashita.memory.read_uint32(gState.pZoneFlags, 0x17);
```

`addons\luashitacast\data.lua:6-21` (`CheckInMogHouse`): read
`zoneFlags = read_uint32(read_uint32(pZoneFlags) + pZoneOffset)`; **bit `0x100` set =
inside Mog House**. ThornyFFXI's Porter uses the identical signature. dlac should
replicate this scan (addons cannot share Lua state).

### C.2 Cross-check: incoming zone packet 0x00A `LoginState`

Server side (`src/map/packets/s2c/0x00a_login.cpp:195-206`):
`if (PChar->inMogHouse()) packet.LoginState = SAVE_LOGIN_STATE_MYROOM;` with
`SAVE_LOGIN_STATE_MYROOM = 1` (`0x00a_login.h:50-58`). Computing struct offsets puts
`LoginState` (u32) at **absolute byte 0x80** of the raw packet — matching the local
`addons\zonename\zonename.lua:74-76` (`struct.unpack('b', e.data, 0x80 + 1) == 1`) and
Windower GearSwap (`packet_parsing.lua:67`, `data:byte(0x81) == 1`).

Caveat: LSB also sends `MYROOM` for the Feretory (Monstrosity) zone
(`0x00a_login.cpp:235-240`) — combine with zone id ≠ Feretory (285) if ever relevant on
CatsEyeXI. On `packet_in` for id 0x00A, also update the zone id and re-arm C.3.

### C.3 Zone permission flag: `MogZoneFlag` — the server literally tells us

Same packet, absolute byte **0xAF** (computed from `0x00a_login.h:100-131`;
`0x00a_login.cpp:212`):

```cpp
packet.MogZoneFlag = PChar->loc.zone->CanUseMisc(MISC_MOGMENU); // flag allows Mog Menu outside Mog House
```

This is **the exact predicate the 0x029 validator uses** for Safe/Safe2/Locker access.
Reading it from the zone-in packet means dlac mirrors the *live* server configuration:
if CatsEyeXI ever adds `MISC_MOGMENU` to Provenance, Safe/Safe2/Locker light up
automatically without a dlac change — and Storage still never does. Today this byte is
0 in Provenance. Until a 0x00A has been observed after addon load, treat it as 0
(conservative).

### C.4 Zone id for Provenance

`AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)`
(`Ashita.h:1076`) — Provenance is **zone 222** (`sql/zone_settings.sql:266`;
`scripts/zones/Provenance/IDs.lua` indexes `zones[xi.zone.PROVENANCE]`).

### C.5 Bottom line for requirement 1

There is a reliable, positive "movement permitted" signal set: the in-MH memory flag
(0x100), the 0x00A `LoginState==1` cross-check, and the 0x00A `MogZoneFlag` for
nomad-menu zones. The hard gate is: **in-MH, OR (zone == 222 AND container is in the
Provenance-legal set)**. If none of these signals affirmatively hold, dlac never
sends a move. No probing, no exceptions.

---

## D. Capacity, fullness, and move confirmation

### D.1 Ashita APIs (verified in `plugins\sdk\Ashita.h:983-994`)

```cpp
uint32_t GetContainerCount(uint32_t containerId);        // used slots
uint32_t GetContainerCountMax(uint32_t containerId);     // capacity (0 = locked/absent)
Ashita::FFXI::item_t* GetContainerItem(uint32_t containerId, uint32_t index);
uint32_t GetContainerUpdateCounter();                    // increments on any item change
uint32_t GetContainerUpdateFlags();                      // containers finished loading
```

`item_t` (`plugins\sdk\ffxi\inventory.h:36-44`): `Id (u16), Index (u16), Count (u32),
Flags (u32), Price, Extra[28]`. dlac already enumerates containers 0-16 this way
(`gearimport.lua` `ALL_CONTAINERS` / `ownedSplit()`, lines 355-390; skip `Id == 0` and
`Id == 65535`). Fullness: `GetContainerCount(id) >= GetContainerCountMax(id)`.
"Unlocked": `GetContainerCountMax(id) > 0` — the client mirror of the server's
`GetSize() > 0` check, fed by s2c 0x01C `GP_SERV_COMMAND_ITEM_MAX`
(`src/map/packets/s2c/0x01c_item_max.h`: `uint8 ItemNum[18]` / `uint16 ItemNum2[18]`
per-container capacities).

### D.2 What confirms a move (incoming packets)

For a successful whole-stack move the handler (`0x029_item_move.cpp:227-241, 268`)
sends:

1. `GP_SERV_COMMAND_ITEM_ATTR` (**0x020**) for the *source* (container, slot) — cleared;
2. `GP_SERV_COMMAND_ITEM_ATTR` (**0x020**) for the *destination* (container, new slot);
3. `GP_SERV_COMMAND_ITEM_SAME` (**0x01D**) — "containers updated / all loaded" marker.

Splits/merges use `charutils::AddItem`/`UpdateItem`, which push 0x020 and
`GP_SERV_COMMAND_ITEM_NUM` (**0x01E**, count change) followed by 0x01D
(`charutils.cpp:1730, 1920`; AddItem tail pushes ITEM_ATTR + ITEM_SAME). s2c 0x01F
(`ITEM_LIST`) appears only in full-container dumps (zone-in / resync).

**Ashita's memory (`GetContainerItem` etc.) updates only after the client processes
these incoming packets** — it mirrors FFXiMain's own inventory structures. It does NOT
update at send time. Therefore:

- After sending, watch `packet_in` for 0x020 touching our source (container, slot),
  then **verify from memory**: source slot now empty/decremented, destination gained
  the item id, `GetContainerUpdateCounter()` advanced.
- A **validation reject produces no reply at all** (B.3) — a timeout is the only
  signal. Use ~2 s; on timeout, cancel the operation and re-scan.
- A **full-destination race** produces a destination resync + 0x01D but the source
  slot is unchanged → treat as rejected.
- **Never fire-and-forget chained moves.** One in-flight move at a time; a second hop
  (should one ever exist) is sent only after the first is memory-verified.

---

## E. Risks

1. **Server reject behavior — benign.** Validation failure: silent drop + server
   console warning (`packet_system.cpp:235`); nothing changes client-side because the
   addon (unlike the native menu) never pre-updates client inventory. Full
   destination at process time: server resyncs the destination container. No kick,
   no rubber-band, no rollback risk: the DB move is a single guarded `UPDATE` with
   in-memory rollback on failure (`0x029_item_move.cpp:227-246`).
2. **PacketGuard** (`src/map/packet_guard.cpp`, enabled by default —
   `settings/default/map.lua:34`): 0x029 is not rate-limited, but it is **not** on
   the cutscene allow-list — a move sent while the player is in a *scripted
   event/cutscene* (`SUBSTATE_IN_CS`) is dropped with a "player substate" warning.
   Precisely scoped in F.4: this substate is set **only** when a Lua `startEvent`
   fires (`charentity.cpp:3163`); ordinary NPC dialog via `showText`/`sendMenu` —
   including the entire nomad-moogle mog-menu session — leaves the character in
   `SUBSTATE_NONE`, where every packet is allowed (`packet_guard.cpp:49-52`).
   Gate on own entity status ≠ 4 (`ANIMATION_EVENT`, `baseentity.h:66`) before
   sending.
3. **Stale slot index = moving the wrong item.** The real hazard is client-side: if
   the UI snapshot is old (item sorted/consumed/moved), `ItemIndex1` may now hold a
   different item. Mitigation (hard rule): re-read `GetContainerItem(from, slot)`
   **immediately before send** and require `Id` and `Count` to match what the user
   clicked; abort otherwise.
4. **Accidental stack-merge:** `ItemIndex2 < 82` invokes the unite path. Always send
   0x52 (A.1).
5. **Equipped / bazaar / locked items:** server rejects `ITEM_LOCKED`; prior art
   additionally skips client `Flags`/status 5 (equipped), 19 (equipped linkshell),
   25 (bazaar). dlac must skip these too — especially equipped wardrobe gear, which
   luashitacast may re-reference in sets.
6. **Duplication:** not achievable through this handler — quantity is clamped by
   `getQuantity() - getReserve()`, splits go through `AddItem`, and the whole-stack
   path is one DB row update. The old pre-rework LSB handler (see Open questions)
   was similarly conservative.
7. **Sort/other addons racing:** the native sort (0x03A) or another addon touching
   inventory mid-move is covered by mitigation 3 + single-in-flight + verify.

---

## F. Nomad Moogles (interaction-scoped access?)

Question (Henrik): Nomad Moogles grant storage access via an NPC menu — can we detect
that interaction, and does the server key 0x029 permission on it? Proposed gate:
`MogZoneFlag OR own-MH, plus a nomad-moogle-interaction check where applicable`.

### F.1 Verdict: (a) zone-wide flag — the interaction is cosmetic to the server

Two competing models were tested against the source:
(a) nomad zones carry `MISC_MOGMENU` zone-wide and the moogle chat is irrelevant to
the server, vs (b) an interaction-scoped state the 0x029 validator honors.

**(a) is the truth.** Evidence:

1. Every zone with a native `Nomad_Moogle` NPC script has `MISC_MOGMENU (0x0020)` set
   in `sql/zone_settings.sql` (fork, branch `base`):

   | Zone (id) | `misc` | & 0x0020 |
   |---|---|---|
   | Tavnazian Safehold (26) | 22120 = 0x5668 | yes |
   | Rabao (247) | 22120 = 0x5668 | yes |
   | Selbina (248) | 21544 = 0x5428 | yes |
   | Mhaura (249) | 21544 = 0x5428 | yes |
   | Kazham (250) | 22056 = 0x5628 | yes |
   | Norg (252) | 22120 = 0x5668 | yes |
   | Nashmau (53) | 17960 = 0x4628 | yes |
   | Mog Garden (280) | 4128 = 0x1020 | yes |

   (Al Zahbi 5784/0x1698 and Whitegate 22024/0x5608 do *not* carry it — those have
   real residential Mog Houses instead; their special-casing lives in
   `hasMogLockerAccess`, B.1. Provenance 4096/0x1000: not set, B.5.)

2. The 0x029 validator was re-read end-to-end
   (`src/map/packets/c2s/0x029_item_move.cpp:47-162`): its only inputs are
   `PChar->loc.zone->CanUseMisc(MISC_MOGMENU)`, `PChar->m_moghouseID`,
   `charutils::hasMogLockerAccess`, `mhflag & 0x20`, container sizes, and the
   recycle-bin setting. **There is no event, menu, interaction, or NPC-proximity
   state anywhere in it.** Its own comment (line 69) says so: "Retail allows
   injecting into Safe from anywhere in a zone with a Nomad Moogle."

3. What the moogle interaction actually does: every native Nomad Moogle script is
   two lines, e.g. `scripts/zones/Selbina/npcs/Nomad_Moogle.lua`:

   ```lua
   entity.onTrigger = function(player, npc)
       player:showText(npc, ID.text.NOMAD_MOOGLE_DIALOG)
       player:sendMenu(xi.menuType.MOOGLE)   -- MOOGLE = 1, scripts/enum/menu_type.lua
   end
   ```

   `sendMenu(1)` (`src/map/lua/lua_baseentity.cpp:2495`) pushes s2c
   **0x02E `GP_SERV_COMMAND_OPENMOGMENU`** — a **header-only 4-byte packet**
   (`src/map/packets/s2c/0x02e_openmogmenu.h`: "inform the client to open the mog
   house menu"; id confirmed in `src/map/enums/packet_s2c.h:58`). The same packet is
   pushed by the in-MH moogle path (`scripts/globals/moghouse.lua:378`). After that,
   the entire mog menu (and any moves the player makes in it) is the client's native
   UI sending ordinary 0x029s. **No server-side state changes, and no "menu closed"
   packet exists** — closing is client-local.

Consequence for Henrik's proposed gate: the "nomad-moogle-interaction check" adds no
server alignment — the server accepts 0x029 from anywhere in a `MISC_MOGMENU` zone
whether or not the moogle was ever spoken to (that is also native retail behavior:
the flag's purpose, per `0x00a_login.cpp:212`, is to enable the client's Mog Menu
zone-wide). `MogZoneFlag` (C.3) already covers native nomad zones exactly. The
CatsEyeXI Provenance moogle remains a live-server unknown → probe protocol in F.5.

### F.2 Client-visible signal: s2c 0x02E

- **Id/layout**: incoming 0x02E, 4 bytes total (header only: `id:9|size:7`, sync).
  No payload, no fields.
- **When sent**: the instant a script calls `sendMenu(MOOGLE)` — i.e. on triggering
  a Nomad Moogle (or the MH moogle). Not sent on menu close; not re-sent while the
  menu is open.
- **Use**: an *edge* signal ("a moogle menu just opened"), usable for UX or for the
  probe below — but it cannot serve as a stateful "menu is open" gate (no close
  event), and per F.1 it is not needed for permission gating.

### F.3 Identifying the interaction target (if ever wanted)

The trigger is client→server 0x01A `GP_CLI_COMMAND_ACTION`
(`src/map/packets/c2s/0x01a_action.h:128-131`): `UniqueNo` u32 @0x04, `ActIndex` u16
@0x08, `ActionID` u16 @0x0A, with `ActionID = Talk = 0x00` (enum at line 54). An
Ashita addon watching `packet_out` for 0x01A/Talk can resolve the NPC name via
`AshitaCore:GetMemoryManager():GetEntity():GetName(ActIndex)` (`Ashita.h:730`).
Pairing "outgoing Talk at entity named *Moogle/Nomad Moogle*" with "incoming 0x02E
within ~1 s" identifies a moogle mog-menu session start unambiguously.

### F.4 PacketGuard re-verified: the moogle menu is NOT an event

The earlier E.2 claim ("dropped during cutscenes/NPC menus") was too broad. Precise
mechanics:

- `SUBSTATE_IN_CS` is set in exactly one place:
  `CCharEntity::tryStartNextEvent()` (`src/map/entities/charentity.cpp:3163`), which
  runs only when a Lua script starts a real **event/cutscene** (`startEvent`); it
  also sets `animation = ANIMATION_EVENT` (= 4, `baseentity.h:66`) and sends
  0x032/0x033/0x034 event packets. It is cleared by `endCurrentEvent()`
  (`charentity.cpp:3102`), `skipEvent()` (`:3211`), and s2c 0x052 `EVENTUCOFF`
  (`0x052_eventucoff.cpp:36`).
- A Nomad Moogle trigger starts **no event**: `onTrigger` only calls
  `showText` + `sendMenu` (F.1), and the 0x01A handler then releases the client
  (`0x01a_action.cpp:149`, `EVENTUCOFF` Standard). The character stays in
  `SUBSTATE_NONE`, where PacketGuard's allow-list permits everything
  (`packet_guard.cpp:49-52`) and 0x029 is not rate-limited.
- This matches retail reality: the client sends 0x029 freely while the native mog
  menu is open — no PacketGuard exception exists because none is needed.

**The nomad path is therefore not design-breaking.** The only real constraint stands
unchanged: never send 0x029 while a scripted event/cutscene is active (own entity
status == 4).

### F.5 Provenance live probe protocol (run once before implementation)

The custom Provenance moogle is not in the public repo, so its mechanism (plain
`sendMenu` vs custom event) and the live zone's `misc` value must be observed
in-game. Protocol — no packets injected, observation only:

**Watch list** (a packet-log addon, or a temporary dlac debug hook on
`packet_in`/`packet_out`):

| Dir | Id | What to record |
|---|---|---|
| in | 0x00A | byte 0x80 (`LoginState`), byte 0xAF (`MogZoneFlag`) on zoning into Provenance |
| in | 0x02E | arrival = native mog menu opened (`sendMenu(MOOGLE)` path) |
| in | 0x032/0x033/0x034 | arrival = scripted event path instead |
| in | 0x052 | client release after trigger |
| out | 0x01A | `ActIndex`/`ActionID` of the moogle trigger |
| in | 0x020 / 0x01D / 0x01E | move confirmations during step 4 |

**Steps:**

1. Zone into Provenance → record `MogZoneFlag` (byte 0xAF). Repo predicts **0**.
2. Trigger the hub moogle → record which of 0x02E vs 0x032/0x034 arrives, and
   whether the native mog menu UI opens with storage options (and which bags it
   lists).
3. If a menu opened: natively move a junk item Inventory → Mog Safe. Record
   success (item moves; two 0x020 + 0x01D observed) vs nothing happening
   (server-side silent reject).
4. If offered, attempt Inventory → **Storage** natively. Expected: not offered, or
   silently rejected (validator requires own-MH for Storage regardless of zone).
5. Repeat step 3 for Locker if a contract is active.

**Interpretation:**

- `MogZoneFlag == 1` → live Provenance already has `MISC_MOGMENU`; the
  "MISC_MOGMENU zone" column of the B.4 matrix applies there and dlac's C.3 gate
  picks it up with zero code changes.
- `MogZoneFlag == 0` and native Safe move fails / isn't offered → repo matches
  live; Provenance allows only Inventory/Satchel/Sack/Case/Wardrobes (B.5) unless
  the server team adds the flag.
- `MogZoneFlag == 0` **but** a native Safe move succeeds → live server diverges
  from every public branch (custom validator or pre-rework handler). Stop and
  re-research before implementing; do not widen any gate on this evidence alone.
- Storage moving natively in Provenance in any variant → model falsified; halt.

Nothing from this probe gets hardcoded: the runtime gate reads `MogZoneFlag` per
zone-in, so a later server-side change to Provenance is absorbed automatically.

---

## Proposed design

### Hard invariants (non-negotiable, enforced in code)

- **INV-1 — The Gate.** A move may be *offered or sent* only when, evaluated fresh at
  that moment: `inMogHouse()` (memory flag 0x100, C.1) **OR** `zoneId == 222`
  (Provenance). Anywhere else: the "Move To" menu entry does not appear at all. If
  the memory signature failed to resolve at load, `inMogHouse()` is permanently
  false (fail closed) and only the Provenance path can open the menu.
- **INV-2 — Storage is Mog-House-only.** Container 2 is offered as source or
  destination **only** when `inMogHouse()`. It is never offered in Provenance, even
  if a future server change relaxes other containers. (The server enforces this too;
  we do not rely on that.)
- **INV-3 — Per-container legality mirrors the server validator.**
  - Always legal (given INV-1): 0 Inventory, 7 Case; 5 Satchel, 6 Sack, 8/10-16
    Wardrobes when `GetContainerCountMax(id) > 0`.
  - 1 Safe, 9 Safe 2, 4 Locker: legal iff `inMogHouse()` OR `MogZoneFlag == 1`
    observed in the current zone's 0x00A (C.3). Unobserved ⇒ 0 ⇒ not offered.
    (Today in Provenance: not offered.)
  - 2 Storage: INV-2. 3 Temporary and 17 Recycle Bin: never offered.
  - Both source and destination must pass; wardrobe destinations only for
    equipment/weapons (always true for dlac's gear UI — assert anyway).
- **INV-4 — Fullness filter.** A destination appears in "Move To" only if
  `GetContainerCount(id) < GetContainerCountMax(id)`. Re-check at click time, not
  just at menu build.
- **INV-5 — Single in-flight, verify-then-proceed.** At most one outstanding move
  addon-wide. Immediately before send: re-read the source slot and require item id +
  count match (E.3); require player status ≠ event (E.2). After send: wait for 0x020
  on the source slot, then memory-verify; 2 s timeout ⇒ treat as rejected, discard
  any queued intent, force a container re-scan before the feature re-arms.
- **INV-6 — Direct moves only.** Source → destination in one packet (A.4). No
  Inventory hop exists in v1. If a hop is ever introduced, the intermediate
  Inventory step must independently satisfy INV-4 for Inventory *before the first
  packet is sent*, and each hop waits on INV-5 verification.
- **INV-7 — Never trust "server will reject".** Server-side validation (B) is the
  safety net, not the mechanism. Every rule above is enforced client-side first; a
  packet that we know would fail is never sent.

### Henrik's nomad-moogle formulation, resolved

Henrik proposed: gate = `MogZoneFlag OR own-MH`, **plus** a nomad-moogle-interaction
check where applicable. Finding F.1 settles the second clause: storage permission is
**(a) zone-wide** — the 0x029 validator has no interaction state, and natively the
Mog Menu is available zone-wide wherever `MogZoneFlag` is set (that is the flag's
purpose). So the interaction check would be *stricter than the native game*, gains no
server alignment, and rests on a fragile signal (0x02E has no close counterpart —
"menu currently open" is unknowable). **Recommendation: drop it.** The gate stays
INV-1/INV-3 as written — `own-MH OR (zone == 222 with the per-container matrix)`,
with Safe/Safe2/Locker keyed to the live `MogZoneFlag`, which already *is* the
server's own nomad-moogle predicate. If Henrik still wants the moogle-chat UX
("storage bags only appear after kupo"), F.2/F.3 give the detection recipe: arm on
0x02E, disarm on zone change — cosmetic only, layered on top of (never instead of)
the invariants.

### Move engine sketch

State machine: `idle → preflight → sent → confirmed | timeout`. `preflight` evaluates
INV-1..5; `sent` records `(fromCid, fromSlot, itemId, count, toCid, sentAt)`;
`packet_in` 0x020/0x01D and a per-frame timeout check drive the transition. On
`confirmed`, refresh dlac's owned-items snapshot (`gearimport.ownedSplit()` consumers)
so the UI reflects the new location. On `timeout`, log to chat ("move not confirmed —
server may have rejected it") and re-scan.

### UI behavior (documenting, not building)

- Right-click a gear row → "Move To →" submenu, one entry per *legal* (INV-3) and
  *non-full* (INV-4) destination, labeled with `containerName(cid)` and free-slot
  count, e.g. `Mog Safe (12 free)`. The item's current container is omitted.
- Outside the Gate (INV-1): no "Move To" entry at all (cleanest signal that movement
  is location-gated; a tooltip on the row may say "moving requires Mog House or
  Provenance").
- Henrik's rule as specified: *if Inventory is full, the right-click menu is
  blocked/greyed with warning "inventory is full."* That rule assumed hop-through-
  Inventory. Finding A.4 removes the technical need. **Recommendation:** grey only
  the "→ Inventory" entry (with the warning as its tooltip) and keep every other
  destination live — a full Inventory is precisely when moving things *out* of it
  matters most. If Henrik prefers the literal rule, implement it as a whole-menu
  grey + warning line; both are trivial. Default to the recommendation pending his
  call.
- While a move is in flight (INV-5): the submenu is disabled ("moving…").
- Items with equipped/bazaar/locked flags: entry greyed with reason.

### Suggested server-side ask (optional, for Henrik → CatsEyeXI)

One-line change: `zone_settings.misc` for zone 222 from 4096 to **4128** (adds
`MISC_MOGMENU 0x0020`). Effect: Safe/Safe 2/Locker become movable at the Provenance
moogle *by the server's own retail-accurate rules*, Storage remains Mog-House-only
(server-enforced), and dlac picks it up automatically through `MogZoneFlag` with zero
addon changes. Side effects to review: the flag also enables the client's native
"Mog Menu" at nomad moogles and `hasMogLockerAccess` type-1 in that zone.

---

## Open questions

1. **Does production run the code in the public repo?** All public branches (`base`,
   `stable`, `mods`, `staging`) carry the modern validated 0x029 handler, but the
   live server binary/DB cannot be inspected from outside. Notably, an older
   CatsEye-lineage snapshot (`Aeltorian/catseyexi`, branch `LSB_August_2023`,
   `src/map/packet_system.cpp` `SmallPacket0x029`) had **no container-access
   validation at all** (and read quantity as u8). If production were that old, the
   server would honor e.g. Storage-in-Provenance — which is exactly why INV-7
   exists: dlac's gates never depend on server rejection. `MogZoneFlag` (C.3) also
   reads whatever the *live* server actually has configured.
2. **Live Provenance customization.** Henrik reports custom hub NPCs (Crystal
   Warriors) that are absent from the public repo — live DB/scripts evidently
   diverge. The public repo's `misc=4096` (no MOGMENU) is therefore *probably* but
   not *certainly* the live value, and the custom hub moogle's mechanism
   (`sendMenu(MOOGLE)` vs a custom event) is unknown. **Resolved into an
   executable plan:** run the F.5 probe protocol once before implementation; the
   runtime gate reads `MogZoneFlag` per zone-in either way, so nothing is
   hardcoded on the outcome.
3. **Safe 2 unlock visibility.** The server gates Safe 2 on `mhflag & 0x20` (MH 2F),
   which the client cannot read directly. Unverified whether
   `GetContainerCountMax(9)` is 0 until 2F is unlocked. Mitigation: offer Safe 2
   only when its max > 0 AND the Safe gate holds; INV-5's timeout covers a wrong
   guess harmlessly.
4. **Locker contract expiry** (charvars `mog-locker-*`) is likewise not
   client-visible. Same mitigation; optionally hide Locker when
   `GetContainerCountMax(4) == 0`.
5. **Can you enter your Mog House from Provenance?** MH entry requires a zoneline
   with `m_toZone == 0` (`0x05e_maprect.cpp:212`); whether zone 222 has one was not
   verified. Irrelevant to safety — if you can't, the MH gate simply never fires
   there.
6. **Windower 5 disagreement** on the 0x00A mog-house bit position (raw 0x81 bit 1)
   vs GearSwap/XiPackets/LSB (u32 at raw 0x80 == 1). The latter three agree and
   include the authoritative server source; W5 is pre-release. Use 0x80.
7. **`GetContainerUpdateCounter()`** is the SDK-sanctioned change signal but no local
   addon exercises it; verify its behavior empirically before relying on it as the
   *sole* confirmation (the 0x020-then-memory-verify path does not depend on it).
