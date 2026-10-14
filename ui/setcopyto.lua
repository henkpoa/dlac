--[[
    dlac/ui/setcopyto.lua -- the Sets tab's "Copy to...": one set, many jobs.

    Henrik 2026-10-14: "In sets, we have a "Copy From..", I want to add "Copy
    To..." where you copy that set to other jobs, when you click that, get a list
    of jobs that you wanna copy the set to, so it's easy to bring general sets to
    every job you have."

    Manage... > Copy to... opens a list of every OTHER job with a tick box each.
    Copy writes the selected set into each ticked job's sets file under the SAME
    name, through setmanager.commitSet -- the Commit button's own rails: a
    parse check, and a backup of the file before it is written.

    THE RULES, each one a decision:

      * WHAT IS COPIED is the set as the Sets tab shows it -- uncommitted edits
        included, and the receipt says so. The source set itself is not touched.
      * A NAME ALREADY THERE IS REPLACED. That is what "bring my Idle set to every
        job" means the second time you do it, after improving it. The row says
        "replaces" before you tick it, the button's line says it again, and the
        file is backed up before the write.
      * GEAR THE JOB CANNOT WEAR IS LEFT OUT there (setimport.workingForJob) and
        named in chat, ONE line for the whole copy. Copied as it is, the piece
        would be a candidate the flatten still picks and the server refuses.
        Virtual entries (dlac:AutoStaff ...) always travel: the engine resolves
        them for the job it is on.
      * MODE GATES travel as written. Modes live per job entry, so a gated piece
        only equips on a job that has that Mode -- one chat line names the gates
        rather than guessing which jobs have them.
      * A JOB DLAC HAS NEVER SEEN starts with the four empty base sets plus this
        one (setmanager's commitTarget), so its first visit finds what the
        starter triggers point at.
      * "ALL MY JOBS" ticks every job the character has unlocked (level 1+) --
        "every job you have". Any job can still be ticked by hand.

    Lives outside gearui because gearui's main chunk sits at the 200-local cap;
    gearui hands it what it needs ONCE (M.configure) and calls M.open / M.render.
    Every player-supplied string (the set name) reaches an imgui text sink only
    through esc() -- those sinks are printf.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');

-- Injected by gearui (M.configure):
--   working()        -> the Sets tab's working model (slotLabel -> { entry, ... })
--   dirty()          -> true while that model holds uncommitted edits
--   slotsFor(w)      -> setmanager's ordered commit slots for a working model
--   slotLabels       -> EQUIP_SLOTS (the slot order)
--   canWear(rec,job) -> the job half of the wear gate
--   setStatus(m,err) -> the Sets tab's status line
--   setmgr           -> gear\setmanager
--   invalidate()     -> profilesets.invalidate
--   esc(s), COL      -> gearfmt.esc and gearui's palette
local deps = nil;
function M.configure(d) deps = d; end

local POPUP = '##dlac_setcopyto';
local COLW  = 168;   -- one grid column: tick + 'WAR' + level + 'replaces' in the themed font
local NCOL  = 3;

-- One copy session: what is being copied, the job rows (read ONCE, when the
-- popup opens -- never per frame), and the tick buffers.
local st = { want = false, job = nil, src = nil, rows = {}, marks = {}, err = nil };

local function readAll(p)
    if p == nil then return nil; end
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end

-- The job you are ON (nil before GetMainJob settles), as an abbreviation.
local function liveJob(jobs)
    local abbr = nil;
    pcall(function() abbr = jobs[AshitaCore:GetMemoryManager():GetPlayer():GetMainJob()]; end);
    return abbr;
end

-- The character's level in job `id` (the game's job order, WAR = 1), or nil when
-- the game cannot say -- headless, or before login.
local function jobLevel(id)
    local lv = nil;
    pcall(function() lv = AshitaCore:GetMemoryManager():GetPlayer():GetJobLevel(id); end);
    return tonumber(lv);
end

-- One row per OTHER job, in the game's job order: { job, level, has, fresh }.
-- has   = that job's sets file already holds a set of this name (Copy replaces it)
-- fresh = dlac has no sets file for that job yet (Copy starts one)
local function buildRows(job, setName)
    local rows, err = {}, nil;
    local prof = try('dlac\\profiles');
    if prof == nil or type(prof.JOBS) ~= 'table' then return rows, 'profiles module unavailable.'; end
    if prof.setsPath(job) == nil then return rows, 'Log in first -- there is no profile to copy into.'; end
    for i, j in ipairs(prof.JOBS) do
        if j ~= job then
            local text = readAll(prof.setsPath(j));
            local has = false;
            pcall(function() has = deps.setmgr.hasSetText(text, setName) == true; end);
            rows[#rows + 1] = { job = j, level = jobLevel(i), has = has, fresh = (text == nil) };
        end
    end
    return rows, err;
end

-- The tick buffer for one job, created on demand.
local function mark(job)
    local b = st.marks[job];
    if b == nil then b = { false }; st.marks[job] = b; end
    return b;
end

function M.open(job, setName)
    if deps == nil then return; end
    st.job, st.src, st.marks = job, setName, {};
    st.rows, st.err = buildRows(job, setName);
    st.want = true;
end

-- Write the set into every ticked job, then tell the player what happened: the
-- receipt on the status line, the left-out pieces and the Mode gates in chat.
local function apply()
    local simport = require('dlac\\gear\\setimport');
    local name = st.src;
    local working = deps.working() or {};
    local srcSlots = #(deps.slotsFor(working) or {});
    local live = nil;
    pcall(function() live = liveJob(require('dlac\\profiles').JOBS); end);
    local results, perJob, wroteLive = {}, {}, false;
    for _, row in ipairs(st.rows) do
        local b = st.marks[row.job];
        if b ~= nil and b[1] == true then
            local job = row.job;
            local r = simport.workingForJob(working, deps.slotLabels,
                function(rec) return deps.canWear(rec, job); end);
            local slots = deps.slotsFor(r.working) or {};
            local ok, action = nil, nil;
            local pok, perr = pcall(function() ok, action = deps.setmgr.commitSet(job, name, slots); end);
            local res = { job = job, ok = (pok and ok == true) };
            if res.ok then
                res.replaced = (tostring(action):find('^replaced') ~= nil);
                res.empty = (#slots == 0 and srcSlots > 0);
                perJob[#perJob + 1] = { job = job, dropped = r.dropped };
                if job == live then wroteLive = true; end
            else
                res.err = pok and tostring(action) or tostring(perr);
            end
            results[#results + 1] = res;
        end
    end
    if #results == 0 then deps.setStatus('Tick at least one job first.', true); return; end

    local dropNote, leftOut = simport.copyToDropNote(perJob, 8);
    if dropNote ~= nil then
        pcall(print, string.format('[dlac] Copy "%s": left out where the job cannot wear it -- %s.', name, dropNote));
    end
    local gates, gated = simport.modeGates(working, deps.slotLabels);
    if gated > 0 and #perJob > 0 then
        pcall(print, string.format('[dlac] Copy "%s": %d piece%s equip only under a Mode (%s) -- on a job without that Mode %s never equip.',
            name, gated, (gated == 1) and '' or 's', table.concat(gates, ', '), (gated == 1) and 'it' or 'they'));
    end
    if #perJob > 0 then
        pcall(deps.invalidate);
        -- Only the job you are ON has its sets loaded in the engine; any other
        -- job reads its file fresh when you change to it.
        if wroteLive then
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl sets reload'); end);
        end
    end
    local text, isErr = simport.copyToReceipt(name, results, leftOut, deps.dirty() == true);
    deps.setStatus(text, isErr);
end

-- Tick every job the character has unlocked. When the game reports no level for
-- ANY job (headless, mid-login) there is nothing to tell them apart by, so all.
local function tickMine()
    local anyKnown = false;
    for _, r in ipairs(st.rows) do if r.level ~= nil then anyKnown = true; break; end end
    for _, r in ipairs(st.rows) do
        mark(r.job)[1] = (not anyKnown) or ((r.level or 0) > 0);
    end
end

-- One grid cell: the tick (dimmed for a job not unlocked yet), its level, and
-- "replaces" when the job already has a set of this name.
local function drawCell(r, COL, esc)
    local dim = (r.level ~= nil and r.level <= 0) and ImGuiCol_Text ~= nil;
    if dim then imgui.PushStyleColor(ImGuiCol_Text, COL.UNOWN or COL.DIM); end
    imgui.Checkbox(r.job .. '##sct_' .. r.job, mark(r.job));
    if dim then imgui.PopStyleColor(1); end
    local tip = nil;
    if r.has then
        tip = string.format('%s already has a set named "%s" -- copying replaces it (the file is backed up first).', r.job, st.src);
    elseif r.fresh then
        tip = string.format('dlac has no sets for %s yet -- copying starts them, with the four empty base sets.', r.job);
    end
    if tip ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(esc(tip)); end
    if r.level ~= nil and r.level > 0 then
        imgui.SameLine(0, 4); imgui.TextColored(COL.DIM, tostring(r.level));
    end
    if r.has then
        imgui.SameLine(0, 6); imgui.TextColored(COL.WANT, 'replaces');
        if imgui.IsItemHovered() then imgui.SetTooltip(esc(tip)); end
    end
end

-- Everything between BeginPopup and EndPopup. It opens nothing it could leave
-- open (no child, and the one style push is popped on the next line), so the
-- caller can run it under a pcall and still reach EndPopup.
local function body()
    local COL, esc = deps.COL, deps.esc;
    if st.err ~= nil then imgui.TextColored(COL.ERR, esc(st.err)); end
    if #st.rows == 0 then
        if st.err == nil then imgui.TextColored(COL.DIM, 'No other job to copy to.'); end
        if imgui.Button('Close##sctclose', { 90, 24 }) then imgui.CloseCurrentPopup(); end
        return;
    end

    -- The grid: NCOL columns, game job order, read left to right.
    local x0 = 8;
    pcall(function() x0 = imgui.GetCursorPosX(); end);
    for i, r in ipairs(st.rows) do
        local col = (i - 1) % NCOL;
        if col > 0 then imgui.SameLine(x0 + col * COLW); end
        drawCell(r, COL, esc);
    end

    imgui.Spacing();
    if imgui.SmallButton('All my jobs##sctall') then tickMine(); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Tick every job you have unlocked (level 1 or higher).');
    end
    imgui.SameLine(0, 6);
    if imgui.SmallButton('None##sctnone') then
        for _, b in pairs(st.marks) do b[1] = false; end
    end

    local n, reps = 0, 0;
    for _, r in ipairs(st.rows) do
        local b = st.marks[r.job];
        if b ~= nil and b[1] == true then
            n = n + 1;
            if r.has then reps = reps + 1; end
        end
    end
    if reps > 0 then
        imgui.TextColored(COL.WANT, esc(string.format('%d ticked job%s already ha%s a "%s" -- copying replaces it.',
            reps, (reps == 1) and '' or 's', (reps == 1) and 's' or 've', st.src)));
    end

    imgui.Separator();
    if n > 0 then
        if imgui.Button(string.format('Copy to %d job%s##sctgo', n, (n == 1) and '' or 's'), { 0, 24 }) then
            imgui.CloseCurrentPopup();
            apply();
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(esc(string.format('Writes "%s" into each ticked job\'s sets, under the same name\n'
                .. '(each file is backed up first). Gear a job cannot wear is left out\n'
                .. 'there and named in chat. This job\'s own set is not touched.', st.src)));
        end
    else
        imgui.TextColored(COL.DIM, 'Tick the jobs to copy into.');
    end
    imgui.SameLine(0, 8);
    if imgui.Button('Cancel##sctcancel', { 90, 24 }) then imgui.CloseCurrentPopup(); end
end

-- Drawn every Sets-tab frame, in the window scope (never inside the Manage...
-- combo's own popup -- the same one-shot OpenPopup rule as its siblings).
function M.render()
    if imgui == nil or deps == nil then return; end
    if st.want then imgui.OpenPopup(POPUP); st.want = false; end
    if not imgui.BeginPopup(POPUP) then return; end
    local ok, err = pcall(body);
    if not ok then
        pcall(function() imgui.TextColored(deps.COL.ERR, deps.esc('Copy to failed: ' .. tostring(err))); end);
    end
    imgui.EndPopup();
end

-- Headless seams.
M._state = st;
M._apply = apply;
M._tickMine = tickMine;
M._buildRows = buildRows;

return M;
