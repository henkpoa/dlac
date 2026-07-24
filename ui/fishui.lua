-- fishui.lua -- the fishing panel (Automations -> "Auto Fish Set").
-- docs/design/fishing-gear.md #2. helmui's sibling: rendered from
-- automationsui's detail delegation with the SAME deps table.
-- Coverage/status live ABOVE the imgui guard so the
-- headless tests reach them (improvement over helmui, whose guard hides all).
--
-- Sections: status line (skill / GP / VP) -> gear matrix (BASE / ANGLER'S /
-- GUILD / MARINERS -- the VP set, ids interleaved with HELM's Plain block) ->
-- rods (standard / legendary) -> target fish (search, ISOLATION rows, rod
-- verdicts from the server's own fail math) -> baits owned (per-container) ->
-- today's ventures (0x017 capture) -> guild corner (GP shop, rank ladder).

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
-- NOT displayed (Henrik 2026-07-18): Halieutica 20945 + Brigands Eyepatch 28443
-- (nothing in-game mentions them) and the legendary-rod +1s 19320/19321 (look
-- unobtainable on CatsEyeXI). fishdb keeps their data and autoPick still
-- honours one if it ever lands in a bag -- they are only invisible here.
local LEGENDARY_RODS = { 17386, 17011 };                   -- Lu Shang's, Ebisu
local LEG_ANY = { [17386] = true, [19320] = true, [17011] = true, [19321] = true };
local SPECIAL_RODS = { [17012] = true, [17013] = true, [19319] = true };  -- Judge's, Basket, MMM
local NO_SUGGEST = { [17012] = true, [17013] = true, [19319] = true,      -- specials...
                     [19320] = true, [19321] = true };     -- ...and the undisplayed +1s

local ADVANCED = {};   -- any of these owned = coverage level 3
for _, id in ipairs(GUILD_GEAR) do ADVANCED[id] = true; end
for _, pair in ipairs(MARINERS) do ADVANCED[pair[1]] = true; ADVANCED[pair[2]] = true; end
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

local _fwok, fw = pcall(require, 'dlac\\feature\\fishwatch');
_fwok = _fwok and type(fw) == 'table';

-- Display name for an id: live API name from fishdb (catalog-identical), else
-- the client resource name, else the fishdb SQL name, else the id.
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
    _names[id] = n or ('#' .. tostring(id));
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
        -- must not lose to the generic stat card)
        if note ~= nil then
            imgui.SetTooltip(note);
        else
            local rec = (deps ~= nil and deps.lookupByName ~= nil) and deps.lookupByName(name) or nil;
            if rec ~= nil and deps ~= nil and type(deps.itemTooltip) == 'function' then
                pcall(deps.itemTooltip, rec);
            else
                imgui.SetTooltip(name);
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

-- Expert Angler tooltip for the Mariners pieces that carry the custom mods
-- (identified 2026-07-18 via bg-wiki CatsEyeXI_Content/Ventures: 2004 =
-- Fatigue Limit +%, 2005 = Golden Arrow Rate +% -- values match the live DB).
local function expertNote(id)
    if not _fcok then return nil; end
    local db = fcalc.db(); if db == nil then return nil; end
    local g = (db.gearBonus or {})[id];
    if g == nil or (g.cx4 == nil and g.cx5 == nil) then return nil; end
    local parts = {};
    if g.cx4 ~= nil then parts[#parts + 1] = string.format('Fatigue Limit +%d%%', g.cx4); end
    if g.cx5 ~= nil then parts[#parts + 1] = string.format('Golden Arrow Rate +%d%%', g.cx5); end
    return string.format('Expert Angler: %s\n(+ Fishing skill -- CatsEyeXI venture gear)',
        table.concat(parts, ', '));
end

-- section state
local sel = { q = { '' }, id = nil, showAllIso = false };
local _reqAt = 0;

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
    local vp = _fwok and fw.venturePoints() or nil;
    parts[#parts + 1] = 'VP ' .. (vp ~= nil and tostring(vp) or '?');
    imgui.TextColored(COL_GOLD, esc(table.concat(parts, '   |   ')));
    -- the bar toggle is panel chrome, so it rides the status row (the target
    -- row below carries Make target now and needs its width)
    if _fwok then
        imgui.SameLine(0, 16);
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
            sel.id = nil;             -- the panel's view too: a clean start
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
        sel.id = tgtId;   -- panel opens on the active target
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
        imgui.TextColored(COL_DIM, 'spots + baits -- best isolation first, click one to fish it:');
        local iso = fcalc.isolationFor(fid);
        if #iso == 0 then
            imgui.TextColored(COL_DIM, 'no known catch spot (quest/contest-gated?).');
        else
            local nShow = sel.showAllIso and #iso or math.min(#iso, 10);
            for i = 1, nShow do
                local row = iso[i];
                imgui.PushID('iso' .. i);
                if row.clean then imgui.TextColored(COL_GOLD, '[ISOLATED]');
                else imgui.TextColored(COL_DIM, string.format('(%d rivals)', #row.others)); end
                if not row.clean and imgui.IsItemHovered() then
                    local names = {};
                    for j = 1, math.min(#row.others, 8) do
                        names[#names + 1] = (db.fish[row.others[j]] or {}).n or ('#' .. row.others[j]);
                    end
                    imgui.SetTooltip('also bites here: ' .. table.concat(names, ', '));
                end
                imgui.SameLine(128);   -- themed font ~9.5px/char: '[ISOLATED]' needs the room
                local place = row.zoneName .. (row.areaName ~= nil and (' -- ' .. row.areaName) or '');
                imgui.TextColored(COL_TEXT, esc(place));
                imgui.SameLine(math.floor(availW * 0.55));
                local powerDots = string.rep('*', row.power or 1);
                if imgui.Selectable(string.format('%s %s##bait%d', row.baitName, powerDots, i)) then
                    if _fwok then fw.setTarget(fid, row.bait); end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip(string.format('bait: %s (affinity %d/3)%s\nclick: make %s the target with THIS bait',
                        row.baitName, row.power or 0,
                        owned(oc, row.bait) and '  -- OWNED' or '  -- not in your bags',
                        f.n));
                end
                if row.mob ~= nil then
                    imgui.SameLine(0, 8);
                    imgui.TextColored(COL_WARN, '[!]');
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip(string.format('a MONSTER can take this bait here: %s%s',
                            row.mob.n or '?', (row.mob.nm or 0) ~= 0 and ' (NM)' or ''));
                    end
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

    -- ---- today's ventures -------------------------------------------------
    if imgui.CollapsingHeader("Today's fishing ventures") then
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

return M;
