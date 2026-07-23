--[[
    dlac/lockstyleapply.lua -- the LOCKSTYLE EXECUTOR, resident in the ADDON state.

    THE PIVOT (issue #81, PRD #80): lockstyle is becoming 100% addon-resident.
    Apply -- the 0x053 build + inject -- was an Engine accident, not a necessity:
    it went engine-side when it called gFunc.LockStyle, but since v42 the packet
    is BUILT here and injected via AshitaCore, the process-wide SDK available in
    every addon state. Every other input (boxes file, Profiles resolver, Owned-gear
    name->id map, job levels, worn equipment) is addon-native already. This module
    is the executor the GUI Apply button calls DIRECTLY -- no queueCmd, no
    request-file, no command bus. The Engine's own copy of the pure core
    (dispatch._lockstyleFrom / _lockstylePacket) is UNTOUCHED this slice; the two
    are pinned byte-identical by the AG parity tests until the Engine's is deleted
    (phase 2). See docs/design/lockstyle-engine-move.md (superseded) and issue #80.

    Bookkeeping is at the CALL SITE, not here: an addon state never hears its own
    queued commands, and same-state visibility of its OWN injected packets is
    unproven -- so feature/lockstyle.lua arms the zone guard and notes lastBox
    directly when it calls apply(), never off observing its own packet_out.

    Divergences from the Engine's copy, all deliberate (PRD #80):
      * the SILENT job gate is predicted through the Gear Oracle's ONE door
        (oracle.anyJobCanWear) -- the GRD guards forbid a second eligibility home,
        so there is no _lsStyleGate twin here.
      * the weapon-category warning and the freeze-current read come from the
        Addon state's own worn-gear source (oracle.wornItem), never gData
        (the addon's gData shim carries no GetEquipment).
    Player-facing chat lines are preserved VERBATIM from the Engine's apply.
]]--

local M = {};

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
local print = (_cfok and type(_cfmt) == 'table' and type(_cfmt.print) == 'function') and _cfmt.print or print;
local _gok, gear = pcall(require, 'dlac\\gear');
_gok = _gok and type(gear) == 'table';
local _orok, oracle = pcall(require, 'dlac\\gear\\gearoracle');
_orok = _orok and type(oracle) == 'table';
-- jobgate's live level READER (abbr -> current level); oracle.anyJobCanWear
-- fronts the GATE but not the reader, so jobgate stays required for levels().
local _jgok, jobgate = pcall(require, 'dlac\\gear\\jobgate');
_jgok = _jgok and type(jobgate) == 'table';

-- ---------------------------------------------------------------------------
-- The PURE CORE, relocated from the Engine BYTE-FOR-BYTE (dispatch.lua v42).
-- Do not "improve" it: the AG-suite parity tests pin these against the Engine's
-- surviving copy, and the Engine builds the identical wire today. Change one,
-- change both, or the parity pins fail (until phase 2 deletes the Engine's).
-- ---------------------------------------------------------------------------

-- Visual slots in EquipKind order (server c2s 0x053 reads ItemNo + EquipKind
-- only; container/index are ignored, so no bag scan belongs here).
local LS_KINDS = { { k = 0, s = 'Main' },  { k = 1, s = 'Sub' },  { k = 2, s = 'Range' },
                   { k = 3, s = 'Ammo' },  { k = 4, s = 'Head' }, { k = 5, s = 'Body' },
                   { k = 6, s = 'Hands' }, { k = 7, s = 'Legs' }, { k = 8, s = 'Feet' } };

-- Lockstyle box selection (pure): parsed lockstyles.lua table + optional box
-- number -> (slot->name table, box name, box index), or (nil, why). Explicit n
-- wins; else the file's marked box (active); else 1. Only string values ride.
function M._lockstyleFrom(t, n)
    if type(t) ~= 'table' or type(t.slots) ~= 'table' then return nil, 'no lockstyle sets saved yet'; end
    n = tonumber(n) or tonumber(t.active) or 1;
    local e = t.slots[n];
    if type(e) ~= 'table' or type(e.set) ~= 'table' then return nil, string.format('lockstyle box %d is empty', n); end
    local out, any = {}, false;
    for slot, v in pairs(e.set) do
        if type(v) == 'string' and v ~= '' then out[slot] = v; any = true; end
    end
    if not any then return nil, string.format('lockstyle box %d has no items', n); end
    return out, ((type(e.name) == 'string' and e.name ~= '') and e.name or ('box ' .. n)), n;
end

-- The 0x053 bytes (pure). resolveId(name) -> item id or nil; equippedId(slot) ->
-- the worn item's id (freeze-current for unnamed slots). styleItems PERSIST per
-- slot server-side, so all nine visual slots ride every time: named -> id,
-- 'remove' -> 0 (renders EMPTY), unnamed -> the worn item's id. Returns the
-- packet table plus what happened per slot.
function M._lockstylePacket(set, resolveId, equippedId)
    local pkt = {};
    for i = 1, 136 do pkt[i] = 0; end
    pkt[1] = 0x53; pkt[2] = 0x88;   -- header u16 = id | (size/2) << 9
    pkt[5] = 9;                     -- Count: all visual slots, every time
    pkt[6] = 3;                     -- Mode: Set
    pkt[7] = 1;                     -- Flags (what the client sends)
    local sent, frozen, missing = {}, {}, {};
    for n, e in ipairs(LS_KINDS) do
        local o = 0x08 + (n - 1) * 8;   -- lockstyleitem_t: ItemIndex, EquipKind,
        pkt[o + 2] = e.k;               -- Category, pad, ItemNo u16 -- index and
                                        -- category are ignored server-side
        local nm = (type(set) == 'table') and set[e.s] or nil;
        local id = 0;
        if type(nm) == 'string' and nm ~= '' and nm ~= 'remove' then
            id = tonumber(resolveId ~= nil and resolveId(nm) or nil) or 0;
            if id > 0 then sent[e.s] = nm; else missing[#missing + 1] = nm; end
        elseif nm == nil then
            id = tonumber(equippedId ~= nil and equippedId(e.s) or nil) or 0;
            if id > 0 then frozen[e.s] = id; end
        end
        pkt[o + 5] = id % 256;
        pkt[o + 6] = math.floor(id / 256) % 256;
    end
    return pkt, { sent = sent, frozen = frozen, missing = missing };
end

-- ---------------------------------------------------------------------------
-- Live reads (the addon-native inputs the Engine reached for via gData / gFunc).
-- All injectable through the deps table so the executor is headless-testable.
-- ---------------------------------------------------------------------------

-- Addon equipment-slot index for the oracle's worn read (FFXI order: Main 0 ..
-- Feet 8; ui/gearui.lua EQUIP_SLOTS is the authority). Only the visual slots.
local EQUIP_SLOT = { Main = 0, Sub = 1, Range = 2, Ammo = 3, Head = 4,
                     Body = 5, Hands = 6, Legs = 7, Feet = 8 };

-- name -> item id, via the char's REAL gear.lua reverse map (the boxes' names
-- came from it) with a resource-manager fallback -- IDENTICAL to the Engine's
-- _lsResolvers resolveId, because dlac\gear resolves to the same char file in
-- both states.
local function liveResolveId(name)
    local id = nil;
    pcall(function()
        local rec = _gok and gear.NameToObject and gear.NameToObject[name] or nil;
        if rec ~= nil then id = tonumber(rec.Id); end
    end);
    if id == nil then
        pcall(function()
            local r = AshitaCore:GetResourceManager():GetItemByName(name, 2)
                   or AshitaCore:GetResourceManager():GetItemByName(name, 0);
            if r ~= nil then id = tonumber(r.Id); end
        end);
    end
    return id;
end

-- Worn item in a visual slot, through the Gear Oracle's ONE door (never gData:
-- the addon's shim has no GetEquipment). Returns the { id, rec, ... } record.
local function liveWorn(slot)
    local idx = EQUIP_SLOT[slot];
    if idx == nil or not _orok then return nil; end
    local w = nil;
    pcall(function() w = oracle.wornItem(idx); end);
    return w;
end

-- slot -> the worn item's id (freeze-current for unnamed slots).
local function liveEquippedId(slot)
    local w = liveWorn(slot);
    return w ~= nil and tonumber(w.id) or nil;
end

-- A style piece's weapon category (Type), from the char's gear record.
local function liveRecType(name)
    local rec = _gok and gear.NameToObject and gear.NameToObject[name] or nil;
    return (type(rec) == 'table') and rec.Type or nil;
end

-- The worn item's weapon category (Type) for the same-category warning.
local function liveWornType(slot)
    local w = liveWorn(slot);
    return (w ~= nil and type(w.rec) == 'table') and w.rec.Type or nil;
end

-- The character's live job levels (abbr -> current level) for the silent
-- job-gate prediction. nil pre-login -> the caller fails open (no warnings).
local function liveJobLevels()
    return _jgok and jobgate.levels() or nil;
end

-- A style piece's record (Jobs + Level) for the job-gate warning wording.
local function liveRec(name)
    return _gok and gear.NameToObject and gear.NameToObject[name] or nil;
end

-- The 0x053 injection -- the process-wide SDK, from THIS state. Returns ok.
local function liveInject(pkt)
    return pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0x053, pkt); end);
end

-- ---------------------------------------------------------------------------
-- The executor. apply(boxTable, box, deps) reads the SAVED boxes table (never a
-- working copy -- the caller passes the loaded file's content), builds and
-- INJECTS the 0x053 from this state, predicts the server's silent gates so
-- "nothing changed" has a name, and stamps the sender-side send witness.
-- Returns a result table: { ok, box, name, styled, missing } | { ok = false, why }.
--
-- deps (all optional; live defaults): resolveId / equippedId / jobLevels /
-- wornType / recType / rec / inject / emit -- the seam the headless tests drive.
-- ---------------------------------------------------------------------------
function M.apply(boxTable, box, deps)
    deps = deps or {};
    local emit       = deps.emit       or print;
    local resolveId  = deps.resolveId  or liveResolveId;
    local equippedId = deps.equippedId or liveEquippedId;
    local jobLevels  = deps.jobLevels  or liveJobLevels;
    local wornType   = deps.wornType   or liveWornType;
    local recType    = deps.recType    or liveRecType;
    local recOf      = deps.rec        or liveRec;
    local inject     = deps.inject     or liveInject;

    local set, why, boxN = M._lockstyleFrom(boxTable, box);
    if set == nil then
        emit('[dlac] lockstyle: ' .. tostring(why));
        return { ok = false, why = why };
    end

    local pkt, r = M._lockstylePacket(set, resolveId, equippedId);

    -- Predict the server's SILENT job gate (canEquipItemOnAnyJob) through the
    -- Gear Oracle's one door: a piece no job of yours can wear at level keeps
    -- the OLD style on that slot, with no message from the server at all.
    local lv = jobLevels();
    if lv ~= nil then
        for slot, nm in pairs(r.sent) do
            local rec = recOf(nm);
            if rec ~= nil and _orok and not oracle.anyJobCanWear(rec, lv) then
                emit(string.format('[dlac] lockstyle: %s will KEEP ITS OLD LOOK -- "%s" needs %s Lv%d,'
                    .. ' and no job of yours is there yet (server: one of YOUR jobs must be able to wear it).',
                    slot, nm, table.concat(type(rec.Jobs) == 'table' and rec.Jobs or { '?' }, '/'),
                    tonumber(rec.Level) or 0));
            end
        end
    end

    -- Weapon styles only take over the same category (hasValidStyle); warn when
    -- the style's type visibly disagrees with what is worn (Addon-state reads).
    for _, ws in ipairs({ 'Main', 'Range' }) do
        local nm = r.sent[ws];
        if nm ~= nil then
            local st, et = recType(nm), wornType(ws);
            if st ~= nil and et ~= nil and st ~= et then
                emit(string.format('[dlac] lockstyle: %s style "%s" (%s) will NOT show over your'
                    .. ' equipped %s -- weapon styles need the same category (server rule).',
                    ws, nm, tostring(st), tostring(et)));
            end
        end
    end

    for _, nm in ipairs(r.missing) do
        emit(string.format('[dlac] lockstyle: "%s" did not resolve to an item id -- its slot will show EMPTY.', nm));
    end

    if not inject(pkt) then
        emit('[dlac] lockstyle: packet send failed.');
        return { ok = false, why = 'packet send failed' };
    end

    local n = 0;
    for _ in pairs(r.sent) do n = n + 1; end
    -- Sender-side send witness: the last REAL apply that reached the SDK this
    -- addon session (the Engine keeps its own M._lsLastSend for its own applies).
    M._lsLastSend = { at = os.clock(), box = boxN, n = n, name = why };
    emit(string.format('[dlac] lockstyle "%s" (box %d) sent -- %d styled slot%s; unnamed slots hold your'
        .. ' current gear\'s look.', tostring(why), boxN, n, n == 1 and '' or 's'));
    return { ok = true, box = boxN, name = why, styled = n, missing = r.missing };
end

-- Sender-side witness accessor (parallels the Engine's debug ls readout; the
-- '/dl debug ls' addon-half integration is a later slice).
function M.lastSend() return M._lsLastSend; end

return M;
