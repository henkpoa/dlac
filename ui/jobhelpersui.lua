--[[
    dlac/ui/jobhelpersui.lua -- the Job Helpers tab (issue #137, PRD #135).

    Registers a MAIN tab, "Job Helpers", to the RIGHT of Gear Helpers -- but ONLY
    while at least one Job helper module is loaded (feature\jobhelpers). The tab
    does not self-register at require time the way gearui's tabs do: dlac.lua
    calls M.maybeRegister(host) AFTER the loader runs, and it registers nothing
    when zero modules loaded. Drop a module folder in and reload -> the tab
    appears; remove it and reload -> the tab is gone (the acceptance test).

    Layout is the Gear Helpers pattern: display-only PER-JOB SECTIONS over a flat
    module list. One row per module under each declared job's CollapsingHeader; a
    multi-job module appears under each job it declares, with ONE shared switch
    state (every row re-reads the live pill + activity, so they never disagree).
    The row's pill is the module's master switch (feature\jobhelpers.setEnabled);
    the status text shows the live inactivity reason (wrong job / town / dead /
    zoning) from the module-activity predicate. Rows within a section drag-reorder
    (up/down buttons + a drag-selectable, the Claim Priority mechanism -- the
    Ashita install has no working BeginPopupContextItem) and the order is
    remembered per job.

    Containment (hard rules 6, 12): every call INTO a module's render hooks is
    pcall-wrapped, so a module that throws mid-render loses its own Panel and
    prints one line -- it never tears the tab or the other modules' rows. The
    frame-level imgui stack recovery is uihost's tabGuard, above this.

    Defensive throughout: no deps / no imgui / headless -> a safe notice or a
    no-op, never an error (the automationsui contract).
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local hasImgui = _iok and imgui ~= nil;

local jh = require('dlac\\feature\\jobhelpers');

-- Colors: status only (NOT the gear-helper coverage ramp -- architecture.md
-- forbids a rival to that ONE ramp; this is a different, on/off/dormant scale).
local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_DIM    = { 0.70, 0.70, 0.70, 1.00 };
local COL_ACTIVE = { 0.35, 1.00, 0.45, 1.00 };
local COL_DORMANT= { 0.85, 0.80, 0.35, 1.00 };
local COL_OFF    = { 0.60, 0.60, 0.60, 1.00 };
local COL_ERR    = { 1.00, 0.45, 0.40, 1.00 };

-- Injected by dlac.lua (the shared services table). The tab itself needs almost
-- nothing; it is handed on to each module's Panel via the render ctx.
local deps = nil;
function M.init(d) deps = d; end

-- Which module's Panel is showing (by module id). Identity-keyed, not index-
-- keyed, so it survives a reorder.
local _sel = nil;

-- Modules whose render hook has already thrown this session -- print the loud
-- line ONCE, then just show the red placeholder (no per-frame chat spam).
local _blamed = {};

-- Imgui text calls are printf format strings, so a '%' in a MODULE-supplied
-- label or status word is a conversion, not a percent sign (ui\panelkit's `esc`
-- carries the field story). Everything author-supplied that reaches a Text or a
-- tooltip on this tab goes through here.
local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

local function statusColor(act)
    if act == nil then return COL_DIM; end
    if act.active then return COL_ACTIVE; end
    if act.reason == 'off' then return COL_OFF; end
    return COL_DORMANT;
end

-- One module row under a section. `i` is the 1-based index within `ids` (this
-- section's resolved order); `job` names the section. Returns nothing; side
-- effects are the pill/reorder mutations.
local function moduleRow(job, ids, i)
    local id  = ids[i];
    local rec = jh.record(id);
    if rec == nil then return; end
    local enabled = jh.isEnabled(id);

    imgui.PushID('jhrow_' .. job .. '_' .. id);

    -- reorder controls (only meaningful when the section has >1 row)
    if #ids > 1 then
        if imgui.Button('^##up', { 20, 20 }) then jh.moveInSection(job, ids, i, -1); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Move up in this section.'); end
        imgui.SameLine(0, 2);
        if imgui.Button('v##dn', { 20, 20 }) then jh.moveInSection(job, ids, i, 1); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Move down in this section.'); end
    else
        imgui.Dummy({ 42, 20 });   -- keep the column aligned for single-row sections
    end
    imgui.SameLine(0, 6);

    -- the master-switch pill (green on / red off). ui\panelkit owns the widget --
    -- the same one a module's own Panel draws, and the same one the hobby bars
    -- draw through craftbar.onOffSwitch, which delegates here.
    local tipOn  = rec.label .. ' is ON -- click to silence this helper.';
    local tipOff = rec.label .. ' is OFF -- click to turn it on.';
    local toggled = false;
    local pkok, panelkit = pcall(require, 'dlac\\ui\\panelkit');
    if pkok and type(panelkit) == 'table' and type(panelkit.pill) == 'function' then
        toggled = panelkit.pill(imgui, enabled, 'jhpill_' .. job .. '_' .. id, tipOn, tipOff);
    else
        toggled = imgui.Button((enabled and 'ON' or 'OFF') .. '##jhpill_' .. job .. '_' .. id, { 46, 22 });
        if imgui.IsItemHovered() then imgui.SetTooltip(esc(enabled and tipOn or tipOff)); end
    end
    if toggled then jh.setEnabled(id, not enabled); end
    imgui.SameLine(0, 8);

    -- the module label (a Selectable so clicking the row opens its Panel).
    -- NAME + PILL ONLY (Henrik's field ruling 2026-07-29, screenshot round 2):
    -- the live status and the module's own status hook render in the PANEL
    -- header, not here -- the list answers "what is installed and armed",
    -- the Panel answers "what is it doing".
    local selected = (_sel == id);
    if imgui.Selectable(rec.label .. '##jhsel_' .. job .. '_' .. id, selected,
                        ImGuiSelectableFlags_None or 0, { 250, 22 }) then
        _sel = id;
    end

    imgui.PopID();
end

-- Render one job section (a CollapsingHeader with its ordered module rows).
local function jobSection(job)
    local ids = jh.idsForJob(job);
    if #ids == 0 then return; end
    -- default-open; the '###' keeps the id stable if the count in the title changes.
    local flag = (ImGuiTreeNodeFlags_DefaultOpen or 32);
    if imgui.CollapsingHeader(job .. '###jhsec_' .. job, flag) then
        imgui.Indent(6);
        for i = 1, #ids do moduleRow(job, ids, i); end
        imgui.Unindent(6);
    end
end

-- The selected module's Panel, contained: a throw loses the Panel and prints
-- once, never the tab.
local function renderPanel()
    if _sel == nil then
        imgui.TextColored(COL_DIM, 'Select a helper on the left to configure it.');
        return;
    end
    local rec = jh.record(_sel);
    if rec == nil then
        imgui.TextColored(COL_DIM, 'Select a helper on the left to configure it.');
        return;
    end
    imgui.TextColored(COL_HEADER, esc(rec.label));
    -- The live status + the module's own status hook live HERE, beside the
    -- Panel title (Henrik's field ruling 2026-07-29): the row stays name+pill.
    local act = jh.activity(rec.id);
    imgui.SameLine(0, 10);
    imgui.TextColored(statusColor(act), esc((act ~= nil and act.label) or '?'));

    -- The render ctx (api 2). `ui` is the Panel widget kit already BOUND to the
    -- host's imgui handle -- which is the handle a module must draw with, because
    -- the smoke suite renders every tab against a stub binding and a module that
    -- required its own would get the wrong instance. `S` is the module's own API
    -- table, the same one its init hook received.
    local kit = nil;
    pcall(function()
        local pk = require('dlac\\ui\\panelkit');
        if type(pk) == 'table' and type(pk.bind) == 'function' then kit = pk.bind(imgui); end
    end);
    local ctx = { imgui = imgui, ui = kit, id = rec.id, record = rec,
                  S = rec.S, deps = rec.S or deps, activity = act };

    if type(rec.mod.status) == 'function' then
        imgui.SameLine(0, 10);
        local sok = pcall(rec.mod.status, ctx);
        if not sok and not _blamed[rec.id] then
            _blamed[rec.id] = true;
            print('[dlac] Job helper ' .. tostring(rec.id) .. ' status hook errored -- contained.');
        end
    end
    imgui.Separator();
    local ok, err = pcall(rec.mod.panel, ctx);
    if not ok then
        if not _blamed[rec.id] then
            _blamed[rec.id] = true;
            print('[dlac] Job helper ' .. tostring(rec.id) .. ' Panel errored: '
                .. tostring(err):gsub('%s+', ' '):sub(1, 120));
        end
        imgui.TextColored(COL_ERR, 'This helper\'s Panel hit an error and was contained.');
    end
end

-- The tab body. job/level are the CURRENT job/level from the host; the tab
-- shows EVERY job's section regardless (a helper for another job shows dormant,
-- never vanishes -- PRD user story 4).
function M.renderTab(job, level)
    if not hasImgui then return; end
    local jobs = jh.jobs();
    if #jobs == 0 then
        imgui.TextColored(COL_DIM, 'No Job helper modules installed.');
        return;
    end

    imgui.TextColored(COL_DIM,
        'One row per installed helper, grouped by the jobs it supports. The pill is its master switch.');
    imgui.Spacing();

    local okL = imgui.BeginChild('##jh_left', { 380, 0 }, true);
    if okL then
        for _, j in ipairs(jobs) do jobSection(j); end
    end
    imgui.EndChild();

    imgui.SameLine();

    local okR = imgui.BeginChild('##jh_right', { 0, 0 }, true);
    if okR then renderPanel(); end
    imgui.EndChild();
end

-- Register the tab with the UI host -- ONLY when a module is loaded. Idempotent
-- (uihost.register replaces in place on a re-register). Called by dlac.lua after
-- the loader runs, and by the smoke suite. Returns true if it registered.
function M.maybeRegister(host)
    if type(host) ~= 'table' or type(host.register) ~= 'function' then return false; end
    if jh.count() < 1 then return false; end
    host.register({ name = 'jobhelpers', tabs = {
        { label = 'Job Helpers', render = function(j, lv) M.renderTab(j, lv); end },
    } });
    return true;
end

return M;
