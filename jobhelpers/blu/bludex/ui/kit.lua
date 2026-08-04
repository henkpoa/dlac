--[[
    bludex/ui/kit.lua -- small ImGui widget kit carrying dlac's field-proven UI
    laws, blue-shifted for Bludex:

      * IMGUI TEXT IS A printf FORMAT STRING. A '%' in drawn text is a
        CONVERSION ("51% HP" -> "51F4A60263P" in the field) -- everything this
        kit draws is escaped, and M.esc is exported for direct imgui calls.
      * PRESENCE PROVES NOTHING. Every widget call is guarded; on a binding
        that lacks it the kit degrades to text or nothing, never to an error.
      * NO BeginTabBar -- it is not field-proven in this install. Tabs are a
        lit/unlit Button row (the craftbar shape).
      * Explanations live in hover tooltips, never inline paragraphs.
      * Every Push pops on every path.

    Pure at load; nothing here reads AshitaCore. Every function takes the
    imgui binding `im` first so the host (or a test stub) owns the instance.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- palette -- dlac's semantic scale, shifted blue for Bludex
-- ---------------------------------------------------------------------------
M.COL = {
    head   = { 0.42, 0.68, 1.00, 1.00 },  -- section headers, spell names
    accent = { 0.55, 0.80, 1.00, 1.00 },  -- values worth the eye
    dim    = { 0.62, 0.66, 0.72, 1.00 },  -- explanations, provenance, off
    ok     = { 0.55, 0.90, 0.55, 1.00 },  -- learned, fits, applied
    warn   = { 1.00, 0.72, 0.30, 1.00 },  -- over budget, needs attention
    err    = { 1.00, 0.45, 0.40, 1.00 },  -- missing, cannot
    lit    = { 0.16, 0.34, 0.62, 1.00 },  -- selected tab / choice button
    litHov = { 0.20, 0.42, 0.74, 1.00 },
    unlit  = { 0.10, 0.13, 0.20, 1.00 },  -- unselected tab / choice button
    badge  = { 0.75, 0.55, 1.00, 1.00 },  -- unbridled / special
};

-- element accents (used for text and fallback icon tints)
M.ELEMENT = {
    Fire    = { 0.95, 0.45, 0.35, 1.00 },
    Ice     = { 0.55, 0.85, 1.00, 1.00 },
    Wind    = { 0.55, 0.95, 0.65, 1.00 },
    Earth   = { 0.85, 0.70, 0.40, 1.00 },
    Thunder = { 0.85, 0.60, 1.00, 1.00 },
    Water   = { 0.45, 0.65, 1.00, 1.00 },
    Light   = { 0.95, 0.95, 0.80, 1.00 },
    Dark    = { 0.70, 0.55, 0.85, 1.00 },
    None    = { 0.75, 0.75, 0.75, 1.00 },
};

local function isFn(im, name)
    return type(im) == 'table' and type(im[name]) == 'function';
end
M.isFn = isFn;

-- printf-trap escape: nothing leaves this kit unescaped.
local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end
M.esc = esc;

-- Attach a tooltip to the item just drawn. Multi-line is fine.
function M.tip(im, tip)
    if tip == nil or tip == '' then return; end
    if not isFn(im, 'IsItemHovered') or not isFn(im, 'SetTooltip') then return; end
    if im.IsItemHovered() then im.SetTooltip(esc(tip)); end
end

function M.text(im, s)
    if isFn(im, 'Text') then im.Text(esc(s)); end
end

function M.ctext(im, col, s)
    if isFn(im, 'TextColored') then im.TextColored(col, esc(s));
    elseif isFn(im, 'Text') then im.Text(esc(s)); end
end

-- "Label: value" on one line -- label dim, value bright.
function M.kv(im, label, value, valueCol)
    M.ctext(im, M.COL.dim, label);
    if isFn(im, 'SameLine') then im.SameLine(); end
    M.ctext(im, valueCol or M.COL.accent, tostring(value));
end

-- Colored, word-wrapped text: TextWrapped wraps at the window edge where
-- ctext/TextColored just clip. Falls back to ctext without TextWrapped.
function M.wrapped(im, col, s)
    if isFn(im, 'TextWrapped') then
        local pushed = false;
        if col and isFn(im, 'PushStyleColor') and isFn(im, 'PopStyleColor') then
            im.PushStyleColor(0, col);                 -- Text
            pushed = true;
        end
        im.TextWrapped(esc(s));
        if pushed then im.PopStyleColor(1); end
    else
        M.ctext(im, col, s);
    end
end

-- kv whose value wraps -- for lists that can outgrow the window width.
function M.kvw(im, label, value, valueCol)
    M.ctext(im, M.COL.dim, label);
    if isFn(im, 'SameLine') then im.SameLine(); end
    M.wrapped(im, valueCol or M.COL.accent, tostring(value));
end

function M.header(im, s)
    M.ctext(im, M.COL.head, s);
    if isFn(im, 'Separator') then im.Separator(); end
end

-- button palettes for litButton's pal override
M.PAL = {
    go  = {   -- green: an action that WANTS clicking (pending changes)
        base = { 0.14, 0.46, 0.24, 1.00 },
        hov  = { 0.18, 0.58, 0.30, 1.00 },
        act  = { 0.22, 0.68, 0.36, 1.00 },
    },
    off = {   -- inert: nothing to do; barely-there, no hover response
        base = { 0.08, 0.10, 0.15, 1.00 },
        hov  = { 0.09, 0.12, 0.17, 1.00 },
        act  = { 0.09, 0.12, 0.17, 1.00 },
    },
};

-- lit/unlit button (the craftbar choice shape). Returns true on click.
-- Pops on every path. `pal` overrides the colors ({base, hov, act}).
function M.litButton(im, label, lit, w, h, pal)
    if not isFn(im, 'Button') then return false; end
    local pushed = false;
    if isFn(im, 'PushStyleColor') and isFn(im, 'PopStyleColor') then
        im.PushStyleColor(21, pal and pal.base or (lit and M.COL.lit or M.COL.unlit));
        im.PushStyleColor(22, pal and pal.hov or (lit and M.COL.litHov or M.COL.lit));
        im.PushStyleColor(23, pal and pal.act or M.COL.litHov);
        pushed = true;
    end
    local ok, clicked = pcall(im.Button, esc(label), w and { w, h or 24 } or nil);
    if pushed then im.PopStyleColor(3); end
    return ok and clicked or false;
end

-- A one-line colored progress bar drawn as text (ProgressBar is not
-- field-proven here): "Points  34 / 79" with the value colored by fit.
function M.meter(im, label, used, max, unit)
    local col = M.COL.ok;
    if max and max > 0 then
        if used > max then col = M.COL.err;
        elseif used >= max * 0.9 then col = M.COL.warn; end
    end
    M.ctext(im, M.COL.dim, label);
    if isFn(im, 'SameLine') then im.SameLine(); end
    local maxs = (max and max > 0) and tostring(max) or '?';
    M.ctext(im, col, string.format('%d / %s%s', used, maxs, unit or ''));
end

-- Content-region width, tolerant of binding return shapes ((x,y) numbers or
-- a table); fallback when unreadable or absurd.
function M.availWidth(im, fallback)
    if isFn(im, 'GetContentRegionAvail') then
        local ok, w = pcall(function()
            local v = { im.GetContentRegionAvail() };
            local first = v[1];
            if type(first) == 'table' then return first[1] or first.x; end
            return first;
        end);
        if ok and type(w) == 'number' and w > 100 then return w; end
    end
    return fallback;
end

-- Measured button width for a set of labels (never hardcode; a hardcoded
-- width has clipped a trailing character in the field more than once).
function M.measure(im, labels, minW)
    local w = minW or 60;
    if isFn(im, 'CalcTextSize') then
        for _, s in ipairs(labels) do
            local ok, tw = pcall(im.CalcTextSize, esc(s));
            if ok and type(tw) == 'number' and tw + 16 > w then w = tw + 16; end
        end
    end
    return w;
end

-- Simple guarded combo over a list of string choices. `state` is a table with
-- .value; returns true if changed. Includes an 'All' entry when allLabel set.
function M.combo(im, id, state, choices, allLabel, width)
    if not (isFn(im, 'BeginCombo') and isFn(im, 'EndCombo') and isFn(im, 'Selectable')) then
        return false;
    end
    if width and isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(width); end
    local shown = state.value or allLabel or '';
    local changed = false;
    if im.BeginCombo(id, esc(shown)) then
        if allLabel then
            if im.Selectable(esc(allLabel), state.value == nil) then
                state.value = nil; changed = true;
            end
        end
        for _, c in ipairs(choices) do
            if im.Selectable(esc(c), state.value == c) then
                state.value = c; changed = true;
            end
        end
        im.EndCombo();
    end
    return changed;
end

return M;
