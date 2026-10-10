-- lua tests/helmstorage.lua
local storage = dofile('feature/helmstorage.lua');
local function p16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function p32(n) return p16(n % 65536) .. p16(math.floor(n / 65536)); end
local function trade(index)
    return string.rep('\0', 4) .. p32(1234) .. string.rep('\0', 50) .. p16(index or 12) .. string.rep('\0', 4);
end
local function motion(player)
    return string.rep('\0', 4) .. p32(player or 99) .. p32(1234) .. p16(1) .. p16(12) .. p16(41);
end
local function attr(slot, id, count, cid, flags)
    return string.rep('\0', 4) .. p32(count) .. p32(0) .. p16(id) .. string.char(cid or 0, slot, flags or 0);
end
local function harness()
    local H = { time = 0, sent = {}, opts = { [7] = true, [5] = true }, ready = true,
        bags = { [0] = { max = 4, items = {} }, [7] = { max = 2, items = {} }, [5] = { max = 2, items = {} } } };
    local function snapshot(cid)
        local b, out = H.bags[cid], { max = H.bags[cid].max, items = {} };
        for k, it in pairs(b.items) do out.items[k] = { id = it.id, count = it.count, flags = it.flags }; end
        return out;
    end
    H.m = storage.new({ clock = function() return H.time; end,
        options = function() return H.opts; end, bag = snapshot,
        playerId = function() return 99; end, isPoint = function(i) return i == 12; end,
        ready = function() return H.ready; end, equipped = function() return H.worn == true; end,
        stack = function(id) return id == 300 and 1 or 12; end,
        send = function(p) H.sent[#H.sent + 1] = p; return true; end });
    function H.put(cid, slot, id, n, flags)
        H.bags[cid].items[slot] = { id = id, count = n, flags = flags or 0 };
    end
    -- An inventory update with no ITEM_SAME, as a sort sends it.
    function H.update(slot, id, n)
        H.m.incoming(0x020, attr(slot, id, n));
        H.put(0, slot, id, n);
    end
    -- The server adding one find: ITEM_ATTR, then ITEM_SAME after EVERY item
    -- (AscensionXI transaction.cpp applyAddItem). H.done sends the last
    -- ITEM_SAME, the tool coming back (confirmTrade).
    function H.reward(slot, id, n, packet)
        H.m.incoming(packet or 0x020, attr(slot, id, n));
        H.put(0, slot, id, n);
        H.m.incoming(0x01D, '');
        H.responding = true;
    end
    function H.done()
        if H.responding then H.m.incoming(0x01D, ''); H.responding = false; end
    end
    function H.start()
        H.done();
        H.m.outgoing(0x036, trade()); H.m.incoming(0x05A, motion());
    end
    function H.tick(dt) H.time = H.time + (dt or 0.4); H.m.tick(); end
    function H.flush() H.done(); H.tick(1.1); H.tick(); end
    function H.pause() H.done(); H.tick(storage.FLUSH_S + 0.1); H.tick(); end
    function H.confirm(srcSlot, id, left, cid, destSlot, count)
        H.m.incoming(0x020, attr(srcSlot, left == 0 and 0 or id, left));
        H.put(0, srcSlot, left == 0 and 0 or id, left);
        H.m.incoming(0x020, attr(destSlot, id, count, cid));
        H.put(cid, destSlot, id, count);
        H.tick();
    end
    return H;
end

-- Only our confirmed HELM trade opens a reward batch.
local h = harness(); h.reward(1, 300, 1); h.pause(); assert(#h.sent == 0);
h.m.outgoing(0x036, trade(13)); h.m.incoming(0x05A, motion());
h.reward(2, 300, 1); h.pause(); assert(#h.sent == 0);
h.m.outgoing(0x036, trade()); h.m.incoming(0x05A, motion(100));
h.reward(3, 300, 1); h.pause(); assert(#h.sent == 0);
h = harness(); h.opts = {}; h.start(); h.reward(1, 300, 1); h.pause(); assert(#h.sent == 0);

-- Twelve swings produce one whole-stack move, not twelve partial moves.
h = harness();
for n = 1, 11 do h.start(); h.reward(1, 100, n); h.flush(); end
assert(#h.sent == 0 and h.m.waiting() == 11, 'partial HELM stacks must wait while gathering');
h.start(); h.reward(1, 100, 12); h.flush();
assert(#h.sent == 1 and h.sent[1][5] == 12 and h.sent[1][10] == 7);
h.confirm(1, 100, 0, 7, 1, 12); assert(h.m.waiting() == 0);

-- Multi-roll rewards: non-stacking items do not wait behind partial stacks.
h = harness(); h.start(); h.reward(1, 100, 3); h.reward(2, 101, 12); h.reward(3, 300, 1); h.flush();
assert(#h.sent == 1 and h.sent[1][11] == 2);
h.confirm(2, 101, 0, 7, 1, 12); h.tick(1.1);
assert(#h.sent == 2 and h.sent[2][11] == 3);
h.confirm(3, 300, 0, 7, 2, 1); h.pause();
assert(#h.sent == 3 and h.sent[3][5] == 3 and h.sent[3][10] == 5, 'downtime flushes partial stacks');

-- Sorting after a batch relocates rewards: quantities survive; slots are live.
h = harness(); h.start(); h.reward(3, 100, 5); h.flush();
h.m.incoming(0x020, attr(3, 0, 0)); h.put(0, 3, 0, 0);
h.m.incoming(0x020, attr(1, 100, 5)); h.put(0, 1, 100, 5);
h.reward(2, 200, 12); -- unrelated arrival outside a HELM response
h.pause(); assert(#h.sent == 1 and h.sent[1][11] == 1 and h.sent[1][5] == 5);
h.confirm(1, 100, 0, 7, 1, 5); h.pause(); assert(#h.sent == 1);

-- Every find of a swing counts: a special find and two rolls each come with
-- their own ITEM_SAME, and the tool coming back sends one more.
h = harness(); h.start(); h.reward(1, 100, 1); h.reward(2, 100, 1); h.reward(3, 101, 1); h.flush();
assert(h.m.waiting() == 3, 'the first ITEM_SAME does not end the swing');

-- The swing ends once its response has been quiet; an arrival after that is
-- not a HELM find.
h = harness(); h.start(); h.reward(1, 100, 12); h.done(); h.tick(storage.SETTLE_S + 0.1);
h.reward(2, 200, 12); h.flush();
assert(h.m.waiting() == 12, 'an arrival after the swing settled is not counted');
h.confirm(1, 100, 0, 7, 1, 12); h.pause(); assert(#h.sent == 1);

-- Single units moved one by one stack in the Case: a move to a free slot never
-- joins a stack server-side, so the mover aims each at the Case stack itself.
h = harness(); h.start(); h.reward(1, 100, 1); h.reward(2, 100, 1); h.pause();
assert(#h.sent == 1 and h.sent[1][12] == 0x52, 'the first unit opens a Case stack');
h.confirm(1, 100, 0, 7, 1, 1); h.tick(1.1);
assert(#h.sent == 2 and h.sent[2][11] == 2 and h.sent[2][10] == 7 and h.sent[2][12] == 1,
    'the second unit joins it instead of taking a slot of its own');

-- A stack with room in the Satchel comes before a free slot in the Case.
h = harness(); h.put(5, 1, 100, 4); h.start(); h.reward(1, 100, 12); h.flush();
assert(h.sent[1][10] == 5 and h.sent[1][12] == 1 and h.sent[1][5] == 12, 'the Satchel stack with room first');

-- Old stock is not owed, even if sorting merges it with a reward.
h = harness(); h.put(0, 1, 100, 8); h.start(); h.reward(1, 100, 12); h.pause();
assert(#h.sent == 0 and h.m.waiting() == 4, 'a mixed stack is left intact');
h.start(); h.reward(2, 100, 3); h.pause();
assert(#h.sent == 1 and h.sent[1][11] == 2 and h.sent[1][5] == 3);
h.confirm(2, 100, 0, 7, 1, 3); h.pause(); assert(#h.sent == 1 and h.m.waiting() == 4);

-- Destination merging works without Case auto-sort, even when all slots are used.
h = harness(); h.put(7, 1, 100, 9); h.put(7, 2, 200, 12);
h.start(); h.reward(1, 100, 12); h.flush();
assert(h.sent[1][12] == 1 and h.sent[1][5] == 12);
h.confirm(1, 100, 9, 7, 1, 12); h.tick(1.1); assert(#h.sent == 1);
h.pause(); assert(#h.sent == 2 and h.sent[2][10] == 5 and h.sent[2][5] == 9);

-- A blocked item does not prevent a different item that fits from moving.
h = harness(); h.opts[5] = false; h.put(7, 1, 101, 9); h.put(7, 2, 200, 12);
h.start(); h.reward(1, 100, 12); h.reward(2, 101, 12); h.flush();
assert(#h.sent == 1 and h.sent[1][11] == 2);
h = harness(); h.opts[5] = false; h.bags[7].max = 0;
h.start(); h.reward(1, 300, 1); h.flush(); assert(#h.sent == 0 and h.m.waiting() == 1);
h.opts[5] = true; h.m.changed(); h.tick(1.1); assert(h.sent[1][10] == 5);

-- A move landing during the next swing must not hide that swing's reward.
h = harness(); h.start(); h.reward(1, 100, 12); h.flush();
h.start(); h.confirm(1, 100, 0, 7, 1, 12); h.reward(2, 100, 2); h.flush();
assert(h.m.waiting() == 2, 'subtract the confirmed move and retain the new reward');
h.pause(); assert(#h.sent == 2 and h.sent[2][5] == 2);

-- A new swing can arrive before the previous batch settles.
-- The next trade counts the last swing even before its response has gone quiet.
h = harness(); h.start(); h.reward(1, 100, 6); h.tick(storage.SETTLE_S / 2);
h.start(); h.reward(1, 100, 12); h.flush();
assert(#h.sent == 1 and h.sent[1][5] == 12, 'the unsettled swing is counted, not dropped');

-- Count-only updates, sorting old stacks, and the observed delayed sort race.
h = harness(); h.put(0, 1, 100, 2); h.put(0, 2, 100, 3); h.start(); h.reward(3, 100, 1);
h.tick(0.544); h.update(2, 0, 0); h.update(3, 0, 0);
h.m.incoming(0x01E, string.rep('\0', 4) .. p32(6) .. string.char(0, 1, 0));
h.put(0, 1, 100, 6); h.m.incoming(0x01D, ''); h.pause();
assert(#h.sent == 0 and h.m.waiting() == 1, 'old stock relocated by sorting is not a reward');
for _, id in ipairs({ 0x020, 0x01F, 0x01E, 0x05A }) do h.m.incoming(id, ''); end

-- Sorting while the swing is still open does not change what counts.
h = harness(); h.put(0, 1, 100, 2); h.put(0, 2, 100, 3); h.start(); h.reward(3, 100, 1);
h.tick(0.2); h.update(2, 0, 0); h.update(3, 0, 0); h.update(1, 100, 6); h.done(); h.pause();
assert(#h.sent == 0 and h.m.waiting() == 1, 'a sort inside the swing is not a find');

-- Incomplete responses, a zone line mid-swing, and disabled destinations cancel work.
h = harness(); h.start(); h.m.incoming(0x020, attr(1, 100, 12)); h.put(0, 1, 100, 12);
h.pause(); assert(#h.sent == 0 and h.m.waiting() == 0);
h = harness(); h.start(); h.reward(1, 100, 12); h.m.incoming(0x00B, ''); h.pause(); assert(#h.sent == 0);
h = harness(); h.start(); h.reward(1, 100, 12); h.opts = {}; h.m.changed(); h.pause(); assert(#h.sent == 0);

-- The counts survive a zone line; nothing moves until the zone has settled.
h = harness(); h.start(); h.reward(1, 100, 5); h.flush(); assert(h.m.waiting() == 5);
h.m.incoming(0x00B, ''); h.tick(storage.ZONE_S - 0.2); h.m.incoming(0x00A, '');
h.tick(storage.ZONE_S - 0.2); assert(#h.sent == 0, 'nothing moves while the zone settles');
h.tick(0.3); assert(#h.sent == 1 and h.sent[1][5] == 5, 'what was gathered before the zone line still moves');

-- A move cut off by a zone line counts as done, so carried stock never takes
-- its place: here it landed, and only the carried 5 are left.
h = harness(); h.put(0, 2, 100, 5); h.start(); h.reward(1, 100, 12); h.flush(); assert(#h.sent == 1);
h.m.incoming(0x00B, ''); h.put(0, 1, 0, 0); h.put(7, 1, 100, 12); h.m.incoming(0x00A, '');
h.tick(storage.ZONE_S + 0.1); h.pause();
assert(#h.sent == 1 and h.m.waiting() == 0, 'the carried stack stays');

-- Missing confirmation stops further moves; no duplicate retry.
h = harness(); h.start(); h.reward(1, 300, 1); h.flush();
h.put(7, 1, 300, 1); h.tick(); assert(h.m.waiting() == 1);
h.tick(5); h.tick(10); assert(#h.sent == 1 and h.m.waiting() == 0);
assert(h.m.status:find('not confirmed', 1, true));
h.m.changed(); h.start(); h.reward(2, 300, 1); h.flush(); assert(#h.sent == 2);

-- Packet confirmations survive a simultaneous withdrawal of another Case stack.
h = harness(); h.put(7, 1, 100, 12); h.start(); h.reward(1, 100, 12); h.flush();
h.m.incoming(0x020, attr(1, 0, 0, 7)); h.put(7, 1, 0, 0);
h.confirm(1, 100, 0, 7, 2, 12); assert(h.m.waiting() == 0);
h.pause(); assert(not h.m.status:find('not confirmed', 1, true));

-- Readiness, equipped/locked items, and inventory settling are still enforced.
h = harness(); h.ready = false; h.start(); h.reward(1, 300, 1); h.flush(); assert(#h.sent == 0);
h.ready = true; h.worn = true; h.tick(); assert(#h.sent == 0);
h.worn = false; h.tick(); assert(#h.sent == 1);
h = harness(); h.start(); h.reward(1, 100, 12); h.tick(0.5); h.tick(0.1); assert(#h.sent == 0);
h.flush(); assert(#h.sent == 1);
h = harness(); h.start(); h.reward(1, 100, 12); h.put(0, 1, 100, 12, 5); h.flush(); assert(#h.sent == 0);
print('OK -- HELM counts across swings/sorts, whole stacks, downtime, stock protection, merges and confirmations');
