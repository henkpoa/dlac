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
local aug      = try("dlac\\feature\\augments");
local statdefs = try("dlac\\data\\statdefs");

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
local function renderBrowseRow(rec, ordinal, job, level, nameW)
    local bg = (ordinal % 2 == 0) and { 1, 1, 1, 0.03 } or { 1, 1, 1, 0.07 };
    imgui.PushStyleColor(ImGuiCol_ChildBg, bg);
    imgui.BeginChild('##aeqrow_' .. tostring(rec.Id or ('n' .. ordinal)), { -1, 22 }, false);
    icons.renderIcon(rec.Id, 18);
    local usable = S.isUsable(rec, job, level);
    local nameColr = owned.isStored(rec) and COL.ERR or (usable and COL.USABLE or COL.LOCKED);
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
    if imgui.IsItemHovered() then S.renderItemTooltip(rec); end
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
    if rec.Id ~= nil then
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
    imgui.TextColored(COL.DIM, 'Hover a slot for details; click for alternatives.');
    imgui.SameLine();
    if imgui.Button((ui.showStats and 'Stats v' or 'Stats >') .. '##eqstats', { 76, 0 }) then
        ui.showStats = not ui.showStats;
    end

    -- Free equip: disable LAC globally so it stops auto-swapping and manual equips stick.
    -- While on, clicking an alternative uses the game's native /equip (bypasses LAC).
    imgui.SameLine(0, 12);
    imgui.Checkbox('Free equip', ui.freeEquip);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Runs /lac disable so LAC stops auto-swapping and your manual equips stay put --\nhandy for fiddling with gear. While on, clicking an alternative equips via the\ngame\'s native /equip (outside LAC). Uncheck to /lac enable and hand control back.');
    end
    if ui._freePrev ~= nil and ui._freePrev ~= ui.freeEquip[1] then
        local cmd = (ui.freeEquip[1] == true) and '/lac disable' or '/lac enable';
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
        if ui.freeEquip[1] == false then               -- leaving free-equip clears engine locks too
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl lock all off'); end);
        end
    end
    ui._freePrev = ui.freeEquip[1];
    if ui.freeEquip[1] == true then
        imgui.SameLine(0, 10);
        imgui.TextColored(COL.ERR, 'LAC OFF -- gear will not auto-swap');
    end

    local availW = imgui.GetContentRegionAvail();
    local leftUsed = ui.showStats and (STATS_W + 8) or 0;

    if ui.showStats then
        S.renderStatsPanel((aug ~= nil) and 'Worn totals (base+aug)' or 'Worn set totals', S.wornSetTotals());
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
        190);                                          -- fixed width: the compare panel sits beside
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
            if aug ~= nil and slDef ~= nil then        -- private augments on the worn piece
                local extra = aug.slotExtra(slDef.equip);
                local ad = extra and aug.describe(extra) or '';
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
            imgui.SetTooltip('While on, clicking an alternative LOCKS this slot (the dlac engine stops\nequipping into it, /lac disable covers legacy profile code) and equips it via\nthe game\'s native /equip -- so it stays put. Uncheck to release the slot.');
        end
        if prevLock == true and ui.lockEquipped[1] == false then
            local s = ui.eqSelected and S.lacSlot(ui.eqSelected) or 'all';
            pcall(function()
                AshitaCore:GetChatManager():QueueCommand(1, '/dl lock ' .. s .. ' off');
                AshitaCore:GetChatManager():QueueCommand(1, '/lac enable ' .. s);
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

    imgui.TextColored(COL.DIM, string.format('Showing %d of %d  |  source: %s  |  red = in storage (not equippable)',
        shown, #items, showAll and (S.hasCatalog and 'full catalog (catalog.lua)' or 'gear.lua (no catalog)')
                              or 'gear you own (anywhere)'));
    if not showAll then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL.DIM, '-- tick "Show all" (top) to browse the full catalog.');
    end
    imgui.Separator();

    -- Force-open sections while searching; collapse once when the search is cleared.
    local forceClose = (not searching) and (ui._treeWasSearching == true);

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
                            for i, rec in ipairs(list) do renderBrowseRow(rec, i, job, level, nW); end
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
                    for i, rec in ipairs(data) do renderBrowseRow(rec, i, job, level, nW); end
                end
            end
        end
    end
    imgui.EndChild();

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
