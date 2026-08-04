--[[
    bludex/ui/traitsui.lua -- the Traits tab: every blue trait ladder, what the
    current editing set feeds it, and which spells to add for the next tier
    (the "I want more Dual Wield" answer).
]]--

local ROOT = (...):sub(1, -#('ui\\traitsui') - 1);   -- relocatable require base
local kit = require(ROOT .. 'ui\\kit');

local M = {};

function M.render(ctx)
    local im, book, st = ctx.im, ctx.book, ctx.state;
    local set = st.editingSet;

    -- current weights by category, once per frame
    local evalByCat = {};
    for _, ev in ipairs(ctx.sets.traitEval(set, book)) do
        evalByCat[ev.cat] = ev;
    end

    kit.ctext(im, kit.COL.dim,
        'Weights come from spells in your CURRENT editing set (Sets tab).');
    if kit.isFn(im, 'Separator') then im.Separator(); end

    if not (kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild')) then return; end
    if im.BeginChild('bdxtraits', { 0, 0 }, false) then
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
                -- contributing spells
                local ids = book.byTrait[cat] or {};
                local max = ctx.budgetMax();
                for _, id in ipairs(ids) do
                    local s = book.spells[id];
                    local inSet = ctx.sets.contains(set, id) ~= nil;
                    local learned = book.learned(id);
                    local okAdd = ctx.sets.canAdd(set, id, book, max);

                    local pushed = false;
                    if kit.isFn(im, 'PushID') then pcall(im.PushID, 'bdxtradd' .. id); pushed = true; end
                    if inSet then
                        -- in the set: the button REMOVES (the + only added before)
                        if kit.litButton(im, '-', true, 22, 18) then
                            ctx.sets.removeId(set, id);
                        end
                    elseif okAdd then
                        if kit.litButton(im, '+', false, 22, 18) then
                            ctx.sets.add(set, id, book, max);
                        end
                    else
                        kit.ctext(im, kit.COL.dim, '   ');
                    end
                    if pushed and kit.isFn(im, 'PopID') then pcall(im.PopID); end
                    if kit.isFn(im, 'SameLine') then im.SameLine(); end

                    local col = kit.COL.accent;
                    if inSet then col = kit.COL.ok;
                    elseif ctx.blu.onBlu() and not learned then col = kit.COL.err; end
                    kit.ctext(im, col, ('%s  w%d / %spts  Lv.%s%s'):format(
                        s.name, s.trait.weight, s.setPoints or '?', s.level or '?',
                        inSet and '  [in set]' or ''));
                    kit.tip(im, inSet and 'click - to remove from the set'
                        or (okAdd and 'click + to add to the set' or nil));
                end
                if kit.isFn(im, 'Separator') then im.Separator(); end
            end
        end
    end
    im.EndChild();
end

return M;
