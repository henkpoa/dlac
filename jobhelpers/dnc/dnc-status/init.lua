--[[
    DNC Status -- what an AscensionXI Dancer cannot see in the client:

      * Perpetual Step's memory: the Steps it remembers, and how many levels
        of each it puts on now (1 + 3 per Unbroken Rhythm stack, all of them
        under Trance);
      * Unbroken Rhythm: the stacks, when the next one drops, and the TP the
        next one costs;
      * the Steps on the monster you are fighting, and how long each lasts.

    READ-ONLY. This module never acts: no commands, no keys, no gear. It
    reads the AscensionXI pack's `dncStatus` service (servers\ascensionxi\
    modules\dncstatus), which joins what the client sees for itself (buffs,
    their timers, TP) with what only the server knows (the remembered levels,
    the Dazes on the target, the prices). Server contract: AscensionXI
    documentation/custom/dnc-status.md; dlac docs/design/dnc-status.md.

    Two surfaces, one drawing: the Panel (the switches, and the same lines as
    a preview) and a small floating window for play. The window shows itself
    only while there is something to show -- a memory, stacks, or a fight --
    so it stays out of the way in town. Showing either one is what makes dlac
    ask the server; a Dancer with both off costs it nothing.
]]--

local SERVICE = 'dncStatus';

-- The pack module may mount after this module's init, so the service is
-- looked up when it is needed, never cached at load.
local function service(S)
    if type(S) ~= 'table' or type(S.server) ~= 'table' or type(S.server.service) ~= 'function' then
        return nil;
    end
    local ok, svc = pcall(S.server.service, SERVICE);
    return (ok and type(svc) == 'table') and svc or nil;
end

local function enabled(S, key)
    local cfg = type(S) == 'table' and S.cfg or nil;
    return cfg ~= nil and cfg.get(key) == true;
end

local function anySection(S)
    return enabled(S, 'rememberedSteps') or enabled(S, 'rhythm') or enabled(S, 'targetEffects');
end

-- The joined view, or nil and why ('job', 'waiting', 'unsupported', 'none').
local function view(svc)
    if svc == nil or type(svc.view) ~= 'function' then return nil, 'none'; end
    local ok, v, why = pcall(svc.view);
    if not ok then return nil, 'waiting'; end
    if type(v) ~= 'table' then return nil, why or 'waiting'; end
    return v;
end

local function clock(sec)
    sec = tonumber(sec);
    if sec == nil then return nil; end
    sec = math.max(0, math.ceil(sec));
    if sec >= 60 then return string.format('%d:%02d', math.floor(sec / 60), sec % 60); end
    return string.format('%ds', sec);
end

-- One line: a coloured lead, then dim words beside it.
local function line(ui, col, lead, dim)
    ui.text(col, lead);
    if dim ~= nil and dim ~= '' then
        ui.sameLine();
        ui.dim(dim);
    end
end

-- What a section has to show. `full` (the Panel) shows the empty states too;
-- the window shows a section only when it has something in it.
local function sections(S, v, full)
    local out = {};
    if v.learnt and enabled(S, 'rememberedSteps') and (full or v.memory ~= nil) then
        out[#out + 1] = 'memory';
    end
    if v.learnt and enabled(S, 'rhythm') and (full or v.stacks > 0 or v.target ~= nil) then
        out[#out + 1] = 'rhythm';
    end
    if enabled(S, 'targetEffects') and (full or v.target ~= nil) then
        out[#out + 1] = 'target';
    end
    return out;
end

local DRAW = {};

function DRAW.memory(ui, v)
    local m = v.memory;
    line(ui, ui.COL.head, 'Perpetual Step', m and clock(m.remaining) or nil);
    if m == nil or #m.steps == 0 then
        ui.dim('  Nothing remembered');
        return;
    end
    for _, st in ipairs(m.steps) do
        local note = nil;
        if st.applies < st.level then note = string.format('puts on %d', st.applies); end
        line(ui, ui.COL.ok, string.format('  %s %d', st.name, st.level), note);
    end
    if v.trance then ui.dim('  Trance: puts on all of it'); end
end

function DRAW.rhythm(ui, v)
    local r = v.rhythm;
    line(ui, ui.COL.head, string.format('Unbroken Rhythm %d/%d', r.stacks, r.max),
         r.stacks > 0 and clock(r.remaining) or nil);
    if r.cost ~= nil then
        local what = r.refresh and 'Refresh' or 'Next stack';
        ui.text(r.short and ui.COL.warn or ui.COL.dim, string.format('  %s %d TP', what, r.cost));
    end
end

function DRAW.target(ui, v)
    local t = v.target;
    if t == nil then
        ui.dim('Not fighting');
        return;
    end
    ui.text(ui.COL.head, t.name or 'Your target');
    if #t.steps == 0 then
        ui.dim('  No Steps');
        return;
    end
    for _, st in ipairs(t.steps) do
        line(ui, ui.COL.ok, string.format('  %s %d', st.name, st.level), clock(st.remaining));
    end
end

local function drawSections(ui, v, list)
    for i, name in ipairs(list) do
        if i > 1 then ui.space(); end
        DRAW[name](ui, v);
    end
end

local WHY = {
    job         = 'Shows while your main job is Dancer.',
    waiting     = 'Waiting for the server.',
    unsupported = 'This server does not send Dancer status.',
    none        = 'This server does not send Dancer status.',
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
    label = 'DNC Status',
    jobs = { 'DNC' },
    servers = { 'ascensionxi' },

    config = {
        file = 'jobhelper-dnc-status.lua',
        keys = {
            rememberedSteps = 'boolean',
            rhythm          = 'boolean',
            targetEffects   = 'boolean',
            window          = 'boolean',
            locked          = 'boolean',
            x               = 'number',
            y               = 'number',
        },
        defaults = {
            rememberedSteps = true,
            rhythm          = true,
            targetEffects   = true,
            window          = true,
            locked          = false,
        },
    },

    panel = function(ctx)
        local ui, S = ctx.ui, ctx.S;
        if ui == nil or S == nil then return; end
        local cfg = S.cfg;
        local function toggle(key, label, tip)
            local nextValue = ui.toggle('dncstatus_' .. key, label, enabled(S, key), tip);
            if nextValue ~= nil and cfg ~= nil then cfg.set(key, nextValue); end
        end

        ui.section('Show', 'What the DNC Status lines show, here and in the window.', function()
            toggle('rememberedSteps', 'Perpetual Step',
                'The Steps Perpetual Step remembers, and how many levels of each it puts on now.');
            toggle('rhythm', 'Unbroken Rhythm',
                'Your stacks, when the next one drops, and the TP the next one costs.');
            toggle('targetEffects', 'Steps on your target',
                'The Steps on the monster you are fighting, and how long each lasts.');
        end);
        ui.section('Window', 'A small window you can drag anywhere. It shows itself only while it has something to show.', function()
            toggle('window', 'Show the window', 'Off: the lines appear only here.');
            toggle('locked', 'Lock it in place', 'Stops the window moving when dragged.');
        end);

        local svc = service(S);
        if svc ~= nil and anySection(S) and type(svc.want) == 'function' then pcall(svc.want); end
        local v, why = view(svc);
        if v == nil then
            ui.dim(WHY[why] or WHY.waiting);
            return;
        end
        local list = sections(S, v, true);
        if #list == 0 then
            ui.dim(v.learnt and 'Nothing switched on.' or 'Perpetual Step and Unbroken Rhythm come at Dancer 30.');
            return;
        end
        drawSections(ui, v, list);
    end,

    status = function(ctx)
        local ui, S = ctx.ui, ctx.S;
        if ui == nil then return; end
        local v = view(service(S));
        if v ~= nil and v.learnt then
            ui.dim(string.format('%d/%d stacks', v.stacks, v.rhythm.max));
        end
    end,

    window = function(ctx)
        local ui, S, imgui = ctx.ui, ctx.S, ctx.imgui;
        if ui == nil or S == nil or imgui == nil then return; end
        if not enabled(S, 'window') or not anySection(S) then return; end
        local svc = service(S);
        if svc == nil then return; end
        if type(svc.want) == 'function' then pcall(svc.want); end
        local now = os.clock();
        savePosition(S, now);
        local hidden = false;
        pcall(function() hidden = require('dlac\\feature\\gamehud').hidden(); end);
        if hidden then return; end
        local v = view(svc);
        if v == nil then return; end
        local list = sections(S, v, false);
        if #list == 0 then return; end

        local x, y = S.cfg and S.cfg.get('x') or nil, S.cfg and S.cfg.get('y') or nil;
        if type(x) == 'number' and type(y) == 'number' then
            imgui.SetNextWindowPos({ x, y }, flag('ImGuiCond_Once'));
        else
            imgui.SetNextWindowPos({ 60, 360 }, flag('ImGuiCond_FirstUseEver'));
        end
        local fl = flag('ImGuiWindowFlags_NoTitleBar') + flag('ImGuiWindowFlags_NoResize')
            + flag('ImGuiWindowFlags_NoScrollbar') + flag('ImGuiWindowFlags_NoScrollWithMouse')
            + flag('ImGuiWindowFlags_AlwaysAutoResize') + flag('ImGuiWindowFlags_NoFocusOnAppearing')
            + flag('ImGuiWindowFlags_NoNav') + flag('ImGuiWindowFlags_NoSavedSettings')
            + flag('ImGuiWindowFlags_NoCollapse');
        if enabled(S, 'locked') then fl = fl + flag('ImGuiWindowFlags_NoMove'); end
        if imgui.Begin('##dlac_dnc_status', { true }, fl) then
            local ok, err = pcall(drawSections, ui, v, list);
            if not ok then ui.err('DNC Status: ' .. tostring(err)); end
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
    _sections = sections,
    _clock    = clock,
};
