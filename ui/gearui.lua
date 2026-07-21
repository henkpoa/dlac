--[[
    dlac/gearui.lua

    Gear browser + set builder UI  --  a Trove-style tabbed ImGui window over the
    gear.lua database, the catalog.lua CatsEyeXI reference, the gearimport
    (/dl scan|stage|commit) pipeline, and the gearoptim stat-weight optimizer.

    Header (shown on every tab): job/level + owned count + Reload LAC/Scan/Stage/Commit/Setup.
    Tabs:
      * Equipped     -- equipmon-style 16-slot grid of what you're wearing (hover a
                        tile for an FFXI-style tooltip), the summed stats of the worn
                        set, and per-slot alternatives you can equip / lock.
      * All Equipment-- the full CatsEyeXI reference (catalog.lua) as a collapsible
                        tree in gear.lua slot/category order, with search + icons.
      * Sets         -- build/view/edit a set, Auto-fill from the optimizer, live score.

    Reused trove/equipmon patterns: item icons via D3DXCreateTextureFromFileInMemoryEx
    on the resource Bitmap; equipped-item lookup via GetEquippedItem -> GetContainerItem;
    BeginTabBar tabbing; BeginTooltip on IsItemHovered; CollapsingHeader/TreeNode tree.

    Open it in-game with:  /dl ui  (or /dlac ui)  -- toggle;  /dl ui on|off.

    Loaded through a guarded require in utils.lua, so anything that goes wrong in here
    can never break profile loading. Every Ashita / imgui / d3d / optimizer call is
    wrapped defensively so a nil can never crash the render loop.
]]--

local gear = require("dlac\\gear");
local bit  = require('bit');
local host = require("dlac\\ui\\uihost");   -- UI module registry: tabs/windows/services
local sf   = require("dlac\\gear\\syncflags");-- auto-sync + persisted flags (sf.flags.debug/.autosync)
local wui  = require("dlac\\ui\\weightsui");-- stat-weights editor (Sets panel + floating window)
local pmenu = require("dlac\\ui\\profilesmenu");   -- Profiles popup (tree + clone/rename/delete forms)

-- Guarded require: the module table, or nil when the lib is missing (or not a
-- table). A missing lib degrades gracefully (no window / no icons) instead of
-- erroring. ONE local per module, no pcall-ok temps: the 200-local chunk cap.
local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- Colored [dlac] chat output (chatfmt): the shadowed `print` re-heads
-- "[dlac] ..."-prefixed lines with the colored header; plain when unavailable.
local print = (function()
    local m = try('dlac\\chatfmt');
    return (m ~= nil and type(m.print) == 'function') and m.print or print;
end)();

-- Shared libs live in Ashita\addons\libs and are require-able from a profile the
-- same way gearimport requires 'encoding'.
local imgui = try('imgui');
local optim = try("dlac\\gear\\gearoptim");
-- Full CatsEyeXI equipment reference access (gear\catalogindex): the lazy 5MB
-- load, the raw id index and the flattened browse records all live THERE now --
-- one walker for every consumer. Powers the All Equipment tab + item lookups.
local ci = require("dlac\\gear\\catalogindex");
-- Dynamic-set writer (commit/delete a set into the <JOB>.lua file). Sets tab only.
local setmgr = try("dlac\\gear\\setmanager");
-- Augment reader: decode private augments from item Extra bytes (worn-stat totals).
local aug = try("dlac\\feature\\augments");
-- Level-scaling stats (Rajas/Tamas/Sattva etc.): effective stats per level.
local lscale = try("dlac\\data\\levelstats");
-- Gear-set bonuses (conditional-effects P1/P3): membership, tier ladders, and
-- THE whole-composition evaluator (comboStats) behind totals and hover.
local gfx = try("dlac\\gear\\geareffects");
-- Owned-gear record rules (Type heal, enrichment precedence) -- one home, REC*.
local grec = try("dlac\\gear\\gearrecord");
-- Window theme (partyfinder-matched palette), pushed around the whole draw.
local style = try("dlac\\ui\\uistyle");
-- Per-job macro book/set (header "Macro" button; applied on login/job change)
-- and enchanted travel items (header "Teleports" dropdown; same module the
-- /dl w|p|t commands live in -- require returns the already-loaded instance).
local macrob = try("dlac\\feature\\macrobook");
local useit = (function()
    local m = try("dlac\\feature\\useitem");
    return (m ~= nil and type(m.menu) == 'function') and m or nil;
end)();

-- Capability flags in ONE table (each was its own local; the 200-cap again).
-- has.dsp / has.statdefs are assigned where those modules load, further down.
local has = {
    imgui    = imgui ~= nil,
    optim    = optim ~= nil,
    catalog  = ci.available(),
    setmgr   = setmgr ~= nil,
    aug      = aug ~= nil,
    lscale   = lscale ~= nil,
    gfx      = gfx ~= nil and type(gfx.comboStats) == 'function',
};
-- Effective stats of a record at a level -- delegates to THE central resolver
-- (levelstats.effective) so every section values scaling items identically.
local function effStats(rec, level)
    if rec == nil then return nil; end
    if not has.lscale or type(lscale.effective) ~= 'function' then return rec.Stats; end
    return lscale.effective(rec, level);
end

local M = {};
M.visible        = false;    -- window visibility flag, toggled by /dl ui
M.working        = {};       -- Sets tab: slotLabel -> ordered list of { rec, minLevel, maxLevel }
M.workingSetName = nil;      -- selected dynamic set name

-- ---------------------------------------------------------------------------
-- UI state (imgui widgets read/write single-element tables in place).
-- ---------------------------------------------------------------------------
local ui = {
    -- All Equipment (browse) tab
    usableNow = { false },
    showAll   = { false },    -- header toggle: browse the full catalog vs only gear you own (default: owned)
    search    = { '' },
    slot      = nil,          -- slot filter, or nil for "All slots"
    -- Equipped tab
    eqSelected  = nil,        -- selected slot label
    lockEquipped = { false }, -- "Lock when equipped" toggle
    freeEquip    = { false },  -- "Free equip": /lac disable + native /equip so manual swaps stick
    _freePrev    = nil,        -- edge-detect for the freeEquip toggle
    -- Shared (Equipped + Sets)
    showStats = false,        -- left "Diablo-style" stats panel toggle
    sortMode  = 'Level',      -- gear-list sort: 'Name' | 'Level' (Level default -- Henrik:
                              -- slot lists read naturally as a level progression)
    -- Sets tab
    setSelected = nil,
    newSetName  = { '' },
    setsDynamic = { true },   -- Auto-build "Dynamic" (level-scaling list) mode, default ON
    buildMax    = { true },   -- optimizer "build as lv.75" toggle (mirrors optim.buildAtMaxLevel; default ON)
    showWeights = false,      -- right-side weights panel toggle
    addStat     = { '' },
    addPer      = { 0 },
    addCap      = { 0 },
    _wbuf       = {},         -- per-stat input buffers for the weights editor
    setsStatus    = '',
    setsStatusErr = false,
};

-- Slot order for the browse filter dropdown.
local SLOT_ORDER = {
    'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Body', 'Hands', 'Legs',
    'Feet', 'Neck', 'Waist', 'Ear', 'Ring', 'Back',
};

-- Collapsible-tree order for the All Equipment tab (gear.lua order).
local SLOT_TREE_ORDER = {
    'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck', 'Ear', 'Body',
    'Hands', 'Ring', 'Back', 'Waist', 'Legs', 'Feet',
};
-- Nested weapon-category order under Main / Range (gear.lua order).
local CAT_ORDER = {
    Main  = { 'HandToHand', 'Dagger', 'Sword', 'GreatSword', 'Axe', 'GreatAxe',
              'Scythe', 'Polearm', 'Katana', 'GreatKatana', 'Club', 'Staff' },
    Range = { 'Archery', 'Marksmanship', 'Throwing', 'StringInstrument',
              'WindInstrument', 'Handbell', 'FishingRod', 'PUP' },
};

-- The 16 equipment slots. `equip` is the GetEquippedItem index (equipmon), `gear`
-- is the gear.lua top-level slot key, `label` is the optimizer / working-set label
-- (Ear/Ring split into Ear1/Ear2 & Ring1/Ring2 -- also the /lac slot name lowercased),
-- `short` is a compact tile tag. Order mirrors equipmon's 4x4 visual (row-major).
local EQUIP_SLOTS = {
    { equip = 0x00, gear = 'Main',  label = 'Main',  short = 'Main' },
    { equip = 0x01, gear = 'Sub',   label = 'Sub',   short = 'Sub'  },
    { equip = 0x02, gear = 'Range', label = 'Range', short = 'Rng'  },
    { equip = 0x03, gear = 'Ammo',  label = 'Ammo',  short = 'Ammo' },
    { equip = 0x04, gear = 'Head',  label = 'Head',  short = 'Head' },
    { equip = 0x09, gear = 'Neck',  label = 'Neck',  short = 'Neck' },
    { equip = 0x0B, gear = 'Ear',   label = 'Ear1',  short = 'Ear1' },
    { equip = 0x0C, gear = 'Ear',   label = 'Ear2',  short = 'Ear2' },
    { equip = 0x05, gear = 'Body',  label = 'Body',  short = 'Body' },
    { equip = 0x06, gear = 'Hands', label = 'Hands', short = 'Hand' },
    { equip = 0x0D, gear = 'Ring',  label = 'Ring1', short = 'Rng1' },
    { equip = 0x0E, gear = 'Ring',  label = 'Ring2', short = 'Rng2' },
    { equip = 0x0F, gear = 'Back',  label = 'Back',  short = 'Back' },
    { equip = 0x0A, gear = 'Waist', label = 'Waist', short = 'Wst'  },
    { equip = 0x07, gear = 'Legs',  label = 'Legs',  short = 'Legs' },
    { equip = 0x08, gear = 'Feet',  label = 'Feet',  short = 'Feet' },
};

local GEAR_OF = {};   -- label -> gear.lua slot key
for _, s in ipairs(EQUIP_SLOTS) do GEAR_OF[s.label] = s.gear; end

-- Colors.
local COL = {   -- ONE table, not ten locals: the 200-local chunk cap
    HEADER = { 0.60, 0.75, 1.00, 1.00 },
    USABLE = { 1.00, 1.00, 1.00, 1.00 },
    LOCKED = { 0.55, 0.55, 0.60, 1.00 },
    LEVEL  = { 0.70, 0.70, 0.78, 1.00 },
    JOBS   = { 0.55, 0.78, 0.55, 1.00 },
    STATS  = { 0.62, 0.62, 0.70, 1.00 },
    DIM    = { 0.70, 0.70, 0.70, 1.00 },
    SCORE  = { 0.95, 0.85, 0.45, 1.00 },
    DMG    = { 0.90, 0.80, 0.45, 1.00 },
    ERR    = { 1.00, 0.45, 0.40, 1.00 },
};
pmenu.configure({ ui = ui, COL = COL });   -- Profiles popup state lives in the shared ui table

-- ---------------------------------------------------------------------------
-- Item icons: own module (dlac\itemicons.lua -- the trove/equipmon texture
-- loader). icons.renderIcon / icons.handleOf / icons.drawElementWheel /
-- icons.release; every entry point degrades to a no-op without d3d/imgui.
-- ---------------------------------------------------------------------------
local icons = require("dlac\\ui\\itemicons");

-- ---------------------------------------------------------------------------
-- Flattening (any gear-shaped table -> sorted records + by-Id/by-Name indexes)
-- lives in gear\catalogindex now (M.flatten -- the one walker); the owned table
-- flattens through the same code the catalog does.
-- ---------------------------------------------------------------------------
local function flattenGear(src)
    return ci.flatten(src);
end

-- Full CatsEyeXI reference (catalogindex.flat) for the All Equipment tab + item
-- lookups. Falls back to gear.lua if catalog failed to load, so the tab always works.
local _allEquip, _allEquipById, _allEquipByName;
local function buildAllEquip()
    if _allEquip == nil then
        if has.catalog then _allEquip, _allEquipById, _allEquipByName = ci.flat();
        else _allEquip, _allEquipById, _allEquipByName = flattenGear(gear); end
    end
    return _allEquip;
end

-- Fill the RAW gear table with catalog stats, in place, once. A Phase-2 gear.lua carries no
-- Stats (owned is a thin ownership record); the catalog has stats for every item by Id. We
-- mutate the shared `gear` table so BOTH the GUI (flattenGear copies e.Stats) and the
-- optimizer (gearoptim reads the same table) see stats. catalog is the base; a stat already
-- on the entry wins (owned overrides, catalog only fills gaps).
local _gearEnriched = false;
local function enrichGearFromCatalog()
    if _gearEnriched or not has.catalog then return; end
    buildAllEquip();   -- ensure the catalog id-index (_allEquipById) exists
    local function walk(container)
        for _, v in pairs(container) do
            if type(v) == 'table' then
                if v.Id ~= nil and v.Name ~= nil then                       -- an item entry
                    local c = _allEquipById[v.Id];
                    if c ~= nil and grec ~= nil then
                        -- Per-record fill (Type + legacy-spelling heal, OneHanded,
                        -- AmmoType, Model, Stats -- owned overrides, catalog fills)
                        -- is a RECORD RULE: gearrecord.enrich, tested REC*. Only
                        -- the container walk lives here.
                        grec.enrich(v, c);
                    end
                else                                                        -- a slot/category table
                    walk(v);
                end
            end
        end
    end
    for _, sv in pairs(gear) do   -- includes NameToObject, so gearoptim's name-keyed reads see stats too
        if type(sv) == 'table' then walk(sv); end
    end
    _gearEnriched = true;
end

-- Owned gear (gear.lua): Equipped alternatives, Sets candidates, equipped-item lookups.
local _owned, _ownedById, _ownedByName;
local function buildOwned()
    if _owned == nil then
        enrichGearFromCatalog();   -- raw gear gets catalog stats before we flatten / score
        _owned, _ownedById, _ownedByName = flattenGear(gear);
    end
    return _owned;
end
pcall(enrichGearFromCatalog);   -- eager: gearui loads last, so raw gear is stat-ready before any use

-- Resolve an item to a record (for tooltips / worn-set stats): owned first, then
-- the full catalog. Id is authoritative; name is the fallback.
local function lookupById(id)
    if id == nil then return nil; end
    if _ownedById   and _ownedById[id]   then return _ownedById[id];   end
    if _allEquipById and _allEquipById[id] then return _allEquipById[id]; end
    return nil;
end
local function lookupByName(name)
    if name == nil then return nil; end
    local ln = string.lower(name);
    if _ownedByName   and _ownedByName[ln]   then return _ownedByName[ln];   end
    if _allEquipByName and _allEquipByName[ln] then return _allEquipByName[ln]; end
    return nil;
end

-- ---------------------------------------------------------------------------
-- Small display / eligibility helpers. The display formatters (esc/truncate/
-- textWrapped/sortedKeys/jobsText/statSummary/fullStatList/qtyTag/nameWidthOf)
-- live in dlac\\gearfmt.lua (the 200-local cap again); the eligibility helpers
-- stay here. gearfmt's live deps (effStats, owned.counts) are injected further
-- down, next to the owned-cache refresh helper.
-- ---------------------------------------------------------------------------
local fmt = require("dlac\\gear\\gearfmt");

-- Eligibility (the single source of truth for every candidate / alternatives /
-- "usable now" list): Jobs contains the current MAIN or SUPPORT job -- or Jobs is
-- {"All"} / unrestricted -- AND Level <= the current main-job level.
local JOB_ABBR = {
    [1]='WAR',[2]='MNK',[3]='WHM',[4]='BLM',[5]='RDM',[6]='THF',[7]='PLD',[8]='DRK',
    [9]='BST',[10]='BRD',[11]='RNG',[12]='SAM',[13]='NIN',[14]='DRG',[15]='SMN',[16]='BLU',
    [17]='COR',[18]='PUP',[19]='DNC',[20]='SCH',[21]='GEO',[22]='RUN',
};

-- Sub job abbreviation + effective level (honours the staticSubLevel override).
-- gData when available (LAC context); Ashita player memory as the fallback.
local function getSubInfo()
    local sj, slv = nil, 0;
    pcall(function()
        if gData ~= nil and gData.GetPlayer ~= nil then
            local p = gData.GetPlayer();
            if p ~= nil then
                sj  = p.SubJob;
                slv = p.SubJobSync or 0;
            end
        end
        if sj == nil then
            local mp = AshitaCore:GetMemoryManager():GetPlayer();
            local id = mp and mp:GetSubJob() or 0;
            if id > 0 then
                sj  = JOB_ABBR[id];
                slv = mp:GetSubJobLevel() or 0;
            end
        end
        if type(staticSubLevel) == 'number' and staticSubLevel > 0 then slv = staticSubLevel; end
    end);
    return sj, slv;
end

-- Equip legality now lives in ONE place: dispatch.jobCanEquip / dispatch.canWear
-- (main job only, level gated on main level -- field-verified on CatsEyeXI:
-- RDM/WHM cannot wear Hlr. Bliaut +1). These wrappers delegate; the inline
-- fallback keeps the GUI usable if dispatch ever fails to load.
local _dsp = try("dlac\\dispatch");
has.dsp = _dsp ~= nil and type(_dsp.jobCanEquip) == 'function';

local function jobCanEquip(jobs, playerJob)
    if has.dsp then return _dsp.jobCanEquip(jobs, playerJob); end
    if jobs == nil or type(jobs) ~= 'table' or #jobs == 0 then return true; end
    for _, j in ipairs(jobs) do
        if j == 'All' or (playerJob ~= nil and playerJob ~= '' and j == playerJob) then return true; end
    end
    return false;
end

local function isUsable(rec, playerJob, playerLevel)
    if has.dsp then return _dsp.canWear(rec, playerJob, playerLevel); end
    if (rec.Level or 0) > (playerLevel or 0) then return false; end
    return jobCanEquip(rec.Jobs, playerJob);
end

-- ---------------------------------------------------------------------------
-- Player info + equipped-item lookup.
-- ---------------------------------------------------------------------------
local function getPlayerInfo()
    local job, level = nil, 0;
    pcall(function()
        if gData == nil or gData.GetPlayer == nil then return; end
        local p = gData.GetPlayer();
        if p == nil then return; end
        job = p.MainJob;
        if type(staticMainLevel) == 'number' and staticMainLevel > 0 then
            level = staticMainLevel;
        else
            level = p.MainJobSync or 0;
        end
    end);
    return job, level;
end

-- "SCH31/WHM15" (or "SCH31" with no sub). Honours static level overrides.
local function jobHeader()
    local s = '?';
    pcall(function()
        if gData == nil or gData.GetPlayer == nil then return; end
        local p = gData.GetPlayer();
        if p == nil then return; end
        local mj  = p.MainJob or '?';
        local mjl = (type(staticMainLevel) == 'number' and staticMainLevel > 0) and staticMainLevel or (p.MainJobSync or 0);
        local sj  = p.SubJob;
        local sjl = (type(staticSubLevel) == 'number' and staticSubLevel > 0) and staticSubLevel or (p.SubJobSync or 0);
        if sj ~= nil and sj ~= '' and sj ~= 'NON' and sj ~= 'None' then
            s = string.format('%s%s/%s%s', tostring(mj), tostring(mjl), tostring(sj), tostring(sjl));
        else
            s = string.format('%s%s', tostring(mj), tostring(mjl));
        end
    end);
    return s;
end

-- Equipped item id for an equipment slot (equipmon's method), or nil.
local function getEquippedId(equipSlot)
    local id = nil;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        if inv == nil then return; end
        local eitem = inv:GetEquippedItem(equipSlot);
        if eitem == nil or eitem.Index == 0 then return; end
        local cont = bit.band(eitem.Index, 0xFF00) / 0x0100;
        local slotInCont = eitem.Index % 0x0100;
        local iitem = inv:GetContainerItem(cont, slotInCont);
        if iitem == nil then return; end
        local iid = iitem.Id;
        if iid == nil or iid == 0 or iid == 65535 then return; end
        id = iid;
    end);
    return id;
end

-- Clean display name: prefer our data (gear.lua/catalog), fall back to the resource.
local nameCache = {};
local function displayName(itemId)
    if itemId == nil then return nil; end
    if nameCache[itemId] ~= nil then
        local v = nameCache[itemId];
        return (v ~= false) and v or nil;
    end
    local nm = nil;
    local rec = lookupById(itemId);
    if rec ~= nil then
        nm = rec.Name;
    else
        pcall(function()
            local res = AshitaCore:GetResourceManager():GetItemById(itemId);
            if res ~= nil and res.Name ~= nil then nm = res.Name[1]; end
        end);
    end
    nameCache[itemId] = nm or false;
    return nm;
end

-- Human label for a gear set (the data carries only ids): two-piece sets read
-- as the pair ("Lava's Ring + Kusha's Ring"); larger sets take their FAMILY
-- word -- the most common first word across the piece names, matched through a
-- stem that survives possessive/short-name drift ("Ares's" vs "Ares", "Skadi's"
-- vs "Skadis"; "Marduks" vs "Mdk." resolves by majority) -- extended while the
-- family shares further words ("Iron Ram set") and keeping a shared quality
-- mark visible ("Ares +1 set" = Salvage II, distinct from base "Ares set").
-- NEVER "<piece> +N": that reads as an HQ item name (the Salvage field bug --
-- "Ares' Cuirass +4" -- Henrik, 2026-07-18). Cached once every name resolves.
local setLabelCache = {};
local function setLabelOf(setId)
    if setLabelCache[setId] ~= nil then return setLabelCache[setId]; end
    local e = (gfx ~= nil and type(gfx.setInfo) == 'function') and gfx.setInfo(setId) or nil;
    if e == nil then return 'set #' .. tostring(setId); end
    local names, resolved = {}, true;
    for i, pid in ipairs(e.pieces) do
        local nm = displayName(pid);
        if nm == nil then nm = '#' .. tostring(pid); resolved = false; end
        names[i] = nm;
    end
    local lbl;
    if #names == 2 then
        lbl = names[1] .. ' + ' .. names[2];
    else
        local words = {};
        for i, nm in ipairs(names) do
            local w = {};
            for t in string.gmatch(nm, '%S+') do w[#w + 1] = t; end
            words[i] = w;
        end
        -- drift-tolerant stem: lowercase, punctuation out, trailing s off --
        -- "Ares's"/"Ares" -> "are", "Skadi's"/"Skadis" -> "skadi"
        local function stem(w)
            w = string.gsub(string.lower(w or ''), '[^%w]', '');
            return (string.gsub(w, 's+$', ''));
        end
        -- majority first-word family (ties -> earliest piece order)
        local counts, order = {}, {};
        for _, w in ipairs(words) do
            local k = stem(w[1]);
            if k ~= '' then
                if counts[k] == nil then order[#order + 1] = k; end
                counts[k] = (counts[k] or 0) + 1;
            end
        end
        local famKey, famN = nil, 0;
        for _, k in ipairs(order) do
            if counts[k] > famN then famKey, famN = k, counts[k]; end
        end
        if famKey ~= nil then
            local fam, raw = {}, nil;
            for _, w in ipairs(words) do
                if stem(w[1]) == famKey then
                    fam[#fam + 1] = w;
                    if raw == nil then raw = w[1]; end
                end
            end
            -- extend while EVERY family member shares the next word
            local parts, wi = { raw }, 2;
            while true do
                local nxt = fam[1][wi];
                if nxt == nil or string.match(nxt, '^%+%d+$') ~= nil then break; end
                local allSame = true;
                for _, w in ipairs(fam) do
                    if w[wi] == nil or stem(w[wi]) ~= stem(nxt) then allSame = false; break; end
                end
                if not allSame then break; end
                parts[#parts + 1] = nxt;
                wi = wi + 1;
            end
            -- a quality mark carried by EVERY family piece stays visible
            local q = string.match(fam[1][#fam[1]] or '', '^%+%d+$');
            if q ~= nil then
                for _, w in ipairs(fam) do
                    if w[#w] ~= q then q = nil; break; end
                end
            end
            lbl = table.concat(parts, ' ') .. ((q ~= nil) and (' ' .. q) or '') .. ' set';
        else
            lbl = tostring(#names) .. '-piece set';
        end
    end
    if resolved then setLabelCache[setId] = lbl; end   -- don't cache '#id' fallbacks
    return lbl;
end

-- ---------------------------------------------------------------------------
-- Candidate lists (eligible OWNED gear per slot), memoized per job/level.
-- Re-sorted by weighted score when weights exist; invalidate on weight edits.
-- ---------------------------------------------------------------------------
local candCache = { key = nil, data = {} };
local function invalidateCandidates() candCache.key = nil; end

-- Live owned quantities -- own module now (dlac\\ownedcache.lua, the 200-local cap
-- again): owned.counts (avail: Inventory+Wardrobes) / owned.totals (owned ANYWHERE)
-- / owned.whereOf / owned.haveInBags / owned.isStored, over gearimport.ownedSplit().
-- Candidate lists filter to gear that is actually in your bags -- gear.lua is a
-- curated DB and can list items you no longer own (e.g. a base "Garrison Sallet"
-- when you only have the +1). Safe fallback: if the live scan returns nothing
-- (inventory manager unavailable / char select), nothing is hidden.
local owned = require("dlac\\gear\\ownedcache");

local function weightsActive()
    if not has.optim or optim.getWeights == nil then return false; end
    local ok, ws = pcall(optim.getWeights);
    if not ok or type(ws) ~= 'table' then return false; end
    -- A weight ZEROED in the editor leaves its entry behind ({ perUnit = 0 });
    -- an all-zero table must count as "no weights" -- otherwise the optimizer
    -- runs, everything scores 0, and Auto-build silently builds nothing
    -- (field case: a dead-looking Auto-build button).
    for _, w in pairs(ws) do
        if (tonumber(type(w) == 'table' and w.perUnit or w) or 0) ~= 0 then return true; end
    end
    return false;
end

local function scoreOf(stats)
    if not has.optim or optim.score == nil then return 0; end
    local ok, sc = pcall(optim.score, stats or {});
    if ok and type(sc) == 'number' then return sc; end
    return 0;
end

-- Per-id owned augment stat deltas { id -> {stat->delta} }, cached (reset with the owned
-- caches). Lets set scoring weigh BASE + your private augments, matching the worn panel.
local _ownedAugStats = nil;
local function ownedAugStatsMap()
    if _ownedAugStats ~= nil then return _ownedAugStats; end
    local m = {};
    if has.aug then pcall(function() m = aug.ownedAugStats() or {}; end); end
    _ownedAugStats = m;
    return _ownedAugStats;
end

-- THE candidate-stats seam: effective stats at level PLUS the augment deltas on
-- the copy you own (by Id). Every scoring consumer -- scoreOfItem, the joint
-- Auto-build pools, the Sub marginal call -- reads candidates through this one
-- helper, so augmented gear is weighed identically everywhere. Zero-copy when
-- the item has no augments.
local function candidateStats(rec, level)
    if rec == nil then return nil; end
    local base = effStats(rec, level);
    local a = (rec.Id ~= nil) and ownedAugStatsMap()[rec.Id] or nil;
    if a == nil then return base; end
    local combined = {};
    if type(base) == 'table' then for k, v in pairs(base) do combined[k] = v; end end
    for k, v in pairs(a) do combined[k] = (combined[k] or 0) + v; end
    return combined;
end

-- Weighted score of an ITEM (per-item: gear-set bonuses deliberately do NOT
-- enter here -- a single item has no combination; set credit lives in the
-- optimizePicks paths and the composition-level workingWeightedScore).
local function scoreOfItem(rec, level)
    if rec == nil then return 0; end
    if level == nil then local _, l = getPlayerInfo(); level = l; end
    return scoreOf(candidateStats(rec, level));
end

-- Effective item-Level cap for SET BUILDING (Auto-build + the manual + Add picker): the
-- "Build as lv.75" toggle (optim.buildAtMaxLevel) lifts the cap to 75 so you can assemble
-- over-level sets; the job restriction is unaffected. The Equipped tab keeps the real level.
local function setBuildLevel(level)
    if has.optim and optim.buildAtMaxLevel == true then return optim.MAX_LEVEL or 75; end
    return level;
end

local function candidatesForSlot(gearSlotKey, job, level)
    local key = tostring(job) .. '|' .. tostring(level);   -- sub job does not affect wearability
    if candCache.key ~= key then candCache.key = key; candCache.data = {}; end
    if candCache.data[gearSlotKey] ~= nil then return candCache.data[gearSlotKey]; end

    local out = {};
    for _, rec in ipairs(buildOwned()) do
        if rec.Slot == gearSlotKey and isUsable(rec, job, level) and owned.haveInBags(rec) then
            out[#out + 1] = rec;
        end
    end

    local useScore = weightsActive();
    table.sort(out, function(a, b)
        if useScore then
            local sa, sb = scoreOfItem(a, level), scoreOfItem(b, level);
            if sa ~= sb then return sa > sb; end
        end
        if (a.Level or 0) ~= (b.Level or 0) then return (a.Level or 0) > (b.Level or 0); end
        return tostring(a.Name) < tostring(b.Name);
    end);

    candCache.data[gearSlotKey] = out;
    return out;
end

-- Sub-slot candidate pool: the native Sub records (shields / grips) PLUS the 1H
-- records that live under Main -- off-hand weapons are Main-slot items in
-- gear.lua, so a plain candidatesForSlot('Sub') can never offer them.
-- subFilter applies the pairing rule on top.
local function subCandidatePool(job, level)
    local pool = {};
    for _, r in ipairs(candidatesForSlot('Sub', job, level)) do pool[#pool + 1] = r; end
    for _, r in ipairs(candidatesForSlot('Main', job, level)) do
        if r.OneHanded == true then pool[#pool + 1] = r; end
    end
    return pool;
end

-- ---------------------------------------------------------------------------
-- Worn-set stat totals (our data only): sum the Stats of the 16 equipped items.
-- ---------------------------------------------------------------------------
-- Returns (totals, setBonuses): totals through geareffects.comboStats -- the
-- whole worn COMPOSITION evaluated at once, so active gear-set bonuses land in
-- the numbers (worn Lava's + Kusha's finally shows ATT+6/ACC+12/DEF+6) -- and
-- setBonuses is the attribution list renderStatsPanel captions from (partial
-- sets included, so "one more piece lights this up" is visible). Counting is
-- per SLOT: two worn copies of one piece count twice (server-verified).
local function wornSetTotals()
    local totals = {};
    local _, _wlvl = getPlayerInfo();
    local comp = {};
    for _, sl in ipairs(EQUIP_SLOTS) do
        local id  = getEquippedId(sl.equip);
        local rec = lookupById(id);
        if rec == nil and id ~= nil then rec = lookupByName(displayName(id)); end
        if rec ~= nil then comp[sl.label] = rec; end
    end
    local bonuses = nil;
    if has.gfx then
        local ok, res = pcall(gfx.comboStats, comp, { level = _wlvl });
        if ok and type(res) == 'table' and type(res.stats) == 'table' then
            for k, v in pairs(res.stats) do
                if k ~= 'DMG' and k ~= 'Delay' then totals[k] = v; end
            end
            bonuses = res.setBonuses;
        end
    end
    if bonuses == nil then   -- geareffects missing/failed: the pre-P1 per-item sum
        for _, rec in pairs(comp) do
            local _st = effStats(rec, _wlvl);
            if type(_st) == 'table' then
                for k, v in pairs(_st) do
                    if type(v) == 'number' and k ~= 'DMG' and k ~= 'Delay' then
                        totals[k] = (totals[k] or 0) + v;
                    end
                end
            end
        end
    end
    -- Fold in live augment deltas so worn totals reflect base + your private augments.
    if has.aug then
        local ok, augTotals = pcall(aug.wornStats);
        if ok and type(augTotals) == 'table' then
            for k, v in pairs(augTotals) do
                if k ~= 'DMG' and k ~= 'Delay' then totals[k] = (totals[k] or 0) + v; end
            end
        end
    end
    return totals, bonuses;
end

-- ---------------------------------------------------------------------------
-- Frame-delayed command queue + frame clock (for the "Lock when equipped"
-- enable/equip/disable sequence) -- own module now (dlac\\cmdqueue.lua, the
-- 200-local cap again). cmdq.tick() runs every d3d_present so it never blocks;
-- cmdq.frame() is the shared frame clock the per-frame logic below reads.
-- ---------------------------------------------------------------------------
local cmdq = require("dlac\\lib\\cmdqueue");

local function lacSlot(label) return string.lower(tostring(label or '')); end

-- The game's native /equip uses the SAME slot names as LAC: ear1/ear2/ring1/
-- ring2 (field-verified 2026-07-11 -- /equip lring etc. simply fails; that
-- lear/rear/lring/rring vocabulary is Windower-tool naming, not the client's).
-- No translation table: one slot name everywhere.

-- Equip an item into a slot. Three modes:
--   freeEquip -- LAC is globally disabled (Free-equip mode); send the *native* game
--                /equip command so it bypasses LAC entirely and sticks (LAC won't
--                re-override while disabled). This is the "equip outside LAC" path.
--   lock      -- lock the slot ENGINE-SIDE (/dl lock: the dispatch engine strips it
--                from every set it equips -- this is what actually holds, and it's
--                what the mirror displays), plus /lac disable as belt-and-suspenders
--                against any legacy hand-written EquipSet calls in the profile, then
--                native /equip. alreadyLocked (from the engine's mirror, so it resets
--                correctly when LAC reloads) skips the re-lock spam.
--   default   -- /lac equip temp-swap (LAC may re-override on the next action).
local function equipToSlot(slotLabel, itemName, lock, freeEquip, alreadyLocked)
    if slotLabel == nil or itemName == nil then return; end
    local slot = lacSlot(slotLabel);
    local nm   = tostring(itemName);
    if freeEquip then
        pcall(function()
            AshitaCore:GetChatManager():QueueCommand(1, string.format('/equip %s "%s"', slot, nm));
        end);
    elseif lock then
        if alreadyLocked then
            cmdq.enqueue(2, string.format('/equip %s "%s"', slot, nm));          -- locked; just equip
        else
            cmdq.enqueue(2,  string.format('/dl lock %s on', slot));             -- engine lock (the real hold)
            cmdq.enqueue(4,  string.format('/lac disable %s', slot));            -- belt for legacy profile code
            cmdq.enqueue(26, string.format('/equip %s "%s"', slot, nm));         -- then equip after it settles
        end
    else
        pcall(function()
            AshitaCore:GetChatManager():QueueCommand(1, string.format('/lac equip %s "%s"', slot, nm));
        end);
    end
end

-- ---------------------------------------------------------------------------
-- Owned quantities, sub-job info, and Sub-slot / paired-slot rules (Phase 3).
-- ---------------------------------------------------------------------------

-- The owned-split cache itself lives in dlac\\ownedcache.lua (see the require up
-- with the candidate helpers); refreshed on Scan / Reload here and on the ~4s
-- d3d_present heartbeat (so container moves -- Safe -> Wardrobe and back --
-- change availability live).
local _ownedAug = nil;   -- cached { itemId -> {augment-desc, ...} } for owned gear
local function refreshOwnedCounts() owned.resetCache(); _ownedAug = nil; _ownedAugStats = nil; invalidateCandidates(); end

-- Re-read <char>\dlac\gear.lua and rebuild the owned view after a Commit, so the GUI
-- reflects newly-imported gear WITHOUT an addon reload. Mutates the shared `gear` table in
-- place (so every capture sees the new data) and drops the owned caches -- buildOwned then
-- rebuilds, re-deriving stats from the catalog.
local function refreshGear()
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name, id = party:GetMemberName(0), party:GetMemberServerId(0);
        if name == nil or name == '' or id == nil then return; end
        local path = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\dlac\\gear.lua',
            AshitaCore:GetInstallPath(), name, id);
        local chunk = loadfile(path);
        if chunk == nil then return; end
        local ok, g = pcall(chunk);
        if ok and type(g) == 'table' then
            for k in pairs(gear) do gear[k] = nil; end   -- refresh the shared gear table in place
            for k, v in pairs(g)  do gear[k] = v;   end
            package.loaded['dlac\\gear'] = gear;
            _gearEnriched = false;             -- new (statless) entries -> re-enrich raw gear
            enrichGearFromCatalog();
            _owned, _ownedById, _ownedByName = nil, nil, nil;   -- force rebuild off the enriched gear
            refreshOwnedCounts();
            pcall(function() if has.optim and type(optim.invalidate) == 'function' then optim.invalidate(); end end);
        end
    end);
end

-- Owned augments per item id (from the live bag scan), cached; refreshed on Reload/Scan.
local function ownedAugMap()
    if _ownedAug ~= nil then return _ownedAug; end
    local m = {};
    if has.aug then pcall(function() m = aug.ownedAugments() or {}; end); end
    _ownedAug = m;
    return _ownedAug;
end

-- gearfmt's live deps (effStats is defined up top, owned.counts is the live
-- owned-quantity map, ownedAugs feeds the gold "Aug:" row tags). Configured HERE,
-- below ownedAugMap's declaration -- a forward reference would capture a nil
-- global, not the local (hard rule 8).
fmt.configure({ effStats = effStats, ownedCounts = owned.counts,
                ownedAugs = function() return ownedAugMap(); end });

-- Dual-wield availability. Prefer utils.isDualWieldAvailable (required lazily to
-- avoid a load-time circular require); else mirror it (THF>=20 / NIN>=10 / DNC>=20).
local function isDualWieldAvailable(mj, mjLevel, sj, sjLevel)
    local ok, utils = pcall(require, "dlac\\utils");
    if ok and type(utils) == 'table' and type(utils.isDualWieldAvailable) == 'function' then
        local r; local pok = pcall(function() r = utils.isDualWieldAvailable(mj, mjLevel, sj, sjLevel); end);
        if pok and r ~= nil then return r == true; end
    end
    if (mj == 'THF' and (mjLevel or 0) >= 20) or (sj == 'THF' and (sjLevel or 0) >= 20) then return true; end
    if (mj == 'NIN' and (mjLevel or 0) >= 10) or (sj == 'NIN' and (sjLevel or 0) >= 10) then return true; end
    if (mj == 'DNC' and (mjLevel or 0) >= 20) or (sj == 'DNC' and (sjLevel or 0) >= 20) then return true; end
    return false;
end

-- Is a Sub-slot record valid given the current Main record? The rule lives in
-- utils.subSlotAllowed (shared with BuildDynamicSets); mirrored below as the
-- fallback, like isDualWieldAvailable.
--
-- HARD RULE (see utils.subSlotAllowed -- reverted three times, never again):
-- `building` = composing a set (a plan, not an equip) -> the Sub offer NEVER
-- adapts to the Main pick or the Dual Wield trait; every shield/grip/1H weapon
-- passes (same-name still needs a real second copy). Equip-now paths (the
-- Equipped tab's alternatives) leave `building` unset and stay strictly gated.
local function subCandidateOk(subRec, mainRec, mainJob, mainLevel, subJob, subLevel, oc, building)
    if mainRec == nil and building ~= true then return false; end   -- equip-now needs a Main
    local dw = isDualWieldAvailable(mainJob, mainLevel, subJob, subLevel);
    local copies = (((oc and subRec.Id) and oc[subRec.Id]) or 0);
    local ok, utils = pcall(require, "dlac\\utils");
    if ok and type(utils) == 'table' and type(utils.subSlotAllowed) == 'function' then
        local r; local pok = pcall(function()
            r = utils.subSlotAllowed(subRec, mainRec, { dw = dw, building = building, copies = copies });
        end);
        if pok and type(r) == 'boolean' then return r; end
    end
    -- fallback mirror of utils.subSlotAllowed (incl. classifySub: the catalog
    -- labels shields AND grips Type="Sub"; grips/straps are all named that way)
    local kind = subRec.Type;
    if kind == 'Sub' then
        local n = string.lower(tostring(subRec.Name or ''));
        kind = (n:find('grip', 1, true) ~= nil or n:find('strap', 1, true) ~= nil) and 'Grip' or 'Shield';
    elseif kind ~= 'Grip' and kind ~= 'Shield' then
        kind = nil;   -- a weapon type ('Sword', 'Axe', ...) or no metadata
    end
    if building == true then                          -- mirror of the utils HARD RULE branch
        if kind ~= nil then return true; end
        if subRec.OneHanded ~= true then return false; end
        if mainRec ~= nil and subRec.Name == mainRec.Name then
            return copies >= 2 or (tonumber(subRec.Count) or 0) >= 2;
        end
        return true;
    end
    if mainRec.OneHanded == false then return kind == 'Grip'; end
    if mainRec.OneHanded ~= true then return false; end
    if kind == 'Shield' then return true; end
    if kind ~= nil then return false; end
    if subRec.OneHanded ~= true then return false; end
    if dw ~= true then return false; end
    if subRec.Name == mainRec.Name then
        return copies >= 2 or (tonumber(subRec.Count) or 0) >= 2;
    end
    return true;
end

-- Filter a Sub candidate list against the current Main record.
local function subFilter(cands, mainRec, job, level, building)
    if mainRec == nil then return {}; end
    local sj, slv = getSubInfo();
    local oc = owned.counts();
    local out = {};
    for _, r in ipairs(cands) do
        if subCandidateOk(r, mainRec, job, level, sj, slv, oc, building) then out[#out + 1] = r; end
    end
    return out;
end

-- Planning surface (the set builder's + Add popup). HARD RULE (see
-- utils.subSlotAllowed): while BUILDING, every Sub-capable item is offered --
-- shields, grips, and one-handers alike -- regardless of the Main plans, the
-- current Dual Wield state, or anything else live. BuildDynamicSets enforces
-- the real pairing per cast; the builder never pre-empts it. The only Main
-- interaction left is the same-name second-copy rule (checked against each
-- Main plan; an empty Main list checks against none and offers everything).
local function subFilterAnyMain(cands, mainList, job, level)
    local mains = {};
    if type(mainList) == 'table' then
        for _, it in ipairs(mainList) do
            if it.rec ~= nil then
                if it.rec.Virtual == true then
                    if string.lower(tostring(it.rec.Name or '')):find('autostaff', 1, true) ~= nil then
                        mains[#mains + 1] = { Name = it.rec.Name, OneHanded = false };
                    end
                else
                    mains[#mains + 1] = it.rec;
                end
            end
        end
    end
    local sj, slv = getSubInfo();
    local oc = owned.counts();
    local out = {};
    for _, r in ipairs(cands) do
        if #mains == 0 then
            -- No Main planned yet: the Sub list must NOT be empty because of
            -- the Main column (Sub-only sets are legitimate plans).
            if subCandidateOk(r, nil, job, level, sj, slv, oc, true) then out[#out + 1] = r; end
        else
            for _, m in ipairs(mains) do
                if subCandidateOk(r, m, job, level, sj, slv, oc, true) then
                    out[#out + 1] = r;
                    break;
                end
            end
        end
    end
    return out;
end

-- Paired slots that fight over the same physical copies.
local PAIR_OF = { Ring1 = 'Ring2', Ring2 = 'Ring1', Ear1 = 'Ear2', Ear2 = 'Ear1' };

-- Ids the paired slot already uses that we own only ONE of (so the current slot must
-- not reuse them). fromSets = read the working set; else read the equipped slot.
local function pairedBlockedIds(slotLabel, fromSets)
    local blocked = {};
    local other = PAIR_OF[slotLabel];
    if other == nil then return blocked; end
    local oc = owned.counts();
    if fromSets then
        local list = M.working[other];
        if type(list) == 'table' then
            for _, it in ipairs(list) do
                local id = it.rec and it.rec.Id;
                if id and (oc[id] or 0) < 2 then blocked[id] = true; end
            end
        end
    else
        for _, s in ipairs(EQUIP_SLOTS) do
            if s.label == other then
                local id = getEquippedId(s.equip);
                if id and (oc[id] or 0) < 2 then blocked[id] = true; end
                break;
            end
        end
    end
    return blocked;
end

-- ---------------------------------------------------------------------------
-- FFXI-style hover tooltip (our gear data only).
-- ---------------------------------------------------------------------------
local function renderItemTooltip(rec)
    imgui.BeginTooltip();
    pcall(function()
        imgui.TextColored(COL.HEADER, fmt.esc(rec.Name or '?'));
        local typeStr = rec.Type or rec.Category or rec.Slot;
        if typeStr ~= nil then imgui.TextColored(COL.DIM, '(' .. fmt.esc(tostring(typeStr)) .. ')'); end
        local _, _lvl = getPlayerInfo();
        local stats = effStats(rec, _lvl);
        if has.lscale and rec.Id ~= nil and lscale.has(rec.Id) then
            imgui.TextColored(COL.DIM, string.format('(scales with level -- shown for Lv%d)', _lvl or 0));
        end
        if type(stats) == 'table' and type(stats.DMG) == 'number' and type(stats.Delay) == 'number' then
            imgui.TextColored(COL.DMG, string.format('DMG:%s Delay:%s', tostring(stats.DMG), tostring(stats.Delay)));
        end
        local sl = fmt.fullStatList(stats);
        if sl ~= '' then imgui.TextColored(COL.STATS, fmt.esc(sl)); end
        local jt = fmt.jobsText(rec.Jobs);
        if jt == 'All' then jt = 'All Jobs'; end
        imgui.TextColored(COL.JOBS, string.format('Lv.%s %s', tostring(rec.Level or 0), jt));
        -- Gear-set membership: the bonus tier ladder + the partner pieces, so an
        -- item's set potential reads off the item itself. * marks pieces you own
        -- (anywhere). Multi-set items show one block per set.
        if has.gfx and rec.Id ~= nil and type(gfx.setsOf) == 'function' then
            local sids = gfx.setsOf(rec.Id);
            if sids ~= nil then
                local tot = owned.totals();
                if type(tot) ~= 'table' then tot = {}; end
                for _, sid in ipairs(sids) do
                    local e = gfx.setInfo(sid);
                    if e ~= nil then
                        local ownedN = 0;
                        for _, pid in ipairs(e.pieces) do
                            if (tot[pid] or 0) > 0 then ownedN = ownedN + 1; end
                        end
                        imgui.Separator();
                        imgui.TextColored(COL.SCORE, string.format('Set bonus -- %s (own %d of %d, active at %d):',
                            setLabelOf(sid), ownedN, #e.pieces, e.min or 2));
                        for c = (e.min or 2), (e.max or 2) do   -- the tier ladder, value AT each count
                            local d = e.tiers[c];
                            if d ~= nil then
                                local line = fmt.fullStatList(d);
                                if line ~= '' then
                                    imgui.TextColored(COL.STATS, string.format('  %d pc: %s', c, fmt.esc(line)));
                                end
                            end
                        end
                        local parts = {};
                        for _, pid in ipairs(e.pieces) do
                            if pid ~= rec.Id then
                                local nm = displayName(pid) or ('#' .. tostring(pid));
                                parts[#parts + 1] = nm .. (((tot[pid] or 0) > 0) and '*' or '');
                            end
                        end
                        for i = 1, #parts, 3 do   -- 3 partner names per line, tooltip-width friendly
                            local chunk = table.concat(parts, ', ', i, math.min(i + 2, #parts));
                            imgui.TextColored(COL.DIM, ((i == 1) and 'With: ' or '      ') .. fmt.esc(chunk));
                        end
                    end
                end
            end
        end
        -- WHERE the item lives (every owned copy): red when only in storage, dim when
        -- equippable -- so "which wardrobe is it in" never needs a bag hunt. The
        -- container aggregation is ownedcache.whereText (one builder); a stored item
        -- with no location detail still warns ('?') rather than staying silent.
        if rec.Id ~= nil then
            local locs = owned.whereText(rec);         -- populates the split cache too
            if owned.isStored(rec) then
                imgui.TextColored(COL.ERR, 'IN STORAGE: ' .. fmt.esc((locs ~= '') and locs or '?')
                    .. '  (move to Inventory/Wardrobe to equip)');
            elseif locs ~= '' then
                imgui.TextColored(COL.DIM, 'Held: ' .. fmt.esc(locs));
            end
        end
        if rec.Id ~= nil then                          -- private augments on your owned copy
            local al = ownedAugMap()[rec.Id];
            if al ~= nil and #al > 0 then
                local more = (#al > 1) and string.format('   (+%d more copies)', #al - 1) or '';
                imgui.TextColored(COL.SCORE, 'Aug: ' .. fmt.esc(al[1]) .. more);
            end
        end
        -- /dl view_ids: the two numbers, last so they never push the item's own
        -- facts down. They are DIFFERENT numbers and the difference matters --
        -- a lockstyle shows the MODEL id; the item id is what the packet names.
        -- Model resolves like lockstyle's modelOf: the record's own field first,
        -- then the catalog BY ID (an owned record only carries Model once the
        -- enrichment pass has run). nil model = the item has no look slot.
        if sf.flags.viewids then
            local mid = tonumber(rec.Model);
            if mid == nil and rec.Id ~= nil then
                buildAllEquip();
                local c = _allEquipById and _allEquipById[rec.Id] or nil;
                if type(c) == 'table' then mid = tonumber(c.Model); end
            end
            imgui.Separator();
            imgui.TextColored(COL.DIM, string.format('Item id: %s      Model id: %s',
                (rec.Id ~= nil) and tostring(rec.Id) or '?',
                (mid ~= nil and mid ~= 0) and tostring(mid) or 'none (no look)'));
        end
    end);
    imgui.EndTooltip();
end

-- ---------------------------------------------------------------------------
-- gearimport module (header Stage / Commit / Scan buttons).
-- ---------------------------------------------------------------------------
local function callImport(fn)
    local ok, mod = pcall(require, "dlac\\gear\\gearimport");
    if ok and mod ~= nil and type(mod[fn]) == 'function' then
        local ok2, ret = pcall(mod[fn]);
        return ok2 and ret or nil;
    end
    print('[dlac] gear UI: gearimport.' .. tostring(fn) .. ' is unavailable.');
    return nil;
end

-- Augment dump: write all augmented gear to augdump.txt (share to identify unknown ids).
local _augStatus = nil;
local function dumpAugs()
    if not has.aug then _augStatus = 'Augment reader unavailable.'; return; end
    local ok, path, count, unk = pcall(aug.dumpToFile);
    if ok and path ~= nil then
        _augStatus = string.format('Wrote %d augmented items to %s', count or 0, tostring(path));
        if unk ~= nil and #unk > 0 then
            _augStatus = _augStatus .. string.format('   |  %d UNKNOWN id(s): %s', #unk, table.concat(unk, ', '));
        end
        pcall(function() print('[dlac] ' .. _augStatus); end);
    else
        _augStatus = 'Aug dump failed (could not resolve char folder / write file).';
    end
end

-- ---------------------------------------------------------------------------
-- Profile migration: convert a LuaAshitacast <JOB>.lua from ffxi-lac to dlac.
-- (JOB_ABBR is defined up with the usability helpers.)
-- ---------------------------------------------------------------------------
local function readFileText(p) local f=io.open(p,'r'); if f==nil then return nil; end local t=f:read('*a'); f:close(); return t; end
local function writeFileText(p,t) local f=io.open(p,'w'); if f==nil then return false; end f:write(t); f:close(); return true; end

-- <install>\config\addons\luashitacast\<Char>_<id>\  (or nil if not logged in).
local function charBase()
    local base = nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name  = party:GetMemberName(0);
        local id    = party:GetMemberServerId(0);
        if name ~= nil and name ~= '' and id ~= nil then
            base = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\', AshitaCore:GetInstallPath(), name, id);
        end
    end);
    return base;
end

-- Engine-owned slot locks, read from the modestate mirror (__locks). The ENGINE is
-- the source of truth -- its session resets on LAC reload, so this view (unlike the
-- old addon-side _disabledSlots table, which outlived LAC reloads and made "Lock when
-- equipped" silently skip re-locking) can never go stale. Throttled to ~1 read/second.
local _lockMirror = { at = -1, locks = {} };
local function engineLocks()
    local now = os.time();
    if now == _lockMirror.at then return _lockMirror.locks; end
    _lockMirror.at = now;
    local locks = {};
    pcall(function()
        local base = charBase();
        if base == nil then return; end
        local chunk = loadfile(base .. 'dlac\\modestate.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' and type(t.__locks) == 'table' then locks = t.__locks; end
    end);
    _lockMirror.locks = locks;
    return locks;
end

-- Current main job's <JOB>.lua path + its abbr (or nil, nil).
local function jobFile()
    local base = charBase();
    if base == nil then return nil, nil; end
    local abbr = nil;
    pcall(function() abbr = JOB_ABBR[AshitaCore:GetMemoryManager():GetPlayer():GetMainJob()]; end);
    if abbr == nil then return nil, nil; end
    return base .. abbr .. '.lua', abbr;
end

-- Setup / migration machinery: own module (dlac\setupui.lua). It gets the
-- file/profile helpers once (the profilesets.configure precedent); the Setup
-- button + plan popup below still render here and call setup.*.
local setup = require("dlac\\ui\\setupui");
setup.configure({
    charBase = charBase, jobFile = jobFile,
    readFileText = readFileText, writeFileText = writeFileText,
    ui = ui,
    status = function(s) _augStatus = s; end,   -- the header status line
});

-- Reload LAC / Scan / Stage / Commit / Augs / Setup, right-aligned on the header row.

-- The "Teleports" header dropdown, three tiers (Henrik, 2026-07-19): the
-- instant/panic strip on top (owned-only -- useitem.menu() already dropped the
-- rest), then "Teleport Earrings" / "Teleport Rings" cascading submenus (every
-- destination listed, dim when unowned), then the exp rings. Fixed columns
-- (destination / item / charges / state) so the rows line up; colors follow
-- the house rules -- lit = equippable now, red = owned but stored, dim = not
-- owned -- plus an amber countdown while the enchant recharges (out of
-- charges). charges = "2/7" for charge-tracked items (Henrik: know at a
-- glance how much is left on the exp bands), red at 0.
--
-- Cascades: probe the BeginMenu binding, never assume (hard rule 2; floatgear
-- field-proved it in this install). Without it the groups fall back to flat
-- sections under dim headers -- the pre-revamp look.
local tpHasMenu = (imgui ~= nil)
    and (type(imgui.BeginMenu) == 'function') and (type(imgui.EndMenu) == 'function');

-- One menu row. key makes the invisible Selectable id unique across the
-- popup's sections and submenus.
local function renderTeleportRow(r, key)
    local id = r.id;
    if id == nil then                              -- not owned: the catalog still knows the icon
        local rec = lookupByName(r.name);
        id = rec and rec.Id or nil;
    end
    icons.renderIcon(id, 18);
    local clickable = (r.owned and r.avail);
    if imgui.Selectable('##tprow' .. key, false) and clickable then
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, r.cmd); end);
        imgui.CloseCurrentPopup();
    end
    -- ", 2/7 charges" tooltip suffix -- only for owned, charge-tracked items
    local chinfo = (r.owned and (r.maxch or 0) > 0 and r.charges ~= nil)
        and string.format(', %d/%d charges', r.charges, r.maxch) or '';
    if imgui.IsItemHovered() then
        if not r.owned then
            imgui.SetTooltip(r.name .. ' -- not owned.');
        elseif not r.avail then
            imgui.SetTooltip(string.format('%s is in %s -- move it to Inventory/Wardrobe to use it.', r.name, tostring(r.where)));
        elseif r.rem > 0 then
            imgui.SetTooltip(string.format('%s: recharging%s -- clicking now equips it and fires the moment it\'s ready  (%s).', r.name, chinfo, r.cmd));
        else
            imgui.SetTooltip(string.format('%s: ready%s  (%s).', r.name, chinfo, r.cmd));
        end
    end
    local col = COL.DIM;                           -- not owned
    if r.owned and r.avail then col = COL.USABLE;  -- lit
    elseif r.owned then col = COL.ERR; end         -- stored: red, as usual
    imgui.SameLine(30);
    imgui.TextColored(col, fmt.esc(r.label));
    imgui.SameLine(150);
    imgui.TextColored(COL.DIM, fmt.esc(r.name));
    if chinfo ~= '' then
        -- charges column: red at 0 -- the reuse countdown alone can't say
        -- "spent"; what 0 means (NPC recharge etc.) is the server's business,
        -- so the number just shows red without claiming a remedy.
        imgui.SameLine(340);   -- clear of the longest names (Federation/Republic Earring) + breathing room
        imgui.TextColored((r.charges > 0) and COL.DIM or COL.ERR,
            string.format('%d/%d', r.charges, r.maxch));
    elseif r.owned and (r.count or 0) > 1 then
        -- stackables (Instant Warp scrolls): the stack size rides the same
        -- column, so you know when you're down to your last one.
        imgui.SameLine(340);
        imgui.TextColored(COL.DIM, 'x' .. tostring(r.count));
    end
    imgui.SameLine(400);   -- state column, past the widest charges text (e.g. "30/30")
    if not r.owned then
        imgui.TextColored(COL.DIM, 'not owned');
    elseif not r.avail then
        imgui.TextColored(COL.ERR, fmt.esc(tostring(r.where)));
    elseif r.rem > 0 then
        local t = math.floor(r.rem);
        imgui.TextColored({ 1.0, 0.72, 0.25, 1.0 }, (t >= 3600)
            and string.format('%d:%02d:%02d', math.floor(t / 3600), math.floor(t / 60) % 60, t % 60)
            or  string.format('%d:%02d', math.floor(t / 60), t % 60));
    else
        imgui.TextColored(COL.USABLE, 'ready');
    end
end

-- A cascading group ("Teleport Earrings" / "Teleport Rings"). No fmt.esc on
-- the menu label -- menu labels are not format strings (floatgear's rule).
-- NO BeginChild anywhere in this chain: a child under a submenu makes ImGui
-- tear the whole popup down when the mouse travels (floatgear, field).
local function renderTeleportGroup(title, list, key)
    if #list == 0 then return; end
    if tpHasMenu then
        if imgui.BeginMenu(title .. '##tp' .. key) then
            for i, r in ipairs(list) do renderTeleportRow(r, key .. i); end
            imgui.EndMenu();
        end
    else
        imgui.TextColored(COL.HEADER, title);
        for i, r in ipairs(list) do renderTeleportRow(r, key .. i); end
    end
end

-- Quick controls (Henrik, 2026-07-20): the popup doubles as the floating
-- quick menu, so two more cascading groups ride under the travel tiers --
-- "Automations" (the Automations-tab list: same rows, same coverage colors;
-- the four with a live switch toggle on click) and "HELM" (the four
-- gathering categories + the idle/auto switches). Toggle and category rows
-- keep the popup OPEN (DontClosePopups) so "pick Mining, flip the idle set
-- ON" is one visit; a binding without the flag closes per click -- degraded,
-- not broken. Modules are pcall-required per frame, NOT captured: the autoui
-- local is declared far BELOW these functions (hard rule 8 -- a forward
-- reference here would be a silent nil global).
local TPQ_KEEP  = ImGuiSelectableFlags_DontClosePopups or 0;
local TPQ_GREEN = { 0.45, 0.90, 0.45, 1.0 };

-- Jump to one automation's panel: show the main window, one-shot select the
-- Automations tab (uihost), land on the detail view, close the popup chain.
-- automationsui is pcall-required, not captured (the autoui local is declared
-- far below -- hard rule 8).
local function tpqOpenPanel(key)
    pcall(function()
        local au = require('dlac\\ui\\automationsui');
        if type(au.openDetail) == 'function' then au.openDetail(key); end
    end);
    pcall(host.selectTab, 'Automations');
    M.visible = true;
    imgui.CloseCurrentPopup();
end

local function renderAutomationsQuick()
    local aok, au = pcall(require, 'dlac\\ui\\automationsui');
    if not aok or type(au) ~= 'table' or type(au.listRows) ~= 'function' then
        imgui.TextColored(COL.ERR, 'automations unavailable.');
        return;
    end
    local rows = au.listRows();
    if #rows == 0 then
        imgui.TextColored(COL.DIM, 'log in to see automations.');
        return;
    end
    -- The live switches, keyed like the rows: state() -> (text, on) for the
    -- second column, flip() = the same call the bars/panels make. Mutual
    -- exclusion between the craft/HELM/fish overlays lives inside the
    -- watchers, never here. Only rows with a switch render at all (Henrik,
    -- 07-20 round 2): the set-driven trio (Iridescence / Obi / Oneiros) has
    -- nothing to flip -- their panels live on the Automations tab itself.
    local SWITCH = {
        craft = {
            tip = 'Craft overlay: wears the selected craft\'s gear while ON (idle only).\nPick craft + goal on the craft bar (/dl craft bar) or the Automations tab.',
            state = function()
                local cw = require('dlac\\feature\\craftwatch');
                if not cw.isEnabled() then return 'off', false; end
                return string.format('ON -- %s (%s)', cw.getCraft() or 'no craft picked', cw.getGoal()), true;
            end,
            flip = function()
                local cw = require('dlac\\feature\\craftwatch');
                cw.setEnabled(not cw.isEnabled());
            end,
        },
        helm = {
            tip = 'HELM idle set: wears the active category\'s gathering gear while ON (idle\nonly). Pick the category in the HELM menu below.',
            state = function()
                local hw = require('dlac\\feature\\helmwatch');
                if not hw.isEnabled() then return 'off', false; end
                return 'ON -- ' .. tostring(hw.getGather() or 'no category'), true;
            end,
            flip = function()
                local hw = require('dlac\\feature\\helmwatch');
                hw.setEnabled(not hw.isEnabled());
            end,
        },
        fish = {
            tip = 'Fishing set: rod, bait and fishing gear while ON (idle only). Pin a rod\nor bait on the fish bar (/dl fish bar).',
            state = function()
                local fw = require('dlac\\feature\\fishwatch');
                if not fw.isEnabled() then return 'off', false; end
                return 'ON', true;
            end,
            flip = function()
                local fw = require('dlac\\feature\\fishwatch');
                fw.setEnabled(not fw.isEnabled());
            end,
        },
        ammo = {
            tip = 'AutoAmmo for the current job: loads enabled ammo for shots and guards\nspecial ammo. Manage the list on its panel.',
            state = function()
                -- Bare ON/off like the rest (Henrik, 07-20 round 2) -- the
                -- job + ammo count still ride the tooltip's Coverage line.
                local aw = require('dlac\\feature\\ammowatch');
                if aw.enabled ~= true then return 'off', false; end
                return 'ON', true;
            end,
            flip = function()
                local aw = require('dlac\\feature\\ammowatch');
                aw.setEnabled(not aw.enabled, select(2, jobFile()));
            end,
        },
        maxmp = {
            tip = 'MaxMP: the banded battery ladder -- max-MP gear follows the precomputed\nplan (/dl plan). Auto-disables on job change; re-enable per job.',
            state = function()
                return (au.maxmpMode() and 'ON' or 'off'), au.maxmpMode();
            end,
            flip = function()
                au.maxmpToggle();
            end,
        },
    };
    for _, r in ipairs(rows) do
        local sw = SWITCH[r.key];
        if sw ~= nil then
            local col = (type(au.levelColor) == 'function') and au.levelColor(r.level, r.max) or COL.DIM;
            -- LEFT-click (Henrik, 2026-07-20): open this automation's panel;
            -- the whole popup chain closes (CloseCurrentPopup from inside a
            -- child menu walks the chain).
            if imgui.Selectable('##tpqa' .. r.key, false, TPQ_KEEP) then
                tpqOpenPanel(r.key);
            end
            -- RIGHT-click: a small on/off context menu. Manual
            -- OpenPopup/BeginPopup (both field-proven in this binding) rather
            -- than the unprobed BeginPopupContextItem. The context popup is a
            -- plain popup, not a child menu, so its CloseCurrentPopup closes
            -- ONLY itself -- the Automations menu stays open showing the flip.
            if imgui.IsItemClicked(1) then
                imgui.OpenPopup('##tpqactx' .. r.key);
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(sw.tip
                    .. '\nLeft-click: open its panel. Right-click: turn it on/off.\nCoverage: '
                    .. tostring(r.txt or ''));
            end
            local txt, on = nil, nil;
            pcall(function() txt, on = sw.state(); end);
            if imgui.BeginPopup('##tpqactx' .. r.key) then
                imgui.TextColored(COL.HEADER, fmt.esc(r.name));
                imgui.Separator();
                if imgui.Selectable((on and 'Turn off' or 'Turn ON') .. '##tpqactxgo' .. r.key,
                                    false, TPQ_KEEP) then
                    pcall(sw.flip);
                    imgui.CloseCurrentPopup();
                end
                imgui.EndPopup();
            end
            imgui.SameLine(8);
            imgui.TextColored(col, fmt.esc(r.name));
            imgui.SameLine(190);
            imgui.TextColored(on and TPQ_GREEN or COL.DIM, fmt.esc(txt or 'off'));
        end
    end
end

local function renderHelmQuick()
    local hok, hw = pcall(require, 'dlac\\feature\\helmwatch');
    if not hok or type(hw) ~= 'table' then
        imgui.TextColored(COL.ERR, 'helmwatch unavailable.');
        return;
    end
    local sel, on, armed;
    pcall(function() sel = hw.getGather(); on = hw.isEnabled(); armed = hw.isAutoHelm(); end);
    -- Top row (Henrik, 07-20 round 2): jump to the full HELM panel -- the
    -- GUI behind this quick menu (Automations tab detail view).
    imgui.Dummy({ 18, 18 });
    imgui.SameLine(0, 6);
    if imgui.Selectable('##tpqhmenu', false, TPQ_KEEP) then tpqOpenPanel('helm'); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Open the HELM panel (Automations tab): ratings, hats, gear ladders and\nboth switches in full.');
    end
    imgui.SameLine(30);
    imgui.TextColored(COL.HEADER, 'HELM menu');
    imgui.Separator();
    for i, g in ipairs({ 'Harvesting', 'Excavation', 'Logging', 'Mining' }) do
        -- Category glyph (helmbar's Image pattern -- these are not item icons);
        -- bright = selected, like the bar. Dummy keeps the columns when the
        -- texture is missing.
        local drew = false;
        pcall(function()
            local hui = require('dlac\\ui\\helmui');
            local tex = (type(hui.texture) == 'function') and hui.texture(g) or nil;
            if tex == nil then return; end
            local ffi = require('ffi');
            imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { 18, 18 },
                { 0, 0 }, { 1, 1 }, (sel == g) and { 1, 1, 1, 1 } or { 1, 1, 1, 0.5 });
            drew = true;
        end);
        if not drew then imgui.Dummy({ 18, 18 }); end
        imgui.SameLine(0, 6);
        if imgui.Selectable('##tpqh' .. i, false, TPQ_KEEP) then
            pcall(function() hw.selectGather(g); end);
        end
        if imgui.IsItemHovered() then
            local helm, surv, bp = 0, 0, false;
            pcall(function() helm, surv, bp = hw.rating(g); end);
            imgui.SetTooltip(string.format(
                '%s -- click to make this the active category (worn while the idle set is ON).\nBreak rating %d%s, Surveyor +%d.',
                g, helm, bp and ' -- BREAK-PROOF' or '/5', surv));
        end
        imgui.SameLine(30);
        imgui.TextColored((sel == g) and COL.USABLE or COL.DIM, g);
        local vp = nil;
        pcall(function() vp = hw.pointsFor(g); end);
        imgui.SameLine(170);
        imgui.TextColored(vp ~= nil and COL.SCORE or COL.DIM,
            'VP ' .. (vp ~= nil and tostring(vp) or '?'));
    end
    imgui.Separator();
    -- The idle switch -- the thing that actually WEARS the gear.
    imgui.Dummy({ 18, 18 });
    imgui.SameLine(0, 6);
    if imgui.Selectable('##tpqhon', false, TPQ_KEEP) then
        pcall(function() hw.setEnabled(not on); end);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(on
            and 'HELM idle set is ON -- gathering gear stays on while idle. Click to turn off.'
            or  'Set HELM Idle: wears your best gathering gear whenever idle, until turned off.\nStarts off each session.');
    end
    imgui.SameLine(30);
    imgui.TextColored(COL.DIM, 'Idle set');
    imgui.SameLine(170);
    imgui.TextColored(on and TPQ_GREEN or COL.DIM, on and 'ON' or 'off');
    -- Auto HELM: the detection-armed overlay (swings / targeting a Point).
    imgui.Dummy({ 18, 18 });
    imgui.SameLine(0, 6);
    if imgui.Selectable('##tpqhauto', false, TPQ_KEEP) then
        pcall(function() hw.setAutoHelm(not armed); end);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(armed
            and 'Auto HELM is armed -- targeting a Point (or swinging) auto-equips that\ncategory\'s gear; normal gear returns after you leave. Click to disarm.'
            or  'Auto HELM: arms detection -- targeting a Point (or swinging) auto-equips\nthat category\'s gear; normal gear returns after you leave.');
    end
    imgui.SameLine(30);
    imgui.TextColored(COL.DIM, 'Auto HELM');
    imgui.SameLine(170);
    local holding = false;
    pcall(function() holding = hw.autoActive(); end);
    imgui.TextColored(armed and TPQ_GREEN or COL.DIM,
        armed and (holding and 'ON -- holding' or 'ON -- armed') or 'off');
end

-- Fishing quick menu (Henrik, 07-20 round 2): panel jump + the idle switch +
-- the current rod/bait/target at a glance. STREAMLINING ONLY -- the fishing
-- scope guard binds here too: no casting, no bite reads, nothing automated.
-- Rod/bait rows are read-only (picking/pinning lives on the fish bar and the
-- panel); '*' marks a manual pin, same glyph as the bar.
local function renderFishQuick()
    local fok, fw = pcall(require, 'dlac\\feature\\fishwatch');
    if not fok or type(fw) ~= 'table' then
        imgui.TextColored(COL.ERR, 'fishwatch unavailable.');
        return;
    end
    -- Top row: the full fishing panel (Automations tab detail view).
    if imgui.Selectable('##tpqfmenu', false, TPQ_KEEP) then tpqOpenPanel('fish'); end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Open the Fishing panel (Automations tab): target fish, rod risk, gear\nladders and the switch in full.');
    end
    imgui.SameLine(8);
    imgui.TextColored(COL.HEADER, 'Fishing menu');
    imgui.Separator();
    -- The idle switch (fishwatch: enabling turns the craft/HELM overlays off).
    local on = false;
    pcall(function() on = fw.isEnabled(); end);
    if imgui.Selectable('##tpqfon', false, TPQ_KEEP) then
        pcall(function() fw.setEnabled(not on); end);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(on
            and 'Fishing set is ON -- rod, bait and fishing gear stay on while idle. Click to\nturn off.'
            or  'Fishing set: wears your rod, bait and best fishing gear while idle, until\nturned off. Turning it on turns the craft/HELM overlays off.');
    end
    imgui.SameLine(8);
    imgui.TextColored(COL.DIM, 'Idle set');
    imgui.SameLine(90);
    imgui.TextColored(on and TPQ_GREEN or COL.DIM, on and 'ON' or 'off');
    -- Read-only state rows: rod / bait (with the bar's pin glyph) + target.
    local PICK_TIP = 'Picked by the heartbeat (best owned, re-ranked ~2s). Pick and pin by hand\non the fish bar (/dl fish bar) or the panel.';
    local PIN_TIP  = 'Pinned by hand (the * ) -- unpinned when it vanishes or the target changes.\nPick and pin on the fish bar (/dl fish bar) or the panel.';
    local rows = {};
    pcall(function()
        local _, rod = fw.getRod();
        local rp = fw.rodPinned();
        rows[#rows + 1] = { 'Rod', rod, rp, rp and PIN_TIP or PICK_TIP };
        local _, bait = fw.getBait();
        local bp = fw.baitPinned();
        rows[#rows + 1] = { 'Bait', bait, bp, bp and PIN_TIP or PICK_TIP };
        local _, tgt = fw.getTarget();
        rows[#rows + 1] = { 'Target', tgt, false,
            'The fish the rod/bait picks aim at. Choose it on the fishing panel\n(or the fish bar).' };
    end);
    for i, s in ipairs(rows) do
        imgui.Dummy({ 0, 0 });
        imgui.SameLine(8);
        imgui.TextColored(COL.DIM, s[1]);
        if imgui.IsItemHovered() then imgui.SetTooltip(s[4]); end
        imgui.SameLine(90);
        imgui.TextColored(s[2] ~= nil and COL.USABLE or COL.DIM,
            fmt.esc(tostring(s[2] or '(none)')) .. (s[3] and ' *' or ''));
    end
end

local function renderTeleportsPopup()
    if not imgui.BeginPopup('##dlac_teleports') then return; end
    imgui.TextColored(COL.HEADER, 'Teleports');
    imgui.SameLine(0, 10);
    imgui.TextColored(COL.DIM, 'click: equip + use when the game says ready');
    imgui.Separator();
    local rows = {};
    pcall(function() rows = useit.menu() or {}; end);
    -- Split into the popup's tiers by the rows' grp tag (useitem owns the tag).
    local top, ears, rings, xps = {}, {}, {}, {};
    for _, r in ipairs(rows) do
        if     r.grp == 'ear'  then ears[#ears + 1]   = r;
        elseif r.grp == 'ring' then rings[#rings + 1] = r;
        elseif r.grp == 'xp'   then xps[#xps + 1]     = r;
        else                        top[#top + 1]     = r; end
    end
    for i, r in ipairs(top) do renderTeleportRow(r, 't' .. i); end
    if #top > 0 then imgui.Separator(); end
    renderTeleportGroup('Teleport Earrings', ears, 'e');
    renderTeleportGroup('Teleport Rings', rings, 'r');
    if #xps > 0 then
        -- Exp rings stay a flat section under the teleports (Henrik);
        -- useitem.menu() already dropped the unowned ones.
        imgui.Separator();
        imgui.TextColored(COL.HEADER, 'Exp rings');
        for i, r in ipairs(xps) do renderTeleportRow(r, 'x' .. i); end
    end
    -- Quick controls (Henrik, 2026-07-20): Automations + HELM ride along as
    -- cascading groups -- the popup is the floating quick menu, not just
    -- travel. Same fallback rule as the teleport groups: no BeginMenu
    -- binding -> flat sections under dim headers.
    imgui.Separator();
    if tpHasMenu then
        if imgui.BeginMenu('Automations##tpqa') then
            pcall(renderAutomationsQuick);
            imgui.EndMenu();
        end
        if imgui.BeginMenu('HELM##tpqh') then
            pcall(renderHelmQuick);
            imgui.EndMenu();
        end
        if imgui.BeginMenu('Fishing##tpqf') then
            pcall(renderFishQuick);
            imgui.EndMenu();
        end
    else
        imgui.TextColored(COL.HEADER, 'Automations');
        pcall(renderAutomationsQuick);
        imgui.TextColored(COL.HEADER, 'HELM');
        pcall(renderHelmQuick);
        imgui.TextColored(COL.HEADER, 'Fishing');
        pcall(renderFishQuick);
    end
    -- Footer: pin/unpin the PF-style floating button. The same menu renders from
    -- the floating button itself, so it is removable from EITHER place.
    imgui.Separator();
    ui._tpFloatBox = ui._tpFloatBox or { false };
    ui._tpFloatBox[1] = (ui._tpFloat == true);
    if imgui.Checkbox('Floating button##tpfloat', ui._tpFloatBox) then
        ui._tpFloat = (ui._tpFloatBox[1] == true);
        ui._flagsDirty = true;
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Pin a small always-on-screen Teleports button (PartyFinder-style).\nDrag its edge to move it. Untick -- here or in the floating menu\nitself -- to remove it. Remembered across sessions.');
    end
    imgui.EndPopup();
end

-- Header buttons, right-aligned. Reload LAC is always shown. Scan/Stage/Commit/Augs are
-- dev-only now that auto-sync keeps gear.lua current, so they appear only in debug mode.
-- Setup shows only while the current job still needs it (or in debug mode). The visible set
-- is measured each frame so the row stays right-aligned no matter which buttons are present.
local function renderHeaderButtons()
    local gap = 4;
    local needSetup = (setup.jobSetupState() ~= 'ok');
    if not needSetup then
        -- dlac-wired but NO profile storage yet: migration is pending, and that
        -- is a setup need too (the popup shows the migrate plan). Once storage
        -- exists the nag ends -- a veteran who keeps a hand-written job file
        -- alongside storage is a supported choice, not a warning state.
        pcall(function()
            local p = require('dlac\\profiles');
            if type(p) == 'table' and not p.storageExists() then needSetup = true; end
        end);
    end

    -- Reload-LAC watcher: the engine stamps a LAC-load generation into
    -- modestate.lua (__loadstamp -- constant across mode changes and engine
    -- self-swaps, new on every real LAC load). When something marked a reload
    -- as needed (ui._lacReloadNeed + the stamp it saw), the Reload LAC button
    -- turns red until the stamp MOVES -- however the reload happens, button or
    -- a command the user types. Throttled to ~1 read/second.
    local function lacLoadStamp()
        local now = os.time();
        if ui._lacStampAt == now then return ui._lacStamp; end
        ui._lacStampAt = now;
        local v = nil;
        pcall(function()
            local base = charBase();
            if base == nil then return; end
            local chunk = loadfile(base .. 'dlac\\modestate.lua');
            if chunk == nil then return; end
            local ok, t = pcall(chunk);
            if ok and type(t) == 'table' and type(t.__loadstamp) == 'string' then v = t.__loadstamp; end
        end);
        ui._lacStamp = v;
        return v;
    end
    local _lacSt = lacLoadStamp();   -- keep the cache warm (marks capture it)
    if ui._lacReloadNeed == true and _lacSt ~= nil and _lacSt ~= ui._lacReloadStamp0 then
        ui._lacReloadNeed, ui._lacReloadStamp0 = nil, nil;
        if type(_augStatus) == 'string' and _augStatus:find('Reload', 1, true) ~= nil then
            _augStatus = 'LuaAshitacast reloaded -- you are live. Build sets in the Sets tab; triggers in the Triggers tab.';
        end
        pcall(function() print('[dlac] LuaAshitacast reload detected -- changes are live.'); end);
    end

    local btns = {};
    do   -- lockstyle window toggle (Henrik's armor icon; left of the Macro book)
        btns[#btns+1] = { w = 26,
          render = function()
              local h = nil; pcall(function() h = require('dlac\\ui\\filetex').handle('lockstyle'); end);
              local clicked = false;
              if h ~= nil then pcall(function() clicked = imgui.ImageButton(h, { 16, 16 }); end);
              else clicked = imgui.Button('LS##hdrls', { 26, 22 }); end
              if imgui.IsItemHovered() then
                  imgui.SetTooltip('Lockstyle boxes -- 30 saved looks PER JOB, applied through LuaAshitacast.\nSave the marked box, import old static lockstyle sets, and\n"OnLoad Lockstyle" re-applies it on every login / job change.');
              end
              if clicked then pcall(function() require('dlac\\feature\\lockstyle').open(); end); end
          end };
    end
    if macrob ~= nil then
        btns[#btns+1] = { w = 26,   -- small book icon (matches the warp button size)
          render = function()
              local h = nil; pcall(function() h = require('dlac\\ui\\filetex').handle('macrobook'); end);
              local clicked = false;
              if h ~= nil then pcall(function() clicked = imgui.ImageButton(h, { 16, 16 }); end);
              else clicked = imgui.Button(macrob.label() .. '##hdrmb', { 26, 22 }); end
              if imgui.IsItemHovered() then
                  imgui.SetTooltip(macrob.label() .. '\n\nMacro book & set for the CURRENT job -- saved per job and applied\nautomatically on login and every job change (replaces the /macro lines\npeople put in profile OnLoad). Jobs you don\'t manage are never touched.');
              end
              if clicked then macrob.open(); end
          end };
    end
    do   -- craft bar toggle (small helmet icon, warp-button size)
        btns[#btns+1] = { w = 26,
          render = function()
              local h = nil; pcall(function() h = require('dlac\\ui\\filetex').handle('craftbar'); end);
              local clicked = false;
              if h ~= nil then pcall(function() clicked = imgui.ImageButton(h, { 16, 16 }); end);
              else clicked = imgui.Button('Cft##hdrcb', { 26, 22 }); end
              if imgui.IsItemHovered() then
                  imgui.SetTooltip('Craft bar -- pick a craft + goal and switch it on to wear that craft\'s\ngear (skill / HQ / NQ). Toggle this floating bar; also /dl craft bar.');
              end
              if clicked then
                  pcall(function() local cw = require('dlac\\feature\\craftwatch'); cw.barVisible = not (cw.barVisible == true); end);
              end
          end };
    end
    if useit ~= nil then
        btns[#btns+1] = { w = 26,
          render = function()   -- FFXI-themed: the Warp Ring icon IS the button --
              -- and while a use is IN FLIGHT it becomes the STOP button: one click
              -- aborts via the same '/dl w|p|t off' the chat hint names.
              local pend = nil;
              pcall(function() pend = (type(useit.pending) == 'function') and useit.pending() or nil; end);
              if pend ~= nil then
                  local clicked = imgui.Button('##hdrtpstop', { 26, 22 });
                  pcall(function()
                      local x, y = imgui.GetItemRectMin();
                      if type(x) == 'table' then y = (x[2] or x.y); x = (x[1] or x.x); end
                      local dl = imgui.GetWindowDrawList();
                      dl:AddCircleFilled({ x + 13, y + 11 }, 8, imgui.GetColorU32({ 0.85, 0.20, 0.20, 1.0 }), 12);
                      dl:AddRectFilled({ x + 9, y + 9 }, { x + 17, y + 13 }, imgui.GetColorU32({ 1, 1, 1, 0.95 }));
                  end);
                  if imgui.IsItemHovered() then
                      imgui.SetTooltip(string.format('ABORT %s  (%s)', tostring(pend.name), tostring(pend.cancel)));
                  end
                  if clicked and pend.cancel ~= nil then
                      pcall(function() AshitaCore:GetChatManager():QueueCommand(1, pend.cancel); end);
                  end
                  return;
              end
              local clicked = false;
              local rec = lookupByName('Warp Ring');
              local id = rec and rec.Id or nil;
              local h = icons.handleOf(id);
              if h ~= nil then
                  -- 16px icon + ImageButton frame padding lands at the 22px row height
                  pcall(function() clicked = imgui.ImageButton(h, { 16, 16 }); end);
              else
                  clicked = imgui.Button('Tele##hdrtp', { 26, 22 });   -- no texture: text fallback
              end
              if imgui.IsItemHovered() then
                  imgui.SetTooltip('Teleports: Instant Warp / Instant Retrace scrolls (used on the spot, no\nequip), Warp / Provenance Ring, Chocobo Whistle, Nexus Cape (to your\nparty leader), Shadow Lord Shirt, the Teleport Earrings / Teleport Rings\nsubmenus, plus your exp rings -- click one to equip it and use it the\nmoment the game says ready (the /dl iw, ir, w, p, c, nexus, shirt, t, xp\ncommands, clickable). Lit = ready, amber = recharging, red = stored,\ndim = not owned. Below the travel tiers: the Automations, HELM and\nFishing quick menus (switch overlays, pick a gathering category, check\nrod/bait -- left-click a row to open its full panel).');
              end
              if clicked then ui._tpOpen = true; end
          end };
    end
    do   -- MAIN-level override for testing/preparing: previews AND the engine follow it
        local _, lvNow = getPlayerInfo();
        local ovr = rawget(_G, 'staticMainLevel');
        local on = (type(ovr) == 'number' and ovr > 0);
        btns[#btns+1] = { l = 'Lv ' .. tostring(lvNow) .. (on and '*' or ''), w = 56,
          tip = 'Preview / test at another MAIN level: the pickers, set previews and the\nlive set flattening all follow it (the engine via /dl set level main).\n* = override active -- gear picks are NOT for your real level right now.',
          fn = function() ui._lvlOpen = true; end };
    end
    btns[#btns+1] =
        { l = 'Reload LAC', w = 104, red = (ui._lacReloadNeed == true),
          tip = 'Reload LuaAshitacast. LAC caches your sets when the profile loads, so after you\ncommit/edit a set (or run Setup) you must reload LAC for the change to take effect.\n\nRED = a change is waiting for a reload. It clears by itself once the reload\nlands -- this button or a command you type, either works.',
          fn = function()
              _augStatus = nil;      -- "Reload LuaAshitacast to apply" is fulfilled by this click
              ui.setsStatus = '';    -- ...and so is the Sets tab's 'replaced "<set>" for <JOB>' line
              refreshOwnedCounts();
              pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/addon reload luashitacast'); end);
          end };
    if sf.flags.debug then
        btns[#btns+1] = { l = 'Scan', w = 52,
            tip = 'Scan your equipment + bags (from the game\'s memory) and print what you own,\nflagging anything not yet in gear.lua. Read-only -- writes nothing. Also refreshes\nthe owned markers shown in these lists.',
            fn = function() callImport('scanAndReport'); refreshOwnedCounts(); end };
        btns[#btns+1] = { l = 'Stage', w = 58,
            tip = 'Scan, then write the items you own that AREN\'T in gear.lua yet to a staging file\n(gear_staging.lua) for review. Your gear.lua is left untouched -- check the staged\nentries first, then Commit them.',
            fn = function() callImport('stage'); end };
        btns[#btns+1] = { l = 'Commit', w = 64,
            tip = 'Merge the staged new items (from Stage) into your gear.lua. Aborts and leaves\ngear.lua untouched if the staging file or the merged result would not parse.',
            fn = function() callImport('commit'); refreshGear(); end };
        btns[#btns+1] = { l = 'Augs', w = 52,
            tip = 'Dump every augmented item you own (name, id, and decoded augment stats) to\naugdump.txt in your dlac folder -- handy for sharing or identifying unknown\naugment ids.',
            fn = function() dumpAugs(); end };
    end
    if needSetup or sf.flags.debug then
        btns[#btns+1] = { l = 'Setup', w = 56, red = needSetup,
            tip = 'Set up this job for dlac. Clicking only shows a PLAN of what will happen,\nin plain words -- nothing is touched until you press Commit in the popup.',
            fn = function()
                -- Build the plan (plain-words, state-dependent); the popup below
                -- renders it and Commit executes. All function-scoped: gearui's
                -- main chunk is at the LuaJIT 200-local cap.
                local base = charBase();
                local jf, abbr = jobFile();
                if base == nil or jf == nil then _augStatus = 'Setup: log in first (no character/job).'; return; end
                local state = setup.jobSetupState();
                local prof = nil;
                pcall(function() local p = require('dlac\\profiles'); if type(p) == 'table' then prof = p; end end);
                local plan = { mode = 'migrate', abbr = abbr, title = 'Set up ' .. abbr .. ' for dlac', lines = {} };
                local L = plan.lines;
                local function add(c, t) L[#L + 1] = { c = c, t = t }; end
                if state == 'nofile' then
                    plan.mode = 'fresh';
                    plan.title = 'First-time setup -- ' .. abbr;
                    add('txt', 'You have no ' .. abbr .. '.lua profile yet. Commit will:');
                    add('txt', '1.  Write ' .. abbr .. '.lua as a small managed shim. LuaAshitacast auto-loads it on every');
                    add('dim', '     job change; it holds NO data and you never need to open it.');
                    add('txt', '2.  Create your profile storage: dlac\\profiles\\Default\\ -- ALL of your sets and');
                    add('dim', '     triggers will live there (share or switch profiles later with /dl profile).');
                    add('txt', '3.  Seed an empty gear inventory (dlac\\gear.lua) -- fill it afterwards with Scan.');
                    add('txt', '4.  Seed the four base sets (Idle / Tp_Default / Resting / Movement, empty) and');
                    add('dim', '     the starter triggers that target them -- everything runs out of the box,');
                    add('dim', '     nothing complains; fill the sets in the Sets tab.');
                    add('txt', 'Nothing that already exists is overwritten.');
                    add('head', 'After Commit: click Reload LAC, then Scan, then build sets in the Sets tab.');
                elseif state == 'ok' and prof ~= nil and prof.storageExists() then
                    plan.mode = 'healthy';
                    plan.title = abbr .. ' is fully set up';
                    add('txt', 'The ' .. abbr .. '.lua shim, profile storage and trigger wiring are all in place.');
                    add('txt', 'Commit only seeds a missing starter sets / trigger file (never overwrites one).');
                else
                    -- 'ffxilac' | 'none' | 'wired' | 'ok' without profile storage:
                    -- ONE standard path. The live <JOB>.lua always ends up the clean
                    -- managed shim; old logic never stays live (Henrik, 2026-07-17).
                    plan.mode = 'migrate';
                    plan.title = 'Move ' .. abbr .. ' (and every other job) to the clean dlac standard';
                    if state == 'ffxilac' then
                        add('txt', 'Your ' .. abbr .. '.lua is an ffxi-lac profile.');
                    elseif state == 'none' then
                        add('txt', 'Your ' .. abbr .. '.lua is a hand-written LuaAshitacast profile.');
                    elseif state == 'wired' then
                        add('txt', 'Your ' .. abbr .. '.lua mixes its own logic with dlac wiring (an old in-place');
                        add('txt', 'conversion, a hand-wired file, or an edited shim).');
                    else
                        add('txt', 'Your jobs are dlac-wired but your data is not in profile storage yet.');
                    end
                    add('head', 'THE STANDARD: the live <JOB>.lua is always a small managed dlac shim -- an old');
                    add('head', 'file with its own equip logic NEVER stays live (two logics fighting over slots');
                    add('head', 'is the mess dlac exists to end). Commit does, for EVERY job file (not just ' .. abbr .. '):');
                    add('head', 'SAFETY: every original is copied to backups\\pre-profiles\\ FIRST and verified');
                    add('head', 'byte-for-byte before anything is rewritten. A first backup is never overwritten');
                    add('head', '(a re-migrated file is saved to a stamped copy beside it instead).');
                    add('txt', '- Your dynamic sets move over verbatim (byte-for-byte).');
                    add('txt', '- Old static sets stay importable: "Copy from" in the Sets tab reads the backup');
                    add('dim', '   (_Priority lists keep their order, so their level scaling survives -- ADR 0008).');
                    add('txt', '- Group tables in your old file stay importable: Triggers tab -> Groups ->');
                    add('dim', '   "Scan my Lua" reads the backup too.');
                    add('txt', '- Hand-written handler code does NOT stay in the live file (it lives on in the');
                    add('dim', '   backup) -- equip behavior is trigger data now.');
                    add('txt', '- Seeds your gear inventory (dlac\\gear.lua) and starter triggers when absent.');
                    add('txt', '- LuaAshitacast reloads automatically afterwards.');
                    add('head', 'The plan, job by job:');
                    local mplan = nil;
                    if prof ~= nil then pcall(function() mplan = prof.currentPlan(); end); end
                    if type(mplan) == 'table' then
                        for _, e in ipairs(mplan) do
                            if e.action == 'skip' then
                                add('dim', e.job .. ':  skip -- ' .. tostring(e.reason));
                            else
                                add('txt', e.job .. ':  migrate');
                                for _, n in ipairs(e.notes or {}) do add('dim', '      - ' .. n); end
                            end
                        end
                    else
                        add('err', '(could not read the per-job plan -- /dl profile migrate shows it in chat)');
                    end
                end
                ui._setupPlan = plan;
                ui._setupOpen = true;
            end };
    end

    local total = 0;
    for i, b in ipairs(btns) do total = total + b.w + (i > 1 and gap or 0); end
    local x = imgui.GetWindowWidth() - total - 12;
    if x < 4 then x = 4; end
    for i, b in ipairs(btns) do
        if i == 1 then imgui.SameLine(x); else imgui.SameLine(0, gap); end
        local red = b.red and ImGuiCol_Button ~= nil;
        if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
        if b.render ~= nil then
            b.render();                                -- self-drawn (icon buttons)
        elseif imgui.Button(b.l .. '##hdr', { b.w, 22 }) then
            b.fn();
        end
        if red then imgui.PopStyleColor(1); end
        if b.tip ~= nil and imgui.IsItemHovered() then imgui.SetTooltip(b.tip); end
    end
    if macrob ~= nil then pcall(macrob.renderPopup); end
    if useit ~= nil then
        if ui._tpOpen then imgui.OpenPopup('##dlac_teleports'); ui._tpOpen = nil; end
        pcall(renderTeleportsPopup);
    end
    if ui._lvlOpen then imgui.OpenPopup('##dlac_lvlovr'); ui._lvlOpen = nil; end
    if imgui.BeginPopup('##dlac_lvlovr') then
        local ovr = rawget(_G, 'staticMainLevel');
        local on = (type(ovr) == 'number' and ovr > 0);
        local live = 0;
        pcall(function() live = gData.GetPlayer().MainJobSync or 0; end);
        local cur = on and ovr or live;
        imgui.TextColored(COL.HEADER, 'Main level override');
        imgui.TextColored(COL.DIM, string.format('live: %d%s', live, on and ('   testing as: ' .. ovr) or '   (no override)'));
        -- sets the ADDON-state global (previews follow instantly) AND queues the
        -- utils command so the LAC-state engine re-flattens at the same level
        local function setLvl(n)
            local v = (n ~= nil) and math.max(1, math.min(75, n)) or 0;
            rawset(_G, 'staticMainLevel', v);
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl set level main ' .. v); end);
        end
        if imgui.SmallButton('-5##lvm5') then setLvl(cur - 5); end
        imgui.SameLine(0, 4);
        if imgui.SmallButton('-1##lvm1') then setLvl(cur - 1); end
        imgui.SameLine(0, 10); imgui.TextColored(COL.USABLE, string.format('%2d', cur)); imgui.SameLine(0, 10);
        if imgui.SmallButton('+1##lvp1') then setLvl(cur + 1); end
        imgui.SameLine(0, 4);
        if imgui.SmallButton('+5##lvp5') then setLvl(cur + 5); end
        imgui.SameLine(0, 14);
        if imgui.SmallButton('back to live##lv0') then setLvl(nil); end
        imgui.EndPopup();
    end

    -- Setup plan popup: what WILL happen, in plain words; nothing runs until
    -- Commit at the bottom. (BeginPopup, not Modal: clicking outside cancels.)
    if ui._setupOpen then imgui.OpenPopup('##dlac_setupplan'); ui._setupOpen = nil; end
    if imgui.BeginPopup('##dlac_setupplan') then
        local p = ui._setupPlan;
        if p == nil then imgui.CloseCurrentPopup(); imgui.EndPopup(); return; end
        imgui.TextColored(COL.HEADER, tostring(p.title));
        imgui.Separator();
        imgui.BeginChild('##dlac_setupplanbody', { 810, math.min(400, 24 + #p.lines * 20) }, false);
        for _, ln in ipairs(p.lines) do
            local col = (ln.c == 'dim' and COL.DIM) or (ln.c == 'head' and COL.SCORE)
                     or (ln.c == 'err' and COL.ERR) or COL.USABLE;
            fmt.textWrapped(col, ln.t);   -- wrapped: the popup stays narrow, lines reflow
        end
        imgui.EndChild();
        imgui.Separator();
        fmt.textWrapped(COL.DIM, 'Nothing has been touched yet. Commit runs the steps above; Cancel closes.');
        local label = (p.mode == 'healthy') and 'Commit (seed triggers)' or 'Commit';
        if imgui.Button(label .. '##dlac_setupgo', { 170, 26 }) then
            ui._setupPlan = nil;
            imgui.CloseCurrentPopup();
            if p.mode == 'migrate' then
                -- The ONE standard path (setupui) -- loud record in chat, exactly
                -- like /dl profile migrate go; status + reload flags via configure{}.
                pcall(function() setup.migrateToCleanProfiles(); end);
            else
                setup.migrateCurrentJob();
            end
        end
        imgui.SameLine(0, 8);
        if imgui.Button('Cancel##dlac_setupno', { 90, 26 }) then
            ui._setupPlan = nil;
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end
end

-- ---------------------------------------------------------------------------
-- Row renderers.
-- ---------------------------------------------------------------------------

-- (qtyTag / nameWidthOf moved to dlac\\gearfmt.lua with the other formatters.)

-- (renderAltRow / renderBrowseRow moved to dlac\equippedui.lua.)

-- The classic 4x4 equipment grid (Main/Sub/Range/Ammo // Head/Neck/Ear1/Ear2 //
-- Body/Hands/Ring1/Ring2 // Back/Waist/Legs/Feet -- EQUIP_SLOTS is already in
-- this order), icon-only boxes like the game's own equip window. Each box is a
-- BUTTON that selects the slot for editing; the item's full info stays on hover.
-- Empty slots show the slot's short name; the selected slot gets a gold box.
-- getText(sl) feeds only the hover line now (the boxes carry no inline text).
local SLOT_BOX = 40;                  -- outer box; the icon fills it minus the frame pad
-- opts (all optional, added for the floating gear window -- old callers pass nothing
-- and keep the exact previous behavior):
--   boxColorOf(sl) -> {r,g,b,a} to override the box color for that slot (pins go red)
--   onRightClick(label) -> called on RMB over a slot. It only REPORTS: OpenPopup and
--     BeginPopup have to share a window scope, and this grid lives inside its own
--     BeginChild, so the caller raises a flag here and opens the popup at ITS level.
--   tight -> boxes touch (equipmon's look): no spacing between them and no padding
--     inside the child, so the grid measures EXACTLY 4*box square and the caller
--     can auto-size a chrome-less window to it.
--   box -> outer box size in px (default SLOT_BOX). The icon and the frame pad
--     scale WITH it, so the grid is one knob wide; at the default it reproduces
--     the old 40/32/4 numbers exactly.
local function renderSlotGrid(idPrefix, gridHeight, selectedLabel, getItemId, getText, onClick, hoverRec, gridW, opts)
    opts = opts or {};
    local gap = opts.tight and 0 or 4;
    local BOX = math.floor(tonumber(opts.box) or SLOT_BOX);
    if BOX < 12 then BOX = 12; end                 -- below this the icon vanishes
    local PAD = math.max(1, math.floor(BOX * 0.1 + 0.5));   -- 4 at BOX=40
    local IMG = BOX - PAD * 2;                              -- 32 at BOX=40
    -- Both vars must be pushed BEFORE BeginChild: WindowPadding is read when the
    -- child window opens, and it is what would otherwise inset the 4x4 inside its
    -- own box and clip the last row.
    if opts.tight then
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 });
    end
    imgui.BeginChild('##' .. idPrefix .. '_grid', { gridW or -1, gridHeight }, false);
    local boxBg = { 0.10, 0.10, 0.13, 1.0 };
    local boxSel = { 0.42, 0.36, 0.16, 1.0 };          -- gold: the slot being edited
    for i, sl in ipairs(EQUIP_SLOTS) do
        local selected = (selectedLabel == sl.label);
        local clicked = false;
        imgui.PushID(idPrefix .. '_' .. sl.label);
        local id = getItemId(sl);
        local handle = icons.handleOf(id);
        local box = (opts.boxColorOf ~= nil) and opts.boxColorOf(sl) or nil;
        if box == nil then box = selected and boxSel or boxBg; end
        if handle ~= nil then
            clicked = imgui.ImageButton(handle, { IMG, IMG }, { 0, 0 }, { 1, 1 }, PAD,
                box, { 1, 1, 1, 1 });
        else
            local vrec = (hoverRec ~= nil) and hoverRec(sl) or nil;
            local isVirt = (vrec ~= nil and vrec.Virtual == true);
            local wheel = math.floor(BOX * 0.7);          -- 28 at BOX=40
            imgui.PushStyleColor(ImGuiCol_Button, box);
            imgui.PushStyleColor(ImGuiCol_Text, COL.LOCKED);
            clicked = imgui.Button(isVirt and ('##vbox' .. sl.label) or sl.short, { BOX, BOX });
            imgui.PopStyleColor(2);
            if isVirt then   -- the element wheel over the button (virtuals have no texture)
                pcall(function()
                    local x, y = imgui.GetItemRectMin();
                    if type(x) == 'table' then y = (x[2] or x.y); x = (x[1] or x.x); end
                    icons.drawElementWheel(wheel, x + (BOX - wheel) / 2, y + (BOX - wheel) / 2);
                end);
            end
        end
        if clicked then onClick(sl.label); end
        if imgui.IsItemHovered() then
            -- RMB: the gearmove pattern, field-confirmed in this client --
            -- IsMouseClicked(1) + IsItemHovered, NOT BeginPopupContextItem (that
            -- one is what failed twice and put right-click on the dead-end list).
            if opts.onRightClick ~= nil and imgui.IsMouseClicked(1) then
                opts.onRightClick(sl.label);
            end
            local r = (hoverRec ~= nil) and hoverRec(sl) or nil;
            if r ~= nil then
                renderItemTooltip(r);
            else
                local extra = (getText ~= nil) and tostring(getText(sl) or '') or '';
                imgui.SetTooltip(sl.label .. ((extra ~= '') and ('  ' .. extra) or '') .. '\nClick to edit this slot.');
            end
        end
        imgui.PopID();
        if i % 4 ~= 0 then imgui.SameLine(0, gap); end
    end
    imgui.EndChild();
    if opts.tight then imgui.PopStyleVar(2); end
end

-- Lockstyle window (own module, hard rule 1): inject the helpers it renders
-- with -- the 4x4 grid above, item icons/tooltips, and the catalog lookup.
-- Function-scoped require: no new chunk local.
pcall(function()
    require('dlac\\feature\\lockstyle').wire{
        slotGrid = renderSlotGrid,
        icon     = icons.renderIcon,
        tooltip  = renderItemTooltip,
        catalog  = lookupByName,
        -- By ID, for the look preview's model lookup. Name can NOT do this job:
        -- the API drops apostrophes, so the catalog says "Arhats Gi" where the
        -- client says "Arhat's Gi". Ids always agree. Builds the index on demand,
        -- so the preview never depends on the enrichment pass having run first.
        catalogById = function(id)
            if id == nil then return nil; end
            buildAllEquip();
            return _allEquipById and _allEquipById[id] or nil;
        end,
        -- "Show gear I don't own" in the picker: the flat catalog list. Already
        -- carries .Slot (flattenGear), so lockstyle filters by slot without
        -- re-walking the Main/Range category nesting.
        allEquip = buildAllEquip,
        -- Owned lookup BY ID, for the same apostrophe reason as catalogById: the
        -- picker must decide "do you own this catalog row" and hand back YOUR
        -- spelling of the name. Matching "Arhats Gi" (catalog) against gear.lua's
        -- "Arhat's Gi" by name would call an owned item unowned.
        ownedById = function(id)
            if id == nil then return nil; end
            buildOwned();
            return _ownedById and _ownedById[id] or nil;
        end,
    };
end);

-- ---------------------------------------------------------------------------
-- Diablo-style Stats panel + shared Name/Level sort control (Phase 3).
-- ---------------------------------------------------------------------------
local STATS_W   = 250;   -- left stats panel width (name column + value column)

-- Fixed grouped stat order. Every stat always renders (0 if absent); present-but-
-- unlisted stats fall under "Other".
-- statdefs: the central stat registry (label / section / aliases). Used by the weights
-- picker (so aliases are searchable) and, over time, the other stat tables below. Guarded.
local statdefs = try("dlac\\data\\statdefs");
has.statdefs = statdefs ~= nil and type(statdefs.list) == 'table';

-- Item-search matching shared by the pickers: comma-separated terms, ALL required
-- ('hmp, refresh' = pieces carrying both). Each term hits on the NAME or on the
-- item's STATS; statdefs resolves aliases per term ('matk' also finds MAB gear).
local function searchCanon(q)
    if q == '' or not has.statdefs or type(statdefs.get) ~= 'function' then return nil; end
    local ok, e = pcall(statdefs.get, q);
    if ok and type(e) == 'table' and type(e.key) == 'string' then
        local c = string.lower(e.key);
        if c ~= q then return c; end
    end
    return nil;
end
local function parseSearch(q)
    local terms = {};
    for t in string.gmatch(q or '', '[^,]+') do
        t = t:match('^%s*(.-)%s*$');
        if t ~= '' then terms[#terms + 1] = { q = t, qc = searchCanon(t) }; end
    end
    return terms;
end
local function itemSearchMatch(rec, terms, level)
    if #terms == 0 then return true; end
    local name = string.lower(tostring(rec.Name or ''));
    local ss = string.lower(fmt.statSummary(rec, level) or '');
    for _, t in ipairs(terms) do
        local hit = string.find(name, t.q, 1, true) ~= nil
            or string.find(ss, t.q, 1, true) ~= nil
            or (t.qc ~= nil and string.find(ss, t.qc, 1, true) ~= nil);
        if not hit then return false; end
    end
    return true;
end

local STAT_GROUPS = {
    { name = 'Attributes', stats = { 'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR' } },
    { name = 'HP/MP',      stats = { 'HP', 'MP', 'HPP', 'MPP', 'Refresh', 'Regen', 'HMP', 'ConserveMP' } },
    { name = 'Offense',    stats = { 'Accuracy', 'Attack', 'RangedAccuracy', 'RangedAttack', 'CriticalHitRate', 'DoubleAttack', 'TripleAttack', 'StoreTP', 'SubtleBlow', 'Haste', 'DualWield' } },
    { name = 'Magic',      stats = { 'MagicAccuracy', 'MagicAttackBonus', 'MagicDefenseBonus', 'FastCast', 'CurePotency', 'Enmity' } },
    { name = 'Defense',    stats = { 'DEF', 'Evasion', 'MagicEvasion' } },
};

-- Stat-weights editor: own module (dlac\weightsui.lua); the Sets weight panel
-- embeds it via wui.editor(). Scoring (weightsActive/scoreOf) stays here.
wui.configure({
    ui = ui, COL = COL, STAT_GROUPS = STAT_GROUPS,
    invalidateCandidates = invalidateCandidates,
    EQUIP_SLOTS = EQUIP_SLOTS,   -- the 4x4 build-slot grid draws from the canonical order
});

-- Data spelling -> canonical listed name, so gear.lua's MATK/MACC land in the right
-- row rather than "Other".
local STAT_ALIAS = {
    MATK = 'MagicAttackBonus', MAB = 'MagicAttackBonus', MagicAttack = 'MagicAttackBonus',
    MACC = 'MagicAccuracy',
    MDB  = 'MagicDefenseBonus', MagicDefense = 'MagicDefenseBonus',
};

local STAT_LISTED = {};
for _, g in ipairs(STAT_GROUPS) do for _, s in ipairs(g.stats) do STAT_LISTED[s] = true; end end

-- Fold a totals table onto canonical (aliased) keys.
local function resolveTotals(totals)
    local out = {};
    for k, v in pairs(totals) do
        local canon = STAT_ALIAS[k] or k;
        out[canon] = (out[canon] or 0) + v;
    end
    return out;
end

-- Grouped stat panel: collapsible sections (open by default, state persisted by
-- imgui), each a two-column list (name | right-aligned value in a fixed value column),
-- fixed order, 0 when absent, then "Other". Zeros are dimmed so real values pop.
-- Optional setBonuses (comboStats' attribution list) captions the gear sets
-- under the groups: active bonuses gold with their deltas (already inside the
-- totals above -- the caption ATTRIBUTES them), partial sets dim with the count
-- still needed. Callers pass it by forwarding wornSetTotals/workingSetTotals'
-- second return value.
local function renderStatsPanel(title, totals, setBonuses)
    imgui.BeginChild('##ffxilac_stats', { STATS_W, -1 }, true);
    imgui.TextColored(COL.HEADER, title);
    imgui.Separator();
    local resolved = resolveTotals(totals);
    local function statLine(name)
        local v = resolved[name] or 0;
        local col = (v ~= 0) and COL.USABLE or COL.DIM;
        imgui.TextColored(col, name);
        local vs = tostring(v);
        imgui.SameLine(STATS_W - 30 - imgui.CalcTextSize(vs));   -- right-aligned value column
        imgui.TextColored(col, vs);
    end
    local function section(name, stats)
        if imgui.CollapsingHeader(name, ImGuiTreeNodeFlags_DefaultOpen) then
            for _, s in ipairs(stats) do statLine(s); end
        end
        imgui.Spacing();   -- blank line between sections
    end
    for _, g in ipairs(STAT_GROUPS) do
        section(g.name, g.stats);
    end
    local others = {};
    for k in pairs(resolved) do if not STAT_LISTED[k] then others[#others + 1] = k; end end
    table.sort(others);
    if #others > 0 then
        section('Other', others);
    end
    if type(setBonuses) == 'table' and #setBonuses > 0 then
        imgui.Separator();
        for _, sb in ipairs(setBonuses) do
            if sb.active then
                imgui.TextColored(COL.SCORE, string.format('Set: %s (%d/%d)',
                    setLabelOf(sb.setId), math.min(sb.count, sb.max or sb.count), sb.max or sb.count));
                local dl = (sb.deltas ~= nil) and fmt.fullStatList(sb.deltas) or '';
                if dl ~= '' then imgui.TextColored(COL.STATS, '  ' .. fmt.esc(dl)); end
            else
                imgui.TextColored(COL.DIM, string.format('Set: %s (%d/%d -- bonus at %d)',
                    setLabelOf(sb.setId), sb.count, sb.max or 0, sb.min or 2));
            end
        end
    end
    imgui.EndChild();
end

-- Shared Name/Level sort combo (default Name; Level = highest first). idSuffix keeps
-- the id unique when two combos can render in one frame (builder + open add-popup).
local function renderSortCombo(idSuffix)
    imgui.TextColored(COL.DIM, 'Sort:'); imgui.SameLine(0, 3);
    imgui.PushItemWidth(70);
    if imgui.BeginCombo('##ffxilac_sort' .. tostring(idSuffix or ''), ui.sortMode or 'Name') then
        if imgui.Selectable('Name',  ui.sortMode == 'Name')  then ui.sortMode = 'Name';  end
        if imgui.Selectable('Level', ui.sortMode == 'Level') then ui.sortMode = 'Level'; end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
end

-- Display-sorted copy of a record list (candidate lists).
local function sortForDisplay(list)
    local out = {};
    for _, r in ipairs(list) do out[#out + 1] = r; end
    if ui.sortMode == 'Level' then
        table.sort(out, function(a, b)
            if (a.Level or 0) ~= (b.Level or 0) then return (a.Level or 0) > (b.Level or 0); end
            return tostring(a.Name) < tostring(b.Name);
        end);
    else
        table.sort(out, function(a, b) return tostring(a.Name) < tostring(b.Name); end);
    end
    return out;
end

-- Display-sorted copy of a working-set item list ({rec,minLevel,maxLevel} wrappers).
local function sortItemsForDisplay(items)
    local out = {};
    for _, it in ipairs(items) do out[#out + 1] = it; end
    if ui.sortMode == 'Level' then
        table.sort(out, function(a, b)
            local la, lb = (a.rec and a.rec.Level) or 0, (b.rec and b.rec.Level) or 0;
            if la ~= lb then return la > lb; end
            return tostring(a.rec and a.rec.Name) < tostring(b.rec and b.rec.Name);
        end);
    else
        table.sort(out, function(a, b)
            return tostring(a.rec and a.rec.Name) < tostring(b.rec and b.rec.Name);
        end);
    end
    return out;
end

-- (Compare panel + Equipped / All Equipment tabs moved to dlac\equippedui.lua;
--  registered as uihost tabs after the services are provided, below.)

-- ---------------------------------------------------------------------------
-- Tab: Sets  --  read/build/edit a dynamic set (ordered list per slot) and commit
-- it to the job file via setmanager. Working model:
--     M.working[slotLabel] = { { rec=<ownedRecord>, minLevel=N, maxLevel=M }, ... }
-- The "current" pick mimics BuildDynamicSets: highest Level <= mainLevel, honouring
-- per-item min/maxLevel.
-- ---------------------------------------------------------------------------

-- gear.lua path for an owned record: gear.<Slot>[.<Category>].<Key>. nil if the
-- record didn't come from gear.lua (no Key) -> such an item can't be committed.
-- Virtual entries (dlac:AutoStaff / dlac:AutoObi) commit as quoted string literals --
-- BuildDynamicSets passes them through and the engine resolves them at equip time.
local function recordPath(rec)
    if rec == nil then return nil; end
    if rec.Virtual == true and type(rec.Name) == 'string' then return string.format('%q', rec.Name); end
    if rec.Key == nil or rec.Slot == nil then return nil; end
    local p = 'gear.' .. rec.Slot;
    if rec.Category ~= nil then p = p .. '.' .. rec.Category; end
    return p .. '.' .. rec.Key;
end

-- A virtual marker's ladder level: the lowest level it can resolve to, from
-- the automations manifest (dispatch.virtualMinLevel -- AutoIridescence with
-- Chatoyant Staff as best owned reads Lv51, not Lv0). 0 = unknown (no
-- manifest / craft-helm-acc families): the old wildcard display, and
-- bestByLevel's old take-the-slot-outright behavior.
local function virtualLevel(name)
    if _dsp ~= nil and type(_dsp.virtualMinLevel) == 'function' then
        local ok, lv = pcall(_dsp.virtualMinLevel, name);
        if ok and type(lv) == 'number' then return lv; end
    end
    return 0;
end

-- Resolve one sets.Dynamic list element (a gear ref, a { gear=ref, minLevel, maxLevel }
-- wrapper, or a Name string) to a working entry. A genuine wrapper has .gear but no
-- .Name -- a plain ref that BuildDynamicSets mutated to carry a stray .gear still has
-- its .Name, so we don't mistake it for a wrapper (and we ignore its stale min/max).
local function resolveSetItem(elem)
    if type(elem) == 'string' then
        if string.lower(string.sub(elem, 1, 5)) == 'dlac:' then   -- virtual slot entry
            return { rec = { Name = elem, Level = virtualLevel(elem), Virtual = true } };
        end
        local rec = _ownedByName and _ownedByName[string.lower(elem)] or nil;
        if rec == nil and type(gear) == 'table' and gear.NameToObject then
            local g = gear.NameToObject[elem];
            if type(g) == 'table' and g.Id ~= nil then rec = _ownedById[g.Id]; end
        end
        return rec and { rec = rec } or nil;
    end
    if type(elem) ~= 'table' then return nil; end

    local ref, minL, maxL, modeC = elem, nil, nil, nil;
    local autoT, remP, accV = nil, nil, nil;   -- Type automation fields (AutoAcc)
    if elem.gear ~= nil and elem.Name == nil then
        ref = elem.gear; minL = elem.minLevel; maxL = elem.maxLevel; modeC = elem.mode;
        autoT = elem.autoType; remP = elem.removePrio; accV = elem.acc;
    end
    -- Wrapper around a STRING gear ref: a gated VIRTUAL entry, exactly how the
    -- Sets tab commits one ({ gear = "dlac:AutoIridescence", mode = "..." }).
    -- Field case: the row VANISHED from the GUI after a reload -- and a commit
    -- from that view would then drop it from the file.
    if type(ref) == 'string' then
        if string.lower(string.sub(ref, 1, 5)) == 'dlac:' then
            return { rec = { Name = ref, Level = virtualLevel(ref), Virtual = true },
                     minLevel = minL, maxLevel = maxL, mode = modeC };
        end
        local rec = _ownedByName and _ownedByName[string.lower(ref)] or nil;
        return rec and { rec = rec, minLevel = minL, maxLevel = maxL, mode = modeC,
                         autoType = autoT, removePrio = remP, acc = accV } or nil;
    end
    if type(ref) ~= 'table' then return nil; end

    local rec = nil;
    if ref.Id ~= nil then rec = _ownedById[ref.Id]; end
    if rec == nil and ref.Name ~= nil then rec = _ownedByName[string.lower(ref.Name)]; end
    if rec == nil and ref.Name ~= nil then     -- not in gear.lua: display-only, no path
        rec = { Name = ref.Name, Level = ref.Level or 0, Id = ref.Id, Jobs = ref.Jobs, Stats = ref.Stats };
    end
    if rec == nil then return nil; end
    return { rec = rec, minLevel = minL, maxLevel = maxL, mode = modeC,
             autoType = autoT, removePrio = remP, acc = accV };
end

-- The profile's raw `sets` table lives in its OWN module (dlac\\profilesets.lua) --
-- gearui's main chunk is at LuaJIT's 200-local cap, so cohesive clusters get their
-- own module (same pattern as triggersui). It reads gProfile.Sets / a global `sets`,
-- falling back to sandbox-running the job file on disk; jobFile is injected once.
local profsets = require("dlac\\gear\\profilesets");
profsets.configure({ jobFile = jobFile });

-- ---------------------------------------------------------------------------
-- Tab: Triggers -- lives in its OWN module (dlac\\triggersui.lua). LuaJIT caps a
-- chunk at 200 LOCAL VARIABLES and gearui's main chunk is close to that cap --
-- add new tabs/features as modules, not as more top-level locals in this file.
-- gearui hands the module its profile/file helpers once, then renders it. Declared
-- HERE (before renderSetsTab) so the Sets tab can call trigui.renderSetOptions.
-- ---------------------------------------------------------------------------
local trigui;
local autoui;         -- ui\automationsui.lua: the Automations tab + manifest machinery
local _modeSetRefs;   -- assigned after modeSetRefs (defined with the Sets machinery below);
                      -- the trigui deps closure above it must not capture a global
do
    -- ONE deps table for both modules: triggersui (Triggers/Groups editor) and
    -- automationsui (the extracted Automations machinery) -- helmui/fishui take
    -- the whole table per call from automationsui, so sharing keeps every
    -- downstream contract identical to the pre-extraction shape.
    local d = {
        ui = ui,   -- the Trigger Monitor toggle rides gearui's persisted view-state
        charBase = charBase, jobFile = jobFile, seedTriggersFile = setup.seedTriggersFile,
        dynamicSetNames = profsets.dynamicSetNames, staticSetNames = profsets.staticSetNames,
        liveSetNames = profsets.liveSetNames,   -- Dynamic + LIVE-file statics (no backup): trigger-target authority
        lookupByName = lookupByName, ownedCounts = owned.counts,  -- automations manifest (owned staves/obis)
        lookupById = lookupById,   -- id-PINNED automation entries (relic stages share one name)
        ownedList = buildOwned,                                   -- max-MP manifest (piece MP values)
        allEquipList = buildAllEquip,                             -- AutoCraft panel: full catalog (owned OR not)
        -- Automation ladders plan equips for RIGHT NOW, so owned-somewhere is
        -- not enough: a stored piece (no copy in Inventory/Wardrobes) is
        -- invisible to LAC's equip, which drops it SILENTLY -- and a staged
        -- winner that never lands blocks every candidate behind it (field
        -- round 3: Radiant Lantern, stored, froze the whole equip queue).
        haveInBags = function(rec)
            return owned.haveInBags(rec) and not owned.isStored(rec);
        end,
        playerJob = function()                                    -- battery job-eligibility (no gData in this state)
            local abbr = nil;
            pcall(function() abbr = JOB_ABBR[AshitaCore:GetMemoryManager():GetPlayer():GetMainJob()]; end);
            return abbr;
        end,
        modeSetRefs = function(n, s)                              -- mode delete: set-entry references (scan / strip)
            if _modeSetRefs == nil then return { refs = {}, touched = {} }; end
            return _modeSetRefs(n, s);
        end,
        renderIcon = icons.renderIcon,                            -- automation detail views (item icons)
        itemTooltip = renderItemTooltip,                          -- hover cards on automation gear lines
        setsRoot = profsets.getSetsRoot,                          -- gearcheck: set contents for the audit
    };
    local ok, m = pcall(require, "dlac\\ui\\triggersui");
    if ok and type(m) == 'table' then
        trigui = m;
        pcall(trigui.init, d);
    else
        pcall(function() print('[dlac] triggersui failed to load: ' .. tostring(m)); end);
    end
    local aok, am = pcall(require, "dlac\\ui\\automationsui");
    if aok and type(am) == 'table' then
        autoui = am;
        pcall(autoui.init, d);
    else
        pcall(function() print('[dlac] automationsui failed to load: ' .. tostring(am)); end);
    end
end

-- Sets-tab "unsaved changes" flag: set true whenever the working set is modified (Auto-build,
-- add/remove/reorder an item, or a copy-from-static seed); cleared when it's committed,
-- (re)loaded from the saved list, deleted, or a fresh New set is started. Drives the red
-- Commit button in renderSetsTab.
local _setDirty = false;

-- Load a dynamic set into the working model (by our 16 slot labels).
local function loadSet(setName)
    M.working = {};
    M.workingSetName = setName;
    ui.setSelected = nil;
    _setDirty = false;              -- freshly (re)loaded from the saved list -> no unsaved changes
    pcall(function()
        local dyn = profsets.getDynamicSets();
        if type(dyn) ~= 'table' then return; end
        local setT = dyn[setName];
        if type(setT) ~= 'table' then return; end
        for _, sl in ipairs(EQUIP_SLOTS) do
            local slotList = setT[sl.label];
            if type(slotList) == 'table' then
                local items = {};
                for _, elem in ipairs(slotList) do
                    local it = resolveSetItem(elem);
                    if it ~= nil then items[#items + 1] = it; end
                end
                if #items > 0 then M.working[sl.label] = items; end
            end
        end
    end);
end

-- The item LAC would wear from a slot's list at mainLevel (highest Level <= mainLevel,
-- honouring per-item min/maxLevel). Mirrors utils.BuildDynamicSets.

-- Preview-side mode check for mode-gated entries: triggersui judges the condition
-- against the LAC-state modestate mirror. Without triggersui, gated entries
-- preview as inactive -- the conservative default.
local entryModeOk = function(mode) return false; end
if trigui ~= nil and type(trigui.entryModeActive) == 'function' then
    entryModeOk = function(mode)
        local ok, r = pcall(trigui.entryModeActive, mode);
        return ok and r == true;
    end
end

-- An entry's mode gate is a string or a LIST (OR). Display form: 'A | B'.
local function modeTagText(m)
    if type(m) == 'table' then return table.concat(m, ' | '); end
    return tostring(m);
end

local function bestByLevel(list, mainLevel)
    if type(list) ~= 'table' then return nil; end
    local best, bestLevel, bestRank = nil, -1, -1;
    local ml = mainLevel or 0;
    -- A virtual entry takes the slot outright -- once the character reaches its
    -- ladder level (rec.Level = the lowest manifest item it resolves to, stamped
    -- by resolveSetItem via virtualLevel; 0 = unknown = the old unconditional
    -- take). Below that, the real items compete and the pick mirrors what
    -- BuildDynamicSets now flattens (Henrik's field case: AutoIridescence at
    -- "Lv0" shadowed the Pilgrim's Wand a leveling WHM actually wears).
    for _, it in ipairs(list) do
        if it.rec ~= nil and it.rec.Virtual == true
           and (tonumber(it.rec.Level) or 0) <= ml then
            return it;
        end
    end
    for _, it in ipairs(list) do
        local rec = it.rec;
        if rec ~= nil and type(rec.Level) == 'number' then
            local minL = it.minLevel or 0;
            local maxL = it.maxLevel or 999;
            -- rank mirrors the engine: active mode-gated entries beat everything;
            -- then a RANGED entry live at this level beats unbounded ones (a range
            -- owns its window); then plain best-by-level. Inactive gates excluded.
            local rank = nil;
            local ranged = (it.minLevel ~= nil or it.maxLevel ~= nil) and 1 or 0;
            if it.mode == nil then rank = ranged;
            elseif entryModeOk(it.mode) then rank = 2 + ranged; end
            if rank ~= nil and rec.Level <= ml and ml >= minL and ml <= maxL
               and (rank > bestRank or (rank == bestRank and rec.Level > bestLevel)) then
                best = it; bestLevel = rec.Level; bestRank = rank;
            end
        end
    end
    return best;
end

-- The PLANNED composition: best-by-level pick per slot (plan data only, nothing
-- live). Shared by the Set-totals panel and the weighted score below.
local function workingComposition(mainLevel)
    local comp = {};
    for _, sl in ipairs(EQUIP_SLOTS) do
        local pick = bestByLevel(M.working[sl.label], mainLevel);
        if pick ~= nil and pick.rec ~= nil then comp[sl.label] = pick.rec; end
    end
    return comp;
end

-- Returns (totals, setBonuses) -- the planned composition through comboStats,
-- so a planned Lava's + Kusha's pair shows its bonus in Set totals (the
-- wornSetTotals twin; same caption plumbing via renderStatsPanel's third arg).
-- Your copies' augments ride ctx.augStats (Henrik's field case: Refresh+1 body
-- native + Refresh+1 legs augment read "+1" here while the score saw +2).
local function workingSetTotals(mainLevel)
    local totals = {};
    local comp = workingComposition(mainLevel);
    if has.gfx then
        local ok, res = pcall(gfx.comboStats, comp,
            { level = mainLevel, augStats = ownedAugStatsMap() });
        if ok and type(res) == 'table' and type(res.stats) == 'table' then
            for k, v in pairs(res.stats) do
                if k ~= 'DMG' and k ~= 'Delay' then totals[k] = v; end
            end
            return totals, res.setBonuses;
        end
    end
    for _, rec in pairs(comp) do   -- fallback: the pre-P1 per-item sum
        local _st = candidateStats(rec, mainLevel);
        if type(_st) == 'table' then
            for k, v in pairs(_st) do
                if type(v) == 'number' and k ~= 'DMG' and k ~= 'Delay' then
                    totals[k] = (totals[k] or 0) + v;
                end
            end
        end
    end
    return totals;
end

-- Weighted score of the working set: ONE whole-composition evaluation -- caps
-- applied to the summed stats, active set bonuses included, augments folded
-- (ctx.augStats, same fold Set totals displays) -- the same objective
-- Auto-build's optimizer maximizes (design #6: one function, one number, zero
-- drift). Falls back to the per-item sum without geareffects.
local function workingWeightedScore(mainLevel)
    local comp = workingComposition(mainLevel);
    if has.gfx then
        local ok, res = pcall(gfx.comboStats, comp,
            { level = mainLevel, augStats = ownedAugStatsMap() });
        if ok and type(res) == 'table' and type(res.stats) == 'table' then
            return scoreOf(res.stats);
        end
    end
    local total = 0;
    for _, rec in pairs(comp) do total = total + scoreOfItem(rec, mainLevel); end
    return total;
end

-- Build setmanager's ORDERED slots array from the working model (non-empty slots only).
local function buildCommitSlots()
    local slots = {};
    for _, sl in ipairs(EQUIP_SLOTS) do
        local list = M.working[sl.label];
        if type(list) == 'table' and #list > 0 then
            local items = {};
            for _, it in ipairs(list) do
                local path = recordPath(it.rec);
                if path ~= nil then
                    local entry = { path = path };
                    if it.minLevel ~= nil then entry.minLevel = it.minLevel; end
                    if it.maxLevel ~= nil then entry.maxLevel = it.maxLevel; end
                    if it.mode ~= nil then entry.mode = it.mode; end
                    if it.autoType ~= nil then
                        -- Type automation: bake the piece's ACC (base stats +
                        -- your copy's augments) into the wrapper -- the seeded
                        -- engine has no catalog to look it up at equip time.
                        entry.autoType = it.autoType;
                        entry.removePrio = it.removePrio or 1;
                        local st = effStats(it.rec, nil);
                        local ag = (it.rec ~= nil and it.rec.Id ~= nil) and ownedAugStatsMap()[it.rec.Id] or nil;
                        entry.acc = math.floor(((type(st) == 'table' and tonumber(st.Accuracy)) or 0)
                                             + ((type(ag) == 'table' and tonumber(ag.Accuracy)) or 0));
                    end
                    items[#items + 1] = entry;
                end
            end
            if #items > 0 then slots[#slots + 1] = { name = sl.label, items = items }; end
        end
    end
    return slots;
end

-- A deleted mode's SET references (triggersui's delete-with-references window).
-- Scans every dynamic set for entries gated on the mode ('X' or 'X:Value', alone
-- or in a mode list). strip=true rewrites the touched sets through the normal
-- commit path: an entry gated ONLY on this mode is deleted (it existed for it);
-- a list gate just loses the dead name. The Sets-tab working state is borrowed
-- for the scan and restored, so an in-progress edit survives.
local function modeSetRefs(modeName, strip)
    local out = { refs = {}, touched = {} };
    local target = string.lower(tostring(modeName or ''));
    if target == '' then return out; end
    local function matches(m)
        local s = string.lower(tostring(m));
        return s == target or string.sub(s, 1, #target + 1) == (target .. ':');
    end
    local _, job = jobFile();
    local keepW, keepN, keepSel, keepDirty = M.working, M.workingSetName, ui.setSelected, _setDirty;
    pcall(function()
        for _, setName in ipairs(profsets.dynamicSetNames()) do
            loadSet(setName);
            local changed = false;
            for lbl, list in pairs(M.working) do
                for i = #list, 1, -1 do
                    local it = list[i];
                    if it.mode ~= nil then
                        local gates = (type(it.mode) == 'table') and it.mode or { it.mode };
                        local kept, hit = {}, false;
                        for _, m in ipairs(gates) do
                            if matches(m) then hit = true; else kept[#kept + 1] = m; end
                        end
                        if hit then
                            out.refs[#out.refs + 1] = {
                                set = setName, slot = lbl,
                                item = (it.rec ~= nil and it.rec.Name) or '?',
                                gone = (#kept == 0),
                            };
                            if strip then
                                if #kept == 0 then table.remove(list, i);
                                else it.mode = (#kept == 1) and kept[1] or kept; end
                                changed = true;
                            end
                        end
                    end
                end
            end
            if strip and changed and job ~= nil and has.setmgr then
                local ok = nil;
                pcall(function() ok = setmgr.commitSet(job, setName, buildCommitSlots()); end);
                if ok == true then out.touched[#out.touched + 1] = setName; end
            end
        end
    end);
    if strip and #out.touched > 0 then profsets.invalidate(); end
    M.working, M.workingSetName, ui.setSelected, _setDirty = keepW, keepN, keepSel, keepDirty;
    table.sort(out.touched);
    -- A stripped set that is ALSO loaded in the builder (with no unsaved edits)
    -- would keep showing the dead gates: re-load it from the rewritten file. A
    -- dirty working copy is the user's -- left alone.
    if strip and keepN ~= nil and not keepDirty then
        for _, s in ipairs(out.touched) do
            if s == keepN then loadSet(keepN); ui.setSelected = keepSel; break; end
        end
    end
    return out;
end
_modeSetRefs = modeSetRefs;

-- Auto-build the working set from stat weights. Dynamic ON = a level-scaling list per
-- slot (keep an item only if it out-scores every kept lower-Level item; order Level
-- asc). OFF = the single best scorer usable now. Paired slots (Ear/Ring) ladder as a
-- PAIR in dynamic mode: one running top-2 walk (gearoptim.pairLadders) fills both
-- physical slots with disjoint chains, so the second-best piece is worn, not benched.
local function autoBuild(job, level)
    local dyn = (ui.setsDynamic[1] == true);
    -- "Build as lv.75" must actually reach Auto-build: when the optimizer flag is set, pick
    -- candidates as if at MAX_LEVEL (item level cap lifted; the JOB restriction inside
    -- candidatesForSlot still applies). Otherwise use the character's real level.
    local useLevel = setBuildLevel(level);   -- "Build as lv.75" lifts the item-level cap
    local oc = owned.counts();
    local built = {};

    -- Which slots to FILL: the per-set build-slot mask (the weights window's 4x4
    -- grid). Unmarked slots are left exactly as the working set has them --
    -- weapons default unmarked, so Auto-build never resets TP unless asked to.
    -- Fallback (optimizer missing): the same weapons-off default, inline.
    local mask = nil;
    if has.optim and type(optim.getSlotMask) == 'function' then
        local okm, m = pcall(optim.getSlotMask);
        if okm and type(m) == 'table' then mask = m; end
    end
    if mask == nil then
        mask = {};
        for _, sl in ipairs(EQUIP_SLOTS) do
            if sl.gear ~= 'Main' and sl.gear ~= 'Sub' and sl.gear ~= 'Range' then
                mask[sl.label] = true;
            end
        end
    end

    -- Stage 1: candidate pools per label. Sub is resolved later (its pool needs
    -- the built Main for the pairing rule).
    local pools = {};
    for _, sl in ipairs(EQUIP_SLOTS) do
        if mask[sl.label] == true and sl.gear ~= 'Sub' then
            pools[sl.label] = candidatesForSlot(sl.gear, job, useLevel);   -- job+level filtered
        end
    end

    -- Stage 2: JOINT pick per label. The optimizer maximizes the SET total with
    -- the weight caps applied to the summed stats (gearoptim.optimizePicks), so
    -- cap budget goes to the pieces that bring the most alongside it, and a slot
    -- whose candidates only duplicate already-capped stats stays empty. Paired
    -- slots may reuse an Id only when you own two copies.
    local jointPick = nil;
    -- Gear-set crediting for the joint pick + the Sub marginal call (P3): the
    -- optimizer counts set pieces across its assignment and folds active tier
    -- bonuses into the capped objective, with seeded restarts so a pair whose
    -- pieces are individually worthless still gets found.
    local fx = has.gfx and { setsOf = gfx.setsOf, setTier = gfx.setTier } or nil;
    if has.optim and type(optim.optimizePicks) == 'function' and weightsActive() then
        local op = {};
        for label, cands in pairs(pools) do
            local arr = {};
            for _, r in ipairs(cands) do
                -- candidateStats, not bare effStats: your copy's augments weigh
                -- in here exactly as they do in scoreOfItem's per-item sorts.
                arr[#arr + 1] = { stats = candidateStats(r, useLevel) or {}, ref = r };
            end
            if #arr > 0 then op[label] = arr; end
        end
        local ok, res = pcall(optim.optimizePicks, op, nil, {
            -- Two picks are the SAME physical item when they are the same record,
            -- share an Id, or share a NAME (legacy gear.lua duplicates -- /dl dedupe
            -- fodder -- must not double a ring you own once). Coexisting then needs
            -- two owned copies; unknown Id counts as one copy (conservative).
            conflict = function(a, b)
                if a == b or (a.Id ~= nil and a.Id == b.Id)
                   or string.lower(tostring(a.Name or '?')) == string.lower(tostring(b.Name or '??')) then
                    local copies = (a.Id ~= nil) and (oc[a.Id] or 0) or 1;
                    return copies < 2;
                end
                return false;
            end,
            effects = fx,
        });
        if ok and type(res) == 'table' and type(res.picks) == 'table' then
            jointPick = {};
            for label, ci in pairs(res.picks) do jointPick[label] = op[label][ci].ref; end
        end
    end

    -- Stage 3: build each slot's list in EQUIP_SLOTS order (Main before Sub).
    -- Unmarked slots are preserved FIRST (not in loop order), so a paired slot
    -- being rebuilt sees its partner's kept list no matter which of the two
    -- labels EQUIP_SLOTS visits first.
    for _, sl in ipairs(EQUIP_SLOTS) do
        if mask[sl.label] ~= true and M.working[sl.label] ~= nil then
            built[sl.label] = M.working[sl.label];
        end
    end
    local pairDone = {};   -- labels the pair-aware dynamic builder already filled
    for _, sl in ipairs(EQUIP_SLOTS) do
        if mask[sl.label] ~= true or pairDone[sl.label] == true then goto continue; end
        -- Dynamic PAIRED slots with BOTH halves being rebuilt: one running top-2
        -- walk (gearoptim.pairLadders) fills both chains. Building slot 1's full
        -- ladder and then barring slot 2 from everything in it starved slot 2
        -- whenever each upgrade beat the last (field case: Curates' + Roundel
        -- earrings under Cure Potency weights both queued on Ear1, Ear2 empty).
        local pairWith = PAIR_OF[sl.label];
        if dyn and pairWith ~= nil and mask[pairWith] == true
           and has.optim and type(optim.pairLadders) == 'function' then
            local ds = {};
            for _, r in ipairs(pools[sl.label] or {}) do
                ds[#ds + 1] = { ref = r, score = scoreOfItem(r, useLevel), level = r.Level or 0,
                                copies = (r.Id ~= nil) and (oc[r.Id] or 0) or 1,
                                id = r.Id, name = r.Name,
                                breaks = (has.lscale and type(lscale.thresholds) == 'function')
                                     and lscale.thresholds(r.Id) or nil };
            end
            local pins = {};
            if jointPick ~= nil then
                for _, lbl in ipairs({ sl.label, pairWith }) do
                    local j = jointPick[lbl];
                    if j ~= nil then
                        for _, d in ipairs(ds) do
                            if d.ref == j then pins[#pins + 1] = d; break; end
                        end
                    end
                end
            end
            -- Banded pair ladders first (the levelLadder twin: value re-scored at
            -- every band edge, between-level windows at breakpoints); the classic
            -- static top-2 walk stays as the fallback.
            local okp, cA, cB;
            if type(optim.pairLevelLadders) == 'function' then
                okp, cA, cB = pcall(optim.pairLevelLadders, ds, {
                    cap = useLevel,
                    scoreAt = function(ref, L) return scoreOfItem(ref, L); end,
                    pins = pins,
                });
            end
            if not (okp and type(cA) == 'table' and type(cB) == 'table') then
                okp, cA, cB = pcall(optim.pairLadders, ds, { pins = pins });
            end
            if okp and type(cA) == 'table' and type(cB) == 'table' then
                local lA, lB = {}, {};
                for _, d in ipairs(cA) do lA[#lA + 1] = { rec = d.ref, minLevel = d.minLevel, maxLevel = d.maxLevel }; end
                for _, d in ipairs(cB) do lB[#lB + 1] = { rec = d.ref, minLevel = d.minLevel, maxLevel = d.maxLevel }; end
                if #lA > 0 then built[sl.label] = lA; end
                if #lB > 0 then built[pairWith] = lB; end
                pairDone[sl.label] = true;
                pairDone[pairWith] = true;
                goto continue;
            end
        end
        local cands = pools[sl.label];
        -- Sub: full pool (shields/grips + 1H weapons), then keep only picks legal
        -- with the Main we already built (Main precedes Sub). Equip-correct: the
        -- auto-build answers "best usable now", so the DW gate applies.
        if sl.gear == 'Sub' then
            local mp = bestByLevel(built['Main'], useLevel);
            cands = subFilter(subCandidatePool(job, useLevel), mp and mp.rec or nil, job, useLevel);
            -- Joint marginal pick for Sub: everything already chosen is the fixed
            -- background, so a Sub that only re-adds capped stats stays home --
            -- while baseComposition pre-loads the chosen pieces' SET counts, so a
            -- grip/shield that completes a set is credited its bonus (credit
            -- added, the offered pool never narrowed -- the Sub HARD RULE).
            if jointPick ~= nil and #cands > 0 then
                local arr, bg = {}, {};
                for _, r in ipairs(cands) do arr[#arr + 1] = { stats = candidateStats(r, useLevel) or {}, ref = r }; end
                for _, rec in pairs(jointPick) do bg[#bg + 1] = candidateStats(rec, useLevel) or {}; end
                local sfx = nil;
                if fx ~= nil then
                    sfx = { setsOf = fx.setsOf, setTier = fx.setTier, baseComposition = jointPick };
                end
                local ok, res = pcall(optim.optimizePicks, { Sub = arr }, nil, { baseStats = bg, effects = sfx });
                if ok and type(res) == 'table' and type(res.picks) == 'table' then
                    jointPick.Sub = (res.picks.Sub ~= nil) and arr[res.picks.Sub].ref or nil;
                end
            end
        end
        -- Paired slot whose partner is NOT being rebuilt alongside it (partner
        -- unmasked, or non-dynamic mode): a single-copy item anywhere in the
        -- partner's FINAL list must not appear anywhere in THIS slot's list --
        -- the level flatten walks each chain independently, so only DISJOINT
        -- chains can never resolve both slots to the same piece. Matched by Id
        -- AND name (legacy duplicate entries). Both-halves-dynamic pairs never
        -- reach this: pairLadders above builds them disjoint by construction.
        if cands ~= nil then
            local other = PAIR_OF[sl.label];
            if other ~= nil and built[other] ~= nil then
                local blkId, blkName = {}, {};
                for _, it in ipairs(built[other]) do
                    local r = it.rec;
                    if r ~= nil and (r.Id == nil or (oc[r.Id] or 0) < 2) then
                        if r.Id ~= nil then blkId[r.Id] = true; end
                        blkName[string.lower(tostring(r.Name or '?'))] = true;
                    end
                end
                if next(blkId) ~= nil or next(blkName) ~= nil then
                    local f = {};
                    for _, r in ipairs(cands) do
                        if not (r.Id and blkId[r.Id])
                           and not blkName[string.lower(tostring(r.Name or '?'))] then
                            f[#f + 1] = r;
                        end
                    end
                    cands = f;
                end
            end
        end
        if cands ~= nil and #cands > 0 then
            local jp = (jointPick ~= nil) and jointPick[sl.label] or nil;
            -- The pair's chain may have claimed the joint pick (it sat as one of
            -- the pair's fallback rungs): the filtered pool is authoritative, so
            -- the pick yields and this slot keeps its own untrimmed ladder.
            if jp ~= nil then
                local inPool = false;
                for _, r in ipairs(cands) do if r == jp then inPool = true; break; end end
                if not inPool then jp = nil; end
            end
            if dyn then
                -- Banded ladder (gearoptim.levelLadder): candidates are re-scored at
                -- every level where value can change (adoption + levelstats
                -- thresholds), so a piece whose worth DECAYS mid-ladder (Garrison
                -- Tunica +1: Refresh+1 dies past Lv.50) gets an explicit
                -- between-level window and the next-best piece takes over. Monotone
                -- slots come back as the classic unranged chain. Joint rule
                -- unchanged: rungs at/above the joint pick's level give way.
                local ladder = nil;
                if has.optim and type(optim.levelLadder) == 'function' then
                    local litems = {};
                    for _, r in ipairs(cands) do
                        litems[#litems + 1] = { ref = r, level = r.Level or 0,
                            breaks = (has.lscale and type(lscale.thresholds) == 'function')
                                 and lscale.thresholds(r.Id) or nil };
                    end
                    local okl, lad = pcall(optim.levelLadder, litems, {
                        cap = useLevel,
                        scoreAt = function(ref, L) return scoreOfItem(ref, L); end,
                        joint = jp,
                    });
                    if okl and type(lad) == 'table' then
                        ladder = {};
                        for _, e in ipairs(lad) do
                            ladder[#ladder + 1] = { rec = e.ref, minLevel = e.minLevel, maxLevel = e.maxLevel };
                        end
                    end
                end
                if ladder ~= nil then
                    if #ladder > 0 then built[sl.label] = ladder; end
                else
                    -- Fallback (gearoptim absent): the classic single-level chain.
                    local byLevel = {};
                    for _, r in ipairs(cands) do byLevel[#byLevel + 1] = r; end
                    table.sort(byLevel, function(a, b)
                        if (a.Level or 0) ~= (b.Level or 0) then return (a.Level or 0) < (b.Level or 0); end
                        return scoreOfItem(a, useLevel) > scoreOfItem(b, useLevel);
                    end);
                    -- Seed at 0 (not -inf): keep an item only when it actually scores > 0 on the
                    -- weighted stats, so a 0-value item is never kept just for being the lowest level.
                    local kept, bestScore = {}, 0;
                    for _, r in ipairs(byLevel) do
                        local sc = scoreOfItem(r, useLevel);
                        if sc > bestScore then kept[#kept + 1] = { rec = r }; bestScore = sc; end
                    end
                    -- The JOINT pick caps the ladder: rungs at/above its level give way
                    -- (they would win the level flatten and undo the set-level choice);
                    -- lower rungs stay as leveling fallbacks. A joint EMPTY leaves the
                    -- ladder alone -- it still earns its keep below the build level.
                    if jp ~= nil then
                        local trimmed = {};
                        for _, it in ipairs(kept) do
                            if (it.rec.Level or 0) < (jp.Level or 0) and it.rec ~= jp then trimmed[#trimmed + 1] = it; end
                        end
                        trimmed[#trimmed + 1] = { rec = jp };
                        kept = trimmed;
                    end
                    if #kept > 0 then built[sl.label] = kept; end
                end
            else
                if jointPick ~= nil then
                    -- Set-level choice: fill only what the joint optimizer chose.
                    if jp ~= nil then built[sl.label] = { { rec = jp } }; end
                else
                    -- No weights active: per-item greedy (score > 0 to fill).
                    local best, bestSc = nil, 0;
                    for _, r in ipairs(cands) do
                        local sc = scoreOfItem(r, useLevel);
                        if sc > bestSc then bestSc = sc; best = r; end
                    end
                    if best ~= nil then built[sl.label] = { { rec = best } }; end
                end
            end
        end
        ::continue::
    end
    M.working = built;
    _setDirty = true;   -- Auto-build modified the working set -> unsaved changes
    -- Report counts to the caller (the button formats the status line -- setStatus
    -- is defined further down, out of this function's scope).
    local nSlots, nRows = 0, 0;
    for _, list in pairs(built) do nSlots = nSlots + 1; nRows = nRows + #list; end
    return nSlots, nRows;
end

local function setStatus(msg, isErr)
    ui.setsStatus = msg or '';
    ui.setsStatusErr = (isErr == true);
    ui.setsStatusAt = os.clock();   -- stamp for the 5s auto-expiry (see the render site)
end

-- Resolve a source set into the working model (slotLabel -> { entry, ... }), owned/known
-- gear only -- the shared core of every "Copy from" flow. No side effects: the callers
-- decide whether to load the result into M.working (single copy) or feed it straight to
-- buildCommitSlots for a new set (the "New set(s)" batch). Two source kinds:
--
--   workingFromDynamic(name)  -> working                 (another Dynamic set)
--   workingFromStatic(name)   -> working, notBestFirst   (a legacy static set)
--
-- The static path routes through the pinned pure transform in dlac\gear\setimport (the
-- headless suite covers its ordering / best-first rules); notBestFirst names the slots
-- whose candidate order diverges from LAC's first-in-list (ADR 0008), for the caller's
-- per-slot chat warning.
local function workingFromDynamic(srcName)
    local built = {};
    pcall(function()
        local dyn = profsets.getDynamicSets();
        local setT = (type(dyn) == 'table') and dyn[srcName] or nil;
        if type(setT) ~= 'table' then return; end
        for _, sl in ipairs(EQUIP_SLOTS) do
            local slotList = setT[sl.label];
            if type(slotList) == 'table' then
                local items = {};
                for _, elem in ipairs(slotList) do
                    local it = resolveSetItem(elem);
                    if it ~= nil then items[#items + 1] = it; end
                end
                if #items > 0 then built[sl.label] = items; end
            end
        end
    end);
    return built;
end

local function workingFromStatic(srcName)
    local working, notBest = {}, {};
    pcall(function()
        local simport = require('dlac\\gear\\setimport');   -- function-scoped: gearui is near the 200-local cap
        local S = profsets.getSetsRoot();
        if type(S) ~= 'table' then return; end
        local setT = S[srcName];
        if type(setT) ~= 'table' then return; end
        local r = simport.importStaticSet(setT, EQUIP_SLOTS, resolveSetItem);
        working, notBest = r.working, r.notBestFirst;
    end);
    return working, notBest;
end

-- #(a working table): count filled slots (working is keyed by label, not an array).
local function countFilledSlots(working)
    local n = 0;
    for _, list in pairs(working) do
        if type(list) == 'table' and #list > 0 then n = n + 1; end
    end
    return n;
end

-- Copy a static (non-Dynamic) set's slots INTO the currently-selected dynamic set,
-- keeping that set's name (issue #15 / ADR 0008). No longer spawns a set named after
-- the source. FULL-REPLACE: the target becomes the static's contents; slots the static
-- doesn't define are cleared. Candidate ORDER is carried verbatim, so a priority list
-- keeps its order; dlac still equips the highest-item-Level candidate (ADR 0008), which
-- diverges from LAC's first-in-list only for a not-best-first slot -- those are named in
-- a per-slot chat warning. The pure transform (static set + resolver -> working lists +
-- not-best-first slots) lives in dlac\gear\setimport so the headless suite can pin it.
local function doCopyFromStatic(srcName)
    local target = M.workingSetName;
    local working, notBest = workingFromStatic(srcName);
    local result = { working = working, notBestFirst = notBest, slotCount = countFilledSlots(working) };
    if result.slotCount > 0 then
        M.working = result.working;   -- FULL-REPLACE: undefined slots are gone
        ui.setSelected = nil;
        _setDirty = true;             -- copied into the set -> unsaved changes to commit
        -- Per-slot warning for any slot NOT ordered best-first (highest item-Level
        -- first) -- the one case dlac's highest-Level pick diverges from LAC's
        -- first-in-list (ADR 0008). Loud, per hard rule 12: a silent behaviour change
        -- is the failure mode, not the divergence itself.
        for _, label in ipairs(result.notBestFirst) do
            pcall(print, string.format('[dlac] Copy from static "%s": slot %s is not ordered best-first (highest item-Level first) -- dlac equips the highest-Level candidate, so its pick may differ from the first in your list. Reorder the slot if you meant strict priority.', srcName, label));
        end
        local warnNote = (#result.notBestFirst > 0)
            and string.format('  %d slot(s) not best-first -- see chat.', #result.notBestFirst) or '';
        setStatus(string.format('Copied static "%s" into "%s" (%d slots -- whole set replaced). Edit, then Commit.%s',
            srcName, target, result.slotCount, warnNote), false);
    else
        -- Nothing resolved to owned/known gear: leave the target untouched rather than
        -- silently wipe the player's work on a copy that produced nothing (hard rule 12).
        setStatus(string.format('Static set "%s" has no owned/known items to copy (blank, or names not in gear.lua). "%s" left unchanged.',
            srcName, target), true);
    end
end

-- Entry point from the Copy from window: refuse without a target, confirm an
-- overwrite, else copy straight in. The overwrite modal is rendered in renderSetsTab.
local function copyFromStaticSet(srcName)
    if M.workingSetName == nil or M.workingSetName == '' then
        setStatus('Create a set first (have a dlac set open), then copy the static set into it.', true);
        return;
    end
    -- Non-empty target -> confirm before anything changes (cancel / click-away aborts).
    local filled = 0;
    for _, list in pairs(M.working) do
        if type(list) == 'table' and #list > 0 then filled = filled + 1; end
    end
    if filled > 0 then
        ui._copyConfirm = { src = srcName, target = M.workingSetName, filled = filled, kind = 'static' };
        ui._copyConfirmOpen = true;   -- one-shot OpenPopup (see renderSetsTab)
        return;
    end
    doCopyFromStatic(srcName);
end

-- Copy another DYNAMIC set's slots INTO the selected set (Henrik 2026-07-20:
-- the Copy from window offers dynamic sources beside the legacy statics).
-- Same FULL-REPLACE contract as the static copy; the source set is untouched.
local function doCopyFromDynamic(srcName)
    local target = M.workingSetName;
    local built = workingFromDynamic(srcName);
    local nSlots = countFilledSlots(built);
    if nSlots > 0 then
        M.working = built;   -- FULL-REPLACE: slots the source doesn't fill are cleared
        ui.setSelected = nil;
        _setDirty = true;
        setStatus(string.format('Copied dynamic "%s" into "%s" (%d slots -- whole set replaced). Edit, then Commit.',
            srcName, target, nSlots), false);
    else
        setStatus(string.format('Dynamic set "%s" has nothing to copy (empty, or its items are not resolvable). "%s" left unchanged.',
            srcName, target), true);
    end
end

local function copyFromDynamicSet(srcName)
    if M.workingSetName == nil or M.workingSetName == '' then
        setStatus('Create or pick a set first, then copy into it.', true);
        return;
    end
    if srcName == M.workingSetName then
        setStatus('That IS the selected set -- pick a different source.', true);
        return;
    end
    local filled = 0;
    for _, list in pairs(M.working) do
        if type(list) == 'table' and #list > 0 then filled = filled + 1; end
    end
    if filled > 0 then
        ui._copyConfirm = { src = srcName, target = M.workingSetName, filled = filled, kind = 'dynamic' };
        ui._copyConfirmOpen = true;
        return;
    end
    doCopyFromDynamic(srcName);
end

-- "Copy from" > "New set(s)" mode: create a fresh dynamic set for EACH marked source,
-- kept under its source name -- migrate many legacy statics (or duplicate dynamics) in
-- one click, no naming a set by hand for each. A name already in use gains a '_Copy'
-- suffix (dlac\gear\setimport.resolveNewSetNames -- the same plan the popup warns from).
-- Each source is resolved with YOUR owned gear and committed straight into <JOB>.lua
-- (a backup per commit, like Auto-Build All), then ONE '/dl sets reload'. The panel's
-- in-progress working set is borrowed for the build and restored, so an uncommitted edit
-- survives untouched. `sources` = ordered array of { name, kind = 'static'|'dynamic' }.
local function copyAsNewSets(job, sources)
    if not has.setmgr then setStatus('setmanager unavailable.', true); return; end
    if job == nil or job == '' then setStatus('Unknown job (are you logged in?).', true); return; end
    if type(sources) ~= 'table' or #sources == 0 then
        setStatus('Mark at least one set to import first.', true); return;
    end
    local simport = require('dlac\\gear\\setimport');
    local plan = simport.resolveNewSetNames(sources, profsets.dynamicSetNames());
    -- Borrow the panel's working state (mirror autoBuildAll / modeSetRefs) so a commit
    -- loop that overwrites M.working leaves the user's in-progress edit intact.
    local keepW, keepN, keepSel, keepDirty = M.working, M.workingSetName, ui.setSelected, _setDirty;
    local made, blank, failed, renamed = 0, 0, 0, 0;
    for _, p in ipairs(plan) do
        local built = (p.kind == 'dynamic') and workingFromDynamic(p.name) or workingFromStatic(p.name);
        M.working = built;
        local slots = buildCommitSlots();
        if #slots > 0 then
            local ok = nil;
            pcall(function() ok = setmgr.commitSet(job, p.finalName, slots); end);
            if ok == true then
                made = made + 1;
                if p.renamed then renamed = renamed + 1; end
            else
                failed = failed + 1;
            end
        else
            -- Nothing resolved to owned/known gear with a path: skip rather than create an
            -- empty set (hard rule 12 -- don't silently manufacture blanks on a migrate).
            blank = blank + 1;
        end
    end
    M.working, M.workingSetName, ui.setSelected, _setDirty = keepW, keepN, keepSel, keepDirty;
    if made > 0 then
        profsets.invalidate();
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl sets reload'); end);
    end
    setStatus(string.format('Created %d new set%s%s%s%s%s',
        made, (made == 1) and '' or 's',
        (made > 0) and ' -- committed and live (hot-swapped).' or ' -- nothing created.',
        (renamed > 0) and string.format('  %d renamed _Copy (name already existed).', renamed) or '',
        (blank > 0) and string.format('  %d skipped: no owned/known gear.', blank) or '',
        (failed > 0) and string.format('  %d FAILED to commit -- try one by hand for the reason.', failed) or ''),
        (made == 0));
end

-- quiet=true (Auto-Build All's loop, Henrik 07-20: "just state how many sets
-- you've rebuilt, not one line for each"): no per-set status and no per-set
-- '/dl sets reload' -- the caller queues ONE reload and one summary at the
-- end. Returns true on a successful commit either way.
local function commitCurrentSet(job, quiet)
    if not has.setmgr then setStatus('setmanager unavailable.', true); return false; end
    if M.workingSetName == nil or M.workingSetName == '' then setStatus('No set selected (pick one, or type a name + New).', true); return false; end
    if job == nil or job == '' then setStatus('Unknown job (are you logged in?).', true); return false; end
    local slots = buildCommitSlots();
    -- An EMPTY set commits on purpose: it's a valid placeholder -- a trigger can
    -- point at it today and gear can come later; dispatching it changes nothing
    -- and leaves worn gear alone (maxmp batteries still cover its slots).
    local emptyNote = (#slots == 0) and '  (EMPTY set: dispatching it changes no gear)' or '';
    local ok, action, backup = nil, nil, nil;
    local pok = pcall(function() ok, action, backup = setmgr.commitSet(job, M.workingSetName, slots); end);
    if pok and ok == true then
        _setDirty = false;         -- committed -> the working set now matches what's saved
        profsets.invalidate();     -- re-read the job file so the Sets list reflects the change
        if not quiet then
            -- Hot-swap the running engine's copy: gProfile.Sets is a live table in the
            -- LAC state, so no LAC reload -- the engine confirms (or refuses) in chat.
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl sets reload'); end);
            setStatus(string.format('%s "%s" for %s -- live now (hot-swapped; Reload LAC only if chat says the swap failed).  backup: %s%s',
                tostring(action), tostring(M.workingSetName), tostring(job), tostring(backup), emptyNote), false);
        end
        return true;
    end
    if not quiet then setStatus('Commit failed: ' .. tostring(action), true); end
    return false;
end

local function deleteCurrentSet(job)
    if not has.setmgr then setStatus('setmanager unavailable.', true); return; end
    if M.workingSetName == nil or M.workingSetName == '' then setStatus('No set selected.', true); return; end
    if job == nil or job == '' then setStatus('Unknown job (are you logged in?).', true); return; end
    local ok, action, backup = nil, nil, nil;
    local pok = pcall(function() ok, action, backup = setmgr.deleteSet(job, M.workingSetName); end);
    if pok and ok ~= true then
        -- Copy-from seeds a STATIC set into the panel under its own name; Delete
        -- then looks in sets.Dynamic and misses (field confusion). Point at the
        -- right tool instead of a bare failure.
        local isStatic = false;
        pcall(function()
            for _, nm in ipairs(profsets.staticSetNames()) do
                if nm == M.workingSetName then isStatic = true; break; end
            end
        end);
        if isStatic then
            setStatus(string.format('"%s" is a STATIC set (Delete removes Dynamic ones). Use the "Delete static" picker next to Copy from.',
                tostring(M.workingSetName)), true);
            return;
        end
        -- Not on disk and not static: a working set that never committed (e.g. its
        -- commit failed). There is nothing to delete -- discard the working copy so
        -- the name doesn't haunt the panel until a reload (field bug: Midcast_STR-VIT).
        if tostring(action):find('set not found', 1, true) ~= nil then
            local nm = tostring(M.workingSetName);
            M.working = {}; M.workingSetName = nil; ui.setSelected = nil; _setDirty = false;
            setStatus(string.format('"%s" was never committed -- discarded the unsaved working set (nothing on disk to delete).', nm), false);
            return;
        end
    end
    if pok and ok == true then
        profsets.invalidate();
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl sets reload'); end);
        setStatus(string.format('deleted "%s" for %s -- live now (hot-swapped).  backup: %s',
            tostring(M.workingSetName), tostring(job), tostring(backup)), false);
        M.working = {}; M.workingSetName = nil; ui.setSelected = nil; _setDirty = false;
    else
        setStatus('Delete failed: ' .. tostring(action), true);
    end
end

-- Rename the selected set EVERYWHERE it is referenced (Henrik 2026-07-20: "I
-- don't want to look for everywhere it is used"): the sets file re-keys the
-- block (content untouched, setmgr.renameSet's backup/parse-check rails),
-- every trigger rule pointing at the old name is rewritten (triggersui
-- commits -- live at once), and the per-set weight stores (points / slot
-- marks / priority / mode + undo snapshots) move along. The panel follows
-- under the new name and the engine hot-swaps sets like Commit. A set that
-- was never committed just renames in the panel.
local function renameCurrentSet(job, newName)
    if not has.setmgr then setStatus('setmanager unavailable.', true); return false; end
    local old = M.workingSetName;
    if old == nil or old == '' then setStatus('No set selected.', true); return false; end
    if job == nil or job == '' then setStatus('Unknown job (are you logged in?).', true); return false; end
    newName = tostring(newName or ''):gsub('^%s+', ''):gsub('%s+$', '');
    if newName == '' then setStatus('Type the new name first.', true); return false; end
    if newName == old then setStatus('That is already the name.', true); return false; end
    for _, nm in ipairs(profsets.dynamicSetNames()) do
        if string.lower(nm) == string.lower(newName) then
            setStatus(string.format('A set named "%s" already exists -- pick another name.', nm), true);
            return false;
        end
    end
    local ok, action = nil, nil;
    local pok = pcall(function() ok, action = setmgr.renameSet(job, old, newName); end);
    if not pok then setStatus('Rename failed: ' .. tostring(action or 'internal error'), true); return false; end
    local onDisk = (ok == true);
    if not onDisk and tostring(action):find('set not found', 1, true) == nil then
        setStatus('Rename failed: ' .. tostring(action), true);
        return false;
    end
    local rules = 0;
    pcall(function() rules = require('dlac\\ui\\triggersui').renameSetRefs(old, newName) or 0; end);
    if has.optim and optim.renameSetKey ~= nil then
        pcall(optim.renameSetKey, job, old, newName);
        pcall(optim.saveWeights);
    end
    M.workingSetName = newName;
    profsets.invalidate();
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl sets reload'); end);
    setStatus(string.format('Renamed "%s" -> "%s"%s; %d trigger rule%s updated; weights moved along -- live now (hot-swapped).',
        old, newName,
        onDisk and '' or ' (never committed -- panel renamed, nothing on disk to re-key)',
        rules, (rules == 1) and '' or 's'), false);
    return true;
end

-- Auto-Build All (Henrik 2026-07-20): build and COMMIT every dynamic set of
-- this job that has stat weights set (per-set points or a priority list) --
-- load, bind, autoBuild, commit, next; the panel returns to the set it showed.
-- The receiving half of a weights-bearing profile import (exports carry
-- weights and EMPTY set shells, never equipment -- the importer's own gear
-- fills them here), and the controls row's "Auto-Build All" button. A set
-- whose weights score nothing keeps its current contents (no empty commit).
-- Returns built, skippedNoWeights, scoredNothing.
local function autoBuildAll(job, level)
    if not has.setmgr then setStatus('setmanager unavailable.', true); return 0, 0, 0; end
    if job == nil or job == '' then setStatus('Unknown job (are you logged in?).', true); return 0, 0, 0; end
    profsets.invalidate();          -- an import may have just written the sets file
    local names = profsets.dynamicSetNames();
    local weighted = {};
    if has.optim then
        pcall(function()
            for _, k in ipairs(optim.perSetKeys() or {}) do weighted[k] = true; end
            for _, k in ipairs(optim.prioPerSetKeys() or {}) do weighted[k] = true; end
        end);
    end
    local todo = {};
    for _, nm in ipairs(names) do
        if weighted[tostring(job) .. '|' .. nm] == true then todo[#todo + 1] = nm; end
    end
    if #todo == 0 then
        setStatus('No set of this job has stat weights set -- nothing to auto-build.', true);
        return 0, #names, 0;
    end
    local prevName = M.workingSetName;
    local built, empty, failed = 0, 0, 0;
    for _, nm in ipairs(todo) do
        loadSet(nm);
        if has.optim and optim.bindSetWeights ~= nil then pcall(optim.bindSetWeights, job, nm); end
        ui._wbuf = {};
        invalidateCandidates();
        local nSlots = 0;
        pcall(function() nSlots = autoBuild(job, level); end);
        if (nSlots or 0) > 0 then
            -- QUIET commit (Henrik 07-20: one summary, not a line per set) --
            -- the single hot-swap + summary below covers the whole sweep.
            if commitCurrentSet(job, true) then built = built + 1;
            else failed = failed + 1; end
        else
            empty = empty + 1;
            _setDirty = false;      -- untouched set: no unsaved-changes flag
        end
    end
    -- Put the panel back on the set it showed before the sweep, then ONE
    -- engine hot-swap for everything the loop committed.
    if prevName ~= nil then loadSet(prevName);
    else M.working = {}; M.workingSetName = nil; ui.setSelected = nil; _setDirty = false; end
    if built > 0 then
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl sets reload'); end);
    end
    local skipped = #names - #todo;
    setStatus(string.format('Auto-built %d set%s%s%s%s -- committed and live.',
        built, (built == 1) and '' or 's',
        (empty > 0) and string.format(' (%d scored nothing and kept their contents)', empty) or '',
        (failed > 0) and string.format(' (%d FAILED to commit -- try committing one by hand for the reason)', failed) or '',
        (skipped > 0) and string.format(' (%d without weights untouched)', skipped) or ''), false);
    return built, skipped, empty, failed;
end

-- A weights-bearing job import auto-builds its sets the moment it lands
-- (profilesmenu calls back; configure MERGES, so this late wiring keeps the
-- ui/COL deps from line ~194). Only possible when the import targeted THIS
-- character's ACTIVE profile under the CURRENT job -- the candidate pools
-- (owned gear, job/level usability) are the current job's; anything else
-- gets a pointer to the Sets tab's Auto-Build All instead.
pmenu.configure({ afterImport = function(dstChar, dstProf, jobName)
    local prof = require('dlac\\profiles');
    if dstChar ~= prof.currentCharFolder() or dstProf ~= prof.activeName() then
        return '  (sets not auto-built: they landed outside this character\'s active profile -- switch there and click Auto-Build All on the Sets tab)';
    end
    local job, level = getPlayerInfo();
    if job == nil or tostring(job) ~= tostring(jobName) then
        return string.format('  (sets not auto-built: you are on %s and the import is %s -- switch job and click Auto-Build All on the Sets tab)',
            tostring(job or '?'), tostring(jobName));
    end
    local built, _, empty, failed = autoBuildAll(job, level);
    return string.format('  Auto-built %d imported set%s from their stat weights with YOUR gear%s%s.',
        built, (built == 1) and '' or 's',
        (empty > 0) and string.format(' (%d scored nothing you own)', empty) or '',
        ((failed or 0) > 0) and string.format(' (%d failed to commit)', failed) or '');
end });

-- (the stat-weights editor body moved to dlac\weightsui.lua -- wui.editor().)

-- Add-item popup: usable owned items for the selected slot not already in its list.
-- One row of the + Add list: browse-row treatment -- alternating bg, reserved
-- name column, Lv / stats columns, red = stored. Returns true when clicked.
local function renderAddRow(rec, ordinal, level, nameW)
    local bg = (ordinal % 2 == 0) and { 1, 1, 1, 0.03 } or { 1, 1, 1, 0.07 };
    imgui.PushStyleColor(ImGuiCol_ChildBg, bg);
    imgui.BeginChild('##addrow_' .. tostring(rec.Id or ordinal) .. '_' .. ordinal, { -1, 22 }, false);
    icons.renderIcon(rec.Id, 18, rec);   -- virtuals (dlac:*) get the element wheel
    local clicked = imgui.Selectable('##addsel_' .. ordinal, false);
    if imgui.IsItemHovered() then renderItemTooltip(rec); end
    local nameCol = 26;
    imgui.SameLine(nameCol);
    imgui.TextColored(owned.isStored(rec) and COL.ERR or COL.USABLE, fmt.esc(rec.Name or '?') .. fmt.qtyTag(rec));
    imgui.SameLine(nameCol + (nameW or 200));
    imgui.TextColored(COL.LEVEL, string.format('Lv%2d', rec.Level or 0));
    local ss = fmt.statSummary(rec, level);
    if ss ~= '' then
        imgui.SameLine(nameCol + (nameW or 200) + 46);
        imgui.TextColored(COL.STATS, fmt.esc(ss));
    end
    local at = fmt.augTag(rec);                        -- your copy's augments, gold
    if at ~= '' then
        imgui.SameLine(0, 10);
        imgui.TextColored(COL.SCORE, fmt.esc(at));
    end
    imgui.EndChild();
    imgui.PopStyleColor(1);
    return clicked;
end

local function renderAddPopup(job, level)
    if not imgui.BeginPopup('##ffxilac_addpick') then return; end
    if ui.setSelected == nil then
        imgui.TextColored(COL.DIM, 'No slot selected.');
    else
        imgui.TextColored(COL.HEADER, 'Add usable item to ' .. ui.setSelected .. ':');
        imgui.SameLine(0, 10); renderSortCombo('add');
        imgui.SameLine(0, 10);
        imgui.TextColored(COL.DIM, 'stays open -- add several; Esc / click outside closes');
        -- Gated add (a section's "Add more"): say so loudly -- every click below
        -- stamps this mode gate on the new row.
        if ui._addGate ~= nil then
            imgui.TextColored(COL.JOBS, '@' .. fmt.esc(tostring(ui._addGate)) .. '  -- every piece added is gated on this mode');
        end
        -- Candidate pool first (the weapon-type filter's buckets derive from it, so it
        -- has to exist before the filter row renders). Sub takes the full paired pool.
        local gearKey = GEAR_OF[ui.setSelected] or ui.setSelected;
        local list = M.working[ui.setSelected] or {};
        local inList = {};
        for _, it in ipairs(list) do if it.rec and it.rec.Name then inList[it.rec.Name] = true; end end
        local useLevel = setBuildLevel(level);   -- "Build as lv.75" lifts the cap for + Add too
        local cands = candidatesForSlot(gearKey, job, useLevel);
        if gearKey == 'Sub' then
            -- Full pool (shields/grips + 1H weapons), paired against EVERY Main
            -- plan -- not just the current pick: that pick is mode/level-dependent,
            -- and a mode-gated staff pick would wrongly hide all 1H weapons. Sets
            -- are plans: a 1H off-hand is addable without the DW trait;
            -- BuildDynamicSets decides at equip time (shield = fallback).
            cands = subFilterAnyMain(subCandidatePool(job, useLevel), M.working['Main'], job, useLevel);
        end
        local blocked = pairedBlockedIds(ui.setSelected, true);
        cands = sortForDisplay(cands);

        -- Filter row: name search + hide gear parked in unavailable containers
        -- + hide the Teleports-menu utility items (ON by default -- Henrik: they
        -- bloat the Ear/Ring lists without adding set value).
        ui.addSearch = ui.addSearch or { '' };
        ui.addAvail  = ui.addAvail  or { false };
        ui.addHideTravel = ui.addHideTravel or { true };
        ui.addTypeFilter = ui.addTypeFilter or {};   -- weapon-type marks (F2a/F2b); {} = "All"
        imgui.TextColored(COL.DIM, 'Search:'); imgui.SameLine(0, 4);
        imgui.PushItemWidth(240);
        imgui.InputText('##addsearch', ui.addSearch, 48);
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Matches item names AND stats -- try HMP, Refresh, FastCast\n(aliases work: matk finds MAB gear). Comma = AND:\n"hmp, refresh" shows only pieces carrying BOTH.');
        end
        imgui.SameLine(0, 14);
        imgui.Checkbox('Available only', ui.addAvail);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Hide gear parked in a container you cannot equip from\n(the red names -- Safe, Storage, Locker, Satchel...).');
        end
        imgui.SameLine(0, 14);
        imgui.Checkbox('Hide teleport/exp items', ui.addHideTravel);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Hide the Teleports-menu utility items (Warp / Provenance Ring, Shadow\nLord Shirt, teleport earrings/rings, exp rings) -- no combat stats, they\nonly bloat the Ear/Ring lists. Untick to add one to a set deliberately.');
        end
        -- Weapon-type filter (F2a/F2b, PRD #14): a multiselect narrowing the VISIBLE
        -- candidates by weapon type -- view-only, never eligibility (HARD RULE 6 /
        -- ADR 0006). Shown only for slots weaponfilter knows (Main / Range / Ammo / Sub)
        -- and only offers the types present in this slot's owned pool. Sub's pool is the
        -- full paired offer (subFilterAnyMain, above) -- the filter hides rows from it,
        -- never re-gating what the picker offers (HARD RULE 6).
        local wf = require('dlac\\gear\\weaponfilter');   -- function-scoped: gearui is near the 200-local cap
        local wfBuckets = wf.presentBuckets(cands, gearKey);
        if #wfBuckets > 0 then
            local nMarked = 0; for _ in pairs(ui.addTypeFilter) do nMarked = nMarked + 1; end
            imgui.SameLine(0, 14);
            imgui.TextColored(COL.DIM, 'Type:'); imgui.SameLine(0, 4);
            imgui.PushItemWidth(150);
            local preview = (nMarked == 0) and 'All'
                or (nMarked == 1 and '1 type' or (nMarked .. ' types'));
            if imgui.BeginCombo('##addtypefilter', preview) then
                -- "All" clears every mark. Marking a specific type auto-deselects All
                -- (nMarked > 0). Checkboxes (not Selectable) keep the dropdown open for
                -- multi-pick without depending on a DontClosePopups flag.
                local allRef = { nMarked == 0 };
                if imgui.Checkbox('All##wf_all', allRef) then ui.addTypeFilter = {}; end
                imgui.Separator();
                for _, b in ipairs(wfBuckets) do
                    local ref = { ui.addTypeFilter[b.key] == true };
                    if imgui.Checkbox(b.label .. '##wf_' .. b.key, ref) then
                        ui.addTypeFilter[b.key] = ref[1] and true or nil;
                    end
                end
                imgui.EndCombo();
            end
            imgui.PopItemWidth();
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Show only the marked weapon types. "All" (default) shows everything;\nmark one or more types to narrow the list. Resets to "All" each open.\nView only -- what is eligible never changes.');
            end
        end

        -- Apply the popup filters up front so the name column sizes to what shows.
        local q = string.lower(ui.addSearch[1] or '');
        local qTerms = parseSearch(q);
        local travelSet = (ui.addHideTravel[1] == true and useit ~= nil
            and type(useit.menuNames) == 'function') and useit.menuNames() or nil;
        local travelHidden = 0;   -- so the empty-list message can blame the filter
        local typeHidden = 0;     -- ditto, for the weapon-type filter
        local shown = {};
        for _, rec in ipairs(cands) do
            if not inList[rec.Name] and not (rec.Id and blocked[rec.Id])
               and itemSearchMatch(rec, qTerms, useLevel)
               and (ui.addAvail[1] ~= true or not owned.isStored(rec)) then
                if travelSet ~= nil and rec.Name ~= nil and travelSet[string.lower(rec.Name)] then
                    travelHidden = travelHidden + 1;
                elseif not wf.visible(rec, ui.addTypeFilter, gearKey) then
                    typeHidden = typeHidden + 1;
                else
                    shown[#shown + 1] = rec;
                end
            end
        end
        local nW = fmt.nameWidthOf(shown);
        imgui.BeginChild('##ffxilac_addlist', { 620, 460 }, false);
        local any = false;
        -- Virtual entries ("slot functions", ADR 0004): resolved by the engine at equip
        -- time from your owned gear. Offered per slot, pinned above the item list.
        local vlist = {};
        if ui.setSelected == 'Main' then
            vlist[#vlist + 1] = { name = 'dlac:AutoIridescence', tip = 'Equips your best USABLE Iridescence staff for the cast (level-checked):\nHQ elemental +2 / NQ +1 (own element) vs a universal weapon\n(Foreshadow +1/Chatoyant = +2 all elements, Iridal = +1); ties go to the\nuniversal, which also covers elementless actions. When nothing usable\nexists (e.g. under-leveled), the OTHER items in this slot\'s list are\nthe fallback -- best-by-level as usual.\n(Sets written as dlac:AutoStaff keep working.)' };
        elseif ui.setSelected == 'Waist' then
            vlist[#vlist + 1] = { name = 'dlac:ElementalObi', tip = 'Equips the matching elemental obi when the net day/weather bonus for\nthe spell\'s element is positive (level-checked). Other items in this\nslot\'s list are the fallback.\n(Sets written as dlac:AutoObi keep working.)' };
        elseif ui.setSelected == 'Sub' then
            -- level = 75: the grip is one fixed Lv75 item, so the marker IS a
            -- Lv75 rung -- the editor row shows it (AutoStaff/Obi stay level 0:
            -- their rung varies with owned gear, virtualMinLevel derives it).
            vlist[#vlist + 1] = { name = 'dlac:AutoOneiros', level = 75, tip = 'Equips Oneiros Grip while its latent Refresh +1 is LIVE: current MP at\nor below 50%% of your BASE pool -- the race/job/sub formula plus Max MP\nmerits, gear excluded (set your merit count on the Automations tab;\nthe threshold re-aims itself on job change and level sync). Needs a\ntwo-handed main; other items in this slot\'s list are the fallback.' };
        end
        -- NOTE: dlac:AutoCraft is deliberately NOT offered here. Craft gear is a SET
        -- automation -- the engine overlays the whole craft set (dispatch.craftOverlay)
        -- when a craft is active -- not a per-slot pick. It is still configured under
        -- the Automations tab, and the engine's per-slot resolveVirtual('dlac:AutoCraft')
        -- (used by the overlay) and any set that still carries the marker keep working.
        if vlist ~= nil then
            for vi, vd in ipairs(vlist) do
                if not inList[vd.name]
                   and (q == '' or string.find(string.lower(vd.name), q, 1, true) ~= nil) then
                    any = true;
                    imgui.TextColored(COL.SCORE, '*');
                    imgui.SameLine(0, 6);
                    if imgui.Selectable(vd.name .. '   (auto -- resolved at equip time)##vadd' .. vi, false) then
                        -- No CloseCurrentPopup (Henrik): the popup stays open so several
                        -- pieces can be added in a row; the added entry drops out of the
                        -- pick list next frame (inList), which is the click feedback.
                        list[#list + 1] = { rec = { Name = vd.name, Level = vd.level or 0, Virtual = true },
                                            mode = ui._addGate };   -- nil unless a section's gated add
                        M.working[ui.setSelected] = list;
                        _setDirty = true;
                    end
                    if imgui.IsItemHovered() then imgui.SetTooltip(vd.tip); end
                end
            end
            imgui.Separator();
        end
        for i, rec in ipairs(shown) do
            any = true;
            if renderAddRow(rec, i, useLevel, nW) then
                -- No CloseCurrentPopup (Henrik): stay open for multi-add; the row
                -- vanishes from the list next frame (now inList) as feedback.
                list[#list + 1] = { rec = rec, mode = ui._addGate };   -- gate nil unless a section's gated add
                M.working[ui.setSelected] = list;
                _setDirty = true;   -- added an item to the slot -> unsaved changes
            end
        end
        if not any then
            imgui.TextColored(COL.DIM, (q ~= '' or ui.addAvail[1] == true or travelHidden > 0 or typeHidden > 0)
                and 'Nothing matches the search / filter.'
                or 'No addable items (check Main for Sub, or you own only one).');
        end
        imgui.EndChild();
    end
    imgui.EndPopup();
end

-- Right-side panel: Dynamic toggle + Auto-build + the stat-weights editor.
local function renderSetsWeightPanel(job, level)
    -- Per-set weight memory: keep the optimizer's ACTIVE weights bound to the
    -- selected set (this window can be open while another tab is up, so it binds
    -- too, not just the Sets tab). A swap stales the editor's number buffers and
    -- the weighted candidate order.
    if has.optim and optim.bindSetWeights ~= nil then
        local okb, changed = pcall(optim.bindSetWeights, job, M.workingSetName);
        if okb and changed then ui._wbuf = {}; invalidateCandidates(); end
    end
    -- Weights are per set only (the shared/no-set table is gone, Henrik 07-17):
    -- with nothing selected there is nothing to tune or build into.
    if M.workingSetName == nil then
        fmt.textWrapped(COL.DIM, 'No set selected -- every set carries its own weights, priority list and build-slot marks. Pick or create a set on the Sets tab.');
        return;
    end
    imgui.Checkbox('Dynamic', ui.setsDynamic);
    if imgui.IsItemHovered() then
        imgui.SetTooltip("When off, builds only ONE item per slot for the set (won't scale with level).");
    end
    -- Build-slot grid (replaces the Skip-weapons checkbox): per-set marks for
    -- which slots Auto-build fills; weapons just default unmarked.
    pcall(wui.slotGrid);
    if imgui.Button('Auto-build##setauto', { -1, 24 }) then
        local nSlots, nRows = autoBuild(job, level);
        -- ALWAYS say what happened: a silent empty result reads as a dead button.
        if (nSlots or 0) > 0 then
            setStatus(string.format('Auto-built %d slot(s), %d row(s) -- Commit to save.', nSlots, nRows), false);
        elseif not weightsActive() then
            if has.optim and type(optim.weightsMode) == 'function'
               and select(2, pcall(optim.weightsMode)) == 'priority' then
                setStatus('Auto-build chose nothing: the priority list is empty. Add stats on the Priority tab below, then build again.', true);
            else
                setStatus('Auto-build chose nothing: no stat weights are set (zeroed weights don\'t count). Weight some stats below, then build again.', true);
            end
        else
            setStatus('Auto-build chose nothing: no owned, equippable item scored above 0 with the current weights.', true);
        end
    end
    imgui.Separator();
    wui.editor();
end

-- Per-entry rules popup (the '~' button on a slot-list row): min/max level bounds
-- and a mode gate. Edits write straight into the working entry (Commit serializes
-- them as the { gear = ..., minLevel/maxLevel/mode } wrapper form).
local function renderEntryEditPopup()
    if not imgui.BeginPopup('##dlac_entryedit') then return; end
    local it = ui._editIt;
    if it == nil or it.rec == nil then imgui.EndPopup(); return; end
    imgui.TextColored(COL.HEADER, fmt.esc(it.rec.Name or '?'));
    imgui.Separator();
    imgui.TextColored(COL.DIM, 'Use only between these main-job levels (0 = no bound):');
    imgui.PushItemWidth(90);
    if imgui.InputInt('min##eemin', ui._editMin) then
        local v = math.max(0, math.floor(ui._editMin[1] or 0)); ui._editMin[1] = v;
        it.minLevel = (v > 0) and v or nil; _setDirty = true;
    end
    imgui.SameLine(0, 10);
    if imgui.InputInt('max##eemax', ui._editMax) then
        local v = math.max(0, math.floor(ui._editMax[1] or 0)); ui._editMax[1] = v;
        it.maxLevel = (v > 0) and v or nil; _setDirty = true;
    end
    imgui.PopItemWidth();
    imgui.Separator();
    -- Compact labels + hover tooltips (Henrik 07-14: "no need for so much blatant text")
    imgui.TextColored(COL.DIM, 'Mode Gates:');
    if imgui.IsItemHovered() then
        imgui.SetTooltip('When enabled, this piece is equipped only while ANY of these\nmodes is active -- and then it beats the unconditional entries\nin this list. Define modes under Triggers > Modes.');
    end

    -- Current gates as a removable list (string or table on the entry).
    local modes = {};
    if type(it.mode) == 'table' then
        for _, m in ipairs(it.mode) do modes[#modes + 1] = tostring(m); end
    elseif it.mode ~= nil then
        modes[1] = tostring(it.mode);
    end
    local changed, removeAt = false, nil;
    for mi, m in ipairs(modes) do
        imgui.TextColored(entryModeOk(m) and COL.JOBS or COL.USABLE, '@' .. fmt.esc(m));
        if imgui.IsItemHovered() then imgui.SetTooltip('Green = active right now.'); end
        imgui.SameLine(0, 8);
        if imgui.SmallButton('x##eemrm_' .. mi) then removeAt = mi; end
    end
    if removeAt ~= nil then table.remove(modes, removeAt); changed = true; end
    if #modes == 0 then imgui.TextColored(COL.DIM, '(always -- no mode gate)'); end

    imgui.PushItemWidth(220);
    if imgui.BeginCombo('##eemodeadd', '+ add mode gate') then
        local opts = {};
        if trigui ~= nil and type(trigui.modeConditions) == 'function' then
            local ok, r = pcall(trigui.modeConditions);
            if ok and type(r) == 'table' then opts = r; end
        end
        local shown = 0;
        for _, c in ipairs(opts) do
            local dup = false;
            for _, m in ipairs(modes) do
                if string.lower(m) == string.lower(c) then dup = true; break; end
            end
            if not dup then
                shown = shown + 1;
                if imgui.Selectable(c, false) then modes[#modes + 1] = c; changed = true; end
            end
        end
        if shown == 0 then imgui.TextColored(COL.DIM, (#opts == 0) and '(no modes yet -- define them on the Triggers tab)' or '(all defined modes already added)'); end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();

    if changed then
        if #modes == 0 then it.mode = nil;
        elseif #modes == 1 then it.mode = modes[1];      -- single gate stays a plain string
        else it.mode = modes; end
        _setDirty = true;
    end

    -- Auto Type (Type automations): hand the piece to an equip automation that
    -- decides at equip time whether to wear it or the slot's next-best pick.
    -- FOUNDATION ONLY on main: no types ship here yet -- the first one
    -- (AutoAcc) lives on feature/autoacc pending GM approval, so the combo
    -- offers None. The plumbing (autoType/removePrio wrappers, flatten
    -- markers, engine budget) stays, so branch and main share one set format
    -- and a branch-committed type still displays and can be cleared. Not
    -- offered on virtual rows (they are already automations).
    if it.rec == nil or it.rec.Virtual ~= true then
        imgui.Separator();
        imgui.TextColored(COL.DIM, 'Auto Type');
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Give this piece an automation type: the engine then decides at\nequip time whether to wear it or the slot\'s next-best piece.\nNo types are available yet.');
        end
        local curType = (it.autoType ~= nil) and tostring(it.autoType) or 'None';
        imgui.PushItemWidth(120);
        if imgui.BeginCombo('##eeautotype', curType) then
            if imgui.Selectable('None', it.autoType == nil) and it.autoType ~= nil then
                it.autoType = nil; it.removePrio = nil; it.acc = nil;
                _setDirty = true;
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
        if it.autoType ~= nil then
            imgui.SameLine(0, 10);
            imgui.PushItemWidth(90);
            if ui._editPrio == nil then ui._editPrio = { it.removePrio or 1 }; end
            if imgui.InputInt('Removal Priority##eeprio', ui._editPrio) then
                local v = math.floor(ui._editPrio[1] or 1); ui._editPrio[1] = v;
                it.removePrio = v; _setDirty = true;
            end
            imgui.PopItemWidth();
            if imgui.IsItemHovered() then
                imgui.SetTooltip('When several typed pieces compete for release,\nHIGHER priority is released first.');
            end
        end
    end
    imgui.EndPopup();
end

-- Left builder: 16 slot tiles + the expanded ordered list for the selected slot.
local function renderSetBuilder(job, level)
    if M.workingSetName == nil then
        fmt.textWrapped(COL.DIM, 'Pick a set above, or type a name and click New, then Auto-build or + Add items.');
        return;
    end

    renderSlotGrid('set', 182, ui.setSelected,
        function(sl)
            local pick = bestByLevel(M.working[sl.label], level);
            return pick and pick.rec and pick.rec.Id or nil;
        end,
        function(sl)
            local list = M.working[sl.label];
            local pick = bestByLevel(list, level);
            local nm = (pick and pick.rec and pick.rec.Name) or '(empty)';
            return string.format('%s (%d)', fmt.truncate(nm, 12), (list and #list) or 0);
        end,
        function(labelKey) ui.setSelected = labelKey; end,
        function(sl)
            local pick = bestByLevel(M.working[sl.label], level);
            return pick and pick.rec or nil;
        end);

    imgui.Separator();
    if ui.setSelected == nil then
        fmt.textWrapped(COL.DIM, 'Select a slot above to edit its ordered list. Yellow = current best-by-level pick.');
        return;
    end

    local list = M.working[ui.setSelected] or {};
    imgui.TextColored(COL.HEADER, string.format('%s list (%d):', ui.setSelected, #list));
    imgui.SameLine(); if imgui.Button('+ Add##setadd', { 60, 0 }) then ui._openAddPopup = true; ui.addSearch = { '' }; ui.addTypeFilter = {}; ui._addGate = nil; end   -- weapon-type filter resets to "All" each open (F2a/F2b); no mode gate (that's the sections' Add more)
    imgui.SameLine(0, 8); renderSortCombo('setlist');

    local pick = bestByLevel(list, level);
    local pickRec = pick and pick.rec or nil;
    local disp = sortItemsForDisplay(list);

    local action = nil;   -- { kind, it }  (by identity, so it maps back to the data list)
    imgui.BeginChild('##ffxilac_slotlist', { -1, -1 }, false);
    if #list == 0 then
        imgui.TextColored(COL.DIM, 'Empty -- click + Add (usable owned items) or Auto-build.');
    else
        -- One BLOCK per item (alternating bg per block, never inside one): line 1 =
        -- name + Lv + rule tags with the buttons pinned right; line 2 = the stats.
        -- No up/down reordering -- list order doesn't matter (best-by-level + rules
        -- decide the pick).
        local openEdit = false;
        local rowN = 0;   -- running render counter: row ids + bg alternation across root + sections
        -- sec = the mode section this copy renders under (nil = the root list).
        -- It only changes what x means: root x removes the ROW (root is the
        -- data list); section x removes THIS GATE (sections are views).
        local function renderRow(it, sec)
            rowN = rowN + 1;
            local di = rowN;
            local rec = it.rec;
            local ss = rec and fmt.statSummary(rec, level) or '';
            local at = fmt.augTag(rec);                -- your copy's augments (line 2, gold)
            local bg = (di % 2 == 0) and { 1, 1, 1, 0.03 } or { 1, 1, 1, 0.07 };
            imgui.PushStyleColor(ImGuiCol_ChildBg, bg);
            imgui.BeginChild('##setrow_' .. tostring(rec and rec.Id or ('n' .. di)) .. '_' .. di,
                { -1, (ss ~= '' or at ~= '') and 42 or 26 }, false);
            icons.renderIcon(rec and rec.Id or nil, 18, rec);   -- virtuals get the element wheel
            -- Picked-row highlight compares the WRAPPER (it == pick), not the record:
            -- one item may appear as several rows with different level ranges, and
            -- only the row the engine would actually use should light up.
            imgui.TextColored((pick ~= nil and it == pick) and COL.SCORE
                or (owned.isStored(rec) and COL.ERR or COL.USABLE),
                fmt.esc((rec and rec.Name) or '?') .. fmt.qtyTag(rec));
            if rec ~= nil and imgui.IsItemHovered() then renderItemTooltip(rec); end
            imgui.SameLine(0, 10);
            imgui.TextColored(COL.LEVEL, string.format('Lv%2d', rec and rec.Level or 0));
            -- Level-range badge: the whole plan must be readable at a glance when one
            -- item spans several rows ([Lv 30-54] ... [Lv 75+]). Green = the rule
            -- matches your current level, dim = this row is dormant right now.
            if it.minLevel ~= nil or it.maxLevel ~= nil then
                imgui.SameLine(0, 8);
                local rng = (it.minLevel ~= nil and it.maxLevel ~= nil)
                        and (tostring(it.minLevel) .. '-' .. tostring(it.maxLevel))
                    or (it.minLevel ~= nil) and (tostring(it.minLevel) .. '+')
                    or ('-' .. tostring(it.maxLevel));
                local inRange = (it.minLevel == nil or level >= it.minLevel)
                            and (it.maxLevel == nil or level <= it.maxLevel);
                imgui.TextColored(inRange and COL.JOBS or COL.DIM, '[Lv ' .. rng .. ']');
                if imgui.IsItemHovered() then
                    imgui.SetTooltip(inRange
                        and 'Behaviour level rule -- matches your current level, so this row is in play.'
                        or  'Behaviour level rule -- outside your current level; this row is dormant until then.');
                end
            end
            if it.mode ~= nil then
                imgui.SameLine(0, 8);
                imgui.TextColored(entryModeOk(it.mode) and COL.JOBS or COL.DIM, '@' .. fmt.esc(modeTagText(it.mode)));
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Mode-gated: used while ANY of these modes is active\n(and then it beats the unconditional entries).\nGreen = active right now.');
                end
            end
            if it.autoType ~= nil then
                imgui.SameLine(0, 8);
                imgui.TextColored(COL.SCORE, string.format('[%s p%d]', fmt.esc(tostring(it.autoType)), it.removePrio or 1));
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Type automation: the engine decides at equip time whether this piece\nor the slot\'s next-best is worn. p = Removal Priority (higher first).');
                end
            end
            imgui.SameLine(imgui.GetWindowWidth() - 86);   -- buttons at the right edge
            if imgui.Button('B##ed_' .. di, { 24, 20 }) then
                ui._editIt = it;
                ui._editMin = { it.minLevel or 0 };
                ui._editMax = { it.maxLevel or 0 };
                ui._editPrio = { it.removePrio or 1 };
                openEdit = true;
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Behaviour rules for this piece:\nlimit it to a level range, or gate it on a mode --\na gated entry is used only while its mode is active.\nNeed the same item in two ranges? Duplicate the row (D)\nand give each row its own range.');
            end
            imgui.SameLine(0, 4);
            if imgui.Button('D##dup_' .. di, { 24, 20 }) then action = { kind = 'dup', it = it }; end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Duplicate this row: same item, its own Behaviour rules.\nUse it to run one item in several level ranges, e.g.\nRajas Ring min30 max54 on one row, min75 on the other.');
            end
            imgui.SameLine(0, 4);
            if imgui.Button('x##rm_' .. di, { 24, 20 }) then
                -- Section x = leave THIS mode only (Henrik: a Harpoon gated
                -- Base + Polearm lost the whole row to one Polearm x).
                if sec ~= nil then action = { kind = 'ungate', it = it, gateKey = sec.key };
                else action = { kind = 'remove', it = it }; end
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip((sec ~= nil)
                    and ('Remove from this mode only: the row loses its @' .. fmt.esc(sec.name) .. ' gate.\nOther mode gates keep it in their sections; with no gate left\nit becomes unconditional and moves to the main list.')
                    or 'Remove from this list.');
            end
            if ss ~= '' or at ~= '' then               -- line 2: stats + your augments
                imgui.SetCursorPosX(26);
                if ss ~= '' then
                    imgui.TextColored(COL.STATS, fmt.esc(ss));
                    if at ~= '' then imgui.SameLine(0, 10); end
                end
                if at ~= '' then imgui.TextColored(COL.SCORE, fmt.esc(at)); end
            end
            imgui.EndChild();
            imgui.PopStyleColor(1);
        end
        -- Mode sections (Henrik, 2026-07-18): a mode gating 2+ rows collapses
        -- them under one header -- mode name + the level ladder inside -- so a
        -- slot bloated with per-mode ladders (Caster rungs + Club rungs on WHM)
        -- stays readable. Rows whose every gate is sectioned live only there;
        -- ungated / solo-gated rows stay in the root list (a solo-gated row that
        -- ALSO has a sectioned gate renders in both). Default collapsed; the id
        -- is set+slot+mode so a toggled-open header survives re-sorts but never
        -- leaks its state across sets or slots.
        local rootRows, modeSecs = fmt.modeSections(disp);
        for _, it in ipairs(rootRows) do renderRow(it); end
        for _, sec in ipairs(modeSecs) do
            local act = entryModeOk(sec.name);
            local label = string.format('@%s  (%d)  Lv %s###msec_%s_%s_%s',
                sec.name, #sec.items, table.concat(sec.levels, ', '),
                tostring(M.workingSetName), tostring(ui.setSelected), sec.key);
            if act then imgui.PushStyleColor(ImGuiCol_Text, COL.JOBS); end
            -- AllowItemOverlap is LOAD-BEARING for the Add more button: without
            -- it the header owns the whole row's hit box and the button only
            -- toggles the section (field report, 07-18). Guarded like every
            -- flag constant -- absent just means the header keeps the row.
            local open = imgui.CollapsingHeader(label,
                (ImGuiTreeNodeFlags_AllowItemOverlap ~= nil) and ImGuiTreeNodeFlags_AllowItemOverlap or 0);
            if act then imgui.PopStyleColor(1); end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('All rows in this list gated on this mode; the numbers are\ntheir item levels, so you can see the ladder at a glance.\nGreen = the mode is active right now (these rows beat the\nunconditional ones). A row gated on several modes appears\nunder each of its sections.');
            end
            -- "Add more" (Henrik 2026-07-18): the picker opens GATED -- every
            -- piece added lands straight in this mode, no Behaviour round-trip
            -- per item. Wins the hover because it is submitted after a header
            -- that passes AllowItemOverlap; themed font: ~9.5px/char + padding.
            imgui.SameLine(imgui.GetWindowWidth() - 104);
            if imgui.SmallButton('Add more##msadd_' .. sec.key) then
                ui._openAddPopup = true; ui.addSearch = { '' };
                ui.addTypeFilter = {};                  -- same All reset as + Add
                ui._addGate = sec.name;
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Add gear straight into this mode: every piece added in the picker\ngets the @' .. fmt.esc(sec.name) .. ' gate automatically.');
            end
            if open then
                imgui.Indent(10);
                for _, it in ipairs(sec.items) do renderRow(it, sec); end
                imgui.Unindent(10);
            end
        end
        -- The popup must open in THIS window's scope, not inside a row child --
        -- OpenPopup/BeginPopup resolve ids per window, so the button only sets a flag.
        if openEdit then imgui.OpenPopup('##dlac_entryedit'); end
        renderEntryEditPopup();
    end
    imgui.EndChild();

    if action ~= nil then
        local di = nil;
        for k, v in ipairs(list) do if v == action.it then di = k; break; end end
        if di ~= nil then
            if action.kind == 'remove' then
                table.remove(list, di);
            elseif action.kind == 'ungate' then
                -- The row stays; it just leaves the clicked section. No gate
                -- left -> unconditional, so it reappears in the root list --
                -- visible, never silently gone.
                action.it.mode = fmt.stripGate(action.it.mode, action.gateKey);
            elseif action.kind == 'dup' then
                -- Fresh rules on the clone: the point of a second row is a DIFFERENT
                -- range/mode, so start blank and let Behaviour set it. Same rec
                -- reference is fine -- rows never mutate their record.
                table.insert(list, di + 1, { rec = action.it.rec });
            end
            if #list == 0 then M.working[ui.setSelected] = nil; else M.working[ui.setSelected] = list; end
            _setDirty = true;   -- list changed -> unsaved changes
        end
    end
end

local function renderSetsTab(job, level)
    if not has.setmgr then
        fmt.textWrapped(COL.ERR, 'setmanager unavailable -- commit/delete disabled (view/build still works).');
    end

    -- Per-set weight memory: one choke point covers the picker, New, Delete and
    -- job changes -- + Add scoring and the stats panel read the active weights
    -- even with the Weights window closed, so the binding can't wait for it.
    if has.optim and optim.bindSetWeights ~= nil then
        local okb, changed = pcall(optim.bindSetWeights, job, M.workingSetName);
        if okb and changed then ui._wbuf = {}; invalidateCandidates(); end
    end

    -- Controls row (compacted 2026-07-20, Henrik: "much more compact, less
    -- bloaty"): set picker + ONE Manage... menu (New / Rename / Delete /
    -- Copy from / Delete static) + the Stats toggle. Commit, Weights and
    -- Auto-Build All moved below the build-level checkbox; the free-text
    -- new-set box, the Profile: line and the Copy from / Delete static row
    -- are gone -- their flows live in the Manage popups now (the Profiles
    -- window covers profile naming/switching).
    imgui.TextColored(COL.DIM, 'Set:'); imgui.SameLine(0, 4);
    imgui.PushItemWidth(240);
    if imgui.BeginCombo('##ffxilac_setpick', M.workingSetName or '(select)') then
        local names = profsets.dynamicSetNames();
        if #names == 0 then
            imgui.TextColored(COL.DIM, '(no sets.Dynamic -- reload the profile?)');
            local _sd = profsets.diag();
            if _sd ~= nil and _sd ~= '' then imgui.TextColored(COL.ERR, fmt.esc(_sd)); end
        end
        for _, nm in ipairs(names) do
            if imgui.Selectable(nm, M.workingSetName == nm) then
                if M.workingSetName ~= nm then loadSet(nm); end
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine();
    -- The Manage... menu: selectables only SET one-shot flags -- the popups
    -- must OpenPopup in the window scope, never inside the combo's own popup.
    imgui.PushItemWidth(140);
    if imgui.BeginCombo('##ffxilac_setmanage', 'Manage...') then
        if imgui.Selectable('New...##smg_new') then
            ui.newSetName[1] = '';
            ui._newSetOpen = true;
        end
        if imgui.Selectable('Rename...##smg_ren') then
            if M.workingSetName == nil or M.workingSetName == '' then
                setStatus('No set selected (pick one first).', true);
            else
                ui._renameBuf = { M.workingSetName };
                ui._renameOpen = true;
            end
        end
        if imgui.Selectable('Delete...##smg_del') then
            if M.workingSetName == nil or M.workingSetName == '' then
                setStatus('No set selected (pick one first).', true);
            else
                ui._delSetOpen = true;
            end
        end
        if imgui.Selectable('Copy from...##smg_copy') then
            -- Opens with no set selected too: the "New set(s)" destination needs no
            -- target (that IS the migrate-many case). Default to replacing the marked
            -- set when there is one, else straight to new-set mode.
            local hasCur = (M.workingSetName ~= nil and M.workingSetName ~= '');
            ui._copyMode  = hasCur and 'current' or 'new';
            ui._copyMarks = {};
            ui._copyFromOpen = true;
        end
        if #profsets.staticSetNames() > 0 then
            if imgui.Selectable('Delete static...##smg_dstat') then
                ui._delStatic = nil;
                ui._delStaticOpen = true;
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Everything that manages the selected set: New, Rename (propagates\neverywhere), Delete, Copy from another set -- and Delete static when\nlegacy static sets are present.');
    end

    imgui.SameLine();
    if imgui.Button((ui.showStats and 'Stats v' or 'Stats >') .. '##setstats', { 72, 22 }) then ui.showStats = not ui.showStats; end

    -- Build-level override (general set management): lifts the item level cap for BOTH
    -- Auto-build and the manual + Add picker, so you can assemble over-level sets.
    if has.optim then
        ui.buildMax[1] = (optim.buildAtMaxLevel == true);
        imgui.Checkbox('Build as lv.75 (ignore level cap)', ui.buildMax);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Ignore the item level cap when building sets OR using + Add -- pick gear as if you\nwere level 75, so you can assemble over-level sets. Your JOB restriction still applies.\nOn by default; unticking is remembered across reloads.');
        end
        if (ui.buildMax[1] == true) ~= (optim.buildAtMaxLevel == true) then
            optim.buildAtMaxLevel = (ui.buildMax[1] == true);
            ui._flagsDirty = true;              -- persist via the render hook (sf.saveUiFlags
                                                -- is defined below this function)
        end
    end

    -- Commit / Weights / Auto-Build All (moved under the level checkbox,
    -- Henrik 07-20 -- the top row keeps only selection + management).
    -- Commit lights red while the working set has unsaved changes (the header
    -- 'Setup' pattern); guarded on ImGuiCol_Button.
    local _cdirty = _setDirty and ImGuiCol_Button ~= nil;
    if _cdirty then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
    if imgui.Button('Commit##setcommit', { 62, 22 }) then commitCurrentSet(job); end
    if _cdirty then imgui.PopStyleColor(1); end
    if imgui.IsItemHovered() then imgui.SetTooltip('Saves your current set into sets.Dynamic in your job file (writes <JOB>.lua). Reload LAC afterward.'); end
    imgui.SameLine();
    if imgui.Button((ui.showWeights and 'Weights v' or 'Weights >') .. '##setwtoggle', { 84, 22 }) then ui.showWeights = not ui.showWeights; end
    if imgui.IsItemHovered() then imgui.SetTooltip('Toggle the Stat Weights editor -- opens in its own resizable, movable window.'); end
    imgui.SameLine();
    if imgui.Button('Auto-Build All##setbuildall', { 0, 22 }) then
        autoBuildAll(job, level);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Will auto-build all gear-sets with stat weights set.');
    end

    -- Equip & Lock / Unlock (Henrik, 07-20: Incursion T3 locks your equipment
    -- server-side on entry -- land a set first, then stop the engine from fighting
    -- the server lock). ONE engine command ('/dl lock set <name>') wears the
    -- COMMITTED set and locks all 16 slots; the button reads the engine's lock
    -- mirror, so it flips to Unlock (and back) within the mirror's ~1s throttle.
    -- All-16 is the flip test: partial locks (Equipped tab) keep Equip & Lock up.
    imgui.SameLine();
    local elLocks, elN = engineLocks(), 0;
    for _ in pairs(elLocks) do elN = elN + 1; end
    if elN >= 16 then
        if imgui.Button('Unlock##seteqlock', { 0, 22 }) then
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl lock all off'); end);
            _lockMirror.at = -1;
            setStatus('Slot locks released -- the engine may swap gear again.');
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Every slot is locked (Equip & Lock). Click to release them all --\nthe engine resumes normal gear swaps.  (/dl lock all off)');
        end
    else
        if imgui.Button('Equip & Lock##seteqlock', { 0, 22 }) then
            if M.workingSetName == nil or M.workingSetName == '' then
                setStatus('Pick a set first -- Equip & Lock wears the committed set, then locks every slot.', true);
            else
                pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl lock set ' .. M.workingSetName); end);
                _lockMirror.at = -1;
                if _setDirty then
                    setStatus(string.format('"%s" equipped & locked -- NOTE: your uncommitted edits are NOT in it (Commit, then Equip & Lock again).', M.workingSetName), true);
                else
                    setStatus(string.format('"%s" equipped & all slots locked -- the engine will not change gear until you Unlock.', M.workingSetName));
                end
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Incursion T3 locks your equipment on entry: this equips the COMMITTED version\nof the selected set, then locks every slot so the engine stops changing gear.\nThe button becomes Unlock; locks also release on /dl lock all off or Reload LAC.');
        end
    end

    -- Automation is a SLOT entry now (ADR 0004, 4th revision): + Add on the Main slot
    -- offers dlac:AutoStaff, on Waist dlac:AutoObi -- no per-set flags anymore.

    -- Auto-expire after 5s: a lingering "... live now" line would otherwise read as a fresh
    -- commit the next time, hiding whether the new one actually took.
    if ui.setsStatus ~= nil and ui.setsStatus ~= '' and os.clock() - (ui.setsStatusAt or 0) > 5 then
        ui.setsStatus = '';
    end
    if ui.setsStatus ~= nil and ui.setsStatus ~= '' then
        fmt.textWrapped(ui.setsStatusErr and COL.ERR or COL.SCORE, fmt.esc(ui.setsStatus));
    end
    imgui.Separator();

    -- Split: [stats panel] | builder.  Stat weights are now their OWN resizable window
    -- (renderWeightsWindow), toggled by the "Weights" button above, so they get real space.
    local availW = imgui.GetContentRegionAvail();
    local statsUsed = ui.showStats and (STATS_W + 8) or 0;

    if ui.showStats then
        -- Priority mode scores with dominance-derived weights -- huge numbers
        -- that mean nothing to a reader, so the header says the mode instead.
        local wHdr = 'Set totals';
        if has.optim and type(optim.weightsMode) == 'function'
           and select(2, pcall(optim.weightsMode)) == 'priority' then
            wHdr = 'Set totals (priority)';
        else
            wHdr = string.format('Set totals (w %g)', workingWeightedScore(level));
        end
        renderStatsPanel(wHdr, workingSetTotals(level));
        imgui.SameLine();
    end

    local builderW = availW - statsUsed;
    if builderW < 190 then builderW = 190; end
    imgui.BeginChild('##ffxilac_setleft', { builderW, -1 }, false);
    renderSetBuilder(job, level);
    imgui.EndChild();

    -- Open + render the add-item popup at window level (vault pattern).
    if ui._openAddPopup then imgui.OpenPopup('##ffxilac_addpick'); ui._openAddPopup = false; end
    renderAddPopup(job, level);

    -- "Copy from static" overwrite confirmation (issue #15). BeginPopup, not Modal:
    -- clicking outside cancels, which IS the "click-away aborts" requirement.
    -- ui._copyConfirmOpen is the one-shot OpenPopup flag; the data in ui._copyConfirm
    -- persists while the popup lives and only drives an import on the Replace button.
    if ui._copyConfirmOpen then imgui.OpenPopup('##dlac_copyconfirm'); ui._copyConfirmOpen = false; end
    if imgui.BeginPopup('##dlac_copyconfirm') then
        local c = ui._copyConfirm;
        if c == nil then imgui.CloseCurrentPopup(); imgui.EndPopup(); return; end
        imgui.TextColored(COL.HEADER, 'Replace set contents?');
        imgui.Separator();
        fmt.textWrapped(COL.USABLE, string.format('Replace "%s" (%d filled slot%s) with %s "%s"?',
            tostring(c.target), c.filled, (c.filled == 1) and '' or 's',
            (c.kind == 'dynamic') and 'dynamic set' or 'static', tostring(c.src)));
        fmt.textWrapped(COL.DIM, 'The whole set is replaced: slots the source does not define are cleared. Nothing is committed until you press Commit.');
        imgui.Separator();
        local red = (ImGuiCol_Button ~= nil);
        if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
        if imgui.Button('Replace##copyconfirmgo', { 120, 24 }) then
            local src, kind = c.src, c.kind;
            ui._copyConfirm = nil;
            imgui.CloseCurrentPopup();
            if kind == 'dynamic' then doCopyFromDynamic(src); else doCopyFromStatic(src); end
        end
        if red then imgui.PopStyleColor(1); end
        imgui.SameLine(0, 8);
        if imgui.Button('Cancel##copyconfirmno', { 90, 24 }) then
            ui._copyConfirm = nil;
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end

    -- New set (Manage... > New): name it, Enter (or Create) starts editing.
    if ui._newSetOpen then imgui.OpenPopup('##dlac_setnew'); ui._newSetOpen = false; end
    if imgui.BeginPopup('##dlac_setnew') then
        imgui.TextColored(COL.HEADER, 'New set');
        if imgui.IsWindowAppearing ~= nil and imgui.IsWindowAppearing()
           and imgui.SetKeyboardFocusHere ~= nil then imgui.SetKeyboardFocusHere(0); end
        imgui.PushItemWidth(200);
        local entered = false;
        if ImGuiInputTextFlags_EnterReturnsTrue ~= nil then
            entered = imgui.InputText('##setnewname', ui.newSetName, 32, ImGuiInputTextFlags_EnterReturnsTrue);
        else
            imgui.InputText('##setnewname', ui.newSetName, 32);
        end
        imgui.PopItemWidth();
        imgui.SameLine(0, 6);
        if imgui.Button('Create##setnewgo', { 0, 22 }) or entered then
            local nm = tostring(ui.newSetName[1] or ''):gsub('^%s+', ''):gsub('%s+$', '');
            if nm ~= '' then
                M.workingSetName = nm; M.working = {}; ui.setSelected = nil; ui.newSetName[1] = '';
                _setDirty = false;   -- brand-new empty set -> nothing unsaved yet
                setStatus('New empty set "' .. nm .. '" -- add items, then Commit.', false);
                imgui.CloseCurrentPopup();
            end
        end
        imgui.TextColored(COL.DIM, 'Enter creates the set and starts editing it.');
        imgui.EndPopup();
    end

    -- Delete set (Manage... > Delete): the warning Henrik asked for verbatim.
    if ui._delSetOpen then imgui.OpenPopup('##dlac_setdelconfirm'); ui._delSetOpen = false; end
    if imgui.BeginPopup('##dlac_setdelconfirm') then
        fmt.textWrapped(COL.USABLE, string.format('Are you sure you want to delete this set?  ("%s")',
            tostring(M.workingSetName)));
        imgui.Separator();
        local red = (ImGuiCol_Button ~= nil);
        if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
        if imgui.Button('Delete##setdelgo', { 100, 24 }) then
            deleteCurrentSet(job);
            imgui.CloseCurrentPopup();
        end
        if red then imgui.PopStyleColor(1); end
        imgui.SameLine(0, 8);
        if imgui.Button('Cancel##setdelno', { 90, 24 }) then imgui.CloseCurrentPopup(); end
        imgui.EndPopup();
    end

    -- Copy from (Manage... > Copy from): dynamic OR legacy static sources, each in
    -- its own scroll list. A destination selector at the top picks WHERE they land:
    --   Current set : the marked set is REPLACED by the one source you click (legacy
    --                 behaviour -- a filled target still goes through the Replace confirm).
    --   New set(s)  : mark ANY number of sources; each becomes a fresh set kept under
    --                 its own name (a name already taken -> _Copy). This is the migrate-
    --                 many path -- no naming a set by hand for each one.
    -- Picks/marks are gathered and dispatched AFTER the children: a Selectable inside a
    -- child never auto-closes the popup, so the close is always explicit.
    if ui._copyFromOpen then imgui.OpenPopup('##dlac_setcopyfrom'); ui._copyFromOpen = false; end
    if imgui.BeginPopup('##dlac_setcopyfrom') then
        local hasCur = (M.workingSetName ~= nil and M.workingSetName ~= '');
        if ui._copyMode == nil then ui._copyMode = hasCur and 'current' or 'new'; end
        if not hasCur then ui._copyMode = 'new'; end   -- nothing marked -> new-set is the only home
        ui._copyMarks = ui._copyMarks or {};
        local newMode = (ui._copyMode == 'new');

        -- Destination selector.
        local curLabel = hasCur and ('Current set: ' .. tostring(M.workingSetName)) or '(no set selected)';
        imgui.TextColored(COL.DIM, 'Copy into:'); imgui.SameLine(0, 6);
        imgui.PushItemWidth(300);
        if imgui.BeginCombo('##dlac_cfdest', newMode and 'New set(s) -- keep source name' or curLabel) then
            if hasCur then
                if imgui.Selectable(curLabel, not newMode) then ui._copyMode = 'current'; end
            end
            if imgui.Selectable('New set(s) -- keep source name', newMode) then ui._copyMode = 'new'; end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
        newMode = (ui._copyMode == 'new');   -- re-read: the combo may have just flipped it

        if newMode then
            imgui.TextColored(COL.DIM, 'Mark one or more sources -- each becomes a NEW set under its own name, built with your gear.');
        else
            imgui.TextColored(COL.DIM, 'Pick a source -- its slots replace "' .. fmt.esc(tostring(M.workingSetName)) .. '".');
        end
        imgui.Separator();

        local statics = profsets.staticSetNames();
        local pick = nil;   -- 'current' mode: single immediate pick

        imgui.BeginChild('##setcf_dyn', { 210, 240 }, true);
        imgui.TextColored(COL.HEADER, 'Dynamic sets');
        local anyD = false;
        for _, nm in ipairs(profsets.dynamicSetNames()) do
            -- 'current' hides the marked set (can't copy onto itself); 'new' shows all
            -- (marking the current set duplicates it as <name>_Copy).
            if newMode or nm ~= M.workingSetName then
                anyD = true;
                if newMode then
                    local key = 'dynamic\0' .. nm;
                    local on = ui._copyMarks[key] == true;
                    if imgui.Selectable(nm .. '##cfd_' .. nm, on) then ui._copyMarks[key] = (not on) or nil; end
                else
                    if imgui.Selectable(nm .. '##cfd_' .. nm, false) then pick = { kind = 'dynamic', nm = nm }; end
                end
            end
        end
        if not anyD then imgui.TextColored(COL.DIM, newMode and '(no dynamic sets)' or '(no other dynamic sets)'); end
        imgui.EndChild();
        imgui.SameLine(0, 8);
        imgui.BeginChild('##setcf_stat', { 210, 240 }, true);
        imgui.TextColored(COL.HEADER, 'Static sets (legacy)');
        if #statics == 0 then imgui.TextColored(COL.DIM, '(none on this profile)'); end
        for _, nm in ipairs(statics) do
            if newMode then
                local key = 'static\0' .. nm;
                local on = ui._copyMarks[key] == true;
                if imgui.Selectable(nm .. '##cfs_' .. nm, on) then ui._copyMarks[key] = (not on) or nil; end
            else
                if imgui.Selectable(nm .. '##cfs_' .. nm, false) then pick = { kind = 'static', nm = nm }; end
            end
        end
        imgui.EndChild();

        if newMode then
            -- Gather marks in display order (dynamic list, then static list) so the
            -- create plan / duplicate warning line up with what the eye sees.
            local sources = {};
            for _, nm in ipairs(profsets.dynamicSetNames()) do
                if ui._copyMarks['dynamic\0' .. nm] then sources[#sources + 1] = { name = nm, kind = 'dynamic' }; end
            end
            for _, nm in ipairs(statics) do
                if ui._copyMarks['static\0' .. nm] then sources[#sources + 1] = { name = nm, kind = 'static' }; end
            end
            -- Duplicate warning: run the SAME plan the commit will, so the names shown
            -- are exactly what gets created (existing names, and in-batch collisions).
            local simport = require('dlac\\gear\\setimport');
            local plan = simport.resolveNewSetNames(sources, profsets.dynamicSetNames());
            local dups = {};
            for _, p in ipairs(plan) do
                if p.renamed then dups[#dups + 1] = p.name .. ' -> ' .. p.finalName; end
            end
            if #dups > 0 then
                fmt.textWrapped(COL.ERR, string.format('%d name%s already exist%s -- will be created as _Copy: %s',
                    #dups, (#dups == 1) and '' or 's', (#dups == 1) and 's' or '', table.concat(dups, ', ')));
            end
            local n = #sources;
            if imgui.Button((n > 0) and string.format('Create %d new set%s##cfnewgo', n, (n == 1) and '' or 's')
                                     or 'Create new set(s)##cfnewgo', { 0, 24 }) then
                if n > 0 then
                    imgui.CloseCurrentPopup();
                    copyAsNewSets(job, sources);
                    ui._copyMarks = {};
                else
                    setStatus('Mark at least one set on the left first.', true);
                end
            end
            imgui.SameLine(0, 8);
            if imgui.Button('Cancel##cfnewcancel', { 90, 24 }) then imgui.CloseCurrentPopup(); ui._copyMarks = {}; end
        else
            if pick ~= nil then
                imgui.CloseCurrentPopup();
                if pick.kind == 'dynamic' then copyFromDynamicSet(pick.nm); else copyFromStaticSet(pick.nm); end
            end
        end
        imgui.EndPopup();
    end

    -- Delete static (Manage... > Delete static): pick a row to arm it, then
    -- the red DELETE confirms -- same backup + Reload-LAC contract as before.
    if ui._delStaticOpen then imgui.OpenPopup('##dlac_delstaticpop'); ui._delStaticOpen = false; end
    if imgui.BeginPopup('##dlac_delstaticpop') then
        imgui.TextColored(COL.HEADER, 'Delete a static set');
        fmt.textWrapped(COL.DIM, 'Legacy sets at the root of <JOB>.lua (backed up first; the live LAC table keeps the set until the next Reload LAC). Trigger rules still pointing at it will show [missing].');
        imgui.Separator();
        imgui.BeginChild('##dstatlist', { 260, 200 }, true);
        local statics = profsets.staticSetNames();
        if #statics == 0 then imgui.TextColored(COL.DIM, '(none left)'); end
        for _, nm in ipairs(statics) do
            if imgui.Selectable(nm .. '##dst_' .. nm, ui._delStatic == nm) then ui._delStatic = nm; end
        end
        imgui.EndChild();
        if ui._delStatic ~= nil then
            local red = (ImGuiCol_Button ~= nil);
            if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
            if imgui.Button('DELETE ' .. fmt.esc(ui._delStatic) .. '##dstatgo', { 0, 24 }) then
                local ok, action, backup = nil, nil, nil;
                pcall(function() ok, action, backup = setmgr.deleteStaticSet(job, ui._delStatic); end);
                if ok == true then
                    profsets.invalidate();
                    setStatus(string.format('deleted static "%s" -- Reload LAC to apply.  backup: %s',
                        tostring(ui._delStatic), tostring(backup)), false);
                else
                    setStatus('delete static failed: ' .. tostring(action), true);
                end
                ui._delStatic = nil;
                imgui.CloseCurrentPopup();
            end
            if red then imgui.PopStyleColor(1); end
        else
            imgui.TextColored(COL.DIM, '(pick a set above to arm the delete)');
        end
        imgui.EndPopup();
    end

    -- Rename popup (2026-07-20): type the new name, one click renames the set
    -- everywhere (sets file + trigger rules + weights). Click-away aborts.
    if ui._renameOpen then imgui.OpenPopup('##dlac_setrename'); ui._renameOpen = false; end
    if imgui.BeginPopup('##dlac_setrename') then
        imgui.TextColored(COL.HEADER, 'Rename set: ' .. fmt.esc(tostring(M.workingSetName)));
        if imgui.IsWindowAppearing ~= nil and imgui.IsWindowAppearing()
           and imgui.SetKeyboardFocusHere ~= nil then imgui.SetKeyboardFocusHere(0); end
        ui._renameBuf = ui._renameBuf or { '' };
        imgui.PushItemWidth(200);
        imgui.InputText('##setrenname', ui._renameBuf, 32);
        imgui.PopItemWidth();
        imgui.SameLine(0, 6);
        if imgui.Button('Rename##setrengo', { 0, 22 }) then
            if renameCurrentSet(job, ui._renameBuf[1]) then imgui.CloseCurrentPopup(); end
        end
        fmt.textWrapped(COL.DIM, 'Renames the set and every reference to it: the sets file block, trigger rules (live at once) and its weights/build-slot marks. Sets hot-swap like Commit.');
        imgui.EndPopup();
    end
end

-- Stat weights in their OWN resizable, movable window (was a cramped right-side panel).
-- Shown while ui.showWeights is set (toggled by the Sets-tab "Weights" button); its own
-- [X] clears the toggle. Rendered as a top-level window, so it must be OUTSIDE the main
-- window's Begin/End (see drawWindow).
local function renderWeightsWindow(job, level)
    if not ui.showWeights then return; end
    imgui.SetNextWindowSize({ 480, 520 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 320, 240 }, { 1000, 1200 });
    local open = { true };
    if imgui.Begin('dlac Stat Weights###dlac_setweights', open, ImGuiWindowFlags_None) then
        pcall(renderSetsWeightPanel, job, level);
    end
    imgui.End();
    if open[1] == false then ui.showWeights = false; end
end

-- ---------------------------------------------------------------------------
-- Window + tab bar.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Tab registration (uihost): registration order = tab order. Every tab --
-- including gearui's own -- goes through the registry, so future modules can
-- contribute tabs/windows without touching this file (Trove's plugin model).
-- ---------------------------------------------------------------------------
-- Shared services first (modules capture these at require time), then the tab
-- modules -- each guarded so a broken module costs its tabs, never the window.
host.provide({
    -- shared state + palette + layout constants
    ui = ui, COL = COL, STATS_W = STATS_W,
    EQUIP_SLOTS = EQUIP_SLOTS, GEAR_OF = GEAR_OF,
    SLOT_ORDER = SLOT_ORDER, SLOT_TREE_ORDER = SLOT_TREE_ORDER, CAT_ORDER = CAT_ORDER,
    hasCatalog = has.catalog,
    -- gear data + candidate machinery
    effStats = effStats, isUsable = isUsable,
    lookupById = lookupById, lookupByName = lookupByName, displayName = displayName,
    buildOwned = buildOwned, buildAllEquip = buildAllEquip, ownedAugMap = ownedAugMap,
    candidatesForSlot = candidatesForSlot, subCandidatePool = subCandidatePool,
    subFilter = subFilter, sortForDisplay = sortForDisplay,
    parseSearch = parseSearch, itemSearchMatch = itemSearchMatch,
    -- equip / lock plumbing
    getPlayerInfo = getPlayerInfo,
    getEquippedId = getEquippedId, equipToSlot = equipToSlot,
    engineLocks = engineLocks, lacSlot = lacSlot,
    lockMirrorDirty = function() _lockMirror.at = -1; end,
    wornSetTotals = wornSetTotals, setLabelOf = setLabelOf,
    -- shared render helpers
    renderStatsPanel = renderStatsPanel, renderSlotGrid = renderSlotGrid,
    renderSortCombo = renderSortCombo, renderItemTooltip = renderItemTooltip,
});
do
    local ok, err = pcall(require, "dlac\\ui\\equippedui");   -- self-registers its two tabs
    if not ok then
        pcall(function() print('[dlac] equippedui failed to load: ' .. tostring(err)); end);
    end
    -- the floating equipment window + the pin menu (self-registers its window)
    local fok, ferr = pcall(require, "dlac\\ui\\floatgear");
    if not fok then
        pcall(function() print('[dlac] floatgear failed to load: ' .. tostring(ferr)); end);
    end
end
host.register({ name = 'sets', tabs = {
    { label = 'Sets', render = renderSetsTab },
}, window = {
    -- the separate, resizable Stat-weights window (Sets "Weights" toggle);
    -- rendered by host.renderWindows at the end of drawWindow
    render = renderWeightsWindow,
} });
host.register({ name = 'triggers', tabs = {
    { label = 'Triggers', render = function(job, level)
        if trigui ~= nil then trigui.render(job, level);
        else imgui.TextColored(COL.ERR, 'triggersui module unavailable.'); end
    end },
} });
-- Automations: its own MAIN tab (was a nav section inside Triggers), rendered by
-- its own module since 2026-07-18 -- ui\automationsui.lua owns the whole manifest
-- machinery (the extraction architecture.md used to note as "later").
host.register({ name = 'automations', tabs = {
    { label = 'Automations', render = function(job, level)
        if autoui ~= nil and type(autoui.renderTab) == 'function' then
            autoui.renderTab(job, level);
        else imgui.TextColored(COL.ERR, 'automationsui module unavailable.'); end
    end },
} });
-- Groups is NOT a standalone tab -- it's a section inside the Triggers tab (under
-- Modes), rendered by triggersui.renderGroups against the same trigger model.

local function drawWindow()
    if not M.visible or not has.imgui then return; end

    local owned = buildOwned();
    buildAllEquip();   -- populate catalog indexes for tooltips / worn-set totals
    local job, level = getPlayerInfo();

    imgui.SetNextWindowSize({ 940, 680 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 480, 340 }, { 1300, 1300 });

    local isOpen = { M.visible };
    if imgui.Begin('dlac Gear###ffxi_lac_gearui', isOpen, ImGuiWindowFlags_None) then
        -- Header line: Profiles menu (top-left), job/level + owned count + "Show
        -- all" toggle, then right-aligned buttons.
        if imgui.SmallButton('Profiles##dlac_pm_btn') then
            ui._profMenuBuild = true;   -- snapshot is (re)built on open, never per frame
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Every dlac profile on this install -- character > profile > jobs.\nSwitch or clone your own; import another character\'s profile into this one.');
        end
        imgui.SameLine(0, 10);
        imgui.TextColored(COL.HEADER, jobHeader());
        imgui.SameLine();
        imgui.TextColored(COL.DIM, string.format('|  %d owned%s', #owned, has.optim and '' or '  |  optimizer OFF'));
        imgui.SameLine(0, 12);
        imgui.Checkbox('Show all', ui.showAll);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Will show all equips, even if you don\'t have them.\nOff (default): the All Equipment tab lists only gear you own (gear.lua).\nOn: it lists the full CatsEyeXI catalog.');
        end
        renderHeaderButtons();
        if _augStatus ~= nil and _augStatus ~= '' then
            fmt.textWrapped(COL.SCORE, fmt.esc(_augStatus));
        end
        do  -- prominent warning when the current job isn't on the clean dlac standard yet
            local _st = setup.jobSetupState();
            if _st == 'ffxilac' or _st == 'none' then
                local _, _ab = jobFile();
                fmt.textWrapped(COL.ERR, string.format('  [!]  %s.lua is NOT set up for dlac -- click the red "Setup" button (top-right). Your file is backed up and replaced by a clean dlac profile; your old sets and groups stay importable from the backup.', tostring(_ab or '?')));
            elseif _st == 'wired' then
                local _, _ab = jobFile();
                fmt.textWrapped(COL.ERR, string.format('  [!]  %s.lua still runs its own logic alongside dlac (old-style conversion) -- click the red "Setup" button (top-right) to move to the clean profile standard. Your file is backed up first; nothing is lost.', tostring(_ab or '?')));
            end
        end

        imgui.Separator();

        if imgui.BeginTabBar('##ffxilac_tabs', ImGuiTabBarFlags_None) then
            -- A tab renderer that errors mid-frame leaves the imgui stack torn for
            -- the rest of the frame -- which presents as "buttons do nothing" with
            -- no trace. Surface every tab error LOUDLY: one chat line per distinct
            -- error and a sticky red banner in the tab (clears on a clean frame).
            local function tabGuard(name, fn, a, b)
                if ui._tabErr ~= nil and ui._tabErr[name] ~= nil then
                    fmt.textWrapped(COL.ERR, '[!] ' .. name .. ' tab error: ' .. fmt.esc(ui._tabErr[name]));
                end
                local ok, err = pcall(fn, a, b);
                ui._tabErr = ui._tabErr or {};
                if ok then
                    ui._tabErr[name] = nil;
                else
                    err = tostring(err);
                    if err ~= ui._tabErr[name] then
                        ui._tabErr[name] = err;
                        pcall(function() print('[dlac] ' .. name .. ' tab error: ' .. err); end);
                    end
                end
            end
            host.renderTabs(tabGuard, job, level);
            imgui.EndTabBar();
        end
    end
    imgui.End();

    -- Registered floating windows (each owns its visibility; the weights window
    -- is the first). A broken window costs itself, never the frame.
    host.renderWindows(function(name, fn, a, b) pcall(fn, a, b); end, job, level);

    -- Profiles menu: its own movable, RESIZABLE window since 2026-07-20 (was a
    -- BeginPopup inside the main Begin). The header button sets
    -- ui._profMenuBuild; render() snapshots, opens and draws it.
    pcall(pmenu.render);

    M.visible = (isOpen[1] == true);
end

-- ---------------------------------------------------------------------------
-- Render event: process the command queue every frame (even while hidden, so a
-- lock sequence completes), then draw while visible. Wrapped so a transient imgui
-- error can never take down the d3d_present hook.
-- ---------------------------------------------------------------------------
-- Gear auto-sync + UI-flag persistence: own module (dlac\syncflags.lua) -- the
-- flag state lives there (sf.flags.debug / sf.flags.autosync); the Ashita event
-- hooks stay HERE and call into it. Hook order is load-bearing: sf.loadUiFlags
-- runs before sf.tick in the d3d_present handler below, so the real <char>
-- gear.lua is swapped in before the first sync can run.
sf.configure({
    charBase = charBase, writeFileText = writeFileText,
    callImport = callImport, refreshGear = refreshGear,
    ui = ui,
    -- Regenerate the automations manifest (autogear.lua) at the sync cadence, so
    -- staves/obis/Iridescence detection never needs a manual Rescan. Builds the
    -- name indexes first: the UI may never have been opened.
    rescanAutogear = function()
        if autoui == nil or type(autoui.rescanAutogear) ~= 'function' then return; end
        buildOwned();
        buildAllEquip();
        autoui.rescanAutogear();
    end,
});

-- Any inventory-changing packet (loot, buy, trade, move -- 0x020 item update /
-- 0x01D inventory finish) schedules the debounced sync (see syncflags.lua).
ashita.events.register('packet_in', 'dlac-gearui-invdirty', function(e)
    if e.id == 0x020 or e.id == 0x01D then
        sf.invDirty();
    end
end);

ashita.events.register('d3d_present', 'dlac-gearui-render', function()
    cmdq.tick();   -- advance the frame clock, flush due commands
    if (cmdq.frame() % 240) == 0 then owned.resetCache(); end   -- availability heartbeat (~4s):
                                                                -- container moves recolour live
    pcall(sf.loadUiFlags);
    if ui._flagsDirty then ui._flagsDirty = nil; pcall(sf.saveUiFlags); end
    pcall(sf.tick);
    if macrob ~= nil then pcall(macrob.pump); end   -- per-job macro book/set (login + job change)
    pcall(function() require('dlac\\feature\\lockstyle').pump(); end);   -- OnLoad lockstyle (login + job change)
    -- Pins are session-only, and the clear has to reach DISK: the engine reads
    -- pinstate.lua from LAC's own state on its own schedule, so a file left over
    -- from last session would glue gear on at login. This must run whether or not
    -- the floating window is open -- it is the only thing that clears it.
    pcall(function() require('dlac\\feature\\pinwatch').loadPinState(); end);
    if ui.showMetrics == true and has.imgui then       -- /dl metrics: overlay hunter
        pcall(function() imgui.ShowMetricsWindow(ui.metricsOpen); end);
        if ui.metricsOpen ~= nil and ui.metricsOpen[1] == false then ui.showMetrics = false; end
    end
    -- PF-style floating Teleports button: lives on screen INDEPENDENT of the main
    -- window (pinned/unpinned from the Teleports menu footer; position remembered).
    -- THEMED like the main window -- unthemed, the semi-transparent defaults let
    -- the game world bleed through and recolor the icon.
    if ui._tpFloat == true and useit ~= nil and has.imgui then
        local tpThemed = style ~= nil and style.push();
        pcall(function()
            if ui._tpPos ~= nil then
                imgui.SetNextWindowPos({ ui._tpPos[1], ui._tpPos[2] }, ImGuiCond_Once or 0);
            end
            local fl = (ImGuiWindowFlags_NoTitleBar or 0) + (ImGuiWindowFlags_AlwaysAutoResize or 0)
                     + (ImGuiWindowFlags_NoScrollbar or 0) + (ImGuiWindowFlags_NoCollapse or 0);
            ui._tpOpenT = ui._tpOpenT or { true };
            ui._tpOpenT[1] = true;
            if imgui.Begin('##dlac_tpfloat', ui._tpOpenT, fl) then
                local pend = nil;
                pcall(function() pend = (type(useit.pending) == 'function') and useit.pending() or nil; end);
                local clicked = false;
                if pend ~= nil then
                    -- a use is in flight: the button IS the abort now
                    clicked = imgui.Button('##tpflstop', { 26, 26 });
                    pcall(function()
                        local x, y = imgui.GetItemRectMin();
                        if type(x) == 'table' then y = (x[2] or x.y); x = (x[1] or x.x); end
                        local dl = imgui.GetWindowDrawList();
                        dl:AddCircleFilled({ x + 13, y + 13 }, 10, imgui.GetColorU32({ 0.85, 0.20, 0.20, 1.0 }), 12);
                        dl:AddRectFilled({ x + 8, y + 11 }, { x + 18, y + 15 }, imgui.GetColorU32({ 1, 1, 1, 0.95 }));
                    end);
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip(string.format('ABORT %s  (%s)', tostring(pend.name), tostring(pend.cancel)));
                    end
                    if clicked and pend.cancel ~= nil then
                        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, pend.cancel); end);
                        clicked = false;
                    end
                else
                    -- The ring ICON, on an explicit OPAQUE dark backing (same one the
                    -- slot grid uses). The earlier "always red" was never the art: the
                    -- window rendered unthemed, and its semi-transparent button let
                    -- the game world bleed through the icon.
                    local rec = lookupByName('Warp Ring');
                    local id = rec and rec.Id or nil;
                    local h = icons.handleOf(id);
                    if h ~= nil then
                        pcall(function()
                            clicked = imgui.ImageButton(h, { 20, 20 },
                                { 0, 0 }, { 1, 1 }, 3, { 0.10, 0.10, 0.13, 1.0 }, { 1, 1, 1, 1 });
                        end);
                    else
                        clicked = imgui.Button('Tele##tpfl', { 36, 26 });
                    end
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip('Teleports  --  drag the edge to move; unpin from the menu.');
                    end
                end
                if clicked then imgui.OpenPopup('##dlac_teleports'); end
                pcall(renderTeleportsPopup);
                -- remember where it was dragged; save once the drag settles
                local px, py = imgui.GetWindowPos();
                if type(px) == 'table' then py = (px[2] or px.y); px = (px[1] or px.x); end
                if type(px) == 'number' and type(py) == 'number' then
                    px, py = math.floor(px), math.floor(py);
                    if ui._tpPos == nil or ui._tpPos[1] ~= px or ui._tpPos[2] ~= py then
                        ui._tpPos = { px, py };
                        ui._tpMovedAt = os.clock() + 1;
                    end
                end
            end
            imgui.End();
            if ui._tpMovedAt ~= nil and os.clock() >= ui._tpMovedAt then
                ui._tpMovedAt = nil;
                ui._flagsDirty = true;
            end
        end);
        if tpThemed then style.pop(); end
    end
    -- Floating Trigger Monitor: INDEPENDENT of the main box, like the lockstyle
    -- and floating-equipment windows (Henrik: it must survive closing dlac's
    -- main window). Own theme bracket.
    if ui._tgMon == true and trigui ~= nil and has.imgui then
        local tgThemed = style ~= nil and style.push();
        pcall(trigui.renderMonitor, ui);
        if tgThemed then style.pop(); end
    end
    -- Lockstyle window: INDEPENDENT of the main box (the header armor button
    -- opens it; it stays up if the main window closes). Own theme bracket,
    -- function-scoped require -- no new chunk local (hard rule 1).
    if has.imgui then
        local lsMod = nil;
        pcall(function() lsMod = require('dlac\\feature\\lockstyle'); end);
        if lsMod ~= nil and lsMod.visible == true then
            local lsThemed = style ~= nil and style.push();
            pcall(lsMod.render);
            if lsThemed then style.pop(); end
        end
    end
    -- Floating equipment window: INDEPENDENT of the main box, like the lockstyle
    -- window above -- the whole point is that it stays up while you play, so it
    -- CANNOT go through uihost's window contract (those render inside drawWindow,
    -- which returns early when the main window is shut). Own theme bracket,
    -- function-scoped require -- no new chunk local (hard rule 1).
    if has.imgui and ui._gearFloat == true then
        local fgMod = nil;
        pcall(function() fgMod = require('dlac\\ui\\floatgear'); end);
        if fgMod ~= nil then
            local fgThemed = style ~= nil and style.push();
            pcall(fgMod.render);
            if fgThemed then style.pop(); end
        end
    end
    if not M.visible or not has.imgui then return; end
    -- Theme push/pop brackets the pcall so an imgui error mid-draw can never
    -- leak the style stack (that would corrupt every OTHER addon's UI too).
    local themed = style ~= nil and style.push();
    pcall(drawWindow);
    if themed then style.pop(); end
end);

-- ---------------------------------------------------------------------------
-- Command hook:  /dl ui [on|off|show|hide|toggle]   (also /dlac ui ...)
-- Additive -- only acts on the `ui` subcommand; mirrors gearimport's argStart.
-- ---------------------------------------------------------------------------
local function argStart(raw)
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then return 7; end
    if raw == '/dl'       or string.sub(raw, 1, 4)  == '/dl '       then return 5;  end
    return nil;
end

ashita.events.register('command', 'dlac-ui', function(e)
    local raw   = string.lower(e.command);
    local start = argStart(raw);
    if start == nil then return; end

    local args = {};
    for a in string.gmatch(string.sub(raw, start), '[^%s]+') do
        table.insert(args, a);
    end
    local sub = args[1];
    if sub ~= 'ui' and sub ~= 'sync' and sub ~= 'autosync' and sub ~= 'debug'
       and sub ~= 'metrics' and sub ~= 'view_ids' then return; end
    e.blocked = true;

    if sub == 'metrics' then        -- imgui metrics window: names the window under the
                                    -- mouse ("Internal state" section) -- the tool for
                                    -- hunting invisible click-eating overlays
        ui.showMetrics = not (ui.showMetrics == true);
        ui.metricsOpen = { true };
        print('[dlac] imgui metrics ' .. (ui.showMetrics and 'ON -- hover the dead spot and read "HoveredWindow" under Internal state.' or 'OFF.'));
        return;
    end

    if sub == 'sync' then          -- manual one-shot: scan + import new gear now
        local n = sf.doSync();
        print(string.format('[dlac] sync: %s', (n > 0) and ('added ' .. n .. ' new item(s) to gear.lua.') or 'nothing new.'));
        return;
    end
    if sub == 'autosync' then       -- toggle the on-job-change auto-sync
        if     args[2] == 'off' then sf.flags.autosync = false;
        elseif args[2] == 'on'  then sf.flags.autosync = true; end
        sf.saveUiFlags();              -- persist; command wins over the on-disk value
        print('[dlac] auto-sync ' .. (sf.flags.autosync and 'ON' or 'OFF')
            .. ' -- indexes new gear on pickup, login and job change.  (/dl autosync on|off)');
        return;
    end
    if sub == 'view_ids' then       -- append item id + model id to every equipment tooltip
        if     args[2] == 'off' then sf.flags.viewids = false;
        elseif args[2] == 'on'  then sf.flags.viewids = true;
        else                         sf.flags.viewids = not sf.flags.viewids; end
        sf.saveUiFlags();              -- persist; command wins over the on-disk value
        print('[dlac] view_ids ' .. (sf.flags.viewids
            and 'ON -- hover any equipment: the tooltip now ends with its item id and its model id (the model is what a lockstyle shows).'
            or  'OFF -- ids hidden again.  (/dl view_ids on)'));
        return;
    end
    if sub == 'debug' then          -- reveal/hide the dev-only Scan/Stage/Commit/Augs buttons
        if     args[2] == 'off' then sf.flags.debug = false;
        elseif args[2] == 'on'  then sf.flags.debug = true;
        else                          sf.flags.debug = not sf.flags.debug; end
        sf.saveUiFlags();              -- persist; command wins over the on-disk value
        print('[dlac] debug ' .. (sf.flags.debug and 'ON -- Scan/Stage/Commit/Augs buttons shown.'
            or 'OFF -- header tidied; auto-sync keeps gear.lua current.  (/dl debug on)'));
        return;
    end

    -- sub == 'ui'
    local mode = args[2];
    if mode == 'on' or mode == 'show' then
        M.visible = true;
    elseif mode == 'off' or mode == 'hide' then
        M.visible = false;
    else
        M.visible = not M.visible;
    end

    -- No routine chat line on toggle (inform by printing as little as
    -- possible) -- the window appearing/disappearing IS the feedback. Only
    -- the can't-show failure case still speaks.
    if M.visible and not has.imgui then
        print('[dlac] gear UI: imgui is unavailable in this context; nothing to show.');
    end
end);

-- ---------------------------------------------------------------------------
-- Cleanup on addon unload: drop our callbacks and free the icon textures.
-- ---------------------------------------------------------------------------
ashita.events.register('unload', 'dlac-gearui-unload', function()
    pcall(function() ashita.events.unregister('d3d_present', 'dlac-gearui-render'); end);
    pcall(function() ashita.events.unregister('command', 'dlac-ui'); end);
    pcall(function() ashita.events.unregister('packet_in', 'dlac-gearui-invdirty'); end);
    pcall(icons.release);
end);

return M;
