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
local recon  = try('dlac\\servers\\vanaheim\\modules\\gearvault\\reconcile');

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

-- The augments ON a vault instance, readable: the identity blob IS the raw
-- exdata for standard augmented gear (every byte of AugmentStandard is
-- stable -- gear-vault.md §4.6), so the oracle's augment passthrough (the
-- one door, ADR 0013 -- never feature\augments directly) decodes it as it
-- would a bag copy's Extra. nil when the blob carries no decodable augments
-- (a signature-only copy, an exotic exdata kind, headless).
local function augTextOf(identity)
    local txt = nil;
    pcall(function()
        local t = require('dlac\\gear\\gearoracle').describeAugments(identity);
        if type(t) == 'string' and t ~= '' then txt = t; end
    end);
    return txt;
end

-- The standard item card, unconditionally -- callers decide WHAT was hovered
-- (a name, or a whole row). `augText` (a vault copy's decoded augments)
-- rides IN as the record's AugText, so the card prints it gold in its own
-- Aug: seat right under the stats -- never a second tooltip stacked on top
-- (Henrik's screenshot round, 2026-08-26). Falls to a plain name tooltip
-- when the record or the service is missing: a hover must never answer
-- NOTHING.
local function showCard(rec, name, augText)
    local S = services();
    if rec ~= nil and type(S.itemTooltip) == 'function' then
        local r = rec;
        if type(augText) == 'string' and augText ~= '' then
            r = {};
            for k, v in pairs(rec) do r[k] = v; end
            r.AugText = augText;
        end
        local ok = pcall(S.itemTooltip, r);
        if ok then return; end
    end
    pcall(imgui.SetTooltip, esc(name));
end

-- ...and the common shape: the card when the LAST item is hovered.
local function hoverCard(rec, name)
    if not imgui.IsItemHovered() then return; end
    showCard(rec, name);
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

-- One queued layout edit from a tab button. `okText` is the success line;
-- the refusal vocabulary is shared. Every accepted edit re-asks the layout
-- so the pane catches up.
local LAYOUT_CODE_WORDS = {
    [12] = 'edits to your ACTIVE job\'s layout need a city (or your Mog House)',
    [15] = 'that entry is no longer in the layout -- re-syncing the view',
    [13] = 'the server did not recognise that item',
    [9]  = 'the vault store errored -- nothing changed',
};

local function layoutEdit(e, okText)
    local queued = vc.requestLayoutSet(e, function(code, err)
        if code == vc.code.OK then
            noteResult(okText, false);
            vc.requestLayout(0);
        elseif code ~= nil then
            noteResult(LAYOUT_CODE_WORDS[code] or ('layout edit refused (code ' .. tostring(code) .. ')'), true);
            if code == vc.code.NOT_IN_LAYOUT then vc.requestLayout(0); end
        else
            noteResult(ERR_WORDS[err] or ('layout edit failed (' .. tostring(err) .. ')'), true);
        end
    end);
    if not queued then
        noteResult('could not queue the layout edit (client dormant)', true);
    end
end

-- The pinned-remove confirmation: first click arms, second click within the
-- window sends. Keyed on the entry so two rows can never confirm each other.
local _confirm = nil;     -- { key, at }
local function confirmArmed(key)
    return _confirm ~= nil and _confirm.key == key and (os.clock() - _confirm.at) < 5.0;
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
            identity = e.identity,
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

-- One gear piece = ONE row (Henrik's ruling, 2026-08-26: "stats are mostly
-- relevant when building the sets anyway, we want a quick overview"): icon +
-- name + Lv + the caller's tags, with the two action buttons in FIXED
-- COLUMNS against the right edge so every row's buttons line up. The stats
-- live in the hover card. The whole row -- buttons included -- highlights
-- as one (a full-width Selectable underneath, lit from LAST frame's hot row
-- so a button hover keeps it glowing -- the one-frame lag no eye can see),
-- and hovering anywhere on it shows the standard item card; the buttons
-- keep their own tooltips.
--
-- deco = { key = unique row id, tags = fn() inline after the name,
--          buttons = fn(hot, b1, b2) -- draws at the columns, calls hot()
--          after any hovered button }. Overlay mechanics: remember Y, lay
-- the Selectable, rewind, draw content over it, then normalize Y.
local _hotKey, _hotNext = nil, nil;
local function renderRow(e, level, COL, deco)
    deco = deco or {};
    local rowH = 19;
    local w = 420;
    pcall(function()
        local ww = imgui.GetWindowWidth();
        if type(ww) == 'number' and ww > 200 then w = ww; end
    end);
    local b2 = w - 84;          -- second button column (Withdraw / Remove)
    local b1 = b2 - 84;         -- first button column (Layout / Pin)

    local y0 = imgui.GetCursorPosY();
    pcall(function() imgui.SetNextItemAllowOverlap(); end);
    imgui.Selectable('##gvrow' .. tostring(deco.key or e.name), _hotKey ~= nil and _hotKey == deco.key,
        ImGuiSelectableFlags_None or 0, { math.max(60, w - 24), rowH });
    local rowHovered = imgui.IsItemHovered();
    imgui.SetCursorPosY(y0);

    if icons ~= nil and type(icons.renderIcon) == 'function' then
        pcall(icons.renderIcon, e.itemId, 18);
        imgui.SameLine(0, 6);
    end
    imgui.TextColored(COL.USABLE or { 1, 1, 1, 1 }, esc(e.name));
    if e.rec ~= nil then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL.LEVEL or COL.DIM, string.format('Lv%d', e.rec.Level or 0));
    end
    if type(deco.tags) == 'function' then deco.tags(); end
    if type(deco.buttons) == 'function' then
        deco.buttons(function()
            if deco.key ~= nil then _hotNext = deco.key; end
        end, b1, b2);
    end
    -- No trailing SetCursorPosY: the content line's own advance matches the
    -- one-line Selectable's, and the newer ImGui ASSERTS on a cursor moved
    -- past the last submitted item ("please submit an item e.g. Dummy()") --
    -- Henrik's screenshot, 2026-08-26.

    if rowHovered then
        if deco.key ~= nil then _hotNext = deco.key; end
        showCard(e.rec, e.name, (type(deco.augOf) == 'function') and deco.augOf() or nil);
    end
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
        for _, e in ipairs(list) do renderRow(e, level, COL, rowTail and rowTail(e) or nil); end
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

-- ---------------------------------------------------------------------------
-- The Inventory sub-tab's list: storable gear sitting in the INVENTORY bag
-- (container 0) right now. dlac's own filter mirrors the server's structural
-- rules where it can: known equipment only (the catalog is gear-only, which
-- IS the equipment test) and never cat-15 ammo (void-storage territory).
-- Equipped/busy pieces stay listed -- the server refuses those per row with
-- its own words. Cached a beat; a deposit ack drops the cache.
-- ---------------------------------------------------------------------------
local _inv, _invAt = nil, 0;
M._invOverride = nil;   -- test seam
local function inventoryStorable()
    if M._invOverride ~= nil then return M._invOverride; end
    local now = os.clock();
    if _inv ~= nil and now - _invAt < 2.0 then return _inv; end
    _invAt = now;
    local out = {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local max = inv:GetContainerCountMax(0) or 0;
        for idx = 0, max do
            local entry = inv:GetContainerItem(0, idx);
            if entry ~= nil and entry.Id ~= nil and entry.Id ~= 0 and entry.Id ~= 65535 then
                local rec = recOf(entry.Id);
                if rec ~= nil and rec.Slot ~= 'Ammo' then
                    out[#out + 1] = {
                        container = 0, slot = idx, itemId = entry.Id,
                        qty = math.max(1, entry.Count or 1),
                        rec = rec, name = rec.Name or nameOf(entry.Id),
                        sortKey = idx,
                    };
                end
            end
        end
    end);
    _inv = out;
    return out;
end

local function invalidateInv() _invAt = 0; end

-- One deposit run (Store / Store all): entries from the inventory list.
local DEPOSIT_WORDS = {
    [3]  = 'not vault gear',
    [4]  = 'equipped or busy',
    [10] = 'the vault already holds its copy (duplicates are refused -- future scrap fodder)',
    [9]  = 'the vault store errored',
};
local function storeRows(rows)
    local list = {};
    for _, r in ipairs(rows) do
        list[#list + 1] = { container = r.container, slot = r.slot };
    end
    local queued = vc.requestDeposit(list, function(acks, err)
        invalidateInv();
        if acks == nil then
            noteResult((err == 'too_far') and 'stand at a Void Warden to store'
                or (ERR_WORDS[err] or ('store failed (' .. tostring(err) .. ')')), true);
            return;
        end
        local stored, dupes, refused = 0, 0, 0;
        for _, a in ipairs(acks) do
            if a.code == vc.code.OK or a.code == vc.code.PARTIAL then stored = stored + 1;
            elseif a.code == vc.code.DUPLICATE then dupes = dupes + 1;
            else refused = refused + 1; end
        end
        if #acks == 1 and stored == 0 then
            noteResult((rows[1] and rows[1].name or 'that piece') .. ': '
                .. (DEPOSIT_WORDS[acks[1].code] or ('refused (code ' .. tostring(acks[1].code) .. ')')), true);
        else
            noteResult(string.format('stored %d piece%s%s%s', stored, (stored == 1) and '' or 's',
                (dupes > 0) and (' -- ' .. dupes .. ' duplicate(s) kept in your bags') or '',
                (refused > 0) and (' -- ' .. refused .. ' refused') or ''), stored == 0);
        end
    end);
    if not queued then
        noteResult('could not queue the store (client dormant, or too many at once)', true);
    end
end

-- Sub-tab selection. The order is FIXED -- Vault, then Inventory (Henrik:
-- "keep it to the right of Vault") -- so the ADR 0033 rebuild trick is out
-- (it selects by submitting first). On re-entering the Gear Vault tab with
-- storable gear, the SetSelected flag rides Inventory's BeginTabItem for a
-- few passes instead: this build's newer binding may honour it (the old
-- one demonstrably dropped it -- ADR 0033), and when it does not, the gold
-- label still points the way. Either way the order never moves.
local _sub = { want = 0, lastSeen = 0 };

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
    -- HALF the window each (Henrik: "take 50% of the space, not a set
    -- amount"), split live from the available width so a resized window
    -- keeps the ratio. GetContentRegionAvail's first return is the width.
    local availW = 700;
    pcall(function()
        local w = imgui.GetContentRegionAvail();
        if type(w) == 'number' and w > 0 then availW = w; end
    end);
    imgui.BeginChild('##gvleft', { math.floor(availW * 0.5) - 6, -24 }, false);
    if uistyl ~= nil and type(uistyl.helpLabel) == 'function' then
        uistyl.helpLabel(imgui, 'This job\'s layout', 'What the SERVER holds for your current main job -- every entry here\nis pulled onto the shelf at job change, wherever it came from (dlac,\n!vault, the website). Editing from this tab arrives in the next slice;\nuntil then: !vault add/remove <item>, in a city.', cHEAD);
    else
        imgui.TextColored(cHEAD, 'This job\'s layout');
    end
    if not lc.fresh then
        imgui.SameLine(0, 8);
        imgui.TextColored(cGOLD, '(fetching...)');
    end
    if recon ~= nil and type(recon.cityBlocked) == 'function' and recon.cityBlocked() then
        imgui.TextColored(cGOLD, 'Additions from your sets are waiting for a city.');
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Edits to your ACTIVE job\'s layout move gear live, so the server only\ntakes them in a city (or your Mog House). They push by themselves when\nyou get there; other jobs\' layouts save from anywhere.');
        end
    end
    local lv = filterView(layoutView(), needle);
    if lv.total > 0 then
        renderTree(lv, 'L', searching, forceClose, level, COL, function(e)
            return {
                key = 'L' .. tostring(e.sortKey),
                augOf = function() return isAugmented(e.identity) and augTextOf(e.identity) or nil; end,
                tags = function()
                    if e.count > 1 then
                        imgui.SameLine(0, 6);
                        imgui.TextColored(cDIM, 'x' .. e.count);
                    end
                    if isAugmented(e.identity) then
                        imgui.SameLine(0, 8);
                        imgui.TextColored(cGOLD, '[aug]');
                        if imgui.IsItemHovered() then
                            showCard(e.rec, e.name, augTextOf(e.identity));
                        end
                    end
                end,
                buttons = function(hot, b1, b2)
                    imgui.SameLine(b1);
                    local pinLabel = (e.pinned and 'Unpin' or 'Pin') .. '##gvp' .. tostring(e.sortKey);
                    if e.pinned then imgui.PushStyleColor(ImGuiCol_Button, { 0.55, 0.45, 0.15, 1.0 }); end
                    if imgui.SmallButton(pinLabel) then
                        layoutEdit({ job = 0, verb = vc.verb.PIN, itemId = e.itemId, count = e.count,
                                     hint = e.hint or 0, pinned = not e.pinned, identity = e.identity },
                            e.pinned and (e.name .. ' unpinned') or (e.name .. ' pinned -- automations must ask before touching it'));
                    end
                    if e.pinned then imgui.PopStyleColor(1); end
                    if imgui.IsItemHovered() then
                        hot();
                        imgui.SetTooltip(e.pinned
                            and 'Pinned (soft-locked): no automation may remove this entry without asking.\nClick to release the pin.'
                            or  'Pin (soft-lock) this entry: dlac\'s own automation must ask you before\nremoving it, even in space-pressure cleanups.');
                    end
                    imgui.SameLine(b2);
                    local rkey = 'rm' .. tostring(e.sortKey);
                    local armed = e.pinned and confirmArmed(rkey);
                    if armed then imgui.PushStyleColor(ImGuiCol_Button, { 0.75, 0.25, 0.20, 1.0 }); end
                    if imgui.SmallButton((armed and 'Sure?' or 'Remove') .. '##gvr' .. tostring(e.sortKey)) then
                        if e.pinned and not armed then
                            _confirm = { key = rkey, at = os.clock() };
                        else
                            _confirm = nil;
                            layoutEdit({ job = 0, verb = vc.verb.REMOVE, itemId = e.itemId, count = 0,
                                         hint = 0, pinned = false, identity = e.identity },
                                e.name .. ' removed from the layout');
                        end
                    end
                    if armed then imgui.PopStyleColor(1); end
                    if imgui.IsItemHovered() then
                        hot();
                        imgui.SetTooltip(e.pinned
                            and 'Remove this PINNED entry -- takes a second click to confirm.\nThe piece itself stays in the vault; only the layout forgets it.'
                            or  'Remove from this job\'s layout. The piece stays in the vault;\nthe shelf drops it at the next job change or live edit.');
                    end
                end,
            };
        end);
    elseif lc.fresh then
        imgui.TextColored(cDIM, searching and 'Nothing in the layout matches.' or 'No entries yet -- this job\'s shelf empties at the next job change.');
    end
    imgui.EndChild();

    imgui.SameLine(0, 10);

    -- ---- right pane: Vault | Inventory sub-tabs (Henrik, 2026-08-26) ----
    imgui.BeginChild('##gvright', { -1, -24 }, false);

    local invList = inventoryStorable();
    local nowClock = os.clock();
    local reentered = (nowClock - _sub.lastSeen) > 1.0;
    _sub.lastSeen = nowClock;
    if reentered and #invList > 0 then
        -- auto-switch attempt: opening the Gear Vault tab with storable gear
        -- lands you on Inventory, ready to Store (see _sub's comment)
        _sub.want = 3;
    end

    local function renderVaultTab()
        local vv = filterView(vaultView(), needle);
        if vv.total > 0 then
            renderTree(vv, 'V', searching, forceClose, level, COL, function(e)
                return {
                    key = 'V' .. tostring(e.rowId),
                    augOf = function() return isAugmented(e.identity) and augTextOf(e.identity) or nil; end,
                    tags = function()
                        if e.qty > 1 then
                            imgui.SameLine(0, 6);
                            imgui.TextColored(cDIM, 'x' .. e.qty);
                        end
                        if isAugmented(e.identity) then
                            imgui.SameLine(0, 8);
                            imgui.TextColored(cGOLD, '[aug]');
                            if imgui.IsItemHovered() then
                                showCard(e.rec, e.name, augTextOf(e.identity));
                            end
                        end
                    end,
                    buttons = function(hot, b1, b2)
                        imgui.SameLine(b1);
                        if imgui.SmallButton('Layout##gvl' .. tostring(e.rowId)) then
                            layoutEdit({ job = 0, verb = vc.verb.ADD, itemId = e.itemId, count = 1,
                                         hint = 0, pinned = false, identity = e.identity },
                                e.name .. ' added to this job\'s layout');
                        end
                        if imgui.IsItemHovered() then
                            hot();
                            imgui.SetTooltip('Add THIS copy (augments included) to your current main job\'s layout.\nLive in a city (or your Mog House); refused in the field.');
                        end
                        imgui.SameLine(b2);
                        if imgui.SmallButton('Withdraw##gvw' .. tostring(e.rowId)) then
                            withdrawRow(e);
                        end
                        if imgui.IsItemHovered() then
                            hot();
                            imgui.SetTooltip('Move this to your inventory (at a Void Warden).');
                        end
                    end,
                };
            end);
        else
            imgui.TextColored(cDIM, (vc.mirror.stamp == nil) and 'The vault has not synced yet -- try Sync.'
                or (searching and 'Nothing in the vault matches.' or 'The vault is empty.'));
        end
    end

    local function renderInvTab()
        -- FLAT list, no category tree (Henrik: "skip the categories in
        -- Inventory, it can't hold that much anyway") -- sorted by name,
        -- the same two-row rows as everywhere else.
        local shown = {};
        for _, r in ipairs(invList) do
            if needle == '' or string.find(string.lower(r.name), needle, 1, true) ~= nil then
                shown[#shown + 1] = r;
            end
        end
        table.sort(shown, function(a, b)
            if a.name == b.name then return a.slot < b.slot; end
            return a.name < b.name;
        end);
        if #shown > 0 then
            if imgui.SmallButton(string.format('Store all (%d)##gvsa', #shown)) then
                storeRows(shown);
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Deposit every listed piece into the Gear Vault.\nWorks at a Void Warden. Equipped pieces and\nduplicates are refused per item and stay in your bags.');
            end
            imgui.SameLine(0, 10);
            imgui.TextColored(cDIM, 'Storable gear in your inventory:');
            -- ONE row per piece here (the hover card carries the stats), with
            -- every Store button flush against the right edge so they line up
            -- in a clean column.
            local btnCol = 340;
            pcall(function()
                local w = imgui.GetWindowWidth();
                if type(w) == 'number' and w > 120 then btnCol = w - 62; end
            end);
            -- Each row rides an invisible full-row Selectable (the Sets-tab /
            -- alternatives idiom): hovering ANYWHERE on the row -- the Store
            -- button included -- highlights the whole line, so the eye can
            -- pair a name with its far-right button without aiming at the
            -- text. The button sits OUTSIDE the Selectable (the automationsui
            -- law: two click targets never share a pixel), so its hover
            -- cannot light the Selectable natively -- instead LAST frame's
            -- hot row renders selected=true (the Header fill), a one-frame
            -- lag no eye can see. Row hover shows the item card; button
            -- hover keeps its own words.
            local hotNow = nil;
            for _, e in ipairs(shown) do
                if icons ~= nil and type(icons.renderIcon) == 'function' then
                    pcall(icons.renderIcon, e.itemId, 18);
                    imgui.SameLine(0, 6);
                end
                -- explicit width: Selectable does NOT speak the child-window
                -- "-1 = fill" convention -- a negative collapses it to a stub
                -- (the sliver Henrik's screenshot caught)
                pcall(function() imgui.SetNextItemAllowOverlap(); end);
                imgui.Selectable('##gvirow' .. tostring(e.slot), M._hotRow == e.slot,
                    ImGuiSelectableFlags_None or 0, { math.max(60, btnCol + 20), 18 });
                local rowHovered = imgui.IsItemHovered();
                imgui.SameLine(26);
                imgui.TextColored(COL.USABLE or { 1, 1, 1, 1 }, esc(e.name));
                if e.rec ~= nil then
                    imgui.SameLine(0, 8);
                    imgui.TextColored(COL.LEVEL or cDIM, string.format('Lv%d', e.rec.Level or 0));
                end
                if e.qty > 1 then
                    imgui.SameLine(0, 6);
                    imgui.TextColored(cDIM, 'x' .. e.qty);
                end
                imgui.SameLine(btnCol);
                if imgui.SmallButton('Store##gvs' .. tostring(e.slot)) then
                    storeRows({ e });
                end
                local btnHovered = imgui.IsItemHovered();
                if rowHovered or btnHovered then hotNow = e.slot; end
                if btnHovered then
                    imgui.SetTooltip('Deposit this into the Gear Vault (at a Void Warden).');
                elseif rowHovered then
                    showCard(e.rec, e.name);
                end
            end
            M._hotRow = hotNow;
        else
            imgui.TextColored(cDIM, searching and 'Nothing in your inventory matches.'
                or 'No storable gear in your inventory.');
        end
    end

    -- Fixed order: Vault, then Inventory. The auto-switch is a held
    -- SetSelected flag on Inventory (see _sub's comment); a binding that
    -- drops the flag simply leaves the player one click from the gold tab.
    if imgui.BeginTabBar('##gvsub') then
        if imgui.BeginTabItem('Vault###gvtv') then
            renderVaultTab();
            imgui.EndTabItem();
        end
        local n = #invList;
        if n > 0 then imgui.PushStyleColor(ImGuiCol_Text, cGOLD); end
        local label = string.format('Inventory (%d)###gvti', n);
        local open;
        if _sub.want > 0 then
            _sub.want = _sub.want - 1;
            local ok, o = pcall(imgui.BeginTabItem, label, nil, ImGuiTabItemFlags_SetSelected or 2);
            if ok then
                open = (o and true or false);
            else
                open = (imgui.BeginTabItem(label) and true or false);
                _sub.want = 0;   -- the shape is refused on this binding: stop asking
            end
            if open then _sub.want = 0; end
        else
            open = (imgui.BeginTabItem(label) and true or false);
        end
        if n > 0 then imgui.PopStyleColor(1); end
        if open then
            renderInvTab();
            imgui.EndTabItem();
        end
        imgui.EndTabBar();
    end
    imgui.EndChild();

    if _lastMsg ~= nil then
        imgui.TextColored(_lastMsg.err and cERR or cDIM, esc(_lastMsg.text));
    end

    -- commit the hot row for next frame's highlight (the one-frame lag)
    _hotKey = _hotNext;
    _hotNext = nil;
end

-- test seams
M._search = _search;
M._filterView = filterView;
function M._lastResult() return _lastMsg; end

return M;
