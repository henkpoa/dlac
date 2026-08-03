--[[
    dlac/ui/priorityui.lua -- the Priority section of the Gear Helpers tab
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

-- What a PLAYER reads for a claimant. The identity (r.name / the keys below /
-- arbstate's saved order) never moves; only the rendered string does -- one map,
-- in gear/arbiter, shared with the Arbiter Monitor and /dl prio + /dl why so no
-- surface can drift. Pure + above the imgui guard, so the headless suite reaches
-- it; a load knot degrades to the identity rather than blanking the row.
function M.label(name)
    local ok, s = pcall(function()
        return require('dlac\\gear\\arbiter').claimantLabel(name);
    end);
    return (ok and type(s) == 'string') and s or name;
end

-- Short, always-visible "controlled from" label (the source hint inline).
M.HINT = {
    Disabled = '/dl disable | Equipped tab',
    Naked    = '/dl naked | Equipped tab',
    Pins     = 'floating gear pin menu',
    Locks    = '/dl lock | Equipped tab | Sets tab',
    AutoAmmo = 'Ammo row',
    MaxMP    = 'MaxMP row',
    Craft    = 'Crafting Gear row / craft bar',
    HELM     = 'HELM row / HELM bar',
    Fishing  = 'Fishing row / fish bar',
    Chocobo  = 'Chocobo row',
    JobHelper= 'Job Helpers tab (per job)',
    External = '/dl claims | Menu > Settings',
    ModeLock = 'Triggers tab > Modes > locks',
    Triggers = 'Triggers tab',
};

-- The full source/control sentence (hover tooltip) -- exactly where each feature
-- is set, per issue #49.
M.SOURCE = {
    -- The CEILING (ADR 0024). It is on this list so a player can SEE why a slot
    -- stopped responding; it is not on it to be dragged, and the hover says so
    -- rather than leaving them hunting for a handle that is not there.
    Disabled = 'Set by /dl disable <slot|all> (release: /dl enable), or the Equipped tab\'s "Free equip" switch.\n'
            .. 'A disabled slot is YOURS: dlac writes nothing to it -- no equip, no unequip -- so what you put '
            .. 'on by hand stays on. Triggers, pins, a locked set and even Naked all stop here.\n'
            .. 'This row cannot be moved. Every other row is a ranking; this one is a boundary.',
    -- The drag lives HERE, so the "naked except ..." trick is explained HERE and
    -- nowhere else (the panel-text standard: one home per idea, in a hover).
    Naked    = 'Set by /dl naked (release: /dl dress), or the Equipped tab\'s Naked switch.\n'
            .. 'Claims every slot EMPTY and keeps it that way. At the top it beats everything, pins '
            .. 'included -- drag Pins or Locks above it to stay naked EXCEPT those.',
    Pins     = 'Set from the floating gear window\'s PIN menu (right-click a slot to pin/unpin).',
    Locks    = 'Set by /dl lock, the Equipped tab\'s "Lock when equipped" and "Lock gear", or the Sets tab\'s "Equip & Lock".\n'
            .. 'This row carries BOTH kinds of lock: a plain slot lock, which only WITHHOLDS a slot (it keeps whatever '
            .. 'is worn there), and a LOCKED SET (/dl lock set ...), which holds specific gear in specific slots and '
            .. 're-applies it every dispatch.\n'
            .. 'A claim ranked ABOVE this row punches through both; a claim below it stops. '
            .. 'Drag it to choose which claimants a lock stops: at the top it vetoes everyone (pins included); '
            .. 'lower, everyone above it punches through.',
    AutoAmmo = 'Set on the Ammo row above (click it for the per-job ammo panel).',
    MaxMP    = 'Set on the MaxMP row above (click it for the band panel), or /dl mode maxmp.',
    Craft    = 'Set on the Crafting Gear row above, or the floating craft bar.',
    HELM     = 'Set on the HELM row above, or the floating HELM bar.',
    Fishing  = 'Set on the Fishing row above, or the floating fish bar.',
    Chocobo  = 'Set on the Chocobo row above (click it for the riding-gear panel).',
    JobHelper= 'The shared row every Job helper\'s Action sequence rides (Reward, ...).\n'
            .. 'Its position here is remembered PER JOB -- dragging it moves it for the job you are on '
            .. 'now, and other jobs keep their own placement. Default: directly below Locks, so a lock, '
            .. 'Naked or Free equip on a needed slot makes the sequence refuse loudly instead of firing.\n'
            .. 'The row hides while no Job helper modules are installed.',
    External = 'The shared row every OTHER ADDON\'s gear claim rides. Switched on with /dl claims on, or the '
            .. '"Let other addons claim gear" row in Menu > Settings -- session only, never saved, and turning '
            .. 'it off releases every held claim at once.\n'
            .. 'A claim is temporary and is never written to any of your files: no addon can edit a set, a '
            .. 'trigger or a mode through it. Default rank is HERE, just above your Triggers -- so a foreign '
            .. 'addon dresses over your trigger sets and under everything you configured yourself, until you '
            .. 'drag it higher.\n'
            .. '/dl claims list names who is holding what, and for how much longer.',
    ModeLock = 'Set per mode in Triggers > Modes: the "locks" button on a mode box opens all 16 slots, '
            .. 'and each slot you give a set is answered by THAT set while the mode is active -- no trigger '
            .. 'rule can move it, on any event. A cycle locks per VALUE, so Weapon:Melee and Weapon:Caster '
            .. 'can hold different slots.\n'
            .. 'Default rank is HERE, just above Other addons and your Triggers: it beats every rule you '
            .. 'wrote, and yields to the activities you armed this session (crafting, HELM, fishing, pins). '
            .. 'Drag it higher to make a locked slot beat those too.',
    Triggers = 'Your Triggers tab. This is the FLOOR -- what is worn when no claim wins a slot.',
};

-- The live claim status for one row. Pure: `live` is the gathered engine-visible
-- state (see M.gatherLive), so tests drive it directly. A claiming row reads as
-- an ON string; a present-but-quiet row reads "idle". The addon reports each
-- claimant's ARMED state (the same reads /dl prio makes); the exact per-slot
-- winner attribution is /dl why's job (step 4).
function M.statusText(name, live)
    live = live or {};
    if name == 'Disabled' then
        local n = tonumber(live.disabled) or 0;
        return n > 0 and string.format('ON -- %d slot%s hands-off', n, n == 1 and '' or 's')
                      or 'off -- no slots disabled';
    elseif name == 'Triggers' then
        return 'floor -- always on';
    elseif name == 'Naked' then
        return live.naked and 'ON -- claiming all 16 slots EMPTY' or 'off';
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
    elseif name == 'JobHelper' then
        -- names the LIVE module + act (issue #138), or idle. jh = { active, text }.
        local jh = live.jobhelper or {};
        return (type(jh.text) == 'string' and jh.text ~= '') and jh.text or 'idle';
    elseif name == 'External' then
        -- extclaim.statusText already names the addons; it is the same string
        -- /dl prio prints, so the chat and the panel cannot drift.
        local ex = live.external or {};
        return (type(ex.text) == 'string' and ex.text ~= '') and ex.text or 'off';
    elseif name == 'ModeLock' then
        -- Names the SLOTS and the SETS, not a count: "3 slots" would send them
        -- back to the Modes list to find out which three.
        local ml = live.modelock or {};
        return (type(ml.text) == 'string' and ml.text ~= '') and ml.text or 'off';
    end
    return '?';
end

-- Is this row actively dressing slots right now? Drives the status color.
local function rowActive(name, live)
    live = live or {};
    if name == 'Triggers' then return true; end
    if name == 'Disabled' then return (tonumber(live.disabled) or 0) > 0; end
    if name == 'Naked'    then return live.naked == true; end
    if name == 'Pins'     then return (tonumber(live.pins)  or 0) > 0; end
    if name == 'Locks'    then return (tonumber(live.locks) or 0) > 0; end
    if name == 'AutoAmmo' then return (live.ammo or {}).on == true and not live.fishing; end
    if name == 'MaxMP'    then return live.maxmp == true; end
    if name == 'Craft'    then return live.craft == true; end
    if name == 'HELM'     then return live.helm == true; end
    if name == 'Fishing'  then return live.fishing == true; end
    if name == 'Chocobo'  then return live.chocobo == true; end
    if name == 'JobHelper' then return (live.jobhelper or {}).active == true; end
    if name == 'External'  then return (live.external or {}).active == true; end
    if name == 'ModeLock'  then return (live.modelock or {}).active == true; end
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
            special   = (name == 'Locks' or name == 'Triggers' or name == 'Disabled'),
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
    local live = { pins = 0, locks = 0, disabled = 0, maxmp = false, craft = false,
                   helm = false, fishing = false, chocobo = false, naked = false,
                   ammo = { on = false, job = nil } };
    local job = (deps ~= nil and type(deps.playerJob) == 'function') and deps.playerJob() or nil;

    pcall(function() live.pins = require('dlac\\feature\\pinwatch').count() or 0; end);
    pcall(function()
        local aw = require('dlac\\feature\\ammowatch');
        aw.selectJob(job);
        live.ammo = { on = (aw.enabled == true), job = job };
    end);
    -- The JobHelper row's live status (issue #138): the running Action sequence
    -- naming its module + act, or idle.
    pcall(function()
        local aseq = require('dlac\\feature\\actionseq');
        live.jobhelper = { active = aseq.active() == true, text = aseq.statusText() };
    end);
    -- The External row (2026-08-01): the live mailbox of claims filed by OTHER
    -- addons. Reads the module directly -- the same require the menu's switch
    -- makes -- so the row can NAME the addons rather than say "something".
    pcall(function()
        local ex = require('dlac\\feature\\extclaim');
        live.external = { on = ex.on == true, active = ex.active() == true, text = ex.statusText() };
    end);
    -- The ModeLock row (2026-08-03): the live plan through triggersui's one
    -- addon-state door, which asks the ENGINE's planner -- so this row, the
    -- Trigger Monitor and the Mode Locks window all read one answer.
    pcall(function()
        local t = require('dlac\\ui\\triggersui');
        if type(t.modeLockLive) ~= 'function' then return; end
        local plan = t.modeLockLive();
        local parts = {};
        for _, slot in ipairs({ 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck', 'Ear1', 'Ear2',
                                'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet' }) do
            if type(plan) == 'table' and plan[slot] ~= nil then
                parts[#parts + 1] = slot .. '=' .. tostring(plan[slot].set);
            end
        end
        live.modelock = { active = (#parts > 0),
                          text = (#parts > 0) and ('holding ' .. table.concat(parts, ', ')) or 'off' };
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
        live.naked = (t.__naked == true);
        if type(t.__locks) == 'table' then
            local n = 0;
            for _, v in pairs(t.__locks) do if v == true then n = n + 1; end end
            live.locks = n;
        end
        if type(t.__disabled) == 'table' then
            local n = 0;
            for _, v in pairs(t.__disabled) do if v == true then n = n + 1; end end
            live.disabled = n;
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
-- opts.embedded: the caller (the Automations tab) draws a "Claim Priority"
-- CollapsingHeader as the title, so skip our own inline bold title -- but keep
-- the one-line hint under it. Standalone callers (none today) get both.
function M.render(deps, opts)
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

    -- issue #138: weave the per-job JobHelper row into the rendered order (a
    -- no-op with zero modules -- the row hides). `order` stays the GLOBAL order
    -- (what a known-row drag commits to); `placed` is what the player sees.
    local job = (deps ~= nil and type(deps.playerJob) == 'function') and deps.playerJob() or nil;
    local placed = order;
    pcall(function()
        local jh = require('dlac\\feature\\jobhelpers');
        if type(jh.placedOrder) == 'function' then
            local p = jh.placedOrder(order, job);
            if type(p) == 'table' and #p > 0 then placed = p; end
        end
    end);

    if not (type(opts) == 'table' and opts.embedded) then
        imgui.TextColored(COL_HEADER, 'Claim priority');
        imgui.SameLine(0, 10);
    end
    imgui.TextColored(COL_DIM, 'top wins -- drag a claimant (or use the arrows) to decide who dresses a contested slot.');
    imgui.Spacing();

    imgui.Dummy({ 0, 0 });
    imgui.SameLine(X_NAME);   imgui.TextColored(COL_HEADER, 'Claimant');
    imgui.SameLine(X_STATUS); imgui.TextColored(COL_HEADER, 'Live status');
    imgui.SameLine(X_HINT);   imgui.TextColored(COL_HEADER, 'Controlled from');
    imgui.Separator();

    local LMB = ImGuiMouseButton_Left or 0;
    local committed = false;                     -- one reorder per frame; re-read next frame
    -- Route a move by row TYPE (issue #138): the JobHelper row writes the current
    -- job's per-job anchor (never the global arbstate); every other row commits
    -- to the global order. dir: -1 up / +1 down.
    local function doMove(rowName, dir)
        if committed then return; end
        if rowName == 'JobHelper' then
            local moved = nil;
            pcall(function()
                local jh = require('dlac\\feature\\jobhelpers');
                if type(jh.moveRankRow) == 'function' then moved = jh.moveRankRow(placed, job, dir); end
            end);
            if moved ~= nil then committed = true; end
            return;
        end
        -- a known claimant / the Locks veto: move it in the GLOBAL order.
        local baseIdx = nil;
        for bi, n in ipairs(order) do if n == rowName then baseIdx = bi; break; end end
        if baseIdx == nil then return; end
        local moved = arbwatch.moveClaimant(order, baseIdx, dir);
        if moved ~= nil then arbwatch.setOrder(moved); committed = true; end
    end

    local rows = M.buildRows(placed, live);
    for i, r in ipairs(rows) do
        if committed then break; end
        imgui.PushID('arbrow_' .. r.name);

        -- Reorder controls (guaranteed path: plain Buttons). Non-draggable rows
        -- get a matching-width spacer so the columns stay aligned.
        if r.draggable then
            if imgui.Button('^##up', { 20, 18 }) then doMove(r.name, -1); end
            if imgui.IsItemHovered() then imgui.SetTooltip('Raise -- win contested slots over the row above.'); end
            imgui.SameLine(0, 2);
            if imgui.Button('v##dn', { 20, 18 }) then doMove(r.name, 1); end
            if imgui.IsItemHovered() then imgui.SetTooltip('Lower -- yield contested slots to the row above.'); end
        else
            imgui.Dummy({ 42, 18 });
        end

        -- The drag handle: a full-width Selectable behind the row text. Dragging
        -- it off itself swaps toward the drag direction (the dear-imgui reorder
        -- idiom), gated to the legal moves by the mover.
        imgui.SameLine(0, 6);
        imgui.Selectable('##arbsel_' .. r.name, false, 0, { 0, 18 });
        if r.draggable and imgui.IsItemActive() and not imgui.IsItemHovered() then
            pcall(function()
                local dx, dy = imgui.GetMouseDragDelta(LMB);
                if type(dx) == 'table' then dy = (dx[2] or dx.y); end
                if type(dy) == 'number' and dy ~= 0 then
                    doMove(r.name, dy < 0 and -1 or 1);
                    if committed then imgui.ResetMouseDragDelta(LMB); end
                end
            end);
        end
        if imgui.IsItemHovered() and r.source ~= '' then imgui.SetTooltip(r.source); end

        -- Overlaid row text. Special rows (Locks veto / Triggers floor) read in
        -- the floor color so they are visibly not ordinary claimants.
        local nameCol = r.special and COL_FLOOR or COL_TEXT;
        -- The LABEL, never the identity (arbiter.claimantLabel): r.name still
        -- keys the imgui id, the drag, HINT/SOURCE and arbstate's saved order.
        imgui.SameLine(X_NAME);   imgui.TextColored(nameCol, M.label(r.name));
        imgui.SameLine(X_STATUS); imgui.TextColored(r.active and COL_ON or COL_IDLE, r.status);
        imgui.SameLine(X_HINT);   imgui.TextColored(COL_DIM, r.hint);
        imgui.PopID();
    end

    imgui.Spacing();
    imgui.TextColored(COL_DIM, 'Free equip is pinned first and the Triggers floor last -- neither moves. The Locks veto drags like any row: a claimant above it punches through a locked slot, one below it stops.');

    -- The current job's Job helper module order (read-only, issue #138): the
    -- tie-break for two helpers requesting a sequence at once -- higher in this
    -- order wins, the loser is refused loudly.
    pcall(function()
        local jh = require('dlac\\feature\\jobhelpers');
        if type(jh.count) ~= 'function' or jh.count() < 1 or job == nil then return; end
        local ids = jh.idsForJob(job);
        if #ids > 0 then
            imgui.TextColored(COL_DIM, string.format('Job helper order (%s): %s', tostring(job), table.concat(ids, ' > ')));
        end
    end);
end

return M;
