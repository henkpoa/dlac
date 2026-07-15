--[[
    dlac/lockstyle.lua -- LOCKSTYLE SETS: a new set type (Henrik, 07-14). NOT
    dynamic sets -- one item name per visual slot, saved in numbered boxes and
    applied through LuaAshitacast's own packet builder (gFunc.LockStyle).

    Window (armor button in the gearui header): the Equipped-tab 4x4 grid on
    the left EDITS the working lockstyle (click a slot -> pick from your
    gear.lua items for it); to the right, 30 boxes (3 columns x 10 rows, the
    macro-menu look) hold the saved lockstyle sets. The MARKED box (gold) is
    where Save lands, box 1 is marked until you pick another. Switching boxes
    with unsaved changes warns first -- continuing DISCARDS the edits.

    Storage: <char>\dlac\profiles\<Name>\lockstyles\<JOB>.lua -- the boxes
    are PER JOB ENTRY (v41) { active, onload = {JOB=box}, slots }. Reads fall
    back per file: the v40 per-profile lockstyles.lua, then the pre-profile
    global dlac\lockstyles.lua; every save serializes ALL boxes into the job
    entry's file, so older-tier boxes migrate whole on the first write.
    Switching profiles OR jobs reloads the boxes live.
    Apply is ENGINE-side ('/dl ls apply [box]' -- dispatch.lua v38 builds the
    table and calls gFunc.LockStyle; only the LAC state has gFunc). "OnLoad
    Lockstyle" binds CURRENT JOB -> MARKED BOX: the pump below (macrobook's
    login/job-change pattern) queues the apply ~6s after login / ~3s after a
    job change, when the game accepts lockstyle packets again.

    Self-contained on purpose (gearui is at the 200-local chunk cap, hard
    rule 1). gearui INJECTS its helpers via M.wire{} -- the 4x4 grid renderer,
    item icons/tooltips and the catalog name lookup -- instead of us requiring
    gearui (load order: this module loads before it).
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local hasImgui = _iok and imgui ~= nil;
local _gok, gear = pcall(require, 'dlac\\gear');
local _pok, profsets = pcall(require, 'dlac\\profilesets');
local _pfok, profiles = pcall(require, 'dlac\\profiles');
_pfok = _pfok and type(profiles) == 'table';

M.visible = false;

-- gearui-injected helpers: slotGrid (renderSlotGrid), icon (renderIcon),
-- tooltip (renderItemTooltip), catalog (lookupByName). All optional-guarded.
local W = {};
function M.wire(t) if type(t) == 'table' then for k, v in pairs(t) do W[k] = v; end end end

-- The slots lockstyle can SHOW (packet 0x53 carries equip slots 0-8 only;
-- gFunc.LockStyle filters the rest -- the grid dims them as "not visual").
local VISUAL = { Main = true, Sub = true, Range = true, Ammo = true, Head = true,
                 Body = true, Hands = true, Legs = true, Feet = true };
local N_BOXES, BOX_W = 30, 112;

local COL_DIM    = { 0.62, 0.62, 0.62, 1.0 };
local COL_HEADER = { 0.60, 0.75, 1.00, 1.0 };
local COL_WARN   = { 1.00, 0.55, 0.30, 1.0 };
local COL_USABLE = { 1.00, 1.00, 1.00, 1.0 };
local GOLD       = { 0.42, 0.36, 0.16, 1.0 };

-- ---------------------------------------------------------------------------
-- storage (macrobook pattern: own char path, own tiny load/save)
-- ---------------------------------------------------------------------------
local data = nil;   -- { active = 1..30, onload = { JOB = box }, slots = { [n] = { name, set = {Slot=Name} } } }

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

local function legacyPath()
    local base = charBase();
    return base and (base .. 'dlac\\lockstyles.lua') or nil;
end

-- which profile + job `data` was loaded for: a change in EITHER reloads the
-- boxes (job changes switch the job entry; the profile menu switches profiles)
local dataProf, dataJob = nil, nil;

local function load_()
    local prof = _pfok and profiles.activeName() or nil;
    local job = jobAbbr();
    if data ~= nil and prof == dataProf and job == dataJob then return; end
    if charBase() == nil or job == nil then return; end   -- pre-login: retry next call
    -- boxes are PER JOB ENTRY: the active profile's lockstyles\<JOB>.lua,
    -- falling back to the v40 per-profile file, then the pre-profile global
    -- one (profiles.lua is the shared path authority)
    local p = (_pfok and profiles.readLockstylesPath(job) or nil) or legacyPath();
    dataProf, dataJob = prof, job;
    data = { active = 1, onload = {}, slots = {} };  -- box 1 marked until chosen otherwise
    M._curReset();                                   -- profile switch: working copy follows
    pcall(function()
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then
            if tonumber(t.active) ~= nil then data.active = math.max(1, math.min(N_BOXES, tonumber(t.active))); end
            if type(t.onload) == 'table' then data.onload = t.onload; end
            if type(t.slots) == 'table' then data.slots = t.slots; end
        end
    end);
end

-- Pure serializer (headless-tested): data table -> file text.
function M._serialize(d)
    local L = { '-- dlac lockstyle sets -- written by the GUI (header armor button); safe to hand-edit.',
                '-- active = the marked box; onload.<JOB> = box applied on login/job change for that job.',
                'return {',
                string.format('    active = %d,', tonumber(d.active) or 1),
                '    onload = {' };
    local jobs = {};
    for j in pairs(d.onload or {}) do jobs[#jobs + 1] = j; end
    table.sort(jobs);
    for _, j in ipairs(jobs) do
        local b = tonumber(d.onload[j]);
        if b ~= nil then L[#L + 1] = string.format('        %s = %d,', j, b); end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    slots = {';
    local ns = {};
    for n in pairs(d.slots or {}) do if tonumber(n) then ns[#ns + 1] = tonumber(n); end end
    table.sort(ns);
    for _, n in ipairs(ns) do
        local e = d.slots[n];
        if type(e) == 'table' and type(e.set) == 'table' then
            L[#L + 1] = string.format('        [%d] = { name = %q, set = {', n, tostring(e.name or ''));
            local ks = {};
            for k in pairs(e.set) do ks[#ks + 1] = k; end
            table.sort(ks);
            for _, k in ipairs(ks) do
                if type(e.set[k]) == 'string' then
                    L[#L + 1] = string.format('            %s = %q,', k, e.set[k]);
                end
            end
            L[#L + 1] = '        } },';
        end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '};';
    L[#L + 1] = '';
    return table.concat(L, '\n');
end

-- Writes ALWAYS land in the job entry (creating 'Default' storage on first
-- use -- the house compat rule); the whole table is serialized, so boxes
-- loaded off an older tier carry into the job entry on the first save.
-- dataJob (not the live job) keys the file: data must never save into a
-- different job's entry than it was loaded for.
local function save()
    if data == nil then return; end
    local p = nil;
    if _pfok and dataJob ~= nil then
        pcall(function() profiles.ensureStorage(); end);
        p = profiles.lockstylesPath(dataJob);
    end
    p = p or legacyPath();
    if p == nil then return; end
    pcall(function()
        local f = io.open(p, 'w');
        if f ~= nil then f:write(M._serialize(data)); f:close(); end
    end);
end

-- ---------------------------------------------------------------------------
-- working copy (what the 4x4 edits) -- always mirrors the MARKED box
-- ---------------------------------------------------------------------------
local cur = nil;            -- { set = {Slot=Name}, dirty = false }
local nameBuf = { '' };
local _status = nil;

-- load_ is defined above this local: a profile switch drops the working copy
-- through this hook (the M._touched pattern) and ensure() rebuilds it.
function M._curReset() cur = nil; end

local function loadBox()
    local e = data.slots[data.active];
    cur = { set = {}, dirty = false };
    if type(e) == 'table' and type(e.set) == 'table' then
        for k, v in pairs(e.set) do if VISUAL[k] and type(v) == 'string' then cur.set[k] = v; end end
    end
    nameBuf[1] = (type(e) == 'table' and type(e.name) == 'string') and e.name or '';
end

local function ensure()
    load_();
    if data ~= nil and cur == nil then loadBox(); end
    return data ~= nil and cur ~= nil;
end

local function switchTo(n)
    data.active = n;
    save();
    loadBox();
    _status = string.format('box %d marked%s.', n,
        (data.slots[n] ~= nil) and (' -- "' .. tostring(data.slots[n].name or '') .. '" loaded') or ' (empty)');
    -- a live preview follows the working copy -- forward-declared local, so the
    -- publish rides an upvalue set later (touchedRef), not a direct call
    if type(M._touched) == 'function' then M._touched(); end
end

-- ---------------------------------------------------------------------------
-- item picking: your gear.lua entries for one slot (Main/Range nest by skill)
-- ---------------------------------------------------------------------------
local function jobOK(rec, job)
    if type(rec.Jobs) ~= 'table' or job == nil then return true; end
    for _, j in ipairs(rec.Jobs) do
        if j == 'All' or j == job then return true; end
    end
    return false;
end

local function listFor(slot, job, q)
    local out = {};
    local function take(t)
        for _, rec in pairs(t) do
            if type(rec) == 'table' and type(rec.Name) == 'string'
               and jobOK(rec, job)
               and (q == '' or string.find(string.lower(rec.Name), q, 1, true) ~= nil) then
                out[#out + 1] = rec;
            end
        end
    end
    pcall(function()
        local t = _gok and gear[slot] or nil;
        if type(t) ~= 'table' then return; end
        if slot == 'Main' or slot == 'Range' then
            for _, byCat in pairs(t) do if type(byCat) == 'table' then take(byCat); end end
        else
            take(t);
        end
    end);
    table.sort(out, function(a, b)
        local la, lb = tonumber(a.Level) or 0, tonumber(b.Level) or 0;
        if la ~= lb then return la > lb; end
        return tostring(a.Name) < tostring(b.Name);
    end);
    return out;
end

local function recOf(name)
    if type(name) ~= 'string' or name == '' or name == 'remove' then return nil; end
    local rec = nil;
    pcall(function() rec = _gok and gear.NameToObject[name] or nil; end);
    if rec == nil and W.catalog ~= nil then pcall(function() rec = W.catalog(name); end); end
    return rec;
end

-- ---------------------------------------------------------------------------
-- Preview (Henrik's design, round 2 -- ENGINE-native like everything else):
-- no /lac disable, no manual /equip. We write the WORKING copy to
-- <char>\dlac\lspreview.lua on every edit; the engine (dispatch v39) reads it
-- like craftstate and, while enabled, OWNS the Default dispatch -- it wears
-- only these pieces (LAC's own wearability checks skip what the player can't
-- wear yet, so under-level picks are allowed but never forced) and unequips
-- every other slot. The pump heartbeats the file (~10s) while previewing; the
-- engine drops a heartbeat older than 30s, so a dead addon can't leave the
-- player stuck stripped. Ending the preview writes enabled=false and the very
-- next dispatch redresses normally.
-- ---------------------------------------------------------------------------
local _preview = false;
local _pvBeatAt = 0;

local function queueCmd(c)
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, c); end);
end

local function writePreview()
    local base = charBase(); if base == nil then return; end
    local L = { '-- dlac lockstyle preview -- TRANSIENT (written by lockstyle.lua, read by the engine).', 'return {' };
    if _preview and cur ~= nil then
        L[#L + 1] = '    enabled = true,';
        L[#L + 1] = string.format('    at = %d,', os.time());
        L[#L + 1] = '    set = {';
        local ks = {};
        for k in pairs(cur.set) do ks[#ks + 1] = k; end
        table.sort(ks);
        for _, k in ipairs(ks) do
            if type(cur.set[k]) == 'string' then
                L[#L + 1] = string.format('        %s = %q,', k, cur.set[k]);
            end
        end
        L[#L + 1] = '    },';
    else
        L[#L + 1] = '    enabled = false,';
    end
    L[#L + 1] = '};';
    L[#L + 1] = '';
    pcall(function()
        local f = io.open(base .. 'dlac\\lspreview.lua', 'w');
        if f ~= nil then f:write(table.concat(L, '\n')); f:close(); end
    end);
    _pvBeatAt = os.clock() + 10;
end

-- Every mutation of the working copy funnels through here: while a preview is
-- live it re-publishes immediately, so the look on screen tracks every edit.
local function touched()
    if _preview then writePreview(); end
end
M._touched = touched;   -- switchTo is defined above this section and publishes through here

local function startPreview()
    -- A live lockstyle VISUAL hides equipment changes -- the preview would be
    -- invisible under it. Switch it off first, every time (Henrik, field).
    queueCmd('/lockstyle off');
    _preview = true;
    writePreview();
    _status = 'previewing -- lockstyle off, the engine wears ONLY this set (updates live as you edit).';
end

local function endPreview()
    _preview = false;
    writePreview();
    _status = 'preview ended -- normal gear redresses.';
end

-- ---------------------------------------------------------------------------
-- window
-- ---------------------------------------------------------------------------
local ui = { selSlot = nil, pick = { '' }, pendingBox = nil, openPick = false, openConfirm = false, openArr = { true } };

local function boxColumn(from, to)
    local clickedBox = nil;
    imgui.BeginGroup();
    for n = from, to do
        local e = data.slots[n];
        -- name only (Henrik: the number ate the width); the tooltip keeps the
        -- box number, and the 10x3 layout implies it anyway
        local nm = (type(e) == 'table' and type(e.name) == 'string' and e.name ~= '') and e.name or '--';
        if #nm > 15 then nm = string.sub(nm, 1, 14) .. '~'; end
        local on = (n == data.active);
        if on then imgui.PushStyleColor(ImGuiCol_Button, GOLD); end
        if imgui.Button(nm .. '##lsbox' .. n, { BOX_W, 19 }) then clickedBox = n; end
        if on then imgui.PopStyleColor(1); end
        if imgui.IsItemHovered() then
            local job = jobAbbr();
            local ol = '';
            for j, b in pairs(data.onload or {}) do if b == n then ol = ol .. ' [OnLoad: ' .. j .. ']'; end end
            imgui.SetTooltip(string.format('box %d%s%s\nClick to mark it -- Save lands in the marked box.%s',
                n, (nm ~= '--') and (': ' .. tostring(e.name)) or ' (empty)', ol,
                (cur ~= nil and cur.dirty and n ~= data.active) and '\nWARNING: unsaved edits on the current box.' or ''));
        end
    end
    imgui.EndGroup();
    return clickedBox;
end

local function renderPicker()
    if ui.openPick then ui.openPick = false; imgui.OpenPopup('##dlac_lspick'); end
    if not imgui.BeginPopup('##dlac_lspick') then return; end
    local slot = ui.selSlot;
    if slot == nil then imgui.EndPopup(); return; end
    imgui.TextColored(COL_HEADER, slot .. ' -- shown in this lockstyle:');
    imgui.SameLine(0, 8);
    imgui.PushItemWidth(150);
    imgui.InputText('##lssearch', ui.pick, 32);
    imgui.PopItemWidth();
    imgui.Separator();
    imgui.BeginChild('##lspicklist', { 340, 300 }, false);
    if imgui.Selectable('(clear -- no lockstyle piece for this slot)##lsclear', false) then
        cur.set[slot] = nil; cur.dirty = true; touched();
        imgui.CloseCurrentPopup();
    end
    if imgui.Selectable('(hide -- lockstyle the slot EMPTY)##lshide', false) then
        cur.set[slot] = 'remove'; cur.dirty = true; touched();
        imgui.CloseCurrentPopup();
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("LAC's 'remove': the lockstyle shows NOTHING in this slot,\neven while something is equipped.");
    end
    imgui.Separator();
    local job = jobAbbr();
    local q = string.lower(ui.pick[1] or '');
    local items = listFor(slot, job, q);
    for i, rec in ipairs(items) do
        if W.icon ~= nil then pcall(W.icon, rec.Id, 18, rec); imgui.SameLine(0, 6); end
        if imgui.Selectable(string.format('%s   Lv%d##lsi%d', tostring(rec.Name), tonumber(rec.Level) or 0, i), false) then
            cur.set[slot] = rec.Name; cur.dirty = true; touched();
            imgui.CloseCurrentPopup();
        end
        if imgui.IsItemHovered() and W.tooltip ~= nil then pcall(W.tooltip, rec); end
    end
    if #items == 0 then
        imgui.TextColored(COL_DIM, (q ~= '') and 'No owned item matches.' or 'Nothing in gear.lua for this slot yet (/dl sync).');
    end
    imgui.EndChild();
    imgui.EndPopup();
end

local function renderDelete()
    if ui.openDelete then ui.openDelete = false; imgui.OpenPopup('##dlac_lsdelete'); end
    if not imgui.BeginPopup('##dlac_lsdelete') then return; end
    local e = data.slots[data.active];
    imgui.TextColored(COL_WARN, string.format('Delete box %d ("%s")?', data.active,
        tostring((type(e) == 'table') and (e.name or '') or '')));
    imgui.TextColored(COL_DIM, 'The saved lockstyle and its OnLoad bindings are removed.');
    if imgui.Button('Delete it##lsdelgo', { 260, 22 }) then
        data.slots[data.active] = nil;
        for j, b in pairs(data.onload or {}) do
            if b == data.active then data.onload[j] = nil; end
        end
        save();
        loadBox();
        touched();
        _status = string.format('box %d deleted.', data.active);
        imgui.CloseCurrentPopup();
    end
    if imgui.Button('Keep it##lsdelno', { 260, 22 }) then
        imgui.CloseCurrentPopup();
    end
    imgui.EndPopup();
end

local function renderConfirm()
    if ui.openConfirm then ui.openConfirm = false; imgui.OpenPopup('##dlac_lsconfirm'); end
    if not imgui.BeginPopup('##dlac_lsconfirm') then return; end
    imgui.TextColored(COL_WARN, string.format('Box %d has UNSAVED changes.', data.active));
    imgui.TextColored(COL_DIM, 'Switching discards them and loads the other box.');
    -- Stacked + wide (Henrik: the side-by-side pair clipped both labels).
    if imgui.Button('Discard changes & switch##lsdisc', { 260, 22 }) then
        local n = ui.pendingBox;
        ui.pendingBox = nil;
        if n ~= nil then switchTo(n); end
        imgui.CloseCurrentPopup();
    end
    if imgui.Button('Keep editing##lskeep', { 260, 22 }) then
        ui.pendingBox = nil;
        imgui.CloseCurrentPopup();
    end
    imgui.EndPopup();
end

-- Rendered from gearui's drawWindow (themed scope), every frame while visible.
function M.render()
    if not hasImgui or not M.visible then return; end
    if not ensure() then
        M.visible = false;
        return;
    end
    imgui.SetNextWindowSize({ 620, 400 }, ImGuiCond_FirstUseEver or 0);
    ui.openArr[1] = true;
    if imgui.Begin('dlac Lockstyle###dlac_lockstyle', ui.openArr, ImGuiWindowFlags_None or 0) then
        local job = jobAbbr();
        local e = data.slots[data.active];
        -- the job in the title says WHOSE boxes these are (per job entry, v41)
        imgui.TextColored(COL_HEADER, string.format('%s lockstyle box %d', tostring(job or '?'), data.active));
        imgui.SameLine(0, 8);
        imgui.TextColored(cur.dirty and COL_WARN or COL_DIM,
            cur.dirty and 'unsaved changes' or ((e ~= nil) and ('"' .. tostring(e.name or '') .. '"') or '(empty)'));
        -- top-right on this row (Henrik): kill the lockstyle visual
        pcall(function()
            local bw = 178;   -- 17 chars at the wide themed font (9.5px/char + padding)
            imgui.SameLine();
            local avail = imgui.GetContentRegionAvail();
            if type(avail) == 'number' and avail > bw then
                imgui.SetCursorPosX(imgui.GetCursorPosX() + avail - bw);
            end
            if imgui.Button('Disable lockstyle##lsoff', { bw, 0 }) then
                queueCmd('/lockstyle off');
                _status = 'lockstyle disabled (/lockstyle off) -- your real gear shows again.';
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('The game\'s /lockstyle off: the lockstyle VISUAL comes off and\nwhat you actually wear shows again.');
            end
        end);
        imgui.Separator();

        imgui.BeginGroup();   -- LEFT: the 4x4 + controls
        if W.slotGrid ~= nil then
            W.slotGrid('dlacls', 186, ui.selSlot,
                function(sl)   -- icon id
                    if not VISUAL[sl.label] then return nil; end
                    local rec = recOf(cur.set[sl.label]);
                    return rec and rec.Id or nil;
                end,
                function(sl)   -- hover text (no record)
                    if not VISUAL[sl.label] then return '(not part of lockstyle)'; end
                    local v = cur.set[sl.label];
                    if v == 'remove' then return '(hidden -- lockstyled empty)'; end
                    return v or '(no lockstyle piece)';
                end,
                function(label)   -- click
                    if not VISUAL[label] then
                        _status = label .. ' is not a visual slot -- lockstyle covers Main/Sub/Range/Ammo/Head/Body/Hands/Legs/Feet.';
                        return;
                    end
                    ui.selSlot = label;
                    ui.pick[1] = '';
                    ui.openPick = true;
                end,
                function(sl) return recOf(cur.set[sl.label]); end,
                190);
        else
            imgui.TextColored(COL_DIM, 'grid unavailable (gearui not wired)');
        end
        imgui.PushItemWidth(108);
        imgui.InputText('##lsname', nameBuf, 24);
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then imgui.SetTooltip('Name for this lockstyle -- saved with the box.'); end
        imgui.SameLine(0, 4);
        if imgui.Button('Save##lssave', { 60, 0 }) then   -- height 0 = frame height, matches the input box
            local copy = {};
            for k, v in pairs(cur.set) do copy[k] = v; end
            data.slots[data.active] = { name = tostring(nameBuf[1] or ''), set = copy };
            cur.dirty = false;
            save();
            _status = string.format('saved box %d as "%s".', data.active, tostring(nameBuf[1] or ''));
        end
        if imgui.IsItemHovered() then imgui.SetTooltip('Save the working lockstyle into the MARKED (gold) box.'); end
        imgui.SameLine(0, 4);
        if imgui.Button('Del##lsdel', { 44, 0 }) then ui.openDelete = true; end
        if imgui.IsItemHovered() then imgui.SetTooltip('Delete the MARKED box\'s saved lockstyle (asks first).'); end
        -- Import from static: many players keep old lockstyle sets as statics.
        local statics = (_pok and type(profsets.staticSetNames) == 'function') and profsets.staticSetNames() or {};
        imgui.PushItemWidth(216);   -- wide enough for the label at the themed font (field-clipped at 186)
        if imgui.BeginCombo('##lsimp', 'Import from static...') then
            if #statics == 0 then imgui.TextColored(COL_DIM, '(no static sets found)'); end
            for _, nm in ipairs(statics) do
                if imgui.Selectable(nm .. '##lsimp_' .. nm, false) then
                    pcall(function()
                        local S = profsets.getSetsRoot();
                        local src = (type(S) == 'table') and S[nm] or nil;
                        if type(src) ~= 'table' then return; end
                        cur.set = {};
                        for k, v in pairs(src) do
                            if VISUAL[k] then
                                if type(v) == 'string' then cur.set[k] = v;
                                elseif type(v) == 'table' and type(v.Name) == 'string' then cur.set[k] = v.Name; end
                            end
                        end
                        cur.dirty = true; touched();
                        _status = string.format('imported static "%s" -- Save to keep it in box %d.', nm, data.active);
                    end);
                end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then imgui.SetTooltip('Copy the visual slots of a static set (live job file +\npre-profiles backups) into the working lockstyle.'); end
        -- OnLoad + Apply row.
        local olBox = { job ~= nil and data.onload[job] == data.active or false };
        if imgui.Checkbox('OnLoad Lockstyle##lsol', olBox) and job ~= nil then
            data.onload[job] = (olBox[1] == true) and data.active or nil;
            save();
            _status = (olBox[1] == true)
                and string.format('%s lockstyles box %d on every login/job change.', job, data.active)
                or (job .. ' OnLoad lockstyle off.');
        end
        if imgui.IsItemHovered() then
            local cur_ol = (job ~= nil) and data.onload[job] or nil;
            imgui.SetTooltip(string.format(
                'Apply the MARKED box automatically every time %s loads\n(login and job change, a few seconds in).%s',
                tostring(job or '?'),
                (cur_ol ~= nil and cur_ol ~= data.active) and string.format('\nCurrently bound to box %d.', cur_ol) or ''));
        end
        -- own row (Henrik: beside the checkbox it widened the whole window);
        -- full column width, same as Import/Preview
        if imgui.Button('Apply lockstyle##lsgo', { 216, 0 }) then
            queueCmd('/dl ls apply');
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Lockstyle the MARKED box now (engine-side: /dl ls apply --\nneeds LuaAshitacast loaded). Unsaved edits are NOT applied: Save first.');
        end
        if imgui.Button((_preview and 'End preview' or 'Preview') .. '##lsprev', { 216, 0 }) then
            if _preview then endPreview(); else startPreview(); end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('The ENGINE wears ONLY this lockstyle (the WORKING copy, live as you\nedit) -- every other slot is unequipped by the top-priority preview\noverlay, and the lockstyle VISUAL is switched off first (it would hide\nthe preview). Pieces you can\'t wear yet are skipped by LAC itself,\nnever forced. Click again (or close this window) to end -- your normal\ngear redresses on the next dispatch. Don\'t preview in combat.');
        end
        imgui.EndGroup();

        imgui.SameLine(0, 12);
        imgui.BeginGroup();   -- RIGHT: the 30 boxes, macro-menu style
        local styled = (ImGuiStyleVar_ItemSpacing ~= nil);
        if styled then imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 3, 2 }); end
        local c1 = boxColumn(1, 10);
        imgui.SameLine(0, 4);
        local c2 = boxColumn(11, 20);
        imgui.SameLine(0, 4);
        local c3 = boxColumn(21, 30);
        if styled then imgui.PopStyleVar(1); end
        imgui.EndGroup();
        local clicked = c1 or c2 or c3;
        if clicked ~= nil and clicked ~= data.active then
            if cur.dirty then
                ui.pendingBox = clicked;
                ui.openConfirm = true;
            else
                switchTo(clicked);
            end
        end

        if _status ~= nil then
            imgui.Separator();
            imgui.TextColored(COL_DIM, _status);
        end
        renderPicker();
        renderConfirm();
        renderDelete();
    end
    imgui.End();
    if ui.openArr[1] == false then M.visible = false; end
end

function M.open()
    M.visible = true;
end

-- ---------------------------------------------------------------------------
-- OnLoad pump (macrobook's login/job-change pattern): queue the engine apply
-- once per job, ~6s after login (zone-in grace) / ~3s after a job change.
-- Jobs with no OnLoad binding are never touched.
-- ---------------------------------------------------------------------------
local appliedJob, pendingJob, dueAt = nil, nil, nil;
function M.pump()
    -- Closing the window while previewing ends the preview (Henrik: always);
    -- while it runs, heartbeat the preview file so the engine knows we're
    -- alive (it drops heartbeats older than 30s -- addon-crash safety).
    if _preview then
        if not M.visible then endPreview();
        elseif os.clock() >= _pvBeatAt then writePreview(); end
    end
    local job = jobAbbr();
    if job == nil then return; end
    load_();
    if data == nil then return; end
    if job ~= appliedJob and job ~= pendingJob then
        pendingJob = job;
        dueAt = os.clock() + ((appliedJob == nil) and 6 or 3);
    end
    if pendingJob ~= nil and dueAt ~= nil and os.clock() >= dueAt then
        appliedJob, pendingJob, dueAt = pendingJob, nil, nil;
        local box = data.onload[appliedJob];
        if tonumber(box) ~= nil then
            pcall(function()
                AshitaCore:GetChatManager():QueueCommand(1, string.format('/dl ls apply %d', tonumber(box)));
            end);
        end
    end
end

-- '/dl ls' in the ADDON state: open the window; block so the game parser stays
-- quiet. 'apply' is left for the LAC state's dispatch handler (it sees the
-- same command -- separate Lua state), which owns gFunc.LockStyle.
ashita.events.register('command', 'dlac-lockstyle', function(e)
    local raw = string.lower(e.command);
    local s = nil;
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then s = 7;
    elseif raw == '/dl' or string.sub(raw, 1, 4) == '/dl ' then s = 5; end
    if s == nil then return; end
    local args = {};
    for a in string.gmatch(string.sub(raw, s), '%S+') do args[#args + 1] = a; end
    if args[1] ~= 'ls' then return; end
    e.blocked = true;
    if args[2] == nil or args[2] == 'open' or args[2] == 'ui' then M.open(); end
end);

return M;
