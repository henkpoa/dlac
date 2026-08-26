--[[
    vanaheim/gearvault/vaultui.lua -- the Gear Vault TAB (slice 2: read-first).

    Registered on the uihost by this pack module's init, so the tab exists
    only where the pack mounts -- and shows through the gear-only surface
    default because the gate never hides a label it cannot name (ADR 0037).

    Three blocks, top to bottom:
      * the status header -- the client's state, the mirrored instance count,
        shelf occupancy read live off the wardrobes, and a Sync button;
      * THIS JOB'S LAYOUT, the server's truth via LAYOUT_LIST -- including
        entries made by `!vault` or the website, which is the point of
        showing the wire's answer rather than anything derived (that half
        arrives in slice 3);
      * the VAULT BROWSER over the mirror -- search, and the slice's one
        write verb: Withdraw, per row. dlac does not know the Void Wardens'
        coordinates (server data, deliberately not in the pack), so the
        button is always live and a TOO_FAR refusal says in words where to
        stand -- honest, and no stale geometry to maintain.

    Everything is read at CALL time from host.services (the uihost law) and
    every text sink goes through fmt.esc (SetTooltip/TextColored are printf
    -- the imgui geometry law).
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

-- Item display name: the shared service first (client-spelling), '#id' last.
local function nameOf(id)
    local S = (host ~= nil) and host.services or {};
    if type(S.displayName) == 'function' then
        local ok, n = pcall(S.displayName, id);
        if ok and type(n) == 'string' and n ~= '' then return n; end
    end
    return '#' .. tostring(id);
end

local ZERO24 = string.rep('\0', 24);

local function isAugmented(identity)
    return type(identity) == 'string' and #identity > 0 and identity ~= ZERO24;
end

-- Shelf occupancy: used/max over Wardrobes 1-8 (cids 8, 10-16 -- NOT
-- contiguous, 9 is Mog Safe 2). Live client read, cached a beat.
local WARDROBES = { 8, 10, 11, 12, 13, 14, 15, 16 };
local _occ = nil;      -- { used, max }
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
-- Withdraw feedback -- one remembered line under the browser, plus chat (the
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
-- The browser's sorted view -- rebuilt only when the mirror moves.
-- ---------------------------------------------------------------------------
local _view = nil;        -- sorted rows with names attached
local _viewStamp = nil;
local function browserRows()
    if _view ~= nil and _viewStamp == vc.mirror.stamp then return _view; end
    _viewStamp = vc.mirror.stamp;
    local out = {};
    for _, r in ipairs(vc.mirror.rows) do
        out[#out + 1] = { rowId = r.rowId, itemId = r.itemId, qty = r.qty,
                          identity = r.identity, name = nameOf(r.itemId) };
    end
    table.sort(out, function(a, b)
        if a.name == b.name then return a.rowId < b.rowId; end
        return a.name < b.name;
    end);
    _view = out;
    return out;
end

local _search = { '' };

-- Layout ask throttle: the tab re-asks a stale layout at most this often.
local _layoutAskAt = 0;
local LAYOUT_ASK_GAP = 3.0;

-- ---------------------------------------------------------------------------
-- The tab
-- ---------------------------------------------------------------------------
function M.render(job, level)
    if imgui == nil then return; end
    local S   = (host ~= nil) and host.services or {};
    local COL = S.COL or {};
    local cERR   = COL.ERR    or { 1.00, 0.45, 0.40, 1.00 };
    local cDIM   = COL.DIM    or { 0.70, 0.70, 0.70, 1.00 };
    local cHEAD  = COL.HEADER or { 0.60, 0.75, 1.00, 1.00 };
    local cOK    = COL.USABLE or { 1, 1, 1, 1 };
    local cGOLD  = COL.SCORE  or { 0.95, 0.85, 0.45, 1.00 };
    local cVAULT = COL.VAULT  or { 0.72, 0.55, 0.95, 1.00 };

    -- ---- status header ----
    local state = vc.state();
    if state == 'dormant' then
        imgui.TextColored(cDIM, 'The Gear Vault is not available on this server (or the addon was refused).');
        return;
    end
    local n = 0;
    for _, r in ipairs(vc.mirror.rows) do n = n + math.max(1, r.qty); end
    imgui.TextColored(cVAULT, string.format('Vault: %d instance%s', n, (n == 1) and '' or 's'));
    imgui.SameLine(0, 10);
    local stCol = (state == 'fresh') and cDIM or cGOLD;
    imgui.TextColored(stCol, '[' .. state .. ']');
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

    imgui.Separator();

    -- ---- this job's layout (the server's truth) ----
    local lc = vc.layoutCache;
    if not lc.fresh and os.clock() - _layoutAskAt > LAYOUT_ASK_GAP then
        _layoutAskAt = os.clock();
        vc.requestLayout(0);
    end
    if uistyl ~= nil and type(uistyl.helpLabel) == 'function' then
        uistyl.helpLabel(imgui, 'This job\'s layout', 'What the SERVER holds for your current main job -- every entry here\nis pulled onto the shelf at job change, wherever it came from (dlac,\n!vault, the website). Editing from this tab arrives in the next slice;\nuntil then: !vault add/remove <item>, in a city.', cHEAD);
    else
        imgui.TextColored(cHEAD, 'This job\'s layout');
    end
    if not lc.fresh then
        imgui.SameLine(0, 8);
        imgui.TextColored(cGOLD, '(fetching...)');
    end
    if lc.entries ~= nil and #lc.entries > 0 then
        local gi = try('dlac\\gear\\gearimport');
        imgui.BeginChild('##gvlayout', { -1, math.min(150, 8 + #lc.entries * 19) }, false);
        for _, e in ipairs(lc.entries) do
            imgui.TextColored(cOK, esc(nameOf(e.itemId)));
            if e.count > 1 then
                imgui.SameLine(0, 6);
                imgui.TextColored(cDIM, 'x' .. e.count);
            end
            if e.pinned then
                imgui.SameLine(0, 8);
                imgui.TextColored(cGOLD, '[pinned]');
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Soft-locked: no automation may remove this entry without asking you.');
                end
            end
            if e.hint ~= nil and gi ~= nil then
                imgui.SameLine(0, 8);
                imgui.TextColored(cDIM, esc(gi.containerName(e.hint)));
            end
        end
        imgui.EndChild();
    elseif lc.fresh then
        imgui.TextColored(cDIM, 'No entries yet -- this job\'s shelf empties at the next job change.');
    end

    imgui.Separator();

    -- ---- the vault browser ----
    if uistyl ~= nil and type(uistyl.helpLabel) == 'function' then
        uistyl.helpLabel(imgui, 'Vault contents', 'Everything in your Gear Vault (the server-side void space).\nWithdraw needs a Void Warden nearby -- the button says so if you are not.', cHEAD);
    else
        imgui.TextColored(cHEAD, 'Vault contents');
    end
    imgui.SameLine(0, 12);
    imgui.PushItemWidth(180);
    imgui.InputText('##gvsearch', _search, 64);
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then imgui.SetTooltip('Filter by name.'); end

    local needle = string.lower(tostring(_search[1] or ''));
    local rows = browserRows();
    imgui.BeginChild('##gvbrowse', { -1, -24 }, false);
    local shown = 0;
    for _, row in ipairs(rows) do
        if needle == '' or string.find(string.lower(row.name), needle, 1, true) ~= nil then
            shown = shown + 1;
            if icons ~= nil and type(icons.renderIcon) == 'function' then
                pcall(icons.renderIcon, row.itemId, 18);
                imgui.SameLine(0, 6);
            end
            imgui.TextColored(cOK, esc(row.name));
            if row.qty > 1 then
                imgui.SameLine(0, 6);
                imgui.TextColored(cDIM, 'x' .. row.qty);
            end
            if isAugmented(row.identity) then
                imgui.SameLine(0, 8);
                imgui.TextColored(cGOLD, '[aug]');
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('This copy carries augments or an inscription -- it comes back byte-identical.');
                end
            end
            imgui.SameLine(0, 12);
            if imgui.SmallButton('Withdraw##gvw' .. tostring(row.rowId)) then
                withdrawRow(row);
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Move this to your inventory. Works at a Void Warden (anywhere for a GM).');
            end
        end
    end
    if shown == 0 then
        imgui.TextColored(cDIM, (#rows == 0) and 'The vault is empty (or the first sync has not run -- try Sync).'
                                            or 'Nothing matches the search.');
    end
    imgui.EndChild();

    if _lastMsg ~= nil then
        imgui.TextColored(_lastMsg.err and cERR or cDIM, esc(_lastMsg.text));
    end
end

-- test seams
M._browserRows = browserRows;
M._search = _search;
function M._lastResult() return _lastMsg; end
function M._noteResult(t, e) noteResult(t, e); end

return M;
