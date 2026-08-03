--[[
    dlac/ui/nmui.lua -- the NM Compendium window (issue #156, PRD #151).

    One floating window, master-detail: the filter and the result list on the
    left, the detail card on the right. This slice is the SHELL -- the list and
    the by-name / by-area filter modes. The card itself (placeholders, the
    disfavour curve, drops, the Treasure Hunter verdict) and the by-drop filter
    land in #157; the right pane holds their place until they do.

    ONE LIST, SEVERAL FILTER MODES -- not several windows. Every search here
    returns NMs, so one list serves all of them. The dig search needs two
    windows because its two searches return different KINDS of thing (items and
    zones) and cross-linking them needs a second window to land in; here,
    clicking a zone only re-filters the list already on screen, which is why the
    cross-link problem simply does not exist in this shape.

    THE WINDOW CONTRACT. Any surface may OPEN a floating window; exactly ONE
    site may DRAW it -- gearui's d3d_present, above its M.visible return, so the
    window lives whether or not the main box is open. Two Begin() calls on one
    window name in a frame merge both bodies into it: content twice, ids
    colliding. M.open / M.openName / M.openArea only set state.

    IT OWNS NO ANSWERS. Every question it asks is answered by feature\nmlookup
    -- the matching, the row list, the zone roster, the row note. That module is
    where the chat command asks them too, which is the point: a weak match is
    labelled a guess on both surfaces and gibberish is refused on both, because
    there is one implementation of "does this name match" and not two.

    THE LIST SCROLLS, and that is not a formality. Most zones hold a handful of
    NMs; Escha Ru'Aun holds 61. The rows sit in a BeginChild so a busy zone
    scrolls instead of running off the bottom of the window.

    EVERY DRAWN STRING IS ESCAPED. ImGui text is printf -- a bare `%` in a name
    prints a heap address. `esc` is not optional decoration.
]]--

local host = require("dlac\\ui\\uihost");

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');
local fmt   = try('dlac\\gear\\gearfmt');
-- The compendium core. Required at LOAD, deliberately: the edge runs one way,
-- and nmlookup reaches back for this module only at call time (its `window`
-- verb), so there is no cycle.
local nml   = try('dlac\\feature\\nmlookup');

local M = {};
M.VERSION = 1;
M.visible = false;

local S = host.services;
local COL = (S ~= nil) and S.COL or nil;

-- gearui provides the shared palette before requiring this module. Missing =
-- render nothing, loudly once, rather than a nil index every frame (the
-- unusedui / wishlistui precedent). `degraded` is what `/dl nm window` reads to
-- answer in chat instead of opening a window that will not draw.
if COL == nil or nml == nil then
    pcall(function() print('[dlac] nmui: shared services missing -- the NM Compendium window is disabled.'); end);
    M.render   = function() end;
    M.open     = function() end;
    M.close    = function() end;
    M.toggle   = function() return false; end;
    M.openName = function() end;
    M.openArea = function() end;
    M.showArea = function() end;
    M.degraded = true;
    host.provide({ nmui = M });
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
    -- The theme font is wide: ~9.5px a character (hard-won, HANDOFF).
    return math.floor(#tostring(s or '') * 9.5);
end

-- A name search scores EVERY shipped entry, Levenshtein included. Past this
-- many rows the list stops being something a player reads and starts being
-- something they scroll past, so it is capped -- and the count that was cut is
-- printed, because a silent truncation reads as "that is all there is".
M.CAP = 200;

-- ---------------------------------------------------------------------------
-- state -- session-only, like every other floating window's open flag
-- ---------------------------------------------------------------------------
local st = {
    mode = 'area',      -- 'name' | 'area'  (the by-drop mode lands with #157)
    q    = { '' },      -- the name box; a {string} because imgui.InputText wants one
    zid  = nil,         -- the area filter's zone
    zq   = { '' },      -- the area picker's own filter box
    sel  = nil,         -- selected row key ('<zid>/<name>/<index>')
};
M._state = st;          -- test seam: drive a filter mode headlessly

local MODES = {
    { key = 'name', label = 'By name',
      tip = 'Type any part of a name. Matching is forgiving -- a typo still finds it,\n'
         .. 'and a weak match is shown but labelled a guess rather than answered as if\n'
         .. 'it were the monster you asked for.' },
    { key = 'area', label = 'By area',
      tip = 'Every notorious monster in one zone, the ones with placeholders first.\n'
         .. 'Opens on the zone you are standing in.' },
};

-- The selection's identity, and deliberately NOT the row's position: the list
-- re-sorts under the player as they type, and a positional key would silently
-- move the selection onto whatever slid into that slot. Zone + name + the first
-- NM index is stable, and it separates a zone's two same-named entries.
local function rowKey(r)
    local idx = (type(r.e.nm) == 'table') and r.e.nm[1] or nil;
    return string.format('%s/%s/%s', tostring(r.zid), tostring(r.n), tostring(idx));
end

-- ---------------------------------------------------------------------------
-- the result list, REBUILT only when the filter changes
-- ---------------------------------------------------------------------------
-- Scoring 2000+ names sixty times a second for a string that has not changed is
-- the difference between a window and a stutter, so the list is cached on the
-- filter that produced it.
local _cache = { key = nil, rows = {}, total = 0 };

local function currentRows()
    local key = string.format('%s\1%s\1%s', tostring(st.mode),
        tostring(st.q[1] or ''), tostring(st.zid));
    if _cache.key ~= key then
        local rows, total = {}, 0;
        if st.mode == 'name' then
            rows, total = nml.nameRows(st.q[1] or '', M.CAP);
        elseif st.zid ~= nil then
            rows = nml.areaRows(st.zid);
            total = #rows;
        end
        -- The two strings every row draws, built ONCE here rather than twice a
        -- row a frame. They are pure functions of the row, so the cache that
        -- owns the row owns them too.
        for _, r in ipairs(rows) do
            r.note = nml.rowNote(r.e);
            r.zone = nml.zoneName(r.zid);
        end
        _cache.key, _cache.rows, _cache.total = key, rows, total;
    end
    return _cache.rows, _cache.total;
end

-- A zone click reported from inside the row loop and acted on AFTER it. Pivoting
-- mid-loop would leave the rows drawn after the click reading a mode the rows
-- before it were not drawn in -- one frame of a list that disagrees with itself.
local _pivot = nil;

-- Drop the cached list. The key already covers the mode, the query and the zone,
-- so this is for the things it does NOT cover -- the row cap, or a caller that
-- wants the next frame rebuilt no matter what.
local function refilter()
    _cache.key = nil;
end

-- ---------------------------------------------------------------------------
-- openers -- state only. Any surface may call these; only gearui draws.
-- ---------------------------------------------------------------------------
function M.open()  M.visible = true;  end
function M.close() M.visible = false; end
function M.toggle()
    M.visible = not M.visible;
    return M.visible;
end

-- Land on a name search. The window opens whether or not the name matches
-- anything: an empty result is an answer ("nothing resembling that"), and a
-- window that refuses to appear looks like a broken command.
function M.openName(query)
    st.mode = 'name';
    st.q[1] = tostring(query or '');
    st.sel  = nil;
    refilter();
    M.visible = true;
end

-- Land on a zone -- by default the one the player is standing in, which is what
-- makes the common case take no input at all. With no zone to read (a zone
-- load, character select) the picker opens empty rather than guessing at one.
function M.openArea(zid)
    st.mode = 'area';
    st.zid  = tonumber(zid) or st.zid;
    st.sel  = nil;
    refilter();
    M.visible = true;
end

-- The cross-link: clicking a zone RE-FILTERS this list. It never opens a second
-- window, and it does not toggle visibility either -- you are already looking at
-- the window it would open.
function M.showArea(zid)
    st.mode = 'area';
    st.zid  = tonumber(zid) or st.zid;
    st.sel  = nil;
    refilter();
end

-- ---------------------------------------------------------------------------
-- the filter bar
-- ---------------------------------------------------------------------------
-- Buttons-as-tabs, the hobbybar/ammoui idiom: ImGuiCol_Button is the one style
-- enum proven in the field here, and the flag global is nil-checked rather than
-- the function (hard rule 2) so a binding without it loses the highlight and
-- nothing else. The active mode is coloured rather than disabled -- a greyed
-- button reads as "you cannot have this", the opposite of what is true.
local MODE_ON = { 0.20, 0.32, 0.55, 1.00 };

local function drawModes()
    for _, m in ipairs(MODES) do
        local on = (st.mode == m.key);
        local pushed = 0;
        if on and ImGuiCol_Button ~= nil then
            imgui.PushStyleColor(ImGuiCol_Button, MODE_ON); pushed = 1;
        end
        if imgui.Button(m.label .. '##dlacnmmode' .. m.key, { 0, 0 }) and not on then
            st.mode = m.key;
            st.sel  = nil;
            refilter();
        end
        if pushed > 0 then imgui.PopStyleColor(pushed); end
        if imgui.IsItemHovered() then imgui.SetTooltip(m.tip); end
        imgui.SameLine(0, 6);
    end
    imgui.TextColored(COL.DIM, 'Both searches answer with NMs, so they filter one list.');
end

-- The zone picker: an InputText filter over the zone Selectables (imgui has no
-- searchable combo here -- the fishui/chocoui idiom).
local function drawZonePicker()
    local label = (st.zid ~= nil) and nml.zoneName(st.zid) or 'Pick an area';
    imgui.PushItemWidth(textW('Western Altepa Desert') + 40);
    if imgui.BeginCombo('##dlacnmzone', esc(label)) then
        imgui.PushItemWidth(-1);
        imgui.InputText('##dlacnmzonesearch', st.zq, 48);
        imgui.PopItemWidth();
        local needle = tostring(st.zq[1] or ''):lower();
        for _, z in ipairs(nml.zoneChoices()) do
            if needle == '' or z.name:lower():find(needle, 1, true) ~= nil then
                local line = string.format('%s  (%d)', esc(z.name), z.n);
                if imgui.Selectable(line .. '##dlacnmz' .. tostring(z.zid), z.zid == st.zid) then
                    M.showArea(z.zid);
                end
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
end

local function drawFilter()
    if st.mode == 'name' then
        imgui.TextColored(COL.DIM, 'Name:');
        imgui.SameLine(0, 6);
        imgui.PushItemWidth(240);
        -- The return value is deliberately ignored: the cache is keyed on the
        -- TEXT, so a change this binding does not report still rebuilds the
        -- list. Asking whether it changed would make the list depend on a
        -- binding detail nothing else here depends on.
        imgui.InputText('##dlacnmsearch', st.q, 48);
        imgui.PopItemWidth();
        return;
    end
    imgui.TextColored(COL.DIM, 'Area:');
    imgui.SameLine(0, 6);
    drawZonePicker();
end

-- ---------------------------------------------------------------------------
-- the list
-- ---------------------------------------------------------------------------
-- One row: an invisible Selectable as the click target, with the columns drawn
-- over it (the + Add list idiom in gearui). A row is a whole line, so a click
-- anywhere on it selects.
local function drawRow(r, i, nameX)
    local key = rowKey(r);
    -- The widget id is positional (unique within the frame); the SELECTION is
    -- not (it has to survive the list re-sorting).
    if imgui.Selectable('##dlacnmsel' .. i, st.sel == key) then st.sel = key; end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(esc(string.format('%s -- %s\n%s', r.n, r.zone, r.note)));
    end
    imgui.SameLine(4);
    -- A guess is dimmed AND labelled. Colour alone is a hint; the word is the
    -- statement, and the statement is what keeps a typo from silently answering
    -- about the wrong monster.
    imgui.TextColored(r.guess and COL.WANT or COL.USABLE, esc(r.n));
    if r.guess then
        imgui.SameLine(0, 4);
        imgui.TextColored(COL.WANT, '(guess)');
    end
    imgui.SameLine(nameX);
    imgui.TextColored(COL.DIM, esc(r.note));
    -- The zone, only where it is news: in area mode every row shares it.
    if st.mode ~= 'area' then
        imgui.SameLine(0, 8);
        if imgui.SmallButton(esc(r.zone) .. '##dlacnmzj' .. i) then
            _pivot = r.zid;
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Show every NM in this area -- it re-filters this list.');
        end
    end
end

local function drawList(rows, total)
    if st.mode == 'name' and tostring(st.q[1] or ''):gsub('%s', '') == '' then
        imgui.TextColored(COL.DIM, 'Type part of a name.');
        return;
    end
    if st.mode == 'area' and st.zid == nil then
        imgui.TextColored(COL.DIM, 'Pick an area above. (It opens on the zone you are standing in.)');
        return;
    end
    if #rows == 0 then
        if st.mode == 'name' then
            -- Refused, not answered. Offering the closest thing in the game to
            -- gibberish is how a player ends up reading about a monster they
            -- never asked for.
            imgui.TextColored(COL.ERR, esc(string.format('Nothing resembling "%s" in the NM table.',
                tostring(st.q[1] or ''))));
        else
            imgui.TextColored(COL.DIM, 'No notorious monsters in the table for that area.');
        end
        return;
    end

    local anyGuess = false;
    local nameW = 150;
    for _, r in ipairs(rows) do
        if r.guess then anyGuess = true; end
        local w = textW(r.n) + (r.guess and textW(' (guess)') or 0) + 20;
        if w > nameW then nameW = w; end
    end
    nameW = math.min(nameW, 300);

    if st.mode == 'name' and rows[1] ~= nil and rows[1].guess then
        imgui.TextColored(COL.WANT, 'Closest matches to what you typed -- none of them is an exact name.');
    elseif anyGuess then
        imgui.TextColored(COL.DIM, 'The dimmed rows are guesses, not name matches.');
    end

    imgui.BeginChild('##dlacnmrows', { -1, -1 }, false);
    local lok = pcall(function()
        for i, r in ipairs(rows) do
            drawRow(r, i, 4 + nameW);
        end
        if total > #rows then
            imgui.Spacing();
            imgui.TextColored(COL.DIM, string.format('(+%d more -- narrow the search)', total - #rows));
        end
    end);
    imgui.EndChild();     -- ALWAYS: the child closes even if a row threw
    if not lok then imgui.TextColored(COL.ERR, 'the list could not be drawn.'); end
end

-- ---------------------------------------------------------------------------
-- the detail pane -- a PLACEHOLDER this slice (the card is #157)
-- ---------------------------------------------------------------------------
local function selectedRow(rows)
    if st.sel == nil then return nil; end
    for _, r in ipairs(rows) do
        if rowKey(r) == st.sel then return r; end
    end
    return nil;
end

local function drawDetail(rows)
    local r = selectedRow(rows);
    if r == nil then
        imgui.TextColored(COL.DIM, 'Pick one on the left.');
        return;
    end
    imgui.TextColored(COL.HEADER, esc(r.n));
    if r.guess then
        imgui.TextColored(COL.WANT, 'Closest match to what you typed -- not an exact name.');
    end
    -- The zone is a cross-link here too, so a detail pane never dead-ends.
    imgui.TextColored(COL.DIM, 'Area:');
    imgui.SameLine(0, 6);
    if imgui.SmallButton(esc(r.zone or nml.zoneName(r.zid)) .. '##dlacnmdetzone') then
        _pivot = r.zid;      -- acted on at the end of the frame, like the rows'
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Show every NM in this area -- it re-filters the list on the left.');
    end
    imgui.TextColored(COL.STATS, esc(r.note or nml.rowNote(r.e)));
    imgui.Separator();
    if fmt ~= nil and type(fmt.textWrapped) == 'function' then
        fmt.textWrapped(COL.DIM, 'The full card -- the spawn indexes to watch, the pop chance as '
            .. 'disfavour actually moves it, where you are on that curve, the drop table and the '
            .. 'Treasure Hunter verdict -- lands in the next slice.');
    else
        imgui.TextColored(COL.DIM, 'The full card lands in the next slice.');
    end
    imgui.Spacing();
    imgui.TextColored(COL.DIM, 'Meanwhile "/dl nm ' .. esc(r.n) .. '" answers all of it in chat.');
end

-- ---------------------------------------------------------------------------
-- the body
-- ---------------------------------------------------------------------------
-- Kept separate from render() so Begin/End (and every child) pair around a
-- pcall: a throw in here costs one frame of content and says so, instead of
-- leaving the ImGui window stack unbalanced for every surface drawn after us.
local function drawBody()
    if nml.data == nil or next(nml.data) == nil then
        imgui.TextColored(COL.ERR, 'The NM table (data\\nmdata.lua) is missing or empty.');
        imgui.TextColored(COL.DIM, 'Nothing to browse until it is back -- the rest of dlac is unaffected.');
        return;
    end

    drawModes();
    drawFilter();
    imgui.Separator();

    local rows, total = currentRows();

    -- Master-detail. The left pane is a fixed share of the window so the detail
    -- card has room to be a card; both panes are children, so the list scrolls
    -- on its own and a 61-NM zone does not push the pane below it off-screen.
    local availW = 640;
    pcall(function()
        local w = imgui.GetContentRegionAvail();
        if type(w) == 'number' and w > 0 then availW = w; end
    end);
    local leftW = math.floor(availW * 0.5);
    if leftW < 240 then leftW = 240; end
    if leftW > 460 then leftW = 460; end

    imgui.BeginChild('##dlacnmleft', { leftW, -1 }, true);
    local lok = pcall(drawList, rows, total);
    imgui.EndChild();
    if not lok then imgui.TextColored(COL.ERR, 'the list could not be drawn.'); end

    imgui.SameLine(0, 8);

    imgui.BeginChild('##dlacnmdetail', { -1, -1 }, true);
    local dok = pcall(drawDetail, rows);
    imgui.EndChild();
    if not dok then imgui.TextColored(COL.ERR, 'the detail pane could not be drawn.'); end

    -- The zone click, acted on now that the whole frame has been drawn in ONE
    -- state. The list pivots on the next frame; nothing on this one disagrees
    -- with anything else on it.
    if _pivot ~= nil then
        local z = _pivot;
        _pivot = nil;
        M.showArea(z);
    end
end

function M.render()
    if imgui == nil or not M.visible then return; end
    local vis = { true };
    imgui.SetNextWindowSize({ 760, 460 }, ImGuiCond_FirstUseEver or 4);
    local opened = imgui.Begin('dlac -- NM Compendium##dlac_nm', vis, ImGuiWindowFlags_None or 0);
    if opened then
        local ok, err = pcall(drawBody);
        if not ok then
            pcall(imgui.TextColored, COL.ERR, esc('render error: ' .. tostring(err)));
        end
    end
    imgui.End();          -- ALWAYS, opened or not: ImGui pairs Begin with End
    if not vis[1] then M.visible = false; end
end

host.provide({ nmui = M });
return M;
