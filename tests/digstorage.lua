-- lua tests/digstorage.lua
local storage = dofile('feature/digstorage.lua');
local function p16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function p32(n) return p16(n % 65536) .. p16(math.floor(n / 65536)); end
local function action(kind)
    return string.rep('\0', 4) .. p32(99) .. p16(5) .. p16(kind or storage.DIG_ACTION) .. string.rep('\0', 16);
end
local function digAnimation(player) return string.rep('\0', 4) .. p32(player or 99) .. p16(5) .. '\0\0'; end
local function attr(slot, id, count, cid, flags)
    return string.rep('\0', 4) .. p32(count) .. p32(0) .. p16(id) .. string.char(cid or 0, slot, flags or 0);
end
local STACK = { [100] = 12, [101] = 12, [300] = 1, [4096] = 12 };
local function harness()
    local H = { time = 10, sent = {}, opts = { [7] = true, [5] = true }, ready = true, worn = {}, refuse = false,
        bags = { [0] = { max = 8, items = {} }, [7] = { max = 2, items = {} }, [5] = { max = 2, items = {} } } };
    local function snapshot(cid)
        local b, out = H.bags[cid], { max = H.bags[cid].max, items = {} };
        for k, it in pairs(b.items) do out.items[k] = { id = it.id, count = it.count, flags = it.flags }; end
        return out;
    end
    H.m = storage.new({ clock = function() return H.time; end,
        options = function() return H.opts; end, bag = snapshot,
        playerId = function() return 99; end,
        ready = function() return H.ready; end, equipped = function(slot) return H.worn[slot] == true; end,
        stack = function(id) return STACK[id] or 12; end,
        send = function(p) if H.refuse then return false; end H.sent[#H.sent + 1] = p; return true; end });
    function H.put(cid, slot, id, n, flags)
        H.bags[cid].items[slot] = (n > 0) and { id = id, count = n, flags = flags or 0 } or nil;
    end
    function H.land(slot, id, n, cid)
        H.m.incoming(0x020, attr(slot, n > 0 and id or 0, n, cid));
        H.put(cid or 0, slot, id, n);
    end
    -- One answered dig: the item updates, ITEM_SAME, then our dig animation.
    function H.dig(rewards, who)
        H.m.outgoing(0x01A, action());
        for _, r in ipairs(rewards or {}) do H.land(r[1], r[2], r[3]); end
        H.m.incoming(0x01D, '');
        H.m.incoming(0x02F, digAnimation(who));
    end
    function H.tick(dt) H.time = H.time + (dt or 0.4); H.m.tick(); end
    function H.pause() H.tick(storage.FLUSH_S + 0.1); end
    -- The server's answer to the last move: source emptied (or left), destination filled.
    function H.confirm(left, destSlot, count)
        local p = H.sent[#H.sent];
        local src, cid = p[11], p[10];
        local id = H.bags[0].items[src].id;
        H.land(src, id, left);
        H.land(destSlot, id, count, cid);
        H.tick();
    end
    return H;
end

-- Nothing counts without our own answered dig.
local h = harness();
h.land(1, 300, 1); h.m.incoming(0x01D, ''); h.pause(); assert(#h.sent == 0, 'a reward with no dig');
h.m.outgoing(0x01A, action(0x04)); h.land(2, 300, 1); h.m.incoming(0x01D, ''); h.m.incoming(0x02F, digAnimation());
h.pause(); assert(#h.sent == 0, 'another action is not a dig');
h.dig({ { 3, 300, 1 } }, 100); h.pause(); h.pause(); assert(#h.sent == 0, 'another player dug');
h = harness(); h.m.outgoing(0x01A, action()); h.land(1, 300, 1); h.m.incoming(0x01D, '');
h.tick(storage.CAPTURE_S + 0.1); h.pause(); assert(#h.sent == 0, 'a dig never answered counts nothing');
h = harness(); h.m.outgoing(0x01A, action()); h.tick(storage.CAPTURE_S + 0.1);
h.land(1, 300, 1); h.m.incoming(0x01D, ''); h.pause(); assert(#h.sent == 0, 'a refused dig counts nothing');
h.dig({ { 2, 300, 1 } }); h.tick(); h.confirm(0, 1, 1); h.pause();
assert(#h.sent == 1 and h.m.waiting() == 0, 'the next dig counts only its own find, not what arrived since');
h = harness(); h.opts = {}; h.dig({ { 1, 300, 1 } }); h.pause(); assert(#h.sent == 0, 'no destination selected');

-- An item that does not stack moves at once, one packet.
h = harness(); h.dig({ { 1, 300, 1 } }); h.tick();
assert(#h.sent == 1 and h.sent[1][5] == 1 and h.sent[1][10] == 7 and h.sent[1][11] == 1 and h.sent[1][12] == 0x52);

-- Stackable digs wait for a full stack, then move it whole: 12 digs, one packet.
h = harness();
for n = 1, 11 do h.dig({ { 1, 100, n } }); h.tick(1); end
assert(#h.sent == 0, 'a partial stack waits while digging continues');
h.dig({ { 1, 100, 12 } }); h.tick();
assert(#h.sent == 1 and h.sent[1][5] == 12, 'the full stack moves in one packet');
h.confirm(0, 1, 12); assert(h.m.waiting() == 0);

-- Dug Gysahl Greens stay for the next dig.
h = harness(); h.dig({ { 1, 4545, 1 }, { 2, 300, 1 } }); h.pause();
assert(#h.sent == 1 and h.sent[1][11] == 2 and h.m.waiting() == 1, 'greens are never counted');

-- Three items per dig (Regular, Burrow, Bore) all count.
h = harness(); h.dig({ { 1, 100, 1 }, { 2, 101, 1 }, { 3, 300, 1 } }); h.tick();
assert(#h.sent == 1 and h.sent[1][11] == 3, 'the non-stacking item first');
h.confirm(0, 1, 1); assert(h.m.waiting() == 2);
h.pause(); assert(#h.sent == 2 and h.sent[2][11] == 1 and h.sent[2][5] == 1, 'partial stacks move after a pause');
h.confirm(0, 2, 1); h.tick(); assert(#h.sent == 3 and h.sent[3][11] == 2 and h.sent[3][10] == 5,
    'the Case is full, so the Satchel');

-- Stock carried in is never moved: 5 in hand plus 7 dug makes a full stack of 12,
-- but only 7 of them are ours.
h = harness(); h.put(0, 1, 100, 5);
h.dig({ { 1, 100, 12 } }); h.pause(); assert(#h.sent == 0, 'a mixed stack stays');
h.dig({ { 2, 100, 3 } }); h.pause();
assert(#h.sent == 1 and h.sent[1][11] == 2 and h.sent[1][5] == 3, 'the dug-only stack moves');
h.confirm(0, 1, 3); h.pause(); assert(#h.sent == 1 and h.m.waiting() == 7);

-- Sorting during a dig moves units between slots without changing what counts.
h = harness(); h.put(0, 1, 100, 6); h.put(0, 4, 100, 6);
h.m.outgoing(0x01A, action());
h.land(4, 100, 7); h.land(1, 100, 12); h.land(4, 100, 1);
h.m.incoming(0x01D, ''); h.m.incoming(0x02F, digAnimation());
assert(h.m.waiting() == 1, 'sorting is not digging');

-- Our move landing in the middle of the next dig does not hide that dig's reward.
h = harness(); for n = 1, 12 do h.dig({ { 1, 100, n } }); end h.tick();
assert(#h.sent == 1);
h.m.outgoing(0x01A, action());
h.land(1, 100, 0); h.land(1, 100, 12, 7);           -- the move: source emptied, Case filled
h.land(2, 100, 1);                                  -- the new dig's reward
h.m.incoming(0x01D, ''); h.m.incoming(0x02F, digAnimation()); h.tick();
assert(h.m.waiting() == 1, 'the in-flight move is added back, the new unit counted');

-- Whole stacks merge into a destination stack with room; the rest waits.
h = harness(); h.put(7, 1, 100, 9);
for n = 1, 12 do h.dig({ { 1, 100, n } }); end h.tick();
assert(h.sent[1][12] == 1 and h.sent[1][5] == 12, 'the whole stack is offered to the Case stack');
h.confirm(9, 1, 12); assert(h.m.waiting() == 9);

-- Units used or moved by hand are dropped from the count.
h = harness(); for n = 1, 5 do h.dig({ { 1, 100, n } }); end
h.put(0, 1, 100, 2); h.pause();
assert(#h.sent == 1 and h.sent[1][5] == 2 and h.m.waiting() == 2);

-- No room anywhere: wait, and resume when room appears.
h = harness(); h.opts[5] = false; h.put(7, 1, 200, 12); h.put(7, 2, 201, 12);
h.dig({ { 1, 300, 1 } }); h.tick(); assert(#h.sent == 0 and h.m.status:find('waiting', 1, true));
h.put(7, 2, 0, 0); h.tick(1.1); assert(#h.sent == 1);

-- A move the server never confirms stops the mover; toggling resumes it.
h = harness(); h.dig({ { 1, 300, 1 } }); h.tick(); h.tick(storage.CONFIRM_S + 0.1); h.tick(10);
assert(#h.sent == 1 and h.m.status:find('not confirmed', 1, true) and h.m.waiting() == 0);
h.dig({ { 2, 300, 1 } }); h.tick(); assert(#h.sent == 1, 'stopped: digs are not tracked');
h.m.changed(); h.dig({ { 3, 300, 1 } }); h.tick();
assert(#h.sent == 2 and h.sent[2][5] == 1, 'resumed: one unit, the one dug since');
h.confirm(0, 1, 1); h.pause();
assert(#h.sent == 2 and h.m.waiting() == 0, 'what was dug while stopped is never moved');

-- A refused send stops the mover until a switch changes.
h = harness(); h.refuse = true; h.dig({ { 1, 300, 1 } }); h.tick();
assert(#h.sent == 0 and h.m.status:find('Move failed', 1, true), 'a refused send stops');
h.refuse = false; h.tick(); assert(#h.sent == 0, 'stopped until a switch changes');
h.m.changed(); h.tick(); assert(#h.sent == 1, 'resumed');

-- Moves wait for the inventory to settle, for the player to be ready, and
-- never take an equipped item.
h = harness(); h.dig({ { 1, 300, 1 } }); h.tick(storage.QUIET_S / 2);
assert(#h.sent == 0, 'the inventory is still changing');
h.tick(storage.QUIET_S); assert(#h.sent == 1);
h = harness(); h.ready = false; h.dig({ { 1, 300, 1 } }); h.tick(); assert(#h.sent == 0, 'not ready');
h.ready = true; h.tick(); assert(#h.sent == 1);
h = harness(); h.dig({ { 1, 300, 1 } }); h.worn[1] = true; h.tick(); assert(#h.sent == 0, 'an equipped item stays');
h.worn[1] = nil; h.tick(); assert(#h.sent == 1);

-- Switching both destinations off forgets the counts.
h = harness(); h.dig({ { 1, 100, 1 } }); h.opts = {}; h.m.changed(); h.opts = { [7] = true }; h.pause();
assert(#h.sent == 0);

-- The counts survive a zone line; nothing moves until the zone has settled.
h = harness(); h.dig({ { 1, 100, 5 } }); h.tick(); assert(h.m.waiting() == 5);
h.m.incoming(0x00B, ''); h.tick(storage.ZONE_S - 0.2); h.m.incoming(0x00A, '');
h.tick(storage.ZONE_S - 0.2); assert(#h.sent == 0, 'nothing moves while the zone settles');
h.tick(0.3); assert(#h.sent == 1 and h.sent[1][5] == 5, 'what was dug before the zone line still moves');

-- A move cut off by a zone line counts as done, so carried stock never takes
-- its place: here it landed, and only the carried 5 are left.
h = harness(); h.put(0, 2, 100, 5); h.dig({ { 1, 100, 12 } }); h.tick(); assert(#h.sent == 1);
h.m.incoming(0x00B, ''); h.put(0, 1, 100, 0); h.put(7, 1, 100, 12); h.m.incoming(0x00A, '');
h.tick(storage.ZONE_S + 0.1); h.pause();
assert(#h.sent == 1 and h.m.waiting() == 0, 'the carried stack stays');

-- The server sends ITEM_SAME after every item it adds; our dig animation
-- comes last, so all three finds count.
h = harness(); h.m.outgoing(0x01A, action());
for slot, id in ipairs({ 100, 101, 102 }) do h.land(slot, id, 1); h.m.incoming(0x01D, ''); end
h.m.incoming(0x02F, digAnimation()); assert(h.m.waiting() == 3, 'every find of one dig');

-- Single units moved one by one stack in the Case: a move to a free slot never
-- joins a stack server-side, so the mover aims each at the Case stack itself.
h = harness(); h.dig({ { 1, 100, 1 } }); h.dig({ { 2, 100, 1 } }); h.pause();
assert(#h.sent == 1 and h.sent[1][12] == 0x52, 'the first unit opens a Case stack');
h.confirm(0, 1, 1); h.tick(1.1);
assert(#h.sent == 2 and h.sent[2][11] == 2 and h.sent[2][10] == 7 and h.sent[2][12] == 1,
    'the second unit joins it instead of taking a slot of its own');

-- A stack with room in the Satchel comes before a free slot in the Case.
h = harness(); h.put(5, 1, 100, 4); for n = 1, 12 do h.dig({ { 1, 100, n } }); end h.tick();
assert(h.sent[1][10] == 5 and h.sent[1][12] == 1 and h.sent[1][5] == 12, 'the Satchel stack with room first');

-- Locked stacks are left alone; truncated packets are ignored.
h = harness(); h.m.outgoing(0x01A, action()); h.m.incoming(0x020, attr(1, 300, 1, 0, 5)); h.put(0, 1, 300, 1, 5);
h.m.incoming(0x01D, ''); h.m.incoming(0x02F, digAnimation()); h.tick(); assert(#h.sent == 0);
for _, id in ipairs({ 0x020, 0x01F, 0x01E, 0x02F, 0x01A }) do h.m.incoming(id, ''); h.m.outgoing(id, ''); end
print('OK -- dig counts, whole-stack moves, pauses, carried stock, sorting, merges and cancellation');
