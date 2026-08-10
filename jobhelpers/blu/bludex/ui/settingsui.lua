--[[
    bludex/ui/settingsui.lua -- the Settings tab.

    The set-point budget, in the three parts it is actually made of:

        cap(level) = base(level) + learned bonus + Assimilation merits
                                                   (merits only at Lv75)

    base            the server's rule, exact at every level (blueutils.cpp)
    learned bonus   CatsEyeXI's award for spells learned, from Boruko in
                    Aht Urghan Whitegate. Counts at EVERY level, sync
                    included -- so a reading below 75 gives it outright.
    merits          Assimilation, job group 2. 2 points each, 5 max = 10.
                    Counts only at level 75.

    Both unknowns fall out of two readings of the client's own cap:
        below 75:  bonus  = cap - base
        at 75:     merits = cap - base - bonus

    Panel text follows dlac's standard (uistyle.helpLabel): the label is
    UNDERLINED and its explanation lives in the hover, never on the panel.
]]--

local M = {};

local ROOT = (...):sub(1, -#('ui\\settingsui') - 1);
local kit  = require(ROOT .. 'ui\\kit');
local sets = require(ROOT .. 'lib\\setmodel');

-- a value on the same line as its underlined label
local function field(im, label, tip, value, col)
    kit.helpLabel(im, label .. ':', tip);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.ctext(im, col or kit.COL.accent, value);
end

-- an inline editor: blank clears back to automatic
local function edit(im, id, current, isKnown, onSet, onClear)
    local buf = { isKnown and tostring(current) or '' };
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.isFn(im, 'PushItemWidth') then im.PushItemWidth(56); end
    if kit.isFn(im, 'InputText') then
        pcall(im.InputText, id, buf, 8);
        local n = tonumber(buf[1]);
        if buf[1] == '' then
            if isKnown then onClear(); end
        elseif n ~= nil and n >= 0 and n ~= current then
            onSet(math.floor(n));
        end
    end
    if kit.isFn(im, 'PopItemWidth') then im.PopItemWidth(); end
end

-- hover-delay choices, in the order they show. A settings file edited by hand
-- can hold anything; delayLabel shows that value rather than snapping it.
local DELAYS = {
    { 'Instant', 0.0 }, { '0.25s', 0.25 }, { '0.5s', 0.5 }, { '0.75s', 0.75 },
    { '1s', 1.0 }, { '1.5s', 1.5 }, { '2s', 2.0 },
};

local function delayLabel(v)
    for _, d in ipairs(DELAYS) do
        if math.abs(d[2] - v) < 0.001 then return d[1]; end
    end
    return ('%gs'):format(v);
end

function M.render(ctx)
    local im, cfg, blu = ctx.im, ctx.cfg, ctx.blu;
    local lvl   = blu.effectiveLevel();
    local base  = sets.baseCapAtLevel(lvl or 0);
    local total = blu.budget();

    local function save()
        cfg.capLearnedBonus = blu.learnedBonus or -1;
        cfg.capMeritPoints  = blu.meritPts or -1;
        if ctx.save then ctx.save(); end
    end

    kit.helpLabel(im, 'Set-point budget',
        'Your point total is worked out by the game client, not sent by the\n'
        .. 'server, and the client only recalculates it when you open the\n'
        .. 'native Blue Magic set menu. Bludex works it out too, from the\n'
        .. 'three parts below, so the total stays right after a level sync.');
    if kit.isFn(im, 'Separator') then im.Separator(); end

    -- THE GAME'S number, not ours -- this row exists to be compared against
    -- the one below it, so it must never show our own answer.
    local clientCap, clientLvl = blu.capValue(), blu.capLevel();
    field(im, 'Current last measured cap',
        'The last total the GAME CLIENT itself worked out -- not Bludex\'s.\n\n'
        .. 'It refreshes ONLY when you open:\n'
        .. '    Magic  ->  Blue Magic  ->  Set\n'
        .. 'and at no other time -- so after a level change it still describes\n'
        .. 'the level you left until you open that menu once.\n\n'
        .. 'Also zone once after loading Bludex: your merits arrive with the\n'
        .. 'zone, and both are needed before the total can be worked out.',
        clientCap and ('%d   (worked out at Lv.%s)'):format(clientCap, tostring(clientLvl or '?'))
            or 'not read yet',
        (clientCap ~= nil and clientLvl == lvl) and kit.COL.ok or kit.COL.warn);

    local src = select(2, blu.budget());
    field(im, 'Budget Bludex is using',
        'What the meters actually show.\n\n'
        .. 'Bludex\'s own figure whenever it can work one out, because it is\n'
        .. 'rebuilt from your CURRENT level every frame, while the game\'s is a\n'
        .. 'stored number that only refreshes at the set menu.\n\n'
        .. 'It defers to the game only when the game has been SEEN to\n'
        .. 'recalculate at this very level and still disagrees -- then the\n'
        .. 'game is right and one of the figures below is wrong.',
        ('%s   %s   (base for Lv.%s is %d)'):format(
            total and tostring(total) or '--',
            (src == 'model') and '[computed]' or (src == 'live') and '[from the game]' or '[stale]',
            tostring(lvl or '?'), base));

    local mKnown = blu.meritPts ~= nil;
    field(im, 'Assimilation Points',
        'From Assimilation, in the job group 2 merits.\n\n'
        .. '2 points per merit, 5 merits maximum -- so 10 points at most.\n'
        .. 'They count only at level 75: a level sync removes them.\n\n'
        .. 'Read automatically WHEN YOU ZONE -- the server pushes your full\n'
        .. 'merit list on every zone-in, and again whenever you raise or lower\n'
        .. 'a merit. Nothing is requested; it simply arrives. It can also be\n'
        .. 'worked out as cap - base - learned bonus at Lv75. Type to override.',
        mKnown and (blu.meritCount
            and ('%d   (%d merits x %d%s)'):format(blu.meritPts, blu.meritCount,
                blu.meritValue, blu.meritValueProven and ', measured' or '')
            or tostring(blu.meritPts))
            or 'not known yet',
        mKnown and kit.COL.ok or kit.COL.warn);
    edit(im, '##bdxmerits', blu.meritPts or 0, mKnown,
        function(n) blu.meritPts = n; save(); end,
        function() blu.meritPts = nil; save(); end);

    local bKnown = blu.learnedBonus ~= nil;
    field(im, 'Learned Bonus Points',
        'CatsEyeXI awards set points for blue magic you have learned.\n'
        .. 'Collect them from Boruko in Aht Urghan Whitegate (J-10, near\n'
        .. 'Waoud), up to 25 points in total.\n\n'
        .. 'These count at EVERY level, level sync included -- so below 75,\n'
        .. 'where merits do not count, they are simply cap - base level\n'
        .. 'points. Open the native Blue Magic set menu once while synced and\n'
        .. 'Bludex reads them off. Type a value to set it yourself.',
        bKnown and tostring(blu.learnedBonus) or 'not known yet',
        bKnown and kit.COL.ok or kit.COL.warn);
    edit(im, '##bdxbonus', blu.learnedBonus or 0, bKnown,
        function(n) blu.learnedBonus = n; save(); end,
        function() blu.learnedBonus = nil; save(); end);

    if kit.isFn(im, 'Separator') then im.Separator(); end
    kit.ctext(im, kit.COL.dim, ('Lv.%s: %d base + %s learned%s = %s'):format(
        tostring(lvl or '?'), base,
        tostring(blu.learnedBonus or '?'),
        ((lvl or 0) >= 75) and (' + ' .. tostring(blu.meritPts or '?') .. ' merits') or '',
        tostring(blu.expectedCap(lvl) or '?')));
    if blu.wireTotal ~= nil then
        kit.helpLabel(im, ('server cross-check: %d'):format(blu.wireTotal),
            'The server sends this on packet 0x063 at login, on zoning, and on\n'
            .. 'any merit change. On CatsEyeXI it carries the learned bonus and\n'
            .. 'the merits added together, so it should equal the two figures\n'
            .. 'above summed. It cannot separate them, which is why each is\n'
            .. 'tracked on its own.', kit.COL.dim);
    end

    if kit.isFn(im, 'Separator') then im.Separator(); end
    kit.helpLabel(im, 'Interface',
        'How the window behaves, rather than what it computes.');
    if kit.isFn(im, 'Separator') then im.Separator(); end

    local delay = tonumber(cfg.tooltipDelay) or 0.5;
    kit.helpLabel(im, 'Hover tooltip delay:',
        'How long the cursor has to REST on something before its tooltip\n'
        .. 'appears.\n\n'
        .. 'At Instant every tooltip fires the moment the cursor crosses it,\n'
        .. 'so simply moving the mouse across the window throws a panel of\n'
        .. 'text over whatever you were reaching for.\n\n'
        .. 'Covers every tooltip in Bludex, the spell tooltips included.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local labels = {};
    for _, d in ipairs(DELAYS) do labels[#labels + 1] = d[1]; end
    local dstate = { value = delayLabel(delay) };
    if kit.combo(im, '##bdxtipdelay', dstate, labels, nil,
                 kit.measure(im, labels, 60) + 24) then
        for _, d in ipairs(DELAYS) do
            if d[1] == dstate.value then
                cfg.tooltipDelay = d[2];
                kit.hoverDelay = d[2];      -- takes effect on this very frame
                if ctx.save then ctx.save(); end
                break;
            end
        end
    end

    -- WHICH KIND COMES FIRST (docs/set-types-plan.md 3): the New chooser
    -- lists this one on top, preselected. It never converts a set.
    local KINDS = { 'levels', 'timeline' };
    kit.helpLabel(im, 'New sets start as:',
        'The set type the New chooser offers first.\n\n'
        .. 'Flat: one spell per slot, applied as-is - and you can add\n'
        .. 'dedicated builds per level range (level sync) under the same\n'
        .. 'name whenever you want them.\n'
        .. 'Slotlist: a list of spells per slot, each taking over at its\n'
        .. 'own level - the most granular control.\n\n'
        .. 'You still choose per set - this only orders the chooser.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local klabels = {};
    for _, k in ipairs(KINDS) do klabels[#klabels + 1] = ctx.sets.KIND_LABELS[k]; end
    local kstate = { value = ctx.sets.KIND_LABELS[cfg.newSetKind] or 'Flat' };
    if kit.combo(im, '##bdxnewkind', kstate, klabels, nil,
                 kit.measure(im, klabels, 80) + 24) then
        for _, k in ipairs(KINDS) do
            if ctx.sets.KIND_LABELS[k] == kstate.value then
                cfg.newSetKind = k;
                if ctx.save then ctx.save(); end
                break;
            end
        end
    end
end

return M;
