--[[
    dlac/ui/unusedui.lua -- the Wardrobe cleanup window (Henrik, 2026-08-03).

    Renders the SAVED audit from gear\unusedgear: what is sitting in a Mog
    Wardrobe that nothing in dlac asks for. The window shows the last report
    and refreshes on the button -- a full profile walk plus a bag pass is not a
    per-frame read, and Henrik asked for exactly this shape: "when issuing
    /dl unused, can it show the recent report that it has saved, where the
    player can choose to refresh / generate new report."

    Three sections, because the audit has three different answers and only one
    of them is "junk" (see the module header for the rulings):
      * Nothing references it        -- the answer the window exists for
      * Only a lockstyle box does    -- MOVEABLE: the server never checks which
                                        container a style piece is in
      * Only a set no rule triggers  -- probably dead, but that is your call

    INDEPENDENT of the main dlac box, like the Wishlist and lockstyle windows:
    gearui's d3d_present calls M.render() inside its own theme bracket while
    M.visible is set. No uihost window contract, no tab.
]]--

local host = require("dlac\\ui\\uihost");

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');
local fmt   = try('dlac\\gear\\gearfmt');
local icons = try('dlac\\ui\\itemicons');
local ug    = try('dlac\\gear\\unusedgear');

local M = {};
M.VERSION = 1;
M.visible = false;

local S = host.services;
local COL = (S ~= nil) and S.COL or nil;

-- gearui provides the shared palette before requiring this module. Missing =
-- render nothing, loudly once, rather than a nil index every frame (the
-- wishlistui precedent).
if COL == nil or ug == nil then
    pcall(function() print('[dlac] unusedui: shared services missing -- the Wardrobe window is disabled.'); end);
    M.render = function() end;
    M.open   = function() end;
    M.close  = function() end;
    M.toggle = function() return false; end;
    M._setSearch = function() end;
    M.degraded = true;   -- /dl unused answers in CHAT rather than silently doing nothing
    host.provide({ unusedui = M });
    return M;
end

local function esc(s)
    if fmt ~= nil and type(fmt.esc) == 'function' then return fmt.esc(tostring(s or '')); end
    return (tostring(s or ''):gsub('%%', '%%%%'));
end

local function textW(s)
    if imgui ~= nil then
        local ok, w = pcall(imgui.CalcTextSize, tostring(s or ''));
        if ok and type(w) == 'number' then return w; end
    end
    return #tostring(s or '') * 10;
end

-- The three sections, in the order a player acts on them.
local SECTIONS = {
    { cls = 'unused', title = 'Nothing references these',
      tip = 'No set, no trigger, no lockstyle box, no gear helper and no ammo/fishing rule\n'
         .. 'names this piece -- across EVERY profile and job entry on this character.\n'
         .. 'These are the ones to move out of a wardrobe.' },
    { cls = 'style',  title = 'Only a lockstyle box uses these',
      tip = 'A lockstyle piece does not need to be in a wardrobe -- or even in your bags.\n'
         .. 'The server validates the item, never the container it sits in, so moving\n'
         .. 'these to the Mog Safe keeps the look.' },
    { cls = 'orphan', title = 'Only in a set no rule triggers',
      tip = 'The piece IS in one of your sets -- but no trigger rule points at that set,\n'
         .. 'so nothing equips it today. Wire the set up, or move the piece out.' },
};

local _search = { '' };
local _wardF = nil;      -- nil = every wardrobe
local _status = '';

-- Test seam: the smoke suite drives the filtered frame (no imgui InputText to
-- type into headless).
function M._setSearch(s) _search[1] = tostring(s or ''); end

function M.open()  M.visible = true;  end
function M.close() M.visible = false; end
function M.toggle()
    M.visible = not M.visible;
    return M.visible;
end

local function locText(row, rep)
    local names = {};
    for _, w in ipairs(row.where or {}) do
        local nm = 'container ' .. tostring(w.cid);
        for _, wd in ipairs((rep ~= nil) and rep.wardrobes or {}) do
            if wd.cid == w.cid then nm = tostring(wd.name); break; end
        end
        names[#names + 1] = nm .. ((w.n or 1) > 1 and (' x' .. w.n) or '');
    end
    return table.concat(names, ', ');
end

local function rowInWardrobe(row, cid)
    if cid == nil then return true; end
    for _, w in ipairs(row.where or {}) do
        if w.cid == cid then return true; end
    end
    return false;
end

-- One section's rows, already filtered. Column stops are measured off what is
-- actually here (the wishlistui idiom), so a wide name never overlaps.
local function renderRows(rows, rep, nameW)
    local LOC_X  = 26 + nameW;
    local locW   = 120;
    for _, r in ipairs(rows) do
        local w = textW(locText(r, rep)) + 18;
        if w > locW then locW = w; end
    end
    locW = math.min(locW, 240);
    local LV_X   = LOC_X + locW;
    local JOBS_X = LV_X + textW('Lv75') + 16;
    local WHY_X  = JOBS_X + textW('WAR,MNK,WHM,BLM') + 16;

    for i, r in ipairs(rows) do
        if icons ~= nil and type(icons.renderIcon) == 'function' then
            pcall(icons.renderIcon, r.id, 18);
            imgui.SameLine(26);
        end
        imgui.TextColored(COL.USABLE, esc(r.name));
        if imgui.IsItemHovered() and #(r.why or {}) > 0 then
            imgui.SetTooltip(esc(table.concat(r.why, '\n')));
        end
        imgui.SameLine(LOC_X);
        imgui.TextColored(COL.DIM, esc(locText(r, rep)));
        imgui.SameLine(LV_X);
        imgui.TextColored(COL.LEVEL, (r.lv ~= nil) and ('Lv' .. tostring(r.lv)) or '--');
        imgui.SameLine(JOBS_X);
        imgui.TextColored(COL.JOBS, esc(r.jobs or '--'));
        if #(r.why or {}) > 0 then
            imgui.SameLine(WHY_X);
            imgui.TextColored(COL.STATS, esc(r.why[1]));
            if imgui.IsItemHovered() then imgui.SetTooltip(esc(table.concat(r.why, '\n'))); end
        end
        if i % 25 == 0 then imgui.Separator(); end
    end
end

-- The window BODY. Kept separate from render() so the Begin/End (and the
-- child's BeginChild/EndChild) can be paired around a pcall: a throw in here
-- costs one frame of content and says so, instead of leaving the ImGui window
-- stack unbalanced for every surface drawn after us.
local function drawBody()
    local rep = ug.load();

    -- Header: when the report was taken, and the one button that matters.
    if rep ~= nil then
        imgui.TextColored(COL.DIM, 'Report taken ' .. esc(rep.stamp or '?'));
    else
        imgui.TextColored(COL.DIM, 'No report yet.');
    end
    imgui.SameLine(0, 10);
    if imgui.SmallButton((rep ~= nil) and 'Refresh##unuref' or 'Generate##unuref') then
        local r, why = ug.refresh();
        if r == nil then
            _status = 'Could not build the report: ' .. tostring(why);
        else
            _status = string.format('Read %d profile(s), %d job entr(ies), %d set(s).',
                (r.stats or {}).profiles or 0, (r.stats or {}).entries or 0, (r.stats or {}).sets or 0);
            rep = r;
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Walk every profile and job entry again, re-read your bags, and save the result.\n'
            .. 'Do this after you move gear around, edit sets, or change a lockstyle box.');
    end

    if rep == nil then
        imgui.Separator();
        if fmt ~= nil and type(fmt.textWrapped) == 'function' then
            fmt.textWrapped(COL.DIM, 'This looks through every profile and every job entry on this character -- '
                .. 'the triggers, the sets they point at, your lockstyle boxes and the gear helpers -- and '
                .. 'then lists what is sitting in a Mog Wardrobe that none of it asks for.\n\n'
                .. 'Press Generate.');
        else
            imgui.TextColored(COL.DIM, 'Press Generate.');
        end
        if _status ~= '' then imgui.TextColored(COL.ERR, esc(_status)); end
        return;
    end

    local c = rep.counts or {};
    local st = rep.stats or {};
    imgui.TextColored(COL.HEADER, string.format('%d items in your wardrobes  --  %d referenced, %d not',
        c.total or 0, c.used or 0, (c.total or 0) - (c.used or 0)));
    imgui.TextColored(COL.DIM, string.format('%d profile(s), %d job entr(ies), %d set(s): %d triggered, %d untriggered.',
        st.profiles or 0, st.entries or 0, st.sets or 0, st.usedSets or 0, st.orphanSets or 0));
    if _status ~= '' then imgui.TextColored(COL.SCORE, esc(_status)); end

    -- Per-wardrobe load, so it is obvious which one to empty first.
    imgui.Separator();
    for _, w in ipairs(rep.wardrobes or {}) do
        if (w.items or 0) > 0 then
            imgui.TextColored((w.flagged or 0) > 0 and COL.WANT or COL.DIM,
                string.format('%s: %d held, %d flagged', esc(w.name), w.items or 0, w.flagged or 0));
            imgui.SameLine(0, 14);
        end
    end
    imgui.NewLine();

    -- Filters.
    imgui.PushItemWidth(textW('Every wardrobe') + 34);
    local curLabel = 'Every wardrobe';
    for _, w in ipairs(rep.wardrobes or {}) do
        if w.cid == _wardF then curLabel = tostring(w.name); end
    end
    if imgui.BeginCombo('##unufward', curLabel) then
        if imgui.Selectable('Every wardrobe', _wardF == nil) then _wardF = nil; end
        for _, w in ipairs(rep.wardrobes or {}) do
            if (w.items or 0) > 0 then
                if imgui.Selectable(esc(w.name) .. '##unuw' .. tostring(w.cid), _wardF == w.cid) then
                    _wardF = w.cid;
                end
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, 8);
    imgui.TextColored(COL.DIM, 'Search:');
    imgui.SameLine(0, 4);
    imgui.PushItemWidth(160);
    imgui.InputText('##unusearch', _search, 48);
    imgui.PopItemWidth();

    -- Split + filter.
    local needle = string.lower(_search[1] or '');
    local byCls, nameW = {}, 140;
    for _, r in ipairs(rep.rows or {}) do
        local keep = rowInWardrobe(r, _wardF);
        if keep and needle ~= '' then
            keep = string.find(string.lower(r.name or ''), needle, 1, true) ~= nil;
        end
        if keep then
            local cls = r.cls or 'unused';
            byCls[cls] = byCls[cls] or {};
            table.insert(byCls[cls], r);
            local w = textW(r.name) + 18;
            if w > nameW then nameW = w; end
        end
    end
    nameW = math.min(nameW, 300);

    imgui.Separator();
    imgui.BeginChild('##unulist', { -1, -1 }, false);
    local lok, lerr = pcall(function()
        local any = false;
        for _, sec in ipairs(SECTIONS) do
            local rows = byCls[sec.cls] or {};
            if #rows > 0 then
                any = true;
                local open = imgui.CollapsingHeader(string.format('%s (%d)###unusec_%s', sec.title, #rows, sec.cls),
                                                    ImGuiTreeNodeFlags_DefaultOpen or 32);
                if imgui.IsItemHovered() then imgui.SetTooltip(sec.tip); end
                if open then
                    if sec.cls == 'style' then
                        imgui.TextColored(COL.HAVE, 'Safe to move: a lockstyle piece works from any container.');
                    end
                    renderRows(rows, rep, nameW);
                    imgui.Spacing();
                end
            end
        end
        if not any then
            imgui.TextColored(COL.HAVE, (needle ~= '' or _wardF ~= nil)
                and 'Nothing matches the filters.'
                or  'Every piece in your wardrobes is referenced by something. Nothing to clean up.');
        end
    end);
    imgui.EndChild();     -- ALWAYS: the child closes even if a row threw
    if not lok then _status = 'the list could not be drawn: ' .. tostring(lerr); end
end

function M.render()
    if imgui == nil or not M.visible then return; end
    local vis = { true };
    imgui.SetNextWindowSize({ 820, 520 }, ImGuiCond_FirstUseEver or 4);
    local opened = imgui.Begin('dlac -- Wardrobe cleanup##dlac_unused', vis, ImGuiWindowFlags_None or 0);
    if opened then
        local ok, err = pcall(drawBody);
        if not ok then
            _status = 'render error: ' .. tostring(err);
            pcall(imgui.TextColored, COL.ERR, esc(_status));
        end
    end
    imgui.End();          -- ALWAYS, opened or not: ImGui pairs Begin with End
    if not vis[1] then M.visible = false; end
end

host.provide({ unusedui = M });
return M;
