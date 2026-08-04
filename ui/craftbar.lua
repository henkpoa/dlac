--[[
    dlac/craftbar.lua -- floating craft control bar.

    A small always-available window: an on/off switch, the eight craft glyphs
    (click to select + equip that craft's gear), the goal (HQ / NQ /
    Skill-Up), a Last Synth button (types the GAME'S OWN /lastsynth -- the
    retail-native repeat command; dlac never intercepts it), and a status
    line naming what that repeat would make (craftwatch's 0x096 observation,
    persisted per char). This is the MANUAL model Henrik settled on --
    you set your gear BEFORE synthing, when equipment changes are legal
    (auto-detection can't, since 0x096 is the first synth packet). The same
    craft/goal controls live in the Automations panel; both drive the single
    craftwatch state.

    Toggle the window: /dl craft bar  (or the button in the Automations panel).
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
if not _iok then return M; end
local cw = require('dlac\\feature\\craftwatch');
local _uok, uistyle = pcall(require, 'dlac\\ui\\uistyle');
_uok = _uok and type(uistyle) == 'table';

local ORDER = { 'Woodworking', 'Smithing', 'Goldsmithing', 'Clothcraft',
                'Leathercraft', 'Bonecraft', 'Alchemy', 'Cooking' };
local GOALS = { { 'hq', 'HQ', 62 }, { 'nq', 'NQ', 62 }, { 'skillup', 'Skill-Up', 86 } };

-- Repeat-synth row. SIX is the cap because six is what a macro bar holds
-- (Henrik) -- these buttons save you the six clicks, they do not craft for you.
-- The run itself lives in feature/synthrun; this file only draws it. Guarded
-- require: a missing/broken synthrun must degrade to the plain Last Synth bar,
-- not take the whole hobby window down with it.
local REPEATS    = { 2, 3, 4, 5, 6 };
local WAIT_BOX_W = 96;
local _srok, sr = pcall(require, 'dlac\\feature\\synthrun');
if not _srok or type(sr) ~= 'table' then sr = nil; end
local _waitBuf, _waitSeen = nil, nil;

-- Craft glyph textures (assets/craft/<Craft>.png), lazy-loaded via D3DX.
local _tex = {};
local function texture(cr)
    local t = _tex[cr];
    if t ~= nil then return (t ~= false) and t or nil; end
    _tex[cr] = false;
    pcall(function()
        local ffi = require('ffi');
        local d3d8 = require('d3d8');
        pcall(ffi.cdef,
            'HRESULT __stdcall D3DXCreateTextureFromFileA(IDirect3DDevice8* pDevice, const char* pSrcFile, IDirect3DTexture8** ppTexture);');
        local dev = d3d8.get_device();
        local path = string.format('%saddons\\dlac\\assets\\craft\\%s.png', AshitaCore:GetInstallPath(), cr);
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileA(dev, path, ptr) == 0 then
            _tex[cr] = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
        end
    end);
    return (_tex[cr] ~= false) and _tex[cr] or nil;
end
M.texture = texture;

-- One clickable craft glyph (bright when selected, dim otherwise). Returns true
-- on click. NOT shared with the Automations panel, whatever the comment here
-- used to say: that panel keeps its own 32px row with its own texture cache,
-- because its glyphs only switch which craft's items are listed -- they do not
-- equip. What the two surfaces DO share is the on/off pill and the skill cell
-- below (M.onOffSwitch / M.craftSkillCell + M.craftSkillUnder).
function M.craftButton(cr, selected, size)
    local drew, tex = false, texture(cr);
    if tex ~= nil then
        drew = pcall(function()
            local ffi = require('ffi');
            imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { size, size },
                { 0, 0 }, { 1, 1 }, selected and { 1, 1, 1, 1 } or { 1, 1, 1, 0.4 });
        end);
        if not drew then
            drew = pcall(function()
                local ffi = require('ffi');
                imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { size, size });
            end);
        end
    end
    if not drew then
        if imgui.Button(cr:sub(1, 4) .. '##cb_' .. cr, { size, size }) then return true; end
        return false;
    end
    local clicked = imgui.IsItemClicked();
    if imgui.IsItemHovered() then imgui.SetTooltip(cr .. '  -- click to equip this craft\'s gear'); end
    return clicked;
end

-- Pill on/off switch: green knob-right = active, red knob-left = inactive
-- (Henrik). Draw-list pill; falls back to a colored button if the draw list
-- isn't available. Returns true when toggled this frame. tipOn/tipOff let
-- other surfaces (the HELM panel/bar) reuse the pill without inheriting the
-- craft tooltips.
-- THE implementation now lives in ui\panelkit.pill, which the Job helper Panel
-- kit needed too -- one pill, drawn identically on a hobby bar, a HELM panel and
-- a Job helper row, and fixed in one place. This stays as the bars' entry point:
-- they call it without an imgui handle, so it passes craftbar's own through (the
-- kit takes the caller's handle, the uistyle.helpLabel contract). Guarded, so an
-- unreachable kit costs the pill its looks and not the bar.
function M.onOffSwitch(on, id, tipOn, tipOff)
    tipOn  = tipOn  or 'Crafting gear is ON -- click to turn off.';
    tipOff = tipOff or 'Crafting gear is OFF -- click to turn on (equips your selected craft).';
    local pk = nil;
    pcall(function() pk = require('dlac\\ui\\panelkit'); end);
    if type(pk) == 'table' and type(pk.pill) == 'function' then
        return pk.pill(imgui, on, id, tipOn, tipOff);
    end
    local toggled = false;                               -- kit unreachable: plain button
    if ImGuiCol_Button ~= nil then
        imgui.PushStyleColor(ImGuiCol_Button, on and { 0.18, 0.55, 0.18, 1 } or { 0.62, 0.18, 0.18, 1 });
    end
    if imgui.Button((on and 'ON' or 'OFF') .. '##onoff_' .. id, { 46, 22 }) then toggled = true; end
    if ImGuiCol_Button ~= nil then imgui.PopStyleColor(1); end
    if imgui.IsItemHovered() then imgui.SetTooltip(on and tipOn or tipOff); end
    return toggled;
end

local isOpen = { true };
local BAR_MIN_W = 430;   -- min CONTENT width (Henrik: wider bar, centered rows;
                         -- fits the goal row + Last Synth with air to spare)

-- ---------------------------------------------------------------------------
-- Skill numbers under the glyphs (2026-08-03). BLUE IS NOT DECORATION. CatsEye
-- sets bit 0x8000 on a craft's skill word the moment it reaches the guild cap
-- -- the comment in charutils.cpp is literally "Blue text." -- and that is the
-- bit the game's own skills menu paints. dlac reads the same bit (see
-- craftwatch.craftSkillInfo), so a blue number here says exactly what a blue
-- number says in the menu: you are at this rank's ceiling, and the next point
-- needs a rank-up test at the guild, not another synth.
--
-- The colour was sampled off the in-game capture Henrik sent (brightest text
-- pixel #659EC9) and nudged up for the antialiasing the sample flattened.
-- ---------------------------------------------------------------------------
local GLYPH_W          = 30;
local COL_SKILL_CAPPED = { 0.42, 0.65, 0.86, 1.00 };   -- at the guild cap
local COL_SKILL        = { 0.70, 0.70, 0.70, 1.00 };   -- room to skill up
local COL_SKILL_UNKNOWN = { 0.42, 0.42, 0.42, 1.00 };  -- unread / never joined

-- The hover behind the number. The icon keeps its own "click to equip" tooltip
-- (craftButton, shared with the Automations panel); this one answers the
-- question the colour raises, which is the panel-text rule -- the surface shows
-- the short thing, the hover explains it.
local function skillTip(craft, info)
    if info == nil then
        return craft .. '\nSkill not readable yet (still logging in?).';
    end
    local s = string.format('%s: skill %d', craft, info.skill);
    if info.cap ~= nil then s = s .. string.format(' / %d', info.cap); end
    local rn = (type(cw.craftRankName) == 'function') and cw.craftRankName(info.rank) or nil;
    if rn ~= nil then s = s .. '  (' .. rn .. ')'; end
    if info.capped then
        s = s .. '\nCAPPED -- blue means you are at this rank\'s ceiling.'
              .. '\nTake the rank-up test at the guild; synthing will not move it.';
    elseif info.cap ~= nil then
        s = s .. string.format('\n%d to go before the cap for this rank.', info.cap - info.skill);
    end
    return s;
end

-- Text width, falling back to the codebase's ~8px/char estimate when the
-- binding's CalcTextSize is unavailable or answers something odd.
local function textW(s)
    local w = #tostring(s) * 8;
    pcall(function()
        local m = imgui.CalcTextSize(s);
        if type(m) == 'number' then w = m; end
    end);
    return w;
end

-- ---- the shared cell (both surfaces that draw craft glyphs use these) -------
-- The bar and the Automations panel draw their glyph rows differently -- 30px
-- and equip-on-click here, 32px and switch-the-section there -- but the NUMBER
-- under a glyph must be the same number in the same colour with the same hover,
-- or the two surfaces start arguing about whether you are capped. So the cell is
-- shared and the rows are not.
--
-- MEASURE, then DRAW, in two calls: both callers center their own row and so
-- need the width before the first glyph goes down, and a 3-digit skill is wider
-- than the glyph above it. `glyphW` is the caller's icon size; `w` comes back as
-- the column width, the wider of the two.
function M.craftSkillCell(craft, glyphW)
    local info = (type(cw.craftSkillInfo) == 'function') and cw.craftSkillInfo(craft) or nil;
    local txt  = (info ~= nil) and tostring(info.skill) or '--';
    return { craft = craft, info = info, txt = txt, tw = textW(txt),
             w = math.max(tonumber(glyphW) or GLYPH_W, textW(txt)) };
end

-- Draw a measured cell's number. Call it INSIDE the glyph's group, immediately
-- after the glyph -- it centers itself against the group's left edge, which is
-- the glyph's own left edge, so it lands under its own icon and not the window.
function M.craftSkillUnder(cell)
    if type(cell) ~= 'table' then return; end
    pcall(function()
        local x = imgui.GetCursorPosX();
        if type(x) == 'number' then
            imgui.SetCursorPosX(x + math.max(0, math.floor((cell.w - cell.tw) / 2)));
        end
    end);
    local col = COL_SKILL;
    if cell.info == nil or cell.info.skill == 0 then
        col = COL_SKILL_UNKNOWN;      -- unreadable, or a guild you never joined
    elseif cell.info.capped then
        col = COL_SKILL_CAPPED;
    end
    imgui.TextColored(col, cell.txt);
    if imgui.IsItemHovered() then imgui.SetTooltip(skillTip(cell.craft, cell.info)); end
end

-- Center the next row of known width within the bar: Dummy + SameLine(indent)
-- (the automationsui craft-glyph pattern).
local function centerNext(availW, rowW)
    local indent = math.max(0, math.floor((availW - rowW) / 2));
    if indent > 0 then imgui.Dummy({ 0, 0 }); imgui.SameLine(indent); end
end

-- The craft bar's CONTENT (no window chrome). Drawn by ui/hobbybar.lua inside the
-- one shared hobby window; availW is that window's content-region width. The same
-- craft/goal controls also live on the Automations panel -- both drive the single
-- craftwatch state. (Was M.render + its own d3d_present window until the bars were
-- unified into hobbybar, ADR 0017.)
function M.renderContent(availW)
    if type(availW) ~= 'number' or availW < BAR_MIN_W then availW = BAR_MIN_W; end
    local sel = cw.getCraft();
    local on = cw.isEnabled();
    -- Wait-timer buffer. Seeded once, then the BUFFER is what you are typing
    -- into; it is re-seeded only when the stored value changes underneath us
    -- (the per-char craftstate.lua landing after login, where charDir() was nil
    -- on the first frames and getSynthWait() was still answering the default).
    local waitSecs = (type(cw.getSynthWait) == 'function') and cw.getSynthWait() or 30;
    local waitMin  = tonumber(cw.WAIT_MIN) or 20;
    local waitMax  = tonumber(cw.WAIT_MAX) or 120;
    if _waitBuf == nil or (_waitSeen ~= nil and _waitSeen ~= waitSecs) then _waitBuf = { waitSecs }; end
    _waitSeen = waitSecs;
    -- Row 1, centered: the 8 craft glyphs, each with its skill under it, + the
    -- on/off switch.
    --
    -- MEASURE FIRST, then draw. Each craft is a GROUP (glyph over number), so a
    -- column is as wide as the wider of the two -- and centerNext needs the row
    -- width BEFORE the first group is begun. Reading the eight skills up front
    -- also means the row cannot change width halfway through itself.
    local cols = {};
    local rowW = 0;
    for i, cr in ipairs(ORDER) do
        cols[i] = M.craftSkillCell(cr, GLYPH_W);
        rowW = rowW + cols[i].w;
    end
    centerNext(availW, rowW + 7 * 6 + 6 + 46);
    for _, c in ipairs(cols) do
        imgui.BeginGroup();
        if M.craftButton(c.craft, sel == c.craft, GLYPH_W) then cw.selectCraft(c.craft); end
        M.craftSkillUnder(c);
        imgui.EndGroup();
        imgui.SameLine(0, 6);
    end
    if M.onOffSwitch(on, 'bar') then cw.setEnabled(not on); end
    imgui.Separator();
    -- Row 2, centered: goal toggles + the Last Synth action (an ACTION, not a
    -- goal -- extra gap + no green-active state).
    local ls = (type(cw.lastSynth) == 'function') and cw.lastSynth() or nil;
    local goalW = 34;
    pcall(function()
        local w = imgui.CalcTextSize('Goal:');
        if type(w) == 'number' then goalW = w; end
    end);
    -- Last Synth is MEASURED, not hardcoded: 86 (the Skill-Up width) clipped the
    -- trailing 'h' (Henrik). Text + padding, never narrower than the goal buttons.
    local lastW = 100;
    pcall(function()
        local w = imgui.CalcTextSize('Last Synth');
        if type(w) == 'number' then lastW = math.max(96, math.floor(w) + 18); end
    end);
    centerNext(availW, goalW + 6 + 62 + 4 + 62 + 4 + 86 + 12 + lastW);
    local goal = cw.getGoal();
    imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, 'Goal:'); imgui.SameLine(0, 6);
    for i, gd in ipairs(GOALS) do
        local gon = (goal == gd[1]);
        if gon then imgui.PushStyleColor(ImGuiCol_Button, { 0.16, 0.55, 0.24, 1 }); end
        if imgui.Button(gd[2] .. '##cbgoal' .. gd[1], { gd[3], 20 }) then cw.setGoal(gd[1]); end
        if gon then imgui.PopStyleColor(1); end
        if i < #GOALS then imgui.SameLine(0, 4); end
    end
    imgui.SameLine(0, 12);
    -- Last Synth / Stop, IN PLACE. While a batch runs this same button is the
    -- brake (Henrik): the biggest target on the bar, and having no live "fire
    -- one now" button means a second batch cannot be started on top of the
    -- first, nor the count desynced.
    local st = (sr ~= nil and type(sr.status) == 'function') and sr.status() or nil;
    if st ~= nil then
        imgui.PushStyleColor(ImGuiCol_Button, { 0.62, 0.18, 0.18, 1 });
        local label = string.format('Stop  %d/%d##cblast', st.done, st.total);
        if imgui.Button(label, { lastW, 20 }) then sr.stop(); end
        imgui.PopStyleColor(1);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Stop the run. The synth already in progress finishes;\nno further /lastsynth is issued.');
        end
    else
        -- The button just TYPES the game's own /lastsynth (retail-native text command;
        -- Henrik: dlac must never intercept or wrap it -- the client does the repeat).
        if imgui.Button('Last Synth##cblast', { lastW, 20 }) then
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/lastsynth'); end);
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Issues the game\'s own /lastsynth -- repeats your most recent synthesis.'
                .. ((ls ~= nil and ls.name ~= nil) and ('\nLast seen: ' .. ls.name) or '')
                .. '\nAlso works typed or in a macro: /lastsynth (and /lastsynth check).');
        end
    end

    -- Row 3, centered: repeat counts + the wait timer. Six is the cap because
    -- six is what a macro bar holds (Henrik) -- this saves the clicks, it does
    -- not craft for you.
    local numW = 26;
    pcall(function()
        local w = imgui.CalcTextSize('6');
        if type(w) == 'number' then numW = math.max(24, math.floor(w) + 18); end
    end);
    local waitLabW = 30;
    pcall(function()
        local w = imgui.CalcTextSize('Wait');
        if type(w) == 'number' then waitLabW = math.floor(w); end
    end);
    centerNext(availW, #REPEATS * numW + (#REPEATS - 1) * 4 + 14 + waitLabW + 6 + WAIT_BOX_W + 16);
    local running = (st ~= nil);
    for i, n in ipairs(REPEATS) do
        if running then
            imgui.PushStyleColor(ImGuiCol_Button, { 0.22, 0.22, 0.22, 1 });
            imgui.PushStyleColor(ImGuiCol_Text,   { 0.45, 0.45, 0.45, 1 });
        end
        -- Locked, not merely discouraged: the click is DROPPED while a batch
        -- runs, so a double-click can never stack two runs (Henrik).
        if imgui.Button(tostring(n) .. '##cbrep' .. n, { numW, 20 }) and not running then
            if sr ~= nil then sr.start(n); end
        end
        if running then imgui.PopStyleColor(2); end
        if imgui.IsItemHovered() then
            if running then
                imgui.SetTooltip('A run is in progress -- Stop it first.');
            else
                imgui.SetTooltip(string.format(
                    'Synth the last recipe %d times, %ds apart.\nOne /lastsynth at a time; stops early if a synth does not start.', n, waitSecs));
            end
        end
        if i < #REPEATS then imgui.SameLine(0, 4); end
    end
    imgui.SameLine(0, 14);
    imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, 'Wait'); imgui.SameLine(0, 6);
    if running then
        imgui.TextColored({ 0.50, 0.50, 0.50, 1 }, string.format('%ds', waitSecs));
    else
        imgui.PushItemWidth(WAIT_BOX_W);
        if imgui.InputInt('s##cbwait', _waitBuf) then
            local v = math.floor(tonumber(_waitBuf[1]) or waitSecs);
            -- Clamp the TOP on every keystroke, the BOTTOM only on blur --
            -- clamping low mid-type makes "45" unreachable (you'd pass 4).
            if v > waitMax then v = waitMax; _waitBuf[1] = v; end
            if v >= waitMin then cw.setSynthWait(v); end
        end
        imgui.PopItemWidth();
        local editing = false;
        pcall(function() editing = imgui.IsItemActive(); end);
        if not editing then
            local v = math.floor(tonumber(_waitBuf[1]) or waitSecs);
            if v < waitMin then _waitBuf[1] = waitMin; cw.setSynthWait(waitMin); end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(string.format(
                'Seconds between synths (%d-%d, remembered for this character).\n'
                .. 'About %ds is the real floor in a quiet zone. The synth animation is\n'
                .. 'frame-tied, so a busy zone like Lower Jeuno needs more -- if synths\n'
                .. 'get skipped, raise this.', waitMin, waitMax, 22));
        end
    end

    -- Status line: WHAT the Last Synth button would make (Henrik: so you know what
    -- it will do before clicking) -- or, mid-run, where the batch has got to.
    if st ~= nil then
        imgui.TextColored({ 0.95, 0.85, 0.45, 1 }, string.format('Synth %d of %d', st.done, st.total));
        imgui.SameLine(0, 6);
        if st.stage == 'finish' then
            imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, '-- finishing...');
        elseif st.nextIn ~= nil then
            imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, string.format('-- next in %ds', st.nextIn));
        elseif st.retrying then
            imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, '-- no synth started, retrying');
        else
            imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, '-- synthing');
        end
    else
        imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, 'Last synth:');
        imgui.SameLine(0, 6);
        if ls == nil then
            imgui.TextColored({ 0.50, 0.50, 0.50, 1 }, '(none on record -- synth once via the menu)');
        else
            imgui.TextColored({ 0.95, 0.85, 0.45, 1 }, ls.name or 'unknown recipe');
            if ls.skill ~= nil and ls.skill ~= 'unknown' then
                imgui.SameLine(0, 0);
                imgui.TextColored({ 0.70, 0.70, 0.70, 1 }, string.format('  (%s%s%s)',
                    ls.skill, ls.lv and (' ' .. ls.lv) or '', ls.desynth and ', desynth' or ''));
            end
        end
    end
    imgui.Dummy({ BAR_MIN_W, 1 });   -- enforces the min width under AlwaysAutoResize
end

return M;
