-- fishui.lua -- the fishing panel (Gear Helpers -> "Fishing Gear").
-- docs/design/fishing-gear.md #2. helmui's sibling: rendered from
-- automationsui's detail delegation with the SAME deps table.
-- Coverage/status live ABOVE the imgui guard so the
-- headless tests reach them (improvement over helmui, whose guard hides all).
--
-- TWO surfaces live here since 2026-07-27:
--   * the PANEL (M.render) -- "what I own": status line (skill / GP / VP) ->
--     gear matrix (BASE / ANGLER'S / GUILD / MARINERS -- the VP set, ids
--     interleaved with HELM's Plain block) -> rods (standard / legendary) ->
--     baits owned (per-container) -> today's ventures (0x017 capture) -> guild
--     corner (GP shop, rank ladder).
--   * the target WINDOW (M.renderSearch -> M.renderTargetBody) -- "what am I
--     hunting": search, rod verdicts from the server's own fail math, ISOLATION
--     rows. A floating window (chocoui's dig-search precedent), so the hobby bar
--     can reach it and it is never buried at the bottom of the panel.

local M = {};

local _fcok, fcalc = pcall(require, 'dlac\\feature\\fishcalc');
_fcok = _fcok and type(fcalc) == 'table';

-- ---------------------------------------------------------------------------
-- Item ids (research 2026-07-18; design doc #1). Names resolve at render time
-- (gearBonus carries the live API names = catalog names; rods via client
-- resources) -- ownership is checked by ID against deps.ownedCounts.
-- ---------------------------------------------------------------------------
local BASE_SET  = { 13808, 14070, 14292, 14171 };          -- Fsh. body/hands/legs/feet
local PAIR_UP   = { [13808] = 13809, [14070] = 14071,      -- base -> Angler's
                    [14292] = 14293, [14171] = 14172 };
local EXTRAS    = { 10925, 15452 };                        -- Fisher's Torque, Fisherman's Belt
local HEAD_RING = { 25608, 39051 };                        -- Tlahtlamah, Angler's Ring
local GUILD_GEAR = { 14195, 11337, 14400, 15554 };         -- Waders, Smock, Apron, Pelican Ring
local MARINERS  = { { 26535, 26536 }, { 25986, 25987 },    -- Tunica, Gloves (base, +1)
                    { 25899, 25900 }, { 25966, 25967 } };  -- Hose, Boots
-- Crooked Jones: a SEPARATE fishing economy, not the VP set (Henrik,
-- 2026-08-06, bg-wiki CatsEyeXI_Systems/Fishing #Crooked_Jones). He trades
-- three named fish a day for DOUBLOONS in Norg (H-8) -- fishing 20+, and the
-- Sinister Stash stalls in Norg and Lower Jeuno are where they spend. The
-- Eyepatch is 12,000 of them.
--   The round-2 research had it as "the Mariners hat analog" purely because
-- id 28443 sits beside HELM's Plain block the way the Mariners ids do. It
-- does not: ADJACENT IDS ARE NOT AN ACQUISITION PATH. It gets its own
-- section under the matrix rather than a column that says VP.
--   Displayed at all since 2026-08-06, when Henrik reversed the 07-18 ruling
-- ("I was wrong about the eyepatch") -- a PLAYER has one and sent its card,
-- so the "nothing in-game mentions them" premise died with it (Henrik does
-- not own one; the field check goes to that player). Still NOT displayed:
-- Halieutica 20945 and the legendary-rod +1s 19320/19321 (they still look
-- unobtainable here). fishdb keeps their data and autoPick still honours one
-- if it lands in a bag -- they are only invisible here.
-- The Sinister Stash, in the wiki's own price order. `gear` marks the one row
-- that is fishing gear (ADVANCED, Expert Angler tooltip); everything else is
-- here because it is what doubloons BUY, which is the question a doubloon
-- balance actually raises.
--   The Chart 9426 and the Hook 9420 are LIVE ids (Henrik, catseyexi.com/item,
-- 2026-08-06) and they are NOT in dlac's catalog, which carries equipment. Do
-- not "correct" them from the public server clone: it has woodworking_set_94
-- at 9420 and smithing_set_80 at 9426 -- the live DB repurposed both, exactly
-- the id-collision the augment/Garrison work hit. The client resource is the
-- authority at runtime and it is what draws the icon.
--   The mount alone has no id, because it is not an item; its art comes from
-- assets\redcrab.png through filetex (the icon bg-wiki uses). Missing file =
-- the row still draws, just without art.
--   That PNG is the 32x32 ANTI-ALIASED crab, not the pixel-art variants that
-- shipped beside it (16/32/48/64/128 are all one 16px sprite at integer
-- upscales -- 467 bytes at 32x32 against this one's 1861 says it). Drawn at
-- 18px next to game item icons, which are themselves 32x32 downscaled, it
-- carries the same ratio and the same softness as its neighbours; a hard
-- pixel sprite at 1.125x or 0.56x shimmers. Do not "upgrade" it to icon-128.
local JONES_SHOP = {
    { id = 18888, cost =  5000, note = 'Required for Treasure Hunts' },
    { id = 25669, cost =  8000, note = 'Crab costumes' },
    { id =  9426, cost = 10000, note = 'Spawns an encounter in Cape Terrigan' },
    { id = 28443, cost = 12000, note = '"Expert Angler"+2 -- Lv.50 all jobs', gear = true },
    { n = 'Red Crab Mount', icon = 'redcrab', cost = 15000, note = 'ACE only' },
    { id = 11009, cost = 15000, note = 'CW only' },
    { id =  9420, cost = 20000, note = 'Fishing ultimate-weapon material' },
};
local JONES_GEAR = {};                                     -- the fishing half, for ADVANCED
for _, row in ipairs(JONES_SHOP) do
    if row.gear and row.id ~= nil then JONES_GEAR[#JONES_GEAR + 1] = row.id; end
end
local LEGENDARY_RODS = { 17386, 17011 };                   -- Lu Shang's, Ebisu
local LEG_ANY = { [17386] = true, [19320] = true, [17011] = true, [19321] = true };
local SPECIAL_RODS = { [17012] = true, [17013] = true, [19319] = true };  -- Judge's, Basket, MMM
local NO_SUGGEST = { [17012] = true, [17013] = true, [19319] = true,      -- specials...
                     [19320] = true, [19321] = true };     -- ...and the undisplayed +1s

local ADVANCED = {};   -- any of these owned = coverage level 3
for _, id in ipairs(GUILD_GEAR) do ADVANCED[id] = true; end
for _, pair in ipairs(MARINERS) do ADVANCED[pair[1]] = true; ADVANCED[pair[2]] = true; end
-- Doubloon gear counts as the currency tier too: level 3 reads "guild/venture"
-- but what it MEANS is "you are past the craftable set and into a shop".
for _, id in ipairs(JONES_GEAR) do ADVANCED[id] = true; end
for _, id in ipairs(HEAD_RING) do ADVANCED[id] = true; end

-- ---------------------------------------------------------------------------
-- Coverage for the Automations LIST row (pure; levelColor ramp).
--   1 = anything fishing-positive owned; 2 = the base four-piece set dressed
--   (either tier per slot); 3 = a guild/venture piece online; 4 = a
--   legendary rod (the kit's crown).
-- ---------------------------------------------------------------------------
M.txt = { [0] = 'nothing yet', 'gear started', 'base set dressed',
          'guild/venture tier', 'LEGENDARY rod -- awesome' };
M.maxLevel = 4;

local function counts(deps)
    if deps == nil or type(deps.ownedCounts) ~= 'function' then return nil; end
    local ok, t = pcall(deps.ownedCounts);
    return (ok and type(t) == 'table') and t or nil;
end
local function owned(oc, id) return oc ~= nil and (oc[id] or 0) >= 1; end

-- Worn-at-once Fish+ total: per slot the best owned Mod::FISH piece. The
-- math lives in fishcalc.wornFishTotal now (the fish bar's rod-dropdown
-- verdict tags share the same effective-skill convention).
local function fishTotal(oc)
    if not _fcok or type(fcalc.wornFishTotal) ~= 'function' then return 0; end
    return fcalc.wornFishTotal(oc);
end

function M.coverage(deps)
    local oc = counts(deps);
    if oc == nil or not _fcok then return 0; end
    local db = fcalc.db(); if db == nil then return 0; end
    local lvl = 0;
    for id, g in pairs(db.gearBonus or {}) do
        if owned(oc, id) then lvl = 1; break; end
    end
    if lvl == 0 then
        for id in pairs(db.rods or {}) do
            if owned(oc, id) then lvl = 1; break; end
        end
    end
    if lvl == 0 then return 0; end
    local baseFull = true;
    for _, id in ipairs(BASE_SET) do
        if not owned(oc, id) and not owned(oc, PAIR_UP[id]) then baseFull = false; break; end
    end
    if baseFull then lvl = 2; end
    if lvl == 2 then
        for id in pairs(ADVANCED) do
            if owned(oc, id) then lvl = 3; break; end
        end
    end
    for id in pairs(LEG_ANY) do
        if owned(oc, id) then lvl = 4; break; end
    end
    return lvl;
end

function M.status(deps)
    local lvl = M.coverage(deps);
    local ft = fishTotal(counts(deps));
    local label = M.txt[lvl] or '';
    if ft > 0 then label = string.format('%s (Fish+%d)', label, ft); end
    return lvl, label;
end

-- ---------------------------------------------------------------------------
-- Render side (addon state only from here down).
-- ---------------------------------------------------------------------------
local _iok, imgui = pcall(require, 'imgui');
if not _iok then return M; end

local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_DIM    = { 0.55, 0.55, 0.55, 1.00 };
local COL_TEXT   = { 0.70, 0.70, 0.70, 1.00 };
local COL_GOLD   = { 0.95, 0.85, 0.45, 1.00 };
local COL_WARN   = { 1.00, 0.60, 0.30, 1.00 };
local COL_ERR    = { 1.00, 0.45, 0.45, 1.00 };
local GREEN_OWNED = { 0.45, 0.90, 0.45, 1.0 };
local GREEN_GLOW  = { 0.75, 1.00, 0.70, 1.0 };

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

-- 12000 -> "12,000". The Stash prices are five figures and read as noise
-- without it; same grouping the wiki's shop table uses.
local function comma(n)
    local s = tostring(math.floor(tonumber(n) or 0));
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse();
    return (out:gsub('^,', ''));
end

local _fwok, fw = pcall(require, 'dlac\\feature\\fishwatch');
_fwok = _fwok and type(fw) == 'table';

-- assets\*.png loader, for the one Stash row that is not an item (restockui's
-- crate-icon precedent). nil handle = no art, never an error.
local _ftok, filetex = pcall(require, 'dlac\\ui\\filetex');
_ftok = _ftok and type(filetex) == 'table' and type(filetex.handle) == 'function';

-- Names for ids fishdb has no row for -- the Sinister Stash sells things that
-- are not fishing gear (a HELM staff, a costume hat, a craft back piece), so
-- nameOf's usual sources come up empty. Client resources still win when the
-- game is there to ask; these are the headless/last-resort spelling.
local SHOP_NAMES = {
    [18888] = "Brigand's Shovel",
    [25669] = 'Crab Cap +1',
    [11009] = "Shaper's Shawl",
    [ 9426] = "Buccaneer's Chart",
    [ 9420] = 'Rusty Fishing Hook',
};

-- Display name for an id: live API name from fishdb (catalog-identical), else
-- the client resource name, else the fishdb SQL name, else a shop name, else
-- the id.
local _names = {};
local function nameOf(id)
    if _names[id] ~= nil then return _names[id]; end
    local n = nil;
    if _fcok then
        local db = fcalc.db();
        if db ~= nil then
            local g = (db.gearBonus or {})[id];
            n = g and g.n or nil;
            if n == nil and db.customBaits ~= nil then n = db.customBaits[id]; end
        end
    end
    if n == nil and _fwok and type(fw._clientName) == 'function' then n = fw._clientName(id); end
    if n == nil and _fcok then
        local db = fcalc.db();
        if db ~= nil then
            n = ((db.rods or {})[id] or {}).n or ((db.baits or {})[id] or {}).n
                or ((db.fish or {})[id] or {}).n;
        end
    end
    _names[id] = n or SHOP_NAMES[id] or ('#' .. tostring(id));
    return _names[id];
end

-- One matrix cell (helmui itemLine, keyed by ID). state: 'glow' | 'owned' |
-- 'better' | 'dim'.
local function itemLine(deps, id, state, note)
    local name = nameOf(id);
    if state == 'glow' then
        pcall(function()
            local x, y = imgui.GetCursorScreenPos();
            local w = 24 + imgui.CalcTextSize(name);
            local dl = imgui.GetWindowDrawList();
            dl:AddRectFilled({ x - 4, y - 2 }, { x + w + 6, y + 18 }, 0x1E8CE6FF, 9);
            dl:AddRectFilled({ x - 2, y - 1 }, { x + w + 3, y + 17 }, 0x2895EBFF, 7);
            dl:AddRectFilled({ x + 1, y + 1 }, { x + w - 2, y + 15 }, 0x30A0F0FF, 5);
        end);
    end
    if deps ~= nil and type(deps.renderIcon) == 'function' then
        deps.renderIcon(id, 18);
    end
    local col = COL_DIM;
    if state == 'glow' then col = GREEN_GLOW;
    elseif state == 'owned' or state == 'better' then col = GREEN_OWNED; end
    imgui.TextColored(col, esc(name));
    if imgui.IsItemHovered() then
        -- explicit note WINS (the helmui rule -- cascade/Expert Angler notes
        -- must not lose to the generic stat card).
        -- esc() is NOT optional here: SetTooltip is printf, so a bare '%' eats
        -- the character after it. The Expert Angler note shipped 08-06 as
        -- "Fatigue Limit +20%, ..." and rendered "+20" with the comma gone
        -- (Henrik's screenshot) -- the percent was never on screen.
        if note ~= nil then
            imgui.SetTooltip(esc(note));
        else
            local rec = (deps ~= nil and deps.lookupByName ~= nil) and deps.lookupByName(name) or nil;
            if rec ~= nil and deps ~= nil and type(deps.itemTooltip) == 'function' then
                pcall(deps.itemTooltip, rec);
            else
                imgui.SetTooltip(esc(name));
            end
        end
    end
end

-- Cell state for a (base, better) pair: base greens through its upgrade
-- ("you're awesome" cascade). No glow here -- only Mariners glows (Henrik
-- 2026-07-18: they are the real fishing end-game).
local function pairStates(oc, baseId, upId)
    local b, u = owned(oc, baseId), upId ~= nil and owned(oc, upId);
    local bs = (b or u) and ((not b and 'better') or 'owned') or 'dim';
    local us = u and 'owned' or 'dim';
    return bs, us;
end

local BETTER_NOTE = 'Green via progression: you own a better piece for this slot --\nso this one is covered. You\'re awesome.';

-- Expert Angler tooltip for the pieces that carry the custom mods (identified
-- 2026-07-18 via bg-wiki CatsEyeXI_Content/Ventures: 2004 = Fatigue Limit +%,
-- 2005 = Golden Arrow Rate +% -- values match the live DB). The wiki's own
-- framing: one Expert Angler increment = +10% daily capacity, multiplicative,
-- which is exactly the cx4 = N x 10 / cx5 = N shape fishdb stores.
--   `source` names the economy the piece comes from and MUST be passed when it
-- is not the venture set -- the Eyepatch spent a day labelled "venture gear"
-- and it is bought with doubloons (Henrik, 2026-08-06: "It is not a venture
-- gear, which we know now").
local function expertNote(id, source)
    if not _fcok then return nil; end
    local db = fcalc.db(); if db == nil then return nil; end
    local g = (db.gearBonus or {})[id];
    if g == nil or (g.cx4 == nil and g.cx5 == nil) then return nil; end
    local parts = {};
    if g.cx4 ~= nil then parts[#parts + 1] = string.format('Fatigue Limit +%d%%', g.cx4); end
    if g.cx5 ~= nil then parts[#parts + 1] = string.format('Golden Arrow Rate +%d%%', g.cx5); end
    -- Brigands Eyepatch carries the cx mods and NO Fish mod (fishdb 28443) --
    -- the only carrier that does, so the tail must not promise skill it has
    -- no line for.
    local src = source or 'CatsEyeXI venture gear';
    local tail = (g.fish ~= nil) and ('\n(+ Fishing skill -- ' .. src .. ')')
                                  or ('\n(' .. src .. ' -- no Fishing skill of its own)');
    return 'Expert Angler: ' .. table.concat(parts, ', ') .. tail;
end

-- Target-picker state. Shared by every surface that opens the window, which is
-- the point: open it from the hobby bar and you land on the same fish you were
-- looking at when you opened it from the panel.
local sel = { q = { '' }, id = nil, showAllIso = false };
local _reqAt = 0;

-- The target window's own open flag (chocoui's `search.area.open` precedent):
-- a {bool} for imgui.Begin's close box, session-only -- it does not reopen
-- after a relog.
local target = { open = { false } };
M._target = target;   -- test seam (open the window headlessly)

-- ---------------------------------------------------------------------------
-- The OPENER. Public because three surfaces open this window -- the panel's
-- Target button, the hobby bar's Fishing tab (the target name IS the button),
-- and /dl fish find -- while the window is DRAWN from exactly one place
-- (M.renderSearch off gearui's d3d_present). Any surface may open a floating
-- window; only one may draw it. `q` (optional) seeds the search box, so
-- `/dl fish find carp` opens with the matches already listed.
-- ---------------------------------------------------------------------------
function M.openTarget(q)
    if type(q) == 'string' and q ~= '' then
        sel.q[1] = q;
        sel.showAllIso = false;
    end
    target.open[1] = true;
end

-- ---------------------------------------------------------------------------
-- The target picker -- the BODY of the floating "Fishing -- Target fish" window
-- (M.renderSearch, at the bottom of this file). This lived INLINE in the panel
-- until 2026-07-27, halfway down a long page: you scrolled past the gear matrix
-- to change what you were fishing for, and the hobby bar could not reach it at
-- all -- its target line was a label whose tooltip told you to go to the panel.
-- Same treatment, and the same reason, as the Chocobo dig search on 07-24.
--
-- Everything it needs is re-derived here (db / owned counts / skill / worn Fish+
-- total) instead of being passed down from the panel, so the body has ONE
-- contract for every caller and the panel keeps none of its state.
-- ---------------------------------------------------------------------------
function M.renderTargetBody(deps, availW)
    if not _fcok or fcalc.db() == nil then
        imgui.TextColored(COL_ERR, 'fishdb missing -- rebuild data/fishdb.lua (tools/gen_fishdb.py).');
        return;
    end
    local db = fcalc.db();
    local oc = counts(deps);
    local skill = _fwok and fw.playerFishSkill() or nil;
    local ft = fishTotal(oc);
    -- The spot list places its bait column at availW * 0.55, so a too-narrow
    -- value crushes the zone names rather than wrapping them.
    if type(availW) ~= 'number' or availW < 420 then availW = 740; end

    -- ---- target fish ------------------------------------------------------
    imgui.TextColored(COL_HEADER, 'TARGET FISH');
    imgui.SameLine(0, 12);
    imgui.PushItemWidth(220);
    imgui.InputText('##fishsearch', sel.q, 48);
    imgui.PopItemWidth();
    local tgtId, tgtName = nil, nil;
    if _fwok then tgtId, tgtName = fw.getTarget(); end
    -- Make target lives ON this row (Henrik: burying it under the spot list
    -- was confusing) -- shown while viewing a fish that isn't the target yet.
    if _fwok and sel.id ~= nil and sel.id ~= tgtId and db.fish[sel.id] ~= nil then
        imgui.SameLine(0, 8);
        if imgui.Button('Make target##fishmk') then fw.setTarget(sel.id); end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Rod and bait auto-pick for this fish (best owned by the\nserver\'s own break math); the fish bar and overlay follow.');
        end
    end
    if tgtId ~= nil then
        imgui.SameLine(0, 12);
        imgui.TextColored(GREEN_GLOW, esc('target: ' .. tostring(tgtName)));
        imgui.SameLine(0, 10);
        if imgui.Button('Clear##fishtgt') and _fwok then
            fw.setTarget(nil);
            sel.id = nil;             -- this window's view too: a clean start
            sel.q[1] = '';
            sel.showAllIso = false;   -- collapsed spot list next time as well
            -- and the FRAME's copy: the adopt line below ran in this same
            -- frame with the stale local and re-pinned the old fish -- the
            -- spot list looked unclearable (Henrik, field round 5).
            tgtId, tgtName = nil, nil;
        end
    end
    -- the pill, right here where the eye already is (label shortened so the
    -- row survives Make-target + target + Clear in the themed font)
    if _fwok then
        imgui.SameLine(0, 20);
        local on = fw.isEnabled();
        if imgui.Button(on and 'Fish Idle: ON##fishpill' or 'Fish Idle: off##fishpill') then
            fw.setEnabled(not on);
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Wear the fishing kit while idle (engine overlay; combat gear\nreturns when you engage). Session-only -- always starts OFF.\nRod and bait follow the target fish.');
        end
    end

    -- Typing = searching: the match list stays up EVERY frame while the box
    -- holds text (the first cut only drew it on the frame the query CHANGED --
    -- one-frame flicker, unpickable; Henrik's "can't search up new ones").
    -- Picking a row clears the box and hands over to the detail view below.
    local q = tostring(sel.q[1] or '');
    if q ~= '' then
        local hits = fcalc.searchFish(q);
        for i = 1, math.min(#hits, 8) do
            local h = hits[i];
            local f = h.fish;
            if imgui.Selectable(string.format('%s  (skill %d%s)##fh%d', f.n, f.sk or 0,
                    (f.leg or 0) ~= 0 and ', LEGENDARY' or '', h.id)) then
                sel.id = h.id;
                sel.showAllIso = false;
                sel.q[1] = '';
            end
        end
        if #hits == 0 then imgui.TextColored(COL_DIM, 'no fish matches.'); end
    elseif sel.id == nil and tgtId ~= nil then
        sel.id = tgtId;   -- the window opens on the active target
    end

    local fid = sel.id;
    if fid ~= nil and db.fish[fid] ~= nil then
        local f = db.fish[fid];
        local eff = (skill or 0) + ft;
        imgui.Spacing();
        imgui.TextColored(COL_GOLD, esc(f.n));
        imgui.SameLine(0, 10);
        local skCol = (eff >= (f.sk or 0)) and GREEN_OWNED or COL_WARN;
        imgui.TextColored(skCol, string.format('skill %d (you: %d)', f.sk or 0, eff));
        imgui.SameLine(0, 10);
        imgui.TextColored(COL_DIM, string.format('%s%s%s  |  bites: %s%s',
            (f.sz or 0) == 1 and 'LARGE' or 'small',
            (f.leg or 0) ~= 0 and ', LEGENDARY' or '',
            (f.item or 0) ~= 0 and ', item' or '',
            fcalc.hourHint(f.hp),
            fcalc.moonHint(f.mp) ~= nil and (', ' .. fcalc.moonHint(f.mp)) or ''));
        local d = (f.sk or 0) - eff;
        if d >= 1 and d <= 50 then
            imgui.TextColored(GREEN_OWNED, string.format('skill-up window: +%d above you%s', d,
                (d >= 9 and d <= 13) and ' -- the ~+11 sweet spot' or ''));
        end
        if _fwok and tgtId == fid then
            local _, rodN = fw.getRod();
            local _, baitN = fw.getBait();
            local rp = type(fw.rodPinned) == 'function' and fw.rodPinned();
            local bp = type(fw.baitPinned) == 'function' and fw.baitPinned();
            imgui.TextColored(GREEN_OWNED, esc(string.format('current target -- rod: %s%s, bait: %s%s',
                tostring(rodN or 'none'), rp and ' (manual)' or '',
                tostring(baitN or 'none'), bp and ' (manual)' or '')));
        end

        -- rod verdicts (server fail math)
        local ownedRods = {};
        for id in pairs(db.rods) do if owned(oc, id) then ownedRods[id] = true; end end
        local ranked = fcalc.rodsFor(f, eff, ownedRods);
        local shownOwned, suggest, ownedSafe = 0, nil, false;
        for _, r in ipairs(ranked) do
            if r.owned and r.v.ok then ownedSafe = true; end
            if r.owned and shownOwned < 3 then
                shownOwned = shownOwned + 1;
                local v = r.v;
                local label, col;
                if v.ok then label, col = 'SAFE', GREEN_OWNED;
                elseif v.loseWhy == 'toobig' then label, col = 'TOO LARGE for it', COL_ERR;
                elseif v.loseWhy == 'toosmall' then label, col = 'too small for it', COL_WARN;
                else
                    label = string.format('risk: %d%% lose / %d%% snap / %d%% break', v.lose, v.snap, v.brk);
                    col = (v.brk > 0 or v.snap > 20) and COL_ERR or COL_WARN;
                end
                imgui.TextColored(COL_TEXT, esc('rod: ' .. nameOf(r.id)));
                imgui.SameLine(0, 8);
                imgui.TextColored(col, esc(label));
            end
            -- LEG_ANY excluded: the legendary tier tops every risk-0 ranking
            -- now, and "go quest Ebisu" is no shopping hint for a carp.
            if suggest == nil and r.v.ok and not NO_SUGGEST[r.id] and not LEG_ANY[r.id] then suggest = r; end
        end
        if shownOwned == 0 then imgui.TextColored(COL_ERR, 'you own no fishing rod.'); end
        -- Only pitch a buy when you actually lack a safe rod for this fish.
        if not ownedSafe and suggest ~= nil and not suggest.owned then
            imgui.TextColored(COL_DIM, esc(string.format('safest rod for this fish: %s (unowned)', nameOf(suggest.id))));
        end

        -- where + bait (the flagship: ISOLATION first). A breath of air first
        -- (Henrik: separate the fish info from the spot list).
        imgui.Spacing();
        imgui.TextColored(COL_DIM, 'spots + baits -- best isolation first, click a ROW to fish it:');
        local iso = fcalc.isolationFor(fid);
        if #iso == 0 then
            imgui.TextColored(COL_DIM, 'no known catch spot (quest/contest-gated?).');
        else
            local nShow = sel.showAllIso and #iso or math.min(#iso, 10);
            for i = 1, nShow do
                local row = iso[i];
                imgui.PushID('iso' .. i);
                -- THE WHOLE ROW IS THE CLICK TARGET (Henrik 2026-07-27: "I cannot
                -- target the end result without clicking on the bait, I would like
                -- to be able to click on the whole row"). Shipped since the feature
                -- began with only the bait cell live -- a ~6-character hit box on a
                -- row you read left-to-right, so the natural click (on the PLACE)
                -- did nothing at all.
                --
                -- Same shape as automationsui.autoRow: a full-width Selectable
                -- FIRST, then every column drawn over it with an ABSOLUTE SameLine.
                -- (SameLine(0) would mean "after the previous item" -- i.e. past the
                -- full-width Selectable, off the right edge -- so the first column
                -- takes a nonzero x like the automations rows do.)
                local rowClick = imgui.Selectable('##isorow', false,
                    (ImGuiSelectableFlags_None or 0), { 0, 18 });
                -- One hover for the row, since there is now one item to hover. It
                -- carries what the three separate cell tooltips used to: the bait
                -- and its affinity, who else bites here, and the monster warning.
                if imgui.IsItemHovered() then
                    local tip = { string.format('bait: %s (affinity %d/3)%s',
                        row.baitName, row.power or 0,
                        owned(oc, row.bait) and '  -- OWNED' or '  -- not in your bags') };
                    if not row.clean then
                        local names = {};
                        for j = 1, math.min(#row.others, 8) do
                            names[#names + 1] = (db.fish[row.others[j]] or {}).n or ('#' .. row.others[j]);
                        end
                        tip[#tip + 1] = 'also bites here: ' .. table.concat(names, ', ');
                    end
                    if row.mob ~= nil then
                        tip[#tip + 1] = string.format('a MONSTER can take this bait here: %s%s',
                            row.mob.n or '?', (row.mob.nm or 0) ~= 0 and ' (NM)' or '');
                    end
                    tip[#tip + 1] = string.format('click: make %s the target with THIS bait', f.n);
                    imgui.SetTooltip(table.concat(tip, '\n'));
                end
                if rowClick and _fwok then fw.setTarget(fid, row.bait); end
                imgui.SameLine(2);
                if row.clean then imgui.TextColored(COL_GOLD, '[ISOLATED]');
                else imgui.TextColored(COL_DIM, string.format('(%d rivals)', #row.others)); end
                imgui.SameLine(128);   -- themed font ~9.5px/char: '[ISOLATED]' needs the room
                local place = row.zoneName .. (row.areaName ~= nil and (' -- ' .. row.areaName) or '');
                imgui.TextColored(COL_TEXT, esc(place));
                imgui.SameLine(math.floor(availW * 0.55));
                imgui.TextColored(COL_TEXT, esc(string.format('%s %s',
                    row.baitName, string.rep('*', row.power or 1))));
                if row.mob ~= nil then
                    imgui.SameLine(0, 8);
                    imgui.TextColored(COL_WARN, '[!]');
                end
                imgui.PopID();
            end
            if #iso > 10 and not sel.showAllIso then
                if imgui.Selectable(string.format('... %d more spots##isomore', #iso - 10)) then
                    sel.showAllIso = true;
                end
            end
            imgui.TextColored(COL_DIM, 'Items can always bite (Smock/Apron reduce them); monsters only outside cities.');
        end
    end
end

-- ---------------------------------------------------------------------------
-- The panel.
-- ---------------------------------------------------------------------------
function M.render(deps, availW)
    if not _fcok or fcalc.db() == nil then
        imgui.TextColored(COL_ERR, 'fishdb missing -- rebuild data/fishdb.lua (tools/gen_fishdb.py).');
        return;
    end
    local db = fcalc.db();
    local oc = counts(deps);
    availW = availW or 900;

    -- Refresh the point streams on panel entry (>5s throttle, debounced again
    -- inside the watchers).
    if _fwok and os.clock() > _reqAt then
        _reqAt = os.clock() + 5;
        pcall(fw.requestPoints);
        pcall(fw.requestGuildPoints);
    end

    -- ---- status line ------------------------------------------------------
    local skill = _fwok and fw.playerFishSkill() or nil;
    local rank = _fwok and fw.playerFishRank() or nil;
    local ft = fishTotal(oc);
    local parts = {};
    if skill ~= nil then
        local cap = (rank ~= nil) and ((rank + 1) * 10) or nil;
        parts[#parts + 1] = string.format('Fishing skill %d%s%s', skill,
            (ft > 0) and string.format(' (+%d gear)', ft) or '',
            (cap ~= nil) and (' / cap ' .. cap) or '');
        if rank ~= nil and db.guild ~= nil and db.guild.ranks ~= nil then
            local rn = db.guild.ranks[rank + 1];
            if rn ~= nil then parts[#parts + 1] = 'rank ' .. rn; end
        end
    else
        parts[#parts + 1] = 'Fishing skill: (not read yet)';
    end
    local gp = _fwok and fw.guildPoints() or nil;
    parts[#parts + 1] = 'GP ' .. (gp ~= nil and tostring(gp) or '?');
    -- VP only where the pack has ventures at all (ADR 0035). Guarded: the
    -- headless suites stub fishwatch without the gate.
    local ventOn = false;
    if _fwok and type(fw.venturesOn) == 'function' then
        pcall(function() ventOn = fw.venturesOn() == true; end);
    end
    if ventOn then
        local vp = fw.venturePoints();
        parts[#parts + 1] = 'VP ' .. (vp ~= nil and tostring(vp) or '?');
    end
    imgui.TextColored(COL_GOLD, esc(table.concat(parts, '   |   ')));
    -- Panel chrome, all on the status row: the target picker, the idle pill and
    -- the bar toggle. The TARGET FISH section that used to sit below is a
    -- floating window now (M.renderSearch) -- this panel is "what I own", that
    -- window is "what am I hunting".
    if _fwok then
        imgui.SameLine(0, 16);
        local _, tName = fw.getTarget();
        if imgui.Button((tName ~= nil and ('Target: ' .. tostring(tName)) or 'Target fish...')
                .. '##fishtgtopen') then
            M.openTarget();
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Search a fish, read the rod verdicts, pick a spot + bait.\nOpens a floating window, so it is never buried at the bottom of\nthis panel (also: /dl fish find).');
        end
        imgui.SameLine(0, 10);
        -- The shared pill, at last. This row is no longer the crowded one that
        -- forced a shortened text button here -- Make target / target / Clear
        -- moved to the window -- so Fishing now matches Craft / HELM / Chocobo /
        -- AutoAmmo / Restock instead of being the one panel with its own switch.
        local pillOn = fw.isEnabled();
        local cbok, craftbar = pcall(require, 'dlac\\ui\\craftbar');
        if cbok and type(craftbar) == 'table' and type(craftbar.onOffSwitch) == 'function' then
            if craftbar.onOffSwitch(pillOn, 'fishpanel',
                'Fishing idle set is ON -- rod, bait and fishing gear stay on while idle. Click to turn off.',
                'Set Fish Idle: wears your best fishing kit whenever idle, until turned off.\nRod and bait follow the target fish.')
            then fw.setEnabled(not pillOn); end
        elseif imgui.Button((pillOn and 'ON' or 'OFF') .. '##fishpanelonoff', { 46, 22 }) then
            fw.setEnabled(not pillOn);
        end
        imgui.SameLine(0, 10);
        local barShown = false;
        pcall(function() barShown = require('dlac\\ui\\hobbybar').isShown('fish'); end);
        if imgui.Button(barShown and 'Hide bar##fishbar' or 'Fish bar##fishbar') then
            pcall(function() require('dlac\\ui\\hobbybar').toggle('fish'); end);
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('The shared hobby bar, on Fishing (also: /dl fish bar).');
        end
    end
    imgui.Spacing();

    -- ---- gear matrix ------------------------------------------------------
    local colW = math.max(190, math.floor(availW / 4));
    imgui.TextColored(COL_HEADER, 'BASE SET');
    imgui.SameLine(colW); imgui.TextColored(COL_HEADER, "ANGLER'S (+1)");
    imgui.SameLine(colW * 2); imgui.TextColored(COL_HEADER, 'GUILD (GP)');
    imgui.SameLine(colW * 3); imgui.TextColored(COL_HEADER, 'MARINERS (VP)');
    imgui.Separator();
    for i = 1, 6 do
        -- column 1+2: the four paired slots, then Torque / Belt (no pair)
        local baseId = BASE_SET[i];
        if baseId ~= nil then
            local bs, us = pairStates(oc, baseId, PAIR_UP[baseId]);
            itemLine(deps, baseId, bs, bs == 'better' and BETTER_NOTE or nil);
            imgui.SameLine(colW);
            itemLine(deps, PAIR_UP[baseId], us);
        else
            local exId = EXTRAS[i - 4];
            if exId ~= nil then
                itemLine(deps, exId, owned(oc, exId) and 'owned' or 'dim');
            else
                imgui.Dummy({ 0, 18 });
            end
            imgui.SameLine(colW);
            local hrId = HEAD_RING[i - 4];
            if hrId ~= nil then itemLine(deps, hrId, owned(oc, hrId) and 'owned' or 'dim');
            else imgui.Dummy({ 0, 1 }); end
        end
        -- column 3: guild GP gear (green when owned -- no glow, see Mariners)
        imgui.SameLine(colW * 2);
        local gId = GUILD_GEAR[i];
        if gId ~= nil then itemLine(deps, gId, owned(oc, gId) and 'owned' or 'dim');
        else imgui.Dummy({ 0, 1 }); end
        -- column 4: the Mariners VP set -- the ONLY armor that glows (Henrik:
        -- the real fishing end-game). Best owned tier shown; Expert Angler
        -- rides the tooltip on the pieces that carry it (Tunica/Boots).
        imgui.SameLine(colW * 3);
        local mPair = MARINERS[i];
        if mPair ~= nil then
            local showId = owned(oc, mPair[2]) and mPair[2] or mPair[1];
            itemLine(deps, showId, owned(oc, showId) and 'glow' or 'dim', expertNote(showId));
        else
            imgui.Dummy({ 0, 1 });
        end
    end
    imgui.Spacing();

    -- ---- Crooked Jones (doubloons) ----------------------------------------
    -- Its own section, not a fifth column: doubloons are a third currency
    -- beside GP and VP, and the matrix's columns ARE the currencies. Green
    -- when owned, no glow -- the glow ruling names the Mariners set
    -- specifically (2026-07-18), and this is not it. The whole Sinister Stash
    -- is listed, not just the fishing piece: the panel is where you see your
    -- doubloon balance, so it is where "what do they buy" belongs.
    imgui.TextColored(COL_HEADER, 'CROOKED JONES (doubloons)');
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Norg (H-8): trade him the day\'s three named fish for doubloons --\n'
            .. 'one lower-tier (60), one middle (40), one legendary (15), +100 for\n'
            .. 'maxing all three; fishing 20+. The Sinister Stash stalls in Norg\n'
            .. 'and Lower Jeuno are where they spend.');
    end
    imgui.Separator();
    for _, row in ipairs(JONES_SHOP) do
        local isOwned = row.id ~= nil and owned(oc, row.id);
        if row.id ~= nil then
            local note = row.gear and expertNote(row.id, 'Crooked Jones gear') or nil;
            itemLine(deps, row.id, isOwned and 'owned' or 'dim', note);
        else
            -- No id: not an item at all, so no ownership claim -- we cannot
            -- see a mount in a bag. Its art is a file (bg-wiki's icon) rather
            -- than a client resource; when the file is missing renderIcon(nil)
            -- still reserves the icon's space and SameLines, so the name keeps
            -- the same x as the rows that have art.
            local h = (row.icon ~= nil and _ftok) and filetex.handle(row.icon) or nil;
            if h ~= nil then
                imgui.Image(h, { 18, 18 });
                imgui.SameLine(0, 6);                  -- renderIcon's own spacing
            elseif deps ~= nil and type(deps.renderIcon) == 'function' then
                deps.renderIcon(nil, 18);
            end
            imgui.TextColored(COL_DIM, esc(row.n));
        end
        -- Own stops, not the matrix's: the longest name here is the Eyepatch
        -- at 18 characters, and the notes need the room the matrix spends on
        -- two more columns. Price at colW, note at colW*2.
        imgui.SameLine(colW);
        imgui.TextColored(isOwned and GREEN_OWNED or COL_TEXT, esc(comma(row.cost)));
        imgui.SameLine(colW * 2);
        imgui.TextColored(COL_DIM, esc(row.note));
    end
    imgui.Spacing();

    -- ---- rods -------------------------------------------------------------
    imgui.TextColored(COL_HEADER, 'RODS');
    imgui.SameLine(colW * 2); imgui.TextColored(COL_HEADER, 'LEGENDARY');
    imgui.Separator();
    local standard = {};
    for id, r in pairs(db.rods) do
        if (r.leg or 0) == 0 and not SPECIAL_RODS[id] then
            standard[#standard + 1] = { id = id, r = r };
        end
    end
    table.sort(standard, function(a, b)
        if (a.r.rating or 0) ~= (b.r.rating or 0) then return (a.r.rating or 0) < (b.r.rating or 0); end
        return nameOf(a.id) < nameOf(b.id);
    end);
    -- Owning a legendary rod greens the whole standard ladder ("you're
    -- awesome" cascade -- Henrik 2026-07-18: Lu Shang's/Ebisu covers them all).
    local legOwned = false;
    for id in pairs(LEG_ANY) do if owned(oc, id) then legOwned = true; break; end end
    local function rodNote(e, better)
        return string.format('%s -- size %s, durability %d%s%s', nameOf(e.id),
            (e.r.sz or 0) == 1 and 'LARGE' or 'small', e.r.maxR or 0,
            (e.r.brk or 0) ~= 0 and ', breakable' or '',
            better and '\nGreen via progression: your legendary rod covers this one.' or '');
    end
    local half = math.ceil(#standard / 2);
    for i = 1, half do
        local a = standard[i];
        local aSt = owned(oc, a.id) and 'owned' or (legOwned and 'better' or 'dim');
        itemLine(deps, a.id, aSt, rodNote(a, aSt == 'better'));
        local b = standard[i + half];
        if b ~= nil then
            imgui.SameLine(colW);
            local bSt = owned(oc, b.id) and 'owned' or (legOwned and 'better' or 'dim');
            itemLine(deps, b.id, bSt, rodNote(b, bSt == 'better'));
        end
        local lId = LEGENDARY_RODS[i];
        if lId ~= nil then
            imgui.SameLine(colW * 2);
            itemLine(deps, lId, owned(oc, lId) and 'glow' or 'dim',
                (lId == 17011) and (nameOf(lId) .. ' -- NEVER breaks')
                or (nameOf(lId) .. ' -- breakable (quest-restorable)'));
        end
    end
    for id in pairs(SPECIAL_RODS) do
        if owned(oc, id) then
            itemLine(deps, id, 'owned', nameOf(id) .. ' -- special rod');
        end
    end
    imgui.Spacing();

    -- ---- baits owned ------------------------------------------------------
    if imgui.CollapsingHeader('Baits owned') then
        local whereOf, totals = nil, nil;
        pcall(function()
            local ocm = require('dlac\\gear\\ownedcache');
            whereOf, totals = ocm.whereOf, ocm.totals();
        end);
        local CONTAINERS = { [0] = 'Inventory', 'Mog Safe', 'Storage', 'Temporary',
                             'Mog Locker', 'Mog Satchel', 'Mog Sack', 'Mog Case',
                             'Wardrobe', 'Mog Safe 2', 'Wardrobe 2', 'Wardrobe 3',
                             'Wardrobe 4', 'Wardrobe 5', 'Wardrobe 6', 'Wardrobe 7',
                             'Wardrobe 8' };
        local ids = {};
        for id in pairs(db.baits) do ids[#ids + 1] = id; end
        for id in pairs(db.customBaits or {}) do ids[#ids + 1] = id; end
        table.sort(ids, function(a, b) return nameOf(a) < nameOf(b); end);
        local any = false;
        for _, id in ipairs(ids) do
            local total = (type(totals) == 'table') and (totals[id] or 0) or 0;
            if total > 0 then
                any = true;
                itemLine(deps, id, 'owned');
                imgui.SameLine(0, 8);
                imgui.TextColored(COL_TEXT, 'x' .. total);
                if imgui.IsItemHovered() and whereOf ~= nil then
                    local parts2 = {};
                    local ok, w = pcall(whereOf, id);
                    if ok and type(w) == 'table' then
                        for cid, n in pairs(w) do
                            parts2[#parts2 + 1] = string.format('%s: %d', CONTAINERS[cid] or ('bag ' .. cid), n);
                        end
                    end
                    table.sort(parts2);
                    local catches = {};
                    for _, e in ipairs(fcalc.fishForBait(id)) do
                        if #catches < 8 then catches[#catches + 1] = (e.fish or {}).n; end
                    end
                    imgui.SetTooltip(table.concat(parts2, '\n')
                        .. (#catches > 0 and ('\ncatches: ' .. table.concat(catches, ', ')) or ''));
                end
                local b = db.baits[id];
                if b ~= nil and (b.t or 0) == 1 then
                    imgui.SameLine(0, 8);
                    imgui.TextColored(COL_DIM, '(lure -- reusable)');
                end
            end
        end
        if not any then imgui.TextColored(COL_DIM, 'no bait in any bag.'); end
    end

    -- ---- today's ventures (only where the pack has them, ADR 0035) --------
    local ventHdrOn = false;
    if _fwok and type(fw.venturesOn) == 'function' then
        pcall(function() ventHdrOn = fw.venturesOn() == true; end);
    end
    if ventHdrOn and imgui.CollapsingHeader("Today's fishing ventures") then
        if imgui.Button('!ventures fishing##fishvent') then
            if _fwok then fw.openCapture(6); end
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '!ventures fishing'); end);
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Types the command (visible in chat) and captures the reply.\nFormat unpinned until the first capture -- raw lines are kept either way.');
        end
        local lines, fresh, general = nil, false, nil;
        if _fwok then lines, fresh, general = fw.venturesFor(); end
        if lines ~= nil then
            if not fresh then imgui.TextColored(COL_WARN, 'stale (past JST midnight) -- refresh:'); end
            for _, ln in ipairs(lines) do imgui.TextColored(COL_TEXT, esc(ln)); end
            -- Captured but unparsed lines are shown here rather than swallowed:
            -- the reply wraps, and a shape we don't know yet is still an answer.
            if general ~= nil and #general > 0 then
                imgui.TextColored(COL_DIM, 'also captured:');
                for _, ln in ipairs(general) do imgui.TextColored(COL_DIM, esc(ln)); end
            end
        elseif general ~= nil and #general > 0 then
            imgui.TextColored(COL_DIM, 'captured (format not recognized yet):');
            for _, ln in ipairs(general) do imgui.TextColored(COL_TEXT, esc(ln)); end
        else
            imgui.TextColored(COL_DIM, 'nothing captured yet today.');
        end
    end

    -- ---- guild corner -----------------------------------------------------
    if imgui.CollapsingHeader("Fisherman's Guild (Port Windurst)") then
        local g = db.guild or {};
        if rank ~= nil and g.rankFish ~= nil then
            local nextFish = g.rankFish[rank + 1];
            if nextFish ~= nil then
                imgui.TextColored(COL_GOLD, esc(string.format(
                    'next rank test: trade %s to Thubu Parohren (within 2.0 of your cap)', nameOf(nextFish))));
            else
                imgui.TextColored(GREEN_OWNED, 'Expert -- the ladder is yours.');
            end
        end
        imgui.TextColored(COL_HEADER, 'GP shop');
        for _, it in ipairs(g.shop or {}) do
            local rec = (deps ~= nil and deps.lookupByName ~= nil) and deps.lookupByName(it.n) or nil;
            local have = rec ~= nil and owned(oc, rec.Id);
            imgui.TextColored(have and GREEN_OWNED or COL_TEXT,
                esc(string.format('%s -- %s GP (%s)', it.n, tostring(it.gp), it.rank)));
        end
        imgui.TextColored(COL_HEADER, 'Key items');
        for _, it in ipairs(g.kis or {}) do
            imgui.TextColored(COL_TEXT, esc(string.format('%s -- %s GP (%s)', it.n, tostring(it.gp), it.rank)));
        end
        -- The carp grind pitch is for people still ON the grind (Henrik).
        if not (owned(oc, 17386) or owned(oc, 19320)) then
            imgui.TextColored(COL_DIM, "Lu Shang's: 10,000 carp to Gallijaux/Joulet (Port San d'Oria) -- Moat Carp pay 10g, Forest Carp 15g.");
        end
    end
end

-- ---------------------------------------------------------------------------
-- The floating target window (chocoui.renderSearch's twin, 2026-07-27). Rendered
-- INDEPENDENTLY of the main box from gearui's d3d_present -- above its
-- `M.visible` return -- so it is reachable with the main window shut, which is
-- the whole point: the hobby bar opens it while you fish.
--
-- ONE draw site. Every other surface (the panel's Target button, the hobby bar's
-- target name, /dl fish find) only sets `target.open[1]` through M.openTarget.
-- A second Begin() on this window name in the same frame would append a second
-- copy of the body into it -- the search drawn twice, ids colliding, the box
-- fighting itself over one buffer.
--
-- `End` is source-paired with `Begin` (floatgear's rule); a body that errors
-- mid-frame is recovered by ImGui at frame end, and gearui's pcall keeps the
-- style stack clean. Guarded: no window API -> nothing drawn.
-- ---------------------------------------------------------------------------
function M.renderSearch(deps)
    if type(imgui.Begin) ~= 'function' or type(imgui.End) ~= 'function' then return; end
    if not target.open[1] then return; end
    if type(imgui.SetNextWindowSize) == 'function' then
        -- Wide enough that the spot list keeps roughly the column widths it had
        -- in the panel; ImGui remembers a resize from here on (imgui.ini).
        imgui.SetNextWindowSize({ 760, 520 }, (ImGuiCond_FirstUseEver or 0));
    end
    local shown = imgui.Begin('Fishing -- Target fish###dlac_fish_target', target.open,
                              (ImGuiWindowFlags_NoCollapse or 0));
    if shown then
        local availW = imgui.GetContentRegionAvail();
        if type(availW) ~= 'number' then availW = nil; end
        M.renderTargetBody(deps, availW);
    end
    imgui.End();
end

return M;
