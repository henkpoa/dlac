-- lua tests/fishstorage.lua
local storage = dofile('feature/fishstorage.lua');
local function p16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function p32(n) return p16(n % 65536) .. p16(math.floor(n / 65536)); end
-- Our 0x110 (GP_CLI_COMMAND_FISHING_2): UniqueNo, para, ActIndex, mode, pad, para2.
local function fishing(mode)
    return string.rep('\0', 4) .. p32(99) .. p32(0) .. p16(1234) .. string.char(mode, 0) .. p32(0);
end
local function attr(slot, id, count, cid, flags)
    return string.rep('\0', 4) .. p32(count) .. p32(0) .. p16(id) .. string.char(cid or 0, slot, flags or 0);
end
-- 100/101 stack to 12 and 300 does not stack (fish); 200 is trash a line
-- brings up (stacks to 12). 400 is a broken rod and 500 the bait: neither is
-- a catch.
local CATCH = { [100] = 'fish', [101] = 'fish', [200] = 'trash', [300] = 'fish' };
local function harness()
    local H = { time = 0, sent = {}, opts = { [7] = true, [5] = true }, ready = true,
        bags = { [0] = { max = 4, items = {} }, [7] = { max = 2, items = {} }, [5] = { max = 2, items = {} } } };
    local function snapshot(cid)
        H.reads = (H.reads or 0) + 1;
        local b, out = H.bags[cid], { max = H.bags[cid].max, items = {} };
        for k, it in pairs(b.items) do out.items[k] = { id = it.id, count = it.count, flags = it.flags }; end
        return out;
    end
    H.m = storage.new({ clock = function() return H.time; end,
        options = function() return H.opts; end, bag = snapshot,
        catchKind = function(id) return CATCH[id]; end,
        ready = function() return H.ready; end, equipped = function() return H.worn == true; end,
        stack = function(id) return id == 300 and 1 or 12; end,
        send = function(p) if H.refuse then return false; end H.sent[#H.sent + 1] = p; return true; end });
    function H.put(cid, slot, id, n, flags)
        H.bags[cid].items[slot] = { id = id, count = n, flags = flags or 0 };
    end
    -- An inventory update with no ITEM_SAME, as a sort sends it.
    function H.update(slot, id, n)
        H.m.incoming(0x020, attr(slot, id, n));
        H.put(0, slot, id, n);
    end
    -- The server answering a reel: ITEM_ATTR + ITEM_SAME for what it adds.
    function H.catch(slot, id, n)
        H.m.incoming(0x020, attr(slot, id, n));
        H.put(0, slot, id, n);
        H.m.incoming(0x01D, '');
    end
    function H.reel() H.m.outgoing(0x110, fishing(storage.REEL)); end
    function H.release() H.m.outgoing(0x110, fishing(storage.RELEASE)); end
    function H.tick(dt) H.time = H.time + (dt or 0.4); H.m.tick(); end
    function H.flush() H.tick(1.1); H.tick(); end
    function H.pause() H.tick(storage.FLUSH_S + 0.1); H.tick(); end
    function H.confirm(srcSlot, id, left, cid, destSlot, count)
        H.m.incoming(0x020, attr(srcSlot, left == 0 and 0 or id, left));
        H.put(0, srcSlot, left == 0 and 0 or id, left);
        H.m.incoming(0x020, attr(destSlot, id, count, cid));
        H.put(cid, destSlot, id, count);
        H.tick();
    end
    return H;
end

-- Only our reel opens a capture: a catch with no reel, a hook check, a lone
-- release, and switches off all count nothing.
local h = harness(); h.catch(1, 300, 1); h.pause(); assert(#h.sent == 0, 'no reel, no catch');
h.m.outgoing(0x110, fishing(2)); h.catch(2, 300, 1); h.pause(); assert(#h.sent == 0, 'a hook check is not a reel');
h.release(); h.catch(3, 300, 1); h.pause(); assert(#h.sent == 0, 'a release is not a reel');
h.m.outgoing(0x110, fishing(storage.REEL):sub(1, 14)); h.catch(4, 300, 1); h.pause();
assert(#h.sent == 0, 'a short packet is ignored');
h = harness(); h.opts = {}; h.reel(); h.catch(1, 300, 1); h.pause(); assert(#h.sent == 0);

-- A fish that does not stack moves as soon as the inventory is quiet.
h = harness(); h.reel(); h.catch(1, 300, 1); h.release(); h.flush();
assert(#h.sent == 1 and h.sent[1][5] == 1 and h.sent[1][10] == 7 and h.sent[1][11] == 1, 'a non-stacking catch moves at once');
h.confirm(1, 300, 0, 7, 1, 1); assert(h.m.waiting() == 0);

-- Twelve quick catches make one whole-stack move, not twelve partial ones.
h = harness();
for n = 1, 11 do h.reel(); h.catch(1, 100, n); h.release(); h.flush(); end
assert(#h.sent == 0 and h.m.waiting() == 11, 'partial stacks wait while you keep reeling in');
h.reel(); h.catch(1, 100, 12); h.release(); h.flush();
assert(#h.sent == 1 and h.sent[1][5] == 12 and h.sent[1][10] == 7);
h.confirm(1, 100, 0, 7, 1, 12); assert(h.m.waiting() == 0);

-- A partial stack moves once you have not reeled in for FLUSH_S.
h = harness(); h.reel(); h.catch(1, 100, 3); h.release(); h.flush(); assert(#h.sent == 0);
h.pause(); assert(#h.sent == 1 and h.sent[1][5] == 3, 'the pause flushes the partial stack');

-- Trash stays unless its switch is on (Henrik 2026-10-15: fish only by
-- default); a fish caught beside it still moves.
h = harness(); h.put(0, 2, 500, 10);
h.reel(); h.catch(1, 200, 1); h.release(); h.pause();
assert(#h.sent == 0 and h.m.waiting() == 0, 'trash stays by default');
h.reel(); h.catch(3, 300, 1); h.release(); h.flush();
assert(#h.sent == 1 and h.sent[1][11] == 3, 'the fish still moves');
-- With "Move trash too" on, the trash catch moves like a fish.
h = harness(); h.opts.trash = true;
h.reel(); h.catch(1, 200, 1); h.release(); h.pause();
assert(#h.sent == 1 and h.sent[1][11] == 1, 'trash moves with its switch on');
-- Trash counted while the switch was on is forgotten when it goes off, at
-- once through changed(), and by the tick if the switch changes behind it.
h = harness(); h.opts.trash = true;
h.reel(); h.catch(1, 200, 3); h.catch(2, 100, 2); h.release(); h.flush();
assert(h.m.waiting() == 5, 'three trash and two fish owed');
h.opts.trash = false; h.m.changed();
assert(h.m.waiting() == 2, 'switching trash off forgets the trash at once');
h.pause(); assert(#h.sent == 1 and h.sent[1][11] == 2, 'only the fish moves');
h = harness(); h.opts.trash = true;
h.reel(); h.catch(1, 200, 3); h.release(); h.flush(); assert(h.m.waiting() == 3);
h.opts.trash = false; h.pause();
assert(#h.sent == 0 and h.m.waiting() == 0, 'the tick drops trash it may no longer move');
-- A broken rod and the bait are never catches, trash switch or not.
h = harness(); h.opts.trash = true; h.put(0, 2, 500, 10); h.put(0, 3, 17, 1);
h.reel();
h.m.incoming(0x020, attr(3, 400, 1)); h.put(0, 3, 400, 1);   -- the rod breaks
h.m.incoming(0x020, attr(2, 500, 9)); h.put(0, 2, 500, 9);   -- the bait goes
h.m.incoming(0x01D, ''); h.release(); h.pause();
assert(#h.sent == 0 and h.m.waiting() == 0, 'no broken rod, no bait');
h = harness(); h.put(0, 2, 500, 3);
h.reel(); h.m.incoming(0x020, attr(2, 500, 12)); h.put(0, 2, 500, 12); h.m.incoming(0x01D, ''); h.pause();
assert(h.m.waiting() == 0, 'more bait in the bags is still not a catch');

-- The release ends the reel at once; an arrival after it is not a catch.
h = harness(); h.reel(); h.catch(1, 100, 12); h.release();
h.catch(2, 101, 12); h.flush();
assert(h.m.waiting() == 12, 'only the reeled catch counts');
-- Without a release, the answer counts once it has been quiet for SETTLE_S.
h = harness(); h.reel(); h.catch(1, 100, 12); h.tick(storage.SETTLE_S + 0.1);
h.catch(2, 101, 12); h.flush();
assert(h.m.waiting() == 12, 'an arrival after the reel settled is not counted');

-- A reel the server never answers (no bite, an interrupted fight) counts
-- nothing, and the next reel counts only its own catch.
h = harness(); h.reel(); h.m.incoming(0x020, attr(1, 100, 5)); h.put(0, 1, 100, 5);
h.tick(storage.CAPTURE_S + 0.1); h.pause(); assert(h.m.waiting() == 0, 'an unanswered reel counts nothing');
h.reel(); h.catch(2, 101, 2); h.release(); h.pause();
assert(#h.sent == 1 and h.sent[1][11] == 2 and h.sent[1][5] == 2);

-- An answered reel that is never released is counted when the next reel goes out.
h = harness(); h.reel(); h.catch(1, 100, 4); h.reel(); h.catch(2, 101, 2); h.release(); h.flush();
assert(h.m.waiting() == 6, 'both reels count');

-- Carried stock is never owed, even when sorting merges it with a catch.
h = harness(); h.put(0, 1, 100, 8); h.reel(); h.catch(1, 100, 12); h.release(); h.pause();
assert(#h.sent == 0 and h.m.waiting() == 4, 'a mixed stack is left intact');

-- Single catches stack in the Case: each move aims at the Case stack itself.
h = harness(); h.reel(); h.catch(1, 100, 1); h.release(); h.pause();
assert(#h.sent == 1 and h.sent[1][12] == 0x52, 'the first catch opens a Case stack');
h.confirm(1, 100, 0, 7, 1, 1);
h.reel(); h.catch(2, 100, 1); h.release(); h.pause();
assert(#h.sent == 2 and h.sent[2][10] == 7 and h.sent[2][12] == 1, 'the next one joins it');
-- A stack with room in the Satchel comes before a free slot in the Case.
h = harness(); h.put(5, 1, 100, 4); h.reel(); h.catch(1, 100, 12); h.release(); h.flush();
assert(h.sent[1][10] == 5 and h.sent[1][12] == 1, 'the Satchel stack with room first');

-- A move landing during the next reel must not hide that reel's catch.
h = harness(); h.reel(); h.catch(1, 100, 12); h.release(); h.flush();
h.reel(); h.confirm(1, 100, 0, 7, 1, 12); h.catch(2, 100, 2); h.release(); h.flush();
assert(h.m.waiting() == 2, 'subtract the confirmed move and keep the new catch');

-- The counts survive a zone line; nothing moves until the zone has settled.
h = harness(); h.reel(); h.catch(1, 100, 5); h.release(); h.flush(); assert(h.m.waiting() == 5);
h.m.incoming(0x00B, ''); h.tick(storage.ZONE_S - 0.2); h.m.incoming(0x00A, '');
h.tick(storage.ZONE_S - 0.2); assert(#h.sent == 0, 'nothing moves while the zone settles');
h.tick(0.3); assert(#h.sent == 1 and h.sent[1][5] == 5, 'what was caught before the zone line still moves');

-- Missing confirmation stops further moves; touching a switch resumes.
h = harness(); h.reel(); h.catch(1, 300, 1); h.release(); h.flush();
h.tick(5); h.tick(10); assert(#h.sent == 1 and h.m.waiting() == 0);
assert(h.m.status:find('not confirmed', 1, true));
h.reel(); h.catch(2, 300, 1); h.release(); h.flush(); assert(#h.sent == 1, 'stopped until a switch changes');
h.m.changed(); h.reel(); h.catch(3, 300, 1); h.release(); h.flush(); assert(#h.sent == 2);

-- A refused send stops the mover too.
h = harness(); h.refuse = true;
h.reel(); h.catch(1, 100, 12); h.release(); h.flush();
assert(#h.sent == 0 and h.m.status:find('Move failed', 1, true));
h.refuse = false; h.reel(); h.catch(2, 300, 1); h.release(); h.flush();
assert(#h.sent == 0, 'stopped after a refused send');

-- Readiness, equipped/locked items and a settling inventory are still enforced.
h = harness(); h.ready = false; h.reel(); h.catch(1, 300, 1); h.release(); h.flush(); assert(#h.sent == 0);
h.ready = true; h.worn = true; h.tick(); assert(#h.sent == 0);
h.worn = false; h.tick(); assert(#h.sent == 1);
h = harness(); h.reel(); h.catch(1, 100, 12); h.release(); h.tick(0.5); h.tick(0.1); assert(#h.sent == 0);
h.flush(); assert(#h.sent == 1);
h = harness(); h.reel(); h.catch(1, 100, 12); h.put(0, 1, 100, 12, 5); h.release(); h.flush(); assert(#h.sent == 0);
-- Switching both destinations off forgets the counts.
h = harness(); h.reel(); h.catch(1, 100, 3); h.release(); h.flush(); assert(h.m.waiting() == 3);
h.opts = {}; h.m.changed(); assert(h.m.waiting() == 0);
-- Idle with a destination on: nothing owed, so the tick reads no bag at all.
h = harness(); for _ = 1, 50 do h.tick(0.1); end
assert((h.reads or 0) == 0, 'an idle mover reads no bag');

print('OK -- catches counted per reel, fish vs trash vs bait and broken rods, whole stacks, pauses, carried stock, merges, zones and confirmations');
