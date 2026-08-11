--[[
    dlac/macrobook.lua -- per-job macro book/page, owned by dlac (no profile edits).

    The classic LAC way is /macro commands in every profile's OnLoad; dlac owns
    it instead: set from the Menu ("Macro book"), saved per job in
    <char>\dlac\macrobooks.lua, and applied automatically -- on login/reload
    (~5s, so the game is ready to take /macro) and on every job change (~2s).
    Runs entirely in the addon state (QueueCommand needs no engine), so there is
    nothing to Reload LAC for. A job with no saved entry is left alone: dlac
    never touches your macro palette unless you asked it to manage that job.

    PAGES, AND PAGES PER SUBJOB (2026-08-11, field request). A book holds ten
    pages -- `/macro set N` -- and which page you want usually depends on the
    SUBJOB, not the main job: WAR/NIN wants the dual-wield page, WAR/SAM the
    two-hander one, same book either way. So an entry is

        WAR = { book = 5, page = 1, subs = { NIN = 2, SAM = 3 } },

    where `page` is the fallback and `subs[<sub abbr>]` overrides it. The pump
    keys on main AND sub, so changing only your subjob re-applies. The stored
    key is `page` (`set` from older files migrates on read): "set" means a GEAR
    set everywhere else in dlac, and one name means one thing.

    The two commands are FRAME-SPACED through lib\cmdqueue, never queued back to
    back: two QueueCommands in one frame can arrive reversed, and a `/macro book`
    landing after its `/macro set` would leave you on page 1 -- which is exactly
    what the field reported.

    Self-contained on purpose (gearui is near the 200-local chunk cap): own
    char path (same derivation as dlac.lua), job abbr from Ashita's resource
    strings, own tiny load/save. gearui only adds the popup render + a pump
    call in its d3d_present hook.
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local hasImgui = _iok and imgui ~= nil;

local data = nil;          -- job abbr -> { book = 1..40, page = 1..10, subs = { ABBR = page } }; nil until loaded
local appliedKey = nil;    -- 'WAR/NIN' the session last applied for
local pendingKey = nil;    -- job/sub change seen, apply at dueAt
local pendingJob, pendingSub = nil, nil;
local dueAt = nil;
local _openReq = false;    -- menu row clicked -> OpenPopup next render
local _extraRows = {};     -- 'WAR/NIN' -> true: a subjob row asked for from the
                           -- combo but not yet given a page. Session-only on
                           -- purpose -- an empty row saves nothing.

local COL_DIM  = { 0.62, 0.62, 0.62, 1.0 };
local COL_LIVE = { 0.85, 0.78, 0.45, 1.0 };   -- the subjob you are actually on

-- Every imgui text sink is printf ([[imgui-geometry-laws]] #5). Book titles come
-- out of the game's own .ttl files, so a '%' in one is the player's to type.
local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

-- The "+ subjob" combo roster: the client's own job ordering, taken from the
-- addon-state gate that already owns it (gear\jobgate.JOBS). A 23rd job would
-- otherwise have to be remembered in one more place -- and GRD4 exists to stop
-- exactly that.
local JOBS = (function()
    local ok, jg = pcall(require, 'dlac\\gear\\jobgate');
    if ok and type(jg) == 'table' and type(jg.JOBS) == 'table' then return jg.JOBS; end
    return {};   -- no gate: the combo is empty, every other row still works
end)();

-- (charBase -- the luashitacast composition -- is GONE, 2026-08-05: it fed only
-- dataDir's fallback, and that fallback was unreachable. Same removal, same
-- reason as feature\lockstyle.)

-- Main and sub abbreviations, or nil each. Job id 0 is NOT a job (hard rule 11:
-- the resource manager stringifies 0 to "NON") -- at login, and for a character
-- with no subjob, that must read as nil and not as a job called NON.
local function jobAbbrs()
    local mj, sj = nil, nil;
    pcall(function()
        local p  = AshitaCore:GetMemoryManager():GetPlayer();
        local rm = AshitaCore:GetResourceManager();
        local a, b = p:GetMainJob(), p:GetSubJob();
        if a ~= nil and a ~= 0 then
            local s = rm:GetString('jobs.names_abbr', a);
            if type(s) == 'string' and s ~= '' then mj = s; end
        end
        if b ~= nil and b ~= 0 then
            local s = rm:GetString('jobs.names_abbr', b);
            if type(s) == 'string' and s ~= '' then sj = s; end
        end
    end);
    return mj, sj;
end

local function jobAbbr() local mj = jobAbbrs(); return mj; end

-- The dlac data home (mode-aware -- feature/native-engine): profiles.dataDir()
-- with the legacy composition as fallback.
local function dataDir()
    local ok, prof = pcall(require, 'dlac\\profiles');
    if ok and type(prof) == 'table' and type(prof.dataDir) == 'function' then
        local ok2, d = pcall(prof.dataDir);
        if ok2 and d ~= nil then return d; end
    end
    return nil;   -- native home or nothing (purge Phase 4: no legacy composition)
end

local function path()
    local d = dataDir();
    return d and (d .. 'macrobooks.lua') or nil;
end

-- ---------------------------------------------------------------------------
-- PURE SEAMS (tested headlessly): the page a job/sub resolves to, the on-read
-- migration, and the file text. No imgui, no AshitaCore, no io.
-- ---------------------------------------------------------------------------

-- One entry, one subjob -> the page to select. The sub override wins; the
-- entry's own page is the fallback; 1 is the floor.
function M._pageFor(e, sub)
    if type(e) ~= 'table' then return 1; end
    if sub ~= nil and type(e.subs) == 'table' then
        local p = tonumber(e.subs[sub]);
        if p ~= nil and p >= 1 and p <= 10 then return math.floor(p); end
    end
    local p = tonumber(e.page) or tonumber(e.set) or 1;   -- `set`: pre-08-11 files
    if p < 1 or p > 10 then return 1; end
    return math.floor(p);
end

-- Files written before 2026-08-11 name the page `set`. Fold it in on read and
-- drop it, so exactly one key is ever written back.
function M._normalize(t)
    if type(t) ~= 'table' then return {}; end
    for _, e in pairs(t) do
        if type(e) == 'table' then
            if e.page == nil and e.set ~= nil then e.page = tonumber(e.set); end
            e.set = nil;
            if type(e.subs) ~= 'table' then e.subs = nil; end
        end
    end
    return t;
end

-- The saved file, as text. Job abbreviations are plain identifiers, but the
-- table is only as trustworthy as whoever edited the file -- anything that is
-- not a three-letter abbr with a 1..10 page is dropped rather than written into
-- a chunk that would then fail to load.
function M._serialize(t)
    local jobs = {};
    for j in pairs(type(t) == 'table' and t or {}) do
        if type(j) == 'string' and j:match('^%a%a%a$') then jobs[#jobs + 1] = j; end
    end
    table.sort(jobs);
    local L = { '-- dlac macro book/page per job -- applied on login, job change and subjob change.',
                '-- Managed from the Menu ("Macro book"); jobs not listed are never touched.',
                '-- page = the fallback; subs.<SUB> = the page to use on that subjob.',
                'return {' };
    for _, j in ipairs(jobs) do
        local e = t[j];
        if type(e) == 'table' then
            local subs = '';
            local ks = {};
            if type(e.subs) == 'table' then
                for k, v in pairs(e.subs) do
                    local p = tonumber(v);
                    if type(k) == 'string' and k:match('^%a%a%a$') and p ~= nil and p >= 1 and p <= 10 then
                        ks[#ks + 1] = k;
                    end
                end
            end
            table.sort(ks);
            if #ks > 0 then
                local parts = {};
                for _, k in ipairs(ks) do
                    parts[#parts + 1] = string.format('%s = %d', k, math.floor(tonumber(e.subs[k])));
                end
                subs = string.format(', subs = { %s }', table.concat(parts, ', '));
            end
            L[#L + 1] = string.format('    %s = { book = %d, page = %d%s },',
                j, tonumber(e.book) or 1, M._pageFor(e, nil), subs);
        end
    end
    L[#L + 1] = '};';
    L[#L + 1] = '';
    return table.concat(L, '\n');
end

-- ---------------------------------------------------------------------------

local function load_()
    if data ~= nil then return; end
    local p = path(); if p == nil then return; end   -- pre-login: retry next call
    data = {};
    pcall(function()
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then data = M._normalize(t); end
    end);
end

local function save()
    local p = path(); if p == nil or data == nil then return; end
    local text = M._serialize(data);
    pcall(function()
        local f = io.open(p, 'w');
        if f ~= nil then f:write(text); f:close(); end
    end);
end

-- Book first, page two frames later. cmdqueue is the house door for issuing a
-- game command (Henrik's ruling 2026-07-29) AND the frame-spacing this pair
-- needs: same-frame QueueCommands can arrive reversed, and `/macro book` after
-- `/macro set` drops you back to page 1.
local function issue(cmd, delayFrames)
    local ok = pcall(function()
        require('dlac\\lib\\cmdqueue').enqueue(delayFrames, cmd);
    end);
    if not ok then
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
    end
end

-- One edit, one line -- and the line names WHAT YOU EDITED. `apply` below speaks
-- for the palette you are wearing; this speaks for a page you configured for a
-- pair you are not on. Field-caught 2026-08-11: setting BLU/WHM to page 3 while
-- on BLU/NIN echoed back "book 5, page 2 (BLU/NIN)" -- every edit called apply,
-- so the ack described the live pair no matter what the click touched.
local function ack(fmt, ...) print('[dlac] ' .. string.format(fmt, ...)); end

local function apply(job, sub)
    local e = (data ~= nil and job ~= nil) and data[job] or nil;
    if type(e) ~= 'table' then return; end
    local book = tonumber(e.book) or 1;
    local page = M._pageFor(e, sub);
    issue(string.format('/macro book %d', book), 0);
    issue(string.format('/macro set %d', page), 2);
    print(string.format('[dlac] macro book %d, page %d (%s).', book, page,
        job .. ((sub ~= nil) and ('/' .. sub) or '')));
end

-- Called every d3d_present (window visible or not). Applies the saved book/page
-- once per main+sub pair: nil -> job (login/reload) waits ~5s, a change waits ~2s.
-- The SUB is part of the key on purpose -- swapping only your subjob is the whole
-- reason the sub pages exist, and the main job never changes for it.
function M.pump()
    local job, sub = jobAbbrs();
    if job == nil then return; end
    load_();
    if data == nil then return; end
    local key = job .. '/' .. (sub or '-');
    if key ~= appliedKey and key ~= pendingKey then
        pendingKey, pendingJob, pendingSub = key, job, sub;
        dueAt = os.clock() + ((appliedKey == nil) and 5 or 2);
    end
    if pendingKey ~= nil and dueAt ~= nil and os.clock() >= dueAt then
        local j, s = pendingJob, pendingSub;
        appliedKey = pendingKey;
        pendingKey, pendingJob, pendingSub, dueAt = nil, nil, nil, nil;
        apply(j, s);
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

-- Header-button label: 'Macro 5-1' when managed for the current job/sub,
-- 'Macro --' when not (or before login).
function M.label()
    load_();
    local job, sub = jobAbbrs();
    local e = (data ~= nil) and data[job or ''] or nil;
    if type(e) == 'table' then
        return string.format('Macro %d-%d', tonumber(e.book) or 1, M._pageFor(e, sub));
    end
    return 'Macro --';
end

function M.open() _openReq = true; end

-- Popup body. OpenPopup/BeginPopup resolve ids per window, so the caller's
-- button only sets a flag (M.open) and this runs in the window scope each frame.
-- Books render like the GAME's own macro-book list (field request): names
-- visible immediately, fixed-width rows stacked top-to-bottom, TWO columns of
-- 20 (the two in-game pages). A click saves AND applies on the spot -- never
-- waits for a profile load.
--
-- There is no "manage this job" step and no "stop managing" button (2026-08-11,
-- Henrik: everyone running dlac wants this, so both buttons were asking a
-- question nobody has). Picking a book IS the opt-in; a job you never pick a
-- book for is still never touched, which is the only state anyone needs. The
-- only thing you can take back is a SUBJOB row, and its 'x' sits on the row.
local GOLD = { 0.42, 0.36, 0.16, 1.0 };
local function pickGrid(prefix, count, perRow, current, w)
    local picked = nil;
    for n = 1, count do
        local on = (n == current);
        if on then imgui.PushStyleColor(ImGuiCol_Button, GOLD); end
        if imgui.Button(tostring(n) .. '##' .. prefix .. n, { w or 26, 20 }) then picked = n; end
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
        if imgui.IsItemHovered() then imgui.SetTooltip(esc(string.format('book %d: %s', n, nm))); end
    end
    imgui.EndGroup();
    return picked;
end

-- One "<label>  [1][2]...[10]" page row. `current` nil = nothing highlighted:
-- that subjob has no page of its own and follows the fallback. The grid starts
-- at a fixed x so every row lines up under the book columns. Returns the page
-- clicked (or nil) AND whether the LABEL was hovered -- the caller emits the
-- tooltip once it has finished the row, so nothing lands between two items that
-- are meant to share a line.
local LABEL_X, PAGE_BTN_W = 46, 22;
local function pageRow(id, label, col, current)
    imgui.TextColored(col, esc(label));
    local hov = imgui.IsItemHovered();
    imgui.SameLine(0, 0);
    pcall(function() imgui.SetCursorPosX(LABEL_X); end);
    return pickGrid(id, 10, 10, current, PAGE_BTN_W), hov;
end

function M.renderPopup()
    if not hasImgui then return; end
    if _openReq then _openReq = false; imgui.OpenPopup('##dlac_macrobook'); end
    if not imgui.BeginPopup('##dlac_macrobook') then return; end
    local job, sub = jobAbbrs();
    load_();
    if job == nil or data == nil then
        imgui.TextColored(COL_DIM, 'No job yet (not logged in?).');
        imgui.EndPopup();
        return;
    end
    local e = data[job];
    local names = bookNames();
    local curBook = (type(e) == 'table') and (tonumber(e.book) or 1) or nil;
    local who = job .. ((sub ~= nil) and ('/' .. sub) or '');

    -- SHORTEST header that still works: 'Macros' + one dim info line (field-
    -- trimmed twice; a long title is what stretches an auto-sized popup).
    imgui.Text('Macros');
    imgui.SameLine(0, 10);
    if curBook == nil then
        imgui.TextColored(COL_DIM, esc(who .. ': pick a book.'));
    else
        local nm = names[curBook];
        imgui.TextColored(COL_DIM, esc(string.format('%s: %d%s - page %d', who, curBook,
            (nm ~= nil) and (' "' .. nm .. '"') or '', M._pageFor(e, sub))));
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Applied immediately on click, and again on every login,\njob change and subjob change.');
    end
    imgui.Spacing();

    -- the game-list look: tight rows; nudged right so the columns sit centered
    -- over the (slightly wider) page rows below
    local styled = (ImGuiStyleVar_ItemSpacing ~= nil);
    if styled then imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 3, 2 }); end
    pcall(function() imgui.SetCursorPosX(imgui.GetCursorPosX() + 16); end);
    local p1 = bookColumn(1, 20, curBook, names);
    imgui.SameLine(0, 6);
    local p2 = bookColumn(21, 40, curBook, names);
    if styled then imgui.PopStyleVar(1); end
    local pb = p1 or p2;
    if pb ~= nil then
        if type(e) ~= 'table' then
            e = { book = pb, page = 1 };     -- picking a book IS the opt-in
            data[job] = e;
        else
            e.book = pb;
        end
        save();
        apply(job, sub);   -- on the spot -- never wait for a profile load
    end

    -- Books only until this job is managed: there is no page to pick yet.
    if type(e) ~= 'table' then
        imgui.Spacing();
        imgui.TextColored(COL_DIM, esc('dlac leaves ' .. job .. '\'s macros alone until you pick one.'));
        imgui.EndPopup();
        return;
    end

    imgui.Spacing();
    local basePage = M._pageFor(e, nil);
    -- The live sub's own page, if it has one: while that is in force the
    -- fallback below is not what you are wearing, and editing it must not send
    -- commands OR report as though it had.
    local liveOverride = (sub ~= nil and type(e.subs) == 'table') and tonumber(e.subs[sub]) or nil;
    local pp, pHov = pageRow('mpg', 'Page', COL_DIM, basePage);
    if pHov then
        imgui.SetTooltip('The page (/macro set) this book opens on.\nA subjob row below overrides it while you are on that sub.');
    end
    if pp ~= nil then
        e.page = pp;
        save();
        if liveOverride == nil then
            apply(job, sub);
        else
            ack('macro page %d saved for %s -- %s is on its own page %d.', pp, job, sub, liveOverride);
        end
    end

    -- Subjob rows: the one you are ON (always offered -- that is the common
    -- case, "set the page for what I am playing right now"), then every sub
    -- that already has a page, then anything added from the combo this session.
    local order, seen = {}, {};
    local function addRow(s)
        if type(s) == 'string' and s ~= '' and s ~= job and not seen[s] then
            seen[s] = true; order[#order + 1] = s;
        end
    end
    addRow(sub);
    if type(e.subs) == 'table' then
        local ks = {};
        for k, v in pairs(e.subs) do
            if type(k) == 'string' and tonumber(v) ~= nil and not seen[k] then ks[#ks + 1] = k; end
        end
        table.sort(ks);
        for _, k in ipairs(ks) do addRow(k); end
    end
    for _, j in ipairs(JOBS) do
        if _extraRows[job .. '/' .. j] then addRow(j); end
    end

    for _, s in ipairs(order) do
        local key = job .. '/' .. s;
        local cur = (type(e.subs) == 'table') and tonumber(e.subs[s]) or nil;
        local ps, sHov = pageRow('mpg' .. s, s, (s == sub) and COL_LIVE or COL_DIM, cur);
        -- The row goes away with the 'x'. It is only offered when there IS
        -- something to remove -- a page of its own, or a row you added from the
        -- combo. The sub you are ON keeps its (unhighlighted) row either way:
        -- that row is an offer, not something you put there.
        local xHov = false;
        if cur ~= nil or _extraRows[key] then
            imgui.SameLine(0, 6);
            if imgui.SmallButton('x##mpgx' .. s) then
                if type(e.subs) == 'table' then e.subs[s] = nil; end
                _extraRows[key] = nil;
                save();
                if s == sub then
                    apply(job, sub);            -- your own page went: fall back now
                elseif cur ~= nil then
                    ack('macro page for %s/%s cleared -- you are on %s.', job, s, who);
                end                             -- an empty row you added says nothing
            end
            xHov = imgui.IsItemHovered();
        end
        if sHov then
            imgui.SetTooltip(esc(string.format('%s/%s uses this page.%s', job, s,
                (cur == nil) and (' Unset -- it follows page ' .. basePage .. '.') or '')));
        elseif xHov then
            imgui.SetTooltip(esc(string.format('Remove %s -- %s/%s goes back to page %d.', s, job, s, basePage)));
        end
        if ps ~= nil then
            e.subs = (type(e.subs) == 'table') and e.subs or {};
            e.subs[s] = ps;
            save();
            if s == sub then
                apply(job, sub);                -- the pair you are wearing: apply it
            else
                ack('macro page %d saved for %s/%s -- you are on %s.', ps, job, s, who);
            end
        end
    end

    -- (Push/PopItemWidth unguarded, like every other combo in the addon: a pcall
    -- around only ONE of the pair is how a stack goes unbalanced, which is native
    -- UB no pcall would catch anyway.)
    pcall(function() imgui.SetCursorPosX(LABEL_X); end);
    imgui.PushItemWidth(120);
    if imgui.BeginCombo('##mbsubadd', '+ subjob') then
        for _, j in ipairs(JOBS) do
            if j ~= job and not seen[j] then
                if imgui.Selectable(j .. '##mbsa' .. j, false) then _extraRows[job .. '/' .. j] = true; end
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Add a page row for a subjob you are not on right now.');
    end
    imgui.EndPopup();
end

return M;
