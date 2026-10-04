-- Dug-item transfers into the Mog Case / Mog Satchel (AscensionXI digging,
-- docs/reference/ascensionxi-digging.md).
--
-- HELM's mover (helmstorage.lua) moves every reward as it lands. Digging is
-- too fast for that: a dig a second, up to three items each with Burrow and
-- Bore. So this one keeps a count per item of what digging added and moves
-- WHOLE stacks only -- a full stack, or an item that does not stack. Partial
-- stacks wait until digging pauses (FLUSH_S). It never moves more of an item
-- than digs added, so stock you carried in stays where it was.
--
-- A dig is our outgoing 0x01A (action 0x11). Its rewards are counted as the
-- net change in each item's inventory total -- sorting moves units between
-- slots but never changes a total -- and only once the server has answered
-- that dig with ITEM_SAME (0x01D) and our own dig animation (0x02F). A refused
-- dig gets neither and counts nothing. Inventory sorting merges partial
-- stacks only, so a full stack's slot cannot change under a move.
local M = { QUIET_S = 0.3, FLUSH_S = 6, CAPTURE_S = 3, CONFIRM_S = 5, GAP_S = 0.2 };
M.DIG_ACTION = 0x11;
-- Gysahl Greens can be dug, and the next dig needs them in the inventory:
-- they stay, whatever the switches say.
M.KEEP = { [4545] = true };
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

-- Where a whole stack of `count` goes in `dst`: a stack of the same item with
-- room (the server moves only what fits), else any free slot (0x52).
-- Returns the slot and how many units will actually move.
local function destination(dst, id, count, stack)
    local free = false;
    for i = 1, dst.max do
        local other = item(dst, i);
        if other.id == 0 or other.count == 0 then
            free = true;
        elseif other.id == id and other.flags == 0 and other.count < stack then
            return i, math.min(count, stack - other.count);
        end
    end
    if free then return 0x52, count; end
end

function M.new(D)
    local self = { owed = {}, status = '' };
    local capture, flight, nextAt, stopped = nil, nil, 0, false;
    local lastInventory, lastDig = -math.huge, -math.huge;
    function self.reset()
        capture, flight, nextAt, stopped = nil, nil, 0, false;
        self.owed, self.status = {}, '';
    end
    local function enabled()
        local opts = D.options();
        return opts[7] or opts[5];
    end
    -- Dug units still in the inventory, waiting for a full stack or a pause.
    function self.waiting()
        local n = 0;
        for _, count in pairs(self.owed) do n = n + count; end
        return n;
    end

    local function finish()
        local after = { items = {} };
        for slot, it in pairs(capture.before.items) do after.items[slot] = it; end
        for slot, it in pairs(capture.items) do after.items[slot] = it; end
        local seen = {};
        for _, it in pairs(after.items) do
            if it.id > 0 and not seen[it.id] and not M.KEEP[it.id] then
                seen[it.id] = true;
                -- A move of ours that landed during the dig lowered the total.
                local gained = total(after, it.id) - total(capture.before, it.id) + (capture.movedOut[it.id] or 0);
                if gained > 0 then self.owed[it.id] = (self.owed[it.id] or 0) + gained; end
            end
        end
        capture = nil;
    end

    function self.outgoing(id, data)
        if id ~= 0x01A or #data < 12 or u16(data, 10) ~= M.DIG_ACTION then return; end
        if not enabled() or stopped then return; end
        lastDig = D.clock();
        if capture then
            -- An earlier dig not answered yet: keep its snapshot, wait for this one.
            capture.at, capture.itemSame, capture.dug = lastDig, false, false;
            return;
        end
        capture = { before = D.bag(0), items = {}, movedOut = {}, at = lastDig };
    end

    function self.incoming(id, data)
        if id == 0x00A or id == 0x00B then self.reset(); return; end
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
            end
        end
        if capture == nil then return; end
        if id == 0x01D then
            capture.itemSame = true;
        elseif id == 0x02F and #data >= 8 and u32(data, 4) == D.playerId() then
            capture.dug = true;
        end
        if capture.itemSame and capture.dug then finish(); end
    end

    local function send(it, srcSlot, id, src)
        local opts = D.options();
        for _, cid in ipairs({ 7, 5 }) do
            if opts[cid] then
                local dst = D.bag(cid);
                local toSlot, moves = destination(dst, id, it.count, D.stack(id));
                if toSlot then
                    local amount = it.count;
                    local p = { 0x29, 0x06, 0, 0, amount % 256, math.floor(amount / 256) % 256,
                        math.floor(amount / 65536) % 256, math.floor(amount / 16777216) % 256,
                        0, cid, srcSlot, toSlot };
                    if not D.send(p) then
                        stopped = true;
                        self.status = 'Move failed. Toggle a destination to resume.';
                        return true;
                    end
                    flight = { id = id, cid = cid, count = moves, source = total(src, id),
                        dest = total(dst, id), destItems = dst, toSlot = toSlot,
                        at = D.clock(), slot = srcSlot, remaining = it.count - moves };
                    self.status = 'Moving dug items...';
                    return true;
                end
            end
        end
        return false;
    end

    function self.tick()
        local now = D.clock();
        if flight then
            local src, dst = D.bag(0), D.bag(flight.cid);
            if (flight.sourceConfirmed or total(src, flight.id) <= flight.source - flight.count)
                and (flight.destConfirmed or total(dst, flight.id) >= flight.dest + flight.count) then
                local left = (self.owed[flight.id] or 0) - flight.count;
                self.owed[flight.id] = left > 0 and left or nil;
                flight, nextAt = nil, now + M.GAP_S;
                self.status = 'Dug items moved.';
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
            -- Refused or unanswered: nothing from it is counted.
            if now - capture.at >= M.CAPTURE_S then capture = nil; end
            return;
        end
        if now < nextAt or now - lastInventory < M.QUIET_S or not D.ready() then return; end
        local src = D.bag(0);
        local flush = now - lastDig >= M.FLUSH_S;
        local ids = {};
        for id, owed in pairs(self.owed) do
            -- Units used or moved by hand are no longer ours to move.
            local held = total(src, id);
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

    -- A destination switched on or off: resume after a stop; with none left,
    -- forget the counts (an outstanding move still confirms).
    function self.changed()
        capture, stopped = nil, false;
        if not enabled() then self.owed = {}; end
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
-- Only a pack whose server supports it (AscensionXI's digging module) arms
-- this; anywhere else the mover never sees a destination.
local function options()
    if require('dlac\\gear\\serverpack').service('digging') == nil then return {}; end
    local cw = require('dlac\\feature\\chocowatch');
    cw.loadState();
    return { [7] = cw.moveCase == true, [5] = cw.moveSatchel == true };
end
M.live = M.new({
    clock = os.clock, options = options, bag = bag,
    playerId = function() return AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0); end,
    ready = function()
        local mm = AshitaCore:GetMemoryManager();
        local index = mm:GetParty():GetMemberTargetIndex(0);
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
    ashita.events.register('packet_out', 'dlac-digstorage-out', function(e)
        if e.blocked or e.id ~= 0x01A then return; end
        pcall(function() if currentCharacter() then M.live.outgoing(e.id, packetData(e)); end end);
    end);
    ashita.events.register('packet_in', 'dlac-digstorage-in', function(e)
        if e.blocked then return; end
        if e.id ~= 0x00A and e.id ~= 0x00B and e.id ~= 0x01D and e.id ~= 0x01E
            and e.id ~= 0x01F and e.id ~= 0x020 and e.id ~= 0x02F then return; end
        pcall(function() if currentCharacter() then M.live.incoming(e.id, packetData(e)); end end);
    end);
    local at = 0;
    ashita.events.register('d3d_present', 'dlac-digstorage-tick', function()
        if os.clock() < at then return; end
        at = os.clock() + 0.1;
        pcall(function() if currentCharacter() then M.live.tick(); end end);
    end);
end
return M;
