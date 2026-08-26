--[[
    vanaheim/gearvault/usage.lua -- slice 4's dlac-side memory (GV3/GV4).

    Two things the vault deliberately does not know (Henrik: "this info
    needs to be handled in DLAC, because gear vault has no business knowing
    if it was ever used or not"):

      * LAST-USED STAMPS, identity-keyed (two differently-augmented copies
        age independently). GV4's definition is A+C -- engine-equipped plus
        observed worn -- and both collapse into one witness: a worn-scan
        beat, because everything the engine equips IS worn moments later.
        Every identity is SEEDED at first sight in the layout, so
        never-used gear has an age and ranks oldest naturally.

      * THE TWO BEHAVIOUR SETTINGS. additions: 'auto' (default -- dlac
        freely pushes derived entries) | 'off'. removals: 'ask' (default --
        shelf pressure presents a marking list) | 'auto' (LRU eviction,
        pinned still always asks) | 'off'.

    One file per character (<char>\dlac\gearvault_usage.lua), written on the
    safe ladder (hard rule 7 via lib\safewrite.replaceLua). Loading is
    latch-free in ADR 0007's sense: a missing char dir just retries on the
    next beat. Pure at load; IO and the clock ride injectable seams.

    EVICTION RANKING (GV3 Full mode, and the 'ask' list's order): UNPINNED
    only -- a pinned entry never auto-ranks, it is presented for explicit
    permission instead; UNASSIGNED first (nothing in the current derivation
    wants it), then oldest last-used first; name as the stable tie-break.
]]--

local M = {};

M.SETTINGS_DEFAULT = { additions = 'auto', removals = 'ask' };

-- seams
M._clock = os.time;
M._dir   = function()
    local d = nil;
    pcall(function() d = require('dlac\\lib\\statefile').charDir(); end);
    return d;
end;

local st = {
    loaded   = false,
    dirty    = false,
    stamps   = {},                       -- key -> epoch seconds
    settings = { additions = 'auto', removals = 'ask' },
};

local function hex48(identity)
    if type(identity) ~= 'string' then return string.rep('0', 48); end
    local out = {};
    for i = 1, 24 do
        out[#out + 1] = string.format('%02x', identity:byte(i) or 0);
    end
    return table.concat(out);
end

-- The usage key of one instance: the vault's own identity vocabulary,
-- '<itemId>:<hex48>' (zero blob = the plain copy).
function M.keyOf(itemId, identity)
    return tostring(itemId or 0) .. ':' .. hex48(identity);
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------
local function filePath()
    local d = M._dir();
    return d and (d .. 'gearvault_usage.lua') or nil;
end

function M._serialize()
    local L = {};
    L[#L + 1] = '-- dlac gear-vault usage (written by dlac; hand edits are fine)';
    L[#L + 1] = 'return {';
    L[#L + 1] = string.format('    settings = { additions = %q, removals = %q },',
        tostring(st.settings.additions), tostring(st.settings.removals));
    L[#L + 1] = '    stamps = {';
    local keys = {};
    for k in pairs(st.stamps) do keys[#keys + 1] = k; end
    table.sort(keys);
    for _, k in ipairs(keys) do
        L[#L + 1] = string.format('        [%q] = %d,', k, st.stamps[k]);
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '}';
    return table.concat(L, '\n') .. '\n';
end

function M._apply(t)
    if type(t) ~= 'table' then return; end
    if type(t.settings) == 'table' then
        local a, r = t.settings.additions, t.settings.removals;
        if a == 'auto' or a == 'off' then st.settings.additions = a; end
        if r == 'ask' or r == 'auto' or r == 'off' then st.settings.removals = r; end
    end
    if type(t.stamps) == 'table' then
        for k, v in pairs(t.stamps) do
            if type(k) == 'string' and type(v) == 'number' then st.stamps[k] = v; end
        end
    end
end

-- Load once per session; nil dir = not ready, retry next beat (never latch).
function M.load()
    if st.loaded then return true; end
    local p = filePath();
    if p == nil then return false; end
    st.loaded = true;
    pcall(function()
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok then M._apply(t); end
    end);
    return true;
end

function M.save()
    if not st.dirty then return true; end
    local p = filePath();
    if p == nil then return false; end
    local ok = false;
    pcall(function()
        local sw = require('dlac\\lib\\safewrite');
        ok = (sw.replaceLua(p, M._serialize()) == true);
    end);
    if not ok then
        -- first write (no file to replace) or headless: plain create
        pcall(function()
            local f = io.open(p, 'w');
            if f ~= nil then f:write(M._serialize()); f:close(); ok = true; end
        end);
    end
    if ok then st.dirty = false; end
    return ok;
end

function M.dirty() return st.dirty; end

-- ---------------------------------------------------------------------------
-- Stamps
-- ---------------------------------------------------------------------------

-- The piece was SEEN USED (worn): stamp now.
function M.stamp(keys)
    local now = M._clock();
    for _, k in ipairs(keys or {}) do
        if st.stamps[k] ~= now then
            st.stamps[k] = now;
            st.dirty = true;
        end
    end
end

-- First sight in the layout: give unseen identities an age WITHOUT touching
-- real stamps (a seed must never make used gear look fresher).
function M.seed(keys)
    local now = M._clock();
    for _, k in ipairs(keys or {}) do
        if st.stamps[k] == nil then
            st.stamps[k] = now;
            st.dirty = true;
        end
    end
end

function M.lastUsed(key) return st.stamps[key]; end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
function M.settings() return st.settings; end

function M.setSetting(k, v)
    if (k == 'additions' and (v == 'auto' or v == 'off'))
        or (k == 'removals' and (v == 'ask' or v == 'auto' or v == 'off')) then
        if st.settings[k] ~= v then
            st.settings[k] = v;
            st.dirty = true;
        end
        return true;
    end
    return false;
end

-- ---------------------------------------------------------------------------
-- Eviction ranking (GV3): entries = layout entries ({ itemId, identity,
-- count, pinned, name }); assignedIds = { [itemId] = true } from the current
-- derivation. Returns { unpinned = ordered candidates, pinned = the pinned
-- ones in the same order } -- the caller evicts from `unpinned` and ASKS
-- about `pinned`, in every mode.
-- ---------------------------------------------------------------------------
function M.rankEvictions(entries, assignedIds)
    assignedIds = assignedIds or {};
    local unpinned, pinned = {}, {};
    for _, e in ipairs(entries or {}) do
        local c = {
            itemId = e.itemId, identity = e.identity, count = e.count or 1,
            pinned = e.pinned == true, name = e.name or tostring(e.itemId),
            key = M.keyOf(e.itemId, e.identity),
            assigned = assignedIds[e.itemId] == true,
        };
        c.last = st.stamps[c.key] or 0;
        if c.pinned then pinned[#pinned + 1] = c; else unpinned[#unpinned + 1] = c; end
    end
    local function order(a, b)
        if a.assigned ~= b.assigned then return not a.assigned; end   -- unassigned first
        if a.last ~= b.last then return a.last < b.last; end          -- oldest first
        return a.name < b.name;
    end
    table.sort(unpinned, order);
    table.sort(pinned, order);
    return { unpinned = unpinned, pinned = pinned };
end

-- test seam
function M._reset()
    st = { loaded = false, dirty = false, stamps = {},
           settings = { additions = 'auto', removals = 'ask' } };
end
function M._st() return st; end

return M;
