--[[
    ascensionxi/pldgauge/draw -- the Paladin gauge's art, drawn with the imgui
    draw list (no textures to ship). draw.panel(dl, u32, x, y, scale, view,
    measure) paints one gauge whose top-left corner is (x, y); draw.size(scale)
    is the box it fills, which init.lua reserves with a Dummy.
    draw.tooltip(view) is the hover text.

    The White Mage gauge's frame (three slots in a row, a charge bar under
    them, one larger element beside them) with the owner's icons:
      Divine Guard: each point is a heater shield, steel blue with a gold
              cross. The big shield on the right carries the Palisade stack
              count, with a ring that fills toward the cap.
      Divine Fury: each point is a pair of crossed great swords, steel
              blades on a crimson glow; the big element is the same pair.
    The next empty slot shows a dim icon that grows with the charge and
    bursts into light when the point is made. With three points and a full
    bar (CAPPED) the points and the bar pulse.

    Geometry is pure (shieldPoints, bladePoints, layout) so the suite can
    check it without imgui; painting goes through the dl handed in.
]]--

local M = {};

local PI = math.pi;

-- Base layout at scale 1, the White Mage gauge's: slots 40 px apart, the
-- side element on the right.
M.W, M.H = 196, 70;
local PAD, SLOT_X0, SLOT_DX, SLOT_Y, BAR_Y, BAR_H = 8, 30, 40, 28, 54, 5;
local SIDE_X, SIDE_Y = 160, 30;
M.SLOT_R = 11;    -- a point icon's half height
M.SIDE_R = 19;    -- the big shield's half height
M.RING_R = 25;    -- the Palisade ring around it
M.GLOW_R = 16;    -- a lit point's glow

M.PALETTE = {
    [1] = { -- Divine Guard
        body = { 0.34, 0.50, 0.78 }, inner = { 0.62, 0.74, 0.94 }, emblem = { 1.00, 0.82, 0.30 },
        glow = { 0.45, 0.70, 1.00 }, bar = { 0.52, 0.78, 1.00 }, edge = { 0.55, 0.72, 1.00 },
    },
    [2] = { -- Divine Fury
        body = { 0.86, 0.89, 0.95 }, inner = { 0.62, 0.66, 0.74 }, emblem = { 1.00, 0.82, 0.30 },
        glow = { 1.00, 0.38, 0.22 }, bar = { 1.00, 0.46, 0.26 }, edge = { 0.95, 0.42, 0.32 },
    },
};
local GOLD, WHITE, GREY = { 1.00, 0.82, 0.30 }, { 1, 1, 1 }, { 0.46, 0.48, 0.54 };
local BG, TRACK = { 0.05, 0.06, 0.10, 0.74 }, { 0.16, 0.18, 0.24, 0.95 };

function M.size(scale)
    scale = scale or 1;
    return math.floor(M.W * scale + 0.5), math.floor(M.H * scale + 0.5);
end

-- Slot i's centre, the bar's rectangle and the side element's centre, all
-- relative to the panel's top-left, at scale 1.
function M.layout()
    local slots = {};
    for i = 1, 3 do slots[i] = { PAD + SLOT_X0 - 10 + (i - 1) * SLOT_DX, PAD + SLOT_Y - 8 }; end
    return {
        slots = slots,
        bar = { PAD + 4, PAD + BAR_Y - 8, PAD + 4 + 2 * SLOT_DX + 32, PAD + BAR_Y - 8 + BAR_H },
        side = { PAD + SIDE_X - 10, PAD + SIDE_Y - 8 },
    };
end

-- A heater shield's outline around (cx, cy), `r` its half height: a flat
-- top, straight upper sides, a curve down to the point. Convex, so
-- PathFillConvex fills it in one call.
function M.shieldPoints(cx, cy, r)
    local shape = {
        { -0.80, -0.92 }, { 0.80, -0.92 }, { 0.84, -0.30 }, { 0.76, 0.18 }, { 0.58, 0.56 },
        { 0.30, 0.86 }, { 0.00, 1.00 }, { -0.30, 0.86 }, { -0.58, 0.56 }, { -0.76, 0.18 }, { -0.84, -0.30 },
    };
    local pts = {};
    for i, p in ipairs(shape) do pts[i] = { cx + p[1] * r, cy + p[2] * r }; end
    return pts;
end

-- Local axes of a sword lying along `angle` (u toward the tip, v across).
local function axis(cx, cy, angle)
    local ca, sa = math.cos(angle), math.sin(angle);
    return function(u, v) return { cx + u * ca - v * sa, cy + u * sa + v * ca }; end
end

-- A great sword's blade, centred on (cx, cy) along `angle` (the tip side),
-- `len` the whole sword: from the crossguard to a point. Convex.
function M.bladePoints(cx, cy, angle, len, width)
    local at = axis(cx, cy, angle);
    local u0, tip, w = -len * 0.16, len * 0.5, width / 2;
    return { at(u0, -w), at(tip - width, -w), at(tip, 0), at(tip - width, w), at(u0, w) };
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

local function rgba(c, a) return { c[1], c[2], c[3], a or c[4] or 1 }; end

local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t };
end

-- The painter: imgui's draw list behind a tiny surface, so the art code reads
-- as shapes and the binding quirks stay here. PathFillConvex is used when the
-- binding has it; otherwise each convex polygon becomes a triangle fan.
local function painter(dl, u32)
    local P = {};
    local usePath = nil;
    function P.poly(pts, c)
        local col = u32(c);
        if usePath ~= false then
            local ok = pcall(function()
                dl:PathClear();
                for i = 1, #pts do dl:PathLineTo(pts[i]); end
                dl:PathFillConvex(col);
            end);
            if ok then usePath = true; return; end
            usePath = false;
            pcall(function() dl:PathClear(); end);
        end
        local cx, cy = 0, 0;
        for i = 1, #pts do cx, cy = cx + pts[i][1], cy + pts[i][2]; end
        local mid = { cx / #pts, cy / #pts };
        for i = 1, #pts do
            local a, b = pts[i], pts[(i % #pts) + 1];
            pcall(function() dl:AddTriangleFilled(mid, a, b, col); end);
        end
    end
    function P.outline(pts, c, th)
        for i = 1, #pts do
            local a, b = pts[i], pts[(i % #pts) + 1];
            pcall(function() dl:AddLine(a, b, u32(c), th or 1); end);
        end
    end
    function P.circle(x, y, r, c, seg)
        pcall(function() dl:AddCircleFilled({ x, y }, r, u32(c), seg or 24); end);
    end
    function P.ring(x, y, r, c, th, seg)
        pcall(function() dl:AddCircle({ x, y }, r, u32(c), seg or 32, th or 1); end);
    end
    function P.line(x1, y1, x2, y2, c, th)
        pcall(function() dl:AddLine({ x1, y1 }, { x2, y2 }, u32(c), th or 1); end);
    end
    function P.rect(x1, y1, x2, y2, c, rounding)
        pcall(function() dl:AddRectFilled({ x1, y1 }, { x2, y2 }, u32(c), rounding or 0); end);
    end
    function P.frame(x1, y1, x2, y2, c, rounding, th)
        pcall(function() dl:AddRect({ x1, y1 }, { x2, y2 }, u32(c), rounding or 0, 0, th or 1); end);
    end
    function P.text(x, y, c, s)
        pcall(function() dl:AddText({ x, y }, u32(c), s); end);
    end
    return P;
end

-- Soft glow: concentric discs, faint at the rim.
local function glow(P, x, y, r, c, a)
    for k = 4, 1, -1 do
        P.circle(x, y, r * (0.45 + 0.14 * k), rgba(c, a * (0.22 + 0.10 * (4 - k)) / 1.6), 28);
    end
end

-- A heater shield with a gold cross, `r` its half height.
function M.shield(P, x, y, r, pal, alpha, lit)
    local body = lit and pal.body or mix(pal.body, GREY, 0.55);
    local inner = lit and pal.inner or mix(pal.inner, GREY, 0.55);
    local emblem = lit and pal.emblem or mix(pal.emblem, GREY, 0.6);
    P.poly(M.shieldPoints(x, y, r), rgba(body, alpha));
    P.poly(M.shieldPoints(x, y - r * 0.04, r * 0.74), rgba(inner, alpha * 0.55));
    -- The cross: two bars, each a convex quad.
    local cw, top, bottom = r * 0.14, y - r * 0.66, y + r * 0.62;
    P.poly({ { x - cw, top }, { x + cw, top }, { x + cw, bottom }, { x - cw, bottom } }, rgba(emblem, alpha));
    local arm = y - r * 0.22;
    P.poly({ { x - r * 0.52, arm - cw }, { x + r * 0.52, arm - cw }, { x + r * 0.52, arm + cw },
             { x - r * 0.52, arm + cw } }, rgba(emblem, alpha));
    P.outline(M.shieldPoints(x, y, r), rgba(lit and WHITE or GREY, alpha * 0.55), math.max(1, r * 0.08));
end

-- One great sword along `angle`: blade, crossguard, grip and pommel.
local function sword(P, x, y, angle, len, pal, alpha, lit)
    local at = axis(x, y, angle);
    local width = len * 0.13;
    local steel = lit and pal.body or mix(pal.body, GREY, 0.55);
    local gold = lit and pal.emblem or mix(pal.emblem, GREY, 0.6);
    P.poly(M.bladePoints(x, y, angle, len, width), rgba(steel, alpha));
    -- The fuller: a thin line down the blade.
    local a1, a2 = at(-len * 0.12, 0), at(len * 0.36, 0);
    P.line(a1[1], a1[2], a2[1], a2[2], rgba(lit and pal.inner or GREY, alpha * 0.9), math.max(1, width * 0.22));
    local g, t = len * 0.17, len * 0.04;
    P.poly({ at(-len * 0.16 - t, -g), at(-len * 0.16 + t, -g), at(-len * 0.16 + t, g), at(-len * 0.16 - t, g) },
        rgba(gold, alpha));
    local gw = width * 0.26;
    P.poly({ at(-len * 0.40, -gw), at(-len * 0.16, -gw), at(-len * 0.16, gw), at(-len * 0.40, gw) },
        rgba(mix(gold, { 0.35, 0.20, 0.10 }, 0.55), alpha));
    local pm = at(-len * 0.44, 0);
    P.circle(pm[1], pm[2], math.max(1.2, width * 0.42), rgba(gold, alpha), 12);
end

-- Two great swords crossing, tips up, `r` the emblem's half height.
function M.swords(P, x, y, r, pal, alpha, lit)
    local len = r * 2.3;
    sword(P, x, y, -PI / 4, len, pal, alpha, lit);
    sword(P, x, y, -3 * PI / 4, len, pal, alpha, lit);
end

local function icon(P, stance, x, y, r, pal, alpha, lit)
    if stance == 2 then M.swords(P, x, y, r, pal, alpha, lit); else M.shield(P, x, y, r, pal, alpha, lit); end
end

-- One point slot. `lit` false draws the dim next point; `grow` (0-1) scales
-- it with the charge; `burst` (0-1) is the lighting flash; `pulse` is set
-- while capped.
function M.point(P, stance, x, y, s, pal, opts)
    opts = opts or {};
    local t = opts.t or 0;
    local lit = opts.lit ~= false;
    local grow = opts.grow or 1;
    if lit then
        local beat = opts.pulse and (0.75 + 0.25 * math.sin(t * 5)) or (0.88 + 0.12 * math.sin(t * 2 + x * 0.05));
        glow(P, x, y, M.GLOW_R * s * beat, pal.glow, opts.pulse and 0.55 or 0.36);
    end
    icon(P, stance, x, y, M.SLOT_R * s * grow, pal, lit and 1 or 0.42, lit);
    if opts.burst ~= nil then   -- the moment it lights: an expanding ring
        local b = opts.burst;
        P.ring(x, y, (M.GLOW_R + 10 * b) * s, rgba(pal.glow, 0.9 * (1 - b)), 2.5 * s, 36);
        glow(P, x, y, (M.GLOW_R + 6 * b) * s, WHITE, 0.6 * (1 - b));
    end
end

-- An empty slot: the icon's faint outline.
local function emptySlot(P, stance, x, y, s, pal)
    if stance == 2 then
        M.swords(P, x, y, M.SLOT_R * s, pal, 0.18, false);
    else
        P.outline(M.shieldPoints(x, y, M.SLOT_R * s), rgba(pal.edge, 0.32), 1.2 * s);
    end
end

-- Divine Guard's big shield: Palisade's stacks as a number, and a ring that
-- fills toward the cap.
local function palisadeShield(P, x, y, s, v, pal, measure)
    local stacks, cap = v.palisade or 0, math.max(1, v.palisadeMax or 30);
    local frac = math.max(0, math.min(1, stacks / cap));
    local up = stacks > 0;
    if up then glow(P, x, y, (M.SIDE_R + 4) * s, pal.glow, 0.25 + 0.45 * frac); end
    M.shield(P, x, y, M.SIDE_R * s, pal, up and 1 or 0.55, up);
    local r = M.RING_R * s;
    P.ring(x, y, r, rgba(GREY, 0.35), 2 * s, 40);
    if frac > 0 then
        local steps = math.max(2, math.floor(40 * frac));
        local a0 = -PI / 2;
        local col = stacks >= cap and GOLD or pal.glow;
        for k = 0, steps - 1 do
            local a1 = a0 + (k / steps) * frac * 2 * PI;
            local a2 = a0 + ((k + 1) / steps) * frac * 2 * PI;
            P.line(x + math.cos(a1) * r, y + math.sin(a1) * r, x + math.cos(a2) * r, y + math.sin(a2) * r,
                   rgba(col, 0.95), 2.4 * s);
        end
    end
    -- The count, on a dark plate so it reads over the cross.
    local label = tostring(stacks);
    local tw, th = measure(label);
    local ty = y - th / 2 + 1 * s;
    P.rect(x - tw / 2 - 3 * s, ty - 1 * s, x + tw / 2 + 3 * s, ty + th + 1 * s, rgba(BG, up and 0.8 or 0.6), 3 * s);
    P.text(x - tw / 2, ty, rgba(up and WHITE or GREY, 1), label);
end

-- Text size when no measure is handed in: about the game font's.
local function guessSize(text) return #tostring(text) * 7, 14; end

-- One whole gauge. `u32` turns {r,g,b,a} into the draw list's colour;
-- `measure(text) -> w, h` sizes text in the real font (imgui.CalcTextSize),
-- because the font does not scale with the gauge.
function M.panel(dl, u32, x0, y0, s, v, measure)
    measure = measure or guessSize;
    local P = painter(dl, u32);
    local stance = v.stance == 2 and 2 or 1;
    local pal = M.PALETTE[stance];
    local w, h = M.size(s);
    local t = v.now or 0;
    P.rect(x0, y0, x0 + w, y0 + h, BG, 9 * s);
    P.frame(x0, y0, x0 + w, y0 + h, rgba(pal.edge, 0.45), 9 * s, 1);

    local L = M.layout();
    local points = math.max(0, math.min(3, v.points or 0));
    for i = 1, 3 do
        local sx, sy = x0 + L.slots[i][1] * s, y0 + L.slots[i][2] * s;
        if i <= points then
            M.point(P, stance, sx, sy, s, pal, { t = t, burst = v.burst and v.burst[i], pulse = v.capped });
        elseif i == points + 1 and (v.progress or 0) > 0 then
            M.point(P, stance, sx, sy, s, pal, { t = t, lit = false, grow = 0.35 + 0.65 * v.progress });
        else
            emptySlot(P, stance, sx, sy, s, pal);
        end
    end

    -- The charge bar: the stance colour toward a point, gold while it fills
    -- the reserve behind three points, pulsing gold once that is full.
    local b = L.bar;
    local bx1, by1, bx2, by2 = x0 + b[1] * s, y0 + b[2] * s, x0 + b[3] * s, y0 + b[4] * s;
    P.rect(bx1, by1, bx2, by2, TRACK, 3 * s);
    local fillCol, alpha = pal.bar, 0.95;
    if v.capped then fillCol, alpha = GOLD, 0.7 + 0.3 * math.sin(t * 5);
    elseif points >= 3 then fillCol = GOLD; end
    local p = v.capped and 1 or (v.progress or 0);
    if p > 0 then P.rect(bx1, by1, bx1 + (bx2 - bx1) * p, by2, rgba(fillCol, alpha), 3 * s); end

    local sx, sy = x0 + L.side[1] * s, y0 + L.side[2] * s;
    if stance == 1 then
        palisadeShield(P, sx, sy, s, v, pal, measure);
    else
        glow(P, sx, sy, (M.SIDE_R + 4) * s, pal.glow, 0.35);
        M.swords(P, sx, sy, M.SIDE_R * s, pal, 0.9, true);
    end
end

-- ---------------------------------------------------------------------------
-- Hover text
-- ---------------------------------------------------------------------------

function M.tooltip(v)
    local lines = {};
    local guard = v.stance ~= 2;
    lines[#lines + 1] = guard and 'Divine Guard: shield points' or 'Divine Fury: your points carry over';
    lines[#lines + 1] = string.format('Points: %d / 3', v.points or 0);
    if v.capped then
        lines[#lines + 1] = 'Three points and a full bar. Spend a point to keep charging.';
    elseif (v.threshold or 0) > 0 then
        lines[#lines + 1] = string.format('Next point: %d%%', math.floor((v.progress or 0) * 100 + 0.5));
    end
    if guard then
        lines[#lines + 1] = 'Shield blocks fill the bar; a Shield Bash that interrupts a spell or TP move gives a point.';
        lines[#lines + 1] = string.format('Palisade: +%d%% block rate (up to +%d%%)', v.palisade or 0, v.palisadeMax or 30);
    else
        lines[#lines + 1] = 'Points are earned in Divine Guard.';
    end
    return table.concat(lines, '\n');
end

return M;
