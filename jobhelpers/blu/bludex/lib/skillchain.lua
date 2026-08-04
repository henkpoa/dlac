--[[
    bludex/lib/skillchain.lua -- skillchain resonance rules + the weaponskill
    partner search for a BLU spell.

    The pairing table and resolution order are a verbatim port of the
    server's battleutils.cpp (skillchain_map + FormSkillchain): the opener's
    properties are tried primary-first, and for each, every closer property
    primary-first; the FIRST pair in the map wins. Weaponskill data comes
    from data/weaponskills.lua (generated).

    Pure: no AshitaCore, no imgui -- smoke-testable headless.
]]--

-- relocatable require base: 'bludex\' standalone, '<host>\bludexlib\' vendored
local ROOT = (...):sub(1, -#('lib\\skillchain') - 1);

local okw, wsdata = pcall(function() return require(ROOT .. 'data\\weaponskills'); end);
if not okw then wsdata = { weapons = {}, ws = {} }; end

local M = {
    weapons = wsdata.weapons,
    ws      = wsdata.ws,
};

-- chain level (display color) and magic-burst elements per resonance
M.LEVEL = {
    Transfixion = 1, Compression = 1, Liquefaction = 1, Scission = 1,
    Reverberation = 1, Detonation = 1, Induration = 1, Impaction = 1,
    Gravitation = 2, Distortion = 2, Fusion = 2, Fragmentation = 2,
    Light = 3, Darkness = 3, ['Light II'] = 4, ['Darkness II'] = 4,
};
M.ELEMENTS = {
    Transfixion = 'Light', Compression = 'Dark', Liquefaction = 'Fire',
    Scission = 'Earth', Reverberation = 'Water', Detonation = 'Wind',
    Induration = 'Ice', Impaction = 'Thunder',
    Gravitation = 'Dark/Earth', Distortion = 'Water/Ice',
    Fusion = 'Fire/Light', Fragmentation = 'Wind/Thunder',
    Light = 'Fire/Wind/Thunder/Light', Darkness = 'Dark/Earth/Water/Ice',
    ['Light II'] = 'Fire/Wind/Thunder/Light',
    ['Darkness II'] = 'Dark/Earth/Water/Ice',
};

-- P[opener][closer] = result (battleutils' skillchain_map keys are
-- { closer, opener } -- flipped here so the loops read naturally)
local P = {};
local function pair(opener, closer, result)
    P[opener] = P[opener] or {};
    P[opener][closer] = result;
end
-- Level 3 pairs
pair('Light', 'Light', 'Light II');
pair('Darkness', 'Darkness', 'Darkness II');
-- Level 2 pairs
pair('Gravitation', 'Distortion', 'Darkness');
pair('Gravitation', 'Fragmentation', 'Fragmentation');
pair('Distortion', 'Gravitation', 'Darkness');
pair('Distortion', 'Fusion', 'Fusion');
pair('Fusion', 'Gravitation', 'Gravitation');
pair('Fusion', 'Fragmentation', 'Light');
pair('Fragmentation', 'Distortion', 'Distortion');
pair('Fragmentation', 'Fusion', 'Light');
-- Level 1 pairs > level 2 skillchain
pair('Transfixion', 'Scission', 'Distortion');
pair('Liquefaction', 'Impaction', 'Fusion');
pair('Detonation', 'Compression', 'Gravitation');
pair('Induration', 'Reverberation', 'Fragmentation');
-- Level 1 pairs
pair('Transfixion', 'Compression', 'Compression');
pair('Transfixion', 'Reverberation', 'Reverberation');
pair('Compression', 'Transfixion', 'Transfixion');
pair('Compression', 'Detonation', 'Detonation');
pair('Liquefaction', 'Scission', 'Scission');
pair('Scission', 'Liquefaction', 'Liquefaction');
pair('Scission', 'Reverberation', 'Reverberation');
pair('Scission', 'Detonation', 'Detonation');
pair('Reverberation', 'Induration', 'Induration');
pair('Reverberation', 'Impaction', 'Impaction');
pair('Detonation', 'Scission', 'Scission');
pair('Induration', 'Compression', 'Compression');
pair('Induration', 'Impaction', 'Impaction');
pair('Impaction', 'Liquefaction', 'Liquefaction');
pair('Impaction', 'Detonation', 'Detonation');

-- The chain an opener/closer property pair produces, nil when none.
-- Property order matters exactly as on the server: opener props are the
-- standing resonance (all of them), closer props primary-first close it.
function M.resolve(openProps, closeProps)
    for _, r in ipairs(openProps or {}) do
        local row = P[r];
        if row ~= nil then
            for _, s in ipairs(closeProps or {}) do
                if row[s] ~= nil then return row[s]; end
            end
        end
    end
    return nil;
end

-- every weaponskill of a weapon, in data (skill level) order
function M.forWeapon(weapon)
    local out = {};
    for _, w in ipairs(M.ws) do
        if w.weapon == weapon then out[#out + 1] = w; end
    end
    return out;
end

-- Partner lists for a spell's properties against one weapon, each entry
-- { ws, chain, level }. wsOpens: WS opens -> spell closes (first in the
-- window); spellOpens: spell opens -> WS closes. Sorted by chain level
-- descending (the big chains first), data order within a level.
function M.partners(spellSC, weapon)
    local wsOpens, spellOpens = {}, {};
    for _, w in ipairs(M.forWeapon(weapon)) do
        local c1 = M.resolve(w.sc, spellSC);
        if c1 ~= nil then
            wsOpens[#wsOpens + 1] = { ws = w, chain = c1, level = M.LEVEL[c1] or 1 };
        end
        local c2 = M.resolve(spellSC, w.sc);
        if c2 ~= nil then
            spellOpens[#spellOpens + 1] = { ws = w, chain = c2, level = M.LEVEL[c2] or 1 };
        end
    end
    local function byLevel(t)
        local keyed = {};
        for i, e in ipairs(t) do keyed[i] = { i = i, e = e }; end
        table.sort(keyed, function(a, b)
            if a.e.level ~= b.e.level then return a.e.level > b.e.level; end
            return a.i < b.i;
        end);
        local out = {};
        for i, k in ipairs(keyed) do out[i] = k.e; end
        return out;
    end
    return byLevel(wsOpens), byLevel(spellOpens);
end

-- display labels for the ws tags
M.TAGS = {
    quest = 'WSNM', relic = 'Relic', mythic = 'Mythic',
    empyrean = 'Empyrean', merit = 'Merit/Aeonic',
};

return M;
