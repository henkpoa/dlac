--[[
    dlac/gearimport.lua

    Gear auto-import  --  Piece #1: the inventory / resource reader.

    Reads the equippable gear you actually own out of Ashita v4 memory and
    reports it to the console, resolving each item to the data we will later
    turn into gear.lua entries: Name, Level, Id, slot, and (for weapons) the
    category / DMG / Delay / one-hand-vs-two-hand, plus a best-effort augment
    decode via LuAshitacast's own decoder.

    This piece is deliberately READ-ONLY. It does not write gear.lua, any
    staging file, or the personal file -- that is Piece #3 onward. Run it
    in-game with:

        /dl scan            (or /dlac scan)

    It is loaded by dlac/utils.lua through a guarded require, so anything
    that goes wrong in here can never break profile loading. Every field is
    read exactly the way the Find addon and LuAshitacast itself read it.
]]--

local gear = require("dlac\\gear");
-- The Owned-gear record rules (Type canon/heal, Shield/Grip by name, effective
-- RSlot): one home, shared with gearui's enrich, gearexport and the type filter.
local grec = require("dlac\\gear\\gearrecord");
-- The safe file-replacement ladder (backup / tmp / validate / rename / restore),
-- written once -- both gear.lua writers here (commit and /dl fix) ride it.
local sw = require("dlac\\lib\\safewrite");
-- Catalog access (lazy load + raw id index): the one walker, shared with gearui.
local ci = require("dlac\\gear\\catalogindex");

local M = {};

-- Colored [dlac] chat output (chatfmt): the shadowed `print` re-heads
-- "[dlac] ..."-prefixed lines with the colored header; plain when unavailable.
local _cfmtok, _cfmt = pcall(require, 'dlac\\chatfmt');
local print = (_cfmtok and type(_cfmt) == 'table' and type(_cfmt.print) == 'function') and _cfmt.print or print;

-- ---------------------------------------------------------------------------
-- Item names in the resource are ShiftJIS. LuAshitacast converts them with the
-- encoding lib; we do the same, and fall back to the raw bytes if the lib isn't
-- reachable from this context (harmless for ASCII English item names).
-- ---------------------------------------------------------------------------
local ok_enc, encoding = pcall(require, 'encoding');
local function decodeName(raw)
    if raw == nil then return nil; end
    if ok_enc and encoding ~= nil then
        local ok, s = pcall(function() return encoding:ShiftJIS_To_UTF8(raw); end);
        if ok and type(s) == 'string' and #s > 0 then return s; end
    end
    return raw;
end

-- Equip-eligible containers: Inventory (0) + the 8 Wardrobes (8, 10-16). This is the
-- AVAILABILITY set -- gear in Safe/Storage/Locker/Satchel is owned but can't be
-- equipped until moved here (the GUI shows such gear with a red name). The list is
-- THE oracle's (issue #70); re-exported here as published API for existing callers
-- (ownedcache, and through it the fishing heartbeat).
M.SCAN_CONTAINERS = require("dlac\\gear\\gearoracle").equipBags();
local AVAIL_SET = {};
for _, cid in ipairs(M.SCAN_CONTAINERS) do AVAIL_SET[cid] = true; end

-- EVERY container that can hold your property -- the ownership truth for /dl prune:
-- Inventory(0), Safe(1)/Safe2(9), Storage(2), Temporary(3), Locker(4), Satchel(5),
-- Sack(6), Case(7), and the 8 Wardrobes. Deliberately broader than SCAN_CONTAINERS:
-- gear parked in deep storage is still OWNED and must never be pruned. (Gear stored
-- OUTSIDE the container system -- e.g. with the Porter Moogle -- is invisible here;
-- the prune dry-run warns about that.)
M.ALL_CONTAINERS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };

-- item.Slots is a bitmask -> map it to the gear.lua top-level slot key. Rings
-- and earrings report a *combined* either-hand / either-ear mask, which is why
-- the 0x1800 / 0x6000 entries exist alongside the single bits.
local SLOT_BY_MASK = {
    [0x0001] = "Main",  [0x0002] = "Sub",    [0x0004] = "Range", [0x0008] = "Ammo",
    [0x0010] = "Head",  [0x0020] = "Body",   [0x0040] = "Hands", [0x0080] = "Legs",
    [0x0100] = "Feet",  [0x0200] = "Neck",   [0x0400] = "Waist",
    [0x0800] = "Ear",   [0x1000] = "Ear",    [0x1800] = "Ear",
    [0x2000] = "Ring",  [0x4000] = "Ring",   [0x6000] = "Ring",
    [0x8000] = "Back",
};

local SLOT_BIT_ORDER = {
    0x0001, 0x0002, 0x0004, 0x0008, 0x0010, 0x0020, 0x0040, 0x0080,
    0x0100, 0x0200, 0x0400, 0x0800, 0x1000, 0x2000, 0x4000, 0x8000,
};

local function slotFromMask(slots)
    if slots == nil or slots == 0 then return nil; end
    if SLOT_BY_MASK[slots] ~= nil then return SLOT_BY_MASK[slots]; end
    -- Unusual combo: fall back to the lowest mapped bit that is set.
    for _, m in ipairs(SLOT_BIT_ORDER) do
        if bit.band(slots, m) ~= 0 and SLOT_BY_MASK[m] ~= nil then
            return SLOT_BY_MASK[m];
        end
    end
    return nil;
end

-- The effective reserved-slot mask (server rslot + the ADR 0010 trinket completion)
-- is a RECORD RULE and lives in gearrecord with the rest of them, so the fresh
-- write and the /dl fix backfill can never disagree with any other consumer.
local effectiveRSlot = grec.effectiveRSlot;

-- RSlot (reserved slots) by item id, from the catalog. The CLIENT resource has no such field --
-- reservation is server data (item_equipment.rslot), so it can only come from the API crawl (plus
-- the trinket completion in effectiveRSlot). Built once, lazily, and guarded: without the catalog
-- (headless tests) every lookup is nil and scanning behaves exactly as before.
local _rslotById = nil;
local function rslotFor(id)
    if _rslotById == nil then
        _rslotById = {};
        pcall(function()
            for cid, rec in pairs(ci.rawIndex()) do
                local rs = effectiveRSlot(rec);
                if rs ~= nil then _rslotById[cid] = rs; end
            end
        end);
    end
    return _rslotById[id];
end

-- Range/Ammo pairing key ("<skill>:<subskill>") by item id, from the catalog. Same
-- shape and same reason as rslotFor above: the CLIENT resource carries Skill but has
-- NO subskill field (Ashita's IItem stops at Skill), and subskill is exactly what
-- separates a gun (26:1) from a crossbow (26:0). So it can only come from the API
-- crawl. Built once, lazily, guarded -- no catalog (headless tests) means
-- every lookup is nil, and every consumer treats nil as "unknown, don't constrain".
--
-- v160: the stamp written into gear.lua is now a CACHE, not the only road. The
-- engine calls THIS (via dispatch.recordPair) whenever a record carries no Pair,
-- so an old file no longer switches the pair law off until its owner runs
-- `/dl fix`. The stamp is kept because it costs nothing and survives a missing
-- catalog; it is no longer load-bearing.
local _pairById = nil;
local function pairFor(id)
    if _pairById == nil then
        _pairById = {};
        pcall(function()
            for cid, rec in pairs(ci.rawIndex()) do
                if type(rec.Pair) == 'string' and rec.Pair ~= '' then _pairById[cid] = rec.Pair; end
            end
        end);
    end
    return _pairById[id];
end

-- Weapon skill id -> the category key used under gear.Main / gear.Range / gear.Ammo.
-- (Instruments and a few exotic ranged types get refined in Piece #2.)
local WEAPON_CATEGORY = {
    [1]  = "HandToHand",  [2]  = "Dagger",       [3]  = "Sword",   [4]  = "GreatSword",
    [5]  = "Axe",         [6]  = "GreatAxe",     [7]  = "Scythe",  [8]  = "Polearm",
    [9]  = "Katana",      [10] = "GreatKatana",  [11] = "Club",    [12] = "Staff",
    [25] = "Archery",     [26] = "Marksmanship", [27] = "Throwing",
};

-- Skills that occupy both hands (no sub weapon possible). Hand-to-Hand is
-- included -- monks can't put anything in the sub slot.
local TWO_HANDED = {
    [1] = true, [4] = true, [6] = true, [7] = true, [8] = true, [10] = true, [12] = true,
};

-- Range slot categories by Skill. Bows/guns/throwing are weapons; instruments and
-- fishing rods are Damage=0 non-weapons but still carry their Skill, so they nest
-- too. Skill ids from the game's skills resource: 41 Stringed Instrument,
-- 42 Wind Instrument, 45 Handbell, 48 Fishing.
local RANGE_CATEGORY = {
    [25] = "Archery",          [26] = "Marksmanship",   [27] = "Throwing",
    [41] = "StringInstrument", [42] = "WindInstrument", [45] = "Handbell", [48] = "FishingRod",
};
local PUP_ONLY_MASK = 262144;   -- Jobs == PUP only (bit 18) -> animators go under Range.PUP

-- THE RANGE BUCKET, for the skill-0 families that have no skill to nest under
-- (animators, soultrappers). It must return SOMETHING: renderEntry drops a
-- Main/Range item with no category, so a nil here means the piece is never
-- written to gear.lua and therefore does not exist for the picker, the
-- ladders, or the engine.
--
-- The 2026-08-03 field case (Coffeepoo, PUP): the base Animator (17859) never
-- showed up anywhere. This bucket used to be gated on `Jobs == PUP_ONLY_MASK`,
-- an EXACT mask test -- but that animator is an ALL-JOBS item on this server
-- (sql/item_equipment.sql: jobs 4194303; catalog: Jobs = {"All"}), so it fell
-- through and was dropped. Every OTHER animator is PUP-only and indexed fine,
-- which is exactly why it read as one broken item rather than a broken rule.
-- The same hole swallowed Soultrapper / Soultrapper 2000 / Fiendtrapper /
-- Soulgauger SGR-1 / Marvelous Cheer.
--
-- So: bucket by WHAT THE PIECE IS, not by who may wear it. `0:10` / `0:11` is
-- the animator subskill (an item fact, the same key the server pairs oils on),
-- with the PUP-only mask kept as the answer when no catalog is loaded to
-- supply a Pair. Anything else skill-0 lands in Misc rather than nowhere.
--
-- A bucket at all, rather than the catalog's flat-at-the-slot shape (E27c):
-- gear.lua's own NameToObject loader walks Main/Range as STRICTLY two levels,
-- so a flat entry there would iterate the record's own fields and die on a nil
-- key. The user file cannot hold what the catalog can.
local function rangeCategory(skill, jobs, pair)
    local cat = RANGE_CATEGORY[skill or 0];
    if cat ~= nil then return cat; end
    if pair == '0:10' or pair == '0:11' or jobs == PUP_ONLY_MASK then return 'PUP'; end
    return 'Misc';
end
M.rangeCategory = rangeCategory;   -- pure seam (tests E29*)

-- Job bitmask -> abbreviations (bit i set = job i can equip; from fancychat).
local EQUIP_JOBS = {
    [1]="WAR",[2]="MNK",[3]="WHM",[4]="BLM",[5]="RDM",[6]="THF",[7]="PLD",[8]="DRK",
    [9]="BST",[10]="BRD",[11]="RNG",[12]="SAM",[13]="NIN",[14]="DRG",[15]="SMN",[16]="BLU",
    [17]="COR",[18]="PUP",[19]="DNC",[20]="SCH",[21]="GEO",[22]="RUN",
};
local ALL_JOBS_MASK = 8388606;   -- 0x7FFFFE: every job -> unrestricted, so no Jobs emitted

-- Decode item.Jobs to a job list. EVERY equippable item gets one: a subset lists
-- the jobs; all-jobs collapses to {"All"} (a matchable sentinel, not omitted) so
-- future job-aware set-building can check every entry the same way.
local function decodeJobs(mask)
    if mask == nil or mask == 0 then return nil; end
    if mask == ALL_JOBS_MASK then return { "All" }; end
    local out = {};
    for i = 1, 22 do
        if bit.band(1, bit.rshift(mask, i)) == 1 and EQUIP_JOBS[i] ~= nil then
            table.insert(out, EQUIP_JOBS[i]);
        end
    end
    if #out == 0 then return nil; end
    if #out >= 22 then return { "All" }; end
    return out;
end

local RARE_FLAG = 0x8000;
local EX_FLAG   = 0x6040;

-- Resolve one raw inventory entry to an enriched record, or nil if it isn't
-- equippable gear (potions, crystals, materials, ...).
local function resolveItem(entry)
    local res = AshitaCore:GetResourceManager():GetItemById(entry.Id);
    if res == nil then return nil; end
    if res.Slots == nil or res.Slots == 0 then return nil; end   -- not equippable

    local shortName = decodeName(res.Name ~= nil and res.Name[1] or nil);
    local fullName = shortName;
    if res.LogNameSingular ~= nil and res.LogNameSingular[1] ~= nil and #res.LogNameSingular[1] > 0 then
        fullName = decodeName(res.LogNameSingular[1]);
    end

    local rec = {
        Id       = entry.Id,
        Name     = shortName,   -- short/equipment name -> what equip calls need
        FullName = fullName,    -- log name (human-readable) -> what the key is built from
        Level    = res.Level,
        Slots    = res.Slots,
        Slot     = slotFromMask(res.Slots),
        Jobs     = res.Jobs,
        Flags    = res.Flags,
        RSlot    = rslotFor(entry.Id),   -- slots this piece takes away while worn
        Pair     = pairFor(entry.Id),    -- Range/Ammo skill:subskill (nil = not a Range/Ammo item)
        Count    = 1,
    };

    rec.Skill = res.Skill;
    local isWeapon = (res.Damage ~= nil and res.Delay ~= nil and res.Skill ~= nil
                      and res.Damage > 0 and res.Delay > 0 and res.Skill > 0);
    if isWeapon then
        rec.IsWeapon = true;
        rec.Damage   = res.Damage;
        rec.Delay    = res.Delay;
    end

    -- Category for the nested slots. Main: by weapon skill. Range: by ranged /
    -- instrument / fishing skill even when Damage=0, and never nil -- see
    -- rangeCategory for why the skill-0 families still get a bucket.
    if rec.Slot == 'Main' then
        rec.Category = WEAPON_CATEGORY[res.Skill or 0];
        if rec.Category ~= nil then rec.OneHanded = (TWO_HANDED[res.Skill] ~= true); end
    elseif rec.Slot == 'Range' then
        rec.Category = rangeCategory(res.Skill, res.Jobs, rec.Pair);
    end

    if res.Description ~= nil then
        rec.Description = res.Description[1];
    end

    -- Best-effort augment decode. Wrapped in pcall so a decode failure (e.g. a
    -- custom CatsEyeXI augment the retail tables don't know) never aborts the scan.
    local ok, aug = pcall(function() return gData.GetAugment(entry); end);
    if ok and type(aug) == 'table' and aug.Type ~= nil and aug.Type ~= 'Unaugmented' then
        rec.Augment = aug;
    end

    return rec;
end

-- Every existing table key in gear.lua, lowercased. Walks recursively: a table
-- with a .Name is an entry (record its key); anything else is a container.
local function collectExistingKeys()
    local keys = {};
    local function walk(t)
        for k, v in pairs(t) do
            if type(v) == 'table' then
                if v.Name ~= nil then
                    if type(k) == 'string' then keys[string.lower(k)] = true; end
                else
                    walk(v);
                end
            end
        end
    end
    for slotName, slotVars in pairs(gear) do
        if slotName ~= 'NameToObject' and type(slotVars) == 'table' then walk(slotVars); end
    end
    return keys;
end

-- The CatsEyeXI private-augment decoder, required lazily and only once (addon
-- state; in a state where it cannot load -- headless, LAC -- every signature
-- reads '' and the augment-aware paths fall back to id behaviour).
local _augTried, _augmod = false, nil;
local function augdecoder()
    if not _augTried then
        _augTried = true;
        pcall(function()
            local m = require('dlac\\feature\\augments');
            if type(m) == 'table' and type(m.signature) == 'function' then _augmod = m; end
        end);
    end
    return _augmod;
end

-- Existing augment-PINNED records: { [lower(Name)..'|'..AugKey] = true }. The
-- augment-split scan judges Known per ROLL against this -- a bare (unpinned)
-- record means "any copy" and cannot vouch for a specific roll, or the second
-- mitten would read as already-documented forever and never stage.
local function collectExistingAugPairs()
    local out = {};
    local function walk(t)
        for _, v in pairs(t) do
            if type(v) == 'table' then
                if v.Name ~= nil then
                    if type(v.AugKey) == 'string' and type(v.Name) == 'string' then
                        out[string.lower(v.Name) .. '|' .. v.AugKey] = true;
                    end
                else
                    walk(v);
                end
            end
        end
    end
    for slotName, slotVars in pairs(gear) do
        if slotName ~= 'NameToObject' and type(slotVars) == 'table' then walk(slotVars); end
    end
    return out;
end

-- Scan the given containers (default: ALL_CONTAINERS -- every bag, safe, locker,
-- satchel, sack, case and wardrobe) and return a list of unique enriched records.
-- Multiple copies of one item collapse to a single record with an incremented
-- .Count (renderEntry emits Count >= 2 on Main weapons -- the same-weapon
-- dual-wield fact that replaced the legacy InBothHands flag).
--
-- EXCEPT augment rolls (2026-08-10, the two-Hecatomb-mittens case): an id owned
-- in >= 2 DISTINCT private-augment rolls is different gear wearing one name --
-- collapsed, every roll but the engine's first bag find is unreachable. Such an
-- id yields one record PER ROLL: AugKey = the canonical signature (augments.
-- signature; '' = the unaugmented copy), AugText = the roll readable, Count =
-- that roll's copies, Known judged per roll (collectExistingAugPairs). A
-- single-roll id keeps the collapsed record, byte-identical to the old scan.
function M.scan(containers)
    containers = containers or M.ALL_CONTAINERS;   -- gear.lua documents everything you OWN,
                                                   -- wherever it lives; availability is display state
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    if inv == nil then
        print('[dlac] scan: inventory manager unavailable.');
        return {};
    end

    local byId  = {};   -- Id -> record, or false once we've decided it's not gear
    local items = {};
    local dec   = augdecoder();
    local rolls = {};   -- Id -> { n=distinct, order={sig..}, count={sig->copies}, text={sig->readable} }

    -- Recognise already-documented items tolerantly: match the short name, the full
    -- (log) name, OR the generated key, against existing Names and keys. Humans
    -- mistype either the name or the key, so any single match means "we have it".
    local knownNames = {};
    for nm in pairs(gear.NameToObject) do knownNames[string.lower(nm)] = true; end
    local knownKeys = collectExistingKeys();

    for _, cid in ipairs(containers) do
        local maxCount = inv:GetContainerCountMax(cid);
        if maxCount ~= nil and maxCount > 0 then
            for idx = 0, maxCount, 1 do
                local entry = inv:GetContainerItem(cid, idx);
                if entry ~= nil and entry.Id ~= nil and entry.Id ~= 0 and entry.Id ~= 65535 then
                    local cached = byId[entry.Id];
                    if cached == nil then
                        local rec = resolveItem(entry);
                        if rec ~= nil then
                            local known = false;
                            if rec.Name and knownNames[string.lower(rec.Name)] then known = true; end
                            if not known and rec.FullName and knownNames[string.lower(rec.FullName)] then known = true; end
                            if not known then
                                local k = M.makeKey(rec.FullName or rec.Name);
                                if k and knownKeys[string.lower(k)] then known = true; end
                            end
                            if not known and rec.Name then
                                local k = M.makeKey(rec.Name);
                                if k and knownKeys[string.lower(k)] then known = true; end
                            end
                            rec.Known = known;
                            byId[entry.Id] = rec;
                            table.insert(items, rec);
                        else
                            byId[entry.Id] = false;   -- resolved once; skip future copies
                        end
                    elseif cached ~= false then
                        cached.Count = cached.Count + 1;
                    end
                    -- Roll tally: one bump per bag slot (the same unit Count
                    -- counts), signature '' for unaugmented copies -- a plain
                    -- copy beside an augmented one is a distinct roll too.
                    if dec ~= nil and byId[entry.Id] ~= false and byId[entry.Id] ~= nil then
                        local sig, txt = '', nil;
                        pcall(function()
                            sig = dec.signature(entry.Extra);
                            if sig ~= '' then txt = dec.describe(entry.Extra); end
                        end);
                        local t = rolls[entry.Id];
                        if t == nil then
                            t = { n = 0, order = {}, count = {}, text = {} };
                            rolls[entry.Id] = t;
                        end
                        if t.count[sig] == nil then
                            t.n = t.n + 1;
                            t.order[#t.order + 1] = sig;
                            t.count[sig] = 0;
                            t.text[sig] = txt;
                        end
                        t.count[sig] = t.count[sig] + 1;
                    end
                end
            end
        end
    end

    -- The augment split (see the function header). Bag-walk order is kept for
    -- the roll records so a rescan stages them in a stable order.
    local out, knownAug = {}, nil;
    for _, rec in ipairs(items) do
        local t = rolls[rec.Id];
        if t ~= nil and t.n >= 2 then
            if knownAug == nil then knownAug = collectExistingAugPairs(); end
            local ln = string.lower(rec.Name or '');
            for _, sig in ipairs(t.order) do
                local copy = {};
                for k, v in pairs(rec) do copy[k] = v; end
                copy.Count   = t.count[sig];
                copy.AugKey  = sig;
                copy.AugText = t.text[sig];
                copy.Known   = (knownAug[ln .. '|' .. sig] == true);
                out[#out + 1] = copy;
            end
        else
            out[#out + 1] = rec;
        end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- Reporting
-- ---------------------------------------------------------------------------
local function flagString(flags)
    if flags == nil then return ''; end
    local s = '';
    if bit.band(flags, RARE_FLAG) ~= 0 then s = s .. '[Rare]'; end
    if bit.band(flags, EX_FLAG)   ~= 0 then s = s .. '[Ex]'; end
    return s;
end

local function augPart(v)
    if v.String ~= nil then return v.String; end
    if v.Stat ~= nil then
        local val = v.Value or 0;
        return tostring(v.Stat) .. ((val >= 0) and '+' or '') .. tostring(val);
    end
    return nil;
end

local function augString(rec)
    if type(rec.AugText) == 'string' and rec.AugText ~= '' then   -- augment-split roll
        return ' {aug: ' .. rec.AugText .. '}';
    end
    if rec.Augment == nil or rec.Augment.Augs == nil then return ''; end
    local parts = {};
    for _, v in pairs(rec.Augment.Augs) do
        local p = augPart(v);
        if p ~= nil then table.insert(parts, p); end
    end
    if #parts == 0 then return ''; end
    return ' {aug: ' .. table.concat(parts, ', ') .. '}';
end

-- Print a readable report. '*' marks items not yet present in gear.lua.
function M.printReport(items)
    table.sort(items, function(a, b)
        local sa, sb = tostring(a.Slot), tostring(b.Slot);
        if sa ~= sb then return sa < sb; end
        return tostring(a.Name) < tostring(b.Name);
    end);

    print(string.format('[dlac] scan found %d equippable item(s):', #items));

    local newCount = 0;
    for _, it in ipairs(items) do
        if not it.Known then newCount = newCount + 1; end

        local loc = it.Slot or '?';
        if it.IsWeapon then loc = loc .. '/' .. tostring(it.Category); end

        local extra = '';
        if it.IsWeapon then
            extra = string.format('  DMG:%d Dly:%d %s',
                it.Damage or 0, it.Delay or 0, it.OneHanded and '1H' or '2H');
        end
        if it.Count and it.Count > 1 then
            extra = extra .. string.format('  x%d', it.Count);
        end

        print(string.format('  %s %-26s Lv%-3s Id:%-6d %-14s%s%s%s',
            (it.Known and ' ' or '*'),
            tostring(it.Name), tostring(it.Level), it.Id,
            loc, extra, flagString(it.Flags), augString(it)));
    end

    print(string.format('[dlac] %d new ( * ), %d already in gear.lua.',
        newCount, #items - newCount));
end

-- Owned quantity per item Id across equip-eligible bags (Inventory + the 8 Wardrobes),
-- including currently-equipped pieces (they still live in their wardrobe slot). Lets the
-- Sets/Auto-build logic avoid assigning more copies of an item than you own -- e.g. a
-- single Star Ring cannot fill both Ring1 and Ring2.
function M.ownedCounts()
    return M.ownedSplit().avail;
end

-- Human names for the container ids (tooltips: WHERE an item actually lives).
local CONTAINER_NAMES = {
    [0] = 'Inventory',  [1] = 'Mog Safe',    [2] = 'Storage',     [3] = 'Temporary',
    [4] = 'Mog Locker', [5] = 'Mog Satchel', [6] = 'Mog Sack',    [7] = 'Mog Case',
    [8] = 'Wardrobe',   [9] = 'Mog Safe 2',  [10] = 'Wardrobe 2', [11] = 'Wardrobe 3',
    [12] = 'Wardrobe 4', [13] = 'Wardrobe 5', [14] = 'Wardrobe 6', [15] = 'Wardrobe 7',
    [16] = 'Wardrobe 8',
};
function M.containerName(cid) return CONTAINER_NAMES[cid] or ('container ' .. tostring(cid)); end

-- One pass over EVERY container -> { total = {id->n}, avail = {id->n}, where = {id->{cid->n}},
--                                    aug = {id->{sig->{total,avail,where}}} }.
--   total: owned anywhere (Safe/Storage/Locker/Satchel/... included) -- visibility.
--   avail: Inventory + Wardrobes only -- equippability (pairing rules, automations,
--          and the red "in storage" name colour when owned but 0 available).
--   where: per-container counts, so tooltips can say WHICH bag holds the item.
--   aug:   the same three, PER private-augment roll (augments.signature of the
--          item's Extra) for augmented copies only -- how an augment-split
--          record (gear.lua AugKey) counts/colours ITS copy instead of every
--          copy of the id (ownedcache.augEntry reads this).
function M.ownedSplit()
    local split = { total = {}, avail = {}, where = {}, aug = {} };
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    if inv == nil then return split; end
    local dec = augdecoder();
    for _, cid in ipairs(M.ALL_CONTAINERS) do
        local maxCount = inv:GetContainerCountMax(cid);
        if maxCount ~= nil and maxCount > 0 then
            for idx = 0, maxCount, 1 do
                local entry = inv:GetContainerItem(cid, idx);
                if entry ~= nil and entry.Id ~= nil and entry.Id ~= 0 and entry.Id ~= 65535 then
                    local n = entry.Count;
                    if n == nil or n < 1 then n = 1; end
                    split.total[entry.Id] = (split.total[entry.Id] or 0) + n;
                    if AVAIL_SET[cid] then
                        split.avail[entry.Id] = (split.avail[entry.Id] or 0) + n;
                    end
                    local w = split.where[entry.Id];
                    if w == nil then w = {}; split.where[entry.Id] = w; end
                    w[cid] = (w[cid] or 0) + n;
                    if dec ~= nil then
                        local sig = '';
                        pcall(function() sig = dec.signature(entry.Extra); end);
                        if sig ~= '' then
                            local per = split.aug[entry.Id];
                            if per == nil then per = {}; split.aug[entry.Id] = per; end
                            local e = per[sig];
                            if e == nil then e = { total = 0, avail = 0, where = {} }; per[sig] = e; end
                            e.total = e.total + n;
                            if AVAIL_SET[cid] then e.avail = e.avail + n; end
                            e.where[cid] = (e.where[cid] or 0) + n;
                        end
                    end
                end
            end
        end
    end
    return split;
end

function M.scanAndReport(containers)
    local items = M.scan(containers);
    M.printReport(items);
    return items;
end

-- ---------------------------------------------------------------------------
-- Entry generation (Piece #2): turn an enriched record into a gear.lua entry.
-- Still writes NOTHING -- `/dl preview` prints the generated Lua so you can
-- eyeball key naming and the parsed stat hints against your real gear.
-- ---------------------------------------------------------------------------

-- Name -> table key, matching the existing convention:
--   "Republic Axe +1"  -> RepublicAxe_1    (+N becomes _N)
--   "Warrior's Axe"     -> WarriorsAxe      (apostrophes dropped BEFORE splitting)
--   "Mercenary's knife" -> MercenarysKnife  (each word capitalised)
-- PascalCase every word: "critical hit rate" -> "CriticalHitRate".
local function pascalWords(s)
    local out = '';
    for word in string.gmatch(s, '[%a%d]+') do
        out = out .. word:sub(1, 1):upper() .. word:sub(2);
    end
    return out;
end

local function makeKey(name)
    if name == nil then return nil; end
    local suffix = '';
    local base = name;
    local plus = string.match(base, '%+(%d+)%s*$');
    if plus ~= nil then
        suffix = '_' .. plus;
        base = string.gsub(base, '%+%d+%s*$', '');
    end
    -- Drop apostrophes first so "Warrior's" -> "Warriors" (one word) not Warrior+S.
    base = base:gsub("'", ''):gsub('\xE2\x80\x99', '');
    local key = pascalWords(base);
    if key == '' then key = 'Item'; end
    return key .. suffix;
end
M.makeKey = makeKey;

-- Key suffix for an augment-split record: '_A' + 4 hex digits of the signature
-- (djb2), '_A0' for the pinned-unaugmented copy. A HASH, not an ordinal, so the
-- key -- which set files reference as gear.<Slot>.<Key> -- survives rescans and
-- bag shuffles: the same roll always regenerates the same key. Labels are the
-- wrong input (AUG_NAME edits would orphan every set reference); the raw
-- signature can't move.
local function augHash(sig)
    if sig == nil or sig == '' then return '0'; end
    local h = 5381;
    for i = 1, #sig do h = (h * 33 + sig:byte(i)) % 65536; end
    return string.format('%04X', h);
end
M.augHash = augHash;

-- Control codes seen inside item descriptions (from the fancychat addon).
local DESC_CODES = {
    ['\x81\x60'] = '~',
    ['\xEF\x1F'] = 'Fire',  ['\xEF\x20'] = 'Ice',       ['\xEF\x21'] = 'Wind',
    ['\xEF\x22'] = 'Earth', ['\xEF\x23'] = 'Lightning', ['\xEF\x24'] = 'Water',
    ['\xEF\x25'] = 'Light', ['\xEF\x26'] = 'Dark',
};

-- Escape Lua pattern-magic bytes so a control code whose byte is '%' (0x25) or
-- '$' (0x24) etc. can be used as a literal gsub pattern. Without this, the Light
-- icon '\xEF\x25' ends a pattern with a bare '%' -> "malformed pattern".
local function patEscape(s)
    return (s:gsub('[%(%)%.%%%+%-%*%?%[%]%^%$]', '%%%1'));
end

local function cleanDescription(desc)
    if desc == nil then return nil; end
    local s = desc;
    for code, repl in pairs(DESC_CODES) do
        s = s:gsub(patEscape(code), repl);
    end
    s = s:gsub('[\r\n]', ' ');
    s = s:gsub('[\1-\31\127]', ' ');            -- strip any remaining control bytes
    s = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '');
    return s;
end
M.cleanDescription = cleanDescription;

-- ---------------------------------------------------------------------------
-- Stat aliases -- your vocabulary. Extend as you note more (one at a time).
--   NAME_ALIASES : single token (incl. element names from icons) -> your key.
--   PHRASE_ALIASES: multi-word phrase -> your abbreviation. { pattern, key, fixed? }
--     pattern captures the number; give a fixed value for boolean-ish effects.
--     Ordered: more specific first (PDT/MDT before DT). Matches are consumed.
-- ---------------------------------------------------------------------------
local NAME_ALIASES = {
    -- an element name followed by a number means resistance
    fire  = "FireResistance",      ice   = "IceResistance",   wind  = "WindResistance",
    earth = "EarthResistance",     water = "WaterResistance",  light = "LightResistance",
    lightning = "ThunderResistance",  dark = "DarkResistance",
};

local PHRASE_ALIASES = {
    { "[Mm]agic%s+[Aa]tk%.?%s+[Bb]onus%s*([%+%-]?%d+)",            "MATK" },
    { "[Mm]agical%s+[Dd]amage%s+[Tt]aken%s*([%+%-]?%d+)",          "MDT"  },
    { "[Pp]hysical%s+[Dd]amage%s+[Tt]aken%s*([%+%-]?%d+)",         "PDT"  },
    { "[Dd]amage%s+[Tt]aken%s*([%+%-]?%d+)",                       "DT"   },
    { "MP%s+[Rr]ecovered%s+[Ww]hile%s+[Hh]ealing%s*([%+%-]?%d+)",  "HMP"  },
    { "HP%s+[Rr]ecovered%s+[Ww]hile%s+[Hh]ealing%s*([%+%-]?%d+)",  "HHP"  },
    { "[Ii]mproves%s+[Mm]ining.-[Hh]arvesting%s+[Rr]esults?",      "HELM", 1 },
};

-- Stats where a trailing '%' changes the meaning (flat vs percent are different
-- stats): "HP+2%" -> HPP, "MP+2%" -> MPP. Keyed by lowercased name.
local PERCENT_ALIASES = {
    hp = "HPP", mp = "MPP",
};

-- Known-stat recogniser: the stat names you already use in gear.lua, lowercased
-- -> your exact spelling. Built once from the loaded gear table, so it adapts to
-- YOUR vocabulary. A parsed hint that matches is "recognised", gets normalised to
-- your spelling, and can be emitted live instead of commented.
local _knownStats = nil;
local function knownStats()
    if _knownStats ~= nil then return _knownStats; end
    _knownStats = {};
    for _, obj in pairs(gear.NameToObject) do
        if type(obj) == 'table' and type(obj.Stats) == 'table' then
            for k in pairs(obj.Stats) do
                if type(k) == 'string' then _knownStats[string.lower(k)] = k; end
            end
        end
    end
    return _knownStats;
end

-- When true, hints whose stat name you already use come out live (uncommented);
-- unrecognised names stay commented. Toggle with `/dl autostat on|off`.
M.AutoApproveKnownStats = true;

-- Best-effort: pull "Stat+N" / "Stat-N" / "Stat:N" tokens out of the cleaned
-- description. Names are PascalCased; recognised ones are normalised to your
-- gear.lua spelling and flagged so renderEntry can emit them live. Deliberately
-- loose (<=4 words, deduped) -- the raw cleaned text is always emitted too.
local function parseStatHints(desc, isWeapon)
    local cleaned = cleanDescription(desc);
    if cleaned == nil or cleaned == '' then return {}, nil; end
    local body = cleaned;
    if isWeapon then
        body = body:gsub('^%s*DMG:%s*[%+%-]?%d+%s*', ''):gsub('^%s*Delay:%s*[%+%-]?%d+%s*', '');
    end

    local known = knownStats();
    local hints = {};
    local seen  = {};
    -- Add a hint. Aliased hits force-recognise (you defined the mapping); plain
    -- names are recognised only if already in your gear.lua. Normalise + dedup.
    local function push(key, value, forceReco)
        if key == nil or value == nil then return; end
        local lk = string.lower(key);
        if seen[lk] ~= nil then return; end
        seen[lk] = true;
        local canonical = known[lk];
        table.insert(hints, {
            key = canonical or key,
            value = value,
            recognized = (forceReco == true) or (canonical ~= nil),
        });
    end

    -- 1) multi-word phrase aliases, matched against the whole text and consumed
    --    so the generic tokenizer below can't re-parse the pieces.
    for _, rule in ipairs(PHRASE_ALIASES) do
        body = body:gsub(rule[1], function(cap)
            push(rule[2], rule[3] or tonumber(cap), true);
            return ' ';
        end);
    end

    -- 2) generic "Stat+N" / "Stat:N" tokens on whatever remains. <=4 words keeps
    --    prose out; an element name (Fire/Dark/...) maps to its Resistance key.
    for rawname, sign, num, pct in string.gmatch(body, '([%a][%a%s]-)%s*([%+%-:])%s*(%d+)(%%?)') do
        local nm = rawname:gsub('^%s+', ''):gsub('%s+$', '');
        local pkey = pascalWords(nm);
        local lkey = string.lower(pkey);
        local words = 0;
        for _ in string.gmatch(nm, '%S+') do words = words + 1; end
        if words <= 4 and #pkey > 0 and #pkey <= 24 and lkey ~= 'dmg' and lkey ~= 'delay' then
            local value = tonumber(num);
            if sign == '-' then value = -value; end
            local aliased = NAME_ALIASES[lkey];
            if pct == '%' and PERCENT_ALIASES[lkey] ~= nil then   -- HP+2% -> HPP, MP+2% -> MPP
                aliased = PERCENT_ALIASES[lkey];
            end
            push(aliased or pkey, value, aliased ~= nil);
        end
    end

    return hints, cleaned;   -- cleaned = full ground-truth text for the -- raw: line
end
M.parseStatHints = parseStatHints;

-- 'Grip' for grips/straps, else 'Shield' (record rule, gearrecord; the engine's
-- own mirror stays utils.classifySub -- the seeded state can't require us).
local subTypeFromName = grec.subTypeFromName;

-- Render one record as Lua source for a gear.lua entry. Returns
-- { path = {"Main","Sword"} or {"Head"}, key = "WaxSword_1", lua = "<text>" }.
local function renderEntry(rec)
    local slot = rec.Slot;
    local path;
    if slot == 'Main' or slot == 'Range' then
        -- Main/Range are category-nested in gear.lua. Without a known weapon category
        -- (instruments/fishing rods have no combat skill) we can't place the item
        -- without corrupting the structure -- skip it (caller reports). Ammo is flat.
        if rec.Category == nil then
            return nil, string.format('%s item, unrecognized category (skill=%s)', tostring(slot), tostring(rec.Skill));
        end
        path = { slot, rec.Category };
    elseif slot == nil then
        return nil, 'no equippable slot';
    else
        path = { slot };
    end

    local key = makeKey(rec.FullName or rec.Name);
    if type(rec.AugKey) == 'string' then key = key .. '_A' .. augHash(rec.AugKey); end
    local L = {};
    local function add(s) table.insert(L, s); end

    add(key .. ' = {');
    add(string.format('    Name = %q,', rec.Name or '?'));
    -- Augment-split records (see M.scan): AugKey is the pin the native engine
    -- exact-matches at equip time (equipcore.checkAugments; '' = must be the
    -- unaugmented copy), AugText the human reading the GUI shows. Both are
    -- machine-stamped, like RSlot.
    if type(rec.AugKey) == 'string' then
        add(string.format('    AugKey = %q,', rec.AugKey));
        if type(rec.AugText) == 'string' and rec.AugText ~= '' then
            add(string.format('    AugText = %q,', rec.AugText));
        end
    end
    add(string.format('    Level = %s,', tostring(rec.Level or 0)));
    add(string.format('    Id = %d,', rec.Id or 0));
    local jobList = decodeJobs(rec.Jobs);
    if jobList ~= nil then
        local q = {};
        for _, j in ipairs(jobList) do table.insert(q, string.format('%q', j)); end
        add('    Jobs = {' .. table.concat(q, ', ') .. '},');
    end
    if (slot == 'Main' or slot == 'Range') and rec.Category ~= nil then
        add(string.format('    Type = %q,', rec.Category));
        if slot == 'Main' and rec.IsWeapon then   -- OneHanded only matters for main/sub pairing
            add(string.format('    OneHanded = %s,', tostring(rec.OneHanded == true)));
            -- Count >= 2 is the same-weapon dual-wield fact (subSlotAllowed's
            -- same-name check; the LAC state has no bag scanner, so the file
            -- carries it). Replaces the legacy InBothHands flag. A single copy
            -- is the default assumption -- not emitted, gear.lua stays thin.
            if (tonumber(rec.Count) or 0) >= 2 then
                add(string.format('    Count = %d,', rec.Count));
            end
        end
    elseif slot == 'Sub' then
        -- The pairing rule needs grip-vs-shield; stamp the unambiguous label
        -- (the catalog calls both "Sub").
        add(string.format('    Type = %q,', subTypeFromName(rec.Name)));
    end
    -- Reserved slots (server rslot): the equip-time engine drops these from a
    -- resolved set, and it reads RAW gear.lua with no catalog to consult -- so the
    -- fact has to live in the file, like Type / OneHanded / Count. Only ~390 items
    -- in the game reserve anything; everything else omits the field.
    if (tonumber(rec.RSlot) or 0) ~= 0 then
        add(string.format('    RSlot = %d,', rec.RSlot));
    end
    -- Range/Ammo pairing key (server item_weapon skill:subskill). Same disk-or-nothing
    -- reason as RSlot: the engine decides Ammo from the raw file. Only Range and Ammo
    -- items carry one; every other slot omits the field.
    if type(rec.Pair) == 'string' and rec.Pair ~= '' then
        add(string.format('    Pair = %q,', rec.Pair));
    end

    -- No Stats block on purpose (Phase 2): item stats -- including weapon DMG/Delay -- come
    -- from the global catalog (catalog.lua) by Id, which carries them for every item. gear.lua
    -- stays a thin ownership record; the GUI and optimizer derive stats at load (buildOwned
    -- merges the catalog in), so nothing is re-parsed per user.
    add('}');

    return { path = path, key = key, lua = table.concat(L, '\n') };
end
M.renderEntry = renderEntry;
M.effectiveRSlot = effectiveRSlot;   -- exported for the trinket-RSlot tests
-- The reserved-slot mask BY ID, catalog-sourced, with the ADR 0010 completion
-- already applied -- i.e. the exact value the scan stamps into gear.lua. The GUI
-- reads it through here rather than off an owned record on purpose: a gear.lua
-- written before v43 carries no RSlot at all, and reading that would show a
-- Vermillion Cloak as harmless right up until the engine drops the Head anyway.
M.rslotFor = rslotFor;
-- The Range/Ammo pair key BY ID, catalog-sourced -- rslotFor's twin, exported
-- for the same reason (v159): the GUI must judge a pair the way the engine
-- does, and a gear.lua written before v128 carries no Pair at all. Reading the
-- owned record would show a bolt and a bow as a fine couple right up until the
-- server strips one of them.
M.pairFor = pairFor;

-- Preview: scan, then print the generated entry for each NEW item. Read-only.
function M.preview(containers)
    local items = M.scan(containers);
    local newItems = {};
    for _, it in ipairs(items) do
        if not it.Known then table.insert(newItems, it); end
    end
    table.sort(newItems, function(a, b)
        local pa = (a.Slot or '') .. '/' .. (a.Category or '');
        local pb = (b.Slot or '') .. '/' .. (b.Category or '');
        if pa ~= pb then return pa < pb; end
        return tostring(a.Name) < tostring(b.Name);
    end);

    print(string.format('[dlac] preview: %d new item(s) would be generated (nothing is written):', #newItems));
    for _, it in ipairs(newItems) do
        local ok, entry, reason = pcall(renderEntry, it);
        if ok and entry ~= nil then
            print(string.format('  -- gear.%s', table.concat(entry.path, '.')));
            for line in string.gmatch(entry.lua, '[^\n]+') do
                print('  ' .. line);
            end
        elseif ok then
            print(string.format('  -- skipped %s: %s', tostring(it.Name), tostring(reason)));
        else
            print(string.format('  -- FAILED to render %s: %s', tostring(it.Name), tostring(entry)));
        end
    end
end

-- ---------------------------------------------------------------------------
-- Staging (Piece #3): group rendered entries into a gear-shaped module, write it
-- next to your profile, and load-check it. Still does NOT touch gear.lua.
-- ---------------------------------------------------------------------------

-- Prepend `pad` to every line of a (multi-line) string.
local function indentLines(text, pad)
    return pad .. text:gsub('\n', '\n' .. pad);
end

-- Player name + server id: LuaAshitacast's gState when loaded inside a profile, else the
-- party manager (dlac addon context, where gState doesn't exist). Returns name, id | nil.
local function pNameId()
    if gState ~= nil and gState.PlayerName ~= nil and gState.PlayerId ~= nil then
        return gState.PlayerName, gState.PlayerId;
    end
    local name, id;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        name = party:GetMemberName(0);
        id   = party:GetMemberServerId(0);
        if name == '' then name = nil; end
    end);
    return name, id;
end

-- The dlac data home (mode-aware -- feature/native-engine): profiles.dataDir()
-- with the legacy composition as fallback.
local function dataDir()
    local d = nil;
    pcall(function()
        local prof = require('dlac\\profiles');
        d = prof.dataDir();
    end);
    return d;   -- native home or nil (purge Phase 4: no legacy fallback composition)
end

-- Absolute path to the staging file, in the dlac data home next to gear.lua.
local function stagingPath()
    local d = dataDir();
    return d and (d .. 'gear_staging.lua') or nil;
end
M.stagingPath = stagingPath;

-- Build the staging module source from a list of records. Armor groups by slot,
-- weapons by slot+category; key collisions are disambiguated with the Id.
function M.serializeStaging(items)
    local nested, flat, skipped = {}, {}, {};
    for _, it in ipairs(items) do
        local ok, entry, reason = pcall(renderEntry, it);
        if not ok then
            table.insert(skipped, { name = it.Name, reason = tostring(entry) });
        elseif entry == nil then
            table.insert(skipped, { name = it.Name, reason = reason or 'skipped' });
        else
            local rec = { key = entry.key, lua = entry.lua, id = it.Id };
            if #entry.path == 2 then
                nested[entry.path[1]] = nested[entry.path[1]] or {};
                nested[entry.path[1]][entry.path[2]] = nested[entry.path[1]][entry.path[2]] or {};
                table.insert(nested[entry.path[1]][entry.path[2]], rec);
            else
                flat[entry.path[1]] = flat[entry.path[1]] or {};
                table.insert(flat[entry.path[1]], rec);
            end
        end
    end

    local function emit(entries, pad, out)
        local used = {};
        for _, e in ipairs(entries) do
            local key = e.key;
            if used[key] then key = e.key .. '_' .. tostring(e.id or 0); end  -- collision -> Id suffix
            used[key] = true;
            local lua = (key == e.key) and e.lua or (key .. e.lua:sub(#e.key + 1));
            table.insert(out, indentLines(lua, pad) .. ',');
        end
    end

    local L = { 'return {' };
    for slot, cats in pairs(nested) do
        table.insert(L, '    ' .. slot .. ' = {');
        for cat, entries in pairs(cats) do
            table.insert(L, '        ' .. cat .. ' = {');
            emit(entries, '            ', L);
            table.insert(L, '        },');
        end
        table.insert(L, '    },');
    end
    for slot, entries in pairs(flat) do
        table.insert(L, '    ' .. slot .. ' = {');
        emit(entries, '        ', L);
        table.insert(L, '    },');
    end
    table.insert(L, '}');
    return table.concat(L, '\n') .. '\n', skipped;
end

-- Scan, generate, write the staging file, and load-check it.
-- One "could not index" line per item name per Lua state (see M.stage).
local _skipWarned = {};
function M._resetSkipWarned() _skipWarned = {}; end   -- test seam

-- quiet: suppress the informational narration (the AUTO-sync path uses this --
-- it is release behavior, not a debugging pipeline). Errors always print, and
-- so does anything the scan could not index.
function M.stage(containers, quiet)
    local items = M.scan(containers);
    local newItems = {};
    for _, it in ipairs(items) do
        if not it.Known then table.insert(newItems, it); end
    end
    if #newItems == 0 then
        if not quiet then print('[dlac] stage: nothing new -- everything scanned is already in gear.lua.'); end
        return;
    end

    local path = stagingPath();
    if path == nil then
        print('[dlac] stage: could not resolve the profile path (are you logged in?).');
        return;
    end

    local body, skipped = M.serializeStaging(newItems);

    local f, ferr = io.open(path, 'w');
    if f == nil then
        print('[dlac] stage: could not open staging file: ' .. tostring(ferr));
        return;
    end
    f:write(body);
    f:close();

    -- load-check the file we just wrote: it must parse AND return a table.
    local status = 'OK';
    local chunk, lerr = loadfile(path);
    if chunk == nil then
        status = 'FAILED to parse: ' .. tostring(lerr);
    else
        local okrun, result = pcall(chunk);
        if not okrun then status = 'errored on load: ' .. tostring(result);
        elseif type(result) ~= 'table' then status = 'did not return a table'; end
    end

    local staged = #newItems - #skipped;
    if not quiet or status ~= 'OK' then   -- a failed load-check must surface even on auto-sync
        print(string.format('[dlac] staged %d new item(s) -> gear_staging.lua  [load-check: %s]', staged, status));
    end
    -- A SKIPPED ITEM MUST SAY SO, auto-sync included (2026-08-03). These lines
    -- used to be gated on `not quiet`, and M.sync stages quiet -- so on the one
    -- path every player actually runs, an item dlac could not index vanished
    -- with no error anywhere. `/dl scan` even LISTS it (the skip happens later,
    -- at serialize time), so it read as found and then never landed. That is
    -- how the all-jobs Animator stayed missing until somebody's friend
    -- mentioned it in passing.
    --
    -- Once per name per state, because a skipped item is never Known and so
    -- comes back on EVERY scan: the periodic sync would otherwise turn an
    -- honest warning into a spam loop, which is the same silence by another
    -- route.
    for _, s in ipairs(skipped) do
        local seen = string.lower(tostring(s.name));
        if not _skipWarned[seen] then
            _skipWarned[seen] = true;
            print(string.format('[dlac] could not index "%s": %s -- it will not appear in dlac.',
                tostring(s.name), tostring(s.reason)));
        end
    end
    if not quiet then
        if status == 'OK' then
            print('[dlac] review gear_staging.lua by your profile, then (soon) /dl commit will merge it.');
        end
    end
end

-- ---------------------------------------------------------------------------
-- Commit (Piece #5): merge gear_staging.lua into gear.lua. Splices from the
-- staging TEXT (so your comments/edits survive) as the first child of each
-- slot/category section -- existing entries are never touched. Backup first,
-- write atomically, re-validate, and auto-restore on any failure.
-- ---------------------------------------------------------------------------

local WEAPON_SLOTS = { Main = true, Range = true };   -- category-nested slots (Ammo is flat)

local function toLines(text)
    local lines = {};
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do lines[#lines + 1] = line; end
    if #lines > 0 and lines[#lines] == '' then lines[#lines] = nil; end   -- drop split artifact
    return lines;
end

-- Header/closer matchers tolerant of a trailing "-- comment". Hand-annotated
-- legacy entries (`MtlMufflers = { -- Mtl. Mufflers/Mythril Mufflers`) must be
-- visible here, or prune/fix/dedupe silently skip them. Anything else after
-- the brace (e.g. an inline table) still disqualifies the line.
--
-- The COMMIT readers (parseStaging / indexGear / slotShapes) share these on
-- purpose. They used to carry their own `= {%s*$` patterns, which meant a
-- commented category header was invisible to indexGear alone: commit then
-- "created" a section that already existed, Lua's last-key-wins threw the new
-- block away, and it reported success while the items silently never landed --
-- so they scanned as new again on the next sync, forever.
local function restOk(rest) return rest:match('^%s*$') ~= nil or rest:match('^%s*%-%-') ~= nil; end
local function hdrAt(line, nsp)
    local key, rest = line:match('^' .. string.rep(' ', nsp) .. '([%w_]+) = {(.*)$');
    if key ~= nil and restOk(rest) then return key; end
    return nil;
end
local function closeAt(line, nsp)
    local rest = line:match('^' .. string.rep(' ', nsp) .. '},(.*)$');
    return rest ~= nil and restOk(rest);
end

-- Parse a staging module's TEXT into { targetKey -> { entryBlock, ... } } where
-- targetKey is "Head" (armor) or "Main.Sword" (weapon). Entry blocks are verbatim
-- source (comments preserved), already at gear.lua's indentation.
local function parseStaging(text)
    local lines = toLines(text);
    local sections, curSlot, curCat = {}, nil, nil;
    local i = 1;
    while i <= #lines do
        local line = lines[i];
        local slotOpen = hdrAt(line, 4);
        local slotClose = closeAt(line, 4);
        local h8 = hdrAt(line, 8);
        local c8 = closeAt(line, 8);
        local h12 = hdrAt(line, 12);
        if slotOpen then curSlot = slotOpen; curCat = nil; i = i + 1;
        elseif slotClose then curSlot = nil; curCat = nil; i = i + 1;
        elseif h8 and curSlot and WEAPON_SLOTS[curSlot] then curCat = h8; i = i + 1;
        elseif c8 and curSlot and WEAPON_SLOTS[curSlot] then curCat = nil; i = i + 1;
        elseif h8 and curSlot then                       -- armor entry (8-space)
            local block = { line }; i = i + 1;
            while i <= #lines and not closeAt(lines[i], 8) do block[#block + 1] = lines[i]; i = i + 1; end
            if i <= #lines then block[#block + 1] = lines[i]; i = i + 1; end
            sections[curSlot] = sections[curSlot] or {}; table.insert(sections[curSlot], table.concat(block, '\n'));
        elseif h12 and curSlot and curCat then           -- weapon entry (12-space)
            local key = curSlot .. '.' .. curCat; local block = { line }; i = i + 1;
            while i <= #lines and not closeAt(lines[i], 12) do block[#block + 1] = lines[i]; i = i + 1; end
            if i <= #lines then block[#block + 1] = lines[i]; i = i + 1; end
            sections[key] = sections[key] or {}; table.insert(sections[key], table.concat(block, '\n'));
        else i = i + 1;
        end
    end
    return sections;
end

-- Map gear.lua's section headers to line numbers: "Head" -> line of `    Head = {`,
-- "Main.Sword" -> line of `        Sword = {` under Main.
local function indexGear(lines)
    local idx, curSlot = {}, nil;
    for i = 1, #lines do
        local s4 = hdrAt(lines[i], 4);
        local s8 = hdrAt(lines[i], 8);
        if s4 then curSlot = s4; if idx[s4] == nil then idx[s4] = i; end
        elseif s8 and curSlot and WEAPON_SLOTS[curSlot] then
            local k = curSlot .. '.' .. s8; if idx[k] == nil then idx[k] = i; end
        end
    end
    return idx;
end

-- How is each slot section actually written in THIS file -- flat entries, or
-- category tables?  An 8-space child that carries its own `Name = "..."` (at
-- 12) is an ENTRY; one that only holds deeper tables is a CATEGORY.
--
-- Commit cannot assume its own layout here. gear.lua's trailer decides per file
-- which slots it walks three levels deep, and a legacy LuAshitacast file nests
-- Ammo by Archery/Marksmanship/Throwing where dlac writes it flat. Splicing a
-- flat entry into a category-nested slot leaves that entry as a sibling of the
-- category tables -- the file still PARSES, so parse-checking sees nothing, but
-- the trailer then descends into the entry's own fields and evaluates
-- ("Bone Arrow").Name -> nil -> "table index is nil", pointing at the trailer
-- hundreds of lines from the cause. So: read the shape, never assume it.
-- Returns { [slot] = 'entry' | 'category' }; a slot with no children is absent.
local function slotShapes(lines)
    local shapes, curSlot, i = {}, nil, 1;
    while i <= #lines do
        local s4, h8 = hdrAt(lines[i], 4), hdrAt(lines[i], 8);
        if s4 then curSlot = s4; i = i + 1;
        elseif closeAt(lines[i], 4) then curSlot = nil; i = i + 1;
        elseif h8 and curSlot then
            local named, j = false, i + 1;
            while j <= #lines and not closeAt(lines[j], 8) do
                if lines[j]:match('^            Name%s*=') then named = true; end
                j = j + 1;
            end
            if shapes[curSlot] == nil then shapes[curSlot] = named and 'entry' or 'category'; end
            i = j + 1;
        else i = i + 1;
        end
    end
    return shapes;
end
M._slotShapes = slotShapes;   -- exported for the tests

-- Pure text transform: return gear.lua text with staging entries spliced in as
-- first children. Never modifies existing lines. Reports counts / created / notfound.
function M.spliceStaging(gearText, stagingText)
    local sections = parseStaging(stagingText);
    local gearLines = toLines(gearText);
    local idx = indexGear(gearLines);
    local shapes = slotShapes(gearLines);
    local insertAfter, report = {}, { inserted = 0, created = {}, notfound = {}, shapeConflict = {} };

    local function queue(ln, block) insertAfter[ln] = insertAfter[ln] or {}; table.insert(insertAfter[ln], block); end

    for targetKey, blocks in pairs(sections) do
        local parent, cat = targetKey:match('^([%w_]+)%.([%w_]+)$');
        local slot = parent or targetKey;
        -- What this staging block needs the slot to be, vs what the file IS.
        -- A disagreement is never splice-able: inserting anyway writes a file
        -- that parses and then dies in the trailer (see slotShapes).
        local want = (cat ~= nil) and 'category' or 'entry';
        if shapes[slot] ~= nil and shapes[slot] ~= want then
            table.insert(report.shapeConflict, { slot = slot, found = shapes[slot], want = want });
        else
            local ln = idx[targetKey];
            if ln ~= nil then
                for _, b in ipairs(blocks) do queue(ln, b); report.inserted = report.inserted + 1; end
            elseif parent and idx[parent] then            -- create missing weapon category
                local nc = { '        ' .. cat .. ' = {' };
                for _, b in ipairs(blocks) do nc[#nc + 1] = b; report.inserted = report.inserted + 1; end
                nc[#nc + 1] = '        },';
                queue(idx[parent], table.concat(nc, '\n'));
                table.insert(report.created, targetKey);
            else
                table.insert(report.notfound, targetKey);
            end
        end
    end
    table.sort(report.shapeConflict, function(a, b) return a.slot < b.slot; end);

    local out = {};
    for i = 1, #gearLines do
        out[#out + 1] = gearLines[i];
        if insertAfter[i] then for _, b in ipairs(insertAfter[i]) do out[#out + 1] = b; end end
    end
    return table.concat(out, '\n') .. '\n', report;
end

local function gearPath()
    local d = dataDir();
    return d and (d .. 'gear.lua') or nil;
end

local function readFile(p) local f = io.open(p, 'r'); if f == nil then return nil; end local t = f:read('*a'); f:close(); return t; end
local function writeFile(p, t) local f = io.open(p, 'w'); if f == nil then return false; end f:write(t); f:close(); return true; end
local function parses(text) local c = (loadstring or load)(text); return c ~= nil; end

local function charBackupDir()
    -- backups follow the active storage home (feature/native-engine)
    local r = nil;
    pcall(function()
        local prof = require('dlac\\profiles');
        r = prof.charRoot();
    end);
    return (r ~= nil) and (r .. 'backups\\') or nil;   -- purge Phase 4: no legacy fallback
end

-- safewrite validator for gear.lua: RUN the candidate file in a sandbox (env
-- falls through to _G for reads, captures gear/NameToObject writes). Catches
-- runtime errors a parse-only check misses -- e.g. a mis-shaped entry making
-- NameToObject[nil] blow up. Shared by commit and /dl fix (it used to live in
-- both, and only one copy would have gotten a future fix).
-- Why won't this gear table load?  Every gear.lua ends with the same trailer --
-- NameToObject[gearVars.Name] = gearVars -- walked at whatever depth that file
-- declares per slot, so ONE mis-shaped entry takes the whole inventory down and
-- the raw error only ever names the trailer, hundreds of lines from the cause.
-- Walk the built table and name the culprit instead.
--
-- Deliberately shape-AGNOSTIC: a file may legitimately nest a slot we write
-- flat (Ammo, in LAC-era files), and that is its trailer's business, not ours.
-- What is broken under ANY trailer is a slot that MIXES entries with category
-- tables, a child that is neither, or an entry with no Name.
function M.gearProblems(gearT, lines)
    local out = {};
    local function lineOf(key)
        if lines == nil or type(key) ~= 'string' or key:match('^[%a_][%w_]*$') == nil then return nil; end
        for i = 1, #lines do if lines[i]:match('^%s*' .. key .. ' = {') then return i; end end
        return nil;
    end
    local function at(key) local l = lineOf(key); return (l ~= nil) and (' (line ' .. l .. ')') or ''; end
    -- A table with no Name that HOLDS named tables is a category, not a broken
    -- entry. Structural, not a head-count: one new entry beside three categories
    -- and thirty beside three must both read the same way round.
    local function isCategory(v)
        for _, c in pairs(v) do if type(c) == 'table' and c.Name ~= nil then return true; end end
        return false;
    end

    for slot, sv in pairs(gearT) do
        if slot ~= 'NameToObject' and type(sv) == 'table' then
            local entries, cats, loose, empty = {}, {}, {}, {};
            for k, v in pairs(sv) do
                if type(v) ~= 'table' then loose[#loose + 1] = k;
                elseif v.Name ~= nil then entries[#entries + 1] = k;
                elseif isCategory(v) then cats[#cats + 1] = k;
                elseif next(v) == nil then empty[#empty + 1] = k;
                else loose[#loose + 1] = k; end
            end
            table.sort(entries); table.sort(cats); table.sort(loose); table.sort(empty);
            if #loose > 0 then
                out[#out + 1] = string.format('gear.%s.%s has no Name%s', slot, loose[1],
                                              at(loose[1])) .. ((#loose > 1) and (' (+%d more)'):format(#loose - 1) or '');
            end
            if #cats > 0 and #entries > 0 then
                out[#out + 1] = string.format(
                    'gear.%s is category-nested (%s) but %s sits directly under it%s -- wrong depth',
                    slot, table.concat(cats, ', '), entries[1], at(entries[1]))
                    .. ((#entries > 1) and (' (+%d more)'):format(#entries - 1) or '');
            elseif #cats == 0 and #empty > 0 then
                out[#out + 1] = string.format('gear.%s.%s is an empty table, not an entry%s',
                                              slot, empty[1], at(empty[1]));
            end
        elseif slot ~= 'NameToObject' then
            out[#out + 1] = string.format('gear.%s is a %s, not a table', slot, type(sv));
        end
    end
    table.sort(out);
    return out;
end

local function gearLoadValidator(chunk, tmpPath)
    local env = setmetatable({}, { __index = _G });
    if setfenv ~= nil then setfenv(chunk, env); end
    local runok, runerr = pcall(chunk);
    if runok and type(env.gear) == 'table' then return true; end
    -- gear = {...} is built BEFORE the trailer runs, so even a trailer blow-up
    -- leaves the table right there to be inspected.
    if type(env.gear) == 'table' then
        local text = readFile(tmpPath);
        local probs = M.gearProblems(env.gear, text ~= nil and toLines(text) or nil);
        if #probs > 0 then
            return nil, tostring(runerr) .. ' -- ' .. table.concat(probs, '; ');
        end
    end
    return nil, runerr;
end

-- quiet: only the success narration is suppressed (auto-sync); every abort/failure
-- prints regardless -- a user must never lose data silently.
function M.commit(quiet)
    local gpath, spath = gearPath(), stagingPath();
    if gpath == nil then print('[dlac] commit: profile path unavailable (are you logged in?).'); return; end

    local stagingText = readFile(spath);
    if stagingText == nil or stagingText:match('^%s*$') or stagingText:match('^%s*return%s*{%s*}%s*$') then
        if not quiet then print('[dlac] commit: staging is empty -- run /dl stage first.'); end
        return;
    end
    if not parses(stagingText) then print('[dlac] commit: staging file does not parse; aborting.'); return; end

    local gearText = readFile(gpath);
    if gearText == nil then print('[dlac] commit: cannot read gear.lua.'); return; end

    local newText, report = M.spliceStaging(gearText, stagingText);
    -- Shape first: this one is about the FILE, not about any one item, and the
    -- remedy is different (reshape or rebuild, not "why is this item missing").
    if #report.shapeConflict > 0 then
        local parts = {};
        for _, c in ipairs(report.shapeConflict) do
            parts[#parts + 1] = string.format('%s is %s here, dlac writes it %s', c.slot,
                (c.found == 'category') and 'nested by category' or 'flat',
                (c.want == 'entry') and 'flat' or 'nested by category');
        end
        print('[dlac] commit ABORTED: gear.lua shape conflict -- ' .. table.concat(parts, '; ') .. '.');
        print('[dlac] nothing written. Delete gear.lua and let /dl scan rebuild it, or reshape that section by hand.');
        return;
    end
    if #report.notfound > 0 then
        print('[dlac] commit: no gear.lua section for: ' .. table.concat(report.notfound, ', ') .. '. Aborting, nothing written.'); return;
    end
    if report.inserted == 0 then print('[dlac] commit: nothing to insert.'); return; end
    if not parses(newText) then print('[dlac] commit ABORTED: spliced result would not parse. gear.lua untouched.'); return; end

    -- backup, then the shared atomic replace (lib\safewrite): tmp -> parse ->
    -- sandbox-run validate -> swap -> post-check, restore on any late failure.
    local backupPath = sw.timestampBackup(charBackupDir(), 'gear_', gearText);
    if backupPath == nil then print('[dlac] commit ABORTED: could not write backup. gear.lua untouched.'); return; end
    local wok, werr = sw.replaceLua(gpath, newText, { origText = gearText, validate = gearLoadValidator });
    if not wok then
        print('[dlac] commit ABORTED: ' .. tostring(werr) .. '. backup: ' .. backupPath);
        return;
    end

    writeFile(spath, 'return {}\n');   -- clear staging so it can't commit twice

    if not quiet then
        local extra = (#report.created > 0) and (' (new sections: ' .. table.concat(report.created, ', ') .. ')') or '';
        print(string.format('[dlac] committed %d entr%s into gear.lua%s.', report.inserted, (report.inserted == 1 and 'y' or 'ies'), extra));
        print('[dlac] backup: ' .. backupPath .. '  --  run /dl r to load.');
    end
end

-- ---------------------------------------------------------------------------
-- Reconcile (`/dl fix`): trust the game resource over human-entered data. For
-- each owned item that matches an existing entry, correct Name -> the real short
-- equip name, Level -> resource level, and stamp a missing Id. Key mismatches and
-- duplicate entries are REPORTED, not changed (renaming keys would break job-file
-- refs; duplicates need a human decision). Backup + sandbox-validated like commit.
-- ---------------------------------------------------------------------------

-- Parse gear.lua text into a flat list of entries with line positions and the
-- parsed Name/Level/Id (+ the line each lives on, for surgical edits).
-- (hdrAt / closeAt live up by toLines -- the commit-side readers need them too.)

local function parseGearEntries(lines)
    local entries = {};
    local function scanEntry(startIdx, indent)
        local e = { startLine = startIdx, indent = indent };
        local j = startIdx + 1;
        while j <= #lines and not closeAt(lines[j], indent) do
            local L = lines[j];
            if e.Name == nil then local v = L:match('^%s+Name = "([^"]*)"'); if v then e.Name = v; e.NameLine = j; end end
            if e.Level == nil then local v = L:match('^%s+Level = (%-?%d+)'); if v then e.Level = tonumber(v); e.LevelLine = j; end end
            if e.Id == nil then local v = L:match('^%s+Id = (%d+)'); if v then e.Id = tonumber(v); e.IdLine = j; end end
            if e.Type == nil then local v = L:match('^%s+Type = "([^"]*)"'); if v then e.Type = v; e.TypeLine = j; end end
            if e.OneHanded == nil then local v = L:match('^%s+OneHanded = (%a+)'); if v then e.OneHanded = (v == 'true'); e.OneHandedLine = j; end end
            if e.RSlot == nil then local v = L:match('^%s+RSlot = (%d+)'); if v then e.RSlot = tonumber(v); e.RSlotLine = j; end end
            if e.Pair == nil then local v = L:match('^%s+Pair = "([^"]*)"'); if v then e.Pair = v; e.PairLine = j; end end
            j = j + 1;
        end
        e.endLine = j;
        return e, j + 1;
    end
    local curSlot, curCat, i = nil, nil, 1;
    while i <= #lines do
        local line = lines[i];
        local s4  = hdrAt(line, 4);
        local sc  = closeAt(line, 4);
        local h8  = hdrAt(line, 8);
        local c8  = closeAt(line, 8);
        local h12 = hdrAt(line, 12);
        if s4 then curSlot = s4; curCat = nil; i = i + 1;
        elseif sc then curSlot = nil; curCat = nil; i = i + 1;
        elseif h8 and curSlot and WEAPON_SLOTS[curSlot] then curCat = h8; i = i + 1;
        elseif c8 and curSlot and WEAPON_SLOTS[curSlot] then curCat = nil; i = i + 1;
        elseif h8 and curSlot then
            local e; e, i = scanEntry(i, 8); e.key = h8; e.parent = curSlot; table.insert(entries, e);
        elseif h12 and curSlot and curCat then
            local e; e, i = scanEntry(i, 12); e.key = h12; e.parent = curSlot .. '.' .. curCat; table.insert(entries, e);
        else i = i + 1;
        end
    end
    return entries;
end

-- Pure reconcile: gear.lua text + owned items -> corrected text + report.
-- metaById (optional): Id -> catalog record, for the pairing-metadata backfill.
function M.computeFixes(gearText, ownedItems, metaById)
    local lines = toLines(gearText);
    local entries = parseGearEntries(lines);

    local byKey, byName, keyN, nameN = {}, {}, {}, {};
    for _, e in ipairs(entries) do
        local lk = string.lower(e.key);
        byKey[lk] = byKey[lk] or {}; table.insert(byKey[lk], e); keyN[lk] = (keyN[lk] or 0) + 1;
        if e.Name then local ln = string.lower(e.Name);
            byName[ln] = byName[ln] or {}; table.insert(byName[ln], e); nameN[ln] = (nameN[ln] or 0) + 1; end
    end

    local report = { fixed = {}, keyMismatch = {}, duplicates = {}, matched = 0, unmatched = 0 };
    local dseen = {};
    for _, e in ipairs(entries) do
        local lk = string.lower(e.key);
        if keyN[lk] > 1 and not dseen['k'..lk] then dseen['k'..lk] = true;
            table.insert(report.duplicates, string.format('key "%s" x%d', e.key, keyN[lk])); end
        if e.Name then local ln = string.lower(e.Name);
            if nameN[ln] > 1 and not dseen['n'..ln] then dseen['n'..ln] = true;
                table.insert(report.duplicates, string.format('name "%s" x%d', e.Name, nameN[ln])); end end
    end

    local replace, insertAfter, removeLine = {}, {}, {};
    for _, item in ipairs(ownedItems) do
        local itemKey = makeKey(item.FullName or item.Name);
        local cand, seen = {}, {};
        local function add(list) if list then for _, e in ipairs(list) do if not seen[e] then seen[e] = true; cand[#cand+1] = e; end end end end
        if itemKey then add(byKey[string.lower(itemKey)]); end
        if item.Name then add(byName[string.lower(item.Name)]); end
        if item.FullName then add(byName[string.lower(item.FullName)]); end

        if #cand == 0 then report.unmatched = report.unmatched + 1;
        elseif #cand > 1 then report.matched = report.matched + 1;   -- ambiguous -> in duplicates
        else
            report.matched = report.matched + 1;
            local e = cand[1];
            if item.Name and e.Name ~= item.Name and e.NameLine then
                local q = string.format('%q', item.Name);
                replace[e.NameLine] = lines[e.NameLine]:gsub('"[^"]*"', function() return q; end, 1);
                report.fixed[#report.fixed+1] = string.format('%s: Name "%s" -> "%s"', e.key, tostring(e.Name), item.Name);
            end
            if item.Level and e.Level ~= item.Level and e.LevelLine then
                replace[e.LevelLine] = lines[e.LevelLine]:gsub('Level = %-?%d+', 'Level = ' .. tostring(item.Level), 1);
                report.fixed[#report.fixed+1] = string.format('%s: Level %s -> %s', e.key, tostring(e.Level), tostring(item.Level));
            end
            if item.Id and e.Id == nil then
                local anchor = e.LevelLine or e.NameLine or e.startLine;
                insertAfter[anchor] = insertAfter[anchor] or {};
                insertAfter[anchor][#insertAfter[anchor]+1] = string.rep(' ', e.indent + 4) .. 'Id = ' .. tostring(item.Id) .. ',';
                report.fixed[#report.fixed+1] = string.format('%s: +Id %s', e.key, tostring(item.Id));
            end
            if itemKey and string.lower(e.key) ~= string.lower(itemKey) then
                report.keyMismatch[#report.keyMismatch+1] = string.format('"%s" should be "%s" (%s)', e.key, itemKey, item.Name or item.FullName or '?');
            end
        end
    end

    -- Pairing-metadata backfill. The equip-time engine reads RAW gear.lua (no GUI
    -- catalog enrichment), so the Sub pairing rule needs Type / OneHanded stamped
    -- into the file: weapons get their catalog Type + OneHanded; Sub items get the
    -- unambiguous legacy label (Shield / Grip -- the catalog calls both "Sub").
    if metaById ~= nil then
        for _, e in ipairs(entries) do
            local c = (e.Id ~= nil) and metaById[e.Id] or nil;
            if c ~= nil then
                local anchor = e.IdLine or e.LevelLine or e.NameLine or e.startLine;
                local pad = string.rep(' ', e.indent + 4);
                local function ins(line, note)
                    insertAfter[anchor] = insertAfter[anchor] or {};
                    insertAfter[anchor][#insertAfter[anchor] + 1] = pad .. line;
                    report.fixed[#report.fixed + 1] = string.format('%s: %s', e.key, note);
                end
                local isMain  = e.parent ~= nil and e.parent:find('Main.', 1, true) == 1;
                local isRange = e.parent ~= nil and e.parent:find('Range.', 1, true) == 1;
                if (isMain or isRange) and e.Type == nil and c.Type ~= nil then
                    ins(string.format('Type = %q,', c.Type), string.format('+Type %q', c.Type));
                end
                -- OneHanded rides through the record rule (healOneHanded):
                -- the catalog says true for H2H (apicrawl ONE-set bug, fixed
                -- locally 2026-07-22) and this very backfill propagated the
                -- lie into files -- H2H pins false, and the stamp is
                -- machine-owned BOTH ways like RSlot below: a wrong stamped
                -- value is corrected in place. Readers key on Type, so an
                -- uncorrected stamp was already inert; this keeps the FILES
                -- truthful too.
                if isMain and c.OneHanded ~= nil then
                    local oh = grec.healOneHanded(e.Type or c.Type, c.OneHanded) == true;
                    if e.OneHanded == nil then
                        ins('OneHanded = ' .. tostring(oh) .. ',', '+OneHanded ' .. tostring(oh));
                    elseif e.OneHanded ~= oh and e.OneHandedLine ~= nil then
                        replace[e.OneHandedLine] = lines[e.OneHandedLine]:gsub('OneHanded = %a+', 'OneHanded = ' .. tostring(oh), 1);
                        report.fixed[#report.fixed + 1] = string.format('%s: OneHanded %s -> %s', e.key, tostring(e.OneHanded), tostring(oh));
                    end
                end
                if e.parent == 'Sub' and e.Type == nil then
                    local t = subTypeFromName(e.Name);
                    ins(string.format('Type = %q,', t), string.format('+Type %q', t));
                end
                -- Reserved slots -- any slot, not just the weapon pair. Every gear.lua
                -- written before RSlot existed lacks it, and the engine cannot see the
                -- catalog, so this backfill is what makes an old file conflict-aware.
                -- The stamp is machine-owned BOTH ways: when the record rule retracts
                -- a reservation (the Automaton Oils, wrongly completed to the Range
                -- bit until 2026.07.22g -- the engine kept displacing a manually
                -- equipped oil), fix removes or corrects the stale line too.
                local effRS = tonumber(effectiveRSlot(c)) or 0;
                if e.RSlot == nil and effRS ~= 0 then
                    ins(string.format('RSlot = %d,', effRS), string.format('+RSlot %d', effRS));
                elseif e.RSlot ~= nil and e.RSlotLine ~= nil and effRS == 0 then
                    removeLine[e.RSlotLine] = true;
                    report.fixed[#report.fixed + 1] = string.format('%s: -RSlot %d', e.key, e.RSlot);
                elseif e.RSlot ~= nil and e.RSlotLine ~= nil and e.RSlot ~= effRS then
                    replace[e.RSlotLine] = lines[e.RSlotLine]:gsub('RSlot = %d+', 'RSlot = ' .. tostring(effRS), 1);
                    report.fixed[#report.fixed + 1] = string.format('%s: RSlot %d -> %d', e.key, e.RSlot, effRS);
                end
                -- Range/Ammo pair key (v128). Same reason as RSlot above: EVERY gear.lua
                -- written before this existed lacks it, the engine cannot see the
                -- catalog, and without it a gun and a crossbow are both just
                -- "Marksmanship" -- so AutoAmmo can keep a bolt out of a bow but not out
                -- of a gun. Insert-only, unlike RSlot: a pair key is a fixed server fact
                -- about the item (item_weapon skill/subskill), not a rule we derive, so
                -- there is nothing to retract and a differing stamp is not ours to
                -- second-guess.
                if e.Pair == nil and type(c.Pair) == 'string' and c.Pair ~= '' then
                    ins(string.format('Pair = %q,', c.Pair), string.format('+Pair %s', c.Pair));
                end
            end
        end
    end

    local out = {};
    for idx = 1, #lines do
        if not removeLine[idx] then out[#out+1] = replace[idx] or lines[idx]; end
        if insertAfter[idx] then for _, l in ipairs(insertAfter[idx]) do out[#out+1] = l; end end
    end
    return table.concat(out, '\n') .. '\n', report;
end

-- Backup origText, then the shared atomic replace (lib\safewrite) with the
-- sandbox-run validator. Returns backupPath, or nil + error.
local function safeReplaceGear(gpath, newText, origText)
    local backupPath, berr = sw.timestampBackup(charBackupDir(), 'gear_', origText);
    if backupPath == nil then return nil, berr; end
    local wok, werr = sw.replaceLua(gpath, newText, { origText = origText, validate = gearLoadValidator });
    if not wok then return nil, tostring(werr) .. ' (backup: ' .. backupPath .. ')'; end
    return backupPath;
end

function M.fix()
    local gpath = gearPath();
    if gpath == nil then print('[dlac] fix: profile path unavailable (are you logged in?).'); return; end
    local gearText = readFile(gpath);
    if gearText == nil then print('[dlac] fix: cannot read gear.lua.'); return; end

    local owned = {};
    for _, it in ipairs(M.scan()) do
        owned[#owned+1] = { Name = it.Name, FullName = it.FullName, Level = it.Level, Id = it.Id };
    end

    -- Catalog metadata (Type / OneHanded) by Id for the pairing backfill, from
    -- the one walker (catalogindex.rawIndex -- read-only shared map). Without
    -- the catalog it is empty and fix behaves exactly as before.
    local metaById = ci.rawIndex();

    local newText, report = M.computeFixes(gearText, owned, metaById);

    if #report.duplicates > 0 then
        print('[dlac] duplicate entries (review by hand -- not auto-changed):');
        for _, d in ipairs(report.duplicates) do print('  * ' .. d); end
    end
    if #report.keyMismatch > 0 then
        print('[dlac] key mismatches (NOT renamed -- would break job-file refs):');
        for _, k in ipairs(report.keyMismatch) do print('  * ' .. k); end
    end

    if #report.fixed == 0 then
        print(string.format('[dlac] fix: no data corrections needed (%d owned item(s) matched).', report.matched));
        return;
    end

    local backupPath, err = safeReplaceGear(gpath, newText, gearText);
    if backupPath == nil then
        print('[dlac] fix ABORTED: ' .. tostring(err) .. '. gear.lua untouched.');
        return;
    end
    print(string.format('[dlac] fixed %d field(s):', #report.fixed));
    for i, f in ipairs(report.fixed) do
        if i > 25 then
            print(string.format('  ... and %d more (diff against the backup to see all).', #report.fixed - 25));
            break;
        end
        print('  ' .. f);
    end
    print('[dlac] backup: ' .. backupPath .. '  --  run /dl r to load.');
end

-- ---------------------------------------------------------------------------
-- Dedupe (`/dl dedupe`): remove redundant entries that share the SAME parent and
-- key (true duplicates -- in Lua all but the last are dead code anyway). Keeps the
-- most complete of each group (has Id, then most fields); reports what it kept.
-- Backup + sandbox-validated like the others.
-- ---------------------------------------------------------------------------

-- Pure: gear.lua text -> deduped text, report, total removed.
function M.computeDedupe(gearText)
    local lines = toLines(gearText);
    local entries = parseGearEntries(lines);

    local groups = {};
    for _, e in ipairs(entries) do
        local g = tostring(e.parent) .. '|' .. string.lower(e.key);
        groups[g] = groups[g] or {}; groups[g][#groups[g]+1] = e;
    end

    -- completeness: an Id counts for a lot, then block size (more fields/stats).
    local function score(e)
        local s = (e.endLine or 0) - (e.startLine or 0);
        if e.Id ~= nil then s = s + 1000; end
        return s;
    end

    local removeLines, report, total = {}, {}, 0;
    for _, grp in pairs(groups) do
        if #grp > 1 then
            local best = grp[1];
            for _, e in ipairs(grp) do if score(e) > score(best) then best = e; end end
            local removed = 0;
            for _, e in ipairs(grp) do
                if e ~= best then
                    for ln = e.startLine, e.endLine do removeLines[ln] = true; end
                    removed = removed + 1; total = total + 1;
                end
            end
            report[#report+1] = { parent = best.parent, key = best.key, name = best.Name, id = best.Id, removed = removed };
        end
    end

    local out = {};
    for idx = 1, #lines do if not removeLines[idx] then out[#out+1] = lines[idx]; end end
    return table.concat(out, '\n') .. '\n', report, total;
end

function M.dedupe()
    local gpath = gearPath();
    if gpath == nil then print('[dlac] dedupe: profile path unavailable (are you logged in?).'); return; end
    local gearText = readFile(gpath);
    if gearText == nil then print('[dlac] dedupe: cannot read gear.lua.'); return; end

    local newText, report, total = M.computeDedupe(gearText);
    if total == 0 then print('[dlac] dedupe: no duplicate entries found.'); return; end

    local backupPath, err = safeReplaceGear(gpath, newText, gearText);
    if backupPath == nil then print('[dlac] dedupe ABORTED: ' .. tostring(err) .. '. gear.lua untouched.'); return; end

    print(string.format('[dlac] removed %d duplicate entr%s (kept the most complete of each):', total, (total == 1 and 'y' or 'ies')));
    for _, r in ipairs(report) do
        print(string.format('  %s.%s -> kept "%s" (Id %s), removed %d', tostring(r.parent), r.key, tostring(r.name), tostring(r.id), r.removed));
    end
    print('[dlac] backup: ' .. backupPath .. '  --  run /dl r to load.');
end

-- ---------------------------------------------------------------------------
-- Prune (`/dl prune`): remove gear.lua entries for items you no longer own
-- ANYWHERE. Ownership is checked against ALL_CONTAINERS (deep storage included),
-- so only genuinely-gone gear -- old hand-added entries like a Mandau you never
-- had, or things long since sold -- gets removed. Dry-run by default;
-- `/dl prune commit` applies with the usual rails (backup + sandbox validation +
-- atomic write via safeReplaceGear).
-- ---------------------------------------------------------------------------

-- Pure prune: gear.lua text + owned items -> newText, report, total. Matching
-- mirrors computeFixes, inverted: an entry is KEPT when its Id matches an owned
-- item's Id, or its Name / table key matches an owned item's Name / FullName /
-- generated key (case-insensitive) -- so id-less hand-written entries survive as
-- long as the item exists in a bag. Removed entries vanish whole (their
-- startLine..endLine, like computeDedupe); every kept line is byte-identical.
function M.computePrune(gearText, ownedItems)
    local lines = toLines(gearText);
    local entries = parseGearEntries(lines);

    local ownedIds, ownedNames, ownedKeys = {}, {}, {};
    for _, it in ipairs(ownedItems) do
        if it.Id ~= nil then ownedIds[it.Id] = true; end
        if it.Name ~= nil then ownedNames[string.lower(it.Name)] = true; end
        if it.FullName ~= nil then ownedNames[string.lower(it.FullName)] = true; end
        local k = makeKey(it.FullName or it.Name);
        if k ~= nil then ownedKeys[string.lower(k)] = true; end
    end

    local removeLines, report, total = {}, {}, 0;
    for _, e in ipairs(entries) do
        local owned = false;
        if e.Id ~= nil and ownedIds[e.Id] then owned = true; end
        if not owned and e.Name ~= nil and ownedNames[string.lower(e.Name)] then owned = true; end
        if not owned and ownedKeys[string.lower(e.key)] then owned = true; end
        if not owned then
            for ln = e.startLine, e.endLine do removeLines[ln] = true; end
            total = total + 1;
            report[#report + 1] = { parent = e.parent, key = e.key, name = e.Name, id = e.Id };
        end
    end

    local out = {};
    for idx = 1, #lines do if not removeLines[idx] then out[#out + 1] = lines[idx]; end end
    return table.concat(out, '\n') .. '\n', report, total;
end

function M.prune(apply)
    local gpath = gearPath();
    if gpath == nil then print('[dlac] prune: profile path unavailable (are you logged in?).'); return; end
    local gearText = readFile(gpath);
    if gearText == nil then print('[dlac] prune: cannot read gear.lua.'); return; end

    local owned = M.scan(M.ALL_CONTAINERS);
    if type(owned) ~= 'table' or #owned == 0 then
        -- An empty scan means the game isn't readable right now (zoning / char
        -- select), NOT that you own nothing -- pruning on it would erase the file.
        print('[dlac] prune ABORTED: the bag scan found nothing (zoning? not logged in?). gear.lua untouched.');
        return;
    end

    local newText, report, total = M.computePrune(gearText, owned);
    if total == 0 then
        print(string.format('[dlac] prune: all entries match gear you own (checked %d items across every container).', #owned));
        return;
    end

    print(string.format('[dlac] prune: %d entr%s match NOTHING in any container (equipped gear and deep storage were checked):',
        total, (total == 1 and 'y' or 'ies')));
    for _, r in ipairs(report) do
        print(string.format('  %s.%s  "%s"%s', tostring(r.parent), tostring(r.key), tostring(r.name),
            (r.id ~= nil) and ('  Id:' .. tostring(r.id)) or ''));
    end
    print('[dlac] every container was checked (bags, safes, storage, locker, satchel, sack, case, wardrobes).');
    print('[dlac] only gear stored OUTSIDE the container system (Porter Moogle slips / delivery box) is invisible -- check the list for those before committing.');

    if not apply then
        print('[dlac] dry run -- nothing written. Run  /dl prune commit  to remove them (a backup is kept).');
        return;
    end

    local backupPath, err = safeReplaceGear(gpath, newText, gearText);
    if backupPath == nil then
        print('[dlac] prune ABORTED: ' .. tostring(err) .. '. gear.lua untouched.');
        return;
    end
    print(string.format('[dlac] pruned %d entr%s from gear.lua.', total, (total == 1 and 'y' or 'ies')));
    print('[dlac] backup: ' .. backupPath .. '  --  run /dl r to load.');
end

-- `/dl prune why <name>`: explain why prune keeps (or would remove) an entry.
-- Finds gear.lua entries whose key or Name contains <name>, then re-runs the
-- ownership test one container at a time, so every keep is attributed to a real
-- item in a real bag. Matching MUST mirror computePrune: Id, then Name vs the
-- item's short/log name, then table key vs the item's generated key.
function M.pruneWhy(query)
    query = tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', '');
    if query == '' then print('[dlac] usage: /dl prune why <item name or key>'); return; end
    local gpath = gearPath();
    if gpath == nil then print('[dlac] prune why: profile path unavailable (are you logged in?).'); return; end
    local gearText = readFile(gpath);
    if gearText == nil then print('[dlac] prune why: cannot read gear.lua.'); return; end

    local q = string.lower(query);
    local targets = {};
    for _, e in ipairs(parseGearEntries(toLines(gearText))) do
        if string.find(string.lower(e.key), q, 1, true)
           or (e.Name ~= nil and string.find(string.lower(e.Name), q, 1, true)) then
            targets[#targets + 1] = e;
        end
    end
    if #targets == 0 then
        print(string.format('[dlac] prune why: no gear.lua entry matches "%s" (checked keys and Names).', query));
        return;
    end

    local function lc(s) return (s ~= nil) and string.lower(s) or nil; end
    for _, e in ipairs(targets) do
        print(string.format('[dlac] %s.%s  "%s"%s:', tostring(e.parent), tostring(e.key), tostring(e.Name),
            (e.Id ~= nil) and ('  Id:' .. tostring(e.Id)) or ''));
        local kept = false;
        for _, cid in ipairs(M.ALL_CONTAINERS) do
            for _, it in ipairs(M.scan({ cid })) do
                local m = nil;
                if e.Id ~= nil and it.Id == e.Id then m = 'Id ' .. tostring(e.Id);
                elseif e.Name ~= nil and (lc(it.Name) == lc(e.Name) or lc(it.FullName) == lc(e.Name)) then m = 'Name';
                else
                    local k = makeKey(it.FullName or it.Name);
                    if k ~= nil and string.lower(k) == string.lower(e.key) then m = 'key'; end
                end
                if m ~= nil then
                    kept = true;
                    print(string.format('  KEPT by "%s" (Id %s) in %s  --  matched on %s',
                        tostring(it.Name), tostring(it.Id), M.containerName(cid), m));
                end
            end
        end
        if not kept then
            print('  matches NOTHING you own -- /dl prune will remove this entry.');
        end
    end
end

-- Auto-sync: scan bags and, ONLY if there's new gear, stage + commit it into gear.lua.
-- Returns the number of new items found (0 = nothing new -> no stage/commit, no output, no
-- writes). ADD-ONLY: the scan covers every container (deep storage included) but entries
-- are only ever added, never removed -- removal stays /dl prune's job, on explicit command.
-- Safe to call often -- commit is parse-validated + backed up, and this is silent whenever
-- there's nothing to add.
function M.sync()
    local added = 0;
    pcall(function()
        local items = M.scan();
        if type(items) ~= 'table' then return; end
        local newCount = 0;
        for _, it in ipairs(items) do if not it.Known then newCount = newCount + 1; end end
        if newCount == 0 then return; end     -- nothing new -> silent no-op
        M.stage(nil, true);                   -- quiet: auto-sync is release behavior,
        M.commit(true);                       -- not the manual debugging pipeline
        added = newCount;
    end);
    return added;
end

-- ---------------------------------------------------------------------------
-- Command hook:  /dl scan | preview | stage | commit | fix | dedupe | prune
-- Self-contained and additive -- it does not touch utils.lua's own handler, and
-- only acts on its own subcommands, leaving everything else alone.
-- ---------------------------------------------------------------------------
local function argStart(raw)
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then return 7; end
    if raw == '/dl'       or string.sub(raw, 1, 4)  == '/dl '       then return 5;  end
    return nil;
end

ashita.events.register('command', 'dlac-import', function(e)
    local raw   = string.lower(e.command);
    local start = argStart(raw);
    if start == nil then return; end

    local args = {};
    for a in string.gmatch(string.sub(raw, start), '[^%s]+') do
        table.insert(args, a);
    end

    local sub = args[1];
    if sub ~= 'scan' and sub ~= 'preview' and sub ~= 'stage' and sub ~= 'commit' and sub ~= 'fix' and sub ~= 'dedupe' and sub ~= 'prune' then return; end   -- leave others to utils.lua

    e.blocked = true;
    if sub == 'preview' then
        M.preview();
        return;
    end
    if sub == 'stage' then
        M.stage();
        return;
    end
    if sub == 'commit' then
        M.commit();
        return;
    end
    if sub == 'fix' then
        M.fix();
        return;
    end
    if sub == 'dedupe' then
        M.dedupe();
        return;
    end
    if sub == 'prune' then
        if args[2] == 'why' then
            M.pruneWhy(table.concat(args, ' ', 3));
        else
            M.prune(args[2] == 'commit');
        end
        return;
    end
    if args[2] == 'equipped' then
        print('[dlac] "scan equipped" arrives with the next piece -- running a full scan for now.');
    end
    M.scanAndReport();
end);

return M;
