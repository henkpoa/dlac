--[[
    dlac/fishwatch.lua -- fishing gear state + venture/GP glue
    (docs/design/fishing-gear.md; the craftwatch/helmwatch third sibling).

    Same philosophy: don't fight the engine, BE the engine. This module WRITES
    <char>\dlac\fishstate.lua { enabled, at, target, rod, bait }; the dispatch
    ENGINE (v64) overlays fishing gear on Default only, standing aside in
    combat. Flip the pill off -> no overlay -> normal idle gear returns. No
    commands, no locks, and NO automation of fishing itself: this module never
    casts, never reacts to bites -- it dresses the player and informs.

    Rod + bait are TARGET-FISH-specific: fishcalc ranks every rod with the
    server's own fail math (line snap / rod break / lose) and the bait picker
    prefers the target's best-power owned bait; both land in fishstate as
    CLIENT item names for the engine to wear. A ~2s bag heartbeat re-picks
    when the rod vanishes or the bait stack runs dry (the overlay re-asserts
    per dispatch, so a fresh stack of the SAME bait re-equips with no help).

    Venture points: helmwatch already speaks the 0x1A4 protocol and stores
    EVERY group/label -- 'Fishing' included (field-confirmed 2026-07-17) --
    so this module just reads through it. Guild points: craftwatch's 0x113
    parser carries the fishing guild at offset 0x20 (fishing guild id 0
    server-side). Today's ventures: same 0x017 capture trick as HELM, with
    the fishing reply format FIELD-CONFIRMED 2026-07-18 (the HELM line shape
    holds) -- raw lines still mirror to fishventures_capture.txt as drift
    insurance, 'Fishing:' lines parse structurally.

    Pure helpers are headless-testable; Ashita glue guarded at the bottom.
]]--

local M = {};

local _fcok, fc = pcall(require, 'dlac\\feature\\fishcalc');
_fcok = _fcok and type(fc) == 'table';

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function say(s) if _cfok and _cfmt.msg then _cfmt.msg(s); else print('[dlac] ' .. s); end end

-- <char>\dlac\ dir: the one addon-side copy (lib\statefile). nil pre-login.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir
    or function() return nil; end;
M._charDir = charDir;   -- test seam

-- Fixed-width, NUL-terminated string field (0x017 / 0x0B5 payloads).
local function u8(data, off) return string.byte(data, off + 1) or 0; end
local function zstr(data, off, maxLen)
    local out = {};
    for i = 1, maxLen do
        local b = string.byte(data, off + i);
        if b == nil or b == 0 then break; end
        out[#out + 1] = string.char(b);
    end
    return table.concat(out);
end

-- Client display name for an item id -- fishstate must carry the names LAC
-- equips by (the client's), not fishdb's SQL prettifications ("Lu Shangs
-- F. Rod" vs "Lu Shang's Fishing Rod"). Called through M so the headless
-- tests can override it (the helmwatch seam rule).
function M._clientName(id)
    local n = nil;
    pcall(function()
        local res = AshitaCore:GetResourceManager():GetItemById(id);
        if res ~= nil and res.Name ~= nil then n = res.Name[1]; end
    end);
    return n;
end

-- Equippable-bag counts (id -> n) from ownedcache; nil when unavailable
-- (headless / pre-login) -- callers must treat nil as "cannot tell, change
-- nothing" (the ADR 0007 rule: not-ready state is not an answer).
local function ownedAvail()
    if M._ownedAvail ~= nil then return M._ownedAvail; end   -- test seam
    local counts = nil;
    pcall(function()
        local oc = require('dlac\\gear\\ownedcache');
        local t = oc.counts();
        if type(t) == 'table' then counts = t; end
    end);
    return counts;
end

-- ---------------------------------------------------------------------------
-- MANUAL fishing control (the craftstate rule). `enabled` is the "Set Fish
-- Idle" pill: session-only ON PURPOSE -- no fishing gear glued on at login.
-- target/rod/bait persist (your project fish survives a relog); `at` is the
-- enable stamp, the engine's three-way arbitration key (v64).
-- ---------------------------------------------------------------------------
M.barVisible = false;
M.enabled = false;
M.target = nil;         -- fishdb fish id (nil = no target: gear + best generic rod)
M.targetName = nil;     -- display name (fishdb)
M.rodId, M.rod = nil, nil;     -- chosen rod: item id + CLIENT name
M.baitId, M.bait = nil, nil;   -- chosen bait: item id + CLIENT name
M.rodPin, M.baitPin = false, false;   -- manual dropdown picks (beat auto while owned)
M._enabledAt = 0;
M._rescanned = false;
local _stateLoaded = false;

local function statePath()
    local dir = charDir();
    return dir and (dir .. 'fishstate.lua') or nil;
end
local function saveState()
    pcall(function()
        local p = statePath();
        if p == nil then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(string.format(
            'return { enabled = %s, at = %d, target = %d, targetName = %q, rod = %q, bait = %q,'
            .. ' rodId = %d, baitId = %d, rodPin = %s, baitPin = %s }\n',
            tostring(M.enabled == true), M._enabledAt or 0, M.target or 0,
            tostring(M.targetName or ''), tostring(M.rod or ''), tostring(M.bait or ''),
            M.rodId or 0, M.baitId or 0,
            tostring(M.rodPin == true), tostring(M.baitPin == true)));
        f:close();
    end);
end
M._saveState = saveState;   -- test seam

function M.loadState()
    if _stateLoaded then return; end
    local dir = charDir();
    if dir == nil then return; end        -- pre-login: retry next call
    _stateLoaded = true;
    pcall(function()
        local chunk = loadfile(dir .. 'fishstate.lua');
        if chunk ~= nil then
            local ok, t = pcall(chunk);
            if ok and type(t) == 'table' then
                -- The pill is NOT restored (craftstate rule). Target and the
                -- resolved rod/bait persist -- the project fish survives.
                if type(t.target) == 'number' and t.target > 0 then M.target = t.target; end
                if type(t.targetName) == 'string' and t.targetName ~= '' then M.targetName = t.targetName; end
                if type(t.rod) == 'string' and t.rod ~= '' then M.rod = t.rod; end
                if type(t.bait) == 'string' and t.bait ~= '' then M.bait = t.bait; end
                if type(t.rodId) == 'number' and t.rodId > 0 then M.rodId = t.rodId; end
                if type(t.baitId) == 'number' and t.baitId > 0 then M.baitId = t.baitId; end
                M.rodPin = t.rodPin == true;
                M.baitPin = t.baitPin == true;
            end
        end
    end);
    M.enabled = false;
    saveState();                          -- sync the file for the engine
end

-- Manifest freshness (helmwatch clone): the fmtver-8 fish ladders must exist
-- before the engine reads them.
local function ensureManifestFresh()
    local first = not M._rescanned;
    M._rescanned = true;
    pcall(function()
        local au = require('dlac\\ui\\automationsui');
        if type(au.rescanAutogear) ~= 'function' then return; end
        local stale = first;
        if not first then
            pcall(function()
                if type(au.manifestStale) == 'function' then stale = au.manifestStale(); end
            end);
        end
        if stale then au.rescanAutogear(); end
    end);
end

function M.isEnabled() M.loadState(); return M.enabled == true; end
function M.getTarget() M.loadState(); return M.target, M.targetName; end
function M.getRod() M.loadState(); return M.rodId, M.rod; end
function M.getBait() M.loadState(); return M.baitId, M.bait; end

-- ---------------------------------------------------------------------------
-- Skill (the craftwatch memory path with the index it deliberately skipped:
-- Ashita craftskills_t order puts Fishing at 0, Woodworking=1 ... Cooking=8).
-- ---------------------------------------------------------------------------
function M.playerFishSkill()
    local v = nil;
    pcall(function()
        local cs = AshitaCore:GetMemoryManager():GetPlayer():GetCraftSkill(0);
        if cs ~= nil then v = cs:GetSkill(); end
    end);
    return v;
end
function M.playerFishRank()
    local r = nil;
    pcall(function()
        local cs = AshitaCore:GetMemoryManager():GetPlayer():GetCraftSkill(0);
        if cs ~= nil and cs.GetRank ~= nil then r = cs:GetRank(); end
    end);
    return r;
end

-- ---------------------------------------------------------------------------
-- Rod + bait resolution. Pure ranking lives in fishcalc; THIS side supplies
-- ownership + the live skill and stamps CLIENT names into the state.
-- ---------------------------------------------------------------------------

-- Owned rod set { [id]=true } from bag counts (nil counts -> nil).
local function ownedRodSet(avail)
    local db = _fcok and fc.db() or nil;
    if db == nil or avail == nil then return nil; end
    local set = nil;
    for id in pairs(db.rods) do
        if (avail[id] or 0) > 0 then set = set or {}; set[id] = true; end
    end
    return set;
end

-- Pick rod + bait for the current target from what the bags hold. keepBait:
-- an explicit still-stocked bait choice survives re-picks (the user picked an
-- ISOLATION bait; silently trading it for a higher-power one would defeat
-- the point). Returns true when anything changed.
function M.autoPick(keepBait)
    local db = _fcok and fc.db() or nil;
    if db == nil then return false; end
    local avail = ownedAvail();
    if avail == nil then return false; end   -- cannot tell: change nothing
    local changed = false;
    local skill = M.playerFishSkill() or 0;
    local f = (M.target ~= nil) and db.fish[M.target] or nil;

    -- Rod: a MANUAL pick (fish bar dropdown) holds while it's in the bags;
    -- otherwise verdict-best owned for the target, or -- no target -- the
    -- legendary tier first (Ebisu > Lu Shang's, always preferred), then
    -- highest server rating (the generic "best fishing rod you have").
    local rodPinned = M.rodPin == true and M.rodId ~= nil and (avail[M.rodId] or 0) > 0;
    local newRodId = nil;
    local rods = (not rodPinned) and ownedRodSet(avail) or nil;
    if rods ~= nil then
        if f ~= nil then
            local best = fc.bestOwnedRod(f, skill, rods);
            if best ~= nil then newRodId = best.id; end
        else
            local bestRank, bestRating = -1, -1;
            for id in pairs(rods) do
                local r = db.rods[id];
                local rank = (type(fc.legRank) == 'function') and fc.legRank(id) or 0;
                local rating = (r and r.rating) or 0;
                if rank > bestRank or (rank == bestRank and rating > bestRating) then
                    bestRank, bestRating, newRodId = rank, rating, id;
                end
            end
        end
    end
    if newRodId ~= nil and newRodId ~= M.rodId then
        M.rodId = newRodId;
        M.rod = M._clientName(newRodId) or (db.rods[newRodId] or {}).n;
        changed = true;
    end

    -- Bait: only meaningful with a target (generic bait guessing would just
    -- burn stacks). Keep a still-stocked explicit choice; else best power
    -- owned for the target.
    if f ~= nil then
        -- A pinned bait is absolute while stocked (manual beats automation,
        -- even off-affinity: the user may know something fishdb doesn't).
        local baitPinned = M.baitPin == true and M.baitId ~= nil and (avail[M.baitId] or 0) > 0;
        local keep = baitPinned
                     or (keepBait == true and M.baitId ~= nil and (avail[M.baitId] or 0) > 0
                         and (db.aff[M.baitId] or {})[M.target] ~= nil);
        if not keep then
            local pick = nil;
            for _, e in ipairs(fc.baitsFor(M.target)) do
                if (avail[e.id] or 0) > 0 then pick = e.id; break; end
            end
            if pick ~= M.baitId then
                M.baitId = pick;
                M.bait = pick ~= nil and (M._clientName(pick) or (db.baits[pick] or {}).n) or nil;
                changed = true;
            end
        end
    end
    return changed;
end

-- Set (or clear) the target fish. Explicit bait: the panel's isolation rows
-- pass the bait they promised so the pick honours it.
function M.setTarget(fishid, baitid)
    M.loadState();
    local db = _fcok and fc.db() or nil;
    -- Changing (or clearing) the target drops both manual pins: a rod pinned
    -- for carp could SNAP on the new fish -- back to the verdict math.
    if fishid == nil then
        M.target, M.targetName = nil, nil;
        M.baitId, M.bait = nil, nil;
        M.rodPin, M.baitPin = false, false;
        saveState();
        return;
    end
    if db == nil or db.fish[fishid] == nil then return; end
    M.rodPin, M.baitPin = false, false;
    M.target = fishid;
    M.targetName = db.fish[fishid].n;
    if baitid ~= nil and (db.aff[baitid] or {})[fishid] ~= nil then
        M.baitId = baitid;
        M.bait = M._clientName(baitid) or (db.baits[baitid] or {}).n;
    end
    M.autoPick(baitid ~= nil);   -- rod always; bait only if none was forced
    ensureManifestFresh();
    saveState();
end

-- Manual overrides (the fish bar dropdowns -- Henrik's rule: manual beats
-- automation, every day). A pin holds while the item is in the bags; a
-- vanish unpins (the heartbeat falls back to auto), and changing target
-- unpins too. id = nil -> back to auto for that slot.
function M.setRod(id)
    M.loadState();
    local db = _fcok and fc.db() or nil;
    if id == nil then
        M.rodPin = false;
        M.autoPick(true);
        saveState();
        return;
    end
    if db == nil or db.rods[id] == nil then return; end
    M.rodId = id;
    M.rod = M._clientName(id) or (db.rods[id] or {}).n;
    M.rodPin = true;
    saveState();
end
function M.setBait(id)
    M.loadState();
    local db = _fcok and fc.db() or nil;
    if id == nil then
        M.baitPin = false;
        -- auto with no target means NO bait (generic bait guessing burns stacks)
        if M.target == nil then M.baitId, M.bait = nil, nil; end
        M.autoPick(false);
        saveState();
        return;
    end
    if db == nil or db.baits[id] == nil then return; end
    M.baitId = id;
    M.bait = M._clientName(id) or (db.baits[id] or {}).n;
    M.baitPin = true;
    saveState();
end
function M.rodPinned() M.loadState(); return M.rodPin == true; end
function M.baitPinned() M.loadState(); return M.baitPin == true; end

-- The pill (bar + panel). Enabling fishing turns the CRAFT and HELM switches
-- off (one overlay at a time). One-way requires only (neither ever requires
-- fishwatch: no cycle); the reverse directions are settled inside the engine
-- by the state files' `at` stamps (newest wins, v64).
function M.setEnabled(on)
    M.loadState();
    M.enabled = (on == true);
    if M.enabled then
        M._enabledAt = os.time();
        ensureManifestFresh();
        M.autoPick(true);
        pcall(function()
            local cw = require('dlac\\feature\\craftwatch');
            if type(cw.isEnabled) == 'function' and cw.isEnabled()
               and type(cw.setEnabled) == 'function' then cw.setEnabled(false); end
        end);
        pcall(function()
            local hw = require('dlac\\feature\\helmwatch');
            if type(hw.isEnabled) == 'function' and hw.isEnabled()
               and type(hw.setEnabled) == 'function' then hw.setEnabled(false); end
        end);
    end
    saveState();
end

-- Bag heartbeat: while dressed, re-rank EVERY beat (field round 5: the old
-- vanish-only check meant a rod added to an empty hand -- or Lu Shang's
-- returning over a base rod -- sat unnoticed until a pill toggle). A better
-- rod arriving in your bags is adopted on the spot; manual pins stay put
-- while owned; a same-name bait restock still needs nothing (the overlay
-- re-asserts the name every dispatch and LAC pulls the next stack).
function M.revalidate()
    M.loadState();
    if not M.enabled then return; end
    local avail = ownedAvail();
    if avail == nil then return; end
    local rodGone = M.rodId ~= nil and (avail[M.rodId] or 0) == 0;
    local baitGone = M.baitId ~= nil and (avail[M.baitId] or 0) == 0;
    -- a pin can't hold air: vanished manual picks fall back to auto
    if rodGone then M.rodPin = false; end
    if baitGone then M.baitPin = false; end
    local oldRodId, oldBait = M.rodId, M.bait;
    if rodGone then M.rodId, M.rod = nil, nil; end
    if baitGone then M.baitId, M.bait = nil, nil; end
    -- keepBait unless the BAIT is what emptied: a rod-side change must never
    -- trade the user's explicit isolation bait up to a stronger one (the
    -- whole point of keepBait; false here did exactly that, silently).
    local changed = M.autoPick(not baitGone);
    if not changed and not rodGone and not baitGone then return; end
    if M.rodId ~= oldRodId then
        if rodGone then
            say(string.format('fishing rod gone -- switched to %s.', tostring(M.rod or 'nothing')));
        elseif oldRodId == nil then
            say(string.format('rod in your bags -- using %s.', tostring(M.rod)));
        elseif M.rod ~= nil then
            say(string.format('better rod in your bags -- switched to %s.', tostring(M.rod)));
        end
    end
    if M.bait ~= oldBait then
        if M.bait ~= nil then
            say(string.format(baitGone and 'bait ran out -- switched to %s.' or 'bait: now using %s.',
                tostring(M.bait)));
        elseif baitGone then
            say('bait ran out -- nothing suitable left in your bags.');
        end
    end
    saveState();
end

-- ---------------------------------------------------------------------------
-- Venture points (through helmwatch's 0x1A4 store) + guild points (through
-- craftwatch's 0x113 parser, Fishing @0x20).
-- ---------------------------------------------------------------------------
function M.venturePoints()
    local v = nil;
    pcall(function()
        local hw = require('dlac\\feature\\helmwatch');
        v = hw.pointsFor('Fishing');
    end);
    return v;
end
function M.requestPoints(force)
    pcall(function() require('dlac\\feature\\helmwatch').requestPoints(force); end);
end
function M.guildPoints()
    local v = nil;
    pcall(function()
        local cw = require('dlac\\feature\\craftwatch');
        v = cw.guildPointsFor('Fishing');
    end);
    return v;
end
function M.requestGuildPoints(force)
    pcall(function() require('dlac\\feature\\craftwatch').requestGuildPoints(force); end);
end

-- ---------------------------------------------------------------------------
-- Today's fishing ventures -- 0x017 capture (helmwatch's trick, own window +
-- files). Format FIELD-CONFIRMED 2026-07-18 ("works like a charm" -- the
-- HELM line shape holds): 'Fishing:' lines parse structurally, everything
-- venture-ish lands in general, and the raw mirror
-- (fishventures_capture.txt) stays as drift insurance.
-- ---------------------------------------------------------------------------
M.ventures = nil;        -- { day = <JST daystamp>, lines = {..}, general = {..} }
local _capUntil = -1;
local _vLoaded = false;

function M.jstDay(t) return math.floor(((t or os.time()) + 9 * 3600) / 86400); end

local function ventPath() local d = charDir(); return d and (d .. 'fishventures.lua') or nil; end
local function ventSave()
    pcall(function()
        local p = ventPath(); if p == nil or M.ventures == nil then return; end
        local parts = { '-- dlac fishing ventures mirror (0x017-captured)\nreturn {\n' };
        parts[#parts + 1] = string.format('    day = %d,\n', M.ventures.day or 0);
        parts[#parts + 1] = '    lines = {\n';
        for _, ln in ipairs(M.ventures.lines or {}) do parts[#parts + 1] = string.format('        %q,\n', ln); end
        parts[#parts + 1] = '    },\n    general = {\n';
        for _, ln in ipairs(M.ventures.general or {}) do parts[#parts + 1] = string.format('        %q,\n', ln); end
        parts[#parts + 1] = '    },\n}\n';
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(table.concat(parts));
        f:close();
    end);
end
local function ventLoad()
    if _vLoaded then return; end
    local dir = charDir(); if dir == nil then return; end
    _vLoaded = true;
    pcall(function()
        local chunk = loadfile(dir .. 'fishventures.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' and M.ventures == nil then M.ventures = t; end
    end);
end

-- One server venture line, structurally: 'Fishing: (Low) x, (Mid) y, (High) z'
-- (the pinned HELM shape with the Fishing category). A drifted format keeps
-- the raw tail as one line.
function M.parseVentureLine(msg)
    local cat, rest = tostring(msg or ''):match('^%s*(%a+):%s*(.+)$');
    if cat == nil or string.lower(cat) ~= 'fishing' then return nil; end
    local low, mid, high = rest:match('%(Low%)%s*(.-)%s*,%s*%(Mid%)%s*(.-)%s*,%s*%(High%)%s*(.-)%s*$');
    if low == nil then return { rest }; end
    return { 'Low:  ' .. low, 'Mid:  ' .. mid, 'High: ' .. high };
end

function M.cleanLine(msg)
    local s = tostring(msg or ''):gsub('[^\032-\126]+', ' ');
    s = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '');
    return s;
end

function M.openCapture(seconds)
    _capUntil = os.clock() + (tonumber(seconds) or 6);
    ventLoad();
    local day = M.jstDay();
    if M.ventures == nil or (M.ventures.day or 0) ~= day then
        M.ventures = { day = day, lines = {}, general = {} };
    end
end
function M.captureOpen() return os.clock() < _capUntil; end

function M.onChatLine(chatType, sender, msg)
    if not M.captureOpen() then return; end
    local clean = M.cleanLine(msg);
    if clean == '' then return; end
    pcall(function()
        local dir = charDir(); if dir == nil then return; end
        local f = io.open(dir .. 'fishventures_capture.txt', 'ab');
        if f == nil then return; end
        f:write(string.format('%s  type=%d  sender=%s  |  %s\n',
            os.date('%Y-%m-%d %H:%M:%S'), tonumber(chatType) or -1, tostring(sender or ''), clean));
        f:close();
    end);
    ventLoad();
    local day = M.jstDay();
    if M.ventures == nil or (M.ventures.day or 0) ~= day then
        M.ventures = { day = day, lines = {}, general = {} };
    end
    if clean:find('=== Today', 1, true) ~= nil then return; end   -- banner
    local lines = M.parseVentureLine(clean);
    if lines ~= nil then
        M.ventures.lines = lines;
        ventSave();
        return;
    end
    if clean:lower():find('venture', 1, true) or clean:lower():find('fish', 1, true) then
        for _, ln in ipairs(M.ventures.general) do
            if ln == clean then return; end
        end
        local t = M.ventures.general;
        t[#t + 1] = clean;
        ventSave();
    end
end

-- Panel accessor: today's lines + the day-freshness flag.
function M.venturesFor()
    ventLoad();
    if M.ventures == nil then return nil, false, nil; end
    local fresh = (M.ventures.day or 0) == M.jstDay();
    local lines = M.ventures.lines;
    if lines ~= nil and #lines == 0 then lines = nil; end
    return lines, fresh, M.ventures.general;
end

-- ---------------------------------------------------------------------------
-- Ashita glue (addon state only).
-- ---------------------------------------------------------------------------
if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_in', 'dlac-fishwatch-in', function(e)
        if e.id == 0x017 and M.captureOpen() then
            pcall(function()
                local chatType = u8(e.data, 0x04);
                local sender = zstr(e.data, 0x08, 13);
                local msg = zstr(e.data, 0x17, #e.data - 0x17);
                M.onChatLine(chatType, sender, msg);
            end);
        end
    end);

    ashita.events.register('packet_out', 'dlac-fishwatch-out', function(e)
        if e.id == 0x0B5 then
            -- A typed "!ventures ..." opens the capture window (own window
            -- beside helmwatch's -- each parser keeps only its own lines).
            pcall(function()
                local msg = zstr(e.data, 0x06, math.max(0, #e.data - 0x06));
                if msg:lower():find('^!ventures') ~= nil then M.openCapture(6); end
            end);
        end
    end);

    -- Bag heartbeat (~2s): only does work while the pill is on.
    local _hbAt = 0;
    ashita.events.register('d3d_present', 'dlac-fishwatch-hb', function()
        pcall(function()
            if os.clock() < _hbAt then return; end
            _hbAt = os.clock() + 2;
            if M.enabled then M.revalidate(); end
        end);
    end);

    -- /dl fish [bar | on | off | target <name> | points | gp | capture | status]
    ashita.events.register('command', 'dlac-fishwatch-cmd', function(e)
        pcall(function()
            local raw = tostring(e.command or '');
            local a, rest = string.lower(raw):match('^/dl%s+(%S+)%s*(.*)');
            if a == nil then a, rest = string.lower(raw):match('^/dlac%s+(%S+)%s*(.*)'); end
            if a ~= 'fish' then return; end
            e.blocked = true;
            local b = rest:match('^(%S*)') or '';
            if b == 'bar' then
                M.barVisible = not M.barVisible;
                say('fish bar ' .. (M.barVisible and 'shown' or 'hidden') .. '.');
            elseif b == 'on' or b == 'off' then
                M.setEnabled(b == 'on');
                say('Set Fish Idle ' .. (M.enabled and 'ON' or 'OFF') .. '.');
            elseif b == 'target' then
                local q = rest:match('^%S+%s+(.+)$');
                if q == nil or q == '' then
                    M.setTarget(nil);
                    say('fish target cleared.');
                else
                    local hits = _fcok and fc.searchFish(q) or {};
                    if #hits == 0 then say('no fish matches "' .. q .. '".');
                    else
                        M.setTarget(hits[1].id);
                        say(string.format('fish target: %s (rod: %s, bait: %s).',
                            tostring(M.targetName), tostring(M.rod or '?'), tostring(M.bait or '?')));
                    end
                end
            elseif b == 'points' then
                M.requestPoints(true);
                local v = M.venturePoints();
                say('Fishing venture points: ' .. (v ~= nil and tostring(v) or 'unknown (stream not seen yet)'));
            elseif b == 'gp' then
                M.requestGuildPoints(true);
                local v = M.guildPoints();
                say('Fishing guild points: ' .. (v ~= nil and tostring(v) or 'unknown (no 0x113 seen yet)'));
            elseif b == 'capture' then
                M.openCapture(6);
                say('fishing ventures capture window open (6s) -- type !ventures fishing.');
            else
                local sk = M.playerFishSkill();
                say(string.format('fish: %s | target %s | rod %s | bait %s | skill %s',
                    M.isEnabled() and 'ON' or 'off', tostring(M.targetName or 'none'),
                    tostring(M.rod or 'none'), tostring(M.bait or 'none'),
                    sk ~= nil and tostring(sk) or '?'));
            end
        end);
    end);
end

return M;
