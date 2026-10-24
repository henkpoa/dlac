--[[
    Divine Elements -- the rules, pure (no Ashita, no imgui), so the suite
    drives every answer headlessly.

    AscensionXI's Paladin, in Divine Fury, charges the next weapon skill with
    divine elements (server modules/custom/lua/pld_divine_fury.lua,
    documentation/custom/pld-divine-guard.md section 8). Each element adds
    its own level 1 property, and the level 2 property it makes with an
    element the weapon skill already has: a level 2 property is a pair of
    elements (Fusion = Fire + Light, Fragmentation = Wind + Lightning,
    Gravitation = Earth + Dark, Distortion = Water + Ice). From level 50 the
    weapon holds two elements, which also pair with each other.

    `plan` answers the window's two questions: what the elements you hold
    give your weapon skills now, and what it takes to make each level 2
    property, cheapest first.
]]--

local M = {};

M.ELEMENTS    = { 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Water', 'Light', 'Dark' };
M.FURY_ICON   = 655;  -- the Divine Fury buff
M.FIRST_ICON  = 660;  -- Divine Fire's buff; the other seven follow in ELEMENTS order
M.FIRST_ABILITY = 929; -- Divine Fire's client ability record (server id 417 + 512)
M.DUAL_LEVEL  = 50;

M.LEVEL1 = {
    Fire = 'Liquefaction', Ice = 'Induration', Wind = 'Detonation', Earth = 'Scission',
    Lightning = 'Impaction', Water = 'Reverberation', Light = 'Transfixion', Dark = 'Compression',
};

-- The level 2 properties in the order the window lists them.
M.PAIRS = {
    { prop = 'Fusion',        elements = { 'Fire', 'Light' } },
    { prop = 'Fragmentation', elements = { 'Wind', 'Lightning' } },
    { prop = 'Gravitation',   elements = { 'Earth', 'Dark' } },
    { prop = 'Distortion',    elements = { 'Ice', 'Water' } },
};

M.LEVEL3 = {
    Light    = { 'Fire', 'Wind', 'Lightning', 'Light' },
    Darkness = { 'Earth', 'Water', 'Ice', 'Dark' },
};

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true; end
    end
    return false;
end

-- The elements a property bursts on: one, two or four.
function M.elementsOf(prop)
    for element, p in pairs(M.LEVEL1) do
        if p == prop then return { element }; end
    end
    for _, pair in ipairs(M.PAIRS) do
        if pair.prop == prop then return { pair.elements[1], pair.elements[2] }; end
    end
    return M.LEVEL3[prop] or {};
end

-- The level 2 property two different elements make, or nil.
function M.pairOf(a, b)
    if a == b then return nil; end
    for _, pair in ipairs(M.PAIRS) do
        if contains(pair.elements, a) and contains(pair.elements, b) then return pair.prop; end
    end
    return nil;
end

-- The properties the elements add to a weapon skill that has `own`, the
-- server's rule (pf.addedProperties): the level 2 pairs first, then each
-- element's level 1, none already in `own`. A pair made only of the weapon
-- skill's own properties adds nothing.
function M.added(own, elements)
    local held, seen, out = {}, {}, {};
    for _, prop in ipairs(own) do
        seen[prop] = true;
        for _, e in ipairs(M.elementsOf(prop)) do held[e] = true; end
    end
    for _, e in ipairs(elements) do held[e] = true; end
    local function add(prop)
        if prop ~= nil and not seen[prop] then
            seen[prop] = true;
            out[#out + 1] = prop;
        end
    end
    for _, e in ipairs(elements) do
        for _, other in ipairs(M.ELEMENTS) do
            if held[other] then add(M.pairOf(e, other)); end
        end
    end
    for _, e in ipairs(elements) do add(M.LEVEL1[e]); end
    return out;
end

-- The divine elements held, in ELEMENTS order, from a buff set { [icon] = true }.
function M.held(buffs)
    local out = {};
    if type(buffs) ~= 'table' then return out; end
    for i, e in ipairs(M.ELEMENTS) do
        if buffs[M.FIRST_ICON + i - 1] then out[#out + 1] = e; end
    end
    return out;
end

-- "Crescent Moon, Hard Slash, Sickle Moon (+2)"
function M.names(list, most)
    most = most or 3;
    local shown = {};
    for i, name in ipairs(list) do
        if i <= most then shown[#shown + 1] = name; end
    end
    local text = table.concat(shown, ', ');
    if #list > most then text = text .. string.format(' (+%d)', #list - most); end
    return text;
end

local function missing(elements, held)
    local n = 0;
    for _, e in ipairs(elements) do
        if not contains(held, e) then n = n + 1; end
    end
    return n;
end

--[[
    The window's plan.
      input = { weaponskills = { { name, sc = {...} }, ... },  -- the ones you can use now
                held = { 'Dark' }, level = 75, points = 3 or nil }
    Returns
      { holding = held,
        gives   = { { skills = {names}, props = {...} }, ... }  -- what the held elements add
        builds  = { { prop, rows = { row, ... } }, ... } }       -- one per level 2 property
    A row is { kind = 'own' | 'ws' | 'any', skills = {names} (own and ws),
    elements = {...} (ws and any), cost = points still to spend, ready = held
    already, affordable = within the points (true when points are unknown) }.
    Rows run cheapest first: what a weapon skill has of its own, then one
    element, then two.
]]--
function M.plan(input)
    local skills = input.weaponskills or {};
    local held   = input.held or {};
    local level  = tonumber(input.level) or 0;
    local points = tonumber(input.points);
    local dual   = level >= M.DUAL_LEVEL;

    local out = { holding = held, gives = {}, builds = {} };

    -- What the held elements add, weapon skills grouped by the same answer.
    if #held > 0 then
        local byKey, order = {}, {};
        for _, ws in ipairs(skills) do
            local props = M.added(ws.sc or {}, held);
            local key = table.concat(props, ',');
            if byKey[key] == nil then
                byKey[key] = { skills = {}, props = props };
                order[#order + 1] = key;
            end
            local group = byKey[key];
            group.skills[#group.skills + 1] = ws.name;
        end
        for _, key in ipairs(order) do out.gives[#out.gives + 1] = byKey[key]; end
        table.sort(out.gives, function(a, b) return #a.props > #b.props; end);
    end

    for _, pair in ipairs(M.PAIRS) do
        local rows = {};
        local own = {};
        for _, ws in ipairs(skills) do
            if contains(ws.sc or {}, pair.prop) then own[#own + 1] = ws.name; end
        end
        if #own > 0 then
            rows[#rows + 1] = { kind = 'own', skills = own, cost = 0, ready = true };
        end

        -- One element, on the weapon skills that already have its partner.
        for i, e in ipairs(pair.elements) do
            local partner = pair.elements[3 - i];
            local list = {};
            for _, ws in ipairs(skills) do
                if not contains(ws.sc or {}, pair.prop) then
                    local mine = {};
                    for _, prop in ipairs(ws.sc or {}) do
                        for _, x in ipairs(M.elementsOf(prop)) do mine[x] = true; end
                    end
                    if mine[partner] then list[#list + 1] = ws.name; end
                end
            end
            if #list > 0 then
                local cost = missing({ e }, held);
                rows[#rows + 1] = { kind = 'ws', skills = list, elements = { e }, cost = cost, ready = cost == 0 };
            end
        end

        -- Both elements: any weapon skill, from level 50.
        if dual then
            local cost = missing(pair.elements, held);
            rows[#rows + 1] = { kind = 'any', elements = { pair.elements[1], pair.elements[2] }, cost = cost, ready = cost == 0 };
        end

        for index, row in ipairs(rows) do
            row.order = index;
            row.affordable = points == nil or row.cost <= points;
        end
        table.sort(rows, function(a, b)
            if a.cost ~= b.cost then return a.cost < b.cost; end
            return a.order < b.order;
        end);
        out.builds[#out.builds + 1] = { prop = pair.prop, rows = rows };
    end

    return out;
end

return M;
