--[[
    dlac/ui/restockui.lua -- the E-Box Restock panel (docs/design/ebox-restock.md;
    ADR 0016). Rendered inside automationsui's Automations detail
    (auto.view == 'restock'); its own module (the 200-local law). CRYSTAL
    WARRIORS ONLY -- automationsui only adds the row when gamemode.get() == 'CW',
    and this render re-checks (belt-and-braces).

    It edits ONE thing: <char>\dlac\restock.lua, through restockwatch's mutators
    (the pure config + planner). Counts + withdraws go through the ONE E-Box
    client (feature/eboxclient); on-hand + free-slots are read live from the
    field bags {Inventory 0, Satchel 5, Sack 6, Case 7} / Inventory (0). Nothing
    here equips or touches the dispatch engine.

    Layout: master ON/OFF + the two nudge settings; a proximity line + Rescan;
    two sections sharing fixed columns -- "Always (every job)" (the character
    list) and "<JOB> only" (the job list, whose target overrides the character
    baseline for the same item); a Fetch all; the slot-safety footer. Every fetch
    is pre-clamped by the planner to min(shortfall, in-box, room), so a click can
    never over-draw or lose items.

    The floating Restock nudge is a SEPARATE surface (M.nudge, hooked from
    gearui's d3d_present); not in this file yet.
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local _rwok, rw = pcall(require, 'dlac\\feature\\restockwatch');
_rwok = _rwok and type(rw) == 'table';
local _ecok, ec = pcall(require, 'dlac\\feature\\eboxclient');
_ecok = _ecok and type(ec) == 'table';
local _gmok, gm = pcall(require, 'dlac\\feature\\gamemode');
_gmok = _gmok and type(gm) == 'table';

local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_DIM    = { 0.55, 0.55, 0.55, 1.00 };
local COL_TEXT   = { 0.70, 0.70, 0.70, 1.00 };
local COL_ERR    = { 0.95, 0.45, 0.40, 1.00 };
local COL_GOLD   = { 0.95, 0.85, 0.45, 1.00 };
local COL_GREEN  = { 0.45, 0.90, 0.45, 1.00 };
local BTN_RED_OFF  = { 0.45, 0.14, 0.14, 1.0 };   -- out of box range
local BTN_GREY_OFF = { 0.28, 0.28, 0.28, 1.0 };   -- nothing to fetch / busy

-- Shared fixed columns (themed font ~9.5px/char). The E-Box AND the field bags
-- can EACH hold 10000+ of a stackable, so every number column fits 5+ digits;
-- Fetch and x sit RELATIVE to the input (SameLine(0, GAP)) so they can never
-- clip into it however wide the number gets.
local NAME_X   = 30;
local NAME_MAX = 18;    -- clip long names so they never run into the have column
local HAVE_X   = 210;
local BOX_X    = 330;
local TGT_X    = 440;
local TGT_W    = 78;    -- the target input width (5+ digits) -- no +/- steppers
local GAP      = 12;

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end
local function clip(s, n)
    s = tostring(s or '');
    if #s <= n then return s; end
    return s:sub(1, n) .. '..';
end

-- The affirmative CW gate (unknown/Wings/ACE = not CW).
local function cwOK()
    if not _gmok then return false; end
    local ok, mode = pcall(gm.get);
    return ok and mode == 'CW';
end

-- ---------------------------------------------------------------------------
-- Live bag reads (AshitaCore; pcall-guarded, headless-safe).
-- ---------------------------------------------------------------------------
local FIELD_BAGS = { 0, 5, 6, 7 };   -- Inventory, Satchel, Sack, Case (useitem BAG_NAMES)

-- On-hand across the FIELD bags, one pass -> { id -> count }.
local function fieldCounts()
    local m = {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for _, bag in ipairs(FIELD_BAGS) do
            local max = inv:GetContainerCountMax(bag) or 0;
            for i = 1, max do
                local it = inv:GetContainerItem(bag, i);
                if it ~= nil and (it.Id or 0) > 0 and (it.Count or 0) > 0 then
                    m[it.Id] = (m[it.Id] or 0) + it.Count;
                end
            end
        end
    end);
    return m;
end

-- Free slots in Inventory (container 0) -- where withdrawals land (the room gate).
local function freeInvSlots()
    local free = 0;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local max = inv:GetContainerCountMax(0) or 0;
        for i = 1, max do
            local it = inv:GetContainerItem(0, i);
            if it == nil or (it.Id or 0) == 0 or (it.Count or 0) == 0 then free = free + 1; end
        end
    end);
    return free;
end

local _stackCache = {};
local function stackOf(id)
    if _stackCache[id] ~= nil then return _stackCache[id]; end
    local s = 1;
    pcall(function()
        local r = AshitaCore:GetResourceManager():GetItemById(id);
        if r ~= nil and (tonumber(r.StackSize) or 0) > 0 then s = r.StackSize; end
    end);
    _stackCache[id] = s;
    return s;
end

-- ---------------------------------------------------------------------------
-- Automations list row contract (above the imgui guard -- the fishui pattern).
-- ---------------------------------------------------------------------------
M.maxLevel = 1;
function M.status(deps)
    if not _rwok then return 0, 'restockwatch failed to load'; end
    rw.loadState();
    if not rw.master then return 0, 'OFF'; end
    local job = (deps ~= nil and type(deps.playerJob) == 'function') and deps.playerJob() or nil;
    local n = #rw.effectiveList(job);
    return 1, string.format('ON -- %d tracked', n);
end
function M.level(deps) return (select(1, M.status(deps))); end

if not _iok then return M; end   -- headless: the pure half above is the module

-- ---------------------------------------------------------------------------
-- Add-picker state (one active at a time; search the box by name).
-- ---------------------------------------------------------------------------
local _add = nil;          -- nil | { scope = 'character'|'job', job = <JOB>|nil }
local _addBuf = { '' };
local _addAt, _addLast = 0, nil;
local _tgtBuf = {};   -- per-row target input strings (type-only, no +/- steppers)
local function closeAdd() _add = nil; _addBuf[1] = ''; _addLast = nil; _addAt = 0; end

-- A SmallButton that visibly refuses (ammoui's offable pattern): dim red (out of
-- range) or grey (nothing / busy), the click swallowed.
local function offableButton(label, canClick, offCol)
    if canClick then return imgui.SmallButton(label); end
    imgui.PushStyleColor(ImGuiCol_Button, offCol);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, offCol);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, offCol);
    imgui.SmallButton(label);
    imgui.PopStyleColor(3);
    return false;
end

-- ---------------------------------------------------------------------------
-- The detail view (automationsui: auto.view == 'restock').
-- ---------------------------------------------------------------------------
function M.render(deps, availW)
    if not _rwok then imgui.TextColored(COL_ERR, 'restockwatch failed to load.'); return; end
    if not _ecok then imgui.TextColored(COL_ERR, 'eboxclient failed to load.'); return; end
    rw.loadState();
    local job = (deps ~= nil and type(deps.playerJob) == 'function') and deps.playerJob() or nil;

    imgui.TextColored(COL_HEADER, 'E-Box Restock');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_TEXT, 'keep chosen items topped up from the Ephemeral Box.');

    if not cwOK() then
        imgui.Separator();
        imgui.TextColored(COL_DIM, 'Crystal Warriors only.');
        return;
    end

    -- Master ON/OFF pill (the craftbar switch, like ammoui).
    local master = (rw.master == true);
    imgui.TextColored(COL_TEXT, 'E-Box Restock:');
    imgui.SameLine(0, 6);
    local cbok, craftbar = pcall(require, 'dlac\\ui\\craftbar');
    local pill = (cbok and type(craftbar) == 'table' and type(craftbar.onOffSwitch) == 'function')
        and craftbar.onOffSwitch or nil;
    local TIP_ON  = 'Restock is ON. Turn off to go fully dark -- no floating nudge and no box queries at all.';
    local TIP_OFF = 'Track items and fetch the shortfall from the Ephemeral Box (near a box), clamped to what the box holds and to your free Inventory space.';
    if pill ~= nil then
        if pill(master, 'restockonoff', TIP_ON, TIP_OFF) then rw.setMaster(not master); end
    else
        if imgui.Button((master and 'ON' or 'OFF') .. '##restockonoff', { 46, 22 }) then rw.setMaster(not master); end
    end

    -- The two nudge settings.
    imgui.SameLine(0, 16);
    local sn = { rw.showNudge == true };
    if imgui.Checkbox('Show floating nudge##rsnudge', sn) then rw.setShowNudge(sn[1]); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Show a small floating icon near an Ephemeral Box when there is something\nworth fetching (hover it for the plan; left-click fetches, right-click opens this).');
    end
    imgui.SameLine(0, 12);
    local ow = { rw.onlyWhenNeeded == true };
    if imgui.Checkbox('Only when needed##rsneed', ow) then rw.setOnlyWhenNeeded(ow[1]); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('On: the nudge appears only when a tracked item is below target and the box\nhas some. Off: it shows near any box (greyed when there is nothing to fetch).');
    end

    imgui.Separator();

    -- The effective set + a live snapshot (one bag pass).
    local entries = rw.effectiveList(job);
    local effT, shadowed, charTgt = {}, {}, {};   -- effective target; job-shadows-char; char baselines
    for _, e in ipairs(entries) do
        effT[e.id] = e.target;
        if e.scope == 'job' and e.shadow ~= nil then shadowed[e.id] = true; end
    end
    for _, e in ipairs(rw.character) do charTgt[e.id] = e.target; end
    local onHand = fieldCounts();
    local ctx = {
        freeSlots = freeInvSlots(),
        onHand  = function(id) return onHand[id] or 0; end,
        inBox   = function(id) return ec.boxCount(id); end,
        stackOf = stackOf,
    };

    -- Proximity + counts refresh (only when master; the near-box gate keeps the
    -- server-load NFR structural -- away from a box we send nothing).
    local dist, nearOK = nil, false;
    if master then
        dist = ec.boxDistance();
        nearOK = (dist ~= nil and dist <= ec.BOX_RANGE);
        if nearOK then ec.ensureCategories(rw.categoriesOf(entries), 25); end
        if ec.lockedReason == 'locked' then
            imgui.TextColored(COL_DIM, 'E-Box: '
                .. ((ec.lockedMsg ~= nil and ec.lockedMsg ~= '') and esc(ec.lockedMsg) or 'not unlocked yet'));
        elseif dist == nil then
            imgui.TextColored(COL_DIM, 'No Ephemeral Box in sight -- stand near one to fetch or add.');
        elseif not nearOK then
            imgui.TextColored(COL_ERR, string.format('Too far from the Ephemeral Box (%.1f yalms -- get within %d).', dist, ec.BOX_RANGE));
        else
            imgui.TextColored(COL_GREEN, string.format('Ephemeral Box in range (%.1f yalms).', dist));
        end
        imgui.SameLine(0, 10);
        if imgui.SmallButton('rescan##rsscan') then ec.rescan(); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Force a fresh box scan + count refresh now.'); end
    else
        imgui.TextColored(COL_DIM, 'OFF -- turn on to track and fetch. Lists below stay editable.');
    end

    -- Fetch a single item up to its effective target (planner-clamped).
    local function fetchOne(id)
        local pl = rw.plan({ { id = id, name = '', target = effT[id] or 0, stack = stackOf(id) } }, ctx);
        if #pl.pulls > 0 then ec.withdrawBatch(pl.pulls); end
    end

    local removeReq = nil;   -- { scope, job, id }
    local DEC = (ImGuiInputTextFlags_CharsDecimal or 0);
    local function row(e, scope)
        -- Buffer key includes the job so the same item tracked on two jobs keeps
        -- two independent target inputs.
        local key = (scope == 'job') and ('j' .. tostring(job) .. '_' .. tostring(e.id))
                                     or  ('c_' .. tostring(e.id));
        imgui.PushID('rsrow_' .. key);
        imgui.Dummy({ 0, 0 }); imgui.SameLine(NAME_X);
        local rec = (deps ~= nil and type(deps.lookupById) == 'function') and deps.lookupById(e.id) or nil;
        if deps ~= nil and type(deps.renderIcon) == 'function' then deps.renderIcon(e.id, 18); end
        local have = onHand[e.id] or 0;
        local tgt = effT[e.id] or e.target;
        imgui.TextColored((have >= tgt) and COL_TEXT or COL_GOLD, esc(clip(e.name, NAME_MAX)));
        if imgui.IsItemHovered() then
            if rec ~= nil and deps ~= nil and type(deps.itemTooltip) == 'function' then pcall(deps.itemTooltip, rec);
            else imgui.SetTooltip(esc(e.name)); end
        end
        if scope == 'character' and shadowed[e.id] then
            imgui.SameLine(0, 6); imgui.TextColored(COL_DIM, string.format('(job uses %d)', tgt));
        elseif scope == 'job' and charTgt[e.id] ~= nil then
            imgui.SameLine(0, 6); imgui.TextColored(COL_DIM, string.format('(overrides %d)', charTgt[e.id]));
        end
        imgui.SameLine(HAVE_X);
        imgui.TextColored((have >= tgt) and COL_DIM or COL_ERR, 'have x' .. tostring(have));
        imgui.SameLine(BOX_X);
        local fetched = (select(1, ec.categoryCounts(e.ahCat)) ~= nil);
        local box = ec.boxCount(e.id);
        imgui.TextColored(COL_DIM, master and (fetched and ('box x' .. tostring(box)) or 'box ...') or 'box --');
        imgui.SameLine(TGT_X);
        imgui.TextColored(COL_DIM, 'Target');
        imgui.SameLine(0, 6);
        local tb = _tgtBuf[key];
        if tb == nil then tb = { tostring(e.target) }; _tgtBuf[key] = tb; end
        imgui.PushItemWidth(TGT_W);
        if imgui.InputText('##rst' .. key, tb, 8, DEC) then
            local n = tonumber(tb[1]);
            if n ~= nil then rw.setTarget(scope, (scope == 'job') and job or nil, e.id, n); end
        end
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then imgui.SetTooltip('The quantity to keep on hand -- Restock fetches the shortfall up to this.'); end
        local short = math.max(0, tgt - have);
        local busy = ec.isBusy();
        local canF = master and nearOK and (not busy) and short > 0 and box > 0 and ctx.freeSlots > 0;
        local offCol = (not nearOK) and BTN_RED_OFF or BTN_GREY_OFF;
        imgui.SameLine(0, GAP);
        if offableButton((busy and '...' or 'Fetch') .. '##rsf' .. key, canF, offCol) then
            fetchOne(e.id);
        end
        if imgui.IsItemHovered() then
            if canF then imgui.SetTooltip(string.format('Top up to %d (box-clamped, only as many as fit Inventory).', tgt));
            elseif not nearOK then imgui.SetTooltip('Stand near an Ephemeral Box to fetch.');
            elseif short <= 0 then imgui.SetTooltip('Already at target.');
            elseif box <= 0 then imgui.SetTooltip('The box holds none of these.');
            elseif ctx.freeSlots <= 0 then imgui.SetTooltip('Inventory full -- free a slot.');
            elseif busy then imgui.SetTooltip('A fetch is already in flight.'); end
        end
        imgui.SameLine(0, GAP);
        if imgui.SmallButton('x##rsdel' .. key) then
            removeReq = { scope = scope, job = (scope == 'job') and job or nil, id = e.id };
        end
        if imgui.IsItemHovered() then imgui.SetTooltip('Stop tracking this item (the item itself is untouched).'); end
        imgui.PopID();
    end

    local function section(title, list, scope)
        imgui.TextColored(COL_HEADER, title);
        if #list == 0 then imgui.SameLine(0, 8); imgui.TextColored(COL_DIM, '(none yet)'); end
        for _, e in ipairs(list) do row(e, scope); end
        if scope == 'job' and (job == nil or job == '') then
            imgui.TextColored(COL_DIM, '(log in to add job items)');
        else
            local addLabel = (scope == 'character') and '+ Add##rsaddc'
                or ('+ Add to ' .. tostring(job or '?') .. '##rsaddj');
            if imgui.SmallButton(addLabel) then
                _add = { scope = scope, job = (scope == 'job') and job or nil };
                _addBuf[1] = ''; _addLast = nil; _addAt = 0;
            end
        end
    end

    section('Always (every job)', rw.character, 'character');
    imgui.Spacing();
    section((tostring(job or '?')) .. ' only', (job ~= nil) and (rw.jobs[job] or {}) or {}, 'job');

    if removeReq ~= nil then rw.removeItem(removeReq.scope, removeReq.job, removeReq.id); end

    -- The add-picker: search the box, click a result to track it.
    if _add ~= nil then
        imgui.Separator();
        imgui.TextColored(COL_GOLD, (_add.scope == 'character')
            and 'Add to Always (every job):' or ('Add to ' .. tostring(_add.job or '?') .. ':'));
        imgui.SameLine(0, 8);
        if imgui.SmallButton('close##rsaddclose') then closeAdd(); end
        if not nearOK then
            imgui.TextColored(COL_DIM, 'Stand near an Ephemeral Box to search its contents.');
        else
            imgui.PushItemWidth(260);
            imgui.InputText('##rssearch', _addBuf, 64);
            imgui.PopItemWidth();
            if imgui.IsItemHovered() then imgui.SetTooltip('Type part of an item name to search the box.'); end
            local buf = _addBuf[1] or '';
            if buf ~= _addLast then
                if _addAt == 0 then _addAt = os.clock(); end
                if (os.clock() - _addAt) >= 0.3 then
                    _addLast = buf; _addAt = 0;
                    if #buf > 0 then ec.search(buf); end
                end
            else
                _addAt = 0;
            end
            local res = ec.searchResults;
            if type(res) == 'table' and #res > 0 then
                for _, r in ipairs(res) do
                    imgui.PushID('rsres_' .. tostring(r.id));
                    imgui.Dummy({ 0, 0 }); imgui.SameLine(NAME_X);
                    if deps ~= nil and type(deps.renderIcon) == 'function' then deps.renderIcon(r.id, 18); end
                    imgui.TextColored(COL_TEXT, esc(clip(r.name or ('#' .. tostring(r.id)), NAME_MAX)));
                    if imgui.IsItemHovered() and r.name ~= nil then imgui.SetTooltip(esc(r.name)); end
                    imgui.SameLine(BOX_X);
                    imgui.TextColored(COL_DIM, 'box x' .. tostring(r.qty or 0));
                    imgui.SameLine(0, GAP);
                    if imgui.SmallButton('+ track##rsadd' .. tostring(r.id)) then
                        rw.addItem(_add.scope, _add.job, {
                            id = r.id, name = r.name, ahCat = r.ahCat, stack = stackOf(r.id),
                        });
                        closeAdd();
                    end
                    imgui.PopID();
                end
            elseif #buf > 0 then
                imgui.TextColored(COL_DIM, 'no matches in the box (type more, or it holds none).');
            end
        end
    end

    -- Fetch all + footer.
    imgui.Separator();
    do
        local plan = rw.plan(entries, ctx);
        local busy = ec.isBusy();
        local canAll = master and nearOK and (not busy) and #plan.pulls > 0;
        local offCol = (not nearOK) and BTN_RED_OFF or BTN_GREY_OFF;
        if canAll then
            if imgui.Button('Fetch all##rsall', { 0, 24 }) then ec.withdrawBatch(plan.pulls); end
        else
            imgui.PushStyleColor(ImGuiCol_Button, offCol);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, offCol);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, offCol);
            imgui.Button((busy and 'Fetching...' or 'Fetch all') .. '##rsall', { 0, 24 });
            imgui.PopStyleColor(3);
        end
        imgui.SameLine(0, 10);
        if master and nearOK then
            local nFetch, nSlots = #plan.fetches, 0;
            for _, f in ipairs(plan.fetches) do nSlots = nSlots + f.slots; end
            local line = string.format('%d free Inventory slots -- this fetches %d item%s (%d slot%s)',
                ctx.freeSlots, nFetch, nFetch == 1 and '' or 's', nSlots, nSlots == 1 and '' or 's');
            if #plan.remainder > 0 then line = line .. string.format('; %d deferred (free slots, then re-click)', #plan.remainder); end
            imgui.TextColored(COL_DIM, line);
        end
        if ec.status ~= nil and (os.clock() - (ec.statusAt or 0)) < 8 then
            imgui.Dummy({ 0, 0 }); imgui.SameLine(NAME_X);
            imgui.TextColored(ec.statusErr and COL_ERR or COL_GREEN, 'E-Box: ' .. esc(ec.status));
        end
    end
    imgui.TextColored(COL_DIM, 'Never withdraws more than your Inventory can hold -- nothing is lost.');
end

return M;
