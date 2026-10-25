--[[
    Divine Elements -- what an AscensionXI Paladin in Divine Fury has charged
    on the weapon, and what it takes to make each level 2 skillchain
    property:

      * Holding: the divine elements on the weapon now, and what they add to
        your weapon skills ("Crescent Moon, Hard Slash: Gravitation,
        Compression").
      * Build: per level 2 property (Fusion, Fragmentation, Gravitation,
        Distortion), cheapest first: the weapon skills that have it of their
        own, a weapon skill plus one element, any weapon skill plus the two
        (from level 50). What you already hold reads "ready"; what costs more
        points than you have is dimmed.

    READ-ONLY. This module never acts: no commands, no keys, no gear. It
    reads the client (the buffs, the Job Abilities menu, your weapon skills)
    and the AscensionXI pack's `pldGauge` service for your points. The rules
    are rules.lua; the weapon skills' properties are the server's own
    (data/weaponskills.lua, generated). Server contract: AscensionXI
    documentation/custom/pld-divine-guard.md section 8; dlac
    docs/design/divine-elements.md.

    The window shows while your main job is Paladin, Divine Fury is up and
    the divine elements are in your Job Abilities menu (from level 15).
]]--

local base  = 'dlac\\jobhelpers\\pld\\divine-elements\\';
local rules = require(base .. 'rules');
local data  = require(base .. 'data\\weaponskills');

local PLD = 7;

-- Skillchain colours, as the chains addon draws them, lightened for a dark window.
local PROP_COL = {
    Fusion        = { 1.00, 0.45, 0.45, 1.00 },
    Fragmentation = { 1.00, 0.60, 1.00, 1.00 },
    Gravitation   = { 0.80, 0.60, 0.35, 1.00 },
    Distortion    = { 0.35, 0.65, 1.00, 1.00 },
    Light         = { 1.00, 1.00, 1.00, 1.00 },
    Darkness      = { 0.55, 0.55, 1.00, 1.00 },
};
local ELEMENT_PROP_COL = {
    Liquefaction = { 1.00, 0.40, 0.35, 1.00 }, Induration = { 0.55, 1.00, 1.00, 1.00 },
    Detonation   = { 0.45, 1.00, 0.45, 1.00 }, Scission   = { 0.80, 0.70, 0.30, 1.00 },
    Impaction    = { 1.00, 0.45, 1.00, 1.00 }, Reverberation = { 0.40, 0.75, 1.00, 1.00 },
    Transfixion  = { 1.00, 1.00, 0.85, 1.00 }, Compression = { 0.60, 0.55, 1.00, 1.00 },
};
local function propCol(ui, prop) return PROP_COL[prop] or ELEMENT_PROP_COL[prop] or ui.COL.dim; end

-- ---------------------------------------------------------------------------
-- The client, behind one seam the suite replaces.
-- ---------------------------------------------------------------------------
local client = {};

-- { job, buffs = { [icon] = true }, listed } or nil.
function client.read()
    local out = nil;
    pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer();
        local buffs = {};
        for _, id in pairs(p:GetBuffs() or {}) do
            if type(id) == 'number' and id > 0 and id < 1024 then buffs[id] = true; end
        end
        out = { job = p:GetMainJob(), buffs = buffs, listed = p:HasAbility(rules.FIRST_ABILITY) == true };
    end);
    return out;
end

-- The weapon skills of the weapon in your hands: { { name, sc }, ... } by name.
function client.weaponskills()
    local list = {};
    pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer();
        local res = AshitaCore:GetResourceManager();
        for id, rec in pairs(data.ws) do
            if p:HasWeaponSkill(id) then
                local name = rec.name;
                local ok, r = pcall(function() return res:GetAbilityById(id); end);
                if ok and r ~= nil and r.Name ~= nil and type(r.Name[1]) == 'string' and r.Name[1] ~= '' then
                    name = r.Name[1];
                end
                list[#list + 1] = { name = name, sc = rec.sc };
            end
        end
    end);
    table.sort(list, function(a, b) return a.name < b.name; end);
    return list;
end

-- The weapon skill list changes only with the weapon; read it once a second.
local wsCache, wsAt = nil, nil;
local function weaponskills(now)
    if wsCache == nil or wsAt == nil or now - wsAt >= 1 or now < wsAt then
        wsCache, wsAt = client.weaponskills(), now;
    end
    return wsCache;
end

local function points(S)
    if type(S) ~= 'table' or type(S.server) ~= 'table' or type(S.server.service) ~= 'function' then return nil; end
    local ok, svc = pcall(S.server.service, 'pldGauge');
    if not ok or type(svc) ~= 'table' or type(svc.view) ~= 'function' then return nil; end
    local okView, v = pcall(svc.view);
    if okView and type(v) == 'table' and v.synced then return tonumber(v.points); end
    return nil;
end

local function level(S)
    if type(S) == 'table' and type(S.player) == 'table' and type(S.player.level) == 'function' then
        local ok, lv = pcall(S.player.level);
        if ok and type(lv) == 'number' then return lv; end
    end
    return 0;
end

local function enabled(S, key)
    local cfg = type(S) == 'table' and S.cfg or nil;
    return cfg ~= nil and cfg.get(key) == true;
end

-- The plan to draw, or nil and why ('job', 'stance', 'level').
local function view(S, now)
    local c = client.read();
    if c == nil or c.job ~= PLD then return nil, 'job'; end
    if not c.buffs[rules.FURY_ICON] then return nil, 'stance'; end
    if not c.listed then return nil, 'level'; end
    local pts = points(S);
    local plan = rules.plan({
        weaponskills = weaponskills(now or 0),
        held         = rules.held(c.buffs),
        level        = level(S),
        points       = pts,
    });
    plan.points = pts;
    return plan;
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
local function propList(ui, props)
    for i, prop in ipairs(props) do
        if i > 1 then ui.sameLine(); ui.dim(','); ui.sameLine(); end
        ui.text(propCol(ui, prop), prop);
    end
end

local function rowLabel(row)
    if row.kind == 'own' then return rules.names(row.skills); end
    local elements = table.concat(row.elements, ' + ');
    if row.kind == 'any' then return 'Any WS + ' .. elements; end
    return rules.names(row.skills) .. ' + ' .. elements;
end

local function rowNote(row)
    if row.kind == 'own' then return 'has it'; end
    if row.ready then return 'ready'; end
    return row.cost == 1 and '1 point' or string.format('%d points', row.cost);
end

local function draw(ui, plan)
    ui.text(ui.COL.head, 'Divine Elements');
    if plan.points ~= nil then
        ui.sameLine();
        ui.dim(plan.points == 1 and '1 point' or string.format('%d points', plan.points));
    end

    if #plan.holding == 0 then
        ui.dim('Holding nothing');
    else
        ui.text(ui.COL.ok, 'Holding ' .. table.concat(plan.holding, ' + '));
        for _, group in ipairs(plan.gives) do
            if #group.props > 0 then
                ui.dim('  ' .. rules.names(group.skills) .. ':');
                ui.sameLine();
                propList(ui, group.props);
            end
        end
    end

    ui.space();
    for _, build in ipairs(plan.builds) do
        ui.text(propCol(ui, build.prop), build.prop);
        if #build.rows == 0 then
            ui.dim('  none of your weapon skills');
        end
        for _, row in ipairs(build.rows) do
            local col = ui.COL.dim;
            if row.ready then col = ui.COL.ok; elseif row.affordable then col = nil; end
            if col == nil then
                ui.text({ 0.92, 0.92, 0.92, 1.00 }, '  ' .. rowLabel(row));
            else
                ui.text(col, '  ' .. rowLabel(row));
            end
            ui.sameLine();
            ui.dim(rowNote(row));
        end
    end

    ui.space();
    ui.dim('Light: Fusion meets Fragmentation. Darkness: Gravitation meets Distortion.');
end

local WHY = {
    job    = 'Shows while your main job is Paladin.',
    stance = 'Shows while Divine Fury is up.',
    level  = 'Shows from level 15, when the divine elements join your Job Abilities.',
};

-- ---------------------------------------------------------------------------
-- The window's position: remembered once a drag settles.
-- ---------------------------------------------------------------------------
local movedAt, posX, posY = nil, nil, nil;

local function flag(name) return rawget(_G, name) or 0; end

local function savePosition(S, now)
    if movedAt == nil or now < movedAt then return; end
    movedAt = nil;
    local cfg = S.cfg;
    if cfg == nil then return; end
    if posX ~= nil then cfg.set('x', posX); end
    if posY ~= nil then cfg.set('y', posY); end
end

return {
    api = 2,
    label = 'Divine Elements',
    jobs = { 'PLD' },
    servers = { 'ascensionxi' },

    config = {
        file = 'jobhelper-divine-elements.lua',
        keys = {
            window = 'boolean',
            locked = 'boolean',
            x      = 'number',
            y      = 'number',
        },
        defaults = {
            window = true,
            locked = false,
        },
    },

    panel = function(ctx)
        local ui, S = ctx.ui, ctx.S;
        if ui == nil or S == nil then return; end
        local cfg = S.cfg;
        local function toggle(key, label, tip)
            local nextValue = ui.toggle('divineelements_' .. key, label, enabled(S, key), tip);
            if nextValue ~= nil and cfg ~= nil then cfg.set(key, nextValue); end
        end
        ui.section('Window', 'A small window you can drag anywhere. It shows while Divine Fury is up.', function()
            toggle('window', 'Show the window', 'Off: the lines appear only here.');
            toggle('locked', 'Lock it in place', 'Stops the window moving when dragged.');
        end);
        ui.dim('Each element adds its own level 1 property: Fire Liquefaction, Ice Induration, Wind Detonation,');
        ui.dim('Earth Scission, Lightning Impaction, Water Reverberation, Light Transfixion, Dark Compression.');
        ui.space();
        local plan, why = view(S, os.clock());
        if plan == nil then
            ui.dim(WHY[why] or WHY.job);
            return;
        end
        draw(ui, plan);
    end,

    status = function(ctx)
        local ui, S = ctx.ui, ctx.S;
        if ui == nil then return; end
        local plan = view(S, os.clock());
        if plan ~= nil and #plan.holding > 0 then
            ui.dim('holding ' .. table.concat(plan.holding, ' + '));
        end
    end,

    window = function(ctx)
        local ui, S, imgui = ctx.ui, ctx.S, ctx.imgui;
        if ui == nil or S == nil or imgui == nil then return; end
        if not enabled(S, 'window') then return; end
        local now = os.clock();
        savePosition(S, now);
        local hidden = false;
        pcall(function() hidden = require('dlac\\feature\\gamehud').hidden(); end);
        if hidden then return; end
        local plan = view(S, now);
        if plan == nil then return; end

        local x, y = S.cfg and S.cfg.get('x') or nil, S.cfg and S.cfg.get('y') or nil;
        if type(x) == 'number' and type(y) == 'number' then
            imgui.SetNextWindowPos({ x, y }, flag('ImGuiCond_Once'));
        else
            imgui.SetNextWindowPos({ 60, 420 }, flag('ImGuiCond_FirstUseEver'));
        end
        local fl = flag('ImGuiWindowFlags_NoTitleBar') + flag('ImGuiWindowFlags_NoResize')
            + flag('ImGuiWindowFlags_NoScrollbar') + flag('ImGuiWindowFlags_NoScrollWithMouse')
            + flag('ImGuiWindowFlags_AlwaysAutoResize') + flag('ImGuiWindowFlags_NoFocusOnAppearing')
            + flag('ImGuiWindowFlags_NoNav') + flag('ImGuiWindowFlags_NoSavedSettings')
            + flag('ImGuiWindowFlags_NoCollapse');
        if enabled(S, 'locked') then fl = fl + flag('ImGuiWindowFlags_NoMove'); end
        if imgui.Begin('##dlac_divine_elements', { true }, fl) then
            local ok, err = pcall(draw, ui, plan);
            if not ok then ui.err('Divine Elements: ' .. tostring(err)); end
            local px, py = imgui.GetWindowPos();
            if type(px) == 'table' then py = px[2] or px.y; px = px[1] or px.x; end
            if type(px) == 'number' and type(py) == 'number' then
                px, py = math.floor(px), math.floor(py);
                if px ~= (posX or x) or py ~= (posY or y) then
                    posX, posY = px, py;
                    movedAt = now + 1;
                end
            end
        end
        imgui.End();
    end,

    -- Not part of the loader contract: the headless suite reads these.
    _client = client,
    _view   = view,
    _draw   = draw,
    _resetCache = function() wsCache, wsAt = nil, nil; end,
};
