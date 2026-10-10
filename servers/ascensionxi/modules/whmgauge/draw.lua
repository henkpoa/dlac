--[[
    ascensionxi/whmgauge/draw -- the flower gauge's art, drawn with the imgui
    draw list (no textures to ship). draw.panel(dl, x, y, scale, view) paints
    one gauge whose top-left corner is (x, y); draw.size(scale) is the box it
    fills, which init.lua reserves with a Dummy. draw.tooltip(view) is the
    hover text.

    The look borrows FFXIV's Lily Gauge, the owner's reference: three flower
    slots in a row, a charge bar under them, and one larger bloom beside them.
      Solace: white lilies with a gold heart. The next empty slot shows a bud
              that grows with the charge and lights when the flower is made.
              The bloom on the right is Divine Seal: lit when ready, a clock
              sweep while it recasts, bright and turning while it is up.
      Misery: violet nightshade with a crimson heart; the glyph on the right
              is Banish's element (a sun for light, a moon once converted).
    A flower's tier sets its size: Regen/Banish I a small glimmer (5 petals),
    II a medium flower (6 petals, two rings), III the biggest (8 petals, two
    rings and a bright halo).

    Geometry is pure (petalPoints, layout) so the suite can check it without
    imgui; painting goes through the dl handed in.
]]--

local M = {};

local PI = math.pi;

-- Base layout at scale 1. Slots are 40 px apart; the side element sits right.
M.W, M.H = 196, 70;
local PAD, SLOT_X0, SLOT_DX, SLOT_Y, BAR_Y, BAR_H = 8, 30, 40, 28, 54, 5;
local SIDE_X, SIDE_Y = 160, 30;

M.TIER = {
    [1] = { petals = 5, len = 9,  width = 7,   inner = false, glow = 12, glowA = 0.22, sparks = 1, name = 'Small' },
    [2] = { petals = 6, len = 12, width = 8,   inner = true,  glow = 16, glowA = 0.32, sparks = 2, name = 'Medium' },
    [3] = { petals = 8, len = 15, width = 8.5, inner = true,  glow = 21, glowA = 0.48, sparks = 3, name = 'Large' },
};

M.PALETTE = {
    [1] = { -- Solace
        outer = { 0.96, 0.97, 1.00 }, inner = { 0.66, 0.84, 1.00 }, heart = { 1.00, 0.84, 0.36 },
        glow = { 0.55, 0.82, 1.00 }, bar = { 0.52, 0.86, 1.00 }, edge = { 0.55, 0.78, 1.00 },
    },
    [2] = { -- Misery
        outer = { 0.50, 0.22, 0.72 }, inner = { 0.86, 0.18, 0.40 }, heart = { 1.00, 0.86, 0.56 },
        glow = { 0.66, 0.26, 0.92 }, bar = { 0.74, 0.32, 0.96 }, edge = { 0.70, 0.32, 0.92 },
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

-- One petal's outline: from its base near the centre out to a pointed tip
-- and back, `n` points a side. A teardrop that is widest two fifths out,
-- convex, so PathFillConvex can fill it in one call.
function M.petalPoints(cx, cy, angle, len, width, n)
    n = n or 6;
    local ca, sa = math.cos(angle), math.sin(angle);
    local base = len * 0.12;
    local right, left = {}, {};
    for k = 0, n do
        local s = k / n;
        local u = base + (len - base) * s;
        local v = (width / 2) * (math.max(0, math.sin(PI * s)) ^ 0.55) * (1 - 0.22 * s);
        right[#right + 1] = { cx + u * ca - v * sa, cy + u * sa + v * ca };
        left[#left + 1]   = { cx + u * ca + v * sa, cy + u * sa - v * ca };
    end
    local pts = {};
    for k = 1, #right do pts[#pts + 1] = right[k]; end
    for k = #left - 1, 2, -1 do pts[#pts + 1] = left[k]; end
    return pts;
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

-- A four-pointed sparkle.
local function sparkle(P, x, y, r, c)
    P.poly({ { x, y - r }, { x + r * 0.22, y }, { x, y + r }, { x - r * 0.22, y } }, c);
    P.poly({ { x - r, y }, { x, y - r * 0.22 }, { x + r, y }, { x, y + r * 0.22 } }, c);
end

-- One flower. `lit` false draws the unlit bud; `grow` (0-1) scales the petals
-- (the bud growing with the charge); `burst` (0-1) is the lighting flash.
function M.flower(P, x, y, s, tier, pal, opts)
    local spec = M.TIER[tier];
    if spec == nil then return; end
    opts = opts or {};
    local t = opts.t or 0;
    local lit = opts.lit ~= false;
    local grow = opts.grow or 1;
    local alpha = lit and 1 or 0.42;
    local outer = lit and pal.outer or mix(pal.outer, GREY, 0.55);
    local inner = lit and pal.inner or mix(pal.inner, GREY, 0.55);
    local heart = lit and (opts.heart or pal.heart) or mix(pal.heart, GREY, 0.6);

    if lit then
        local pulse = 0.85 + 0.15 * math.sin(t * 2.2 + x * 0.05);
        glow(P, x, y, spec.glow * s * pulse, pal.glow, spec.glowA);
    end
    local len, width = spec.len * s * grow, spec.width * s * (0.55 + 0.45 * grow);
    local spin = -PI / 2;
    for k = 0, spec.petals - 1 do
        local a = spin + k * 2 * PI / spec.petals;
        P.poly(M.petalPoints(x, y, a, len, width, 6), rgba(outer, alpha));
    end
    if spec.inner then
        for k = 0, spec.petals - 1 do
            local a = spin + (k + 0.5) * 2 * PI / spec.petals;
            P.poly(M.petalPoints(x, y, a, len * 0.62, width * 0.7, 5), rgba(inner, alpha));
        end
    end
    P.circle(x, y, math.max(1.5, (tier + 1.2) * s * grow), rgba(heart, alpha), 16);

    if lit then
        for k = 1, spec.sparks do
            local a = t * (0.6 + 0.15 * k) + k * 2 * PI / spec.sparks;
            local r = (spec.glow - 3) * s;
            local tw = 0.5 + 0.5 * math.sin(t * 3.1 + k * 1.7);
            sparkle(P, x + math.cos(a) * r, y + math.sin(a) * r, (1.6 + tier * 0.7) * s * (0.6 + 0.4 * tw),
                    rgba(WHITE, 0.55 + 0.45 * tw));
        end
    end
    if opts.burst ~= nil then   -- the moment it lights: an expanding ring
        local b = opts.burst;
        P.ring(x, y, (spec.glow + 10 * b) * s, rgba(pal.glow, 0.9 * (1 - b)), 2.5 * s, 36);
        glow(P, x, y, (spec.glow + 6 * b) * s, WHITE, 0.6 * (1 - b));
    end
end

-- An empty slot: a faint seed ring.
local function emptySlot(P, x, y, s, pal)
    P.ring(x, y, 9 * s, rgba(pal.edge, 0.28), 1.2 * s, 24);
    P.circle(x, y, 1.6 * s, rgba(pal.edge, 0.35), 10);
end

-- Divine Seal's bloom, beside the slots under Solace.
local function sealBloom(P, x, y, s, seal, t)
    local petals, len, width = 12, 21 * s, 8 * s;
    if seal.ready or seal.active then
        local speed = seal.active and 1.4 or 0.0;
        local pulse = seal.active and (0.85 + 0.15 * math.sin(t * 6)) or (0.9 + 0.1 * math.sin(t * 1.6));
        glow(P, x, y, 27 * s * pulse, GOLD, seal.active and 0.75 or 0.5);
        for k = 0, petals - 1 do
            local a = -PI / 2 + k * 2 * PI / petals + t * speed * 0.2;
            P.poly(M.petalPoints(x, y, a, len, width, 6), rgba(GOLD, 1));
        end
        for k = 0, 5 do
            local a = -PI / 2 + (k + 0.5) * 2 * PI / 6 - t * speed * 0.3;
            P.poly(M.petalPoints(x, y, a, len * 0.55, width * 1.1, 5), rgba(WHITE, 0.95));
        end
        P.circle(x, y, 4.5 * s, rgba({ 1.0, 0.95, 0.70 }, 1), 18);
        local n = seal.active and 4 or 2;
        for k = 1, n do
            local a = t * (seal.active and 1.8 or 0.7) + k * 2 * PI / n;
            sparkle(P, x + math.cos(a) * 24 * s, y + math.sin(a) * 24 * s, 3.2 * s, rgba(WHITE, 0.9));
        end
        return;
    end
    -- Recasting (or unknown): a grey bud and a gold clock sweep of the time spent.
    for k = 0, petals - 1 do
        local a = -PI / 2 + k * 2 * PI / petals;
        P.poly(M.petalPoints(x, y, a, len * 0.55, width * 0.8, 5), rgba(GREY, 0.55));
    end
    P.circle(x, y, 3.5 * s, rgba(GREY, 0.8), 14);
    local r = 25 * s;
    P.ring(x, y, r, rgba(GREY, 0.35), 2 * s, 40);
    local rem = tonumber(seal.remaining);
    if rem ~= nil and rem > 0 then
        local total = math.max(120, seal.total or rem);
        local done = math.max(0, math.min(1, 1 - rem / total));
        local steps = math.max(2, math.floor(40 * done));
        local a0 = -PI / 2;
        for k = 0, steps - 1 do
            local a1 = a0 + (k / steps) * done * 2 * PI;
            local a2 = a0 + ((k + 1) / steps) * done * 2 * PI;
            P.line(x + math.cos(a1) * r, y + math.sin(a1) * r, x + math.cos(a2) * r, y + math.sin(a2) * r,
                   rgba(GOLD, 0.9), 2.4 * s);
        end
    end
end

-- Banish's element under Misery: a sun for light, a moon once converted.
local function banishGlyph(P, x, y, s, dark, t)
    if dark then
        glow(P, x, y, 18 * s, { 0.45, 0.20, 0.80 }, 0.45);
        P.circle(x, y, 10 * s, rgba({ 0.78, 0.66, 1.00 }, 1), 28);
        P.circle(x + 5 * s, y - 3.5 * s, 9 * s, rgba(BG, 1), 28);   -- the shadow bite
        sparkle(P, x - 8 * s, y + 9 * s, 2.6 * s, rgba(WHITE, 0.7 + 0.3 * math.sin(t * 2.5)));
        return;
    end
    glow(P, x, y, 18 * s, GOLD, 0.45);
    for k = 0, 7 do
        local a = k * PI / 4 + t * 0.25;
        local r1, r2, w = 9 * s, 15 * s, 0.22;
        P.poly({ { x + math.cos(a - w) * r1, y + math.sin(a - w) * r1 },
                 { x + math.cos(a) * r2, y + math.sin(a) * r2 },
                 { x + math.cos(a + w) * r1, y + math.sin(a + w) * r1 } }, rgba(GOLD, 0.95));
    end
    P.circle(x, y, 8 * s, rgba({ 1.0, 0.92, 0.62 }, 1), 24);
end

-- Text size when no measure is handed in: about the game font's.
local function guessSize(text) return #tostring(text) * 7, 14; end

-- One whole gauge. `u32` turns {r,g,b,a} into the draw list's colour;
-- `measure(text) -> w, h` sizes text in the real font (imgui.CalcTextSize),
-- because the font does not scale with the gauge: labels are placed from
-- the panel's bottom edge up, so they can never hang outside it.
function M.panel(dl, u32, x0, y0, s, v, measure)
    measure = measure or guessSize
    local P = painter(dl, u32);
    local pal = M.PALETTE[v.stance] or M.PALETTE[1];
    local w, h = M.size(s);
    local t = v.now or 0;
    P.rect(x0, y0, x0 + w, y0 + h, BG, 9 * s);
    P.frame(x0, y0, x0 + w, y0 + h, rgba(pal.edge, 0.45), 9 * s, 1);

    local L = M.layout();
    local held, firstEmpty = 0, nil;
    for i = 1, 3 do
        if (v.flowers[i] or 0) > 0 then held = held + 1; elseif firstEmpty == nil then firstEmpty = i; end
    end
    for i = 1, 3 do
        local sx, sy = x0 + L.slots[i][1] * s, y0 + L.slots[i][2] * s;
        local tier = v.flowers[i] or 0;
        if tier > 0 then
            M.flower(P, sx, sy, s, tier, pal, { t = t, burst = v.burst[i] });
        elseif i == firstEmpty and v.tier > 0 and v.progress > 0 then
            M.flower(P, sx, sy, s, v.tier, pal, { t = t, lit = false, grow = 0.25 + 0.75 * v.progress });
        else
            emptySlot(P, sx, sy, s, pal);
        end
    end

    -- The charge bar: stance colour while it makes a flower, gold while it
    -- upgrades one, grey when it waits (three flowers, nothing to upgrade).
    local b = L.bar;
    local bx1, by1, bx2, by2 = x0 + b[1] * s, y0 + b[2] * s, x0 + b[3] * s, y0 + b[4] * s;
    P.rect(bx1, by1, bx2, by2, TRACK, 3 * s);
    local fillCol = pal.bar;
    if v.capped then fillCol = GREY; elseif held >= 3 then fillCol = GOLD; end
    local p = v.capped and 1 or v.progress;
    if p > 0 then P.rect(bx1, by1, bx1 + (bx2 - bx1) * p, by2, rgba(fillCol, 0.95), 3 * s); end
    if not v.synced then
        local msg = v.live and 'syncing' or 'no server data';
        local _, th = measure(msg);
        P.text(bx1, math.min(by2 + 2 * s, y0 + h - th - 2 * s), rgba(GREY, 0.9), msg);
    end

    local sx, sy = x0 + L.side[1] * s, y0 + L.side[2] * s;
    if v.stance == 1 and v.seal ~= nil then
        sealBloom(P, sx, sy, s, v.seal, t);
    elseif v.stance == 2 then
        banishGlyph(P, sx, sy, s, v.dark, t);
    end
    if v.boosting and (v.boost or 0) > 0 then
        local label = ({ 'x1.5', 'x2', 'x2.5' })[v.boost] or '';
        local tw, th = measure(label);
        P.text(sx - tw / 2, y0 + h - th - 3 * s, rgba(pal.glow, 1), label);
    end
end

-- ---------------------------------------------------------------------------
-- Hover text
-- ---------------------------------------------------------------------------

local TIER_NAME = { 'small', 'medium', 'large' };

local function clock(sec)
    sec = math.max(0, math.floor(sec + 0.5));
    return string.format('%d:%02d', math.floor(sec / 60), sec % 60);
end

function M.tooltip(v, extra)
    local lines = {};
    local solace = v.stance == 1;
    lines[#lines + 1] = solace and 'Afflatus Solace: Regen flowers' or 'Afflatus Misery: Judgement flowers';
    if not v.synced then
        lines[#lines + 1] = extra or 'Waiting for the server.';
        return table.concat(lines, '\n');
    end
    local unit = solace and 'HP healed by your Regens' or 'TP from your hits on Judged monsters';
    if v.capped then
        lines[#lines + 1] = 'Three flowers held. Use Bloom or Harvest to keep charging.';
    else
        lines[#lines + 1] = string.format('Charge: %d / %d %s', v.charge, v.threshold, unit);
    end
    local held = {};
    for i = 1, 3 do if (v.flowers[i] or 0) > 0 then held[#held + 1] = TIER_NAME[v.flowers[i]]; end end
    lines[#lines + 1] = 'Flowers: ' .. (#held > 0 and table.concat(held, ', ') or 'none');
    if v.tier > 0 then
        lines[#lines + 1] = string.format('Next flower: %s (%s %s)', TIER_NAME[v.tier],
            solace and 'Regen' or 'Banish', ({ 'I', 'II', 'III' })[v.tier]);
    end
    if v.boosting and (v.boost or 0) > 0 then
        lines[#lines + 1] = string.format('Next %s: +%d%% from a %s flower', solace and 'Regen' or 'Banish',
            v.boost * 50, TIER_NAME[v.boost]);
    end
    if solace and v.seal ~= nil then
        local s = v.seal;
        local txt = s.active and 'active' or (s.ready and 'ready')
            or (tonumber(s.remaining) ~= nil and clock(s.remaining)) or 'unknown';
        lines[#lines + 1] = 'Divine Seal: ' .. txt;
    end
    if not solace then
        lines[#lines + 1] = v.dark and 'Banish: dark (bursts on dark skillchains)'
            or 'Banish: light (bursts on light skillchains)';
    end
    return table.concat(lines, '\n');
end

return M;
