--[[
    dlac/augments.lua — read & decode CatsEyeXI item augments (private augments)
    from an item's Extra bytes in Ashita memory, and turn a worn item's augments into
    gear.lua stat deltas so worn-stat totals / tooltips can show base + augment.

    Format (see the augdump addon / memory catseyexi-augment-extdata-format):
      Extra is a byte string. Extra[0]=0x02 (augmented marker), Extra[1]=type/rank.
      From Extra[2], each augment is one 2-byte little-endian word until 0x0000:
        id = word & 0x07FF ;  magnitude = (word >> 11) + 1  (= tier, 1..32).
      id -> stat(s) via AUG_STATS and a readable label via AUG_NAME. The id is the
      retail augment PACKET id, client-rendered; mappings verified against CatsEyeXI's
      own server augment_name table (and LSB augments.sql + tools/modifier_map.lua).
      Value = base + (tier-1)*step; base/step are 1 for almost every id (so value ==
      tier), except the ids in SCALE below (HP/MP high ranges, count-by-N, WS dmg).
      Ids 136/163/205/214/219/256 are UNDEFINED gaps in the server table (no stat,
      garbled in-game) -- they surface only from trailing extdata bytes on relic/NM
      gear, so they are intentionally left unmapped rather than guessed.
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
    -- Identified from a friend's augdump by cross-referencing LSB's augments.sql
    -- (the packet-id -> modId table) with tools/modifier_map.lua. Only the ids that
    -- map to a stat the optimizer already models (see apicrawl CORE) are summed here;
    -- everything else is display-only in AUG_NAME below.
    [31]  = {'Evasion'}, [37] = {'MagicEvasion'}, [41] = {'CriticalHitRate'},
    [68]  = {'Accuracy','Attack'}, [130] = {'Attack','RangedAttack'},
    [133] = {'MagicAttackBonus'}, [143] = {'DoubleAttack'}, [144] = {'TripleAttack'},
    [145] = {'Counter'}, [146] = {'DualWield'}, [195] = {'SubtleBlow'}, [740] = {'DMG'},
    -- +33 stat variants (paired with SCALE below so they sum as +33, not +1):
    [62]  = {'Accuracy'}, [63] = {'RangedAccuracy'}, [64] = {'MagicAccuracy'}, [65] = {'Attack'},
    [66]  = {'RangedAttack'}, [69] = {'RangedAccuracy','RangedAttack'},
    [129] = {'Accuracy','RangedAccuracy'}, [131] = {'MagicAccuracy','MagicAttackBonus'},
    -- NOTE: 2/3/4/10/11/12/18 (HP/MP high ranges), 78/79/82/83 (count-by-N) and the WS-dmg
    -- families are display-only (not summed) -- some surface as trailing-byte noise on relic
    -- gear, so counting them could inflate worn totals. 40 (Enmity) is a reduction, also
    -- display-only. Their VALUES still render correctly via SCALE / attrsFor (below).
};

-- Readable label per id (for tooltips). Falls back to "aug#<id>". Regenerated from
-- CatsEyeXI's server augment_name table: irregular ids listed explicitly here, regular
-- families (attributes, skills, resists, pet attrs, weapon DMG/Delay) filled by the loop
-- below. Weapon-skill DMG augments (1024-1140, 1536-1652) get a generic "WS DMG" name in
-- attrsFor(); the two the author actually owns keep their real names (1026/1067).
local AUG_NAME = {
    -- HP / MP
    [1]='HP',[2]='HP',[3]='HP',[4]='HP',[9]='MP',[10]='MP',[11]='MP',[12]='MP',
    [17]='HP/MP',[18]='HP/MP',[78]='HP',[79]='HP',[82]='MP',[83]='MP',
    -- Accuracy / Attack / Evasion / Defense / Magic
    [23]='Acc',[25]='Att',[27]='R.Acc',[29]='R.Att',[31]='Evasion',[33]='DEF',[35]='M.Acc',
    [37]='M.Eva',[39]='Enmity',[40]='Enmity',[41]='Crit Rate',[42]='Enemy Crit Rate',
    [62]='Acc',[63]='R.Acc',[64]='M.Acc',[65]='Att',[66]='R.Att',
    [68]='Acc/Att',[69]='R.Acc/R.Att',[70]='M.Acc/M.Atk',[129]='Acc/R.Acc',[130]='Att/R.Att',
    [131]='M.Acc/M.Atk',[132]='Dbl.Atk./Crit',[133]='M.Atk Bns',[134]='M.Def Bns',
    -- DMG / delay / haste / dmg-taken
    [45]='DMG',[47]='Delay',[48]='Delay',[49]='Haste',[50]='Slow',[76]='DMG',[77]='Delay',
    [51]='HHP',[52]='HMP',[53]='Spell Intr.',[54]='PDT',[55]='M.Dmg Taken',[56]='Breath DT',
    [57]='M.Crit Rate',[58]='M.Def Bns',[71]='DT',
    -- Regen / refresh / traits
    [59]='Regain(latent)',[60]='Refresh(latent)',[61]='Resist Ailments',[67]='All Songs',
    [72]='EXP',[73]='EXP',[74]='Cap Pt',[75]='Cap Pt',[80]='M.Acc/M.Dmg',[81]='Eva/M.Eva',
    [137]='Regen',[138]='Refresh',[139]='Rapid Shot',[140]='Fast Cast',[141]='Conserve MP',
    [142]='Store TP',[143]='Dbl.Atk.',[144]='Triple Atk.',[145]='Counter',[146]='Dual Wield',
    [147]='Treasure Hunter',[148]='Gilfinder',[151]='Martial Arts',[153]='Shield Mastery',
    [194]='Kick Rate',[195]='Subtle Blow',[198]='Zanshin',[211]='Snapshot',[212]='Recycle',
    [215]='Ninja Tool Exp.',[232]='True Shot',[233]='Blood Boon',[237]='Occult Acumen',[251]='Daken',
    [313]='Earth M.Acc',
    -- Ability delays / potency / recast / weapon-skill mods (320-380)
    [320]='BP Delay',[321]='Perp. Cost',[322]='Song Cast',[323]='Cure Cast',[324]='Call Beast Delay',
    [325]='Quick Draw Delay',[326]='WS Acc.',[327]='WS Dmg',[328]='Crit Dmg',[329]='Cure Pot.',
    [330]='Waltz Pot.',[331]='Waltz Delay',[332]='SC Dmg',[333]='Conserve TP',[334]='M.Burst Dmg',
    [335]='M.Crit Dmg',[336]='Sic Delay',[337]='Song Recast',[338]='Barrage',[339]='Elem. Siphon',
    [340]='Roll Delay',[341]='Repair Pot.',[342]='Waltz TP Cost',[343]='Drain/Aspir',[347]='Healing Recast',
    [348]='Elem. Recast',[349]='Enfb. Recast',[350]='Occ. Max M.Acc',[351]='Occ.Quicken',[352]='Occ. TP Dmg',
    [353]='TP Bonus',[354]='Quad.Atk.',[355]='Enh. Recast',[356]='Cure Rcvd',[360]='Save TP',
    [362]='Magic Dmg',[363]='Block Rate',[366]='BP Delay II',[368]='Phalanx',[369]='BP Dmg',
    [370]='Rev. Flourish',[371]='Regen Pot.',[372]='Embolden',[374]='Enh.Dur.',[379]='Enmity/Utsu',
    [380]='Phys.Dmg Limit',
    -- Attribute combos / misc bundles
    [550]='STR/DEX',[551]='STR/VIT',[552]='STR/AGI',[553]='DEX/AGI',[554]='INT/MND',[555]='MND/CHR',
    [556]='INT/MND/CHR',[557]='STR/CHR',[558]='STR/INT',[559]='STR/MND',[640]='Counter',
    [896]='Sword Enh. Dmg',[897]='Souleater',[899]='Sword Enh. Dmg',[913]='Move Speed',
    [1152]='DEF',[1153]='Evasion',[1154]='M.Eva',[1155]='PDT',[1156]='M.Dmg Taken',[1157]='Spell Intr.',
    [1158]='Resist Ailments',[1246]='Pet:PDT',[1247]='Pet:M.Dmg Taken',[1248]='Enh.Dur.',[1249]='Helix Dur.',
    [1250]='Indi Dur.',[1251]='Enfb. Dur.',[1264]='Meditate Dur.',[1472]='Parry Rate',
    [1026]='Howling Fist',[1067]='Black Halo',
    -- Pet: family (96-127)
    [96]='Pet:Acc/R.Acc',[97]='Pet:Att/R.Att',[98]='Pet:Evasion',[99]='Pet:DEF',[100]='Pet:M.Acc',
    [101]='Pet:M.Atk',[102]='Pet:Crit Rate',[103]='Pet:Enemy Crit',[104]='Pet:Enmity',[105]='Pet:Enmity',
    [106]='Pet:Acc/R.Acc',[107]='Pet:Att/R.Att',[108]='Pet:M.Acc/M.Atk',[109]='Pet:DblAtk/Crit',
    [110]='Pet:Regen',[111]='Pet:Haste',[112]='Pet:DT',[113]='Pet:R.Acc',[114]='Pet:R.Att',
    [115]='Pet:Store TP',[116]='Pet:Subtle Blow',[117]='Pet:M.Eva',[118]='Pet:PDT',[119]='Pet:M.Def Bns',
    [120]='Avatar:M.Atk',[121]='Pet:Breath',[122]='Pet:TP Bonus',[123]='Pet:Dbl.Atk.',[124]='Pet:Acc/Att',
    [125]='Pet:M.Acc/M.Dmg',[126]='Pet:Magic Dmg',[127]='Pet:M.Dmg Taken',
    -- Left unmapped on purpose: 136/163/205/214/219/256 are UNDEFINED gaps in CatsEyeXI's own
    -- table (no stat, garbled in-game) -- they only surface from trailing extdata bytes on
    -- relic/NM/empyrean gear (Apogee, Pinnacle, Sky gods), not real augments.
};
-- Fill the regular id families (guarded so the explicit labels above always win).
do
    local function fill(id, label) if AUG_NAME[id] == nil then AUG_NAME[id] = label; end end
    local EL = { 'Fire','Ice','Wind','Earth','Lightning','Water','Light','Dark' };
    for i, e in ipairs(EL) do
        fill(767 + i, e .. ' Res.'); fill(775 + i, e .. ' Res.'); fill(831 + i, 'Add.' .. e);
    end
    local AT = { 'STR','DEX','VIT','AGI','INT','MND','CHR' };
    for i, a in ipairs(AT) do
        fill(511 + i, a); fill(518 + i, a); fill(1791 + i, 'Pet:' .. a); fill(1798 + i, 'Pet:' .. a);
    end
    local RS = { 'Sleep','Poison','Paralyze','Blind','Silence','Virus','Petrify','Bind','Curse','Gravity','Slow','Stun','Charm' };
    for i, r in ipairs(RS) do fill(175 + i, r .. ' Res.'); end
    local SK1 = { 'H2H','Dagger','Sword','G.Sword','Axe','G.Axe','Scythe','Polearm','Katana','G.Katana','Club','Staff' };
    for i, s in ipairs(SK1) do fill(256 + i, s .. ' Skill'); end
    local SK2 = { 'Auto Melee','Auto Ranged','Auto Magic','Archery','Marksman','Throwing' };
    for i, s in ipairs(SK2) do fill(277 + i, s .. ' Skill'); end
    local SK3 = { 'Shield','Parry','Divine','Healing','Enh.Mag.','Enf.Mag.','Elem.Mag.','Dark Mag.','Summon','Ninjutsu','Sing','String','Wind','Blue Mag.','Geomancy','Handbell' };
    for i, s in ipairs(SK3) do fill(285 + i, s .. ' Skill'); end
    for i = 0, 5 do fill(740 + i, 'DMG'); fill(746 + i, 'R.DMG'); end
    for id = 752, 759 do fill(id, 'Delay'); end
    for id = 760, 767 do fill(id, 'R.Delay'); end
end
-- Ids whose magnitude reads as a percentage (WS-dmg families handled in attrsFor).
local PERCENT = {
    [41]=true,[42]=true,[47]=true,[48]=true,[49]=true,[50]=true,[53]=true,[54]=true,[55]=true,
    [56]=true,[57]=true,[71]=true,[77]=true,[140]=true,[143]=true,[144]=true,[322]=true,[323]=true,
    [327]=true,[328]=true,[329]=true,[330]=true,[332]=true,[334]=true,[335]=true,[350]=true,[351]=true,
    [352]=true,[354]=true,[356]=true,[380]=true,[897]=true,[899]=true,[913]=true,[1155]=true,[1156]=true,
    [1157]=true,[1248]=true,[1472]=true,
};
-- Ids whose effect is a reduction (stored positive; display with '-').
local REDUCE = {
    [40]=true,[42]=true,[48]=true,[53]=true,[54]=true,[55]=true,[56]=true,[58]=true,[71]=true,[77]=true,
    [320]=true,[321]=true,[322]=true,[323]=true,[324]=true,[325]=true,[331]=true,[336]=true,[337]=true,
    [340]=true,[342]=true,[347]=true,[348]=true,[349]=true,[355]=true,[1155]=true,[1156]=true,[1157]=true,
};
-- Ids whose applied value isn't just the tier: value = base + (tier-1)*step.
-- (Anything not listed is base=1, step=1, so value == tier == mag. step=0 means a fixed value.)
local SCALE = {
    [2]={33,1},[3]={65,1},[4]={97,1},        -- HP high ranges (HP+33/+65/+97 and up)
    [10]={33,1},[11]={65,1},[12]={97,1},     -- MP high ranges
    [18]={33,1},[70]={33,1},                 -- HP+33/MP+33 ; M.Acc+33/M.Atk+33
    [62]={33,1},[63]={33,1},[64]={33,1},[65]={33,1},[66]={33,1},  -- Acc/R.Acc/M.Acc/Att/R.Att +33
    [78]={2,2},[82]={2,2},[79]={3,3},[83]={3,3},                  -- HP/MP "count by 2" / "count by 3"
    [76]={33,1},[741]={33,1},[742]={65,1},[743]={97,1},           -- melee DMG high ranges
    [747]={33,1},[748]={65,1},[749]={97,1},                       -- ranged DMG high ranges
    [339]={5,5},[640]={2,2},                 -- Elemental Siphon (x5) ; Counter+2 (count by 2)
    [1152]={10,0},[1153]={3,0},[1154]={3,0}, -- fixed-value bundles: DEF+10, Eva+3, M.Eva+3
    [1155]={2,0},[1156]={2,0},[1157]={2,0},[1158]={2,0},[1246]={2,0},[1247]={2,0},  -- fixed -2% / +2
};

-- Resolve id+tier -> (name, value, isPercent, isReduce), applying SCALE plus the two
-- weapon-skill DMG families (1024-1140 / 1536-1652: "+5% per tier"), which are named
-- generically ("WS DMG") since only the specific ones the author owns are in AUG_NAME.
local function attrsFor(id, mag)
    local name   = AUG_NAME[id];
    local pct    = PERCENT[id] or false;
    local reduce = REDUCE[id] or false;
    local sc     = SCALE[id];                        -- value = base + (tier-1)*step
    local val    = sc and (sc[1] + (mag - 1) * sc[2]) or mag;
    if (id >= 1024 and id <= 1140) or (id >= 1536 and id <= 1652) then
        name = name or 'WS DMG';
        val  = 5 * mag;   -- "+5% (count by 5)"
        pct  = true;
    end
    return name, val, pct, reduce;
end

-- Decode an Extra byte-string -> list of { id, mag, val, pct, reduce, keys, name }.
function M.decode(extra)
    local out = {};
    if type(extra) ~= 'string' or #extra < 4 or extra:byte(1) ~= 0x02 then return out; end
    local i = 3;   -- byte offset 2 (skip the 2-byte header)
    while i + 1 <= #extra do
        local word = (extra:byte(i) or 0) + (extra:byte(i + 1) or 0) * 256;
        if word ~= 0 then
            local id  = word % 2048;                    -- word & 0x07FF
            local mag = math.floor(word / 2048) + 1;    -- (word >> 11) + 1  (tier)
            local name, val, pct, reduce = attrsFor(id, mag);
            out[#out + 1] = { id = id, mag = mag, val = val, pct = pct, reduce = reduce,
                              keys = AUG_STATS[id], name = name };
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
            for _, k in ipairs(a.keys) do t[k] = (t[k] or 0) + a.val; end
        end
    end
    return t;
end

-- Human-readable augment summary, e.g. "HP+15, DEX/AGI+3, Haste+3%". "" if none.
function M.describe(extra)
    local parts = {};
    for _, a in ipairs(M.decode(extra)) do
        local nm   = a.name or ('aug#' .. tostring(a.id));
        local sign = a.reduce and '-' or '+';
        local pct  = a.pct and '%' or '';
        parts[#parts + 1] = string.format('%s%s%d%s', nm, sign, a.val, pct);
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

-- { itemId -> { statKey -> delta } } for augmented copies in your bags -- the first augmented
-- copy of each id, decoded to stat deltas (M.stats). Powers augment-aware set scoring so the
-- weighing counts your private augments, not just base stats.
function M.ownedAugStats()
    local out = {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        if inv == nil then return; end
        for _, cid in ipairs(SCAN_CONTAINERS) do
            local max = inv:GetContainerCountMax(cid);
            if max ~= nil and max > 0 then
                for j = 1, max do
                    local item = inv:GetContainerItem(cid, j);
                    if item ~= nil and item.Id ~= nil and item.Id ~= 0 and item.Id ~= 65535 and out[item.Id] == nil then
                        local s = M.stats(item.Extra);
                        if next(s) ~= nil then out[item.Id] = s; end
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
