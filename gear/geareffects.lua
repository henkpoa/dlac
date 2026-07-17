--[[
    dlac/geareffects.lua -- conditional item effects: THE gear-set bonus evaluator
    (docs/design/conditional-effects.md; P1 display + P3 optimizer seam).

    Pure core in the groupsmodel/actionpicker mold: no Ashita, no imgui, no file
    IO. Data arrives from the generated modules (pcall-required with {} fallback,
    the levelstats.lua pattern) or injected via M.configure for headless tests.
    Never seeded into LAC -- the GAME applies the real set bonuses at equip time;
    everything here is planning/display/scoring (ADR 0006: sets are plans).

    Set semantics, verified against the server applier (gear_sets.lua:2473-2510,
    read 2026-07-17 -- design doc Appendix C):
      * counting is per composition SLOT, no uniqueness check -- two copies of one
        piece in Ring1/Ring2 count as TWO;
      * a piece counts only while ctx.level >= its required Level (the level-sync
        gate); nil ctx.level = no gate (stats themselves always sum);
      * a tier value is the TOTAL at that count (replacement, not cumulative):
        tiers[math.min(count, max)], nil below min -- `max` ships in the data, the
        runtime never re-derives server tier indexing;
      * piece lists may EXCEED max (alternate pieces, weapons included) and an
        item can belong to several sets (setsOf returns a list).

    Latent rows (data\latentstats.lua) are LOADED here but dormant: no condition
    predicates are registered yet -- that is P2 (issue #41). latentsOf exists so
    P2 wires display without another data pass.

    Copy-on-write discipline (the levelstats.apply rule): never write into
    rec.Stats; itemStats returns the resolver's table (zero-copy passthrough for
    non-scaling items), comboStats builds fresh sums.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- data (self-loaded, test-overridable)
-- ---------------------------------------------------------------------------
local gearsets = {};   -- setId -> { pieces = {ids}, min, max, tiers = {[count] = {stat->delta}} }
local latents  = {};   -- itemId -> latent rows (dormant until P2)
local lstats   = nil;  -- the levelstats module (M.effective), THE stats-at-level resolver
local byItem   = {};   -- itemId -> sorted {setId, ...} reverse index

local function rebuildIndex()
    byItem = {};
    for sid, e in pairs(gearsets) do
        if type(e) == 'table' and type(e.pieces) == 'table' then
            for _, pid in ipairs(e.pieces) do
                local l = byItem[pid];
                if l == nil then l = {}; byItem[pid] = l; end
                l[#l + 1] = sid;
            end
        end
    end
    for _, l in pairs(byItem) do table.sort(l); end
end

-- Inject/replace data (tests, or a future explicit reload). Partial: only the
-- keys given are replaced; gearsets triggers a reverse-index rebuild.
function M.configure(deps)
    if type(deps) ~= 'table' then return; end
    if type(deps.gearsets) == 'table' then gearsets = deps.gearsets; rebuildIndex(); end
    if type(deps.latents) == 'table' then latents = deps.latents; end
    if deps.levelstats ~= nil then lstats = deps.levelstats; end
end

do  -- default load: generated data + the central level resolver, all fail-soft
    local ok, d = pcall(require, "dlac\\data\\gearsets");
    if ok and type(d) == 'table' then gearsets = d; end
    ok, d = pcall(require, "dlac\\data\\latentstats");
    if ok and type(d) == 'table' then latents = d; end
    ok, d = pcall(require, "dlac\\data\\levelstats");
    if ok and type(d) == 'table' then lstats = d; end
    rebuildIndex();
end

-- ---------------------------------------------------------------------------
-- membership + tier access (the optimizer seam -- opts.effects in optimizePicks)
-- ---------------------------------------------------------------------------

-- Sets this item belongs to: sorted {setId, ...}, or nil (zero-alloc for the
-- overwhelmingly common no-set item).
function M.setsOf(itemId)
    if itemId == nil then return nil; end
    return byItem[itemId];
end

-- The raw set entry (pieces/min/max/tiers), or nil.
function M.setInfo(setId)
    return (setId ~= nil) and gearsets[setId] or nil;
end

-- Stat deltas of a set at a piece count: tiers[math.min(count, max)], nil below
-- min. The ONLY tier arithmetic in the runtime (design #3.1).
function M.setTier(setId, count)
    local e = (setId ~= nil) and gearsets[setId] or nil;
    if e == nil or type(count) ~= 'number' or count < (e.min or 2) then return nil; end
    return e.tiers[math.min(count, e.max or count)];
end

-- Latent rows for an item (P2 consumes these; nothing evaluates them yet).
function M.latentsOf(itemId)
    if itemId == nil then return nil; end
    return latents[itemId];
end

-- ---------------------------------------------------------------------------
-- evaluation
-- ---------------------------------------------------------------------------

-- Effective ITEM-LOCAL stats (level scaling; latent conditions arrive with P2).
-- Delegates to levelstats.effective -- zero-copy passthrough when nothing
-- applies. ctx = { level = n } or nil; slotLabel reserved for P2's
-- EQUIPPED_IN_SLOT latents.
function M.itemStats(rec, ctx, slotLabel)
    if type(rec) ~= 'table' then return nil; end
    if lstats ~= nil and type(lstats.effective) == 'function' then
        return lstats.effective(rec, ctx and ctx.level or nil);
    end
    return rec.Stats;
end

-- Per-set piece counts of a composition ({ slotLabel -> rec }), per SLOT
-- (duplicates count twice) and level-gated like the server applier: a piece
-- with rec.Level above ctx.level does not count. Returns { setId -> count }.
function M.countPieces(composition, ctx)
    local cnt = {};
    local level = (ctx ~= nil) and tonumber(ctx.level) or nil;
    for _, rec in pairs(composition or {}) do
        if type(rec) == 'table' and rec.Id ~= nil then
            local sids = byItem[rec.Id];
            if sids ~= nil and (level == nil or (tonumber(rec.Level) or 0) <= level) then
                for _, sid in ipairs(sids) do cnt[sid] = (cnt[sid] or 0) + 1; end
            end
        end
    end
    return cnt;
end

-- THE TRUE COMBINATION EVALUATOR: stats of a whole composition -- every item's
-- effective stats summed PLUS every active set-bonus tier. Returns
--   { stats = { statKey -> total },      -- numeric keys only; fresh table
--     setBonuses = { { setId, count, min, max, tier, deltas, active }, ... } }
-- setBonuses lists every set with at least one piece present (sorted by setId),
-- INCLUDING below-min partial sets (active = false, deltas = nil) -- that is the
-- "one more piece lights this up" display row. tier is the applied tier count
-- (min(count, max)) when active.
function M.comboStats(composition, ctx)
    local out = {};
    for _, rec in pairs(composition or {}) do
        if type(rec) == 'table' then
            local st = M.itemStats(rec, ctx);
            if type(st) == 'table' then
                for k, v in pairs(st) do
                    if type(v) == 'number' then out[k] = (out[k] or 0) + v; end
                end
            end
        end
    end
    local cnt = M.countPieces(composition, ctx);
    local sids = {};
    for sid in pairs(cnt) do sids[#sids + 1] = sid; end
    table.sort(sids);
    local bonuses = {};
    for _, sid in ipairs(sids) do
        local e = gearsets[sid];
        local deltas = M.setTier(sid, cnt[sid]);
        if deltas ~= nil then
            for k, v in pairs(deltas) do
                if type(v) == 'number' then out[k] = (out[k] or 0) + v; end
            end
        end
        bonuses[#bonuses + 1] = {
            setId  = sid,
            count  = cnt[sid],
            min    = e.min,
            max    = e.max,
            tier   = (deltas ~= nil) and math.min(cnt[sid], e.max) or nil,
            deltas = deltas,
            active = deltas ~= nil,
        };
    end
    return { stats = out, setBonuses = bonuses };
end

return M;
