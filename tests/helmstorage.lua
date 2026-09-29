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
        stack = function() return 12; end,
        send = function(p) H.sent[#H.sent + 1] = p; return true; end });
    function H.put(cid, slot, id, n, flags)
        H.bags[cid].items[slot] = { id = id, count = n, flags = flags or 0 };
    end
    function H.reward(slot, id, n, packet)
        H.m.incoming(packet or 0x020, attr(slot, id, n));
        H.put(0, slot, id, n);
        H.m.incoming(0x01D, '');
    end
    function H.start()
        H.m.outgoing(0x036, trade()); H.m.incoming(0x05A, motion());
    end
    function H.tick(dt) H.time = H.time + (dt or 0.4); H.m.tick(); end
    function H.flush() H.tick(1.1); H.tick(); end
    function H.confirm(srcSlot, id, left, cid, destSlot, count)
        H.m.incoming(0x020, attr(srcSlot, left == 0 and 0 or id, left));
        H.put(0, srcSlot, left == 0 and 0 or id, left);
        H.m.incoming(0x020, attr(destSlot, id, count, cid));
        H.put(cid, destSlot, id, count);
        H.tick();
    end
    return H;
end

-- Only our confirmed HELM trade can open a reward batch.
local h = harness();
h.reward(1, 100, 1); h.flush(); assert(#h.sent == 0);
h.m.outgoing(0x036, trade(13)); h.m.incoming(0x05A, motion());
h.reward(2, 101, 1); h.flush(); assert(#h.sent == 0);
h.m.outgoing(0x036, trade()); h.m.incoming(0x05A, motion(100));
h.reward(3, 102, 1); h.flush(); assert(#h.sent == 0);
h = harness(); h.opts = {}; h.start(); h.reward(1, 100, 1); h.flush(); assert(#h.sent == 0);

-- Preserve pre-existing items, including a partially filled source stack.
h = harness(); h.put(0, 1, 100, 8); h.put(0, 2, 605, 12);
h.start(); h.reward(1, 100, 10); h.reward(2, 605, 11); h.flush();
assert(#h.sent == 1 and #h.sent[1] == 12);
assert(h.sent[1][5] == 2 and h.sent[1][9] == 0 and h.sent[1][10] == 7 and h.sent[1][12] == 0x52);
h.confirm(1, 100, 8, 7, 1, 2); h.tick(); assert(#h.sent == 1 and #h.m.queue == 0);

-- All rewards from a multi-roll swing are queued; one move at a time.
h = harness(); h.start(); h.reward(1, 100, 1); h.reward(2, 101, 1); h.flush();
h.tick(); assert(#h.sent == 1);
h.confirm(1, 100, 0, 7, 1, 1); h.tick(); assert(#h.sent == 2 and h.sent[2][11] == 2);

-- A full Case falls back to Satchel; unselected bags are never used.
h = harness(); h.put(7, 1, 200, 12); h.put(7, 2, 201, 12);
h.start(); h.reward(1, 100, 1); h.flush(); assert(h.sent[1][10] == 5);
h = harness(); h.opts[5] = false; h.bags[7].max = 0;
h.start(); h.reward(1, 100, 1); h.flush(); assert(#h.sent == 0 and #h.m.queue == 1);
h.bags[7].max = 2; h.tick(1.1); assert(#h.sent == 1);

-- Whole gathered stacks merge, including into an otherwise full container.
h = harness(); h.put(7, 1, 100, 11); h.put(7, 2, 200, 12);
h.start(); h.reward(1, 100, 3); h.flush();
assert(h.sent[1][5] == 3 and h.sent[1][12] == 1);
h.confirm(1, 100, 2, 7, 1, 12); h.tick();
assert(h.sent[2][5] == 2 and h.sent[2][10] == 5);
-- Partial source transfers need a FREE slot: server AddItem does not merge.
h = harness(); h.put(0, 1, 100, 8); h.put(7, 1, 100, 3); h.put(7, 2, 200, 12);
h.start(); h.reward(1, 100, 9); h.flush(); assert(h.sent[1][10] == 5);

-- Stale slots cannot send a different item or remove the old stock.
h = harness(); h.start(); h.reward(1, 100, 1); h.tick(1.1); h.put(0, 1, 200, 1); h.tick();
assert(#h.sent == 0 and #h.m.queue == 0);
h = harness(); h.start(); h.reward(1, 100, 1); h.tick(1.1); h.put(0, 1, 100, 2); h.tick();
assert(#h.sent == 0);
h = harness(); h.ready = false; h.start(); h.reward(1, 100, 1); h.flush(); assert(#h.sent == 0);
h.ready = true; h.worn = true; h.tick(); assert(#h.sent == 0);
h.worn = false; h.tick(); assert(#h.sent == 1);

-- Timeout never retries; destination-only/source-only changes do not confirm.
h = harness(); h.start(); h.reward(1, 100, 1); h.flush();
h.put(7, 1, 100, 1); h.tick(); assert(#h.m.queue == 1);
h.tick(5); h.tick(10); assert(#h.sent == 1 and #h.m.queue == 0);
assert(h.m.status:find('not confirmed', 1, true));
h.m.changed(); h.start(); h.reward(2, 101, 1); h.flush(); assert(#h.sent == 2);

-- Zoning and disabling cancel pending work.
h = harness(); h.start(); h.reward(1, 100, 1); h.m.incoming(0x00B, ''); h.flush(); assert(#h.sent == 0);
h = harness(); h.start(); h.reward(1, 100, 1); h.opts = {}; h.m.changed(); h.flush(); assert(#h.sent == 0);

-- Count-only updates to existing stacks and truncated packets.
h = harness(); h.put(0, 1, 100, 3); h.start();
h.m.incoming(0x01E, string.rep('\0', 4) .. p32(4) .. string.char(0, 1, 0));
h.put(0, 1, 100, 4); h.m.incoming(0x01D, ''); h.flush(); assert(h.sent[1][5] == 1);
for _, id in ipairs({ 0x020, 0x01F, 0x01E, 0x05A }) do h.m.incoming(id, ''); end

-- A new destination releases an existing queue, without sweeping old items.
h = harness(); h.opts[5] = false; h.bags[7].max = 0;
h.start(); h.reward(1, 100, 1); h.flush(); assert(#h.sent == 0);
h.opts[5] = true; h.m.changed(); h.tick(1.1); assert(h.sent[1][10] == 5);

-- Another swing while a transfer is outstanding is still observed. A source
-- acknowledgement remains valid if that same item is gathered again before tick.
h = harness(); h.start(); h.reward(1, 100, 1); h.flush();
h.m.incoming(0x020, attr(1, 0, 0)); h.put(0, 1, 0, 0); h.put(7, 1, 100, 1);
h.start(); h.reward(1, 100, 1); h.tick(); h.flush();
assert(#h.sent == 2 and h.sent[2][5] == 1);

-- An incomplete reward burst is discarded instead of being guessed at.
h = harness(); h.start(); h.m.incoming(0x020, attr(1, 100, 1)); h.put(0, 1, 100, 1);
h.tick(6); h.tick(); assert(#h.sent == 0);
-- Production 2026-09-28: reward in slot 20 at 33263.359; auto-stack
-- removes it at 33263.903 and raises slot 16 from 3 to 4. The old mover
-- sent at 33263.843, just before the stack operation reached memory.
h = harness(); h.bags[0].max = 30; h.put(0, 16, 4105, 3); h.start();
h.reward(20, 4105, 1);
h.tick(0.384); h.tick(0.101);
h.time = 0.544;
h.m.incoming(0x020, attr(20, 0, 0)); h.put(0, 20, 0, 0);
h.m.incoming(0x01E, string.rep('\0', 4) .. p32(4) .. string.char(0, 16, 0));
h.put(0, 16, 4105, 4); h.m.incoming(0x01D, '');
h.tick(1.1); h.tick();
assert(#h.sent == 1 and h.sent[1][11] == 16 and h.sent[1][5] == 1,
    'live auto-stack race: move the gathered unit from its settled slot, not the vanished reward slot');
h.confirm(16, 4105, 3, 7, 1, 1); h.tick(6);
assert(not h.m.status:find('not confirmed', 1, true) and #h.m.queue == 0,
    'live auto-stack race must not disable further gathering moves');
-- Auto-sort may merge several old stacks along with the reward. Their
-- relocation is not newly gathered quantity.
h = harness(); h.put(0, 1, 100, 2); h.put(0, 2, 100, 3); h.start(); h.reward(3, 100, 1);
h.reward(1, 100, 6); h.reward(2, 0, 0); h.reward(3, 0, 0); h.flush();
assert(#h.sent == 1 and h.sent[1][5] == 1 and h.sent[1][11] == 1,
    'sorting old stacks must preserve all five pre-existing items');
-- Production 33541.384: an existing Case stack was withdrawn while a HELM
-- deposit was pending. Its source/deposit packets confirmed the move, but
-- comparing total Case holdings against the old total incorrectly timed out.
h = harness(); h.put(0, 1, 100, 3); h.put(7, 1, 100, 9);
h.start(); h.reward(1, 100, 4); h.flush();
h.m.incoming(0x020, attr(1, 0, 0, 7)); h.put(7, 1, 0, 0);
h.m.incoming(0x020, attr(3, 100, 9, 0)); h.put(0, 3, 100, 9);
h.confirm(1, 100, 3, 7, 1, 1);
assert(#h.m.queue == 0, 'concurrent Case withdrawal must not hide a confirmed HELM deposit');
h.tick(6); h.start(); h.reward(2, 101, 1); h.flush();
assert(#h.sent == 2, 'gathering must continue after the concurrent withdrawal/deposit');
print('OK -- HELM reward tracking, exact quantities, destination fallback, stacking, confirmation and cancellation');
