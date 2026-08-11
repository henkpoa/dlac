--[[
    bludex/lib/traitsource.lua -- WHERE A TRAIT CAME FROM.

    A job trait and a blue trait can be the same trait. When they are, the
    job GIVES you its tier for free -- and what the set's weight buys is
    only what climbs PAST it.

    THE CEXI LAW (Henrik, from the field, 2026-08-10): a blue tier HIGHER
    than the job's rank does apply -- invest the full weight for tier 2 and
    you get tier 2, /DNC's tier 1 or not. Weight that only reaches a tier
    the job already grants buys nothing (you had it anyway); nothing is
    ever "out of reach". This SUPERSEDES the base-LSB reading (the
    blueutils.cpp `TODO remove the trait and add the blu trait if it's
    stronger` suggested stronger-blue was never written) -- the field
    beats the public source, and the live 0x0AC bit stays the referee.

    THE COLLISION IS BY TRAIT ID, NOT BY LADDER. Category 24 is trait 15
    (Double Attack) on rung 1 and trait 16 (Triple Attack) on rung 2; category
    28 is 20 (Gilfinder) then 19 (Treasure Hunter). A WAR sub kills rung 1 and
    leaves rung 2 standing, because they are different traits. Every tier
    carries its own traitId for exactly this reason.

    THE SCALE IS bg-wiki's (2026-08-11): every ladder costs 8 trait points per
    rung, and a feeder spell pays 4 (6 on Skillchain/Mag. Burst/Gilfinder, 8
    for the lv99 spells, per-spell on Auto Refresh). Never write a rung's cost
    as a literal -- read it off the ladder. base-LSB is NOT the authority here:
    it mixes that scale with a legacy 1-unit one and ships only the first rung
    of most ladders. tools/generate_spells.py WIKI_LADDER carries the whole
    story and data/traits.lua is generated from it.

    ORDER OF EVENTS (src/map/utils/charutils.cpp, BuildingCharTraitsTable):
    main job at your main level, then sub job at your sub level, then blue.
    Within a job, the highest RANK whose level you have reached wins
    (battleutils::AddTraits) -- which is why sub-job tiers are usually low:
    the sub level is half of yours.

    AUTHORITY. data/jobtraits.lua is the public clone, i.e. base-LSB, and
    CatsEyeXI can override it where we cannot see. The live 0x0AC trait bit is
    the referee: `hasTrait` answers whether a trait is genuinely up right now,
    and every verdict carries the disagreement rather than hiding it. What the
    bit CANNOT do is attribute -- blue traits set the same bits -- which is
    why the table exists at all.

    Pure: no AshitaCore, no imgui. The caller passes jobs, levels, weights and
    (optionally) a live trait predicate.
]]--

local ROOT = (...):sub(1, -#('lib\\traitsource') - 1);
local jobdata = require(ROOT .. 'data\\jobtraits');

local M = {};

-- The client's command table puts job traits at 0x600; a trait's ability id is
-- that plus its trait id (dlac reads 1554 = 1536 + 18 for Dual Wield).
M.ABILITY_BASE = 1536;

function M.abilityId(traitId)
    return M.ABILITY_BASE + traitId;
end

M.jobCode = function(jobId) return jobdata.codes[jobId or 0]; end
M.jobName = function(jobId) return jobdata.names[jobId or 0]; end

-- ---------------------------------------------------------------------------
-- the job side
-- ---------------------------------------------------------------------------

-- What ONE job grants at ONE level: { [traitId] = { rank, level, mods, ... } }.
-- Mirrors battleutils::AddTraits -- rows at or below your level, highest rank
-- per trait id wins.
function M.jobTraits(jobId, level)
    local out = {};
    local rows = jobdata.jobs[jobId or 0];
    if rows == nil or level == nil or level < 1 then return out; end
    for traitId, ladder in pairs(rows) do
        local best = nil;
        for _, rung in ipairs(ladder) do
            if level >= rung.level and (best == nil or rung.rank > best.rank) then
                best = rung;
            end
        end
        if best ~= nil then
            out[traitId] = {
                traitId = traitId, job = jobId, level = best.level,
                rank = best.rank, mods = best.mods,
                merit = best.merit, tag = best.tag,
            };
        end
    end
    return out;
end

-- BOTH jobs merged the way the server merges them: main first, then sub, and a
-- higher rank displaces a lower one whichever job it came from. Each entry
-- carries `slot` ('main' | 'sub') -- the answer to "where from".
function M.jobs(mainJob, mainLevel, subJob, subLevel)
    local out = {};
    local function fold(jobId, level, slot)
        for traitId, e in pairs(M.jobTraits(jobId, level)) do
            local prev = out[traitId];
            if prev == nil or e.rank > prev.rank then
                e.slot = slot;
                e.code = jobdata.codes[jobId];
                e.name = jobdata.names[jobId];
                out[traitId] = e;
            end
        end
    end
    fold(mainJob, mainLevel, 'main');
    fold(subJob, subLevel, 'sub');
    return out;
end

-- ---------------------------------------------------------------------------
-- the blue side, and the verdict
-- ---------------------------------------------------------------------------

-- The two documented overwrites inside blueutils' staging loop: a higher rung
-- that is a DIFFERENT trait still displaces the lower one.
local OVERWRITES = {
    DOUBLE_ATTACK = 'TRIPLE_ATTACK',
    GILFINDER     = 'TREASURE_HUNTER',
};

-- A RUNG'S OWN NAME. Only worth showing when it differs from the ladder's --
-- category 24 is called Double Attack but its top rung is Triple Attack, a
-- different trait, and saying so is the difference between a clear row and a
-- baffling one. nil when the data has no name for the id.
function M.traitName(book, traitId)
    local names = book and book.traits and book.traits.traitNames;
    return names and names[traitId] or nil;
end

local function firstStat(tier)
    local m = tier.mods and tier.mods[1];
    return m and m.stat or nil;
end

-- does `staged` displace `tier` (both eligible, staged is the higher rung)?
local function displaces(staged, tier)
    if staged.traitId == tier.traitId then return true; end
    local want = OVERWRITES[firstStat(tier) or ''];
    return want ~= nil and firstStat(staged) == want;
end

-- ONE LADDER, ANSWERED. `weight` is what the set feeds this category (0 is a
-- real answer -- a job can hold the ladder on its own). `jobs` is M.jobs(...).
-- `hasTrait(traitId)` is optional and returns true/false/nil.
--
--   active      what is genuinely up, tier order, each { source = 'job'|'set' }
--   suppressed  blue tiers redundant because the job already GRANTS them
--   deadWeight  the set feeds this ladder and gets NOTHING back for it
--   contested   a job holds some id in this ladder (so the ladder is contested
--               even when a higher rung still gets through)
function M.verdict(cat, weight, book, jobs, hasTrait)
    local info = book.traits.categories[cat];
    local out = {
        cat = cat,
        name = (info and info.name) or ('Trait ' .. tostring(cat)),
        weight = weight or 0,
        active = {}, suppressed = {},
        held = {},
        deadWeight = false, contested = false,
    };
    if info == nil then return out; end
    jobs = jobs or {};

    -- THE LADDER, RUNG BY RUNG, against the jobs -- before the set is even
    -- looked at. One state matters (the CEXI law, Henrik 2026-08-10 -- the
    -- old 'blocked / out of reach' is gone, higher rungs are always open):
    --
    --   held   the job's own rank reaches this rung: you already have this
    --          much of the trait, from them, set or no set
    --
    -- Ranked PER RUNG, by that rung's own trait id, because a ladder is not
    -- always one trait: on category 24 a WAR at Double Attack rank 3 holds
    -- rung 1 and touches rung 2 not at all -- that is Triple Attack, another
    -- trait, and it comes through from the set untouched.
    for i, tier in ipairs(info.tiers) do
        local e = jobs[tier.traitId or info.traitId];
        if e ~= nil then
            out.contested = true;
            if out.blocker == nil then out.blocker = e; end
            if e.rank >= i then out.held[i] = e; end
        end
    end

    -- Descending rungs, exactly the order blueutils stages them in
    -- (trait_points_needed DESC), so the top rung is judged first. A rung
    -- the job already HOLDS is redundant for the set (suppressed); a rung
    -- ABOVE the job's rank comes through from the set -- blue climbs past
    -- a job trait on CatsEyeXI (the field law).
    local staged = {};
    local eligible = 0;
    for i = #info.tiers, 1, -1 do
        local tier = info.tiers[i];
        local traitId = tier.traitId or info.traitId;
        if out.weight >= tier.points then
            eligible = eligible + 1;
            if out.held[i] ~= nil then
                out.suppressed[#out.suppressed + 1] = {
                    tierIndex = i, points = tier.points, traitId = traitId,
                    mods = tier.mods, job = out.held[i],
                    held = true,
                };
            else
                local beaten = false;
                for _, s in ipairs(staged) do
                    if displaces(s, { traitId = traitId, mods = tier.mods }) then
                        beaten = true;
                        break;
                    end
                end
                if not beaten then
                    staged[#staged + 1] = { traitId = traitId, mods = tier.mods };
                    out.active[#out.active + 1] = {
                        source = 'set', tierIndex = i, points = tier.points,
                        traitId = traitId, mods = tier.mods,
                        -- TIER, not stat values: the two ladders express the
                        -- same trait through different modifiers (job Clear
                        -- Mind grants MPHEAL, blue grants CLEAR_MIND), so the
                        -- rank is the only thing comparable across them.
                        tier = i, traitName = M.traitName(book, traitId),
                    };
                end
            end
        end
    end

    -- the job's own rung on this ladder, whether or not it blocked anything:
    -- a trait you have from /DRG is active even with an empty set. Its TIER is
    -- the job's rank -- the game's own counter for that trait, and the number
    -- that lines up with the rungs below it.
    local seen = {};
    for _, a in ipairs(out.active) do seen[a.traitId] = true; end
    for _, tier in ipairs(info.tiers) do
        local traitId = tier.traitId or info.traitId;
        local e = jobs[traitId];
        if e ~= nil and not seen[traitId] then
            seen[traitId] = true;
            out.active[#out.active + 1] = {
                source = 'job', traitId = traitId, job = e,
                tier = e.rank, rank = e.rank, mods = e.mods, merit = e.merit,
                traitName = M.traitName(book, traitId),
            };
        end
    end
    table.sort(out.active, function(a, b) return (a.tier or 0) > (b.tier or 0); end);

    -- the point of the whole module: weight paid in, nothing delivered
    out.deadWeight = out.weight > 0 and eligible > 0 and #out.suppressed == eligible;

    -- the live bit has the last word on whether a trait is up. It cannot say
    -- WHERE from (blue traits set the same bits), so it only ever confirms or
    -- contradicts -- never attributes.
    if hasTrait ~= nil then
        for _, a in ipairs(out.active) do
            -- NOT `ok and live or nil`: a false answer is the whole point of
            -- asking, and that idiom turns it back into nil
            local ok, live = pcall(hasTrait, a.traitId);
            if ok and type(live) == 'boolean' then
                a.live = live;
                if not live then out.disagrees = true; end
            end
        end
    end
    return out;
end

-- WHICH RUNGS OF A LADDER A JOB ALREADY GRANTS, regardless of what the set
-- feeds (the CEXI law: only rungs the job's rank REACHES are redundant --
-- everything above them is open to the set). verdict's `suppressed` is
-- this filtered to the rungs the set actually reached; this is the whole
-- picture, which is what a spell tooltip needs (the spell is usually not
-- in the set yet when you are deciding).
-- Returns { blocks = {{tierIndex, traitId, job}}, total = #tiers } --
-- `all` = the job grants every rung, so feeding this ladder buys nothing.
function M.ladderBlocks(cat, book, jobs)
    local info = book.traits.categories[cat];
    local out = { blocks = {}, total = 0 };
    if info == nil then return out; end
    out.total = #info.tiers;
    for i, tier in ipairs(info.tiers) do
        local e = (jobs or {})[tier.traitId or info.traitId];
        if e ~= nil and e.rank >= i then
            out.blocks[#out.blocks + 1] = {
                tierIndex = i, traitId = tier.traitId or info.traitId, job = e,
            };
        end
    end
    out.all = out.total > 0 and #out.blocks == out.total;
    return out;
end

-- Every ladder at once: the Traits tab's whole answer in one call. `weights`
-- is { [cat] = weight } (build it from sets.traitEval). Sorted by name, and
-- ladders neither fed nor job-held are dropped unless `all` is true.
function M.survey(book, weights, jobs, hasTrait, all)
    local out = {};
    for _, choice in ipairs(book.traitChoices) do
        local v = M.verdict(choice.cat, (weights or {})[choice.cat] or 0,
                            book, jobs, hasTrait);
        if all or #v.active > 0 or #v.suppressed > 0 or v.weight > 0 then
            out[#out + 1] = v;
        end
    end
    table.sort(out, function(a, b) return a.name < b.name; end);
    return out;
end

-- { [cat] = weight } from a sets.traitEval array -- the shape verdict wants.
function M.weightsOf(evals)
    local w = {};
    for _, ev in ipairs(evals or {}) do w[ev.cat] = ev.weight; end
    return w;
end

return M;
