--[[
    dlac/feature/craftpick.lua -- crafting gear for ONE recipe, weakest craft first.

    AscensionXI's Nexus (its crafting window) tells dlac which crafts the next
    synth needs (feature\nexuslink); this module answers which owned pieces to
    wear for it. Pure: owned pieces, the recipe's requirements and the player's
    skills come in as tables, so the suite drives every case headless
    (tests\nexuscraft.lua, NC*).

    WHY WEAKEST FIRST. On AscensionXI's server (synthutils.cpp, the
    crafting-hq-tier-rates fence) every craft a recipe needs makes its OWN break
    roll when you are under its level, and the HQ chance is 2% plus 1% for every
    level the LOWEST craft clears the recipe by, plus Synth HQ gear. A point of
    skill on the weakest craft is worth something; the same point on a stronger
    craft is worth nothing until the weakest catches up. Skill gear counts at the
    moment the synth starts; material-loss and skill-up gear count when it ends.

    TWO PASSES.
      1. Skill slots: every slot where an owned piece raises a craft the recipe
         needs. Every combination is tried (after dropping a piece that another
         piece for the same slot matches or beats on every needed craft), and
         the winner has the best margins sorted weakest first, compared at the
         first place they differ: the weakest craft goes as high as the gear
         allows, then the next weakest, and so on.
      2. Every slot still free, for the goal (craftwatch's hq / nq / skillup):
           hq      Synth HQ, then success, then material loss, then skill-up gain
           nq      a ring that blocks HQ for a needed craft, then success,
                   material loss, conserve, skill-up gain
           skillup skill-up gain, then success, material loss, Synth HQ
    A piece that blocks HQ for a needed craft is never worn under the hq goal.
]]--

local M = {};

M.CRAFTS = { 'Woodworking', 'Smithing', 'Goldsmithing', 'Clothcraft',
             'Leathercraft', 'Bonecraft', 'Alchemy', 'Cooking' };

-- Slot family (the gear record's Slot, lowercased) -> the equip slots it can
-- fill. Ammo is left out on purpose: crafting never wants an ammo swap (the
-- craft overlay's CRAFT_OVERLAY_SLOTS leaves it out for the same reason).
M.FAMILY = {
    main = { 'Main' }, sub = { 'Sub' }, range = { 'Range' },
    head = { 'Head' }, neck = { 'Neck' }, ear = { 'Ear1', 'Ear2' },
    body = { 'Body' }, hands = { 'Hands' }, ring = { 'Ring1', 'Ring2' },
    back = { 'Back' }, waist = { 'Waist' }, legs = { 'Legs' }, feet = { 'Feet' },
};
M.SLOT_ORDER = { 'Main', 'Sub', 'Range', 'Head', 'Neck', 'Ear1', 'Ear2', 'Body',
                 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet' };

-- Above this many combinations the skill pass stops trying them all and fills
-- the weakest craft one piece at a time instead. AscensionXI's craft gear tops
-- out near 4,000 combinations for a three-craft recipe.
M.COMBO_LIMIT = 50000;

local function num(v) return tonumber(v) or 0; end

local function sortedKeys(t)
    local ks = {};
    for k in pairs(t or {}) do ks[#ks + 1] = k; end
    table.sort(ks, function(a, b) return tostring(a) < tostring(b); end);
    return ks;
end

-- The crafts a requirement map names, in a fixed order. `req` = { Craft = level }.
function M.involved(req)
    local out = {};
    for _, c in ipairs(M.CRAFTS) do
        if num((req or {})[c]) > 0 then out[#out + 1] = c; end
    end
    return out;
end

local function blocksHq(item, involved)
    for _, c in ipairs(involved) do
        if num((item.anti or {})[c]) > 0 then return true; end
    end
    return false;
end

-- Success the piece adds to this recipe: the flat rate, plus a guild ring's
-- own-craft success (which the server only grants with its HQ block worn).
local function successFor(item, involved)
    local s = num(item.succ);
    for _, c in ipairs(involved) do s = s + num((item.sb or {})[c]); end
    return s;
end

-- The goal's ranking of a piece's non-skill stats, as a list compared left to
-- right (bigger first).
function M.goalScore(item, involved, goal)
    local succ = successFor(item, involved);
    if goal == 'nq' then
        return { blocksHq(item, involved) and 1 or 0, succ, num(item.mat), num(item.consv), num(item.gain) };
    elseif goal == 'skillup' then
        return { num(item.gain), succ, num(item.mat), num(item.hqr) };
    end
    return { num(item.hqr), succ, num(item.mat), num(item.gain) };
end

local function compareLists(a, b)   -- 1 when a is bigger, -1 when b is, 0 equal
    local n = math.max(#a, #b);
    for i = 1, n do
        local x, y = a[i] or 0, b[i] or 0;
        if x > y then return 1; end
        if x < y then return -1; end
    end
    return 0;
end
M._compareLists = compareLists;

local function anyPositive(list)
    for _, v in ipairs(list) do if v > 0 then return true; end end
    return false;
end

local function skillVec(item, involved)
    local v = {};
    for i, c in ipairs(involved) do v[i] = num((item.sk or {})[c]); end
    return v;
end

-- Margins sorted weakest first: the "leximin" key the skill pass maximises.
local function leximin(margins)
    local s = {};
    for i, m in ipairs(margins) do s[i] = m; end
    table.sort(s);
    return s;
end
M._leximin = leximin;

-- Drop a piece another piece for the same slot matches or beats on every
-- needed craft (ties keep the better goal score, then the name first in the
-- alphabet, so the answer never depends on table order).
local function prune(cands, goal, involved)
    local keep = {};
    for i, a in ipairs(cands) do
        local beaten = false;
        for j, b in ipairs(cands) do
            if i ~= j then
                local ge, gt = true, false;
                for k = 1, #a.vec do
                    if b.vec[k] < a.vec[k] then ge = false; break; end
                    if b.vec[k] > a.vec[k] then gt = true; end
                end
                if ge then
                    if gt then beaten = true;
                    else
                        local c = compareLists(b.score, a.score);
                        if c > 0 or (c == 0 and b.item.name < a.item.name) then beaten = true; end
                    end
                end
            end
            if beaten then break; end
        end
        if not beaten then keep[#keep + 1] = a; end
    end
    return keep;
end

local function usable(item, level)
    if type(item) ~= 'table' or type(item.name) ~= 'string' or item.name == '' then return false; end
    if level ~= nil and num(item.level) > level then return false; end
    return M.FAMILY[string.lower(tostring(item.slot or ''))] ~= nil;
end

-- The best pieces for a recipe.
--   items  -- the manifest's craftItems: { name, slot, level, n, sk, anti, sb,
--             hqr, succ, gain, mat, consv } (sk/anti/sb are { Craft = n })
--   req    -- { Craft = recipe level } for every craft the recipe needs
--   skills -- { Craft = your level }; a craft missing here counts as exactly
--             at the recipe's level
--   opts   -- { goal = 'hq'|'nq'|'skillup' (default hq), level = main job level }
-- Returns picks { Slot = item name } and info { involved, margins = { Craft =
-- margin with the picks on }, weakest, combos, greedy }.
function M.pick(items, req, skills, opts)
    opts = opts or {};
    local goal = (opts.goal == 'nq' or opts.goal == 'skillup') and opts.goal or 'hq';
    local level = tonumber(opts.level);
    local involved = M.involved(req);
    local picks, info = {}, { involved = involved, margins = {}, combos = 0, greedy = false };
    if #involved == 0 then return picks, info; end

    local base = {};
    for i, c in ipairs(involved) do
        local have = tonumber((skills or {})[c]);
        base[i] = (have ~= nil) and (have - num(req[c])) or 0;
    end

    -- Usable pieces by family, in name order.
    local byFamily = {};
    local list = {};
    for _, it in ipairs(items or {}) do
        if usable(it, level) and not (goal == 'hq' and blocksHq(it, involved)) then
            list[#list + 1] = it;
        end
    end
    table.sort(list, function(a, b) return a.name < b.name; end);
    for _, it in ipairs(list) do
        local fam = string.lower(it.slot);
        byFamily[fam] = byFamily[fam] or {};
        local fl = byFamily[fam];
        fl[#fl + 1] = it;
    end

    -- Pass 1: the skill slots.
    local slots, cands = {}, {};
    for _, fam in ipairs(sortedKeys(M.FAMILY)) do
        local cs = {};
        for _, it in ipairs(byFamily[fam] or {}) do
            local v = skillVec(it, involved);
            if anyPositive(v) then
                cs[#cs + 1] = { item = it, vec = v, score = M.goalScore(it, involved, goal) };
            end
        end
        if #cs > 0 then
            local paired = #M.FAMILY[fam] > 1;
            if not paired then cs = prune(cs, goal, involved); end
            for _, slot in ipairs(M.FAMILY[fam]) do
                slots[#slots + 1] = slot;
                -- A pair slot may also stay empty: its partner may need the
                -- only copy of the piece.
                local opts2 = {};
                for _, c in ipairs(cs) do opts2[#opts2 + 1] = c; end
                if paired then opts2[#opts2 + 1] = false; end
                cands[slot] = opts2;
            end
        end
    end

    local combos = 1;
    for _, slot in ipairs(slots) do combos = combos * #cands[slot]; end
    info.combos = combos;

    local chosen = {};
    local function counts(sel)
        local used = {};
        for _, c in pairs(sel) do
            if c then used[c.item.name] = (used[c.item.name] or 0) + 1; end
        end
        return used;
    end
    local function marginsOf(sel)
        local m = {};
        for i = 1, #involved do m[i] = base[i]; end
        for _, c in pairs(sel) do
            if c then for i = 1, #involved do m[i] = m[i] + c.vec[i]; end end
        end
        return m;
    end
    local function secondary(sel)
        local tot, nPieces, names = {}, 0, {};
        for _, slot in ipairs(slots) do
            local c = sel[slot];
            if c then
                nPieces = nPieces + 1;
                names[#names + 1] = c.item.name;
                for i, v in ipairs(c.score) do tot[i] = (tot[i] or 0) + v; end
            end
        end
        return tot, nPieces, table.concat(names, '\031');
    end
    -- The comparison key of a selection: weakest first, then the goal's own
    -- stats on the chosen pieces, then fewer pieces, then names (a fixed answer).
    local function keyOf(sel)
        local tot, nPieces, names = secondary(sel);
        return { lex = leximin(marginsOf(sel)), tot = tot, n = nPieces, names = names };
    end
    local function better(ka, kb)
        if kb == nil then return true; end
        local c = compareLists(ka.lex, kb.lex);
        if c ~= 0 then return c > 0; end
        c = compareLists(ka.tot, kb.tot);
        if c ~= 0 then return c > 0; end
        if ka.n ~= kb.n then return ka.n < kb.n; end
        return ka.names < kb.names;
    end

    local best, bestKey = nil, nil;
    if #slots > 0 and combos <= M.COMBO_LIMIT then
        local sel = {};
        local used = {};
        local function walk(i)
            if i > #slots then
                local k = keyOf(sel);
                if better(k, bestKey) then
                    best, bestKey = {}, k;
                    for s, v in pairs(sel) do best[s] = v; end
                end
                return;
            end
            local slot = slots[i];
            for _, c in ipairs(cands[slot]) do
                if c == false then
                    sel[slot] = false;
                    walk(i + 1);
                    sel[slot] = nil;
                else
                    local nm = c.item.name;
                    if (used[nm] or 0) < math.max(1, num(c.item.n)) then
                        used[nm] = (used[nm] or 0) + 1;
                        sel[slot] = c;
                        walk(i + 1);
                        sel[slot] = nil;
                        used[nm] = used[nm] - 1;
                    end
                end
            end
        end
        walk(1);
    elseif #slots > 0 then
        -- Too many combinations: raise the weakest craft one piece at a time.
        info.greedy = true;
        best = {};
        local stuck = {};
        while true do
            local m = marginsOf(best);
            local w = nil;
            for i = 1, #involved do
                if not stuck[i] and (w == nil or m[i] < m[w]) then w = i; end
            end
            if w == nil then break; end
            local used = counts(best);
            local pickSlot, pickC = nil, nil;
            for _, slot in ipairs(slots) do
                if best[slot] == nil then
                    for _, c in ipairs(cands[slot]) do
                        if c and c.vec[w] > 0 and (used[c.item.name] or 0) < math.max(1, num(c.item.n)) then
                            local cmp = 0;
                            if pickC ~= nil then
                                cmp = (c.vec[w] > pickC.vec[w]) and 1 or ((c.vec[w] < pickC.vec[w]) and -1 or 0);
                                if cmp == 0 then
                                    local sa, sb = 0, 0;
                                    for k = 1, #involved do sa = sa + c.vec[k]; sb = sb + pickC.vec[k]; end
                                    cmp = (sa > sb) and 1 or ((sa < sb) and -1 or compareLists(c.score, pickC.score));
                                end
                            end
                            if pickC == nil or cmp > 0 then pickSlot, pickC = slot, c; end
                        end
                    end
                end
            end
            if pickC == nil then stuck[w] = true;
            else best[pickSlot] = pickC; end
        end
    end

    for slot, c in pairs(best or {}) do
        if c then chosen[slot] = c.item; end
    end

    -- Pass 2: the free slots, for the goal.
    local used = {};
    for _, it in pairs(chosen) do used[it.name] = (used[it.name] or 0) + 1; end
    for _, slot in ipairs(M.SLOT_ORDER) do
        if chosen[slot] == nil then
            local fam = nil;
            for f, ss in pairs(M.FAMILY) do
                for _, s in ipairs(ss) do if s == slot then fam = f; end end
            end
            local bestIt, bestScore = nil, nil;
            for _, it in ipairs(byFamily[fam] or {}) do
                if (used[it.name] or 0) < math.max(1, num(it.n)) then
                    local sc = M.goalScore(it, involved, goal);
                    if anyPositive(sc) and (bestScore == nil or compareLists(sc, bestScore) > 0) then
                        bestIt, bestScore = it, sc;
                    end
                end
            end
            if bestIt ~= nil then
                chosen[slot] = bestIt;
                used[bestIt.name] = (used[bestIt.name] or 0) + 1;
            end
        end
    end

    for slot, it in pairs(chosen) do picks[slot] = it.name; end

    local final = {};
    for i = 1, #involved do final[i] = base[i]; end
    for _, it in pairs(chosen) do
        local v = skillVec(it, involved);
        for i = 1, #involved do final[i] = final[i] + v[i]; end
    end
    local weakest = nil;
    for i, c in ipairs(involved) do
        info.margins[c] = final[i];
        if weakest == nil or final[i] < info.margins[weakest] then weakest = c; end
    end
    info.weakest = weakest;
    return picks, info;
end

-- Do two pick tables name the same piece in every slot?
function M.samePicks(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return false; end
    for k, v in pairs(a) do
        if type(b[k]) ~= 'string' or string.lower(b[k]) ~= string.lower(v) then return false; end
    end
    for k in pairs(b) do if a[k] == nil then return false; end end
    return true;
end

return M;
