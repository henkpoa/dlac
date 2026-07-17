--[[
    dlac/weightsui.lua

    The stat-weights EDITOR (per-stat pts/cap rows, live-apply, searchable add
    picker), extracted from gearui (the LuaJIT 200-local chunk cap). The Sets
    tab embeds it via wui.editor(); the floating "dlac Stat Weights" window is
    gearui's renderSetsWeightPanel in a shell (registered as a uihost window).

    Scoring itself (weightsActive / scoreOf) stays in gearui -- the Sets
    candidate machinery calls it every frame; this module is only the UI.

    Deps arrive once via wui.configure{} (the profilesets.configure precedent):
        ui                    -- gearui's live view-state table (_wbuf, addStat, ...)
        COL                   -- shared palette
        STAT_GROUPS           -- grouped stat names (the suggestion fallback)
        invalidateCandidates  -- weights changed: re-sort the candidate lists
]]--

local wui = {};

local fmt = require("dlac\\gear\\gearfmt");
local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui    = try('imgui');
local optim    = try("dlac\\gear\\gearoptim");
local statdefs = try("dlac\\data\\statdefs");
local hasStatdefs = statdefs ~= nil and type(statdefs.list) == 'table';

local D = nil;   -- deps from gearui; editor() no-ops until configured
wui.configure = function(deps)
    if type(deps) == 'table' then D = deps; end
end

-- Flat, de-duplicated stat list for the weights "add" searchable dropdown (kept in group
-- order). Typing still accepts any custom name; this is just the suggestion set.
local _choices = nil;
local function weightChoices()
    if _choices ~= nil then return _choices; end
    _choices = {};
    local seen = {};
    local function add(s) if not seen[s] then seen[s] = true; _choices[#_choices + 1] = s; end end
    for _, g in ipairs((D and D.STAT_GROUPS) or {}) do for _, s in ipairs(g.stats) do add(s); end end
    for _, s in ipairs({ 'DMG', 'Counter', 'MovementSpeed', 'PDT', 'DT' }) do add(s); end
    return _choices;
end

-- Suggestion list for the weights "add stat" picker. Sourced from statdefs when available, so
-- the search matches key/label/aliases (type "MATK" or "MagicAttackBonus" -> find MAB) and
-- picking inserts the CANONICAL key; falls back to the grouped choices. Each entry:
--   { key = <canonical key to insert>, label = <display>, terms = {<lowercased key/label/aliases>} }
local _weightSuggest = nil;
local function weightSuggestions()
    if _weightSuggest ~= nil then return _weightSuggest; end
    local out = {};
    if hasStatdefs then
        for _, e in ipairs(statdefs.list) do
            local lbl = e.label or e.key;
            local terms = { string.lower(e.key) };
            if string.lower(lbl) ~= terms[1] then terms[#terms + 1] = string.lower(lbl); end
            if e.aliases ~= nil then for _, a in ipairs(e.aliases) do terms[#terms + 1] = string.lower(a); end end
            out[#out + 1] = { key = e.key, label = lbl, terms = terms };
        end
    else
        for _, name in ipairs(weightChoices()) do
            out[#out + 1] = { key = name, label = name, terms = { string.lower(name) } };
        end
    end
    _weightSuggest = out;
    return out;
end

-- The 4x4 build-slot grid (2026-07-17, replaces the Skip-weapons checkbox):
-- text-only tiles in equipmon's visual order marking which slots Auto-build
-- FILLS for the bound set (shared when none). Unmarked slots are left exactly
-- as the working set has them. Weapons default unmarked (swapping Main/Sub/
-- Range resets TP) but are one click away. Rides the same per-set binding and
-- gearweights.lua persistence as the weights -- no rebuilding marks between
-- sets. Checkbox toggles need no candidate invalidation: the mask changes
-- WHICH slots build, never how items score.
wui.slotGrid = function()
    if D == nil or imgui == nil or optim == nil then return; end
    if type(D.EQUIP_SLOTS) ~= 'table' or type(optim.getSlotMask) ~= 'function' then return; end
    local COL = D.COL;
    local mask = nil;
    pcall(function() mask = optim.getSlotMask(); end);
    if type(mask) ~= 'table' then return; end
    imgui.TextColored(COL.DIM, 'build slots:');
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Mark the slots Auto-build fills; unmarked slots keep whatever the set\nalready holds. Each set remembers its own marks (with its weights).\nWeapons start unmarked so building never resets your TP -- tick them\nwhen you do want weapons picked.');
    end
    for i, sl in ipairs(D.EQUIP_SLOTS) do
        local b = { mask[sl.label] == true };
        if imgui.Checkbox(sl.short .. '##bslot_' .. sl.label, b) then
            pcall(optim.setSlotEnabled, sl.label, b[1]);
            pcall(optim.saveWeights);
        end
        if i % 4 ~= 0 then imgui.SameLine(math.floor((i % 4) * 74) + 1); end
    end
end

-- The weights editor body (fills the surrounding child/window).
wui.editor = function()
    if D == nil or imgui == nil then return; end
    local ui, COL = D.ui, D.COL;
    if optim == nil then
        imgui.TextColored(COL.DIM, 'Optimizer unavailable -- weights disabled.');
        return;
    end
    -- Say WHOSE weights these are: each set remembers its own (shared when none).
    pcall(function()
        local bk = (optim.weightsBoundTo ~= nil) and optim.weightsBoundTo() or nil;
        if bk ~= nil then
            local j, s = string.match(bk, '^([^|]+)|(.+)$');
            imgui.TextColored(COL.HEADER, string.format('weights for set "%s" (%s)', s or bk, j or '?'));
        else
            imgui.TextColored(COL.HEADER, 'shared weights (no set selected)');
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Every set remembers its own stat weights. Selecting a set for the FIRST\ntime starts it from the shared table; edits after that stick to that set\nonly, and come back when you re-select it.');
        end
    end);
    imgui.TextColored(COL.DIM, 'pts/point up to cap (cap 0 = none) -- applies as you type:');
    imgui.BeginChild('##ffxilac_weights', { -1, -1 }, true);   -- fill the (now windowed) space

    -- Adaptive name column: the stat name gets all the width the window can spare (the
    -- pts/cap/x controls need ~200px), so widening the window shows long names in full.
    local availW  = imgui.GetContentRegionAvail();
    local nameCol = availW - 200; if nameCol < 44 then nameCol = 44; end
    local nchars  = math.max(6, math.floor(nameCol / 7));

    local ws = {};
    pcall(function() ws = optim.getWeights() or {}; end);
    for _, stat in ipairs(fmt.sortedKeys(ws)) do
        local w = ws[stat];
        local b = ui._wbuf[stat];
        if b == nil then
            local pv = (type(w) == 'table' and w.perUnit) or 0;
            b = { per = { math.floor(pv + 0.5) }, cap = { (type(w) == 'table' and w.cap) or 0 } };
            ui._wbuf[stat] = b;
        end
        imgui.TextColored(COL.USABLE, fmt.truncate(stat, nchars));
        if #stat > nchars and imgui.IsItemHovered() then imgui.SetTooltip(stat); end
        imgui.SameLine(nameCol);
        imgui.TextColored(COL.DIM, 'pts'); imgui.SameLine(0, 2);
        imgui.PushItemWidth(52);
        local chgPer = imgui.InputInt('##per_' .. stat, b.per, 0);
        imgui.PopItemWidth();
        imgui.SameLine(0, 6); imgui.TextColored(COL.DIM, 'cap'); imgui.SameLine(0, 2);
        imgui.PushItemWidth(46);
        local chgCap = imgui.InputInt('##cap_' .. stat, b.cap, 0);
        imgui.PopItemWidth();
        -- Live apply (Henrik): the number in the box IS the weight -- a "Set" click
        -- was too easy to miss. Mid-typing values ("2" on the way to "20") apply
        -- transiently and self-correct on the next keystroke.
        if chgPer or chgCap then
            pcall(optim.setWeight, stat, b.per[1], (b.cap[1] and b.cap[1] > 0) and b.cap[1] or nil);
            pcall(optim.saveWeights);
            D.invalidateCandidates();
        end
        imgui.SameLine(0, 3);
        if imgui.Button('x##wx_' .. stat, { 20, 0 }) then
            pcall(optim.clearWeight, stat);
            pcall(optim.saveWeights);
            ui._wbuf[stat] = nil;
            D.invalidateCandidates();
        end
    end

    imgui.Separator();

    -- Add row: searchable stat dropdown -- type in the box to filter suggestions, click one
    -- (or keep your own text), then set pts/cap and Add.
    imgui.TextColored(COL.DIM, 'add'); imgui.SameLine(0, 4);
    imgui.PushItemWidth(160);
    if imgui.BeginCombo('##addstat', (ui.addStat[1] ~= '' and ui.addStat[1]) or '(type to search)') then
        if imgui.IsWindowAppearing ~= nil and imgui.IsWindowAppearing()
           and imgui.SetKeyboardFocusHere ~= nil then imgui.SetKeyboardFocusHere(0); end
        imgui.PushItemWidth(-1); imgui.InputText('##addfilter', ui.addStat, 32); imgui.PopItemWidth();
        imgui.Separator();
        local q, shown = string.lower(ui.addStat[1] or ''), 0;
        for _, sug in ipairs(weightSuggestions()) do
            local match = (q == '');
            if not match then
                for _, t in ipairs(sug.terms) do
                    if string.find(t, q, 1, true) ~= nil then match = true; break; end
                end
            end
            if match then
                shown = shown + 1;
                local disp = (sug.label ~= sug.key) and (sug.label .. '  (' .. sug.key .. ')') or sug.key;
                if imgui.Selectable(disp .. '##sug_' .. sug.key, false) then
                    ui.addStat[1] = sug.key;             -- insert the canonical key (not the alias/label)
                    imgui.CloseCurrentPopup();
                end
            end
        end
        if shown == 0 then imgui.TextColored(COL.DIM, '(no match -- Add will use your typed text)'); end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, 6); imgui.TextColored(COL.DIM, 'pts'); imgui.SameLine(0, 2);
    imgui.PushItemWidth(52); imgui.InputInt('##addper', ui.addPer, 0); imgui.PopItemWidth();
    imgui.SameLine(0, 6); imgui.TextColored(COL.DIM, 'cap'); imgui.SameLine(0, 2);
    imgui.PushItemWidth(46); imgui.InputInt('##addcap', ui.addCap, 0); imgui.PopItemWidth();
    imgui.SameLine(0, 6);
    if imgui.Button('Add##addw', { 40, 0 }) then
        local name = ui.addStat[1];
        if name ~= nil and name ~= '' then
            pcall(optim.setWeight, name, ui.addPer[1], (ui.addCap[1] and ui.addCap[1] > 0) and ui.addCap[1] or nil);
            pcall(optim.saveWeights);
            ui.addStat[1] = '';
            D.invalidateCandidates();
        end
    end

    imgui.EndChild();
end

return wui;
