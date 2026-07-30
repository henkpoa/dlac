--[[
    dlac/ui/panelkit.lua -- the Job helper PANEL KIT: dlac's field-proven ImGui
    patterns, as widgets, so a module author declares a Panel instead of building
    one.

    WHY THIS EXISTS. The BST Helper's Panel was 350 lines with 47 hand-written
    `type(imgui.X) == 'function'` guards, three separate copies of the same
    lit/unlit button group, a hand-rolled SliderFloat-with-InputInt fallback, a
    hand-rolled CalcTextSize width measurement, and the same "armed / not acting /
    off, plus a Last line" status block written out three times. None of that was
    careless -- every piece of it is a real lesson:

      * PRESENCE PROVES NOTHING (hard rule 2). `BeginPopupContextItem` is bound in
        this Ashita install and does not work. So a widget is used only where dlac
        already drives it in the field, and every call is guarded.
      * `RadioButton` is called nowhere in dlac, so a small exclusive choice is a
        lit/unlit `Button` pair -- the craftbar shape.
      * A HARDCODED WIDTH HAS CLIPPED a trailing character in the field more than
        once ("Last Synth"), so the widest label is MEASURED.
      * The right-hand Panel child is whatever is left of a window whose minimum
        is 480, so mutually exclusive choices STACK vertically -- side by side,
        three of them wanted ~520px and clipped (2026-07-29, screenshot round 2).
      * IMGUI TEXT IS A printf FORMAT STRING, so a '%' in it is a CONVERSION: the
        Reward rule's "below 51% pet HP" reached the field as "below 51F4A60263et
        HP" (2026-07-29, screenshot round 3) -- '% p' read as %p, a heap address
        printed, the 'p' eaten. The kit ESCAPES every string it draws, so an
        author stating a threshold in words cannot hit it.
      * The PANEL-TEXT STANDARD: never hang an explanatory paragraph off a label
        (it clips at the panel edge); the label is underlined and the explanation
        lives in its hover (uistyle.helpLabel; Henrik's ruling 2026-07-24, and
        again in round 2: "do some word wrapping, I can't make the window wider").

    Those lessons are worth exactly as much as they are hard to re-learn, and
    every one of them was previously transmitted by an author reading the guide
    carefully and remembering. Now they are the default behavior of a function.

    THE HANDLE IS ALWAYS THE CALLER'S. Every function takes `im` first, and
    `bind(im)` returns the same kit with it pre-applied -- the uistyle.helpLabel
    contract, and it is not cosmetic: the Panel renders under whatever binding (or
    test stub) the HOST holds, and a shared module requiring its own `imgui` gets
    the wrong instance in the smoke suite.

    EVERY FUNCTION IS SAFE ON A BINDING THAT LACKS ITS WIDGET. It degrades to
    text, or to nothing, and never to an error -- so a Panel built on this kit
    renders headlessly (the smoke suite draws every tab against a stub) and a
    module cannot lose its Panel to a missing widget.

    STACK DISCIPLINE. Every Push here pops on every path, including the failure
    paths; every BeginCombo that returned true ends. The frame-level recovery in
    uihost is the host's guard against a torn frame -- this kit is what keeps it
    from being needed.

    Pure at load; nothing here reads AshitaCore.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- the house palette for a Panel
-- ---------------------------------------------------------------------------
--
-- Deliberately NOT the gear-helper coverage ramp (architecture.md forbids a rival
-- to that one ramp): this is the on / dormant / off / bad scale, the same one
-- ui\jobhelpersui uses for its rows.
M.COL = {
    head = { 0.60, 0.75, 1.00, 1.00 },   -- section headers, titles
    dim  = { 0.70, 0.70, 0.70, 1.00 },   -- explanation, "last beat", off states
    ok   = { 0.55, 0.90, 0.55, 1.00 },   -- armed and acting
    warn = { 1.00, 0.72, 0.30, 1.00 },   -- blocked, and the player can fix it
    err  = { 1.00, 0.45, 0.40, 1.00 },   -- broken
    lit  = { 0.18, 0.55, 0.18, 1.00 },   -- the selected button in a choice group
};

-- The default button size for a stacked choice, and the floor a measured width
-- may not go under.
M.CHOICE_H   = 24;
M.CHOICE_MIN = 120;

local function isFn(im, name)
    return type(im) == 'table' and type(im[name]) == 'function';
end

-- EVERY IMGUI TEXT CALL IS A printf FORMAT STRING (Text, TextColored,
-- TextDisabled, SetTooltip). A '%' in the text is therefore a CONVERSION, not a
-- percent sign: `below 51% pet HP` came out as `below 51F4A60263et HP` in the
-- field (2026-07-29) -- ImGui read '% p' as the pointer conversion %p, printed a
-- heap address and swallowed the 'p'. So nothing leaves this kit unescaped.
-- (gear\gearfmt.lua carries the same helper for the gear UI; this is panelkit's
-- copy so a Panel author never has to know the trap exists.)
local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end
M.esc = esc;

-- Attach `tip` to the item just drawn. Multi-line ('\n') is fine.
local function tipOn(im, tip)
    if tip == nil or tip == '' then return; end
    if not isFn(im, 'IsItemHovered') or not isFn(im, 'SetTooltip') then return; end
    if im.IsItemHovered() then im.SetTooltip(esc(tip)); end
end
M.tip = tipOn;

-- ---------------------------------------------------------------------------
-- text + layout
-- ---------------------------------------------------------------------------

function M.text(im, col, s)
    if not isFn(im, 'TextColored') then return; end
    im.TextColored(col or M.COL.dim, esc(s));
end

function M.dim(im, s)  M.text(im, M.COL.dim,  s); end
function M.ok(im, s)   M.text(im, M.COL.ok,   s); end
function M.warn(im, s) M.text(im, M.COL.warn, s); end
function M.err(im, s)  M.text(im, M.COL.err,  s); end

function M.space(im) if isFn(im, 'Spacing')   then im.Spacing();   end end
function M.rule(im)  if isFn(im, 'Separator') then im.Separator(); end end

-- Put the next item on the same line as the last. Guarded, because a binding
-- without SameLine must lay out badly rather than error.
function M.sameLine(im, gap)
    if isFn(im, 'SameLine') then im.SameLine(0, tonumber(gap) or 8); end
end

-- Greyed-out text (a control that is present but unavailable -- the "Reward now
-- (down 41s)" shape). Falls back to dim text on a binding without TextDisabled.
function M.disabled(im, s)
    if isFn(im, 'TextDisabled') then im.TextDisabled(esc(s)); return; end
    M.dim(im, s);
end

-- A SECTION HEADER, to the panel-text standard: the label underlined, the
-- explanation in its hover. Never an inline paragraph -- it clips at the panel
-- edge, and the window's minimum width is 480.
function M.header(im, label, tip)
    local drew = false;
    pcall(function()
        local us = require('dlac\\ui\\uistyle');
        if type(us) ~= 'table' or type(us.helpLabel) ~= 'function' then return; end
        -- helpLabel draws + tooltips RAW, so the escaping happens here (see esc).
        us.helpLabel(im, esc(label), (tip ~= nil) and esc(tip) or nil, M.COL.head);
        drew = true;
    end);
    if drew then return; end
    M.text(im, M.COL.head, label);      -- uistyle unreachable: plain coloured label
    tipOn(im, tip);
end

-- A whole section at once: header, a blank line, the body, then a rule. `body` is
-- a function; a throw inside it costs the section, never the Panel (the caller is
-- already contained by the tab, so this is the finer-grained net).
function M.section(im, label, tip, body)
    M.header(im, label, tip);
    M.space(im);
    if type(body) == 'function' then pcall(body); end
    M.space(im);
    M.rule(im);
    M.space(im);
end

-- ---------------------------------------------------------------------------
-- controls
-- ---------------------------------------------------------------------------

-- A plain button. Returns true on click, false otherwise (including on a binding
-- without Button, so a caller never has to check).
function M.button(im, id, label, tip, w, h)
    if not isFn(im, 'Button') then return false; end
    local clicked = im.Button(tostring(label) .. '##' .. tostring(id),
                              { w or 130, h or 26 });
    tipOn(im, tip);
    return clicked == true;
end

-- A checkbox. Returns the NEW value when the player changed it, else nil -- so
-- `local v = ui.toggle(...); if v ~= nil then save(v) end` is the whole idiom and
-- an unchanged frame writes nothing.
function M.toggle(im, id, label, value, tip)
    if not isFn(im, 'Checkbox') then return nil; end
    local buf = { value == true };
    local out = nil;
    if im.Checkbox(tostring(label) .. '##' .. tostring(id), buf) then out = buf[1]; end
    tipOn(im, tip);
    return out;
end

-- The widest of a list of labels, MEASURED, plus padding -- never hardcoded.
-- Falls back to a width that fits ~16 characters at the themed font when the
-- binding has no CalcTextSize.
function M.widthFor(im, labels)
    local w = 176;
    pcall(function()
        if not isFn(im, 'CalcTextSize') then return; end
        local widest = 0;
        for _, s in ipairs((type(labels) == 'table') and labels or {}) do
            local tw = im.CalcTextSize(tostring(s));
            if type(tw) == 'number' and tw > widest then widest = tw; end
        end
        if widest > 0 then w = math.max(M.CHOICE_MIN, math.floor(widest) + 20); end
    end);
    return w;
end

-- AN EXCLUSIVE CHOICE, as a lit/unlit button group -- the proven substitute for
-- RadioButton, which is called nowhere in dlac (hard rule 2: its presence would
-- prove nothing about it).
--
--   opts = {
--     values     = { 'off', 'attack', 'follow' },   -- REQUIRED, the switch order
--     labels     = { off = 'Off', ... },            -- display text per value
--     helps      = { off = '...', ... },            -- hover per value (optional)
--     horizontal = false,                           -- default: STACKED (see header)
--     w, h       = <override the measured size>,
--   }
--
-- Returns the picked value when the player clicked one, else nil.
function M.choice(im, id, opts, current)
    opts = (type(opts) == 'table') and opts or {};
    local values = (type(opts.values) == 'table') and opts.values or {};
    if #values == 0 then return nil; end
    local labels = (type(opts.labels) == 'table') and opts.labels or {};
    local helps  = (type(opts.helps)  == 'table') and opts.helps  or {};

    local labelList = {};
    for i, v in ipairs(values) do labelList[i] = labels[v] or tostring(v); end
    local w = tonumber(opts.w) or M.widthFor(im, labelList);
    local h = tonumber(opts.h) or M.CHOICE_H;

    local picked = nil;
    for i, v in ipairs(values) do
        local lit = (current == v);
        -- Push the lit colour only when we can, and pop on EVERY path.
        local pushed = false;
        if lit and ImGuiCol_Button ~= nil and isFn(im, 'PushStyleColor') then
            im.PushStyleColor(ImGuiCol_Button, M.COL.lit);
            pushed = true;
        end
        local clicked = false;
        if isFn(im, 'Button') then
            clicked = im.Button(labelList[i] .. '##' .. tostring(id) .. '_' .. tostring(v), { w, h });
        end
        if pushed and isFn(im, 'PopStyleColor') then im.PopStyleColor(1); end
        tipOn(im, helps[v]);
        if clicked then picked = v; end
        -- Horizontal is opt-in and the LAST item never gets a SameLine.
        if opts.horizontal == true and i < #values and isFn(im, 'SameLine') then
            im.SameLine(0, 6);
        end
    end
    return picked;
end

-- A NUMERIC SLIDER. SliderFloat is field-proven (the floating-gear scale in
-- equippedui); SliderInt is called nowhere in dlac, so InputInt -- proven in
-- three panels -- is the fallback rather than a second unproven slider.
--
-- Returns the new value when the player moved it, else nil. CLAMP ON THE WAY IN
-- at the caller: a drag is one call per frame, and a store that writes on
-- mutation only turns that into one write per distinct value you actually keep.
function M.slider(im, id, value, min, max, fmt, tip, width)
    local out = nil;
    local drew = false;
    if isFn(im, 'PushItemWidth') then im.PushItemWidth(tonumber(width) or 150); end
    if isFn(im, 'SliderFloat') then
        local buf = { tonumber(value) or 0 };
        drew = true;
        if im.SliderFloat('##' .. tostring(id), buf, min, max, fmt or '%.0f') then out = buf[1]; end
    elseif isFn(im, 'InputInt') then
        local buf = { tonumber(value) or 0 };
        drew = true;
        if im.InputInt('##' .. tostring(id), buf) then out = buf[1]; end
    end
    if isFn(im, 'PopItemWidth') then im.PopItemWidth(); end
    if drew then tipOn(im, tip); end
    return out, drew;
end

-- A DROPDOWN over a list of rows. `rows` is any array; `labelOf(row)` renders
-- one (defaults to tostring). `current` is the selected row's label text, or nil.
-- `noneLabel`, when given, prepends a "nothing selected" entry that returns the
-- string it is labelled with.
--
-- Returns the picked row (or the noneLabel string) when the player chose, else
-- nil. Guarded: BeginCombo is not in every binding, and EndCombo runs only when
-- BeginCombo returned true.
function M.combo(im, id, current, rows, labelOf, tip, noneLabel)
    if not isFn(im, 'BeginCombo') or not isFn(im, 'EndCombo') then return nil; end
    local render = (type(labelOf) == 'function') and labelOf or tostring;
    local picked = nil;
    if im.BeginCombo('##' .. tostring(id), tostring(current or noneLabel or '')) then
        if noneLabel ~= nil and isFn(im, 'Selectable') then
            if im.Selectable(tostring(noneLabel) .. '##' .. tostring(id) .. '_none',
                             current == nil) then
                picked = noneLabel;
            end
        end
        for i, row in ipairs((type(rows) == 'table') and rows or {}) do
            local label = tostring(render(row));
            if isFn(im, 'Selectable') then
                if im.Selectable(label .. '##' .. tostring(id) .. '_' .. tostring(i),
                                 label == current) then
                    picked = row;
                end
            end
        end
        im.EndCombo();
    end
    tipOn(im, tip);
    return picked;
end

-- THE ON/OFF PILL (green knob-right on, red knob-left off -- Henrik's widget).
-- Draw-list pill, falling back to a coloured button when the draw list is
-- unavailable. Returns true when toggled this frame.
--
-- This is the ONE implementation: ui\craftbar.onOffSwitch (the hobby bars' entry
-- point) delegates here, so the pill on a Job helper row, a craft bar and a HELM
-- panel are the same widget and stay that way.
function M.pill(im, on, id, tipOnText, tipOffText)
    local W, H = 46, 22;
    local toggled = false;
    local ok = pcall(function()
        local x, y = im.GetCursorScreenPos();
        im.InvisibleButton('##onoff_' .. tostring(id), { W, H });
        toggled = im.IsItemClicked();
        local dl = im.GetWindowDrawList();
        local track = 0xFF2E2E9E;                       -- ARGB red
        if on == true then track = 0xFF2E8B2E; end      -- ARGB green
        local knob = 0xFFEEEEEE;
        dl:AddRectFilled({ x, y }, { x + W, y + H }, track, H / 2, ImDrawCornerFlags_All or 0);
        local kx = x + H / 2;
        if on == true then kx = x + W - H / 2; end
        dl:AddCircleFilled({ kx, y + H / 2 }, H / 2 - 3, knob, 16);
    end);
    if not ok then
        local pushed = false;
        if ImGuiCol_Button ~= nil and isFn(im, 'PushStyleColor') then
            local col = { 0.62, 0.18, 0.18, 1.00 };
            if on == true then col = { 0.18, 0.55, 0.18, 1.00 }; end
            im.PushStyleColor(ImGuiCol_Button, col);
            pushed = true;
        end
        local face = 'OFF';
        if on == true then face = 'ON'; end
        if isFn(im, 'Button') and im.Button(face .. '##onoff_' .. tostring(id), { W, H }) then
            toggled = true;
        end
        if pushed and isFn(im, 'PopStyleColor') then im.PopStyleColor(1); end
    end
    local t = tipOffText;
    if on == true then t = tipOnText; end
    tipOn(im, t);
    return toggled == true;
end

-- ---------------------------------------------------------------------------
-- the RULE STATUS block -- "is this thing going to act, and what did it last do?"
-- ---------------------------------------------------------------------------
--
-- Every standing rule owes the player these two lines, and the BST Helper wrote
-- them out three times with the same precedence and the same colour split. The
-- split is the load-bearing part, so it lives here rather than in each module:
--
--   * DIM   -- the rule is off. Not a problem; the player turned it off.
--   * WARN  -- something the PLAYER can fix is blocking it: the wrong job, town,
--              dead, zoning, no jug picked. Orange means "look at me".
--   * OK    -- armed and acting.
--   * DIM   -- and underneath, what the last evaluation decided.
--
-- What must NOT be WARN is the rule working: "no pet out", "above the threshold",
-- "waiting out the lockout" are normal, they happen on most beats, and colouring
-- them orange would cry wolf all session. They belong in the dim `last` line.
--
--   spec = {
--     armed     = <bool>,                  -- your rule's own switch
--     activity  = <the activity record>,   -- S.me.acting()
--     blocked   = <string|nil>,            -- YOUR gate, checked before activity
--     offText   = 'The rule is off -- ...',
--     armedText = 'Armed: below 50% pet HP.',
--     last      = <string|nil>,            -- your decisionText(lastDecision())
--     lastLabel = 'Last beat',             -- default 'Last'
--   }
function M.ruleStatus(im, spec)
    spec = (type(spec) == 'table') and spec or {};
    if spec.armed ~= true then
        M.dim(im, spec.offText or 'This rule is off.');
    elseif type(spec.blocked) == 'string' and spec.blocked ~= '' then
        M.warn(im, spec.blocked);
    elseif type(spec.activity) == 'table' and spec.activity.active ~= true then
        M.warn(im, 'Not acting: ' .. tostring(spec.activity.label or 'inactive') .. '.');
    else
        M.ok(im, spec.armedText or 'Armed.');
    end
    if type(spec.last) == 'string' and spec.last ~= '' then
        M.dim(im, tostring(spec.lastLabel or 'Last') .. ': ' .. spec.last .. '.');
    end
end

-- ---------------------------------------------------------------------------
-- bind -- the kit with the handle already applied
-- ---------------------------------------------------------------------------
--
-- `ui = panelkit.bind(ctx.imgui)` and then `ui.header(...)`, `ui.toggle(...)`.
-- The Job Helpers tab does this for you and hands the result over as `ctx.ui`, so
-- a module's Panel never mentions the handle at all.
--
-- Built by walking M, so a widget added above is bound automatically and cannot
-- be forgotten here. NOT_BOUND lists the functions that take no handle -- they
-- are carried over AS THEY ARE, because handing them an `im` first argument would
-- quietly corrupt what they return (`esc(im)` would escape a table address).
local NOT_BOUND = { bind = true, esc = true };
function M.bind(im)
    local b = { COL = M.COL, imgui = im, raw = M };
    for name, fn in pairs(M) do
        if type(fn) == 'function' and not NOT_BOUND[name] then
            b[name] = function(...) return fn(im, ...); end
        end
    end
    b.esc = M.esc;
    return b;
end

return M;
