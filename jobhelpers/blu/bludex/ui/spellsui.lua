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
local scrules = require(ROOT .. 'lib\\skillchain');

local M = {};

-- The codex's "which spells" choices: two axes on one list, because they
-- answer the same question. The last two are membership of the build being
-- edited -- the same spells the rows draw green.
M.SHOW_CHOICES = { 'Learned', 'Missing', 'In the set', 'Not in the set' };

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

-- The job side of a trait ladder, when the host wired it in (ctx.jobTraits).
-- nil when it did not -- an unwired host claims nothing rather than claiming
-- "no job grants this".
function M.ladderBlocks(ctx, cat)
    if ctx.tsrc == nil or ctx.jobTraits == nil or cat == nil then return nil; end
    local ok, r = pcall(ctx.tsrc.ladderBlocks, cat, ctx.book, ctx.jobTraits);
    return ok and r or nil;
end

local function learnedText(ctx, id)
    if ctx.blu.onBlu() or ctx.book.learned(id) then
        if ctx.book.learned(id) then return 'learned', kit.COL.ok; end
        -- NOT EVERY SPELL YOU LACK IS ONE YOU MISSED (Henrik 2026-08-10,
        -- sixth round). A granted spell -- Thunderbolt, off the food Lengua
        -- Regia -- is not learned from a mob at all, so the red "not
        -- learned" was accusing you of a gap you cannot close. It reads as
        -- what it is, and the note below names what does grant it.
        local s = ctx.book.spells[id];
        if s ~= nil and s.grantedBy ~= nil then
            return 'not learnable - granted', kit.COL.badge;
        end
        return 'not learned', kit.COL.err;
    end
    return nil, nil;
end

-- `hovered` (optional): the row-wide state from listRow -- the overlay row
-- draws art LAST, so IsItemHovered on the last item only covers the name.
-- true shows, false skips, nil falls back to the last-item check.
-- `extra` (optional): array of { text, color } rows appended at the end --
-- the Assign pane explains a blocked spell through it.
function M.tooltip(ctx, id, hovered, extra)
    local im, book = ctx.im, ctx.book;
    if hovered == false then return; end
    if hovered ~= true
        and not (kit.isFn(im, 'IsItemHovered') and im.IsItemHovered()) then return; end
    -- the same dwell every other tooltip waits out (Settings: hover delay).
    -- Keyed by spell so moving along a list restarts it row by row.
    if not kit.hoverReady('bdxspell' .. tostring(id)) then return; end
    local s = book.spells[id];
    if s == nil then return; end

    -- the info rows, each { text, color } -- shared by both tooltip flavors
    local rows = {};
    local function add(txt, col) rows[#rows + 1] = { txt, col }; end
    add(s.name, kit.COL.head);
    add(('%s - Lv.%s - %s'):format(s.category, s.level or '?', s.spellType or '?'), kit.COL.dim);
    -- what it costs to CAST, next to what it costs to SET (field ask
    -- 2026-08-07) -- the two numbers a spell is picked on
    if s.mpCost then add(('%d MP'):format(s.mpCost), kit.COL.accent); end
    -- the client DAT's own description (it carries its own line breaks)
    local desc = book.description(id);
    if desc then add(desc, { 0.90, 0.90, 0.95, 1.00 }); end
    if s.setPoints then add(('Set: %d blue pts'):format(s.setPoints), kit.COL.accent); end
    if s.mods and #s.mods > 0 then
        local parts = {};
        for _, m in ipairs(s.mods) do
            parts[#parts + 1] = ('%s%+d'):format(ctx.sets.prettyStat(m.stat), m.value);
        end
        add('Stats: ' .. table.concat(parts, '  '), kit.COL.ok);
    end
    if s.trait then
        local cat = s.trait.category;
        local tw = s.trait.weight or 0;
        add(('Trait: %s  (+%d Point%s)'):format(
            book.traitName(cat), tw, tw == 1 and '' or 's'), kit.COL.accent);
        -- the editing set's progress on that ladder: points / next threshold
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
                -- the same price idiom the Traits tab speaks (Henrik
                -- 2026-08-10: one grammar for tier costs everywhere)
                add(('   Tier %d: %d/%d Points'):format(nextRank, weight, nextP), kit.COL.dim);
            else
                add(('   %d Points - max tier reached'):format(weight), kit.COL.ok);
            end
        end
        -- the job's stake in the ladder, one short line (Henrik 2026-08-10,
        -- third round: no mechanics lecture in a tooltip)
        local bl = M.ladderBlocks(ctx, cat);
        if bl ~= nil and #bl.blocks > 0 then
            local j = bl.blocks[1].job;
            local who = ('%s (%s job)'):format(j.code or '?',
                j.slot == 'sub' and 'sub' or 'main');
            if bl.all then
                add(('   %s already grants every tier of this ladder'):format(who),
                    kit.COL.warn);
            else
                add(('   %s grants tier %d'):format(who, j.rank), kit.COL.dim);
            end
        end
    end
    if s.unbridled then add('Unbridled Learning', kit.COL.badge); end
    local lt, ltc = learnedText(ctx, id);
    if lt then add(lt, ltc); end
    -- assignment status, timeline-aware: a spell in the set shows its level
    -- range(s) even while inactive at the current level (Henrik's ask) --
    -- mutation lives in the Sets tab now, so no click hints here
    if ctx.sets.contains(ctx.state.editingSet, id) then
        local ranges = ctx.sets.activeRanges
            and ctx.sets.activeRanges(ctx.state.editingSet, id) or {};
        if #ranges > 0 then
            for _, r in ipairs(ranges) do
                add(('in set: Lv.%d-%d'):format(r.lo, r.hi), kit.COL.ok);
            end
        else
            add('in the editing set', kit.COL.ok);
        end
    end
    for _, e in ipairs(extra or {}) do add(e[1], e[2]); end

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
    if s.grantedBy then
        kit.wrapped(im, kit.COL.badge,
            ('Not learned from a mob - granted by %s.'):format(s.grantedBy));
    end
    if not s.castable then
        kit.ctext(im, kit.COL.err, 'Learnable but NEVER castable at the 75 cap.');
    end

    -- assignment status FIRST, where the button used to be. The compendium
    -- is a pure reference now (Henrik 2026-08-08) -- every set mutation
    -- lives in the Sets tab, so this reports and points, never acts.
    if s.castable and not s.unbridled and s.setPoints then
        local ranges = ctx.sets.activeRanges
            and ctx.sets.activeRanges(ctx.state.editingSet, id) or {};
        if #ranges > 0 then
            for _, r in ipairs(ranges) do
                kit.ctext(im, kit.COL.ok, ('In the editing set: Lv.%d-%d'):format(r.lo, r.hi));
            end
        elseif ctx.sets.contains(ctx.state.editingSet, id) then
            kit.ctext(im, kit.COL.ok, 'In the editing set.');
        elseif not book.learned(id) then
            kit.ctext(im, kit.COL.err, 'Not learned - learn it before it can be set.');
        else
            kit.ctext(im, kit.COL.dim, 'Not in the editing set - assign it on the Sets tab (a slot\'s + button).');
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

    -- the client DAT's own description, ahead of the stat rows
    local desc = book.description(id);
    if desc then
        kit.wrapped(im, { 0.90, 0.90, 0.95, 1.00 }, desc);
        if kit.isFn(im, 'Separator') then im.Separator(); end
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
        kit.kv(im, 'Set cost', ('%d blue point%s'):format(s.setPoints, s.setPoints == 1 and '' or 's'));
    end
    if s.trait then
        kit.kv(im, 'Trait', ('%s  (+%d Point%s)'):format(
            book.traitName(s.trait.category), s.trait.weight or 0,
            (s.trait.weight or 0) == 1 and '' or 's'));
        -- and the job's stake in that ladder, one short line
        local bl = M.ladderBlocks(ctx, s.trait.category);
        if bl ~= nil and #bl.blocks > 0 then
            local j = bl.blocks[1].job;
            local who = ('%s (%s job)'):format(j.code or '?',
                j.slot == 'sub' and 'sub' or 'main');
            kit.wrapped(im, bl.all and kit.COL.warn or kit.COL.dim,
                bl.all
                    and ('%s already grants every tier of %s.'):format(
                        who, book.traitName(s.trait.category))
                    or ('%s grants tier %d of %s.'):format(
                        who, j.rank, book.traitName(s.trait.category)));
        end
    end
    if s.skillchain and #s.skillchain > 0 then
        kit.kvw(im, 'Skillchain', table.concat(s.skillchain, ', '));
        -- weaponskill partners live in their OWN window (a lot of rows) --
        -- here just the door. Hidden in the embedded-Panel fallback: a
        -- Panel host may not open windows.
        if not (ctx.embedded == true and ctx.floatWindow ~= true) then
            local st = ctx.state;
            st.scOpen = st.scOpen or { false };
            local w = kit.measure(im, { 'Skillchain partners' }, 150);
            if kit.litButton(im, 'Skillchain partners', st.scOpen[1], w, 24) then
                st.scOpen[1] = not st.scOpen[1];
                st.scFocus = true;
            end
            kit.tip(im, 'Which weaponskills chain with this spell, per weapon --\n'
                .. 'open with the weaponskill and close with the spell, or the\n'
                .. 'other way around. WSNM, Relic, Mythic, Empyrean and\n'
                .. 'Merit/Aeonic weaponskills included.');
        end
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

    -- learn-location hints (retail-era data via blucheck) live in their OWN
    -- window (field ask 2026-08-04: the inline zone list made Spell Info a
    -- wall) -- here just the door. The embedded-Panel fallback keeps the
    -- inline list: a Panel host may not open windows.
    local hints = book.hintList(id);
    if hints then
        if kit.isFn(im, 'Separator') then im.Separator(); end
        if ctx.embedded == true and ctx.floatWindow ~= true then
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
        else
            local st = ctx.state;
            st.learnOpen = st.learnOpen or { false };
            local lbl = ('Learn from - %d zone%s'):format(#hints, #hints == 1 and '' or 's');
            local w = kit.measure(im, { lbl }, 150);
            if kit.litButton(im, lbl, st.learnOpen[1], w, 24) then
                st.learnOpen[1] = not st.learnOpen[1];
                st.learnFocus = true;
            end
            kit.tip(im, 'Where to learn this spell, in its own window.\n'
                .. '(retail-era data; CatsEyeXI can differ)');
        end
    end

    -- provenance, quietly
    local prov = 'data: ' .. (s.src or '?');
    if s.verify then prov = prov .. '  unverified: ' .. table.concat(s.verify, ', '); end
    kit.ctext(im, kit.COL.dim, prov);
end

-- ---------------------------------------------------------------------------
-- list rows and the Spell Info window
-- ---------------------------------------------------------------------------

-- One list row: ONE Selectable spans the whole row -- icon AND name (field
-- ask 2026-08-04: the icon was inert art beside a text-only hit target).
-- The highlight, both clicks and hover cover everything; the art and the
-- colored name draw OVER the Selectable afterwards.
-- Returns (leftClicked, rightClicked, hovered). `hovered` is the row-wide
-- state for tooltip(); nil on the fallback path (tooltip self-checks then).
-- In-set spells draw green; unlearned draw opts.dimColor (default dim)
-- while on BLU; in-set wins. opts.label overrides the row text (the traits
-- tab composes the trait points and level into it).
-- `opts.dimArt` greys the ICON without touching the text rule -- what a row
-- the level cannot give you yet needs (Henrik 2026-08-10, sixth round:
-- grey the row instead of tagging every one of them), where the caller
-- already owns the text color through opts.textCol.
function M.listRow(ctx, id, iconSz, nameW, selected, showIcon, opts)
    local im, book = ctx.im, ctx.book;
    local s = book.spells[id];
    local pushed = pushId(im, 'bdxrow' .. id);
    local clicked, rclicked, hovered = false, false, nil;
    if s == nil then
        clicked = kit.litButton(im, '#' .. tostring(id), selected, nameW, iconSz);
        popId(im, pushed);
        return clicked, false, nil;
    end
    local label = (opts and opts.label) or s.name;
    local dimColor = (opts and opts.dimColor) or kit.COL.dim;
    -- unlearned draws loud -- but a GRANTED spell is not unlearned, it is
    -- simply not something you learn (Henrik 2026-08-10, sixth round), so
    -- it never wears the red of a gap you could have closed
    local dim = ctx.blu.onBlu() and not book.learned(id)
        and s.grantedBy == nil or false;
    local artDim = dim or ((opts and opts.dimArt) == true);
    local inSet = ctx.sets.contains(ctx.state.editingSet, id) ~= nil;
    -- opts.textCol overrides the whole coloring rule -- the Sets tab's own
    -- rows are ALL in the set, so the green tint says nothing there
    local textCol = (opts and opts.textCol)
        or (inSet and kit.COL.ok or (dim and dimColor or nil));
    local drawIcon = showIcon ~= false;
    local rowH = drawIcon and iconSz or math.min(iconSz, 20);
    local pad = 8;                                     -- icon-to-name gap
    local rowW = (drawIcon and (iconSz + pad) or 0) + nameW;

    local x0, y0 = nil, nil;
    if kit.isFn(im, 'GetCursorPosX') and kit.isFn(im, 'GetCursorPosY') then
        local okx, cx = pcall(im.GetCursorPosX);
        local oky, cy = pcall(im.GetCursorPosY);
        if okx and type(cx) == 'number' then x0 = cx; end
        if oky and type(cy) == 'number' then y0 = cy; end
    end
    local overlayOk = false;
    if x0 ~= nil and y0 ~= nil and kit.isFn(im, 'Selectable')
        and kit.isFn(im, 'SetCursorPosX') and kit.isFn(im, 'SetCursorPosY') then
        local okS, r = pcall(im.Selectable, '##bdxhit', selected, 0, { rowW, rowH });
        if okS then
            overlayOk = true;
            clicked = r or false;
            if kit.isFn(im, 'IsItemHovered') then
                local okh, hv = pcall(im.IsItemHovered);
                hovered = okh and (hv or false) or false;
            end
            if kit.isFn(im, 'IsItemClicked') then
                local okc, rc = pcall(im.IsItemClicked, 1);    -- right button
                rclicked = okc and rc or false;
            end
            -- where the NEXT row starts -- the Selectable owns the row's
            -- real item spacing; restored after the art overlays
            local yAfter = nil;
            local oky2, cy2 = pcall(im.GetCursorPosY);
            if oky2 and type(cy2) == 'number' then yAfter = cy2; end
            if drawIcon then
                local h = filetex.spell(book, s, 'grid64');
                if h ~= nil and kit.isFn(im, 'Image') then
                    pcall(im.SetCursorPosX, x0);
                    pcall(im.SetCursorPosY, y0);
                    local tint = artDim and { 0.45, 0.45, 0.50, 0.85 } or { 1, 1, 1, 1 };
                    local okI = pcall(im.Image, h, { iconSz, iconSz }, { 0, 0 }, { 1, 1 }, tint);
                    if not okI then pcall(im.Image, h, { iconSz, iconSz }); end
                end
            end
            local textH = 17;
            if kit.isFn(im, 'GetTextLineHeight') then
                local okt, th = pcall(im.GetTextLineHeight);
                if okt and type(th) == 'number' and th > 0 then textH = th; end
            end
            pcall(im.SetCursorPosX, x0 + (drawIcon and (iconSz + pad) or 0));
            pcall(im.SetCursorPosY, y0 + math.max(0, (rowH - textH) / 2));
            if textCol then kit.ctext(im, textCol, label);
            else kit.text(im, label); end
            if yAfter ~= nil then pcall(im.SetCursorPosY, yAfter); end
        end
    end
    if not overlayOk then
        -- fallback (binding without the cursor calls): icon + text target
        local selH = iconSz;
        if drawIcon then
            local h = filetex.spell(book, s, 'grid64');
            if h ~= nil and kit.isFn(im, 'Image') then
                local tint = artDim and { 0.45, 0.45, 0.50, 0.85 } or { 1, 1, 1, 1 };
                local okI = pcall(im.Image, h, { iconSz, iconSz }, { 0, 0 }, { 1, 1 }, tint);
                if not okI then pcall(im.Image, h, { iconSz, iconSz }); end
                if kit.isFn(im, 'SameLine') then im.SameLine(); end
            end
            selH = math.min(iconSz, 20);
        end
        if kit.isFn(im, 'Selectable') then
            local pushedCol = false;
            if textCol and kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
                im.PushStyleColor(0, textCol);                 -- Text
                pushedCol = true;
            end
            local ok, r = pcall(im.Selectable, kit.esc(label), selected, 0, { nameW, selH });
            if not ok then ok, r = pcall(im.Selectable, kit.esc(label), selected); end
            if pushedCol then im.PopStyleColor(1); end
            clicked = ok and r or false;
        else
            clicked = kit.litButton(im, label, selected, nameW, selH);
        end
        if kit.isFn(im, 'IsItemClicked') then
            local okc, rc = pcall(im.IsItemClicked, 1);        -- right button
            rclicked = okc and rc or false;
        end
    end
    popId(im, pushed);
    return clicked, rclicked, hovered;
end

-- The View density combo, shared by the codex and traits tabs: reads and
-- persists ctx.cfg[cfgKey] ('big' | 'medium' | 'normal' | 'compact');
-- returns the key. 'Normal' (24px) is the combo's all-label default.
function M.densityCombo(ctx, cfgKey)
    local im = ctx.im;
    local density = ctx.cfg[cfgKey] or 'normal';
    local dChoices = { 'Big (64px icons)', 'Medium (32px icons)', 'Compact (no icons)' };
    local dToKey = {
        ['Big (64px icons)']    = 'big',
        ['Medium (32px icons)'] = 'medium',
        ['Compact (no icons)']  = 'compact',
    };
    local dFromKey = { big = dChoices[1], medium = dChoices[2], compact = dChoices[3] };
    local w = kit.measure(im, { dChoices[1], dChoices[2], dChoices[3], 'Normal' }, 96) + 24;
    local dstate = { value = dFromKey[density] };
    if kit.combo(im, '##bdxview_' .. cfgKey, dstate, dChoices, 'Normal', w) then
        density = dstate.value and dToKey[dstate.value] or 'normal';
        ctx.cfg[cfgKey] = density;
        if ctx.save then ctx.save(); end
    end
    return density;
end

-- density key -> (iconSz, showIcon) for list rows
function M.densityParams(density)
    if density == 'big' then return 64, true; end
    if density == 'medium' then return 32, true; end
    if density == 'compact' then return 18, false; end
    return 24, true;
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

-- The Learn-from window: opened by the Spell Info button, follows the
-- selected spell, closable via the title bar. Lists EVERY zone -- the
-- inline section it replaced truncated at six.
function M.learnWindow(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    if not st.learnOpen or not st.learnOpen[1] then return; end
    if st.selectedId == nil then st.learnOpen[1] = false; return; end
    local s = book.spells[st.selectedId];
    local hints = s ~= nil and book.hintList(st.selectedId) or nil;
    if hints == nil then st.learnOpen[1] = false; return; end
    if not (kit.isFn(im, 'Begin') and kit.isFn(im, 'End')) then return; end
    if kit.isFn(im, 'SetNextWindowSizeConstraints') then
        pcall(im.SetNextWindowSizeConstraints, { 320, 240 }, { 700, 900 });
    end
    if st.learnFocus and kit.isFn(im, 'SetNextWindowFocus') then
        pcall(im.SetNextWindowFocus);
    end
    st.learnFocus = nil;
    local visible = false;
    local ok = pcall(function()
        visible = im.Begin('Learn from##bdxlearn', st.learnOpen);
    end);
    if ok and visible then
        kit.ctext(im, kit.COL.head, s.name);
        kit.ctext(im, kit.COL.dim, '(retail-era data; CatsEyeXI can differ)');
        if kit.isFn(im, 'Separator') then im.Separator(); end
        for _, hz in ipairs(hints) do
            kit.ctext(im, kit.COL.accent, hz.zone);
            kit.wrapped(im, kit.COL.dim, '  ' .. table.concat(hz.mobs, ', '));
        end
    end
    if ok then im.End(); end
end

-- chain level -> row color: the big chains wear the loud colors
local SC_LEVEL_COL = {
    [1] = kit.COL.accent, [2] = kit.COL.ok, [3] = kit.COL.warn, [4] = kit.COL.badge,
};

-- one partner list: 'WS name   -> Chain  [tag]' rows, chain colored by level
local function scPartnerRows(im, list)
    if #list == 0 then
        kit.ctext(im, kit.COL.dim, '  nothing chains');
        return;
    end
    local nameW = 120;
    if kit.isFn(im, 'CalcTextSize') then
        for _, e in ipairs(list) do
            local ok, tw = pcall(im.CalcTextSize, kit.esc(e.ws.name));
            if ok and type(tw) == 'number' and tw > nameW then nameW = tw; end
        end
    end
    for _, e in ipairs(list) do
        kit.text(im, e.ws.name);
        if kit.isFn(im, 'SameLine') then im.SameLine(nameW + 24); end
        kit.ctext(im, SC_LEVEL_COL[e.level] or kit.COL.accent, '-> ' .. e.chain);
        kit.tip(im, ('Magic burst: %s'):format(scrules.ELEMENTS[e.chain] or '?'));
        if e.ws.tag then
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            kit.ctext(im, kit.COL.dim, '  [' .. (scrules.TAGS[e.ws.tag] or e.ws.tag) .. ']');
        end
    end
end

-- The Skillchain-partners window: opened from Spell Info, follows the
-- selected spell. A weapon chooser (Sword first -- BLU's weapon), then the
-- two directions the user asked for in this order: open with the
-- weaponskill / close with the spell, and open with the spell / close with
-- a weaponskill.
function M.scWindow(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    if not st.scOpen or not st.scOpen[1] then return; end
    if st.selectedId == nil then st.scOpen[1] = false; return; end
    local s = book.spells[st.selectedId];
    if s == nil or s.skillchain == nil or #s.skillchain == 0 then
        st.scOpen[1] = false;
        return;
    end
    if not (kit.isFn(im, 'Begin') and kit.isFn(im, 'End')) then return; end
    if kit.isFn(im, 'SetNextWindowSizeConstraints') then
        pcall(im.SetNextWindowSizeConstraints, { 380, 320 }, { 800, 1200 });
    end
    if st.scFocus and kit.isFn(im, 'SetNextWindowFocus') then
        pcall(im.SetNextWindowFocus);
    end
    st.scFocus = nil;
    local visible = false;
    local ok = pcall(function()
        visible = im.Begin('Skillchain partners##bdxsc', st.scOpen);
    end);
    if ok and visible then
        kit.ctext(im, kit.COL.head, s.name);
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.accent, '  ' .. table.concat(s.skillchain, ', '));
        st.scWeapon = st.scWeapon or { value = 'Sword' };
        kit.ctext(im, kit.COL.dim, 'Weapon');
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        local w = kit.measure(im, scrules.weapons, 100) + 24;
        kit.combo(im, '##bdxscweapon', st.scWeapon, scrules.weapons, nil, w);
        if kit.isFn(im, 'Separator') then im.Separator(); end

        local weapon = st.scWeapon.value or 'Sword';
        local wsOpens, spellOpens = scrules.partners(s.skillchain, weapon);
        kit.ctext(im, kit.COL.head, ('Open with a %s weaponskill, close with %s'):format(weapon, s.name));
        scPartnerRows(im, wsOpens);
        if kit.isFn(im, 'Separator') then im.Separator(); end
        kit.ctext(im, kit.COL.head, ('Open with %s, close with a %s weaponskill'):format(s.name, weapon));
        scPartnerRows(im, spellOpens);
        if kit.isFn(im, 'Separator') then im.Separator(); end
        kit.ctext(im, kit.COL.dim, 'Hover a chain for its magic-burst elements.');
    end
    if ok then im.End(); end
end

-- ---------------------------------------------------------------------------
-- the tab
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- THE ASSIGN MENU (Henrik 2026-08-10, fourth round): right-clicking a spell
-- while a SLOTLIST is being edited opens a list of all twenty slots -- each
-- named with its bracket and the spell its Lv.75 plan holds -- and hovering
-- one cascades into that slot's whole timeline, "Add <spell> here..." on
-- top (which hands the add to the slot editor window, level box and all).
-- Opened by the codex AND traits rows; rendered once at each list's scope.
-- Degrades: without cascade support the slots list flat and click straight
-- through to the editor; without popups at all the right-click keeps its
-- old refusal note.
-- ---------------------------------------------------------------------------
function M.canAssignMenu(im)
    return kit.isFn(im, 'OpenPopup') and kit.isFn(im, 'BeginPopup')
        and kit.isFn(im, 'EndPopup');
end

function M.renderAssignMenu(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local id = st.assignMenuId;
    if id == nil or not M.canAssignMenu(im) then return; end
    local set = st.editingSet;
    if ctx.sets.kindOf(set) ~= 'timeline' or set.chains == nil then
        st.assignMenuId = nil;
        return;
    end
    local opened = false;
    pcall(function() opened = im.BeginPopup('##bdxassignmenu'); end);
    if not opened then return; end
    local s = book.spells[id];
    local sname = s and s.name or ('#' .. tostring(id));
    kit.ctext(im, kit.COL.head, ('Assign %s to...'):format(sname));
    if kit.isFn(im, 'Separator') then im.Separator(); end
    local canCascade = kit.isFn(im, 'BeginMenu') and kit.isFn(im, 'EndMenu');
    for slot = 1, 20 do
        local floor = ctx.sets.bracketFloor(slot);
        local cur = (set.ids or {})[slot] or 0;
        local curName = (cur ~= 0)
            and ((book.spells[cur] and book.spells[cur].name) or ('#' .. cur))
            or '(empty)';
        local label = ('%2d  Lv.%d+  %s'):format(slot, floor, curName);
        if canCascade then
            local okM = false;
            pcall(function() okM = im.BeginMenu(kit.esc(label) .. ('##bdxam%d'):format(slot)); end);
            if okM then
                local okA, hitA = pcall(im.Selectable, kit.esc(('Add %s here...'):format(sname)));
                if okA and hitA then
                    st.slotEdit = { slot = slot, addId = id, addLvl = { '' } };
                    st.assignMenuId = nil;
                    pcall(im.CloseCurrentPopup);
                end
                if kit.isFn(im, 'Separator') then im.Separator(); end
                local chain = set.chains[slot] or {};
                if #chain == 0 then
                    kit.ctext(im, kit.COL.dim, '(no entries)');
                end
                for i, e in ipairs(chain) do
                    local lo, hi = ctx.sets.entryRange(set, slot, i);
                    local nm = (e.id == 0) and 'empty'
                        or ((book.spells[e.id] and book.spells[e.id].name) or ('#' .. e.id));
                    kit.ctext(im, kit.COL.dim, ('%d-%d  %s'):format(lo or floor, hi or 75, nm));
                end
                pcall(im.EndMenu);
            end
        else
            local okS, hitS = pcall(im.Selectable, kit.esc(label) .. ('##bdxam%d'):format(slot));
            if okS and hitS then
                st.slotEdit = { slot = slot, addId = id, addLvl = { '' } };
                st.assignMenuId = nil;
                pcall(im.CloseCurrentPopup);
            end
        end
    end
    pcall(im.EndPopup);
end

function M.render(ctx)
    local im, book, st = ctx.im, ctx.book, ctx.state;
    local f = st.filters;
    f.sort = f.sort or {};
    f.stat = f.stat or {};
    st.detailOpen = st.detailOpen or { false };

    -- The slotlist banner is GONE (Henrik 2026-08-10, sixth round: "we can
    -- add via the add menu atm, so please remove this text"). It was written
    -- when a codex right-click could only REMOVE from a slotlist; the assign
    -- menu landed on that same right-click a round later and the warning
    -- went stale where it stood, telling people the opposite of the truth.
    -- The menu names the slots itself -- nothing left to warn about.

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
    -- which spells to show at all: what you know, and what you have set
    -- (Henrik 2026-08-07 -- the codex colors them green, this lists them alone)
    kit.combo(im, '##bdxlearn', f.learned, M.SHOW_CHOICES, 'All spells',
        comboW(M.SHOW_CHOICES, 'All spells'));
    kit.tip(im, 'Which spells the list shows.\n\n'
        .. 'Learned / Missing is what you have learned in game.\n'
        .. 'In the set / Not in the set is the build you are editing --\n'
        .. 'the same spells the list draws in green.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Reset', false, 60, 22) then
        f.text[1] = ''; f.category.value = nil; f.element.value = nil;
        f.spellType.value = nil; f.trait.value = nil; f.learned.value = nil;
        f.sort.value = nil; f.stat.value = nil;
    end

    -- resolve filter spec
    local traitCat = nil;
    if f.trait.value then
        for _, t in ipairs(book.traitChoices) do
            if t.name == f.trait.value then traitCat = t.cat; break; end
        end
    end
    local learned, inSet = nil, nil;
    if f.learned.value == 'Learned' then learned = true;
    elseif f.learned.value == 'Missing' then learned = false;
    elseif f.learned.value == M.SHOW_CHOICES[3] then inSet = true;
    elseif f.learned.value == M.SHOW_CHOICES[4] then inSet = false; end
    local ids = book.filter({
        text = f.text[1], category = f.category.value, element = f.element.value,
        spellType = f.spellType.value, traitCat = traitCat, learned = learned,
        stat = f.stat.value,
    });
    -- membership is the SET's business, not the book's: the book has no idea
    -- which build is open, so the filter engine stays free of it
    if inSet ~= nil then
        local keep = {};
        for _, id in ipairs(ids) do
            if (ctx.sets.contains(ctx.state.editingSet, id) ~= nil) == inSet then
                keep[#keep + 1] = id;
            end
        end
        ids = keep;
    end

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
    kit.ctext(im, kit.COL.dim, '  Stat:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxstatf', f.stat, book.statChoices, 'All stats',
        comboW(book.statChoices, 'All stats'));
    kit.tip(im, 'Only spells whose set bonus grants this stat.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.ctext(im, kit.COL.dim, '  View:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local density = M.densityCombo(ctx, 'codexDensity');
    if st.addNote then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   ' .. st.addNote);
    end

    -- the list -- density picks icon size, column target width and cap:
    -- big = 64px icons in 1-2 columns, normal = 24px in up to 3,
    -- compact = text only in up to 5
    local availW = availWidth(im, 800);
    local iconSz, showIcon = M.densityParams(density);
    local targetW, maxCols = 250, 3;
    if density == 'big' then targetW, maxCols = 340, 2;
    elseif density == 'medium' then targetW, maxCols = 270, 3;
    elseif density == 'compact' then targetW, maxCols = 180, 5; end
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
        local rowTop = nil;
        for i, id in ipairs(ids) do
            local col = (i - 1) % cols;
            if col == 0 then
                rowTop = nil;
                if kit.isFn(im, 'GetCursorPosY') then
                    local oky, cy = pcall(im.GetCursorPosY);
                    if oky and type(cy) == 'number' then rowTop = cy; end
                end
            elseif kit.isFn(im, 'SameLine') then
                im.SameLine(col * colW + 8);
                -- anchor every column to the ROW top: the previous item was
                -- the vertically-centered NAME (cursor moved down half the
                -- icon height), and SameLine anchors to ITS line -- which
                -- staggered the columns by 22px in the Big view (field).
                if rowTop ~= nil and kit.isFn(im, 'SetCursorPosY') then
                    pcall(im.SetCursorPosY, rowTop);
                end
            end
            -- the row grammar, right-click restored for the flat kind
            -- (Henrik 2026-08-10: "you can just right click like before").
            -- A SLOTLIST assigns per slot: right-click still REMOVES, and
            -- an add is refused with the reason pointing at the Sets tab
            -- (setmodel.canAdd names it).
            local lclick, rclick, hov = M.listRow(ctx, id, iconSz, nameW, st.selectedId == id, showIcon);
            if lclick then
                st.selectedId = id;
                st.detailOpen[1] = true;
                st.detailFocus = true;
            end
            if rclick and ctx.sets ~= nil then
                local eset = st.editingSet;
                local s2 = book.spells[id];
                if ctx.sets.kindOf(eset) == 'timeline' and M.canAssignMenu(im) then
                    -- a slotlist right-click opens the slot menu (fourth
                    -- field round) -- assignment stays per slot
                    st.assignMenuId = id;
                    pcall(im.OpenPopup, '##bdxassignmenu');
                elseif ctx.sets.contains(eset, id) then
                    ctx.sets.removeId(eset, id);
                    st.addNote = ('Removed %s.'):format(s2 and s2.name or id);
                else
                    local okAdd, whyAdd = ctx.sets.canAdd(eset, id, book,
                        ctx.budgetMax and ctx.budgetMax() or nil);
                    if okAdd then
                        ctx.sets.add(eset, id, book, ctx.budgetMax and ctx.budgetMax() or nil);
                        st.addNote = ('Added %s.'):format(s2 and s2.name or id);
                    else
                        st.addNote = ('Cannot add %s: %s.'):format(s2 and s2.name or id, whyAdd);
                    end
                end
            end
            M.tooltip(ctx, id, hov);
        end
        M.renderAssignMenu(ctx);       -- the slot menu, if a row opened it
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
    -- (the Spell Info window itself draws in host.renderBody now -- traits
    -- rows open it too, so it serves every tab)
end

return M;
