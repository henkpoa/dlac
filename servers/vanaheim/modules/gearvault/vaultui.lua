--[[
    vanaheim/gearvault/vaultui.lua -- the Gear Vault TAB (slice 2; layout
    reworked to Henrik's field notes, 2026-08-26: "slice the sections
    vertically... adapt to All Equipment look... know the stats").

    Two PANES side by side, splitting VERTICALLY so both scale to hundreds
    of rows: THIS JOB'S LAYOUT on the left, THE VAULT on the right. Both
    panes wear the All Equipment look -- collapsible per-slot sections
    (Main/Range nest their weapon categories), counts on every header,
    search force-opens the tree -- and every row shows Lv + the stat
    summary inline and the STANDARD item hover card (host.services
    .itemTooltip, the same renderer every other gear line uses), so vault
    gear reads like gear, not like a name list.

    Registered on the uihost by this pack module's init: the tab exists
    only where the pack mounts, and shows through the gear-only surface
    default because the gate never hides a label it cannot name (ADR 0037).

    Withdraw (the slice's one write verb) rides each vault row. dlac does
    not know the Void Wardens' coordinates (server data, deliberately not
    in the pack), so the button is always live and a TOO_FAR refusal says
    in words where to stand.

    Everything is read at CALL time from host.services (the uihost law)
    and every text sink goes through fmt.esc (SetTooltip/TextColored are
    printf -- the imgui geometry law).
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

local imgui  = try('imgui');
local host   = try('dlac\\ui\\uihost');
local icons  = try('dlac\\ui\\itemicons');
local fmt    = try('dlac\\gear\\gearfmt');
local uistyl = try('dlac\\ui\\uistyle');
local vc     = require('dlac\\servers\\vanaheim\\modules\\gearvault\\vaultclient');

local esc = (fmt ~= nil and type(fmt.esc) == 'function') and fmt.esc or function(s) return tostring(s or ''); end

local function chat(msg)
    local cf = try('dlac\\chatfmt');
    if cf ~= nil and type(cf.print) == 'function' then pcall(cf.print, '[dlac] ' .. tostring(msg));
    else print('[dlac] ' .. tostring(msg)); end
end

-- ---------------------------------------------------------------------------
-- Small readers
-- ---------------------------------------------------------------------------

local function services()
    return (host ~= nil) and host.services or {};
end

-- Item display name: the shared service first (client-spelling), '#id' last.
local function nameOf(id)
    local S = services();
    if type(S.displayName) == 'function' then
        local ok, n = pcall(S.displayName, id);
        if ok and type(n) == 'string' and n ~= '' then return n; end
    end
    return '#' .. tostring(id);
end

local function recOf(id)
    local S = services();
    if type(S.lookupById) == 'function' then
        local ok, r = pcall(S.lookupById, id);
        if ok and type(r) == 'table' then return r; end
    end
    return nil;
end

local ZERO24 = string.rep('\0', 24);

local function isAugmented(identity)
    return type(identity) == 'string' and #identity > 0 and identity ~= ZERO24;
end

-- The standard hover card, or a plain name tooltip when the record (or the
-- service) is missing -- a hover must never answer NOTHING.
local function hoverCard(rec, name)
    if not imgui.IsItemHovered() then return; end
    local S = services();
    if rec ~= nil and type(S.itemTooltip) == 'function' then
        local ok = pcall(S.itemTooltip, rec);
        if ok then return; end
    end
    pcall(imgui.SetTooltip, esc(name));
end

-- Shelf occupancy: used/max over Wardrobes 1-8 (cids 8, 10-16 -- NOT
-- contiguous, 9 is Mog Safe 2). Live client read, cached a beat.
local WARDROBES = { 8, 10, 11, 12, 13, 14, 15, 16 };
local _occ = nil;
local _occAt = 0;
local function shelfOccupancy()
    local now = os.clock();
    if _occ ~= nil and now - _occAt < 2.0 then return _occ; end
    _occAt = now;
    local used, max = 0, 0;
    local ok = pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for _, cid in ipairs(WARDROBES) do
            local m = inv:GetContainerCountMax(cid) or 0;
            if m > 0 then
                max = max + m;
                used = used + (inv:GetContainerCount(cid) or 0);
            end
        end
    end);
    _occ = ok and { used = used, max = max } or { used = 0, max = 0 };
    return _occ;
end

-- ---------------------------------------------------------------------------
-- Withdraw feedback -- one remembered line under the panes, plus chat (the
-- field is where withdraws happen to fail, and the tab may be closed by then).
-- ---------------------------------------------------------------------------
local _lastMsg = nil;      -- { text, err = bool }

local WITHDRAW_WORDS = {
    [1] = 'partly withdrawn -- your bags filled up',
    [2] = 'nothing to withdraw',
    [4] = 'that item is busy',
    [5] = 'the vault no longer holds that -- re-syncing',
    [6] = 'your bags are full -- nothing withdrawn',
    [7] = 'you already hold that RARE item',
    [8] = 'the server is busy -- try again',
    [9] = 'the vault store errored -- nothing moved',
};

local ERR_WORDS = {
    too_far     = 'stand at a Void Warden to withdraw',
    busy        = 'the server is busy -- try again',
    unavailable = 'the vault is unavailable right now',
    timeout     = 'no answer -- outcome unknown, re-syncing the mirror',
    malformed   = 'the reply did not parse -- please report this',
};

local function noteResult(text, isErr)
    _lastMsg = { text = text, err = (isErr == true) };
    chat('gear vault: ' .. text);
end

local function withdrawRow(row)
    local nm = nameOf(row.itemId);
    local okQueued = vc.requestWithdraw({ { rowId = row.rowId, qty = row.qty } }, function(acks, err)
        if acks == nil then
            noteResult(ERR_WORDS[err] or ('withdraw failed (' .. tostring(err) .. ')'), true);
            return;
        end
        local a = acks[1];
        if a == nil then return; end
        if a.moved > 0 and (a.code == 0 or a.code == vc.code.PARTIAL) then
            local tail = (a.code == vc.code.PARTIAL) and ('  (' .. WITHDRAW_WORDS[1] .. ')') or '';
            noteResult('withdrew ' .. nm .. ((a.moved > 1) and (' x' .. a.moved) or '') .. tail,
                       a.code ~= 0);
        else
            noteResult(nm .. ': ' .. (WITHDRAW_WORDS[a.code] or ('refused (code ' .. tostring(a.code) .. ')')), true);
        end
    end);
    if not okQueued then
        noteResult('could not queue the withdraw (client dormant or busy)', true);
    end
end

-- ---------------------------------------------------------------------------
-- Grouping -- the All Equipment shape: rows bucketed by the record's Slot
-- (Main/Range nest their weapon Category), unknown ids under 'Other'. Views
-- are rebuilt only when their source stamp moves.
-- ---------------------------------------------------------------------------
local function bucket(grouped, rec, entry)
    local slot = (rec ~= nil and rec.Slot) or 'Other';
    if slot == 'Main' or slot == 'Range' then
        grouped[slot] = grouped[slot] or { _cats = {} };
        local cat = (rec ~= nil and rec.Category) or '?';
        grouped[slot]._cats[cat] = grouped[slot]._cats[cat] or {};
        table.insert(grouped[slot]._cats[cat], entry);
    else
        grouped[slot] = grouped[slot] or {};
        table.insert(grouped[slot], entry);
    end
end

local function sortGroups(grouped)
    local byName = function(a, b)
        if a.name == b.name then return (a.sortKey or 0) < (b.sortKey or 0); end
        return a.name < b.name;
    end
    for _, data in pairs(grouped) do
        if data._cats ~= nil then
            for _, list in pairs(data._cats) do table.sort(list, byName); end
        else
            table.sort(data, byName);
        end
    end
end

-- The vault browser's view: mirror rows enriched with rec/name.
local _vView, _vStamp = nil, nil;
local function vaultView()
    if _vView ~= nil and _vStamp == vc.mirror.stamp then return _vView; end
    _vStamp = vc.mirror.stamp;
    local grouped, total = {}, 0;
    for _, r in ipairs(vc.mirror.rows) do
        local rec = recOf(r.itemId);
        total = total + 1;
        bucket(grouped, rec, {
            rowId = r.rowId, itemId = r.itemId, qty = r.qty, identity = r.identity,
            rec = rec, name = nameOf(r.itemId), sortKey = r.rowId,
        });
    end
    sortGroups(grouped);
    _vView = { grouped = grouped, total = total };
    return _vView;
end

-- The layout pane's view: layout entries enriched the same way.
local _lView, _lStamp = nil, nil;
local function layoutView()
    if _lView ~= nil and _lStamp == vc.layoutCache.stamp then return _lView; end
    _lStamp = vc.layoutCache.stamp;
    local grouped, total = {}, 0;
    for _, e in ipairs(vc.layoutCache.entries or {}) do
        local rec = recOf(e.itemId);
        total = total + 1;
        bucket(grouped, rec, {
            itemId = e.itemId, count = e.count, hint = e.hint, pinned = e.pinned,
            rec = rec, name = nameOf(e.itemId), sortKey = e.ordinal,
        });
    end
    sortGroups(grouped);
    _lView = { grouped = grouped, total = total };
    return _lView;
end

-- ---------------------------------------------------------------------------
-- Row + tree renderers (the All Equipment look)
-- ---------------------------------------------------------------------------

-- One row: icon, name (fixed column), Lv, stat summary -- then the caller's
-- trailing decorations. The standard card on hovering the name.
local function renderRow(e, level, nameW, COL, trailing)
    if icons ~= nil and type(icons.renderIcon) == 'function' then
        pcall(icons.renderIcon, e.itemId, 18);
        imgui.SameLine(0, 6);
    end
    imgui.TextColored(COL.USABLE or { 1, 1, 1, 1 }, esc(e.name));
    hoverCard(e.rec, e.name);
    local nameCol = 26 + (nameW or 200);
    if e.rec ~= nil then
        imgui.SameLine(nameCol);
        imgui.TextColored(COL.LEVEL or COL.DIM, string.format('Lv%2d', e.rec.Level or 0));
        local ss = (fmt ~= nil and type(fmt.statSummary) == 'function') and fmt.statSummary(e.rec, level) or '';
        if ss ~= '' then
            imgui.SameLine(nameCol + 46);
            imgui.TextColored(COL.STATS or COL.DIM, esc(ss));
        end
    end
    if type(trailing) == 'function' then trailing(); end
end

-- The name-column width for a group (fmt.nameWidthOf wants records with .Name).
local function widthOf(list)
    if fmt ~= nil and type(fmt.nameWidthOf) == 'function' then
        local ok, w = pcall(fmt.nameWidthOf, list);
        if ok and type(w) == 'number' then return w; end
    end
    return 200;
end

-- The slot order the All Equipment tree walks, from the shared services --
-- falling back to alphabetical pairs() order only when the service is absent.
local function slotOrder(grouped)
    local S = services();
    local order = {};
    local seen = {};
    for _, slot in ipairs(S.SLOT_TREE_ORDER or {}) do
        if grouped[slot] ~= nil then order[#order + 1] = slot; seen[slot] = true; end
    end
    local extra = {};
    for slot in pairs(grouped) do
        if not seen[slot] then extra[#extra + 1] = slot; end
    end
    table.sort(extra);
    for _, slot in ipairs(extra) do order[#order + 1] = slot; end
    return order;
end

-- One pane's tree: collapsible slot sections, Main/Range nesting categories.
-- `idp` keeps the two panes' imgui ids apart. Searching force-opens every
-- section; clearing the search collapses them once (the All Equipment
-- idiom, so the tree does not stay sprawled after a lookup).
local function renderTree(view, idp, searching, forceClose, level, COL, rowTail)
    local S = services();
    local function renderList(list)
        local nW = widthOf(list);
        for _, e in ipairs(list) do renderRow(e, level, nW, COL, rowTail and rowTail(e) or nil); end
    end
    local function arm()
        if searching then imgui.SetNextItemOpen(true);
        elseif forceClose then imgui.SetNextItemOpen(false); end
    end
    for _, slot in ipairs(slotOrder(view.grouped)) do
        local data = view.grouped[slot];
        local cnt = 0;
        if data._cats ~= nil then
            for _, list in pairs(data._cats) do cnt = cnt + #list; end
        else
            cnt = #data;
        end
        if cnt > 0 then
            arm();
            if imgui.CollapsingHeader(string.format('%s (%d)###gvh%s_%s', slot, cnt, idp, slot)) then
                if data._cats ~= nil then
                    local seen = {};
                    local function renderCat(cat)
                        local list = data._cats[cat];
                        if list == nil or #list == 0 then return; end
                        seen[cat] = true;
                        arm();
                        if imgui.TreeNode(string.format('%s (%d)###gvc%s_%s_%s', cat, #list, idp, slot, cat)) then
                            renderList(list);
                            imgui.TreePop();
                        end
                    end
                    for _, cat in ipairs((S.CAT_ORDER or {})[slot] or {}) do renderCat(cat); end
                    local extra = {};
                    for cat in pairs(data._cats) do if not seen[cat] then extra[#extra + 1] = cat; end end
                    table.sort(extra);
                    for _, cat in ipairs(extra) do renderCat(cat); end
                else
                    renderList(data);
                end
            end
        end
    end
end

-- A filtered COPY of a view for the search needle (name substring).
local function filterView(view, needle)
    if needle == '' then return view; end
    local out = { grouped = {}, total = 0 };
    for slot, data in pairs(view.grouped) do
        if data._cats ~= nil then
            for cat, list in pairs(data._cats) do
                for _, e in ipairs(list) do
                    if string.find(string.lower(e.name), needle, 1, true) ~= nil then
                        out.grouped[slot] = out.grouped[slot] or { _cats = {} };
                        out.grouped[slot]._cats[cat] = out.grouped[slot]._cats[cat] or {};
                        table.insert(out.grouped[slot]._cats[cat], e);
                        out.total = out.total + 1;
                    end
                end
            end
        else
            for _, e in ipairs(data) do
                if string.find(string.lower(e.name), needle, 1, true) ~= nil then
                    out.grouped[slot] = out.grouped[slot] or {};
                    table.insert(out.grouped[slot], e);
                    out.total = out.total + 1;
                end
            end
        end
    end
    return out;
end

local _search = { '' };

-- Layout ask throttle: the tab re-asks a stale layout at most this often.
local _layoutAskAt = 0;
local LAYOUT_ASK_GAP = 3.0;

-- The layout pane's fixed width: enough for name + Lv + a stat clip.
local LEFT_W = 360;

-- ---------------------------------------------------------------------------
-- The tab
-- ---------------------------------------------------------------------------
function M.render(job, level)
    if imgui == nil then return; end
    local S   = services();
    local COL = S.COL or {};
    local cERR   = COL.ERR    or { 1.00, 0.45, 0.40, 1.00 };
    local cDIM   = COL.DIM    or { 0.70, 0.70, 0.70, 1.00 };
    local cHEAD  = COL.HEADER or { 0.60, 0.75, 1.00, 1.00 };
    local cGOLD  = COL.SCORE  or { 0.95, 0.85, 0.45, 1.00 };
    local cVAULT = COL.VAULT  or { 0.72, 0.55, 0.95, 1.00 };

    -- ---- status header (full width) ----
    local state = vc.state();
    if state == 'dormant' then
        imgui.TextColored(cDIM, 'The Gear Vault is not available on this server (or the addon was refused).');
        return;
    end
    local n = 0;
    for _, r in ipairs(vc.mirror.rows) do n = n + math.max(1, r.qty); end
    imgui.TextColored(cVAULT, string.format('Vault: %d instance%s', n, (n == 1) and '' or 's'));
    imgui.SameLine(0, 10);
    imgui.TextColored((state == 'fresh') and cDIM or cGOLD, '[' .. state .. ']');
    if imgui.IsItemHovered() then
        imgui.SetTooltip('fresh -- the mirror matches the server.\nstale -- something moved (job change, !vault, zoning); a re-sync is due.\nsyncing -- pages are on the wire now.');
    end
    imgui.SameLine(0, 12);
    local occ = shelfOccupancy();
    if occ.max > 0 then
        imgui.TextColored(cDIM, string.format('Shelf (Wardrobes 1-8): %d/%d', occ.used, occ.max));
        if imgui.IsItemHovered() then
            imgui.SetTooltip('The wardrobes are the vault\'s CACHE on this server: the active job\'s\nworking set, swapped automatically at job change. dlac never writes them.');
        end
        imgui.SameLine(0, 12);
    end
    if imgui.SmallButton('Sync##gvsync') then
        vc.refresh();
        vc.requestLayout(0);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Re-read the vault and the layout from the server now.');
    end
    imgui.SameLine(0, 12);
    imgui.TextColored(cDIM, 'Search:');
    imgui.SameLine(0, 4);
    imgui.PushItemWidth(160);
    imgui.InputText('##gvsearch', _search, 64);
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then imgui.SetTooltip('Filter BOTH panes by name.'); end

    imgui.Separator();

    local needle = string.lower(tostring(_search[1] or ''));
    local searching = (needle ~= '');
    local forceClose = (not searching) and (M._wasSearching == true);
    M._wasSearching = searching;

    -- ---- left pane: this job's layout ----
    local lc = vc.layoutCache;
    if not lc.fresh and os.clock() - _layoutAskAt > LAYOUT_ASK_GAP then
        _layoutAskAt = os.clock();
        vc.requestLayout(0);
    end
    imgui.BeginChild('##gvleft', { LEFT_W, -24 }, false);
    if uistyl ~= nil and type(uistyl.helpLabel) == 'function' then
        uistyl.helpLabel(imgui, 'This job\'s layout', 'What the SERVER holds for your current main job -- every entry here\nis pulled onto the shelf at job change, wherever it came from (dlac,\n!vault, the website). Editing from this tab arrives in the next slice;\nuntil then: !vault add/remove <item>, in a city.', cHEAD);
    else
        imgui.TextColored(cHEAD, 'This job\'s layout');
    end
    if not lc.fresh then
        imgui.SameLine(0, 8);
        imgui.TextColored(cGOLD, '(fetching...)');
    end
    local lv = filterView(layoutView(), needle);
    if lv.total > 0 then
        renderTree(lv, 'L', searching, forceClose, level, COL, function(e)
            return function()
                if e.count > 1 then
                    imgui.SameLine(0, 6);
                    imgui.TextColored(cDIM, 'x' .. e.count);
                end
                if e.pinned then
                    imgui.SameLine(0, 8);
                    imgui.TextColored(cGOLD, '[pin]');
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip('Soft-locked: no automation may remove this entry without asking you.');
                    end
                end
            end;
        end);
    elseif lc.fresh then
        imgui.TextColored(cDIM, searching and 'Nothing in the layout matches.' or 'No entries yet -- this job\'s shelf empties at the next job change.');
    end
    imgui.EndChild();

    imgui.SameLine(0, 10);

    -- ---- right pane: the vault ----
    imgui.BeginChild('##gvright', { -1, -24 }, false);
    if uistyl ~= nil and type(uistyl.helpLabel) == 'function' then
        uistyl.helpLabel(imgui, 'Vault contents', 'Everything in your Gear Vault (the server-side void space).\nWithdraw needs a Void Warden nearby -- the button says so if you are not.', cHEAD);
    else
        imgui.TextColored(cHEAD, 'Vault contents');
    end
    local vv = filterView(vaultView(), needle);
    if vv.total > 0 then
        renderTree(vv, 'V', searching, forceClose, level, COL, function(e)
            return function()
                if e.qty > 1 then
                    imgui.SameLine(0, 6);
                    imgui.TextColored(cDIM, 'x' .. e.qty);
                end
                if isAugmented(e.identity) then
                    imgui.SameLine(0, 8);
                    imgui.TextColored(cGOLD, '[aug]');
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip('This copy carries augments or an inscription -- it comes back byte-identical.');
                    end
                end
                imgui.SameLine(0, 12);
                if imgui.SmallButton('Withdraw##gvw' .. tostring(e.rowId)) then
                    withdrawRow(e);
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Move this to your inventory. Works at a Void Warden (anywhere for a GM).');
                end
            end;
        end);
    else
        imgui.TextColored(cDIM, (vc.mirror.stamp == nil) and 'The vault has not synced yet -- try Sync.'
            or (searching and 'Nothing in the vault matches.' or 'The vault is empty.'));
    end
    imgui.EndChild();

    if _lastMsg ~= nil then
        imgui.TextColored(_lastMsg.err and cERR or cDIM, esc(_lastMsg.text));
    end
end

-- test seams
M._search = _search;
M._filterView = filterView;
function M._lastResult() return _lastMsg; end

return M;
