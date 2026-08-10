--[[
    dlac/ui/giftboxui.lua -- the reward-box icon in the ONE floating tray.

    A tray member (ui\tray.lua -- read its header for the slot contract): it
    appears when there are openable boxes in your inventory -- whatever
    feature\giftbox's six families cover -- AND you are somewhere it is worth
    opening them (see placeOK: at an E-Box as a Crystal Warrior, in town as
    anyone else). Clicking it opens them, the same run as /dl giftbox. Henrik,
    2026-08-05: "if any giftboxes are detected, add this icon in the floating
    menu under the e-box stocker icons."

    The COMMAND is not gated by any of this and never has been. `/dl giftbox`
    works wherever you are; the place rule only decides when the icon is worth
    the screen space.

    UNDER the crates, which is also where the tray's own ORDER ruling puts it:
    constant members first, volatile ones at the bottom, so the icons you click
    by muscle memory never move under the cursor. Boxes come and go with
    your bag -- easily the most volatile thing in the tray -- and the crate above
    it is Store, one click and no confirm. Anything that could slide Store under
    a cursor is the one arrangement that must not happen.

    NO NEW ART. The button draws the BOX'S OWN in-game icon through
    itemicons.handleOf, so it is the same picture the item has in your inventory
    -- and it stays right if CatsEyeXI ever adds a box we have never heard of,
    because we render whatever we found rather than a PNG we shipped.
]]--

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');
local gb    = try('dlac\\feature\\giftbox');
local icons = try('dlac\\ui\\itemicons');
local gmode = try('dlac\\feature\\gamemode');
local loc   = try('dlac\\feature\\location');
local ec    = try('dlac\\feature\\eboxclient');

local M = {};

-- Matches the crates and the Teleports button exactly: 30px of art in a 3px
-- frame = 36x36. The comment on restockui's NUDGE_SZ is the law here -- these
-- three live in one column and a mismatch reads as a mistake. Change together.
local ICON_SZ  = 30;
local ICON_PAD = 3;

-- WHERE the icon is allowed to appear. It shipped Crystal-Warriors-only, which
-- Henrik replaced the next day (2026-08-06): *"For non-CW, you can have that
-- icon once you're in town. CW is only interested in using this close to an
-- e-box."*
--
-- So it is not a mode gate any more -- it is a PLACE gate that asks the mode
-- which place. The reason the two differ is what you do straight after opening
-- a box: a Crystal Warrior wants the payout going into the Ephemeral Box he is
-- standing at, so the icon belongs where that box is and nowhere else. Everyone
-- else has no box to stand at, so the useful moment is arriving in town with a
-- full bag -- the same moment the E-Box crates were built around.
--
-- UCW answers 'CW' by design (Henrik's ruling: same playmode).
--
-- AN UNREADABLE MODE FALLS TO THE TOWN RULE, which reverses the old comment
-- here, and deliberately. The affirmative gate ("unknown is not permission")
-- existed because this was a CW-ONLY icon and a failed render-flags read must
-- not paint one onto a non-CW screen. Both modes get the icon now, so that risk
-- is gone and the only question left is which of two conditions to apply --
-- where the strict answer silently costs a non-CW player the feature and the
-- general one costs a Crystal Warrior an extra icon while he stands in town.
-- A tray icon is not a click; take the harmless failure.
local function mode()
    if gmode == nil or type(gmode.get) ~= 'function' then return nil; end
    local ok, m = pcall(gmode.get);
    return ok and m or nil;
end

local function placeOK()
    if mode() == 'CW' then
        if ec == nil or type(ec.nearBox) ~= 'function' then return false; end
        local ok, near = pcall(ec.nearBox);
        return ok and near == true;
    end
    if loc == nil or type(loc.inTown) ~= 'function' then return false; end
    local ok, town = pcall(loc.inTown);
    -- `== true` and not truthiness: inTown answers nil for an unreadable zone,
    -- and mid-zone is not a town (location.lua's own rule -- never guess).
    return ok and town == true;
end

-- THE CHEAP GATE. Reads feature\giftbox's throttled snapshot, never the bag:
-- the scan behind it runs at most every SCAN_EVERY seconds (see the note on
-- that constant for why this is inside the contract rather than a breach of it).
--
-- PLACE IS ASKED FIRST, and that ordering is the whole reason the gate is cheap:
-- a render-flags read plus either one party-memory word (the zone) or one
-- entwatch lookup the E-Box crates are already paying for every frame. Nobody
-- out in the field pays for the bag scan -- not even the throttled one -- which
-- is a wider saving than the old CW-only test made.
function M.trayWants()
    if gb == nil or not placeOK() then return false; end
    local ok, p = pcall(gb.peek);
    return ok and type(p) == 'table' and p.have == true;
end

function M.trayDraw()
    -- Re-checked here, belt-and-braces, exactly as restockui re-checks its own
    -- gate: the tray asks trayWants and then calls this, and the two must not
    -- be able to disagree if a caller ever draws without asking.
    if imgui == nil or gb == nil or not placeOK() then return; end
    local ok, p = pcall(gb.peek);
    if not ok or type(p) ~= 'table' or not p.have then return; end

    local running = false;
    pcall(function() running = gb.running() == true; end);
    local roomy = (p.free >= gb.NEED_FREE);

    local clicked = false;
    imgui.PushID('dlac_giftbox_tray');
    local h = (icons ~= nil and p.top ~= nil and type(icons.handleOf) == 'function')
        and icons.handleOf(p.top.id) or nil;
    -- Dimmed while there is no room: the icon still SHOWS (you have boxes, that
    -- is the fact it reports) but it reads as not-now, and the tooltip says how
    -- many slots you are short. Hiding it instead would answer "why is my
    -- box icon gone" with silence.
    local tint = roomy and { 1, 1, 1, 1 } or { 1, 1, 1, 0.45 };
    if h ~= nil then
        -- Explicit frame padding for the same reason restockui passes it: left
        -- off, ImageButton takes the style's (4,3) and the button comes out
        -- 48x46 -- visibly bigger than the crate directly above it.
        pcall(function()
            clicked = imgui.ImageButton(h, { ICON_SZ, ICON_SZ }, { 0, 0 }, { 1, 1 },
                ICON_PAD, { 0, 0, 0, 0 }, tint);
        end);
    else
        -- The item texture failed to load (or we have no id yet). Same 36 tall
        -- so a missing icon never changes the column's layout; width per the
        -- themed-font law, ~9.5px/char + 16.
        local label = 'Boxes';
        clicked = imgui.Button(label, { math.floor(#label * 9.5) + 16, ICON_SZ + ICON_PAD * 2 });
    end
    local hovered = imgui.IsItemHovered();
    imgui.PopID();

    if hovered then
        local tip;
        if running then
            tip = 'Opening boxes now.\nType /dl giftbox stop to halt.';
        elseif not roomy then
            tip = string.format('%d box%s -- NOT ENOUGH ROOM.\n\n'
                .. 'Each box pays out up to 5 items, so %d free inventory slots\n'
                .. 'are needed and you have %d. Free %d more and click.',
                p.total, (p.total == 1) and '' or 'es',
                gb.NEED_FREE, p.free, gb.NEED_FREE - p.free);
        else
            tip = string.format('%d box%s in your inventory (%d free slots).\n\n'
                .. 'Click to open them all, one at a time. It stops by itself\n'
                .. 'the moment there is no room for the next payout.',
                p.total, (p.total == 1) and '' or 'es', p.free);
        end
        pcall(function() imgui.SetTooltip(tip); end);
    end

    -- One door: the click issues the command rather than calling M.start(), so
    -- the icon and the typed command can never drift into two behaviours.
    if clicked then
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl giftbox'); end);
    end
end

return M;
