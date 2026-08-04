--[[
    dlac/ui/nmui.lua -- the NM Compendium window (issues #156 + #157, PRD #151).

    One floating window, master-detail: the filter and the result list on the
    left, the NM's detail card on the right. #156 built the shell and the
    by-name / by-area modes; #157 filled the card in and added the third mode.

    ONE LIST, SEVERAL FILTER MODES -- not several windows. Every search here
    returns NMs, so one list serves all of them. The dig search needs two
    windows because its two searches return different KINDS of thing (items and
    zones) and cross-linking them needs a second window to land in; here,
    clicking a zone -- or a DROP -- only re-filters the list already on screen,
    which is why the cross-link problem simply does not exist in this shape.

    THE WINDOW CONTRACT. Any surface may OPEN a floating window; exactly ONE
    site may DRAW it -- gearui's d3d_present, above its M.visible return, so the
    window lives whether or not the main box is open. Two Begin() calls on one
    window name in a frame merge both bodies into it: content twice, ids
    colliding. M.open / M.openName / M.openArea only set state.

    IT OWNS NO ANSWERS, AND THE CARD IS WHERE THAT EARNS ITS KEEP. Every figure
    on it is already computed somewhere else and consumed here:

        feature\nmlookup  -- the matching, the rows, the zone roster, the row
                             note, the pop lines (kind, repop window, the base
                             chance, the disfavour curve, rounds to guaranteed),
                             the FilterScan filter, and the by-drop mode's rows.
        feature\nmtrack   -- the live count: rounds witnessed, the current
                             chance, the cooldown / primed states, and the
                             STALE record that must render no percentage.
        feature\nmloot    -- the drop table: rolls, groups and their shares,
                             tier names, and the Treasure Hunter verdict.

    Not one percentage is worked out in this file, and that is the rule: a
    second implementation of any of them is how the window and the chat command
    start disagreeing about the same monster in the same session. The stale-count
    rule survives BY CONSTRUCTION rather than by care -- nmtrack answers `chance
    = nil` for a stale record, so there is no number here to render.

    THE LIST SCROLLS, and that is not a formality. Most zones hold a handful of
    NMs; Escha Ru'Aun holds 61. The rows sit in a BeginChild so a busy zone
    scrolls instead of running off the bottom of the window. The CARD scrolls
    for the same reason and is deliberately NOT capped the way the chat readout
    is: chat stops at 32 rolls because nobody wants a hundred lines scrolling
    past, and a pane that scrolls on its own has no such problem.

    EVERY DRAWN STRING IS ESCAPED. ImGui text is printf -- a bare `%` in a name
    prints a heap address. This pane is nothing but percentages, so `esc` is not
    optional decoration; it is the difference between "common (15%)" and a heap
    address. It has shipped as a real bug in this repo.
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
-- THE central "issue a game command" door (Henrik's ruling 2026-07-29: one
-- reusable function, never a per-module wrapper). It queues on the frame clock,
-- so the FilterScan line leaves on the next tick on the main thread rather than
-- inside this render call.
local cmdq  = try('dlac\\lib\\cmdqueue');

-- The two modules the card reads, reached at CALL time and never captured: they
-- require nmlookup at load, this file requires nmlookup at load, and a build
-- where either failed must cost the card a section rather than the window.
local function tracker() return try('dlac\\feature\\nmtrack'); end
local function loot()    return try('dlac\\feature\\nmloot');  end

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
    M.showDrop = function() end;
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
    mode = 'area',      -- 'name' | 'area' | 'drop'
    q    = { '' },      -- the name box; a {string} because imgui.InputText wants one
    zid  = nil,         -- the area filter's zone
    zq   = { '' },      -- the area picker's own filter box
    dq   = { '' },      -- the by-drop box
    sel  = nil,         -- selected row key ('<zid>/<name>/<index>')
    th   = 0,           -- the Treasure Hunter level the card reads drops at
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
    { key = 'drop', label = 'By drop',
      tip = 'Type an item and the list becomes every NM that drops it.\n'
         .. 'Matching here is strict -- across 2183 items a near-miss is noise, not a\n'
         .. 'hedge -- so a name it does not recognise is refused rather than guessed at.\n'
         .. 'Clicking a drop on the card comes here too.' },
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
local _cache = { key = nil, rows = {}, total = 0, items = {} };

local function currentRows()
    local key = string.format('%s\1%s\1%s\1%s', tostring(st.mode),
        tostring(st.q[1] or ''), tostring(st.zid), tostring(st.dq[1] or ''));
    if _cache.key == key then return _cache.rows, _cache.total, _cache.items; end

    local rows, total, items = {}, 0, {};
    local keep = true;
    if st.mode == 'name' then
        rows, total = nml.nameRows(st.q[1] or '', M.CAP);
    elseif st.mode == 'drop' then
        -- The reverse lookup. It resolves every drop-table item name through
        -- the client once, which is exactly why this is behind the same cache
        -- as the rest: per frame it would be a stutter.
        rows, total, items = nml.dropRows(st.dq[1] or '', M.CAP);
        -- ...but an empty answer from a client that could name NOTHING is not
        -- an answer, it is "cannot tell yet" (ADR 0007 -- a latch makes one bad
        -- read permanent). In the moments after a login the item resources
        -- answer with nothing, so every by-drop search reads as "nothing drops
        -- that", and caching it would keep saying so long after the client
        -- caught up. So that one result is left UNCACHED: it costs an early
        -- return a frame, because nmloot's own retry throttle makes the re-ask
        -- free, and it heals itself the moment names arrive.
        local lt = loot();
        if total == 0 and lt ~= nil and type(lt.namedCount) == 'function'
           and lt.namedCount() == 0 then
            keep = false;
        end
    elseif st.zid ~= nil then
        rows = nml.areaRows(st.zid);
        total = #rows;
    end
    -- The two strings every row draws, built ONCE here rather than twice a row
    -- a frame. They are pure functions of the row, so the cache that owns the
    -- row owns them too.
    for _, r in ipairs(rows) do
        r.note = nml.rowNote(r.e);
        r.zone = nml.zoneName(r.zid);
    end
    _cache.key   = keep and key or nil;
    _cache.rows, _cache.total, _cache.items = rows, total, items;
    return rows, total, items;
end

-- A zone click reported from inside the row loop and acted on AFTER it. Pivoting
-- mid-loop would leave the rows drawn after the click reading a mode the rows
-- before it were not drawn in -- one frame of a list that disagrees with itself.
local _pivot = nil;
-- The drop click, held for the same reason and kept apart because it pivots to
-- a different MODE: acting on it mid-card would redraw the list under a card
-- that was half-drawn from the row it is about to stop being about.
local _pivotDrop = nil;
-- What the last FilterScan apply did, and for WHICH row -- so the answer sits
-- under the button that was pressed and vanishes the moment the card is about
-- another monster. A silent button is indistinguishable from a broken one.
local _apply = nil;

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

-- The other cross-link, and the mirror of the one above: clicking a DROP on the
-- card re-filters the list to every NM that gives it. Same shape for the same
-- reason -- all three modes answer with NMs, so the answer lands in the list
-- already on screen and no second window is needed to hold it.
function M.showDrop(item)
    st.mode  = 'drop';
    st.dq[1] = tostring(item or '');
    st.sel   = nil;
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
    imgui.TextColored(COL.DIM, 'All three answer with NMs, so they filter one list.');
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
    if st.mode == 'drop' then
        imgui.TextColored(COL.DIM, 'Drop:');
        imgui.SameLine(0, 6);
        imgui.PushItemWidth(240);
        imgui.InputText('##dlacnmdropsearch', st.dq, 48);
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
    -- In the by-drop mode the news is WHICH drop answered, not how the NM pops
    -- -- that is what the card is for, and the row was listed because of the
    -- item. The pop note is still one hover away, on the tooltip above.
    imgui.TextColored(COL.DIM, esc((st.mode == 'drop') and (r.dropNote or r.note) or r.note));
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

local function drawList(rows, total, items)
    if st.mode == 'name' and tostring(st.q[1] or ''):gsub('%s', '') == '' then
        imgui.TextColored(COL.DIM, 'Type part of a name.');
        return;
    end
    if st.mode == 'drop' and tostring(st.dq[1] or ''):gsub('%s', '') == '' then
        imgui.TextColored(COL.DIM, 'Type an item -- the list becomes every NM that drops it.');
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
        elseif st.mode == 'drop' then
            -- Refused for the same reason, and one more: the drop table is
            -- what the server publishes, so "nothing here drops that" is a
            -- real answer -- and it is not the same statement as "no such
            -- item", which this cannot know (hard rule 12).
            imgui.TextColored(COL.ERR, esc(string.format('No NM in the drop table drops anything called "%s".',
                tostring(st.dq[1] or ''))));
            imgui.TextColored(COL.DIM, 'Field NMs only -- the table holds no instanced content.');
        else
            imgui.TextColored(COL.DIM, 'No notorious monsters in the table for that area.');
        end
        return;
    end

    -- What the list is OF. A search for "boots" answers about several items,
    -- and a list of NMs with no statement of which item each answered for is a
    -- list nobody can act on.
    if st.mode == 'drop' and items ~= nil and #items > 0 then
        local named = items[1];
        if #items > 1 then named = named .. string.format(' (+%d more matching)', #items - 1); end
        imgui.TextColored(COL.DIM, esc('Every NM that drops ' .. named .. ':'));
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
-- the detail card (issue #157) -- the payoff, and it computes nothing
-- ---------------------------------------------------------------------------
local function selectedRow(rows)
    if st.sel == nil then return nil; end
    for _, r in ipairs(rows) do
        if rowKey(r) == st.sel then return r; end
    end
    return nil;
end

local function section(title)
    imgui.Spacing();
    imgui.TextColored(COL.HEADER, title);
end

-- Wrapped AND escaped. Every sentence on this card carries a percentage, and an
-- unescaped `%` in an ImGui string prints a heap address.
local function line(col, s)
    if fmt ~= nil and type(fmt.textWrapped) == 'function' then
        fmt.textWrapped(col, esc(s));
    else
        imgui.TextColored(col, esc(s));
    end
end

-- The readouts consumed from nmlookup and nmtrack arrive with their two-space
-- CHAT indent. The card supplies its own, so it is stripped rather than drawn
-- as a ragged left edge.
local function chatLine(col, s)
    line(col, (tostring(s or ''):gsub('^%s+', '')));
end

-- The chocoui indent idiom: a zero-height Dummy, then SameLine with no spacing.
local function indent(px)
    imgui.Dummy({ px, 0 });
    imgui.SameLine(0, 0);
end

-- ---- the spawn points, and the one-click filter over them ------------------
local function cardPlaceholders(entry, key)
    section('Placeholders');
    local ph = (type(entry.ph) == 'table') and entry.ph or {};
    if #ph == 0 then
        -- NOT an empty card. An NM with no placeholders is not a gap in the
        -- table, it is a monster that pops another way -- and the section
        -- below says which way.
        line(COL.DIM, 'None in the table -- this one does not come from a placeholder.');
    else
        indent(8);
        imgui.TextColored(COL.USABLE, esc(string.format('%s x%d', tostring(entry.p or '?'), #ph)));
        imgui.SameLine(0, 8);
        imgui.TextColored(COL.STATS, esc('indexes ' .. nml.runs(ph)));
    end
    local nmIdx = (type(entry.nm) == 'table') and entry.nm or {};
    if #nmIdx > 0 then
        indent(8);
        imgui.TextColored(COL.USABLE, esc(tostring(entry.n or '?')));
        imgui.SameLine(0, 8);
        imgui.TextColored(COL.STATS,
            esc(((#nmIdx > 1) and 'indexes ' or 'index ') .. nml.runs(nmIdx)));
    end

    -- THE ACTION. One click, and the widescan shows only these spawn points --
    -- which is the whole reason the indexes are worth reading. It goes out
    -- through the central command door, so the line leaves on the next frame
    -- on the main thread rather than from inside this render call.
    local f = nml.filterFor(entry);
    if f == nil then
        line(COL.DIM, 'No indexes to narrow a widescan with for this one.');
        return;
    end
    if imgui.Button('Apply FilterScan filter##dlacnmapply', { 0, 0 }) then
        local sent = false;
        if cmdq ~= nil and type(cmdq.issue) == 'function' then
            sent = (cmdq.issue('/filterscan ' .. f) == true);
        end
        _apply = { key = key, ok = sent };
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(esc('Sends  /filterscan ' .. f
            .. '\n(FilterScan must be loaded for this to bite.)'));
    end
    imgui.SameLine(0, 8);
    imgui.TextColored(COL.DIM, esc('/filterscan ' .. f));
    -- A button that says nothing back is indistinguishable from a broken one
    -- (hard rule 12), and the answer is tied to the row so it cannot outlive
    -- the card it was pressed on.
    if _apply ~= nil and _apply.key == key then
        if _apply.ok then
            line(COL.HAVE, 'Applied -- FilterScan must be loaded for this to bite.');
        else
            line(COL.ERR, 'Could not send the command -- type the line above instead.');
        end
    end
end

-- ---- how it pops: the kind, the window, the base, and the curve ------------
-- Straight from nmlookup.popLines, which is what the chat command prints. That
-- is not laziness: the disfavour curve, the "not a lottery, so no curve"
-- caveat and the admission that a base chance is missing are all decisions with
-- a reason recorded, and a second rendering of them is a second place for one
-- of those reasons to be lost.
local function cardPop(entry)
    section('How it pops');
    local lines = nil;
    pcall(function() lines = nml.popLines(entry); end);
    if type(lines) ~= 'table' or #lines == 0 then
        line(COL.DIM, 'The table does not say how this one pops.');
        return;
    end
    for _, s in ipairs(lines) do chatLine(COL.STATS, s); end
end

-- ---- where YOU are on that curve -------------------------------------------
local function cardTracking(entry, zid)
    local trk = tracker();
    if trk == nil or type(trk.entryLines) ~= 'function' then return; end
    local ok, lines = pcall(trk.entryLines, entry, zid);
    if not ok or type(lines) ~= 'table' or #lines == 0 then return; end
    -- The COLOUR comes from the tracker's own verdict, never from reading its
    -- words back. A stale record, a cooldown and a primed camp all mean "this
    -- number is not what you would take it for", and the eye should say so
    -- before the sentence does. The stale record carries no percentage to
    -- render in the first place -- nmtrack answers nil for it, so that rule
    -- holds here by construction and not by care.
    local col = COL.STATS;
    pcall(function()
        local now = tonumber(trk.reads.now()) or 0;
        local sts = trk.status(trk.record(zid, entry), entry, now);
        if type(sts) == 'table' and (sts.stale or sts.roll ~= 'ok' or sts.hedge) then
            col = COL.WANT;
        end
    end);
    section('Your count');
    for _, s in ipairs(lines) do chatLine(col, s); end
end

-- ---- the drop table, and the Treasure Hunter verdict -----------------------
-- The level the card reads the drop table at. A LEVEL and not a toggle,
-- because TH is a bracket lookup: "what would this drop at TH4" is a question
-- with an exact answer, and it is the one a THF asks before deciding whether
-- the gear is worth the slots.
local function drawTHPicker(lt)
    local maxTH = tonumber(lt.TH_MAX) or 14;
    imgui.TextColored(COL.DIM, 'Treasure Hunter:');
    imgui.SameLine(0, 6);
    imgui.PushItemWidth(textW('TH14') + 34);
    if imgui.BeginCombo('##dlacnmth', 'TH' .. tostring(st.th)) then
        for lvl = 0, maxTH do
            if imgui.Selectable('TH' .. lvl .. '##dlacnmthl' .. lvl, lvl == st.th) then
                st.th = lvl;
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('TH is a lookup, not a multiplier: the rate picks a rarity bracket\n'
            .. 'and the TH level picks the value inside it. TH0 is no TH gear at all.');
    end
end

-- What the chosen level does to one roll, as the tail of its line.
-- -> text, colour  (nil when there is nothing worth saying)
--
-- THE VERDICT IS SHOWN AT EVERY LEVEL, INCLUDING TH0: "no gain, it already
-- drops every time" is the answer a player needs BEFORE they know to ask for a
-- level, and it is the one an unchanged number could never give them.
--
-- The FIGURE at TH0 is held back where it would only repeat the rate already
-- printed beside it -- with one exception that is not noise. Because the rate
-- merely SELECTS a bracket, an off-tier rate does not read back as itself (the
-- 68 shipped rows at `gr = 750` read 24%), and that is precisely the number
-- that looks like a bug when it is left unsaid.
local function thTail(lt, stored, isGroup)
    local helps, txt = lt.thVerdict(stored, st.th, isGroup);
    if not helps then return txt, COL.DIM; end
    if (tonumber(st.th) or 0) > 0 then
        return string.format('TH%d %s', st.th, txt), COL.SCORE;
    end
    local at, stated = lt.thPct(0, stored), lt.pctOf(stored);
    if at ~= nil and stated ~= nil and math.abs(at - stated) > 1e-9 then
        return 'TH0 ' .. txt, COL.SCORE;
    end
    return nil, nil;
end

-- One drop, and it is a BUTTON: clicking it pivots the list to every NM that
-- gives it -- the mirror of the zone button on a row, and what keeps the card
-- from being where browsing stops.
local function drawDrop(name, key, px, rateTxt, tailTxt, tailCol)
    indent(px);
    if imgui.SmallButton(esc(name) .. '##dlacnmdrop' .. key) then _pivotDrop = name; end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(esc(string.format(
            'Show every NM that drops %s -- it re-filters the list on the left.', name)));
    end
    if rateTxt ~= nil and rateTxt ~= '' then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL.STATS, esc(rateTxt));
    end
    if tailTxt ~= nil and tailTxt ~= '' then
        imgui.SameLine(0, 8);
        imgui.TextColored(tailCol or COL.SCORE, esc(tailTxt));
    end
end

local function cardDrops(entry)
    section('Drops');
    local lt = loot();
    if lt == nil then
        line(COL.DIM, 'The drop readout is not available in this build.');
        return;
    end
    -- Three absences, and they must not look alike (hard rule 12).
    if type(lt.data) ~= 'table' or next(lt.data) == nil then
        line(COL.ERR, 'The drop table (data\\nmdrops.lua) is missing or empty.');
        return;
    end
    if not lt.hasPool(entry) then
        line(COL.DIM, 'This NM table carries no pool id, so its drops cannot be looked up '
            .. '-- the data file predates them.');
        return;
    end
    local rows = lt.rowsFor(entry);
    if #rows == 0 then
        line(COL.DIM, 'Nothing in the drop table for this one.');
        return;
    end
    -- Under the absences, not above them: a TH level to read rates at is only
    -- a question worth asking once there are rates to read.
    drawTHPicker(lt);

    local kill, take = lt.rolls(rows);
    if #kill == 0 then
        -- Five shipped pools are Steal and Despoil and nothing else. Saying so
        -- is not the same as saying nothing.
        line(COL.DIM, 'Nothing a kill gives -- this one only has what is below.');
    else
        local grouped = false;
        for _, b in ipairs(kill) do
            if b.kind == 'group' and #b.rows > 1 then grouped = true; end
        end
        -- "rolls" and not "items": the same item can appear twice, and those
        -- are two independent rolls rather than a bug in the table.
        line(COL.DIM, (#kill == 1) and '1 roll:'
            or string.format('%d rolls, each rolled on its own:', #kill));
        if grouped then
            line(COL.DIM, 'A group rolls once, then ONE item in it wins by weight '
                .. '-- the % beside a member is its share of the group.');
        end
        if (tonumber(st.th) or 0) > 0 then
            line(COL.DIM, 'TH is a lookup, not a multiplier -- the rate picks a rarity '
                .. 'bracket, the TH level picks the value in it.');
        end
        -- Deliberately UNCAPPED where chat stops at 32 rolls and 12 members:
        -- the pane scrolls, so the reason for the cap does not exist here.
        for k, b in ipairs(kill) do
            if b.kind == 'group' and #b.rows > 1 then
                indent(8);
                imgui.TextColored(COL.STATS,
                    esc(string.format('one of these, %s:', lt.rateText(b.gr) or 'rate not stated')));
                local tail, tcol = thTail(lt, b.gr, true);
                if tail ~= nil then
                    imgui.SameLine(0, 8);
                    imgui.TextColored(tcol, esc(tail));
                end
                for j, row in ipairs(b.rows) do
                    local share = lt.shareOf(b, row);
                    drawDrop(lt.itemName(row.i), string.format('%d_%d', k, j), 24,
                        (share ~= nil) and lt.pctText(share) or nil, nil, nil);
                end
            else
                -- A group of ONE is drawn as a plain drop at the GROUP's rate:
                -- that IS its chance, and there is nothing for it to be "one
                -- of". A presentation choice -- TH still reads the group rate.
                local row  = (b.kind == 'group') and b.rows[1] or b.row;
                local rate = (b.kind == 'group') and b.gr or row.r;
                local tail, tcol = thTail(lt, rate, false);
                drawDrop(lt.itemName(row.i), tostring(k), 8, lt.rateText(rate), tail, tcol);
            end
        end
    end

    if #take > 0 then
        local hows, seen = {}, {};
        for _, tk in ipairs(take) do
            if not seen[tk.how] then seen[tk.how] = true; hows[#hows + 1] = tk.how; end
        end
        imgui.Spacing();
        -- Their own block, because listing them as drops tells a player to
        -- expect something a kill will never give.
        line(COL.DIM, string.format('Not kill loot -- %s only, a kill never gives these:',
            table.concat(hows, ' / ')));
        for k, tk in ipairs(take) do
            local rate = lt.rateText(tk.row.r);
            local lbl  = '(' .. tk.how .. ')';
            if rate ~= nil then lbl = lbl .. '  ' .. rate; end
            drawDrop(lt.itemName(tk.row.i), 't' .. tostring(k), 8, lbl, nil, nil);
        end
        if (tonumber(st.th) or 0) > 0 then
            -- Said rather than left to be read as "TH does nothing for these".
            line(COL.DIM, 'No TH figures here -- the lookup above is the kill\'s drop roll, '
                .. 'which is not where these come from.');
        end
    end
end

local function drawDetail(rows)
    local r = selectedRow(rows);
    if r == nil then
        imgui.TextColored(COL.DIM, 'Pick one on the left.');
        return;
    end
    local key = rowKey(r);
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
    imgui.Separator();
    cardPlaceholders(r.e, key);
    cardPop(r.e);
    cardTracking(r.e, r.zid);
    cardDrops(r.e);
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

    local rows, total, items = currentRows();

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
    local lok = pcall(drawList, rows, total, items);
    imgui.EndChild();
    if not lok then imgui.TextColored(COL.ERR, 'the list could not be drawn.'); end

    imgui.SameLine(0, 8);

    imgui.BeginChild('##dlacnmdetail', { -1, -1 }, true);
    local dok = pcall(drawDetail, rows);
    imgui.EndChild();
    if not dok then imgui.TextColored(COL.ERR, 'the detail pane could not be drawn.'); end

    -- The two pivots, acted on now that the whole frame has been drawn in ONE
    -- state. The list pivots on the next frame; nothing on this one disagrees
    -- with anything else on it. A drop click wins a tie -- it came from the
    -- card, which is the more specific of the two gestures.
    if _pivotDrop ~= nil then
        local item = _pivotDrop;
        _pivotDrop, _pivot = nil, nil;
        M.showDrop(item);
    elseif _pivot ~= nil then
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
