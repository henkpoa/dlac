local base = 'dlac\\servers\\ascensionxi\\modules\\voidrestock\\';
local restock = require(base .. 'restock');
local model = require(base .. 'model');
local client = restock.client;
local ok, imgui = pcall(require, 'imgui');
local textures = require('dlac\\ui\\filetex');
local M = {};
local query, addTarget = { '' }, { 12 };
local edits, lastConfig = {}, nil;
-- Ashita's established fixed-column layout (E-Box uses SameLine offsets too).
-- The scroll regions have a fixed width; long names never push actions around.
local TABLE_W, INV_X, VOID_X, TARGET_X, ACTION_X = 780, 260, 350, 440, 550;
local function esc(s) return tostring(s or ''):gsub('%%', '%%%%'); end
local function open()
    require('dlac\\ui\\gearui').openAutomation('restock');
end
local function button(label, enabled, action, width)
    if not enabled then
        imgui.PushStyleColor(ImGuiCol_Button, { 0.20, 0.20, 0.22, 1 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.20, 0.20, 0.22, 1 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.20, 0.20, 0.22, 1 });
    end
    local clicked = imgui.Button(label, { width or 140, 24 });
    if not enabled then imgui.PopStyleColor(3); end
    if clicked and enabled then action(); end
end
local function nameCell(name)
    imgui.Text(esc(#name > 24 and (name:sub(1, 22) .. '..') or name));
    if imgui.IsItemHovered() then imgui.SetTooltip(esc(name)); end
end
local function header(actions)
    imgui.TextDisabled('Item'); imgui.SameLine(INV_X); imgui.TextDisabled('Inventory');
    imgui.SameLine(VOID_X); imgui.TextDisabled('Void');
    imgui.SameLine(TARGET_X); imgui.TextDisabled('Keep');
    imgui.SameLine(ACTION_X); imgui.TextDisabled(actions or 'Actions'); imgui.Separator();
end
local function countsCells(id, counts)
    imgui.SameLine(INV_X); imgui.Text(tostring(counts[id] or 0));
    imgui.SameLine(VOID_X); imgui.Text(client.fresh and tostring(client.counts[id] or 0) or '?');
end
local function copy() return model.normalize(restock.config); end
local function editList(config, scope)
    if scope == 'character' then return config.character; end
    local job = restock.job();
    config.jobs[job] = config.jobs[job] or {};
    return config.jobs[job];
end
local function drawList(scope, title, entries, counts, width)
    imgui.Separator(); imgui.Text(esc(title));
    imgui.BeginChild('##void-list-' .. scope, { width, math.min(210, math.max(65, 42 + #entries * 30)) }, true,
        ImGuiWindowFlags_HorizontalScrollbar or 2048);
    header();
    if #entries == 0 then imgui.TextDisabled('No items listed. Add one below.'); end
    for _, entry in ipairs(entries) do
        local key = scope .. ':' .. entry.id;
        edits[key] = edits[key] or { entry.target };
        imgui.PushID(key);
        nameCell(entry.name); countsCells(entry.id, counts);
        imgui.SameLine(TARGET_X); imgui.SetNextItemWidth(95); imgui.InputInt('##keep', edits[key]);
        imgui.SameLine(ACTION_X);
        button('Save', not restock.busy(), function()
            local config = copy();
            for _, e in ipairs(editList(config, scope)) do if e.id == entry.id then e.target = edits[key][1]; end end
            restock.save(config);
        end, 80);
        imgui.SameLine(ACTION_X + 90);
        button('Remove', not restock.busy(), function()
            local config = copy(); local list = editList(config, scope);
            for i, e in ipairs(list) do if e.id == entry.id then table.remove(list, i); break; end end
            restock.save(config);
        end, 90);
        imgui.PopID();
    end
    imgui.EndChild();
end
-- The same filter applies to Inventory, stored balances AND exact-name search.
function M.candidates(counts, text)
    local candidates, rows = {}, {};
    for id in pairs(counts or {}) do candidates[id] = true; end
    for id in pairs(client.counts) do candidates[id] = true; end
    if text ~= '' then
        pcall(function()
            local r = AshitaCore:GetResourceManager():GetItemByName(text, 2)
                or AshitaCore:GetResourceManager():GetItemByName(text, 0);
            if r and r.Id > 0 and r.Id < 65535 then candidates[r.Id] = true; end
        end);
    end
    for id in pairs(candidates) do
        local rec = restock.item(id);
        if rec.restockable and (text == '' or rec.name:lower():find(text:lower(), 1, true)) then rows[#rows + 1] = rec; end
    end
    table.sort(rows, function(a, b) return a.name < b.name; end);
    return rows;
end
function M.render(deps, availW)
    if not ok or not imgui then return; end
    if not restock.syncContext() then imgui.TextWrapped(esc(restock.message ~= '' and restock.message or 'Waiting for your character and job.')); return; end
    if lastConfig ~= restock.config then edits, lastConfig = {}, restock.config; end
    local plan, counts = restock.plan();
    local width = math.min(TABLE_W, tonumber(availW) or TABLE_W);
    imgui.Text('Void Restock');
    imgui.TextWrapped('Keep your chosen quantities in Inventory. Job targets override the same item on the always list. Unlisted items stay untouched.');
    local near, busy = restock.near(), restock.busy();
    imgui.TextDisabled(near and 'Void Coffer in range' or 'Move within 5 yalms of a Void Coffer to move items.');
    button('Refresh stock', near and not busy, function() client.refresh(); end);
    imgui.SameLine();
    button('Fetch shortfall', near and not busy and client.fresh and plan and #plan.fetch > 0,
        function() restock.start('fetch'); end);
    imgui.SameLine();
    button('Store excess', near and not busy and client.fresh and plan and #plan.store > 0,
        function() restock.start('store'); end);
    if busy then imgui.SameLine(); if imgui.Button('Stop') then restock.stop(); end end
    imgui.TextWrapped(esc(client.message));
    if restock.message ~= '' then imgui.TextWrapped(esc(restock.message)); end
    local nudge = { restock.config.nudge };
    if imgui.Checkbox('Show buttons near Void Coffers', nudge) then
        local config = copy(); config.nudge = nudge[1]; restock.save(config);
    end
    drawList('character', 'Always (every job)', restock.config.character, counts or {}, width);
    drawList('job', restock.job() .. ' only', restock.config.jobs[restock.job()] or {}, counts or {}, width);
    imgui.Separator(); imgui.Text('Add an item');
    imgui.SetNextItemWidth(240); imgui.InputText('Search inventory / stored stock', query, 128);
    imgui.SetNextItemWidth(95); imgui.InputInt('Target quantity', addTarget);
    local rows = M.candidates(counts, query[1]);
    local listed = { character = {}, job = {} };
    for _, e in ipairs(restock.config.character) do listed.character[e.id] = true; end
    for _, e in ipairs(restock.config.jobs[restock.job()] or {}) do listed.job[e.id] = true; end
    imgui.BeginChild('##void-picker', { width, 290 }, true, ImGuiWindowFlags_HorizontalScrollbar or 2048);
    header('Add to list');
    for i = 1, math.min(200, #rows) do
        local rec = rows[i]; imgui.PushID('add' .. rec.id);
        nameCell(rec.name); countsCells(rec.id, counts or {});
        imgui.SameLine(TARGET_X); imgui.Text(tostring(math.max(0, addTarget[1])));
        for _, scope in ipairs({ 'character', 'job' }) do
            imgui.SameLine(scope == 'character' and ACTION_X or ACTION_X + 110);
            button(scope == 'character' and '+ Always' or ('+ ' .. restock.job()), not busy and not listed[scope][rec.id], function()
                local config = copy(); local list = editList(config, scope);
                list[#list + 1] = { id = rec.id, name = rec.name, target = addTarget[1] };
                restock.save(config);
            end, 100);
        end
        imgui.PopID();
    end
    if #rows == 0 then imgui.TextDisabled('No supplies match. Gear pieces are excluded; ammo is included.'); end
    imgui.EndChild();
    if #rows > 200 then imgui.TextDisabled('Showing 200 matches; refine your search.'); end
    imgui.TextWrapped('Void Storage decides which items and tiers can be stored. Listed duplicate scrolls follow its normal sale rule.');
end
function M.trayWants()
    return restock.syncContext() and restock.config.nudge and restock.near();
end
local function trayButton(asset, fallback, tip, action)
    local tex = textures.handle(asset);
    local clicked;
    imgui.PushID('void-' .. fallback);
    imgui.PushStyleColor(ImGuiCol_Button, fallback == 'S' and { 0.42, 0.12, 0.18, 1 } or { 0.10, 0.36, 0.20, 1 });
    if tex then clicked = imgui.ImageButton(tex, { 30, 30 }, { 0, 0 }, { 1, 1 }, 3, { 0, 0, 0, 0 }, { 1, 1, 1, 1 });
    else clicked = imgui.Button(fallback, { 36, 36 }); end
    if clicked then action(); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(esc(tip .. '\nRight-click to edit your Void Restock lists.'));
        if imgui.IsMouseClicked(1) then open(); end
    end
    imgui.PopStyleColor(1); imgui.PopID();
end
function M.trayDraw()
    if not ok or not imgui or not M.trayWants() then return; end
    local plan = restock.plan();
    local ready = not restock.busy() and client.fresh and plan ~= nil;
    -- Store is always first: changing shortages never move a deposit button
    -- under a cursor aimed at Fetch. Stale counts lead to a read, never a move.
    trayButton('void_storage', 'S', 'Store excess of listed items; keep inventory targets.', function()
        if ready then restock.start('store'); elseif not restock.busy() then client.refresh(); end
    end);
    if ready and #plan.fetch > 0 then
        trayButton('void_storage', 'F', 'Fetch listed shortages from Void Storage.', function() restock.start('fetch'); end);
    end
end
return M;
