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
end

return M;
