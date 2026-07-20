--[[
    dlac/feature/eboxammo.lua -- E-Box ammo counts + withdraw (AutoAmmo's
    Crystal-Warrior extra; docs/design/auto-ammo.md).

    CatsEyeXI's E-Box is Crystal-Warrior-only storage, spoken over the custom
    0x1A4 request/response protocol (the trove addon's wire format --
    trove/utils/packet.lua + plugins/ebox.lua -- reimplemented here exactly
    like helmwatch reimplemented GET_POINTS, so dlac never depends on trove
    being installed). This module does TWO things for the AutoAmmo panel:

      counts   -- GET_CATEGORY(15 = Ammunition): ONE request streams every
                  ammo item in the box as ITEM rows (u16 id @0x08, u32 qty
                  @0x0C); CLEAR(0) resets the staging, END_LIST(2, source
                  byte @0x05 == 0 = ebox) commits it.
      withdraw -- WITHDRAW(2): u16 itemId @0x08, u32 qty @0x0C; the ACK(3)
                  carries request action @0x05, success @0x06, message @0x10.

    LOCKED(4) is the server's own gate (reason @0x05: 1 = not a Crystal
    Warrior, 2 = E-Box not unlocked yet) -- the UI gate is gamemode.get()
    == 'CW' (affirmative ONLY; nil is unknown and shows nothing), LOCKED is
    the belt-and-braces answer if the client-side read ever lies.

    Pending discipline: 0x1A4 is a party line (helmwatch's points, trove's
    panels, us). We stage ITEM rows only while OUR request is in flight and
    consume (e.blocked) only what we asked for -- Ashita still hands blocked
    events to every other addon, so nobody is starved (the helmwatch rule);
    blocking matters because the retail client has no idea what opcode 0x1A4
    is. Parsing is plain string.byte -- no struct -- so every wire path here
    runs headless (tests EB*).
]]--

local M = {};

local PKT_1A4 = 0x1A4;
-- C2S
local ACT_WITHDRAW     = 2;
local ACT_GET_CATEGORY = 5;
-- S2C
local ACT_CLEAR    = 0;
local ACT_ITEM     = 1;
local ACT_END_LIST = 2;
local ACT_ACK      = 3;
local ACT_LOCKED   = 4;

local AH_CAT_AMMO = 15;   -- 'Ammunition' (trove trove.lua AH_NAMES)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
M.counts = nil;          -- [itemId] = qty in the E-Box; nil until a stream commits
M.at = 0;                -- os.clock() of the last committed stream
M.lockedReason = nil;    -- nil | 'cw' (server says not CW) | 'locked' (E-Box not unlocked)
M.lockedMsg = nil;       -- the server's own words for the lock
M.status = nil;          -- last withdraw result line (shown briefly by the panel)
M.statusErr = false;
M.statusAt = 0;
M.busy = false;          -- one withdraw in flight at a time
local _busyUntil = 0;    -- trove's safety timeout: a lost ACK must not wedge the button
local _pending = false;  -- our GET_CATEGORY stream is in flight
local _staging = nil;

-- clock, injectable for the headless tests
function M._now() return os.clock(); end

-- ---------------------------------------------------------------------------
-- The gate: Crystal Warriors only (Henrik: "only crystal warriors may view
-- this"). Affirmative 'CW' opens; 'Wings'/'ACE'/nil (unknown) stay shut --
-- the never-gate-on-nil rule points the safe way here: unknown = hidden.
-- ---------------------------------------------------------------------------
local _gmok, _gm = pcall(require, 'dlac\\feature\\gamemode');
_gmok = _gmok and type(_gm) == 'table' and type(_gm.get) == 'function';
function M.isCW()
    if not _gmok then return false; end
    local ok, mode = pcall(_gm.get);
    return ok and mode == 'CW';
end

-- ---------------------------------------------------------------------------
-- Wire helpers (trove/utils/packet.lua shapes, string.byte only)
-- ---------------------------------------------------------------------------
local function u8(data, off) return string.byte(data, off + 1) or 0; end
local function u16(data, off) return u8(data, off) + u8(data, off + 1) * 256; end
local function u32(data, off)
    return u8(data, off) + u8(data, off + 1) * 0x100
         + u8(data, off + 2) * 0x10000 + u8(data, off + 3) * 0x1000000;
end
local function zstr(data, off, maxLen)
    local out = {};
    for i = 1, maxLen do
        local b = string.byte(data, off + i);
        if b == nil or b == 0 then break; end
        out[#out + 1] = string.char(b);
    end
    return table.concat(out);
end

local function sendRaw(p)
    pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(PKT_1A4, p); end);
end
local function makePkt(action)
    local p = {};
    for i = 1, 64 do p[i] = 0; end
    p[5] = action;
    return p;
end

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------

-- Ask the box for its whole Ammunition category. Throttle: the panel calls
-- refreshIfStale per frame; a real request goes out at most once per maxAge.
function M._beginStream()   -- split out as the headless seam (tests EB*)
    _pending = true;
    _staging = {};
end
function M.refresh()
    if not M.isCW() then return false; end
    if M.lockedReason ~= nil then return false; end   -- the server already said no
    M._beginStream();
    local p = makePkt(ACT_GET_CATEGORY);
    p[11] = AH_CAT_AMMO;   -- u8 @0x0A
    sendRaw(p);
    return true;
end

function M.refreshIfStale(maxAge)
    if _pending then return false; end
    if M.counts ~= nil and (M._now() - M.at) < (tonumber(maxAge) or 15) then return false; end
    return M.refresh();
end

-- Withdraw qty of itemId into the bags. Clamped to what the box holds (the
-- pure half _clampQty is the tested rule).
function M._clampQty(qty, have)
    qty = math.floor(tonumber(qty) or 0);
    have = math.floor(tonumber(have) or 0);
    if qty < 1 or have < 1 then return 0; end
    if qty > have then return have; end
    return qty;
end

function M.withdraw(itemId, qty)
    if not M.isCW() or M.busy then return false; end
    itemId = math.floor(tonumber(itemId) or 0);
    qty = M._clampQty(qty, (M.counts ~= nil) and M.counts[itemId] or 0);
    if itemId <= 0 or qty <= 0 then return false; end
    M.busy = true;
    _busyUntil = M._now() + 3;
    local p = makePkt(ACT_WITHDRAW);
    p[0x08 + 1] = itemId % 256;              -- u16 @0x08
    p[0x08 + 2] = math.floor(itemId / 256) % 256;
    p[0x0C + 1] = qty % 256;                 -- u32 @0x0C (qty is small; low bytes suffice)
    p[0x0C + 2] = math.floor(qty / 256) % 256;
    p[0x0C + 3] = math.floor(qty / 0x10000) % 256;
    p[0x0C + 4] = math.floor(qty / 0x1000000) % 256;
    sendRaw(p);
    return true;
end

-- The panel reads busy through this so the lost-ACK timeout is applied at
-- read time (no frame hook needed).
function M.isBusy()
    if M.busy and M._now() > _busyUntil then M.busy = false; end
    return M.busy;
end

-- Manual rescan (Henrik, field round 3: "would be nice to be able to have it
-- scanned"): poke the entity watcher (next tick sweeps fresh) AND re-request
-- the box counts.
function M.rescan()
    if _ewok then _ew.poke(M.BOX_NAME); end
    M.at = 0;
    return M.refresh();
end

local function setStatus(msg, isErr)
    M.status, M.statusErr, M.statusAt = msg, (isErr == true), M._now();
end

-- ---------------------------------------------------------------------------
-- One inbound 0x1A4. Returns true when WE consumed it (caller blocks it --
-- the retail client has no idea what this opcode is; every other addon still
-- sees the event, so blocking starves nobody).
-- ---------------------------------------------------------------------------
function M._onPacket(data)
    local action = u8(data, 0x04);

    if action == ACT_CLEAR then
        if not _pending then return false; end
        _staging = {};
        return true;
    end

    if action == ACT_ITEM then
        if not _pending then return false; end   -- someone else's stream (trove's panel)
        local id  = u16(data, 0x08);
        local qty = u32(data, 0x0C);
        if id > 0 then _staging[id] = qty; end
        return true;
    end

    if action == ACT_END_LIST then
        if not _pending then return false; end
        if u8(data, 0x05) ~= 0 then return false; end   -- source 0 = ebox; others belong elsewhere
        M.counts = _staging or {};
        M.at = M._now();
        _pending = false;
        _staging = nil;
        return true;
    end

    if action == ACT_ACK then
        if u8(data, 0x05) ~= ACT_WITHDRAW or not M.busy then return false; end
        M.busy = false;
        local success = u8(data, 0x06);
        local msg = zstr(data, 0x10, 31);
        if success == 1 then
            setStatus((msg ~= '') and msg or 'withdrawn -- check your bags', false);
            -- the box changed: re-count now (the bags count themselves via ownedcache)
            M.at = 0;
            M.refresh();
        else
            setStatus((msg ~= '') and msg or 'withdraw refused', true);
        end
        return true;
    end

    if action == ACT_LOCKED then
        -- Only meaningful when WE poked the box; an unsolicited LOCKED (some
        -- other addon's request) must not shut our panel half down.
        if not _pending and not M.busy then return false; end
        local reason = u8(data, 0x05);
        M.lockedMsg = zstr(data, 0x10, 31);
        M.lockedReason = (reason == 1) and 'cw' or 'locked';
        _pending, _staging, M.busy = false, nil, false;
        return true;
    end

    return false;
end

-- ---------------------------------------------------------------------------
-- The physical box, via the CENTRAL entity watcher (lib/entwatch -- built
-- from this feature's field rounds; eboxammo is its first consumer). E-Boxes
-- are DYNAMICALLY SPAWNED NPCs named "Ephemeral Box" (Henrik's Bastok Mines
-- sample 17737730 = zone 234, index 0x802); entwatch owns every scan idiom
-- those rounds paid for (trimmed/ci names, rendered bit, the full
-- 0x000-0x8FF range) and keeps the tracked boxes' distances fresh.
-- ---------------------------------------------------------------------------
M.BOX_NAME = 'Ephemeral Box';
M.BOX_RANGE = 5;   -- yalms -- FIELD-PINNED (Henrik, 2026-07-20: "the box range
                   -- is 5"); was 6 (the trade-range guess) for one round

local _ewok, _ew = pcall(require, 'dlac\\lib\\entwatch');
_ewok = _ewok and type(_ew) == 'table';

-- Nearest box in YALMS, or nil when none is tracked in this zone. The watch
-- is (re)registered on every ask -- idempotent -- and the ask itself is what
-- keeps the callback-less watch inside entwatch's demand window: the panel
-- polls while open, and an unopened panel costs nothing.
function M.boxDistance()
    if not _ewok then return nil; end
    _ew.watch('eboxammo', M.BOX_NAME);
    return (_ew.nearest(M.BOX_NAME));
end

-- Ashita glue, guarded (headless: no ashita global, nothing registers).
pcall(function()
    ashita.events.register('packet_in', 'dlac_eboxammo_packet_in', function(e)
        if e.id ~= PKT_1A4 then return; end
        local ok, consumed = pcall(M._onPacket, e.data_modified or e.data);
        if ok and consumed == true then e.blocked = true; end
    end);
end);

-- HIDDEN diagnostic (the /dl merits precedent -- deliberately in no help
-- list): `/dl ebox` dumps what the scan actually sees, so a field round
-- returns DATA, not theories -- round 2 shipped an exact-name compare
-- (GetName pads with whitespace), round 3 a too-short index range (the boxes
-- are dynamic entities); this dump would have caught both in one pass.
pcall(function()
    ashita.events.register('command', 'dlac_eboxammo_cmd', function(e)
        pcall(function()
            local cmd = string.lower(e.command or '');
            local a = cmd:match('^/dl%s+(%S+)');
            if a == nil then a = cmd:match('^/dlac%s+(%S+)'); end
            if a ~= 'ebox' then return; end
            e.blocked = true;
            local gm = nil;
            pcall(function() gm = _gm.get(); end);
            print(string.format('[dlac] ebox: gamemode=%s isCW=%s locked=%s counts=%s dist=%s range=%d',
                tostring(gm), tostring(M.isCW()), tostring(M.lockedReason),
                (M.counts ~= nil) and 'cached' or 'nil', tostring(M.boxDistance()), M.BOX_RANGE));
            if _ewok then   -- the watcher's own view (the raw sweep below stays independent)
                for _, w in ipairs(_ew.debugState()) do
                    print(string.format('[dlac] ebox watch: %q subs=[%s] matches=%d active=%s',
                        w.name, w.subs, w.matches, tostring(w.active)));
                end
            end
            local em = AshitaCore:GetMemoryManager():GetEntity();
            local nRaw, nRen, nHit, near = 0, 0, 0, {};
            for i = 0, 2303 do
                pcall(function()
                    if em:GetRawEntity(i) == nil then return; end
                    nRaw = nRaw + 1;
                    local rf = em:GetRenderFlags0(i) or 0;
                    if rf < 0 then rf = rf + 4294967296; end
                    local ren = (math.floor(rf / 0x200) % 2) == 1;
                    if ren then nRen = nRen + 1; end
                    local nm = tostring(em:GetName(i) or ''):gsub('%s+$', '');
                    local d = em:GetDistance(i);
                    if string.find(string.lower(nm), 'ephemeral', 1, true) ~= nil then
                        nHit = nHit + 1;
                        print(string.format('[dlac] ebox HIT idx=0x%03X name=%q sid=%s rf0=0x%08X rendered=%s distSq=%s (%.1fy)',
                            i, nm, tostring(em:GetServerId(i)), rf, tostring(ren), tostring(d),
                            (type(d) == 'number' and d >= 0) and math.sqrt(d) or -1));
                    elseif ren and nm ~= '' and type(d) == 'number' and d >= 0 and d < 900 then
                        near[#near + 1] = { i = i, nm = nm, d = d };
                    end
                end);
            end
            table.sort(near, function(x, y) return x.d < y.d; end);
            local parts = {};
            for k = 1, math.min(8, #near) do
                parts[#parts + 1] = string.format('%s(0x%03X,%.1fy)', near[k].nm, near[k].i, math.sqrt(near[k].d));
            end
            print(string.format('[dlac] ebox: raw=%d rendered=%d ephemeral-hits=%d; nearest named: %s',
                nRaw, nRen, nHit, table.concat(parts, ', ')));
        end);
    end);
end);

return M;
