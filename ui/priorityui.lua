--[[
    dlac/ui/priorityui.lua -- the Priority section of the Automations tab
    (ADR 0012, step 2 / issue #49).

    ONE strict draggable list, top wins: the seven claimants (Pins, AutoAmmo,
    MaxMP, Craft, HELM, Fishing, Chocobo) plus the Locks veto row (draggable since step 3,
    ADR 0012 -- a claimant above it punches through a locked slot, one below stops;
    rendered visually distinct so it never reads as an ordinary claimant) and the
    Triggers floor (pinned last, immovable). A row shows a drag control, the row
    name, a source/control hint (where the feature is set) and a LIVE claim/veto
    status. Reordering commits through arbwatch (the arbstate Statefile writer)
    and the engine hot-reloads it -- no Reload LAC.

    Rendered from automationsui's list view (M.render(deps)); the pure display
    seams (SOURCE / HINT / statusText / buildRows) sit ABOVE the imgui guard so
    the headless suite can exercise them (fishui / ammoui pattern; tests PU*).
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local hasImgui = _iok and imgui ~= nil;

local _awok, arbwatch = pcall(require, 'dlac\\feature\\arbwatch');
local hasArb = _awok and type(arbwatch) == 'table';

-- Colors (match the automationsui / gearui palette).
local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_DIM    = { 0.70, 0.70, 0.70, 1.00 };
local COL_TEXT   = { 0.88, 0.88, 0.88, 1.00 };
local COL_ON     = { 0.55, 0.90, 0.55, 1.00 };   -- a claim actively dressing slots
local COL_IDLE   = { 0.70, 0.70, 0.70, 1.00 };   -- present but not claiming
local COL_FLOOR  = { 0.80, 0.72, 0.45, 1.00 };   -- the Triggers floor / veto (special rows)

-- Short, always-visible "controlled from" label (the source hint inline).
M.HINT = {
    Pins     = 'floating gear pin menu',
    Locks    = '/dl lock | Equipped tab | Sets tab',
    AutoAmmo = 'AutoAmmo row',
    MaxMP    = 'MaxMP row',
    Craft    = 'Auto Craft Set row / craft bar',
    HELM     = 'HELM row / HELM bar',
    Fishing  = 'Fishing row / fish bar',
    Chocobo  = 'Chocobo row',
    Triggers = 'Triggers tab',
};

-- The full source/control sentence (hover tooltip) -- exactly where each feature
-- is set, per issue #49.
M.SOURCE = {
    Pins     = 'Set from the floating gear window\'s PIN menu (right-click a slot to pin/unpin).',
    Locks    = 'Set by /dl lock, the Equipped tab\'s "Lock when equipped", or the Sets tab\'s "Equip & Lock".\n'
            .. 'This is the VETO row -- a claim ranked ABOVE it punches through a locked slot; a claim below it stops. '
            .. 'Drag it to choose which claimants the lock stops: at the top it vetoes everyone (pins included); '
            .. 'lower, everyone above it punches through.',
    AutoAmmo = 'Set on the AutoAmmo row above (click it for the per-job ammo panel).',
    MaxMP    = 'Set on the MaxMP row above (click it for the band panel), or /dl mode maxmp.',
    Craft    = 'Set on the Auto Craft Set row above, or the floating craft bar.',
    HELM     = 'Set on the HELM row above, or the floating HELM bar.',
    Fishing  = 'Set on the Fishing row above, or the floating fish bar.',
    Chocobo  = 'Set on the Chocobo row above (click it for the riding-gear panel).',
    Triggers = 'Your Triggers tab. This is the FLOOR -- what is worn when no claim wins a slot.',
};

-- The live claim status for one row. Pure: `live` is the gathered engine-visible
-- state (see M.gatherLive), so tests drive it directly. A claiming row reads as
-- an ON string; a present-but-quiet row reads "idle". The addon reports each
-- claimant's ARMED state (the same reads /dl prio makes); the exact per-slot
-- winner attribution is /dl why's job (step 4).
function M.statusText(name, live)
    live = live or {};
    if name == 'Triggers' then
        return 'floor -- always on';
    elseif name == 'Pins' then
        local n = tonumber(live.pins) or 0;
        return n > 0 and string.format('claiming %d pinned slot%s', n, n == 1 and '' or 's') or 'idle';
    elseif name == 'Locks' then
        local n = tonumber(live.locks) or 0;
        return n > 0 and string.format('veto -- %d slot%s locked', n, n == 1 and '' or 's')
                      or 'idle -- no locks';
    elseif name == 'AutoAmmo' then
        local a = live.ammo or {};
        if not a.on then return 'off'; end
        if live.fishing then return 'standing down: fishing live'; end
        return 'claiming Ammo' .. (a.job and (' on ' .. tostring(a.job)) or '');
    elseif name == 'MaxMP' then
        return live.maxmp and 'ON -- claiming battery slots by MP band' or 'off';
    elseif name == 'Craft' then
        return live.craft and 'claiming: armed' or 'idle';
    elseif name == 'HELM' then
        return live.helm and 'claiming: armed (idle only)' or 'idle';
    elseif name == 'Fishing' then
        return live.fishing and 'claiming: armed (idle only)' or 'idle';
    elseif name == 'Chocobo' then
        return live.chocobo and 'claiming: armed (idle only)' or 'idle';
    end
    return '?';
end

-- Is this row actively dressing slots right now? Drives the status color.
local function rowActive(name, live)
    live = live or {};
    if name == 'Triggers' then return true; end
    if name == 'Pins'     then return (tonumber(live.pins)  or 0) > 0; end
    if name == 'Locks'    then return (tonumber(live.locks) or 0) > 0; end
    if name == 'AutoAmmo' then return (live.ammo or {}).on == true and not live.fishing; end
    if name == 'MaxMP'    then return live.maxmp == true; end
    if name == 'Craft'    then return live.craft == true; end
    if name == 'HELM'     then return live.helm == true; end
    if name == 'Fishing'  then return live.fishing == true; end
    if name == 'Chocobo'  then return live.chocobo == true; end
    return false;
end

-- The display model for the section -- pure, so the row set (order, fixedness,
-- hints, status) is testable without imgui.
function M.buildRows(order, live)
    local fixed = (hasArb and arbwatch.FIXED) or { Locks = true, Triggers = true };
    local out = {};
    for i, name in ipairs(order or {}) do
        out[i] = {
            name      = name,
            hint      = M.HINT[name] or '',
            source    = M.SOURCE[name] or '',
            status    = M.statusText(name, live),
            active    = rowActive(name, live),
            special   = (name == 'Locks' or name == 'Triggers'),
            draggable = (fixed[name] ~= true),
        };
    end
    return out;
end

if not hasImgui then return M; end   -- headless: the pure half above is the module

-- ---------------------------------------------------------------------------
-- Live-state gather (the render half). Each read is guarded: a watcher that
-- failed to load, or a pre-login state, just leaves that row reading "off/idle".
-- ---------------------------------------------------------------------------
function M.gatherLive(deps)
    local live = { pins = 0, locks = 0, maxmp = false, craft = false, helm = false,
                   fishing = false, chocobo = false, ammo = { on = false, job = nil } };
    local job = (deps ~= nil and type(deps.playerJob) == 'function') and deps.playerJob() or nil;

    pcall(function() live.pins = require('dlac\\feature\\pinwatch').count() or 0; end);
    pcall(function()
        local aw = require('dlac\\feature\\ammowatch');
        aw.selectJob(job);
        live.ammo = { on = (aw.enabled == true), job = job };
    end);
    pcall(function() live.craft   = require('dlac\\feature\\craftwatch').isEnabled() == true; end);
    pcall(function() live.helm    = require('dlac\\feature\\helmwatch').isEnabled() == true; end);
    pcall(function() live.fishing = require('dlac\\feature\\fishwatch').isEnabled() == true; end);
    pcall(function() live.chocobo = require('dlac\\feature\\chocowatch').isEnabled() == true; end);

    -- MaxMP mode + slot locks both live in the LAC engine's modestate mirror
    -- (<char>\dlac\modestate.lua), the same file gearui reads for the lock pills.
    pcall(function()
        if deps == nil then return; end
        local base = (type(deps.dataDir) == 'function') and deps.dataDir() or nil;
        if base == nil and type(deps.charBase) == 'function' then
            local cb = deps.charBase();
            base = cb and (cb .. 'dlac\\') or nil;
        end
        if base == nil then return; end
        local chunk = loadfile(base .. 'modestate.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if not ok or type(t) ~= 'table' then return; end
        live.maxmp = (t.maxmp == true);
        if type(t.__locks) == 'table' then
            local n = 0;
            for _, v in pairs(t.__locks) do if v == true then n = n + 1; end end
            live.locks = n;
        end
    end);
    return live;
end

-- Fixed column offsets (absolute from the window's left margin, the
-- automationsui table convention). The reorder controls sit left of Name.
-- Hints are the longest text (multi-surface lists), so Controlled-from sits
-- LAST and gets the open right edge (Henrik, field round 07-21).
local X_NAME, X_STATUS, X_HINT = 66, 190, 460;

-- ---------------------------------------------------------------------------
-- The section. Rendered from automationsui's list view (below the automation
-- table). Draws the strict list top-first; a claimant is reordered by the arrow
-- controls OR by dragging its row, both committing through arbwatch.setOrder --
-- the engine hot-reloads arbstate on its next dispatch, no Reload LAC.
-- ---------------------------------------------------------------------------
function M.render(deps)
    if not hasImgui then return; end
    if not hasArb then
        imgui.TextColored(COL_DIM, 'Claim priority unavailable (arbwatch failed to load).');
        return;
    end
    local order = arbwatch.order();
    if type(order) ~= 'table' or #order == 0 then
        imgui.TextColored(COL_DIM, 'Claim priority unavailable.');
        return;
    end
    local live = M.gatherLive(deps);

    imgui.TextColored(COL_HEADER, 'Claim priority');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_DIM, 'top wins -- drag a claimant (or use the arrows) to decide who dresses a contested slot.');
    imgui.Spacing();

    imgui.Dummy({ 0, 0 });
    imgui.SameLine(X_NAME);   imgui.TextColored(COL_HEADER, 'Claimant');
    imgui.SameLine(X_STATUS); imgui.TextColored(COL_HEADER, 'Live status');
    imgui.SameLine(X_HINT);   imgui.TextColored(COL_HEADER, 'Controlled from');
    imgui.Separator();

    local LMB = ImGuiMouseButton_Left or 0;
    local committed = false;                     -- one reorder per frame; re-read next frame
    local function commit(newOrder)
        if newOrder == nil or committed then return; end
        arbwatch.setOrder(newOrder);
        committed = true;
    end

    local rows = M.buildRows(order, live);
    for i, r in ipairs(rows) do
        if committed then break; end
        imgui.PushID('arbrow_' .. r.name);

        -- Reorder controls (guaranteed path: plain Buttons). Non-draggable rows
        -- get a matching-width spacer so the columns stay aligned.
        if r.draggable then
            if imgui.Button('^##up', { 20, 18 }) then commit(arbwatch.moveClaimant(order, i, -1)); end
            if imgui.IsItemHovered() then imgui.SetTooltip('Raise -- win contested slots over the row above.'); end
            imgui.SameLine(0, 2);
            if imgui.Button('v##dn', { 20, 18 }) then commit(arbwatch.moveClaimant(order, i, 1)); end
            if imgui.IsItemHovered() then imgui.SetTooltip('Lower -- yield contested slots to the row above.'); end
        else
            imgui.Dummy({ 42, 18 });
        end

        -- The drag handle: a full-width Selectable behind the row text. Dragging
        -- it off itself swaps toward the drag direction (the dear-imgui reorder
        -- idiom), which arbwatch.moveClaimant gates to the legal moves.
        imgui.SameLine(0, 6);
        imgui.Selectable('##arbsel_' .. r.name, false, 0, { 0, 18 });
        if r.draggable and imgui.IsItemActive() and not imgui.IsItemHovered() then
            pcall(function()
                local dx, dy = imgui.GetMouseDragDelta(LMB);
                if type(dx) == 'table' then dy = (dx[2] or dx.y); end
                if type(dy) == 'number' and dy ~= 0 then
                    local moved = arbwatch.moveClaimant(order, i, dy < 0 and -1 or 1);
                    if moved ~= nil then
                        commit(moved);
                        imgui.ResetMouseDragDelta(LMB);
                    end
                end
            end);
        end
        if imgui.IsItemHovered() and r.source ~= '' then imgui.SetTooltip(r.source); end

        -- Overlaid row text. Special rows (Locks veto / Triggers floor) read in
        -- the floor color so they are visibly not ordinary claimants.
        local nameCol = r.special and COL_FLOOR or COL_TEXT;
        imgui.SameLine(X_NAME);   imgui.TextColored(nameCol, r.name);
        imgui.SameLine(X_STATUS); imgui.TextColored(r.active and COL_ON or COL_IDLE, r.status);
        imgui.SameLine(X_HINT);   imgui.TextColored(COL_DIM, r.hint);
        imgui.PopID();
    end

    imgui.Spacing();
    imgui.TextColored(COL_DIM, 'The Triggers floor is pinned last. The Locks veto drags like any row: a claimant above it punches through a locked slot, one below it stops.');
end

return M;
