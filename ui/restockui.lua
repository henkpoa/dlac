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

    Layout: ONE header line (the label hovers its own explanation -- no prose on
    the panel), master ON/OFF + the two nudge settings; a proximity line +
    Rescan; Fetch all RIGHT THERE under the switch, so the add-picker can never
    push it down; then the two sections sharing fixed columns -- "Always (every
    job)" (the character list) and "<JOB> only" (the job list, whose target
    overrides the character baseline for the same item). Every fetch is
    pre-clamped by the planner to min(shortfall, in-box, room), so a click can
    never over-draw -- and the wiki is explicit that over-drawn items fall to the
    floor and are gone for good.

    The add-picker searches on a BUTTON, never on typing (v2 grill B1): one
    click = one packet, results are correlated to the string they answer for,
    rows already on the list are hidden, and adding keeps the picker open
    because you usually add several things from one search.

    The floating nudge (M.nudge, hooked from gearui's d3d_present) is a stack of
    up to three icons near a box:
      * GREEN  -- fetch the shortfall, counting every field bag as on-hand;
      * YELLOW -- only when Inventory alone is short while another field bag
                  holds some: tops INVENTORY up from the box, reporting where
                  the other copies are. (Moving them out of the Mog Case would
                  be better and costs no box stock, but dlac may not move items
                  between containers yet -- deferred, see the v2 grill C2.)
      * RED    -- `!box store`, always present near a box, arm-then-confirm
                  because it instantly deposits every storable item you carry.
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local _rwok, rw = pcall(require, 'dlac\\feature\\restockwatch');
_rwok = _rwok and type(rw) == 'table';
local _ecok, ec = pcall(require, 'dlac\\feature\\eboxclient');
_ecok = _ecok and type(ec) == 'table';
local _gmok, gm = pcall(require, 'dlac\\feature\\gamemode');
_gmok = _gmok and type(gm) == 'table';
local _ftok, filetex = pcall(require, 'dlac\\ui\\filetex');   -- the crate icons (assets/ebox*.png)
_ftok = _ftok and type(filetex) == 'table';
local _usok, uistyle = pcall(require, 'dlac\\ui\\uistyle');   -- helpLabel: underline + hover
_usok = _usok and type(uistyle) == 'table' and type(uistyle.helpLabel) == 'function';

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

-- The MOG HOUSE bags: Safe, Storage, Locker, Safe 2. Reachable only at a moogle,
-- so stock parked here cannot answer a shortfall in the field -- which is the
-- yellow icon's whole question (Henrik, 2026-07-28). Wardrobes are deliberately
-- absent (gear only, and equippable where you stand), and so is Temporary (3):
-- event items are not stock.
local HOME_BAGS  = { 1, 2, 4, 9 };
local BAG_NAMES  = { [0] = 'Inventory',  [1] = 'Mog Safe',  [2] = 'Storage',
                     [4] = 'Mog Locker', [5] = 'Mog Satchel', [6] = 'Mog Sack',
                     [7] = 'Mog Case',   [9] = 'Mog Safe 2' };
M._FIELD_BAGS = FIELD_BAGS;   -- test seams (RS9g): the ruling is the bag split
M._HOME_BAGS  = HOME_BAGS;

-- Quiver/pouch -> ammo, generated from the server's own item scripts
-- (tools/gen_ammocontainers.py). `!box ammo` hands back CONTAINERS: a Blind Bolt
-- withdrawal arrives as a Blind Bolt Quiver, stack 12, each one 99 bolts -- so a
-- single Inventory slot holds 1188 and NONE of it is visible as "Blind Bolt".
-- Without this, on-hand read 0 and Restock kept offering to fetch more.
local _acok, AMMO_BOX = pcall(require, 'dlac\\data\\ammocontainers');
_acok = _acok and type(AMMO_BOX) == 'table';

-- On-hand across the FIELD bags, ONE pass. Returns:
--   all   { id -> count }            LOOSE items only
--   per   { id -> { [bag] = count } } the same, per bag (the yellow icon's report)
--   boxed { ammoId -> { qty, n, name } } what your quivers/pouches are worth
--
-- Containers are kept SEPARATE on purpose. They count toward "do I have enough"
-- (so we stop fetching bolts you already own 1188 of), but they are NOT loose
-- ammo: you cannot shoot a quiver, and the fix for an empty Inventory is to open
-- one, not to withdraw from the box. Folding them into `per` would make the
-- yellow icon offer a box withdrawal for ammo already in your bags.
local function scanBags(bags, boxed)
    local all, per = {}, {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for _, bag in ipairs(bags) do
            local max = inv:GetContainerCountMax(bag) or 0;
            for i = 1, max do
                local it = inv:GetContainerItem(bag, i);
                if it ~= nil and (it.Id or 0) > 0 and (it.Count or 0) > 0 then
                    all[it.Id] = (all[it.Id] or 0) + it.Count;
                    local p = per[it.Id];
                    if p == nil then p = {}; per[it.Id] = p; end
                    p[bag] = (p[bag] or 0) + it.Count;
                    local c = (boxed ~= nil) and _acok and AMMO_BOX[it.Id] or nil;
                    if c ~= nil then
                        local b = boxed[c.id];
                        if b == nil then b = { qty = 0, n = 0, name = c.name }; boxed[c.id] = b; end
                        b.qty = b.qty + it.Count * c.qty;
                        b.n   = b.n + it.Count;
                    end
                end
            end
        end
    end);
    return all, per;
end

local function bagScan()
    local boxed = {};
    local all, per = scanBags(FIELD_BAGS, boxed);
    return all, per, boxed;
end

-- The same pass over the Mog House bags. Quivers are NOT unpacked here: a pouch
-- in the Mog Safe is stock you cannot reach either, and the yellow icon reports
-- WHERE things are, not what they would be worth once opened.
local function homeScan() return scanBags(HOME_BAGS, nil); end

-- What "do I have enough?" should count: loose + what your containers hold.
local function stockOf(all, boxed, id)
    local n = (all or {})[id] or 0;
    local b = (boxed or {})[id];
    return n + ((b ~= nil) and (tonumber(b.qty) or 0) or 0);
end
M._stockOf = stockOf;   -- test seam (AC*), above the imgui guard

-- "1 in Mog Safe, 4 in Mog Locker" -- where the out-of-reach copies actually are.
local function whereText(p)
    if type(p) ~= 'table' then return ''; end
    local parts = {};
    for _, bag in ipairs(HOME_BAGS) do
        local n = p[bag];
        if n ~= nil and n > 0 then
            parts[#parts + 1] = string.format('%d in %s', n, BAG_NAMES[bag] or ('bag ' .. tostring(bag)));
        end
    end
    return table.concat(parts, ', ');
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
-- The picker searches ONLY when the Search button is clicked (v2 grill B1): a
-- query costs a packet, and typing is not a request. Nothing is remembered
-- between openings -- eboxclient owns the correlation (searchFor) and we clear
-- it on open and on close, so stale hits can never answer a new question.
local _add = nil;          -- nil | { scope = 'character'|'job', job = <JOB>|nil }
local _addBuf = { '' };
local _tgtBuf = {};   -- per-row target input strings (type-only, no +/- steppers)
local function resetSearch()
    _addBuf[1] = '';
    if _ecok then pcall(ec.clearSearch); end
end
local function closeAdd() _add = nil; resetSearch(); end

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

    -- ONE header line: the label carries its own explanation in a hover
    -- (panel-text standard) instead of a second line of prose beside it.
    local TIP_WHAT =
        'Keeps chosen items topped up from the Ephemeral Box.\n\n'
     .. 'Near a box it counts what you already have across Inventory, Mog Satchel,\n'
     .. 'Sack and Case, then fetches only the shortfall -- never more than the box\n'
     .. 'holds, and never more than your Inventory has room for.\n'
     .. 'Box counts are read once and then tracked by arithmetic, so standing here\n'
     .. 'crafting costs no server traffic.';
    if _usok then uistyle.helpLabel(imgui, 'E-Box Restock', TIP_WHAT, COL_HEADER);
    else imgui.TextColored(COL_HEADER, 'E-Box Restock'); end

    if not cwOK() then
        imgui.Separator();
        imgui.TextColored(COL_DIM, 'Crystal Warriors only.');
        return;
    end

    -- Master ON/OFF pill (the craftbar switch, like ammoui).
    local master = (rw.master == true);
    imgui.SameLine(0, 10);
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
    local onHand, _onPer, boxed = bagScan();
    local ctx = {
        freeSlots = freeInvSlots(),
        onHand  = function(id) return stockOf(onHand, boxed, id); end,
        inBox   = function(id) return ec.boxCount(id); end,
        stackOf = stackOf,
    };

    -- Proximity + counts refresh (only when master; the near-box gate keeps the
    -- server-load NFR structural -- away from a box we send nothing).
    local dist, nearOK = nil, false;
    if master then
        dist = ec.boxDistance();
        nearOK = (dist ~= nil and dist <= ec.BOX_RANGE);
        -- VERIFY, not poll: this sends only while a tracked category is unknown
        -- or something dirtied it (a refused withdraw, any `!box ...`, zoning).
        -- Once counted, standing at the box is free -- calling it every frame is
        -- a table walk. See feature/eboxclient's header for the whole model.
        if nearOK then ec.verifyCategories(rw.categoriesOf(entries)); end
        if ec.lockedReason == 'locked' then
            imgui.TextColored(COL_DIM, 'E-Box: '
                .. ((ec.lockedMsg ~= nil and ec.lockedMsg ~= '') and esc(ec.lockedMsg) or 'not unlocked yet'));
        elseif dist == nil then
            imgui.TextColored(COL_DIM, 'No Ephemeral Box in sight -- stand near one to fetch (searching works anywhere).');
        elseif not nearOK then
            imgui.TextColored(COL_ERR, string.format('Too far from the Ephemeral Box (%.1f yalms -- get within %d to fetch).', dist, ec.BOX_RANGE));
        else
            imgui.TextColored(COL_GREEN, string.format('Ephemeral Box in range (%.1f yalms).', dist));
        end
        imgui.SameLine(0, 10);
        if imgui.SmallButton('rescan##rsscan') then ec.rescan(); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Force a fresh box scan + count refresh now.'); end
    else
        imgui.TextColored(COL_DIM, 'OFF -- turn on to track and fetch. Lists below stay editable.');
    end

    -- Fetch all, HERE -- directly under the switch, so opening the add-picker
    -- below can never push the button that actually does the work off-screen
    -- (Henrik, v2 grill B5). Its explanation is in the hover, not on the panel.
    local plan = rw.plan(entries, ctx);
    do
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
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Fetch every tracked item\'s shortfall in one go.\n'
                .. 'Never withdraws more than your Inventory can hold, so nothing is\n'
                .. 'ever dropped and lost; anything that does not fit is reported and\n'
                .. 'waits for you to free a slot.');
        end
        if master and nearOK then
            imgui.SameLine(0, 10);
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
        local have = stockOf(onHand, boxed, e.id);
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
        local bx = boxed[e.id];
        imgui.TextColored((have >= tgt) and COL_DIM or COL_ERR,
            'have x' .. tostring(have) .. ((bx ~= nil) and '*' or ''));
        if bx ~= nil and imgui.IsItemHovered() then
            -- The star, explained: most of that count is not loose ammo, and you
            -- cannot shoot it until you open one.
            imgui.SetTooltip(string.format(
                '%d loose, plus %d %s worth %d more.\nRestock counts them so it stops fetching'
                .. ' what you already own --\nbut you must open one before you can use it.',
                onHand[e.id] or 0, bx.n, esc(bx.name), bx.qty));
        end
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
                resetSearch();   -- a fresh question: never reopen onto old hits
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
        -- closeAdd() nils _add, and everything below dereferences it. This block
        -- is the last thing render draws, so bail out rather than nest the rest.
        -- (Anything appended to render() after this point must move ABOVE it.)
        if _add == nil then return; end
        -- NO proximity gate on the picker (Henrik, 2026-07-28): trove searches the
        -- box from anywhere in the field -- `trove/plugins/ebox.lua` has no
        -- distance or zone check on ANY 0x1A4 action -- so the server plainly
        -- answers a SEARCH wherever you stand, and refusing to ask was our
        -- invention, not the protocol's. The NFR is untouched: this is one packet
        -- per explicit click, still behind one-in-flight and MIN_GAP. Building the
        -- list is the half of the feature you do while you have a spare minute;
        -- FETCHING is what still needs you standing at a box.
        imgui.PushItemWidth(260);
        imgui.InputText('##rssearch', _addBuf, 64);
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Part of an item name. Nothing is sent until you click Search.');
        end
        local buf = _addBuf[1] or '';
        local searching = ec.searchBusy();

        -- THE button. One click = one query; no typing ever reaches the wire,
        -- and a refused click is visibly refused instead of silently dropped
        -- (the old debounce marked the text as "asked" before the throttle
        -- had accepted it, so the search never went out at all).
        imgui.SameLine(0, GAP);
        local canSearch = (#buf > 0) and (not searching) and ec.canQuery();
        if offableButton((searching and 'searching...' or 'Search') .. '##rsdosearch',
                         canSearch, BTN_GREY_OFF) then
            ec.search(buf);
        end
        if imgui.IsItemHovered() then
            if searching then imgui.SetTooltip('Waiting for the box to answer.');
            elseif #buf == 0 then imgui.SetTooltip('Type part of an item name first.');
            elseif not canSearch then imgui.SetTooltip('One box query at a time -- try again in a moment.');
            else imgui.SetTooltip('Ask the box what it holds matching this name.\n'
                .. 'Works anywhere -- you only need to stand at a box to FETCH.'); end
        end

        -- Already-tracked ids in the list we are adding TO: those rows are
        -- hidden, so searching "bolt" twice shows only what is left to add.
        local intoList = (_add.scope == 'character') and rw.character
            or ((_add.job ~= nil) and (rw.jobs[_add.job] or {}) or {});
        local tracked = {};
        for _, e in ipairs(intoList) do tracked[e.id] = true; end

        -- Results answer ONE string. If the box came back for "bolt" and the
        -- text now reads "bolts", we show nothing rather than last question's
        -- hits (which is what made the old picker feel like it was lying).
        local answered = (ec.searchFor ~= nil and ec.searchFor == buf);
        local res = answered and ec.searchResults or nil;
        if searching then
            imgui.TextColored(COL_DIM, 'searching the box...');
        elseif type(res) == 'table' then
            local shown = 0;
            for _, r in ipairs(res) do
                if not tracked[r.id] then
                    shown = shown + 1;
                    imgui.PushID('rsres_' .. tostring(r.id));
                    imgui.Dummy({ 0, 0 }); imgui.SameLine(NAME_X);
                    if deps ~= nil and type(deps.renderIcon) == 'function' then deps.renderIcon(r.id, 18); end
                    imgui.TextColored(COL_TEXT, esc(clip(r.name or ('#' .. tostring(r.id)), NAME_MAX)));
                    if imgui.IsItemHovered() and r.name ~= nil then imgui.SetTooltip(esc(r.name)); end
                    imgui.SameLine(BOX_X);
                    imgui.TextColored(COL_DIM, 'box x' .. tostring(r.qty or 0));
                    imgui.SameLine(0, GAP);
                    -- Adding does NOT close the picker: you usually add several
                    -- (every bolt) from one search. The row simply disappears.
                    if imgui.SmallButton('+ track##rsadd' .. tostring(r.id)) then
                        rw.addItem(_add.scope, _add.job, {
                            id = r.id, name = r.name, ahCat = r.ahCat, stack = stackOf(r.id),
                        });
                    end
                    imgui.PopID();
                end
            end
            if shown == 0 then
                imgui.TextColored(COL_DIM, (#res > 0)
                    and 'every match is already on this list.'
                    or  'no matches in the box (try a shorter name).');
            end
        elseif #buf > 0 then
            imgui.TextColored(COL_DIM, 'press Search to look in the box.');
        end
    end

end

-- ---------------------------------------------------------------------------
-- The floating Restock nudge (gearui d3d_present hook, beside floatgear). A
-- small crate icon (assets/ebox.png -- Henrik's art) that pops up near an
-- Ephemeral Box while you play: hover = the fetch plan, LEFT-click = Fetch all
-- (pre-clamped, cannot over-draw), RIGHT-click = open the panel, badge = # items
-- below target the box can fill. Self-gates so it costs nothing away from a box.
-- INDEPENDENT of the main window (rendered directly from d3d_present, the
-- floatgear pattern) -- deps is gearui's table, for the current job.
-- ---------------------------------------------------------------------------
local _nudgeOpen = { true };
local _redArmAt = 0;     -- arm-then-confirm clock for the deposit icon
local RED_ARM   = 3;     -- seconds an armed deposit stays armed
local NUDGE_SZ  = 40;
local TIP_MAX   = 12;    -- rows before a tooltip starts saying "+N more"

local function openPanel()
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl restock'); end);
end

-- One icon button. A missing PNG falls back to a labelled button -- an asset
-- that failed to load must never leave the surface unclickable.
local function iconButton(tex, fallback, id)
    local clicked = false;
    imgui.PushID(id);
    local h = _ftok and filetex.handle(tex) or nil;
    if h ~= nil then
        pcall(function() clicked = imgui.ImageButton(h, { NUDGE_SZ, NUDGE_SZ }); end);
    else
        clicked = imgui.Button(fallback, { NUDGE_SZ + 8, NUDGE_SZ });
    end
    local right   = imgui.IsItemClicked(1);
    local hovered = imgui.IsItemHovered();
    imgui.PopID();
    return clicked, right, hovered;
end

function M.nudge(deps)
    -- Every early return DISARMS the deposit icon. The arm is a 3s timer that is
    -- otherwise only cleared by a not-hovered frame inside the drawing block --
    -- so arming it, then stepping out of range (or toggling the nudge off) and
    -- back within 3s, would leave a single click firing `!box store`. That guard
    -- is the only thing between a stray click and depositing everything you carry.
    if not _rwok or not _ecok then _redArmAt = 0; return; end
    rw.loadState();
    if not (rw.master and rw.showNudge) then _redArmAt = 0; return; end
    if not cwOK() then _redArmAt = 0; return; end
    local dist = ec.boxDistance();
    if dist == nil or dist > ec.BOX_RANGE then _redArmAt = 0; return; end   -- only near a box
    local job = (deps ~= nil and type(deps.playerJob) == 'function') and deps.playerJob() or nil;
    local entries = rw.effectiveList(job);
    ec.verifyCategories(rw.categoriesOf(entries));

    local all, _per, boxed = bagScan();
    local home, homePer    = homeScan();
    local free = freeInvSlots();
    local function heldOf(id)  return stockOf(all, boxed, id); end
    local function homeOf(id)  return home[id] or 0; end
    local function inBox(id)   return ec.boxCount(id); end

    -- GREEN: on-hand = every field bag (a Mog Case copy counts, which is right)
    -- PLUS what your quivers/pouches hold, so it stops offering to fetch bolts
    -- you are already carrying 1188 of.
    local plan = rw.plan(entries, { freeSlots = free,
        onHand = heldOf, inBox = inBox, stackOf = stackOf });

    -- YELLOW (revised 07-28): the shortfalls whose missing copies are sitting at
    -- your MOG HOUSE -- Safe, Storage, Locker -- where nothing you do out here
    -- can reach them. The other field bags are with you and count as held, so
    -- they no longer raise this icon. Its click fetches JUST these items, on
    -- green's own arithmetic (no deliberate over-draw any more: there is nothing
    -- reachable left to double up on).
    local need, yplan = rw.homeStockNeed(entries, { held = heldOf, stored = homeOf }), nil;
    if #need > 0 then
        local want, sub = {}, {};
        for _, n in ipairs(need) do want[n.id] = true; end
        for _, e in ipairs(entries) do if want[e.id] then sub[#sub + 1] = e; end end
        yplan = rw.plan(sub, { freeSlots = free, onHand = heldOf, inBox = inBox, stackOf = stackOf });
    end

    -- "Only when needed" governs the GREEN crate. The deposit icon ignores it:
    -- Henrik's rule is that it is always there near a box, and there is nothing
    -- to detect -- we never track whether you have anything worth storing.
    local showGreen = not (rw.onlyWhenNeeded and plan.badge == 0);

    local FL = (ImGuiWindowFlags_NoTitleBar or 0) + (ImGuiWindowFlags_NoResize or 0)
             + (ImGuiWindowFlags_NoScrollbar or 0) + (ImGuiWindowFlags_NoCollapse or 0)
             + (ImGuiWindowFlags_AlwaysAutoResize or 0) + (ImGuiWindowFlags_NoFocusOnAppearing or 0)
             + (ImGuiWindowFlags_NoNav or 0);
    imgui.SetNextWindowPos({ 300, 300 }, (ImGuiCond_FirstUseEver or 0));
    _nudgeOpen[1] = true;   -- forced-true table (floatgear's shape); no title bar = no close
    if imgui.Begin('##dlac_restock_nudge', _nudgeOpen, FL) then
        local busy = ec.isBusy();

        if showGreen then
            local canFetch = (#plan.pulls > 0) and not busy;
            local clicked, rightClicked, hovered = iconButton('ebox', 'E-Box', 'rsnudge_green');
            if plan.badge > 0 then
                imgui.SameLine(0, 6);
                imgui.TextColored(canFetch and COL_GOLD or COL_DIM, 'x' .. tostring(plan.badge));
            end
            if clicked and canFetch then ec.withdrawBatch(plan.pulls); end
            if rightClicked then openPanel(); end
            if hovered then
                imgui.BeginTooltip();
                imgui.TextColored(COL_HEADER, 'E-Box Restock');
                if #plan.fetches == 0 then
                    imgui.TextColored(COL_DIM, (plan.badge > 0) and 'Inventory full -- free a slot.' or 'Nothing to fetch right now.');
                else
                    imgui.TextColored(COL_TEXT, 'Left-click fetches:');
                    local shown = 0;
                    for _, f in ipairs(plan.fetches) do
                        if shown < TIP_MAX then
                            imgui.TextColored(COL_TEXT, string.format('   %s  x%d', esc(f.name or ('#' .. tostring(f.id))), f.qty));
                            shown = shown + 1;
                        end
                    end
                    if #plan.fetches > shown then
                        imgui.TextColored(COL_DIM, string.format('   +%d more', #plan.fetches - shown));
                    end
                end
                if #plan.remainder > 0 then
                    imgui.TextColored(COL_DIM, string.format('%d deferred -- free slots, then click again.', #plan.remainder));
                end
                imgui.Separator();
                imgui.TextColored(COL_DIM, 'Left-click: fetch all    Right-click: open panel');
                imgui.EndTooltip();
            end
        end

        if yplan ~= nil then
            local canY = (#yplan.pulls > 0) and not busy;
            local clicked, rightClicked, hovered = iconButton('ebox_yellow', 'At home', 'rsnudge_yellow');
            imgui.SameLine(0, 6);
            imgui.TextColored(canY and COL_GOLD or COL_DIM, 'x' .. tostring(#need));
            if clicked and canY then ec.withdrawBatch(yplan.pulls); end
            if rightClicked then openPanel(); end
            if hovered then
                imgui.BeginTooltip();
                imgui.TextColored(COL_HEADER, 'You own these -- but they are at your Mog House');
                -- What the click will ACTUALLY pull, per item: homeStockNeed's
                -- `want` is the raw shortfall and knows nothing about box stock
                -- or free slots, so quoting it would contradict the planner's own
                -- list a few lines below in the same tooltip.
                local yq = {};
                for _, f in ipairs(yplan.fetches) do yq[f.id] = (yq[f.id] or 0) + f.qty; end
                for i, n in ipairs(need) do
                    if i <= TIP_MAX then
                        local got = yq[n.id] or 0;
                        imgui.TextColored(COL_TEXT, string.format('   %s  --  x%d on you of %d, %s  ->  %s',
                            esc(n.name or ('#' .. tostring(n.id))), n.held, n.target,
                            whereText(homePer[n.id]),
                            (got < n.want) and string.format('pull %d of %d', got, n.want)
                                            or string.format('pull %d', got)));
                    end
                end
                if #need > TIP_MAX then
                    imgui.TextColored(COL_DIM, string.format('   +%d more', #need - TIP_MAX));
                end
                imgui.Separator();
                if #yplan.fetches > 0 then
                    imgui.TextColored(COL_TEXT, 'Left-click fetches just these from the box:');
                    local shown = 0;
                    for _, f in ipairs(yplan.fetches) do
                        if shown < TIP_MAX then
                            imgui.TextColored(COL_TEXT, string.format('   %s  x%d', esc(f.name or ('#' .. tostring(f.id))), f.qty));
                            shown = shown + 1;
                        end
                    end
                    imgui.TextColored(COL_DIM, 'Your Mog House copies stay there -- you cannot reach them');
                    imgui.TextColored(COL_DIM, 'from here, so the box covers you until you go home.');
                else
                    imgui.TextColored(COL_DIM, busy and 'A fetch is already in flight.'
                        or 'The box cannot add any of these -- yours are at the Mog House.');
                end
                imgui.Separator();
                imgui.TextColored(COL_DIM, 'Left-click: fetch to Inventory    Right-click: open panel');
                imgui.EndTooltip();
            end
        end

        do
            -- DEPOSIT (always near a box). `!box store` is instant and stores
            -- EVERY storable item in Inventory -- including what Restock just
            -- fetched -- so it arms on the first click and fires on the second.
            local armed = (_redArmAt > 0) and ((os.clock() - _redArmAt) < RED_ARM);
            local clicked, _rc, hovered = iconButton('ebox_red_icon-64', 'Store', 'rsnudge_red');
            if clicked then
                if armed then ec.boxStore(); _redArmAt = 0; armed = false;
                else _redArmAt = os.clock(); armed = true; end
            elseif not hovered then
                _redArmAt = 0; armed = false;    -- moving away disarms it
            end
            if armed then
                imgui.SameLine(0, 6);
                imgui.TextColored(COL_ERR, 'sure?');
            end
            if hovered then
                imgui.BeginTooltip();
                imgui.TextColored(COL_HEADER, 'Store All   (!box store)');
                imgui.TextColored(COL_TEXT, 'Instantly deposits EVERY storable item in your Inventory:');
                imgui.TextColored(COL_TEXT, 'crafting materials, food, ninjutsu tools, ammo, oils.');
                imgui.TextColored(COL_DIM,  'That includes anything Restock just fetched.');
                imgui.Separator();
                imgui.TextColored(armed and COL_ERR or COL_DIM,
                    armed and 'Armed -- click again to store.' or 'Click once to arm, again to store.');
                imgui.EndTooltip();
            end
        end
    end
    imgui.End();
end

-- /dl restock -- open the panel (also the nudge's right-click target). Own
-- command handler (the useitem pattern): fires for every command, acts only on
-- 'restock'. gearui is lazy-required at call time (no load-order cycle).
pcall(function()
    ashita.events.register('command', 'dlac_restock_cmd', function(e)
        local raw = string.lower(e.command or '');
        local a = raw:match('^/dl%s+(%S+)') or raw:match('^/dlac%s+(%S+)');
        if a ~= 'restock' then return; end
        e.blocked = true;
        if not cwOK() then return; end   -- 100% CW-only: non-CW gets nothing (not even the gated panel)
        pcall(function()
            local g = require('dlac\\ui\\gearui');
            if type(g.openAutomation) == 'function' then g.openAutomation('restock'); end
        end);
    end);
end);

return M;
