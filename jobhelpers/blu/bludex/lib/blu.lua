--[[
    bludex/lib/blu.lua -- the in-game Blue Magic layer: read the live set, the
    live set-point budget, and set/unset spells via the client's own packet
    machinery.

    Ported from the `blusets` addon by atom0s / Ashita Development Team
    (GPL-3), with gratitude. The signature scans, the 0x102 packet layout and
    the safe-mode approach are theirs; this port wraps them nil-safe (a failed
    signature degrades a feature, never crashes the addon) and speaks REAL
    spell ids (512+) at the API surface.

    WHY the budget comes from here and not from data: CatsEyeXI computes total
    blue magic points from level + merits (+2/merit Assimilation, custom) +
    job-point gifts + spells learned (custom). The CLIENT already holds the
    result -- reading it live can never desync. data/traits.lua rules are the
    display fallback only.
]]--

require('common');
local chat = require('chat');

local _fok, ffi = pcall(require, 'ffi');

local M = {
    mode  = 'safe',      -- 'safe' = the client's own send function (it paces
                         -- itself to ~1/s); 'fast' = hand-injected packets,
                         -- delay honored below 1s (blusets' fast mode)
    delay = 1.1,         -- seconds between packets when applying spells
};

local sig = { offset = nil, points = nil, equipex = nil };

if _fok and ffi ~= nil then
    pcall(function()
        ffi.cdef[[
            typedef uint8_t (__cdecl *bludex_equipex_t)(uint8_t isSubJob, uint16_t jobType, uint16_t index, uint8_t id);

            /* Packet 0x0102 - Extended Equip (client to server), BLU layout.
               One spell per packet by protocol: Spells[] marks the slot being
               touched, SpellId says set (raw id) or unset (0). (blusets) */
            typedef struct bludex_equipex_c2s_t {
                uint16_t    IdSize;
                uint16_t    Sync;
                uint8_t     SpellId;
                uint8_t     Unknown0000;
                uint16_t    Unknown0001;
                uint8_t     JobId;
                uint8_t     IsSubJob;
                uint16_t    Unknown0002;
                uint8_t     Spells[20];
                uint8_t     Unknown0003[132];
            } bludex_equipex_c2s_t;
        ]];
    end);
    -- Signatures carried verbatim from blusets (sibling addons are the
    -- signature authority; these are field-proven on this client).
    pcall(function()
        local p = ashita.memory.find('FFXiMain.dll', 0, 'C1E1032BC8B0018D????????????B9????????F3A55F5E5B', 10, 0);
        if p ~= nil and p ~= 0 then sig.offset = ffi.cast('uint32_t*', p); end
    end);
    pcall(function()
        local p = ashita.memory.find('FFXiMain.dll', 0, 'A1????????33C98A4E5E33D28A565D5F5E8950148948185B83C414C20400', 1, 0);
        if p ~= nil and p ~= 0 then sig.points = ffi.cast('uint8_t***', p); end
    end);
    pcall(function()
        local p = ashita.memory.find('FFXiMain.dll', 0, '8B0D????????81EC9C00000085C95356570F??????????8B', 0, 0);
        if p ~= nil and p ~= 0 then sig.equipex = ffi.cast('bludex_equipex_t', p); end
    end);
end

local function player()
    return AshitaCore:GetMemoryManager():GetPlayer();
end

function M.isBluMain()
    local ok, r = pcall(function() return player():GetMainJob() == 16; end);
    return ok and r or false;
end

function M.isBluSub()
    local ok, r = pcall(function() return player():GetSubJob() == 16; end);
    return ok and r or false;
end

function M.onBlu()
    return M.isBluMain() or M.isBluSub();
end

function M.hasSpell(id)
    local ok, r = pcall(function() return player():HasSpell(id); end);
    return ok and r or false;
end

-- Live budget from client memory. Returns max, spent -- or nil, nil when the
-- signature is unavailable (caller falls back to data rules / settings).
function M.points()
    if sig.points == nil then return nil, nil; end
    local ok, max, spent = pcall(function()
        return sig.points[0][0][0x18], sig.points[0][0][0x14];
    end);
    if not ok or max == nil or max <= 0 then return nil, nil; end
    return max, spent;
end

local function bufferPtr()
    local ptr = ashita.memory.read_uint32(AshitaCore:GetPointerManager():Get('inventory'));
    if ptr == 0 then return 0; end
    ptr = ashita.memory.read_uint32(ptr);
    if ptr == 0 then return 0; end
    return ptr + sig.offset[0] + (M.isBluMain() and 0x00 or 0x9C);
end

-- The 20 live slot bytes as the CLIENT stores them (real id - 512), 1-based;
-- nil when the buffer is unreachable.
local function rawSlots()
    if sig.offset == nil then return nil; end
    local ok, out = pcall(function()
        local ptr = ashita.memory.read_uint32(AshitaCore:GetPointerManager():Get('inventory'));
        if ptr == 0 then return nil; end
        ptr = ashita.memory.read_uint32(ptr);
        if ptr == 0 then return nil; end
        local base = ptr + sig.offset[0] + (M.isBluMain() and 0x04 or 0xA0);
        return ashita.memory.read_array(base, 0x14);
    end);
    return ok and out or nil;
end

-- The 20 live slots as REAL spell ids (0 = empty). Empty table when
-- unavailable.
function M.currentSet()
    local raw = rawSlots();
    if raw == nil then return {}; end
    local set = {};
    for i = 1, 20 do
        local b = raw[i] or 0;
        set[i] = (b ~= 0) and (b + 512) or 0;
    end
    return set;
end

-- ---------------------------------------------------------------------------
-- debug surface (/bludex debug): which signatures resolved, and the raw
-- points read WITHOUT the max>0 gate -- in the field this distinguishes
-- 'signature missing' from 'struct reads zero' (the private-server quirk
-- where job data stays stale until the native menus touch it).
-- ---------------------------------------------------------------------------
function M.sigStatus()
    return {
        offset  = sig.offset ~= nil,
        points  = sig.points ~= nil,
        equipex = sig.equipex ~= nil,
    };
end

function M.pointsRaw()
    if sig.points == nil then return false, nil, nil; end
    local ok, max, spent = pcall(function()
        return tonumber(sig.points[0][0][0x18]), tonumber(sig.points[0][0][0x14]);
    end);
    if not ok then return false, nil, nil; end
    return true, max, spent;
end

-- ---------------------------------------------------------------------------
-- the points nudge: on LSB-family servers (CatsEyeXI) the client's BLU
-- structs stay stale after login until the native status/equip/Set Spells
-- menus fire a C2S 0x061 player-info request -- the server answers with the
-- job-extra battery that fills them. Injecting the same request wakes the
-- struct without opening a menu. 0x061 is a read-only "resend my stats" ask.
-- ---------------------------------------------------------------------------
local nudge = { last = 0, tries = 0 };

function M.requestJobData()
    local ok = pcall(function()
        -- full packet bytes incl. header: id 0x61, size 0x08 (byte1 = size/2)
        AshitaCore:GetPacketManager():AddOutgoingPacket(0x061,
            { 0x61, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
    end);
    return ok;
end

-- Call freely (the header does, every frame it shows 'reading...'): fires
-- only on BLU, only when the signature is alive but the struct reads zero,
-- at most 3 times, 10s apart. A successful read re-arms it.
function M.nudgePoints()
    if not M.onBlu() then return; end
    local okRaw, max = M.pointsRaw();
    if not okRaw then return; end                    -- signature dead: no packet can help
    if max ~= nil and max > 0 then nudge.tries = 0; return; end
    if nudge.tries >= 3 then return; end
    local now = os.clock();
    if now - nudge.last < 10 then return; end
    nudge.last = now;
    nudge.tries = nudge.tries + 1;
    M.requestJobData();
end

-- One refresh on window open (field-confirmed cure for the stale structs):
-- cheap freshness for the points read and the live set.
function M.refreshIfOnBlu()
    if M.onBlu() then M.requestJobData(); end
end

-- Fire a refresh whenever the job identity changes -- level up/down or a
-- main/sub swap invalidates the BLU structs the same way login does. Called
-- once per frame while the window is open; the compare makes it a no-op
-- almost always. First sight only sets the baseline (the on-open refresh
-- already covered that moment).
local watched = nil;
function M.watchJobState()
    local ok, cur = pcall(function()
        local p = player();
        return ('%d.%d/%d.%d'):format(p:GetMainJob(), p:GetMainJobLevel(),
            p:GetSubJob(), p:GetSubJobLevel());
    end);
    if not ok or cur == nil then return false; end
    if watched == nil then watched = cur; return false; end
    if cur ~= watched then
        watched = cur;
        if M.onBlu() then M.requestJobData(); end
        return true;
    end
    return false;
end

function M.canApply()
    return sig.equipex ~= nil and sig.offset ~= nil and M.onBlu();
end

local function msg(s)
    print(chat.header('bludex'):append(chat.message(s)));
end

-- The CAST LOCK: setting or unsetting any spell locks Blue Magic casting
-- for about a minute (the game's own rule). Every 0x102 we send restamps
-- the clock, so the countdown runs from the LAST packet of an apply.
-- castReadyIn() -> whole seconds remaining, 0 when casting is free.
--
-- Each stamp also arms a deferred chat line for lock-end -- a task, not a
-- UI poll, so it fires with the window closed and whatever gates the host's
-- tick. Only the LATEST stamp's task speaks (generation check); the task
-- owns clearing the stamp, castReadyIn only reports.
M.castLock = 60;                 -- seconds; adjust here if CEXI differs
local lastChangeAt = nil;
local lockGen = 0;

local function stampSetChange()
    lastChangeAt = os.clock();
    lockGen = lockGen + 1;
    local gen = lockGen;
    pcall(function()
        ashita.tasks.once(M.castLock, function()
            if gen ~= lockGen or lastChangeAt == nil then return; end
            lastChangeAt = nil;
            msg('Blue Magic is castable again.');
        end);
    end);
end

function M.castReadyIn()
    if lastChangeAt == nil then return 0; end
    local rem = M.castLock - (os.clock() - lastChangeAt);
    if rem <= 0 then return 0; end
    return math.ceil(rem);
end

-- The per-packet pause. Safe mode is paced by the client's own limiter
-- anyway, so anything under 1.0 buys nothing there; fast mode honors the
-- configured delay down to 0.2s.
local function stepDelay()
    if M.mode == 'fast' then return math.max(M.delay, 0.2); end
    return math.max(M.delay, 1.0);
end

-- fast mode: hand-build the 0x102 and inject it, bypassing the client's
-- internal send pacing (blusets' 'fast' mode). 0x5302 = id 0x102, size 0xA4.
local function injectSetPacket(slot, byte)
    local eqex = ffi.new('bludex_equipex_c2s_t', {
        IdSize = 0x5302, JobId = 0x10, IsSubJob = M.isBluSub() and 1 or 0,
    });
    if byte == 0 then
        local raw = rawSlots();
        assert(raw ~= nil, 'blu buffer unreachable');
        eqex.SpellId = 0;
        eqex.Spells[slot - 1] = raw[slot] or 0;   -- unset names the spell it removes
    else
        eqex.SpellId = byte;
        eqex.Spells[slot - 1] = byte;
    end
    local packet = ffi.string(eqex, ffi.sizeof('bludex_equipex_c2s_t')):totable();
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x102, packet);
end

-- Set one slot (1-20) to a REAL spell id, or 0 to unset. Fast mode falls
-- back to the safe client call on any injection failure.
function M.setSlot(slot, realId)
    if not M.canApply() then return false; end
    if slot < 1 or slot > 20 then return false; end
    local byte = 0;
    if realId ~= nil and realId ~= 0 then
        if realId < 513 or realId > 767 then return false; end
        byte = realId - 512;
    end
    if M.mode == 'fast' and pcall(injectSetPacket, slot, byte) then
        stampSetChange();
        return true;
    end
    local ok = pcall(function()
        sig.equipex(M.isBluMain() and 0 or 1, 0x1000, slot - 1, byte);
    end);
    if ok then stampSetChange(); end
    return ok;
end

-- Reset all set spells. Fast mode injects the reset (SpellId 0, the current
-- slots named in Spells[]); safe mode queues via the client packet queue.
function M.resetAll()
    if not M.canApply() then return false; end
    if M.mode == 'fast' then
        local okf = pcall(function()
            local raw = rawSlots();
            assert(raw ~= nil, 'blu buffer unreachable');
            local eqex = ffi.new('bludex_equipex_c2s_t', {
                IdSize = 0x5302, JobId = 0x10, IsSubJob = M.isBluSub() and 1 or 0,
            });
            for i = 1, 20 do eqex.Spells[i - 1] = raw[i] or 0; end
            local packet = ffi.string(eqex, ffi.sizeof('bludex_equipex_c2s_t')):totable();
            AshitaCore:GetPacketManager():AddOutgoingPacket(0x102, packet);
        end);
        if okf then stampSetChange(); return true; end
    end
    local ok = pcall(function()
        AshitaCore:GetPacketManager():QueuePacket(0x102, 0xA4, 0x00, 0x00, 0x00, function(ptr)
            local p = ffi.cast('uint8_t*', ptr);
            ffi.fill(p + 0x04, 0xA0);
            ffi.copy(p + 0x08, ffi.cast('uint8_t*', bufferPtr()), 0x9C);
        end);
    end);
    if ok then stampSetChange(); end
    return ok;
end

-- Sort spell ids ascending by BLU spell level (unknown levels last). THE
-- LEVEL LAW: a level-down strips set spells the lowered level cannot hold,
-- and a synced-down apply gets its tail rejected -- so castable spells must
-- be SENT first and SIT in the lowest slots, where they survive.
local function byLevel(ids, book)
    local out = {};
    for _, id in ipairs(ids) do out[#out + 1] = id; end
    if book and book.spells then
        table.sort(out, function(a, b)
            local la = (book.spells[a] and book.spells[a].level) or 999;
            local lb = (book.spells[b] and book.spells[b].level) or 999;
            if la ~= lb then return la < lb; end
            return a < b;
        end);
    end
    return out;
end

-- Position-independent plan against the live set: targets are matched by
-- spell IDENTITY, not slot -- the same spells in any layout cost zero
-- packets. Missing spells are paired lowest-level-first with the lowest
-- open slots. removeExtras=false never unsets anything (the restore path).
-- Returns nil when the live set is unreadable.
local function planDiff(ids, book, removeExtras)
    local live = M.currentSet();
    if #live ~= 20 then return nil; end
    local want = {};
    for slot = 1, 20 do
        local id = ids[slot] or 0;
        if id ~= 0 and M.hasSpell(id) then want[id] = true; end
    end
    local liveIds, removes, empties = {}, {}, {};
    for slot = 1, 20 do
        local id = live[slot] or 0;
        if id == 0 then
            empties[#empties + 1] = slot;
        elseif want[id] or not removeExtras then
            liveIds[id] = true;
        else
            removes[#removes + 1] = slot;
            empties[#empties + 1] = slot;   -- open once the unset lands
        end
    end
    local missing, kept = {}, 0;
    for id in pairs(want) do
        if liveIds[id] then kept = kept + 1; else missing[#missing + 1] = id; end
    end
    missing = byLevel(missing, book);
    local adds, noSlot = {}, 0;
    for i, id in ipairs(missing) do
        if empties[i] then adds[#adds + 1] = { slot = empties[i], id = id };
        else noSlot = noSlot + 1; end
    end
    return { removes = removes, adds = adds, kept = kept, noSlot = noSlot };
end

-- Apply a whole set (array of 20 real ids / 0s): reset, then set each spell
-- lowest level first with a delay between packets. Skips unlearned spells.
-- Runs as a background task; onDone() fires from that task when finished.
M.applying = false;
function M.applySet(ids, book, onDone)
    if not M.canApply() then
        msg('Cannot apply: BLU is not your main or sub job (or memory signatures failed).');
        return false;
    end
    if M.applying then
        msg('Already applying a set; wait for it to finish.');
        return false;
    end
    local delay = stepDelay();
    local pick = {};
    for slot = 1, 20 do
        local id = ids[slot] or 0;
        if id ~= 0 then
            if M.hasSpell(id) then
                pick[#pick + 1] = id;
            else
                local sp = AshitaCore:GetResourceManager():GetSpellById(id);
                msg(('Skipping %s: not learned.'):format(sp and sp.Name[1] or tostring(id)));
            end
        end
    end
    local list = {};
    for i, id in ipairs(byLevel(pick, book)) do
        list[#list + 1] = { slot = i, id = id };
    end
    M.applying = true;
    ashita.tasks.once(1, function()
        M.resetAll();
        coroutine.sleep(delay);
        for _, e in ipairs(list) do
            M.setSlot(e.slot, e.id);
            coroutine.sleep(delay);
        end
        M.applying = false;
        msg(('Set applied (%d spells, lowest level first). Spells castable in ~%ds.'):format(
            #list, M.castLock));
        if onDone then pcall(onDone); end
    end);
    return true;
end

-- Apply only the DIFFERENCE between the live set and the target. Removals
-- go first (frees slots, points, and any spell moving between slots -- the
-- client refuses a spell set twice), then adds, lowest level first into the
-- lowest slots. Falls back to applySet when the live set cannot be read.
function M.applyDiff(ids, book, onDone)
    if not M.canApply() then
        msg('Cannot apply: BLU is not your main or sub job (or memory signatures failed).');
        return false;
    end
    if M.applying then
        msg('Already applying a set; wait for it to finish.');
        return false;
    end
    for slot = 1, 20 do
        local id = ids[slot] or 0;
        if id ~= 0 and not M.hasSpell(id) then
            local sp = AshitaCore:GetResourceManager():GetSpellById(id);
            msg(('Skipping %s: not learned.'):format(sp and sp.Name[1] or tostring(id)));
        end
    end
    local plan = planDiff(ids, book, true);
    if plan == nil then
        msg('Could not read the live set - doing a full reset + apply instead.');
        return M.applySet(ids, book, onDone);
    end
    if #plan.removes == 0 and #plan.adds == 0 then
        msg('The live set already matches - nothing to send.');
        if onDone then pcall(onDone); end
        return true;
    end
    local delay = stepDelay();
    M.applying = true;
    ashita.tasks.once(1, function()
        for _, slot in ipairs(plan.removes) do
            M.setSlot(slot, 0);
            coroutine.sleep(delay);
        end
        for _, e in ipairs(plan.adds) do
            M.setSlot(e.slot, e.id);
            coroutine.sleep(delay);
        end
        M.applying = false;
        msg(('Set updated: %d added (lowest level first), %d removed, %d kept. Spells castable in ~%ds.'):format(
            #plan.adds, #plan.removes, plan.kept, M.castLock));
        if onDone then pcall(onDone); end
    end);
    return true;
end

-- The auto-restore path: put back whatever a level change stripped from the
-- last-applied set. ADDS ONLY -- never unsets, so anything set by hand in
-- the native menu survives. Quiet when nothing is missing (this fires after
-- every level change). Ends by re-reading the live set and reporting how
-- many actually stuck -- a still-synced level rejects the tail server-side.
function M.restoreMissing(ids, book, onDone)
    if not M.canApply() or M.applying then return false; end
    local plan = planDiff(ids, book, false);
    if plan == nil or #plan.adds == 0 then return false; end
    local delay = stepDelay();
    M.applying = true;
    msg(('Level change: restoring %d spell(s), lowest level first.'):format(#plan.adds));
    ashita.tasks.once(1, function()
        for _, e in ipairs(plan.adds) do
            M.setSlot(e.slot, e.id);
            coroutine.sleep(delay);
        end
        coroutine.sleep(0.5);
        local liveNow, after = {}, M.currentSet();
        if #after == 20 then
            for i = 1, 20 do if after[i] ~= 0 then liveNow[after[i]] = true; end end
        end
        local stuck = 0;
        for _, e in ipairs(plan.adds) do if liveNow[e.id] then stuck = stuck + 1; end end
        M.applying = false;
        if #after == 20 and stuck < #plan.adds then
            msg(('Restored %d of %d - the rest need a higher level (or a free slot). Spells castable in ~%ds.'):format(
                stuck, #plan.adds, M.castLock));
        else
            msg(('Restored %d spell(s). Spells castable in ~%ds.'):format(#plan.adds, M.castLock));
        end
        if onDone then pcall(onDone); end
    end);
    return true;
end

return M;
