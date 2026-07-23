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

-- The dig-rank ladder labels (0..8) -- the shipped data wins, digrank's fallback
-- covers a missing table. Returns a 0-indexed table.
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
    local seed = (cwok and tonumber(cw.rankManual)) or 0;

    imgui.TextColored(COL_TEXT, 'Set your dig rank:');
    imgui.SameLine(0, 6);
    imgui.PushItemWidth(160);
    local seedLabel = (ladder[seed] ~= nil) and tostring(ladder[seed]) or ('rank ' .. seed);
    if imgui.BeginCombo('##chocorank', seedLabel) then
        for i = 0, 8 do
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
        imgui.TextColored(COL_TEXT, string.format('%s (%d%%)', clk.moon.name, clk.moon.percent or 0));
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
        imgui.TextColored(COL_GOLD, string.format('%.0f%%', avg * 100));
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
end

return M;
