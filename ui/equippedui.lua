--[[
    dlac/equippedui.lua

    The Equipped + All Equipment tabs, extracted from gearui (the LuaJIT
    200-local chunk cap; every tab is a uihost module now). Registers both tabs
    on require via uihost; gearui host.provide{}s the shared services FIRST
    (candidate pools, lookups, slot grid, stats panel, shared ui state table),
    so the captures below are safe at load time.

    Shared state: S.ui is gearui's live view-state table (persisted by its
    ui-flags writer) -- this module reads/writes the same fields the tab always
    used (eqSelected, altSearch, freeEquip, lockEquipped, search, slot, ...).
]]--

local host  = require("dlac\\ui\\uihost");
local icons = require("dlac\\ui\\itemicons");
local fmt   = require("dlac\\gear\\gearfmt");
local cmdq  = require("dlac\\lib\\cmdqueue");
local owned = require("dlac\\gear\\ownedcache");

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui    = try('imgui');
-- Worn private-augment display goes through the Gear Oracle now (issue #74, PRD
-- #69): this module asks gearOracle.wornAugExtra/describeAugments and never
-- requires the augment decoder itself (the GRD5 rule is absolute since #74).
local gearOracle = require("dlac\\gear\\gearoracle");
local statdefs = try("dlac\\data\\statdefs");
local uistyle  = try("dlac\\ui\\uistyle");   -- helpLabel: underline + hover, the panel-text standard

-- The Wishlist owns the item context-menu BODY (so the same rows can hang off
-- other surfaces later); this module owns only the right-click detection and the
-- popup scope. Required through try(): a missing/broken wishlistui must cost the
-- menu, never the tab.
local wishui = try("dlac\\ui\\wishlistui");
-- The job selector (ui\jobbrowse). Required directly rather than threaded
-- through the services table: it is a leaf module with no gearui dependency, and
-- only ONE of these two tabs consults it. The Equipped tab refuses to draw while
-- browsing (see its head); All Equipment follows the picker like every other
-- editing surface -- its "usable now" filter IS the "what can this job wear"
-- view, and its right-click menu is wishlist-only, so it cannot touch your gear.
local jbrowse = try("dlac\\ui\\jobbrowse");
local ITEM_MENU = '##dlac_itemmenu';

local S = host.services;
-- Stable shared tables/constants, captured once (gearui provides before it
-- requires this module; registration below refuses to run if they're absent).
local ui, COL = S.ui, S.COL;
local EQUIP_SLOTS, GEAR_OF = S.EQUIP_SLOTS, S.GEAR_OF;
local SLOT_ORDER, SLOT_TREE_ORDER, CAT_ORDER = S.SLOT_ORDER, S.SLOT_TREE_ORDER, S.CAT_ORDER;
local STATS_W = S.STATS_W or 250;

local function calcTextW(s)
    local ok, w = pcall(imgui.CalcTextSize, tostring(s or ''));
    if ok and type(w) == 'number' then return w; end
    return #tostring(s or '') * 7;
end

-- Alternatives row (Equipped tab): icon + selectable + static columns. Returns
-- true when clicked. Hovering feeds the compare panel (drawn above the list).
local function renderAltRow(rec, ordinal, job, level, nameW)
    icons.renderIcon(rec.Id, 18);
    local clicked = imgui.Selectable('##altsel_' .. ordinal, false);
    if imgui.IsItemHovered() then
        -- Feed the compare panel (drawn above the list; it reads last frame's
        -- hover) instead of a tooltip -- the card shows the same info without
        -- covering the list.
        ui._cmpHover = rec;
        ui._cmpFrame = cmdq.frame();
    end
    local nameCol = 26;                                -- just after the icon
    imgui.SameLine(nameCol);
    imgui.TextColored(owned.isStored(rec) and COL.ERR or COL.USABLE, fmt.esc(rec.Name or '?'));
    imgui.SameLine(nameCol + (nameW or 200));
    imgui.TextColored(COL.LEVEL, string.format('Lv%2d', rec.Level or 0));
    local ss = fmt.statSummary(rec, level);
    if ss ~= '' then
        imgui.SameLine(nameCol + (nameW or 200) + 46);
        imgui.TextColored(COL.STATS, fmt.esc(ss));
    end
    local q = fmt.qtyTag(rec);
    if q ~= '' then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL.DIM, q);
    end
    local at = fmt.augTag(rec);                        -- your copy's augments, gold
    if at ~= '' then
        imgui.SameLine(0, 10);
        imgui.TextColored(COL.SCORE, fmt.esc(at));
    end
    return clicked;
end

-- Browse row (All Equipment tree): icon + Name + Level + stats in STATIC COLUMNS --
-- nameW is computed per group from the longest name so every row in a section
-- aligns. Alternating bg, whole-row hover tooltip; job list lives in the tooltip.
--
-- Right-click reports through `onRight` (the renderSlotGrid contract): the row
-- can only SAY it was right-clicked, because OpenPopup and BeginPopup must share
-- a window scope and this row is drawn inside the tree's BeginChild. The tab
-- opens the popup after EndChild. IsMouseClicked(1) + IsItemHovered, never
-- BeginPopupContextItem -- that one is the twice-failed dead end.
local function renderBrowseRow(rec, ordinal, job, level, nameW, onRight)
    local bg = (ordinal % 2 == 0) and { 1, 1, 1, 0.03 } or { 1, 1, 1, 0.07 };
    imgui.PushStyleColor(ImGuiCol_ChildBg, bg);
    -- AugKey joins the id: augment-split rolls share an Id, and two rows under
    -- one imgui id leave the second one dead to clicks.
    imgui.BeginChild('##aeqrow_' .. tostring(rec.Id or ('n' .. ordinal)) .. (rec.AugKey or ''), { -1, 22 }, false);
    icons.renderIcon(rec.Id, 18);
    local usable = S.isUsable(rec, job, level);
    -- stored beats locked beats ok -- the precedence lives in ownedcache.verdict
    -- (tests AV*); this panel only maps states onto its palette.
    --
    -- UNOWNED sits ABOVE all three (Henrik's call): not having a piece at all is
    -- the more basic fact than which bag it is in or whether this job could wear
    -- it, and the job gate is spelled out in the hover anyway. haveInBags fails
    -- OPEN, so pre-login (empty bag map) nothing is painted unowned.
    -- Greyed out since 2026-08-04 (was orange) -- the one unowned shade dlac uses,
    -- see COL.UNOWN in gearui. The hover says it in words too.
    local mine = owned.haveInBags(rec);
    local nameColr;
    if not mine then
        nameColr = COL.UNOWN;
    else
        local v = owned.verdict(rec, usable);
        nameColr = (v == 'stored' and COL.ERR) or (v == 'locked' and COL.LOCKED) or COL.USABLE;
    end
    imgui.TextColored(nameColr, fmt.esc(rec.Name or '?'));
    local nameCol = 26 + (nameW or 200);               -- icon (18+6 pad) + name column
    imgui.SameLine(nameCol);
    imgui.TextColored(COL.LEVEL, string.format('Lv%2d', rec.Level or 0));
    local ss = fmt.statSummary(rec, level);
    if ss ~= '' then
        imgui.SameLine(nameCol + 46);                  -- fixed Lv column
        imgui.TextColored(COL.STATS, fmt.esc(ss));
    end
    local at = fmt.augTag(rec);                        -- augments on your owned copy
    if at ~= '' then
        imgui.SameLine(0, 10);
        imgui.TextColored(COL.SCORE, fmt.esc(at));
    end
    imgui.EndChild();
    imgui.PopStyleColor(1);
    if imgui.IsItemHovered() then
        if onRight ~= nil and imgui.IsMouseClicked(1) then onRight(rec); end
        S.renderItemTooltip(rec);
    end
end

-- One item card: icon + name / [Slot] tag / stats / augments / Lv+jobs. STATIC,
-- generous height (matches the slot grid) so hovering different items never
-- moves the layout -- overly long content clips inside the card instead. The
-- jobs line wraps only at '/' boundaries (imgui would break mid job name:
-- 'WAR/MNK/DR' + 'G/WHM').
local CARD_H = 182;
local function renderItemCard(rec, level, w, tag)
    local innerW = w - 18;
    local ss = fmt.statSummary(rec, level);
    local augText = nil;
    if type(rec.AugText) == 'string' and rec.AugText ~= '' then
        augText = 'Aug: ' .. rec.AugText;              -- augment-split roll: exactly this copy
    elseif rec.Id ~= nil then
        local al = S.ownedAugMap()[rec.Id];
        if al ~= nil and #al > 0 then
            augText = 'Aug: ' .. al[1] .. ((#al > 1) and string.format(' (+%d)', #al - 1) or '');
        end
    end
    local jt = fmt.jobsText(rec.Jobs);
    if jt == 'All' then jt = 'All Jobs'; end
    imgui.BeginChild('##card_' .. tostring(tag or '') .. '_' .. tostring(rec.Id or rec.Name or '?'),
        { w, CARD_H }, true, ImGuiWindowFlags_NoScrollbar or 0);
    icons.renderIcon(rec.Id, 18);
    fmt.textWrapped(owned.isStored(rec) and COL.ERR or COL.USABLE, fmt.esc(tostring(rec.Name or '?')));
    imgui.TextColored(COL.DIM, '[' .. tostring(ui.eqSelected or rec.Slot or '?') .. ']'
        .. ((tag ~= nil) and ('  ' .. tag) or ''));
    if ss ~= '' then fmt.textWrapped(COL.STATS, fmt.esc(ss)); end
    if augText ~= nil then fmt.textWrapped(COL.SCORE, fmt.esc(augText)); end
    -- 'Lv.73  WHM/BLM/' -- continuation lines break at job boundaries only.
    do
        local cur = string.format('Lv.%d  ', rec.Level or 0);
        local toks = {};
        for tok in string.gmatch(tostring(jt), '[^/]+') do toks[#toks + 1] = tok; end
        for ti, tok in ipairs(toks) do
            local piece = tok .. ((ti < #toks) and '/' or '');
            if cur ~= '' and calcTextW(cur .. piece) > innerW then
                imgui.TextColored(COL.JOBS, fmt.esc(cur));
                cur = piece;
            else
                cur = cur .. piece;
            end
        end
        if cur ~= '' then imgui.TextColored(COL.JOBS, fmt.esc(cur)); end
    end
    imgui.EndChild();
end

-- Stat wins/losses of `cand` vs `eq` at `level`: green = improvement, red = loss
-- (lowerBetter stats from statdefs flip the coloring). Flows and wraps by width.
local function renderStatDelta(eq, cand, level)
    local a = S.effStats(eq, level) or {};
    local b = S.effStats(cand, level) or {};
    local keys, seen = {}, {};
    for k in pairs(a) do if not seen[k] then seen[k] = true; keys[#keys + 1] = k; end end
    for k in pairs(b) do if not seen[k] then seen[k] = true; keys[#keys + 1] = k; end end
    table.sort(keys);
    local avail = imgui.GetContentRegionAvail();
    if type(avail) ~= 'number' or avail < 120 then avail = 400; end
    local any, x = false, 0;
    for _, k in ipairs(keys) do
        local d = (tonumber(b[k]) or 0) - (tonumber(a[k]) or 0);
        if d ~= 0 then
            local lower = false;
            if statdefs ~= nil and type(statdefs.get) == 'function' then
                local e = statdefs.get(k);
                lower = (e ~= nil and e.lowerBetter == true);
            end
            local good = (d > 0) ~= lower;
            local txt = string.format('%+d %s', d, k);
            local tw = calcTextW(txt) + 14;
            if any and x > 0 and (x + tw) <= avail then imgui.SameLine(0, 14); else x = 0; end
            imgui.TextColored(good and { 0.45, 0.90, 0.45, 1.0 } or { 0.95, 0.45, 0.40, 1.0 }, txt);
            x = x + tw;
            any = true;
        end
    end
    if not any then imgui.TextColored(COL.DIM, 'No stat changes.'); end
end

-- Right of the slot grid: the equipped item's card; hovering an alternative below
-- puts its card beside it, with the stat delta underneath -- compare before you
-- switch. The hover is captured by the list (drawn later), so we read last frame's.
local function renderComparePanel(level)
    imgui.BeginGroup();
    local hov = ui._cmpHover;
    if hov ~= nil and (cmdq.frame() - (ui._cmpFrame or 0)) > 2 then
        hov = nil; ui._cmpHover = nil;                 -- hover ended
    end
    if ui.eqSelected == nil then
        imgui.TextColored(COL.DIM, 'Select a slot to inspect and compare gear.');
    else
        local slDef;
        for _, s in ipairs(EQUIP_SLOTS) do if s.label == ui.eqSelected then slDef = s; break; end end
        local eqRec = slDef and S.lookupById(S.getEquippedId(slDef.equip)) or nil;
        -- Adaptive width: split what's actually left of the window between the
        -- two cards; when that would be too narrow, stack them instead.
        local avail = imgui.GetContentRegionAvail();
        if type(avail) ~= 'number' or avail < 200 then avail = 620; end
        local cardW = math.floor((avail - 16) / 2);
        local twoCol = (cardW >= 260);
        if not twoCol then cardW = math.floor(avail - 4); end
        cardW = math.min(math.max(cardW, 280), 360);   -- generous, near-static band
        if eqRec ~= nil then
            renderItemCard(eqRec, level, cardW, 'equipped');
        else
            imgui.TextColored(COL.DIM, '(nothing equipped in ' .. ui.eqSelected .. ')');
        end
        if hov ~= nil and hov ~= eqRec then
            if eqRec ~= nil and twoCol then imgui.SameLine(0, 12); end
            renderItemCard(hov, level, cardW, 'hovering');
            imgui.Spacing();
            renderStatDelta(eqRec, hov, level);
        elseif eqRec ~= nil then
            imgui.TextColored(COL.DIM, 'Hover an alternative below to compare.');
        end
    end
    imgui.EndGroup();
end

-- ---------------------------------------------------------------------------
-- Tab: Equipped
-- ---------------------------------------------------------------------------
local function renderEquippedTab(job, level)
    -- BROWSING ANOTHER JOB (2026-08-06). This tab is a picture of YOUR BODY --
    -- what you are wearing, plus per-slot alternatives that EQUIP ON CLICK. There
    -- is no honest version of it for a job you are not on, and the guessed
    -- version ("what the engine would put on you as WAR") would be inference over
    -- facts we do not have: what the Arbiter would actually rule, and what is in
    -- your bags at the time. Henrik, 2026-08-06: "can't view live equipment
    -- either way on a job you're not on."
    --
    -- The tab stays SUBMITTED to the bar rather than being dropped from it. If it
    -- happens to be the selected tab when the picker moves, removing it makes
    -- ImGui reassign the selection -- and this build's tab-selection flag does not
    -- work, so putting it back costs the whole bar-regeneration machinery
    -- (uihost's beginForced comment block). A greyed-out tab is not worth that.
    if jbrowse ~= nil and jbrowse.active() then
        local live = jbrowse.liveJob();
        imgui.Spacing();
        imgui.TextColored(COL.WANT, 'Not available while browsing ' .. tostring(jbrowse.selected())
            .. ' -- you are on ' .. (live or 'no job') .. '.');
        imgui.TextColored(COL.DIM, 'This tab shows what you are WEARING. There is nothing to show for a job you');
        imgui.TextColored(COL.DIM, 'are not on, and dlac will not guess it.');
        imgui.Spacing();
        if live ~= nil and imgui.Button('Back to ' .. live .. '##dlac_eqbackjob', { 0, 24 }) then
            jbrowse.clear();
        end
        return;
    end
    imgui.TextColored(COL.DIM, 'Hover a slot for details; click for alternatives.');
    imgui.SameLine();
    if imgui.Button((ui.showStats and 'Stats v' or 'Stats >') .. '##eqstats', { 76, 0 }) then
        ui.showStats = not ui.showStats;
    end

    -- FREE EQUIP (ADR 0024). This used to fire /lac disable, which under the
    -- native engine talks to a LuaAshitacast that is no longer doing the
    -- equipping -- the switch that says "stop auto-swapping my gear" did nothing
    -- at all in the mode we ship. It now drives dlac's own ceiling
    -- (/dl disable all), which works identically in both engines.
    --
    -- The ENGINE owns the state, so the box is drawn from the mirror rather than
    -- from a remembered addon-side flag: /dl disable from chat, and the job-change
    -- / logout release, both have to move this checkbox. That is also why the old
    -- ui._freePrev edge-detect is gone -- Checkbox's return value IS the edge, and
    -- a remembered previous value is exactly what goes stale when the engine
    -- drops the state on its own.
    imgui.SameLine(0, 12);
    local dzMap = (S.engineDisabled ~= nil) and S.engineDisabled() or {};
    local nDis = 0;
    for _, v in pairs(dzMap) do if v == true then nDis = nDis + 1; end end
    local fe = { nDis > 0 };
    if imgui.Checkbox('Free equip', fe) and S.setEngineFreeEquip ~= nil then
        S.setEngineFreeEquip(fe[1]);
        if not fe[1] then                              -- leaving free-equip clears engine locks too
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl lock all off'); end);
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Hands all 16 slots back to you: dlac writes nothing to them -- no equip, no\n'
            .. 'unequip -- so what you put on stays on. Triggers, pins, automations, a locked\n'
            .. 'set and even Naked all stop here; it is the one thing nothing outranks.\n\n'
            .. 'While on, clicking an alternative equips via the game\'s native /equip.\n'
            .. 'Also /dl disable <slot> for a single slot. Uncheck to hand control back.');
    end
    -- Keep the shared flag in step for the equip path below (a free-equip click
    -- goes out as the game's native /equip, not /lac equip).
    ui.freeEquip[1] = fe[1];
    if fe[1] then
        imgui.SameLine(0, 10);
        imgui.TextColored(COL.ERR, (nDis >= 16) and 'FREE EQUIP -- dlac is off your gear'
            or string.format('FREE EQUIP -- %d slot(s) are yours', nDis));
    end

    -- Naked (ADR 0021). Deliberately next to Free equip: the two read alike and
    -- one BEATS the other. That used to be an accident of LuaAshitacast (its
    -- PrepareEquip refuses to unequip a Disabled slot, so the strip landed
    -- nothing and said nothing, in LAC mode only); since ADR 0024 it is the
    -- stated rule in both engines -- the ceiling outranks the strip. The checkbox
    -- is drawn unavailable rather than clickable-and-inert.
    if S.engineNaked ~= nil then
        imgui.SameLine(0, 12);
        local blocked = (nDis >= 16);
        local nk = { S.engineNaked() == true };
        if blocked then
            imgui.TextColored(COL.DIM, 'Naked');
        elseif imgui.Checkbox('Naked##eqnaked', nk) then
            S.setEngineNaked(nk[1]);
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(blocked and
                ('Unavailable while Free equip owns all 16 slots: dlac cannot unequip a slot it\n'
              .. 'has been told not to touch, so stripping would silently do nothing.\n'
              .. 'Uncheck Free equip first.')
             or ('Takes EVERY piece off and keeps it off -- a standing claim, not a one-off strip,\n'
              .. 'so your triggers and every gear rule ranked below it stay off your gear.\n'
              .. 'It sits at the top of Gear Helpers > Claim Priority and beats everything, pins\n'
              .. 'included; drag Pins above it there to stay naked EXCEPT your pinned pieces.\n\n'
              .. 'Taking a weapon off zeroes your TP and drops Aftermath -- that is the server.\n'
              .. 'Getting dressed brings back what your sets NAME; anything you had put on by\n'
              .. 'hand you re-equip yourself.\n\n'
              .. 'Release: uncheck this, /dl dress, or /dl reload. Also /dl naked.'));
        end
        if nk[1] and not blocked then
            imgui.SameLine(0, 10);
            imgui.TextColored(COL.ERR, 'NAKED -- all slots held empty');
        end
    end

    -- LOCKED SET (ADR 0022). This tab owns the STATE: the Sets tab fires the
    -- command for a named set, but what is currently held belongs where what you
    -- are WEARING is already shown. The switch here is set-current -- "lock
    -- exactly what I have on" -- the one variant with no set to pick, and the
    -- one an Incursion run actually reaches for at the entrance.
    if S.engineHeld ~= nil then
        local held = S.engineHeld();
        imgui.SameLine(0, 12);
        local hk = { held ~= nil };
        if imgui.Checkbox('Lock gear##eqheld', hk) then
            pcall(function()
                AshitaCore:GetChatManager():QueueCommand(1,
                    hk[1] and '/dl lock set-current' or '/dl lock set off');
            end);
            if S.lockMirrorDirty ~= nil then S.lockMirrorDirty(); end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Locks what you are wearing right now -- all 16 slots, empty stays empty.\n'
                .. 'Most things cannot override it (see Claim Priority under the Gear Helpers tab).\n'
                .. 'To lock a named set instead, use Equip & Lock on the Sets tab.');
        end
        if held ~= nil then
            imgui.SameLine(0, 10);
            local n = tonumber(held.n) or 0;
            local tip = string.format('%d of 16 slots locked, re-applied every dispatch.\n', n)
                .. ((n < 16) and ('The other ' .. tostring(16 - n) .. ' are free -- unnamed, or the piece was not on you.\n') or '')
                .. 'Uncheck to release.';
            if uistyle ~= nil and type(uistyle.helpLabel) == 'function' then
                uistyle.helpLabel(imgui, string.format('LOCKED: %s', tostring(held.name)), tip, COL.ERR);
            else
                imgui.TextColored(COL.ERR, string.format('LOCKED: %s', tostring(held.name)));
                if imgui.IsItemHovered() then imgui.SetTooltip(tip); end
            end
        end
    end

    -- The floating equipment window (floatgear owns the window; this is just its
    -- switch, kept next to the other Equipped-tab toggles).
    imgui.SameLine(0, 12);
    local fl = { ui._gearFloat == true };
    if imgui.Checkbox('Floating equipment', fl) then
        ui._gearFloat = fl[1];
        ui._flagsDirty = true;                         -- remembered across sessions
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Opens the 4x4 equipment window (equipmon-style) that stays up while you play.\nHover a slot for the same details as here; RIGHT-CLICK a slot to PIN an item\ninto it -- the engine then wears that piece and nothing can take it off.\nPinned slots show a red frame. Pins clear when you reload.\n\nSHIFT+drag the window to move it.');
    end
    -- Size lives next to the switch, and only while the window is up: it is the
    -- one setting you cannot discover from the window itself (it has no chrome).
    if ui._gearFloat == true then
        local fg = S.floatgear;
        imgui.SameLine(0, 8);
        imgui.PushItemWidth(84);
        local sc = { (fg ~= nil) and fg.scale() or 1.0 };
        if imgui.SliderFloat('##gfscale', sc, (fg ~= nil) and fg.SCALE_MIN or 0.5,
                             (fg ~= nil) and fg.SCALE_MAX or 3.0, '%.2fx') then
            ui._gfScale = sc[1];
            ui._flagsDirty = true;
        end
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Size of the floating equipment window -- drag it, or double-click to type a number.');
        end
    end

    local availW = imgui.GetContentRegionAvail();
    local leftUsed = ui.showStats and (STATS_W + 8) or 0;

    if ui.showStats then
        S.renderStatsPanel(gearOracle.hasAugments() and 'Worn totals (base+aug)' or 'Worn set totals', S.wornSetTotals());
        imgui.SameLine();
    end

    imgui.BeginChild('##ffxilac_eqmain', { availW - leftUsed, -1 }, false);

    S.renderSlotGrid('eq', 182, ui.eqSelected,
        function(sl) return S.getEquippedId(sl.equip); end,
        function(sl)
            local id = S.getEquippedId(sl.equip);
            return fmt.truncate(id and (S.displayName(id) or ('#' .. tostring(id))) or '(empty)', 18);
        end,
        function(labelKey) ui.eqSelected = labelKey; ui.altSearch = { '' }; end,
        function(sl) return S.lookupById(S.getEquippedId(sl.equip)); end,
        190,                                           -- fixed width: the compare panel sits beside
        {
            -- The server's encumbrance, struck across the box (2026-08-06). The
            -- same hook and the same service the floating bar draws from, so
            -- the tab and the bar cannot disagree about which slots are shut.
            --
            -- Server encumbrance ONLY -- deliberately not dlac's own engine
            -- locks, which this tab already states in words ("[LOCKED]" beside
            -- the selected slot, with the way to release it). Those two are
            -- different claims: one you can undo from here, one you cannot
            -- undo at all, and one mark for both would say neither.
            crossOf = function(sl) return S.encumbered(sl.equip) == true; end,
            noteOf  = function(sl)
                if S.encumbered(sl.equip) ~= true then return nil; end
                return S.ENCUMBERED_NOTE;
            end,
        });
    imgui.SameLine(0, 14);
    -- FIXED-height panel: hover must never resize the layout, or the list below
    -- shifts under the cursor and the hover jitters between two rows. Card area
    -- (grid height) + three dedicated rows for the compare text.
    local _plh = 21;
    pcall(function()
        local v = imgui.GetTextLineHeightWithSpacing();
        if type(v) == 'number' and v > 0 then _plh = v; end
    end);
    imgui.BeginChild('##eqcmppanel', { -1, 182 + math.floor(_plh * 3) + 12 }, false,
        ImGuiWindowFlags_NoScrollbar or 0);
    renderComparePanel(level);
    imgui.EndChild();

    imgui.Separator();

    if ui.eqSelected == nil then
        fmt.textWrapped(COL.DIM, 'Select a slot above to see the alternatives you can equip there.');
    else
        -- Selected slot header + equipped item.
        local gearKey = GEAR_OF[ui.eqSelected] or ui.eqSelected;
        local slDef;
        for _, s in ipairs(EQUIP_SLOTS) do if s.label == ui.eqSelected then slDef = s; break; end end
        local eqId = slDef and S.getEquippedId(slDef.equip) or nil;

        local slotLocked = (S.engineLocks()[S.lacSlot(ui.eqSelected)] == true);
        imgui.TextColored(COL.HEADER, ui.eqSelected .. ' slot');
        if slotLocked then
            imgui.SameLine(0, 8);
            imgui.TextColored(COL.ERR, '[LOCKED]');
            if imgui.IsItemHovered() then
                imgui.SetTooltip('The dlac engine will not equip into this slot (locked).\nUncheck "Lock when equipped" to release it, or /dl lock ' .. S.lacSlot(ui.eqSelected) .. ' off.');
            end
        end
        if eqId ~= nil then
            icons.renderIcon(eqId, 24);
            imgui.TextColored(COL.USABLE, fmt.esc(S.displayName(eqId) or ('#' .. tostring(eqId))));
            local rec = S.lookupById(eqId);
            if rec ~= nil then
                imgui.SameLine(0, 8); imgui.TextColored(COL.LEVEL, 'Lv' .. tostring(rec.Level or 0));
                local ss = fmt.statSummary(rec, level);
                if ss ~= '' then imgui.TextColored(COL.STATS, fmt.esc(ss)); end
            end
            if gearOracle.hasAugments() and slDef ~= nil then  -- private augments on the worn piece
                local extra = gearOracle.wornAugExtra(slDef.equip);
                local ad = extra and gearOracle.describeAugments(extra) or '';
                if ad ~= '' then imgui.TextColored(COL.SCORE, 'Aug: ' .. fmt.esc(ad)); end
            end
        else
            imgui.TextColored(COL.DIM, '(nothing equipped in this slot)');
        end

        -- Candidates (Sub: shields/grips + 1H weapons, filtered by the equipped
        -- Main -- equip-now, so the DW gate applies), then searched + display-sorted.
        local mainRec = S.lookupById(S.getEquippedId(0x00));
        local alts = (gearKey == 'Sub') and S.subCandidatePool(job, level) or S.candidatesForSlot(gearKey, job, level);
        if gearKey == 'Sub' then alts = S.subFilter(alts, mainRec, job, level); end
        ui.altSearch = ui.altSearch or { '' };
        local altQ = string.lower(ui.altSearch[1] or '');
        if altQ ~= '' then
            local altTerms = S.parseSearch(altQ);
            local f = {};
            for _, r in ipairs(alts) do
                if S.itemSearchMatch(r, altTerms, level) then f[#f + 1] = r; end
            end
            alts = f;
        end
        alts = S.sortForDisplay(alts);

        imgui.Spacing();
        imgui.TextColored(COL.HEADER, string.format('Alternatives (%d):', #alts));
        imgui.SameLine(0, 10); S.renderSortCombo('eq');
        imgui.SameLine(0, 12);
        imgui.TextColored(COL.DIM, 'Search:'); imgui.SameLine(0, 4);
        imgui.PushItemWidth(170);
        imgui.InputText('##eqaltsearch', ui.altSearch, 48);
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Matches item names AND stats -- try HMP, Refresh, FastCast\n(aliases work: matk finds MAB gear). Comma = AND:\n"hmp, refresh" shows only pieces carrying BOTH.');
        end
        imgui.SameLine(0, 12);
        local prevLock = ui._lockPrev;
        imgui.Checkbox('Lock when equipped', ui.lockEquipped);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('While on, clicking an alternative LOCKS this slot (the dlac engine stops\nequipping into it -- the same engine lock the Priority list\'s Locks row governs)\nand equips it via the game\'s native /equip -- so it stays put.\nUncheck to release the slot.');
        end
        if prevLock == true and ui.lockEquipped[1] == false then
            local s = ui.eqSelected and S.lacSlot(ui.eqSelected) or 'all';
            pcall(function()
                AshitaCore:GetChatManager():QueueCommand(1, '/dl lock ' .. s .. ' off');
            end);
            S.lockMirrorDirty();   -- re-read the engine mirror promptly
        end
        ui._lockPrev = ui.lockEquipped[1];

        imgui.BeginChild('##ffxilac_eqalts', { -1, -1 }, false);
        if #alts == 0 then
            if altQ ~= '' then
                imgui.TextColored(COL.DIM, 'Nothing matches the search.');
            elseif gearKey == 'Sub' and mainRec == nil then
                imgui.TextColored(COL.DIM, 'No Main equipped -- equip a weapon first.');
            else
                imgui.TextColored(COL.DIM, 'No eligible gear for this slot at your job/level.');
            end
        else
            local nW = fmt.nameWidthOf(alts);
            for i, rec in ipairs(alts) do
                if renderAltRow(rec, i, job, level, nW) then
                    S.equipToSlot(ui.eqSelected, rec.Name, ui.lockEquipped[1] == true, ui.freeEquip[1] == true, slotLocked);
                    S.lockMirrorDirty();   -- lock state may just have changed
                end
            end
        end
        imgui.EndChild();
    end

    imgui.EndChild();
end

-- ---------------------------------------------------------------------------
-- Tab: All Equipment (collapsible tree over catalog.lua, gear.lua fallback)
-- ---------------------------------------------------------------------------
local function renderAllEquipTab(job, level)
    -- Filter row: slot dropdown + "Usable now" + name search. (Buttons live in the header.)
    imgui.PushItemWidth(130);
    if imgui.BeginCombo('##ffxilac_slot', ui.slot or 'All slots') then
        if imgui.Selectable('All slots', ui.slot == nil) then ui.slot = nil; end
        for _, s in ipairs(SLOT_ORDER) do
            if imgui.Selectable(s, ui.slot == s) then ui.slot = s; end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, 10);
    imgui.Checkbox('Usable now', ui.usableNow);
    imgui.SameLine(0, 10);
    -- The SAME flag Menu > Settings drives (ui.showAll) -- one setting, two
    -- surfaces. It lived only in Settings from 07-24, where it read as a
    -- preference called "Show all equipment"; this is the tab you are looking at
    -- when you notice a piece is missing, so the switch belongs here too, worded
    -- the way the lockstyle picker has worded it since 07-15.
    local sa = { ui.showAll[1] == true };
    if imgui.Checkbox("Show gear I don't own##aeqall", sa) then
        ui.showAll[1] = sa[1];
        ui._flagsDirty = true;                         -- remembered across sessions
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Off (default): only gear you own (anywhere).\n'
            .. 'On: every piece of equipment in the game -- yours and the rest.\n\n'
            .. 'Orange = you do not own it. Right-click any row to put it on your Wishlist.\n'
            .. 'Combine with "Usable now" for "what could my job wear that I do not have".');
    end
    imgui.SameLine(0, 10);
    imgui.TextColored(COL.DIM, 'Search:');
    imgui.SameLine(0, 4);
    imgui.PushItemWidth(-1);
    imgui.InputText('##ffxilac_search', ui.search, 64);
    imgui.PopItemWidth();

    -- Default to what you own (gear.lua); "Show all" (header) opens the full catalog.
    local showAll = (ui.showAll[1] == true);
    local items = showAll and S.buildAllEquip() or S.buildOwned();
    local usableOnly = (ui.usableNow[1] == true);
    local needle = string.lower(ui.search[1] or '');
    local searching = (needle ~= '');

    -- Group the filtered items by slot (Main/Range further by category).
    local grouped, shown = {}, 0;
    for _, rec in ipairs(items) do
        local keep = true;
        if ui.slot ~= nil and rec.Slot ~= ui.slot then keep = false; end
        if keep and usableOnly and not S.isUsable(rec, job, level) then keep = false; end
        if keep and not showAll and not owned.haveInBags(rec) then keep = false; end   -- owned view = actually in your bags
        if keep and searching and string.find(string.lower(rec.Name or ''), needle, 1, true) == nil then keep = false; end
        if keep then
            shown = shown + 1;
            local slot = rec.Slot or '?';
            if slot == 'Main' or slot == 'Range' then
                grouped[slot] = grouped[slot] or { _cats = {} };
                local cat = rec.Category or '?';
                grouped[slot]._cats[cat] = grouped[slot]._cats[cat] or {};
                table.insert(grouped[slot]._cats[cat], rec);
            else
                grouped[slot] = grouped[slot] or {};
                table.insert(grouped[slot], rec);
            end
        end
    end

    imgui.TextColored(COL.DIM, string.format('Showing %d of %d  |  source: %s  |  red = in storage (not equippable)%s',
        shown, #items, showAll and (S.hasCatalog and 'full catalog (catalog.lua)' or 'gear.lua (no catalog)')
                              or 'gear you own (anywhere)',
        showAll and '  |  grey = not owned' or ''));
    if not showAll then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL.DIM, '-- tick "Show gear I don\'t own" to browse the full catalog.');
    end
    imgui.Separator();

    -- Force-open sections while searching; collapse once when the search is cleared.
    local forceClose = (not searching) and (ui._treeWasSearching == true);

    -- Right-click target for this frame. The rows detect the click inside the
    -- tree's BeginChild and only REPORT it; the popup is opened below, after
    -- EndChild, because OpenPopup and BeginPopup resolve their id against the
    -- current window and must share one (floatgear's law).
    local rmb = nil;
    local function onRight(rec) rmb = rec; end

    imgui.BeginChild('##ffxilac_tree', { -1, -1 }, false);
    for _, slot in ipairs(SLOT_TREE_ORDER) do
        local data = grouped[slot];
        local cnt = 0;
        if data ~= nil then
            if slot == 'Main' or slot == 'Range' then
                for _, list in pairs(data._cats) do cnt = cnt + #list; end
            else
                cnt = #data;
            end
        end
        if cnt > 0 then
            if searching then imgui.SetNextItemOpen(true);
            elseif forceClose then imgui.SetNextItemOpen(false); end
            if imgui.CollapsingHeader(string.format('%s (%d)###aeqh_%s', slot, cnt, slot)) then
                if slot == 'Main' or slot == 'Range' then
                    local seen = {};
                    local function renderCat(cat)
                        local list = data._cats[cat];
                        if list == nil or #list == 0 then return; end
                        seen[cat] = true;
                        if searching then imgui.SetNextItemOpen(true);
                        elseif forceClose then imgui.SetNextItemOpen(false); end
                        if imgui.TreeNode(string.format('%s (%d)###aeqc_%s_%s', cat, #list, slot, cat)) then
                            local nW = fmt.nameWidthOf(list);
                            for i, rec in ipairs(list) do renderBrowseRow(rec, i, job, level, nW, onRight); end
                            imgui.TreePop();
                        end
                    end
                    for _, cat in ipairs(CAT_ORDER[slot] or {}) do renderCat(cat); end
                    local extra = {};
                    for cat in pairs(data._cats) do if not seen[cat] then extra[#extra + 1] = cat; end end
                    table.sort(extra);
                    for _, cat in ipairs(extra) do renderCat(cat); end
                else
                    local nW = fmt.nameWidthOf(data);
                    for i, rec in ipairs(data) do renderBrowseRow(rec, i, job, level, nW, onRight); end
                end
            end
        end
    end
    imgui.EndChild();

    -- The item context menu. Popup at WINDOW scope (see onRight above). The menu
    -- BODY lives in wishlistui so the same rows can hang off other surfaces
    -- later; this tab owns only which record it is for.
    if rmb ~= nil then
        ui._itemMenuRec = rmb;
        imgui.OpenPopup(ITEM_MENU);
    end
    -- Constrained rather than wrapped in a child: a BeginChild anywhere in a menu
    -- chain tears the whole popup down the moment the cursor moves toward a
    -- submenu (floatgear paid for this one twice).
    imgui.SetNextWindowSizeConstraints({ 210, 0 }, { 380, 460 });
    if imgui.BeginPopup(ITEM_MENU) then
        if wishui ~= nil and type(wishui.renderItemMenu) == 'function' then
            pcall(wishui.renderItemMenu, ui._itemMenuRec, job);
        else
            imgui.TextColored(COL.DIM, 'Wishlist unavailable.');
        end
        imgui.EndPopup();
    end

    ui._treeWasSearching = searching;
end

-- Register both tabs -- refuse loudly (chat line, no tabs) if gearui didn't
-- provide the services first; a silent half-broken tab is worse than a missing
-- one. No imgui check here: tabs only ever render from inside gearui's
-- imgui-guarded window (and the headless smoke test asserts this registration).
if ui ~= nil and COL ~= nil and EQUIP_SLOTS ~= nil then
    host.register({ name = 'equipped', tabs = {
        { label = 'Equipped',      render = renderEquippedTab },
        { label = 'All Equipment', render = renderAllEquipTab },
    } });
else
    pcall(function() print('[dlac] equippedui: uihost services missing -- tabs not registered (load order?)'); end);
end

return { renderEquippedTab = renderEquippedTab, renderAllEquipTab = renderAllEquipTab };
