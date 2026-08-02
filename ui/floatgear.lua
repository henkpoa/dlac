--[[
    dlac/ui/floatgear.lua

    The floating equipment window (equipmon's 4x4, but ImGui and interactive) and
    the PIN menu that hangs off it. Its own module -- gearui stays off the LuaJIT
    200-local ceiling (hard rule 1), and this file owns every local it needs.

    It reads uihost's shared services but does NOT register a uihost `window`:
    those render inside gearui's drawWindow, which returns early when the main
    box is shut, and this window's whole point is to stay up while you play. So
    gearui's d3d_present calls M.render directly, inside its own theme bracket --
    the lockstyle-window pattern.

    What it is: the same 4x4 grid the Equipped tab draws (S.renderSlotGrid, so
    icons and the full hover tooltip come for free and can never drift from the
    tab's), in a window you can leave open while you play. Right-click a slot to
    pin an item into it; a pinned slot's box turns RED. SHIFT+drag moves it
    (equipmon's gesture -- and the only one available: see the NoMove note in
    M.render). The Equipped tab's slider scales it; the scale is one number,
    `opts.box`, that renderSlotGrid derives the icon and frame pad from.

    Right-click: IsMouseClicked(1) + IsItemHovered feeding the ordinary
    OpenPopup/BeginPopup pair -- the pattern gearmove field-confirmed on
    feature/storage-move. (BeginPopupContextItem is the one that failed twice and
    put "right-click" on the dead-ends list; do not reach for it.) The grid
    reports the click from inside its own BeginChild and this module opens the
    popup at WINDOW scope, because OpenPopup and BeginPopup must share a scope.

    FIELD-CONFIRMED 07-15 (Henrik): right-click opens the menu AND imgui.BeginMenu
    cascades in this binding -- the first Lua caller of BeginMenu in this install.
    The drill-down fallback below is now dead weight kept only as a guard for a
    binding change; hasMenu has never been false in the field.

    Two hard-won imgui facts live in this file, both about the same rule -- a
    SUBMENU is drawn outside the rect of the window that declares it:
      * the pin list must NOT sit in a BeginChild, or moving the mouse toward a
        submenu leaves the child and ImGui tears down the whole popup;
      * so the popup is bounded with SetNextWindowSizeConstraints instead.

    Pins are the engine's, not this window's: pinwatch writes
    <char>\dlac\pinstate.lua and dispatch (v44) wears the pinned names at top
    priority every dispatch. This module only edits that table.

    2026-08-03, three field asks (Henrik):
      * the list offers only what you can put on RIGHT NOW -- job, level AND
        bags. The job/level gate was always there (the Gear Oracle's canWear,
        via candidatesForSlot); what was missing is the bag half, so a piece in
        a Mog Locker was offered and the pin then sat there doing nothing. Asked
        through gearui's `avail.have` -- the same function the Sets tab previews
        the engine's refusal with, so the menu and the engine cannot disagree.
      * every row carries the item's ICON (ui\itemicons, the equippedui call),
        because a wall of names is not how you find a hat.
      * a slot holds SEVERAL pins, one per trigger -- Optical Hat on TP_Default,
        Walahra Turban on Movement. pinwatch owns that list and the engine picks
        between them per dispatch; this file shows them, adds to them, and
        removes them one at a time or all at once.

    ...and two follow-ups from the same round:
      * the popup's width is MEASURED, not a constant (popupMaxW). A flat cap let
        the item list grow freely while clipping every pinned row.
      * hovering a row shows that item's FACTS in a panel beside the menu
        (renderFactsPanel) -- the same card the hover tooltip draws everywhere
        else, placed where the menu chain cannot reach it. A tooltip could not do
        this job: it follows the cursor, and the cursor is on the menu.
]]--

local host = require("dlac\\ui\\uihost");
local pins = require("dlac\\feature\\pinwatch");
local fmt  = require("dlac\\gear\\gearfmt");

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');
local dsp   = try("dlac\\dispatch");
-- Icons for the pin list. try(), not a bare require: this window renders whether
-- or not d3d came up, and itemicons itself already no-ops without it -- a nil
-- here just means text rows, never a dead window.
local icons = try("dlac\\ui\\itemicons");

local M = {};

local S = host.services;
local ui, COL = S.ui, S.COL;
local GEAR_OF = S.GEAR_OF;

-- gearui provides its services BEFORE requiring this file, so the captures above
-- are safe (the equippedui precedent). If that order ever changes, fail loud and
-- render nothing rather than throwing a nil index every frame.
if ui == nil or COL == nil or S.renderSlotGrid == nil then
    print('[dlac] floatgear: shared services missing -- the floating window is disabled.');
    M.render = function() end;
    return M;
end

-- Cascading submenus: BeginMenu/EndMenu are declared in the Ashita SDK and their
-- symbols are in the binding, but NOTHING in this install calls them from Lua --
-- and symbol presence proves nothing here (BeginPopupContextItem is bound too,
-- and does not work). So probe the binding rather than assume it (hard rule 2).
-- Bound -> the Windows-style "item -> All / trigger" cascade. Not bound -> the
-- same choices as a drill-down inside the popup (gearmove's quantity-chooser
-- pattern), which uses only APIs already proven in this client.
local hasMenu = (imgui ~= nil)
    and (type(imgui.BeginMenu) == 'function') and (type(imgui.EndMenu) == 'function');

-- THE hover flags for the drag, and the reason shift+drag was dead for five rounds.
--
-- renderSlotGrid draws the 4x4 inside its own BeginChild. So when the cursor is on
-- a slot, ImGui's hovered window is that CHILD -- and IsWindowHovered() defaults to
-- an EXACT window match (`if (ref_window != cur_window) return false`), comparing
-- the child against this window and returning false. Every frame. The drag could
-- never latch, which looked exactly like "shift is not detected" and sent three
-- rounds chasing the keyboard.
--
-- ChildWindows is the fix, and libs/imgui.lua:324 says so in as many words:
-- "IsWindowHovered() only: Return true if any children of the window is hovered".
-- RectOnly does NOT contain it (:332), nor does AllowWhenBlockedByActiveItem --
-- both of which I tried. AllowWhenOverlapped is deliberately NOT included: ImGui
-- asserts it is unsupported for IsWindowHovered.
--
-- Fallbacks are the REAL bit values, not 0: `or 0` on a flag silently disables it,
-- which is precisely the failure mode above -- and it makes the flags assertable
-- headless, where the globals do not exist.
local HOVER_FLAGS = (ImGuiHoveredFlags_ChildWindows or 1)                    -- bit 0
                  + (ImGuiHoveredFlags_AllowWhenBlockedByActiveItem or 32);  -- bit 5
M._HOVER_FLAGS = HOVER_FLAGS;   -- test seam

local POPUP  = '##dlac_pinmenu';
local CAP    = 200;       -- rows drawn per popup; the overflow is COUNTED, not hidden
local BOX0   = 40;        -- renderSlotGrid's default box; scale 1.0 == the tab's size

-- Shift: the Win32 key state, straight from user32. TWO earlier attempts failed in
-- the field, and the reason is the same both times -- they asked something that
-- only knows about shift SOMETIMES:
--
--   1. imgui.GetIO().KeyShift -- dead during normal play. Ashita only feeds the
--      keyboard into ImGui's IO when ImGui wants it; standing in the world it does
--      not. (fancychat DOES use it -- inside its chat-INPUT mode, where ImGui has
--      focus. Proven in this install, wrong for this context.)
--   2. Ashita's `key` (WNDPROC) event, VK_SHIFT + the lparam transition bit --
--      equipmon's exact code. Also never fired here.
--
-- GetKeyState asks the OS, so it is true whenever the key is physically down, no
-- matter who has focus or which input path the client is using. This is what trove
-- uses -- its comment reads "Win32 key state for shift-to-move", the same gesture.
-- The high bit means "down", hence < 0. cdef is pcall'd because another addon in
-- this Lua state may have declared the same symbol already.
-- BOTH user32 reads, OR'd. They differ in a way that matters here: GetKeyState is
-- relative to the calling thread's message queue, GetAsyncKeyState is the physical
-- key. trove uses the first, XIUI the second; after two field misses this is not
-- the place to bet on one. The high bit means "down", hence < 0 on the short.
local ffi = (function()
    local ok, m = pcall(require, 'ffi');      -- ffi is not a plain table: guard on nil,
    return (ok and m ~= nil) and m or nil;    -- the itemicons pattern, not try()
end)();
if ffi ~= nil then
    -- pcall'd separately: another addon in this Lua state may have declared either
    -- symbol already, and one failing must not take the other down with it.
    pcall(ffi.cdef, 'short __stdcall GetKeyState(int nVirtKey);');
    pcall(ffi.cdef, 'short __stdcall GetAsyncKeyState(int vKey);');
end
local VK_SHIFT = 0x10;

-- The Ashita `key` (WNDPROC) event -- source 3. Kept alongside the user32 reads
-- rather than instead of them: see shiftDown.
local _keyShift = false;
pcall(function()
    local b = require('bit');
    ashita.events.register('key', 'dlac_floatgear_key', function(e)
        if e ~= nil and e.wparam == VK_SHIFT then
            -- lparam bit 31 = transition state: 1 when the key is going UP
            _keyShift = not (b.band(e.lparam, b.lshift(0x8000, 0x10)) == b.lshift(0x8000, 0x10));
        end
    end);
end);

-- FOUR sources, OR'd. That is not elegance, it is arithmetic: three separate
-- single-source attempts have now failed in the field (imgui IO, the key event,
-- user32-only), each one picked because some other addon here "proves" it, and
-- each one wrong for THIS context. Every source is independently harmless and
-- costs nothing per frame, so read them all and take any yes. When one is finally
-- shown to work, this collapses to that one -- but not before.
local function shiftDown()
    if ffi ~= nil then
        local ok, v = pcall(function() return ffi.C.GetAsyncKeyState(VK_SHIFT) < 0; end);
        if ok and v == true then return true; end
        local ok2, v2 = pcall(function() return ffi.C.GetKeyState(VK_SHIFT) < 0; end);
        if ok2 and v2 == true then return true; end
    end
    if _keyShift == true then return true; end
    local ok3, v3 = pcall(function() return imgui.GetIO().KeyShift; end);
    return ok3 and v3 == true;
end
-- Test seam: the smoke suite overrides this. The OS call cannot run headless, so
-- what the tests cover is the LATCH and the click suppression around it -- the
-- logic that broke -- not the key read itself.
M.shiftHeld = shiftDown;

-- The window's scale, clamped HERE rather than at the slider: uiflags.lua is a
-- plain Lua file a player can edit, and a 0 or a negative there would collapse the
-- grid to nothing with no way back through the GUI.
M.SCALE_MIN, M.SCALE_MAX = 0.5, 3.0;
function M.scale()
    local s = tonumber(ui._gfScale) or 1.0;
    if s < M.SCALE_MIN then s = M.SCALE_MIN; end
    if s > M.SCALE_MAX then s = M.SCALE_MAX; end
    return s;
end
local scaleNow = M.scale;
local _openFor  = nil;    -- slot label whose menu should open next frame
local _menuSlot = nil;    -- slot the open popup belongs to
local _dragging = false;  -- shift+drag latch: set on press, cleared on release
-- Keyless move mode (right-click menu). Shift detection has now missed three
-- times in the field, and every failure looked identical from your side: nothing
-- happens. This needs no key at all -- while it is on, plain LMB drags the window
-- and the slots stop taking clicks. If Shift ever proves reliable this stays
-- anyway: it is the accessible route for anyone who cannot chord a drag.
local _moveMode = false;
local _drillItem = nil;   -- fallback mode: item picked, now choosing scope
local _search = { '' };
-- Was the pin popup drawn LAST frame? The width measurement is only worth
-- building while the menu is up, and this is the only honest way to know: ImGui
-- owns the popup's open state and BeginPopup is the one thing that reports it.
local _popupUp = false;
-- The item whose facts the side panel shows this frame, and the popup's screen
-- rect to place that panel against. Both are filled DURING the popup and read
-- after it closes, in the same frame -- so neither can go stale.
local _hoverRec  = nil;
local _popupRect = nil;
local _panelOpenT = { true };

-- --------------------------------------------------------------------------
-- Trigger choices for the scope submenu.
-- --------------------------------------------------------------------------

-- Every trigger of the CURRENT job entry as { key, text, short }. `key` is the
-- engine's scope key (dispatch.pinScopeKey over dispatch.ruleLabel) -- built from
-- the engine's own functions so the addon and LAC states cannot spell it
-- differently; `text` is the human line for the menu; `short` is the same line
-- WITHOUT the set name, for the pinned rows, where the piece is already named on
-- the left and " -> Movement" is the longest and least useful third of the row.
local function triggerChoices()
    local out = {};
    if dsp == nil or type(dsp.pinScopeKey) ~= 'function' then return out; end
    local tui = package.loaded["dlac\\ui\\triggersui"];   -- load order: don't force it
    if tui == nil or type(tui.currentModel) ~= 'function' then return out; end
    local data = nil;
    pcall(function() data = tui.currentModel(); end);
    if type(data) ~= 'table' then return out; end
    for _, ev in ipairs(dsp.EVENTS or {}) do
        local list = data[ev];
        if type(list) == 'table' then
            for _, r in ipairs(list) do
                if type(r) == 'table' and type(r.when) == 'table' then
                    -- whenAny (v54) and cases (issue #126) are part of the label:
                    -- both states must spell an OR / case rule's scope key
                    -- identically, and a case-LESS rule keys byte-for-byte as
                    -- before so existing pins survive untouched (PRD story 19).
                    local label = dsp.ruleLabel(r.when, r.whenAny, r.cases);
                    local parts = {};
                    for k, v in pairs(r.when) do
                        local pk = (type(dsp.PRETTY_KEY) == 'table' and dsp.PRETTY_KEY[k]) or k;
                        if v == true then parts[#parts + 1] = tostring(pk);
                        elseif type(v) == 'table' then
                            local vs = {};
                            for _, x in ipairs(v) do vs[#vs + 1] = tostring(x); end
                            table.sort(vs);
                            parts[#parts + 1] = tostring(pk) .. ' = ' .. table.concat(vs, '/');
                        else parts[#parts + 1] = tostring(pk) .. ' = ' .. tostring(v); end
                    end
                    table.sort(parts);
                    local shown = (#parts > 0) and table.concat(parts, ', ') or 'any';
                    local setn = (type(r.set) == 'string') and r.set
                              or ((type(r.set) == 'table') and r.set[1] or nil);
                    out[#out + 1] = {
                        key  = dsp.pinScopeKey(ev, label),
                        text = string.format('%s  %s%s', ev, shown,
                            setn and ('  -> ' .. tostring(setn)) or ''),
                        -- The compact spelling every ROW uses -- see disambiguate.
                        menu = setn and string.format('%s  -> %s', ev, tostring(setn))
                                     or string.format('%s  %s', ev, shown),
                    };
                end
            end
        end
    end
    return M.disambiguate(out);
end

-- THE ROW SPELLING, and why it is not simply the short one.
--
-- The cascade was ~750px wide in the field (2026-08-03) because every row spelled
-- out its conditions: "Midcast  magicType = White Magic, skill = Enfeebling Magic
-- -> Enfeebling_White". Popup plus cascade came to ~1000px of a ~1130px client,
-- which is what left the item-facts panel nowhere to go. "Midcast -> Enfeebling_
-- White" says the same thing in a third of the width.
--
-- But the conditions cannot just be DROPPED, and the field screenshots are why:
-- that job has two Default rules reading `status = Idle`, one feeding the Idle
-- set and one feeding Weapon. Drop the set and they are the same row twice; drop
-- the conditions and they are still distinct. The set name is the half that
-- identifies a rule to a person.
--
-- So: compact by default, and any label that would appear TWICE falls back to the
-- full line -- which is the only case that needed the width in the first place.
-- Pure and exported: the whole point is a guarantee (no two rows read alike) and
-- a guarantee wants a test, not a render to squint at.
function M.disambiguate(out)
    local seen = {};
    for _, c in ipairs(out or {}) do
        seen[c.menu] = (seen[c.menu] or 0) + 1;
    end
    for _, c in ipairs(out or {}) do
        if (seen[c.menu] or 0) > 1 then c.menu = c.text; end
    end
    return out;
end

-- scope key -> the choice it came from, so a PIN can be described with the words
-- you picked it by instead of the raw "Default|mode=TP_Default".
local function choiceByKey(choices)
    local m = {};
    for _, c in ipairs(choices or {}) do m[c.key] = c; end
    return m;
end

-- One pin's scope, in words. `field` picks which of the choice's two spellings
-- to use ('short' for a row, 'text' for a tooltip). A key the current job no
-- longer has (you edited or deleted that trigger) falls back to the raw key
-- rather than vanishing: the pin is real, it is simply quiet, and hiding the
-- reason would make it unremovable by anything but "remove all".
local function scopeTextOf(e, byKey, field)
    if type(e) ~= 'table' or type(e.scope) ~= 'table' then return 'All -- every dispatch'; end
    local parts = {};
    for _, k in ipairs(e.scope) do
        local c = (type(byKey) == 'table') and byKey[k] or nil;
        parts[#parts + 1] = tostring((type(c) == 'table' and c[field or 'menu']) or k);
    end
    if #parts == 0 then return 'All -- every dispatch'; end
    return table.concat(parts, ' / ');
end

-- The visible text of one pinned row. Shared with the width measurement below --
-- a popup told to fit a row it did not actually measure is the bug this exists
-- to prevent.
local function pinRowText(e, byKey)
    return string.format('%s   --   %s', tostring(e.item), scopeTextOf(e, byKey, 'menu'));
end

-- The scope keys this slot's pins already hold -> the item holding each ('All'
-- is its own key). Lets the scope menu say WHICH piece owns a trigger before
-- you overwrite it.
local function heldByKey(slot)
    local m = {};
    for _, e in ipairs(pins.pinsOf(slot)) do
        if type(e.scope) == 'table' then
            for _, k in ipairs(e.scope) do m[tostring(k)] = e.item; end
        else
            m['All'] = e.item;
        end
    end
    return m;
end

-- --------------------------------------------------------------------------
-- The pin menu.
-- --------------------------------------------------------------------------

-- Draw an item's icon and leave the cursor on the same line, or nothing at all
-- when icons are unavailable. Never a Dummy in that case: itemicons draws one
-- to keep a COLUMN aligned, and a menu with no icons at all should just be the
-- text menu it used to be.
local ICON = 20;

-- Text width, the equippedui pattern: this binding's CalcTextSize returns a
-- NUMBER, and the character fallback keeps the measurement honest headless and
-- on a binding that lacks it.
local function calcTextW(s)
    if imgui == nil or type(imgui.CalcTextSize) ~= 'function' then return #tostring(s or '') * 7; end
    local ok, w = pcall(imgui.CalcTextSize, tostring(s or ''));
    if ok and type(w) == 'number' and w > 0 then return w; end
    return #tostring(s or '') * 7;
end

-- HOW WIDE THE POPUP IS ALLOWED TO GET, measured from the rows it is about to
-- draw rather than picked in advance.
--
-- Henrik, 2026-08-03: "make the right click menu grow with the text -- I think
-- it's doing that, but only based on equip names and not the pin list." Both
-- were already inside ONE auto-sizing popup; the difference was the ceiling. An
-- item name is ~20 characters and never came near the old flat 380, so the list
-- looked like it grew freely -- while a pinned row is a name AND a trigger and
-- sailed straight past it, where the only thing a clamped popup can do is clip.
--
-- So the cap becomes a measurement. MAX is a real limit and stays: a rule with
-- six conditions can produce a scope line wide enough to cover the screen, and
-- past that point the honest answer is a scrollbar, not a window you cannot see
-- around. Measured UNFILTERED on purpose -- the width holding still while you
-- type is worth more than shaving pixels off it per keystroke.
local MIN_W, MAX_W, CAP_W = 250, 620, 460;   -- floor, ceiling, height cap
-- The CASCADE's height cap (its width is left free -- see the note at BeginMenu).
-- Deliberately shorter than the parent popup's: the cascade opens level with the
-- row you are hovering, which can be most of the way down the list, so a submenu
-- as tall as the popup would start below the screen's bottom edge as often as not.
local SUB_MAX_H = 340;
local function popupMaxW(slot, byKey, pool)
    local widest = 0;
    for _, e in ipairs(pins.pinsOf(slot)) do
        local w = calcTextW(pinRowText(e, byKey));
        if w > widest then widest = w; end
    end
    -- The candidate rows: only the longest NAME can be the widest row, so one
    -- measurement does for the whole list however long it is.
    local longest = '';
    for _, rec in ipairs(pool or {}) do
        local nm = tostring(rec.Name or '');
        if #nm > #longest then longest = nm; end
    end
    if longest ~= '' then
        -- +26: BeginMenu draws a submenu arrow past the label.
        local w = calcTextW(longest) + 26;
        if w > widest then widest = w; end
    end
    -- + the icon column and the window's own padding/scrollbar allowance.
    widest = math.floor(widest + ICON + 6 + 34);   -- floored: a fractional cap
    if widest < MIN_W then return MIN_W; end       -- jitters the popup by a pixel
    if widest > MAX_W then return MAX_W; end       -- as the text changes
    return widest;
end

-- The item facts panel: the SAME card the hover tooltip draws everywhere else in
-- dlac (gearui.renderItemTooltip with `bare` -- stats, DMG/Delay, set-bonus
-- ladder, where the copies live, your augments, jobs), in a window of our own
-- placed BESIDE the menu.
--
-- Henrik, 2026-08-03: "show the stats of the item as well -- somewhere where it
-- doesn't clip into the right click menu or cover it." A tooltip cannot satisfy
-- that: it follows the cursor, and the cursor is on the menu. So the panel is
-- pinned to the popup's own rect instead, and goes on the LEFT -- the scope
-- cascade opens to the RIGHT, so the left is the one side the menu chain can
-- never grow into. If the popup is hard against the left edge of the screen
-- there is no left, and it drops UNDERNEATH the popup instead: a submenu is
-- drawn beside its parent ROW, never below the whole popup.
--
-- NoInputs is not decoration. This window is drawn under the cursor's path while
-- you read a menu, and any mouse it caught would be a mouse the menu did not --
-- which is how an info panel turns into "the menu randomly stops responding".
-- NoFocusOnAppearing keeps it from stealing focus the frame it shows up.
local PANEL_W = 360;
-- REAL bit values as fallbacks, never `or 0` -- the HOVER_FLAGS lesson at the top
-- of this file, and it bites harder here. `or 0` on the input flags does not
-- degrade the panel: it hands the panel the mouse the MENU needed, and the
-- failure reads as "the right-click menu randomly stops responding", which is
-- nobody's idea of a missing constant. Spelled as the three individual bits
-- rather than NoInputs (which is just their union) so each one has a fallback.
local PANEL_FLAGS = (ImGuiWindowFlags_NoTitleBar or 1)                 -- bit 0
                  + (ImGuiWindowFlags_NoResize or 2)                   -- bit 1
                  + (ImGuiWindowFlags_NoCollapse or 32)                -- bit 5
                  + (ImGuiWindowFlags_AlwaysAutoResize or 64)          -- bit 6
                  + (ImGuiWindowFlags_NoSavedSettings or 256)          -- bit 8
                  + (ImGuiWindowFlags_NoMouseInputs or 512)            -- bit 9
                  + (ImGuiWindowFlags_NoFocusOnAppearing or 4096)      -- bit 12
                  + (ImGuiWindowFlags_NoNavInputs or 262144)           -- bit 18
                  + (ImGuiWindowFlags_NoNavFocus or 524288);           -- bit 19
M._PANEL_FLAGS = PANEL_FLAGS;   -- test seam

local function renderFactsPanel(rec)
    if imgui == nil or type(rec) ~= 'table' or _popupRect == nil then return; end
    if type(S.renderItemTooltip) ~= 'function' then return; end
    local px, py, pw, ph = _popupRect[1], _popupRect[2], _popupRect[3], _popupRect[4];
    local x, y = px - PANEL_W - 8, py;
    if x < 4 then x, y = px, py + (ph or 0) + 8; end
    imgui.SetNextWindowPos({ x, y }, (ImGuiCond_Always or 1));
    -- min.x == max.x pins the WIDTH while the height still auto-sizes to the
    -- card. (Not SetNextWindowSize({0,0}) + AlwaysAutoResize -- that pair is the
    -- collapsed-window trap this codebase has a law about.)
    imgui.SetNextWindowSizeConstraints({ PANEL_W, 0 }, { PANEL_W, 620 });
    _panelOpenT[1] = true;
    local shown = imgui.Begin('##dlac_pinfacts', _panelOpenT, PANEL_FLAGS);
    if shown then
        -- `bare` = the card without its tooltip frame. pcall'd because this runs
        -- on the render path and a card that throws must cost the panel, never
        -- the frame -- and End() below still runs either way.
        pcall(S.renderItemTooltip, rec, nil, true);
    end
    imgui.End();
end
M._renderFactsPanel = renderFactsPanel;   -- test seam

-- The catalog record behind a NAME -- a pin stores a name, so the facts panel and
-- the pinned rows' icons both have to get back to a record. nil when the name has
-- no record, which callers read as "nothing to show", never as an error.
local function lookupName(nm)
    if type(S.lookupByName) ~= 'function' then return nil; end
    local rec = nil;
    pcall(function() rec = S.lookupByName(nm); end);
    return (type(rec) == 'table') and rec or nil;
end

local function rowIcon(name)
    if icons == nil or type(icons.renderIcon) ~= 'function' then return; end
    local rec = lookupName(name);
    pcall(icons.renderIcon, (rec ~= nil) and rec.Id or nil, ICON, rec);
end

local function applyPin(slot, itemName, scope)
    pins.setPin(slot, itemName, scope);
    _drillItem = nil;
    pcall(function() imgui.CloseCurrentPopup(); end);
end

-- The scope rows for one item: "All" on top (the hard set -- every dispatch),
-- then one row per trigger of this job.
--
-- `inMenu` says we are inside a BeginMenu (the cascade), where MenuItem is the
-- right widget; the drill-down fallback uses Selectable. Tying the widget to
-- `hasMenu` rather than to `imgui.MenuItem ~= nil` keeps the fallback path on
-- APIs this client has actually proven -- MenuItem is used by shipped addons
-- with one argument, but only ever inside a menu.
--
-- No fmt.esc on these labels: esc doubles '%' for imgui's FORMATTING calls
-- (Text/TextColored). Selectable and MenuItem labels are not format strings, so
-- escaping would render a literal '%%' -- which is why nothing else in dlac
-- escapes a Selectable label either.
local function renderScopeRows(slot, name, choices, inMenu)
    local held = heldByKey(slot);
    -- What already owns this scope, appended to the row. Overwriting a trigger's
    -- pin is normal and silent -- but you should be able to SEE that it is what
    -- the click is about to do before you make it.
    local function row(label, key)
        local cur = held[key];
        if cur ~= nil then label = label .. '   [' .. tostring(cur) .. ']'; end
        if inMenu then return imgui.MenuItem(label); end
        return imgui.Selectable(label);
    end
    local hit = false;
    if row('All', 'All') then applyPin(slot, name, 'All'); hit = true; end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Pin for EVERYTHING -- the engine wears this piece on\nevery dispatch and nothing can take it back off.\n\nAll REPLACES every other pin on this slot.');
    end
    imgui.Separator();
    if #choices > 0 then
        for _, c in ipairs(choices) do
            if row(c.menu or c.text, c.key) then applyPin(slot, name, { c.key }); hit = true; end
            -- The conditions the compact label leaves out, on hover. They are the
            -- reason the row is short, so they have to be one movement away.
            if imgui.IsItemHovered() then imgui.SetTooltip(fmt.esc(tostring(c.text))); end
        end
        imgui.Separator();
        imgui.TextColored(COL.DIM, 'One pin per trigger. Pinning a trigger leaves\nthis slot\'s other trigger pins alone.');
    else
        imgui.TextColored(COL.DIM, '(this job has no triggers yet)');
    end
    return hit;
end

-- Candidate pool for a slot -- the SAME service the Equipped tab's Alternatives
-- list uses. Gating by job/level (and, for Sub, by the worn Main) is CORRECT
-- here: a pin equips immediately, so this is not set BUILDING and ADR 0006's
-- never-gate rule does not apply. The Sub HARD RULE (reverted 3x) protects the
-- BUILDER's Sub picker; the immediately-equipping Alternatives list gates, and
-- so does this. Offering a shield you cannot hold next to your 2H would just
-- pin a piece that never lands.
--
-- The BAG half of "right now" (Henrik, 2026-08-03: "only show gear that is
-- wearable at that very moment -- nothing in mog locker etc"). candidatesForSlot
-- gates ownership on owned-ANYWHERE, which is right for a set BUILDER and wrong
-- here: a pin equips, and a piece in a Mog Safe or Locker cannot be equipped, so
-- offering it just pins something that never lands and looks like a broken pin.
--
-- Asked through gearui's avail.have -- the same function the Sets tab previews
-- the engine's own refusal with, so the two can never drift. Three-valued for
-- the reason it is three-valued there: nil means the bag scan has not answered
-- yet (or the name has no record), and hiding on "don't know" would empty the
-- menu at exactly the wrong moment. Only a definite false hides a row.
local function equippableNow(rec)
    if type(S.avail) ~= 'table' or type(S.avail.have) ~= 'function' then return true; end
    local ok, v = pcall(S.avail.have, (type(rec) == 'table') and rec.Name or nil);
    if not ok then return true; end
    return v ~= false;
end
M._equippableNow = equippableNow;   -- test seam

local function candidatesFor(slot, job, level)
    local gearKey = GEAR_OF[slot] or slot;
    local list = nil;
    if slot == 'Sub' and S.subFilter ~= nil and S.subCandidatePool ~= nil then
        local mainRec = S.lookupById(S.getEquippedId(0x00));   -- the WORN Main
        local ok, res = pcall(S.subFilter, S.subCandidatePool(job, level),
            mainRec, job, level, false);                       -- building = false
        if ok and type(res) == 'table' then list = res; end
    end
    if list == nil then list = S.candidatesForSlot(gearKey, job, level) or {}; end
    -- A NEW table, never a filter in place: candidatesForSlot hands back its own
    -- cached array and every other surface reads that same one.
    local out = {};
    for _, rec in ipairs(list) do
        if equippableNow(rec) then out[#out + 1] = rec; end
    end
    return out;
end

-- `choices` and `pool` are computed by M.render (the width measurement needs
-- them BEFORE BeginPopup, and building them twice a frame would be waste), but
-- both are optional: the fallbacks keep this function drivable on its own.
local function renderPinMenu(job, level, choices, pool)
    local slot = _menuSlot;
    if slot == nil then return; end

    imgui.TextColored(COL.HEADER, slot);
    imgui.Separator();

    -- Keyless move mode, top of the menu: the window has no title bar to grab and
    -- Shift has been unreliable here, so this is the route that cannot fail.
    if _moveMode then
        imgui.TextColored(COL.SCORE, 'MOVE MODE -- drag the boxes to move.');
        if imgui.Selectable('Done moving') then
            _moveMode = false;
            _dragging = false;        -- the latch must not outlive the mode
            pcall(function() imgui.CloseCurrentPopup(); end);
        end
        imgui.Separator();
        return;                       -- nothing else is useful while moving
    end
    if imgui.Selectable('Move window') then
        _moveMode = true;
        pcall(function() imgui.CloseCurrentPopup(); end);
        return;
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Drag the boxes to move the window; right-click for "Done moving".\nShift+drag does the same without the mode, when Shift is detected.');
    end
    imgui.Separator();

    if choices == nil then choices = triggerChoices(); end
    local byKey = choiceByKey(choices);

    -- Unpin first: it is the one row you want instantly when the frame is red.
    -- A slot can hold SEVERAL pins now, so this is a list and each row removes
    -- its OWN pin -- "you should be able to choose all, or specific trigger pin
    -- mapping" (Henrik). Removing one and returning immediately is deliberate:
    -- the indices shift under clearPinAt, and re-reading them next frame is
    -- cheaper than reasoning about it here.
    local held = pins.pinsOf(slot);
    if #held > 0 then
        imgui.TextColored(COL.SCORE, (#held == 1) and 'Pinned here:'
                                      or string.format('Pinned here (%d):', #held));
        for i, e in ipairs(held) do
            rowIcon(e.item);
            -- No fmt.esc, and NO truncation: a Selectable label is not a format
            -- string (see renderScopeRows), and the popup is now sized to this
            -- exact text (popupMaxW measures pinRowText). Cutting the line here
            -- and widening the window for it would be two answers to one
            -- question -- and the truncated half was the trigger, which is the
            -- only thing distinguishing one pinned row from the next.
            if imgui.Selectable(pinRowText(e, byKey) .. '##unpin' .. i) then
                pins.clearPinAt(slot, i);
                pcall(function() imgui.CloseCurrentPopup(); end);
                return;
            end
            if imgui.IsItemHovered() then
                -- The tooltip gets the LONG spelling -- set name included --
                -- because there is no width to fight over in a tooltip.
                imgui.SetTooltip(fmt.esc(string.format(
                    'Remove THIS pin.\n\n%s\nApplies to: %s',
                    tostring(e.item), scopeTextOf(e, byKey, 'text'))));
                -- ...and the side panel gets the piece itself. By NAME, because a
                -- pin is stored as a name: the record is the catalog's answer to
                -- it, and nil (a pinned name with no record) simply shows nothing.
                _hoverRec = lookupName(e.item);
            end
        end
        if #held > 1 then
            if imgui.Selectable(string.format('Remove all %d pins on %s', #held, slot)) then
                pins.clearPin(slot);
                pcall(function() imgui.CloseCurrentPopup(); end);
                return;
            end
        end
        imgui.Separator();
    end

    -- Fallback drill-down: item chosen, now pick the scope in place. The panel
    -- follows the CHOSEN item here rather than the hover -- on this screen there
    -- is nothing else it could usefully be about.
    if not hasMenu and _drillItem ~= nil then
        _hoverRec = lookupName(_drillItem);
        imgui.TextColored(COL.HEADER, fmt.esc(_drillItem));
        imgui.TextColored(COL.DIM, 'Apply to which triggers?');
        imgui.Separator();
        if imgui.Selectable('< back') then _drillItem = nil; return; end
        renderScopeRows(slot, _drillItem, choices, false);
        return;
    end

    imgui.PushItemWidth(210);
    imgui.InputText('##pinsearch', _search, 64);
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then imgui.SetTooltip('Filter by name.'); end

    local q = string.lower(tostring(_search[1] or ''));
    local list = pool or candidatesFor(slot, job, level);
    -- NO BeginChild around this list, deliberately. A submenu is drawn OUTSIDE the
    -- rect of the window it is declared in; inside a child, moving the mouse from
    -- one item toward its submenu leaves the child, ImGui decides the menu
    -- hierarchy lost the cursor, and it tears down the WHOLE popup -- Henrik:
    -- "the whole initial right click menu disappears when you keep moving the
    -- mouse to the next gear piece". The popup itself is size-constrained instead
    -- (see the SetNextWindowSizeConstraints before BeginPopup), so a long list
    -- still scrolls without a child window in the menu chain.
    local shown, matched = 0, 0;
    for _, rec in ipairs(list) do
        local nm = tostring(rec.Name or '?');
        if q == '' or string.find(string.lower(nm), q, 1, true) ~= nil then
            matched = matched + 1;
            if shown < CAP then                -- a popup is not a browser
                shown = shown + 1;
                -- The icon, then the row on the same line (itemicons ends with
                -- its own SameLine). Drawn from the RECORD's id rather than by
                -- name -- no lookup, and it is the id the grid's own tooltip
                -- already uses. A menu row whose icon failed to load just starts
                -- where a text row would.
                if icons ~= nil and type(icons.renderIcon) == 'function' then
                    pcall(icons.renderIcon, rec.Id, ICON, rec);
                end
                -- raw nm, not fmt.esc: menu/selectable labels are not format
                -- strings (see renderScopeRows)
                if hasMenu then
                    -- BOUND THE CASCADE, so a job with thirty triggers gets a
                    -- scrollbar instead of a submenu taller than the screen.
                    --
                    -- The constraint, NOT a BeginChild around the scope rows: a
                    -- child window inside the menu chain is the thing that tore
                    -- the whole popup down (see the header), and a constraint is
                    -- the mechanism already used on the parent popup. It has to
                    -- be set before BeginMenu because BeginMenu is what Begins
                    -- the submenu window. Height only -- capping the width would
                    -- re-clip the very rows the compact spelling just fixed.
                    imgui.SetNextWindowSizeConstraints({ 0, 0 }, { 100000, SUB_MAX_H });
                    -- BeginMenu's RETURN is the hover signal, not IsItemHovered:
                    -- a submenu in a popup opens on hover and stays open while
                    -- you are inside it, so "this cascade is open" is exactly
                    -- "this is the item I am looking at" -- and it keeps the
                    -- facts up while you travel across to pick a trigger, which
                    -- a hover test on the parent row would drop the moment the
                    -- cursor left it.
                    if imgui.BeginMenu(nm .. '##pin' .. tostring(rec.Id)) then
                        _hoverRec = rec;
                        renderScopeRows(slot, nm, choices, true);
                        imgui.EndMenu();
                    end
                else
                    if imgui.Selectable(nm .. '##pin' .. tostring(rec.Id)) then
                        _drillItem = nm;
                    end
                    if imgui.IsItemHovered() then _hoverRec = rec; end
                end
            end
        end
    end
    -- NEUTRALISE the constraint no submenu consumed. Every closed BeginMenu above
    -- left one armed, and next-window data survives until the next Begin ANYWHERE
    -- -- including another addon's window (the note before BeginPopup says so).
    -- A max of 100000 x 100000 constrains nothing, so this is a clear, not a
    -- setting; ImGui offers no other way to take one back.
    if hasMenu then imgui.SetNextWindowSizeConstraints({ 0, 0 }, { 100000, 100000 }); end
    if #list == 0 then
        -- Distinct from "nothing MATCHES": the pool itself is empty, and after
        -- the bag gate above the likeliest reason is that the piece you have in
        -- mind is sitting somewhere the game cannot equip it from.
        imgui.TextColored(COL.DIM, 'Nothing in your bags fits this slot at this\njob and level. Gear in a Mog Safe, Locker or\nStorage is not offered -- move it first.');
    elseif matched == 0 then
        imgui.TextColored(COL.DIM, 'Nothing you can equip here matches.');
    elseif matched > shown then
        -- Say what was dropped. A silent truncation reads as "that's everything
        -- you own", and the piece you wanted is the one that isn't there.
        imgui.Separator();
        imgui.TextColored(COL.DIM, string.format('+%d more -- type to narrow.', matched - shown));
    end

    -- Unpin-all lives here rather than under the grid: the window is chrome-less
    -- now, and a stray line of text below it would put the box back. It clears
    -- EVERY slot -- the per-slot and per-trigger removals are up in the pinned
    -- list, so the three scopes of "clear" all have a home and none of them is
    -- reachable by accident from another one's row.
    local total, slots = pins.count(), pins.slotCount();
    if total > 0 then
        imgui.Separator();
        if imgui.Selectable(string.format('Remove all %d pins (%d slot%s)',
                total, slots, (slots == 1) and '' or 's')) then
            pins.clearAll();
            pcall(function() imgui.CloseCurrentPopup(); end);
        end
    end
end

-- --------------------------------------------------------------------------
-- The window.
-- --------------------------------------------------------------------------

local PIN_BOX  = { 0.55, 0.13, 0.13, 1.0 };   -- red:    pinned for ALL dispatches
-- Violet: pinned, but only on named triggers -- the slot dispatches normally the
-- rest of the time. Worth its own colour now that a slot can hold several pins:
-- red used to mean "this piece is stuck on", and a purely scoped pin does not
-- mean that. Deliberately far from the gold below, which is a MODE, not a state.
local PIN_COND = { 0.32, 0.20, 0.55, 1.0 };
local MOVE_BOX = { 0.62, 0.50, 0.16, 1.0 };   -- gold: Shift is down, drag to move

-- Rendered INDEPENDENTLY of the main dlac box (gearui's d3d_present calls this
-- directly, the lockstyle-window pattern) -- NOT via uihost's `window` contract.
-- That contract renders inside drawWindow, which returns early unless the main
-- window is open, and the whole point of this window is that it stays up while
-- you play. gearui owns the theme bracket around this call.
function M.render()
    if imgui == nil or ui._gearFloat ~= true then return; end
    local job, level = S.getPlayerInfo();
    S.buildAllEquip();          -- catalog indexes: the hover tooltip needs them,
                                -- and drawWindow (which normally does this every
                                -- frame) is not running when the main box is shut

    -- Once, not FirstUseEver (the TP float's choice): FirstUseEver defers to
    -- imgui.ini if ImGui remembered this window itself, and OUR uiflags copy is
    -- the one the addon maintains. Applies on the session's first frame, then the
    -- shift-drag below owns the position.
    if type(ui._gfPos) == 'table' then
        imgui.SetNextWindowPos({ ui._gfPos[1], ui._gfPos[2] }, ImGuiCond_Once or 0);
    end

    -- Chrome off (Henrik: "remove the actual box or hide the borders") -- no title
    -- bar, no border, no background: just the 16 boxes, equipmon-style.
    -- AlwaysAutoResize sizes the window to the tight grid, so there is no size to
    -- remember and none to get wrong.
    --
    -- NoMove is ALWAYS on and the window is moved by hand under Shift instead
    -- (equipmon's gesture). ImGui's own drag only moves a window from a spot no
    -- item claimed, and a 4x4 of ImageButtons leaves no such spot -- the old
    -- "drag it by the invisible rim" was the best that flag could do, and it was
    -- a bad answer. NoMove also stops the window sliding when you grab a slot.
    local shift = M.shiftHeld() or _moveMode;   -- shiftHeld is a seam: tests drive it
    local FL = (ImGuiWindowFlags_NoTitleBar or 0) + (ImGuiWindowFlags_NoResize or 0)
             + (ImGuiWindowFlags_NoScrollbar or 0) + (ImGuiWindowFlags_NoCollapse or 0)
             + (ImGuiWindowFlags_AlwaysAutoResize or 0) + (ImGuiWindowFlags_NoBackground or 0)
             + (ImGuiWindowFlags_NoMove or 0);
    -- Padding to 0 as well now that nothing needs a drag rim: the window is then
    -- EXACTLY the grid. Popped straight after Begin -- both vars are consumed
    -- there, and leaving them pushed would flatten the pin popup's own frame.
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });

    -- No title bar means no close button, so this table is never written back --
    -- but keep passing one (force-true each frame, the TP float's shape) rather
    -- than nil: this binding is fed a table everywhere else. The Equipped tab's
    -- checkbox is what closes the window.
    ui._gfOpenT = ui._gfOpenT or { true };
    ui._gfOpenT[1] = true;
    local shown = imgui.Begin('##dlac_float', ui._gfOpenT, FL);
    imgui.PopStyleVar(2);            -- WindowBorderSize + WindowPadding: consumed by
                                     -- Begin; the pin popup below must not inherit them
    if shown then
        -- Hover is read HERE, before the grid, because the box colours below need
        -- it. Safe: ImGui resolves the hovered window in NewFrame from the PREVIOUS
        -- frame's rects, so it does not matter that this frame's child has not been
        -- submitted yet.
        local overWin = imgui.IsWindowHovered(HOVER_FLAGS);

        -- The grab cue. Shift alone is NOT enough to light the grid: Shift is held
        -- constantly in normal play (running, macros), and lighting all 16 boxes
        -- every time was "yellow christmas lights" (Henrik). It shows only when
        -- Shift could ACTUALLY start a drag -- i.e. the cursor is over the window --
        -- or while a drag is live, or in move mode, which is a state you can get
        -- stuck in and must be able to see.
        --
        -- Deliberately the SAME expression as the click suppression below: what you
        -- see is exactly when the slots stop taking clicks. A cue that disagreed
        -- with the behaviour would be worse than none.
        local grab = _moveMode or _dragging or (shift and overWin);

        local box  = math.floor(BOX0 * scaleNow() + 0.5);
        local grid = box * 4;        -- tight: no spacing, no child padding
        S.renderSlotGrid('float', grid, nil,
            function(sl) return S.getEquippedId(sl.equip); end,
            function(sl)
                local id = S.getEquippedId(sl.equip);
                return fmt.truncate(id and (S.displayName(id) or ('#' .. tostring(id))) or '(empty)', 18);
            end,
            -- Left-click opens the menu too (RMB is the ask, LMB the guarantee) --
            -- but never while the grab cue is up: that click is a drag, and the
            -- button fires on RELEASE, by which time Shift may already be back up.
            -- `_dragging` inside `grab` is what covers that gap.
            function(labelKey) if not grab then _openFor = labelKey; end end,
            function(sl) return S.lookupById(S.getEquippedId(sl.equip)); end,
            grid,
            {
                tight = true,
                box   = box,
                -- Grab cue: the window has no frame, so the boxes are its only way
                -- to say "grabbable now". Same mechanism that paints a pinned slot
                -- red -- ImageButton's bg_col, field-proven here. (An earlier
                -- attempt drew a rect via GetWindowDrawList():AddRect with 6 args,
                -- a signature nothing else in dlac uses; inside its pcall it just
                -- drew nothing, and a silent indicator is worse than none -- it
                -- made a working key read look broken for three rounds.)
                boxColorOf = function(sl)
                    if grab then return MOVE_BOX; end
                    if pins.isPinned(sl.label) then
                        return pins.hasAllPin(sl.label) and PIN_BOX or PIN_COND;
                    end
                    return nil;
                end,
                -- RIGHT-click is never suppressed: the drag is a LEFT-button
                -- gesture, and in move mode the menu is the only way back OUT of
                -- move mode -- gating this too would strand you in it.
                onRightClick = function(labelKey) _openFor = labelKey; end,
            });

        -- Shift+drag anywhere on the grid moves the window. Done by hand because
        -- the ImageButton under the cursor owns the click, so ImGui would never
        -- move the window itself -- but the mouse state is global, so it reports
        -- the drag regardless of which item is active.
        --
        -- LATCHED: shift+press over the window starts it, and it then runs until
        -- the button comes up. Testing hover every frame instead would drop the
        -- drag the moment the cursor outran the window (or crossed the pin popup),
        -- and re-testing shift would drop it if you let the key go mid-drag --
        -- equipmon needs Shift only to START, and this matches.
        -- Starts on IsMouseDown, not IsMouseClicked: Clicked is true for exactly one
        -- frame, so any frame we miss (or a Shift pressed just after the button
        -- went down) loses the gesture entirely. Down is forgiving and the latch
        -- makes it idempotent.
        local LMB = ImGuiMouseButton_Left or 0;   -- overWin was read above the grid
        if not _dragging and shift and imgui.IsMouseDown(LMB) and overWin then
            _dragging = true;
            pcall(function() imgui.ResetMouseDragDelta(LMB); end);
        end
        if _dragging then
            if not imgui.IsMouseDown(LMB) then
                _dragging = false;
                ui._gfMovedAt = os.clock() + 1;      -- persist once the drag settles
            else
                pcall(function()
                    local dx, dy = imgui.GetMouseDragDelta(LMB);
                    if type(dx) == 'table' then dy = (dx[2] or dx.y); dx = (dx[1] or dx.x); end
                    if type(dx) == 'number' and type(dy) == 'number' and (dx ~= 0 or dy ~= 0) then
                        local wx, wy = imgui.GetWindowPos();
                        if type(wx) == 'table' then wy = (wx[2] or wx.y); wx = (wx[1] or wx.x); end
                        imgui.SetWindowPos({ wx + dx, wy + dy });
                        imgui.ResetMouseDragDelta(LMB);
                    end
                end);
            end
        end

        -- Popup at WINDOW scope: the grid detected the click inside its child,
        -- but OpenPopup/BeginPopup have to share a scope, so both happen here.
        if _openFor ~= nil then
            _menuSlot, _drillItem = _openFor, nil;
            _search[1] = '';
            _openFor = nil;
            imgui.OpenPopup(POPUP);
        end
        -- Constrain the POPUP instead of wrapping its list in a child window: a
        -- child in the menu chain is what killed the cascade (see renderPinMenu).
        -- BeginPopup forces AlwaysAutoResize on popups, so a constraint is the way
        -- to bound one -- clamped, it grows a scrollbar by itself.
        --
        -- The upper bound is MEASURED, not a constant (popupMaxW): a flat 380 let
        -- the item list grow freely -- names never reach it -- while clipping every
        -- pinned row, which is a name AND a trigger. Same frame, no lag: the rows
        -- are built here and handed to renderPinMenu, because the constraint has
        -- to be set BEFORE BeginPopup and a width taken from last frame's content
        -- would resize a frame late every time the list changed.
        --
        -- Only built when the menu is actually up. `_openFor` covers the opening
        -- frame (it becomes _menuSlot just above) and `_popupUp` covers every
        -- frame after, so a shut menu costs nothing.
        local choices, pool, maxW = nil, nil, MAX_W;
        if _menuSlot ~= nil and (_openFor ~= nil or _popupUp) then
            local okw = pcall(function()
                choices = triggerChoices();
                pool    = candidatesFor(_menuSlot, job, level);
                maxW    = popupMaxW(_menuSlot, choiceByKey(choices), pool);
            end);
            if not okw then choices, pool, maxW = nil, nil, MAX_W; end
        end
        -- Safe to call unconditionally even on the frames the popup is shut: this
        -- binding is ImGui >= 1.77 (the header declares ImGuiPopupFlags), and
        -- BeginPopup's early-out consumes the next-window data exactly as Begin
        -- would. Otherwise the constraint would leak onto the next window opened
        -- anywhere in the frame -- including another addon's.
        imgui.SetNextWindowSizeConstraints({ MIN_W, 0 }, { maxW, CAP_W });
        _popupUp = false;
        -- Cleared every frame, filled only by a menu that actually drew: the
        -- facts panel then cannot outlive the menu it belongs to, and there is
        -- no "close the panel" case to get wrong.
        _hoverRec, _popupRect = nil, nil;
        if imgui.BeginPopup(POPUP) then
            _popupUp = true;
            renderPinMenu(job, level, choices, pool);
            -- The popup's own rect, read from INSIDE it -- the only place ImGui
            -- will tell you. It is what the facts panel is placed against.
            pcall(function()
                local x, y = imgui.GetWindowPos();
                if type(x) == 'table' then y = (x[2] or x.y); x = (x[1] or x.x); end
                local w, h = imgui.GetWindowSize();
                if type(w) == 'table' then h = (w[2] or w.y); w = (w[1] or w.x); end
                if type(x) == 'number' and type(y) == 'number' and type(w) == 'number' then
                    _popupRect = { x, y, w, tonumber(h) or 0 };
                end
            end);
            imgui.EndPopup();
        end

        -- Remember where it was dragged, but save only once the drag SETTLES (the
        -- TP float's pattern): position changes every frame while you drag, and
        -- marking the flags dirty per frame would rewrite uiflags.lua ~60x/sec.
        pcall(function()
            local x, y = imgui.GetWindowPos();
            if type(x) == 'table' then y = (x[2] or x.y); x = (x[1] or x.x); end
            if type(x) == 'number' and type(y) == 'number' then
                x, y = math.floor(x), math.floor(y);
                local p = ui._gfPos;
                if type(p) ~= 'table' or p[1] ~= x or p[2] ~= y then
                    ui._gfPos = { x, y };
                    ui._gfMovedAt = os.clock() + 1;
                end
            end
        end);
    end
    -- NOTHING to pop here: both vars were already popped right after Begin (line
    -- above the grid). An extra PopStyleVar underflows ImGui's style stack, which
    -- is not a Lua error -- it is an EXCEPTION_ACCESS_VIOLATION in Present that
    -- takes the whole client down. Shipped exactly that in e85cc43 by adding the
    -- second push without removing this round's older pop. Count the pushes.
    imgui.End();
    -- The facts panel, AFTER this window closes rather than nested inside it.
    -- Nesting Begin/End is legal, but this window's End is the one guarded by
    -- the style-stack comment above and there is no reason to put another
    -- window's balance inside its scope.
    if _hoverRec ~= nil then renderFactsPanel(_hoverRec); end
    if ui._gfMovedAt ~= nil and os.clock() >= ui._gfMovedAt then
        ui._gfMovedAt = nil;
        ui._flagsDirty = true;
    end
end

M._triggerChoices = triggerChoices;   -- test seam
M.hasMenu = hasMenu;

-- Published so the Equipped tab's size slider can share this module's clamp
-- instead of keeping a second copy of the range. gearui requires equippedui
-- BEFORE floatgear, so the tab must read host.services.floatgear at CALL time
-- (it does) rather than capture it at load.
host.provide({ floatgear = M });

return M;
