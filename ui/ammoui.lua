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

-- NO E-Box surface here (removed 2026-07-27, auto-ammo.md Section 10.8). This panel
-- carried CW-only box counts and per-row Fetch / Fetch up to buttons until E-Box
-- Restock could carry category 15 with targets and top-up -- Henrik: "we have E-box
-- restocker now which is better". The panel has NO gamemode awareness at all now:
-- every player sees exactly the same AutoAmmo.
local CAT_SEL = nil; -- the category view selection (session-only)

local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_DIM    = { 0.55, 0.55, 0.55, 1.00 };
local COL_TEXT   = { 0.70, 0.70, 0.70, 1.00 };
local COL_ERR    = { 0.95, 0.45, 0.40, 1.00 };
local COL_GOLD   = { 0.95, 0.85, 0.45, 1.00 };
local COL_GREEN  = { 0.45, 0.90, 0.45, 1.00 };
-- Type-tab backgrounds, the hobbybar strip's colours (one idiom for "tabs made of
-- buttons" across the GUI): green = the type your equipped ranged weapon actually
-- fires, blue = the one you are editing.
local COL_LIVE     = { 0.16, 0.55, 0.24, 1.0 };
local COL_SELECTED = { 0.20, 0.35, 0.60, 1.0 };

-- What is in the Range slot, and therefore which ammo category can be loaded at all.
-- Straight through gearoracle (THE one worn-item door, ADR 0013) -- its record is the
-- CATALOG record, so Pair is exact here with no manifest refresh needed. Equip slot 2
-- is Range. nil = nothing worn, or an item the catalog cannot place.
local function liveRangeCategory()
    local cat, nm = nil, nil;
    pcall(function()
        local go = require('dlac\\gear\\gearoracle');
        local w = go.wornItem(2);
        if w == nil or type(w.rec) ~= 'table' then return; end
        nm  = w.rec.Name;
        cat = aw.categoryForPair(w.rec.Pair);
    end);
    return cat, nm;
end

-- What is worn in the Ammo slot (equip slot 3), same door as the Range read
-- above. The row wearing it renders GREEN -- one law with the type tabs: green
-- is always a LIVE fact, blue is always your selection.
local function liveAmmoName()
    local nm = nil;
    pcall(function()
        local go = require('dlac\\gear\\gearoracle');
        local w = go.wornItem(3);
        if w ~= nil and type(w.rec) == 'table' then nm = w.rec.Name; end
    end);
    return (type(nm) == 'string') and string.lower(nm) or nil;
end

-- The level the ENGINE will gear at -- the /dl set level main override first,
-- exactly as dispatch's playerLevel and utils.determineLevels resolve it. The
-- panel must not disagree with the engine about which rungs are reachable.
-- nil = unknown, and unknown gates nothing (the engine's rule too).
local function gearLevel()
    local ovr = rawget(_G, 'staticMainLevel');
    if type(ovr) == 'number' and ovr > 0 then return ovr; end
    local lv = nil;
    pcall(function() lv = gData.GetPlayer().MainJobSync; end);
    lv = tonumber(lv);
    if lv ~= nil and lv > 0 then return lv; end
    return nil;
end

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

-- Fixed column offsets, shared by BOTH lists so they read as one table
-- (Henrik's field ask). The automationsui row-offset pattern; the themed font
-- runs ~9.5px/char, so text columns need real room or they collide.
-- Name and qty are the SHARED pair (Henrik's "make the table look nice"); the
-- tails diverge by design -- flag ticks on a priority row, skill/Lv/+ Add on an
-- owned one. The priority row's own Lv column (v134) sits between qty and the
-- ticks: the level is a gate now, so it belongs beside the other gate (stock).
local NAME_X  = 64;    -- icon + name (the priority arrows live left of it)
local QTY_X   = 330;   -- stack count
local LVP_X   = 392;   -- priority rows: the level gate
local FLAGS_X = 452;   -- priority rows: the Ranged/WS/Special ticks
local DEL_X   = 700;   -- priority rows: remove
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
    local job = (deps ~= nil and type(deps.playerJob) == 'function') and deps.playerJob() or nil;
    aw.selectJob(job);   -- fmt 2: the row reports the CURRENT job's own switch
    if not aw.enabled then return 0, 'OFF' .. ((job ~= nil) and (' on ' .. job) or ''); end
    local n, sp = #aw.list, 0;
    for _, e in ipairs(aw.list) do
        if type(e.special) == 'table' then sp = sp + 1; end
    end
    local txt = string.format('ON on %s -- %d ammo', tostring(job), n);
    if sp > 0 then txt = txt .. string.format(', %d special', sp); end
    return 1, txt;
end
function M.level(deps) return (select(1, M.status(deps))); end

if not _iok then return M; end   -- imgui-less (headless): the pure half above is the module

-- Test seams for the category selection (a session-only module local). smoke drives
-- the real render once per worn-weapon branch and has to read the landing tab and
-- clear it between cases; kept explicit rather than one overloaded accessor, because
-- "reset to nil" and "read" cannot be told apart through a single nil argument.
function M._catSel() return CAT_SEL; end
function M._resetCatSel() CAT_SEL = nil; end

-- ---------------------------------------------------------------------------
-- The detail view (automationsui: auto.view == 'ammo').
-- ---------------------------------------------------------------------------
function M.render(deps, availW)
    if not _awok then
        imgui.TextColored(COL_ERR, 'ammowatch failed to load.');
        return;
    end
    local job = (deps ~= nil and type(deps.playerJob) == 'function') and deps.playerJob() or nil;
    aw.selectJob(job);   -- fmt 2: everything below edits THIS job's own section
    -- Teach old entries their pair key (v128). Opening the panel is the one moment
    -- the catalog and the config are both in hand; after the first sweep nothing is
    -- missing and this costs a loop over a handful of rows. Without it a list built
    -- before v128 keeps falling back to AmmoType, which cannot separate a bolt from
    -- a bullet -- i.e. the reported bug would survive the fix that addressed it.
    pcall(function()
        local cx = require('dlac\\gear\\catalogindex');
        aw.backfillPairs(function(id)
            local r = cx.rawById(id);
            return (type(r) == 'table') and r.Pair or nil;
        end);
    end);
    imgui.TextColored(COL_HEADER, 'AutoAmmo');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_TEXT, 'decides what sits in the Ammo slot, per shot and per weapon skill.');

    -- Per-job switch (field round 2: "all jobs can't use all ammos") -- each
    -- job keeps its OWN priority list and its OWN persisted on/off.
    local on = (aw.enabled == true);
    imgui.TextColored(COL_TEXT, 'AutoAmmo on');
    imgui.SameLine(0, 5);
    imgui.TextColored(COL_GOLD, tostring(job or '?'));
    imgui.SameLine(0, 2);
    imgui.TextColored(COL_TEXT, ':');
    imgui.SameLine(0, 6);
    local cbok, craftbar = pcall(require, 'dlac\\ui\\craftbar');
    local pill = (cbok and type(craftbar) == 'table' and type(craftbar.onOffSwitch) == 'function')
        and craftbar.onOffSwitch or nil;
    local TIP_ON  = 'AutoAmmo is ON for this job (each job remembers its own switch and list;\nstays on across sessions -- it is a protection system). Click to turn off.';
    local TIP_OFF = 'Loads this job\'s enabled ammo for ranged attacks and weapon skills, and\nstrictly guards special ammo (equipped only for its windows; swept off --\nor the slot emptied -- anywhere a shot could consume it). Each job keeps\nits own list and switch, remembered across sessions.';
    if job == nil then
        imgui.TextColored(COL_DIM, '(log in first)');
    elseif pill ~= nil then
        if pill(on, 'ammoonoff', TIP_ON, TIP_OFF) then aw.setEnabled(not on, job); end
    else
        if imgui.Button((on and 'ON' or 'OFF') .. '##ammoonoff', { 46, 22 }) then aw.setEnabled(not on, job); end
    end
    imgui.SameLine(0, 14);
    imgui.TextColored(COL_DIM, 'each job keeps its own list and switch');
    -- The other jobs' sections, at a glance (and proof nothing was lost).
    local sum = (type(aw.jobSummary) == 'function') and aw.jobSummary() or {};
    local others = {};
    for _, s in ipairs(sum) do
        if s.job ~= job then
            others[#others + 1] = string.format('%s %s (%d)', s.job, s.enabled and 'ON' or 'off', s.n);
        end
    end
    if #others > 0 then
        imgui.TextColored(COL_DIM, 'also configured: ' .. esc(table.concat(others, ', ')));
    end

    imgui.Separator();

    -- ------------------------------------------------------------------
    -- Category view (field round 5: "list is gonna become super bloated").
    -- One ammo type at a time; the selector filters BOTH lists below. The
    -- job's priority list still spans all types underneath -- category is a
    -- VIEW, nothing is stored.
    -- ------------------------------------------------------------------
    local ownedAll = ownedShootingAmmo(deps);
    local inList = {};
    for _, e in ipairs(aw.list) do inList[string.lower(e.name)] = true; end
    local catCfg, catOwn = {}, {};
    for _, e in ipairs(aw.list) do
        local c = aw.categoryOf(e.name, e.type, e.pair);
        catCfg[c] = (catCfg[c] or 0) + 1;
    end
    for _, rec in ipairs(ownedAll) do
        if not inList[string.lower(rec.Name)] then
            local c = aw.categoryOf(rec.Name, rec.AmmoType, rec.Pair);
            catOwn[c] = (catOwn[c] or 0) + 1;
        end
    end
    local liveCat, liveWeapon = liveRangeCategory();
    if CAT_SEL == nil then
        -- First open lands on what you are actually holding -- that is the type you
        -- came here to edit. Only when nothing is equipped does it fall back to the
        -- first type this job configured. NEVER auto-switches after that: once you
        -- have clicked a tab it is yours, and swapping weapons mid-edit must not
        -- yank the list out from under you (the green tab already says what changed).
        CAT_SEL = liveCat;
        if CAT_SEL == nil then
            for _, c in ipairs(aw.CATEGORIES) do
                if (catCfg[c] or 0) > 0 then CAT_SEL = c; break; end
            end
        end
        CAT_SEL = CAT_SEL or 'Bullets';
    end
    -- TABS, one per type (Henrik, 2026-07-26 -- the combo and its "Ammo type:" label
    -- are gone; the strip says what the label used to). The tab whose ammo your
    -- EQUIPPED ranged weapon actually fires lights GREEN, so the panel answers "what
    -- can I even load right now" at a glance instead of making you know that a
    -- Staurobow is a crossbow. Buttons-as-tabs is the hobbybar idiom -- ImGuiCol_Button
    -- is the one style enum proven in the field here, so the two channels are kept
    -- apart by MEANING, not by fighting over one colour: green = what fires, blue =
    -- what you are editing, and the Priority list header below names the selection so
    -- it stays readable even when green wins the same tab.
    for _, c in ipairs(aw.CATEGORIES) do
        local nCfg, nOwn = catCfg[c] or 0, catOwn[c] or 0;
        -- 'Other' still only appears when something is in it; a LIVE type always
        -- appears, or a culverin would light nothing at all.
        if c ~= 'Other' or (nCfg + nOwn) > 0 or c == liveCat then
            local isLive = (c == liveCat);
            local pushed = 0;
            if isLive then
                imgui.PushStyleColor(ImGuiCol_Button, COL_LIVE); pushed = pushed + 1;
            elseif c == CAT_SEL then
                imgui.PushStyleColor(ImGuiCol_Button, COL_SELECTED); pushed = pushed + 1;
            end
            if imgui.Button(string.format('%s (%d)##ammocat_%s', c, nCfg, c), { 0, 0 }) then
                CAT_SEL = c;
            end
            if pushed > 0 then imgui.PopStyleColor(pushed); end
            if imgui.IsItemHovered() then
                local t = string.format('%s -- %d set up, %d more owned.', c, nCfg, nOwn);
                if isLive then
                    t = t .. string.format('\n\nGREEN: your %s fires this type, so this is what\nAutoAmmo can load right now.',
                        esc(tostring(liveWeapon or 'ranged weapon')));
                elseif liveCat ~= nil then
                    t = t .. string.format('\n\nYour %s cannot fire these -- AutoAmmo will not load\nthem while it is equipped. (%s is green.)',
                        esc(tostring(liveWeapon or 'ranged weapon')), liveCat);
                elseif liveWeapon == nil then
                    t = t .. '\n\nNothing in your Range slot -- with no ranged weapon\nequipped AutoAmmo does nothing at all.';
                end
                imgui.SetTooltip(t);
            end
            imgui.SameLine(0, 4);
        end
    end
    imgui.Dummy({ 0, 0 });   -- close the SameLine run

    -- ------------------------------------------------------------------
    -- Priority list. Order IS the engine's fallback order.
    -- ------------------------------------------------------------------
    -- The header carries the selection, so the tab strip's green can mean ONE thing
    -- (what your weapon fires) without also having to say which tab you are on.
    imgui.TextColored(COL_HEADER, 'Priority list -- ' .. esc(tostring(CAT_SEL)));
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
    else
        -- A colour key, not prose: hovering the right row cannot teach you what
        -- a colour MEANS, so this is the one thing a tooltip can't carry.
        imgui.TextColored(COL_DIM, 'green = worn right now   |   red = skipped (above your level, or none in your bags)');
    end
    -- The category-visible subsequence: move buttons swap VISIBLE neighbours
    -- (which need not be adjacent in the underlying all-types list).
    local vis = {};
    for i, e in ipairs(aw.list) do
        if aw.categoryOf(e.name, e.type, e.pair) == CAT_SEL then vis[#vis + 1] = i; end
    end
    if #aw.list > 0 and #vis == 0 then
        imgui.TextColored(COL_DIM, string.format(
            'no %s configured for %s yet -- add from the owned list below (other types: use the selector).',
            string.lower(CAT_SEL), tostring(job or '?')));
    end
    local removeAt = nil;
    local wornL   = liveAmmoName();
    local myLevel = gearLevel();
    for vk, i in ipairs(vis) do
        local e = aw.list[i];
        imgui.PushID('ammorow_' .. i);
        if imgui.SmallButton('^') and vk > 1 then aw.swapAmmo(i, vis[vk - 1]); end
        imgui.SameLine(0, 2);
        if imgui.SmallButton('v') and vk < #vis then aw.swapAmmo(i, vis[vk + 1]); end
        imgui.SameLine(NAME_X);
        local rec = (deps ~= nil and type(deps.lookupByName) == 'function') and deps.lookupByName(e.name) or nil;
        if deps ~= nil and type(deps.renderIcon) == 'function' then
            deps.renderIcon((rec and rec.Id) or e.id, 18);
        end
        local n = countOf(deps, e.id);
        -- GREEN = this is what is in your Ammo slot right now (the §9.6 law).
        local isLiveRow = (wornL ~= nil and string.lower(tostring(e.name)) == wornL);
        imgui.TextColored(isLiveRow and COL_GREEN or ((n >= 1) and COL_TEXT or COL_ERR), esc(e.name));
        if imgui.IsItemHovered() and rec ~= nil and deps ~= nil and type(deps.itemTooltip) == 'function' then
            pcall(deps.itemTooltip, rec);
        end
        imgui.SameLine(QTY_X);
        imgui.TextColored((n >= 1) and COL_DIM or COL_ERR, 'x' .. tostring(n));
        if n < 1 and imgui.IsItemHovered() then
            imgui.SetTooltip('None in your equippable bags -- the engine skips this entry\n(and never plans ammo you do not stock).');
        end
        -- The level gate (v134), the exact twin of the stock column beside it:
        -- red when this rung is out of reach, and the tooltip says the same
        -- thing in the same words -- "the engine skips this entry".
        imgui.SameLine(LVP_X);
        local lv = tonumber(rec and rec.Level) or tonumber(e.level);
        if lv == nil then
            imgui.TextColored(COL_DIM, 'Lv ?');
            if imgui.IsItemHovered() then
                imgui.SetTooltip('This item\'s level is unknown here -- an unknown never disqualifies\nan entry, so the engine still considers it.');
            end
        else
            local tooHigh = (myLevel ~= nil and myLevel < lv);
            imgui.TextColored(tooHigh and COL_ERR or COL_DIM, 'Lv ' .. tostring(lv));
            if imgui.IsItemHovered() then
                if tooHigh then
                    imgui.SetTooltip(string.format(
                        'Needs Lv %d, you are %d -- the engine skips this entry\nand loads the best one you CAN wear, further down.', lv, myLevel));
                else
                    imgui.SetTooltip('You can wear this one.');
                end
            end
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
    imgui.TextColored(COL_HEADER, 'Owned ' .. string.lower(CAT_SEL));
    imgui.SameLine(0, 8);
    imgui.TextColored(COL_DIM, '(in your equippable bags, not configured yet)');
    local shown = 0;
    for _, rec in ipairs(ownedAll) do
        if not inList[string.lower(rec.Name)]
           and aw.categoryOf(rec.Name, rec.AmmoType, rec.Pair) == CAT_SEL then
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
        imgui.TextColored(COL_DIM, string.format(
            'nothing new -- every %s you own is configured (or you carry none).', string.lower(CAT_SEL)));
    end

    imgui.Separator();
    imgui.TextColored(COL_DIM, 'Special ammo is never left equipped where a shot could consume it; with');
    imgui.TextColored(COL_DIM, 'nothing else enabled in your bags, the slot is emptied -- an empty gun');
    imgui.TextColored(COL_DIM, 'refuses the shot, which is the point.');
end

return M;
