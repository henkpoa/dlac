--[[
    dlac/gear/equipcore.lua -- the native equip pipeline, part 1 (resolver +
    packet builders). feature/native-engine: dlac absorbing LuaAshitacast.

    LuaAshitacast's equip.lua is the reference implementation: this module
    ports its semantics -- entry normalization, worn-set flagging, bag
    resolution, priority ordering, conflict unequips, the 0x050/0x051 packet
    shapes -- with the same behavior an existing set file expects, so a
    character flipping to the native engine sees identical equips.

    LAYERING (the house pure-core rule): everything in this file is PURE and
    offline-tested (EQC* in tests\run_tests.lua). The resolver runs against an
    injectable SNAPSHOT -- a plain-table view of the player + inventory -- and
    returns a PLAN -- packets to send, nothing sent from here. The Ashita-facing
    shell (equip state machine + packet interception, part 2) builds snapshots
    from AshitaCore and executes plans; dispatch.lua's native backend feeds
    sets in. No AshitaCore, no gFunc, no io anywhere in this file.

    SNAPSHOT shape (what the resolver consumes):
        snap = {
            job      = <main job id 1..22>,
            level    = <effective level for gear gates (sync-aware)>,
            disabled   = { [slot]=true },   -- /dl-equivalent of /lac disable
            encumbered = { [slot]=true },   -- server encumbrance bits (0x1B)
            equipped = { [slot] = item|nil },   -- the worn view, trust-window
                                                -- already applied by the shell
            items    = { item, ... },       -- candidate items in BAG SCAN ORDER
        }
        item = {
            Container = <bag id>, Index = <inventory index>, Id = <item id>,
            Count = n, Flags = n,           -- Flags==19 is bazaared (skipped)
            Name = <lowercased client name>,
            Level = n, Jobs = <job bitmask>, Slots = <slot bitmask>,
            ResFlags = <item flags word; 0x800 = equippable>,
            augment = nil | { Path=, Rank=, Trial=, Augs={ {String=}, ... } },
        }

    PLAN shape (what the resolver returns):
        plan = {
            satisfied = bool,               -- everything already worn: send nothing
            conflicts = { { Slot=<0-based worn slot>, Container= }, ... },
            equips    = { { Slot=<0-based>, Index=, Container= }, ... },  -- ordered
            stamps    = { { Slot=<0-based>, Index=, Container= }, ... },  -- trust-window
                                            -- entries the shell records (equips +
                                            -- displaced holes), never sent
        }

    Slot ids are LuaAshitacast's 1..16 order (packet slot = id - 1):
    Main Sub Range Ammo Head Body Hands Legs Feet Neck Waist Ear1 Ear2
    Ring1 Ring2 Back.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- constants
-- ---------------------------------------------------------------------------

M.SLOT_NAMES = { 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Body', 'Hands',
                 'Legs', 'Feet', 'Neck', 'Waist', 'Ear1', 'Ear2', 'Ring1',
                 'Ring2', 'Back' };

M.SLOT_ID = {};
for i, n in ipairs(M.SLOT_NAMES) do M.SLOT_ID[n] = i; end

-- LuaAshitacast's default gSettings.EquipBags: wardrobes first, inventory
-- last -- the scan order every existing profile resolved against.
M.DEFAULT_EQUIP_BAGS = { 8, 10, 11, 12, 13, 14, 15, 16, 0 };

-- Container-name pins for entry.Bag given as a string (LAC accepts both).
M.CONTAINERS = {
    Inventory = 0, Safe = 1, Storage = 2, Temporary = 3, Locker = 4,
    Satchel = 5, Sack = 6, Case = 7, Wardrobe = 8, Safe2 = 9,
    Wardrobe2 = 10, Wardrobe3 = 11, Wardrobe4 = 12, Wardrobe5 = 13,
    Wardrobe6 = 14, Wardrobe7 = 15, Wardrobe8 = 16,
};

-- ---------------------------------------------------------------------------
-- small pure helpers (no bit library: the headless suite runs plain Lua)
-- ---------------------------------------------------------------------------

-- Is bit N (0-based) set in mask? Doubles are exact well past any item mask.
local function bitSet(mask, n)
    if type(mask) ~= 'number' then return false; end
    return math.floor(mask / (2 ^ n)) % 2 == 1;
end
M.bitSet = bitSet;

-- ---------------------------------------------------------------------------
-- entry normalization (LAC MakeItemTable parity)
-- ---------------------------------------------------------------------------

-- A set entry is a string name or a table { Name, Augment, AugPath, AugRank,
-- AugTrial, Bag, Priority }. Special names: 'remove' (unequip; default
-- priority -100), 'displaced' (hold the slot empty without a packet),
-- 'ignore' (drop the slot from the plan entirely -- callers see nil).
function M.normalizeEntry(v)
    local e = nil;
    if type(v) == 'string' then
        e = { Name = string.lower(v) };
    elseif type(v) == 'table' then
        e = {};
        for k, val in pairs(v) do
            if k == 'Name' and type(val) == 'string' then
                e.Name = string.lower(val);
            elseif k == 'Augment' then
                e.Augment = val;
            elseif k == 'Bag' then
                if type(val) == 'string' then
                    e.Bag = M.CONTAINERS[val];
                elseif type(val) == 'number' then
                    e.Bag = val;
                end
            elseif k == 'Priority' and type(val) == 'number' then
                e.Priority = val;
            elseif k == 'AugPath' then
                e.AugPath = val;
            elseif k == 'AugRank' then
                e.AugRank = val;
            elseif k == 'AugTrial' then
                e.AugTrial = val;
            end
        end
    else
        return nil;
    end
    if type(e.Name) ~= 'string' then return nil; end

    if e.Name == 'ignore' then return nil; end
    if e.Name == 'displaced' then
        e.Index = -1;
    elseif e.Name == 'remove' then
        e.Index = 0;
        if e.Priority == nil then e.Priority = -100; end
    end
    if e.Priority == nil then e.Priority = 0; end
    return e;
end

-- ---------------------------------------------------------------------------
-- matching predicates (CheckAugments / CheckResource / CheckEquipTable parity)
-- ---------------------------------------------------------------------------

-- Does a parsed augment satisfy an entry's augment pins? `augment` may be nil
-- (unaugmented item): pins then fail, absent pins pass.
function M.checkAugments(entry, augment)
    local aug = augment or {};
    if entry.AugPath ~= nil and aug.Path ~= entry.AugPath then return false; end
    if entry.AugRank ~= nil and aug.Rank ~= entry.AugRank then return false; end
    if entry.AugTrial ~= nil and aug.Trial ~= entry.AugTrial then return false; end
    if entry.Augment ~= nil then
        local wants;
        if type(entry.Augment) == 'string' then wants = { entry.Augment };
        elseif type(entry.Augment) == 'table' then wants = entry.Augment;
        else return false; end
        for _, want in pairs(wants) do
            local found = false;
            if type(aug.Augs) == 'table' then
                for _, have in pairs(aug.Augs) do
                    if type(have) == 'table' and have.String == want then found = true; break; end
                end
            end
            if not found then return false; end
        end
    end
    return true;
end

-- Can the player equip this item at all (equippable flag + level + job)?
function M.checkUsable(item, job, level)
    if item == nil then return false; end
    if not bitSet(item.ResFlags, 11) then return false; end   -- 0x800 = equippable
    if type(item.Level) == 'number' and level < item.Level then return false; end
    if not bitSet(item.Jobs, job) then return false; end      -- LAC: Jobs & 2^job
    return true;
end

-- Does a WORN item satisfy an entry (worn view: no slot/level gate -- it is
-- already on)? Mirrors LAC CheckItemMatch, including empty-slot-vs-remove.
function M.wornMatches(entry, item, job, level)
    if item == nil or item.Id == nil or item.Id == 0 then
        return entry.Name == 'remove';
    end
    if not M.checkUsable(item, job, level) then return false; end
    if entry.Name ~= item.Name then return false; end
    if entry.Bag ~= nil and entry.Bag ~= item.Container then return false; end
    return M.checkAugments(entry, item.augment);
end

-- ---------------------------------------------------------------------------
-- the resolver
-- ---------------------------------------------------------------------------

-- Resolve a set against a snapshot into a plan. `set` maps slot id (1..16) OR
-- proper-case slot name to entries (normalizeEntry input shapes). Never
-- mutates its arguments.
function M.planSet(set, snap)
    local plan = { satisfied = false, conflicts = {}, equips = {}, stamps = {} };
    if type(set) ~= 'table' or type(snap) ~= 'table' then
        plan.satisfied = true;
        return plan;
    end
    local disabled   = snap.disabled or {};
    local encumbered = snap.encumbered or {};
    local equipped   = snap.equipped or {};
    local job, level = snap.job or 0, snap.level or 0;

    -- 1) normalize into slot-id keys ('ignore' entries drop here)
    local want = {};
    for k, v in pairs(set) do
        local slot = (type(k) == 'number') and k or M.SLOT_ID[k];
        if slot ~= nil and slot >= 1 and slot <= 16 then
            local e = M.normalizeEntry(v);
            if e ~= nil then want[slot] = e; end
        end
    end

    -- 2) flag the worn view: satisfied entries skip; reserved instances are
    --    untouchable (their slot's entry claims them, or the slot is frozen)
    local worn = {};        -- [slot] = { Container, Index, Reserved }
    for slot = 1, 16 do
        local item = equipped[slot];
        if item ~= nil and item.Id ~= nil and item.Id ~= 0 then
            local w = { Container = item.Container, Index = item.Index, Reserved = false };
            local e = want[slot];
            if e ~= nil then
                if M.wornMatches(e, item, job, level) then
                    e.Index, e.Container, e.Skip = item.Index, item.Container, true;
                    w.Reserved = true;
                elseif encumbered[slot] == true or disabled[slot] == true then
                    w.Reserved = true;
                end
            end
            worn[slot] = w;
        end
    end

    -- all satisfied already? (a remove entry on an occupied slot is NOT)
    local allDone = true;
    for slot, e in pairs(want) do
        if e.Index == nil then allDone = false; break; end
        if e.Index == 0 and worn[slot] ~= nil then allDone = false; break; end
    end
    if allDone then
        plan.satisfied = true;
        return plan;
    end

    -- 3) locate: first-fit over the snapshot's items in scan order. One item
    --    instance visits once, so it can never fill two slots.
    for _, item in ipairs(snap.items or {}) do
        if item.Flags ~= 19 and item.Id ~= nil and item.Id ~= 0
           and (item.Count or 0) > 0 and M.checkUsable(item, job, level) then
            for slot, e in pairs(want) do
                if e.Name == item.Name
                   and e.Index == nil
                   and disabled[slot] ~= true and encumbered[slot] ~= true
                   and not (function()   -- worn AND reserved elsewhere?
                        for _, w in pairs(worn) do
                            if w.Index == item.Index and w.Container == item.Container
                               and w.Reserved == true then return true; end
                        end
                        return false;
                    end)()
                   and bitSet(item.Slots, slot - 1)
                   and (e.Bag == nil or e.Bag == item.Container)
                   and M.checkAugments(e, item.augment) then
                    e.Index, e.Container = item.Index, item.Container;
                    break;   -- this instance is spoken for
                end
            end
        end
    end

    -- 4) order by priority (desc; ties resolve to the lowest slot -- LAC's
    --    1..16 max-scan), dropping satisfied/unresolved entries
    local pending = {};
    for slot, e in pairs(want) do
        if e.Index ~= nil and e.Skip ~= true then
            pending[#pending + 1] = { slot = slot, e = e };
        end
    end
    table.sort(pending, function(a, b)
        if a.e.Priority ~= b.e.Priority then return a.e.Priority > b.e.Priority; end
        return a.slot < b.slot;
    end);

    for _, p in ipairs(pending) do
        local slot, e = p.slot, p.e;
        if e.Index == -1 then
            -- displaced: hold the slot in the trust window, send nothing
            plan.stamps[#plan.stamps + 1] = { Slot = slot - 1, Index = 0, Container = 0 };
        elseif e.Index == 0 then
            -- remove: only when something is worn and the slot is not frozen
            local w = worn[slot];
            if w ~= nil and disabled[slot] ~= true then
                local entry = { Slot = slot - 1, Index = 0, Container = w.Container };
                plan.equips[#plan.equips + 1] = entry;
                plan.stamps[#plan.stamps + 1] = entry;
            end
        else
            local entry = { Slot = slot - 1, Index = e.Index, Container = e.Container };
            plan.equips[#plan.equips + 1] = entry;
            plan.stamps[#plan.stamps + 1] = entry;
        end
    end

    -- 5) conflicts: a claimed instance worn in another (unreserved) slot must
    --    leave that slot first
    for _, eq in ipairs(plan.equips) do
        if eq.Index ~= 0 then
            for slot, w in pairs(worn) do
                if w.Index == eq.Index and w.Container == eq.Container
                   and w.Reserved == false and (slot - 1) ~= eq.Slot then
                    plan.conflicts[#plan.conflicts + 1] = { Slot = slot - 1, Container = w.Container };
                end
            end
        end
    end

    plan.satisfied = (#plan.equips == 0 and #plan.conflicts == 0 and #plan.stamps == 0);
    return plan;
end

-- ---------------------------------------------------------------------------
-- packet builders (byte-table parity with LuaAshitacast)
-- ---------------------------------------------------------------------------

-- 0x050 equip request: one slot. Bytes 1..4 are the header Ashita fills.
function M.build0x50(index, slot0, container)
    local p = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    p[5] = index;
    p[6] = slot0;
    p[7] = container;
    return p;
end

function M.buildUnequip0x50(slot0, container)
    return M.build0x50(0, slot0, container);
end

-- 0x051 equipset: up to 16 slots in one packet. [5] = count; entry i (1-based)
-- lands at offset 4 + i*4 + 1 as Index, Slot, Container.
function M.build0x51(equips)
    local p = {};
    for i = 1, 72 do p[i] = 0x00; end
    local count = 0;
    for _, eq in ipairs(equips or {}) do
        count = count + 1;
        local off = 4 + (count * 4) + 1;
        p[off]     = eq.Index;
        p[off + 1] = eq.Slot;
        p[off + 2] = eq.Container;
        p[5] = count;
        if count >= 16 then break; end
    end
    return p;
end

-- Which packet shape a plan should ride: LAC's rule -- explicit styles win;
-- 'auto' sends singles under 9 pieces, the equipset from 9 up.
function M.chooseStyle(nEquips, style)
    if style == 'set' then return 'set'; end
    if style == 'single' then return 'single'; end
    if nEquips < 9 then return 'single'; end
    return 'set';
end

return M;
