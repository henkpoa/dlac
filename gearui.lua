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

-- Shared libs live in Ashita\addons\libs and are require-able from a profile the
-- same way gearimport requires 'encoding'. Guard each so a missing lib degrades
-- gracefully (no window / no icons) instead of erroring.
local _iok, imgui = pcall(require, 'imgui');
local _fok, ffi   = pcall(require, 'ffi');
local _dok, d3d   = pcall(require, 'd3d8');
local _ook, optim = pcall(require, "dlac\\gearoptim");
-- Full CatsEyeXI equipment reference (1306 items), same nested shape as gear.lua.
-- Powers the "All Equipment" browse tab only; falls back to gear.lua if missing.
local _cok, catalog = pcall(require, "dlac\\catalog");
-- Dynamic-set writer (commit/delete a set into the <JOB>.lua file). Sets tab only.
local _sok, setmgr = pcall(require, "dlac\\setmanager");
-- Augment reader: decode private augments from item Extra bytes (worn-stat totals).
local _augok, aug  = pcall(require, "dlac\\augments");

local hasImgui    = _iok and imgui ~= nil;
local hasD3D      = _fok and _dok and ffi ~= nil and d3d ~= nil;
local hasOptim    = _ook and type(optim) == 'table';
local hasCatalog  = _cok and type(catalog) == 'table';
local hasSetmgr   = _sok and type(setmgr) == 'table';
local hasAug      = _augok and type(aug) == 'table';

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
    sortMode  = 'Name',       -- gear-list sort: 'Name' | 'Level'
    -- Sets tab
    setSelected = nil,
    newSetName  = { '' },
    lockSet     = { false },
    setsDynamic = { true },   -- Auto-build "Dynamic" (level-scaling list) mode, default ON
    buildMax    = { false },  -- optimizer "build as lv.75" toggle (mirrors optim.buildAtMaxLevel)
    ignoreWeapons = { true }, -- Auto-build: skip Main/Sub/Range so weapon swaps don't reset TP (default ON)
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
local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_USABLE = { 1.00, 1.00, 1.00, 1.00 };
local COL_LOCKED = { 0.55, 0.55, 0.60, 1.00 };
local COL_LEVEL  = { 0.70, 0.70, 0.78, 1.00 };
local COL_JOBS   = { 0.55, 0.78, 0.55, 1.00 };
local COL_STATS  = { 0.62, 0.62, 0.70, 1.00 };
local COL_DIM    = { 0.70, 0.70, 0.70, 1.00 };
local COL_SCORE  = { 0.95, 0.85, 0.45, 1.00 };
local COL_DMG    = { 0.90, 0.80, 0.45, 1.00 };
local COL_ERR    = { 1.00, 0.45, 0.40, 1.00 };

-- ---------------------------------------------------------------------------
-- Item-icon loader (trove/equipmon load_item_texture). One D3D texture per item
-- id from the resource's in-memory bitmap, cached, drawn with imgui.Image. A no-op
-- (blank placeholder) when d3d8 / ffi could not be required.
-- ---------------------------------------------------------------------------
local C, d3d8dev;
if hasD3D then
    C = ffi.C;
    local okdev, dev = pcall(function() return d3d.get_device(); end);
    if okdev and dev ~= nil then
        d3d8dev = dev;
    else
        hasD3D = false;
    end
    if hasD3D then
        pcall(function()
            ffi.cdef[[
                HRESULT __stdcall D3DXCreateTextureFromFileInMemoryEx(IDirect3DDevice8* pDevice, const void* pSrcData, unsigned int SrcDataSize, unsigned int Width, unsigned int Height, unsigned int MipLevels, unsigned int Usage, int Format, int Pool, unsigned int Filter, unsigned int MipFilter, unsigned int ColorKey, void* pSrcInfo, void* pPalette, IDirect3DTexture8** ppTexture);
            ]];
        end);
    end
end

local texCache   = {};   -- itemId -> texture (or false once we know it has none)
local texHandles = {};   -- itemId -> uint32 handle for imgui.Image

local function loadItemTexture(itemId)
    if not hasD3D then return false; end
    if texCache[itemId] ~= nil then return texCache[itemId]; end
    if itemId == nil or itemId == 0 then texCache[itemId] = false; return false; end

    local item = AshitaCore:GetResourceManager():GetItemById(itemId);
    if item == nil or item.ImageSize == nil or item.ImageSize == 0 then
        texCache[itemId] = false;
        return false;
    end

    pcall(function()
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if (C.D3DXCreateTextureFromFileInMemoryEx(
                d3d8dev, item.Bitmap, item.ImageSize,
                0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
                C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED,
                C.D3DX_DEFAULT, C.D3DX_DEFAULT,
                0xFF000000, nil, nil, ptr) == C.S_OK) then
            local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
            texCache[itemId]   = tex;
            texHandles[itemId] = tonumber(ffi.cast('uint32_t', tex));
        end
    end);

    if texCache[itemId] == nil then texCache[itemId] = false; end
    return texCache[itemId];
end

-- Draw an item icon (or a blank placeholder), then SameLine so the caller can put
-- the item's text right after it.
local function renderIcon(itemId, size)
    local drew = false;
    if itemId ~= nil and itemId ~= 0 then
        local tex = loadItemTexture(itemId);
        local handle = texHandles[itemId];
        if tex and tex ~= false and handle ~= nil then
            pcall(function() imgui.Image(handle, { size, size }); end);
            drew = true;
        end
    end
    if not drew then
        pcall(function() imgui.Dummy({ size, size }); end);
    end
    imgui.SameLine(0, 6);
end

local function releaseTextures()
    for _, tex in pairs(texCache) do
        if tex and tex ~= false then
            pcall(function()
                ffi.gc(tex, nil);
                tex:Release();
            end);
        end
    end
    texCache   = {};
    texHandles = {};
end

-- ---------------------------------------------------------------------------
-- Flatten any gear-shaped table (gear.lua OR catalog.lua -- identical structure)
-- into a sorted record list plus by-Id / by-Name indexes. Walked exactly the way
-- gear.lua's NameToObject builder walks (a table with a .Name is an entry; anything
-- else is a container). Records are fresh copies, so per-row memo fields never
-- mutate the source table.
-- ---------------------------------------------------------------------------
local function flattenGear(src)
    local list, byId, byName = {}, {}, {};
    local function add(slot, category, key, e)
        local rec = {
            Name = e.Name, Level = e.Level or 0, Id = e.Id, Jobs = e.Jobs,
            Slot = slot, Category = category, Type = e.Type, Stats = e.Stats,
            Key = key,                     -- gear.lua table key, for building a commit path
            OneHanded = e.OneHanded,       -- weapon 1H vs 2H (Sub-slot pairing rules)
            InBothHands = e.InBothHands,   -- owns two copies for same-weapon dual-wield
        };
        list[#list + 1] = rec;
        if rec.Id ~= nil then byId[rec.Id] = rec; end
        if type(rec.Name) == 'string' then byName[string.lower(rec.Name)] = rec; end
    end
    local function walk(slot, container, category)
        for key, v in pairs(container) do
            if type(v) == 'table' then
                if v.Name ~= nil then
                    add(slot, category, key, v);
                else
                    walk(slot, v, (category == nil) and tostring(key) or category);
                end
            end
        end
    end
    if type(src) == 'table' then
        for slot, slotVars in pairs(src) do
            if slot ~= 'NameToObject' and type(slotVars) == 'table' then
                walk(slot, slotVars, nil);
            end
        end
    end
    table.sort(list, function(a, b)
        if a.Slot ~= b.Slot then return tostring(a.Slot) < tostring(b.Slot); end
        local ca, cb = a.Category or '', b.Category or '';
        if ca ~= cb then return ca < cb; end
        if a.Level ~= b.Level then return (a.Level or 0) < (b.Level or 0); end
        return tostring(a.Name) < tostring(b.Name);
    end);
    return list, byId, byName;
end

-- Full CatsEyeXI reference (catalog.lua) for the All Equipment tab + item lookups.
-- Falls back to gear.lua if catalog failed to load, so the tab always works.
local _allEquip, _allEquipById, _allEquipByName;
local function buildAllEquip()
    if _allEquip == nil then _allEquip, _allEquipById, _allEquipByName = flattenGear(hasCatalog and catalog or gear); end
    return _allEquip;
end

-- Fill the RAW gear table with catalog stats, in place, once. A Phase-2 gear.lua carries no
-- Stats (owned is a thin ownership record); the catalog has stats for every item by Id. We
-- mutate the shared `gear` table so BOTH the GUI (flattenGear copies e.Stats) and the
-- optimizer (gearoptim reads the same table) see stats. catalog is the base; a stat already
-- on the entry wins (owned overrides, catalog only fills gaps).
local _gearEnriched = false;
local function enrichGearFromCatalog()
    if _gearEnriched or not hasCatalog then return; end
    buildAllEquip();   -- ensure the catalog id-index (_allEquipById) exists
    local function walk(container)
        for _, v in pairs(container) do
            if type(v) == 'table' then
                if v.Id ~= nil and v.Name ~= nil then                       -- an item entry
                    local c = _allEquipById[v.Id];
                    if c ~= nil and type(c.Stats) == 'table' and next(c.Stats) ~= nil then
                        if type(v.Stats) ~= 'table' or next(v.Stats) == nil then
                            v.Stats = c.Stats;
                        else
                            local m = {};
                            for k, x in pairs(c.Stats) do m[k] = x; end
                            for k, x in pairs(v.Stats) do m[k] = x; end
                            v.Stats = m;
                        end
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
-- Small display / eligibility helpers.
-- ---------------------------------------------------------------------------
local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

local function truncate(s, n)
    s = tostring(s or '');
    if #s <= n then return s; end
    return s:sub(1, n - 2) .. '..';
end

local function sortedKeys(t)
    local ks = {};
    for k in pairs(t) do ks[#ks + 1] = k; end
    table.sort(ks);
    return ks;
end

local function jobsText(jobs)
    if jobs == nil then return 'All'; end
    if type(jobs) ~= 'table' or #jobs == 0 then return 'All'; end
    return table.concat(jobs, '/');
end

-- Eligibility (the single source of truth for every candidate / alternatives /
-- "usable now" list): Jobs contains the current main job -- or Jobs is {"All"} /
-- unrestricted -- AND Level <= the current main-job level.
local function jobCanEquip(jobs, playerJob)
    if jobs == nil then return true; end                       -- no restriction
    if type(jobs) ~= 'table' or #jobs == 0 then return true; end
    for _, j in ipairs(jobs) do
        if j == 'All' then return true; end
        if playerJob ~= nil and playerJob ~= '' and j == playerJob then return true; end
    end
    return false;
end

local function isUsable(rec, playerJob, playerLevel)
    if (rec.Level or 0) > (playerLevel or 0) then return false; end
    return jobCanEquip(rec.Jobs, playerJob);
end

local function fmtStat(k, v)
    if type(v) == 'boolean' then return k; end
    if type(v) == 'number' then return k .. ((v >= 0) and '+' or '') .. tostring(v); end
    return k .. ':' .. tostring(v);
end

-- Priority order for compact summaries / totals; anything else comes after, alpha.
local STAT_PRIORITY = {
    'DMG', 'Delay', 'DEF', 'HP', 'MP', 'Accuracy', 'Attack', 'Haste',
    'MATK', 'MagicAttack', 'RangedAccuracy', 'STR', 'DEX', 'VIT', 'AGI',
    'INT', 'MND', 'CHR', 'Evasion', 'Enmity', 'StoreTP',
};

-- Compact (<=4 token) stat line for rows. Memoized on the record.
local function statSummary(rec)
    if rec._statStr ~= nil then return rec._statStr; end
    local stats, out = rec.Stats, '';
    if type(stats) == 'table' then
        local parts, used = {}, {};
        for _, k in ipairs(STAT_PRIORITY) do
            local v = stats[k];
            if v ~= nil and type(v) ~= 'table' then
                parts[#parts + 1] = fmtStat(k, v); used[k] = true;
                if #parts >= 4 then break; end
            end
        end
        if #parts < 4 then
            for k, v in pairs(stats) do
                if not used[k] and type(k) == 'string' and type(v) ~= 'table' then
                    parts[#parts + 1] = fmtStat(k, v);
                    if #parts >= 4 then break; end
                end
            end
        end
        out = table.concat(parts, ' ');
    end
    rec._statStr = out;
    return out;
end

-- Full stat line for the tooltip (all stats, priority first, DMG/Delay & Pet omitted).
local function fullStatList(stats)
    if type(stats) ~= 'table' then return ''; end
    local parts, used = {}, {};
    for _, k in ipairs(STAT_PRIORITY) do
        local v = stats[k];
        if v ~= nil and type(v) ~= 'table' and k ~= 'DMG' and k ~= 'Delay' then
            parts[#parts + 1] = fmtStat(k, v); used[k] = true;
        end
    end
    for k, v in pairs(stats) do
        if type(k) == 'string' and not used[k] and type(v) ~= 'table' and k ~= 'DMG' and k ~= 'Delay' then
            parts[#parts + 1] = fmtStat(k, v);
        end
    end
    return table.concat(parts, ' ');
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

-- ---------------------------------------------------------------------------
-- Candidate lists (eligible OWNED gear per slot), memoized per job/level.
-- Re-sorted by weighted score when weights exist; invalidate on weight edits.
-- ---------------------------------------------------------------------------
local candCache = { key = nil, data = {} };
local function invalidateCandidates() candCache.key = nil; end

-- Live owned quantities (defined further below; needs gearimport). Forward-declared
-- so candidate lists can filter to gear that is actually in your bags -- gear.lua is a
-- curated DB and can list items you no longer own (e.g. a base "Garrison Sallet" when
-- you only have the +1). Safe fallback: if the live scan returns nothing (inventory
-- manager unavailable / char select), don't hide anything.
local ownedCounts;
local function haveInBags(rec)
    if rec == nil or rec.Id == nil then return true; end
    local oc = ownedCounts and ownedCounts() or nil;
    if type(oc) ~= 'table' or next(oc) == nil then return true; end
    return (oc[rec.Id] or 0) >= 1;
end

local function weightsActive()
    if not hasOptim or optim.getWeights == nil then return false; end
    local ok, ws = pcall(optim.getWeights);
    if not ok or type(ws) ~= 'table' then return false; end
    for _ in pairs(ws) do return true; end
    return false;
end

local function scoreOf(stats)
    if not hasOptim or optim.score == nil then return 0; end
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
    if hasAug then pcall(function() m = aug.ownedAugStats() or {}; end); end
    _ownedAugStats = m;
    return _ownedAugStats;
end

-- Weighted score of an ITEM: base Stats PLUS the augment deltas on the copy you own (by Id),
-- so augmented gear is weighed correctly. Use this (not scoreOf) when scoring a gear record.
local function scoreOfItem(rec)
    if rec == nil then return 0; end
    local base = rec.Stats;
    local a = (rec.Id ~= nil) and ownedAugStatsMap()[rec.Id] or nil;
    if a == nil then return scoreOf(base); end
    local combined = {};
    if type(base) == 'table' then for k, v in pairs(base) do combined[k] = v; end end
    for k, v in pairs(a) do combined[k] = (combined[k] or 0) + v; end
    return scoreOf(combined);
end

-- Effective item-Level cap for SET BUILDING (Auto-build + the manual + Add picker): the
-- "Build as lv.75" toggle (optim.buildAtMaxLevel) lifts the cap to 75 so you can assemble
-- over-level sets; the job restriction is unaffected. The Equipped tab keeps the real level.
local function setBuildLevel(level)
    if hasOptim and optim.buildAtMaxLevel == true then return optim.MAX_LEVEL or 75; end
    return level;
end

local function candidatesForSlot(gearSlotKey, job, level)
    local key = tostring(job) .. '|' .. tostring(level);
    if candCache.key ~= key then candCache.key = key; candCache.data = {}; end
    if candCache.data[gearSlotKey] ~= nil then return candCache.data[gearSlotKey]; end

    local out = {};
    for _, rec in ipairs(buildOwned()) do
        if rec.Slot == gearSlotKey and isUsable(rec, job, level) and haveInBags(rec) then
            out[#out + 1] = rec;
        end
    end

    local useScore = weightsActive();
    table.sort(out, function(a, b)
        if useScore then
            local sa, sb = scoreOfItem(a), scoreOfItem(b);
            if sa ~= sb then return sa > sb; end
        end
        if (a.Level or 0) ~= (b.Level or 0) then return (a.Level or 0) > (b.Level or 0); end
        return tostring(a.Name) < tostring(b.Name);
    end);

    candCache.data[gearSlotKey] = out;
    return out;
end

-- ---------------------------------------------------------------------------
-- Worn-set stat totals (our data only): sum the Stats of the 16 equipped items.
-- ---------------------------------------------------------------------------
local function wornSetTotals()
    local totals = {};
    for _, sl in ipairs(EQUIP_SLOTS) do
        local id  = getEquippedId(sl.equip);
        local rec = lookupById(id);
        if rec == nil and id ~= nil then rec = lookupByName(displayName(id)); end
        if rec ~= nil and type(rec.Stats) == 'table' then
            for k, v in pairs(rec.Stats) do
                if type(v) == 'number' and k ~= 'DMG' and k ~= 'Delay' then
                    totals[k] = (totals[k] or 0) + v;
                end
            end
        end
    end
    -- Fold in live augment deltas so worn totals reflect base + your private augments.
    if hasAug then
        local ok, augTotals = pcall(aug.wornStats);
        if ok and type(augTotals) == 'table' then
            for k, v in pairs(augTotals) do
                if k ~= 'DMG' and k ~= 'Delay' then totals[k] = (totals[k] or 0) + v; end
            end
        end
    end
    return totals;
end

-- ---------------------------------------------------------------------------
-- Frame-delayed command queue (for the "Lock when equipped" enable/equip/disable
-- sequence). Processed every frame in d3d_present so it never blocks.
-- ---------------------------------------------------------------------------
local frameCounter = 0;
local cmdQueue = {};

local function enqueueCmd(delayFrames, cmd)
    cmdQueue[#cmdQueue + 1] = { at = frameCounter + math.max(0, delayFrames), cmd = cmd };
end

local function processCmdQueue()
    if #cmdQueue == 0 then return; end
    local remaining = {};
    for _, c in ipairs(cmdQueue) do
        if frameCounter >= c.at then
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, c.cmd); end);
        else
            remaining[#remaining + 1] = c;
        end
    end
    cmdQueue = remaining;
end

local function lacSlot(label) return string.lower(tostring(label or '')); end

-- Equip an item into a slot. Three modes:
--   freeEquip -- LAC is globally disabled (Free-equip mode); send the *native* game
--                /equip command so it bypasses LAC entirely and sticks (LAC won't
--                re-override while disabled). This is the "equip outside LAC" path.
--   lock      -- /lac disable the slot ONCE (tracked, so repeat clicks don't re-disable
--                and spam "<slot> disabled"), then native /equip so LAC leaves it put.
--   default   -- /lac equip temp-swap (LAC may re-override on the next action).
-- Per-slot lock state: slots we've already /lac disabled (cleared on enable -- see below).
local _disabledSlots = {};
local function equipToSlot(slotLabel, itemName, lock, freeEquip)
    if slotLabel == nil or itemName == nil then return; end
    local slot = lacSlot(slotLabel);
    local nm   = tostring(itemName);
    if freeEquip then
        pcall(function()
            AshitaCore:GetChatManager():QueueCommand(1, string.format('/equip %s "%s"', slot, nm));
        end);
    elseif lock then
        -- Lock this one slot: /lac disable it (only the FIRST time -- tracked in
        -- _disabledSlots so repeat clicks don't re-send /lac disable), then native /equip
        -- so LAC leaves just this slot put. Uncheck "Lock when equipped" to re-enable it.
        if _disabledSlots[slot] then
            enqueueCmd(2, string.format('/equip %s "%s"', slot, nm));          -- already locked; just equip
        else
            enqueueCmd(2,  string.format('/lac disable %s', slot));            -- disable once...
            enqueueCmd(26, string.format('/equip %s "%s"', slot, nm));         -- ...then equip after it settles
            _disabledSlots[slot] = true;
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

-- gearimport.ownedCounts() -> { [Id]=count } across all bags incl. equipped.
-- Cached; refreshed on Scan / Reload.
local _ownedCounts = nil;
local _ownedAug    = nil;   -- cached { itemId -> {augment-desc, ...} } for owned gear
function ownedCounts()   -- assigns the forward-declared upvalue (see haveInBags)
    if _ownedCounts ~= nil then return _ownedCounts; end
    local counts = {};
    pcall(function()
        local ok, mod = pcall(require, "dlac\\gearimport");
        if ok and mod ~= nil and type(mod.ownedCounts) == 'function' then
            local c = mod.ownedCounts();
            if type(c) == 'table' then counts = c; end
        end
    end);
    _ownedCounts = counts;
    return counts;
end
local function refreshOwnedCounts() _ownedCounts = nil; _ownedAug = nil; _ownedAugStats = nil; invalidateCandidates(); end

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
            pcall(function() if hasOptim and type(optim.invalidate) == 'function' then optim.invalidate(); end end);
        end
    end);
end

-- Owned augments per item id (from the live bag scan), cached; refreshed on Reload/Scan.
local function ownedAugMap()
    if _ownedAug ~= nil then return _ownedAug; end
    local m = {};
    if hasAug then pcall(function() m = aug.ownedAugments() or {}; end); end
    _ownedAug = m;
    return _ownedAug;
end

-- Sub job abbreviation + effective level (honours the staticSubLevel override).
local function getSubInfo()
    local sj, slv = nil, 0;
    pcall(function()
        if gData == nil or gData.GetPlayer == nil then return; end
        local p = gData.GetPlayer();
        if p == nil then return; end
        sj = p.SubJob;
        if type(staticSubLevel) == 'number' and staticSubLevel > 0 then slv = staticSubLevel;
        else slv = p.SubJobSync or 0; end
    end);
    return sj, slv;
end

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

-- Is a Sub-slot record valid given the current Main record? Mirrors
-- utils.BuildDynamicSets: 2H main -> Grip only; 1H main -> Shield, or a 1H weapon
-- when dual-wield is up (same-name needs two copies via InBothHands or ownedCount>=2).
local function subCandidateOk(subRec, mainRec, mainJob, mainLevel, subJob, subLevel, oc)
    if mainRec == nil then return false; end          -- no Main -> no Sub
    local st = subRec.Type;
    if mainRec.OneHanded == false then
        return st == 'Grip';
    elseif mainRec.OneHanded == true then
        if st == 'Shield' then return true; end
        if subRec.OneHanded == true and isDualWieldAvailable(mainJob, mainLevel, subJob, subLevel) then
            if subRec.Name == mainRec.Name then
                if subRec.InBothHands == true then return true; end
                return (((oc and subRec.Id) and oc[subRec.Id]) or 0) >= 2;
            end
            return true;   -- a different 1H weapon
        end
        return false;
    end
    return false;
end

-- Filter a Sub candidate list against the current Main record.
local function subFilter(cands, mainRec, job, level)
    if mainRec == nil then return {}; end
    local sj, slv = getSubInfo();
    local oc = ownedCounts();
    local out = {};
    for _, r in ipairs(cands) do
        if subCandidateOk(r, mainRec, job, level, sj, slv, oc) then out[#out + 1] = r; end
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
    local oc = ownedCounts();
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
        imgui.TextColored(COL_HEADER, esc(rec.Name or '?'));
        local typeStr = rec.Type or rec.Category or rec.Slot;
        if typeStr ~= nil then imgui.TextColored(COL_DIM, '(' .. esc(tostring(typeStr)) .. ')'); end
        local stats = rec.Stats;
        if type(stats) == 'table' and type(stats.DMG) == 'number' and type(stats.Delay) == 'number' then
            imgui.TextColored(COL_DMG, string.format('DMG:%s Delay:%s', tostring(stats.DMG), tostring(stats.Delay)));
        end
        local sl = fullStatList(stats);
        if sl ~= '' then imgui.TextColored(COL_STATS, esc(sl)); end
        local jt = jobsText(rec.Jobs);
        if jt == 'All' then jt = 'All Jobs'; end
        imgui.TextColored(COL_JOBS, string.format('Lv.%s %s', tostring(rec.Level or 0), jt));
        if rec.Id ~= nil then                          -- private augments on your owned copy
            local al = ownedAugMap()[rec.Id];
            if al ~= nil and #al > 0 then
                local more = (#al > 1) and string.format('   (+%d more copies)', #al - 1) or '';
                imgui.TextColored(COL_SCORE, 'Aug: ' .. esc(al[1]) .. more);
            end
        end
    end);
    imgui.EndTooltip();
end

-- ---------------------------------------------------------------------------
-- gearimport module (header Stage / Commit / Scan buttons).
-- ---------------------------------------------------------------------------
local function callImport(fn)
    local ok, mod = pcall(require, "dlac\\gearimport");
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
    if not hasAug then _augStatus = 'Augment reader unavailable.'; return; end
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
-- ---------------------------------------------------------------------------
local JOB_ABBR = {
    [1]='WAR',[2]='MNK',[3]='WHM',[4]='BLM',[5]='RDM',[6]='THF',[7]='PLD',[8]='DRK',
    [9]='BST',[10]='BRD',[11]='RNG',[12]='SAM',[13]='NIN',[14]='DRG',[15]='SMN',[16]='BLU',
    [17]='COR',[18]='PUP',[19]='DNC',[20]='SCH',[21]='GEO',[22]='RUN',
};
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

-- Current main job's <JOB>.lua path + its abbr (or nil, nil).
local function jobFile()
    local base = charBase();
    if base == nil then return nil, nil; end
    local abbr = nil;
    pcall(function() abbr = JOB_ABBR[AshitaCore:GetMemoryManager():GetPlayer():GetMainJob()]; end);
    if abbr == nil then return nil, nil; end
    return base .. abbr .. '.lua', abbr;
end

-- Is the current job's <JOB>.lua already wired for dlac?
--   'ok'      -> requires the dlac library AND every handler ends in utils.dispatch (healthy)
--   'shims'   -> requires the library but one or more handlers lack the dispatch shim
--   'ffxilac' -> still an ffxi-lac profile (needs conversion)
--   'none'    -> a custom/other profile (needs in-place conversion -- logic is KEPT)
--   'nofile' / 'nojob' -> no profile file / no job.
-- Cached per file; cleared after a Setup run (see below).
local _setupState, _setupStateJob = nil, nil;
local function jobSetupState()
    local jf = jobFile();
    if jf == nil then return 'nojob'; end
    if _setupStateJob == jf and _setupState ~= nil then return _setupState; end
    local st;
    local text = readFileText(jf);
    if text == nil then st = 'nofile';
    elseif text:find([[dlac\\utils]], 1, true) then
        st = 'ok';
        -- per-handler shim health: every Handle* must exist and END with its dispatch call
        if hasSetmgr and type(setmgr.analyzeShims) == 'function' then
            local aok, a = pcall(setmgr.analyzeShims, text);
            if aok and type(a) == 'table' and a.healthy ~= true then st = 'shims'; end
        end
    elseif text:find('ffxi-lac', 1, true) then st = 'ffxilac';
    else st = 'none'; end
    _setupState, _setupStateJob = st, jf;
    return st;
end

-- One-line bootstrap that puts the dlac addon library on the profile's package.path so
-- require("dlac\\utils") resolves to the addon. [[...]] keeps the backslashes literal.
local MIGRATE_BOOT = [[package.path = package.path .. ';' .. AshitaCore:GetInstallPath() .. 'addons\\?.lua';  -- dlac: use the dlac addon library]];

-- Transform ffxi-lac profile text -> dlac: repoint requires/loadfile + add the addon lib
-- to package.path (idempotent). Returns the new text.
local function migrateJobText(text)
    local out = (text:gsub('ffxi%-lac', 'dlac'));
    if not out:find([[addons\\?.lua]], 1, true) then out = MIGRATE_BOOT .. '\n' .. out; end
    return out;
end

-- Starter profile written when a job has no dlac profile yet. This mirrors LuaAshitacast's
-- own `/lac newlua` skeleton (OnLoad/AllowAddSet kept, so `/lac addset` works) and adds the
-- dlac wiring: the require, a Dynamic sets scaffold, `utils.rebuildSets(sets)` plus a
-- `utils.dispatch('<Handler>')` shim in every handler (ADR 0002). ALL equip logic is data
-- in <char>\dlac\triggers\<JOB>.lua -- Setup seeds it with the classic status rules
-- (Engaged/Resting/Movement/Idle) so a fresh profile behaves out of the box. Build sets in
-- the GUI (Sets tab); wire behavior in the Triggers tab (or edit the trigger file directly).
-- MIGRATE_BOOT is prepended when written so LAC can resolve require("dlac\\utils"). Inside
-- [[...]] the backslashes are literal on purpose.
local STARTER_PROFILE = [[
local profile = {};
local utils = require("dlac\\utils");   -- everything comes through this one require
local gear  = utils.gear;               -- the shared gear inventory
local sets = {
    Dynamic = {                         -- dlac: build these in the GUI (Sets tab); best-per-level is auto-picked
        Idle       = {},
        Tp_Default = {},
        Resting    = {},
        Movement   = {},
    },
};
profile.Sets = sets;

profile.Packer = {
};

profile.OnLoad = function()
    gSettings.AllowAddSet = true;
end

profile.OnUnload = function()
end

profile.HandleCommand = function(args)
end

-- All equip logic is data: utils.dispatch reads <char>\dlac\triggers\<JOB>.lua
-- (hot-reloaded -- edit triggers in the dlac GUI or the file; no /lac reload needed).
profile.HandleDefault = function()
    sets = utils.rebuildSets(sets);
    utils.dispatch('Default');
end

profile.HandleAbility     = function() utils.dispatch('Ability');     end
profile.HandleItem        = function() utils.dispatch('Item');        end
profile.HandlePrecast     = function() utils.dispatch('Precast');     end
profile.HandleMidcast     = function() utils.dispatch('Midcast');     end
profile.HandlePreshot     = function() utils.dispatch('Preshot');     end
profile.HandleMidshot     = function() utils.dispatch('Midshot');     end
profile.HandleWeaponskill = function() utils.dispatch('Weaponskill'); end

return profile;
]];

-- Seed <char>\dlac\triggers\<JOB>.lua with the classic status rules (never clobbers an
-- existing file). The starter text lives in dispatch.lua (single source of truth); the
-- addon-state copy of dispatch is inert but its exports are still readable. Returns true
-- when a file was written.
local function seedTriggersFile(base, abbr)
    if base == nil or abbr == nil then return false; end
    local path = base .. 'dlac\\triggers\\' .. abbr .. '.lua';
    if readFileText(path) ~= nil then return false; end   -- user data: never overwrite
    local ok, dsp = pcall(require, "dlac\\dispatch");
    if not ok or type(dsp) ~= 'table' or type(dsp.starterTriggersText) ~= 'string' then return false; end
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then
            ashita.fs.create_directory(base .. 'dlac\\triggers\\');
        end
    end);
    return writeFileText(path, dsp.starterTriggersText);
end

-- Set up the current job's <JOB>.lua for dlac. Convert-IN-PLACE policy: an existing
-- profile's own logic is NEVER removed or replaced -- Setup only adds the dlac require,
-- appends `utils.dispatch('<H>')` at the END of each existing handler (their code runs
-- first; dlac overlays last), and creates the handlers they don't have. Idempotent:
-- clicking Setup on a healthy profile changes nothing.
--   'ok'      -> healthy (still seeds a missing trigger file, then reports).
--   'shims'   -> dlac profile missing shims -> repair (setmanager.repairShims).
--   'ffxilac' -> repoint requires at dlac (backup .flbak), then repair shims.
--   'none'    -> custom profile: backup .flbak, add bootstrap+require, repair shims.
--   'nofile'  -> initialize from scratch: write the self-contained dlac starter.
-- Also seeds <char>\dlac\ with a gear.lua (from an existing ffxi-lac folder, else the
-- bundled empty template) and a starter triggers\<JOB>.lua so the dispatch shims have
-- data to act on (ADR 0002).
local function migrateCurrentJob()
    local base = charBase();
    if base == nil then _augStatus = 'Setup: log in first (no character folder).'; return; end
    local jf, abbr = jobFile();
    if jf == nil then _augStatus = 'Setup: unknown job.'; return; end
    local state = jobSetupState();

    if state == 'ok' then
        local seeded = seedTriggersFile(base, abbr);
        _augStatus = abbr .. '.lua is already set up for dlac.'
            .. (seeded and ('  Seeded starter triggers\\' .. abbr .. '.lua.') or '');
        return;
    end

    -- seed <char>\dlac\ from an existing ffxi-lac setup, if present (never clobbered)
    pcall(function() os.execute('mkdir "' .. base .. 'dlac" 2>nul'); end);
    for _, f in ipairs({ 'gear.lua', 'gcinclude.lua', 'gcdisplay.lua' }) do
        if readFileText(base .. 'dlac\\' .. f) == nil then
            local src = readFileText(base .. 'ffxi-lac\\' .. f);
            if src ~= nil then writeFileText(base .. 'dlac\\' .. f, src); end
        end
    end
    -- fresh users have no ffxi-lac to copy: seed an empty gear.lua from the bundled template
    -- so the profile loads and Scan/Commit can populate it.
    if readFileText(base .. 'dlac\\gear.lua') == nil then
        local tmpl = readFileText(AshitaCore:GetInstallPath() .. 'addons\\dlac\\gear.lua');
        if tmpl ~= nil then writeFileText(base .. 'dlac\\gear.lua', tmpl); end
    end
    -- and the starter trigger file, so the profile's dispatch shims equip out of the box.
    seedTriggersFile(base, abbr);

    if state == 'nofile' then
        -- nothing to convert: write a fresh, self-contained dlac starter.
        if writeFileText(jf, MIGRATE_BOOT .. '\n' .. STARTER_PROFILE) then
            _setupState = nil;
            _augStatus = string.format('Initialized a dlac %s.lua. Reload LuaAshitacast, then build sets and triggers in the GUI.', abbr);
            pcall(function() print('[dlac] ' .. _augStatus); end);
        else
            _augStatus = 'Setup: could not write ' .. jf;
        end
        return;
    end

    -- Existing profile ('ffxilac' | 'none' | 'shims'): convert in place.
    if state == 'ffxilac' or state == 'none' then
        local text = readFileText(jf);
        if text == nil then _augStatus = 'Setup: could not read ' .. jf; return; end
        writeFileText(jf .. '.flbak', text);   -- one-time backup of the pre-dlac original
        if state == 'ffxilac' then
            text = migrateJobText(text);       -- repoint ffxi-lac requires (adds the bootstrap)
        elseif not text:find([[addons\\?.lua]], 1, true) then
            text = MIGRATE_BOOT .. '\n' .. text;   -- make require("dlac\\...") resolvable
        end
        if not writeFileText(jf, text) then _augStatus = 'Setup: could not write ' .. jf; return; end
    end

    -- Append the dispatch shims (creates missing handlers; adds the require if absent).
    -- setmanager parse-checks and keeps its own rotated backup; aborts untouched on failure.
    local okr, report, bpath = false, 'setmanager unavailable', nil;
    if hasSetmgr and type(setmgr.repairShims) == 'function' then
        local pok = pcall(function() okr, report, bpath = setmgr.repairShims(abbr); end);
        if not pok then okr, report = false, 'internal error'; end
    end
    _setupState = nil;
    if okr ~= true then
        _augStatus = string.format('Setup: shim wiring failed (%s). Your original is safe (%s.lua.flbak / backups).',
            tostring(report), abbr);
        return;
    end
    local parts = {};
    if type(report) == 'table' then
        if report.requireAdded         then parts[#parts + 1] = 'require added'; end
        if #(report.created or {}) > 0 then parts[#parts + 1] = 'created ' .. table.concat(report.created, '/'); end
        if #(report.appended or {}) > 0 then parts[#parts + 1] = 'shimmed ' .. table.concat(report.appended, '/'); end
        if #(report.moved or {}) > 0   then parts[#parts + 1] = 'moved ' .. table.concat(report.moved, '/'); end
        for _, w in ipairs(report.warnings or {}) do pcall(function() print('[dlac] setup: ' .. w); end); end
    end
    _augStatus = string.format(
        'Set up %s.lua in place (%s). Your own handler logic was kept -- dlac dispatch runs last. Reload LuaAshitacast to apply.',
        abbr, (#parts > 0) and table.concat(parts, ', ') or 'no changes needed');
    pcall(function() print('[dlac] ' .. _augStatus); end);
end

-- Reload LAC / Scan / Stage / Commit / Augs / Setup, right-aligned on the header row.
local debugMode = false;   -- /dl debug on -- reveals the dev-only Scan/Stage/Commit/Augs buttons

-- Header buttons, right-aligned. Reload LAC is always shown. Scan/Stage/Commit/Augs are
-- dev-only now that auto-sync keeps gear.lua current, so they appear only in debug mode.
-- Setup shows only while the current job still needs it (or in debug mode). The visible set
-- is measured each frame so the row stays right-aligned no matter which buttons are present.
local function renderHeaderButtons()
    local gap = 4;
    local needSetup = (jobSetupState() ~= 'ok');
    local btns = {
        { l = 'Reload LAC', w = 104,
          tip = 'Reload LuaAshitacast. LAC caches your sets when the profile loads, so after you\ncommit/edit a set (or run Setup) you must reload LAC for the change to take effect.',
          fn = function() refreshOwnedCounts(); pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/addon reload luashitacast'); end); end },
    };
    if debugMode then
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
    if needSetup or debugMode then
        btns[#btns+1] = { l = 'Setup', w = 56, red = needSetup,
            tip = 'Set up this job\'s LuaAshitacast profile so dlac can drive it: points the\nprofile at the dlac library and seeds your character\'s dlac config folder.\nBacks up the original as <JOB>.lua.flbak. Reload LuaAshitacast afterward.',
            fn = function() migrateCurrentJob(); end };
    end

    local total = 0;
    for i, b in ipairs(btns) do total = total + b.w + (i > 1 and gap or 0); end
    local x = imgui.GetWindowWidth() - total - 12;
    if x < 4 then x = 4; end
    for i, b in ipairs(btns) do
        if i == 1 then imgui.SameLine(x); else imgui.SameLine(0, gap); end
        local red = b.red and ImGuiCol_Button ~= nil;
        if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
        if imgui.Button(b.l .. '##hdr', { b.w, 22 }) then b.fn(); end
        if red then imgui.PopStyleColor(1); end
        if imgui.IsItemHovered() then imgui.SetTooltip(b.tip); end
    end
end

-- ---------------------------------------------------------------------------
-- Row renderers.
-- ---------------------------------------------------------------------------

-- "xN" owned tag (only when we own two or more -- the interesting case for DW /
-- paired slots). Empty otherwise. Contains no '%'.
local function qtyTag(rec)
    local c = (rec and rec.Id) and ownedCounts()[rec.Id] or nil;
    if c ~= nil and c >= 2 then return '  x' .. tostring(c); end
    return '';
end

-- Clickable alternative row (Equipped tab): icon + name/Lv/stats Selectable, with a
-- hover tooltip. Returns true when clicked.
local function renderAltRow(rec, ordinal, job, level)
    renderIcon(rec.Id, 18);
    local label = string.format('%s   Lv%d   %s%s##altsel_%d',
        truncate(rec.Name or '?', 26), rec.Level or 0, statSummary(rec), qtyTag(rec), ordinal);
    local clicked = imgui.Selectable(label, false);
    if imgui.IsItemHovered() then renderItemTooltip(rec); end
    return clicked;
end

-- Clickable candidate row (Sets tab). Returns true when clicked.
local function renderPickRow(rec, ordinal, idPrefix)
    renderIcon(rec.Id, 18);
    local label = string.format('%s  Lv%d  %s%s##%s_%d',
        truncate(rec.Name or '?', 24), rec.Level or 0, statSummary(rec), qtyTag(rec), idPrefix, ordinal);
    return imgui.Selectable(label, false);
end

-- Browse row (All Equipment tree): icon + Name + Level + stats, alternating bg,
-- whole-row hover tooltip. No job-list text (it's in the tooltip).
local function renderBrowseRow(rec, ordinal, job, level)
    local bg = (ordinal % 2 == 0) and { 1, 1, 1, 0.03 } or { 1, 1, 1, 0.07 };
    imgui.PushStyleColor(ImGuiCol_ChildBg, bg);
    imgui.BeginChild('##aeqrow_' .. tostring(rec.Id or ('n' .. ordinal)), { -1, 22 }, false);
    renderIcon(rec.Id, 18);
    local usable = isUsable(rec, job, level);
    imgui.TextColored(usable and COL_USABLE or COL_LOCKED, esc(rec.Name or '?'));
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_LEVEL, 'Lv' .. tostring(rec.Level or 0));
    local ss = statSummary(rec);
    if ss ~= '' then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL_STATS, esc(ss));
    end
    if rec.Id ~= nil then                              -- augments on your owned copy
        local al = ownedAugMap()[rec.Id];
        if al ~= nil and #al > 0 then
            local txt = al[1];
            if #al > 1 then txt = txt .. string.format(' (+%d)', #al - 1); end
            imgui.SameLine(0, 10);
            imgui.TextColored(COL_SCORE, 'Aug: ' .. esc(txt));
        end
    end
    imgui.EndChild();
    imgui.PopStyleColor(1);
    if imgui.IsItemHovered() then renderItemTooltip(rec); end
end

-- A 2-column grid of slot tiles (icon + "Slot: text"). Optional hoverRec(sl) drives
-- a hover tooltip for the tile's item.
local function renderSlotGrid(idPrefix, gridHeight, selectedLabel, getItemId, getText, onClick, hoverRec)
    imgui.BeginChild('##' .. idPrefix .. '_grid', { -1, gridHeight }, false);
    local availW = imgui.GetContentRegionAvail();
    local colW = math.max(120, (availW - 72) / 2);
    for i, sl in ipairs(EQUIP_SLOTS) do
        renderIcon(getItemId(sl), 22);
        local label = string.format('%-5s %s##%s_%s', sl.short, getText(sl), idPrefix, sl.label);
        if imgui.Selectable(label, selectedLabel == sl.label, ImGuiSelectableFlags_None, { colW, 24 }) then
            onClick(sl.label);
        end
        if hoverRec ~= nil and imgui.IsItemHovered() then
            local r = hoverRec(sl);
            if r ~= nil then renderItemTooltip(r); end
        end
        if i % 2 == 1 then imgui.SameLine(); end
    end
    imgui.EndChild();
end

-- ---------------------------------------------------------------------------
-- Diablo-style Stats panel + shared Name/Level sort control (Phase 3).
-- ---------------------------------------------------------------------------
local STATS_W   = 250;   -- left stats panel width (name column + value column)

-- Fixed grouped stat order. Every stat always renders (0 if absent); present-but-
-- unlisted stats fall under "Other".
-- statdefs: the central stat registry (label / section / aliases). Used by the weights
-- picker (so aliases are searchable) and, over time, the other stat tables below. Guarded.
local _sdok, statdefs = pcall(require, "dlac\\statdefs");
local hasStatdefs = _sdok and type(statdefs) == 'table' and type(statdefs.list) == 'table';

local STAT_GROUPS = {
    { name = 'Attributes', stats = { 'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR' } },
    { name = 'HP/MP',      stats = { 'HP', 'MP', 'HPP', 'MPP', 'Refresh', 'Regen', 'HMP', 'ConserveMP' } },
    { name = 'Offense',    stats = { 'Accuracy', 'Attack', 'RangedAccuracy', 'RangedAttack', 'CriticalHitRate', 'DoubleAttack', 'TripleAttack', 'StoreTP', 'SubtleBlow', 'Haste', 'DualWield' } },
    { name = 'Magic',      stats = { 'MagicAccuracy', 'MagicAttackBonus', 'MagicDefenseBonus', 'FastCast', 'CurePotency', 'Enmity' } },
    { name = 'Defense',    stats = { 'DEF', 'Evasion', 'MagicEvasion' } },
};

-- Flat, de-duplicated stat list for the weights "add" searchable dropdown (kept in group
-- order). Typing still accepts any custom name; this is just the suggestion set.
local WEIGHT_CHOICES = {};
do
    local seen = {};
    local function add(s) if not seen[s] then seen[s] = true; WEIGHT_CHOICES[#WEIGHT_CHOICES + 1] = s; end end
    for _, g in ipairs(STAT_GROUPS) do for _, s in ipairs(g.stats) do add(s); end end
    for _, s in ipairs({ 'DMG', 'Counter', 'MovementSpeed', 'PDT', 'DT' }) do add(s); end
end

-- Suggestion list for the weights "add stat" picker. Sourced from statdefs when available, so
-- the search matches key/label/aliases (type "MATK" or "MagicAttackBonus" -> find MAB) and
-- picking inserts the CANONICAL key; falls back to WEIGHT_CHOICES. Each entry:
--   { key = <canonical key to insert>, label = <display>, terms = {<lowercased key/label/aliases>} }
local _weightSuggest = nil;
local function weightSuggestions()
    if _weightSuggest ~= nil then return _weightSuggest; end
    local out = {};
    if hasStatdefs then
        for _, e in ipairs(statdefs.list) do
            local lbl = e.label or e.key;
            local terms = { string.lower(e.key) };
            if string.lower(lbl) ~= terms[1] then terms[#terms + 1] = string.lower(lbl); end
            if e.aliases ~= nil then for _, a in ipairs(e.aliases) do terms[#terms + 1] = string.lower(a); end end
            out[#out + 1] = { key = e.key, label = lbl, terms = terms };
        end
    else
        for _, name in ipairs(WEIGHT_CHOICES) do
            out[#out + 1] = { key = name, label = name, terms = { string.lower(name) } };
        end
    end
    _weightSuggest = out;
    return out;
end

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
local function renderStatsPanel(title, totals)
    imgui.BeginChild('##ffxilac_stats', { STATS_W, -1 }, true);
    imgui.TextColored(COL_HEADER, title);
    imgui.Separator();
    local resolved = resolveTotals(totals);
    local function statLine(name)
        local v = resolved[name] or 0;
        local col = (v ~= 0) and COL_USABLE or COL_DIM;
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
    imgui.EndChild();
end

-- Shared Name/Level sort combo (default Name; Level = highest first). idSuffix keeps
-- the id unique when two combos can render in one frame (builder + open add-popup).
local function renderSortCombo(idSuffix)
    imgui.TextColored(COL_DIM, 'Sort:'); imgui.SameLine(0, 3);
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

-- ---------------------------------------------------------------------------
-- Tab: Equipped
-- ---------------------------------------------------------------------------
local function renderEquippedTab(job, level)
    imgui.TextColored(COL_DIM, 'Hover a slot for details; click for alternatives.');
    imgui.SameLine();
    if imgui.Button((ui.showStats and 'Stats v' or 'Stats >') .. '##eqstats', { 76, 0 }) then
        ui.showStats = not ui.showStats;
    end

    -- Free equip: disable LAC globally so it stops auto-swapping and manual equips stick.
    -- While on, clicking an alternative uses the game's native /equip (bypasses LAC).
    imgui.SameLine(0, 12);
    imgui.Checkbox('Free equip', ui.freeEquip);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Runs /lac disable so LAC stops auto-swapping and your manual equips stay put --\nhandy for fiddling with gear. While on, clicking an alternative equips via the\ngame\'s native /equip (outside LAC). Uncheck to /lac enable and hand control back.');
    end
    if ui._freePrev ~= nil and ui._freePrev ~= ui.freeEquip[1] then
        local cmd = (ui.freeEquip[1] == true) and '/lac disable' or '/lac enable';
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
        _disabledSlots = {};   -- a global enable/disable resets per-slot lock tracking
    end
    ui._freePrev = ui.freeEquip[1];
    if ui.freeEquip[1] == true then
        imgui.SameLine(0, 10);
        imgui.TextColored(COL_ERR, 'LAC OFF -- gear will not auto-swap');
    end

    local availW = imgui.GetContentRegionAvail();
    local leftUsed = ui.showStats and (STATS_W + 8) or 0;

    if ui.showStats then
        renderStatsPanel(hasAug and 'Worn totals (base+aug)' or 'Worn set totals', wornSetTotals());
        imgui.SameLine();
    end

    imgui.BeginChild('##ffxilac_eqmain', { availW - leftUsed, -1 }, false);

    renderSlotGrid('eq', 236, ui.eqSelected,
        function(sl) return getEquippedId(sl.equip); end,
        function(sl)
            local id = getEquippedId(sl.equip);
            return truncate(id and (displayName(id) or ('#' .. tostring(id))) or '(empty)', 18);
        end,
        function(labelKey) ui.eqSelected = labelKey; end,
        function(sl) return lookupById(getEquippedId(sl.equip)); end);

    imgui.Separator();

    if ui.eqSelected == nil then
        imgui.TextColored(COL_DIM, 'Select a slot above to see the alternatives you can equip there.');
    else
        -- Selected slot header + equipped item.
        local gearKey = GEAR_OF[ui.eqSelected] or ui.eqSelected;
        local slDef;
        for _, s in ipairs(EQUIP_SLOTS) do if s.label == ui.eqSelected then slDef = s; break; end end
        local eqId = slDef and getEquippedId(slDef.equip) or nil;

        imgui.TextColored(COL_HEADER, ui.eqSelected .. ' slot');
        if eqId ~= nil then
            renderIcon(eqId, 24);
            imgui.TextColored(COL_USABLE, esc(displayName(eqId) or ('#' .. tostring(eqId))));
            local rec = lookupById(eqId);
            if rec ~= nil then
                imgui.SameLine(0, 8); imgui.TextColored(COL_LEVEL, 'Lv' .. tostring(rec.Level or 0));
                local ss = statSummary(rec);
                if ss ~= '' then imgui.TextColored(COL_STATS, esc(ss)); end
            end
            if hasAug and slDef ~= nil then           -- private augments on the worn piece
                local extra = aug.slotExtra(slDef.equip);
                local ad = extra and aug.describe(extra) or '';
                if ad ~= '' then imgui.TextColored(COL_SCORE, 'Aug: ' .. esc(ad)); end
            end
        else
            imgui.TextColored(COL_DIM, '(nothing equipped in this slot)');
        end

        -- Candidates (Sub filtered by the equipped Main), then display-sorted.
        local mainRec = lookupById(getEquippedId(0x00));
        local alts = candidatesForSlot(gearKey, job, level);
        if gearKey == 'Sub' then alts = subFilter(alts, mainRec, job, level); end
        alts = sortForDisplay(alts);

        imgui.Spacing();
        imgui.TextColored(COL_HEADER, string.format('Alternatives (%d):', #alts));
        imgui.SameLine(0, 10); renderSortCombo('eq');
        imgui.SameLine(0, 12);
        local prevLock = ui._lockPrev;
        imgui.Checkbox('Lock when equipped', ui.lockEquipped);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('While on, clicking an alternative /lac disables just this slot and equips it\nvia the game\'s native /equip, so LAC leaves it put. Uncheck to /lac enable it.');
        end
        if prevLock == true and ui.lockEquipped[1] == false then
            local s = ui.eqSelected and lacSlot(ui.eqSelected) or 'all';
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/lac enable ' .. s); end);
            if s == 'all' then _disabledSlots = {}; else _disabledSlots[s] = nil; end   -- re-enabled; forget it
        end
        ui._lockPrev = ui.lockEquipped[1];

        imgui.BeginChild('##ffxilac_eqalts', { -1, -1 }, false);
        if #alts == 0 then
            if gearKey == 'Sub' and mainRec == nil then
                imgui.TextColored(COL_DIM, 'No Main equipped -- equip a weapon first.');
            else
                imgui.TextColored(COL_DIM, 'No eligible gear for this slot at your job/level.');
            end
        else
            for i, rec in ipairs(alts) do
                if renderAltRow(rec, i, job, level) then
                    equipToSlot(ui.eqSelected, rec.Name, ui.lockEquipped[1] == true, ui.freeEquip[1] == true);
                end
            end
        end
        imgui.EndChild();
    end

    imgui.EndChild();
end

-- ---------------------------------------------------------------------------
-- Tab: All Equipment (collapsible tree over catalog.lua, gear.lua fallback)
-- ---------------------------------------------------------------------------
local function renderAllEquipTab(job, level)
    -- Filter row: slot dropdown + "Usable now" + name search. (Buttons live in the header.)
    imgui.PushItemWidth(130);
    if imgui.BeginCombo('##ffxilac_slot', ui.slot or 'All slots') then
        if imgui.Selectable('All slots', ui.slot == nil) then ui.slot = nil; end
        for _, s in ipairs(SLOT_ORDER) do
            if imgui.Selectable(s, ui.slot == s) then ui.slot = s; end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, 10);
    imgui.Checkbox('Usable now', ui.usableNow);
    imgui.SameLine(0, 10);
    imgui.TextColored(COL_DIM, 'Search:');
    imgui.SameLine(0, 4);
    imgui.PushItemWidth(-1);
    imgui.InputText('##ffxilac_search', ui.search, 64);
    imgui.PopItemWidth();

    -- Default to what you own (gear.lua); "Show all" (header) opens the full catalog.
    local showAll = (ui.showAll[1] == true);
    local items = showAll and buildAllEquip() or buildOwned();
    local usableOnly = (ui.usableNow[1] == true);
    local needle = string.lower(ui.search[1] or '');
    local searching = (needle ~= '');

    -- Group the filtered items by slot (Main/Range further by category).
    local grouped, shown = {}, 0;
    for _, rec in ipairs(items) do
        local keep = true;
        if ui.slot ~= nil and rec.Slot ~= ui.slot then keep = false; end
        if keep and usableOnly and not isUsable(rec, job, level) then keep = false; end
        if keep and not showAll and not haveInBags(rec) then keep = false; end   -- owned view = actually in your bags
        if keep and searching and string.find(string.lower(rec.Name or ''), needle, 1, true) == nil then keep = false; end
        if keep then
            shown = shown + 1;
            local slot = rec.Slot or '?';
            if slot == 'Main' or slot == 'Range' then
                grouped[slot] = grouped[slot] or { _cats = {} };
                local cat = rec.Category or '?';
                grouped[slot]._cats[cat] = grouped[slot]._cats[cat] or {};
                table.insert(grouped[slot]._cats[cat], rec);
            else
                grouped[slot] = grouped[slot] or {};
                table.insert(grouped[slot], rec);
            end
        end
    end

    imgui.TextColored(COL_DIM, string.format('Showing %d of %d  |  source: %s',
        shown, #items, showAll and (hasCatalog and 'full catalog (catalog.lua)' or 'gear.lua (no catalog)')
                              or 'gear you own (in your bags)'));
    if not showAll then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL_DIM, '-- tick "Show all" (top) to browse the full catalog.');
    end
    imgui.Separator();

    -- Force-open sections while searching; collapse once when the search is cleared.
    local forceClose = (not searching) and (ui._treeWasSearching == true);

    imgui.BeginChild('##ffxilac_tree', { -1, -1 }, false);
    for _, slot in ipairs(SLOT_TREE_ORDER) do
        local data = grouped[slot];
        local cnt = 0;
        if data ~= nil then
            if slot == 'Main' or slot == 'Range' then
                for _, list in pairs(data._cats) do cnt = cnt + #list; end
            else
                cnt = #data;
            end
        end
        if cnt > 0 then
            if searching then imgui.SetNextItemOpen(true);
            elseif forceClose then imgui.SetNextItemOpen(false); end
            if imgui.CollapsingHeader(string.format('%s (%d)###aeqh_%s', slot, cnt, slot)) then
                if slot == 'Main' or slot == 'Range' then
                    local seen = {};
                    local function renderCat(cat)
                        local list = data._cats[cat];
                        if list == nil or #list == 0 then return; end
                        seen[cat] = true;
                        if searching then imgui.SetNextItemOpen(true);
                        elseif forceClose then imgui.SetNextItemOpen(false); end
                        if imgui.TreeNode(string.format('%s (%d)###aeqc_%s_%s', cat, #list, slot, cat)) then
                            for i, rec in ipairs(list) do renderBrowseRow(rec, i, job, level); end
                            imgui.TreePop();
                        end
                    end
                    for _, cat in ipairs(CAT_ORDER[slot] or {}) do renderCat(cat); end
                    local extra = {};
                    for cat in pairs(data._cats) do if not seen[cat] then extra[#extra + 1] = cat; end end
                    table.sort(extra);
                    for _, cat in ipairs(extra) do renderCat(cat); end
                else
                    for i, rec in ipairs(data) do renderBrowseRow(rec, i, job, level); end
                end
            end
        end
    end
    imgui.EndChild();

    ui._treeWasSearching = searching;
end

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

-- Resolve one sets.Dynamic list element (a gear ref, a { gear=ref, minLevel, maxLevel }
-- wrapper, or a Name string) to a working entry. A genuine wrapper has .gear but no
-- .Name -- a plain ref that BuildDynamicSets mutated to carry a stray .gear still has
-- its .Name, so we don't mistake it for a wrapper (and we ignore its stale min/max).
local function resolveSetItem(elem)
    if type(elem) == 'string' then
        if string.lower(string.sub(elem, 1, 5)) == 'dlac:' then   -- virtual slot entry
            return { rec = { Name = elem, Level = 0, Virtual = true } };
        end
        local rec = _ownedByName and _ownedByName[string.lower(elem)] or nil;
        if rec == nil and type(gear) == 'table' and gear.NameToObject then
            local g = gear.NameToObject[elem];
            if type(g) == 'table' and g.Id ~= nil then rec = _ownedById[g.Id]; end
        end
        return rec and { rec = rec } or nil;
    end
    if type(elem) ~= 'table' then return nil; end

    local ref, minL, maxL = elem, nil, nil;
    if elem.gear ~= nil and elem.Name == nil then
        ref = elem.gear; minL = elem.minLevel; maxL = elem.maxLevel;
    end
    if type(ref) ~= 'table' then return nil; end

    local rec = nil;
    if ref.Id ~= nil then rec = _ownedById[ref.Id]; end
    if rec == nil and ref.Name ~= nil then rec = _ownedByName[string.lower(ref.Name)]; end
    if rec == nil and ref.Name ~= nil then     -- not in gear.lua: display-only, no path
        rec = { Name = ref.Name, Level = ref.Level or 0, Id = ref.Id, Jobs = ref.Jobs, Stats = ref.Stats };
    end
    if rec == nil then return nil; end
    return { rec = rec, minLevel = minL, maxLevel = maxL };
end

-- The profile's raw `sets` table. LuAshitacast exposes the loaded profile as the
-- gProfile global, and gProfile.Sets IS the profile's `sets` table whether it was
-- declared local (BLM/BLU/BRD/COR/...) or global (SCH-style) -- BuildDynamicSets
-- mutates that table in place but leaves .Dynamic intact. Fall back to a global
-- `sets` if gProfile isn't reachable; nil until a profile is loaded.
-- Addon context has no gProfile. Read the current job's <JOB>.lua from disk and run it in
-- a sandbox (LuaAshitacast globals stubbed to a permissive no-op) to recover its `sets`
-- table -- its gear refs resolve against the same preloaded gear the GUI uses. Cached per
-- file; cleared on job change and after a commit/delete.
local _profileSets, _profileSetsKey, _setsDiag = nil, nil, nil;
local function loadProfileSets()
    local jf = jobFile();
    if jf == nil then _setsDiag = 'no job file (logged in? job known?)'; return nil; end
    if _profileSetsKey == jf and _profileSets ~= nil then return _profileSets; end
    _profileSetsKey = jf;
    local chunk = loadfile(jf);
    if chunk == nil then _setsDiag = 'could not open ' .. jf; _profileSets = nil; return nil; end
    local STUB; STUB = setmetatable({}, { __index = function() return STUB; end, __call = function() return STUB; end });
    local env = setmetatable({}, {
        __index    = function(_, k) local g = rawget(_G, k); if g ~= nil then return g; end return STUB; end,
        __newindex = function(t, k, v) rawset(t, k, v); end,
    });
    if setfenv ~= nil then setfenv(chunk, env); end   -- LuaJIT (Ashita)
    local ok, ret = pcall(chunk);                     -- profiles end with `return profile`
    -- Prefer the returned profile.Sets (works whether the profile used `local sets` or a
    -- global one); fall back to a global `sets` assigned into the sandbox env.
    local s = nil;
    if ok and type(ret) == 'table' and type(ret.Sets) == 'table' then s = ret.Sets;
    elseif type(rawget(env, 'sets')) == 'table' then s = rawget(env, 'sets'); end
    if type(s) == 'table' then
        _profileSets = s;
        _setsDiag = (type(s.Dynamic) == 'table') and nil or ('ran ' .. jf .. ' but it has no sets.Dynamic');
    else
        _profileSets = nil;
        _setsDiag = 'ran ' .. jf .. ' but found no sets' .. (ok and '' or (' -- error: ' .. tostring(ret)));
    end
    return _profileSets;
end

local function getSetsRoot()
    local prof = rawget(_G, 'gProfile');
    if type(prof) == 'table' and type(prof.Sets) == 'table' then return prof.Sets; end
    local s = rawget(_G, 'sets');
    if type(s) == 'table' then return s; end
    return loadProfileSets();   -- addon: parse the current job's <JOB>.lua on disk
end

-- The .Dynamic sub-table specifically (the only sets we build/commit).
local function getDynamicSets()
    local S = getSetsRoot();
    if type(S) == 'table' and type(S.Dynamic) == 'table' then return S.Dynamic; end
    return nil;
end

-- Names of the dynamic sets (the only sets we edit). Guarded: nil until profile load.
local function dynamicSetNames()
    local names = {};
    pcall(function()
        local dyn = getDynamicSets();
        if type(dyn) ~= 'table' then return; end
        for k, v in pairs(dyn) do
            if type(v) == 'table' then names[#names + 1] = tostring(k); end
        end
    end);
    table.sort(names);
    return names;
end

-- Names of the profile's NON-Dynamic sibling sets (static / flattened sets like
-- Idle, Precast, Cure, ...). These are the migration sources the "Copy from" helper
-- can seed a Dynamic set from. Excludes 'Dynamic' itself. Guarded: nil until load.
local function staticSetNames()
    local names = {};
    pcall(function()
        local S = getSetsRoot();
        if type(S) ~= 'table' then return; end
        for k, v in pairs(S) do
            if k ~= 'Dynamic' and type(v) == 'table' then names[#names + 1] = tostring(k); end
        end
    end);
    table.sort(names);
    return names;
end

-- ---------------------------------------------------------------------------
-- Tab: Triggers -- lives in its OWN module (dlac\\triggersui.lua). LuaJIT caps a
-- chunk at 200 LOCAL VARIABLES and gearui's main chunk is close to that cap --
-- add new tabs/features as modules, not as more top-level locals in this file.
-- gearui hands the module its profile/file helpers once, then renders it. Declared
-- HERE (before renderSetsTab) so the Sets tab can call trigui.renderSetOptions.
-- ---------------------------------------------------------------------------
local trigui;
do
    local ok, m = pcall(require, "dlac\\triggersui");
    if ok and type(m) == 'table' then
        trigui = m;
        pcall(trigui.init, {
            charBase = charBase, jobFile = jobFile, seedTriggersFile = seedTriggersFile,
            dynamicSetNames = dynamicSetNames, staticSetNames = staticSetNames,
            lookupByName = lookupByName, ownedCounts = ownedCounts,   -- automations manifest (owned staves/obis)
        });
    else
        pcall(function() print('[dlac] triggersui failed to load: ' .. tostring(m)); end);
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
        local dyn = getDynamicSets();
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
local function bestByLevel(list, mainLevel)
    if type(list) ~= 'table' then return nil; end
    local best, bestLevel = nil, -1;
    local ml = mainLevel or 0;
    for _, it in ipairs(list) do                       -- a virtual entry takes the slot outright
        if it.rec ~= nil and it.rec.Virtual == true then return it; end
    end
    for _, it in ipairs(list) do
        local rec = it.rec;
        if rec ~= nil and type(rec.Level) == 'number' then
            local minL = it.minLevel or 0;
            local maxL = it.maxLevel or 999;
            if rec.Level <= ml and ml >= minL and ml <= maxL and rec.Level > bestLevel then
                best = it; bestLevel = rec.Level;
            end
        end
    end
    return best;
end

-- Sum the Stats of the best-by-level pick per slot (our data only).
local function workingSetTotals(mainLevel)
    local totals = {};
    for _, sl in ipairs(EQUIP_SLOTS) do
        local pick = bestByLevel(M.working[sl.label], mainLevel);
        if pick ~= nil and pick.rec ~= nil and type(pick.rec.Stats) == 'table' then
            for k, v in pairs(pick.rec.Stats) do
                if type(v) == 'number' and k ~= 'DMG' and k ~= 'Delay' then
                    totals[k] = (totals[k] or 0) + v;
                end
            end
        end
    end
    return totals;
end

local function workingWeightedScore(mainLevel)
    local total = 0;
    for _, sl in ipairs(EQUIP_SLOTS) do
        local pick = bestByLevel(M.working[sl.label], mainLevel);
        if pick ~= nil and pick.rec ~= nil then total = total + scoreOfItem(pick.rec); end
    end
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
                    items[#items + 1] = entry;
                end
            end
            if #items > 0 then slots[#slots + 1] = { name = sl.label, items = items }; end
        end
    end
    return slots;
end

-- Auto-build the working set from stat weights. Dynamic ON = a level-scaling list per
-- slot (keep an item only if it out-scores every kept lower-Level item; order Level
-- asc). OFF = the single best scorer usable now.
local function autoBuild(job, level)
    local dyn = (ui.setsDynamic[1] == true);
    -- "Build as lv.75" must actually reach Auto-build: when the optimizer flag is set, pick
    -- candidates as if at MAX_LEVEL (item level cap lifted; the JOB restriction inside
    -- candidatesForSlot still applies). Otherwise use the character's real level.
    local useLevel = setBuildLevel(level);   -- "Build as lv.75" lifts the item-level cap
    local oc = ownedCounts();
    local built = {};
    for _, sl in ipairs(EQUIP_SLOTS) do
        -- Skip weapon slots when asked, so Auto-build never swaps Main/Sub/Range and resets TP.
        -- Preserve whatever the working set already holds there (M.working = built below would
        -- otherwise wipe it).
        if ui.ignoreWeapons[1] == true and (sl.gear == 'Main' or sl.gear == 'Sub' or sl.gear == 'Range') then
            if M.working[sl.label] ~= nil then built[sl.label] = M.working[sl.label]; end
            goto continue;
        end
        local cands = candidatesForSlot(sl.gear, job, useLevel);   -- already job+level filtered
        -- Sub: keep only picks legal with the Main we already built (Main precedes Sub).
        if sl.gear == 'Sub' then
            local mp = bestByLevel(built['Main'], useLevel);
            cands = subFilter(cands, mp and mp.rec or nil, job, useLevel);
        end
        -- Paired slot (Ring2<-Ring1, Ear2<-Ear1): drop single-copy Ids the pair already uses.
        local other = PAIR_OF[sl.label];
        if other ~= nil and built[other] ~= nil then
            local blk = {};
            for _, it in ipairs(built[other]) do
                local id = it.rec and it.rec.Id;
                if id and (oc[id] or 0) < 2 then blk[id] = true; end
            end
            if next(blk) then
                local f = {};
                for _, r in ipairs(cands) do if not (r.Id and blk[r.Id]) then f[#f + 1] = r; end end
                cands = f;
            end
        end
        if #cands > 0 then
            if dyn then
                local byLevel = {};
                for _, r in ipairs(cands) do byLevel[#byLevel + 1] = r; end
                table.sort(byLevel, function(a, b)
                    if (a.Level or 0) ~= (b.Level or 0) then return (a.Level or 0) < (b.Level or 0); end
                    return scoreOfItem(a) > scoreOfItem(b);
                end);
                -- Seed at 0 (not -inf): keep an item only when it actually scores > 0 on the
                -- weighted stats, so a 0-value item is never kept just for being the lowest level.
                local kept, bestScore = {}, 0;
                for _, r in ipairs(byLevel) do
                    local sc = scoreOfItem(r);
                    if sc > bestScore then kept[#kept + 1] = { rec = r }; bestScore = sc; end
                end
                if #kept > 0 then built[sl.label] = kept; end
            else
                -- Seed at 0 (not -inf): pick a single item only when it scores > 0; if nothing
                -- in the slot carries a weighted stat, leave the slot empty.
                local best, bestSc = nil, 0;
                for _, r in ipairs(cands) do
                    local sc = scoreOfItem(r);
                    if sc > bestSc then bestSc = sc; best = r; end
                end
                if best ~= nil then built[sl.label] = { { rec = best } }; end
            end
        end
        ::continue::
    end
    M.working = built;
    _setDirty = true;   -- Auto-build modified the working set -> unsaved changes
end

-- "Lock" a committed set via LAC (takes effect once the file is committed + reloaded).
local function applySetLock(setName, lock)
    if lock then
        enqueueCmd(2, '/lac enable');
        if setName ~= nil and setName ~= '' then enqueueCmd(26, '/lac set ' .. setName); end
    else
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/lac enable'); end);
    end
end

local function setStatus(msg, isErr)
    ui.setsStatus = msg or '';
    ui.setsStatusErr = (isErr == true);
end

-- Migration helper: seed the working model from a static (non-Dynamic) set so an old
-- hand-authored set (e.g. sets.Idle) becomes an editable Dynamic set. Each slot in a
-- static set holds ONE element (gear ref / name string / '' for blank); a flattened
-- set may too. We also accept a genuine list ([1] present) so re-seeding from another
-- Dynamic set works. Naming: a name typed in the New box wins (then it's cleared),
-- else the source name -- so the user can rename the target before copying.
local function copyFromStaticSet(srcName)
    M.working = {};
    ui.setSelected = nil;
    local typed = ui.newSetName[1];
    local target = (typed ~= nil and typed ~= '') and typed or srcName;
    ui.newSetName[1] = '';
    local n = 0;
    pcall(function()
        local S = getSetsRoot();
        if type(S) ~= 'table' then return; end
        local setT = S[srcName];
        if type(setT) ~= 'table' then return; end
        for _, sl in ipairs(EQUIP_SLOTS) do
            local slotVal = setT[sl.label];
            if slotVal ~= nil then
                -- List (Dynamic) vs single element (static): a gear.lua record has no [1].
                local elems = (type(slotVal) == 'table' and slotVal[1] ~= nil) and slotVal or { slotVal };
                local items = {};
                for _, elem in ipairs(elems) do
                    local it = resolveSetItem(elem);
                    if it ~= nil then items[#items + 1] = it; end
                end
                if #items > 0 then M.working[sl.label] = items; n = n + 1; end
            end
        end
    end);
    M.workingSetName = target;
    _setDirty = true;   -- seeded/copied a set -> unsaved changes to commit
    if n > 0 then
        setStatus(string.format('Seeded "%s" from static set "%s" (%d slots). Edit, then Commit to write it into sets.Dynamic.', target, srcName, n), false);
    else
        setStatus(string.format('Static set "%s" has no owned/known items to copy (blank or names not in gear.lua).', srcName), true);
    end
end

local function commitCurrentSet(job)
    if not hasSetmgr then setStatus('setmanager unavailable.', true); return; end
    if M.workingSetName == nil or M.workingSetName == '' then setStatus('No set selected (pick one, or type a name + New).', true); return; end
    if job == nil or job == '' then setStatus('Unknown job (are you logged in?).', true); return; end
    local slots = buildCommitSlots();
    if #slots == 0 then setStatus('Nothing to commit -- the set is empty.', true); return; end
    local ok, action, backup = nil, nil, nil;
    local pok = pcall(function() ok, action, backup = setmgr.commitSet(job, M.workingSetName, slots); end);
    if pok and ok == true then
        _setDirty = false;    -- committed -> the working set now matches what's saved
        _profileSets = nil;   -- re-read the job file so the Sets list reflects the change
        setStatus(string.format('%s "%s" for %s. Reload (top-right) to apply.  backup: %s',
            tostring(action), tostring(M.workingSetName), tostring(job), tostring(backup)), false);
    else
        setStatus('Commit failed: ' .. tostring(action), true);
    end
end

local function deleteCurrentSet(job)
    if not hasSetmgr then setStatus('setmanager unavailable.', true); return; end
    if M.workingSetName == nil or M.workingSetName == '' then setStatus('No set selected.', true); return; end
    if job == nil or job == '' then setStatus('Unknown job (are you logged in?).', true); return; end
    local ok, action, backup = nil, nil, nil;
    local pok = pcall(function() ok, action, backup = setmgr.deleteSet(job, M.workingSetName); end);
    if pok and ok == true then
        _profileSets = nil;
        setStatus(string.format('deleted "%s" for %s. Reload to apply.  backup: %s',
            tostring(M.workingSetName), tostring(job), tostring(backup)), false);
        M.working = {}; M.workingSetName = nil; ui.setSelected = nil; _setDirty = false;
    else
        setStatus('Delete failed: ' .. tostring(action), true);
    end
end

local function renderWeightsEditor()
    if not hasOptim then
        imgui.TextColored(COL_DIM, 'Optimizer unavailable -- weights disabled.');
        return;
    end
    imgui.TextColored(COL_DIM, 'pts/point up to cap (cap 0 = none):');
    imgui.BeginChild('##ffxilac_weights', { -1, -1 }, true);   -- fill the (now windowed) space

    -- Adaptive name column: the stat name gets all the width the window can spare (the
    -- pts/cap/Set/x controls need ~236px), so widening the window shows long names in full.
    local availW  = imgui.GetContentRegionAvail();
    local nameCol = availW - 236; if nameCol < 44 then nameCol = 44; end
    local nchars  = math.max(6, math.floor(nameCol / 7));

    local ws = {};
    pcall(function() ws = optim.getWeights() or {}; end);
    for _, stat in ipairs(sortedKeys(ws)) do
        local w = ws[stat];
        local b = ui._wbuf[stat];
        if b == nil then
            local pv = (type(w) == 'table' and w.perUnit) or 0;
            b = { per = { math.floor(pv + 0.5) }, cap = { (type(w) == 'table' and w.cap) or 0 } };
            ui._wbuf[stat] = b;
        end
        imgui.TextColored(COL_USABLE, truncate(stat, nchars));
        if #stat > nchars and imgui.IsItemHovered() then imgui.SetTooltip(stat); end
        imgui.SameLine(nameCol);
        imgui.TextColored(COL_DIM, 'pts'); imgui.SameLine(0, 2);
        imgui.PushItemWidth(52); imgui.InputInt('##per_' .. stat, b.per, 0); imgui.PopItemWidth();
        imgui.SameLine(0, 6); imgui.TextColored(COL_DIM, 'cap'); imgui.SameLine(0, 2);
        imgui.PushItemWidth(46); imgui.InputInt('##cap_' .. stat, b.cap, 0); imgui.PopItemWidth();
        imgui.SameLine(0, 6);
        if imgui.Button('Set##w_' .. stat, { 36, 0 }) then
            pcall(optim.setWeight, stat, b.per[1], (b.cap[1] and b.cap[1] > 0) and b.cap[1] or nil);
            pcall(optim.saveWeights);
            invalidateCandidates();
        end
        imgui.SameLine(0, 3);
        if imgui.Button('x##wx_' .. stat, { 20, 0 }) then
            pcall(optim.clearWeight, stat);
            pcall(optim.saveWeights);
            ui._wbuf[stat] = nil;
            invalidateCandidates();
        end
    end

    imgui.Separator();

    -- Add row: searchable stat dropdown -- type in the box to filter suggestions, click one
    -- (or keep your own text), then set pts/cap and Add.
    imgui.TextColored(COL_DIM, 'add'); imgui.SameLine(0, 4);
    imgui.PushItemWidth(160);
    if imgui.BeginCombo('##addstat', (ui.addStat[1] ~= '' and ui.addStat[1]) or '(type to search)') then
        if imgui.IsWindowAppearing ~= nil and imgui.IsWindowAppearing()
           and imgui.SetKeyboardFocusHere ~= nil then imgui.SetKeyboardFocusHere(0); end
        imgui.PushItemWidth(-1); imgui.InputText('##addfilter', ui.addStat, 32); imgui.PopItemWidth();
        imgui.Separator();
        local q, shown = string.lower(ui.addStat[1] or ''), 0;
        for _, sug in ipairs(weightSuggestions()) do
            local match = (q == '');
            if not match then
                for _, t in ipairs(sug.terms) do
                    if string.find(t, q, 1, true) ~= nil then match = true; break; end
                end
            end
            if match then
                shown = shown + 1;
                local disp = (sug.label ~= sug.key) and (sug.label .. '  (' .. sug.key .. ')') or sug.key;
                if imgui.Selectable(disp .. '##sug_' .. sug.key, false) then
                    ui.addStat[1] = sug.key;             -- insert the canonical key (not the alias/label)
                    imgui.CloseCurrentPopup();
                end
            end
        end
        if shown == 0 then imgui.TextColored(COL_DIM, '(no match -- Add will use your typed text)'); end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, 6); imgui.TextColored(COL_DIM, 'pts'); imgui.SameLine(0, 2);
    imgui.PushItemWidth(52); imgui.InputInt('##addper', ui.addPer, 0); imgui.PopItemWidth();
    imgui.SameLine(0, 6); imgui.TextColored(COL_DIM, 'cap'); imgui.SameLine(0, 2);
    imgui.PushItemWidth(46); imgui.InputInt('##addcap', ui.addCap, 0); imgui.PopItemWidth();
    imgui.SameLine(0, 6);
    if imgui.Button('Add##addw', { 40, 0 }) then
        local name = ui.addStat[1];
        if name ~= nil and name ~= '' then
            pcall(optim.setWeight, name, ui.addPer[1], (ui.addCap[1] and ui.addCap[1] > 0) and ui.addCap[1] or nil);
            pcall(optim.saveWeights);
            ui.addStat[1] = '';
            invalidateCandidates();
        end
    end

    imgui.EndChild();
end

-- Add-item popup: usable owned items for the selected slot not already in its list.
local function renderAddPopup(job, level)
    if not imgui.BeginPopup('##ffxilac_addpick') then return; end
    if ui.setSelected == nil then
        imgui.TextColored(COL_DIM, 'No slot selected.');
    else
        imgui.TextColored(COL_HEADER, 'Add usable item to ' .. ui.setSelected .. ':');
        imgui.SameLine(0, 10); renderSortCombo('add');
        local gearKey = GEAR_OF[ui.setSelected] or ui.setSelected;
        local list = M.working[ui.setSelected] or {};
        local inList = {};
        for _, it in ipairs(list) do if it.rec and it.rec.Name then inList[it.rec.Name] = true; end end
        local useLevel = setBuildLevel(level);   -- "Build as lv.75" lifts the cap for + Add too
        local cands = candidatesForSlot(gearKey, job, useLevel);
        if gearKey == 'Sub' then
            local mp = bestByLevel(M.working['Main'], useLevel);
            cands = subFilter(cands, mp and mp.rec or nil, job, useLevel);
        end
        local blocked = pairedBlockedIds(ui.setSelected, true);
        cands = sortForDisplay(cands);
        imgui.BeginChild('##ffxilac_addlist', { 380, 320 }, false);
        local any = false;
        -- Virtual entries ("slot functions", ADR 0004): resolved by the engine at equip
        -- time from your owned gear. Offered per slot, pinned above the item list.
        local vlist = nil;
        if ui.setSelected == 'Main' then
            vlist = { { name = 'dlac:AutoStaff', tip = 'Equips your best USABLE Iridescence staff for the cast (level-checked):\nHQ elemental +2 / NQ +1 (own element) vs a universal weapon\n(Chatoyant/Foreshadow +1 = +2 all elements, Iridal = +1); ties go to the\nuniversal, which also covers elementless actions. When nothing usable\nexists (e.g. under-leveled), the OTHER items in this slot\'s list are\nthe fallback -- best-by-level as usual.' } };
        elseif ui.setSelected == 'Waist' then
            vlist = { { name = 'dlac:AutoObi', tip = 'Equips the matching elemental obi when the net day/weather bonus for\nthe spell\'s element is positive (level-checked). Other items in this\nslot\'s list are the fallback.' } };
        end
        if vlist ~= nil then
            for vi, vd in ipairs(vlist) do
                if not inList[vd.name] then
                    any = true;
                    imgui.TextColored(COL_SCORE, '*');
                    imgui.SameLine(0, 6);
                    if imgui.Selectable(vd.name .. '   (auto -- resolved at equip time)##vadd' .. vi, false) then
                        list[#list + 1] = { rec = { Name = vd.name, Level = 0, Virtual = true } };
                        M.working[ui.setSelected] = list;
                        _setDirty = true;
                        imgui.CloseCurrentPopup();
                    end
                    if imgui.IsItemHovered() then imgui.SetTooltip(vd.tip); end
                end
            end
            imgui.Separator();
        end
        for i, rec in ipairs(cands) do
            if not inList[rec.Name] and not (rec.Id and blocked[rec.Id]) then
                any = true;
                if renderPickRow(rec, i, 'addpick') then
                    list[#list + 1] = { rec = rec };
                    M.working[ui.setSelected] = list;
                    _setDirty = true;   -- added an item to the slot -> unsaved changes
                    imgui.CloseCurrentPopup();
                end
                if imgui.IsItemHovered() then renderItemTooltip(rec); end
            end
        end
        if not any then imgui.TextColored(COL_DIM, 'No addable items (check Main for Sub, or you own only one).'); end
        imgui.EndChild();
    end
    imgui.EndPopup();
end

-- Right-side panel: Dynamic toggle + Auto-build + the stat-weights editor.
local function renderSetsWeightPanel(job, level)
    imgui.Checkbox('Dynamic', ui.setsDynamic);
    if imgui.IsItemHovered() then
        imgui.SetTooltip("When off, builds only ONE item per slot for the set (won't scale with level).");
    end
    imgui.Checkbox('Skip weapons (Main/Sub/Range)', ui.ignoreWeapons);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Leaves Main/Sub/Range untouched when Auto-building, so weapon swaps don\'t reset your TP.');
    end
    if imgui.Button('Auto-build##setauto', { -1, 24 }) then autoBuild(job, level); end
    imgui.Separator();
    renderWeightsEditor();
end

-- Left builder: 16 slot tiles + the expanded ordered list for the selected slot.
local function renderSetBuilder(job, level)
    if M.workingSetName == nil then
        imgui.TextColored(COL_DIM, 'Pick a set above, or type a name and click New, then Auto-build or + Add items.');
        return;
    end

    renderSlotGrid('set', 236, ui.setSelected,
        function(sl)
            local pick = bestByLevel(M.working[sl.label], level);
            return pick and pick.rec and pick.rec.Id or nil;
        end,
        function(sl)
            local list = M.working[sl.label];
            local pick = bestByLevel(list, level);
            local nm = (pick and pick.rec and pick.rec.Name) or '(empty)';
            return string.format('%s (%d)', truncate(nm, 12), (list and #list) or 0);
        end,
        function(labelKey) ui.setSelected = labelKey; end,
        function(sl)
            local pick = bestByLevel(M.working[sl.label], level);
            return pick and pick.rec or nil;
        end);

    imgui.Separator();
    if ui.setSelected == nil then
        imgui.TextColored(COL_DIM, 'Select a slot above to edit its ordered list. Yellow = current best-by-level pick.');
        return;
    end

    local list = M.working[ui.setSelected] or {};
    imgui.TextColored(COL_HEADER, string.format('%s list (%d):', ui.setSelected, #list));
    imgui.SameLine(); if imgui.Button('+ Add##setadd', { 60, 0 }) then ui._openAddPopup = true; end
    imgui.SameLine(0, 8); renderSortCombo('setlist');

    local pick = bestByLevel(list, level);
    local pickRec = pick and pick.rec or nil;
    local disp = sortItemsForDisplay(list);

    local action = nil;   -- { kind, it }  (by identity, so it maps back to the data list)
    imgui.BeginChild('##ffxilac_slotlist', { -1, -1 }, false);
    if #list == 0 then
        imgui.TextColored(COL_DIM, 'Empty -- click + Add (usable owned items) or Auto-build.');
    else
        for di, it in ipairs(disp) do
            local rec = it.rec;
            renderIcon(rec and rec.Id or nil, 18);
            imgui.TextColored((rec ~= nil and rec == pickRec) and COL_SCORE or COL_USABLE,
                esc((rec and rec.Name) or '?') .. qtyTag(rec));
            if rec ~= nil and imgui.IsItemHovered() then renderItemTooltip(rec); end
            imgui.SameLine(0, 8); imgui.TextColored(COL_LEVEL, 'Lv' .. tostring(rec and rec.Level or 0));
            local ss = rec and statSummary(rec) or '';
            if ss ~= '' then imgui.SameLine(0, 8); imgui.TextColored(COL_STATS, esc(ss)); end
            if it.minLevel ~= nil then imgui.SameLine(0, 8); imgui.TextColored(COL_DIM, 'min' .. tostring(it.minLevel)); end
            if it.maxLevel ~= nil then imgui.SameLine(0, 8); imgui.TextColored(COL_DIM, 'max' .. tostring(it.maxLevel)); end
            imgui.SameLine(0, 12);
            if imgui.SmallButton('^##up_' .. di)   then action = { kind = 'up',     it = it }; end
            imgui.SameLine(0, 2);
            if imgui.SmallButton('v##down_' .. di) then action = { kind = 'down',   it = it }; end
            imgui.SameLine(0, 2);
            if imgui.SmallButton('x##rm_' .. di)   then action = { kind = 'remove', it = it }; end
        end
    end
    imgui.EndChild();

    if action ~= nil then
        local di = nil;
        for k, v in ipairs(list) do if v == action.it then di = k; break; end end
        if di ~= nil then
            if action.kind == 'remove' then
                table.remove(list, di);
            elseif action.kind == 'up' and di > 1 then
                list[di], list[di - 1] = list[di - 1], list[di];
            elseif action.kind == 'down' and di < #list then
                list[di], list[di + 1] = list[di + 1], list[di];
            end
            if #list == 0 then M.working[ui.setSelected] = nil; else M.working[ui.setSelected] = list; end
            _setDirty = true;   -- removed/reordered an item -> unsaved changes
        end
    end
end

local function renderSetsTab(job, level)
    if not hasSetmgr then
        imgui.TextColored(COL_ERR, 'setmanager unavailable -- commit/delete disabled (view/build still works).');
    end

    -- Controls row: set picker + New + Commit + Delete + Lock + Weights toggle.
    imgui.TextColored(COL_DIM, 'Set:'); imgui.SameLine(0, 4);
    imgui.PushItemWidth(150);
    if imgui.BeginCombo('##ffxilac_setpick', M.workingSetName or '(select)') then
        local names = dynamicSetNames();
        if #names == 0 then
            imgui.TextColored(COL_DIM, '(no sets.Dynamic -- reload the profile?)');
            if _setsDiag ~= nil and _setsDiag ~= '' then imgui.TextColored(COL_ERR, esc(_setsDiag)); end
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
    imgui.PushItemWidth(104); imgui.InputText('##ffxilac_newset', ui.newSetName, 32); imgui.PopItemWidth();
    imgui.SameLine();
    if imgui.Button('New##setnew', { 46, 22 }) then
        local nm = ui.newSetName[1];
        if nm ~= nil and nm ~= '' then
            M.workingSetName = nm; M.working = {}; ui.setSelected = nil; ui.newSetName[1] = '';
            _setDirty = false;   -- brand-new empty set -> nothing unsaved yet
            setStatus('New empty set "' .. nm .. '" -- add items, then Commit.', false);
        end
    end
    imgui.SameLine();
    -- Light the Commit button red while the working set has unsaved changes (same pattern as the
    -- header 'Setup' button). Guarded on ImGuiCol_Button so a missing constant can't error.
    local _cdirty = _setDirty and ImGuiCol_Button ~= nil;
    if _cdirty then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
    if imgui.Button('Commit##setcommit', { 62, 22 }) then commitCurrentSet(job); end
    if _cdirty then imgui.PopStyleColor(1); end
    if imgui.IsItemHovered() then imgui.SetTooltip('Saves your current set into sets.Dynamic in your job file (writes <JOB>.lua). Reload LAC afterward.'); end
    imgui.SameLine(); if imgui.Button('Delete##setdel', { 58, 22 }) then deleteCurrentSet(job); end

    imgui.SameLine();
    local prevLock = ui._setLockPrev;
    imgui.Checkbox('Lock', ui.lockSet);
    if imgui.IsItemHovered() then imgui.SetTooltip('Checked: /lac enable then /lac set <set>.  Unchecked: /lac enable.  (Commit + Reload first.)'); end
    if prevLock ~= nil and prevLock ~= ui.lockSet[1] then applySetLock(M.workingSetName, ui.lockSet[1] == true); end
    ui._setLockPrev = ui.lockSet[1];

    imgui.SameLine();
    if imgui.Button((ui.showStats and 'Stats v' or 'Stats >') .. '##setstats', { 72, 22 }) then ui.showStats = not ui.showStats; end
    imgui.SameLine();
    if imgui.Button((ui.showWeights and 'Weights v' or 'Weights >') .. '##setwtoggle', { 84, 22 }) then ui.showWeights = not ui.showWeights; end
    if imgui.IsItemHovered() then imgui.SetTooltip('Toggle the Stat Weights editor -- opens in its own resizable, movable window.'); end

    -- Build-level override (general set management): lifts the item level cap for BOTH
    -- Auto-build and the manual + Add picker, so you can assemble over-level sets.
    if hasOptim then
        ui.buildMax[1] = (optim.buildAtMaxLevel == true);
        imgui.Checkbox('Build as lv.75 (ignore level cap)', ui.buildMax);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Ignore the item level cap when building sets OR using + Add -- pick gear as if you\nwere level 75, so you can assemble over-level sets. Your JOB restriction still applies.');
        end
        optim.buildAtMaxLevel = (ui.buildMax[1] == true);
    end

    -- Automation is a SLOT entry now (ADR 0004, 4th revision): + Add on the Main slot
    -- offers dlac:AutoStaff, on Waist dlac:AutoObi -- no per-set flags anymore.

    -- Migration helper: seed a Dynamic working set from a static (non-Dynamic) set.
    imgui.TextColored(COL_DIM, 'Copy from:'); imgui.SameLine(0, 4);
    imgui.PushItemWidth(150);
    if imgui.BeginCombo('##ffxilac_copyfrom', '(static set)') then
        local statics = staticSetNames();
        if #statics == 0 then imgui.TextColored(COL_DIM, '(none -- no static sets on this profile)'); end
        for _, nm in ipairs(statics) do
            if imgui.Selectable(nm, false) then copyFromStaticSet(nm); end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Seed a Dynamic set from an old static set (e.g. Idle).\nType a name in New first to rename the target; otherwise it keeps the source name.\nEdit the lists, then Commit to write it into sets.Dynamic.');
    end
    imgui.SameLine(0, 6); imgui.TextColored(COL_DIM, 'seed a Dynamic set from a static one (migration)');

    if ui.setsStatus ~= nil and ui.setsStatus ~= '' then
        imgui.PushTextWrapPos(0.0);
        imgui.TextColored(ui.setsStatusErr and COL_ERR or COL_SCORE, esc(ui.setsStatus));
        imgui.PopTextWrapPos();
    end
    imgui.Separator();

    -- Split: [stats panel] | builder.  Stat weights are now their OWN resizable window
    -- (renderWeightsWindow), toggled by the "Weights" button above, so they get real space.
    local availW = imgui.GetContentRegionAvail();
    local statsUsed = ui.showStats and (STATS_W + 8) or 0;

    if ui.showStats then
        renderStatsPanel(string.format('Set totals (w %g)', workingWeightedScore(level)), workingSetTotals(level));
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
local function drawWindow()
    if not M.visible or not hasImgui then return; end

    local owned = buildOwned();
    buildAllEquip();   -- populate catalog indexes for tooltips / worn-set totals
    local job, level = getPlayerInfo();

    imgui.SetNextWindowSize({ 940, 680 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 480, 340 }, { 1300, 1300 });

    local isOpen = { M.visible };
    if imgui.Begin('dlac Gear###ffxi_lac_gearui', isOpen, ImGuiWindowFlags_None) then
        -- Header line: job/level + owned count + "Show all" toggle, then right-aligned buttons.
        imgui.TextColored(COL_HEADER, jobHeader());
        imgui.SameLine();
        imgui.TextColored(COL_DIM, string.format('|  %d owned%s', #owned, hasOptim and '' or '  |  optimizer OFF'));
        imgui.SameLine(0, 12);
        imgui.Checkbox('Show all', ui.showAll);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Will show all equips, even if you don\'t have them.\nOff (default): the All Equipment tab lists only gear you own (gear.lua).\nOn: it lists the full CatsEyeXI catalog.');
        end
        renderHeaderButtons();
        if _augStatus ~= nil and _augStatus ~= '' then
            imgui.TextColored(COL_SCORE, esc(_augStatus));
        end
        do  -- prominent warning when the current job isn't wired for dlac yet
            local _st = jobSetupState();
            if _st == 'ffxilac' or _st == 'none' then
                local _, _ab = jobFile();
                imgui.TextColored(COL_ERR, string.format('  [!]  %s.lua is NOT set up for dlac -- click the red "Setup" button (top-right). Your existing logic is kept; dlac is added at the end.', tostring(_ab or '?')));
            elseif _st == 'shims' then
                local _, _ab = jobFile();
                imgui.TextColored(COL_ERR, string.format('  [!]  %s.lua is missing trigger shims -- click the red "Setup" button (top-right) to add them (your logic is kept).', tostring(_ab or '?')));
            end
        end
        imgui.Separator();

        if imgui.BeginTabBar('##ffxilac_tabs', ImGuiTabBarFlags_None) then
            if imgui.BeginTabItem('Equipped') then
                pcall(renderEquippedTab, job, level);
                imgui.EndTabItem();
            end
            if imgui.BeginTabItem('All Equipment') then
                pcall(renderAllEquipTab, job, level);
                imgui.EndTabItem();
            end
            if imgui.BeginTabItem('Sets') then
                pcall(renderSetsTab, job, level);
                imgui.EndTabItem();
            end
            if imgui.BeginTabItem('Triggers') then
                if trigui ~= nil then
                    pcall(trigui.render, job, level);
                else
                    imgui.TextColored(COL_ERR, 'triggersui module unavailable.');
                end
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end
    end
    imgui.End();

    renderWeightsWindow(job, level);   -- separate, resizable Stat-weights window (Sets "Weights" toggle)

    M.visible = (isOpen[1] == true);
end

-- ---------------------------------------------------------------------------
-- Render event: process the command queue every frame (even while hidden, so a
-- lock sequence completes), then draw while visible. Wrapped so a transient imgui
-- error can never take down the d3d_present hook.
-- ---------------------------------------------------------------------------
-- Keep gear.lua current automatically. A job change reloads the LAC profile ("loading a
-- lua"), so we re-scan shortly after; also fires on login (nil -> job). Add-only + a silent
-- no-op when nothing is new, so it is cheap and never spams. Toggle with /dl autosync off.
local autoSyncEnabled = true;
local _syncedJob, _syncDueFrame = nil, nil;
local function doSync()
    local added = callImport('sync');
    added = (type(added) == 'number') and added or 0;
    if added > 0 then refreshGear(); end
    return added;
end
local function autoSyncOnJobChange()
    if not autoSyncEnabled then return; end
    local j = nil;
    pcall(function() j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
    if j ~= nil and j ~= 0 and j ~= _syncedJob then
        _syncedJob    = j;
        _syncDueFrame = frameCounter + 120;   -- ~2s after the change, so inventory has loaded
    end
    if _syncDueFrame ~= nil and frameCounter >= _syncDueFrame then
        _syncDueFrame = nil;
        doSync();
    end
end

-- UI-flag persistence: debug + auto-sync survive reloads via <char>\dlac\uiflags.lua
-- (a `return {...}` module, like gearweights.lua). Defaults stay debug=false / autosync=true;
-- a /dl command updates the flag AND re-saves, and wins over the on-disk value -- once a
-- command has run (or the file has loaded), loadUiFlags no longer clobbers the live value.
local _flagsLoaded = false;
local function uiFlagsPath()
    local base = charBase();
    return base and (base .. 'dlac\\uiflags.lua') or nil;
end
local function saveUiFlags()
    local p = uiFlagsPath(); if p == nil then return; end   -- pre-login: can't persist yet
    _flagsLoaded = true;                                    -- command is now authoritative
    pcall(function()
        writeFileText(p, string.format('return { debug = %s, autosync = %s }\n',
            tostring(debugMode), tostring(autoSyncEnabled)));
    end);
end
local function loadUiFlags()
    if _flagsLoaded then return; end
    local p = uiFlagsPath(); if p == nil then return; end   -- pre-login: retry next frame
    _flagsLoaded = true;
    pcall(function()
        local chunk = loadfile(p);
        if chunk == nil then return; end                    -- no file yet -> keep defaults
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then
            if type(t.debug)    == 'boolean' then debugMode       = t.debug;    end
            if type(t.autosync) == 'boolean' then autoSyncEnabled = t.autosync; end
        end
    end);
end

ashita.events.register('d3d_present', 'dlac-gearui-render', function()
    frameCounter = frameCounter + 1;
    processCmdQueue();
    pcall(loadUiFlags);
    pcall(autoSyncOnJobChange);
    if not M.visible or not hasImgui then return; end
    pcall(drawWindow);
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
    if sub ~= 'ui' and sub ~= 'sync' and sub ~= 'autosync' and sub ~= 'debug' then return; end
    e.blocked = true;

    if sub == 'sync' then          -- manual one-shot: scan + import new gear now
        local n = doSync();
        print(string.format('[dlac] sync: %s', (n > 0) and ('added ' .. n .. ' new item(s) to gear.lua.') or 'nothing new.'));
        return;
    end
    if sub == 'autosync' then       -- toggle the on-job-change auto-sync
        if     args[2] == 'off' then autoSyncEnabled = false;
        elseif args[2] == 'on'  then autoSyncEnabled = true; end
        saveUiFlags();              -- persist; command wins over the on-disk value
        print('[dlac] auto-sync ' .. (autoSyncEnabled and 'ON' or 'OFF')
            .. ' -- re-scans gear.lua on job change.  (/dl autosync on|off)');
        return;
    end
    if sub == 'debug' then          -- reveal/hide the dev-only Scan/Stage/Commit/Augs buttons
        if     args[2] == 'off' then debugMode = false;
        elseif args[2] == 'on'  then debugMode = true;
        else                          debugMode = not debugMode; end
        saveUiFlags();              -- persist; command wins over the on-disk value
        print('[dlac] debug ' .. (debugMode and 'ON -- Scan/Stage/Commit/Augs buttons shown.'
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

    if M.visible and not hasImgui then
        print('[dlac] gear UI: imgui is unavailable in this context; nothing to show.');
    else
        print('[dlac] gear UI ' .. (M.visible and 'shown' or 'hidden') .. '.');
    end
end);

-- ---------------------------------------------------------------------------
-- Cleanup on addon unload: drop our callbacks and free the icon textures.
-- ---------------------------------------------------------------------------
ashita.events.register('unload', 'dlac-gearui-unload', function()
    pcall(function() ashita.events.unregister('d3d_present', 'dlac-gearui-render'); end);
    pcall(function() ashita.events.unregister('command', 'dlac-ui'); end);
    pcall(releaseTextures);
end);

return M;
