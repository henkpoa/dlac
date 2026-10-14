--[[
    dlac/feature/bagindex.lua -- what the equip bags hold, KEPT instead of
    re-read (2026-10-13, the stutter report).

    Henrik: "Why does it need to check EVERYTHING all the time? Should cache it
    and only check if something arrives into inventory." Every gear decision
    learned where its pieces were by walking all nine equip bags -- Inventory
    and the eight Wardrobes, up to 720 slots, a C++ call per slot -- and the
    per-second item counter walked them again. The bags never change behind
    the client's back: the server reports every item it adds, moves, re-flags
    or uses up with a packet that NAMES the container and slot it touched
    (the AscensionXI server's src/map/packets/s2c, XiPackets layouts):
        0x01E ITEM_NUM    a count changed        Category @0x08, ItemIndex @0x09
        0x01F ITEM_LIST   an item placed/flagged Category @0x0A, ItemIndex @0x0B
        0x020 ITEM_ATTR   a full item (+augments) Category @0x0E, ItemIndex @0x0F
        0x050 EQUIP_LIST  equipped from here     ItemIndex @0x04, Category @0x06
    and resets them wholesale with two more: 0x00A (zone-in: the whole
    inventory is sent again) and 0x01C (container sizes).

    So: ONE walk (at load, after a zone-in or a size change). After that a
    packet marks just the slot it names, and that slot alone is read again --
    one call -- the next time anyone asks. Nothing is read on a timer, and
    nothing is read for a question the index already answers.

    THE TIMING RULE. Ashita hands over an incoming packet BEFORE the client
    applies it to memory, and one chunk can carry an inventory packet and the
    0x028 that fires a gear swap side by side. A slot read within SETTLE_S of
    the last inventory packet is used, but stays marked: the first ask after
    the window reads it again. A read that finds the slot unchanged keeps the
    old entry object, so nothing downstream is rebuilt for it.

    ENTRIES are { Container, Index, Id, Count, Flags, Extra, Name, seq } and
    are never changed once linked: a changed slot gets a NEW entry. Consumers
    may therefore hang what they derive from one ON it (equipengine keeps its
    planSet view there) -- it dies with the entry. `seq` orders entries the
    way LuaAshitacast scans: bag by bag in M.BAGS order, slot by slot.

    The equip engine does not trust this blindly: it re-reads every slot it is
    about to equip FROM (only when a packet goes out) and calls invalidateAll()
    on a mismatch, so a packet this index never saw costs one extra walk,
    never a wrong piece.
]]--

local M = {};

-- The equip-eligible containers in LuaAshitacast's SCAN ORDER -- wardrobes
-- first, inventory last: equipcore.DEFAULT_EQUIP_BAGS, the order first-fit
-- takes a copy in. The same SET as dispatch's AMMO_BAGS (both parity-pinned
-- in the tests).
M.BAGS = { 8, 10, 11, 12, 13, 14, 15, 16, 0 };
M.SETTLE_S = 0.25;    -- see THE TIMING RULE
M._clock = os.clock;  -- test seam
-- Test seam: true = walk on every ask and keep nothing (the pre-index
-- behavior), for suites that rewrite their fake bags without a packet.
M._walkEveryAsk = false;

local POS = {};
for i, c in ipairs(M.BAGS) do POS[c] = i; end

local function keyOf(c, i) return c * 256 + i; end

local _slots  = {};        -- [key] = entry
local _byName = {};        -- [lowered name] = { [key] = entry }
local _countById, _countByName = {}, {};
local _all    = true;      -- a full walk is owed
local _dirty  = {};        -- [key] = true: named by a packet since last read
local _lastInv = -math.huge;
local _built  = false;     -- has any read succeeded yet
local _nameById = {};      -- item id -> lowered client name (resources are immutable)

M.version = 0;             -- bumped whenever an entry changes
M.stats = { walks = 0, reads = 0, heals = 0 };   -- full walks, slot reads, engine heals

-- Item id -> lowered client name: GetItemById (and the Name table the binding
-- builds on every access) once per item ID, ever. A nil resource is not
-- remembered; a nameless one is ''.
local function nameOf(resMgr, id)
    local nm = _nameById[id];
    if nm ~= nil then return nm; end
    local res = resMgr:GetItemById(id);
    if res == nil then return nil; end
    nm = string.lower(res.Name[1] or '');
    _nameById[id] = nm;
    return nm;
end

local function readSlot(inv, resMgr, c, i)
    M.stats.reads = M.stats.reads + 1;
    local ci = inv:GetContainerItem(c, i);
    if ci == nil then return nil; end
    local id = ci.Id;
    if id == nil or id == 0 or id == 65535 then return nil; end
    local n = tonumber(ci.Count) or 0;
    if n <= 0 then return nil; end
    return { Container = c, Index = i, Id = id, Count = n, Flags = ci.Flags,
             Extra = ci.Extra, Name = nameOf(resMgr, id), seq = (POS[c] or 99) * 256 + i };
end

local function unlink(key, e)
    if e.Name ~= nil and e.Name ~= '' then
        local set = _byName[e.Name];
        if set ~= nil then
            set[key] = nil;
            if next(set) == nil then _byName[e.Name] = nil; end
        end
        local m = (_countByName[e.Name] or 0) - e.Count;
        _countByName[e.Name] = (m > 0) and m or nil;
    end
    local n = (_countById[e.Id] or 0) - e.Count;
    _countById[e.Id] = (n > 0) and n or nil;
end

local function link(key, e)
    if e.Name ~= nil and e.Name ~= '' then
        local set = _byName[e.Name];
        if set == nil then set = {}; _byName[e.Name] = set; end
        set[key] = e;
        _countByName[e.Name] = (_countByName[e.Name] or 0) + e.Count;
    end
    _countById[e.Id] = (_countById[e.Id] or 0) + e.Count;
end

local function put(key, new)
    local old = _slots[key];
    if old == nil and new == nil then return; end
    if old ~= nil and new ~= nil and old.Id == new.Id and old.Count == new.Count
       and old.Flags == new.Flags and old.Extra == new.Extra then
        return;   -- unchanged: the old entry, and all built on it, stays
    end
    if old ~= nil then unlink(key, old); end
    if new ~= nil then link(key, new); end
    _slots[key] = new;
    M.version = M.version + 1;
end

local function walk(inv, resMgr)
    M.stats.walks = M.stats.walks + 1;
    for _, c in ipairs(M.BAGS) do
        local max = tonumber(inv:GetContainerCountMax(c)) or 0;
        for i = 1, max do put(keyOf(c, i), readSlot(inv, resMgr, c, i)); end
        -- a locked or shrunk container holds nothing past its size
        for i = math.max(max, 0) + 1, 80 do put(keyOf(c, i), nil); end
    end
end

-- Bring the index up to date: the full walk when one is owed, else just the
-- slots packets named. Free when nothing is owed. false = memory unreadable.
function M.refresh()
    if M._walkEveryAsk then _all = true; end
    if not _all and next(_dirty) == nil then return true; end
    local ok = pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local resMgr = AshitaCore:GetResourceManager();
        if _all then
            walk(inv, resMgr);
        else
            for key in pairs(_dirty) do
                put(key, readSlot(inv, resMgr, math.floor(key / 256), key % 256));
            end
        end
    end);
    if not ok then return false; end
    _built = true;
    if M._clock() - _lastInv >= M.SETTLE_S then
        _all, _dirty = false, {};
    end
    -- An EMPTY index is never final: a live character always holds something
    -- (what it wears, at least), so empty means the bags were read before they
    -- were there -- char select, mid-zone.
    if next(_slots) == nil then _all = true; end
    return true;
end

-- id -> summed Count and lowered name -> summed Count over the equip bags,
-- plus the version they are at. LIVE tables, kept between calls: read them,
-- never write them, and key a memo on the version, not on their identity.
-- nil when the bags have never been readable.
function M.counts()
    if not M.refresh() and not _built then return nil, nil, nil; end
    return _countById, _countByName, M.version;
end

-- The entry at one bag slot, or nil when it is empty (or not an equip bag).
function M.entryAt(c, i)
    M.refresh();
    return _slots[keyOf(c, i)];
end

-- Every entry whose name `want` (a set of lowered names; nil = all) asks
-- for, in scan order. nil when the bags have never been readable.
local function bySeq(a, b) return a.seq < b.seq; end
function M.named(want)
    if not M.refresh() and not _built then return nil; end
    local out = {};
    if want == nil then
        for _, e in pairs(_slots) do out[#out + 1] = e; end
    else
        for name in pairs(want) do
            local set = _byName[name];
            if set ~= nil then
                for _, e in pairs(set) do out[#out + 1] = e; end
            end
        end
    end
    if #out > 1 then table.sort(out, bySeq); end
    return out;
end

-- An incoming packet: mark what it says changed. Pure on (id, data), so the
-- tests drive wire bodies straight through it.
local SLOT_AT = {          -- packet id -> { container offset, slot offset }
    [0x01E] = { 0x08, 0x09 },
    [0x01F] = { 0x0A, 0x0B },
    [0x020] = { 0x0E, 0x0F },
    [0x050] = { 0x06, 0x04 },
};
function M.noteIncoming(id, data)
    if id == 0x00A or id == 0x01C then
        _all, _lastInv = true, M._clock();
        return;
    end
    local at = SLOT_AT[id];
    if at == nil then return; end
    local c = (type(data) == 'string') and string.byte(data, at[1] + 1) or nil;
    local i = (type(data) == 'string') and string.byte(data, at[2] + 1) or nil;
    if c == nil or i == nil then       -- a short packet: trust nothing
        _all, _lastInv = true, M._clock();
        return;
    end
    if POS[c] == nil or i == 0 then return; end   -- not an equip bag / the gil slot / an unequip
    _dirty[keyOf(c, i)] = true;
    _lastInv = M._clock();
end

-- Mark one slot for a re-read (a consumer found the index disagreeing with
-- what the game shows there).
function M.touch(c, i)
    if POS[c] ~= nil and type(i) == 'number' and i > 0 then _dirty[keyOf(c, i)] = true; end
end

-- Walk everything again on the next ask (the engine's safety net tripped).
function M.invalidateAll()
    _all = true;
    M.stats.heals = M.stats.heals + 1;
end

-- Test seam: forget everything (a fresh world).
function M._reset()
    _slots, _byName, _countById, _countByName = {}, {}, {}, {};
    _all, _dirty, _lastInv, _built = true, {}, -math.huge, false;
    _nameById = {};
    M.version = 0;
    M.stats = { walks = 0, reads = 0, heals = 0 };
end

pcall(function()
    ashita.events.register('packet_in', 'dlac-bagindex-in', function(e)
        M.noteIncoming(e.id, e.data);
    end);
end);

return M;
