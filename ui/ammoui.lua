--[[
    dlac/ui/ammoui.lua -- the AutoAmmo panel (docs/design/auto-ammo.md).

    Rendered inside automationsui's Automations detail (auto.view == 'ammo');
    its own module (the 200-local law). automationsui pcall-requires this at
    render time and hands over its deps table (lookupByName / ownedCounts /
    renderIcon / itemTooltip / playerJob -- the gearui init injection).

    The panel edits ONE thing: <char>\dlac\ammostate.lua, through ammowatch's
    mutators. The dispatch engine (v73) does everything live: count-verified
    picks per event, the special-bullet protection sweep, the 'remove' ladder
    end. Nothing here equips.

    Layout: master pill + the jobs map chips; the priority list (order = the
    engine's fallback order, ▲▼ to reorder) with Ranged / WS / Special ticks
    and, on special rows, the three behaviour ticks (Unlimited Shot / Quick
    Draw / free WSs); below, every owned-but-unconfigured shooting ammo with
    a + Add. Ammo = catalog AmmoType Marksmanship/Archery/Throwing -- trinket
    "ammo" is set business, never AutoAmmo's.
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');

local _awok, aw = pcall(require, 'dlac\\feature\\ammowatch');
_awok = _awok and type(aw) == 'table';

local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_DIM    = { 0.55, 0.55, 0.55, 1.00 };
local COL_TEXT   = { 0.70, 0.70, 0.70, 1.00 };
local COL_ERR    = { 0.95, 0.45, 0.40, 1.00 };
local COL_GOLD   = { 0.95, 0.85, 0.45, 1.00 };
local COL_GREEN  = { 0.45, 0.90, 0.45, 1.00 };

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

-- Fixed column offsets, shared by BOTH lists so they read as one table
-- (Henrik's field ask). The automationsui row-offset pattern; the themed font
-- runs ~9.5px/char, so text columns need real room or they collide.
local NAME_X  = 64;    -- icon + name (the priority arrows live left of it)
local QTY_X   = 330;   -- stack count
local FLAGS_X = 392;   -- priority rows: the Ranged/WS/Special ticks
local DEL_X   = 660;   -- priority rows: remove
local SKILL_X = 392;   -- owned rows: AmmoType
local LV_X    = 516;   -- owned rows: Lv xx
local ADD_X   = 578;   -- owned rows: + Add (space RESERVED to its right -- more
                       -- per-row controls are planned)

-- Shooting-ammo catalog rows (flat records), owned split off per render.
-- AmmoType is the discriminator: absent = trinket/pet food -- not ours.
local SHOOT_TYPE = { Marksmanship = true, Archery = true, Throwing = true };
local function ownedShootingAmmo(deps)
    local out = {};
    pcall(function()
        local cx = require('dlac\\gear\\catalogindex');
        local list = cx.flat();
        local oc = (deps ~= nil and type(deps.ownedCounts) == 'function') and deps.ownedCounts() or nil;
        if type(list) ~= 'table' or type(oc) ~= 'table' then return; end
        for _, rec in ipairs(list) do
            if rec.Slot == 'Ammo' and SHOOT_TYPE[rec.AmmoType or ''] == true
               and (oc[rec.Id] or 0) >= 1 then
                out[#out + 1] = rec;
            end
        end
        table.sort(out, function(a, b)
            if a.AmmoType ~= b.AmmoType then return tostring(a.AmmoType) < tostring(b.AmmoType); end
            local la, lb = tonumber(a.Level) or 0, tonumber(b.Level) or 0;
            if la ~= lb then return la > lb; end
            return tostring(a.Name) < tostring(b.Name);
        end);
    end);
    return out;
end

local function countOf(deps, id)
    local n = 0;
    pcall(function()
        local oc = (deps ~= nil and type(deps.ownedCounts) == 'function') and deps.ownedCounts() or nil;
        if type(oc) == 'table' then n = oc[id] or 0; end
    end);
    return n;
end

-- ---------------------------------------------------------------------------
-- Automations list row contract. ABOVE the imgui guard on purpose (the fishui
-- pattern): the row status must work headless and in-game whether or not this
-- render half could bind imgui.
-- ---------------------------------------------------------------------------
M.maxLevel = 1;
function M.status(deps)
    if not _awok then return 0, 'ammowatch failed to load'; end
    aw.loadState();
    if not aw.enabled then return 0, 'OFF'; end
    local n, sp = #aw.list, 0;
    for _, e in ipairs(aw.list) do
        if type(e.special) == 'table' then sp = sp + 1; end
    end
    local txt = string.format('ON -- %d ammo', n);
    if sp > 0 then txt = txt .. string.format(', %d special', sp); end
    return 1, txt;
end
function M.level(deps) return (select(1, M.status(deps))); end

if not _iok then return M; end   -- imgui-less (headless): the pure half above is the module

-- ---------------------------------------------------------------------------
-- The detail view (automationsui: auto.view == 'ammo').
-- ---------------------------------------------------------------------------
function M.render(deps, availW)
    if not _awok then
        imgui.TextColored(COL_ERR, 'ammowatch failed to load.');
        return;
    end
    aw.loadState();

    imgui.TextColored(COL_HEADER, 'AutoAmmo');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_TEXT, 'decides what sits in the Ammo slot, per shot and per weapon skill.');

    -- Master pill (craftbar's one implementation) + the jobs chips.
    local on = (aw.enabled == true);
    imgui.TextColored(COL_TEXT, 'AutoAmmo:');
    imgui.SameLine(0, 6);
    local cbok, craftbar = pcall(require, 'dlac\\ui\\craftbar');
    local pill = (cbok and type(craftbar) == 'table' and type(craftbar.onOffSwitch) == 'function')
        and craftbar.onOffSwitch or nil;
    local job = (deps ~= nil and type(deps.playerJob) == 'function') and deps.playerJob() or nil;
    local TIP_ON  = 'AutoAmmo is ON (stays on across sessions -- it is a protection system).\nClick to turn off.';
    local TIP_OFF = 'Loads your enabled ammo for ranged attacks and weapon skills, and strictly\nguards special ammo (equipped only for its windows; swept off -- or the slot\nemptied -- anywhere a shot could consume it). Stays on across sessions.';
    if pill ~= nil then
        if pill(on, 'ammoonoff', TIP_ON, TIP_OFF) then aw.setEnabled(not on, job); end
    else
        if imgui.Button((on and 'ON' or 'OFF') .. '##ammoonoff', { 46, 22 }) then aw.setEnabled(not on, job); end
    end
    imgui.SameLine(0, 14);
    imgui.TextColored(COL_TEXT, 'Active on:');
    local jk = {};
    for j in pairs(aw.jobs) do jk[#jk + 1] = j; end
    table.sort(jk);
    for _, j in ipairs(jk) do
        imgui.SameLine(0, 6);
        if imgui.SmallButton(j .. '  x##ammojob_' .. j) then aw.setJob(j, false); end
        if imgui.IsItemHovered() then imgui.SetTooltip('AutoAmmo acts on ' .. j .. '. Click to remove.'); end
    end
    if job ~= nil and aw.jobs[job] ~= true then
        imgui.SameLine(0, 6);
        if imgui.SmallButton('+ ' .. job .. '##ammojobadd') then aw.setJob(job, true); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Add your current job -- AutoAmmo only acts on listed jobs.'); end
    end
    if #jk == 0 then
        imgui.SameLine(0, 6);
        imgui.TextColored(COL_ERR, '(no jobs -- AutoAmmo acts on nothing)');
    end

    imgui.Separator();

    -- ------------------------------------------------------------------
    -- Priority list. Order IS the engine's fallback order.
    -- ------------------------------------------------------------------
    imgui.TextColored(COL_HEADER, 'Priority list');
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, '(top loads first)');
    imgui.SameLine(0, 10);
    if imgui.SmallButton('Sort by level##ammosort') then
        aw.sortByLevel(function(e)
            if deps ~= nil and type(deps.lookupByName) == 'function' then
                local r = deps.lookupByName(e.name);
                if r ~= nil then return r.Level; end
            end
            return 0;
        end);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Reorder the whole list best-first (item level, highest first) -- usually\nwhat you want. Order = the engine\'s fallback order; fine-tune with the arrows.');
    end
    if #aw.list == 0 then
        imgui.TextColored(COL_DIM, 'nothing configured yet -- add ammo from the owned list below.');
    end
    local removeAt = nil;
    for i, e in ipairs(aw.list) do
        imgui.PushID('ammorow_' .. i);
        if imgui.SmallButton('^') and i > 1 then aw.moveAmmo(i, -1); end
        imgui.SameLine(0, 2);
        if imgui.SmallButton('v') and i < #aw.list then aw.moveAmmo(i, 1); end
        imgui.SameLine(NAME_X);
        local rec = (deps ~= nil and type(deps.lookupByName) == 'function') and deps.lookupByName(e.name) or nil;
        if deps ~= nil and type(deps.renderIcon) == 'function' then
            deps.renderIcon((rec and rec.Id) or e.id, 18);
        end
        local n = countOf(deps, e.id);
        imgui.TextColored((n >= 1) and COL_TEXT or COL_ERR, esc(e.name));
        if imgui.IsItemHovered() and rec ~= nil and deps ~= nil and type(deps.itemTooltip) == 'function' then
            pcall(deps.itemTooltip, rec);
        end
        imgui.SameLine(QTY_X);
        imgui.TextColored((n >= 1) and COL_DIM or COL_ERR, 'x' .. tostring(n));
        if n < 1 and imgui.IsItemHovered() then
            imgui.SetTooltip('None in your equippable bags -- the engine skips this entry\n(and never plans ammo you do not stock).');
        end
        imgui.SameLine(FLAGS_X);
        local sp = (type(e.special) == 'table');
        local b1 = { e.ranged == true };
        if imgui.Checkbox('Ranged##r' .. i, b1) then aw.setFlag(i, 'ranged', b1[1]); end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(sp and 'Special ammo is never a normal pick.'
                             or 'OK for normal ranged attacks.');
        end
        imgui.SameLine(0, 10);
        local b2 = { e.ws == true };
        if imgui.Checkbox('WS##w' .. i, b2) then aw.setFlag(i, 'ws', b2[1]); end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(sp and 'Special ammo is never a normal pick.'
                             or 'OK for ammo-consuming ranged weapon skills.');
        end
        imgui.SameLine(0, 10);
        local b3 = { sp };
        if imgui.Checkbox('Special##s' .. i, b3) then aw.setSpecial(i, b3[1]); end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('NEVER equipped where a shot could consume it -- only for the ticked\nwindows below, and swept off (or the slot emptied) everywhere else.');
        end
        imgui.SameLine(DEL_X);
        if imgui.SmallButton('x##del' .. i) then removeAt = i; end
        if imgui.IsItemHovered() then imgui.SetTooltip('Remove from AutoAmmo (the item itself is untouched).'); end
        if sp then
            imgui.Dummy({ 0, 0 }); imgui.SameLine(NAME_X);
            imgui.TextColored(COL_GOLD, 'windows:');
            imgui.SameLine(0, 8);
            local u = { e.special.unlimited == true };
            if imgui.Checkbox('Unlimited Shot##u' .. i, u) then aw.setBehaviour(i, 'unlimited', u[1]); end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Worn while the Unlimited Shot effect is up -- the shot consumes nothing.');
            end
            imgui.SameLine(0, 10);
            local q = { e.special.quickdraw == true };
            if imgui.Checkbox('Quick Draw##q' .. i, q) then aw.setBehaviour(i, 'quickdraw', q[1]); end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Worn for the Quick Draw shots -- they consume a card, never the bullet\n(and Quick Draw refuses to fire with an empty Ammo slot, so this can\nun-block it too). Marksmanship ammo only.');
            end
            imgui.SameLine(0, 10);
            local fw = { e.special.freews == true };
            if imgui.Checkbox('Free WSs##f' .. i, fw) then aw.setBehaviour(i, 'freews', fw[1]); end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Worn for the three magical ranged weapon skills that consume NO ammo\non this server: Leaden Salute, Wildfire, Trueflight.');
            end
        end
        imgui.PopID();
    end
    if removeAt ~= nil then aw.removeAmmo(removeAt); end

    imgui.Separator();

    -- ------------------------------------------------------------------
    -- Owned, not configured.
    -- ------------------------------------------------------------------
    imgui.TextColored(COL_HEADER, 'Owned ammo');
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, '(shooting ammo in your equippable bags, not configured yet)');
    local inList = {};
    for _, e in ipairs(aw.list) do inList[string.lower(e.name)] = true; end
    local shown = 0;
    for _, rec in ipairs(ownedShootingAmmo(deps)) do
        if not inList[string.lower(rec.Name)] then
            shown = shown + 1;
            imgui.PushID('ammoown_' .. tostring(rec.Id));
            imgui.Dummy({ 0, 0 });
            imgui.SameLine(NAME_X);   -- same name column as the priority list: one table, two sections
            if deps ~= nil and type(deps.renderIcon) == 'function' then
                deps.renderIcon(rec.Id, 18);
            end
            imgui.TextColored(COL_TEXT, esc(rec.Name));
            if imgui.IsItemHovered() and deps ~= nil and type(deps.itemTooltip) == 'function' then
                pcall(deps.itemTooltip, rec);
            end
            imgui.SameLine(QTY_X);
            imgui.TextColored(COL_DIM, 'x' .. tostring(countOf(deps, rec.Id)));
            imgui.SameLine(SKILL_X);
            imgui.TextColored(COL_DIM, tostring(rec.AmmoType));
            imgui.SameLine(LV_X);
            imgui.TextColored(COL_DIM, string.format('Lv %d', tonumber(rec.Level) or 0));
            imgui.SameLine(ADD_X);
            if imgui.SmallButton('+ Add##add' .. tostring(rec.Id)) then aw.addAmmo(rec); end
            imgui.PopID();
        end
    end
    if shown == 0 then
        imgui.TextColored(COL_DIM, 'nothing new -- everything you own is configured (or you carry no shooting ammo).');
    end

    imgui.Separator();
    imgui.TextColored(COL_DIM, 'Special ammo is never left equipped where a shot could consume it; with');
    imgui.TextColored(COL_DIM, 'nothing else enabled in your bags, the slot is emptied -- an empty gun');
    imgui.TextColored(COL_DIM, 'refuses the shot, which is the point.');
end

return M;
