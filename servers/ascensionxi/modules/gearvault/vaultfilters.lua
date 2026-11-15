--[[
    ascensionxi/gearvault/vaultfilters.lua -- the Gear Vault tab's FILTERS
    (ticket AXI-103: "my vault is getting full of things I will never use
    when I am building out new jobs").

    A filter HIDES rows from the Vault and Shared Vault lists; it never moves,
    marks or forgets a piece. Nothing is hidden for good: the tab says how
    many rows the filters hold back and one click shows them all again. That
    is the whole answer to "I cannot find my ____ but I know I have one".

    Four filters, all off by default:
      job     only gear the current main job can wear (at any level)
      level   only gear between two levels
      hq      hide a piece once you own its high-quality version
      hobby   crafting and gathering gear: show it, hide it, or show only it

    Pure and headless: the tab hands in the records and the held counts, so
    the suite reads every rule (tests/gearvault_filters.lua).
]]--

local M = {};

local counts = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\layoutcounts');

M.HOBBY = { 'show', 'hide', 'only' };

function M.defaults(cap)
    return { job = false, hq = false, hobby = 'show', lvMin = 1, lvMax = cap or 75 };
end

-- A stored filter table made safe to use: unknown values fall back to "off",
-- and the two level ends are kept in order inside 1..cap.
function M.clean(f, cap)
    cap = cap or 75;
    local d = M.defaults(cap);
    if type(f) ~= 'table' then return d; end
    d.job = (f.job == true);
    d.hq = (f.hq == true);
    if f.hobby == 'hide' or f.hobby == 'only' then d.hobby = f.hobby; end
    local lo, hi = math.floor(tonumber(f.lvMin) or 1), math.floor(tonumber(f.lvMax) or cap);
    lo = math.max(1, math.min(cap, lo));
    hi = math.max(1, math.min(cap, hi));
    if lo > hi then lo, hi = hi, lo; end
    d.lvMin, d.lvMax = lo, hi;
    return d;
end

-- How many filters are doing something (the button's count).
function M.activeCount(f, cap)
    cap = cap or 75;
    local n = 0;
    if f.job then n = n + 1; end
    if f.hq then n = n + 1; end
    if f.hobby ~= 'show' then n = n + 1; end
    if f.lvMin > 1 or f.lvMax < cap then n = n + 1; end
    return n;
end

-- ---------------------------------------------------------------------------
-- Crafting and gathering gear: any piece that carries a stat for synthesis,
-- fishing, HELM (harvesting, logging, mining, excavation) or chocobo digging.
-- That is the guild aprons and rings, the Field and HELM sets, the fishing
-- gear and the dig gear, by what they DO -- no name list to fall behind.
-- ---------------------------------------------------------------------------
local HOBBY_KEYS = {
    WoodworkingSkill = true, SmithingSkill = true, GoldsmithingSkill = true, ClothcraftSkill = true,
    LeathercraftSkill = true, BonecraftSkill = true, AlchemySkill = true, CookingSkill = true,
    FishingSkill = true,
    HELM = true, EGGHELM = true, HelmBreakReduction = true, Surveyor = true,
    ConserveIngredient = true, ChocoboRidingTime = true,
};

function M.isHobbyStat(key)
    if type(key) ~= 'string' then return false; end
    if HOBBY_KEYS[key] then return true; end
    return key:find('^Synth') ~= nil or key:find('^AntiHQ') ~= nil or key:find('^Dig') ~= nil
        or key:find('ExtraRoll$') ~= nil;
end

function M.isHobby(rec)
    if type(rec) ~= 'table' or type(rec.Stats) ~= 'table' then return false; end
    for key in pairs(rec.Stats) do
        if M.isHobbyStat(key) then return true; end
    end
    return false;
end

-- ---------------------------------------------------------------------------
-- Job
-- ---------------------------------------------------------------------------
local function jobSet(rec)
    local set, all = {}, false;
    for k, v in pairs(type(rec.Jobs) == 'table' and rec.Jobs or {}) do
        local j = (type(k) == 'number') and v or k;
        if j == 'All' then all = true; elseif type(j) == 'string' then set[j] = true; end
    end
    return set, all;
end

-- Can `job` (an abbreviation) wear rec at SOME level? A record without a
-- job list cannot be judged and passes.
function M.wearableBy(rec, job)
    if type(rec) ~= 'table' or type(rec.Jobs) ~= 'table' or job == nil then return true; end
    local set, all = jobSet(rec);
    return all or set[job] == true;
end

-- Does every job that wears `low` also wear `high`?
local function coversJobs(high, low)
    local hs, hall = jobSet(high);
    if hall then return true; end
    local ls, lall = jobSet(low);
    if lall then return false; end
    for j in pairs(ls) do
        if not hs[j] then return false; end
    end
    return true;
end

-- ---------------------------------------------------------------------------
-- High quality. `better` is the pack's data\hqpairs.lua: [itemId] = the ids
-- the same recipe line makes at high quality.
--
-- A piece is hidden when the HQ copies you hold cover every slot the piece
-- could fill: one for a body piece, TWO for a ring, an earring or a one-handed
-- weapon (Mindlor's point on the ticket: with one HQ ring you may still wear
-- the NQ beside it). An HQ copy counts only when it asks for no higher level
-- and is open to every job the lower piece is, so hiding never costs a job or
-- a level-sync an option. An AUGMENTED copy is never hidden: its augments are
-- its own.
-- ---------------------------------------------------------------------------
function M.superseded(e, ctx)
    local rec = e.rec;
    local list = (type(ctx.better) == 'table') and ctx.better[e.itemId] or nil;
    if type(rec) ~= 'table' or type(list) ~= 'table' then return false; end
    if type(ctx.augmented) == 'function' and ctx.augmented(e) then return false; end
    local need = counts.limit(rec) or 1;
    local have = 0;
    for _, id in ipairs(list) do
        local n = (ctx.held or {})[id] or 0;
        if n > 0 then
            local hrec = ctx.recOf(id);
            if type(hrec) == 'table' and (tonumber(hrec.Level) or 0) <= (tonumber(rec.Level) or 0)
                and coversJobs(hrec, rec) then
                have = have + n;
            end
        end
    end
    return have >= need;
end

-- ---------------------------------------------------------------------------
-- One row against every filter. true = show it.
--   ctx = { job = 'WAR' | nil, held = itemId -> copies owned,
--           better = hqpairs, recOf = fn(id) -> record,
--           augmented = fn(row) -> true for an augmented copy }
-- A row whose record is unknown always shows: a filter must never hide what
-- it cannot read.
-- ---------------------------------------------------------------------------
function M.shows(e, f, ctx)
    local rec = e.rec;
    if type(rec) ~= 'table' then return true; end
    if f.job and not M.wearableBy(rec, ctx.job) then return false; end
    local lv = tonumber(rec.Level) or 0;
    if lv < f.lvMin or lv > f.lvMax then return false; end
    if f.hobby ~= 'show' then
        local hobby = M.isHobby(rec);
        if (f.hobby == 'hide' and hobby) or (f.hobby == 'only' and not hobby) then return false; end
    end
    if f.hq and M.superseded(e, ctx) then return false; end
    return true;
end

-- A filtered COPY of a grouped view ({ grouped = slot -> list | { _cats },
-- total }) with the name needle and the filters applied together.
-- out.hidden = rows that match the needle but are held back by a filter.
function M.apply(view, needle, f, ctx)
    local out = { grouped = {}, total = 0, hidden = 0 };
    local filtering = (f ~= nil);
    local function keep(e)
        if needle ~= '' and string.find(string.lower(e.name), needle, 1, true) == nil then return false; end
        if filtering and not M.shows(e, f, ctx) then
            out.hidden = out.hidden + 1;
            return false;
        end
        out.total = out.total + 1;
        return true;
    end
    for slot, data in pairs(view.grouped) do
        if data._cats ~= nil then
            for cat, list in pairs(data._cats) do
                for _, e in ipairs(list) do
                    if keep(e) then
                        out.grouped[slot] = out.grouped[slot] or { _cats = {} };
                        out.grouped[slot]._cats[cat] = out.grouped[slot]._cats[cat] or {};
                        table.insert(out.grouped[slot]._cats[cat], e);
                    end
                end
            end
        else
            for _, e in ipairs(data) do
                if keep(e) then
                    out.grouped[slot] = out.grouped[slot] or {};
                    table.insert(out.grouped[slot], e);
                end
            end
        end
    end
    return out;
end

return M;
