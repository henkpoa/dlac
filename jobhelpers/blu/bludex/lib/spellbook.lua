--[[
    bludex/lib/spellbook.lua -- the data service over data/spells.lua,
    data/traits.lua and data/hints.lua: lookups, indexes, and the filter
    engine the codex UI drives.

    Pure at load: requires only generated data. The single AshitaCore touch
    (learned()) is runtime-only and guarded, so this module loads headless.
]]--

-- relocatable require base: 'bludex\' standalone, '<host>\bludexlib\' when
-- vendored inside another addon (see INTEGRATION.md)
local ROOT = (...):sub(1, -#('lib\\spellbook') - 1);

local data   = require(ROOT .. 'data\\spells');
local traits = require(ROOT .. 'data\\traits');
local okh, hints = pcall(function() return require(ROOT .. 'data\\hints'); end);
if not okh then hints = { hints = {} }; end

local M = {
    spells = data.spells,
    order  = data.order,
    meta   = data.meta,
    traits = traits,
    hints  = hints.hints or {},
};

local function norm(s)
    return (tostring(s):lower():gsub('[^a-z0-9]', ''));
end
M.norm = norm;

-- ---------------------------------------------------------------------------
-- indexes (built once at load)
-- ---------------------------------------------------------------------------
M.byName = {};              -- normalized name -> id
M.byTrait = {};             -- trait category -> { ids sorted by weight desc }
M.categories = { 'Buff', 'Debuff', 'Healing', 'Offensive' };
M.elements = { 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark', 'None' };
M.types = {};               -- distinct spellType values, sorted

do
    local tset = {};
    for _, id in ipairs(M.order) do
        local s = M.spells[id];
        M.byName[norm(s.name)] = id;
        if s.trait then
            local t = M.byTrait[s.trait.category];
            if t == nil then t = {}; M.byTrait[s.trait.category] = t; end
            t[#t + 1] = id;
        end
        if s.spellType then tset[s.spellType] = true; end
    end
    for cat, ids in pairs(M.byTrait) do
        table.sort(ids, function(a, b)
            local wa = M.spells[a].trait.weight or 0;
            local wb = M.spells[b].trait.weight or 0;
            if wa ~= wb then return wa > wb; end
            return (M.spells[a].setPoints or 99) < (M.spells[b].setPoints or 99);
        end);
    end
    for t in pairs(tset) do M.types[#M.types + 1] = t; end
    table.sort(M.types);
end

-- trait category list for the filter combo: { {cat=n, name=s}, ... } sorted
-- by name; only categories some spell actually feeds.
M.traitChoices = {};
do
    for cat in pairs(M.byTrait) do
        local info = traits.categories[cat];
        M.traitChoices[#M.traitChoices + 1] = {
            cat = cat, name = (info and info.name) or ('Trait ' .. cat),
        };
    end
    table.sort(M.traitChoices, function(a, b) return a.name < b.name; end);
end

function M.traitName(cat)
    local info = traits.categories[cat];
    return (info and info.name) or ('Trait ' .. cat);
end

-- ---------------------------------------------------------------------------
-- runtime lookups (guarded; safe headless)
-- ---------------------------------------------------------------------------
function M.learned(id)
    local ok, r = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(id);
    end);
    return ok and r or false;
end

function M.zoneName(zoneId)
    local ok, r = pcall(function()
        return AshitaCore:GetResourceManager():GetString('zones.names', tonumber(zoneId));
    end);
    if ok and r ~= nil and r ~= '' then return r; end
    return 'Zone #' .. tostring(zoneId);
end

-- Learn-location hints for a spell: { { zone = 'Name', mobs = {...} }, ... }
-- (retail-era data from blucheck; CatsEyeXI spawns can differ).
function M.hintList(id)
    local h = M.hints[id];
    if h == nil then return nil; end
    local out = {};
    for zoneId, mobs in pairs(h) do
        out[#out + 1] = { zone = M.zoneName(zoneId), mobs = mobs };
    end
    table.sort(out, function(a, b) return a.zone < b.zone; end);
    return out;
end

-- ---------------------------------------------------------------------------
-- the filter engine
-- ---------------------------------------------------------------------------
-- spec fields (all optional):
--   text       substring match on normalized name
--   category   'Buff'|'Debuff'|'Healing'|'Offensive'
--   element    'Fire'|...|'None'
--   spellType  'Physical'|'Magical'|'Breath'
--   traitCat   number -- only spells feeding that trait category
--   learned    true (only learned) | false (only missing) | nil (all)
--   includeUncastable  default false (Regeneration stays hidden)
function M.filter(spec)
    spec = spec or {};
    local text = spec.text and spec.text ~= '' and norm(spec.text) or nil;
    local out = {};
    for _, id in ipairs(M.order) do
        local s = M.spells[id];
        local keep = true;
        if not s.castable and not spec.includeUncastable then keep = false; end
        if keep and spec.category and s.category ~= spec.category then keep = false; end
        if keep and spec.element and s.element ~= spec.element then keep = false; end
        if keep and spec.spellType and s.spellType ~= spec.spellType then keep = false; end
        if keep and spec.traitCat and not (s.trait and s.trait.category == spec.traitCat) then keep = false; end
        if keep and text and not norm(s.name):find(text, 1, true) then keep = false; end
        if keep and spec.learned ~= nil and M.learned(id) ~= spec.learned then keep = false; end
        if keep then out[#out + 1] = id; end
    end
    return out;
end

return M;
