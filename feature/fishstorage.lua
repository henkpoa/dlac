-- Caught-item transfers into the Mog Case / Mog Satchel (AscensionXI fishing,
-- docs/reference/ascensionxi-fishing.md). The third mover, built on HELM's
-- (feature/helmstorage.lua) and digging's: keep a count per item of what
-- fishing added ("owed") and move WHOLE stacks only -- a full stack, or an
-- item that does not stack, as you fish; a partial stack once fishing has
-- paused for FLUSH_S. It never moves more of an item than your catches added,
-- so stock you carried in stays where it was.
--
-- One catch is our reel -- outgoing 0x110 mode 3, RequestEndMiniGame -- then
-- the server's answer: ITEM_ATTR + ITEM_SAME for the catch (CatchFish /
-- CatchItem, an ItemClaimTransaction), then the bait it took (BaitLoss, one
-- more ITEM_SAME). A broken line or rod answers with the bait and, for a rod,
-- the broken rod. Nothing marks the last packet, so a reel is counted once its
-- answer has been quiet for SETTLE_S, or at our own release (0x110 mode 4),
-- which the client sends only after the catch animation. Only ids the pack's
-- fishing tables list as catches are ever owed (fishdb.fish), never bait,
-- never a broken rod -- and of those, TRASH (the rows the server flags as not
-- a fish: rusty gear, kelp, shells, scrolls) only while the player's "Move
-- trash too" switch is on. It is off by default: fish only (Henrik
-- 2026-10-15). D.catchKind(id) says 'fish', 'trash' or nil.
local M = { QUIET_S = 1, FLUSH_S = 6, CAPTURE_S = 5, SETTLE_S = 0.5, CONFIRM_S = 5, GAP_S = 0.2, ZONE_S = 5 };
M.REEL, M.RELEASE = 3, 4;   -- GP_CLI_COMMAND_FISHING_2_MODE
local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256; end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536; end
-- container, slot, item id (nil: unchanged), count, flags -- as helmstorage.
local function update(id, data)
    if id == 0x020 and #data >= 17 then
        return data:byte(15), data:byte(16), u16(data, 12), u32(data, 4), data:byte(17);
    elseif id == 0x01F and #data >= 13 then
        return data:byte(11), data:byte(12), u16(data, 8), u32(data, 4), data:byte(13);
    elseif id == 0x01E and #data >= 11 then
        return data:byte(9), data:byte(10), nil, u32(data, 4), data:byte(11);
    end
end
local function item(bag, slot) return bag.items[slot] or { id = 0, count = 0, flags = 0 }; end
local function total(bag, id)
    local n = 0;
    for _, it in pairs(bag.items) do if it.id == id then n = n + it.count; end end
    return n;
end

-- Where a whole stack of `count` goes among the selected `bags` (in order):
-- a stack of the same item with room in ANY of them first (the server moves
-- only what fits), else a free slot (0x52). A move to a free slot never joins
-- a stack, so without the merge each move would take a slot of its own.
-- Returns the bag, the slot and how many units will actually move.
local function destination(bags, id, count, stack)
    for _, b in ipairs(bags) do
        for i = 1, b.bag.max do
            local other = item(b.bag, i);
            if other.id == id and other.flags == 0 and other.count > 0 and other.count < stack then
                return b, i, math.min(count, stack - other.count);
            end
        end
    end
    for _, b in ipairs(bags) do
        for i = 1, b.bag.max do
            local other = item(b.bag, i);
            if other.id == 0 or other.count == 0 then return b, 0x52, count; end
        end
    end
end

function M.new(D)
    local self = { owed = {}, status = '' };
    local capture, flight, nextAt, stopped = nil, nil, 0, false;
    local lastInventory, lastReel, holdUntil = -math.huge, -math.huge, -math.huge;
    function self.reset()
        capture, flight, nextAt, stopped = nil, nil, 0, false;
        lastInventory, lastReel, holdUntil = -math.huge, -math.huge, -math.huge;
        self.owed, self.status = {}, '';
    end
    local function enabled()
        local opts = D.options();
        return opts[7] or opts[5];
    end
    -- Caught units still in the inventory, waiting for a full stack or a pause.
    function self.waiting()
        local n = 0;
        for _, count in pairs(self.owed) do n = n + count; end
        return n;
    end

    -- A fish is always owed; trash only while its switch is on.
    local function owes(id, opts)
        local kind = D.catchKind(id);
        return kind == 'fish' or (kind == 'trash' and opts.trash == true);
    end

    local function finish()
        local after = { items = {} };
        for slot, it in pairs(capture.before.items) do after.items[slot] = it; end
        for slot, it in pairs(capture.items) do after.items[slot] = it; end
        local seen, opts = {}, D.options();
        for _, it in pairs(after.items) do
            if it.id > 0 and not seen[it.id] and owes(it.id, opts) then
                seen[it.id] = true;
                -- A move of ours that landed during the reel lowered the total.
                local gained = total(after, it.id) - total(capture.before, it.id) + (capture.movedOut[it.id] or 0);
                if gained > 0 then self.owed[it.id] = (self.owed[it.id] or 0) + gained; end
            end
        end
        capture = nil;
    end

    -- A zone line: drop what was in flight (its reply may never come) and hold
    -- moves while the inventory is sent again. The counts stay, so what was
    -- caught before the zone line still moves after it. A move in flight is
    -- taken as done: if it never landed, those units stay in the inventory.
    function self.zoned()
        if flight then
            local left = (self.owed[flight.id] or 0) - flight.count;
            self.owed[flight.id] = left > 0 and left or nil;
        end
        capture, flight = nil, nil;
        holdUntil = D.clock() + M.ZONE_S;
        if not stopped then self.status = ''; end
    end

    function self.outgoing(id, data)
        if id ~= 0x110 or #data < 15 or not enabled() or stopped then return; end
        local mode = data:byte(15);
        if mode == M.RELEASE then
            -- The catch animation is over: everything the reel brought is in.
            if capture and capture.answered then finish(); end
            return;
        end
        if mode ~= M.REEL then return; end
        -- An earlier reel answered and never released (an interruption):
        -- count it before this one.
        if capture and capture.answered then finish(); end
        lastReel = D.clock();
        capture = { before = D.bag(0), items = {}, movedOut = {}, at = lastReel, last = lastReel };
    end

    function self.incoming(id, data)
        if id == 0x00A or id == 0x00B then self.zoned(); return; end
        local now = D.clock();
        local cid, slot, iid, count, flags = update(id, data);
        if flight and cid == 0 and slot == flight.slot and count == flight.remaining
            and (iid == nil or iid == flight.id or (count == 0 and iid == 0)) then
            if capture and not flight.sourceConfirmed then
                capture.movedOut[flight.id] = (capture.movedOut[flight.id] or 0) + flight.count;
            end
            flight.sourceConfirmed = true;
        end
        if flight and cid == flight.cid then
            local old = item(flight.destItems, slot);
            local newId = iid or old.id;
            if newId == flight.id then
                if flight.toSlot == 0x52 then
                    if (old.id == 0 or old.count == 0) and count == flight.count then flight.destConfirmed = true; end
                elseif slot == flight.toSlot and old.id == flight.id and count == old.count + flight.count then
                    flight.destConfirmed = true;
                end
            end
            flight.destItems.items[slot] = { id = newId, count = count, flags = flags };
        end
        if cid == 0 and slot ~= nil and slot > 0 then
            lastInventory = now;
            if capture then
                local old = capture.items[slot] or item(capture.before, slot);
                capture.items[slot] = { id = iid or old.id, count = count, flags = flags };
                capture.last = now;
            end
        end
        if capture and id == 0x01D then
            -- One of several in a reel (see the top): wait for the quiet.
            capture.answered, capture.last = true, now;
        end
    end

    local function send(it, srcSlot, id, src)
        local opts, bags = D.options(), {};
        for _, cid in ipairs({ 7, 5 }) do
            if opts[cid] then bags[#bags + 1] = { cid = cid, bag = D.bag(cid) }; end
        end
        local dst, toSlot, moves = destination(bags, id, it.count, D.stack(id));
        if not dst then return false; end
        local amount = it.count;
        local p = { 0x29, 0x06, 0, 0, amount % 256, math.floor(amount / 256) % 256,
            math.floor(amount / 65536) % 256, math.floor(amount / 16777216) % 256,
            0, dst.cid, srcSlot, toSlot };
        if not D.send(p) then
            stopped = true;
            self.status = 'Move failed. Toggle a destination to resume.';
            return true;
        end
        flight = { id = id, cid = dst.cid, count = moves, source = total(src, id),
            dest = total(dst.bag, id), destItems = dst.bag, toSlot = toSlot,
            at = D.clock(), slot = srcSlot, remaining = it.count - moves };
        self.status = 'Moving your catch...';
        return true;
    end

    function self.tick()
        local now = D.clock();
        if capture and capture.answered
            and (now - capture.last >= M.SETTLE_S or now - capture.at >= M.CAPTURE_S) then
            finish();
        end
        if flight then
            local src, dst = D.bag(0), D.bag(flight.cid);
            if (flight.sourceConfirmed or total(src, flight.id) <= flight.source - flight.count)
                and (flight.destConfirmed or total(dst, flight.id) >= flight.dest + flight.count) then
                local left = (self.owed[flight.id] or 0) - flight.count;
                self.owed[flight.id] = left > 0 and left or nil;
                flight, nextAt = nil, now + M.GAP_S;
                self.status = 'Catch moved.';
            elseif now - flight.at >= M.CONFIRM_S then
                -- A late reply must never cause a second move of the same item.
                flight, capture, stopped = nil, nil, true;
                self.owed = {};
                self.status = 'Move not confirmed. Toggle a destination to resume.';
            end
            return;
        end
        if not enabled() then self.reset(); return; end
        if stopped then return; end
        if capture then
            -- Never answered (no bite, an interrupted fight): nothing counts.
            if now - capture.at >= M.CAPTURE_S then capture = nil; end
            return;
        end
        -- Nothing owed, nothing to move: the bag walk below only serves
        -- self.owed (the 2026-10-13 stutter rule).
        if next(self.owed) == nil then return; end
        if now < nextAt or now < holdUntil or now - lastInventory < M.QUIET_S or not D.ready() then return; end
        local src, opts = D.bag(0), D.options();
        local flush = now - lastReel >= M.FLUSH_S;
        local ids = {};
        for id, owed in pairs(self.owed) do
            -- Units used or moved by hand are no longer ours to move, nor is
            -- trash once its switch is off.
            local held = owes(id, opts) and total(src, id) or 0;
            if held < owed then owed = held; self.owed[id] = held > 0 and held or nil; end
            if owed > 0 then ids[#ids + 1] = id; end
        end
        table.sort(ids);
        local blocked = false;
        for _, id in ipairs(ids) do
            local owed, stack = self.owed[id], D.stack(id);
            for slot = 1, src.max do
                local it = item(src, slot);
                if it.id == id and it.flags == 0 and it.count > 0 and it.count <= owed
                    and (flush or it.count >= stack) and not D.equipped(slot) then
                    if send(it, slot, id, src) then return; end
                    blocked = true;
                    break;
                end
            end
        end
        if blocked then
            self.status = 'Selected bags are full or unavailable; waiting for space.';
            nextAt = now + 1;
        end
    end

    -- A switch changed: resume after a stop; with no destination left, forget
    -- the counts; with trash switched off, forget the trash (an outstanding
    -- move still confirms).
    function self.changed()
        capture, stopped = nil, false;
        if not enabled() then
            self.owed = {};
        else
            local opts = D.options();
            for id in pairs(self.owed) do
                if not owes(id, opts) then self.owed[id] = nil; end
            end
        end
        if not flight then self.status = ''; end
    end
    return self;
end

local function inv() return AshitaCore:GetMemoryManager():GetInventory(); end
local function bag(cid)
    local inventory = inv();
    local out = { max = inventory:GetContainerCountMax(cid) or 0, items = {} };
    for slot = 1, out.max do
        local it = inventory:GetContainerItem(cid, slot);
        if it and it.Id ~= 0 then
            out.items[slot] = { id = it.Id, count = it.Count, flags = it.Flags or 0 };
        end
    end
    return out;
end
-- Only a pack whose server supports it (AscensionXI's fishing module) arms
-- this; anywhere else the mover never sees a destination.
local function options()
    local svc = require('dlac\\gear\\serverpack').service('fishing');
    if svc == nil or svc.moveCatches ~= true then return {}; end
    local fw = require('dlac\\feature\\fishwatch');
    fw.loadState();
    return { [7] = fw.moveCase == true, [5] = fw.moveSatchel == true, trash = fw.moveTrash == true };
end
-- What a line can bring up, by kind: 'fish', or 'trash' for a row the server
-- flags as not a fish (fishdb `item`); nil for anything else, bait included --
-- the next cast needs it.
local function catchKind(id)
    local db = require('dlac\\feature\\fishcalc').db();
    local f = (db ~= nil and db.fish ~= nil) and db.fish[id] or nil;
    if f == nil or (db.baits or {})[id] ~= nil then return nil; end
    return (f.item or 0) ~= 0 and 'trash' or 'fish';
end
M._options, M._catchKind = options, catchKind;   -- test seams (the live wiring)
M.live = M.new({
    clock = os.clock, options = options, bag = bag, catchKind = catchKind,
    ready = function()
        local mm = AshitaCore:GetMemoryManager();
        local index = mm:GetParty():GetMemberTargetIndex(0);
        -- Counts outlive a zone line, so a load longer than ZONE_S must still
        -- hold moves (the helmwatch/jobhelpers zoning probe).
        local pl = mm:GetPlayer();
        local z = pl and pl.GetIsZoning and pl:GetIsZoning();
        if z == true or (type(z) == 'number' and z ~= 0) then return false; end
        return index ~= nil and index > 0 and mm:GetPlayer():GetMainJob() > 0
            and mm:GetEntity():GetStatus(index) ~= 4;
    end,
    equipped = function(slot)
        for i = 0, 15 do
            local eq = inv():GetEquippedItem(i);
            if eq and eq.Index == slot then return true; end
        end
        return false;
    end,
    stack = function(id)
        local rec = AshitaCore:GetResourceManager():GetItemById(id);
        return rec and tonumber(rec.StackSize) or 1;
    end,
    send = function(packet)
        return pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0x029, packet); end);
    end,
});

if ashita and ashita.events then
    local lastDir;
    local function currentCharacter()
        local dir = require('dlac\\lib\\statefile').charDir();
        if dir ~= lastDir then M.live.reset(); lastDir = dir; end
        return dir ~= nil;
    end
    local function packetData(e)
        return type(e.data_modified) == 'string' and #e.data_modified > 0 and e.data_modified or e.data;
    end
    ashita.events.register('packet_out', 'dlac-fishstorage-out', function(e)
        if e.blocked or e.id ~= 0x110 then return; end
        pcall(function() if currentCharacter() then M.live.outgoing(e.id, packetData(e)); end end);
    end);
    ashita.events.register('packet_in', 'dlac-fishstorage-in', function(e)
        if e.blocked then return; end
        if e.id ~= 0x00A and e.id ~= 0x00B and e.id ~= 0x01D
            and e.id ~= 0x01E and e.id ~= 0x01F and e.id ~= 0x020 then return; end
        pcall(function() if currentCharacter() then M.live.incoming(e.id, packetData(e)); end end);
    end);
    local at = 0;
    ashita.events.register('d3d_present', 'dlac-fishstorage-tick', function()
        if os.clock() < at then return; end
        at = os.clock() + 0.1;
        pcall(function() if currentCharacter() then M.live.tick(); end end);
    end);
end
return M;
