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

-- Headless-safe requires: everything Ashita-side is used at RUN time only,
-- so the module must still LOAD without the client -- that is what lets the
-- smoke suite test the pure parts (parseMeritBonus, the budget model).
pcall(require, 'common');
local _cok, chat = pcall(require, 'chat');
if not _cok then chat = nil; end

-- relocatable require base; setmodel provides the sorted apply layout
local ROOT = (...):sub(1, -#('lib\\blu') - 1);
local setmodel = require(ROOT .. 'lib\\setmodel');

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

-- The 0x102 QUERY: SpellId 0 with NO slots named changes nothing server-side
-- (the unset loop finds nothing) but the handler still answers with the
-- extended-job packet (0x044) -- the refresh opening the native Set Spells
-- menu triggers, and the ONLY thing that recomputes the point cap after a
-- level sync starts or ends (field 2026-08-06: 0x061 does not touch it).
-- DO NOT add a 0x102 "query" here to chase the point cap. That was tried
-- (4430c86) and DISPROVED in the field on 2026-08-06, twice over:
--
--   * The server's answer cannot carry the cap. GP_SERV_COMMAND_EXTENDED_JOB
--     ::BLU writes Job, IsSubJob and SetSpells[20] and leaves its remaining
--     132 bytes untouched -- the point cap NEVER crosses the wire. The
--     client computes max/spent itself, so no packet can refresh them.
--   * The packet is not free. The 0x102 handler ends with an unconditional
--     "force recast on all currently-set blu spells" loop (60s each),
--     whatever the packet asked for -- so a "harmless query" silently locks
--     Blue Magic for a minute, and did so on every window open.
--
-- Probe capture (addons/bdxdiag): two injected 0x102 queries fired straight
-- through a sync transition and the cap did not move; opening the native
-- Set Spells menu moved it with NO packets on the wire at all.
-- 0x061 stays: it genuinely does wake the stale-after-login structs.
function M.requestJobData()
    local ok = pcall(function()
        -- full packet bytes incl. header: id 0x61, size 0x08 (byte1 = size/2)
        AshitaCore:GetPacketManager():AddOutgoingPacket(0x061,
            { 0x61, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
    end);
    return ok;
end

-- ---------------------------------------------------------------------------
-- THE CAP IS CLIENT-SIDE, AND ONLY THE NATIVE MENU RECOMPUTES IT.
--
-- Field 2026-08-06: synced 75 -> 40 and the struct held the level-75 numbers
-- (max=79 spent=79) for seven seconds against a 3-spell set, until the native
-- Set Spells menu was opened -- then both snapped to max=49 spent=7 at once.
-- So after ANY level change the struct describes the PREVIOUS level until the
-- player opens that menu. Nothing we can send changes it.
--
-- We cannot fix it, so we detect it and say so. The cap is trustworthy only
-- while the level still matches the one it was computed at: remember the
-- level each time the client recomputes, and suspect the cap whenever the
-- current level has moved away from it. Returning to that level clears the
-- suspicion by itself -- the untouched cap is correct there again, which is
-- exactly the sync-down-and-back case.
-- ---------------------------------------------------------------------------
-- verified: we WATCHED the client recompute this value. A value merely
-- found sitting there at load looks identical but may be hours stale.
local capWatch = { max = nil, lvl = nil, suspect = false, verified = false };

-- THE BUDGET, in three named parts. Only the base is derivable; the other
-- two are read or measured, and they are NEVER lumped together (doing that
-- produced a 133-point budget against a true 79 on 2026-08-06).
--
--     cap(level) = base(level) + learnedBonus + merits, merits only at 75+
--
--   learnedBonus  CatsEyeXI's award for spells learned, from Boruko in Aht
--                 Urghan Whitegate. Up to 25. Applies at EVERY level, level
--                 sync included -- so below 75 it is the ONLY thing above
--                 the base rule, and one reading there gives it outright.
--   merits        Assimilation (job group 2), 2 points each, 5 max = 10.
--                 Server-side these apply ONLY at level 75.
--
-- Henrik 2026-08-06: at Lv40 the client read 49, base 25 -> bonus 24. At
-- Lv75 it read 79, base 45 -> merits = 79 - 45 - 24 = 10, his five merits.
M.learnedBonus = nil;  -- points from spells learned (nil = not known yet)
M.meritPts     = nil;  -- Assimilation points (nil = not known yet)
M.onCapLearn   = nil;  -- host sets this to persist a new reading

-- Packet 0x063 MISCDATA type 0x02 carries a `bluBonus` field, which arrives
-- by itself at login, on every zone, and on any merit change -- nothing is
-- ever sent to ask for it.
--
--   0x063_miscdata_merits.h, after the 4-byte packet header:
--     0x04 type (0x02 = merits)   0x08 limitPoints
--     0x0A uint16 bitfield: meritPoints:7, bluBonus:6, then three flags
--
-- CAUTION: on CatsEyeXI this field is NOT the merit points. Stock LSB fills
-- it from GetMeritValue(MERIT_ASSIMILATION) alone, but Henrik's client sent
-- 34 where his merits are worth 10 -- CEXI folds the learned bonus in too.
-- So it equals learnedBonus + merits, and is only useful for CROSS-CHECKING
-- the two numbers we track separately. Never treat it as either one.
function M.parseMeritBonus(data)
    if type(data) ~= 'string' or #data < 0x0C then return nil; end
    if data:byte(0x04 + 1) ~= 0x02 then return nil; end   -- not the merits variant
    local lo, hi = data:byte(0x0A + 1), data:byte(0x0B + 1);
    if lo == nil or hi == nil then return nil; end
    return math.floor((lo + hi * 256) / 128) % 64;        -- (w >> 7) & 0x3F
end

-- true when a level change has happened and the client has not recomputed
-- since: max (and spent) still belong to the level we left.
function M.capStale()
    return capWatch.suspect;
end

-- the level the current cap was computed for (nil until first seen)
function M.capLevel()
    return capWatch.lvl;
end

-- the client's own cap as the watch last observed it (nil until first seen)
function M.capValue()
    return capWatch.max;
end

-- THE MERITS, READ ON ZONING (packet 0x08C, the approach dlac's meritwatch
-- proved). This is the one that actually reports Assimilation: 0x063 gives
-- the two summed and can never split them, while 0x08C carries the per-merit
-- ALLOCATIONS, and CatsEyeXI pushes the full list at EVERY ZONE-IN (plus a
-- single-entry update whenever a merit is raised or lowered). Nothing is
-- requested -- the merit system is push-only.
--
--   u16 count; u16 pad; { u16 id; u8 next; u8 count } x count
--
-- Merit ids are even on the wire; an ODD id is the full-removal flag (id|1),
-- meaning that merit is back to zero.
M.MERIT_ASSIMILATION = 3014;   -- merits.sql 3014 = MCATEGORY_BLU_2 + 0x06
M.meritValue         = 2;      -- CatsEyeXI pays 2 points per merit (stock: 1)
M.meritCount         = nil;    -- merits ALLOCATED, straight off 0x08C
M.meritValueProven   = false;  -- true once meritValue is measured, not assumed

-- Pure parser: 0x08C wire data (header included) -> the Assimilation merit
-- COUNT, or nil when this packet carries no Assimilation entry. Bounds-
-- checked per entry, so a short or legacy packet can never over-read.
function M.parseMeritCount(data)
    if type(data) ~= 'string' or #data < 0x0C then return nil; end
    local n = (data:byte(0x04 + 1) or 0) + (data:byte(0x05 + 1) or 0) * 256;
    local found = nil;
    for i = 0, n - 1 do
        local off = 0x08 + i * 4;
        if off + 4 > #data then break; end
        local id = (data:byte(off + 1) or 0) + (data:byte(off + 2) or 0) * 256;
        local removed = (id % 2 == 1);
        if removed then id = id - 1; end
        if id == M.MERIT_ASSIMILATION then
            found = removed and 0 or (data:byte(off + 4) or 0);
        end
    end
    return found;
end

-- Reconcile the three figures. The MERITS are authoritative -- 0x08C reports
-- the allocations themselves -- and the wire total is bonus + merits, so the
-- learned bonus is simply the remainder, RECOMPUTED every time either input
-- moves. That is what makes a Boruko visit cost a zone rather than a trip to
-- the set menu: collect the points, zone, and the new total arrives with the
-- merits still known, so the bonus follows by subtraction.
-- Returns true when something changed.
local function reconcile()
    if M.wireTotal == nil then return false; end
    -- All three known? Then the per-merit rate is MEASURED, not assumed:
    -- 0x08C gives the allocations, a sub-75 reading gives the learned bonus
    -- on its own, and the rest of the wire total is what the merits are
    -- worth. Proves (or corrects) the +2 CatsEyeXI is believed to pay.
    if M.meritCount ~= nil and M.meritCount > 0 and M.learnedBonus ~= nil then
        local worth = M.wireTotal - M.learnedBonus;
        if worth >= 0 and (worth % M.meritCount) == 0 then
            local per = worth / M.meritCount;
            if per > 0 then
                M.meritValue = per;
                M.meritValueProven = true;
                if M.meritPts ~= worth then M.meritPts = worth; return true; end
                return false;
            end
        end
    end
    if M.meritPts ~= nil then
        local b = M.wireTotal - M.meritPts;
        if b >= 0 and M.learnedBonus ~= b then M.learnedBonus = b; return true; end
        return false;
    end
    if M.learnedBonus ~= nil then
        local m = M.wireTotal - M.learnedBonus;
        if m >= 0 and M.meritPts ~= m then M.meritPts = m; return true; end
    end
    return false;
end

-- One 0x08C landed. Merit COUNTS are level-independent -- unlike 0x063's
-- total, the server does not zero them under a sync -- so this is believed
-- at any level. With the merits known, one 0x063 completes the set.
function M.setMeritCount(count)
    if count == nil then return false; end
    M.meritCount = count;
    local pts = count * M.meritValue;
    local moved = (M.meritPts ~= pts);
    M.meritPts = pts;
    -- reconcile may correct meritValue (and so meritPts) from the real numbers
    local fixed = reconcile();
    return moved or fixed;
end

-- The 0x063 reading (standalone only): learnedBonus + merits, summed.
-- Kept purely as a CROSS-CHECK -- it can confirm the pair we track but can
-- never be either of them. Believed only at 75+, where the server sends it.
M.wireTotal = nil;

function M.setWireTotal(n)
    if n == nil then return false; end
    local lvl = M.effectiveLevel();
    if lvl == nil or lvl < 75 then return false; end
    if M.wireTotal == n then return false; end
    M.wireTotal = n;
    reconcile();
    return true;
end

-- cap(level) = base(level) + learnedBonus + merits (merits only at 75+).
-- nil while a term that applies at this level is still unknown.
function M.expectedCap(level)
    level = level or M.effectiveLevel();
    if level == nil or level < 1 then return nil; end
    if M.learnedBonus == nil then return nil; end
    local total = setmodel.baseCapAtLevel(level) + M.learnedBonus;
    if level < 75 then return total; end
    if M.meritPts == nil then return nil; end
    return total + M.meritPts;
end

-- The budget to PLAN A RUNG with (setmodel.LEVELS: 1/11/.../71). A rung is a
-- band -- 41 covers 41-50 -- and a band shares one base, so the rung's own
-- level answers for all of it. The top band is the exception: it runs 71-75
-- and the Assimilation merits switch on at 75, so that is the level it is
-- planned at (a Lv.71 build IS the level-75 build).
--
-- Returns cap, source:
--   'model'  both parts known -- ours, and right at every rung
--   'base'   the server's base rule alone, a FLOOR: this character's learned
--            bonus is not measured yet, so the real cap is higher than this.
function M.rungCap(level)
    if level == nil or level < 1 then return nil, nil; end
    local est = M.expectedCap(level >= setmodel.TOP and 75 or level);
    if est ~= nil then return est, 'model'; end
    return setmodel.baseCapAtLevel(level), 'base';
end

-- The budget to SHOW. The client's own number while it is trustworthy;
-- otherwise the model for the level we are actually standing at.
-- Returns value, source: 'live' | 'model' | 'stale' (nothing better known).
-- OURS WINS once both parts are known (Henrik's call 2026-08-06, and the
-- evidence backs it): the client's number is a cache that goes stale on
-- every level change, while ours is recomputed from the level each frame.
-- Once a zone has given the merits and one recompute has given the learned
-- bonus, our answer is right at every level and the client's is right only
-- until you sync.
--
-- The exception is the useful one: if the client's value is FRESH -- it just
-- recomputed, so it describes this very level -- and still disagrees with
-- ours, then OUR MODEL IS WRONG. Defer to the client and let the UI say so,
-- rather than quietly overriding the game with arithmetic.
function M.budget(levelIn)
    -- capWatch.max is the client's value AS OBSERVED by the watch (which runs
    -- every frame from host.tick) -- the same number points() returns, but the
    -- one the freshness flags actually describe.
    local mx  = capWatch.max;
    local est = M.expectedCap(levelIn);
    local fresh = (mx ~= nil) and not capWatch.suspect;
    if est ~= nil then
        -- the client only outranks us when we actually WATCHED it recompute
        -- at this level. A value merely found at load proves nothing -- it is
        -- most likely the level sync's leftover (field 2026-08-06: 49 sitting
        -- there at Lv75 after a reload, while ours correctly said 79).
        if fresh and capWatch.verified and mx ~= est then return mx, 'live'; end
        return est, 'model';
    end
    if fresh then return mx, 'live'; end
    if mx ~= nil then return mx, 'stale'; end
    return nil, nil;
end

-- true when the client's number and ours differ. verified says whether the
-- client's was WATCHED being recomputed at this level: if it was, our model
-- is wrong; if it was not, the client is simply out of date and one visit to
-- the set menu settles it.
function M.capDisagrees(levelIn)
    local mx, est = capWatch.max, M.expectedCap(levelIn);
    if mx == nil or est == nil or capWatch.suspect then return false, false; end
    return mx ~= est, capWatch.verified;
end

-- Call once per frame (host.tick does). Cheap: two reads and a compare.
-- mxIn/lvlIn override the live reads so the suite can drive it (this
-- function has been the source of three separate field bugs; it is not
-- allowed to stay untestable).
--
-- The rule it exists to enforce: the client's cap is trustworthy ONLY while
-- our level still matches the level it was computed at. Everything below is
-- about not mistaking something else for a recompute.
function M.watchCap(mxIn, lvlIn)
    local testing = (mxIn ~= nil or lvlIn ~= nil);
    if not testing and not M.onBlu() then capWatch.suspect = false; return; end
    local mx  = testing and mxIn or M.points();
    local lvl = testing and lvlIn or M.effectiveLevel();

    -- An EMPTY struct is not a reading. It reads empty through a zone
    -- handoff and at login, and treating the nil -> value bounce as a
    -- recompute is how a Lv40 cap of 49 got adopted as correct for Lv75
    -- after zoning out of a sync (field 2026-08-06). Hold everything.
    if mx == nil then return; end

    -- The FIRST real reading is not a transition either -- it is merely the
    -- first time we looked, and the value may have been stale for hours.
    -- Baseline it, never learn from it (this produced a bogus 54-point
    -- learned bonus, and a 133-point budget with it).
    if capWatch.max == nil then
        capWatch.max, capWatch.lvl, capWatch.suspect = mx, lvl, false;
        capWatch.verified = false;      -- found sitting there, not witnessed
        return;
    end

    if mx ~= capWatch.max then
        -- A real value -> value change: the client recomputed just now, for
        -- the level we are standing at. The one instant its number is known
        -- to describe our level -- so measure while it is true.
        capWatch.max, capWatch.lvl, capWatch.suspect = mx, lvl, false;
        capWatch.verified = true;       -- we watched this one happen
        if lvl ~= nil and lvl >= 1 then
            local rest, moved = mx - setmodel.baseCapAtLevel(lvl), false;
            if lvl < 75 then
                -- Merits do not apply here, so what is left above the base IS
                -- the learned bonus, with no assumption in it at all: 49 - 25
                -- = 24. This is the reading that SETTLES a fresh character --
                -- until it lands, the split of 0x063's total rests on the
                -- believed per-merit rate, and reconcile can now measure that
                -- rate from this bonus and correct the merits with it.
                if rest >= 0 and M.learnedBonus ~= rest then
                    M.learnedBonus = rest; moved = true;
                end
                if reconcile() then moved = true; end
            else
                -- At 75 every term applies, so what sits above the base IS
                -- bonus + merits -- the very number 0x063 carries. Take it
                -- from the client's own cap instead of waiting for the
                -- packet: 79 - 45 = 34. This is what lets the dlac flavor,
                -- which has no packet hook at all, reach the same answer
                -- from two menu visits (one at 75, one under a sync).
                if rest >= 0 and M.wireTotal ~= rest then
                    M.wireTotal = rest; moved = true;
                end
                if reconcile() then moved = true; end
            end
            if moved and M.onCapLearn ~= nil then pcall(M.onCapLearn); end
        end
        return;
    end

    -- Unchanged value: trustworthy only if we are still at its level.
    if lvl == nil or capWatch.lvl == nil then return; end
    capWatch.suspect = (lvl ~= capWatch.lvl);
end

-- Forget everything learned about this character's point budget: both
-- figures, the merit allocations behind them, the measured per-merit rate,
-- and the watch's idea of what the client last reported. Returns what was
-- discarded so the caller can show it. Everything re-derives itself -- the
-- merits and the server total from one zone, the learned bonus from the next
-- level sync or Set Spells visit.
function M.forgetBudget()
    local had = {
        bonus  = M.learnedBonus, merits = M.meritPts, count = M.meritCount,
        wire   = M.wireTotal,    rate   = M.meritValue,
        proven = M.meritValueProven,
    };
    M.learnedBonus, M.meritPts, M.meritCount, M.wireTotal = nil, nil, nil, nil;
    M.meritValue, M.meritValueProven = 2, false;
    M.resetCapWatch();
    return had;
end

-- test seam: forget everything the watch has observed
function M.resetCapWatch()
    capWatch = { max = nil, lvl = nil, suspect = false };
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
--
-- Returns nil (no change) or the KIND of change, so the caller can react by
-- direction: 'jobs' (main/sub identity moved), 'up' / 'down' (pure level
-- movement, the BLU-relevant level when on BLU). A falsy check still works
-- for callers that only care THAT something changed.
local watched = nil;
function M.watchJobState()
    local ok, jobs, lvl = pcall(function()
        local p = player();
        local main, sub = p:GetMainJob(), p:GetSubJob();
        local l = (main == 16 and p:GetMainJobLevel())
            or (sub == 16 and p:GetSubJobLevel())
            or p:GetMainJobLevel();
        return ('%d/%d'):format(main, sub), l;
    end);
    if not ok or jobs == nil then return nil; end
    -- Level 0 is NOT a level change -- it is the client mid-handoff. Probe
    -- capture 2026-08-06: one level sync produced 75 -> 0 -> 75 -> 40, three
    -- "changes" where the player experienced one, each firing a refresh (and,
    -- while the 0x102 query existed, a 60s Blue Magic recast). Treat an
    -- unreadable level as no reading at all: hold the baseline and wait.
    if lvl == nil or lvl <= 0 then return nil; end
    if watched == nil then watched = { jobs = jobs, lvl = lvl }; return nil; end
    if jobs == watched.jobs and lvl == watched.lvl then return nil; end
    local kind = 'jobs';
    if jobs == watched.jobs then
        kind = (lvl > watched.lvl) and 'up' or 'down';
    end
    watched = { jobs = jobs, lvl = lvl };
    if M.onBlu() then M.requestJobData(); end
    return kind;
end

-- Forget the observed job identity. For a character switch: the character
-- coming in must set a fresh baseline, not read as the previous one having
-- changed jobs (which would arm the level-change restore for them).
function M.resetJobWatch()
    watched = nil;
end

function M.canApply()
    return sig.equipex ~= nil and sig.offset ~= nil and M.onBlu();
end

local function msg(s)
    if chat == nil then print('[bludex] ' .. tostring(s)); return; end
    print(chat.header('bludex'):append(chat.message(s)));
end

-- the one chat voice, exported: the host's level-change watcher speaks
-- through it so every bludex line wears the same header
function M.announce(s)
    msg(s);
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
-- layoutT (optional) is a caller-computed 20-slot target layout
-- (setmodel.applyLayout: a timeline set's slots are authorship and must
-- not be re-sorted); without it the sorted-placement law applies.
function M.applyDiff(ids, book, onDone, layoutT)
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
    local live = M.currentSet();
    if #live ~= 20 then
        msg('Could not read the live set - doing a full reset + apply instead.');
        return M.applySet(ids, book, onDone);
    end
    -- The target LAYOUT: the caller's (a timeline set's slot authorship),
    -- else level-sorted (field 2026-08-04: the game's own set list should
    -- read in level order -- slot i holds the i-th lowest learned spell).
    -- Slot-wise diff against it -- a matching slot costs nothing; a spell
    -- in the wrong slot is an unset plus a set (the client refuses a spell
    -- set twice, so every unset goes first).
    local T = layoutT or setmodel.sortedLayout(ids, book);
    local removes, adds, kept = {}, {}, 0;
    for slot = 1, 20 do
        local have = live[slot] or 0;
        if have == T[slot] then
            if have ~= 0 then kept = kept + 1; end
        else
            if have ~= 0 then removes[#removes + 1] = slot; end
            if T[slot] ~= 0 then adds[#adds + 1] = { slot = slot, id = T[slot] }; end
        end
    end
    if #removes == 0 and #adds == 0 then
        msg('The live set already matches - nothing to send.');
        if onDone then pcall(onDone); end
        return true;
    end
    local delay = stepDelay();
    M.applying = true;
    ashita.tasks.once(1, function()
        for _, slot in ipairs(removes) do
            M.setSlot(slot, 0);
            coroutine.sleep(delay);
        end
        for _, e in ipairs(adds) do        -- ascending slot = ascending level
            M.setSlot(e.slot, e.id);
            coroutine.sleep(delay);
        end
        M.applying = false;
        msg(('Set updated: %d placed (level order), %d cleared, %d kept. Spells castable in ~%ds.'):format(
            #adds, #removes, kept, M.castLock));
        if onDone then pcall(onDone); end
    end);
    return true;
end

-- The effective BLU level RIGHT NOW -- the synced level when a level sync
-- is on (the client reports the adjusted level). nil off BLU / unreadable.
function M.effectiveLevel()
    local ok, lvl = pcall(function()
        local p = player();
        if p:GetMainJob() == 16 then return p:GetMainJobLevel(); end
        if p:GetSubJob() == 16 then return p:GetSubJobLevel(); end
        return nil;
    end);
    if not ok or lvl == nil or lvl <= 0 then return nil; end
    return lvl;
end

-- BOTH jobs and BOTH levels, for the trait-collision model: a blue trait is
-- killed by the same trait coming from either job (lib/traitsource.lua), so
-- the whole pair matters, not just whichever side is BLU. All four nil off a
-- readable character; sub job 0 = no sub job.
function M.jobPair()
    local ok, r = pcall(function()
        local p = player();
        return {
            mainJob = p:GetMainJob(), mainLevel = p:GetMainJobLevel(),
            subJob = p:GetSubJob(), subLevel = p:GetSubJobLevel(),
        };
    end);
    if not ok or r == nil then return nil; end
    return r;
end

-- IS THIS TRAIT UP RIGHT NOW -- the server's own answer, not ours.
-- The server builds the merged trait list (job traits then blue) and ships it
-- as a bit mask on packet 0x0AC, which the client keeps in its command table
-- with job traits based at 0x600. So ability id 1536 + traitId is the live
-- bit; dlac reads 1554 for Dual Wield the same way.
--
-- It is the REFEREE, never the source: blue traits set these same bits, so a
-- lit bit says "you have it" and nothing about where it came from.
-- true / false, or nil when unreadable.
function M.hasTrait(traitId)
    if traitId == nil then return nil; end
    local ok, r = pcall(function()
        return player():HasAbility(1536 + traitId) == true;
    end);
    if not ok then return nil; end
    return r;
end

-- The level-sync view of the LIVE set: what the client holds right now.
-- Part of the read surface, currently drawn by nothing: the header used to
-- carry it as a second pair of meters beside the editing build's, and one
-- pair that describes where you are said it better (Henrik 2026-08-07).
-- Under a sync the client's set struct keeps only the spells the level
-- still enables (field 2026-08-06), so this is simply the live set counted
-- and costed, with the server's slot rule for the level. nil off BLU, when
-- the set is unreadable, or when the level cannot be read.
function M.syncStats(book)
    local lvl = M.effectiveLevel();
    if lvl == nil then return nil; end
    local live = M.currentSet();
    if #live ~= 20 then return nil; end
    local active, pts = 0, 0;
    for i = 1, 20 do
        local id = live[i] or 0;
        if id ~= 0 then
            active = active + 1;
            local s = book and book.spells and book.spells[id];
            if s ~= nil then pts = pts + (s.setPoints or 0); end
        end
    end
    return {
        level = lvl,
        active = active,
        activePoints = pts,
        maxSlots = setmodel.slotsAtLevel(lvl),
    };
end

-- The level-DOWN report: a level decrease (sync down, delevel) sends NO
-- packets -- the client disables over-level spells itself and re-enables
-- them when the level returns, and the set is level-sorted so the survivors
-- already sit in the low slots. This only tells the user where the set
-- stands now. Quiet off BLU, when the set is unreadable, and when the new
-- level disables nothing (Henrik 2026-08-06: no noise unless it matters).
function M.reportLevelDown(book)
    if not M.onBlu() then return; end
    local live = M.currentSet();
    if #live ~= 20 then return; end
    local lvl = M.effectiveLevel();
    if lvl == nil then return; end
    local filled, disabled = 0, 0;
    for i = 1, 20 do
        local id = live[i] or 0;
        if id ~= 0 then
            filled = filled + 1;
            local s = book and book.spells and book.spells[id];
            if s ~= nil and s.level ~= nil and s.level > lvl then
                disabled = disabled + 1;
            end
        end
    end
    if disabled == 0 then return; end
    local free = 20 - filled;
    msg(('Level down to %d: the game disabled %d of %d set spells (above level) - nothing was sent, they return when the level does. %d castable%s.'):format(
        lvl, disabled, filled, filled - disabled,
        free > 0 and (', %d slots free'):format(free) or ''));
end

-- THE ADDS-ONLY RESTORE, back from its 2026-08-08 retirement (docs/
-- set-types-plan.md: the LEVELS kind keeps the old promise -- a level
-- change puts spells back and never takes any away -- while the timeline
-- kind keeps its re-plan. Which one runs is decided by the followed set's
-- kind in ui/host.lua, never both.)
--
-- Position-independent plan against the live set: targets are matched by
-- spell IDENTITY, not slot -- a level-change restore must put spells back
-- without reshuffling the set. Missing spells are paired lowest-level-first
-- with the lowest open slots. Returns nil when the live set is unreadable.
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
