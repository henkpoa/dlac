--[[
    dlac/chocoui.lua -- the Chocobo riding-gear panel (docs/design/chocobo-gear.md).

    Rendered inside automationsui's Automations detail (auto.view == 'choco');
    its OWN module (the helmui/fishui pattern -- keeps automationsui's local
    budget clear). automationsui pcall-requires it at render time and hands over
    its deps table (ownedList / lookupByName / ownedCounts / haveInBags /
    renderIcon / itemTooltip / playerJob -- the gearui init injection).

    The simplest of the four idle-gear siblings: one on/off switch, a fixed
    "best riding-time set" (no category, no target), and a top section that
    reports the TOTAL riding time. The coverage/status helpers sit ABOVE the
    imgui guard on purpose, so the Automations list row works headless / before
    any render (the fishui/ammoui contract).
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- Pure helpers (ABOVE the imgui guard): the best owned riding-time piece per
-- slot, the total riding time, and the coverage level for the Automations list
-- row. Everything reads through the injected deps -- no imgui, no Ashita -- so
-- these run headless and before any render.
-- ---------------------------------------------------------------------------

-- The six slots the Chocobo set dresses (issue #95). Main is the Chocobo Wand.
M.SLOT_ORDER = { 'Main', 'Neck', 'Body', 'Hands', 'Legs', 'Feet' };
local CHOCO_SLOTS = { Main = true, Neck = true, Body = true,
                      Hands = true, Legs = true, Feet = true };

-- The base whistle is 30 minutes (1800 s); each ChocoboRidingTime point adds
-- one minute (the server computes duration as 1800 + mod*60 seconds at whistle
-- time). So total minutes = 30 + summed ChocoboRidingTime over the worn set.
M.BASE_MINUTES = 30;

-- Best owned+equippable riding piece per slot -> { [SlotLabel] = { name, ride, id } }.
-- Reads the SAME facts the engine's manifest builder does (owned records carry
-- catalog Stats after enrichment; ChocoboRidingTime is a flat Misc stat, never
-- level-scaled, so rec.Stats is exact) and applies the same in-bags gate, so
-- the panel lists what the engine would actually equip. Safe with nil deps.
function M.bestPerSlot(deps)
    local best = {};
    if deps == nil or type(deps.ownedList) ~= 'function' then return best; end
    local ok, list = pcall(deps.ownedList);
    if not ok or type(list) ~= 'table' then return best; end
    for _, rec in ipairs(list) do
        local sl = tostring(rec.Slot or '');
        local st = (type(rec.Stats) == 'table') and rec.Stats or {};
        local ride = tonumber(st.ChocoboRidingTime) or 0;
        local inBags = (type(deps.haveInBags) ~= 'function') or deps.haveInBags(rec);
        if CHOCO_SLOTS[sl] == true and ride > 0 and inBags and rec.Name ~= nil then
            local cur = best[sl];
            if cur == nil or ride > cur.ride
               or (ride == cur.ride and tostring(rec.Name) < cur.name) then
                best[sl] = { name = rec.Name, ride = ride, id = rec.Id };
            end
        end
    end
    return best;
end

-- Total riding time in MINUTES for the best owned set (30 base + summed
-- ChocoboRidingTime), plus the number of the six slots covered.
function M.totalMinutes(deps)
    local best = M.bestPerSlot(deps);
    local sum, slots = 0, 0;
    for _, p in pairs(best) do sum = sum + (p.ride or 0); slots = slots + 1; end
    return M.BASE_MINUTES + sum, slots, best;
end

M.txt = { [0] = 'nothing applicable', 'riding gear started',
          'most slots covered', 'FULL SET -- awesome' };
M.maxLevel = 3;

-- Coverage level (0..3) for the levelColor ramp: 0 nothing, 1 = a piece or two,
-- 2 = 3..5 of the six slots, 3 = the full six-slot set.
function M.level(deps)
    local _, slots = M.totalMinutes(deps);
    if slots >= #M.SLOT_ORDER then return 3; end
    if slots >= 3 then return 2; end
    if slots >= 1 then return 1; end
    return 0;
end

-- level + display text for the Automations list row: the coverage label with
-- the total riding time appended once anything is owned.
function M.status(deps)
    local minutes, slots = M.totalMinutes(deps);
    local level = 0;
    if slots >= #M.SLOT_ORDER then level = 3;
    elseif slots >= 3 then level = 2;
    elseif slots >= 1 then level = 1; end
    local txt = M.txt[level] or '';
    if level > 0 then txt = string.format('%s (ride %d min)', txt, minutes); end
    return level, txt;
end

-- ---------------------------------------------------------------------------
-- Dig-guide scaffold helpers (issue #97) -- ABOVE the imgui guard so they run
-- headless. The rank state (for the panel AND the tab views' grey-out), the
-- live Vana'diel clock read, and the general dig-success figure.
-- ---------------------------------------------------------------------------

-- The resolved dig-rank state -- the ONE door the panel and the (later) tab
-- views read for grey-out. Delegates to chocowatch (the state owner); a
-- fail-soft default keeps the panel alive if the watcher is unavailable.
-- { rank, source, exact, label, sourceLabel }; exact = true only server-reported.
function M.rankState()
    local cwok, cw = pcall(require, 'dlac\\feature\\chocowatch');
    if cwok and type(cw) == 'table' and type(cw.rankState) == 'function' then
        local ok, rs = pcall(cw.rankState);
        if ok and type(rs) == 'table' then return rs; end
    end
    return { rank = 0, source = 'manual', exact = false, label = 'Amateur', sourceLabel = 'manual' };
end

-- The dig-rank ladder labels (0..10, Amateur..Expert) -- the shipped data wins,
-- digrank's fallback covers a missing table. Returns a 0-indexed table.
function M.rankLadder()
    local dcok, dc = pcall(require, 'dlac\\feature\\digcalc');
    if dcok and type(dc) == 'table' and type(dc.db) == 'function' then
        local db = nil; pcall(function() db = dc.db(); end);
        if type(db) == 'table' and type(db.ranks) == 'table' then return db.ranks; end
    end
    local drok, dr = pcall(require, 'dlac\\feature\\digrank');
    if drok and type(dr) == 'table' and type(dr.RANKS) == 'table' then return dr.RANKS; end
    return {};
end

-- The live Vana'diel clock for the guide header: { day, dayElement, weather,
-- weatherElement, moon = { name, percent, waxing, age }, vday }. Every field is
-- read through a guarded nativedata call and degrades to nil (never errors) when
-- the client memory is unreadable -- so the header renders gracefully with
-- whatever it could read (issue #97: "graceful when weather is unavailable").
function M.clock()
    local out = {};
    local ndok, nd = pcall(require, 'dlac\\feature\\nativedata');
    if not ndok or type(nd) ~= 'table' then return out; end
    pcall(function()
        local env = (type(nd.GetEnvironment) == 'function') and nd.GetEnvironment() or {};
        out.day            = env.Day;
        out.dayElement     = env.DayElement;
        out.weather        = env.Weather;
        out.weatherElement = env.WeatherElement;
        -- double weather yields the cluster, not the crystal (nativedata spells
        -- it "<Element> x2"); a missing read leaves it nil = single (crystal).
        out.doubleWeather  = (type(env.Weather) == 'string') and (env.Weather:find('x2', 1, true) ~= nil) or false;
        local ts = (type(nd.timestamp) == 'function') and nd.timestamp() or nil;
        if type(ts) == 'table' and ts.day ~= nil then
            out.vday = ts.day;
            local vmok, vm = pcall(require, 'dlac\\feature\\vanamoon');
            if vmok and type(vm) == 'table' then out.moon = vm.phase(ts.day); end
        end
    end);
    return out;
end

-- The general dig-success figure for a rank + moon percent: the typical per-dig
-- success across the enabled zones (digcalc.averageSuccess). Returns (fraction,
-- zoneCount) or nil when the moon is unknown or the zone data is not yet
-- generated -- the panel says which, never a fake number.
function M.generalSuccess(rank, moonPercent)
    if moonPercent == nil then return nil; end
    local dcok, dc = pcall(require, 'dlac\\feature\\digcalc');
    if not dcok or type(dc) ~= 'table' or type(dc.averageSuccess) ~= 'function' then return nil; end
    local mu = dc.moonMult(moonPercent);
    local avg, n = dc.averageSuccess(rank or 0, mu);
    return avg, n;
end

-- The by-area zone picker's source (issue #98): every enabled zone as
-- { { id, n }, ... } sorted by name. Empty when the per-zone data is not yet
-- generated -- the panel then says so plainly.
function M.zoneList()
    local dcok, dc = pcall(require, 'dlac\\feature\\digcalc');
    if not dcok or type(dc) ~= 'table' or type(dc.zones) ~= 'function' then return {}; end
    local ok, list = pcall(dc.zones);
    return (ok and type(list) == 'table') and list or {};
end

-- The rank number out of a resolved rank state (or a bare number). Amateur (0)
-- floor keeps the odds/grey-out queries honest when the state is unreadable.
local function rankOf(rankState)
    if type(rankState) == 'table' then return tonumber(rankState.rank) or 0; end
    return tonumber(rankState) or 0;
end

-- The whole by-area view for one zone, composed from the pure engine + rank
-- brain so the tab renders (and the tests assert) headless. Returns:
--   { name, success,
--     pools = { { pool, S, items = { <odds row> + gate + reqLabel }, ... } },  -- POOL order
--     conditionals = { <conditional row> + gate + reqLabel, ... } }
-- Each pool's items are sorted by (2) PER DIG descending (issue #98 AC), name as
-- the tiebreak so the order never flickers; every row carries digrank.gate's
-- grey-out verdict ('ok'/'locked'/'dimmed') and the requirement's rank label.
-- nil when the zone is unknown or the per-zone data is absent (fail soft).
function M.areaRows(zoneId, rankState, clock)
    local dcok, dc = pcall(require, 'dlac\\feature\\digcalc');
    if not dcok or type(dc) ~= 'table' then return nil; end
    local drok, dr = pcall(require, 'dlac\\feature\\digrank');
    if not drok or type(dr) ~= 'table' then dr = nil; end
    clock = clock or {};
    local moonPct = (type(clock.moon) == 'table') and clock.moon.percent or clock.moonPercent;
    local rank = rankOf(rankState);
    local mu = dc.moonMult(moonPct);
    local zo = dc.zoneOdds(zoneId, rank, mu);
    if type(zo) ~= 'table' then return nil; end
    local ladder = M.rankLadder();
    local function gate(req) return dr and dr.gate(req, rankState) or 'ok'; end
    local function reqLabel(req) return dr and dr.label(req, ladder) or ('rank ' .. tostring(req)); end

    local out = { name = zo.name, success = zo.success, pools = {}, conditionals = {} };
    for _, pe in ipairs(zo.pools or {}) do
        local items = (type(pe.odds) == 'table') and pe.odds.items or {};
        table.sort(items, function(a, b)
            if (a.perDig or 0) ~= (b.perDig or 0) then return (a.perDig or 0) > (b.perDig or 0); end
            return tostring(a.n) < tostring(b.n);
        end);
        for _, it in ipairs(items) do
            it.gate = gate(it.rank);
            it.reqLabel = reqLabel(it.rank);
        end
        out.pools[#out.pools + 1] = { pool = pe.pool, S = (pe.odds or {}).S or 0, items = items };
    end

    if type(dc.conditionalDrops) == 'function' then
        local conds = dc.conditionalDrops(zoneId, rank, {
            dayElement = clock.dayElement, weatherElement = clock.weatherElement,
            doubleWeather = clock.doubleWeather, moonPercent = moonPct,
        });
        for _, c in ipairs(conds or {}) do
            c.gate = gate(c.minRank);
            c.reqLabel = reqLabel(c.minRank);
            out.conditionals[#out.conditionals + 1] = c;
        end
    end
    return out;
end

-- The by-item search source (issue #99): every diggable item (pool items PLUS
-- the conditional crystals/rocks/ores) as digcalc.itemIndex rows, sorted by
-- name. Empty when the per-zone data is not yet generated (the panel says so).
function M.itemList()
    local dcok, dc = pcall(require, 'dlac\\feature\\digcalc');
    if not dcok or type(dc) ~= 'table' or type(dc.itemIndex) ~= 'function' then return {}; end
    local ok, list = pcall(dc.itemIndex);
    return (ok and type(list) == 'table') and list or {};
end

-- The whole by-item view for one selected item (issue #99): every zone + pool it
-- drops from, priced for the current rank + moon, each row stamped with
-- digrank.gate's grey-out verdict + the requirement's rank label -- the SAME
-- grey-out the by-area tab uses (the "never lie" rule). `entry` is an itemList
-- row. nil when the item/db is unresolvable (fail soft).
function M.itemRows(entry, rankState, clock)
    local dcok, dc = pcall(require, 'dlac\\feature\\digcalc');
    if not dcok or type(dc) ~= 'table' or type(dc.itemSources) ~= 'function' then return nil; end
    local drok, dr = pcall(require, 'dlac\\feature\\digrank');
    if not drok or type(dr) ~= 'table' then dr = nil; end
    clock = clock or {};
    local moonPct = (type(clock.moon) == 'table') and clock.moon.percent or clock.moonPercent;
    local rank = rankOf(rankState);
    local mu = dc.moonMult(moonPct);
    local view = dc.itemSources(entry, rank, mu, clock);
    if type(view) ~= 'table' then return nil; end
    local ladder = M.rankLadder();
    local function gate(req) return dr and dr.gate(req, rankState) or 'ok'; end
    local function reqLabel(req) return dr and dr.label(req, ladder) or ('rank ' .. tostring(req)); end
    for _, s in ipairs(view.sources or {}) do
        local req = (s.req ~= nil) and s.req or s.minRank;
        s.gate = gate(req);
        s.reqLabel = reqLabel(req);
    end
    view.reqLabel = reqLabel(view.minRank);
    view.gate = gate(view.minRank);
    return view;
end

-- ---------------------------------------------------------------------------
-- The detail view (automationsui: auto.view == 'choco'). Everything below the
-- imgui guard: headless require returns the pure stub above.
-- ---------------------------------------------------------------------------
local _iok, imgui = pcall(require, 'imgui');
if not _iok then return M; end

local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_DIM    = { 0.55, 0.55, 0.55, 1.00 };
local COL_TEXT   = { 0.70, 0.70, 0.70, 1.00 };
local COL_GOLD   = { 0.95, 0.85, 0.45, 1.00 };
local GREEN_OWNED = { 0.45, 0.90, 0.45, 1.0 };

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

-- By-area tab state (issue #98): the zone-search buffer + the picked zone.
-- Session-only, panel-local -- selecting a zone is a view choice, not persisted.
local area = { q = { '' }, zoneId = nil };

-- By-item tab state (issue #99): the item-search buffer + the selected index
-- entry. Session-only, panel-local like the by-area state above.
local byitem = { q = { '' }, sel = nil };

-- The cross-link one-shot (issue #99): a zone clicked in the By item results
-- focuses the By area tab on it. `focusArea` is consumed by the next tab-bar
-- pass (the uihost.selectTab idiom, applied to this panel's own tab bar).
local guide = { focusArea = false };

-- Jump to the By area view focused on `zoneId`: point the by-area state at it,
-- clear its search so the picked zone shows, and request the tab switch.
local function jumpToArea(zoneId)
    area.zoneId = zoneId;
    area.q[1] = '';
    guide.focusArea = true;
end

-- A probability as a compact percent: more decimals for the tiny per-dig odds so
-- a rare item never reads as a flat "0%".
local function pct(x)
    local v = (tonumber(x) or 0) * 100;
    if v <= 0 then return '0%'; end
    if v < 0.1 then return string.format('%.2f%%', v); end
    if v < 10  then return string.format('%.1f%%', v); end
    return string.format('%.0f%%', v);
end

-- One diggable-item row: icon + name + rank requirement + the two odds, greyed by
-- the rank gate. 'locked' (over a MEASURED rank) and 'dimmed' (over an ESTIMATE)
-- both dim the row, but only the estimate spells out "you're at least Y" -- the
-- "never lie" rule (issue #97 digrank.gate) rendered.
local function renderDigRow(deps, it, rs)
    local col = (it.gate == 'ok') and COL_TEXT or COL_DIM;
    imgui.Dummy({ 6, 0 }); imgui.SameLine(0, 0);
    if it.id ~= nil and deps ~= nil and type(deps.renderIcon) == 'function' then
        deps.renderIcon(it.id, 16); imgui.SameLine(0, 4);
    end
    imgui.TextColored(col, esc(tostring(it.n or '?')));
    if imgui.IsItemHovered() and it.id ~= nil and deps ~= nil and type(deps.lookupById) == 'function' then
        local rec = deps.lookupById(it.id);
        if rec ~= nil and type(deps.itemTooltip) == 'function' then pcall(deps.itemTooltip, rec); end
    end
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, string.format('[%s]', it.reqLabel or ('rank ' .. tostring(it.rank))));
    imgui.SameLine(0, 8);
    imgui.TextColored(col, esc(string.format('hit %s  dig %s', pct(it.onHit), pct(it.perDig))));
    if it.gate == 'locked' then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL_DIM, string.format('-- locked: needs %s', it.reqLabel or '?'));
    elseif it.gate == 'dimmed' then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL_DIM, string.format("-- needs %s, you're at least %s",
            it.reqLabel or '?', (rs and rs.label) or '?'));
    end
end

-- One conditional-drop row (weather crystal / day rock / elemental ore): the item
-- + its ~chance + the spelled-out condition + an active/inactive flag against the
-- live clock, greyed by the rank gate like an ordinary row.
local function renderCondRow(deps, c, rs)
    local col = (c.gate == 'ok') and COL_TEXT or COL_DIM;
    imgui.Dummy({ 6, 0 }); imgui.SameLine(0, 0);
    if c.id ~= nil and deps ~= nil and type(deps.renderIcon) == 'function' then
        deps.renderIcon(c.id, 16); imgui.SameLine(0, 4);
    end
    imgui.TextColored(col, esc(tostring(c.n or '?')));
    if imgui.IsItemHovered() and c.id ~= nil and deps ~= nil and type(deps.lookupById) == 'function' then
        local rec = deps.lookupById(c.id);
        if rec ~= nil and type(deps.itemTooltip) == 'function' then pcall(deps.itemTooltip, rec); end
    end
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, esc(string.format('~%d%%', tonumber(c.chance) or 0)));
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, esc('when ' .. tostring(c.condition or '')));
    imgui.SameLine(0, 8);
    if c.active then
        imgui.TextColored(GREEN_OWNED, '[active now]');
    elseif not c.clockActive then
        imgui.TextColored(COL_DIM, '[inactive: condition not met]');
    elseif c.gate == 'locked' then
        imgui.TextColored(COL_DIM, string.format('[needs %s]', c.reqLabel or '?'));
    else
        imgui.TextColored(COL_DIM, string.format("[needs %s, you're at least %s]",
            c.reqLabel or '?', (rs and rs.label) or '?'));
    end
end

-- The By-area tab: a searchable zone dropdown -> that zone's diggable items,
-- grouped by pool with rank + the two odds, then the conditional drops flagged
-- against the live clock. rs = the resolved rank state, clk = the live clock.
function M.renderByArea(deps, rs, clk)
    local zones = M.zoneList();
    if #zones == 0 then
        imgui.TextColored(COL_DIM, 'no per-zone dig data yet -- run gen_digdata.py (maintainer) to light this up.');
        return;
    end

    -- searchable dropdown: an InputText filter atop the zone Selectables (the
    -- fishui pattern -- imgui has no native searchable combo here).
    local curName = nil;
    for _, z in ipairs(zones) do if z.id == area.zoneId then curName = z.n; end end
    imgui.TextColored(COL_TEXT, 'Zone:');
    imgui.SameLine(0, 6);
    imgui.PushItemWidth(240);
    if imgui.BeginCombo('##chocozone', curName or 'pick a zone') then
        imgui.InputText('##chocozonesearch', area.q, 48);
        local needle = tostring(area.q[1] or ''):lower();
        for _, z in ipairs(zones) do
            local nm = tostring(z.n or '');
            if needle == '' or nm:lower():find(needle, 1, true) then
                if imgui.Selectable(string.format('%s##z%d', esc(nm), z.id), z.id == area.zoneId) then
                    area.zoneId = z.id;
                end
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();

    if area.zoneId == nil then
        imgui.TextColored(COL_DIM, 'Pick a zone to see everything diggable there.');
        return;
    end

    local rows = M.areaRows(area.zoneId, rs, clk);
    if type(rows) ~= 'table' then
        imgui.TextColored(COL_DIM, 'no dig data for that zone.');
        return;
    end

    imgui.Spacing();
    imgui.TextColored(COL_DIM, 'hit = share of a successful pull;  dig = absolute chance per attempt.');
    if type(rows.success) == 'number' then
        imgui.TextColored(COL_HEADER, 'A dig here yields something:');
        imgui.SameLine(0, 6);
        imgui.TextColored(COL_GOLD, esc(pct(rows.success)));
        imgui.SameLine(0, 6);
        imgui.TextColored(COL_DIM, string.format('(at %s + this moon)', (rs and rs.label) or 'your rank'));
    end
    imgui.Spacing();

    for _, pe in ipairs(rows.pools) do
        imgui.TextColored(COL_HEADER, string.format('%s pool', tostring(pe.pool)));
        imgui.SameLine(0, 8);
        imgui.TextColored(COL_DIM, esc(string.format('(yields something %s)', pct(pe.S))));
        if #pe.items == 0 then
            imgui.TextColored(COL_DIM, '  (nothing diggable here)');
        end
        for _, it in ipairs(pe.items) do renderDigRow(deps, it, rs); end
        imgui.Spacing();
    end

    -- conditional crystal/rock/ore drops -- their own clearly marked group.
    imgui.TextColored(COL_HEADER, 'Conditional drops');
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, '(weather crystals, day rocks, elemental ores -- the Regular pool mixes these in)');
    if #rows.conditionals == 0 then
        imgui.TextColored(COL_DIM, '  (none listed for this zone)');
    end
    for _, c in ipairs(rows.conditionals) do renderCondRow(deps, c, rs); end
end

-- One by-item POOL source row: a clickable zone (the cross-link), the pool, the
-- rank requirement + the two odds, greyed by the rank gate exactly like a by-area
-- row. Clicking the zone jumps to the By area view focused on it (issue #99 AC).
local function renderItemPoolRow(deps, s, rs)
    local col = (s.gate == 'ok') and COL_TEXT or COL_DIM;
    imgui.Dummy({ 6, 0 }); imgui.SameLine(0, 0);
    if imgui.Button(string.format('%s##bisrc%s_%s', esc(tostring(s.zoneName or '?')),
                    tostring(s.zoneId), tostring(s.pool))) then
        jumpToArea(s.zoneId);
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Jump to this zone in the By area tab.'); end
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_HEADER, string.format('%s pool', tostring(s.pool)));
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, string.format('[%s]', s.reqLabel or ('rank ' .. tostring(s.req))));
    imgui.SameLine(0, 8);
    imgui.TextColored(col, esc(string.format('hit %s  dig %s', pct(s.onHit), pct(s.perDig))));
    if s.gate == 'locked' then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL_DIM, string.format('-- locked: needs %s', s.reqLabel or '?'));
    elseif s.gate == 'dimmed' then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL_DIM, string.format("-- needs %s, you're at least %s",
            s.reqLabel or '?', (rs and rs.label) or '?'));
    end
end

-- The By-item tab (issue #99): a fuzzy item search -> the matching diggable
-- items (crystals/rocks/ores included) -> the selected item's every zone + pool
-- with rank + the two odds, greyed by the rank gate, plus the item<->area
-- cross-link. rs = the resolved rank state, clk = the live clock.
function M.renderByItem(deps, rs, clk)
    local index = M.itemList();
    if #index == 0 then
        imgui.TextColored(COL_DIM, 'no per-zone dig data yet -- run gen_digdata.py (maintainer) to light this up.');
        return;
    end

    imgui.TextColored(COL_TEXT, 'Item:');
    imgui.SameLine(0, 6);
    imgui.PushItemWidth(240);
    imgui.InputText('##chocoitemsearch', byitem.q, 48);
    imgui.PopItemWidth();
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, 'type part of a name -- crystals, rocks and ores are in here too.');

    -- the match list: items whose name contains the needle. Shown only while
    -- searching; capped so a one-letter needle never floods the panel.
    local needle = tostring(byitem.q[1] or ''):lower();
    if needle ~= '' then
        local shown, CAP = 0, 40;
        for _, e in ipairs(index) do
            if tostring(e.n):lower():find(needle, 1, true) then
                shown = shown + 1;
                if shown <= CAP then
                    local sel = (byitem.sel ~= nil and byitem.sel.key == e.key);
                    if imgui.Selectable(string.format('%s##bi_%s', esc(tostring(e.n)), tostring(e.key)), sel) then
                        byitem.sel = e;
                    end
                end
            end
        end
        if shown == 0 then
            imgui.TextColored(COL_DIM, '  (no diggable item matches)');
        elseif shown > CAP then
            imgui.TextColored(COL_DIM, string.format('  (+%d more -- refine the search)', shown - CAP));
        end
        imgui.Spacing();
    end

    if byitem.sel == nil then
        imgui.TextColored(COL_DIM, 'Search an item, then pick it to see every zone + pool it drops from.');
        return;
    end

    local view = M.itemRows(byitem.sel, rs, clk);
    if type(view) ~= 'table' then
        imgui.TextColored(COL_DIM, 'no dig data for that item.');
        return;
    end

    -- the selected item header: icon + name + its rank requirement.
    imgui.Spacing();
    if view.id ~= nil and deps ~= nil and type(deps.renderIcon) == 'function' then
        deps.renderIcon(view.id, 18); imgui.SameLine(0, 6);
    end
    imgui.TextColored(COL_GOLD, esc(tostring(view.n or '?')));
    if imgui.IsItemHovered() and view.id ~= nil and deps ~= nil and type(deps.lookupById) == 'function' then
        local rec = deps.lookupById(view.id);
        if rec ~= nil and type(deps.itemTooltip) == 'function' then pcall(deps.itemTooltip, rec); end
    end
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, string.format('needs %s', view.reqLabel or ('rank ' .. tostring(view.minRank))));
    imgui.Spacing();
    imgui.TextColored(COL_DIM, 'hit = share of a successful pull;  dig = absolute chance per attempt.');
    imgui.TextColored(COL_DIM, 'Click a zone to jump to its By area view.');
    imgui.Spacing();

    if view.kind == 'conditional' then
        -- the shared condition line (weather crystal / day rock / elemental ore),
        -- flagged active/inactive against the live clock, greyed by the rank gate.
        imgui.TextColored(COL_HEADER, 'Conditional drop');
        imgui.SameLine(0, 8);
        imgui.TextColored(COL_DIM, esc(string.format('~%d%% when %s',
            tonumber(view.chance) or 0, tostring(view.condition))));
        imgui.SameLine(0, 8);
        if view.active then
            imgui.TextColored(GREEN_OWNED, '[active now]');
        elseif not view.clockActive then
            imgui.TextColored(COL_DIM, '[inactive: condition not met]');
        elseif view.gate == 'locked' then
            imgui.TextColored(COL_DIM, string.format('[needs %s]', view.reqLabel or '?'));
        else
            imgui.TextColored(COL_DIM, string.format("[needs %s, you're at least %s]",
                view.reqLabel or '?', (rs and rs.label) or '?'));
        end
        imgui.Spacing();

        if view.allZones then
            -- crystals / rocks drop in EVERY digging zone -- a note beats 26
            -- identical clickable rows; the By area tab prices any single zone.
            imgui.TextColored(COL_TEXT, string.format(
                'Diggable in any of the %d digging zones -- open By area to price a specific one.',
                #view.sources));
        else
            -- ores are a specific 9-zone set -- list them as cross-link buttons.
            imgui.TextColored(COL_TEXT, 'Diggable in these elemental-ore zones (click to jump):');
            for _, s in ipairs(view.sources) do
                imgui.Dummy({ 6, 0 }); imgui.SameLine(0, 0);
                if imgui.Button(string.format('%s##biore%s', esc(tostring(s.zoneName or '?')), tostring(s.zoneId))) then
                    jumpToArea(s.zoneId);
                end
            end
        end
        return;
    end

    -- a pool item: every zone + pool it drops from, best per-dig first.
    if #view.sources == 0 then
        imgui.TextColored(COL_DIM, '  (not found in any zone pool)');
    end
    for _, s in ipairs(view.sources) do renderItemPoolRow(deps, s, rs); end
end

-- Begin one of this panel's guide tabs, forcing selection when the cross-link
-- asked for it (the uihost.selectTab idiom). Probe-don't-assume (hard rule 2):
-- a binding without the 3-arg BeginTabItem / the flag global just renders
-- normally -- the jump is dropped, never a crash.
local function beginGuideTab(label, forceSel)
    if forceSel then
        local ok, o = pcall(imgui.BeginTabItem, label, nil, ImGuiTabItemFlags_SetSelected or 2);
        if ok then return o == true; end
    end
    return imgui.BeginTabItem(label);
end

function M.render(deps, availW)
    local cwok, cw = pcall(require, 'dlac\\feature\\chocowatch');
    cwok = cwok and type(cw) == 'table';

    imgui.TextColored(COL_HEADER, 'Chocobo');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_TEXT, 'wears your best riding-time gear ON IDLE ONLY -- equip it before you whistle.');

    -- The on/off switch: session-only OFF at login (the craftstate rule). Reuse
    -- craftbar's pill (the helmui precedent) so every switch looks the same.
    local on = cwok and cw.isEnabled();
    imgui.TextColored(COL_TEXT, 'Set Chocobo Idle:');
    imgui.SameLine(0, 6);
    local cbok, craftbar = pcall(require, 'dlac\\ui\\craftbar');
    local pill = (cbok and type(craftbar) == 'table' and type(craftbar.onOffSwitch) == 'function')
        and craftbar.onOffSwitch or nil;
    local IDLE_ON  = 'Chocobo idle set is ON -- your riding gear stays on while idle.\nStarts OFF each session; click to turn off.';
    local IDLE_OFF = 'Wears your best riding-time gear whenever you are idle, until turned off.\nStarts OFF each session (off after relog).';
    if pill ~= nil then
        if pill(on, 'chocoidle', IDLE_ON, IDLE_OFF) and cwok then cw.setEnabled(not on); end
    else
        if imgui.Button((on and 'ON' or 'OFF') .. '##chocopanelonoff', { 46, 22 }) and cwok then cw.setEnabled(not on); end
    end
    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Top section: total riding time.
    local minutes, slots, best = M.totalMinutes(deps);
    imgui.TextColored(COL_HEADER, 'Total riding time:');
    imgui.SameLine(0, 6);
    imgui.TextColored(COL_GOLD, string.format('%d minutes', minutes));
    imgui.SameLine(0, 6);
    imgui.TextColored(COL_DIM, string.format('(30 base + %d from gear)', minutes - M.BASE_MINUTES));
    imgui.TextColored(COL_DIM, 'The server computes ride duration as 1800 + mod*60 seconds at whistle time,');
    imgui.TextColored(COL_DIM, 'so every point of Chocobo riding time is one more minute in the saddle.');
    imgui.Spacing();

    -- Equipped pieces (best per slot). Each row: icon + name + the +ride tag.
    imgui.TextColored(COL_HEADER, 'Equipped pieces:');
    for _, slot in ipairs(M.SLOT_ORDER) do
        local p = best[slot];
        imgui.TextColored(COL_DIM, string.format('  %-6s', slot));
        imgui.SameLine(0, 6);
        if p ~= nil then
            local rec = (deps ~= nil and type(deps.lookupByName) == 'function') and deps.lookupByName(p.name) or nil;
            if deps ~= nil and type(deps.renderIcon) == 'function' then
                deps.renderIcon((rec and rec.Id) or p.id, 18);
            end
            imgui.TextColored(GREEN_OWNED, esc(p.name));
            if imgui.IsItemHovered() and rec ~= nil and deps ~= nil and type(deps.itemTooltip) == 'function' then
                pcall(deps.itemTooltip, rec);
            end
            imgui.SameLine(0, 8);
            imgui.TextColored(COL_GOLD, string.format('+%d', p.ride));
        else
            imgui.TextColored(COL_DIM, '(none owned)');
        end
    end
    imgui.Spacing();
    imgui.TextColored(COL_DIM, string.format('%d of %d slots covered.', slots, #M.SLOT_ORDER));
    imgui.Spacing();

    -- The Wand / weapon-slot + whistle-timing note (issue #95, verbatim intent).
    imgui.TextColored(COL_TEXT, 'Note: includes the Chocobo Wand -- takes your weapon slot; equip the set');
    imgui.TextColored(COL_TEXT, 'before you whistle.');
    imgui.Spacing();
    imgui.TextColored(COL_DIM, 'The switch is session-only: it turns OFF after a relog.');

    -- =======================================================================
    -- Dig guide (scaffold) -- issue #97. The dig rank + its source, the live
    -- Vana'diel clock header, and the general dig-success figure. The by-item /
    -- by-area search tabs are later slices; they hang off this rank + clock.
    -- =======================================================================
    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();
    imgui.TextColored(COL_HEADER, 'Dig guide');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_TEXT, 'your dig rank + the live moon/day/weather for the odds.');
    imgui.Spacing();

    -- ---- Dig rank (manual pick + source label) ----
    local rs = M.rankState();
    local ladder = M.rankLadder();
    -- Seed the picker from the RESOLVED rank (not just the manual pick), so a
    -- timing/ratchet detection shows in the dropdown the moment you open the panel
    -- -- otherwise the picker sat on your old manual pick while only the "Current
    -- dig rank" line moved (Henrik, field 2026-07-24). Picking still sets the
    -- manual seed; you can't drop below a detected floor (resolve takes max).
    local seed = tonumber(rs.rank) or (cwok and tonumber(cw.rankManual)) or 0;

    imgui.TextColored(COL_TEXT, 'Set your dig rank:');
    imgui.SameLine(0, 6);
    imgui.PushItemWidth(160);
    local seedLabel = (ladder[seed] ~= nil) and tostring(ladder[seed]) or ('rank ' .. seed);
    -- Walk 0..max(ladder) so the picker auto-covers the full 0..10 ladder
    -- (Amateur .. Expert) without a magic number -- extend the ladder, the
    -- picker follows.
    local maxRank = 0;
    for k in pairs(ladder) do
        if type(k) == 'number' and k > maxRank then maxRank = k; end
    end
    if imgui.BeginCombo('##chocorank', seedLabel) then
        for i = 0, maxRank do
            local lbl = (ladder[i] ~= nil) and tostring(ladder[i]) or ('rank ' .. i);
            if imgui.Selectable(string.format('%s##rank%d', lbl, i), i == seed) and cwok then
                cw.setManualRank(i);
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The dig rank is masked out of the client, so pick your best guess here.\nIt only seeds the guide -- digging an item above it auto-raises the rank.');
    end

    -- The resolved rank + its honest source label. exact (server-reported) shows
    -- plainly; an estimate says so, so the grey-out never lies.
    imgui.TextColored(COL_TEXT, 'Current dig rank:');
    imgui.SameLine(0, 6);
    imgui.TextColored(COL_GOLD, tostring(rs.label or ('rank ' .. (rs.rank or 0))));
    imgui.SameLine(0, 6);
    if rs.exact then
        imgui.TextColored(GREEN_OWNED, '(' .. (rs.sourceLabel or 'reported by server') .. ')');
    else
        imgui.TextColored(COL_DIM, string.format('(%s -- estimate)', rs.sourceLabel or rs.source or 'manual'));
    end
    imgui.TextColored(COL_DIM, 'manual = your pick;  >= from digs = raised by an item you dug;  reported by server = exact.');
    imgui.Spacing();

    -- ---- Live Vana'diel clock header (moon / day / weather) ----
    local clk = M.clock();
    imgui.TextColored(COL_HEADER, 'Right now in Vana\'diel:');
    -- Moon.
    imgui.TextColored(COL_DIM, '  Moon');
    imgui.SameLine(0, 6);
    if type(clk.moon) == 'table' and clk.moon.name ~= nil then
        imgui.TextColored(COL_TEXT, esc(string.format('%s (%d%%)', clk.moon.name, clk.moon.percent or 0)));
    else
        imgui.TextColored(COL_DIM, 'unavailable');
    end
    -- Day.
    imgui.SameLine(0, 16);
    imgui.TextColored(COL_DIM, 'Day');
    imgui.SameLine(0, 6);
    if clk.day ~= nil then
        imgui.TextColored(COL_TEXT, clk.dayElement and string.format('%s (%s)', clk.day, clk.dayElement) or tostring(clk.day));
    else
        imgui.TextColored(COL_DIM, 'unavailable');
    end
    -- Weather.
    imgui.SameLine(0, 16);
    imgui.TextColored(COL_DIM, 'Weather');
    imgui.SameLine(0, 6);
    if clk.weather ~= nil then
        imgui.TextColored(COL_TEXT, tostring(clk.weather));
    else
        imgui.TextColored(COL_DIM, 'unavailable');
    end
    imgui.Spacing();

    -- ---- General dig-success figure (current rank + moon) ----
    local moonPct = (type(clk.moon) == 'table') and clk.moon.percent or nil;
    local avg, nZones = M.generalSuccess(rs.rank or 0, moonPct);
    imgui.TextColored(COL_HEADER, 'General dig success:');
    imgui.SameLine(0, 6);
    if avg ~= nil then
        imgui.TextColored(COL_GOLD, esc(string.format('%.0f%%', avg * 100)));
        imgui.SameLine(0, 6);
        imgui.TextColored(COL_DIM, string.format('(typical of a hit across %d zone%s, at %s + this moon)',
            nZones or 0, (nZones == 1) and '' or 's', rs.label or ('rank ' .. (rs.rank or 0))));
    elseif moonPct == nil then
        imgui.TextColored(COL_DIM, 'waiting on the Vana\'diel clock (moon unavailable).');
    else
        imgui.TextColored(COL_DIM, 'no per-zone dig data yet -- run gen_digdata.py (maintainer) to light this up.');
    end
    imgui.TextColored(COL_DIM, 'Odds are best on a New or Full moon, worst at the half moons.');
    imgui.Spacing();
    imgui.TextColored(COL_DIM, 'v1 assumes standard gear (it ignores the dig-rare weight bonus).');
    imgui.Spacing();

    -- =======================================================================
    -- The two guide tabs. By area (issue #98) is live; By item (issue #99)
    -- lands next and reuses the row/odds rendering above. Guard the tab
    -- bindings (probe-don't-assume, hard rule 2) and fall back to By area.
    -- =======================================================================
    local hasTabs = type(imgui.BeginTabBar) == 'function'
        and type(imgui.BeginTabItem) == 'function'
        and type(imgui.EndTabItem) == 'function'
        and type(imgui.EndTabBar) == 'function';
    if not hasTabs then
        M.renderByArea(deps, rs, clk);
        return;
    end
    if imgui.BeginTabBar('##chocoguidetabs') then
        -- the cross-link one-shot: a zone clicked in By item focuses By area on it.
        local forceArea = guide.focusArea; guide.focusArea = false;
        if beginGuideTab('By area', forceArea) then
            M.renderByArea(deps, rs, clk);
            imgui.EndTabItem();
        end
        if beginGuideTab('By item', false) then
            M.renderByItem(deps, rs, clk);
            imgui.EndTabItem();
        end
        imgui.EndTabBar();
    end
end

return M;
