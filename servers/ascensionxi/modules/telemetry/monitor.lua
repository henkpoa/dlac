--[[
    ascensionxi/telemetry/monitor -- the accuracy box: the monster you fight,
    your ACC for each hand against it, and the piece AutoAcc wears in each of
    its slots. One short line per thing: every explanation lives in the hover
    of an underlined label (dlac's panel-text standard, ui\uistyle.helpLabel),
    and a warning is drawn only while something is wrong (owner, 2026-10-05:
    "as minimalistic as we can").

    It speaks a player's language: no session or frame counts, lane states,
    revisions or the model's internal reasons ("You don't need to give out
    super detailed server statistics"). The precise reason for a slot stays
    in /dl why.

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
local uistyle = try('dlac\\ui\\uistyle');

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
local PIECE_X = COLUMNS[2].x;   -- an AutoAcc row's piece lines up with the ACC column

local AUTOACC_TIP = 'AutoAcc wears your AutoAcc pieces only while you need the accuracy:\n'
    .. 'once every hand reaches the cap without one, its slot wears its normal pick.';
local WAITING = 'AutoAcc is waiting for the server\'s numbers';
local KEPT_ON = 'AutoAcc keeps your accuracy pieces on';

-- The model's reason for a slot (autoacc.decide), in a player's words. Any
-- reason not listed (the checks, the lane, an outfit the frames do not
-- cover) is the box waiting for the server.
local PLAIN = {
    ['needed for the cap'] = 'you need it to reach the cap',
    ['the full set does not reach the cap'] = 'you don\'t reach the cap even with it',
    ['only the standing Default set releases'] = 'AutoAcc only swaps pieces in your standing set',
    ['weapon slots stay'] = 'weapons always stay on',
    ['no fallback'] = 'the slot has nothing else to wear',
    ['its enchantment would be lost'] = 'taking it off would end its enchantment',
    ['it lowers max HP while an HP latent is worn'] = 'swapping it would lower your max HP while a piece that counts your HP is worn',
    ['unverified'] = 'the server\'s numbers didn\'t match DLAC\'s for it',
    ['a release of it was predicted wrongly'] = 'the server\'s numbers didn\'t match DLAC\'s for it',
    ['inside an Onslaught run'] = 'you\'re in an Onslaught run',
    ['it covers another slot'] = 'it takes up two slots',
    ['augmented'] = 'DLAC can\'t work out an augmented copy exactly',
    ['an equip script dlac does not model'] = 'it has a special equip effect',
    ['not in the catalog'] = 'DLAC doesn\'t know this piece',
};
local function plainWhy(why)
    why = tostring(why or '');
    if PLAIN[why] ~= nil then return PLAIN[why]; end
    local trigger = why:match('^held until the next frame: (.+)$');
    if trigger ~= nil then return 'for a moment (' .. trigger .. ')'; end
    if why:find('^an accuracy latent') ~= nil then return 'its accuracy depends on a condition'; end
    return WAITING;
end

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
    if cs.phase == 'dormant' then return 0, 'off -- the server is not sending numbers'; end
    if cs.phase ~= 'live' then
        return 0, (cs.why == 'waiting for an AutoAcc piece') and 'no AutoAcc piece worn' or 'starting';
    end
    local r = report();
    if r.trigger ~= nil then return 0, 'holding -- ' .. tostring(r.trigger); end
    if r.usable ~= true then return 0, 'waiting for the server\'s numbers'; end
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

-- A label: underlined when it has a hover, which carries its explanation.
-- helpLabel draws raw, so the escaping happens here.
local function label(color, text, tip)
    if tip ~= nil and uistyle ~= nil and type(uistyle.helpLabel) == 'function' then
        uistyle.helpLabel(imgui, esc(text), esc(tip), color);
        return;
    end
    imgui.TextColored(color, esc(text));
    if tip ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(esc(tip)); end
end

-- A value with a hover, not underlined: the rows' data.
local function cell(color, text, tip)
    imgui.TextColored(color, esc(text));
    if tip ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(esc(tip)); end
end

-- A short label after the line's own, for as long as it applies.
local function flag(color, text, tip)
    imgui.SameLine(0, 12);
    label(color, text, tip);
end

local function frameAge(r)
    local a = M._autoacc;
    if a == nil or type(a._clock) ~= 'function' or r.frameAt == nil then return nil; end
    local ok, now = pcall(a._clock);
    return (ok and type(now) == 'number') and (now - r.frameAt) or nil;
end

local function targetName(frame)
    if type(M._targetName) ~= 'function' then return nil; end
    local ok, n = pcall(M._targetName, frame);
    return (ok and type(n) == 'string' and n ~= '') and n or nil;
end

-- The top line: the monster, or why there is none.
local function drawTarget(col, r, phase, frame)
    if phase == 'dormant' then
        label(col.WANT, 'Unavailable', 'The server isn\'t sending accuracy numbers right now,\nso ' .. KEPT_ON .. '.');
        return;
    end
    if phase ~= 'live' then label(col.DIM, 'Starting', 'Connecting to the server.'); return; end
    if frame == nil then label(col.DIM, 'No target', 'Engage a monster to see your numbers against it.'); return; end
    local failed = r.formulaOk == false or r.mismatch ~= nil;
    local age = frameAge(r);
    local tip = { (age ~= nil) and ('Updated %.1f s ago. '):format(age) or '' };
    tip[1] = tip[1] .. 'The server only sends new numbers when something changes.';
    if failed or r.usable ~= true then tip[#tip + 1] = WAITING .. ', so it keeps your accuracy pieces on.'; end
    label(col.USABLE, ('%s, Lv %d'):format(targetName(frame) or 'Target', frame.targetLevel or 0), table.concat(tip, '\n'));
    if (frame.flashPenalty or 0) > 0 then
        flag(col.WANT, ('Flash -%d'):format(frame.flashPenalty), 'Flash takes this much ACC until it wears off.');
    end
    if failed then
        flag(col.ERR, 'Check failed', 'DLAC\'s numbers don\'t match the server\'s right now,\nso ' .. KEPT_ON .. ' until they do.');
    end
end

-- The applicable hands, one row each; the others are named in the Hand hover.
local function drawTable(col, frame)
    local rows, hidden = {}, {};
    for _, ctx in ipairs(frame.contexts or {}) do
        if ctx.applicability == wire.applicability.APPLICABLE then rows[#rows + 1] = ctx;
        else
            hidden[#hidden + 1] = ('%s: %s'):format(CONTEXT_NAMES[ctx.kind] or ('context ' .. tostring(ctx.kind)),
                NOT_APPLICABLE[ctx.applicability] or 'not applicable');
        end
    end
    for i, c in ipairs(COLUMNS) do
        if i > 1 then imgui.SameLine(c.x); end
        local tip = c.tip;
        if i == 1 and #hidden > 0 then tip = 'Not shown:\n' .. table.concat(hidden, '\n'); end
        if i == 2 and (frame.foodAccPct or 0) > 0 then
            tip = tip .. ('\nYour food adds %d%% ACC, up to %d, and is counted in.'):format(frame.foodAccPct, frame.foodAccCap or 0);
        end
        label(col.DIM, c.label, tip);
    end
    for _, ctx in ipairs(rows) do
        imgui.TextColored(col.USABLE, esc(CONTEXT_NAMES[ctx.kind] or ('context ' .. tostring(ctx.kind))));
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
        for i, c in ipairs(cells) do
            imgui.SameLine(COLUMNS[i + 1].x);
            imgui.TextColored(c[2], esc(c[1]));
        end
        imgui.SameLine(TAIL_X);
        local tip = (ctx.kind == wire.context.RANGED) and 'Shown for reference: AutoAcc decides on melee only.' or nil;
        if toCap <= 0 then
            cell(col.HAVE, ('%d spare'):format(-toCap), tip);
        else
            cell(col.WANT, ('needs %d'):format(toCap), tip);
        end
    end
end

-- The prediction check on the last swap, for the AutoAcc hover. A swap that
-- was not checked says nothing.
local function predictionText(pr)
    if type(pr) ~= 'table' then return nil; end
    if pr.verdict == 'waiting' then return 'Your last swap: waiting for the server to confirm DLAC\'s numbers.'; end
    if pr.verdict == 'matched' then return 'Your last swap: the server confirmed DLAC\'s numbers.'; end
    if pr.verdict == 'mismatch' then
        return 'Your last swap: the server\'s numbers didn\'t match DLAC\'s, so those pieces stay on.';
    end
    return nil;
end

-- Pieces the server's numbers contradicted: AutoAcc leaves them on.
local function keptOn(r)
    local names = {};
    for id in pairs(r.unverified or {}) do names[#names + 1] = itemName(id); end
    for id in pairs(r.mispredicted or {}) do names[#names + 1] = itemName(id); end
    table.sort(names);
    return names;
end

-- A slot's hover: the piece it wears and why, in a player's words.
local function rowTip(piece, fallback, why)
    local name = (piece ~= nil) and tostring(piece) or 'The accuracy piece';
    if fallback ~= nil then
        return ('%s is on: you reach the cap without %s.'):format(tostring(fallback), (piece ~= nil) and tostring(piece) or 'it');
    end
    if why == 'the slot is not the piece' then return 'Something else is in this slot.'; end
    if why == 'needed for the cap' then return ('%s is on: %s.'):format(name, PLAIN[why]); end
    return ('%s stays on: %s.'):format(name, plainWhy(why));
end

-- The AutoAcc header, then each slot and the piece it wears now: green when
-- the slot went back to its normal pick, white while the accuracy piece is
-- needed, dim when it stays on for another reason (the hover says which).
local function drawAutoAcc(col, r)
    local tip = { AUTOACC_TIP };
    if r.trigger ~= nil then tip[#tip + 1] = 'Every piece stays on for a moment (' .. tostring(r.trigger) .. ').'; end
    tip[#tip + 1] = predictionText(r.prediction);
    label(col.HEADER, 'AutoAcc', table.concat(tip, '\n\n'));
    local kept = keptOn(r);
    if #kept > 0 then
        flag(col.WANT, ('%d kept on'):format(#kept),
            'The server\'s numbers didn\'t match DLAC\'s for these, so AutoAcc leaves them on:\n' .. table.concat(kept, '\n'));
    end
    local d = r.decision;
    if type(d) ~= 'table' or next(d.why or {}) == nil then
        flag(col.DIM, 'no piece', 'In the Sets tab, click ~ on an accuracy piece and choose Gear Rule: AutoAcc.');
        return;
    end
    local typed, release = d.typed or {}, d.release or {};
    local function row(slot, why)
        imgui.TextColored(col.USABLE, esc(slot));
        imgui.SameLine(PIECE_X);
        local piece, fallback = typed[slot], release[slot];
        if fallback ~= nil then
            cell(col.HAVE, fallback, rowTip(piece, fallback, why));
        else
            cell((why == 'needed for the cap') and col.USABLE or col.DIM, piece or '?', rowTip(piece, nil, why));
        end
    end
    local seen = {};
    for _, slot in ipairs(SLOT_ORDER) do
        if d.why[slot] ~= nil then row(slot, d.why[slot]); seen[slot] = true; end
    end
    for slot, why in pairs(d.why) do
        if not seen[slot] then row(tostring(slot), why); end
    end
end

-- The box itself (the panel and the floating window both draw this).
function M.drawBody()
    if imgui == nil then return; end
    -- An open box is demand: the session runs while someone looks.
    if type(M._want) == 'function' then pcall(M._want); end
    local col = palette();
    if not nativeOn() then
        label(col.WANT, 'Engine disarmed',
            'Another gear addon (LuaAshitacast?) is loaded, so AutoAcc does nothing.\nUnload it and /addon reload dlac.');
    end
    local cs, r = clientState(), report();
    local frame = r.frame;
    local live = cs.phase == 'live' and type(frame) == 'table' and frame.laneState == wire.laneState.LIVE;
    drawTarget(col, r, cs.phase, live and frame or nil);
    if live then
        imgui.Separator();
        drawTable(col, frame);
    end
    imgui.Separator();
    drawAutoAcc(col, r);
end

-- The Gear Helpers panel: the box, and a button for the floating window.
function M.panel()
    if imgui == nil then return; end
    local col = palette();
    label(col.HEADER, 'Accuracy and AutoAcc',
        'Your hit rate against the monster you fight.\nAutoAcc wears accuracy gear only while you need it.');
    imgui.SameLine(0, 10);
    if imgui.SmallButton(M.visible and 'Close window##aamon' or 'Open window##aamon') then
        M.visible = not M.visible;
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('This box in its own window. /dl accuracy opens and closes it too.'); end
    imgui.Separator();
    M.drawBody();
end

-- The floating window: gearui's d3d_present calls this while M.visible.
-- AlwaysAutoResize makes it exactly as big as what it shows, so nothing sets
-- its size (no SetNextWindowSize beside it: the collapse law in ui\hobbybar).
function M.render()
    if imgui == nil or not M.visible then return; end
    local open = { true };
    if imgui.Begin('dlac -- Accuracy##dlac_autoacc', open, ImGuiWindowFlags_AlwaysAutoResize or 0) then
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
