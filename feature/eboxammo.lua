--[[
    dlac/feature/eboxammo.lua -- AutoAmmo's E-Box section, now a THIN ADAPTER
    over the one client (ADR 0016; docs/design/ebox-restock.md Section 6).

    This WAS the standalone 0x1A4 ammo client. It is now a behaviour-preserving
    adapter over feature/eboxclient (the single door), narrowed to the
    Ammunition category (15). Its public surface is UNCHANGED so ui/ammoui.lua
    needs no edit: every call delegates to the client and mirrors the fields the
    panel reads (counts / lockedReason / status...). eboxammo NO LONGER registers
    a packet handler -- the client owns the wire, so two features can never race
    on the party line (the reason the fold had to precede E-Box Restock going
    live). The whole wire path is now tested on the client (EBC*); these EB*
    checks pin the ADAPTER (delegation + the cat-15 mirror).

    Headless: require of the client fails (like gamemode/entwatch did before), so
    the tests inject it via _setClient; every method no-ops safely when nil.
]]--

local M = {};

local AH_CAT_AMMO = 15;   -- 'Ammunition' (trove AH_NAMES)
M._CAT = AH_CAT_AMMO;

-- The one client. require fails headless -> nil; the tests inject via _setClient.
local _client = nil;
pcall(function()
    local ok, c = pcall(require, 'dlac\\feature\\eboxclient');
    if ok and type(c) == 'table' then _client = c; end
end);
function M._setClient(c) _client = c; end   -- headless seam (EB*)

-- Proximity constants mirrored for callers/tests; the client owns the real ones.
M.BOX_NAME  = 'Ephemeral Box';
M.BOX_RANGE = (_client ~= nil and _client.BOX_RANGE) or 5;

-- Fields ui/ammoui.lua reads each frame -- kept as fields, synced from the
-- client on every delegated call.
M.counts       = nil;    -- [itemId] = qty in the E-Box (cat 15); nil until a commit
M.at           = 0;
M.lockedReason = nil;
M.lockedMsg    = nil;
M.status       = nil;
M.statusErr    = false;
M.statusAt     = 0;
M.busy         = false;

function M._now() return os.clock(); end   -- vestigial (the client keeps its own); kept for compat

-- Copy the client's shared state into the mirror the panel reads, narrowed to
-- the ammo category.
local function sync()
    local c = _client;
    if c == nil then return; end
    M.counts       = c.categoryCounts(AH_CAT_AMMO);   -- the cat-15 items map, or nil
    M.lockedReason = c.lockedReason;
    M.lockedMsg    = c.lockedMsg;
    M.status, M.statusErr, M.statusAt = c.status, c.statusErr, c.statusAt;
    M.busy         = (type(c.isBusy) == 'function') and c.isBusy() or c.busy;
end
M._sync = sync;   -- test seam

function M.isCW()
    return (_client ~= nil) and _client.isCW() or false;
end

-- Pure clamp: delegate when a client is present, else the same rule locally so
-- the tested behaviour holds even with no client.
function M._clampQty(qty, have)
    if _client ~= nil then return _client._clampQty(qty, have); end
    qty = math.floor(tonumber(qty) or 0); have = math.floor(tonumber(have) or 0);
    if qty < 1 or have < 1 then return 0; end
    if qty > have then return have; end
    return qty;
end

-- Begin a cat-15 stream WITHOUT the wire (headless seam, EB*).
function M._beginStream()
    if _client ~= nil then _client._beginRequest('category', AH_CAT_AMMO); end
end

-- Force a re-count (rescan / after a withdraw): always-stale ensureCategory.
function M.refresh()
    if _client == nil then return false; end
    local r = _client.ensureCategory(AH_CAT_AMMO, -1);
    sync();
    return r;
end

-- The panel calls this per frame; a real request goes out at most once per
-- maxAge, and the mirror re-syncs every call (so a just-committed stream shows).
function M.refreshIfStale(maxAge)
    if _client == nil then return false; end
    local r = _client.ensureCategory(AH_CAT_AMMO, tonumber(maxAge) or 15);
    sync();
    return r;
end

function M.withdraw(itemId, qty)
    if _client == nil then return false; end
    local r = _client.withdraw(itemId, qty);
    sync();
    return r;
end

function M.isBusy()
    if _client == nil then return false; end
    local b = _client.isBusy();
    sync();
    return b;
end

-- Deliver one inbound 0x1A4 to the client and re-sync (headless seam, EB*). In
-- game the client's own handler does this; eboxammo registers NOTHING.
function M._onPacket(data)
    if _client == nil then return false; end
    local c = _client._onPacket(data);
    sync();
    return c;
end

-- Manual rescan (the panel's button): poke the watcher + stale, then re-request.
function M.rescan()
    if _client == nil then return false; end
    _client.rescan();
    M.at = 0;
    return M.refresh();
end

-- Nearest Ephemeral Box in yalms (the client owns the entwatch subscription).
function M.boxDistance()
    return (_client ~= nil) and _client.boxDistance() or nil;
end

-- ---------------------------------------------------------------------------
-- HIDDEN diagnostic `/dl ebox` (the /dl merits precedent -- in no help list):
-- dumps what the scan actually sees so a field round returns DATA, not
-- theories. Now eboxclient-backed (sync first), but the raw entity sweep stays
-- independent. Kept here (AutoAmmo's home) rather than moved, to keep the fold
-- minimal; _gm/_ew are required for the dump only.
-- ---------------------------------------------------------------------------
local _gmok, _gm = pcall(require, 'dlac\\feature\\gamemode');
_gmok = _gmok and type(_gm) == 'table';
local _ewok, _ew = pcall(require, 'dlac\\lib\\entwatch');
_ewok = _ewok and type(_ew) == 'table';

pcall(function()
    ashita.events.register('command', 'dlac_eboxammo_cmd', function(e)
        pcall(function()
            local cmd = string.lower(e.command or '');
            local a = cmd:match('^/dl%s+(%S+)');
            if a == nil then a = cmd:match('^/dlac%s+(%S+)'); end
            if a ~= 'ebox' then return; end
            e.blocked = true;
            sync();
            local gm = nil;
            pcall(function() gm = _gm.get(); end);
            print(string.format('[dlac] ebox: gamemode=%s isCW=%s locked=%s counts=%s dist=%s range=%d',
                tostring(gm), tostring(M.isCW()), tostring(M.lockedReason),
                (M.counts ~= nil) and 'cached' or 'nil', tostring(M.boxDistance()), M.BOX_RANGE));
            if _ewok then
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
