--[[
    ascensionxi/gearvault/vaultui.lua -- the Gear Vault TAB (slice 2; layout
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
local vc     = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\vaultclient');
local counts = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\layoutcounts');
local recon  = try('dlac\\servers\\ascensionxi\\modules\\gearvault\\reconcile');
local usg    = try('dlac\\servers\\ascensionxi\\modules\\gearvault\\usage');

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
    if type(identity) ~= 'string' or identity == ZERO24 then return false; end
    local ok, text = pcall(function() return require('dlac\\gear\\gearoracle').describeAugments(identity); end);
    return ok and type(text) == 'string' and text ~= '';
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
    not_attuned = 'finish The Deeper Room first -- the vault does not know you yet',
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
    [17] = 'that copy no longer exists -- sync the layout',
    [18] = 'store that copy in the vault first',
    [19] = 'that copy is already in this job\'s layout',
    [12] = 'edits to your ACTIVE job\'s layout need a city (or your Mog House)',
    [15] = 'that entry is no longer in the layout -- re-syncing the view',
    [13] = 'the server did not recognise that item',
    [9]  = 'the vault store errored -- nothing changed',
};

local function layoutEdit(e, okText)
    e.reason = e.reason or 'manual-layout';
    if (e.job or 0) == 0 then e.job = vc.currentJob() or vc.layoutCache.job or 0; end
    local queued = vc.requestLayoutSet(e, function(code, err)
        if code == vc.code.OK or code == vc.code.PARTIAL then
            if e.verb == vc.verb.ADD and e.pinned then
                -- ADD does not apply the pin flag on the server. Queue PIN
                -- before reconciliation can see the new unpinned assignment.
                layoutEdit({ job = e.job, verb = vc.verb.PIN, itemId = e.itemId,
                    instanceId = e.instanceId, identity = e.identity, count = e.count,
                    hint = e.hint or 0, pinned = true }, okText);
                return;
            end
            noteResult(code == vc.code.PARTIAL and (okText .. ' (partly applied; refreshing)') or okText, false);
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
            rowId = r.rowId, itemId = r.itemId, qty = r.qty, identity = r.identity, instanceId = r.instanceId,
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
        if e.kind ~= 2 then
        local rec = recOf(e.itemId);
        total = total + 1;
        bucket(grouped, rec, {
            itemId = e.itemId, count = e.count, hint = e.hint, pinned = e.pinned,
            identity = e.identity, instanceId = e.instanceId, ordinal = e.ordinal, kind = e.kind, state = e.state,
            location = e.location, slot = e.slot,
            rec = rec, name = nameOf(e.itemId), sortKey = e.ordinal,
        });
        end
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
--          after any hovered button,
--          b1w = optional first-column width (default 84 -- the vault pane
--          widens it for its Add to Mog Wardrobe button) }.
-- Overlay mechanics: remember Y, lay the Selectable, rewind, draw content
-- over it, then normalize Y.
local _hotKey, _hotNext = nil, nil;
local _openLayoutMenu, _layoutMenu = nil, nil;
local function renderRow(e, level, COL, deco)
    deco = deco or {};
    local rowH = 19;
    local w = 420;
    pcall(function()
        local ww = imgui.GetWindowWidth();
        if type(ww) == 'number' and ww > 200 then w = ww; end
    end);
    local b2 = w - 84;          -- second button column (Withdraw / Remove)
    local b1 = b2 - (deco.b1w or 84);   -- first button column (Pin, or the vault
                                        -- pane's wider Add to Mog Wardrobe)

    local y0 = imgui.GetCursorPosY();
    pcall(function() imgui.SetNextItemAllowOverlap(); end);
    imgui.Selectable('##gvrow' .. tostring(deco.key or e.name), _hotKey ~= nil and _hotKey == deco.key,
        ImGuiSelectableFlags_None or 0, { math.max(60, w - 24), rowH });
    local rowHovered = imgui.IsItemHovered();
    if rowHovered and deco.context and imgui.IsMouseClicked(1) then _openLayoutMenu = e; end
    imgui.SetCursorPosY(y0);

    if icons ~= nil and type(icons.renderIcon) == 'function' then
        pcall(icons.renderIcon, e.itemId, 18);
        imgui.SameLine(0, 6);
    end
    imgui.TextColored(deco.nameColor or COL.USABLE or { 1, 1, 1, 1 }, esc(e.name));
    local warningHovered = deco.warning ~= nil and imgui.IsItemHovered();
    if e.rec ~= nil then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL.LEVEL or COL.DIM, string.format('Lv%d', e.rec.Level or 0));
    end
    if type(deco.tags) == 'function' then deco.tags(); end
    if deco.warning ~= nil then
        imgui.SameLine(0, 8);
        imgui.TextColored(deco.nameColor or COL.DIM, deco.warningTag or '[In bags]');
        warningHovered = imgui.IsItemHovered() or warningHovered;
    end
    if type(deco.buttons) == 'function' then
        deco.buttons(function()
            if deco.key ~= nil then _hotNext = deco.key; end
        end, b1, b2);
    end
    -- No trailing SetCursorPosY: the content line's own advance matches the
    -- one-line Selectable's, and the newer ImGui ASSERTS on a cursor moved
    -- past the last submitted item ("please submit an item e.g. Dummy()") --
    -- Henrik's screenshot, 2026-08-26.

    if warningHovered then
        if deco.key ~= nil then _hotNext = deco.key; end
        imgui.SetTooltip(deco.warning);
    elseif rowHovered then
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

-- WHICH bag slots are on the body right now: (container*256 + slot) ->
-- { equip = equipment slot 0-15, label = 'Head' }. Read through the shared
-- EQUIP_SLOTS list and the oracle's location door (GRD1 -- never a raw
-- GetEquippedItem in a pack module). Cached a beat; the unequip path drops
-- the cache so the row re-reads the body right after its packet left.
local _worn, _wornAt = nil, 0;
M._wornOverride = nil;   -- test seam: { [container*256+slot] = { equip=, label= } }
local function wornAtSlot()
    if M._wornOverride ~= nil then return M._wornOverride; end
    local now = os.clock();
    if _worn ~= nil and now - _wornAt < 0.5 then return _worn; end
    _wornAt = now;
    local out = {};
    pcall(function()
        local S = services();
        local oracle = require('dlac\\gear\\gearoracle');
        if type(S.EQUIP_SLOTS) ~= 'table' or type(oracle.wornLocation) ~= 'function' then return; end
        for _, sl in ipairs(S.EQUIP_SLOTS) do
            local cont, idx = oracle.wornLocation(sl.equip);
            if cont ~= nil and idx ~= nil then
                out[cont * 256 + idx] = { equip = sl.equip, label = sl.label };
            end
        end
    end);
    _worn = out;
    return out;
end
local function invalidateWorn() _wornAt = 0; end

-- Text width for right-aligning a wider button against the Store column;
-- the codebase's ~9.5px/char estimate when the binding has no CalcTextSize.
local function textW(s)
    local w = #tostring(s) * 9.5;
    pcall(function()
        local m = imgui.CalcTextSize(s);
        if type(m) == 'number' then w = m; end
    end);
    return w;
end

-- One deposit run (Store / Store all): entries from the inventory list.
local DEPOSIT_WORDS = {
    [3]  = 'not vault gear',
    [4]  = 'equipped or busy',
    [10] = 'Already in gear vault',
    [9]  = 'the vault store errored',
};
local DUPLICATE_WORDS = {
    [1] = 'Already in gear vault',
    [2] = 'Already Equipped',
    [3] = 'Already in Mog Wardrobe',
};
local function storeRows(rows, afterUnequip, onDone)
    local list = {};
    for _, r in ipairs(rows) do
        list[#list + 1] = { container = r.container, slot = r.slot, expectedInstanceId = r.expectedInstanceId };
    end
    local queued = vc.requestDeposit(list, function(acks, err)
        invalidateInv();
        if type(onDone) == 'function' then pcall(onDone); end
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
            local words = DEPOSIT_WORDS[acks[1].code] or ('refused (code ' .. tostring(acks[1].code) .. ')');
            if acks[1].code == vc.code.DUPLICATE then
                words = DUPLICATE_WORDS[acks[1].duplicateLocation] or DEPOSIT_WORDS[vc.code.DUPLICATE];
            end
            if afterUnequip and acks[1].code == 4 then
                -- the deposit outran the unequip (or something dressed the
                -- slot again in between): say which race, not just "busy"
                words = 'still equipped when the store arrived -- try again';
            end
            noteResult((rows[1] and rows[1].name or 'that piece') .. ': ' .. words, true);
        else
            noteResult(string.format('stored %d piece%s%s%s', stored, (stored == 1) and '' or 's',
                (dupes > 0) and (' -- ' .. dupes .. ' duplicate(s) kept in your bags') or '',
                (refused > 0) and (' -- ' .. refused .. ' refused') or ''), stored == 0);
        end
    end);
    if not queued then
        if type(onDone) == 'function' then pcall(onDone); end
        noteResult('could not queue the store (client dormant, or too many at once)', true);
    end
end

-- UNEQUIP & STORE (Henrik, 2026-09-09: "this doesn't work for equipped
-- items"). The store refuses a worn piece per item (code 4), so a worn
-- row's button takes it off first.
--
-- THE STRIP IS A CLAIM (field round 2, the same day). Round 1's raw 0x050
-- unequip left the body for exactly one 0.4s tick: the engine's Default
-- pass, whose set still named the piece, dressed the slot straight back
-- ("I don't see the item being unequipped either") -- the Naked argument,
-- relived. So the button now arms a LEASED STRIP on the engine's Naked row
-- (dispatch.stripSlot: the slot claims 'remove' on every dispatch until
-- released or the lease runs out), and the engine itself takes the piece
-- off and HOLDS the slot bare. A locked or Free-equip slot cannot be
-- stripped; the button says so instead of timing out. The raw unequip
-- (equipengine.unequipSlot) stays as the fallback where the engine's
-- registry is not there to ask.
--
-- THE DEPOSIT WAITS FOR THE CLIENT (field round 1, the same day). The first
-- cut queued the deposit straight behind the unequip -- the outgoing stream
-- keeps the order, so the SERVER was fine: the piece landed in the vault.
-- The CLIENT was not: its inventory kept a ghost copy of the piece (could
-- not be equipped or sold; zoning resynced it away). The server's answer to
-- the unequip and its answer to the deposit both touch the same bag slot,
-- and when they leave in the same tick the client applies them in an order
-- that resurrects the item. So the store is now a PENDING step: the deposit
-- leaves only after the client ITSELF shows the equipment slot empty AND
-- the bag item no longer flagged equipped (5 = worn), then a short settle
-- so any trailing item update has landed; a timeout says so in words and
-- stores nothing. Driven from the module pump, so a closed tab still
-- finishes it. Nothing is claimed or locked: the set that names the piece
-- keeps naming it, and the vault layout engine brings it back by its rules.
M._pendingStore = nil;     -- { e, worn, at, seenAt, strip }
M.SETTLE  = 0.35;          -- seconds the client must show it off before the deposit leaves
M.TIMEOUT = 4.0;           -- seconds before a never-applied unequip gives up
M.LEASE   = 10;            -- the strip's lease: outlives TIMEOUT + settle + the deposit's round trip

local function dispatchMod()
    local d = nil;
    pcall(function() d = require('dlac\\dispatch'); end);
    return (type(d) == 'table') and d or nil;
end

-- Let the slot go: the engine's next pass dresses it again (with whatever is
-- left -- the piece is in the vault by then, or never left the bags).
local function releaseStrip(p)
    if p == nil or p.strip == nil then return; end
    local d = dispatchMod();
    if d ~= nil and type(d.stripRelease) == 'function' then pcall(d.stripRelease, p.strip); end
    p.strip = nil;
end

-- What the CLIENT shows for the pending piece: is the equipment slot still
-- pointing at its bag slot; the bag item's Flags and Id right now.
M._clientViewOverride = nil;   -- test seam: function(e, worn) -> stillWorn, flags, id
local function clientView(e, worn)
    if M._clientViewOverride ~= nil then return M._clientViewOverride(e, worn); end
    local stillWorn, flags, id = true, nil, nil;
    pcall(function()
        local oracle = require('dlac\\gear\\gearoracle');
        local cont, idx = oracle.wornLocation(worn.equip);
        stillWorn = (cont == e.container and idx == e.slot);
        local ci = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(e.container, e.slot);
        if ci ~= nil then flags = ci.Flags; id = ci.Id; end
    end);
    return stillWorn, flags, id;
end

-- The pending step's beat (every frame from the module pump; `now` is a
-- test seam). One pending store at a time: the row shows 'Storing...'.
function M.pumpPending(now)
    local p = M._pendingStore;
    if p == nil then return; end
    now = now or os.clock();
    local stillWorn, flags, id = clientView(p.e, p.worn);
    if id ~= nil and id ~= p.e.itemId then
        M._pendingStore = nil;
        releaseStrip(p);
        noteResult(p.e.name .. ': the bag slot changed under it -- nothing stored', true);
        return;
    end
    if (not stillWorn) and flags ~= 5 then
        if p.seenAt == nil then p.seenAt = now; end
        if now - p.seenAt >= M.SETTLE then
            M._pendingStore = nil;
            invalidateWorn();
            -- the strip holds through the deposit's round trip and lets go
            -- on the answer, whatever it was
            if p.after then p.after(function() releaseStrip(p); end);
            else storeRows({ p.e }, true, function() releaseStrip(p); end); end
        end
        return;
    end
    p.seenAt = nil;
    if now - p.at >= M.TIMEOUT then
        M._pendingStore = nil;
        releaseStrip(p);
        noteResult(p.e.name .. ': the client never showed it unequipped -- nothing stored, try again', true);
    end
end

local function unequipAndStore(e, worn, after)
    if M._pendingStore ~= nil then return; end   -- one at a time
    local d = dispatchMod();
    if d ~= nil and type(d.stripSlot) == 'function' then
        local why = (type(d.stripBlocked) == 'function') and d.stripBlocked(worn.label) or nil;
        if why == 'locked' then
            noteResult(e.name .. ': the ' .. tostring(worn.label) .. ' slot is locked -- /dl lock '
                .. string.lower(tostring(worn.label)) .. ' off first, then try again', true);
            return;
        elseif why == 'disabled' then
            noteResult(e.name .. ': the ' .. tostring(worn.label) .. ' slot is under Free equip -- '
                .. 'dlac may not take it off; unequip it by hand, then Store', true);
            return;
        end
        local canon = d.stripSlot(worn.label, M.LEASE);
        if canon ~= nil then
            invalidateWorn();
            M._pendingStore = { e = e, worn = worn, at = os.clock(), seenAt = nil, strip = canon, after = after };
            return;
        end
    end
    -- no registry to ask (the legacy engine's state): the raw unequip, and
    -- hope nothing dresses the slot back before the client shows it off
    local sent = false;
    pcall(function()
        local eng = require('dlac\\feature\\equipengine');
        if type(eng.unequipSlot) == 'function' then
            sent = eng.unequipSlot(worn.equip, e.container, 'Gear Vault (unequip & store)') == true;
        end
    end);
    if not sent then
        noteResult(e.name .. ': could not send the unequip -- take it off by hand, then Store', true);
        return;
    end
    invalidateWorn();
    M._pendingStore = { e = e, worn = worn, at = os.clock(), seenAt = nil, after = after };
end

function M.retireLayoutEntry(selected)
    if M._pendingStore or vc.layoutBusy() then return noteResult('wait for the current gear move to finish', true); end
    local e;
    if vc.layoutCache.fresh and vc.currentJob() == vc.layoutCache.job then
        for _, row in ipairs(vc.layoutCache.entries or {}) do
            if row.instanceId == selected.instanceId and row.ordinal == selected.ordinal then e = row; break; end
        end
    end
    if not e or (e.instanceId or 0) == 0 then
        vc.requestLayout(0); return noteResult('refreshing this copy; try again once the layout is fresh', true);
    end
    local blocked = recon.retireBlocked(e.itemId);
    if blocked then return noteResult(blocked, true); end
    local name = nameOf(e.itemId);
    local bag = { itemId = e.itemId, name = name, container = e.location, slot = e.slot };
    if e.state ~= 0 then
        local mapping = vc.instanceAt(e.location, e.slot, e.itemId);
        if not mapping or mapping.instanceId ~= e.instanceId then
            return noteResult('checking this copy\'s location; try again in a moment', true);
        end
        if e.state == 2 and e.location ~= 0 then
            return noteResult('move this copy to Inventory before sending it to the Gear Vault', true);
        end
    end
    local worn = e.state ~= 0 and wornAtSlot()[e.location * 256 + e.slot] or nil;
    if worn then
        local disp = dispatchMod();
        local why = disp and disp.stripBlocked and disp.stripBlocked(worn.label);
        if why then return noteResult('release the ' .. worn.label .. ' slot lock / Free equip first', true); end
    end
    local edit = services().removeGearFromSets;
    if not edit then return noteResult('set editor is unavailable', true); end
    local ok, err = edit(e.itemId, e.identity);
    if not ok then return noteResult(err or 'could not update sets', true); end
    local job = vc.currentJob();
    local profile = require('dlac\\profiles');
    local profileName = profile.activeName();
    local function sameContext()
        return vc.currentJob() == job and profile.activeName() == profileName;
    end
    local function move(done)
        done = done or function() end;
        if not sameContext() then done(); return noteResult('job or profile changed; gear move cancelled', true); end
        local queued = vc.requestLayoutSet({ job = job, verb = vc.verb.REMOVE,
            itemId = e.itemId, instanceId = e.instanceId, ordinal = e.ordinal, count = 0,
            reason = 'remove-from-sets' }, function(code, why)
                if code ~= vc.code.OK then
                    done(); return noteResult('sets updated; vault move failed: ' .. tostring(why or code), true);
                end
                vc.requestLayout(0);
                if e.state == 2 then
                    local lookup = vc.requestLookup({ { container = bag.container, slot = bag.slot } }, function(rows)
                        local at = rows and rows[1];
                        if not sameContext() or not at or at.instanceId ~= e.instanceId then
                            done(); return noteResult('sets and layout updated; could not verify this copy for deposit, use Store', true);
                        end
                        bag.expectedInstanceId = e.instanceId;
                        storeRows({ bag }, worn ~= nil, done);
                    end);
                    if not lookup then done(); noteResult('sets updated; could not verify the deposit location', true); end
                else
                    done(); noteResult(name .. ' removed from sets and returned to Gear Vault');
                end
            end);
        if not queued then done(); noteResult('sets updated; could not queue the vault move', true); end
    end
    if worn then unequipAndStore(bag, worn, move); else move(); end
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
    -- ---- status header (full width). The vault COUNT rides the Vault
    -- sub-tab's label instead of a sentence here (Henrik, 2026-08-30:
    -- "needless space... just add the total number of equips to the vault
    -- tab like we do with inventory"), and the sync state keeps a seat only
    -- when it has something to say -- fresh is silence.
    local state = vc.state();
    if state == 'dormant' then
        imgui.TextColored(cDIM, 'The Gear Vault is not available on this server (or the addon was refused).');
        return;
    end
    if state == 'unattuned' then
        -- The server refuses every vault op until The Deeper Room is done
        -- (D14). Say so where the player is looking, and stop -- the panes
        -- below would only describe a vault that does not exist yet.
        imgui.TextColored(cGOLD, 'The Gear Vault does not know you yet.');
        imgui.TextColored(cDIM, string.format('Finish the quest %s to open it: %s.', vc.ATTUNE_QUEST, vc.ATTUNE_HINT));
        imgui.TextColored(cDIM, 'Once it is done, dlac notices on its own (or press Check now).');
        if imgui.IsItemHovered() then imgui.SetTooltip('Quest page: ' .. vc.ATTUNE_WIKI); end
        if imgui.SmallButton('Check now##gvattune') then vc.refresh(); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Ask the server again right now.'); end
        return;
    end
    local vaultN = 0;
    for _, r in ipairs(vc.mirror.rows) do vaultN = vaultN + math.max(1, r.qty); end
    if state ~= 'fresh' then
        imgui.TextColored(cGOLD, '[' .. state .. ']');
        if imgui.IsItemHovered() then
            imgui.SetTooltip('stale -- something moved (job change, !vault, zoning); a re-sync is due.\nsyncing -- pages are on the wire now. Nothing shows here when the\nmirror matches the server.');
        end
        imgui.SameLine(0, 12);
    end
    local occ = shelfOccupancy();
    if occ.max > 0 then
        imgui.TextColored(cDIM, string.format('Wardrobes 1-8: %d/%d', occ.used, occ.max));
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

    -- Vault options live behind the COG at the row's right edge (Henrik,
    -- 2026-08-30: "move Vault options to a cog wheel icon right of the
    -- search bar -- edge right if possible"). The settings.png the header
    -- menu already ships; no texture (headless, or a failed load) degrades
    -- to a plain Options button so the popup is never lost.
    do
        local winW = nil;
        pcall(function() winW = imgui.GetWindowWidth(); end);
        if type(winW) == 'number' and winW > 260 then imgui.SameLine(winW - 34);
        else imgui.SameLine(0, 12); end
        local cogClicked = false;
        local tex = nil;
        pcall(function() tex = require('dlac\\ui\\filetex').handle('settings'); end);
        if tex ~= nil and type(imgui.ImageButton) == 'function' then
            cogClicked = imgui.ImageButton(tex, { 16, 16 });
        else
            cogClicked = imgui.SmallButton('Options##gvcog');
        end
        if imgui.IsItemHovered() then imgui.SetTooltip('Vault options.'); end
        if cogClicked and type(imgui.OpenPopup) == 'function' then imgui.OpenPopup('##gvoptpop'); end
        if usg ~= nil and type(imgui.BeginPopup) == 'function' and imgui.BeginPopup('##gvoptpop') then
            local s = usg.settings();
            local function settingRow(label, tip, key, options)
                imgui.TextColored(cDIM, label);
                if imgui.IsItemHovered() then imgui.SetTooltip(tip); end
                imgui.SameLine(0, 8);
                for i, o in ipairs(options) do
                    if i > 1 then imgui.SameLine(0, 4); end
                    local on = (s[key] == o.v);
                    if on then imgui.PushStyleColor(ImGuiCol_Button, { 0.55, 0.45, 0.15, 1.0 }); end
                    if imgui.SmallButton(o.l .. '###gvset_' .. key .. '_' .. o.v) then
                        usg.setSetting(key, o.v);
                    end
                    if on then imgui.PopStyleColor(1); end
                end
            end
            settingRow('Additions from sets:',
                'Auto (default): dlac pushes every VAULTED piece your sets and triggers name\ninto this job\'s layout by itself (gear in your bags never moves -- store it\nwith a Void Warden first).\nOff: layouts change only by your own hand (the buttons here, !vault).',
                'additions', { { v = 'auto', l = 'Auto' }, { v = 'off', l = 'Off' } });
            settingRow('Removals when the wardrobes are full:',
                'Ask (default): dlac presents a list of least-used entries for you to mark.\nAuto: dlac removes least-used UNPINNED entries by itself -- pinned entries\nstill always ask.\nOff: dlac never removes; trim the layout by hand.',
                'removals', { { v = 'ask', l = 'Ask' }, { v = 'auto', l = 'Auto' }, { v = 'off', l = 'Off' } });
            imgui.EndPopup();
        end
    end

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
        uistyl.helpLabel(imgui, 'Mog Wardrobe Layout', 'This is what you have in your current Mog Wardrobe for this job.\nThe Mog Wardrobe is fed gear from the Gear Vault per job, to fully\nutilize your wardrobe slots.\nGear can only move between your Gear Vault and wardrobe when you\nare in a city.\nTo add gear into the Gear Vault, stand near a Void Storage Warden NPC.', cHEAD);
    else
        imgui.TextColored(cHEAD, 'Mog Wardrobe Layout');
    end
    -- Right of the header: the fetch, or the additions engine's countdown.
    -- The engine's 8s beat was invisible (Henrik, 2026-09-10: a stored
    -- piece "did nothing" until the next beat, which reads as broken);
    -- the header lost its "Current" to make room for the clock.
    if not lc.fresh then
        imgui.SameLine(0, 8);
        imgui.TextColored(cGOLD, '(fetching...)');
    else
        local nb = (recon ~= nil and type(recon.nextBeat) == 'function') and recon.nextBeat() or nil;
        local words = nil;
        if type(nb) == 'number' then words = string.format('sync in %ds', math.ceil(nb));
        elseif nb == 'busy' or nb == 'syncing' then words = 'syncing...';
        elseif nb == 'paused' then words = 'sync paused';
        end
        if words ~= nil then
            imgui.SameLine(0, 8);
            imgui.TextColored(cDIM, words);
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Every 8 seconds dlac checks your sets and triggers against the Gear Vault\nand adds any vaulted piece this layout is missing (gear in your bags never\nmoves -- store it with a Void Storage Warden first). Additions to your\nACTIVE job apply in a city; elsewhere they wait. Sync re-reads the server now.');
            end
        end
    end

    -- Where are we? The town service PREDICTS what the server's city gate
    -- will say; the evidence (a NOT_IN_CITY refusal -> cityBlocked) can only
    -- confirm it. Prediction never gates the wire -- only what this pane
    -- COMPLAINS about (Henrik's 2026-08-30 field round: "shelf is full"
    -- fired at him in the field when the real blocker was the city gate).
    local inField = false;
    pcall(function() inField = require('dlac\\feature\\location').inTown() == false; end);

    -- ---- wardrobe pressure (GV3): the banner + the marking dialog ----
    local pr = (recon ~= nil and type(recon.pressure) == 'function') and recon.pressure() or nil;
    local prWant = (pr ~= nil) and ((pr.over or 0) + (pr.waiting or 0)) or 0;

    -- OUT IN THE FIELD nothing can transfer whatever the space situation,
    -- so a full wardrobe is not a complaint and the eviction dialog would
    -- only queue refusals: one calm gold notice covers everything pending.
    local cityHeld = (recon ~= nil and type(recon.cityBlocked) == 'function' and recon.cityBlocked());
    if cityHeld or (inField and prWant > 0) then
        local wrapped = (fmt ~= nil and type(fmt.textWrapped) == 'function')
            and fmt.textWrapped or function(col, s) imgui.TextColored(col, s); end;
        wrapped(cGOLD, (prWant > 0)
            and string.format('%d piece%s from your sets %s waiting to move into your wardrobes.',
                prWant, (prWant == 1) and '' or 's', (prWant == 1) and 'is' or 'are')
            or 'Additions from your sets are waiting for a city.');
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Gear only moves between the Gear Vault and your wardrobes in a city\n(or your Mog House) -- everything pending transfers by itself when\nyou arrive. Other jobs\' layouts save from anywhere.');
        end
    end

    if pr ~= nil and prWant > 0 and not inField then
        -- BUTTON FIRST, text wrapped under it (Henrik's screenshot: the
        -- button rode the end of a long line and clipped off the pane edge).
        -- No "shelf" in player-facing words (Henrik, 2026-08-30: "people
        -- don't know what shelf means").
        local wrapped = (fmt ~= nil and type(fmt.textWrapped) == 'function')
            and fmt.textWrapped or function(col, s) imgui.TextColored(col, s); end;
        local words = string.format('Mog Wardrobe is full: %d equipment piece%s cannot fit in.',
            prWant, (prWant == 1) and '' or 's');
        if pr.mode == 'off' then
            wrapped(cERR, words);
            wrapped(cDIM, 'Removals are Off -- trim the layout with the Remove buttons below.');
        else
            if imgui.SmallButton((M._evictOpen and 'Hide' or 'Choose what to remove') .. '###gvevb') then
                if not M._evictOpen then
                    -- pre-tick greedily: least-used unpinned until BOTH the
                    -- overflow and the waiting derived pieces have room;
                    -- pinned entries are NEVER pre-ticked
                    M._marks = {};
                    local freed = 0;
                    local target = (pr.over or 0) + (pr.waiting or 0);
                    for _, c in ipairs(pr.candidates) do
                        local tick = freed < target;
                        M._marks[c.key] = { tick };
                        if tick then freed = freed + c.count; end
                    end
                    for _, c in ipairs(pr.pinned) do M._marks[c.key] = { false }; end
                end
                M._evictOpen = not M._evictOpen;
            end
            wrapped(cERR, words);
        end
        wrapped(cDIM, 'If you don\'t have enough wardrobe space, the recommended action is to\nwithdraw gear into your inventory: stand close to a Void Storage Warden\nto withdraw equipment there and keep using it from your bags.');
        if M._evictOpen and pr.mode ~= 'off' then
            local marked, frees = 0, 0;
            local function evictRow(c, isPinned)
                local buf = M._marks[c.key] or { false };
                M._marks[c.key] = buf;
                imgui.Checkbox('##gvem' .. c.key, buf);
                imgui.SameLine(0, 6);
                imgui.TextColored(isPinned and cGOLD or (COL.USABLE or { 1, 1, 1, 1 }),
                    esc(nameOf(c.itemId)) .. (isPinned and '  [pin]' or ''));
                if imgui.IsItemHovered() then
                    local age = (usg ~= nil and usg.lastUsed(c.key)) or nil;
                    imgui.SetTooltip((c.assigned and 'Your sets still name this piece.\n' or 'Nothing in your sets names this piece.\n')
                        .. (age ~= nil and os.date('Last seen worn: %Y-%m-%d', age) or 'Never seen worn.')
                        .. (isPinned and '\nPINNED: only you may remove it -- ticking it here is that permission.' or ''));
                end
                if buf[1] then marked = marked + 1; frees = frees + c.count; end
            end
            for _, c in ipairs(pr.candidates) do evictRow(c, false); end
            for _, c in ipairs(pr.pinned) do evictRow(c, true); end
            if marked > 0 then
                if imgui.SmallButton(string.format('Remove marked (%d, frees %d)###gvevgo', marked, frees)) then
                    local all = {};
                    for _, c in ipairs(pr.candidates) do all[#all + 1] = c; end
                    for _, c in ipairs(pr.pinned) do all[#all + 1] = c; end
                    local tomb = {};
                    for _, c in ipairs(all) do
                        local buf = M._marks[c.key];
                        if buf ~= nil and buf[1] then
                            -- a removed SET-WANTED entry is tombstoned, or the
                            -- additions engine re-adds it on the next beat
                            -- (the 2026-08-27 tug-of-war field round)
                            if c.assigned and usg ~= nil then
                                tomb[#tomb + 1] = usg.keyOf(c.itemId, nil);
                            end
                            layoutEdit({ job = 0, verb = vc.verb.REMOVE, itemId = c.itemId, instanceId = c.instanceId, ordinal = c.ordinal,
                                         count = 0, hint = 0, pinned = false, identity = c.identity },
                                nameOf(c.itemId) .. ' removed from the layout');
                        end
                    end
                    if #tomb > 0 and usg ~= nil then pcall(usg.exclude, tomb); end
                    M._evictOpen = false;
                    M._marks = {};
                end
            else
                imgui.TextColored(cDIM, 'Mark entries to remove; least-used come pre-marked.');
            end
        end
        imgui.Separator();
    elseif M._evictOpen then
        M._evictOpen = false;   -- pressure resolved: the dialog closes itself
        M._marks = {};
    end

    if type(vc.instanceMode) == 'function' and vc.instanceMode() then
        local reviewCount = 0;
        for _, e in ipairs(lc.entries or {}) do if e.kind == 2 then reviewCount = reviewCount + 1; end end
        if reviewCount > 0 and imgui.TreeNode('Needs review (' .. reviewCount .. ')##gvreview') then
            imgui.TextWrapped('Choose the copy this job should use, or dismiss the old entry. Missing entries use no wardrobe space.');
            for _, e in ipairs(lc.entries or {}) do
                if e.kind == 2 then
                    local title = nameOf(e.itemId) .. (e.state == 2 and ' -- missing' or ' -- choose a copy');
                    if e.pinned then title = title .. ' [pinned]'; end
                    if imgui.TreeNode(title .. '##gvreview' .. e.ordinal) then
                        local aug = augTextOf(e.identity);
                        if aug then imgui.TextWrapped('Saved augments: ' .. aug); end
                        local candidates = vc.bindingCandidates(e.itemId);
                        for _, candidate in ipairs(candidates) do
                            local label = candidate.where .. ' copy #' .. candidate.instanceId;
                            local currentAug = augTextOf(candidate.identity);
                            if currentAug then imgui.TextWrapped(currentAug); end
                            if lc.fresh and vc.mirror.fresh and not vc.layoutBusy()
                                and imgui.SmallButton('Use ' .. label .. '##gvbind' .. e.ordinal .. ':' .. candidate.instanceId) then
                                layoutEdit({ job = lc.job, verb = vc.verb.BIND, selector = 2,
                                    itemId = e.itemId, ordinal = e.ordinal, instanceId = candidate.instanceId },
                                    nameOf(e.itemId) .. ' linked to the selected copy');
                            end
                        end
                        if #candidates == 0 then imgui.TextWrapped('No available copy yet. Store it in the vault, or wait for wardrobe lookup.'); end
                        local key = 'review' .. e.ordinal;
                        local armed = e.pinned and confirmArmed(key);
                        if lc.fresh and not vc.layoutBusy() and imgui.SmallButton((armed and 'Sure?' or 'Dismiss entry') .. '##gvdismiss' .. e.ordinal) then
                            if e.pinned and not armed then _confirm = { key = key, at = os.clock() };
                            else
                                layoutEdit({ job = lc.job, verb = vc.verb.REMOVE, selector = 2,
                                    itemId = e.itemId, ordinal = e.ordinal }, nameOf(e.itemId) .. ' old entry dismissed');
                            end
                        end
                        imgui.TreePop();
                    end
                end
            end
            imgui.TreePop();
        end
        if vc.lost and #vc.lost.entries > 0 and imgui.TreeNode('Removed or replaced copies##gvlost') then
            for _, e in ipairs(vc.lost.entries) do
                local reason = e.state == 2 and ('replaced by copy #' .. e.replacedBy)
                    or (e.state == 3 and 'identity needs review after rebuild' or 'no longer owned');
                imgui.TextWrapped(nameOf(e.itemId) .. ' #' .. e.instanceId .. ': ' .. reason);
            end
            imgui.TreePop();
        end
    end

    local lv = filterView(layoutView(), needle);
    if lv.total > 0 then
        renderTree(lv, 'L', searching, forceClose, level, COL, function(e)
            local outside = (e.instanceId or 0) > 0 and e.kind == 0 and e.state == 2;
            local recycled = outside and e.location == 17;
            return {
                key = 'L' .. tostring(e.sortKey),
                context = true,
                nameColor = outside and cGOLD or nil,
                warningTag = recycled and '[Recycle Bin]' or nil,
                warning = recycled and ('You discarded this copy, but it is still recoverable from the Recycle Bin.\n'
                    .. 'It remains assigned to this job\'s layout and cannot be fetched by the vault.\n'
                    .. 'Recover it to Inventory, then Store it at a Void Storage Warden to use it again.\n'
                    .. 'Remove the layout entry if you no longer want it assigned.')
                    or outside and ('This copy is in your bags, outside the Gear Vault and Mog Wardrobes.\n'
                    .. 'It is still assigned to this job\'s layout, but the vault cannot fetch it from your bags.\n'
                    .. 'Store this copy at a Void Storage Warden to make it available again.\n'
                    .. 'You do not need to remove it from the layout or add it again.') or nil,
                augOf = function() return isAugmented(e.identity) and augTextOf(e.identity) or nil; end,
                tags = function()
                    local count = counts.count(e, e.rec);
                    if count > 1 then
                        imgui.SameLine(0, 6);
                        imgui.TextColored(cDIM, 'x' .. count);
                    end
                    if isAugmented(e.identity) then
                        imgui.SameLine(0, 8);
                        imgui.TextColored(cGOLD, '[aug]');
                        -- no tooltip of its own: the ROW hover already shows
                        -- the card with the Aug: line (a second card doubled
                        -- the box -- Henrik's screenshot)
                    end
                end,
                buttons = function(hot, b1, b2)
                    imgui.SameLine(b1);
                    local pinLabel = (e.pinned and 'Unpin' or 'Pin') .. '##gvp' .. tostring(e.sortKey);
                    if e.pinned then imgui.PushStyleColor(ImGuiCol_Button, { 0.55, 0.45, 0.15, 1.0 }); end
                    if imgui.SmallButton(pinLabel) then
                        layoutEdit({ job = 0, verb = vc.verb.PIN, instanceId = e.instanceId, ordinal = e.ordinal, itemId = e.itemId, count = e.count,
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
                        local wornNow = (recon ~= nil and type(recon.wornNow) == 'function') and recon.wornNow() or {};
                        if wornNow[e.itemId] or wornNow['i:' .. tostring(e.instanceId)] then
                            -- an equipped piece cannot leave the shelf: the
                            -- apply skips ITEM_LOCKED, so removing its entry
                            -- only desyncs the layout (Henrik's field round)
                            noteResult(e.name .. ' is equipped right now -- unequip it first, then remove', true);
                        elseif e.pinned and not armed then
                            _confirm = { key = rkey, at = os.clock() };
                        else
                            _confirm = nil;
                            -- removing the plain copy of a SET-WANTED id is
                            -- tombstoned, or the engine re-adds it next beat
                            if usg ~= nil and ((e.instanceId or 0) > 0 or e.identity == ZERO24) then
                                local der = (recon ~= nil and type(recon.derivedIds) == 'function')
                                    and recon.derivedIds() or {};
                                if der[e.itemId] then
                                    pcall(usg.exclude, { usg.keyOf(e.itemId, nil) });
                                end
                            end
                            layoutEdit({ job = 0, verb = vc.verb.REMOVE, instanceId = e.instanceId, ordinal = e.ordinal, itemId = e.itemId, count = 0,
                                         hint = 0, pinned = false, identity = e.identity },
                                e.name .. ' removed from the layout');
                        end
                    end
                    if armed then imgui.PopStyleColor(1); end
                    if imgui.IsItemHovered() then
                        hot();
                        imgui.SetTooltip(e.pinned
                            and 'Remove this PINNED entry -- takes a second click to confirm.\nThe piece itself stays in the vault; only the layout forgets it.'
                            or  'Remove from this job\'s layout. The piece stays in the vault;\nyour wardrobes drop it at the next job change or live edit.');
                    end
                end,
            };
        end);
    elseif lc.fresh then
        imgui.TextColored(cDIM, searching and 'Nothing in the layout matches.'
            or 'Nothing here yet -- add gear to your Mog Wardrobe layout:\neither from the Vault tab (Add to Mog Wardrobe),\nor let dlac add automatically based on your built sets\n(see settings, the cog wheel).');
    end

    -- WAITING FOR ROOM (Henrik's 2026-08-27 "limbo" round: pieces the
    -- engine holds back for space were invisible until they materialised
    -- after a removal). Named here, gold: they belong to the layout the
    -- moment room appears; Bench one to stop wanting it instead.
    if pr ~= nil and pr.waitingItems ~= nil and #pr.waitingItems > 0 then
        imgui.PushStyleColor(ImGuiCol_Text, cGOLD);
        local wOpen = imgui.CollapsingHeader(string.format('Waiting for room (%d)###gvwait', #pr.waitingItems));
        imgui.PopStyleColor(1);
        -- the explanation is a HOVER, not free text (Henrik, 2026-08-30)
        if imgui.IsItemHovered() then
            imgui.SetTooltip('These items are queued up to be added to your wardrobe layout.\nIf space is available and you enter a city, these will automatically\nbe added.');
        end
        if wOpen then
            for _, wI in ipairs(pr.waitingItems) do
                imgui.TextColored(COL.USABLE or { 1, 1, 1, 1 }, esc(nameOf(wI.itemId))
                    .. ((wI.need or 1) > 1 and (' x' .. wI.need) or ''));
                imgui.SameLine(0, 10);
                if imgui.SmallButton('Bench##gvwb' .. tostring(wI.itemId)) then
                    if usg ~= nil then
                        pcall(usg.exclude, { usg.keyOf(wI.itemId, nil) });
                        noteResult(nameOf(wI.itemId) .. ' benched -- dlac stops trying to shelve it', false);
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Stop wanting this in your wardrobes -- it moves to the Bench below,\nand Restore brings it back any time.');
                end
            end
        end
    end

    -- THE BENCH (Henrik's 2026-08-27 design round: exclusions must be
    -- visible and one click from coming back). Set-wanted pieces the player
    -- removed sit here BY NAME; Restore clears the tombstone and the
    -- engine re-adds the piece the moment the shelf has room -- his "only
    -- re-add when space is available", with the CHOICE remembered.
    if usg ~= nil and usg.excludedCount() > 0 then
        -- The header carries the ACTIONABLE fact -- free shelf slots mean a
        -- Restore would land right now -- and lights GOLD when that is true
        -- (the Inventory tab's lights-up language; Henrik's 2026-08-27 note:
        -- "clearly show something should be done").
        local free = (recon ~= nil and type(recon.freeSlots) == 'function') and recon.freeSlots() or nil;
        local actionable = (free ~= nil and free > 0);
        local benchLabel = string.format('Benched (%d)%s###gvbench', usg.excludedCount(),
            (free ~= nil) and string.format(' -- %d wardrobe slot%s free', free, (free == 1) and '' or 's') or '');
        if actionable then imgui.PushStyleColor(ImGuiCol_Text, cGOLD); end
        local benchOpen = imgui.CollapsingHeader(benchLabel);
        if actionable then imgui.PopStyleColor(1); end
        if benchOpen then
            imgui.TextColored(cDIM, 'Removed by you; dlac will not re-add these by itself.');
            for _, b in ipairs(usg.excludedList()) do
                imgui.TextColored(COL.USABLE or { 1, 1, 1, 1 }, esc(nameOf(b.itemId)));
                imgui.SameLine(0, 10);
                if imgui.SmallButton('Restore##gvrb' .. tostring(b.itemId)) then
                    usg.unexclude(b.key);
                    noteResult(nameOf(b.itemId) .. ' restored -- it rejoins the layout when your wardrobes have room', false);
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Let dlac add this back -- it returns to the layout on the next\nbeat if your wardrobes have room, and waits (visibly) if not.');
                end
            end
        end
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
                            -- no tooltip of its own: the row hover carries it
                        end
                        if usg ~= nil and usg.isExcluded(usg.keyOf(e.itemId, nil)) then
                            imgui.SameLine(0, 8);
                            imgui.TextColored(cDIM, '[excluded]');
                            if imgui.IsItemHovered() then
                                imgui.SetTooltip('You removed this from the layout, so dlac will not add it back\nby itself. Add to Mog Wardrobe puts it back and clears this.');
                            end
                        end
                    end,
                    b1w = 210,   -- room for the named action (was 'Layout' -- jargon)
                    buttons = function(hot, b1, b2)
                        imgui.SameLine(b1);
                        local admission = vc.layoutAddState(e.itemId, e.identity, e.instanceId);
                        local have, units = 0, admission.reserved;
                        for _, entry in ipairs(admission.entries or {}) do
                            units = units + counts.count(entry, recOf(entry.itemId));
                            if ((e.instanceId or 0) > 0 and entry.instanceId == e.instanceId)
                                or ((e.instanceId or 0) == 0 and entry.itemId == e.itemId and (entry.identity or ZERO24) == (e.identity or ZERO24)) then
                                have = have + (entry.count or 1);
                            end
                        end
                        local present = have >= ((e.instanceId or 0) > 0 and 1 or (counts.limit(e.rec) or math.huge));
                        local full = occ.max > 0 and units >= occ.max;
                        if admission.pending then
                            imgui.TextColored(cDIM, 'Queued / syncing...');
                        elseif not admission.ready then
                            imgui.TextColored(cDIM, 'Syncing layout...');
                        elseif present then
                            imgui.TextColored(cDIM, 'In Mog Wardrobe');
                        elseif full then
                            imgui.TextColored(cDIM, 'Mog Wardrobe full');
                        elseif imgui.SmallButton('Add to Mog Wardrobe##gvl' .. tostring(e.rowId)) then
                            -- a manual add is the player overruling their own
                            -- removal: clear the tombstone first
                            if usg ~= nil then pcall(usg.unexclude, usg.keyOf(e.itemId, nil)); end
                            layoutEdit({ job = 0, verb = vc.verb.ADD, instanceId = e.instanceId, itemId = e.itemId, count = 1,
                                         hint = 0, pinned = true, identity = e.identity },
                                e.name .. ' added and pinned to this job\'s layout');
                        end
                        if imgui.IsItemHovered() then
                            hot();
                            imgui.SetTooltip('Add and pin THIS copy (augments included) to your current main job\'s\nMog Wardrobe layout. The pin keeps automatic cleanup from returning it.\nLive in a city (or your Mog House); refused in the field.');
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
        -- No [wanted] tags and no Store-wanted shortcut any more (Henrik,
        -- 2026-08-30: "it's confusing, people need to realize themselves
        -- that they need to add gear into vault for mog wardrobe usage") --
        -- the pane just lists what is storable and lets the player curate.
        if #shown > 0 then
            if imgui.SmallButton(string.format('Store all (%d)##gvsa', #shown)) then
                storeRows(shown);
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Deposit every listed piece into the Gear Vault.\nWorks at a Void Warden. Equipped pieces and\nduplicates are refused per item and stay in your bags\n(a worn piece has its own Unequip & Store button).');
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
            -- a WORN row's button is 'Unequip & Store' (right-aligned to the
            -- same edge as the plain Store column) and the row says which
            -- slot it is on, so the eye knows why the button differs
            local wornMap = wornAtSlot();
            local unequipLabel = 'Unequip & Store';
            local unequipCol = math.max(60, btnCol - (textW(unequipLabel) - textW('Store')));
            for _, e in ipairs(shown) do
                local worn = wornMap[e.container * 256 + e.slot];
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
                local pend = M._pendingStore;
                local pendingHere = (pend ~= nil and pend.e.container == e.container and pend.e.slot == e.slot);
                if pendingHere then
                    -- the unequip is out; the deposit leaves once the client
                    -- shows the piece off (pumpPending) -- the button says so
                    -- and takes no click
                    imgui.SameLine(0, 6);
                    imgui.TextColored(cDIM, esc('[worn: ' .. tostring(worn and worn.label or '?') .. ']'));
                    imgui.SameLine(unequipCol);
                    imgui.SmallButton('Storing...##gvus' .. tostring(e.slot));
                elseif worn ~= nil then
                    imgui.SameLine(0, 6);
                    imgui.TextColored(cDIM, esc('[worn: ' .. tostring(worn.label) .. ']'));
                    imgui.SameLine(unequipCol);
                    if imgui.SmallButton(unequipLabel .. '##gvus' .. tostring(e.slot)) then
                        unequipAndStore(e, worn);
                    end
                else
                    imgui.SameLine(btnCol);
                    if imgui.SmallButton('Store##gvs' .. tostring(e.slot)) then
                        storeRows({ e });
                    end
                end
                local btnHovered = imgui.IsItemHovered();
                if rowHovered or btnHovered then hotNow = e.slot; end
                if btnHovered then
                    imgui.SetTooltip(pendingHere and 'Taking it off -- the deposit follows once the game shows it unequipped.'
                        or (worn ~= nil)
                        and 'Take this off, then deposit it into the Gear Vault (at a Void Warden).\nThe deposit waits until the game itself shows the piece unequipped.'
                        or  'Deposit this into the Gear Vault (at a Void Warden).');
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
        -- the count is the header's old "N pieces stored" sentence, demoted
        -- to the fun-stat seat the Inventory tab already uses
        if imgui.BeginTabItem(string.format('Vault (%d)###gvtv', vaultN)) then
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

    -- Both popup calls share the parent window scope, like the floating menus.
    if _openLayoutMenu then
        _layoutMenu, _openLayoutMenu = _openLayoutMenu, nil;
        imgui.OpenPopup('##gv-layout-actions');
    end
    if imgui.BeginPopup('##gv-layout-actions') then
        if imgui.Selectable('Remove from sets and send to gear vault') and _layoutMenu then
            M.retireLayoutEntry(_layoutMenu);
            imgui.CloseCurrentPopup();
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Remove this copy\'s references from the current job\'s sets and release its layout assignment.\nOther jobs are unchanged. Generic references to this item are removed too.');
        end
        imgui.EndPopup();
    end

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
