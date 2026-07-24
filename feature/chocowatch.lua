--[[
    dlac/chocowatch.lua -- Chocobo riding-gear state
    (docs/design/chocobo-gear.md; the craft/HELM/fishing fourth sibling).

    Same philosophy: don't fight the engine, BE the engine. This module WRITES
    <char>\dlac\chocostate.lua { enabled, at }; the dispatch ENGINE overlays the
    resolved riding-time gear on Default ONLY (idle-only is the requirement, not
    an accident -- riding gear must never ride into an action event) and wears
    the best owned piece per slot for Main/Neck/Body/Hands/Legs/Feet. Flip the
    switch off -> no overlay -> normal idle gear returns.

    Unlike the other three siblings this one is TINY: no target, no category, no
    packet protocol, no bar. It equips the one fixed "best riding-time set" and
    the panel reports the total riding time. `enabled` is session-only, NEVER
    restored at login (the craftstate rule -- no gear glued on at login); `at`
    is the enable stamp the Arbiter reads.

    Pure helpers are headless-testable; Ashita glue guarded at the bottom.
]]--

local M = {};

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function say(s) if _cfok and _cfmt.msg then _cfmt.msg(s); else print('[dlac] ' .. s); end end

-- <char>\dlac\ dir: the one addon-side copy (lib\statefile). nil pre-login.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir
    or function() return nil; end;
M._charDir = charDir;   -- test seam

-- The pure dig-rank brain (issue #97): ratchet / server-read decode / effective-
-- rank resolution. chocowatch owns only the Ashita glue (the live skill read,
-- the chat hook, persistence); digrank does the logic and is headless-tested.
local _drok, digrank = pcall(require, 'dlac\\feature\\digrank');
_drok = _drok and type(digrank) == 'table';
M._digrank = _drok and digrank or nil;   -- test seam

-- digcalc.db() is the shipped dig data: the rank ladder labels + the item->rank
-- map the ratchet consults. Loaded lazily / fails soft, like everywhere else.
local function digDb()
    local ok, dc = pcall(require, 'dlac\\feature\\digcalc');
    if not ok or type(dc) ~= 'table' or type(dc.db) ~= 'function' then return nil; end
    local d = nil; pcall(function() d = dc.db(); end);
    return d;
end

-- ---------------------------------------------------------------------------
-- MANUAL Chocobo control (the craftwatch/helmwatch model). You flip the switch
-- from the Automations panel; this just writes chocostate.lua and the engine
-- wears the result. `enabled` is session-only ON PURPOSE (same as craft/helm/
-- fishing): no riding gear glued on at login. `at` is the enable timestamp,
-- the Arbiter's rank tiebreak key (unused today -- rank settles overlaps).
-- ---------------------------------------------------------------------------
M.enabled = false;         -- "Set Chocobo Idle": session-only; starts OFF
M._enabledAt = 0;          -- os.time() of the last enable (state-file `at`)
M._rescanned = false;      -- manifest freshness ensured once this session?
-- The dig rank is masked out of the client, so dlac assembles it (issue #97).
-- Unlike `enabled`, these PERSIST across sessions -- a manual pick and a ratchet
-- floor are knowledge, not a session toggle.
M.rankManual = 0;          -- the player's dropdown seed (0..10); default Amateur
M.rankFloor  = 0;          -- the one-way ratchet floor (highest dug requirement)
local _stateLoaded = false;

-- Timing rank detection (issue #100): the server gates the first dig after a
-- zone-in until clamp(60 - 5*rank, 10, 60)s, so the delay to the first completed
-- dig reveals the rank. Session-only baseline; the learned rank lands in the
-- PERSISTED rankFloor (one-way), and rankFloor at MAX is the permanent latch --
-- skill never deranks, so detection then stops for good (Henrik's rule).
M._zoneInAt = nil;         -- os.clock() at the last zone-in (nil = none yet)
-- Proof of a REAL dig this zone visit: the client sends C2S 0x063
-- (GP_CLI_COMMAND_DIG, dig-exclusive -- server src/map/packets/c2s/0x063_dig.h)
-- when it finishes a dig animation. Without this gate ANY chat line matching a
-- dig phrase ("Obtained:", "with ease", "find nothing") near a zone-in could
-- ratchet the rank up (and latch it at max, permanently). Set on 0x063, cleared
-- on 0x00A.
M._digThisZone = false;

-- The timing read only fires when we have a zone-in baseline AND a real dig
-- happened this visit. Exposed so the gate is headless-testable.
function M._digGateOpen()
    return M._zoneInAt ~= nil and M._digThisZone == true;
end

local function statePath()
    local dir = charDir();
    return dir and (dir .. 'chocostate.lua') or nil;
end
local function saveState()
    pcall(function()
        local p = statePath();
        if p == nil then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        -- enabled is session-only (written OFF-truthfully here); rankManual /
        -- rankFloor persist and are read back by loadState.
        f:write(string.format('return { enabled = %s, at = %d, rankManual = %d, rankFloor = %d }\n',
            tostring(M.enabled == true), M._enabledAt or 0,
            M.rankManual or 0, M.rankFloor or 0));
        f:close();
    end);
end
M._saveState = saveState;   -- test seam

function M.loadState()
    if _stateLoaded then return; end
    local dir = charDir();
    if dir == nil then return; end        -- pre-login: retry next call
    _stateLoaded = true;
    -- Read the persisted rank back (the switch is NOT restored -- craftstate
    -- rule -- so it starts OFF each session; the rank state is knowledge and
    -- survives). A torn/absent file leaves the defaults, then re-syncs.
    pcall(function()
        local chunk = loadfile(dir .. 'chocostate.lua');
        if chunk ~= nil then
            local ok, t = pcall(chunk);
            if ok and type(t) == 'table' then
                if _drok then
                    M.rankManual = digrank.clamp(t.rankManual);
                    M.rankFloor  = digrank.clamp(t.rankFloor);
                else
                    M.rankManual = tonumber(t.rankManual) or 0;
                    M.rankFloor  = tonumber(t.rankFloor) or 0;
                end
            end
        end
    end);
    M.enabled = false;
    M._enabledAt = 0;
    saveState();                          -- sync a clean OFF file for the engine
end

-- Manifest freshness (fishwatch clone): the choco ladders must exist before the
-- engine reads them.
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

-- The on/off switch (panel). Craft/HELM/Fishing/Chocobo CO-CLAIM (ADR 0012
-- amendment): arming Chocobo stands nothing else down -- all armed activities
-- claim and the Arbiter's rank settles every overlapping slot per slot.
function M.setEnabled(on)
    M.loadState();
    M.enabled = (on == true);
    if M.enabled then
        M._enabledAt = os.time();
        ensureManifestFresh();
    end
    saveState();
end

-- ---------------------------------------------------------------------------
-- Dig rank (issue #97). Three stacked sources, honestly labelled: the manual
-- pick, the one-way ratchet floor, and a live (usually masked) server read.
-- digrank does the pure logic; this owns persistence + the Ashita reads.
-- ---------------------------------------------------------------------------

-- Set the manual rank seed (the guide's dropdown). Clamped to 0..10, persisted.
function M.setManualRank(rank)
    M.loadState();
    M.rankManual = _drok and digrank.clamp(rank) or (tonumber(rank) or 0);
    saveState();
end

-- Record a dug item ("Obtained: <item>"): map it to its dig-rank requirement and
-- ratchet the floor up if the requirement exceeds it. One-way (never lowers).
-- Returns true when the floor actually rose (so the caller can announce it).
-- A non-diggable item (not in the data) is a no-op, so a stray "Obtained:" line
-- from a non-dig source never moves the rank.
function M.recordObtained(name)
    if not _drok then return false; end
    M.loadState();
    local req = digrank.itemRequirement(name, digDb());
    if req == nil then return false; end
    local newFloor = digrank.ratchet(M.rankFloor, req);
    if newFloor > M.rankFloor then
        M.rankFloor = newFloor;
        saveState();
        return true;
    end
    return false;
end

-- The permanent max-latch (issue #100, Henrik's rule): skill can't derank, so
-- once the floor reaches the top of the ladder the rank is fixed and timing
-- detection switches off for good. rankFloor persists, so this survives relog --
-- a maxed character never runs the zone-timing read again.
function M._rankMaxed()
    if not _drok then return false; end
    return (M.rankFloor or 0) >= digrank.MAX_RANK;
end

-- Record a COMPLETED dig for the timing rank read (issue #100). `elapsed` is the
-- seconds from the zone-in to this dig; digrank inverts the first-dig cooldown
-- (60 - 5*rank, floored at 10s) into a rank and the one-way ratchet raises the
-- floor if it is higher. Returns true when the floor actually rose. No-op once
-- maxed (the latch) or before any zone-in stamp. The first completed dig of a
-- visit is the tightest (highest) read; later, slower digs read lower and, being
-- a ratchet input, never lower the floor.
function M.recordDigTiming(elapsed)
    if not _drok or M._rankMaxed() then return false; end
    M.loadState();
    local rank = digrank.rankFromZoneTiming(elapsed);
    if rank == nil then return false; end
    local newFloor = digrank.ratchet(M.rankFloor, rank);
    if newFloor > M.rankFloor then
        M.rankFloor = newFloor;
        saveState();
        return true;
    end
    return false;
end

-- The live server dig-rank read, throttled (~2s). GetCraftSkill(11) returns the
-- 0xFFFF mask forever on the current server, so this is nil in practice; if a
-- build ever unmasks it, digrank.serverRank decodes the exact rank and it wins.
M._serverCache = { rank = nil, at = -1 };
function M.serverRankLive()
    if not _drok then return nil; end
    local now = os.clock();
    if (now - (M._serverCache.at or -1)) < 2 then return M._serverCache.rank; end
    M._serverCache.at = now;
    local raw = nil;
    pcall(function()
        if AshitaCore == nil then return; end
        local pl = AshitaCore:GetMemoryManager():GetPlayer();
        if pl ~= nil then raw = pl:GetCraftSkill(11); end
    end);
    M._serverCache.rank = (raw ~= nil) and digrank.serverRank(raw) or nil;
    return M._serverCache.rank;
end

-- The resolved rank state the panel renders AND the tab views gate grey-out on:
-- { rank, source, exact, label, sourceLabel }. `exact` is true ONLY for a
-- server-reported rank -- the tab views hard-lock over-rank items against an
-- exact rank and merely dim them against an estimate (manual/ratchet).
function M.rankState()
    M.loadState();
    if not _drok then
        return { rank = M.rankManual or 0, source = 'manual', exact = false,
                 label = 'rank ' .. (M.rankManual or 0), sourceLabel = 'manual' };
    end
    local db = digDb();
    local ranks = (type(db) == 'table') and db.ranks or nil;
    return digrank.resolve(M.rankManual, M.rankFloor, M.serverRankLive(), ranks);
end

-- ---------------------------------------------------------------------------
-- Ashita glue
-- ---------------------------------------------------------------------------
if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    -- /dl choco [on | off | status]. The subject (an on/off riding-gear switch)
    -- lives in the addon state, so the command does too (the helm/fish
    -- precedent) -- its own blocked registration, never the dispatch whitelist.
    ashita.events.register('command', 'dlac-chocowatch-cmd', function(e)
        pcall(function()
            local raw = string.lower(e.command or '');
            local a, b = raw:match('^/dl%s+(%S+)%s*(%S*)');
            if a == nil then a, b = raw:match('^/dlac%s+(%S+)%s*(%S*)'); end
            if a ~= 'choco' and a ~= 'chocobo' then return; end
            e.blocked = true;
            if b == 'on' or b == 'off' then
                M.setEnabled(b == 'on');
                say('Chocobo idle set ' .. (M.enabled and 'ON' or 'OFF') .. '.');
                return;
            end
            -- bare /dl choco: status, now with the resolved dig rank + source.
            local rs = M.rankState();
            say('chocobo: idle set = ' .. (M.isEnabled() and 'ON' or 'off')
                .. ' (session-only -- off after relog). Equips your best riding-time gear while idle.');
            say(string.format('  dig rank: %s (%s)%s', rs.label or ('rank ' .. rs.rank),
                rs.sourceLabel or rs.source, rs.exact and '' or ' -- estimate'));
        end);
    end);

    -- Zone-in timing baseline (issue #100): the server measures the first-dig
    -- cooldown from the zone entry, so stamp os.clock() on every 0x00A. A BARE
    -- timestamp -- no chat, no IO -- so it is safe on the packet (network)
    -- thread; the dlacprobe crash was per-line chat prints from a packet handler,
    -- which this deliberately does none of.
    ashita.events.register('packet_in', 'dlac-chocowatch-zonein', function(e)
        if e.id == 0x00A then M._zoneInAt = os.clock(); M._digThisZone = false; end
    end);

    -- Dig-completion proof (issue #100 hardening): the client sends C2S 0x063 when
    -- it finishes a chocobo dig animation (GP_CLI_COMMAND_DIG, dig-exclusive). Flag
    -- it so the timing read below trusts ONLY a real dig this zone visit, never a
    -- passer-by's chat that merely matches a dig phrase. Bare flag -- no chat/IO,
    -- safe on the packet (network) thread.
    ashita.events.register('packet_out', 'dlac-chocowatch-digdone', function(e)
        if e.id == 0x063 then M._digThisZone = true; end
    end);

    -- Dig chat -> rank knowledge. Two one-way inputs, BOTH feeding the persisted
    -- floor and running always (independent of the riding-gear toggle -- the rank
    -- is the baseline beneath the guide):
    --   (1) an "Obtained: <item>" line ratchets to that item's rank requirement
    --       (the hgather channel); a non-diggable obtain is a no-op.
    --   (2) a COMPLETED dig's delay since the zone-in reveals the exact rank via
    --       the first-dig cooldown (issue #100), until the max latch stops it.
    -- Main-thread text only -- no packets, no per-line spam.
    ashita.events.register('text_in', 'dlac-chocowatch-dig', function(e)
        pcall(function()
            if not _drok then return; end
            local msg = e.message;
            if type(msg) ~= 'string' then return; end
            local tag, item = digrank.classifyDigLine(msg);
            if tag == nil then return; end

            local raised, why = false, nil;
            -- (1) item ratchet on an obtained line (unchanged behaviour).
            if tag == 'obtained' and item ~= nil and M.recordObtained(item) then
                raised, why = true, '>= from digging ' .. item;
            end
            -- (2) timing read on a completed dig, off the zone-in baseline -- but
            -- ONLY when a real dig (0x063) happened this zone visit, so a foreign
            -- chat line can never ratchet or latch the rank.
            if digrank.isCompletedDig(tag) and M._digGateOpen() then
                if M.recordDigTiming(os.clock() - M._zoneInAt) then
                    raised, why = true, 'measured from your first-dig timing';
                end
            end

            if raised then
                local rs = M.rankState();
                say(string.format('dig rank raised to %s (%s).',
                    rs.label or ('rank ' .. rs.rank), why));
            end
        end);
    end);
end

return M;
