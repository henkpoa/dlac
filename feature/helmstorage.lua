-- Gathered-item transfers. The 0x029 move and live preflight follow the
-- private hidden-features:gearmove.lua implementation, without its storage UI.
-- AscensionXI HELM sends our motion (0x05A), the rewards, then ITEM_SAME.
-- Observe only that response to our tool trade; never sweep old inventory.
local M = {};
-- The native inventory sort can arrive ~550ms after a HELM reward (live
-- 2026-09-28). Wait for a full second without inventory changes before
-- choosing source slots; the server may otherwise stack one away mid-move.
M.SETTLE_S = 1;
local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256; end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536; end
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

function M.new(D)
    local self = { queue = {}, status = '' };
    local trade, capture, flight, nextAt, stopped = nil, nil, nil, 0, false;
    function self.reset()
        trade, capture, flight, nextAt, stopped = nil, nil, nil, 0, false;
        self.queue, self.status = {}, '';
    end
    local function enabled()
        local opts = D.options();
        return opts[7] or opts[5];
    end
    local function finish()
        if not capture then return; end
        if not capture.complete then capture = nil; return; end
        local after = { items = {} };
        for slot, it in pairs(capture.before.items) do after.items[slot] = it; end
        for slot, it in pairs(capture.items) do after.items[slot] = it; end
        -- Sorting can combine OLD stacks too. Only the net increase for an
        -- item id is a gathering reward, regardless of which slots now hold it.
        local remaining = {};
        for _, it in pairs(after.items) do
            if it.id > 0 and remaining[it.id] == nil then
                remaining[it.id] = math.max(0, total(after, it.id) - total(capture.before, it.id));
            end
        end
        for slot = 1, capture.before.max do
            local it, before = item(after, slot), item(capture.before, slot);
            local gained = math.min(it.count, remaining[it.id] or 0);
            if gained > 0 and it.id > 0 and it.flags == 0 then
                remaining[it.id] = remaining[it.id] - gained;
                local merged = false;
                for _, q in ipairs(self.queue) do
                    if q.slot == slot and q.id == it.id and q.expected == before.count then
                        q.count, q.expected = q.count + gained, it.count;
                        merged = true; break;
                    end
                end
                if not merged then
                    self.queue[#self.queue + 1] = { slot = slot, id = it.id, count = gained, expected = it.count };
                end
            end
        end
        capture, trade = nil, nil;
    end
    function self.outgoing(id, data)
        if id ~= 0x036 or #data < 64 or not enabled() or stopped then return; end
        finish();
        trade = nil;
        if not D.isPoint(u16(data, 0x3A)) then return; end
        trade = { target = u32(data, 4), at = D.clock() };
    end
    function self.incoming(id, data)
        if id == 0x00A or id == 0x00B then self.reset(); return; end
        local cid, slot, iid, count, flags = update(id, data);
        if flight and cid == 0 and slot == flight.slot and count == flight.remaining
            and (iid == nil or iid == flight.id or (count == 0 and iid == 0)) then
            flight.sourceConfirmed = true;
        end
        if flight and cid == flight.cid then
            local old = item(flight.destItems, slot);
            local newId = iid or old.id;
            -- Confirm the actual deposit, not a container-wide total: the
            -- player can withdraw another stack while this move is pending.
            -- A split/free-slot move creates a new stack; an explicit merge
            -- updates precisely the destination slot selected when sending.
            if newId == flight.id then
                if flight.toSlot == 0x52 then
                    if (old.id == 0 or old.count == 0) and count == flight.count then
                        flight.destConfirmed = true;
                    end
                elseif slot == flight.toSlot and old.id == flight.id and count == old.count + flight.count then
                    flight.destConfirmed = true;
                end
            end
            flight.destItems.items[slot] = { id = newId, count = count, flags = flags };
        end
        if not enabled() or stopped then return; end
        local now = D.clock();
        if id == 0x05A and #data >= 18 and trade and now - trade.at < 5
            and u32(data, 4) == D.playerId() and u32(data, 8) == trade.target
            and u16(data, 16) >= 40 and u16(data, 16) <= 42 then
            capture = { before = D.bag(0), items = {}, at = now, last = now };
            return;
        end
        if not capture then return; end
        if id == 0x01D then capture.complete = true; capture.last = now; return; end
        if cid == 0 and slot > 0 then
            local old = capture.items[slot] or item(capture.before, slot);
            capture.items[slot] = { id = iid or old.id, count = count, flags = flags };
            capture.last = now;
        end
    end
    function self.tick()
        local now = D.clock();
        if flight then
            local src, dst = D.bag(0), D.bag(flight.cid);
            if (flight.sourceConfirmed or total(src, flight.id) <= flight.source - flight.count)
                and (flight.destConfirmed or total(dst, flight.id) >= flight.dest + flight.count) then
                local q = self.queue[1];
                if q then
                    q.count, q.expected = q.count - flight.count, q.expected - flight.count;
                    if q.count <= 0 then table.remove(self.queue, 1); end
                end
                flight, nextAt = nil, now + 0.35;
                self.status = 'Gathered items moved.';
            elseif now - flight.at >= 5 then
                -- A late reply must never cause a second move of the same item.
                flight, capture, trade, stopped = nil, nil, nil, true;
                self.queue = {};
                self.status = 'Move not confirmed. Toggle a destination to resume.';
            end
            return;
        end
        if not enabled() then self.reset(); return; end
        if stopped then return; end
        if capture then
            if capture.complete and now - capture.last >= M.SETTLE_S then finish();
            elseif now - capture.at >= 5 then capture, trade = nil, nil; end
            return;
        end
        if trade and now - trade.at >= 5 then trade = nil; end
        if trade or now < nextAt or #self.queue == 0 or not D.ready() then return; end
        local q, src = self.queue[1], D.bag(0);
        local it = item(src, q.slot);
        if it.id ~= q.id or it.count ~= q.expected then
            table.remove(self.queue, 1);
            self.status = 'Inventory changed; gathered items left in Inventory.';
            return;
        end
        if it.flags ~= 0 or D.equipped(q.slot) then return; end
        local opts = D.options();
        for _, cid in ipairs({ 7, 5 }) do
            if opts[cid] then
                local dst = D.bag(cid);
                local slot, count, free = nil, 0, false;
                for i = 1, dst.max do
                    local other = item(dst, i);
                    if other.id == 0 or other.count == 0 then free = true;
                    elseif q.count == it.count and other.id == q.id and other.flags == 0
                        and other.count < D.stack(q.id) then
                        slot, count = i, math.min(q.count, D.stack(q.id) - other.count);
                    end
                end
                if not slot and free then slot, count = 0x52, q.count; end
                if slot and count > 0 then
                    -- Whole-stack moves can merge; the server clamps to the
                    -- destination's room. Partial moves require a free slot.
                    local amount = slot == 0x52 and count or it.count;
                    local p = { 0x29, 0x06, 0, 0, amount % 256, math.floor(amount / 256) % 256,
                        math.floor(amount / 65536) % 256, math.floor(amount / 16777216) % 256,
                        0, cid, q.slot, slot };
                    if D.send(p) then
                        flight = { id = q.id, cid = cid, count = count, source = total(src, q.id),
                            dest = total(dst, q.id), destItems = dst, toSlot = slot,
                            at = now, slot = q.slot, remaining = it.count - count };
                        self.status = 'Moving gathered items...';
                    else
                        stopped = true;
                        self.status = 'Move failed. Toggle a destination to resume.';
                    end
                    return;
                end
            end
        end
        self.status = 'Selected bags are full or unavailable; waiting for space.';
        nextAt = now + 1;
    end
    -- Selecting another destination can release items waiting for space.
    -- Disabling both cancels unsent work, retaining any outstanding move.
    function self.changed()
        trade, capture, stopped = nil, nil, false;
        if not enabled() then
            self.queue = flight and { self.queue[1] } or {};
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
local function options()
    local hw = require('dlac\\feature\\helmwatch');
    hw.loadState();
    return { [7] = hw.moveCase == true, [5] = hw.moveSatchel == true };
end
M.live = M.new({
    clock = os.clock, options = options, bag = bag,
    isPoint = function(index)
        return require('dlac\\feature\\helmwatch').gatherFromNpcName(
            AshitaCore:GetMemoryManager():GetEntity():GetName(index)) ~= nil;
    end,
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
    ashita.events.register('packet_out', 'dlac-helmstorage-out', function(e)
        if e.blocked or e.id ~= 0x036 then return; end
        pcall(function() if currentCharacter() then M.live.outgoing(e.id, packetData(e)); end end);
    end);
    ashita.events.register('packet_in', 'dlac-helmstorage-in', function(e)
        if e.blocked then return; end
        if e.id ~= 0x00A and e.id ~= 0x00B and e.id ~= 0x05A and e.id ~= 0x01D
            and e.id ~= 0x01E and e.id ~= 0x01F and e.id ~= 0x020 then return; end
        pcall(function() if currentCharacter() then M.live.incoming(e.id, packetData(e)); end end);
    end);
    local at = 0;
    ashita.events.register('d3d_present', 'dlac-helmstorage-tick', function()
        if os.clock() < at then return; end
        at = os.clock() + 0.1;
        pcall(function() if currentCharacter() then M.live.tick(); end end);
    end);
end
return M;
