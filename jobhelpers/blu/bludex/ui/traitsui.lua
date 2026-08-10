--[[
    bludex/ui/traitsui.lua -- the Traits tab: every blue trait ladder, what the
    current editing set feeds it, and which spells to add for the next tier
    (the "I want more Dual Wield" answer).

    The spell rows speak the codex grammar (2026-08-04, reference-only since
    the timeline, 2026-08-08): icon+name rows in the chosen View density
    (own setting, cfg.traitsDensity), left-click opens the Spell Info
    window, hover shows the rich tooltip. In-set rows draw green, unlearned
    red. Assignment lives in the Sets tab's Assign pane.
]]--

local ROOT = (...):sub(1, -#('ui\\traitsui') - 1);   -- relocatable require base
local kit      = require(ROOT .. 'ui\\kit');
local tsrc     = require(ROOT .. 'lib\\traitsource');
local spellsui = require(ROOT .. 'ui\\spellsui');

local M = {};

-- 'Acc +10, R.Acc +10' -- a few job traits carry no direct modifier (the
-- server implements them in Lua), and an empty list must still say something.
local function modsText(ctx, mods)
    local parts = {};
    for _, m in ipairs(mods or {}) do
        parts[#parts + 1] = ('%s %+d'):format(ctx.sets.prettyStat(m.stat), m.value);
    end
    if #parts == 0 then return 'no direct stat bonus'; end
    return table.concat(parts, ', ');
end

-- WHERE IT CAME FROM, in as few words as fit on a row.
local function jobLabel(e)
    local who = e.code or ('job ' .. tostring(e.job));
    return ('%s (%s job)'):format(who, e.slot == 'sub' and 'sub' or 'main');
end

local function sourceLabel(a)
    if a.source ~= 'job' then return 'your set'; end
    return jobLabel(a.job);
end

-- WHAT YOU HAVE, IN THE LADDER'S OWN UNITS (Henrik 2026-08-07: "we wanna
-- correlate the trait tiers, not the actual stats"). The two sides of a
-- collision do not share a modifier -- job Clear Mind grants MPHEAL, the blue
-- ladder grants CLEAR_MIND -- so a stat value read off one side means nothing
-- against the other. The RANK does: it is the game's own counter for that
-- trait, and it is what the rungs below are numbered by.
--
-- The rung's own name comes along only when it differs from the ladder's, so
-- 'Triple Attack tier 2' never reads as a Double Attack tier. The SOURCE
-- tag only when it is a JOB (Henrik 2026-08-10, third round: your own set
-- earning its own tier needs no attribution -- that is the normal case).
local function tierLabel(v, a)
    local n = (a.traitName ~= nil and a.traitName ~= v.name)
        and (a.traitName .. ' tier ') or 'Tier ';
    if a.source == 'job' then
        return ('%s%d [%s]'):format(n, a.tier or 0, sourceLabel(a));
    end
    return ('%s%d'):format(n, a.tier or 0);
end

-- The sentence that matters: what the job already gives. Kept in one place
-- -- the Traits tab says it long, the spell tooltip says it short. (CEXI
-- law, field 2026-08-10: the job GRANTS its tier; weight that only reaches
-- that tier buys nothing NEW, but a higher tier is still yours for the
-- full weight -- nothing is blocked.)
function M.givenTip(v)
    local e = v.blocker;
    if e == nil then return nil; end
    return ('%s grants %s at rank %d whatever your set does, so weight that\n'
        .. 'only reaches that tier buys nothing new. A HIGHER tier still\n'
        .. 'applies -- invest its full weight and the blue trait takes over.'):format(
        jobLabel(e), v.name, e.rank);
end
M.blockedTip = M.givenTip;             -- the old name, kept for callers

local tlCache = { at = -10 };          -- the tiers-by-level sweep, 1s stale

function M.render(ctx)
    local im, book, st = ctx.im, ctx.book, ctx.state;
    local set = st.editingSet;
    st.detailOpen = st.detailOpen or { false };
    local isTl = ctx.sets.kindOf(set) == 'timeline';

    -- the header is just the View control (Henrik 2026-08-10, third round)
    -- -- plus, for a SLOTLIST, the level slider (fourth round): the ladders
    -- read the slotlist AT that level, and the job side scales with it
    kit.ctext(im, kit.COL.dim, 'View:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local density = spellsui.densityCombo(ctx, 'traitsDensity');
    local shown = nil;
    if isTl then
        st.preview = st.preview or {};     -- SHARED with the Sets tab slider
        local liveLvl = ctx.blu.effectiveLevel();
        shown = (st.preview.value ~= nil) and st.preview.value or (liveLvl or 75);
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.head, '   Level');
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        local sbuf = { shown };
        if kit.sliderInt(im, '##bdxtraitlvl', sbuf, 1, 75, 200) then
            st.preview.value = sbuf[1];
            shown = sbuf[1];
        end
        kit.tip(im, 'The ladders below read the slotlist AT this level, and your\n'
            .. 'job traits scale with it (a sub job runs at half the level).\n'
            .. 'The same slider as the Sets tab.');
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if kit.litButton(im, 'Live', st.preview.value == nil,
            kit.measure(im, { 'Live' }, 40), 20) then
            st.preview.value = nil;
            shown = liveLvl or 75;
        end
        kit.tip(im, 'Follow your real level (75 while off BLU).');
    end
    if st.addNote then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   ' .. st.addNote);
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    -- weights by category -- from the slotlist RESOLVED at the slider level
    -- when there is one, from the editing build itself otherwise
    local evalSource = isTl and ctx.sets.resolveAtLevel(set, shown or 75, book) or set;
    local evalByCat = {};
    for _, ev in ipairs(ctx.sets.traitEval(evalSource, book)) do
        evalByCat[ev.cat] = ev;
    end

    -- a host without the job side still renders the ladders; it just cannot
    -- attribute (an empty job map = "nothing known", never "nothing granted")
    local verdict = ctx.verdict
        or function(c, w) return tsrc.verdict(c, w, book, {}, nil); end;
    -- previewing away from live scales the JOB side too -- main at the
    -- slider level, sub at half of it -- and the live-bit referee stands
    -- down (its bits describe the live level alone)
    if isTl and ctx.jobPair ~= nil then
        local liveLvl = ctx.blu.effectiveLevel();
        if shown ~= nil and (liveLvl == nil or shown ~= liveLvl) then
            local jp = ctx.jobPair;
            local jobsAt = tsrc.jobs(jp.mainJob, shown, jp.subJob, math.floor(shown / 2));
            verdict = function(c, w) return tsrc.verdict(c, w, book, jobsAt, nil); end;
        end
    end

    -- IS THE EDITING SET LIVE? The 0x0AC referee reflects what is EQUIPPED;
    -- while the editing set's spells are not applied, "game says no" on a
    -- set-sourced trait states the obvious and is suppressed (Henrik
    -- 2026-08-10, from the field). Job-sourced traits stay checkable: jobs
    -- are always worn. Membership is what matters -- bits know no slots.
    local setLive = false;
    if ctx.blu.currentSet ~= nil then
        local live = ctx.blu.currentSet();
        if #live == 20 then
            local liveHas = {};
            for i = 1, 20 do if live[i] ~= 0 then liveHas[live[i]] = true; end end
            local lvlNow = (ctx.blu.effectiveLevel and ctx.blu.effectiveLevel()) or 75;
            local plan = ctx.sets.resolveAtLevel(set, lvlNow, book);
            setLive = true;
            for i = 1, 20 do
                local id = plan[i] or 0;
                if id ~= 0 and book.learned(id) and not liveHas[id] then
                    setLive = false;
                    break;
                end
            end
        end
    end

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
            -- WHAT IS ACTUALLY UP, and from where. A job trait beats a blue
            -- one outright, so the set's own ladder reading is not the answer
            -- on its own (lib/traitsource.lua).
            local v = verdict(cat, weight);
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            if #v.active > 0 then
                for ai, a in ipairs(v.active) do
                    if ai > 1 and kit.isFn(im, 'SameLine') then im.SameLine(); end
                    -- green either way: you HAVE this. The tag says from whom.
                    kit.ctext(im, kit.COL.ok, tierLabel(v, a));
                    if a.source == 'job' then
                        kit.tip(im, ('%s grants %s at rank %d, from level %d.\n'
                            .. 'It gives %s -- which is NOT what the blue rungs below\n'
                            .. 'grant: the same trait, a different modifier, so only the\n'
                            .. 'tier number compares between them.\n\n'
                            .. 'Job traits are applied before blue ones, and a blue trait\n'
                            .. 'matching one you already have is discarded rather than\n'
                            .. 'added to it or upgraded.'):format(
                            a.job.name or sourceLabel(a), a.traitName or v.name,
                            a.job.rank, a.job.level, modsText(ctx, a.mods)));
                    else
                        kit.tip(im, ('Your set earns this: %s.'):format(modsText(ctx, a.mods)));
                    end
                end
                if v.deadWeight and v.blocker ~= nil then
                    -- the job GIVES this tier (Henrik 2026-08-10: "it is not
                    -- blocking you") -- say so, quietly, and no more
                    if kit.isFn(im, 'SameLine') then im.SameLine(); end
                    kit.ctext(im, kit.COL.dim, ('  Active from %s'):format(jobLabel(v.blocker)));
                    kit.tip(im, M.givenTip(v));
                end
                -- THE ROAD ABOVE, for ANY active ladder (Henrik 2026-08-10,
                -- third round: name the next tier's cost plainly -- and on
                -- a set-earned ladder too, where the tag stays silent). The
                -- blue ladder counts its own weight from zero either way.
                local top = v.active[1];
                if top ~= nil and info ~= nil and weight > 0 then
                    local nxtTier = (top.tier or 0) + 1;
                    local nxt = info.tiers[nxtTier];
                    if nxt ~= nil and weight < nxt.points then
                        if kit.isFn(im, 'SameLine') then im.SameLine(); end
                        kit.ctext(im, kit.COL.warn, ('  Tier %d at %d weight (%d now)'):format(
                            nxtTier, nxt.points, weight));
                        local jobNote = (top.source == 'job')
                            and ('\nThe job\'s tier %d does not stand in for the blue\nrungs below it.'):format(top.tier or 0)
                            or '';
                        kit.tip(im, ('Tier %d activates once your set feeds %d total weight\n'
                            .. '-- %d more from here.%s'):format(
                            nxtTier, nxt.points, nxt.points - weight, jobNote));
                    end
                end
            elseif weight > 0 then
                -- price the first tier too (fourth round: "add the tier
                -- price when the trait isn't active yet")
                local t1 = info and info.tiers and info.tiers[1] or nil;
                if t1 ~= nil then
                    kit.ctext(im, kit.COL.warn, ('Tier 1 at %d weight (%d now)'):format(
                        t1.points, weight));
                    kit.tip(im, ('Tier 1 activates once your set feeds %d total weight\n-- %d more from here.'):format(
                        t1.points, t1.points - weight));
                else
                    kit.ctext(im, kit.COL.warn, ('weight %d - below tier 1'):format(weight));
                end
            else
                kit.ctext(im, kit.COL.dim, 'not in set');
            end
            -- the live 0x0AC bit is the referee: when the game disagrees with
            -- the table, say so rather than keep asserting -- but only where
            -- the bit can KNOW: a set-sourced trait is only checkable while
            -- the editing set is actually worn (setLive above)
            local saysNo = false;
            for _, a in ipairs(v.active) do
                if a.live == false and (a.source == 'job' or setLive) then
                    saysNo = true;
                end
            end
            if saysNo then
                if kit.isFn(im, 'SameLine') then im.SameLine(); end
                kit.ctext(im, kit.COL.warn, '  (game says no)');
                kit.tip(im, 'The game\'s own trait list does not have this trait up, though\n'
                    .. 'Bludex works out that it should be. The job-trait table is the\n'
                    .. 'public server source; CatsEyeXI can differ from it. Trust the game.');
            end

            if open and info then
                -- THE LADDER, with each rung in one of two states (the CEXI
                -- law -- nothing is out of reach anymore):
                --   held  a job's rank already reaches it -- green, named,
                --         and annotated with what the job ACTUALLY grants
                --         (different modifier, so never left implied)
                --   open  the set's own, reached or not -- job rank or no
                for ti, tier in ipairs(info.tiers) do
                    local reached = weight >= tier.points;
                    local heldBy = v.held[ti];
                    local note, col = '', kit.COL.dim;
                    if heldBy ~= nil then
                        col = kit.COL.ok;
                        note = ('   <- %s, rank %d: %s'):format(
                            jobLabel(heldBy), heldBy.rank, modsText(ctx, heldBy.mods));
                    elseif reached then
                        col = kit.COL.ok;
                    end
                    kit.ctext(im, col, ('   tier %d  (weight %d): %s%s'):format(
                        ti, tier.points, modsText(ctx, tier.mods), note));
                    if heldBy ~= nil then
                        kit.tip(im, ('You already have tier %d of %s, from %s.\n\n'
                            .. 'The job trait grants %s; the blue rung grants %s --\n'
                            .. 'the same trait through a different modifier, which is why\n'
                            .. 'only the tier number compares. Feeding weight PAST this\n'
                            .. 'tier still climbs: a higher blue tier takes over.'):format(
                            ti, v.name, jobLabel(heldBy),
                            modsText(ctx, heldBy.mods), modsText(ctx, tier.mods)));
                    end
                end
                -- contributing spells -- the codex row grammar (left-click =
                -- Spell Info, right-click = toggle in/out of the set)
                local indented = false;
                if kit.isFn(im, 'Indent') and kit.isFn(im, 'Unindent') then
                    pcall(im.Indent, 14);
                    indented = true;
                end
                -- the codex row grammar, right-click restored for the flat
                -- kind (Henrik 2026-08-10: "you can just right click like
                -- before"); a SLOTLIST assigns per slot, so its rows stay
                -- reference-only and canAdd names the reason on hover
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
                        if isTl and spellsui.canAssignMenu(im) then
                            -- a slotlist right-click opens the slot menu
                            -- (fourth field round) -- assignment per slot
                            st.assignMenuId = id;
                            pcall(im.OpenPopup, '##bdxassignmenu');
                        elseif inSet then
                            ctx.sets.removeId(set, id);
                            st.addNote = ('Removed %s.'):format(s.name);
                        else
                            local okAdd, whyAdd = ctx.sets.canAdd(set, id, book, ctx.budgetMax());
                            if okAdd then
                                ctx.sets.add(set, id, book, ctx.budgetMax());
                                st.addNote = ('Added %s.'):format(s.name);
                            else
                                st.addNote = ('Cannot add %s: %s.'):format(s.name, whyAdd);
                            end
                        end
                    end
                    spellsui.tooltip(ctx, id, hov);
                end
                if indented then pcall(im.Unindent, 14); end
                if kit.isFn(im, 'Separator') then im.Separator(); end
            end
        end
        -- THE TIERS BY LEVEL (fourth round): under a slotlist, the whole
        -- curve in one list -- which tier each ladder holds across 1-75,
        -- straight from the timeline (setmodel.tierTimeline, cached 1s)
        if isTl then
            if kit.isFn(im, 'Separator') then im.Separator(); end
            kit.ctext(im, kit.COL.head, 'Tiers by level (this slotlist)');
            kit.tip(im, 'What each ladder holds at every level, resolved from the\nslot timeline. The slider above previews any one level;\nthis is the whole curve.');
            if tlCache.set ~= set or (os.clock() - tlCache.at) > 1.0 then
                tlCache.set, tlCache.at = set, os.clock();
                tlCache.list = ctx.sets.tierTimeline(set, book);
            end
            for _, rec in ipairs(tlCache.list or {}) do
                local parts = {};
                for _, sp in ipairs(rec.spans) do
                    parts[#parts + 1] = (sp.lo == sp.hi)
                        and ('tier %d at Lv.%d'):format(sp.tier, sp.lo)
                        or ('tier %d Lv.%d-%d'):format(sp.tier, sp.lo, sp.hi);
                end
                kit.wrapped(im, kit.COL.dim, ('%s: %s'):format(rec.name, table.concat(parts, ', ')));
            end
            if tlCache.list == nil or #tlCache.list == 0 then
                kit.ctext(im, kit.COL.dim, 'no tiers activate at any level');
            end
        end
        spellsui.renderAssignMenu(ctx);    -- the slot menu, if a row opened it
    end
    im.EndChild();
end

return M;
