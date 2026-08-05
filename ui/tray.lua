--[[
    dlac/ui/tray.lua

    The ONE floating icon tray (Henrik, 2026-08-03). The Teleports button and the
    E-Box Restock crates used to be two separate always-on-screen windows, each
    with its own Begin/End and its own remembered position -- two little boxes
    scattered across the same screen, doing the same kind of job. This is the
    hobby-bar move (ADR 0017) applied to the floats: ONE window supplies the
    chrome and the position, and each member draws its icons INLINE.

    That they belonged together was already written down before this file existed:
    restockui sized its crate to 30px art + 3px pad specifically to match gearui's
    TPF_ICON / TPF_PAD, with a comment warning that the two must be changed
    together "or they drift". Two windows enforcing a shared size by comment is
    exactly the drift this removes.

    THE SLOT CONTRACT. A member answers two questions:

        trayWants(deps) -> boolean   a CHEAP gate: "have I anything on screen
                                     right now?" -- no bag scans, no planning.
        trayDraw(deps)               draws its icon(s) inline. No Begin, no End,
                                     no SetNextWindowPos, and NO SameLine between
                                     icons -- see the axis note below.

    Two phases, and the order matters: EVERY member is asked before ANYTHING is
    drawn, because if none of them wants the screen we must not Begin at all. An
    empty AlwaysAutoResize window is not nothing -- it is a little grey box that
    sits there and takes clicks.

    THE AXIS: TOP TO BOTTOM (Henrik, 2026-08-03). The tray grows DOWNWARD -- one
    column, one icon per line, nothing here calls SameLine. AlwaysAutoResize keeps
    the window's top-left pinned and grows it down and right, so a column keeps
    the whole tray hanging off the spot you dragged it to instead of creeping
    sideways across the screen as icons appear.

    ORDER = CONSTANT MEMBERS FIRST (Henrik's ruling). SLOTS below reads
    top-to-bottom, and the volatile icons go at the BOTTOM so that the ones you
    click by muscle memory never move under your cursor. This matters concretely:
    Store is one click, no confirm, and deposits your whole Inventory, while the
    green crate comes and goes with "Only when needed" -- so any order that put
    green above Store would slide Store under a cursor aimed at a fetch.

    APPEARANCE IS STILL EACH MEMBER'S OWN BUSINESS. Nothing here decides when an
    icon shows: Teleports appears because you pinned it, the crates appear
    because you are standing near a box with something worth fetching. The tray
    just stops asking for a window once every member has gone quiet, so an empty
    tray is no tray -- exactly how the E-Box float behaved on its own.

    POSITION: ui._tpPos (tpx/tpy in uiflags) -- the Teleports float's own saved
    spot, inherited deliberately. The tray takes ONE position, so one of the two
    floats had to move on first run; this way the button you pinned stays where
    you put it and the crates come to IT.

    NO SetNextWindowSize. AlwaysAutoResize sizes this window to whatever its
    members drew, and a zero-component size request would re-arm ImGui's
    AutoFitFrames every frame -- the collapse law in hobbybar.render.
]]--

local host = require('dlac\\ui\\uihost');

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');

local M = {};

-- TOP TO BOTTOM. The Teleports button first (it is pinned, so it is there or it
-- is not -- it never flickers with what you are standing next to), then the
-- E-Box crates, whose own first icon is the anchored Store.
--
-- Members are named, not registered: a tray slot is a deliberate decision about
-- what may live permanently on a player's screen, and the list of those is worth
-- being able to read in one place.
local SLOTS = {
    { mod = 'dlac\\ui\\gearui',    wants = 'trayTeleportsWants', draw = 'trayTeleportsDraw' },
    { mod = 'dlac\\ui\\restockui', wants = 'trayWants',          draw = 'trayDraw'          },
    -- Giftboxes LAST (Henrik, 2026-08-05: "under the e-box stocker icons"), and
    -- the ORDER ruling above says the same thing independently: this is the most
    -- volatile member in the tray -- it comes and goes with what is in your bag
    -- -- and the crate above it is Store, one click and no confirm. Anything
    -- that could slide Store under a cursor is the arrangement to avoid.
    { mod = 'dlac\\ui\\giftboxui', wants = 'trayWants',          draw = 'trayDraw'          },
};
M.SLOTS = SLOTS;   -- test seam: the ORDER is the ruling, so it is assertable

-- Vertical breathing room between two SLOTS -- the pinned button and the crates
-- are different kinds of thing and should not read as one block. Within a slot,
-- consecutive icons take ImGui's default ItemSpacing, as the crates always did.
local SLOTGAP = 4;

-- NoFocusOnAppearing comes from the E-Box nudge: this window can appear on its
-- own while you are playing (walk up to a box) and must not steal the keyboard
-- when it does. NoNav is deliberately NOT inherited -- the Teleports popup opens
-- from in here, and the float it came from never carried it.
local FL = (ImGuiWindowFlags_NoTitleBar or 0) + (ImGuiWindowFlags_AlwaysAutoResize or 0)
         + (ImGuiWindowFlags_NoScrollbar or 0) + (ImGuiWindowFlags_NoCollapse or 0)
         + (ImGuiWindowFlags_NoFocusOnAppearing or 0);

local _open = { true };   -- forced-true (floatgear's shape); no title bar = no close

function M.render(deps)
    if imgui == nil then return; end
    local ui = host.services and host.services.ui;
    if ui == nil then return; end

    -- PHASE 1 -- ask everyone, draw nobody. A member that errors in its gate is
    -- simply absent this frame; one broken slot must not cost the others their
    -- window (and must not take down the d3d_present handler).
    local live = {};
    for _, s in ipairs(SLOTS) do
        local mod = try(s.mod);
        local ask = (mod ~= nil) and mod[s.wants] or nil;
        if type(ask) == 'function' and type(mod[s.draw]) == 'function' then
            local ok, yes = pcall(ask, deps);
            if ok and yes == true then live[#live + 1] = mod[s.draw]; end
        end
    end
    if #live == 0 then return; end   -- nothing needed -> no window at all

    if type(ui._tpPos) == 'table' then
        imgui.SetNextWindowPos({ ui._tpPos[1], ui._tpPos[2] }, ImGuiCond_Once or 0);
    else
        -- Never pinned, never dragged: the E-Box nudge's old first-run corner.
        imgui.SetNextWindowPos({ 300, 300 }, ImGuiCond_FirstUseEver or 0);
    end

    _open[1] = true;
    if imgui.Begin('##dlac_tray', _open, FL) then
        for i, draw in ipairs(live) do
            if i > 1 then imgui.Dummy({ 0, SLOTGAP }); end   -- a COLUMN: never SameLine
            pcall(draw, deps);
        end

        -- Remember where it was dragged; save once the drag settles (the TP
        -- float's own logic, moved up here with the window it belongs to).
        local px, py = imgui.GetWindowPos();
        if type(px) == 'table' then py = (px[2] or px.y); px = (px[1] or px.x); end
        if type(px) == 'number' and type(py) == 'number' then
            px, py = math.floor(px), math.floor(py);
            if ui._tpPos == nil or ui._tpPos[1] ~= px or ui._tpPos[2] ~= py then
                ui._tpPos = { px, py };
                ui._tpMovedAt = os.clock() + 1;
            end
        end
    end
    imgui.End();
    if ui._tpMovedAt ~= nil and os.clock() >= ui._tpMovedAt then
        ui._tpMovedAt = nil;
        ui._flagsDirty = true;
    end
end

host.provide({ tray = M });
return M;
