--[[
    dlac/helmui.lua -- the Auto HELM Set panel (docs/design/helm-gear.md).

    Rendered inside triggersui's Automations detail (auto.view == 'helm');
    lives in its OWN module because triggersui rides the LuaJIT 200-local
    chunk cap -- triggersui only pcall-requires this at render time and hands
    over its deps table (lookupByName / ownedCounts / renderIcon /
    itemTooltip / playerJob -- the trigui.init injection).

    Layout (Henrik's spec, verbatim intent):
      four columns, rows height-aligned --
        1: Field gear (Body/Hands/Legs/Feet, then Torque/Rope at the bottom)
        2: Plain pieces (VP shop)          3: Plain +1 (commendation upgrade)
        4: the four category hats (goblin NPC order: Harv/Excav/Log/Mine)
      green = owned OR a strictly-better corresponding piece is owned (the
      "you're awesome" cascade: Plain +1 greens Plain AND Field of its slot);
      top-tier pieces (Plain +1, hats) get a HOLY-LIGHT backlight when owned
      (dopamine is a design requirement). Below: the category tab row
      (assets/helm glyphs) with venture points + today's ventures per tab.
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
if not _iok then return M; end

local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_DIM    = { 0.55, 0.55, 0.55, 1.00 };
local COL_TEXT   = { 0.70, 0.70, 0.70, 1.00 };
local COL_GOLD   = { 0.95, 0.85, 0.45, 1.00 };
local GREEN_OWNED = { 0.45, 0.90, 0.45, 1.0 };
local GREEN_GLOW  = { 0.75, 1.00, 0.70, 1.0 };   -- the backlit tier reads brighter

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

-- ---------------------------------------------------------------------------
-- The progression matrix. Slot rows in Henrik's order; hats in the goblin
-- NPC's sales order. Names are exact catalog names (ids in the design doc).
-- ---------------------------------------------------------------------------
local ROWS = {
    { field = 'Field Tunica', plain = 'Plain Tunica', p1 = 'Plain Tunica +1' },
    { field = 'Field Gloves', plain = 'Plain Gloves', p1 = 'Plain Gloves +1' },
    { field = 'Field Hose',   plain = 'Plain Hose',   p1 = 'Plain Hose +1'   },
    { field = 'Field Boots',  plain = 'Plain Boots',  p1 = 'Plain Boots +1'  },
};
local FIELD_EXTRA = { 'Field Torque', 'Field Rope' };   -- no better variant (yet)
local HATS = {   -- goblin NPC order; VP prices from the wiki (5000 each)
    { g = 'Harvesting', name = 'Harv. Sun Hat'     },
    { g = 'Excavation', name = 'Excavators Shades' },
    { g = 'Logging',    name = 'Lumberjacks Beret' },
    { g = 'Mining',     name = 'Miners Helmet'     },
};

local ORDER = { 'Harvesting', 'Excavation', 'Logging', 'Mining' };
local selected = 'Harvesting';
local _tex = {};           -- category glyphs (assets/helm/<Category>.png)
local _vpSectionSeen = nil;

local function texture(g)
    local t = _tex[g];
    if t ~= nil then return (t ~= false) and t or nil; end
    _tex[g] = false;
    pcall(function()
        local ffi = require('ffi');
        local d3d8lib = require('d3d8');
        pcall(ffi.cdef,
            'HRESULT __stdcall D3DXCreateTextureFromFileA(IDirect3DDevice8* pDevice, const char* pSrcFile, IDirect3DTexture8** ppTexture);');
        local dev = d3d8lib.get_device();
        local path = string.format('%saddons\\dlac\\assets\\helm\\%s.png', AshitaCore:GetInstallPath(), g);
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileA(dev, path, ptr) == 0 then
            _tex[g] = d3d8lib.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
        end
    end);
    return (_tex[g] ~= false) and _tex[g] or nil;
end
M.texture = texture;   -- helmbar reuses the same loader/cache

-- ---------------------------------------------------------------------------
-- ownership (the triggersui ownedRec pattern, deps passed per call)
-- ---------------------------------------------------------------------------
local function ownedRec(deps, name)
    if deps == nil or deps.lookupByName == nil then return nil; end
    local rec = deps.lookupByName(name);
    if rec == nil or rec.Id == nil then return nil; end
    local oc = (deps.ownedCounts ~= nil) and deps.ownedCounts() or nil;
    if type(oc) == 'table' and (oc[rec.Id] or 0) >= 1 then return rec; end
    return nil;
end
local function owns(deps, name) return ownedRec(deps, name) ~= nil; end

-- ---------------------------------------------------------------------------
-- One matrix line. state: 'glow' (owned top tier -- holy backlight),
-- 'owned' (green), 'better' (green via a better corresponding piece),
-- 'dim' (nothing). Glow = layered soft-gold rounded rects behind icon+text
-- (draw-list; ABGR u32s, the craftbar pill precedent); a pcall failure
-- degrades to the plain green line.
-- ---------------------------------------------------------------------------
local function itemLine(deps, name, state, note)
    if state == 'glow' then
        pcall(function()
            local x, y = imgui.GetCursorScreenPos();
            local w = 24 + imgui.CalcTextSize(name);
            local dl = imgui.GetWindowDrawList();
            dl:AddRectFilled({ x - 4, y - 2 }, { x + w + 6, y + 18 }, 0x1E8CE6FF, 9);
            dl:AddRectFilled({ x - 2, y - 1 }, { x + w + 3, y + 17 }, 0x2895EBFF, 7);
            dl:AddRectFilled({ x + 1, y + 1 }, { x + w - 2, y + 15 }, 0x30A0F0FF, 5);
        end);
    end
    local rec = (deps ~= nil and deps.lookupByName ~= nil) and deps.lookupByName(name) or nil;
    if deps ~= nil and type(deps.renderIcon) == 'function' then
        deps.renderIcon(rec and rec.Id or nil, 18);
    end
    local col = COL_DIM;
    if state == 'glow' then col = GREEN_GLOW;
    elseif state == 'owned' or state == 'better' then col = GREEN_OWNED; end
    imgui.TextColored(col, esc(name));
    if imgui.IsItemHovered() then
        if note ~= nil then
            imgui.SetTooltip(note);
        elseif rec ~= nil and deps ~= nil and type(deps.itemTooltip) == 'function' then
            pcall(deps.itemTooltip, rec);
        end
    end
end

-- Per-slot cascade states for one matrix row.
local function rowStates(deps, row)
    local f, p, p1 = owns(deps, row.field), owns(deps, row.plain), owns(deps, row.p1);
    local fs = (f or p or p1) and ((not f and 'better') or 'owned') or 'dim';
    local ps = (p or p1) and ((not p and 'better') or 'owned') or 'dim';
    local ps1 = p1 and 'glow' or 'dim';
    return fs, ps, ps1;
end

local BETTER_NOTE = 'Green via progression: you own a better piece for this slot --\nso this one is covered. You\'re awesome.';

-- ---------------------------------------------------------------------------
-- Coverage level for the Automations LIST row (levelColor ramp).
--   1 = field gear started; 2 = break-proof (+5 rating); 3 = +5 AND Surveyor
--   pieces online; 4 = every Plain +1 AND every hat (the full kit).
-- ---------------------------------------------------------------------------
M.txt = { [0] = 'nothing applicable', 'field gear started', 'break-proof (+5)',
          'Surveyor online', 'FULL KIT -- awesome' };

-- level + the wearable-at-once totals (Henrik: show HELM+ / Surveyor+ next to
-- the status). Per slot the BEST owned tier counts (catalog stats); hats
-- contribute the best single Surveyor -- only one head fits.
local function coverage(deps)
    local rating, anyPiece, anySurv = 0, false, false;
    local allTop = true;
    local helmTot, survTot = 0, 0;
    local function statsOf(name)
        local rec = (deps ~= nil and deps.lookupByName ~= nil) and deps.lookupByName(name) or nil;
        local st = (rec ~= nil and type(rec.Stats) == 'table') and rec.Stats or {};
        return tonumber(st.HELM) or 0, tonumber(st.Surveyor) or 0;
    end
    for _, row in ipairs(ROWS) do
        local f, p, p1 = owns(deps, row.field), owns(deps, row.plain), owns(deps, row.p1);
        if f or p or p1 then rating = rating + 1; anyPiece = true; end
        if p or p1 then anySurv = true; end
        if not p1 then allTop = false; end
        local best = (p1 and row.p1) or (p and row.plain) or (f and row.field) or nil;
        if best ~= nil then
            local h, s = statsOf(best);
            helmTot = helmTot + h; survTot = survTot + s;
        end
    end
    for _, nm in ipairs(FIELD_EXTRA) do
        if owns(deps, nm) then
            rating = rating + 1; anyPiece = true;
            local h, s = statsOf(nm);
            helmTot = helmTot + h; survTot = survTot + s;
        end
    end
    local hatSurv = 0;
    for _, h in ipairs(HATS) do
        if owns(deps, h.name) then
            anySurv = true; anyPiece = true;
            local _, s = statsOf(h.name);
            if s > hatSurv then hatSurv = s; end
        else
            allTop = false;
        end
    end
    survTot = survTot + hatSurv;
    local level = 0;
    if allTop then level = 4;
    elseif rating >= 5 and anySurv then level = 3;
    elseif rating >= 5 then level = 2;
    elseif anyPiece then level = 1; end
    return level, helmTot, survTot;
end

function M.level(deps) return (select(1, coverage(deps))); end

-- level + display text for the Automations list row: the coverage label with
-- the wearable totals appended once anything is owned.
function M.status(deps)
    local level, helmTot, survTot = coverage(deps);
    local txt = M.txt[level] or '';
    if level > 0 and (helmTot > 0 or survTot > 0) then
        txt = string.format('%s (HELM+%d, Surv+%d)', txt, helmTot, survTot);
    end
    return level, txt;
end
M.maxLevel = 4;

-- ---------------------------------------------------------------------------
-- The detail view (triggersui: auto.view == 'helm').
-- ---------------------------------------------------------------------------
function M.render(deps, availW)
    local hwok, hw = pcall(require, 'dlac\\feature\\helmwatch');
    hwok = hwok and type(hw) == 'table';

    imgui.TextColored(COL_HEADER, 'Auto HELM Set');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_TEXT, 'pick a category (on the floating bar) -> wears your best gathering gear ON IDLE ONLY.');
    -- The two switches (Henrik's split): "Set HELM Idle" = the manual pin,
    -- session-only OFF at login; "Auto HELM" = detection-armed temporary
    -- overlay, PERSISTED until turned off.
    local on = hwok and hw.isEnabled();
    imgui.TextColored(COL_TEXT, 'Set HELM Idle:');
    imgui.SameLine(0, 6);
    local cbok, craftbar = pcall(require, 'dlac\\ui\\craftbar');
    local pill = (cbok and type(craftbar) == 'table' and type(craftbar.onOffSwitch) == 'function')
        and craftbar.onOffSwitch or nil;
    local IDLE_ON  = 'HELM idle set is ON -- your gathering gear stays on while idle.\nStarts OFF each session; click to turn off.';
    local IDLE_OFF = 'Wears your best gathering gear whenever you are idle, until turned off.\nStarts OFF each session.';
    if pill ~= nil then
        if pill(on, 'helmidle', IDLE_ON, IDLE_OFF) and hwok then hw.setEnabled(not on); end
    else
        if imgui.Button((on and 'ON' or 'OFF') .. '##helmpanelonoff', { 46, 22 }) and hwok then hw.setEnabled(not on); end
    end
    imgui.SameLine(0, 14);
    local autoOn = hwok and hw.isAutoHelm();
    imgui.TextColored(COL_TEXT, 'Auto HELM:');
    imgui.SameLine(0, 6);
    local rangeY = (hwok and type(hw.proxEnter) == 'function') and hw.proxEnter() or 10;
    local AUTO_ON  = string.format('Auto HELM is ON: target a gathering Point within %d yalms (or just swing)\nand that category\'s gear equips itself; it stays on while you remain near\nthe SAME point -- even though HELMing clears your target -- and your normal\ngear returns moments after you walk away. Starts OFF each session.\nClick to turn off.', rangeY);
    local AUTO_OFF = string.format('Target a gathering Point within %d yalms (or swing at one) and Auto HELM\nequips that category\'s gear; it stays on while you remain near that point\nand your normal gear returns moments after you leave. Starts OFF each\nsession (a tab-target in passing should not re-dress you).', rangeY);
    if pill ~= nil then
        if pill(autoOn, 'helmauto', AUTO_ON, AUTO_OFF) and hwok then hw.setAutoHelm(not autoOn); end
    else
        if imgui.Button((autoOn and 'ON' or 'OFF') .. '##helmautoonoff', { 46, 22 }) and hwok then hw.setAutoHelm(not autoOn); end
    end
    imgui.SameLine(0, 14);
    imgui.TextColored(COL_TEXT, 'Range:');
    imgui.SameLine(0, 4);
    local rb = { rangeY };
    imgui.PushItemWidth(64);
    if imgui.InputInt('##helmproxrange', rb) and hwok and type(hw.setProxRange) == 'function' then
        hw.setProxRange(rb[1]);
    end
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Auto HELM detect range in yalms (3-20, default 10): how close a targeted\ngathering Point must be to equip in advance. Raise it if lag or macro spam\nmakes your swings land from further out; the keep-wearing leash is +2y.\nRemembered per character.');
    end
    imgui.SameLine(0, 10);
    local barOn = hwok and (hw.barVisible == true);
    if imgui.Button((barOn and 'Hide bar' or 'Show bar') .. '##helmbartoggle', { 78, 22 }) and hwok then
        hw.barVisible = not barOn;
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The floating HELM bar: category glyphs, the switches, points and rating.\nAlso /dl helm bar.');
    end
    imgui.SameLine(0, 14);
    local activeG = hwok and hw.getGather() or nil;
    imgui.TextColored(COL_DIM, 'Active: ' .. tostring(activeG or '(none)'));
    if hwok and hw.autoActive() then
        imgui.SameLine(0, 8);
        imgui.TextColored(GREEN_OWNED, '-- AUTO holding');
    end
    imgui.Spacing();

    -- The four-column progression matrix.
    local colW = math.max(200, math.floor((availW or 800) / 4));
    imgui.BeginGroup();
    imgui.TextColored(COL_HEADER, 'Field Gear');
    for _, row in ipairs(ROWS) do
        local fs = select(1, rowStates(deps, row));
        itemLine(deps, row.field, fs, (fs == 'better') and BETTER_NOTE or nil);
    end
    imgui.TextColored(COL_DIM, '- - - - - - - -');
    for _, nm in ipairs(FIELD_EXTRA) do
        itemLine(deps, nm, owns(deps, nm) and 'owned' or 'dim');
    end
    imgui.EndGroup();
    imgui.SameLine(colW);
    imgui.BeginGroup();
    imgui.TextColored(COL_HEADER, 'Plain (3000 VP)');
    for _, row in ipairs(ROWS) do
        local _, ps = rowStates(deps, row);
        itemLine(deps, row.plain, ps, (ps == 'better') and BETTER_NOTE or nil);
    end
    imgui.EndGroup();
    imgui.SameLine(colW * 2);
    imgui.BeginGroup();
    imgui.TextColored(COL_HEADER, 'Plain +1');
    for _, row in ipairs(ROWS) do
        local _, _, ps1 = rowStates(deps, row);
        itemLine(deps, row.p1, ps1);
    end
    imgui.EndGroup();
    imgui.SameLine(colW * 3);
    imgui.BeginGroup();
    imgui.TextColored(COL_HEADER, 'Hats (5000 VP)');
    for _, h in ipairs(HATS) do
        itemLine(deps, h.name, owns(deps, h.name) and 'glow' or 'dim');
    end
    imgui.EndGroup();
    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Category selector: the four glyphs, centered (the craft selector
    -- pattern -- a view switch here; the ACTIVE category lives on the bar).
    local rowW = 4 * 32 + 3 * 14;
    local indent = math.max(0, math.floor(((availW or 800) - rowW) / 2));
    if indent > 0 then imgui.Dummy({ 0, 0 }); imgui.SameLine(indent); end
    for i, g in ipairs(ORDER) do
        local sel = (selected == g);
        local tex = texture(g);
        local drew = false;
        if tex ~= nil then
            drew = pcall(function()
                local ffi = require('ffi');
                imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { 32, 32 },
                    { 0, 0 }, { 1, 1 }, sel and { 1, 1, 1, 1 } or { 1, 1, 1, 0.45 });
            end);
        end
        if not drew then
            if imgui.Button(g:sub(1, 4) .. '##helmtab' .. g, { 32, 32 }) then selected = g; end
        end
        if imgui.IsItemClicked() then selected = g; end
        if imgui.IsItemHovered() then imgui.SetTooltip(g .. '  -- show this category\'s points and ventures'); end
        if i < #ORDER then imgui.SameLine(0, 14); end
    end
    imgui.Spacing();

    -- Venture points for the selected category (0x1A4 GET_POINTS; every entry
    -- into this section re-requests -- the craft panel's GP-refresh pattern).
    if hwok then
        if _vpSectionSeen == nil or (os.clock() - _vpSectionSeen) > 1.0 then
            pcall(function() hw.requestPoints(true); end);
        end
        _vpSectionSeen = os.clock();
    end
    imgui.TextColored(COL_HEADER, selected .. ' Venture Points: ');
    imgui.SameLine(0, 4);
    local vp = nil;
    if hwok then pcall(function() vp = hw.pointsFor(selected); end); end
    if vp ~= nil then
        imgui.TextColored(COL_GOLD, tostring(vp));
    elseif hwok and hw.pointsReady() then
        imgui.TextColored(COL_DIM, 'not in the points stream yet  (/dl helm points to inspect)');
    else
        imgui.TextColored(COL_DIM, '(requested -- reopen in a moment)');
    end

    -- The category's double-yield hat.
    local hat = nil;
    for _, h in ipairs(HATS) do if h.g == selected then hat = h; break; end end
    if hat ~= nil then
        imgui.TextColored(COL_TEXT, 'Double-yield hat:');
        imgui.SameLine(0, 6);
        imgui.TextColored(owns(deps, hat.name) and GREEN_OWNED or COL_DIM, esc(hat.name));
    end
    imgui.Spacing();

    -- Today's ventures for this category (0x017-captured; format pinned by
    -- field capture -- until then the keyword buckets carry the display).
    imgui.TextColored(COL_HEADER, 'Today\'s ' .. selected .. ' ventures:');
    imgui.SameLine(0, 8);
    -- MEASURED width (themed-font rule: ~9.5px/char clips fixed 110) + full
    -- button height -- field report: the label was cropped both ways.
    local vbW = 152;
    pcall(function()
        local w = imgui.CalcTextSize('!ventures helm');
        if type(w) == 'number' then vbW = math.max(152, math.floor(w) + 18); end
    end);
    if imgui.Button('!ventures helm##helmvent', { vbW, 22 }) then
        pcall(function()
            hw.openCapture(6);
            AshitaCore:GetChatManager():QueueCommand(1, '!ventures helm');
        end);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Types the server\'s own !ventures helm and captures the reply\n(also refreshes this list).');
    end
    local lines, fresh, general = nil, false, nil;
    if hwok then pcall(function() lines, fresh, general = hw.venturesFor(selected); end); end
    if lines ~= nil and #lines > 0 then
        if not fresh then
            imgui.TextColored(COL_DIM, '(from a previous JST day -- refresh)');
        end
        for _, ln in ipairs(lines) do
            imgui.TextColored(fresh and COL_TEXT or COL_DIM, esc(ln));
        end
    else
        imgui.TextColored(COL_DIM, '(none captured yet -- click the button, or type !ventures helm yourself)');
    end
    if general ~= nil and #general > 0 then
        imgui.TextColored(COL_DIM, 'Uncategorized venture lines:');
        for _, ln in ipairs(general) do imgui.TextColored(COL_DIM, esc(ln)); end
    end
    imgui.Spacing();

    -- Last auto-detected category (outgoing-trade watch).
    if hwok and hw.lastDetect ~= nil then
        imgui.TextColored(COL_DIM, string.format('Last gathering detected: %s (%s)',
            hw.lastDetect.gather, hw.lastDetect.npc or '?'));
    end
    imgui.TextColored(COL_DIM, 'Green = owned (or a better piece covers it); backlit = top tier owned. +5 rating = no tool breakage\n(excavation excepted -- As Square Enix Intended). Surveyor trims "you find nothing" results.');
end

return M;
