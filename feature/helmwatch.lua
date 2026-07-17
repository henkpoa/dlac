--[[
    dlac/helmwatch.lua -- HELM gathering state + venture tracking
    (docs/design/helm-gear.md; fishing deliberately excluded).

    The craftwatch twin for Harvesting / Excavation / Logging / Mining. Same
    philosophy: don't fight the engine, BE the engine. This module just WRITES
    <char>\dlac\helmstate.lua { gather, enabled, at }; the dispatch ENGINE
    overlays the resolved HELM gear on Default ONLY (idle -- never an action
    event; Henrik's hard requirement) at v59. Flip the switch off -> no
    overlay -> normal idle gear returns. No commands, no locks.

    Venture points: CatsEyeXI's custom 0x1A4 request/response protocol (the
    trove addon's mechanism -- trove/utils/packet.lua). We send GET_POINTS
    (action 8) and parse the POINTS_ENTRY (action 7) stream: group @0x08
    (19b) | label @0x1C (23b) | value i32 @0x34; CLEAR(0)/END_LIST(2) ends a
    stream. Which group/label the four HELM pools use is pinned by a field
    capture (/dl helm points dumps everything seen).

    Today's ventures: the server's `!ventures` reply is plain 0x017 chat from
    the PRIVATE module -- format unknowable from source. So: when the player
    SENDS a "!ventures" line (outgoing 0x0B5 speech), we open a short capture
    window on incoming 0x017, mirror the raw lines to
    <char>\dlac\helmventures_capture.txt (the field data that pins the
    regexes), and keyword-bucket them per category for the panel meanwhile.

    Category auto-detection: HELM is trade-to-NPC and the point NPCs are
    NAMED for their category ("Mining Point" etc.). Outgoing trade-complete
    0x036 carries the target index @0x08; the entity name tells us what the
    player is gathering -- the bar auto-switches so the right hat is on for
    the NEXT swing.

    Pure helpers are headless-testable; Ashita glue guarded at the bottom.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- categories + the semantic hat map (catalog stats can't say WHICH category a
-- hat doubles -- the id block 25557-25560 is one hat per category, so the map
-- is hardcoded; everything else about HELM gear is stat-driven from the
-- catalog's HELM / Surveyor keys at manifest-rescan time).
-- ---------------------------------------------------------------------------
M.ORDER = { 'Harvesting', 'Excavation', 'Logging', 'Mining' };
M.HATS  = { Harvesting = 'Harv. Sun Hat',   Excavation = 'Excavators Shades',
            Logging    = 'Lumberjacks Beret', Mining     = 'Miners Helmet' };

local VALID = {};
for _, g in ipairs(M.ORDER) do VALID[g] = true; VALID[string.lower(g)] = g; end

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function say(s) if _cfok and _cfmt.msg then _cfmt.msg(s); else print('[dlac] ' .. s); end end

-- <char>\dlac\ dir (craftwatch's kiCharDir pattern). nil pre-login.
local function charDir()
    local dir = nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name, id = party:GetMemberName(0), party:GetMemberServerId(0);
        if name == nil or name == '' or id == nil then return; end
        dir = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\dlac\\',
            AshitaCore:GetInstallPath(), name, id);
    end);
    return dir;
end
M._charDir = charDir;   -- test seam

-- ---------------------------------------------------------------------------
-- byte helpers (pure; shared by every parser below)
-- ---------------------------------------------------------------------------
local function u8(data, off)  return string.byte(data, off + 1) or 0; end
local function u16(data, off) return u8(data, off) + u8(data, off + 1) * 256; end
local function u32(data, off)
    return u8(data, off) + u8(data, off + 1) * 256
         + u8(data, off + 2) * 65536 + u8(data, off + 3) * 16777216;
end
local function i32(data, off)
    local v = u32(data, off);
    if v >= 0x80000000 then v = v - 0x100000000; end
    return v;
end
-- Fixed-width, NUL-terminated string field.
local function zstr(data, off, maxLen)
    local out = {};
    for i = 1, maxLen do
        local b = string.byte(data, off + i);
        if b == nil or b == 0 then break; end
        out[#out + 1] = string.char(b);
    end
    return table.concat(out);
end
M._zstr = zstr;   -- test seam

-- ---------------------------------------------------------------------------
-- MANUAL HELM control (the craftwatch model). You pick the category + on/off
-- from the floating bar / panel / command; this just writes helmstate.lua and
-- the engine wears the result. `enabled` is session-only ON PURPOSE (same as
-- craft): no gathering gear glued on at login. `at` is the enable timestamp --
-- the engine's arbitration key when BOTH craft and helm switches are somehow
-- on (newer writer wins; see dispatch v59).
-- ---------------------------------------------------------------------------
M.barVisible = false;      -- floating HELM bar (helmbar.lua) shown?
M.activeGather = nil;      -- 'Harvesting' | 'Excavation' | 'Logging' | 'Mining'
M.enabled = false;         -- session-only; starts OFF
M._enabledAt = 0;          -- os.time() of the last enable (state-file `at`)
M._rescanned = false;      -- manifest freshness ensured once this session?
local _stateLoaded = false;

local function statePath()
    local dir = charDir();
    return dir and (dir .. 'helmstate.lua') or nil;
end
local function saveState()
    pcall(function()
        local p = statePath();
        if p == nil then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(string.format('return { gather = %q, enabled = %s, at = %d }\n',
            tostring(M.activeGather or ''), tostring(M.enabled == true), M._enabledAt or 0));
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
        local chunk = loadfile(dir .. 'helmstate.lua');
        if chunk ~= nil then
            local ok, t = pcall(chunk);
            if ok and type(t) == 'table' then
                if type(t.gather) == 'string' and VALID[t.gather] == true then M.activeGather = t.gather; end
                -- `enabled` is NOT restored: the switch starts OFF each session
                -- (no gathering gear glued on at login). The category DOES persist.
            end
        end
    end);
    M.enabled = false;
    saveState();                          -- sync the file to enabled=false for the engine
end

function M.getGather() M.loadState(); return M.activeGather; end
function M.isEnabled() M.loadState(); return M.enabled == true; end

-- Manifest freshness (craftwatch.ensureManifestFresh clone): the fmtver-7
-- helm ladders must exist before the engine reads them.
local function ensureManifestFresh()
    local first = not M._rescanned;
    M._rescanned = true;
    pcall(function()
        local tg = require('dlac\\ui\\triggersui');
        if type(tg.rescanAutogear) ~= 'function' then return; end
        local stale = first;
        if not first then
            pcall(function()
                if type(tg.manifestStale) == 'function' then stale = tg.manifestStale(); end
            end);
        end
        if stale then tg.rescanAutogear(); end
    end);
end

-- The on/off switch (bar + panel). Enabling HELM turns the CRAFT switch off
-- (one gathering/crafting overlay at a time -- they fight over the same
-- slots). One-way require only (craftwatch never requires helmwatch: no
-- cycle); the reverse direction -- craft enabled while helm is on -- is
-- settled inside the engine by the state files' `at` stamps (newer wins).
function M.setEnabled(on)
    M.loadState();
    M.enabled = (on == true);
    if M.enabled then
        M._enabledAt = os.time();
        ensureManifestFresh();
        pcall(function()
            local cw = require('dlac\\feature\\craftwatch');
            if type(cw.isEnabled) == 'function' and cw.isEnabled()
               and type(cw.setEnabled) == 'function' then cw.setEnabled(false); end
        end);
    end
    saveState();
end

-- Pick the category. Selecting ONLY sets which category is active (the
-- craft-button rule); the engine equips it while the switch is on.
function M.selectGather(gather)
    local g = VALID[gather] == true and gather or VALID[string.lower(tostring(gather or ''))];
    if type(g) ~= 'string' then return; end
    M.loadState();
    M.activeGather = g;
    ensureManifestFresh();
    saveState();
end

-- ---------------------------------------------------------------------------
-- Venture points -- CatsEyeXI 0x1A4 protocol (trove's utils/packet.lua wire
-- format, reimplemented so dlac has no dependency on trove being installed).
-- Server-authoritative: groups/labels/values all come from the server; we
-- keep EVERYTHING seen (the field capture decides which entries are the four
-- HELM pools; pointsFor() finds a category by tolerant label match meanwhile).
-- ---------------------------------------------------------------------------
local PKT_1A4 = 0x1A4;
local ACT_GET_POINTS   = 8;   -- C2S
local ACT_POINTS_ENTRY = 7;   -- S2C
local ACT_CLEAR        = 0;   -- S2C stream reset
local ACT_END_LIST     = 2;   -- S2C stream terminator

M.points = {};          -- group -> label -> value (last committed stream)
M.pointsSeen = false;   -- a live 0x1A4 points stream committed this session
M.pointsPersisted = false;
local _ptsStaging = nil;
local _ptsLoaded = false;

local function vpPath() local d = charDir(); return d and (d .. 'venturepoints.lua') or nil; end
local function vpSave()
    pcall(function()
        local p = vpPath(); if p == nil then return; end
        local parts = { '-- dlac venture-points mirror (0x1A4 GET_POINTS-tracked)\nreturn {\n' };
        local gs = {};
        for g in pairs(M.points) do gs[#gs + 1] = g; end
        table.sort(gs);
        for _, g in ipairs(gs) do
            parts[#parts + 1] = string.format('    [%q] = {\n', g);
            local ls = {};
            for l in pairs(M.points[g]) do ls[#ls + 1] = l; end
            table.sort(ls);
            for _, l in ipairs(ls) do
                parts[#parts + 1] = string.format('        [%q] = %d,\n', l, M.points[g][l]);
            end
            parts[#parts + 1] = '    },\n';
        end
        parts[#parts + 1] = '}\n';
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(table.concat(parts));
        f:close();
    end);
end
local function vpLoad()
    if _ptsLoaded then return; end
    local dir = charDir(); if dir == nil then return; end
    _ptsLoaded = true;
    pcall(function()
        local chunk = loadfile(dir .. 'venturepoints.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' and not M.pointsSeen then
            M.points = t;
            M.pointsPersisted = true;
        end
    end);
end

-- One inbound 0x1A4. Returns true when the packet was consumed (caller sets
-- e.blocked -- the retail client has no idea what opcode 0x1A4 is; trove
-- blocks it for the same reason, and Ashita still hands the event to every
-- other addon, so blocking here starves nobody).
function M.on1A4(data)
    if type(data) ~= 'string' or #data < 0x06 then return false; end
    local action = u8(data, 0x04);
    if action == ACT_POINTS_ENTRY then
        if #data < 0x38 then return true; end
        vpLoad();
        _ptsStaging = _ptsStaging or {};
        local group = zstr(data, 0x08, 19);
        local label = zstr(data, 0x1C, 23);
        local value = i32(data, 0x34);
        if group ~= '' or label ~= '' then
            _ptsStaging[group] = _ptsStaging[group] or {};
            _ptsStaging[group][label] = value;
        end
        return true;
    end
    if action == ACT_CLEAR or action == ACT_END_LIST then
        -- Terminators are shared by every 0x1A4 list type; only commit when a
        -- POINTS stream is actually staged (a currency stream ending is not ours).
        if _ptsStaging ~= nil then
            M.points = _ptsStaging;
            _ptsStaging = nil;
            M.pointsSeen = true;
            vpSave();
        end
        return true;
    end
    return true;   -- any other 0x1A4 action: not ours, still not the client's
end

-- Ask the server for the points list (trove packet.send(GET_POINTS) clone:
-- 64 zero bytes, action at offset 0x04). Debounced like requestGuildPoints.
local _vpReqAt = -10;
function M.requestPoints(force)
    if os.clock() - _vpReqAt < (force and 1 or 5) then return; end
    _vpReqAt = os.clock();
    pcall(function()
        local p = {};
        for i = 1, 64 do p[i] = 0; end
        p[5] = ACT_GET_POINTS;
        AshitaCore:GetPacketManager():AddOutgoingPacket(PKT_1A4, p);
    end);
end

-- The points entry for a HELM category. CONFIRMED live 2026-07-17 (Mindie):
-- the server streams group "Ventures" with labels exactly Harvesting /
-- Excavation / Logging / Mining (+ Fishing, EXP, Battle, Dynamis) -- so the
-- Ventures-group exact match is the real path; the tolerant fallbacks stay
-- for label drift. Returns value, group, label -- or nil when absent.
function M.pointsFor(gather)
    vpLoad();
    local want = string.lower(tostring(gather or ''));
    if want == '' then return nil; end
    local vg = M.points['Ventures'];
    if type(vg) == 'table' then
        for l, v in pairs(vg) do
            if string.lower(l) == want then return v, 'Ventures', l; end
        end
    end
    for g, labels in pairs(M.points) do
        for l, v in pairs(labels) do
            if string.lower(l) == want then return v, g, l; end
        end
    end
    for g, labels in pairs(M.points) do
        for l, v in pairs(labels) do
            local ll = string.lower(l);
            if ll:find(want, 1, true) or want:find(ll, 1, true) then return v, g, l; end
        end
    end
    return nil;
end
function M.pointsReady() vpLoad(); return M.pointsSeen or M.pointsPersisted; end

-- ---------------------------------------------------------------------------
-- Today's ventures -- capture + keyword bucket. The private module prints the
-- `!ventures` reply as 0x017 chat; until a field capture pins the exact
-- format, every line seen inside the capture window is (a) mirrored raw to
-- helmventures_capture.txt and (b) bucketed by category keyword for display.
-- ---------------------------------------------------------------------------
M.ventures = nil;        -- { day = <JST daystamp>, cats = { Harvesting = {lines}, ... }, general = {lines} }
local _capUntil = -1;
local _capCount = 0;
local _vLoaded = false;

-- JST day stamp (ventures rotate at JST midnight).
function M.jstDay(t) return math.floor(((t or os.time()) + 9 * 3600) / 86400); end

local function ventPath() local d = charDir(); return d and (d .. 'helmventures.lua') or nil; end
local function ventSave()
    pcall(function()
        local p = ventPath(); if p == nil or M.ventures == nil then return; end
        local parts = { '-- dlac ventures mirror (0x017-captured, keyword-bucketed)\nreturn {\n' };
        parts[#parts + 1] = string.format('    day = %d,\n', M.ventures.day or 0);
        parts[#parts + 1] = '    general = {\n';
        for _, ln in ipairs(M.ventures.general or {}) do parts[#parts + 1] = string.format('        %q,\n', ln); end
        parts[#parts + 1] = '    },\n    cats = {\n';
        for _, g in ipairs(M.ORDER) do
            local lines = (M.ventures.cats or {})[g];
            if lines ~= nil and #lines > 0 then
                parts[#parts + 1] = string.format('        [%q] = {\n', g);
                for _, ln in ipairs(lines) do parts[#parts + 1] = string.format('            %q,\n', ln); end
                parts[#parts + 1] = '        },\n';
            end
        end
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
        local chunk = loadfile(dir .. 'helmventures.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' and M.ventures == nil then M.ventures = t; end
    end);
end

-- One server venture line, structurally. Format PINNED by field capture
-- 2026-07-17 (helmventures_capture.txt, Mindie):
--     === Today's Goblin Ventures ===                      (banner, type 29)
--     Mining: (Low) Ordelles Caves, (Mid) Garlaige Citadel [S], (High) Grauberg [S]
-- Returns category + display lines { 'Low: ...', 'Mid: ...', 'High: ...' },
-- or nil for anything else. Tier text is captured lazily so progress markup
-- the wiki promises on active objectives ("denoted by the objective
-- progress") rides along verbatim; a drifted format keeps the raw tail.
function M.parseVentureLine(msg)
    local cat, rest = tostring(msg or ''):match('^%s*(%a+):%s*(.+)$');
    if cat == nil or VALID[cat] ~= true then return nil; end
    local low, mid, high = rest:match('%(Low%)%s*(.-)%s*,%s*%(Mid%)%s*(.-)%s*,%s*%(High%)%s*(.-)%s*$');
    if low == nil then return cat, { rest }; end
    return cat, { 'Low:  ' .. low, 'Mid:  ' .. mid, 'High: ' .. high };
end

-- Sanitize a chat payload for storage: FFXI chat embeds control/autotranslate
-- bytes; keep printable ASCII, collapse runs of the rest to single spaces.
function M.cleanLine(msg)
    local s = tostring(msg or ''):gsub('[^\032-\126]+', ' ');
    s = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '');
    return s;
end

function M.openCapture(seconds)
    _capUntil = os.clock() + (tonumber(seconds) or 6);
    _capCount = 0;
    ventLoad();
    -- A fresh capture on a new JST day replaces yesterday's list.
    local day = M.jstDay();
    if M.ventures == nil or (M.ventures.day or 0) ~= day then
        M.ventures = { day = day, cats = {}, general = {} };
    end
end
function M.captureOpen() return os.clock() < _capUntil; end

-- One incoming 0x017 while the window is open. Raw mirror ALWAYS (append) --
-- that file is what pins the real parser; bucketed store for the panel.
function M.onChatLine(chatType, sender, msg)
    if not M.captureOpen() then return; end
    local clean = M.cleanLine(msg);
    if clean == '' then return; end
    _capCount = _capCount + 1;
    pcall(function()
        local dir = charDir(); if dir == nil then return; end
        local f = io.open(dir .. 'helmventures_capture.txt', 'ab');
        if f == nil then return; end
        f:write(string.format('%s  type=%d  sender=%s  |  %s\n',
            os.date('%Y-%m-%d %H:%M:%S'), tonumber(chatType) or -1, tostring(sender or ''), clean));
        f:close();
    end);
    -- Structured store: a parsed category line REPLACES that category (one
    -- reply is the day's whole truth); the banner is dropped; anything else
    -- venture-ish lands in general once (field data for future formats).
    -- Stray party/say chat inside the window parses as nothing and is only
    -- kept in the raw capture file.
    ventLoad();
    local day = M.jstDay();
    if M.ventures == nil or (M.ventures.day or 0) ~= day then
        M.ventures = { day = day, cats = {}, general = {} };
    end
    if clean:find('=== Today', 1, true) ~= nil then return; end   -- banner
    local g, lines = M.parseVentureLine(clean);
    if g ~= nil then
        M.ventures.cats[g] = lines;
        ventSave();
        return;
    end
    if clean:lower():find('venture', 1, true) then
        for _, ln in ipairs(M.ventures.general) do
            if ln == clean then return; end                       -- dedupe re-runs
        end
        local t = M.ventures.general;
        t[#t + 1] = clean;
        ventSave();
    end
end

-- Panel accessor: lines for one category + the day-freshness flag.
function M.venturesFor(gather)
    ventLoad();
    if M.ventures == nil then return nil, false; end
    local fresh = (M.ventures.day or 0) == M.jstDay();
    return (M.ventures.cats or {})[gather], fresh, M.ventures.general;
end

-- ---------------------------------------------------------------------------
-- Category auto-detection -- via the RESULT event. FIELD-PINNED 2026-07-17
-- (Ghelsba Outpost capture, dlacprobe): the HELM result arrives as incoming
-- 0x034 EVENTNUM -- num[0] u32 @0x08 = item found (0 = nothing, num[1] =
-- broke), ActIndex u16 @0x28 = the gathering Point NPC (the u16 zone id
-- sitting next to it @0x2A confirmed the alignment), EventNum @0x2C = the
-- zone's HELM csid. The Point NPCs are NAMED for their category, so entity-
-- name resolution does the semantics -- no per-zone csid table. (The
-- original guess -- outgoing trade 0x036, index @0x08 -- never fired in the
-- field; replaced wholesale.)
-- ---------------------------------------------------------------------------
M.lastDetect = nil;   -- { gather, npc, at = os.clock() }

function M.gatherFromNpcName(name)
    local n = tostring(name or '');
    for _, g in ipairs(M.ORDER) do
        if n:find('^' .. g .. ' Point') ~= nil then return g; end
    end
    return nil;
end

-- The event source's entity index from a 0x034, or nil. Pure (tests feed the
-- real Ghelsba bytes).
function M.eventNpcIndex(data)
    if type(data) ~= 'string' or #data < 0x2A then return nil; end
    local idx = u16(data, 0x28);
    if idx == 0 then return nil; end
    return idx;
end

-- nameOf is a test seam; live, the entity table resolves the index.
function M.onEventNum(data, nameOf)
    local idx = M.eventNpcIndex(data);
    if idx == nil then return; end
    local name = nil;
    if nameOf ~= nil then name = nameOf(idx);
    else pcall(function() name = AshitaCore:GetMemoryManager():GetEntity():GetName(idx); end); end
    local g = M.gatherFromNpcName(name);
    if g == nil then return; end
    M.lastDetect = { gather = g, npc = name, at = os.clock() };
    -- Auto-switch: with the switch ON, the hat/category follows what you are
    -- actually gathering (this swing's result is already rolled -- the swap
    -- dresses you for the NEXT one, which is how a session works anyway).
    if M.isEnabled() and M.activeGather ~= g then M.selectGather(g); end
end

-- ---------------------------------------------------------------------------
-- Overlay preview + rating (bar/panel display). Reads the manifest's helm
-- ladders directly (same file the engine reads; tiny cached parse) -- the
-- rungs carry their HELM stat, so the break-roll rating needs no catalog.
-- Rating = sum of HELM over the non-Head picks; >= 5 -> breakage impossible
-- (roll floor 1 + 5*7.3 = 37.5 > the 33% default). Excavation ignores it.
-- ---------------------------------------------------------------------------
local _man = { data = nil, at = -10 };
local function manifest()
    local now = os.clock();
    if _man.data ~= nil and now - _man.at < 5 then return _man.data; end
    _man.at = now;
    _man.data = nil;
    pcall(function()
        local dir = charDir(); if dir == nil then return; end
        local chunk = loadfile(dir .. 'autogear.lua'); if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then _man.data = t; end
    end);
    return _man.data;
end
M._setManifest = function(t) _man.data = t; _man.at = os.clock() + 1e9; end   -- test seam

local function playerLevel()
    local lvl = 99;
    pcall(function()
        local v = AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel();
        if type(v) == 'number' and v > 0 then lvl = v; end
    end);
    return lvl;
end

local HELM_SLOTS = { 'head', 'neck', 'body', 'hands', 'waist', 'legs', 'feet' };

-- { [SlotLabel] = { name, helm, surv } } for a category at the player level --
-- the same first-usable-rung walk the engine does (dispatch dlac:AutoHelm).
function M.preview(gather, lvl)
    local a = manifest();
    local h = (type(a) == 'table') and a.helm or nil;
    if type(h) ~= 'table' then return {}; end
    lvl = lvl or playerLevel();
    local out = {};
    for _, sk in ipairs(HELM_SLOTS) do
        local pick = nil;
        if sk == 'head' then
            local hat = (type(h.hats) == 'table') and h.hats[gather] or nil;
            if type(hat) == 'table' and type(hat.name) == 'string'
               and (tonumber(hat.level) or 0) <= lvl then pick = hat; end
        end
        if pick == nil then
            local lad = h[sk];
            if type(lad) == 'table' then
                for _, r in ipairs(lad) do
                    if type(r) == 'table' and type(r.name) == 'string'
                       and (tonumber(r.level) or 0) <= lvl then pick = r; break; end
                end
            end
        end
        if pick ~= nil then
            local label = sk:gsub('^%l', string.upper);
            out[label] = { name = pick.name, helm = tonumber(pick.helm) or 0,
                           surv = tonumber(pick.surv) or 0 };
        end
    end
    return out;
end

-- rating (sum of HELM on non-Head picks), surveyor total, breakProof flag.
function M.rating(gather, lvl)
    local pv = M.preview(gather, lvl);
    local helm, surv = 0, 0;
    for slot, p in pairs(pv) do
        if slot ~= 'Head' then helm = helm + (p.helm or 0); end
        surv = surv + (p.surv or 0);
    end
    return helm, surv, (helm >= 5);
end

-- ---------------------------------------------------------------------------
-- Ashita glue
-- ---------------------------------------------------------------------------
if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_in', 'dlac-helmwatch-in', function(e)
        if e.id == PKT_1A4 then
            local consumed = false;
            pcall(function() consumed = M.on1A4(e.data); end);
            if consumed then e.blocked = true; end
        elseif e.id == 0x034 then
            pcall(function() M.onEventNum(e.data); end);   -- HELM result -> category
        elseif e.id == 0x017 and M.captureOpen() then
            pcall(function()
                local chatType = u8(e.data, 0x04);
                local sender = zstr(e.data, 0x08, 13);
                local msg = zstr(e.data, 0x17, #e.data - 0x17);
                M.onChatLine(chatType, sender, msg);
            end);
        end
    end);

    ashita.events.register('packet_out', 'dlac-helmwatch-out', function(e)
        if e.id == 0x0B5 then
            -- Player speech: a "!ventures" line opens the 0x017 capture window
            -- (the server's reply is what we're really after).
            pcall(function()
                local msg = zstr(e.data, 0x06, math.max(0, #e.data - 0x06));
                if msg:lower():find('^!ventures') ~= nil then M.openCapture(6); end
            end);
        end
    end);

    -- One-shot points fetch on login (the craftwatch 0x10F tick pattern):
    -- poll ~2s until actually in-game, request once, unregister.
    local _vpTickAt = 0;
    ashita.events.register('d3d_present', 'dlac-helmwatch-vp', function()
        pcall(function()
            if os.clock() < _vpTickAt then return; end
            _vpTickAt = os.clock() + 2;
            local pl = AshitaCore:GetMemoryManager():GetPlayer();
            if pl == nil or (pl:GetMainJob() or 0) == 0 then return; end
            if pl.GetIsZoning ~= nil then
                local z = pl:GetIsZoning();
                if z == true or (type(z) == 'number' and z ~= 0) then return; end
            end
            M.requestPoints();
            ashita.events.unregister('d3d_present', 'dlac-helmwatch-vp');
        end);
    end);

    -- /dl helm [bar | <category> | points | show | capture | status]
    ashita.events.register('command', 'dlac-helmwatch-cmd', function(e)
        pcall(function()
            local raw = string.lower(e.command or '');
            local a, b = raw:match('^/dl%s+(%S+)%s*(%S*)');
            if a == nil then a, b = raw:match('^/dlac%s+(%S+)%s*(%S*)'); end
            if a ~= 'helm' then return; end
            e.blocked = true;
            if b == 'bar' then
                M.barVisible = not M.barVisible;
                say('HELM bar ' .. (M.barVisible and 'shown' or 'hidden') .. '.');
                return;
            end
            if VALID[b] ~= nil then
                M.selectGather(type(VALID[b]) == 'string' and VALID[b] or b);
                say('HELM category: ' .. tostring(M.activeGather) .. '.');
                return;
            end
            if b == 'points' then
                -- Field tool: dump EVERYTHING the 0x1A4 points stream carries,
                -- so the HELM pools' group/label can be pinned from live data.
                M.requestPoints(true);
                if not M.pointsReady() then
                    say('venture points: requested -- run /dl helm points again in a moment.');
                    return;
                end
                say('0x1A4 points stream (group / label / value):');
                local gs = {};
                for g in pairs(M.points) do gs[#gs + 1] = g; end
                table.sort(gs);
                for _, g in ipairs(gs) do
                    local ls = {};
                    for l in pairs(M.points[g]) do ls[#ls + 1] = l; end
                    table.sort(ls);
                    for _, l in ipairs(ls) do
                        say(string.format('  %-18s %-22s %d', g, l, M.points[g][l]));
                    end
                end
                for _, g in ipairs(M.ORDER) do
                    local v, grp, lbl = M.pointsFor(g);
                    say(string.format('  -> %s resolves to: %s', g,
                        v ~= nil and string.format('%d (%s / %s)', v, grp, lbl) or 'NOT FOUND'));
                end
                return;
            end
            if b == 'show' then                        -- what would the engine equip?
                local g = M.getGather();
                if g == nil then say('helm show: pick a category first (/dl helm mining etc).'); return; end
                local pv = M.preview(g);
                local helm, surv, bp = M.rating(g);
                say(string.format('helm show: %s -> engine overlay (rating %d%s, Surveyor +%d):',
                    g, helm, bp and ' -- BREAK-PROOF' or '/5', surv));
                local any = false;
                for _, slot in ipairs({ 'Head', 'Neck', 'Body', 'Hands', 'Waist', 'Legs', 'Feet' }) do
                    if pv[slot] ~= nil then any = true; say(string.format('  %-6s %s', slot, pv[slot].name)); end
                end
                if not any then say('  (nothing -- no HELM gear in bags, or rescan pending)'); end
                return;
            end
            if b == 'capture' then                     -- manual 0x017 capture window
                M.openCapture(8);
                say('capturing system chat for 8s -> helmventures_capture.txt (type !ventures now).');
                return;
            end
            -- bare /dl helm: status.
            say(string.format('helm: category = %s, switch = %s.',
                M.getGather() or '(none -- /dl helm mining etc)', M.isEnabled() and 'ON' or 'off'));
            say('  pick a category + flip the switch on the HELM bar (/dl helm bar) -- the engine');
            say('  wears your best gathering gear ON IDLE ONLY until you turn it off.');
            if M.lastDetect ~= nil then
                say(string.format('  last detected: %s (%s)', M.lastDetect.gather, M.lastDetect.npc or '?'));
            end
        end);
    end);
end

return M;
