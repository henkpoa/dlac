--[[
    bludex/ui/traitsui.lua -- the Traits tab: every blue trait ladder, what the
    current editing set feeds it, and which spells to add for the next tier
    (the "I want more Dual Wield" answer).

    The spell rows speak the codex grammar (2026-08-04): icon+name rows in the
    chosen View density (own setting, cfg.traitsDensity), left-click opens the
    Spell Info window, right-click toggles the spell in/out of the editing
    set, hover shows the rich tooltip. In-set rows draw green, unlearned red.
]]--

local ROOT = (...):sub(1, -#('ui\\traitsui') - 1);   -- relocatable require base
local kit      = require(ROOT .. 'ui\\kit');
local spellsui = require(ROOT .. 'ui\\spellsui');

local M = {};

function M.render(ctx)
    local im, book, st = ctx.im, ctx.book, ctx.state;
    local set = st.editingSet;
    st.detailOpen = st.detailOpen or { false };

    -- current weights by category, once per frame
    local evalByCat = {};
    for _, ev in ipairs(ctx.sets.traitEval(set, book)) do
        evalByCat[ev.cat] = ev;
    end

    kit.ctext(im, kit.COL.dim,
        'Weights come from spells in your CURRENT editing set (Sets tab).');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.ctext(im, kit.COL.dim, '   View:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local density = spellsui.densityCombo(ctx, 'traitsDensity');
    if st.addNote then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   ' .. st.addNote);
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    if not (kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild')) then return; end
    if im.BeginChild('bdxtraits', { 0, 0 }, false) then
        local iconSz, showIcon = spellsui.densityParams(density);
        local nameW = math.max(kit.availWidth(im, 600) - (showIcon and iconSz or 0) - 56, 120);
        for _, choice in ipairs(book.traitChoices) do
            local cat = choice.cat;
            local info = book.traits.categories[cat];
            local ev = evalByCat[cat];
            local weight = ev and ev.weight or 0;

            local open = st.openCat[cat] or false;
            if kit.isFn(im, 'Selectable') then
                local ok, clicked = pcall(im.Selectable, kit.esc((open and '[-] ' or '[+] ') .. choice.name), false);
                if ok and clicked then
                    st.openCat[cat] = not open;
                    open = not open;
                end
            else
                kit.ctext(im, kit.COL.head, choice.name);
                open = true;
            end
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            if ev and ev.tier then
                kit.ctext(im, kit.COL.ok, ('active: %s  (weight %d)'):format(ev.tierText, weight));
            elseif weight > 0 then
                kit.ctext(im, kit.COL.warn, ('weight %d - below tier 1'):format(weight));
            else
                kit.ctext(im, kit.COL.dim, 'not in set');
            end

            if open and info then
                -- the ladder
                for ti, tier in ipairs(info.tiers) do
                    local parts = {};
                    for _, m in ipairs(tier.mods) do
                        parts[#parts + 1] = ('%s %+d'):format(ctx.sets.prettyStat(m.stat), m.value);
                    end
                    local reached = weight >= tier.points;
                    kit.ctext(im, reached and kit.COL.ok or kit.COL.dim,
                        ('   tier %d  (weight %d): %s'):format(ti, tier.points, table.concat(parts, ', ')));
                end
                -- contributing spells -- the codex row grammar (left-click =
                -- Spell Info, right-click = toggle in/out of the set)
                local indented = false;
                if kit.isFn(im, 'Indent') and kit.isFn(im, 'Unindent') then
                    pcall(im.Indent, 14);
                    indented = true;
                end
                for _, id in ipairs(book.byTrait[cat] or {}) do
                    local s = book.spells[id];
                    local inSet = ctx.sets.contains(set, id) ~= nil;
                    local label = ('%s  w%d / %spts  Lv.%s%s'):format(
                        s.name, s.trait.weight, s.setPoints or '?', s.level or '?',
                        inSet and '  [in set]' or '');
                    local lclick, rclick, hov = spellsui.listRow(ctx, id, iconSz, nameW,
                        st.selectedId == id, showIcon,
                        { label = label, dimColor = kit.COL.err });
                    if lclick then
                        st.selectedId = id;
                        st.detailOpen[1] = true;
                        st.detailFocus = true;
                    end
                    if rclick then
                        if inSet then
                            ctx.sets.removeId(set, id);
                            st.addNote = ('Removed %s.'):format(s.name);
                            if ctx.save then ctx.save(); end
                        else
                            local ok2, why = ctx.sets.add(set, id, book, ctx.budgetMax());
                            st.addNote = ok2 and ('Added %s.'):format(s.name)
                                or ('Cannot add %s: %s.'):format(s.name, why);
                            if ok2 and ctx.save then ctx.save(); end
                        end
                    end
                    spellsui.tooltip(ctx, id, hov);
                end
                if indented then pcall(im.Unindent, 14); end
                if kit.isFn(im, 'Separator') then im.Separator(); end
            end
        end
    end
    im.EndChild();
end

return M;
