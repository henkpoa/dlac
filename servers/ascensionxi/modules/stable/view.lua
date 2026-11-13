-- Stable presentation only. Server responses remain authoritative.
local imgui = require('imgui');
local textures = require('dlac\\ui\\filetex');
local grid = require('dlac\\servers\\ascensionxi\\modules\\stable\\grid');
local M = {};
local selected, renameOpen = 2, false;
local habitatOpen, formFilter, ownershipFilter = false, 'all', 'all';
local search = { '' };
local presetOpen, presetIndex, selectedRoster = false, 1, nil;
local presetName = { '' };
local gold, dim, green = { 0.86, 0.73, 0.43, 1 }, { 0.58, 0.61, 0.66, 1 }, { 0.45, 0.78, 0.59, 1 };
local slots = { 'I', 'II', 'III' };
local blue, white, red = { 0.55, 0.76, 0.96, 1 }, { 0.9, 0.91, 0.94, 1 }, { 0.94, 0.5, 0.47, 1 };
local detailMove, detailsOpen, abilityInfo;

-- Reuse DLAC HELM's literal-text path. Percentages are not printf formats.
local function plain(color, text)
    imgui.PushStyleColor(ImGuiCol_Text, color);
    local ok, err = pcall(imgui.TextUnformatted, text);
    imgui.PopStyleColor();
    if not ok then error(err); end
end

local function literalTooltip(text)
    imgui.BeginTooltip();
    imgui.PushTextWrapPos(380);
    local ok, err = pcall(plain, white, text);
    imgui.PopTextWrapPos();
    imgui.EndTooltip();
    if not ok then error(err); end
end

local function tip(text)
    if imgui.IsItemHovered() then literalTooltip(text); end
end

local function button(text, enabled, size)
    if not enabled then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.38); end
    local clicked = imgui.Button(text, size or { 0, 0 });
    if not enabled then imgui.PopStyleVar(); end
    return clicked and enabled;
end

local function portrait(c, id, size, locked)
    local entry = c.catalog[math.floor(id / 2)];
    local texture = entry and (textures.queuedPackHandle or textures.packHandle)('ascensionxi', 'stable\\' .. entry.key .. (id % 2 == 1 and '-shiny' or ''));
    if texture then
        imgui.Image(texture, size, { 0, 0 }, { 1, 1 }, locked and { 0.08, 0.08, 0.09, 1 } or { 1, 1, 1, 1 });
    else
        imgui.Button('?##portrait', size);
    end
end

local function select(id)
    if selected ~= id then habitatOpen = false; end
    selected = id;
end

local function rosterSlot(state, id)
    for slot = 1, 3 do if state.roster[slot] == id then return slot; end end
end

local function popup(c)
    if detailsOpen then imgui.OpenPopup('Ability details##bst'); detailsOpen = false; end
    if imgui.BeginPopup('Ability details##bst') then
        imgui.BeginChild('##bstmovebody', { 480, 420 }, false);
        if detailMove then abilityInfo(detailMove, nil, true); end
        imgui.EndChild();
        if imgui.Button('Close##bstmove') then imgui.CloseCurrentPopup(); end
        imgui.EndPopup();
    end
    if presetOpen then imgui.OpenPopup('Rename roster##bst'); presetOpen = false; end
    if imgui.BeginPopup('Rename roster##bst') then
        imgui.TextColored(gold, 'ROSTER ' .. slots[presetIndex]);
        imgui.SetNextItemWidth(210);
        imgui.InputText('Name##preset', presetName, 16);
        tip('3-15 letters.');
        if button('Rename##preset', not c.readOnly and not c.pending and presetName[1] ~= '') then c.preset(3, presetIndex, presetName[1]); imgui.CloseCurrentPopup(); end
        imgui.TextColored(dim, 'Changes require the Stable Master.');
        imgui.EndPopup();
    end
    if renameOpen then imgui.OpenPopup('Rename companion##bst'); renameOpen = false; end
    if imgui.BeginPopup('Rename companion##bst') then
        imgui.Text(c.label(selected));
        imgui.SetNextItemWidth(220);
        imgui.InputText('##nickname', c.names[selected], 24);
        if button('Save', not c.readOnly and not c.pending) then c.rename(selected, c.names[selected][1]); imgui.CloseCurrentPopup(); end
        imgui.SameLine();
        if button('Use original name', not c.readOnly and not c.pending) then c.rename(selected, ''); imgui.CloseCurrentPopup(); end
        imgui.TextColored(dim, '3-23 letters and spaces; single spaces between words');
        imgui.EndPopup();
    end
end

function M.shinyChance(entry, level)
    if not entry or not entry.catchMinLevel or not entry.catchMaxLevel or level < 1 or level > 75 then return 0; end
    local span = math.max(20, entry.catchMaxLevel - entry.catchMinLevel);
    local gap = math.max(0, math.min(span, entry.catchMaxLevel - level));
    return math.floor((10000 * span - 8000 * gap) / span);
end

function M.habitatOdds(entry, lo, hi)
    local function percent(chance, precision)
        return string.format(precision or '%.4f', chance / 10000):gsub('0+$', ''):gsub('%.$', '') .. '%';
    end
    if not entry or not entry.catchMaxLevel then return nil, false, 'Unavailable'; end
    if lo > 75 then return 'Above the level-75 capture limit.', false, 'Unavailable'; end
    local upper = math.min(75, hi);
    local lowerChance, upperChance = M.shinyChance(entry, lo), M.shinyChance(entry, upper);
    local best = upper >= entry.catchMaxLevel;
    local odds = percent(lowerChance);
    if lowerChance ~= upperChance then odds = odds .. ' - ' .. percent(upperChance); end
    local visible = percent(lowerChance, '%.2f');
    if lowerChance ~= upperChance then visible = visible .. '-' .. percent(upperChance, '%.2f'); end
    local text = (best and 'Best shiny hunting source\n' or '') .. 'Shiny chance: ' .. odds .. '\n';
    if best then text = text .. string.format('1%% at level %d.\n', entry.catchMaxLevel); end
    text = text .. 'Based on the beast\'s actual level, for this companion variety.\nOne roll on your first successful Charm of this beast.\nYou must be at least the beast\'s level to capture it.';
    if hi > 75 then text = text .. '\nLevel 76+ spawns cannot be captured.'; end
    return text, best, visible;
end

-- AXI server catch guidance extends legacy six-column rows with an optional note.
function M.parseHabitat(row)
    if type(row) ~= 'string' then return nil; end
    local zone, mob, lo, hi, count, seconds, suffix = row:match('^([^|]+)|([^|]+)|(%d+)|(%d+)|(%d+)|(%d+)(.*)$');
    if not zone or (suffix ~= '' and not suffix:match('^|[^|]*$')) then return nil; end
    return zone, mob, lo, hi, count, seconds, suffix:sub(2);
end

local function habitats(c, height)
    if not habitatOpen then return; end
    imgui.Separator();
    imgui.TextColored(gold, c.catalog[math.floor(selected / 2)].name .. ' habitats'); imgui.SameLine();
    if imgui.SmallButton('Close##habitats') then habitatOpen = false; return; end
    if not c.habitats or c.habitats.id ~= math.floor(selected / 2) or not c.habitats.rows then
        local current = c.habitats and c.habitats.id == math.floor(selected / 2) and c.habitats;
        if current and current.loading and c.pending then
            imgui.TextColored(dim, 'Loading locations...');
        else
            imgui.TextWrapped(current and current.error or 'Locations are not loaded.');
            if button('Retry##habitats', not c.pending) then c.find(math.floor(selected / 2)); end
        end
        return;
    end
    if #c.habitats.rows == 0 then imgui.TextColored(dim, 'No wild locations are available for this companion.'); return; end
    imgui.BeginChild('##bsthabitats', { 0, height }, true);
    imgui.Columns(6, 'bsthabitatcolumns-odds', true);
    for _, title in ipairs({ 'Area', 'Beast', 'Level', 'Shiny chance', 'Spawns', 'Respawn' }) do
        imgui.TextColored(gold, title); imgui.NextColumn();
    end
    imgui.Separator();
    local entry = c.catalog[math.floor(selected / 2)];
    for _, row in ipairs(c.habitats.rows) do
        local zone, mob, lo, hi, count, seconds, note = M.parseHabitat(row);
        if zone then
            imgui.TextWrapped(zone); imgui.NextColumn();
            imgui.TextWrapped(mob);
            if note ~= '' then imgui.TextWrapped(note); end
            imgui.NextColumn();
            local odds, best, chance = M.habitatOdds(entry, tonumber(lo), tonumber(hi));
            local x, y = imgui.GetCursorScreenPos();
            if type(x) == 'table' then y = x[2]; x = x[1]; end
            if best then
                local dl = imgui.GetWindowDrawList();
                local ink = 0xFF6EB1D0;
                dl:AddTriangleFilled({ x + 7, y + 1 }, { x + 4, y + 8 }, { x + 10, y + 8 }, ink);
                dl:AddTriangleFilled({ x + 7, y + 15 }, { x + 4, y + 8 }, { x + 10, y + 8 }, ink);
                dl:AddTriangleFilled({ x, y + 8 }, { x + 7, y + 5 }, { x + 7, y + 11 }, ink);
                dl:AddTriangleFilled({ x + 14, y + 8 }, { x + 7, y + 5 }, { x + 7, y + 11 }, ink);
            end
            imgui.Dummy({ 14, 16 }); if odds then tip(odds); end
            imgui.SameLine();
            imgui.TextColored(best and gold or dim, lo .. '-' .. hi); if odds then tip(odds); end
            imgui.NextColumn();
            plain(best and gold or white, chance); if odds then tip(odds); end
            imgui.NextColumn();
            imgui.Text(count); imgui.NextColumn();
            imgui.Text(tostring(tonumber(seconds) / 60) .. ' min'); imgui.NextColumn();
        end
    end
    imgui.Columns(1); imgui.EndChild();
end

local previousCharges, gainedFrom, gainedAt;
local function rgba(r, g, b, a)
    return math.floor(math.max(0, math.min(1, a or 1)) * 255) * 16777216 + b * 65536 + g * 256 + r;
end

local function measure(text)
    local w, h = imgui.CalcTextSize(text);
    if type(w) == 'table' then return w[1] or w.x, w[2] or w.y; end
    return w, h;
end

local function paw(dl, x, y, scale, color)
    dl:AddCircleFilled({ x, y + 2 * scale }, 4.5 * scale, color, 20);
    for _, toe in ipairs({ { -6, -3 }, { -2, -6 }, { 3, -6 }, { 7, -2 } }) do
        dl:AddCircleFilled({ x + toe[1] * scale, y + toe[2] * scale }, 2.4 * scale, color, 16);
    end
end

local function clipped(dl, low, high, draw)
    dl:PushClipRect(low, high, true);
    local ok, err = pcall(draw);
    dl:PopClipRect();
    if not ok then error(err); end
end

function M.charges(clocks, scale)
    if not clocks then imgui.TextColored(dim, 'Ready charges: syncing...'); return; end
    scale = scale or 1;
    local now = clocks.time or os.clock();
    if previousCharges and clocks.charges > previousCharges then
        gainedFrom, gainedAt = previousCharges, now;
    elseif previousCharges and clocks.charges < previousCharges then
        gainedAt = nil;
    end
    previousCharges = clocks.charges;
    local x, y = imgui.GetCursorScreenPos();
    if type(x) == 'table' then y = x[2]; x = x[1]; end
    local _, fontHeight = measure('READY');
    fontHeight = fontHeight or 16;
    local count = string.format('%d / 3', clocks.charges);
    local countWidth = measure(count);
    local w = math.max(248 * scale, measure('READY') + countWidth + 64 * scale);
    local pad, gap, cellHeight = 14 * scale, 7 * scale, 26 * scale;
    local cellY = y + pad + fontHeight + 12 * scale;
    local h = cellY - y + cellHeight + pad;
    local dl = imgui.GetWindowDrawList();
    local ink = rgba(236, 225, 197);
    dl:AddRectFilled({ x + 2, y + 3 }, { x + w + 2, y + h + 3 }, rgba(0, 0, 0, 0.26), 9);
    dl:AddRectFilled({ x, y }, { x + w, y + h }, rgba(18, 21, 25, 0.95), 8);
    dl:AddRect({ x, y }, { x + w, y + h }, rgba(136, 117, 73, 0.65), 8, 0, 1);
    dl:AddText({ x + pad, y + pad }, rgba(208, 177, 110), 'READY');
    dl:AddText({ x + w - pad - countWidth, y + pad }, ink, count);
    local cellWidth = (w - pad * 2 - gap * 2) / 3;
    local progress = math.max(0, math.min(1, 1 - clocks.nextSeconds / clocks.periodSeconds));
    for index = 1, 3 do
        local left = x + pad + (index - 1) * (cellWidth + gap);
        local right = left + cellWidth;
        local charged = index <= clocks.charges;
        local charging = index == clocks.charges + 1;
        dl:AddRectFilled({ left, cellY }, { right, cellY + cellHeight }, rgba(35, 39, 44), 5);
        if charged then
            dl:AddRectFilled({ left, cellY }, { right, cellY + cellHeight }, rgba(191, 159, 89), 5);
            dl:AddLine({ left + 6, cellY + 1 }, { right - 6, cellY + 1 }, rgba(255, 229, 169, 0.65), 1);
        elseif charging and progress > 0 then
            local edge = left + cellWidth * progress;
            clipped(dl, { left, cellY }, { edge, cellY + cellHeight }, function()
                dl:AddRectFilled({ left, cellY }, { right, cellY + cellHeight }, rgba(122, 106, 66), 5);
            end);
            -- A moving highlight stays inside the recovering segment.
            local sweep = left + cellWidth * ((now * 0.38) % 1);
            clipped(dl, { left + 1, cellY + 1 }, { edge, cellY + cellHeight - 1 }, function()
                for band = -5, 5 do
                    local alpha = (1 - math.abs(band) / 6) * 0.13;
                    dl:AddRectFilled({ sweep + band * 2, cellY + 1 }, { sweep + band * 2 + 2, cellY + cellHeight - 1 }, rgba(245, 213, 146, alpha), 0);
                end
            end);
        end
        dl:AddRect({ left, cellY }, { right, cellY + cellHeight }, rgba(187, 157, 94, charged and 0.8 or 0.25), 5, 0, 1);
        -- A small paw makes each segment read as a companion charge.
        local cx, cy = (left + right) / 2, cellY + 14 * scale;
        paw(dl, cx, cy, scale, charged and rgba(52, 44, 28, 0.85) or rgba(157, 151, 128, 0.55));
        if gainedAt and index > gainedFrom and charged then
            local phase = (now - gainedAt) / 0.75;
            if phase >= 0 and phase < 1 then
                local spread = phase * 5;
                dl:AddRect({ left - spread, cellY - spread }, { right + spread, cellY + cellHeight + spread },
                    rgba(255, 226, 157, (1 - phase) * 0.8), 5 + spread, 0, 2);
            end
        end
    end
    imgui.Dummy({ w + 2, h + 3 });
    local tooltip = string.format('Shared by your companions.\nCurrent recharge: %ds', clocks.periodSeconds);
    local reduction = 30 - clocks.periodSeconds;
    if reduction > 0 then tooltip = tooltip .. string.format('\nReady Recharge merits: -%ds', reduction); end
    tip(tooltip);
    return { draw = dl, x = x + pad, y = cellY, width = cellWidth, height = cellHeight, gap = gap, charges = clocks.charges };
end

abilityInfo = function(move, gauge, expanded)
    imgui.PushTextWrapPos(expanded and 460 or 380);
    plain(gold, move.name);
    imgui.SameLine();
    local x, y = imgui.GetCursorScreenPos();
    local dl = imgui.GetWindowDrawList();
    local _, fontHeight = measure(move.name);
    local cell = math.max(18, fontHeight or 16);
    for cost = 1, move.charges do paw(dl, x + cell / 2 + (cost - 1) * cell, y + cell / 2, 0.72 * cell / 18, rgba(208, 177, 110)); end
    imgui.Dummy({ move.charges * cell, cell });
    plain(dim, (move.target or 'Companion') .. ' | Lv. ' .. move.level);
    local scaling = move.scaling;
    if not scaling or scaling.kind ~= 'heal' or expanded then plain(white, move.description or ''); end
    if gauge and gauge.charges < move.charges then plain(red, 'Not enough charges'); end
    if scaling then
        imgui.Spacing();
        for _, row in ipairs(scaling.summary) do
            plain(blue, row.label);
            plain(row.penalty and red or green, row.value);
        end
        if scaling.summaryNote ~= '' then imgui.Spacing(); plain(dim, scaling.summaryNote); end
        if expanded then
            imgui.Spacing();
            plain(gold, 'Calculation details');
            for _, row in ipairs(scaling.rows) do
                plain(blue, row.label);
                plain((row.label == 'Cost' or row.label == 'Outgoing damage' or row.label == 'DEF' and row.value:sub(1, 1) == '-') and red or white, row.value);
            end
            if scaling.note ~= '' then imgui.Spacing(); plain(dim, scaling.note); end
        else
            plain(dim, 'Click for details');
        end
    end
    imgui.PopTextWrapPos();
end;

local function readyMoves(entry, gauge)
    imgui.TextColored(dim, 'READY MOVES');
    local width = imgui.GetContentRegionAvail();
    local _, fontHeight = measure('READY');
    local rowHeight = math.max(24, (fontHeight or 16) + 8);
    for _, move in ipairs(entry.moves) do
        local x, y = imgui.GetCursorScreenPos();
        local hovered;
        if imgui.InvisibleButton('##bst-move-' .. move.name, { width, rowHeight }) then
            detailMove, detailsOpen = move, true;
        end
        hovered = imgui.IsItemHovered();
        local dl = imgui.GetWindowDrawList();
        if hovered then dl:AddRectFilled({ x, y }, { x + width, y + rowHeight }, rgba(191, 159, 89, 0.13), 4); end
        local iconsLeft = x + width - 3 * 20;
        dl:PushClipRect({ x, y }, { iconsLeft - 6, y + rowHeight }, true);
        dl:AddText({ x + 2, y + 4 }, rgba(148, 156, 168), string.format('%2d', move.level));
        dl:AddText({ x + measure('00') + 12, y + 4 }, rgba(224, 224, 228), move.name);
        dl:PopClipRect();
        for cost = 1, move.charges do
            paw(dl, iconsLeft + 10 + (cost - 1) * 20, y + rowHeight / 2, 0.72, rgba(208, 177, 110));
        end
        if hovered then
            imgui.SetMouseCursor(ImGuiMouseCursor_Hand or 7);
            imgui.BeginTooltip();
            abilityInfo(move, gauge, false);
            imgui.EndTooltip();
            if gauge then
                for index = 1, 3 do
                    local available = index <= gauge.charges;
                    local spent = available and index > math.max(0, gauge.charges - move.charges);
                    local missing = not available and index <= move.charges;
                    if spent or missing then
                        local left = gauge.x + (index - 1) * (gauge.width + gauge.gap);
                        local color = missing and rgba(235, 111, 108) or rgba(255, 226, 157);
                        gauge.draw:AddRectFilled({ left, gauge.y }, { left + gauge.width, gauge.y + gauge.height }, rgba(18, 21, 25, 0.42), 5);
                        gauge.draw:AddRect({ left, gauge.y }, { left + gauge.width, gauge.y + gauge.height }, color, 5, 0, 2);
                        paw(gauge.draw, left + gauge.width / 2, gauge.y + 14, 1, color);
                    end
                end
            end
        end
    end
end

function M.reset(keepChoices)
    detailMove, detailsOpen = nil, false;
    previousCharges, gainedFrom, gainedAt = nil, nil, nil;
    renameOpen, habitatOpen = false, false;
    if not keepChoices then selected, search[1], formFilter, ownershipFilter = 2, '', 'all', 'all'; end
    presetOpen, selectedRoster = false, nil;
end

function M.render(c)
    imgui.BeginChild('##bstcanvas', { 0, 0 }, false);
    imgui.TextColored(gold, 'COMPANIONS'); imgui.SameLine();
    if button('Refresh##bst', not c.pending or c.pendingOp == 0xF4) then c.request(0xF0); end
    imgui.SameLine(); imgui.SmallButton('?##bsthelp');
    tip('Charm > Seal Beast > trade the filled jug to a Stable Master.\nSelect a companion below, then assign it to a roster slot. Use Call Beast in the field.');
    if c.readOnly then imgui.TextWrapped('Finish zoning before managing companions.'); end
    if not c.state then
        imgui.TextWrapped(c.pending and 'Loading your Stable...' or c.notice);
        imgui.EndChild(); return;
    end
    if c.pending then imgui.SameLine(); imgui.TextColored(dim, 'Updating...');
    elseif c.notice ~= '' and c.notice ~= 'Stable updated.' then
        imgui.TextWrapped(c.notice);
    end
    local state = c.state;
    local ordinary, shiny = 0, 0;
    for id = 1, #c.catalog do
        if state.discovered[id * 2] then ordinary = ordinary + 1; end
        if state.discovered[id * 2 + 1] then shiny = shiny + 1; end
    end
    imgui.TextColored(dim, string.format('Collection   Regular %d/67    Shiny %d/67    Total %d/134', ordinary, shiny, ordinary + shiny));
    imgui.Spacing();

    local available, bodyHeight = imgui.GetContentRegionAvail();
    local sideBySide = available >= 850;
    local detailWidth = sideBySide and math.max(280, math.min(360, math.floor(available * 0.25))) or available;
    local width = sideBySide and available - detailWidth - 8 or available;
    imgui.BeginChild('##bstcollection', { width, sideBySide and 0 or math.max(420, bodyHeight * 0.65) }, false);
    if selectedRoster == nil or selectedRoster == 0 and state.activeRoster ~= 0 then selectedRoster = state.activeRoster; end
    if state.activeRoster == 0 then
        if imgui.RadioButton('Current##roster0', selectedRoster == 0) then selectedRoster = 0; end
        tip('Your previous lineup is preserved. Choose a roster and use it when ready.');
    end
    for index = 1, 3 do
        if index > 1 or state.activeRoster == 0 then imgui.SameLine(); end
        if imgui.RadioButton(slots[index] .. '##roster' .. index, selectedRoster == index) then selectedRoster = index; end
        local saved = state.presets[index];
        tip(saved and saved.name or 'Roster ' .. slots[index]);
    end
    local editing = selectedRoster ~= 0 and state.presets[selectedRoster] or nil;
    local roster = { roster = editing and editing.roster or state.roster };
    local isActive = selectedRoster == state.activeRoster;
    local function assign(slot, id)
        if selectedRoster == 0 then c.assign(slot, id); else c.editRoster(selectedRoster, slot, id); end
    end
    imgui.SameLine(); imgui.TextColored(gold, editing and editing.name or 'Current');
    imgui.SameLine();
    if isActive then imgui.TextColored(green, 'Active');
    elseif button('Use roster', not c.readOnly and not c.pending) then c.preset(2, selectedRoster); end
    tip('The active roster supplies Call Beast slots I, II and III. Switch at a Stable Master.');
    if selectedRoster ~= 0 then
        imgui.SameLine();
        if button('Rename##roster', not c.readOnly and not c.pending) then
            presetIndex, presetOpen, presetName[1] = selectedRoster, true, editing and editing.name or '';
        end
        tip('Assignments and removals save automatically at the Stable Master.');
    end
    imgui.Spacing();
    local stacked = width < 600;
    local slotWidth = stacked and width or math.floor((width - 16) / 3);
    for slot = 1, 3 do
        if slot > 1 and not stacked then imgui.SameLine(); end
        imgui.PushID('bst-roster-' .. slot);
        imgui.BeginChild('##slot', { slotWidth, 132 }, true);
        local id = roster.roster[slot];
        imgui.TextColored(gold, slots[slot]); imgui.SameLine();
        imgui.TextColored(isActive and state.active == slot and green or dim, isActive and state.active == slot and 'CALLED' or 'SLOT');
        if id ~= 0 then
            portrait(c, id, { 54, 54 }, false); imgui.SameLine();
            imgui.BeginGroup();
            imgui.TextWrapped(c.label(id));
            local pet = state.owned[id];
            imgui.TextColored(pet and pet.dead and { 0.9, 0.4, 0.4, 1 } or dim, pet and pet.dead and 'Fallen' or 'Ready');
            imgui.EndGroup();
        else
            imgui.TextColored(dim, '+  Empty slot'); imgui.Dummy({ 0, 30 });
        end
        local canAssign = state.owned[selected] and not rosterSlot(roster, selected);
        if button('Assign selected##slot', not c.readOnly and not c.pending and canAssign) then assign(slot, selected); end
        local selectedSlot = rosterSlot(roster, selected);
        tip(canAssign and ('Assign ' .. c.label(selected) .. ' to slot ' .. slots[slot] .. (id ~= 0 and (' in place of ' .. c.label(id)) or '') .. '. At the Stable Master.') or
            selectedSlot and ('Already in slot ' .. slots[selectedSlot] .. '. Remove it from that slot first to move it.') or 'Select an available companion in the grid first.');
        if id ~= 0 then
            imgui.SameLine();
            if button('X##remove', not c.readOnly and not c.pending) then assign(slot, 0); end
            tip('Remove from this roster slot. Your companion stays registered.');
        end
        imgui.EndChild(); imgui.PopID();
    end

    imgui.Spacing();
    imgui.SetNextItemWidth(math.max(120, math.min(240, width - 210)));
    imgui.InputText('Search##bst', search, 64);
    if width >= 900 then imgui.SameLine(); end
    for index, filter in ipairs({ { 'all', 'All companions' }, { 'regular', 'Regular' }, { 'shiny', 'Shinies (' .. shiny .. ')' } }) do
        if index > 1 then imgui.SameLine(); end
        if imgui.RadioButton(filter[2] .. '##form', formFilter == filter[1]) then
            formFilter = filter[1];
            if formFilter ~= 'all' then select(math.floor(selected / 2) * 2 + (formFilter == 'shiny' and 1 or 0)); end
        end
    end
    for index, filter in ipairs({ { 'all', 'All' }, { 'owned', 'Available' }, { 'missing', 'Not caught' } }) do
        if index > 1 then imgui.SameLine(); end
        if imgui.RadioButton(filter[2] .. '##ownership', ownershipFilter == filter[1]) then ownershipFilter = filter[1]; end
        if filter[1] == 'owned' then tip('Registered companions, including those already in your roster.'); end
    end

    local gridWidth, remainingHeight = imgui.GetContentRegionAvail();
    local habitatHeight = habitatOpen and math.min(250, math.max(120, remainingHeight * 0.4)) or 0;
    local columns = math.max(1, math.floor(gridWidth / 155));
    local cardWidth = math.floor((gridWidth - 18 - (columns - 1) * 8) / columns);
    imgui.BeginChild('##bstgrid', { gridWidth, math.max(120, remainingHeight - (habitatOpen and habitatHeight + 36 or 0)) }, false);
    local cards = grid.cards(c.catalog, state, search[1], formFilter, ownershipFilter);
    local visible = #cards;
    local rowHeight = cardWidth + 98;
    local origin = imgui.GetCursorPosY();
    local first, last, total = grid.rows(visible, columns, rowHeight, imgui.GetScrollY(), imgui.GetWindowHeight(), origin);
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing or 0, { 8, 8 });
    for index = first * columns + 1, math.min(visible, last * columns) do
        local id = cards[index];
        local catalogId = math.floor(id / 2);
        local entry = c.catalog[catalogId];
        local pet = state.owned[id];
        local shinyForm = id % 2 == 1;
        do
            if (index - 1) % columns ~= 0 then imgui.SameLine();
            else imgui.SetCursorPosY(origin + math.floor((index - 1) / columns) * rowHeight); end
            imgui.PushID('bst-card-' .. id);
            local x, y = imgui.GetCursorScreenPos();
            local hovered = imgui.IsWindowHovered(ImGuiHoveredFlags_ChildWindows or 1) and
                imgui.IsMouseHoveringRect({ x, y }, { x + cardWidth, y + cardWidth + 90 }, true);
            if hovered and imgui.IsMouseClicked(0) then select(id); end
            local highlighted = hovered or selected == id;
            if highlighted then
                imgui.PushStyleColor(ImGuiCol_ChildBg, hovered and { 0.16, 0.17, 0.21, 1 } or { 0.13, 0.12, 0.10, 1 });
                imgui.PushStyleColor(ImGuiCol_Border, selected == id and gold or { 0.60, 0.65, 0.75, 1 });
            end
            imgui.BeginChild('##companion', { cardWidth, cardWidth + 90 }, true);
            portrait(c, id, { cardWidth - 16, cardWidth - 16 }, not pet);
            -- Put the shiny badge on its own line and wrap long names instead
            -- of clipping both the name and ownership inside a small card.
            local name = pet and pet.name ~= '' and pet.name or entry.name;
            imgui.TextWrapped(name);
            local slot = rosterSlot(roster, id);
            imgui.TextColored(shinyForm and gold or dim, shinyForm and 'Shiny' or entry.family);
            imgui.TextColored(selected == id and gold or slot and green or dim,
                selected == id and 'Selected' or slot and 'Slot ' .. slots[slot] or pet and 'Registered' or '?');
            if hovered then
                imgui.SetMouseCursor(ImGuiMouseCursor_Hand or 7);
                literalTooltip(c.label(id) .. ' | ' .. entry.family .. (pet and '' or '\nUndiscovered'));
            end
            imgui.EndChild();
            if highlighted then imgui.PopStyleColor(2); end
            imgui.PopID();
        end
    end
    imgui.PopStyleVar();
    if total > 0 then imgui.SetCursorPosY(origin + total * rowHeight); imgui.Dummy({ 1, 1 }); end
    if visible == 0 then imgui.TextColored(dim, 'No companions match.'); end
    imgui.EndChild();
    habitats(c, habitatHeight);
    imgui.EndChild();
    if sideBySide then imgui.SameLine(); end
    imgui.BeginChild('##bstdetails', { detailWidth, sideBySide and 0 or 400 }, true);
    local pet, entry = state.owned[selected], c.catalog[math.floor(selected / 2)];
    -- Every companion reserves the same identity rows, including unnamed forms.
    imgui.Text(c.label(selected));
    if selected % 2 == 1 then
        tip(c.label(selected) .. '\nShiny: +10% base HP, STR, DEX, VIT, AGI, INT, MND, CHR, attack, defense, accuracy and evasion.\nRounded down, before gear and buffs.');
    else
        tip(c.label(selected));
    end
    imgui.TextColored(dim, pet and pet.name ~= '' and entry.name or (selected % 2 == 1 and 'Shiny' or 'Regular'));
    imgui.TextColored(dim, entry.family .. ' family');
    local portraitSize = math.min(220, detailWidth - 32);
    portrait(c, selected, { portraitSize, portraitSize }, not pet);
    imgui.TextColored(dim, pet and pet.level > 0 and string.format('Lv.%d   HP %d   TP %d', pet.level, pet.hp, pet.tp) or pet and 'Registered' or 'Not registered');
    local _, fontHeight = measure('Rename');
    local actionHeight = math.max(24, (fontHeight or 16) + 8);
    if pet then
        if button('Rename', not c.readOnly and not c.pending, { 0, actionHeight }) then renameOpen = true; end
        local slot = rosterSlot(roster, selected);
        if slot then imgui.SameLine(); imgui.TextColored(green, 'Slot ' .. slots[slot]);
        else
            imgui.SameLine();
            for index = 1, 3 do
                if index > 1 then imgui.SameLine(); end
                if button(slots[index] .. '##assign', not c.readOnly and not c.pending, { measure(slots[index]) + 12, actionHeight }) then assign(index, selected); end
                tip('Assign to slot ' .. slots[index] .. ' in ' .. (editing and editing.name or 'Current') .. ' at the Stable Master.' .. (roster.roster[index] ~= 0 and (' Replaces ' .. c.label(roster.roster[index]) .. '.') or ''));
            end
        end
    else
        button('Rename', false, { 0, actionHeight });
        tip('Register this companion to rename or assign it.');
    end
    if button(habitatOpen and 'Hide habitats' or 'Find in the wild', not c.pending) then
        habitatOpen = not habitatOpen;
        if habitatOpen and (not c.habitats or c.habitats.id ~= math.floor(selected / 2)) then c.find(math.floor(selected / 2)); end
    end
    imgui.Spacing();
    local gauge;
    if c.combatEnabled then gauge = M.charges(c.cooldowns); end
    readyMoves(entry, gauge);
    if #state.captures > 0 then
        imgui.Spacing(); imgui.TextColored(gold, 'CAPTURED JUGS');
        for _, capture in ipairs(state.captures) do
            imgui.TextWrapped(c.label(capture.companion));
            if button('Register##jug' .. capture.token, not c.readOnly and not c.pending) then c.register(capture.token); end
            tip('Keep the jug in your inventory and stand near the Stable Master.');
        end
    end
    imgui.EndChild();
    popup(c);
    imgui.EndChild();
end

return M;
