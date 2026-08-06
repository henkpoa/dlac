--[[
    dlac/ui/jobbrowse.lua -- browse and BUILD for a job you are not on.

    "Sometimes you just want to edit other jobs, if you're waiting for someone or
    just had an idea" (Henrik, 2026-08-06). The Gear window's header grows a job
    picker; picking a job you are not on re-points the EDITORS -- Sets, Triggers,
    Groups, Modes, Blueprints, Weights -- at that job's files.

    PURELY BROWSING AND BUILDING. This module never equips, never claims a slot,
    never tells the engine anything. dispatch/equipengine read GetMainJob()
    themselves and have never asked the UI for a job, so the Arbiter keeps
    dressing your REAL job no matter what is on screen -- the separation is
    structural, not a rule anyone has to remember.

    TWO SEAMS, and this module is the only thing behind both:

      * WHICH JOB'S FILES  -- gearui's jobFile() consults M.selected(), and every
        file-shaped consumer already resolves through that one injected helper
        (profilesets, triggersui). setupui keeps the LIVE one: migration and shim
        repair are about the job you are standing on, never the one you are
        reading.
      * WHICH JOB THE TABS DRAW -- gearui hands (job, level) to host.renderTabs,
        and off-job that pair becomes (browsed, 75).

    WHY 75, FLAT. Henrik: "You do not need to know the job levels honestly... 99%
    of the time you build as lvl 75 either way." Asking the game for each job's
    real level is possible (GetJobLevel) and deliberately not done -- build-ahead
    is already how this codebase treats set building (the Sets tab allows
    over-level sets; the group browser is explicitly not level-gated), so one flat
    number is both simpler and closer to how sets actually get built. The one case
    it under-shows is a job taken past 75; that is one line to revisit if it ever
    bites.

    The level NEVER travels as staticMainLevel. That global is read by the ENGINE
    (dispatch, gearoptim, petfood, ammoui), so borrowing it to preview WAR would
    quietly re-level what your live job equips. Browsing owns its own number and
    hands it only to the tab renderers.

    Wearability needs nothing else: isUsable is gearOracle.canWear(rec, job,
    level) -- main job only, level-gated on the main level, no hidden live read --
    so "as if I were on WAR at 75" is literally those two arguments. The sub job
    never enters it.

    NOT PERSISTED. A view state, reset to live on load. A real job change does NOT
    clear the selection either: the set you are building for WAR stays valid when
    you change to BLM, and the header says loudly where you are.

    Every string built here is composed of fixed job abbreviations and literals --
    no player-supplied text reaches a text sink, so there is no esc() call to
    forget. Keep it that way (imgui text sinks are printf: an unescaped % prints a
    heap address).
]]--

local M = {};

-- The level every browsed job is viewed at. UI-only; see the header.
M.LEVEL = 75;

local _sel  = nil;    -- browsed job abbr; nil = follow the live job
local _list = nil;    -- combo snapshot, built on OPEN and dropped on close

local JOB_ABBR = {
    [1]='WAR',[2]='MNK',[3]='WHM',[4]='BLM',[5]='RDM',[6]='THF',[7]='PLD',[8]='DRK',
    [9]='BST',[10]='BRD',[11]='RNG',[12]='SAM',[13]='NIN',[14]='DRG',[15]='SMN',[16]='BLU',
    [17]='COR',[18]='PUP',[19]='DNC',[20]='SCH',[21]='GEO',[22]='RUN',
};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');

-- The job you are actually on (nil at character select / before GetMainJob
-- settles -- id 0 reads as no job, hard rule 11).
local function liveJob()
    local abbr = nil;
    pcall(function() abbr = JOB_ABBR[AshitaCore:GetMemoryManager():GetPlayer():GetMainJob()]; end);
    return abbr;
end
M.liveJob = liveJob;

-- The raw selection (nil = following live). Callers that need "which job am I
-- editing" want M.job(); this one is for the two seams that must know whether a
-- CHOICE was made.
function M.selected() return _sel; end

-- The job every editor should read/write: the browsed one, else the live one.
function M.job() return _sel or liveJob(); end

-- Are we looking at a job we are not on? nil live job (char select) with a
-- selection still counts -- the header should say so rather than look normal.
function M.active()
    if _sel == nil then return false; end
    return _sel ~= liveJob();
end

-- The level the tabs draw at: 75 while browsing, nil = "use the live reading".
function M.level()
    if M.active() then return M.LEVEL; end
    return nil;
end

-- Picking your own job means "follow live" -- so a later job change follows too.
function M.set(abbr)
    if abbr == nil or abbr == '' or abbr == liveJob() then _sel = nil; return; end
    _sel = tostring(abbr);
end

function M.clear() _sel = nil; end

-- Which jobs this character's ACTIVE profile already has files for. 66 file
-- probes (profiles.profileJobsAt), so it is snapshotted when the combo opens and
-- dropped when it closes -- never per frame. The Profiles menu sets the
-- precedent (ui._profMenuBuild: "snapshot is (re)built on open, never per frame").
local function buildList()
    local have = {};
    pcall(function()
        local prof = require('dlac\\profiles');
        if type(prof) ~= 'table' then return; end
        local rows = prof.profileJobsAt(prof.currentCharFolder(), prof.activeName());
        for _, r in ipairs(rows or {}) do
            if type(r) == 'table' and r.job ~= nil then have[tostring(r.job)] = true; end
        end
    end);
    local order = {};
    pcall(function()
        local prof = require('dlac\\profiles');
        if type(prof) == 'table' and type(prof.JOBS) == 'table' then order = prof.JOBS; end
    end);
    if #order == 0 then
        for i = 1, 22 do order[#order + 1] = JOB_ABBR[i]; end
    end
    local out = {};
    for _, j in ipairs(order) do out[#out + 1] = { job = j, has = (have[j] == true) }; end
    return out;
end

-- The rows INSIDE the open combo. Its own function so the caller can drive it
-- under a pcall and still reach EndCombo/PopItemWidth: a push or a Begin* left
-- unmatched is not a Lua error, it is native UB inside ImGui that no pcall
-- catches and that takes the whole client down (the floatgear crash, smoke S50).
local function drawRows(COL, cur, live)
    if _list == nil then
        local ok, l = pcall(buildList);
        _list = (ok and type(l) == 'table') and l or {};
    end
    for _, row in ipairs(_list) do
        if imgui.Selectable(row.job .. '##jb_' .. row.job, row.job == cur) then
            if row.job ~= cur then M.set(row.job); end
        end
        -- The two facts worth carrying per row: which job you are ON, and which
        -- ones dlac has nothing for yet. A job with no entry is still selectable
        -- -- the Triggers tab's own "Create starter triggers" button is how it
        -- gets one, so there is nothing extra to build here.
        if row.job == live then
            imgui.SameLine(); imgui.TextColored(COL.DIM, '(on)');
        elseif not row.has then
            imgui.SameLine(); imgui.TextColored(COL.DIM, '(new)');
        end
    end
end

-- THE PICKER. Drawn by gearui on the header row. The caller needs no return
-- value: a changed selection moves the `job` that drawWindow hands the tabs, and
-- the working-set drop already keys on that -- so switching the picker drops a
-- half-built set through the SAME path a real job change uses.
function M.render(COL)
    if imgui == nil then return; end
    local live = liveJob();
    local cur  = _sel or live;

    imgui.PushItemWidth(78);   -- themed font is wide: 3 chars + padding, no clip
    if imgui.BeginCombo('##dlac_jobsel', cur or '--') then
        pcall(drawRows, COL, cur, live);
        imgui.EndCombo();
    else
        _list = nil;           -- closed: the next open re-probes for new entries
    end
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Browse and build another job\'s sets and triggers, as if you were on\n'
            .. 'it at level 75. Editing only -- nothing equips, and your live job keeps\n'
            .. 'working exactly as it does now.');
    end
end

-- THE STATE MARKER. A banner under the header row while browsing: what you are
-- looking at, what you are actually on, and the one-click way back. Half of what
-- makes this safe is that browsing can never be mistaken for being there.
-- Returns true if the player clicked back to live.
function M.renderBanner(COL, textWrapped)
    if imgui == nil or not M.active() then return false; end
    local live = liveJob();
    local msg = '[!]  Viewing ' .. tostring(_sel) .. ' as level ' .. tostring(M.LEVEL)
        .. ' -- you are on ' .. (live or 'no job') .. '. Edits save to ' .. tostring(_sel)
        .. '\'s files; nothing equips.';
    -- Orange, the "do not read this as the live fact" shade.
    if textWrapped ~= nil then textWrapped(COL.WANT, msg); else imgui.TextColored(COL.WANT, msg); end
    local back = false;
    if live ~= nil then
        if imgui.SmallButton('Back to ' .. live .. '##dlac_jobback') then M.clear(); back = true; end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Return the editors to the job you are actually on.');
        end
    end
    return back;
end

return M;
