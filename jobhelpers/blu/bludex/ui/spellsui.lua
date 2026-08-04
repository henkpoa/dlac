--[[
    bludex/ui/spellsui.lua -- the Codex tab: filter row, a set-budget readout,
    and an icon+name LIST (1-3 columns by window width). Clicking a row opens
    the Spell Info window (the 320 sprite plus everything the data layer
    knows, with Add-to-set at the top).

    All imgui calls run through kit's guards; every icon draw has a text
    fallback so a failed texture never blanks the tab. spellButton (the icon
    cell) stays exported for the Sets tab slot grid.
]]--

local ROOT = (...):sub(1, -#('ui\\spellsui') - 1);   -- relocatable require base
local kit     = require(ROOT .. 'ui\\kit');
local filetex = require(ROOT .. 'ui\\filetex');

local M = {};

-- guarded PushID/PopID: a grid of ImageButtons re-uses texture handles as IDs,
-- so every button gets an explicit ID pushed around it.
local function pushId(im, id)
    if kit.isFn(im, 'PushID') then pcall(im.PushID, tostring(id)); return true; end
    return false;
end
local function popId(im, pushed)
    if pushed and kit.isFn(im, 'PopID') then pcall(im.PopID); end
end

-- content-region width (now shared via the kit)
local function availWidth(im, fallback)
    return kit.availWidth(im, fallback);
end

-- One spell cell: ImageButton if the sprite loads, text button otherwise.
-- Returns true on click. `dimmed` greys the sprite (unlearned).
function M.spellButton(ctx, id, size, selected, dimmed)
    local im, book = ctx.im, ctx.book;
    local s = book.spells[id];
    local clicked = false;
    local pushed = pushId(im, 'bdxsp' .. id);
    if s == nil then
        -- an id the data does not know (a live-read slot can carry one):
        -- an inert-looking but still clickable cell, never an error.
        -- +4: image cells are size + 2px frame padding per side; text cells
        -- must match or mixed rows drift out of alignment.
        clicked = kit.litButton(im, '#' .. tostring(id), selected, size + 4, size + 4);
        popId(im, pushed);
        return clicked;
    end
    local h = filetex.spell(book, s, size >= 96 and 'grid128' or 'grid64');
    if h ~= nil and kit.isFn(im, 'ImageButton') then
        -- ImageButton's frame draws in the style Button color (red in the
        -- default Ashita theme) -- make it transparent so only the sprite
        -- shows; hover/active glow soft blue.
        local styled = false;
        if kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
            im.PushStyleColor(21, { 0, 0, 0, 0 });                 -- Button
            im.PushStyleColor(22, { 0.20, 0.42, 0.74, 0.45 });     -- Hovered
            im.PushStyleColor(23, { 0.20, 0.42, 0.74, 0.70 });     -- Active
            im.PushStyleColor(5,  { 0, 0, 0, 0 });                 -- Border: no square outline
            styled = true;
        end
        local bg = selected and { 0.20, 0.42, 0.74, 0.85 } or { 0, 0, 0, 0 };
        local tint = dimmed and { 0.45, 0.45, 0.50, 0.85 } or { 1, 1, 1, 1 };
        local ok, r = pcall(im.ImageButton, h, { size, size }, { 0, 0 }, { 1, 1 }, 2, bg, tint);
        if not ok then
            ok, r = pcall(im.ImageButton, h, { size, size });
        end
        if styled then im.PopStyleColor(4); end
        clicked = ok and r or false;
    else
        -- +4 to match the image cells' frame padding (see above)
        clicked = kit.litButton(im, s.name:sub(1, 10), selected, size + 4, size + 4);
    end
    popId(im, pushed);
    return clicked;
end

local function learnedText(ctx, id)
    if ctx.blu.onBlu() or ctx.book.learned(id) then
        if ctx.book.learned(id) then return 'learned', kit.COL.ok; end
        return 'not learned', kit.COL.err;
    end
    return nil, nil;
end

function M.tooltip(ctx, id)
    local im, book = ctx.im, ctx.book;
    if not (kit.isFn(im, 'IsItemHovered') and im.IsItemHovered()) then return; end
    local s = book.spells[id];
    if s == nil then return; end

    -- the info rows, each { text, color } -- shared by both tooltip flavors
    local rows = {};
    local function add(txt, col) rows[#rows + 1] = { txt, col }; end
    add(s.name, kit.COL.head);
    add(('%s - Lv.%s - %s'):format(s.category, s.level or '?', s.spellType or '?'), kit.COL.dim);
    if s.setPoints then add(('Set: %d pts'):format(s.setPoints), kit.COL.accent); end
    if s.mods and #s.mods > 0 then
        local parts = {};
        for _, m in ipairs(s.mods) do
            parts[#parts + 1] = ('%s%+d'):format(ctx.sets.prettyStat(m.stat), m.value);
        end
        add('Stats: ' .. table.concat(parts, '  '), kit.COL.ok);
    end
    if s.trait then
        local cat = s.trait.category;
        add(('Trait: %s  (weight %d)'):format(book.traitName(cat), s.trait.weight), kit.COL.accent);
        -- the editing set's progress on that ladder: weight / next threshold
        local weight = 0;
        for _, ev in ipairs(ctx.sets.traitEval(ctx.state.editingSet, book)) do
            if ev.cat == cat then weight = ev.weight; break; end
        end
        local info = book.traits.categories[cat];
        if info then
            local nextP, nextRank = nil, nil;
            for ti, tier in ipairs(info.tiers) do
                if weight < tier.points then nextP = tier.points; nextRank = ti; break; end
            end
            if nextP then
                add(('   %d / %d - for rank %d'):format(weight, nextP, nextRank), kit.COL.dim);
            else
                add(('   %d - max rank reached'):format(weight), kit.COL.ok);
            end
        end
    end
    if s.unbridled then add('Unbridled Learning', kit.COL.badge); end
    local lt, ltc = learnedText(ctx, id);
    if lt then add(lt, ltc); end
    if s.castable and not s.unbridled and s.setPoints then
        if ctx.sets.contains(ctx.state.editingSet, id) then
            add('right-click: remove from set', kit.COL.dim);
        elseif book.learned(id) then
            add('right-click: add to set', kit.COL.dim);
        end
    end

    -- rich flavor: the 64 sprite centered over the text, lines colored.
    -- BeginTooltip is not field-proven here, so everything inside is
    -- guarded and the plain SetTooltip text is the fallback.
    local h = filetex.spell(book, s, 'grid64');
    if h ~= nil and kit.isFn(im, 'BeginTooltip') and kit.isFn(im, 'EndTooltip')
        and kit.isFn(im, 'Image') then
        local ok = pcall(im.BeginTooltip);
        if ok then
            local wMax = 64;
            if kit.isFn(im, 'CalcTextSize') then
                for _, r in ipairs(rows) do
                    local okc, tw = pcall(im.CalcTextSize, kit.esc(r[1]));
                    if okc and type(tw) == 'number' and tw > wMax then wMax = tw; end
                end
            end
            local off = (wMax - 64) / 2;
            if off > 0 and kit.isFn(im, 'GetCursorPosX') and kit.isFn(im, 'SetCursorPosX') then
                local okx, cx = pcall(im.GetCursorPosX);
                if okx and type(cx) == 'number' then pcall(im.SetCursorPosX, cx + off); end
            end
            pcall(im.Image, h, { 64, 64 });
            for _, r in ipairs(rows) do
                kit.ctext(im, r[2], r[1]);
            end
            pcall(im.EndTooltip);
            return;
        end
    end

    local lines = {};
    for _, r in ipairs(rows) do lines[#lines + 1] = r[1]; end
    kit.tip(im, table.concat(lines, '\n'));
end

-- ---------------------------------------------------------------------------
-- the detail panel (also reused by the Sets tab through ctx)
-- ---------------------------------------------------------------------------
function M.detail(ctx, id)
    local im, book = ctx.im, ctx.book;
    local s = book.spells[id];
    if s == nil then
        kit.ctext(im, kit.COL.dim, 'Select a spell.');
        return;
    end

    kit.ctext(im, kit.COL.head, s.name);
    local lt, ltc = learnedText(ctx, id);
    if lt then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, ltc, '[' .. lt .. ']');
    end
    if s.unbridled then
        kit.ctext(im, kit.COL.badge, 'Unbridled Learning');
    end
    if not s.castable then
        kit.ctext(im, kit.COL.err, 'Learnable but NEVER castable at the 75 cap.');
    end

    -- add/remove FIRST -- the working button belongs at the top, not under
    -- a screen of lore. It flips to remove when the spell is in the set.
    if s.castable and not s.unbridled and s.setPoints then
        local btnW = kit.measure(im, { 'Add to current set', 'Remove from set' }, 150);
        if ctx.sets.contains(ctx.state.editingSet, id) then
            -- removal always works, even for spells that predate the
            -- learned gate (or came in from a live read)
            if kit.litButton(im, 'Remove from set', true, btnW, 26) then
                ctx.sets.removeId(ctx.state.editingSet, id);
                ctx.state.addNote = ('Removed %s.'):format(s.name);
                if ctx.save then ctx.save(); end
            end
        elseif not book.learned(id) then
            kit.ctext(im, kit.COL.err, 'Not learned - learn it before it can be set.');
        else
            if kit.litButton(im, 'Add to current set', false, btnW, 26) then
                local max = ctx.budgetMax();
                local ok, why = ctx.sets.add(ctx.state.editingSet, id, book, max);
                ctx.state.addNote = ok and ('Added %s.'):format(s.name) or ('Cannot add: %s.'):format(why);
                if ok and ctx.save then ctx.save(); end
            end
        end
        if ctx.state.addNote then
            kit.ctext(im, kit.COL.dim, ctx.state.addNote);
        end
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    local h = filetex.spell(book, s, 'detail');
    if h ~= nil and kit.isFn(im, 'Image') then
        -- center the sprite in the window
        local off = (availWidth(im, 352) - 320) / 2;
        if off > 0 and kit.isFn(im, 'GetCursorPosX') and kit.isFn(im, 'SetCursorPosX') then
            local okx, cx = pcall(im.GetCursorPosX);
            if okx and type(cx) == 'number' then pcall(im.SetCursorPosX, cx + off); end
        end
        pcall(im.Image, h, { 320, 320 });
    end

    kit.kv(im, 'Type', ('%s%s'):format(s.spellType or '?',
        s.damageType and (' (' .. s.damageType .. ')') or ''));
    kit.kv(im, 'Element', s.element or 'None', kit.ELEMENT[s.element] or kit.COL.accent);
    if s.ecosystem then kit.kv(im, 'Monster', s.ecosystem); end
    kit.kv(im, 'Level', ('BLU %s%s'):format(s.level or '?',
        (s.stockLevel and s.stockLevel ~= s.level) and ('  (retail ' .. s.stockLevel .. ')') or ''));
    if s.mpCost then
        local t = ('%d MP'):format(s.mpCost);
        if s.castTime then t = t .. ('   cast %.1fs'):format(s.castTime); end
        if s.recastTime then t = t .. ('   recast %.0fs'):format(s.recastTime); end
        kit.kv(im, 'Cost', t);
    end
    if s.aoe then kit.kv(im, 'Area', 'AoE'); end
    if s.setPoints then
        kit.kv(im, 'Set cost', ('%d point%s'):format(s.setPoints, s.setPoints == 1 and '' or 's'));
    end
    if s.trait then
        kit.kv(im, 'Trait', ('%s  (weight %d)'):format(
            book.traitName(s.trait.category), s.trait.weight));
    end
    if s.skillchain and #s.skillchain > 0 then
        kit.kvw(im, 'Skillchain', table.concat(s.skillchain, ', '));
    end
    if s.bursts and #s.bursts > 0 then
        kit.kvw(im, 'Bursts on', table.concat(s.bursts, ', '));
    end
    if s.numhits and s.numhits > 1 then kit.kv(im, 'Hits', tostring(s.numhits)); end
    if s.mods and #s.mods > 0 then
        local parts = {};
        for _, m in ipairs(s.mods) do
            parts[#parts + 1] = ('%s%+d'):format(ctx.sets.prettyStat(m.stat), m.value);
        end
        kit.kv(im, 'Stats', table.concat(parts, '  '), kit.COL.ok);
    end
    if s.note then
        if kit.isFn(im, 'TextWrapped') then
            im.TextWrapped(kit.esc(s.note));
        else
            kit.ctext(im, kit.COL.warn, s.note);
        end
    end

    -- learn-location hints (retail-era data via blucheck)
    local hints = book.hintList(id);
    if hints then
        if kit.isFn(im, 'Separator') then im.Separator(); end
        kit.ctext(im, kit.COL.head, 'Learn from');
        local shown = 0;
        for _, hz in ipairs(hints) do
            if shown >= 6 then
                kit.ctext(im, kit.COL.dim, ('...and %d more zones'):format(#hints - shown));
                break;
            end
            kit.ctext(im, kit.COL.accent, hz.zone);
            kit.wrapped(im, kit.COL.dim, '  ' .. table.concat(hz.mobs, ', '));
            shown = shown + 1;
        end
        kit.ctext(im, kit.COL.dim, '(retail-era data; CatsEyeXI can differ)');
    end

    -- provenance, quietly
    local prov = 'data: ' .. (s.src or '?');
    if s.verify then prov = prov .. '  unverified: ' .. table.concat(s.verify, ', '); end
    kit.ctext(im, kit.COL.dim, prov);
end

-- ---------------------------------------------------------------------------
-- list rows and the Spell Info window
-- ---------------------------------------------------------------------------

-- One list row: icon (unless showIcon is false) + the spell name as a
-- Selectable. Returns (leftClicked, rightClicked). In-set spells draw
-- green; unlearned dim (while on BLU); in-set wins.
function M.listRow(ctx, id, iconSz, nameW, selected, showIcon)
    local im, book = ctx.im, ctx.book;
    local s = book.spells[id];
    local pushed = pushId(im, 'bdxrow' .. id);
    local clicked, rclicked = false, false;
    if s == nil then
        clicked = kit.litButton(im, '#' .. tostring(id), selected, nameW, iconSz);
        popId(im, pushed);
        return clicked, false;
    end
    local dim = ctx.blu.onBlu() and not book.learned(id) or false;
    local inSet = ctx.sets.contains(ctx.state.editingSet, id) ~= nil;
    local selH = iconSz;
    if showIcon ~= false then
        local h = filetex.spell(book, s, 'grid64');
        if h ~= nil and kit.isFn(im, 'Image') then
            local tint = dim and { 0.45, 0.45, 0.50, 0.85 } or { 1, 1, 1, 1 };
            local okI = pcall(im.Image, h, { iconSz, iconSz }, { 0, 0 }, { 1, 1 }, tint);
            if not okI then pcall(im.Image, h, { iconSz, iconSz }); end
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
        end
        -- keep the name a text-height item, vertically centered on the icon
        selH = math.min(iconSz, 20);
        if iconSz > selH and kit.isFn(im, 'GetCursorPosY') and kit.isFn(im, 'SetCursorPosY') then
            local oky, cy = pcall(im.GetCursorPosY);
            if oky and type(cy) == 'number' then
                pcall(im.SetCursorPosY, cy + (iconSz - selH) / 2);
            end
        end
    end
    local textCol = inSet and kit.COL.ok or (dim and kit.COL.dim or nil);
    if kit.isFn(im, 'Selectable') then
        local pushedCol = false;
        if textCol and kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
            im.PushStyleColor(0, textCol);                     -- Text
            pushedCol = true;
        end
        local ok, r = pcall(im.Selectable, kit.esc(s.name), selected, 0, { nameW, selH });
        if not ok then ok, r = pcall(im.Selectable, kit.esc(s.name), selected); end
        if pushedCol then im.PopStyleColor(1); end
        clicked = ok and r or false;
    else
        clicked = kit.litButton(im, s.name, selected, nameW, selH);
    end
    if kit.isFn(im, 'IsItemClicked') then
        local okc, rc = pcall(im.IsItemClicked, 1);            -- right button
        rclicked = okc and rc or false;
    end
    popId(im, pushed);
    return clicked, rclicked;
end

-- The Spell Info window: opened by clicking a row, closable via the title
-- bar. Rendered inside the host's style pushes, so it inherits the theme.
function M.detailWindow(ctx)
    local im, st = ctx.im, ctx.state;
    if not st.detailOpen or not st.detailOpen[1] then return; end
    if st.selectedId == nil then st.detailOpen[1] = false; return; end
    if not (kit.isFn(im, 'Begin') and kit.isFn(im, 'End')) then return; end
    if kit.isFn(im, 'SetNextWindowSizeConstraints') then
        pcall(im.SetNextWindowSizeConstraints, { 380, 420 }, { 900, 1400 });
    end
    if st.detailFocus and kit.isFn(im, 'SetNextWindowFocus') then
        pcall(im.SetNextWindowFocus);
    end
    st.detailFocus = nil;
    local visible = false;
    local ok = pcall(function()
        visible = im.Begin('Spell Info##bdxspellinfo', st.detailOpen);
    end);
    if ok and visible then
        local dok, derr = pcall(M.detail, ctx, st.selectedId);
        if not dok then
            kit.ctext(im, kit.COL.err, 'detail error: ' .. tostring(derr));
        end
    end
    if ok then im.End(); end
end

-- ---------------------------------------------------------------------------
-- the tab
-- ---------------------------------------------------------------------------
function M.render(ctx)
    local im, book, st = ctx.im, ctx.book, ctx.state;
    local f = st.filters;
    f.sort = f.sort or {};
    st.detailOpen = st.detailOpen or { false };

    -- filter row -- combo widths measured over every label they can show
    -- (the kit law: a hardcoded width clips a trailing character; "All eleme").
    local function comboW(choices, allLabel)
        local labels = { allLabel };
        for _, c in ipairs(choices) do labels[#labels + 1] = c; end
        return kit.measure(im, labels, 96) + 24;    -- +24 for the arrow box
    end
    local traitNames = {};
    for _, t in ipairs(book.traitChoices) do traitNames[#traitNames + 1] = t.name; end
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(160); end
    if kit.isFn(im, 'InputText') then
        pcall(im.InputText, '##bdxsearch', f.text, 64);
        kit.tip(im, 'Filter by name');
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxcat', f.category, book.categories, 'All types',
        comboW(book.categories, 'All types'));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxele', f.element, book.elements, 'All elements',
        comboW(book.elements, 'All elements'));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxsty', f.spellType, book.types, 'All kinds',
        comboW(book.types, 'All kinds'));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxtrait', f.trait, traitNames, 'All traits',
        comboW(traitNames, 'All traits'));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxlearn', f.learned, { 'Learned', 'Missing' }, 'All spells',
        comboW({ 'Learned', 'Missing' }, 'All spells'));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Reset', false, 60, 22) then
        f.text[1] = ''; f.category.value = nil; f.element.value = nil;
        f.spellType.value = nil; f.trait.value = nil; f.learned.value = nil;
        f.sort.value = nil;
    end

    -- resolve filter spec
    local traitCat = nil;
    if f.trait.value then
        for _, t in ipairs(book.traitChoices) do
            if t.name == f.trait.value then traitCat = t.cat; break; end
        end
    end
    local learned = nil;
    if f.learned.value == 'Learned' then learned = true;
    elseif f.learned.value == 'Missing' then learned = false; end
    local ids = book.filter({
        text = f.text[1], category = f.category.value, element = f.element.value,
        spellType = f.spellType.value, traitCat = traitCat, learned = learned,
    });

    -- sort (in place -- book.filter returns a fresh array each call)
    local sortBy = f.sort.value;
    if sortBy ~= nil then
        local sp = book.spells;
        if sortBy == 'Name' then
            table.sort(ids, function(a, b) return sp[a].name < sp[b].name; end);
        elseif sortBy == 'Level' then
            table.sort(ids, function(a, b)
                local la, lb = sp[a].level or 999, sp[b].level or 999;
                if la ~= lb then return la < lb; end
                return sp[a].name < sp[b].name;
            end);
        elseif sortBy == 'Type' then
            table.sort(ids, function(a, b)
                local ta, tb = sp[a].spellType or '~', sp[b].spellType or '~';
                if ta ~= tb then return ta < tb; end
                return sp[a].name < sp[b].name;
            end);
        end
    end

    -- results row: count, sort, view density, and the last add/remove note
    -- (the right-click path has no window open to show it in)
    kit.ctext(im, kit.COL.dim, ('%d spells'):format(#ids));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.ctext(im, kit.COL.dim, '   Sort:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxsort', f.sort, { 'Name', 'Level', 'Type' }, 'default',
        comboW({ 'Name', 'Level', 'Type' }, 'default'));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.ctext(im, kit.COL.dim, '  View:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local density = ctx.cfg.codexDensity or 'normal';
    local dChoices = { 'Big (64px icons)', 'Compact (no icons)' };
    local dToKey = { ['Big (64px icons)'] = 'big', ['Compact (no icons)'] = 'compact' };
    local dFromKey = { big = dChoices[1], compact = dChoices[2] };
    local dstate = { value = dFromKey[density] };
    if kit.combo(im, '##bdxview', dstate, dChoices, 'Normal', comboW(dChoices, 'Normal')) then
        density = dstate.value and dToKey[dstate.value] or 'normal';
        ctx.cfg.codexDensity = density;
        if ctx.save then ctx.save(); end
    end
    if st.addNote then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   ' .. st.addNote);
    end

    -- the list -- density picks icon size, column target width and cap:
    -- big = 64px icons in 1-2 columns, normal = 24px in up to 3,
    -- compact = text only in up to 5
    local availW = availWidth(im, 800);
    local iconSz, targetW, maxCols, showIcon = 24, 250, 3, true;
    if density == 'big' then
        iconSz, targetW, maxCols = 64, 340, 2;
    elseif density == 'compact' then
        iconSz, targetW, maxCols, showIcon = 18, 180, 5, false;
    end
    local cols = math.max(1, math.min(maxCols, math.floor(availW / targetW)));
    local colW = math.floor((availW - 16) / cols);   -- -16: scrollbar margin
    local nameW = math.max(colW - (showIcon and iconSz or 0) - 28, 80);

    -- Embedded (dlac Job helper Panel) may not open windows from the Panel.
    -- When the hosting addon runs our detail through its sanctioned float
    -- surface (host.renderDetailFloat via dlac's `window` hook), Spell Info
    -- floats as usual; on a host without that surface the detail renders as
    -- an in-panel child on the right instead. Standalone keeps its float.
    local DETAIL_W = 372;
    local paneDetail = ctx.embedded == true and ctx.floatWindow ~= true
        and st.detailOpen[1] and st.selectedId ~= nil;
    local listW = 0;
    if paneDetail then
        listW = math.max(availW - DETAIL_W - 12, 240);
        cols = math.max(1, math.min(cols, math.floor(listW / targetW)));
        colW = math.floor((listW - 16) / cols);
        nameW = math.max(colW - (showIcon and iconSz or 0) - 28, 80);
    end

    local function rows()
        for i, id in ipairs(ids) do
            local col = (i - 1) % cols;
            if col ~= 0 and kit.isFn(im, 'SameLine') then im.SameLine(col * colW + 8); end
            local lclick, rclick = M.listRow(ctx, id, iconSz, nameW, st.selectedId == id, showIcon);
            if lclick then
                st.selectedId = id;
                st.detailOpen[1] = true;
                st.detailFocus = true;
            end
            if rclick then
                -- toggle set membership without opening the window
                local s = book.spells[id];
                if s ~= nil then
                    if ctx.sets.contains(st.editingSet, id) then
                        ctx.sets.removeId(st.editingSet, id);
                        st.addNote = ('Removed %s.'):format(s.name);
                        if ctx.save then ctx.save(); end
                    else
                        local ok, why = ctx.sets.add(st.editingSet, id, book, ctx.budgetMax());
                        st.addNote = ok and ('Added %s.'):format(s.name)
                            or ('Cannot add %s: %s.'):format(s.name, why);
                        if ok and ctx.save then ctx.save(); end
                    end
                end
            end
            M.tooltip(ctx, id);
        end
    end

    if kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild') then
        if im.BeginChild('bdxlist', { paneDetail and listW or 0, 0 }, false) then rows(); end
        im.EndChild();
        if paneDetail then
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            if im.BeginChild('bdxdetail', { DETAIL_W, 0 }, true) then
                if kit.litButton(im, 'Close', false, 60, 22) then
                    st.detailOpen[1] = false;
                end
                local dok, derr = pcall(M.detail, ctx, st.selectedId);
                if not dok then
                    kit.ctext(im, kit.COL.err, 'detail error: ' .. tostring(derr));
                end
            end
            im.EndChild();
        end
    else
        rows();
    end

    if ctx.embedded ~= true then
        M.detailWindow(ctx);
    end
end

return M;
