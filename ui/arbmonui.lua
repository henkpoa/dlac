--[[
    dlac/ui/arbmonui.lua -- the Arbiter Monitor (2026-07-28).

    A floating window over the DECISION RING (dispatch v152, M.getDecisions):
    the 4x4 equip-screen grid of the viewed decision -- each cell naming the
    resolved item, chip-coloured by the claimant that WON the slot -- plus the
    decision log underneath, newest first. Clicking a log line PINS the grid to
    that moment; Live snaps back to following the newest.

    One record, three renderers (the integration-surface ruling): /dl why in
    chat, this window, and later the stream. Everything here RENDERS the stashed
    record -- contest, plan, ladders, ctx were all captured at decision time --
    and derives nothing (mpBands' law: the record is the behavior, never render
    a rival). The Trigger Monitor stays untouched at its own altitude: it shows
    what the trigger layer PROPOSED; this window shows what the Arbiter DID.

    Same float pattern as the Trigger Monitor: gearui's d3d_present calls
    M.renderMonitor(ui) inside its own theme bracket when ui._arbMon is set;
    the [X] clears the flag (persisted via uiflags like tgmon). Defensive
    throughout -- no imgui / no dispatch just renders nothing or a notice.
]]--

local host = require('dlac\\ui\\uihost');

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');
local dsp   = try('dlac\\dispatch');
local icons = try('dlac\\ui\\itemicons');
local arb   = try('dlac\\gear\\arbiter');

-- The support recorder (feature/report). Required LAZILY at call time, not
-- captured here: this window loads early and the recorder is a late module in
-- the load loop, so a captured nil would leave the button permanently dead.
local function rep()
    local ok, m = pcall(require, 'dlac\\feature\\report');
    return (ok and type(m) == 'table') and m or nil;
end

-- Claimant identity -> what a player reads (gear/arbiter owns the map; the
-- Priority list and /dl prio + /dl why go through the same one). CLAIM_COL and
-- every lookup below stay keyed by the IDENTITY -- only the drawn string moves.
local function claimLabel(name)
    if arb == nil or type(arb.claimantLabel) ~= 'function' then return name; end
    local ok, s = pcall(arb.claimantLabel, name);
    return (ok and type(s) == 'string') and s or name;
end

local hasImgui    = imgui ~= nil;
local hasDispatch = dsp ~= nil and type(dsp.getDecisions) == 'function';
local LOCK_HELD   = (dsp ~= nil) and dsp.LOCK_HELD or nil;

local M = {};

-- The 16 slots in the game's own equip-screen order (the Equipped tab's grid).
local GRID = {
    { 'Main', 'Sub',   'Range', 'Ammo'  },
    { 'Head', 'Neck',  'Ear1',  'Ear2'  },
    { 'Body', 'Hands', 'Ring1', 'Ring2' },
    { 'Back', 'Waist', 'Legs',  'Feet'  },
};

-- Claimant colours -- literal, not themed (the idlefloat rule: the colour IS
-- the meaning, it must read the same under any theme). One per rank row; an
-- unknown claimant (a future row) gets the neutral fallback rather than nothing.
local CLAIM_COL = {
    Disabled = { 0.55, 0.60, 0.70, 1.0 },   -- free equip: steel
    Naked    = { 0.85, 0.30, 0.30, 1.0 },
    Pins     = { 0.95, 0.75, 0.20, 1.0 },
    Locks    = { 0.90, 0.55, 0.15, 1.0 },
    AutoAmmo = { 0.30, 0.80, 0.90, 1.0 },
    MaxMP    = { 0.35, 0.55, 0.95, 1.0 },
    Craft    = { 0.80, 0.60, 0.40, 1.0 },
    HELM     = { 0.45, 0.80, 0.35, 1.0 },
    Fishing  = { 0.25, 0.75, 0.65, 1.0 },
    Chocobo  = { 0.75, 0.85, 0.30, 1.0 },
    -- Mode lock: a warm gold, deliberately close to the Trigger Monitor's own
    -- locks line and deliberately NOT the Locks orange -- it sits next to the
    -- Triggers purple in the grid, and the two rows it must never be confused
    -- with are Locks (a /dl lock veto) and Triggers (the rule it overruled).
    ModeLock = { 0.95, 0.78, 0.35, 1.0 },
    Triggers = { 0.70, 0.50, 0.95, 1.0 },
};
local COL_OTHER  = { 0.60, 0.60, 0.60, 1.0 };   -- a claimant not in the table
local COL_KEPT   = { 0.42, 0.45, 0.50, 1.0 };   -- nobody claimed the slot
local COL_HEADER = { 0.75, 0.80, 0.90, 1.0 };
local COL_TEXT   = { 0.72, 0.76, 0.80, 1.0 };
local COL_BRIGHT = { 0.95, 0.97, 1.00, 1.0 };   -- changed THIS decision
local COL_DIM    = { 0.55, 0.58, 0.63, 1.0 };
local COL_WARN   = { 0.95, 0.70, 0.30, 1.0 };
local COL_ERR    = { 0.95, 0.45, 0.40, 1.0 };   -- a slot whose whole ladder was refused

-- Responsive grid (Henrik, field round 1: "only show icons until you move it
-- to become wide enough... make every slot have double the space and print the
-- equipment name"). The window's width decides the mode: at NAME_MIN per cell
-- the names appear, truncated to what the cell actually fits (themed font,
-- ~9.5px/char); below it the grid collapses to chip + icon, the icon growing
-- into the freed space. NAME_CELL_W (the fresh-install default) is double the
-- original fixed cell.
local NAME_CELL_W = 236;
local NAME_MIN    = 160;

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

local function trunc(s, n)
    s = tostring(s or '');
    if #s <= n then return s; end
    return string.sub(s, 1, n - 2) .. '..';
end

-- Case-insensitive slot lookup (the /dl why <slot> helper's twin: producers
-- disagree on slot-key case, so every record read goes through this).
local function findCI(map, slotLower)
    if type(map) ~= 'table' then return nil, nil; end
    for slot, v in pairs(map) do
        if string.lower(tostring(slot)) == slotLower then return v, slot; end
    end
    return nil, nil;
end

-- Item id by display name, for the cell icon. gearui provides lookupByName in
-- host.services; absence (or a claim sentinel that is not an item) just means
-- no icon -- the text carries the cell.
local function idOf(name)
    if type(name) ~= 'string' or name == '' then return nil; end
    local S = host.services;
    local lk = (S ~= nil) and S.lookupByName or nil;
    if lk == nil then return nil; end
    local ok, rec = pcall(lk, name);
    return (ok and type(rec) == 'table') and rec.Id or nil;
end

-- The 10x10 colour chip: a Dummy sized for it, then a drawlist rect over the
-- dummy's rect (GetItemRectMin is the proven read -- the gearui TP-float idiom).
local function chip(col)
    imgui.Dummy({ 12, 13 });
    pcall(function()
        local x, y = imgui.GetItemRectMin();
        if type(x) == 'table' then y = (x[2] or x.y); x = (x[1] or x.x); end
        if type(x) ~= 'number' or type(y) ~= 'number' then return; end
        local dl = imgui.GetWindowDrawList();
        dl:AddRectFilled({ x + 1, y + 2 }, { x + 11, y + 12 }, imgui.GetColorU32(col));
    end);
end

-- Everything one cell needs, from the record alone.
local function cellInfo(rec, slot)
    local ls = string.lower(slot);
    local con = rec.contest;
    local ops = con ~= nil and findCI(con.explain, ls) or nil;
    local win = ops ~= nil and ops[1] or nil;
    local item = findCI(rec.plan, ls);
    local sup = con ~= nil and findCI(con.sup, ls) or nil;

    -- Did the arbiter have to walk past somebody's pick to land here?
    -- (2026-08-01) 'unavail'/'reserve' = it fell and something else is worn;
    -- 'dead' = nothing on the ladder could be equipped, so the slot was left
    -- alone. The grid says WHICH without a hover -- a slot quietly wearing its
    -- second choice is exactly the thing you would never think to hover over.
    local fall = (con ~= nil) and con.fall or nil;
    local rv   = (con ~= nil) and findCI(con.rep, ls) or nil;
    local fell = nil;
    if rv ~= nil then fell = (rv.why == 'unavail') and 'unavail' or 'reserve';
    elseif fall ~= nil and findCI(fall.dead, ls) ~= nil then fell = 'dead'; end

    -- The Range/Ammo PAIR verdict (v159): its own answer, never folded into
    -- "reserved". The half of it that drops a bolt beside a bow has no
    -- reservation in it at all -- two ordinary pieces the server will not let
    -- coexist -- and a cell reading "(empty: reserved)" would send you looking
    -- for a reserving piece that does not exist.
    local pv = (con ~= nil) and con.pair or nil;
    if pv ~= nil and string.lower(tostring(pv.slot)) ~= ls then pv = nil; end

    local color = COL_KEPT;
    if win ~= nil then color = CLAIM_COL[win.name] or COL_OTHER; end

    local text, isItem = '(kept)', false;
    if pv ~= nil and pv.remove ~= true then
        text = '(empty: pair)';
    elseif sup ~= nil then
        text = '(empty: reserved)';
    elseif win ~= nil and LOCK_HELD ~= nil and win.item == LOCK_HELD then
        text = '(lock: keep worn)';
    elseif item == 'remove' then
        text = '(removed)';
    elseif item ~= nil then
        text, isItem = item, true;
    elseif win ~= nil then
        text = tostring(win.item);        -- a defending sentinel ('(free equip)')
    end

    -- The MODE LOCK QUEUE for this slot (2026-08-03): other active modes that
    -- also lock it and are waiting behind the winner. Read from the RECORD, like
    -- everything else here -- a pinned decision must not borrow the present.
    local queued = nil;
    for _, q in ipairs((con ~= nil and con.mlq) or {}) do
        if type(q) == 'table' and string.lower(tostring(q.slot)) == ls then
            queued = queued or {};
            queued[#queued + 1] = q;
        end
    end

    local changed = findCI(rec.changed, ls) == true;
    -- The icon-mode fallback marker for cells with nothing to draw: kept,
    -- removed, lock-held, reserved-empty, a defending sentinel, or an item
    -- whose icon cannot resolve. Two glyphs, dim; the hover is the authority.
    local mark = '--';
    if pv ~= nil and pv.remove ~= true then mark = 'pr';
    elseif sup ~= nil then mark = 'rs';
    elseif win ~= nil and LOCK_HELD ~= nil and win.item == LOCK_HELD then mark = 'lk';
    elseif item == 'remove' then mark = 'rm';
    elseif isItem then mark = '[?]';
    elseif win ~= nil then mark = (win.name == 'Disabled') and 'fe' or '..';
    end
    return {
        text = text, color = color, changed = changed,
        iconId = isItem and idOf(text) or nil,
        winner = win, ops = ops, mark = mark, fell = fell, queued = queued,
    };
end

-- The hover: the full /dl why <slot> answer for THIS record, one composed
-- string (SetTooltip is the codebase's hover; panel-text standard).
local function tooltipText(rec, slot, d)
    local ls = string.lower(slot);
    local out = {};
    out[#out + 1] = string.format('%s -- the contest (%s, %s)', slot, tostring(rec.event), tostring(rec.time));
    -- ONE ANSWER PER SLOT (two-way-arbiter.md §11). The no-contest line is not a
    -- verdict -- it is what a renderer says when the contest was EMPTY -- and a
    -- refused slot has an empty contest by construction, so printing it above the
    -- verdict below gives the same slot two disagreeing answers. Asked through
    -- arbiter.slotVerdict, the ONE walk, so this hover and /dl why can never
    -- drift apart about which channel speaks.
    local hasVerdict = false;
    if arb ~= nil and type(arb.slotVerdict) == 'function' then
        local vok, vk = pcall(arb.slotVerdict, rec.contest, slot);
        hasVerdict = vok and vk ~= nil;
    end
    if d.ops == nil and not hasVerdict then
        out[#out + 1] = '  nobody claimed it (kept as worn).';
    elseif d.ops ~= nil then
        for i, op in ipairs(d.ops) do
            local item = (LOCK_HELD ~= nil and op.item == LOCK_HELD) and 'LOCK-HELD (keep worn)' or tostring(op.item);
            out[#out + 1] = string.format('  %d. %s (rank %d): %s%s',
                i, tostring(claimLabel(op.name)), op.rank or 0, item, (i == 1) and '   <- winner' or '');
        end
    end
    local con = rec.contest;
    local whyOf = nil;                  -- rung name -> refusal reason, this slot
    if con ~= nil then
        local rv = findCI(con.rep, ls);
        local iv = findCI(con.inel, ls);
        local sv = findCI(con.sup, ls);
        local fall = con.fall;
        local dv = (fall ~= nil) and findCI(fall.dead, ls) or nil;
        if rv ~= nil then
            -- Two refusals reach one line, so it has to say which one: telling
            -- someone their Mog Safe piece "reserves Head" sends them hunting
            -- an imaginary bug.
            if rv.why == 'unavail' then
                out[#out + 1] = string.format('fell: %s -> %s (%s is not in a bag you can equip from)',
                    tostring(rv.from), tostring(rv.to), tostring(rv.from));
            else
                out[#out + 1] = string.format('fell: %s -> %s (it reserves %s -- owned above)',
                    tostring(rv.from), tostring(rv.to), tostring(rv.by));
            end
        elseif dv ~= nil then
            out[#out + 1] = string.format('UNAVAILABLE: %s is not in a bag you can equip from,', tostring(dv));
            out[#out + 1] = '  and nothing below it on the ladder is either -- kept as worn.';
        elseif iv ~= nil then
            out[#out + 1] = string.format('INELIGIBLE: it reserves %s, which a higher claim owns.', tostring(iv));
        elseif sv ~= nil then
            out[#out + 1] = string.format('held EMPTY: reserved by %s (the server clears it).', tostring(sv));
        end
        -- The pair verdict's own sentence, and it says WHICH of the three laws
        -- answered: the Level contest, the pairing mismatch, or the worn stick
        -- that had to come off. "The server would strip a slot" is the shared
        -- consequence and the reason any of it exists.
        local pvv = con.pair;
        if pvv ~= nil and string.lower(tostring(pvv.slot)) == ls then
            if pvv.remove == true then
                out[#out + 1] = string.format('REMOVED: worn %s cannot sit beside %s --', tostring(pvv.loser), tostring(pvv.keep));
                out[#out + 1] = '  the server would strip the Range slot, so the stick comes off.';
            elseif pvv.why == 'mismatch' then
                out[#out + 1] = string.format('held EMPTY: %s cannot be fired by %s.', tostring(pvv.loser), tostring(pvv.keep));
                out[#out + 1] = '  The ammo yields -- the Range slot is never forced off.';
            else
                out[#out + 1] = string.format('held EMPTY: %s and %s cannot coexist,', tostring(pvv.loser), tostring(pvv.keep));
                out[#out + 1] = string.format('  and %s is the higher Level, so it is kept.', tostring(pvv.keep));
            end
        end
        local ref = (fall ~= nil) and findCI(fall.refused, ls) or nil;
        if type(ref) == 'table' then
            whyOf = {};
            for _, r in ipairs(ref) do whyOf[r.name] = r.why; end
        end
        -- THE MODE LOCK QUEUE (2026-08-03, Henrik: first come, first serve).
        -- Named right after the verdict, because "Mode lock won this slot" and
        -- "another mode you have on is waiting for it" are two different facts
        -- and only the second one explains why turning a mode off changes gear.
        if d.queued ~= nil then
            out[#out + 1] = 'mode lock QUEUE (first come, first serve):';
            for _, q in ipairs(d.queued) do
                out[#out + 1] = string.format('  held by %s (%s)', tostring(q.kept.by), tostring(q.kept.set));
                out[#out + 1] = string.format('  waiting: %s (%s)', tostring(q.lost.by), tostring(q.lost.set));
            end
            out[#out + 1] = '  turn the holder off and the next one takes the slot.';
        end
        local src = findCI(con.src, ls);
        if src ~= nil then
            -- Suppressed when the ladder below names a DIFFERENT source. The
            -- floor writes contest.src for every slot it touches, winner or
            -- not, so a slot a CLAIMANT won still carries a trigger set name --
            -- and printing it above a fall that happened inside the claimant's
            -- own ladder reads as if the set were involved. The ladder line
            -- names its own source, so nothing is lost by staying quiet.
            local l = findCI(rec.ladders, ls);
            if l == nil or tostring(l.set) == tostring(src) then
                out[#out + 1] = 'set: ' .. tostring(src);
            end
        end
    end
    local lad = findCI(rec.ladders, ls);
    if lad ~= nil and type(lad.items) == 'table' and #lad.items > 0 then
        -- The WHOLE ladder, each refused rung struck through with its reason
        -- (Henrik's ruling, 2026-08-01). The survivor on its own does not
        -- answer "why am I not wearing the piece I asked for" -- the rungs the
        -- arbiter walked past, and what stopped each one, is the answer. Free:
        -- the record already carried the ladder, it just never said which rungs
        -- lost.
        local names = {};
        for _, nm in ipairs(lad.items) do
            local w = whyOf ~= nil and whyOf[nm] or nil;
            if w == 'unavail' then names[#names + 1] = nm .. '  [x not in your bags]';
            elseif w == 'reserve' then names[#names + 1] = nm .. '  [x reserves a slot owned above]';
            else names[#names + 1] = nm; end
        end
        out[#out + 1] = string.format('ladder (%s):', tostring(lad.set));
        for i, n in ipairs(names) do out[#out + 1] = string.format('  %d. %s', i, n); end
    end
    return table.concat(out, '\n');
end

-- The "decided under" line + its hover (buffs ride the hover -- too long for
-- the face). All fields optional: the snapshot is defensive by construction.
local function renderCtxLine(rec)
    local c = rec.ctx or {};
    local bits = {};
    if c.job ~= nil then
        local j = tostring(c.job) .. tostring(c.jobLevel or '');
        if c.sub ~= nil then j = j .. '/' .. tostring(c.sub) .. tostring(c.subLevel or ''); end
        bits[#bits + 1] = j;
    end
    if c.status ~= nil then
        bits[#bits + 1] = tostring(c.status) .. ((c.moving == true) and ' (moving)' or '');
    end
    if c.tp ~= nil then bits[#bits + 1] = 'TP ' .. tostring(c.tp); end
    if c.mpp ~= nil then bits[#bits + 1] = 'MP ' .. tostring(c.mpp) .. '%'; end
    if c.day ~= nil or c.weather ~= nil then
        bits[#bits + 1] = tostring(c.day or '?') .. ' day / ' .. tostring(c.weather or 'clear');
    end
    if type(c.modes) == 'table' and #c.modes > 0 then
        bits[#bits + 1] = 'modes: ' .. table.concat(c.modes, ', ');
    end
    if #bits == 0 then return; end
    imgui.TextColored(COL_DIM, esc(table.concat(bits, '   ')));
    if imgui.IsItemHovered() then
        local extra = {};
        if type(c.buffs) == 'table' and #c.buffs > 0 then
            extra[#extra + 1] = 'buffs: ' .. table.concat(c.buffs, ', ');
        end
        if c.pet ~= nil then
            extra[#extra + 1] = 'pet: ' .. tostring(c.pet) .. ' (' .. tostring(c.petStatus) .. ')';
        end
        if c.moon ~= nil then extra[#extra + 1] = 'moon: ' .. tostring(c.moon); end
        imgui.SetTooltip((#extra > 0) and esc(table.concat(extra, '\n'))
                         or 'The world at decision time, captured with the record.');
    end
end

-- The viewed record: header + grid + legend. Public so the smoke suite can
-- drive the full render against a fixture record (the S50 lesson: a load test
-- cannot catch an unbalanced or nil-global render path).
function M.renderRecord(rec, ui)
    if not hasImgui or type(rec) ~= 'table' then return; end

    -- header: when, what, and (pinned) the way back to Live
    imgui.TextColored(COL_HEADER, string.format('%s  %s', tostring(rec.time), tostring(rec.event)));
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_BRIGHT, esc(trunc(tostring(rec.action or ''), 34)));
    if ui ~= nil and ui._arbPin ~= nil then
        imgui.SameLine(0, 12);
        imgui.TextColored(COL_WARN, '[pinned]');
        imgui.SameLine(0, 6);
        if imgui.SmallButton('Live##arbmon_live') then ui._arbPin = nil; end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Back to following the newest decision.');
        end
    end
    renderCtxLine(rec);
    imgui.Separator();

    -- the 4x4 grid, responsive: measure the window, size the cells from it
    local availW = 4 * NAME_CELL_W;
    pcall(function()
        local w = imgui.GetContentRegionAvail();
        if type(w) == 'table' then w = (w[1] or w.x); end
        if type(w) == 'number' and w > 40 then availW = w; end
    end);
    local cellW = math.max(40, math.floor((availW - 8) / 4));
    local nameMode = cellW >= NAME_MIN;
    local nameChars = math.max(8, math.min(26, math.floor((cellW - 45) / 9.5)));
    local iconSz = nameMode and 16 or math.max(18, math.min(32, cellW - 20));
    for r = 1, 4 do
        for c = 1, 4 do
            local slot = GRID[r][c];
            if c > 1 then imgui.SameLine(8 + (c - 1) * cellW); end
            imgui.BeginGroup();
            local d = cellInfo(rec, slot);
            chip(d.color);
            if nameMode then
                imgui.SameLine(0, 4);
                imgui.TextColored(COL_DIM, slot);
                if d.iconId ~= nil and icons ~= nil then
                    pcall(icons.renderIcon, d.iconId, iconSz);
                    imgui.SameLine(0, 3);
                end
                imgui.TextColored(d.changed and COL_BRIGHT or COL_TEXT, esc(trunc(d.text, nameChars)));
            else
                -- icon-only: slot identity is the grid position (the game's own
                -- equip layout) + the hover; the icon takes the space instead
                imgui.SameLine(0, 3);
                if d.iconId ~= nil and icons ~= nil then
                    pcall(icons.renderIcon, d.iconId, iconSz);
                else
                    imgui.TextColored(COL_DIM, d.mark);
                end
            end
            -- The fall marker, drawn in BOTH modes: '*' the slot is wearing its
            -- second choice, '!' nothing on its ladder could be equipped. The
            -- hover carries the reason and the struck-through ladder.
            if d.fell ~= nil then
                imgui.SameLine(0, 3);
                imgui.TextColored((d.fell == 'dead') and COL_ERR or COL_WARN,
                                  (d.fell == 'dead') and '!' or '*');
            end
            -- The mode-lock QUEUE marker, drawn in BOTH modes like the fall
            -- marker and for the same reason (2026-08-03): a slot where another
            -- active mode is waiting behind the winner is exactly the thing you
            -- would never think to hover over. The hover carries who waits.
            if d.queued ~= nil then
                imgui.SameLine(0, 3);
                imgui.TextColored(CLAIM_COL.ModeLock, 'q');
            end
            imgui.EndGroup();
            if imgui.IsItemHovered() then
                imgui.SetTooltip(esc(tooltipText(rec, slot, d)));
            end
        end
        imgui.Spacing();
    end

    -- legend: only the claimants that WON something in this record
    local seen, names = {}, {};
    local exp = rec.contest ~= nil and rec.contest.explain or nil;
    for _, ops in pairs(exp or {}) do
        local w = ops[1];
        if w ~= nil and not seen[w.name] then
            seen[w.name] = true;
            names[#names + 1] = w.name;
        end
    end
    table.sort(names);
    if #names > 0 then
        local firstChip = true;
        for _, name in ipairs(names) do
            if not firstChip then imgui.SameLine(0, 10); end
            firstChip = false;
            chip(CLAIM_COL[name] or COL_OTHER);
            imgui.SameLine(0, 3);
            imgui.TextColored(COL_DIM, esc(claimLabel(name)));
        end
    end
end

-- The log: one line per decision, newest first; clicking pins the grid.
local function renderLog(ring, viewed, ui)
    imgui.TextColored(COL_HEADER, 'decisions');
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, '(click a line to pin the grid to that moment)');
    imgui.BeginChild('##dlac_arbmon_log', { 0, 0 }, false);
    for i = #ring, 1, -1 do
        local r = ring[i];
        local line = string.format('%s  %-11s %s -- %d slot%s', tostring(r.time), tostring(r.event),
            trunc(tostring(r.action or ''), 24), r.nChanged or 0, ((r.nChanged or 0) == 1) and '' or 's');
        if imgui.Selectable(esc(line) .. '##arbdec' .. tostring(r.seq), r.seq == viewed.seq) then
            if i == #ring then ui._arbPin = nil;        -- newest = just follow Live
            else ui._arbPin = r.seq; end
        end
    end
    imgui.EndChild();
end

-- ---------------------------------------------------------------------------
-- THE SUPPORT RECORDER BAR (2026-08-03). Henrik: "add a debug tool in the
-- arbiter monitor... enable the debug, get as much information as possible
-- into a log file, then send those files to me."
--
-- The bar is a DOOR, not the owner: feature/report holds the recorder, and
-- '/dl report' + '/dl mark' open the same one. This window is where a player
-- already is when they notice gear did the wrong thing, so the button belongs
-- here -- but the capture spans far more than the arbiter, and a second
-- implementation of it living in a renderer is how the two drift apart.
-- ---------------------------------------------------------------------------
local COL_REC  = { 0.95, 0.35, 0.35, 1.0 };
local COL_OK   = { 0.45, 0.85, 0.45, 1.0 };
local _markBuf = { '' };

function M.renderRecorder(ui)
    if not hasImgui then return; end
    local R = rep();
    if R == nil then
        imgui.TextColored(COL_DIM, 'support recorder unavailable (feature/report did not load)');
        return;
    end
    local st = nil;
    pcall(function() st = R.status(); end);

    if st == nil then
        if imgui.SmallButton('Record a report##arbmon_rec') then
            local pok, started, why = pcall(R.start, R.DEF_S, false);
            if pok and started == true then
                if ui ~= nil then ui._arbRepPath = nil; end
                print(string.format('[dlac] report: RECORDING for %ds. Do the thing that goes wrong,'
                    .. ' and mark the moment when it does.', R.DEF_S));
            else
                -- A button that refuses in silence is the failure this whole
                -- feature exists to stop happening to somebody else.
                print('[dlac] report: could not start -- ' .. tostring(pok and why or started));
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Record what dlac does for ' .. tostring(R.DEF_S) .. ' seconds, then write ONE'
                .. ' sendable file into addons\\dlac\\debug\\.\n'
                .. 'It starts with the decisions ALREADY in memory, so a bug you just saw is in it too.\n'
                .. 'The file holds your character name, dlac settings, sets, triggers and gear facts,\n'
                .. 'plus dlac\'s own chat lines -- no tells, no party chat. Send it to the addon author.\n'
                .. 'Same thing from chat: /dl report   (/dl report full bundles every job)');
        end
        if ui ~= nil and ui._arbRepPath ~= nil then
            imgui.SameLine(0, 10);
            imgui.TextColored(COL_OK, 'wrote: ' .. esc(tostring(ui._arbRepPath)));
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Send this ONE file. It is the whole picture.');
            end
        end
        return;
    end

    imgui.TextColored(COL_REC, string.format('RECORDING  %d:%02d left', math.floor(st.left / 60), st.left % 60));
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, string.format('%d decision%s, %d mark%s',
        st.decisions, (st.decisions == 1) and '' or 's', st.marks, (st.marks == 1) and '' or 's'));
    imgui.SameLine(0, 10);
    -- MARKED or NOT is the whole state of this control (Henrik, field round 1:
    -- "if I have marked an event, the button should change to de-mark and
    -- remove it"). Marked: the note becomes text and the button undoes it.
    -- Unmarked: the field is live and the button places one.
    if st.marked then
        imgui.TextColored(COL_OK, esc('marked: ' .. trunc((st.markNote ~= nil and st.markNote ~= '')
            and st.markNote or '(no note)', 30)));
        if imgui.IsItemHovered() then
            imgui.SetTooltip('This moment is flagged in the report.\n'
                .. 'It stays one mark however many times you press it -- pressing again would only\n'
                .. 'replace these words. A new decision starts a new moment you can mark separately.');
        end
        imgui.SameLine(0, 6);
        if imgui.SmallButton('Un-mark##arbmon_unmark') then
            pcall(R.unmark);
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Remove this mark. The log still records that you placed and removed it --\n'
                .. 'the timeline is never rewritten, only the index is.');
        end
    else
        imgui.PushItemWidth(180);
        imgui.InputText('##arbmon_marknote', _markBuf, 96);
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then
            imgui.SetTooltip('What went wrong, in your words. It lands in the file at this moment.');
        end
        imgui.SameLine(0, 6);
        if imgui.SmallButton('Mark##arbmon_mark') then
            pcall(R.mark, tostring(_markBuf[1] or ''));
            _markBuf[1] = '';
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Flag THIS moment. In a five-minute log, finding the moment is the hard part.\n'
                .. 'Works from a macro too: /dl mark <note>');
        end
    end
    imgui.SameLine(0, 6);
    if imgui.SmallButton('Stop & write##arbmon_recstop') then
        local ok, p = pcall(R.stop, 'the player stopped it from the Monitor');
        if ok and type(p) == 'string' and ui ~= nil then ui._arbRepPath = p; end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Finish now and write the file. It writes itself when the window closes anyway.');
    end
end

-- The floating window. Titled (imgui.ini remembers where you drag it); the [X]
-- clears the toggle, exactly like the Trigger Monitor.
function M.renderMonitor(ui)
    if not hasImgui or ui == nil or ui._arbMon ~= true then return; end
    -- Fresh-install default = the wide NAME layout (4 double-space cells);
    -- shrink it and the grid collapses to icons. An existing imgui.ini keeps
    -- whatever size the player last dragged (FirstUseEver).
    imgui.SetNextWindowSize({ 4 * NAME_CELL_W + 26, 480 }, ImGuiCond_FirstUseEver);
    local open = { true };
    if imgui.Begin('dlac Arbiter Monitor##dlac_arbmon', open) then
        -- The recorder bar sits ABOVE the ring check on purpose: "nothing has
        -- happened yet" is exactly when a player wants to start recording.
        M.renderRecorder(ui);
        imgui.Separator();
        local ring = hasDispatch and dsp.getDecisions() or nil;
        if type(ring) ~= 'table' or #ring == 0 then
            imgui.TextColored(COL_DIM, 'no decisions yet -- do something and watch.');
        else
            local rec = ring[#ring];
            if ui._arbPin ~= nil then
                local found = nil;
                for i = #ring, 1, -1 do
                    if ring[i].seq == ui._arbPin then found = ring[i]; break; end
                end
                if found ~= nil then rec = found;
                else ui._arbPin = nil; end              -- pruned off the ring: back to Live
            end
            M.renderRecord(rec, ui);
            imgui.Separator();
            renderLog(ring, rec, ui);
        end
    end
    imgui.End();
    if not open[1] then
        ui._arbMon = false;
        ui._flagsDirty = true;
    end
end

host.provide({ arbmonui = M });
return M;
