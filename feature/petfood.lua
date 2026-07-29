--[[
    dlac/feature/petfood.lua -- the pet-food LADDER (issue #138, PRD #135).

    A Ladder in the CONTEXT.md sense: an ordered candidate list plus the rule
    that reads it -- walk top-down (highest tier first), take the first rung that
    clears every gate; gates only ever REMOVE candidates, never reorder. Here the
    rungs are the eight pet-food tiers and the two gates are:
      1. equip LEVEL -- the player's level must reach the tier's level, or the
         food is unequippable (the ammo slot rejects it);
      2. bag STOCK   -- at least one of that tier must sit in an equippable bag
         (Owned vs Available: what the player CARRIES is the control, per the
         PRD -- there is NO list UI, the ladder reads the bags).

    There is deliberately no player-facing list: the highest tier a BST both can
    wear AND is carrying is the right Reward food, always, so the feature reads it
    off the bags instead of asking. Carrying none is a LOUD refusal, not a silent
    no-op (hard rule 12): "you are not carrying any pet food."

    The tier table is DATA here, not read from the catalog -- CatsEyeXI's catalog
    ships only six of the eight tiers (Gamma and Epsilon are absent), and the
    ladder must still gate on the levels of the two it does not stock so a level
    band never silently collapses. Ids/levels are the canonical FFXI pet foods
    (Alpha 12 -> Theta 96, every 12 levels). Ammo slot, "All" jobs.

    Pure core: `pick(reads)` takes injected level + per-id stock reads and no
    AshitaCore, so the acceptance tests (AC4) drive every band headlessly. The
    live reads (`liveReads`) wrap ownedcache + the player level under pcall.
]]--

local M = {};

-- The eight tiers, LOWEST first (the natural level order). pick() walks this
-- HIGHEST first. Id + Level are the two facts the gates need; Name is what the
-- claim and the chat line carry.
M.TIERS = {
    { key = 'Alpha',   name = 'Pet Food Alpha',   id = 17016, level = 12 },
    { key = 'Beta',    name = 'Pet Food Beta',    id = 17017, level = 24 },
    { key = 'Gamma',   name = 'Pet Food Gamma',   id = 17018, level = 36 },
    { key = 'Delta',   name = 'Pet Food Delta',   id = 17019, level = 48 },
    { key = 'Epsilon', name = 'Pet Food Epsilon', id = 17020, level = 60 },
    { key = 'Zeta',    name = 'Pet Food Zeta',    id = 17021, level = 72 },
    { key = 'Eta',     name = 'Pet Food Eta',     id = 17022, level = 84 },
    { key = 'Theta',   name = 'Pet Food Theta',   id = 17023, level = 96 },
};

-- ---------------------------------------------------------------------------
-- pure core -- reads injected, no AshitaCore
-- ---------------------------------------------------------------------------
--
-- reads = {
--   level     = <player level, number>          -- nil = unknown (treated as 99,
--                                                  so a pre-login preview never
--                                                  hides a tier the bags hold),
--   stockOf   = function(id) -> count in bags,   -- 0 / nil = not carried,
-- }
-- returns:
--   on success -> { ok = true, id, name, key, level }  (the chosen rung)
--   on failure -> { ok = false, reason = 'none-carried' | 'level' }
--     'none-carried' -- no tier is BOTH wearable and in the bags (the loud
--                       refusal case); 'level' -- carried food but every carried
--                       tier is above the player's level.
function M.pick(reads)
    reads = reads or {};
    local level = tonumber(reads.level);
    if level == nil then level = 99; end            -- unknown level never hides a carried tier
    local stockOf = (type(reads.stockOf) == 'function') and reads.stockOf or function() return 0; end

    local carriedAny = false;                        -- carrying food at all (any tier, any level)
    for i = #M.TIERS, 1, -1 do                        -- HIGHEST tier first
        local t = M.TIERS[i];
        local n = tonumber(stockOf(t.id)) or 0;
        if n > 0 then
            carriedAny = true;
            if t.level <= level then
                return { ok = true, id = t.id, name = t.name, key = t.key, level = t.level };
            end
        end
    end
    -- Carried food but every carried tier is above the player's level -> 'level';
    -- carrying nothing at all -> the loud 'none-carried' refusal.
    if carriedAny then return { ok = false, reason = 'level' }; end
    return { ok = false, reason = 'none-carried' };
end

-- The chat line for a refusal, naming the blocker in one honest sentence (hard
-- rule 12). Pure; the caller emits it.
function M.refusalLine(pick)
    if type(pick) ~= 'table' then return 'no pet food available.'; end
    if pick.reason == 'level' then
        return 'the pet food you are carrying is above your level.';
    end
    return 'you are not carrying any pet food.';
end

-- ---------------------------------------------------------------------------
-- live reads (Ashita only)
-- ---------------------------------------------------------------------------

-- Per-id available (equippable-bag) count, via ownedcache (the one owned-count
-- door). 0 when it cannot answer -- a food it cannot see is a food not carried,
-- which is the safe read here (better a refusal than firing Reward bare).
M._stockOf = function(id)
    local n = 0;
    pcall(function()
        local oc = require('dlac\\gear\\ownedcache');
        local counts = (type(oc.counts) == 'function') and oc.counts() or nil;
        if type(counts) == 'table' then n = tonumber(counts[id]) or 0; end
    end);
    return n;
end

-- The player's current level, or nil (unknown). Main-job level.
M._playerLevel = function()
    local lv = nil;
    pcall(function()
        local p = gData and gData.GetPlayer and gData.GetPlayer() or nil;
        if type(p) == 'table' then lv = tonumber(p.MainJobLevel); end
    end);
    return lv;
end

function M.liveReads()
    return { level = M._playerLevel(), stockOf = M._stockOf };
end

-- The one-liner the button uses. A caller override (`reads`) keeps it drivable.
function M.choose(reads)
    return M.pick(reads or M.liveReads());
end

return M;
