--[[
    ascensionxi/telemetry/monitor -- the accuracy box: for the monster you
    fight, your ACC for each hand, its evasion, the level correction, the hit
    rate the server rolls against, the cap, the ACC at which the cap starts,
    and how much you have to spare or still need. Below it, AutoAcc: why each
    piece went or stayed on, and whether the server's numbers for the new
    outfit matched what dlac predicted.

    For any player: an open box is demand, so it starts the telemetry session
    on its own and keeps it while it is open. The numbers are the server's
    (each frame's own live totals), so the box never shows a guess.

    One body, two places: the Gear Helpers row's panel (automationsui's helper
    registry) and a floating window (/dl accuracy or /dl autoacc), which
    gearui's d3d_present draws through the serverpack service
    'autoaccMonitor' -- core never requires a servers\ path.
]]--

local base = 'dlac\\servers\\ascensionxi\\modules\\telemetry\\';
local wire = require(base .. 'wire');
local formula = require(base .. 'formula');

local M = { visible = false };

M._client = nil;      -- the telemetry client (init.lua)
M._autoacc = nil;     -- the AutoAcc model (init.lua)
M._want = nil;        -- () keeps the session while the box is drawn (init.lua: client.want)
M._targetName = nil;  -- (frame) -> the monster's name, or nil

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

-- A rate in basis points as text, '95%' (drawn through esc like every string).
local function pct(bp) return ('%d%%'):format(math.floor((bp or 0) / 100)); end

local CONTEXT_NAMES = { [0] = 'Main hand', [1] = 'Off hand', [2] = 'Kick', [3] = 'Ranged' };
local NOT_APPLICABLE = { [1] = 'no weapon', [2] = 'not available', [3] = 'out of range',
                         [4] = 'no valid target', [5] = 'not supported' };
local LANE_STATES = { [0] = 'idle', [1] = 'live', [2] = 'target not found', [3] = 'target gone',
                      [4] = 'out of range', [5] = 'suspended', [6] = 'not permitted', [7] = 'unsupported' };
local SLOT_ORDER = { 'Head', 'Neck', 'Ear1', 'Ear2', 'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet',
                     'Main', 'Sub', 'Range', 'Ammo' };

-- The table's columns: x offsets, headings and what each one means.
local COLUMNS = {
    { x = 0,   label = 'Hand' },
    { x = 92,  label = 'ACC',    tip = 'Your accuracy for this hand as the server computes it: skill, DEX,\ngear, food and merits. Ranged shows ranged accuracy.' },
    { x = 142, label = 'EVA',    tip = 'The monster\'s evasion against this hand.' },
    { x = 192, label = 'Level',  tip = 'The level correction: ACC taken away when the monster is\nabove your level. It never adds any.' },
    { x = 244, label = 'Hit',    tip = 'The hit rate the server rolls against, standing in front of the monster.' },
    { x = 292, label = 'Cap',    tip = 'The most the hit rate can be.' },
    { x = 340, label = 'Cap at', tip = 'The ACC at which this hand reaches the cap. More than that is wasted.' },
};
local TAIL_X = 410;

-- dlac's engine is the only one since the LuaAshitacast purge; it is off
-- only when the Tripwire disarmed it for the session.
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

local function itemName(id)
    local a = M._autoacc;
    local v = (a ~= nil and type(a._vectorOf) == 'function') and a._vectorOf(id) or nil;
    return (type(v) == 'table' and v.name) or ('item ' .. tostring(id));
end

-- One line for the Gear Helpers row: level 1 while the model can decide.
-- (The row draws its text as a format string: status() escapes.)
local function status()
    if not nativeOn() then return 0, 'off -- the engine is disarmed'; end
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

local function line(col, label, text, color, tip)
    imgui.TextColored(col.DIM, label);
    imgui.SameLine(110);
    imgui.TextColored(color or col.USABLE, esc(text));
    if tip ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(esc(tip)); end
end

local function drawTable(col, frame)
    for i, c in ipairs(COLUMNS) do
        if i > 1 then imgui.SameLine(c.x); end
        imgui.TextColored(col.DIM, c.label);
        if c.tip ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(esc(c.tip)); end
    end
    for _, ctx in ipairs(frame.contexts or {}) do
        imgui.TextColored(col.USABLE, CONTEXT_NAMES[ctx.kind] or ('context ' .. tostring(ctx.kind)));
        if ctx.applicability ~= wire.applicability.APPLICABLE then
            imgui.SameLine(COLUMNS[2].x);
            imgui.TextColored(col.DIM, NOT_APPLICABLE[ctx.applicability] or 'not applicable');
        else
            local eff = formula.effective(frame, ctx, ctx.liveAcc or 0);
            local toCap = formula.accToCap(ctx, eff);
            local atCap = (ctx.thresholdBp or 0) >= formula.capThresholdBp(ctx);
            local cells = {
                { ('%d'):format(ctx.liveAcc or 0), col.USABLE },
                { ('%d'):format(ctx.targetEva or 0), col.USABLE },
                { ('%+d'):format(ctx.levelCorrection or 0), (ctx.levelCorrection or 0) < 0 and col.WANT or col.DIM },
                { pct(ctx.thresholdBp), atCap and col.HAVE or col.WANT },
                { pct(ctx.capBp), col.DIM },
                { ('%d'):format((ctx.liveAcc or 0) + toCap), col.USABLE },
            };
            for i, cell in ipairs(cells) do
                imgui.SameLine(COLUMNS[i + 1].x);
                imgui.TextColored(cell[2], esc(cell[1]));
            end
            imgui.SameLine(TAIL_X);
            if toCap <= 0 then
                imgui.TextColored(col.HAVE, ('%d spare'):format(-toCap));
            else
                imgui.TextColored(col.WANT, ('needs %d'):format(toCap));
            end
            if ctx.kind == wire.context.RANGED and imgui.IsItemHovered() then
                imgui.SetTooltip('Shown for reference: AutoAcc decides on melee only.');
            end
        end
    end
end

local function releaseText(release)
    local parts = {};
    for slot, fallback in pairs(release or {}) do parts[#parts + 1] = tostring(slot) .. ' to ' .. tostring(fallback); end
    table.sort(parts);
    return table.concat(parts, ', ');
end

local function drawPrediction(col, pr)
    if type(pr) ~= 'table' then return; end
    local what = releaseText(pr.release);
    if pr.verdict == 'waiting' then
        line(col, 'Prediction', 'waiting for the server to measure ' .. what, col.DIM);
        return;
    end
    if pr.verdict == 'not checked' then
        line(col, 'Prediction', 'not checked: ' .. tostring(pr.why or '?'), col.DIM);
        return;
    end
    local good = pr.verdict == 'matched';
    line(col, 'Prediction', good and ('matched the server for ' .. what) or ('WRONG for ' .. what .. ': those pieces stay on'),
        good and col.HAVE or col.ERR,
        'dlac predicts each hand\'s ACC and hit rate in the outfit a release makes,\n'
        .. 'and compares them with the server\'s own numbers once it wears that outfit.');
    local kinds = {};
    for kind in pairs(pr.rows or {}) do kinds[#kinds + 1] = kind; end
    table.sort(kinds);
    for _, kind in ipairs(kinds) do
        local row = pr.rows[kind];
        if row.measuredAcc ~= nil then
            local same = row.acc == row.measuredAcc and row.threshold == row.measuredThreshold;
            imgui.Dummy({ 0, 0 });
            imgui.SameLine(110);
            imgui.TextColored(same and col.DIM or col.ERR, esc(('%s: ACC %d predicted, %d measured; hit %s, %s'):format(
                CONTEXT_NAMES[kind] or tostring(kind), row.acc or 0, row.measuredAcc, pct(row.threshold),
                pct(row.measuredThreshold))));
        end
    end
end

local function drawAutoAcc(col, r)
    imgui.TextColored(col.HEADER, 'AutoAcc');
    local d = r.decision;
    if type(d) ~= 'table' or next(d.why or {}) == nil then
        imgui.TextColored(col.DIM, 'No piece uses it. In the Sets tab, click ~ on an accuracy piece and choose Gear Rule: AutoAcc.');
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
    drawPrediction(col, r.prediction);
end

local function keptOnLine(col, r)
    local names, count = {}, 0;
    for id in pairs(r.unverified or {}) do count = count + 1; names[#names + 1] = itemName(id) .. ' (unverified)'; end
    for id in pairs(r.mispredicted or {}) do count = count + 1; names[#names + 1] = itemName(id) .. ' (predicted wrongly)'; end
    if count == 0 then return; end
    table.sort(names);
    line(col, 'Kept on', ('%d piece%s'):format(count, count == 1 and '' or 's'), col.WANT,
        'The server\'s numbers did not match dlac\'s for these, so AutoAcc leaves them on:\n' .. table.concat(names, '\n'));
end

-- The box itself (the panel and the floating window both draw this).
function M.drawBody()
    if imgui == nil then return; end
    -- An open box is demand: the session runs while someone looks.
    if type(M._want) == 'function' then pcall(M._want); end
    local col = palette();
    if not nativeOn() then
        imgui.TextColored(col.WANT, 'dlac\'s engine is disarmed this session: AutoAcc decides nothing.');
        imgui.TextColored(col.DIM, 'Another engine is loaded (LuaAshitacast?). Unload it and /addon reload dlac.');
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
    line(col, 'Telemetry', phaseText, nil, ('%d frames received, %d accepted'):format(stats.pushes or 0, stats.accepted or 0));

    local r = report();
    local frame = r.frame;
    if type(frame) ~= 'table' or frame.laneState ~= wire.laneState.LIVE then
        imgui.TextColored(col.DIM, 'Engage a monster: your numbers against it appear here.');
        imgui.Separator();
        drawAutoAcc(col, r);
        return;
    end

    local age = nil;
    local a = M._autoacc;
    if a ~= nil and type(a._clock) == 'function' and r.frameAt ~= nil then
        local ok, now = pcall(a._clock);
        if ok and type(now) == 'number' then age = now - r.frameAt; end
    end
    local name = nil;
    if type(M._targetName) == 'function' then
        local ok, n = pcall(M._targetName, frame);
        if ok and type(n) == 'string' and n ~= '' then name = n; end
    end
    line(col, 'Target', ('%slevel %d, updated %s'):format(name and (name .. ', ') or '', frame.targetLevel or 0,
        age ~= nil and ('%.1f s ago'):format(age) or ('at rev ' .. tostring(frame.rev))), nil,
        'The server sends a new frame only when something you cannot see changes,\nso "updated" can be a while ago.');
    if r.usable == true then
        line(col, 'Checks', ('dlac\'s math and gear agree with the server (%d frame%s)'):format(r.bases or 0,
            (r.bases == 1) and '' or 's'), col.HAVE);
    else
        line(col, 'Checks', r.why or 'not usable', col.WANT);
    end
    if r.trigger ~= nil then
        line(col, 'Holding', r.trigger, col.WANT, 'Every AutoAcc piece stays on until the next frame from the server.');
    end
    local effects = {};
    if (frame.flashPenalty or 0) > 0 then effects[#effects + 1] = ('Flash takes %d ACC'):format(frame.flashPenalty); end
    if (frame.foodAccPct or 0) > 0 then
        effects[#effects + 1] = ('food adds %d%% ACC, up to %d'):format(frame.foodAccPct, frame.foodAccCap or 0);
    end
    if #effects > 0 then line(col, 'Effects', table.concat(effects, '; ')); end
    keptOnLine(col, r);
    imgui.Separator();
    drawTable(col, frame);
    imgui.Separator();
    drawAutoAcc(col, r);
end

-- The Gear Helpers panel: the box, and a button for the floating window.
function M.panel()
    if imgui == nil then return; end
    local col = palette();
    imgui.TextColored(col.HEADER, 'Accuracy and AutoAcc');
    imgui.SameLine(0, 10);
    imgui.TextColored(col.DIM, 'your hit rate against the monster you fight; AutoAcc wears accuracy gear only while you need it');
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
    imgui.SetNextWindowSize({ 560, 380 }, ImGuiCond_FirstUseEver or 4);
    if imgui.Begin('dlac -- Accuracy##dlac_autoacc', open, ImGuiWindowFlags_None or 0) then
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
