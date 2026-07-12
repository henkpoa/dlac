--[[
    dlac/macrobook.lua -- per-job macro book/set, owned by dlac (no profile edits).

    The classic LAC way is /macro commands in every profile's OnLoad; dlac owns
    it instead: set from the GUI header (the "Macro b-s" button), saved per job
    in <char>\dlac\macrobooks.lua, and applied automatically -- on login/reload
    (~5s, so the game is ready to take /macro) and on every job change (~2s).
    Runs entirely in the addon state (QueueCommand needs no engine), so there is
    nothing to Reload LAC for. A job with no saved entry is left alone: dlac
    never touches your macro palette unless you asked it to manage that job.

    Self-contained on purpose (gearui is near the 200-local chunk cap): own
    char path (same derivation as dlac.lua), job abbr from Ashita's resource
    strings, own tiny load/save. gearui only adds the header button + a pump
    call in its d3d_present hook.
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local hasImgui = _iok and imgui ~= nil;

local data = nil;          -- job abbr -> { book = 1..20, set = 1..10 }; nil until loaded
local appliedJob = nil;    -- job the session last applied for
local pendingJob = nil;    -- job change seen, apply at dueAt
local dueAt = nil;
local _openReq = false;    -- header button clicked -> OpenPopup next render

local COL_DIM = { 0.62, 0.62, 0.62, 1.0 };

local function charBase()
    local base = nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name  = party:GetMemberName(0);
        local id    = party:GetMemberServerId(0);
        if name == nil or name == '' or id == nil or id == 0 then return; end
        base = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\', AshitaCore:GetInstallPath(), name, id);
    end);
    return base;
end

local function jobAbbr()
    local abbr = nil;
    pcall(function()
        local j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob();
        if j == nil or j == 0 then return; end
        local s = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', j);
        if type(s) == 'string' and s ~= '' then abbr = s; end
    end);
    return abbr;
end

local function path()
    local base = charBase();
    return base and (base .. 'dlac\\macrobooks.lua') or nil;
end

local function load_()
    if data ~= nil then return; end
    local p = path(); if p == nil then return; end   -- pre-login: retry next call
    data = {};
    pcall(function()
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then data = t; end
    end);
end

local function save()
    local p = path(); if p == nil or data == nil then return; end
    local jobs = {};
    for j in pairs(data) do jobs[#jobs + 1] = j; end
    table.sort(jobs);
    local L = { '-- dlac macro book/set per job -- applied on login and job change.',
                '-- Managed from the GUI header ("Macro" button); jobs not listed are never touched.',
                'return {' };
    for _, j in ipairs(jobs) do
        local e = data[j];
        if type(e) == 'table' then
            L[#L + 1] = string.format('    %s = { book = %d, set = %d },',
                j, tonumber(e.book) or 1, tonumber(e.set) or 1);
        end
    end
    L[#L + 1] = '};';
    L[#L + 1] = '';
    pcall(function()
        local f = io.open(p, 'w');
        if f ~= nil then f:write(table.concat(L, '\n')); f:close(); end
    end);
end

local function apply(job)
    local e = (data ~= nil and job ~= nil) and data[job] or nil;
    if type(e) ~= 'table' then return; end
    pcall(function()
        local cm = AshitaCore:GetChatManager();
        cm:QueueCommand(1, string.format('/macro book %d', tonumber(e.book) or 1));
        cm:QueueCommand(1, string.format('/macro set %d', tonumber(e.set) or 1));
        print(string.format('[dlac] macro book %d, set %d (%s).', tonumber(e.book) or 1, tonumber(e.set) or 1, job));
    end);
end

-- Called every d3d_present (window visible or not). Applies the saved book/set
-- once per job: nil -> job (login/reload) waits ~5s, job -> job waits ~2s.
function M.pump()
    local job = jobAbbr();
    if job == nil then return; end
    load_();
    if data == nil then return; end
    if job ~= appliedJob and job ~= pendingJob then
        pendingJob = job;
        dueAt = os.clock() + ((appliedJob == nil) and 5 or 2);
    end
    if pendingJob ~= nil and dueAt ~= nil and os.clock() >= dueAt then
        appliedJob, pendingJob, dueAt = pendingJob, nil, nil;
        apply(appliedJob);
    end
end

-- ---------------------------------------------------------------------------
-- Macro book NAMES, read from the game's own title files: USER/<serverid hex>/
-- mcr.ttl (books 1-20) and mcr_2.ttl (21-40). Format (field-decoded): a
-- 24-byte header, then twenty 16-byte null-padded titles. The CatsEyeXI
-- bundle keeps the game at <Ashita>\..\Game\FINAL FANTASY XI\ -- when that
-- (or the files) is absent, the picker just shows numbers.
-- ---------------------------------------------------------------------------
local _namesAt, _names = 0, nil;
local function bookNames()
    if _names ~= nil and os.clock() < _namesAt then return _names; end
    _namesAt = os.clock() + 30;
    _names = {};
    pcall(function()
        local id = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0);
        if id == nil or id == 0 then return; end
        local userDir = string.format('%s..\\Game\\FINAL FANTASY XI\\USER\\%x\\',
            AshitaCore:GetInstallPath(), id);
        for page, fname in ipairs({ 'mcr.ttl', 'mcr_2.ttl' }) do
            local f = io.open(userDir .. fname, 'rb');
            if f ~= nil then
                local raw = f:read('*a');
                f:close();
                for i = 0, 19 do
                    local rec = raw:sub(0x19 + i * 16, 0x18 + (i + 1) * 16);
                    if rec ~= nil then
                        local nm = rec:gsub('%z.*$', ''):gsub('[^\32-\126]', '?');
                        if nm ~= '' then _names[(page - 1) * 20 + i + 1] = nm; end
                    end
                end
            end
        end
    end);
    return _names;
end

-- Header-button label: 'Macro 5-1' when managed for the current job, 'Macro --'
-- when not (or before login).
function M.label()
    load_();
    local e = (data ~= nil) and data[jobAbbr() or ''] or nil;
    if type(e) == 'table' then
        return string.format('Macro %d-%d', tonumber(e.book) or 1, tonumber(e.set) or 1);
    end
    return 'Macro --';
end

function M.open() _openReq = true; end

-- Popup body. OpenPopup/BeginPopup resolve ids per window, so the caller's
-- button only sets a flag (M.open) and this runs in the window scope each frame.
-- Books render like the GAME's own macro-book list (field request): names
-- visible immediately, fixed-width rows stacked top-to-bottom, TWO columns of
-- 20 (the two in-game pages). Sets 1-10 stay one number row. A click saves AND
-- applies on the spot -- never waits for a profile load.
local GOLD = { 0.42, 0.36, 0.16, 1.0 };
local function pickGrid(prefix, count, perRow, current)
    local picked = nil;
    for n = 1, count do
        local on = (n == current);
        if on then imgui.PushStyleColor(ImGuiCol_Button, GOLD); end
        if imgui.Button(tostring(n) .. '##' .. prefix .. n, { 26, 20 }) then picked = n; end
        if on then imgui.PopStyleColor(1); end
        if n % perRow ~= 0 and n < count then imgui.SameLine(0, 3); end
    end
    return picked;
end

-- One column of 20 book-name rows (the game-list look: tight, fixed width).
local function bookColumn(from, to, current, names)
    local picked = nil;
    imgui.BeginGroup();
    for n = from, to do
        local on = (n == current);
        if on then imgui.PushStyleColor(ImGuiCol_Button, GOLD); end
        local nm = names[n] or ('Book ' .. n);
        if imgui.Button(nm .. '##mbk' .. n, { 124, 19 }) then picked = n; end
        if on then imgui.PopStyleColor(1); end
        if imgui.IsItemHovered() then imgui.SetTooltip(string.format('book %d: %s', n, nm)); end
    end
    imgui.EndGroup();
    return picked;
end

function M.renderPopup()
    if not hasImgui then return; end
    if _openReq then _openReq = false; imgui.OpenPopup('##dlac_macrobook'); end
    if not imgui.BeginPopup('##dlac_macrobook') then return; end
    local job = jobAbbr();
    load_();
    if job == nil or data == nil then
        imgui.TextColored(COL_DIM, 'No job yet (not logged in?).');
        imgui.EndPopup();
        return;
    end
    local e = data[job];
    if type(e) ~= 'table' then
        imgui.Text(string.format('Macro palette for %s', job));
        imgui.TextColored(COL_DIM, 'Not managed: dlac leaves this job\'s macro book alone.');
        if imgui.Button('Manage ' .. job .. '\'s macro book##mbon') then
            data[job] = { book = 1, set = 1 };
            save();
        end
        imgui.EndPopup();
        return;
    end
    local names = bookNames();
    local curBook, curSet = tonumber(e.book) or 1, tonumber(e.set) or 1;
    imgui.Text(string.format('Macro palette for %s', job));
    imgui.SameLine(0, 10);
    local curName = names[curBook];
    imgui.TextColored(COL_DIM, string.format('book %d%s -- set %d   (applied NOW and on every login / job change)',
        curBook, (curName ~= nil) and (' "' .. curName .. '"') or '', curSet));
    imgui.Spacing();
    -- the game-list look: tight rows
    local styled = (ImGuiStyleVar_ItemSpacing ~= nil);
    if styled then imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 3, 2 }); end
    local p1 = bookColumn(1, 20, curBook, names);
    imgui.SameLine(0, 6);
    local p2 = bookColumn(21, 40, curBook, names);
    if styled then imgui.PopStyleVar(1); end
    local pb = p1 or p2;
    imgui.Spacing();
    imgui.TextColored(COL_DIM, 'Set:');
    local ps = pickGrid('mst', 10, 10, curSet);
    if pb ~= nil or ps ~= nil then
        e.book = pb or curBook;
        e.set  = ps or curSet;
        save();
        apply(job);   -- on the spot -- never wait for a profile load
    end
    imgui.Spacing();
    if imgui.SmallButton('Stop managing##mboff') then
        data[job] = nil;
        save();
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Forget the saved book/set for ' .. job .. ' -- dlac stops touching\nits macro palette (the game keeps whatever is active).');
    end
    imgui.EndPopup();
end

return M;
