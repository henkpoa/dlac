--[[
    bludex/ui/setsui.lua -- the Sets tab: saved sets, the 20-slot editor, the
    live budget meters, apply/read/clear against the game, and the computed
    stats + traits panel for the set being edited.

    The budget meter prefers the LIVE client value (lib/blu points signature;
    CatsEyeXI's custom merit/learning bonuses included). Everything degrades:
    no signature -> settings override -> '?'.
]]--

local ROOT = (...):sub(1, -#('ui\\setsui') - 1);     -- relocatable require base
local kit      = require(ROOT .. 'ui\\kit');
local filetex  = require(ROOT .. 'ui\\filetex');
local spellsui = require(ROOT .. 'ui\\spellsui');

local M = {};

local LEFT_W  = 210;
local MID_W   = 330;

-- ---------------------------------------------------------------------------
-- the set actions -- ONE definition each, shared by the Sets tab buttons and
-- the window header's Save / Apply / Revert (host.renderBody)
-- ---------------------------------------------------------------------------

-- Save the editing set into the saved list (the active entry, or a new one).
function M.saveEditing(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local copy = ctx.sets.clone(st.editingSet, st.editingSet.name);
    copy.name = st.editingSet.name;
    if st.activeSet and cfg.sets[st.activeSet] then
        cfg.sets[st.activeSet] = copy;
    else
        table.insert(cfg.sets, copy);
        st.activeSet = #cfg.sets;
    end
    cfg.activeSetName = copy.name;                 -- remembered across loads
    if ctx.save then ctx.save(); end
    st.applyNote = 'Saved.';
end

-- Revert the editing set to its saved copy (or to a fresh empty set when
-- nothing is saved yet) -- removes ALL unsaved changes.
function M.revertEditing(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local saved = st.activeSet and cfg.sets[st.activeSet] or nil;
    if saved ~= nil then
        st.editingSet = ctx.sets.clone(saved, saved.name);
        st.applyNote = 'Reverted to the saved set.';
    else
        st.editingSet = ctx.sets.new(('Set %d'):format(#cfg.sets + 1));
        st.applyNote = 'Reverted - empty set.';
    end
    st.addNote = nil;
end

-- Apply the editing set in game (diff), snapshotting the auto-restore
-- target. Says WHY when it cannot.
function M.applyEditing(ctx)
    local st = ctx.state;
    if ctx.blu.applying then return; end
    if not ctx.blu.canApply() then
        st.applyNote = ctx.blu.onBlu()
            and 'Cannot apply: the client memory signatures did not resolve.'
            or 'Cannot apply: BLU is not your main or sub job.';
        return;
    end
    if ctx.blu.applyDiff(st.editingSet.ids, ctx.book) then
        local snap = {};
        for k = 1, 20 do snap[k] = st.editingSet.ids[k] or 0; end
        ctx.cfg.lastApplied = { ids = snap };
        if ctx.save then ctx.save(); end
        st.applyNote = 'Applying the changes, lowest level first - watch the chat log.';
    end
end

-- Does the editing set differ from its SAVED copy? Drives the header's
-- green Save and the Revert. With no active saved set, any content counts.
function M.unsaved(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local saved = st.activeSet and cfg.sets[st.activeSet] or nil;
    if saved == nil then
        return ctx.sets.count(st.editingSet) > 0;
    end
    if tostring(saved.name) ~= tostring(st.editingSet.name) then return true; end
    for i = 1, 20 do
        if (saved.ids[i] or 0) ~= (st.editingSet.ids[i] or 0) then return true; end
    end
    return false;
end

-- ---------------------------------------------------------------------------
-- saved sets (persisted in settings as { name = s, ids = {20} })
-- ---------------------------------------------------------------------------
local function savedList(ctx)
    local im, st, cfg = ctx.im, ctx.state, ctx.cfg;
    kit.header(im, 'Saved sets');
    if kit.isFn(im, 'Selectable') then
        for i, entry in ipairs(cfg.sets) do
            local label = ('%s (%d)##bdxset%d'):format(entry.name, (function()
                local n = 0;
                for k = 1, 20 do if (entry.ids[k] or 0) ~= 0 then n = n + 1; end end
                return n;
            end)(), i);
            local ok, clicked = pcall(im.Selectable, kit.esc(label), st.activeSet == i);
            if ok and clicked then
                st.activeSet = i;
                st.editingSet = ctx.sets.clone(entry, entry.name);
                st.applyNote = nil;
                cfg.activeSetName = entry.name;    -- remembered across loads
                if ctx.save then ctx.save(); end
            end
        end
    end
    if #cfg.sets == 0 then
        kit.ctext(im, kit.COL.dim, 'none yet');
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    local rowW = kit.measure(im, { 'New', 'Save', 'Delete' }, 50);
    if kit.litButton(im, 'New', false, rowW, 22) then
        st.editingSet = ctx.sets.new(('Set %d'):format(#cfg.sets + 1));
        st.activeSet = nil;
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Save', false, rowW, 22) then
        M.saveEditing(ctx);
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Delete', false, rowW, 22) then
        if st.activeSet and cfg.sets[st.activeSet] then
            table.remove(cfg.sets, st.activeSet);
            st.activeSet = nil;
            cfg.activeSetName = '';
            if ctx.save then ctx.save(); end
            st.applyNote = 'Deleted.';
        end
    end

    -- name box
    kit.ctext(im, kit.COL.dim, 'Name');
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(LEFT_W - 20); end
    if kit.isFn(im, 'InputText') then
        st.nameBuf[1] = st.editingSet.name;
        if pcall(im.InputText, '##bdxsetname', st.nameBuf, 48) then
            st.editingSet.name = st.nameBuf[1];
        end
    end
end

-- ---------------------------------------------------------------------------
-- the slot grid + meters + game actions
-- ---------------------------------------------------------------------------

-- The LIST flavor of the slot area (Henrik 2026-08-04): the set's spells as
-- codex-grammar rows -- left-click Spell Info, right-click removes, the
-- live state as a label tag. Empty slots collapse into one dim count.
local function slotList(ctx, liveIds)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    local nameW = math.max(kit.availWidth(im, MID_W) - 24 - 40, 120);
    local shown = 0;
    for i = 1, 20 do
        local id = set.ids[i] or 0;
        if id ~= 0 then
            shown = shown + 1;
            local s = book.spells[id];
            local liveTag = '';
            if liveIds ~= nil then
                liveTag = liveIds[id] and '' or '  (not active yet)';
            end
            local label = ((s ~= nil) and s.name or ('#' .. id)) .. liveTag;
            local lclick, rclick = spellsui.listRow(ctx, id, 24, nameW,
                st.selectedId == id, true, { label = label });
            if lclick then
                st.selectedId = id;
                st.detailOpen[1] = true;
                st.detailFocus = true;
            end
            if rclick then
                ctx.sets.removeSlot(set, i);
                st.applyNote = nil;
            end
            spellsui.tooltip(ctx, id);
        end
    end
    if shown == 0 then
        kit.ctext(im, kit.COL.dim, 'The set is empty - add spells from the Codex or Traits.');
    else
        local free = 20 - ctx.sets.count(set);
        if free > 0 then
            kit.ctext(im, kit.COL.dim, ('%d free slot%s'):format(free, free == 1 and '' or 's'));
        end
    end
end
local function slotGrid(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    st.detailOpen = st.detailOpen or { false };

    -- the layout choice on the header line (Henrik 2026-08-04): the spatial
    -- 5x4 grid, or codex-grammar rows with names. Persisted.
    kit.ctext(im, kit.COL.head, 'Slots');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local layout = ctx.cfg.setsLayout or 'grid';
    local lw = kit.measure(im, { 'Grid', 'List' }, 40);
    if kit.litButton(im, 'Grid', layout == 'grid', lw, 18) and layout ~= 'grid' then
        ctx.cfg.setsLayout = 'grid'; layout = 'grid';
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'The 5x4 slot cells.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'List', layout == 'list', lw, 18) and layout ~= 'list' then
        ctx.cfg.setsLayout = 'list'; layout = 'list';
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'Named rows, like the Codex: left-click for Spell Info,\nright-click removes from the set.');
    if kit.isFn(im, 'Separator') then im.Separator(); end

    -- what the CLIENT has set right now, refreshed every frame: spells not
    -- yet live draw dimmed and light up one by one as an apply lands them.
    -- nil when the live set is unreadable (then nothing is dimmed).
    local liveIds = nil;
    local live = ctx.blu.currentSet();
    if #live == 20 then
        liveIds = {};
        for i = 1, 20 do if live[i] ~= 0 then liveIds[live[i]] = true; end end
    end

    if layout == 'list' then
        slotList(ctx, liveIds);
    else
    -- center the 5-cell rows in the column: equal space both sides
    -- (the grid body keeps its original indent; the else wraps it)
    local cell = 48;
    local gridW = (cell + 4) * 5 + 8 * 4;      -- cell+frame padding, 8px gaps
    local pad = math.max(0, math.floor((kit.availWidth(im, MID_W) - gridW) / 2));
    for i = 1, 20 do
        if ((i - 1) % 5) ~= 0 and kit.isFn(im, 'SameLine') then im.SameLine(); end
        if ((i - 1) % 5) == 0 and pad > 0
            and kit.isFn(im, 'GetCursorPosX') and kit.isFn(im, 'SetCursorPosX') then
            local okx, cx = pcall(im.GetCursorPosX);
            if okx and type(cx) == 'number' then pcall(im.SetCursorPosX, cx + pad); end
        end
        local id = set.ids[i] or 0;
        if id ~= 0 then
            local inGame = liveIds == nil or liveIds[id] == true;
            if spellsui.spellButton(ctx, id, cell, false, not inGame) then
                ctx.sets.removeSlot(set, i);
                st.applyNote = nil;
            end
            local liveLine = '';
            if liveIds ~= nil then
                liveLine = inGame and '\nactive in game' or '\nnot active in game (Apply sends it)';
            end
            local s = book.spells[id];
            if s ~= nil then
                kit.tip(im, ('%s\n%d pts%s%s\nclick to remove'):format(
                    s.name, s.setPoints or 0,
                    s.mpCost and ('  ' .. s.mpCost .. ' MP') or '', liveLine));
            else
                kit.tip(im, ('slot %d: spell id %d is not in the data%s\nclick to remove'):format(i, id, liveLine));
            end
        else
            local pushed = false;
            if kit.isFn(im, 'PushID') then pcall(im.PushID, 'bdxslot' .. i); pushed = true; end
            local h = filetex.ui('slot-empty-64');
            if h ~= nil and kit.isFn(im, 'ImageButton') then
                local styled = false;
                if kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
                    im.PushStyleColor(21, { 0, 0, 0, 0 });
                    im.PushStyleColor(22, { 0.20, 0.42, 0.74, 0.30 });
                    im.PushStyleColor(23, { 0.20, 0.42, 0.74, 0.50 });
                    im.PushStyleColor(5,  { 0, 0, 0, 0 });   -- Border: no square outline
                    styled = true;
                end
                -- same call shape as spellButton (frame padding 2) so image
                -- cells always land at cell+4 regardless of which art loads
                local okB = pcall(im.ImageButton, h, { cell, cell }, { 0, 0 }, { 1, 1 }, 2,
                    { 0, 0, 0, 0 }, { 1, 1, 1, 0.9 });
                if not okB then pcall(im.ImageButton, h, { cell, cell }); end
                if styled then im.PopStyleColor(4); end
            else
                -- +4: match the image cells' 2px frame padding per side.
                -- '##e' = a blank cell (the '-' read as content in the field)
                kit.litButton(im, '##e', false, cell + 4, cell + 4);
            end
            if pushed and kit.isFn(im, 'PopID') then pcall(im.PopID); end
            kit.tip(im, ('slot %d (empty)'):format(i));
        end
    end
    end

    if kit.isFn(im, 'Separator') then im.Separator(); end
    local used = ctx.sets.usedPoints(st.editingSet, book);
    local max = ctx.budgetMax();
    kit.meter(im, 'Points', used, max, '');
    if max == nil then
        kit.tip(im, 'Live budget appears when you are on BLU.\nSet an override in settings otherwise.');
    end
    kit.meter(im, 'Slots ', ctx.sets.count(st.editingSet), 20, '');
    kit.ctext(im, kit.COL.dim, ('Total MP %d'):format(ctx.sets.usedMP(st.editingSet, book)));

    -- game actions (widths measured -- 'Apply in gam' clipped in the field).
    -- The Apply button wears the diff state: green = the live set differs
    -- (click me), inert = already matching, plain = live state unknown.
    if kit.isFn(im, 'Separator') then im.Separator(); end
    local applyW = kit.measure(im, { 'Apply in game', 'Applying...' }, 100);
    local readW  = kit.measure(im, { 'Read current' }, 90);
    local clearW = kit.measure(im, { 'Clear' }, 50);
    local dirty = nil;                     -- nil = unknown (live unreadable)
    if liveIds ~= nil then
        -- slot-wise against the SORTED layout (what Apply would send): the
        -- right spells in the wrong order count as pending too
        dirty = false;
        local T = ctx.sets.sortedLayout(set.ids, ctx.book);
        for i = 1, 20 do
            if (live[i] or 0) ~= T[i] then dirty = true; break; end
        end
    end
    local pal = nil;
    if not ctx.blu.applying then
        if dirty == true then pal = kit.PAL.go;
        elseif dirty == false then pal = kit.PAL.off; end
    end
    if kit.litButton(im, ctx.blu.applying and 'Applying...' or 'Apply in game', false, applyW, 26, pal) then
        if dirty == false then
            st.applyNote = 'Already up to date - nothing to apply.';
        else
            M.applyEditing(ctx);
        end
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Read current', false, readW, 26) then
        local live = ctx.blu.currentSet();
        if #live == 20 then
            local unknown = 0;
            for i = 1, 20 do
                st.editingSet.ids[i] = live[i];
                if live[i] ~= 0 and book.spells[live[i]] == nil then unknown = unknown + 1; end
            end
            -- unknown ids are kept (honest mirror of the client) -- the grid
            -- draws them as '#id' cells and the totals simply skip them.
            st.applyNote = unknown == 0 and 'Read the live set.'
                or ('Read the live set; %d slot(s) hold ids the data does not know.'):format(unknown);
        else
            st.applyNote = 'Could not read the live set.';
        end
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Clear', false, clearW, 26) then
        ctx.sets.clear(st.editingSet);
        st.applyNote = nil;
    end
    if not ctx.blu.onBlu() then
        kit.ctext(im, kit.COL.warn, 'BLU is not your main or sub job.');
    end
    if st.applyNote then kit.ctext(im, kit.COL.dim, st.applyNote); end

    -- level-change behavior: restore the last-applied set automatically, or
    -- leave everything to the Apply button
    -- the naming law: name the rule for its condition, never 'Auto <thing>'
    kit.ctext(im, kit.COL.dim, 'Level change:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local lvW = kit.measure(im, { 'Restore', 'Manual' }, 64);
    local auto = ctx.cfg.autoRestore == true;
    if kit.litButton(im, 'Restore', auto, lvW, 20) and not auto then
        ctx.cfg.autoRestore = true;
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'After a level or job change, any spells stripped from the\n'
        .. 'LAST APPLIED set are re-set automatically - lowest level first,\n'
        .. 'into the lowest open slots. Adds only; never removes.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Manual', not auto, lvW, 20) and auto then
        ctx.cfg.autoRestore = false;
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'Nothing is applied automatically - you click Apply.');

    -- quick add
    if kit.isFn(im, 'Separator') then im.Separator(); end
    kit.ctext(im, kit.COL.head, 'Add a spell');
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(MID_W - 30); end
    if kit.isFn(im, 'InputText') then
        pcall(im.InputText, '##bdxaddsearch', st.addBuf, 48);
    end
    if st.addBuf[1] ~= '' then
        local ids = ctx.book.filter({ text = st.addBuf[1] });
        local max2 = ctx.budgetMax();
        for i = 1, math.min(#ids, 7) do
            local id = ids[i];
            local s = book.spells[id];
            local okAdd = ctx.sets.canAdd(st.editingSet, id, book, max2);
            local pushed = false;
            if kit.isFn(im, 'PushID') then pcall(im.PushID, 'bdxadd' .. id); pushed = true; end
            if kit.litButton(im, '+', false, 22, 20) and okAdd then
                ctx.sets.add(st.editingSet, id, book, max2);
            end
            if pushed and kit.isFn(im, 'PopID') then pcall(im.PopID); end
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            kit.ctext(im, okAdd and kit.COL.accent or kit.COL.dim,
                ('%s  (%s pts)'):format(s.name, s.setPoints or '?'));
        end
    end
end

-- ---------------------------------------------------------------------------
-- stats + traits for the editing set
-- ---------------------------------------------------------------------------
local function statsPanel(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    kit.header(im, 'Set stats');
    local stats = ctx.sets.stats(st.editingSet, book);
    if #stats == 0 then
        kit.ctext(im, kit.COL.dim, 'no stat bonuses yet');
    else
        for _, e in ipairs(stats) do
            kit.ctext(im, e.value >= 0 and kit.COL.ok or kit.COL.err,
                ('%s %+d'):format(ctx.sets.prettyStat(e.stat), e.value));
        end
    end

    if kit.isFn(im, 'Separator') then im.Separator(); end
    kit.header(im, 'Traits');
    local evals = ctx.sets.traitEval(st.editingSet, book);
    if #evals == 0 then
        kit.ctext(im, kit.COL.dim, 'no trait weight yet');
    end
    for _, ev in ipairs(evals) do
        if ev.tier then
            kit.ctext(im, kit.COL.ok, ('%s: %s'):format(ev.name, ev.tierText));
        else
            kit.ctext(im, kit.COL.dim, ('%s: below tier 1'):format(ev.name));
        end
        if ev.nextPoints then
            kit.ctext(im, kit.COL.dim, ('   %d more weight -> %s'):format(
                ev.nextPoints - ev.weight, ev.nextText or 'next tier'));
        end
    end
end

function M.render(ctx)
    local im = ctx.im;
    -- child widths follow their widest measured rows (the clipping law --
    -- 'Clea', 'Man' and 'Dele' all clipped in the field at the old fixed
    -- widths)
    local rowW = kit.measure(im, { 'New', 'Save', 'Delete' }, 50);
    LEFT_W = math.max(210, rowW * 3 + 32);
    local gameRow = kit.measure(im, { 'Apply in game', 'Applying...' }, 100)
        + kit.measure(im, { 'Read current' }, 90)
        + kit.measure(im, { 'Clear' }, 50);
    local levelRow = kit.measure(im, { 'Level change:' }, 60)
        + kit.measure(im, { 'Restore', 'Manual' }, 64) * 2;
    MID_W = math.max(330, gameRow + 34, levelRow + 34);
    if kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild') then
        if im.BeginChild('bdxsaved', { LEFT_W, 0 }, true) then savedList(ctx); end
        im.EndChild();
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if im.BeginChild('bdxslots', { MID_W, 0 }, true) then slotGrid(ctx); end
        im.EndChild();
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if im.BeginChild('bdxstats', { 0, 0 }, true) then statsPanel(ctx); end
        im.EndChild();
    else
        savedList(ctx); slotGrid(ctx); statsPanel(ctx);
    end
end

return M;
