--[[
    dlac/augments.lua — read & decode CatsEyeXI item augments (private augments)
    from an item's Extra bytes in Ashita memory, and turn a worn item's augments into
    gear.lua stat deltas so worn-stat totals / tooltips can show base + augment.

    Format (see the augdump addon / memory catseyexi-augment-extdata-format):
      Extra is a byte string. Extra[0]=0x02 (augmented marker), Extra[1]=type/rank.
      From Extra[2], each augment is one 2-byte little-endian word until 0x0000:
        id = word & 0x07FF ;  magnitude = (word >> 11) + 1.
      id -> stat(s) via AUG_STATS (built by in-game + bg-wiki correlation; ~86% coverage).
      0x01-header items are enchanted-charge data (teleport rings etc.), not augments.
]]--

local M = {};

-- augment id -> gear.lua stat key(s) it grants (each at the augment's magnitude).
local AUG_STATS = {
    [1]   = {'HP'},     [9]   = {'MP'},     [17]  = {'HP','MP'},
    [23]  = {'Accuracy'},   [25] = {'Attack'},  [27] = {'RangedAccuracy'}, [29] = {'RangedAttack'},
    [33]  = {'DEF'},    [35]  = {'MagicAccuracy'}, [39] = {'Enmity'}, [45] = {'DMG'}, [49] = {'Haste'},
    [52]  = {'HMP'},    [54]  = {'PDT'},    [71]  = {'DT'},     [134] = {'MagicDefenseBonus'},
    [137] = {'Regen'},  [138] = {'Refresh'},[140] = {'FastCast'}, [141] = {'ConserveMP'},
    [142] = {'StoreTP'},
    [267] = {'ClubSkill'}, [296] = {'SingingSkill'}, [298] = {'WindInstrumentSkill'},
    [313] = {'EarthMagicAcc'}, [323] = {'CureCastTime'}, [329] = {'CurePotency'},
    [337] = {'SongRecast'}, [351] = {'OccQuickenSpell'}, [1248] = {'EnhancingDuration'},
    [1792] = {'Pet_STR'},
    [512] = {'STR'},[513]={'DEX'},[514]={'VIT'},[515]={'AGI'},[516]={'INT'},[517]={'MND'},[518]={'CHR'},
    [553] = {'DEX','AGI'}, [554] = {'INT','MND'}, [559] = {'STR','MND'},
};

-- Readable label per id (for tooltips). Falls back to "aug#<id>".
local AUG_NAME = {
    [1]='HP',[9]='MP',[17]='HP/MP',[23]='Acc',[25]='Att',[27]='R.Acc',[29]='R.Att',[33]='DEF',
    [35]='M.Acc',[39]='Enmity',[45]='DMG',[49]='Haste',[52]='HMP',[54]='PDT',[71]='DT',
    [134]='M.Def Bns',[137]='Regen',[138]='Refresh',[140]='Fast Cast',[141]='Conserve MP',
    [142]='Store TP',[267]='Club Skill',[296]='Sing Skill',[298]='Wind Skill',[313]='Earth M.Acc',
    [323]='Cure Cast',[329]='Cure Pot.',[337]='Song Recast',[351]='Occ.Quicken',[1248]='Enh.Dur.',
    [1792]='Pet:STR',[512]='STR',[513]='DEX',[514]='VIT',[515]='AGI',[516]='INT',[517]='MND',
    [518]='CHR',[553]='DEX/AGI',[554]='INT/MND',[559]='STR/MND',
};
-- Ids whose magnitude reads as a percentage.
local PERCENT = { [49]=true,[54]=true,[71]=true,[140]=true,[323]=true,[329]=true,[351]=true,[1248]=true };
-- Ids whose effect is a reduction (stored positive; display with '-').
local REDUCE  = { [54]=true,[71]=true,[323]=true,[337]=true };

-- Decode an Extra byte-string -> list of { id, mag, keys, name }. Empty if not augmented.
function M.decode(extra)
    local out = {};
    if type(extra) ~= 'string' or #extra < 4 or extra:byte(1) ~= 0x02 then return out; end
    local i = 3;   -- byte offset 2 (skip the 2-byte header)
    while i + 1 <= #extra do
        local word = (extra:byte(i) or 0) + (extra:byte(i + 1) or 0) * 256;
        if word ~= 0 then
            local id  = word % 2048;                    -- word & 0x07FF
            local mag = math.floor(word / 2048) + 1;    -- (word >> 11) + 1
            out[#out + 1] = { id = id, mag = mag, keys = AUG_STATS[id], name = AUG_NAME[id] };
        end
        i = i + 2;
    end
    return out;
end

-- Summed stat deltas for an Extra string: { statKey = delta } (known ids only).
function M.stats(extra)
    local t = {};
    for _, a in ipairs(M.decode(extra)) do
        if a.keys ~= nil then
            for _, k in ipairs(a.keys) do t[k] = (t[k] or 0) + a.mag; end
        end
    end
    return t;
end

-- Human-readable augment summary, e.g. "HP+15, DEX/AGI+3, Haste+3%". "" if none.
function M.describe(extra)
    local parts = {};
    for _, a in ipairs(M.decode(extra)) do
        local nm   = a.name or ('aug#' .. tostring(a.id));
        local sign = REDUCE[a.id] and '-' or '+';
        local pct  = PERCENT[a.id] and '%' or '';
        parts[#parts + 1] = string.format('%s%s%d%s', nm, sign, a.mag, pct);
    end
    return table.concat(parts, ', ');
end

-- True if the item has any augment data (0x02 header + a non-zero augment word).
function M.isAugmented(extra)
    return #M.decode(extra) > 0;
end

-- The Extra byte-string of the item worn in equipment slot 0-15, or nil.
-- GetEquippedItem returns a PACKED Index (high byte = container, low byte = slot),
-- matching gearui's getEquippedId -- there is no separate .Slot field in this build.
function M.slotExtra(equipSlot)
    local extra = nil;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        if inv == nil then return; end
        local eitem = inv:GetEquippedItem(equipSlot);
        if eitem == nil or eitem.Index == 0 then return; end
        local cont       = math.floor(eitem.Index / 256) % 256;   -- high byte = container
        local slotInCont = eitem.Index % 256;                     -- low byte  = slot in container
        local item = inv:GetContainerItem(cont, slotInCont);
        if item ~= nil then extra = item.Extra; end
    end);
    return extra;
end

-- Summed augment stat deltas across all 16 worn slots: { statKey = delta }.
function M.wornStats()
    local totals = {};
    for slot = 0, 15 do
        local extra = M.slotExtra(slot);
        if extra ~= nil then
            for k, v in pairs(M.stats(extra)) do totals[k] = (totals[k] or 0) + v; end
        end
    end
    return totals;
end

-- ---------------------------------------------------------------------------
-- Bag scanning: owned augments per item + a shareable dump file.
-- ---------------------------------------------------------------------------
-- Equip-eligible containers (Inventory + the 8 Wardrobes), matching gearimport.
local SCAN_CONTAINERS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 };

local function hexOf(extra)
    if type(extra) ~= 'string' then return ''; end
    local p = {};
    for i = 1, #extra do p[i] = string.format('%02X', extra:byte(i)); end
    return table.concat(p, ' ');
end

-- { [itemId] = { "HP+15, ...", ... } } for augmented copies across your bags.
function M.ownedAugments()
    local out = {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        if inv == nil then return; end
        for _, cid in ipairs(SCAN_CONTAINERS) do
            local max = inv:GetContainerCountMax(cid);
            if max ~= nil and max > 0 then
                for j = 1, max do
                    local item = inv:GetContainerItem(cid, j);
                    if item ~= nil and item.Id ~= nil and item.Id ~= 0 and item.Id ~= 65535 then
                        local d = M.describe(item.Extra);
                        if d ~= '' then
                            local lst = out[item.Id] or {};
                            lst[#lst + 1] = d;
                            out[item.Id] = lst;
                        end
                    end
                end
            end
        end
    end);
    return out;
end

-- <install>config\addons\luashitacast\<Name>_<Id>\dlac\augdump.txt, or nil.
local function dumpPath()
    local p = nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name  = party:GetMemberName(0);
        local id    = party:GetMemberServerId(0);
        if name ~= nil and name ~= '' and id ~= nil then
            p = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\dlac\\augdump.txt',
                AshitaCore:GetInstallPath(), name, id);
        end
    end);
    return p;
end

-- Write a shareable augment report (every augmented item: name, id, decoded augments,
-- with <UNKNOWN> for unmapped ids). Returns (path|nil, itemCount, sortedUnknownIdList).
function M.dumpToFile()
    local out, unknown, count = {}, {}, 0;
    out[#out + 1] = '# dlac augment dump -- share this so unknown augment ids can be identified.';
    out[#out + 1] = '# For any <UNKNOWN> line, note what that augment reads as in-game (stat + value).';
    out[#out + 1] = '# decode: id = word & 0x7FF ; magnitude = (word>>11)+1  (see dlac/augments.lua)';
    out[#out + 1] = '# ------------------------------------------------------------';
    out[#out + 1] = '';   -- summary line, filled in below
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local res = AshitaCore:GetResourceManager();
        if inv == nil then return; end
        for _, cid in ipairs(SCAN_CONTAINERS) do
            local max = inv:GetContainerCountMax(cid);
            if max ~= nil and max > 0 then
                for j = 1, max do
                    local item = inv:GetContainerItem(cid, j);
                    if item ~= nil and item.Id ~= nil and item.Id ~= 0 and item.Id ~= 65535 then
                        local augs = M.decode(item.Extra);
                        if #augs > 0 then
                            count = count + 1;
                            local nm = '?';
                            pcall(function()
                                local r = res:GetItemById(item.Id);
                                if r ~= nil and r.Name ~= nil then nm = r.Name[1] or '?'; end
                            end);
                            out[#out + 1] = string.format('%s (id=%d)  raw=%s', nm, item.Id, hexOf(item.Extra));
                            for _, a in ipairs(augs) do
                                if a.name == nil then unknown[a.id] = true; end
                                out[#out + 1] = string.format('    id=%-4d +%-3d  %s',
                                    a.id, a.mag, a.name or '<UNKNOWN -- what does this augment read in-game?>');
                            end
                        end
                    end
                end
            end
        end
    end);
    local unk = {};
    for id in pairs(unknown) do unk[#unk + 1] = id; end
    table.sort(unk);
    out[5] = string.format('# %d augmented items; %d unknown id(s): %s',
        count, #unk, (#unk > 0) and table.concat(unk, ', ') or '(none)');
    local path, ok = dumpPath(), false;
    if path ~= nil then
        pcall(function()
            local f = io.open(path, 'w');
            if f ~= nil then f:write(table.concat(out, '\n') .. '\n'); f:close(); ok = true; end
        end);
    end
    return (ok and path or nil), count, unk;
end

return M;
