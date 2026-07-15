--[[
    lookpreview.lua -- show a lockstyle WITHOUT equipping anything (v42, round 2).

    MECHANISM (round 2 -- the round-1 memory pokes never rendered): the client's
    appearance is driven by ONE channel -- the server's GRAP_LIST packet (0x051).
    The server source (CatsEyeXI src/map/packets/s2c/0x051_grap_list.cpp, read
    2026-07-15) shows the whole wire format:

        GrapIDTbl[0] = face | race << 8
        GrapIDTbl[1] = head  + 0x1000      GrapIDTbl[5] = feet + 0x5000
        GrapIDTbl[2] = body  + 0x2000      GrapIDTbl[6] = main + 0x6000
        GrapIDTbl[3] = hands + 0x3000      GrapIDTbl[7] = sub  + 0x7000
        GrapIDTbl[4] = legs  + 0x4000      GrapIDTbl[8] = ranged + 0x8000

    So we INJECT that packet locally (AddIncomingPacket) with our own model ids
    -- exactly what the server does when a lockstyle applies, minus the server.
    The entity's look_t memory (plugins/sdk/ffxi/entity.h) is populated FROM
    these packets, which is why its fields carry the same base+model values --
    a snapshot of it restores verbatim on preview end.

    Why round 1 failed (writing entity Look + ModelUpdateFlags directly, the
    sexchange pattern): the flags-triggered rebuild re-derives the EQUIPMENT
    slots from your real gear, so the poked values never survive to render.
    sexchange gets away with it because race/hair are not gear-derived -- and
    even then it patches the incoming packets too. The packet IS the mechanism;
    round 1 was writing to what the packet writes to, one step too late.

    While a preview is live we also REWRITE incoming appearance packets (0x051,
    and 0x00D self-updates) in place: the real look they carry refreshes our
    restore snapshot, and the preview is painted over them so the server can
    never stomp what you see. Zoning (0x00A) simply ends the preview -- the
    fresh zone's own look is authoritative.

    Nothing here is equipped, nothing is SENT to the server, nobody else sees
    it. Worst failure mode is looking wrong until the next appearance update.
--]]

local M = {};

local _fok, ffi = pcall(require, 'ffi');
_fok = _fok and ffi ~= nil;

-- dlac slot name -> look_t field + model-id base (entity.h; confirmed by the
-- GRAP_LIST source above). Note dlac says Range, the client field is Ranged.
local LOOK = {
    Head  = { f = 'Head',   base = 0x1000 },
    Body  = { f = 'Body',   base = 0x2000 },
    Hands = { f = 'Hands',  base = 0x3000 },
    Legs  = { f = 'Legs',   base = 0x4000 },
    Feet  = { f = 'Feet',   base = 0x5000 },
    Main  = { f = 'Main',   base = 0x6000 },
    Sub   = { f = 'Sub',    base = 0x7000 },
    Range = { f = 'Ranged', base = 0x8000 },
};
M._LOOK = LOOK;   -- test seam

-- look_t fields in GrapIDTbl[1..8] order -- packet building and interception
-- both walk this list, so the order is load-bearing (matches the server source).
local FIELDS = { 'Head', 'Body', 'Hands', 'Legs', 'Feet', 'Main', 'Sub', 'Ranged' };
local FBASE  = { Head = 0x1000, Body = 0x2000, Hands = 0x3000, Legs = 0x4000,
                 Feet = 0x5000, Main = 0x6000, Sub = 0x7000, Ranged = 0x8000 };
M._FIELDS = FIELDS;   -- test seam

-- ---------------------------------------------------------------------------
-- pure helpers (headless-tested)
-- ---------------------------------------------------------------------------
-- {Slot = ItemName} -> {look_t field = base + model}. 'remove' is LAC's "show
-- nothing here" -> the bare base (model 0 renders as the naked slot). A name
-- with no model id is DROPPED, not zeroed: no model means the catalog has no
-- appearance for it, which is not the same as "show nothing".
function M._plan(set, modelOf)
    local out = {};
    if type(set) ~= 'table' or type(modelOf) ~= 'function' then return out; end
    local function put(slot, name)
        local L = LOOK[slot];
        if L == nil or type(name) ~= 'string' or name == '' then return; end
        if name == 'remove' then out[L.f] = L.base; return; end
        local m = modelOf(name);
        if type(m) == 'number' and m > 0 then out[L.f] = L.base + m; end
    end
    for slot, name in pairs(set) do put(slot, name); end
    -- Ammo has no look field: FFXI renders a thrown weapon (shuriken, boomerang)
    -- in the RANGED slot. Only fill it when Range itself is empty -- a real
    -- ranged weapon always wins the slot it shares.
    if out.Ranged == nil and set.Ammo ~= nil then
        local L = LOOK.Range;
        local name = set.Ammo;
        if name == 'remove' then out[L.f] = L.base;
        elseif type(name) == 'string' and name ~= '' then
            local m = modelOf(name);
            if type(m) == 'number' and m > 0 then out[L.f] = L.base + m; end
        end
    end
    return out;
end

-- A full 8-field look: the plan's slots over the snapshot's, bare base where
-- neither knows. The GRAP packet is whole-look -- every injection needs all 8.
function M._merged(saved, plan)
    local out = {};
    for _, f in ipairs(FIELDS) do
        out[f] = (plan and plan[f]) or (saved and saved[f]) or FBASE[f];
    end
    return out;
end

-- The GRAP_LIST bytes: 4-byte header + GrapIDTbl[9] + pad = 0x18. The header
-- u16 is id | (size/2) << 9 (the filters addon builds 0x0B4 the same way);
-- AddIncomingPacket gets the id separately, the prefill is belt-and-braces.
local P51_LEN = 0x18;
function M._packet51(face, race, lookmap)
    local t = {};
    for i = 1, P51_LEN do t[i] = 0; end
    t[1] = 0x51;
    t[2] = 0x18;
    t[5] = (tonumber(face) or 0) % 256;   -- GrapIDTbl[0] low byte
    t[6] = (tonumber(race) or 0) % 256;   -- GrapIDTbl[0] high byte
    local o = 7;                          -- GrapIDTbl[1] (0-based 0x06)
    for _, f in ipairs(FIELDS) do
        local v = (lookmap and lookmap[f]) or FBASE[f];
        t[o]     = v % 256;
        t[o + 1] = math.floor(v / 256) % 256;
        o = o + 2;
    end
    return t;
end

-- ---------------------------------------------------------------------------
-- live state
-- ---------------------------------------------------------------------------
local _active  = false;
local _saved   = nil;    -- look_t field -> value: the REAL look (start snapshot,
                         -- refreshed from every intercepted appearance packet)
local _planned = nil;    -- the current plan (named slots only)
local _face, _race = 0, 0;
local _nextCheck = 0;

local function entity()
    local p = nil;
    pcall(function() p = GetPlayerEntity(); end);
    if p == nil then return nil; end
    local ok = pcall(function() local _ = p.Look.Head; end);   -- guard: struct present
    return ok and p or nil;
end

local function inject(lookmap)
    pcall(function()
        AshitaCore:GetPacketManager():AddIncomingPacket(0x051, M._packet51(_face, _race, lookmap));
    end);
end

function M.active() return _active; end

function M.start(set, modelOf)
    local p = entity();
    if p == nil then return false; end
    if not _active then
        _saved = {};
        pcall(function()
            for _, f in ipairs(FIELDS) do _saved[f] = p.Look[f]; end
            _face = p.Look.Hair % 256;
            _race = p.Race;
        end);
        -- Defensive: an early build of this module set ActorLockFlag while
        -- previewing; a reload mid-preview could strand it at 1, which makes
        -- the model ignore gear changes for the session. We never want it.
        pcall(function() p.ActorLockFlag = 0; end);
        _active = true;
        _nextCheck = 0;
    end
    return M.update(set, modelOf);
end

-- Re-plan and re-inject. Called on every edit of the working copy, so the look
-- on screen tracks the picker live. Returns ok + how many slots the plan
-- actually styled -- 0 means the injection repaints the current look verbatim
-- (a set whose pieces have no model ids), which the caller should SAY, because
-- on screen it is indistinguishable from "nothing happened".
function M.update(set, modelOf)
    if not _active then return false; end
    _planned = M._plan(set, modelOf);
    inject(M._merged(_saved, _planned));
    local n = 0;
    for _ in pairs(_planned) do n = n + 1; end
    return true, n;
end

-- End: inject the snapshot back. It is the real look as of the last appearance
-- update (interception keeps it fresh), never an invention -- and the next
-- real equip or zone rebuilds from truth regardless.
function M.stop()
    if not _active then return; end
    local back = M._merged(_saved, nil);
    _active, _planned, _saved = false, nil, nil;
    inject(back);
end

-- Self-heal, once a second: if the rendered look drifted from what we want
-- (a client-local rebuild the packets don't cover), re-inject. Entity look_t
-- mirrors the last applied appearance, so this is 8 reads when settled.
function M.pump()
    if not _active or _planned == nil then return; end
    if os.clock() < _nextCheck then return; end
    _nextCheck = os.clock() + 1.0;
    local p = entity();
    if p == nil then return; end
    local want = M._merged(_saved, _planned);
    local drift = false;
    pcall(function()
        for _, f in ipairs(FIELDS) do
            if p.Look[f] ~= want[f] then drift = true; return; end
        end
    end);
    if drift then inject(want); end
end

-- ---------------------------------------------------------------------------
-- interception: while previewing, appearance packets refresh the snapshot and
-- get repainted with the preview, so the server can't stomp the screen.
-- ffi-gated: headless test runs (plain Lua) skip the live packet layer whole.
-- ---------------------------------------------------------------------------
if _fok then
    ashita.events.register('packet_in', 'dlac_lookpreview_in', function(e)
        if not _active or e.blocked or e.injected then return; end

        if e.id == 0x00A then
            -- Zoning: the new zone's look is authoritative; the preview is over.
            -- (lockstyle.lua's pump notices active() dropped and updates its UI.)
            _active, _planned, _saved = false, nil, nil;
            return;
        end

        -- Appearance payload offset: 0x051 carries GrapIDTbl at 0x04; a 0x00D
        -- PC update carries the same block at 0x48 for the local player when
        -- its look flag (0x10) is set (offsets per sexchange.lua, shipped).
        local base = nil;
        if e.id == 0x051 then
            base = 0x04;
        elseif e.id == 0x00D then
            local ok = pcall(function()
                local p = ffi.cast('uint8_t*', e.data_modified_raw);
                local sid = p[0x04] + p[0x05] * 0x100 + p[0x06] * 0x10000 + p[0x07] * 0x1000000;
                local mine = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0);
                if sid == mine and math.floor(p[0x0A] / 16) % 2 == 1 then base = 0x48; end
            end);
            if not ok then return; end
        end
        if base == nil then return; end

        pcall(function()
            local p = ffi.cast('uint8_t*', e.data_modified_raw);
            -- capture the REAL look this packet carries -> fresh restore target
            _face, _race = p[base], p[base + 1];
            local o = base + 2;
            for _, f in ipairs(FIELDS) do
                _saved[f] = p[o] + p[o + 1] * 0x100;
                o = o + 2;
            end
            -- then repaint it with the preview so it never reaches the screen
            local want = M._merged(_saved, _planned);
            o = base + 2;
            for _, f in ipairs(FIELDS) do
                local v = want[f];
                p[o]     = v % 256;
                p[o + 1] = math.floor(v / 256) % 256;
                o = o + 2;
            end
        end);
    end);
end

return M;
