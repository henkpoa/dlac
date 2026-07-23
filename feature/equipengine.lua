--[[
    dlac/feature/equipengine.lua -- the native equip pipeline, part 2: action
    interception + the equip state machine. feature/native-engine: dlac
    absorbing LuaAshitacast.

    THE TIMING SERVICE (LuaAshitacast packethandlers.lua is the reference --
    this is the part of LAC that was never optional): the client's outgoing
    action packets (0x01A spell/WS/ability/ranged, 0x037 item use) are BLOCKED,
    the precast dispatch fires and its gear goes out FIRST, the action packet
    is re-injected behind it, and the midcast dispatch follows -- so precast
    gear is on when the action leaves and midcast gear lands after. Completion
    timers (cast time, fast cast, snapshot, fixed delays) + the incoming 0x028
    action stream decide when the player is idle again and Default resumes.

    LAYERING: the PURE half (byte readers, chunk parser, the action ROUTE
    table, completion math, 0x028 decode, augment header decode) is offline-
    tested (EQE* in tests\run_tests.lua). The Ashita-facing half (snapshot
    building, packet send/inject, event registration) guards every touch and
    only ACTS when the native-engine flag is on (profiles.nativeMode) -- flag
    off, every hook returns immediately and LuaAshitacast stays the engine.

    THE DISPATCH SEAM: this module does not know about triggers. It calls
    M.onEvent('<Handler>', ctx) at each timing point; the native dispatch
    backend (dispatch.lua, wired separately) evaluates rules and feeds gear
    back through M.equipSet(set) into the per-event buffer; bufferFlush
    resolves ONCE through gear\equipcore and sends. That mirrors LAC's
    ClearBuffer -> Handle* -> ProcessBuffer exactly -- overlays merge in the
    buffer, later writes win per slot.

    ADDING A DISPATCH POINT LATER (the reason this is table-driven): a new
    action category -- or a wholly new signal -- becomes one ACTION_ROUTES row
    (or one explicit M.fireEvent call site), and trigger files can carry the
    new handler name with no pipeline surgery. The handler-name vocabulary
    lives in the trigger files; nothing here enumerates it.

    COEXISTENCE TRIPWIRE: two interceptors on the same client is a feedback
    hazard (both block + re-inject 0x01A). Every packet this module injects is
    fingerprinted; a FOREIGN injected action packet matching a fresh
    fingerprint of ours means another engine (LuaAshitacast) re-emitted it --
    interception disarms for the session and says so, loudly. Foreign injected
    actions that are NOT echoes are treated as new actions, LAC-parity.
]]--

local M = {};

local _eqok, eqc = pcall(require, 'dlac\\gear\\equipcore');
_eqok = _eqok and type(eqc) == 'table';

-- ---------------------------------------------------------------------------
-- settings (LuaAshitacast timing defaults, verbatim)
-- ---------------------------------------------------------------------------

M.SETTINGS = {
    AllowSyncEquip   = true,
    PetskillDelay    = 4.0,
    WeaponskillDelay = 3.0,
    AbilityDelay     = 2.5,
    SpellOffset      = 1.0,
    RangedBase       = 10.0,
    RangedOffset     = 0.5,
    ItemBase         = 8,
    ItemOffset       = 1.0,
    FastCast         = 0,
    Snapshot         = 0,
    EquipBags        = nil,   -- nil = equipcore.DEFAULT_EQUIP_BAGS
};

-- ---------------------------------------------------------------------------
-- pure byte readers (little-endian bitstream, the FFXI packing)
-- ---------------------------------------------------------------------------

-- Bits [bitOff, bitOff+nbits) of a raw byte string, LSB-first within bytes,
-- starting at 0-based byteOff. Mirrors ashita.bits.unpack_be as the game data
-- actually uses it. Returns 0 past the end (short packets read as zeros).
function M.bitsAt(str, byteOff, bitOff, nbits)
    local v, place = 0, 1;
    for i = 0, nbits - 1 do
        local bitpos = bitOff + i;
        local byte = string.byte(str, byteOff + math.floor(bitpos / 8) + 1) or 0;
        local bit = math.floor(byte / (2 ^ (bitpos % 8))) % 2;
        v = v + bit * place;
        place = place * 2;
    end
    return v;
end

function M.u16at(str, byteOff)   -- 0-based offset
    local a = string.byte(str, byteOff + 1) or 0;
    local b = string.byte(str, byteOff + 2) or 0;
    return a + b * 256;
end

function M.u32at(str, byteOff)
    return M.u16at(str, byteOff) + M.u16at(str, byteOff + 2) * 65536;
end

-- An outgoing chunk into its packets: { { id, size, off } ... } (off 0-based).
-- FFXI header u16: id = low 9 bits, size = next 7 bits, in 4-byte units.
function M.parseChunk(str)
    local out, off, n = {}, 0, #str;
    while off < n do
        local w = M.u16at(str, off);
        local id = w % 512;
        local size = (math.floor(w / 512) % 128) * 4;
        if size <= 0 then break; end   -- torn header: stop, never spin
        out[#out + 1] = { id = id, size = size, off = off };
        off = off + size;
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- the action routes -- THE dispatch-point table
-- ---------------------------------------------------------------------------

-- One row per handled outgoing 0x01A category. `pre` fires before the action
-- re-injects (its gear must beat the action out the door), `mid` after.
-- Styles are LAC's: precast wants one 0x051 ('set'), midcast singles.
-- A future dispatch point = a new row (or a fireEvent call site elsewhere).
M.ACTION_ROUTES = {
    [0x03] = { type = 'Spell',       pre = 'Precast',     preStyle = 'set',
               mid = 'Midcast',      midStyle = 'single', timing = 'cast' },
    [0x07] = { type = 'Weaponskill', pre = 'Weaponskill', preStyle = 'auto',
               timing = 'fixed',     delayKey = 'WeaponskillDelay' },
    [0x09] = { type = 'Ability',     pre = 'Ability',     preStyle = 'auto',
               timing = 'fixed',     delayKey = 'AbilityDelay' },
    [0x10] = { type = 'Ranged',      pre = 'Preshot',     preStyle = 'set',
               mid = 'Midshot',      midStyle = 'single', timing = 'ranged' },
};

function M.routeOf(category) return M.ACTION_ROUTES[category]; end

-- Action-packet fields (outgoing 0x01A): target index, category, action id.
function M.parseAction(str)
    return {
        target   = M.u16at(str, 0x08),
        category = M.u16at(str, 0x0A),
        actionId = M.u16at(str, 0x0C),
    };
end

-- Item-use packet fields (outgoing 0x037).
function M.parseItemUse(str)
    return {
        target    = M.u16at(str, 0x0C),
        itemIndex = M.bitsAt(str, 0x0E, 0, 8),
        container = M.bitsAt(str, 0x10, 0, 8),
    };
end

-- Completion clock for an action: when Default may resume if no 0x028 says
-- otherwise first. castTime is the resource's raw CastTime (quarter-seconds).
function M.completionOf(route, castTime, settings, now)
    local s = settings or M.SETTINGS;
    if route == nil then return now; end
    if route.timing == 'cast' then
        local base = (castTime or 0) * 0.25;
        base = (base * (100 - (s.FastCast or 0))) / 100;
        return now + base + (s.SpellOffset or 0);
    elseif route.timing == 'ranged' then
        local base = ((s.RangedBase or 0) * (100 - (s.Snapshot or 0))) / 100;
        return now + base + (s.RangedOffset or 0);
    elseif route.timing == 'fixed' then
        return now + (s[route.delayKey] or 0);
    end
    return now;
end

function M.itemCompletionOf(castTime, settings, now)
    local s = settings or M.SETTINGS;
    if castTime ~= nil then
        return now + castTime * 0.25 + (s.ItemOffset or 0);
    end
    return now + (s.ItemBase or 0) + (s.ItemOffset or 0);
end

-- ---------------------------------------------------------------------------
-- incoming 0x028 (action) decode -- action/pet completion + interrupts
-- ---------------------------------------------------------------------------

M.ACTION_COMPLETE_TYPES     = { [2]=true, [3]=true, [4]=true, [5]=true, [6]=true, [14]=true, [15]=true };
M.PET_ACTION_COMPLETE_TYPES = { [4]=true, [11]=true, [13]=true };

-- The fields the state machine consumes. `interrupted` decodes LAC's magic:
-- ranged/magic types 8 and 12 carry param 28787 when the action was cut.
function M.parse0x28(str)
    local userId = M.u32at(str, 0x05);
    local actionType = M.bitsAt(str, 10, 2, 4);
    local interrupted = false;
    if actionType == 8 or actionType == 12 then
        interrupted = (M.bitsAt(str, 10, 6, 16) == 28787);
    end
    return { userId = userId, actionType = actionType, interrupted = interrupted };
end

-- ---------------------------------------------------------------------------
-- augment header decode (pure; the pin fields planSet matches on)
-- ---------------------------------------------------------------------------

M.AUGMENT_PATHS = { [0] = 'A', [1] = 'B', [2] = 'C', [3] = 'D' };

-- Path / Rank / Trial out of an item's Extra bytes (LAC data.GetAugment's
-- header logic; the per-stat Augs strings need the augment resource tables and
-- ride in via M.augmentStringsOf below). nil for unaugmented items.
function M.parseAugmentHeader(extra)
    if type(extra) ~= 'string' or #extra < 2 then return nil; end
    local augType = string.byte(extra, 1);
    if augType ~= 2 and augType ~= 3 then return nil; end
    local augFlag = string.byte(extra, 2);
    local aug = {};
    if (math.floor(augFlag / 0x20) % 2) == 1 then
        -- Delve style
        aug.Type = 'Delve';
        aug.Path = M.AUGMENT_PATHS[M.bitsAt(extra, 0, 16, 2)];
        aug.Rank = M.bitsAt(extra, 0, 18, 4);
        return aug;
    end
    if augFlag == 131 then
        -- Dynamis style
        aug.Type = 'Dynamis';
        aug.Path = M.AUGMENT_PATHS[M.bitsAt(extra, 0, 32, 2)];
        aug.Rank = M.bitsAt(extra, 0, 50, 5);
        return aug;
    end
    if (math.floor(augFlag / 0x08) % 2) == 1 then return nil; end   -- synth shields
    if (math.floor(augFlag / 0x80) % 2) == 1 then return nil; end   -- Evolith
    if (math.floor(augFlag / 0x40) % 2) == 1 then
        -- Magian trial
        aug.Type = 'Magian';
        aug.Trial = M.bitsAt(extra, 0, 80, 15);
        return aug;
    end
    aug.Type = 'Oseem';
    return aug;
end

-- Optional richer decode: the addon's augment module can supply the per-stat
-- strings ('STR+5', ...) an Augment pin matches against. Absent, pins on Augs
-- strings simply never match -- the safe direction (a wrong-augment piece is
-- never equipped by mistake).
M.augmentStringsOf = nil;   -- function(item) -> { 'STR+5', ... } | nil

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

M.state = {
    action     = nil,    -- { Type, Resource, Target, Completion, route }
    petAction  = nil,    -- pet timing (0x028-driven)
    encumbered = {},     -- [slot]=true (incoming 0x1B bits)
    disabled   = {},     -- [slot]=true (/dl-level slot disable, future surface)
    tripped    = false,  -- coexistence tripwire fired this session
};

local _trust = {};        -- [slot] = { Item = {..}|nil, Timer = clock }  (0.2s window)
local _buffer = {};       -- per-event equip buffer: [slot] = raw entry
local _injectedFP = {};   -- fingerprints of packets WE injected: fp -> clock
local _lastActionFP = nil;-- resend dedup (the client re-sends 0x01A on lag)

M.onEvent = nil;          -- the dispatch seam: function(handlerName, ctx)
M.say = nil;              -- chat printer (wired by the command surface)

local function say(s)
    if type(M.say) == 'function' then pcall(M.say, s);
    else pcall(print, '[dlac] ' .. s); end
end

-- Native flag, throttled via profiles (the one authority). Tripwire wins.
-- NEVER arms inside LuaAshitacast's Lua state: dispatch.lua is seeded there
-- and requires this module too -- two armed interceptors (one per state) is
-- exactly the double-engine hazard. The addon state is the only home.
local function nativeOn()
    if M.state.tripped then return false; end
    if rawget(_G, 'gFunc') ~= nil then return false; end   -- LAC state: refuse
    local ok, prof = pcall(require, 'dlac\\profiles');
    if not ok or type(prof) ~= 'table' then return false; end
    local ok2, on = pcall(prof.nativeMode);
    return ok2 and on == true;
end
M.nativeOn = nativeOn;

-- ---------------------------------------------------------------------------
-- snapshot building (Ashita-facing)
-- ---------------------------------------------------------------------------

-- The worn view for one slot: the trust window first (packets we just sent
-- outrun the memory view by ~0.2s), then live equipment memory.
local function currentEquip(slot, invMgr, resMgr)
    local t = _trust[slot];
    if t ~= nil then
        if os.clock() < t.Timer then return t.Item; end
        _trust[slot] = nil;
    end
    local item = nil;
    pcall(function()
        local eq = invMgr:GetEquippedItem(slot - 1);
        if eq == nil then return; end
        local index = eq.Index % 256;
        if index == 0 then return; end
        local container = math.floor(eq.Index / 256) % 256;
        local ci = invMgr:GetContainerItem(container, index);
        if ci == nil or ci.Id == 0 or ci.Count == 0 then return; end
        local res = resMgr:GetItemById(ci.Id);
        if res == nil then return; end
        item = {
            Container = container, Index = index, Id = ci.Id,
            Count = ci.Count, Flags = ci.Flags,
            Name = string.lower(res.Name[1] or ''),
            Level = res.Level, Jobs = res.Jobs, Slots = res.Slots,
            ResFlags = res.Flags,
            augment = M.parseAugmentHeader(ci.Extra),
        };
    end);
    return item;
end

-- The worn view for one slot, for OTHER modules (nativedata's GetEquipment):
-- same trust-window-first read the resolver uses.
function M.currentEquipView(slot)
    local item = nil;
    pcall(function()
        local mm = AshitaCore:GetMemoryManager();
        item = currentEquip(slot, mm:GetInventory(), AshitaCore:GetResourceManager());
    end);
    return item;
end

-- A full equipcore snapshot from live memory. `wantNames` (set of lowercased
-- names) prefilters the bag scan -- only names the buffer actually asks for
-- are collected, so a cast never pays for the whole inventory.
local function liveSnapshot(wantNames)
    local snap = { job = 0, level = 0, disabled = M.state.disabled,
                   encumbered = M.state.encumbered, equipped = {}, items = {} };
    local okAll = pcall(function()
        local mm = AshitaCore:GetMemoryManager();
        local invMgr, resMgr = mm:GetInventory(), AshitaCore:GetResourceManager();
        local player = mm:GetPlayer();
        snap.job = player:GetMainJob();
        if M.SETTINGS.AllowSyncEquip then
            snap.level = player:GetJobLevel(snap.job);
        else
            snap.level = player:GetMainJobLevel();
        end
        for slot = 1, 16 do
            snap.equipped[slot] = currentEquip(slot, invMgr, resMgr);
        end
        -- Bag availability: LAC gates wardrobes 3+ behind retail account-flag
        -- sig-scans -- checks its own comments say "do not work on topaz".
        -- CatsEye is Topaz-lineage: an unavailable container reports max 0 and
        -- skips itself, so the scan needs no flag reads here. (If a field
        -- round ever shows an equip FROM a locked wardrobe being refused
        -- server-side, that is where an availability gate goes.)
        local bags = M.SETTINGS.EquipBags or (_eqok and eqc.DEFAULT_EQUIP_BAGS) or {};
        for _, container in ipairs(bags) do
            local max = invMgr:GetContainerCountMax(container);
            for index = 1, max do
                local ci = invMgr:GetContainerItem(container, index);
                if ci ~= nil and ci.Id ~= 0 and ci.Count > 0 then
                    local res = resMgr:GetItemById(ci.Id);
                    if res ~= nil then
                        local nm = string.lower(res.Name[1] or '');
                        if wantNames == nil or wantNames[nm] then
                            snap.items[#snap.items + 1] = {
                                Container = container, Index = index, Id = ci.Id,
                                Count = ci.Count, Flags = ci.Flags,
                                Name = nm, Level = res.Level, Jobs = res.Jobs,
                                Slots = res.Slots, ResFlags = res.Flags,
                                augment = M.parseAugmentHeader(ci.Extra),
                            };
                        end
                    end
                end
            end
        end
    end);
    if not okAll then return nil; end
    return snap;
end

-- ---------------------------------------------------------------------------
-- packet send + fingerprints
-- ---------------------------------------------------------------------------

local function fingerprint(id, str)
    return tostring(id) .. ':' .. str;
end

local function injectPacket(id, bytes)
    pcall(function()
        AshitaCore:GetPacketManager():AddOutgoingPacket(id, bytes);
    end);
end

-- Re-inject a BLOCKED action/item packet (string form -> byte table), leaving
-- a fingerprint so the tripwire can recognize an echo from another engine.
local function reinject(id, str)
    local bytes = {};
    for i = 1, #str do bytes[i] = string.byte(str, i); end
    _injectedFP[fingerprint(id, str)] = os.clock();
    injectPacket(id, bytes);
end

local function stampTrust(stamps, invMgr)
    local now = os.clock();
    for _, s in ipairs(stamps or {}) do
        local entry = { Timer = now + 0.2, Item = nil };
        if s.Index ~= nil and s.Index > 0 then
            pcall(function()
                local ci = invMgr:GetContainerItem(s.Container, s.Index);
                if ci ~= nil and ci.Id ~= 0 then
                    local res = AshitaCore:GetResourceManager():GetItemById(ci.Id);
                    entry.Item = {
                        Container = s.Container, Index = s.Index, Id = ci.Id,
                        Count = ci.Count, Flags = ci.Flags,
                        Name = res ~= nil and string.lower(res.Name[1] or '') or '',
                        Level = res ~= nil and res.Level or 0,
                        Jobs = res ~= nil and res.Jobs or 0,
                        Slots = res ~= nil and res.Slots or 0,
                        ResFlags = res ~= nil and res.Flags or 0,
                        augment = M.parseAugmentHeader(ci.Extra),
                    };
                end
            end);
        end
        _trust[s.Slot + 1] = entry;
    end
end

-- ---------------------------------------------------------------------------
-- the equip buffer (LAC ClearBuffer / EquipItemToBuffer / ProcessBuffer)
-- ---------------------------------------------------------------------------

function M.bufferClear() _buffer = {}; end

-- Headless test seam: a shallow copy of the current buffer (EQE pins the
-- merge semantics through the real equipSet door).
function M._bufferPeek()
    local out = {};
    for k, v in pairs(_buffer) do out[k] = v; end
    return out;
end

-- Merge a set into the current event's buffer. Slot keys are 1..16 or proper
-- case names; later writes win per slot; 'ignore' clears a slot.
function M.equipSet(set)
    if type(set) ~= 'table' or not _eqok then return; end
    for k, v in pairs(set) do
        local slot = (type(k) == 'number') and k or eqc.SLOT_ID[k];
        if slot ~= nil and slot >= 1 and slot <= 16 then
            if type(v) == 'string' and string.lower(v) == 'ignore' then
                _buffer[slot] = nil;
            else
                _buffer[slot] = v;
            end
        end
    end
end

-- Resolve + send the buffered set. One resolution per event, LAC-parity.
function M.bufferFlush(style)
    if not _eqok then return; end
    local any = false;
    for _ in pairs(_buffer) do any = true; break; end
    if not any then return; end

    -- prefilter: only names the buffer references get scanned out of bags
    local wantNames = {};
    for _, v in pairs(_buffer) do
        local e = eqc.normalizeEntry(v);
        if e ~= nil and e.Name ~= 'remove' and e.Name ~= 'displaced' then
            wantNames[e.Name] = true;
        end
    end

    local snap = liveSnapshot(wantNames);
    if snap == nil then return; end
    local plan = eqc.planSet(_buffer, snap);
    M.bufferClear();
    if plan.satisfied then return; end

    local invMgr;
    pcall(function() invMgr = AshitaCore:GetMemoryManager():GetInventory(); end);

    for _, c in ipairs(plan.conflicts) do
        injectPacket(0x50, eqc.buildUnequip0x50(c.Slot, c.Container));
        _trust[c.Slot + 1] = { Timer = os.clock() + 0.2, Item = nil };
    end

    local chosen = eqc.chooseStyle(#plan.equips, style);
    if #plan.equips > 0 then
        if chosen == 'set' then
            injectPacket(0x51, eqc.build0x51(plan.equips));
        else
            for _, eq in ipairs(plan.equips) do
                injectPacket(0x50, eqc.build0x50(eq.Index, eq.Slot, eq.Container));
            end
        end
    end
    if invMgr ~= nil then stampTrust(plan.stamps, invMgr); end
end

-- Fire one dispatch point: clear the buffer, let the backend fill it, flush.
-- This is the call every current AND future dispatch source rides through.
-- Always flushes: unlike LAC's HandleEquipEvent (whose action-in-flight gate
-- guards against stale shim calls), every fireEvent here has a live cause --
-- an action, the Default pump, or a synthesized point like PetAction.
function M.fireEvent(name, style, ctx)
    if type(M.onEvent) ~= 'function' then return; end
    M.bufferClear();
    local ok, err = pcall(M.onEvent, name, ctx);
    if not ok then say('native engine: ' .. tostring(name) .. ' handler error: ' .. tostring(err)); end
    M.bufferFlush(style);
end

-- ---------------------------------------------------------------------------
-- the action pipeline (outgoing)
-- ---------------------------------------------------------------------------

-- Resource lookup for an action id, guarded (nil headless / unknown).
local function actionResource(route, actionId)
    local res = nil;
    pcall(function()
        local rm = AshitaCore:GetResourceManager();
        if route.type == 'Spell' then
            res = rm:GetSpellById(actionId);
        elseif route.type == 'Ability' then
            res = rm:GetAbilityById(actionId + 0x200);
        elseif route.type == 'Weaponskill' then
            res = rm:GetAbilityById(actionId);
        end
    end);
    return res;
end

-- One blocked 0x01A, as a string. Fires pre -> reinject -> mid.
function M.handleAction(str)
    local a = M.parseAction(str);
    local route = M.routeOf(a.category);
    if route == nil then
        reinject(0x1A, str);   -- not ours to manage: pass it through
        return;
    end
    local now = os.clock();
    local res = actionResource(route, a.actionId);
    M.state.action = {
        Type = route.type, route = route, Resource = res, Target = a.target,
        Completion = M.completionOf(route, res ~= nil and res.CastTime or nil, M.SETTINGS, now),
    };
    M.fireEvent(route.pre, route.preStyle, M.state.action);
    reinject(0x1A, str);
    if route.mid ~= nil then
        M.state.action.Completion = M.completionOf(route, res ~= nil and res.CastTime or nil, M.SETTINGS, os.clock());
        M.fireEvent(route.mid, route.midStyle, M.state.action);
    end
end

-- One blocked 0x037 (item use).
function M.handleItemUse(str)
    local u = M.parseItemUse(str);
    local now = os.clock();
    local res, castTime = nil, nil;
    pcall(function()
        local ci = AshitaCore:GetMemoryManager():GetInventory()
            :GetContainerItem(u.container, u.itemIndex);
        if ci ~= nil and ci.Id ~= 0 and ci.Count > 0 then
            res = AshitaCore:GetResourceManager():GetItemById(ci.Id);
            if res ~= nil then castTime = res.CastTime; end
        end
    end);
    M.state.action = {
        Type = 'Item', Resource = res, Target = u.target,
        Completion = M.itemCompletionOf(castTime, M.SETTINGS, now),
    };
    M.fireEvent('Item', 'auto', M.state.action);
    reinject(0x37, str);
end

-- The per-chunk pump: expire actions, walk the chunk's packets for actions
-- (resend-deduped), then run Default when idle. Mirrors HandleOutgoingChunk.
function M.handleOutgoingChunk(e)
    local now = os.clock();
    if M.state.action ~= nil and M.state.action.Completion < now then
        M.state.action = nil;
    end
    if M.state.petAction ~= nil and M.state.petAction.Completion < now then
        M.state.petAction = nil;
    end

    -- prune stale inject fingerprints (tripwire memory, ~2s)
    for fp, at in pairs(_injectedFP) do
        if now - at > 2.0 then _injectedFP[fp] = nil; end
    end

    local chunk = e.chunk_data;
    for _, p in ipairs(M.parseChunk(chunk)) do
        if p.id == 0x1A then
            local body = string.sub(chunk, p.off + 1, p.off + p.size);
            local fp = fingerprint(0x1A, body);
            if fp ~= _lastActionFP then
                _lastActionFP = fp;
                local a = M.parseAction(body);
                if M.routeOf(a.category) ~= nil then
                    M.handleAction(body);
                end
            end
        elseif p.id == 0x37 then
            local body = string.sub(chunk, p.off + 1, p.off + p.size);
            local fp = fingerprint(0x37, body);
            if fp ~= _lastActionFP then
                _lastActionFP = fp;
                M.handleItemUse(body);
            end
        end
    end

    if M.state.action == nil then
        M.fireEvent('Default', 'auto');
    end
end

-- The packet_out event. Blocks handled actions (the chunk pump re-injects),
-- watches for foreign injections (tripwire), runs the pump once per chunk.
function M.handleOutgoing(e)
    if not nativeOn() then return; end

    if e.injected == true then
        if e.id == 0x1A or e.id == 0x37 then
            local body = string.sub(e.data, 1, e.size);
            local fp = fingerprint(e.id, body);
            if _injectedFP[fp] ~= nil then
                _injectedFP[fp] = nil;   -- our own re-injection coming back through
                return;
            end
            -- a foreign injection: another engine echoing us = coexistence trip
            if _lastActionFP == fp then
                M.state.tripped = true;
                say('NATIVE ENGINE DISARMED: another equip engine is re-injecting action packets (LuaAshitacast still loaded?). Unload it (/addon unload luashitacast) and /addon reload dlac.');
                return;
            end
            -- a genuinely new injected action (another addon casting): manage it
            if e.id == 0x1A then
                local a = M.parseAction(body);
                if M.routeOf(a.category) ~= nil then
                    M.handleAction(body);
                    e.blocked = true;
                end
            else
                M.handleItemUse(body);
                e.blocked = true;
            end
        end
        return;
    end

    -- run the chunk pump once per chunk (this packet IS the chunk's head)
    if e.data_raw ~= nil and e.chunk_data_raw ~= nil then
        local head = string.sub(e.chunk_data, 1, e.size);
        if head == string.sub(e.data, 1, e.size) then
            M.handleOutgoingChunk(e);
        end
    end

    -- block what the pump manages; it has already re-injected the keepers
    if e.id == 0x1A then
        local a = M.parseAction(e.data);
        if M.routeOf(a.category) ~= nil then e.blocked = true; end
    elseif e.id == 0x37 then
        e.blocked = true;
    end
end

-- ---------------------------------------------------------------------------
-- incoming (0x028 completion stream, 0x1B encumbrance)
-- ---------------------------------------------------------------------------

-- Pet-action fields out of a 0x028 the PET authored (LAC parity: type 7 =
-- ability/mobskill -- message 43 marks the mobskill -- type 8 = spell).
function M.parse0x28Pet(str)
    return {
        actionId = M.bitsAt(str, 0, 213, 17),
        message  = M.bitsAt(str, 28, 6, 10),
    };
end

function M.handleIncoming(e)
    if not nativeOn() then return; end
    if e.id == 0x028 then
        local a = M.parse0x28(e.data);
        local myId = nil;
        pcall(function()
            myId = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0);
        end);
        if myId ~= nil and a.userId == myId then
            if M.ACTION_COMPLETE_TYPES[a.actionType] or a.interrupted then
                M.state.action = nil;
            end
            return;
        end
        -- the pet's stream: track its action for the PetAction dispatch hold
        pcall(function()
            local mm = AshitaCore:GetMemoryManager();
            local myIndex = mm:GetParty():GetMemberTargetIndex(0);
            local petIndex = mm:GetEntity():GetPetTargetIndex(myIndex);
            if petIndex == 0 then return; end
            if a.userId ~= mm:GetEntity():GetServerId(petIndex) then return; end
            if M.PET_ACTION_COMPLETE_TYPES[a.actionType] or a.interrupted then
                M.state.petAction = nil;
                return;
            end
            if a.actionType ~= 7 and a.actionType ~= 8 then return; end
            local p = M.parse0x28Pet(e.data);
            if p.actionId == 0 then return; end
            local now = os.clock();
            local pa = { Id = p.actionId };
            if a.actionType == 7 then
                pa.Completion = now + (M.SETTINGS.PetskillDelay or 4.0);
                if p.message == 43 then
                    pa.Type = 'MobSkill';
                    local nm = AshitaCore:GetResourceManager():GetString('monsters.abilities', p.actionId - 256);
                    pa.Name = (type(nm) == 'string') and nm or nil;
                else
                    pa.Type = 'Ability';
                    pa.Resource = AshitaCore:GetResourceManager():GetAbilityById(p.actionId + 512);
                end
            else
                pa.Type = 'Spell';
                pa.Resource = AshitaCore:GetResourceManager():GetSpellById(p.actionId);
                local ct = (pa.Resource ~= nil) and pa.Resource.CastTime or 0;
                pa.Completion = now + ct * 0.25 + (M.SETTINGS.SpellOffset or 1.0);
            end
            M.state.petAction = pa;
            M.fireEvent('PetAction', 'auto', pa);   -- the dispatch point pet rules ride
        end);
    elseif e.id == 0x01B then
        pcall(function()
            for i = 1, 16 do
                M.state.encumbered[i] = (M.bitsAt(e.data, 0x60, i - 1, 1) == 1);
            end
        end);
    end
end

-- ---------------------------------------------------------------------------
-- registration (no-ops until the native flag is on)
-- ---------------------------------------------------------------------------

pcall(function()
    ashita.events.register('packet_out', 'dlac-equipengine-out', function(e)
        M.handleOutgoing(e);
    end);
    ashita.events.register('packet_in', 'dlac-equipengine-in', function(e)
        M.handleIncoming(e);
    end);
end);

return M;
