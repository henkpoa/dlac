--[[
    ascensionxi/telemetry/monitor -- the AutoAcc readout: what the combat
    telemetry says about the mob you fight, how far each hand is from the hit
    cap, and why each AutoAcc piece went or stayed on the last decision.

    One body, two places: the Gear Helpers row's panel (automationsui's helper
    registry) and a floating window (/dl autoacc), which gearui's d3d_present
    draws through the serverpack service 'autoaccMonitor' -- core never
    requires a servers\ path. Everything it shows is already computed: the
    client's state, the model's report and the frame's own numbers, read only
    while a surface is open.
]]--

local base = 'dlac\\servers\\ascensionxi\\modules\\telemetry\\';
local wire = require(base .. 'wire');
local formula = require(base .. 'formula');

local M = { visible = false };

M._client = nil;    -- the telemetry client (init.lua)
M._autoacc = nil;   -- the AutoAcc model (init.lua)

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');

local FALLBACK = { HEADER = { 0.60, 0.75, 1.00, 1.00 }, DIM = { 0.70, 0.70, 0.70, 1.00 },
                   USABLE = { 1.00, 1.00, 1.00, 1.00 }, HAVE = { 0.45, 0.90, 0.45, 1.00 },
                   WANT = { 1.00, 0.55, 0.30, 1.00 }, ERR = { 1.00, 0.45, 0.40, 1.00 },
                   SCORE = { 0.95, 0.85, 0.45, 1.00 } };

local function palette()
    local host = try('dlac\\ui\\uihost');
    local col = host ~= nil and host.services ~= nil and host.services.COL or nil;
    return (type(col) == 'table') and col or FALLBACK;
end

local function esc(s) return (tostring(s or ''):gsub('%%', '%%%%')); end

local CONTEXT_NAMES = { [0] = 'Main hand', [1] = 'Off hand', [2] = 'Kick', [3] = 'Ranged' };
local NOT_APPLICABLE = { [1] = 'no weapon', [2] = 'not available', [3] = 'out of range',
                         [4] = 'no valid target', [5] = 'not supported' };
local LANE_STATES = { [0] = 'idle', [1] = 'live', [2] = 'target not found', [3] = 'target gone',
                      [4] = 'out of range', [5] = 'suspended', [6] = 'not permitted', [7] = 'unsupported' };
local SLOT_ORDER = { 'Head', 'Neck', 'Ear1', 'Ear2', 'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet',
                     'Main', 'Sub', 'Range', 'Ammo' };

local function nativeOn()
    local eng = try('dlac\\feature\\equipengine');
    if eng == nil or type(eng.nativeOn) ~= 'function' then return false; end
    local ok, on = pcall(eng.nativeOn);
    return ok and on == true;
end

local function clientState()
    local c = M._client;
    if c == nil or type(c.state) ~= 'function' then return {}; end
    local ok, s = pcall(c.state);
    return (ok and type(s) == 'table') and s or {};
end

local function report()
    local a = M._autoacc;
    if a == nil or type(a.report) ~= 'function' then return {}; end
    local ok, r = pcall(a.report);
    return (ok and type(r) == 'table') and r or {};
end

-- One line for the Gear Helpers row: level 1 while the model can decide.
-- (The row draws its text as a format string: status() escapes.)
local function status()
    if not nativeOn() then return 0, 'off -- needs the Native engine'; end
    local cs = clientState();
    if cs.phase == 'dormant' then return 0, 'off -- ' .. tostring(cs.why or 'telemetry unavailable'); end
    if cs.phase ~= 'live' then
        return 0, (cs.why == 'waiting for an AutoAcc piece') and 'no AutoAcc piece worn' or 'starting';
    end
    local r = report();
    if r.trigger ~= nil then return 0, 'holding -- ' .. tostring(r.trigger); end
    if r.usable ~= true then return 0, 'live -- ' .. tostring(r.why or 'no frame yet'); end
    local released = 0;
    local d = r.decision;
    for _ in pairs(type(d) == 'table' and d.release or {}) do released = released + 1; end
    return 1, ('live -- %d piece%s released'):format(released, released == 1 and '' or 's');
end

function M.status()
    local level, text = status();
    return level, esc(text);
end
M.maxLevel = 1;

local function line(col, label, text, tip)
    imgui.TextColored(col.DIM, label);
    imgui.SameLine(110);
    imgui.TextColored(col.USABLE, esc(text));
    if tip ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(esc(tip)); end
end

local function drawContexts(col, frame)
    imgui.TextColored(col.DIM, 'Context');
    imgui.SameLine(110); imgui.TextColored(col.DIM, 'Hit rate');
    imgui.SameLine(190); imgui.TextColored(col.DIM, 'Cap');
    imgui.SameLine(250); imgui.TextColored(col.DIM, 'To the cap');
    for _, ctx in ipairs(frame.contexts or {}) do
        local name = CONTEXT_NAMES[ctx.kind] or ('context ' .. tostring(ctx.kind));
        imgui.TextColored(col.USABLE, name);
        if ctx.applicability ~= wire.applicability.APPLICABLE then
            imgui.SameLine(110);
            imgui.TextColored(col.DIM, NOT_APPLICABLE[ctx.applicability] or 'not applicable');
        else
            local _, eff = formula.compose(frame, ctx);
            local toCap = formula.accToCap(ctx, eff);
            imgui.SameLine(110); imgui.TextColored(col.USABLE, ('%.0f%%%%'):format((ctx.thresholdBp or 0) / 100));
            imgui.SameLine(190); imgui.TextColored(col.DIM, ('%.0f%%%%'):format((ctx.capBp or 0) / 100));
            imgui.SameLine(250);
            if toCap <= 0 then
                imgui.TextColored(col.HAVE, ('%d ACC spare'):format(-toCap));
            else
                imgui.TextColored(col.WANT, ('needs %d ACC'):format(toCap));
            end
            if ctx.kind == wire.context.RANGED and imgui.IsItemHovered() then
                imgui.SetTooltip('Shown for reference: AutoAcc v1 decides on melee only.');
            end
        end
    end
end

local function drawDecision(col, d)
    imgui.TextColored(col.HEADER, 'Last decision');
    if type(d) ~= 'table' or next(d.why or {}) == nil then
        imgui.TextColored(col.DIM, 'None yet: dlac asks when a set with an AutoAcc piece is worn.');
        return;
    end
    local seen = {};
    local function row(slot, why)
        imgui.TextColored(col.USABLE, esc(slot));
        imgui.SameLine(110);
        local released = (d.release or {})[slot] ~= nil;
        imgui.TextColored(released and col.HAVE or col.DIM, esc(why));
    end
    for _, slot in ipairs(SLOT_ORDER) do
        if d.why[slot] ~= nil then row(slot, d.why[slot]); seen[slot] = true; end
    end
    for slot, why in pairs(d.why) do
        if not seen[slot] then row(tostring(slot), why); end
    end
end

-- The readout itself (the panel and the floating window both draw this).
function M.drawBody()
    if imgui == nil then return; end
    local col = palette();
    if not nativeOn() then
        imgui.TextColored(col.WANT, 'The Native engine is off: AutoAcc pieces are always worn.');
        imgui.TextColored(col.DIM, 'Turn it on with /dl engine native on.');
        imgui.Separator();
    end

    local cs = clientState();
    local phase = tostring(cs.phase or 'off');
    local phaseText = phase;
    if phase == 'settling' then phaseText = tostring(cs.why or 'starting');
    elseif phase == 'dormant' then phaseText = 'off -- ' .. tostring(cs.why or '?');
    elseif phase == 'live' then phaseText = 'live, battle lane ' .. tostring(LANE_STATES[cs.laneState] or cs.laneState);
    elseif phase == 'hello' then phaseText = 'starting a session';
    end
    local stats = type(cs.stats) == 'table' and cs.stats or {};
    line(col, 'Telemetry', phaseText, ('%d frames received, %d accepted'):format(stats.pushes or 0, stats.accepted or 0));

    local r = report();
    local frame = r.frame;
    if type(frame) ~= 'table' then
        imgui.TextColored(col.DIM, 'No frame yet.');
        imgui.Separator();
        drawDecision(col, r.decision);
        return;
    end
    local age = nil;
    local a = M._autoacc;
    if a ~= nil and type(a._clock) == 'function' and r.frameAt ~= nil then
        local ok, now = pcall(a._clock);
        if ok and type(now) == 'number' then age = now - r.frameAt; end
    end
    line(col, 'Target', ('level %d, frame %s'):format(frame.targetLevel or 0,
        age ~= nil and ('%.1f s ago'):format(age) or ('rev ' .. tostring(frame.rev))));
    if r.usable == true then
        line(col, 'Checks', ('formula and gear agree (%d frame%s for this state)'):format(r.bases or 0, (r.bases == 1) and '' or 's'));
    else
        imgui.TextColored(col.DIM, 'Checks');
        imgui.SameLine(110);
        imgui.TextColored(col.WANT, esc(r.why or 'not usable'));
    end
    if r.trigger ~= nil then
        imgui.TextColored(col.DIM, 'Holding');
        imgui.SameLine(110);
        imgui.TextColored(col.WANT, esc(r.trigger));
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Every AutoAcc piece stays on until the next frame from the server.');
        end
    end
    local unverified = 0;
    local names = {};
    for id in pairs(r.unverified or {}) do
        unverified = unverified + 1;
        local v = (a ~= nil and type(a._vectorOf) == 'function') and a._vectorOf(id) or nil;
        names[#names + 1] = (type(v) == 'table' and v.name) or ('item ' .. tostring(id));
    end
    if unverified > 0 then
        imgui.TextColored(col.DIM, 'Unverified');
        imgui.SameLine(110);
        imgui.TextColored(col.WANT, ('%d piece%s'):format(unverified, unverified == 1 and '' or 's'));
        if imgui.IsItemHovered() then
            table.sort(names);
            imgui.SetTooltip(esc('The server\'s numbers did not match dlac\'s for these, so they stay on:\n'
                .. table.concat(names, '\n')));
        end
    end
    imgui.Separator();
    drawContexts(col, frame);
    imgui.Separator();
    drawDecision(col, r.decision);
end

-- The Gear Helpers panel: the body, and a button for the floating window.
function M.panel()
    if imgui == nil then return; end
    local col = palette();
    imgui.TextColored(col.HEADER, 'AutoAcc');
    imgui.SameLine(0, 10);
    imgui.TextColored(col.DIM, 'gear rule -- an armour piece worn only while the hit cap needs it');
    if imgui.SmallButton(M.visible and 'Close the floating window##aamon' or 'Open as a floating window##aamon') then
        M.visible = not M.visible;
    end
    imgui.Separator();
    M.drawBody();
end

-- The floating window: gearui's d3d_present calls this while M.visible.
function M.render()
    if imgui == nil or not M.visible then return; end
    local open = { true };
    imgui.SetNextWindowSize({ 430, 340 }, ImGuiCond_FirstUseEver or 4);
    if imgui.Begin('dlac -- AutoAcc##dlac_autoacc', open, ImGuiWindowFlags_None or 0) then
        local ok, err = pcall(M.drawBody);
        if not ok then pcall(imgui.TextColored, FALLBACK.ERR, esc('render error: ' .. tostring(err))); end
    end
    imgui.End();
    if not open[1] then M.visible = false; end
end

function M.toggle()
    M.visible = not M.visible;
    return M.visible;
end

return M;
