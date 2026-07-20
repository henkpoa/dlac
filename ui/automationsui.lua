--[[
    dlac/automationsui.lua -- the Automations tab (its own MAIN tab, right of Triggers)
    plus the whole automations manifest machinery (ADR 0004 and everything that grew
    on it: staves/obis, MaxMP batteries, craft/HELM/fish ladders).

    Extracted from triggersui.lua 2026-07-18: LuaJIT caps a chunk at 200 local
    variables; the automation block owned 30 of triggersui's 123 and shared nothing
    with the trigger editor beyond the deps table. This module gets its own budget.

    gearui injects the SAME deps table triggersui gets (M.init) and registers the
    Automations tab (M.renderTab). The rescan seams live HERE now:
    M.rescanAutogear / M.manifestStale / M.currentFmt -- craftwatch, helmwatch,
    fishwatch and gearui's auto-sync hook (syncflags) all require THIS module.
    Everything is defensive: no deps / no imgui just renders a notice instead of
    erroring, and headless (tests) every entry point is a safe no-op.
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local _dpok, dsp  = pcall(require, "dlac\\dispatch");
local _lsok, lscale = pcall(require, "dlac\\data\\levelstats");
local _nmok, nmp  = pcall(require, "dlac\\data\\nativemp");
local hasImgui    = _iok and imgui ~= nil;
local hasDispatch = _dpok and type(dsp) == 'table';
local hasLScale   = _lsok and type(lscale) == 'table';
local hasNmp      = _nmok and type(nmp) == 'table';

local function mainLevel()
    local lv = nil;
    pcall(function() lv = AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel(); end);
    return (type(lv) == 'number' and lv > 0) and lv or 99;
end

-- Injected by gearui (M.init): the same table triggersui receives -- charBase,
-- lookupByName, ownedCounts, ownedList, allEquipList, haveInBags, playerJob,
-- renderIcon, itemTooltip (the automation keys); helmui/fishui take the whole
-- table per call, so sharing one table keeps their contract unchanged.
local deps = nil;
function M.init(d)
    deps = d;
end

-- Colors (match gearui's palette).
local COL_HEADER = { 0.60, 0.75, 1.00, 1.00 };
local COL_DIM    = { 0.70, 0.70, 0.70, 1.00 };
local COL_ERR    = { 1.00, 0.45, 0.40, 1.00 };

-- Owned-vs-Available facts (ADR 0005) for the item rows: a piece parked in
-- storage must read RED (owned, can't be equipped), not dim-as-unowned.
-- Guarded: without the module the rows just keep the pre-ruling colors.
local _ocok, ocache = pcall(require, 'dlac\\gear\\ownedcache');
_ocok = _ocok and type(ocache) == 'table';

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end
local function writeFileText(p, t)
    local f = io.open(p, 'w'); if f == nil then return false; end
    f:write(t); f:close(); return true;
end

-- ---------------------------------------------------------------------------
-- Automations (ADR 0004): auto elemental staff / auto obi. The GUI owns DERIVING
-- the manifest -- from the player's bags via deps.ownedCounts + deps.lookupByName --
-- and writes <char>\dlac\autogear.lua; the LAC-state engine hot-reloads it and
-- synthesizes band-60 rules at Midcast. Name lists are era/CatsEyeXI staples; the
-- Iridescence list is a fallback until the catalog carries the stat (issue #5).
-- ---------------------------------------------------------------------------
local ELEMENTS8 = { 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark' };
local STAFF_NQ = {
    Fire = 'Fire Staff',   Ice = 'Ice Staff',     Wind = 'Wind Staff',   Earth = 'Earth Staff',
    Thunder = 'Thunder Staff', Water = 'Water Staff', Light = 'Light Staff', Dark = 'Dark Staff',
};
local STAFF_HQ = {
    Fire = "Vulcan's Staff",  Ice = "Aquilo's Staff",   Wind = "Auster's Staff",  Earth = "Terra's Staff",
    Thunder = "Jupiter's Staff", Water = "Neptune's Staff", Light = "Apollo's Staff", Dark = "Pluto's Staff",
};
local OBI = {
    Fire = 'Karin Obi', Ice = 'Hyorin Obi', Wind = 'Furin Obi', Earth = 'Dorin Obi',
    Thunder = 'Rairin Obi', Water = 'Suirin Obi', Light = 'Korin Obi', Dark = 'Anrin Obi',
};
-- Universal obi (all elements). On CatsEyeXI the eight elemental obis don't exist --
-- Hachirin-no-obi is THE obi; the day/weather gate still applies per cast.
local OBI_UNIVERSAL = { 'Hachirin-no-obi' };
-- Universal Iridescence weapons (all elements) -> their tier. CatsEyeXI tiers:
-- elemental staves carry Iridescence for THEIR element only (NQ +1 / HQ +2);
-- these carry it for every element. Fallback list until the catalog carries the
-- Iridescence stat (issue #5); ordered check picks the highest owned tier.
local UNIVERSAL = {
    -- ordered check picks the FIRST owned: the specific +2 weapons are preferred,
    -- Chatoyant is the +2 fallback, Iridal the +1 tier.
    { name = 'Foreshadow +1',   tier = 2 },
    { name = 'Claustrum',       tier = 2 },
    { name = 'Chatoyant Staff', tier = 2 },
    { name = 'Iridal Staff',    tier = 1 },
};

-- Manifest schema version: bump when autoCommit writes NEW fields. An on-disk
-- manifest with an older fmtver self-heals (renderAutomations triggers a rescan)
-- so a dlac update never needs a manual "Rescan owned gear" click.
local AUTO_FMT = 9;   -- 2: mpBest ladders; 3: MP level-effective; 4: staves/obis job-checked; 5: craft ladders; 6: skill-up fillers in hq/nq; 7: helm ladders + hat map; 8: fish ladders; 9: oneiros grip + mpMerits

local auto = { data = nil, loadedFor = nil, status = '' };

local function autoPath()
    local base = deps and deps.charBase and deps.charBase() or nil;
    return base and (base .. 'dlac\\autogear.lua') or nil;
end

local function autoLoad()
    local p = autoPath();
    if p == nil then return; end
    if auto.loadedFor == p and auto.data ~= nil then return; end
    auto.loadedFor = p;
    auto.data = {};
    pcall(function()
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then auto.data = t; end
    end);
end

-- Is this exact item name in the player's bags? (catalog/owned lookup -> Id -> count)
local function ownedRec(name)
    if deps.lookupByName == nil then return nil; end
    local rec = deps.lookupByName(name);
    if rec == nil or rec.Id == nil then return nil; end
    local oc = (deps.ownedCounts ~= nil) and deps.ownedCounts() or nil;
    if type(oc) == 'table' and (oc[rec.Id] or 0) >= 1 then return rec; end
    return nil;
end

-- Owned AND equippable by the CURRENT job -- THE automation rule (field case:
-- Foreshadow +1 sat in WHM's manifest as the universal; WHM can't wear it and
-- AutoIridescence looked dead). The manifest is per-job, so every staff/obi
-- pick passes the central eligibility check; item LEVEL is still checked live
-- by the engine at resolve time.
local function curJob()
    return (type(deps.playerJob) == 'function') and deps.playerJob() or nil;
end
local function usableRec(name, job)
    local rec = ownedRec(name);
    if rec == nil then return nil; end
    if hasDispatch and type(dsp.canWear) == 'function'
       and not dsp.canWear(rec, job, 99) then return nil; end
    return rec;
end

-- Re-derive the manifest from bags (HQ staff preferred), write it, hot-reload the engine.
-- The manifest carries GEAR DATA only; whether an automation fires is decided by the
-- SET: a dlac:AutoStaff / dlac:AutoObi virtual entry in its Main / Waist slot (Sets tab).
local function autoCommit()
    local p = autoPath();
    if p == nil then auto.status = 'not logged in.'; return; end
    -- USER-SET fields survive regeneration by riding the loaded manifest:
    -- seed auto.data from disk first (no-op when already loaded), then carry
    -- mpMerits forward. mpMerits = Max MP merit LEVELS (0..10: merit.cpp caps
    -- usable merits at cap[75]=10 -- the menu's own 10/10; the merits.sql 15
    -- headroom needs Lv80+) -- the one Oneiros-threshold input the client
    -- cannot read passively (merits only cross the wire when the menu opens).
    autoLoad();
    local mpMerits = (type(auto.data) == 'table') and math.floor(tonumber(auto.data.mpMerits) or 0) or 0;
    if mpMerits < 0 then mpMerits = 0; elseif mpMerits > 10 then mpMerits = 10; end
    -- Per-element pick: HQ staff (Iridescence +2 for its element) over NQ (+1).
    -- Every entry records its item LEVEL so the engine can skip gear the character
    -- is under-leveled for (and fall back to the slot's regular pick).
    -- Job-aware picks: gData does NOT exist in the addon state -- the job comes
    -- from Ashita memory via deps.playerJob.
    local job = curJob();
    -- Oneiros Grip (dlac:AutoOneiros, Sub): one item, but the engine can't read
    -- the catalog -- name + level ride the manifest like every other automation.
    local oneirosGrip = usableRec('Oneiros Grip', job);
    local staff, obi, nStaff, nObi = {}, {}, 0, 0;
    for _, el in ipairs(ELEMENTS8) do
        local hq, nq = usableRec(STAFF_HQ[el], job), usableRec(STAFF_NQ[el], job);
        if hq ~= nil then staff[el] = { name = hq.Name, tier = 2, level = hq.Level or 0 }; nStaff = nStaff + 1;
        elseif nq ~= nil then staff[el] = { name = nq.Name, tier = 1, level = nq.Level or 0 }; nStaff = nStaff + 1; end
        local ob = usableRec(OBI[el], job);
        if ob ~= nil then obi[el] = { name = ob.Name, level = ob.Level or 0 }; nObi = nObi + 1; end
    end
    -- Best usable universal (highest tier first -- the list is ordered).
    local uni, uniLevel = nil, 0;
    for _, u in ipairs(UNIVERSAL) do
        local rec = usableRec(u.name, job);
        if rec ~= nil then uni = u; uniLevel = rec.Level or 0; break; end
    end
    -- Universal obi (Hachirin-no-obi): covers every element.
    local obiUni, obiUniLevel = nil, 0;
    for _, nm in ipairs(OBI_UNIVERSAL) do
        local rec = usableRec(nm, job);
        if rec ~= nil then obiUni, obiUniLevel = rec.Name, rec.Level or 0; break; end
    end
    -- Max-MP mode data: every owned piece carrying flat MP, lower(name) -> total,
    -- PLUS the best battery per equip slot (ear/ring get the top two) so the
    -- engine can EQUIP them, not just hold them. The engine can't read the
    -- catalog, so both ride this manifest.
    local mp, mpBest = {}, {};
    pcall(function()
        if type(deps.ownedList) ~= 'function' then return; end
        local counts = (type(deps.ownedCounts) == 'function') and deps.ownedCounts() or nil;
        local lvl = mainLevel();
        local bySlot = {};   -- gear-slot key -> candidates { name, mp, level }
        for _, rec in ipairs(deps.ownedList() or {}) do
            -- LEVEL-EFFECTIVE stats via THE central resolver (levelstats.effective):
            -- Tamas Ring is MP 15 on paper but 29 at Lv74. Values are a snapshot at
            -- scan-time level; the constant auto-rescans keep them fresh.
            local st = (hasLScale and type(lscale.effective) == 'function')
                and lscale.effective(rec, lvl) or rec.Stats;
            if type(st) ~= 'table' then st = nil; end
            -- Convert counts: 25 HP -> MP is +25 max MP for this mode's purposes.
            local v = (st ~= nil) and ((tonumber(st.MP) or 0) + (tonumber(st.ConvertHPtoMP) or 0)) or 0;
            if v > 0 and rec.Name ~= nil then
                local k = string.lower(rec.Name);
                if (mp[k] or 0) < v then mp[k] = v; end   -- hold map: unfiltered (worn = legal)
                -- Battery CANDIDATES use the central eligibility check (main job
                -- only; the manifest regenerates on job change) and must be in an
                -- equippable bag -- a job-illegal or stored pick would make the
                -- engine's /equip fail SILENTLY and the whole mode look dead.
                -- Job checked at level 99: the ladder may carry gear to grow into;
                -- the ENGINE picks the best rung wearable at the live level.
                local sl = tostring(rec.Slot or '');
                if sl ~= '' and sl ~= 'Main' and sl ~= 'Sub' and sl ~= 'Range'
                   and (not hasDispatch or type(dsp.canWear) ~= 'function' or dsp.canWear(rec, job, 99))
                   and (type(deps.haveInBags) ~= 'function' or deps.haveInBags(rec)) then
                    bySlot[sl] = bySlot[sl] or {};
                    local c = { name = rec.Name, mp = v, level = rec.Level or 0 };
                    table.insert(bySlot[sl], c);
                    -- A genuine duplicate (two Astral Rings) may fill BOTH paired slots.
                    if (sl == 'Ear' or sl == 'Ring') and type(counts) == 'table'
                       and rec.Id ~= nil and (counts[rec.Id] or 0) >= 2 then
                        table.insert(bySlot[sl], c);
                    end
                end
            end
        end
        -- Ladders, best first. Ear/Ring alternate into two DISJOINT ladders so
        -- one physical item can never be picked for both slots.
        local LADDER = 4;
        for sl, list in pairs(bySlot) do
            table.sort(list, function(a, b)
                if a.mp ~= b.mp then return a.mp > b.mp; end
                return a.name < b.name;
            end);
            if sl == 'Ear' or sl == 'Ring' then
                local l1, l2 = {}, {};
                for i, c in ipairs(list) do
                    local t = (i % 2 == 1) and l1 or l2;
                    if #t < LADDER then t[#t + 1] = c; end
                end
                if #l1 > 0 then mpBest[string.lower(sl) .. '1'] = l1; end
                if #l2 > 0 then mpBest[string.lower(sl) .. '2'] = l2; end
            else
                local l = {};
                for i = 1, math.min(#list, LADDER) do l[i] = list[i]; end
                mpBest[string.lower(sl)] = l;
            end
        end
    end);
    -- Craft automation data (docs/design/craft-automation.md): per SLOT, per
    -- CRAFT, per GOAL ('hq'/'nq'), a best-first ladder of owned+wearable gear.
    -- Craft-specific and universal pieces compete in ONE ladder ("the Torques
    -- in a row, then the universal"): an Artisans Torque scores for every
    -- craft, a Smiths Ring only for Smithing's nq ladder. Data-driven from
    -- catalog stats -- a catalog update + rescan picks up new server gear.
    -- Goals per Henrik: hq = raise HQ (AntiHQ gear DISQUALIFIES); nq = block
    -- HQ on purpose (crafting materials you don't want HQ'd).
    local craftBest = {};
    pcall(function()
        if type(deps.ownedList) ~= 'function' then return; end
        local CRAFTS = { 'Woodworking', 'Smithing', 'Goldsmithing', 'Clothcraft',
                         'Leathercraft', 'Bonecraft', 'Alchemy', 'Cooking' };
        local counts = (type(deps.ownedCounts) == 'function') and deps.ownedCounts() or nil;
        local lvl = mainLevel();
        local CLADDER = 3;
        local bySlot = {};   -- slotKey -> craft -> goal -> { {name, score, level}, ... }
        for _, rec in ipairs(deps.ownedList() or {}) do
            local st = (hasLScale and type(lscale.effective) == 'function')
                and lscale.effective(rec, lvl) or rec.Stats;
            local sl = tostring(rec.Slot or '');
            if type(st) == 'table' and rec.Name ~= nil and sl ~= ''
               and (not hasDispatch or type(dsp.canWear) ~= 'function' or dsp.canWear(rec, job, 99))
               and (type(deps.haveInBags) ~= 'function' or deps.haveInBags(rec)) then
                local succ  = tonumber(st.SynthSuccessRate) or 0;
                local hqr   = tonumber(st.SynthHQRate) or 0;
                local gain  = tonumber(st.SynthSkillGain) or 0;
                local mat   = tonumber(st.SynthMaterialLoss) or 0;
                local consv = tonumber(st.ConserveIngredient) or 0;
                local dup = (sl == 'Ear' or sl == 'Ring') and type(counts) == 'table'
                            and rec.Id ~= nil and (counts[rec.Id] or 0) >= 2;
                -- Skill-up items (Midras's Helm, Bonze Cape, Shapers Shawl) have
                -- no per-craft mod, so they'd only ever fill the SKILL-UP goal.
                -- Henrik wants them worn under HQ/NQ TOO -- but only as FILLERS:
                -- a real craft-skill item (Chef's Hat for HQ) must still win its
                -- slot. gain*0.3 (floored) keeps every skill-up item below the
                -- weakest craft-skill contribution (skill=1 -> 10), so it fills
                -- otherwise-empty slots and never beats real skill/HQ/anti gear.
                local gainFill = math.floor(gain * 0.3);
                for _, cr in ipairs(CRAFTS) do
                    local skill = tonumber(st[cr .. 'Skill']) or 0;
                    local anti  = tonumber(st['AntiHQ' .. cr]) or 0;
                    -- hq (Henrik): "prioritize Skill gear to break tiers" --
                    -- craft skill first, HQ+ second; anti-HQ BLOCKS the goal;
                    -- skill-up items fill empty slots (gainFill, always < skill).
                    local hqScore = (anti > 0) and 0 or (skill * 10 + hqr * 5 + succ + gainFill);
                    -- nq: the HQ block is the point; skill/success still help;
                    -- skill-up items fill empty slots (they don't affect HQ odds).
                    local nqScore = anti * 100 + skill * 3 + succ * 2 + mat + consv + gainFill;
                    -- skillup: "skill up items over skill+" -- SynthSkillGain
                    -- gear first, raw craft skill second.
                    local suScore = gain * 10 + skill * 2 + succ;
                    for goal, score in pairs({ hq = hqScore, nq = nqScore, skillup = suScore }) do
                        if score > 0 then
                            bySlot[sl] = bySlot[sl] or {};
                            bySlot[sl][cr] = bySlot[sl][cr] or {};
                            local lad = bySlot[sl][cr][goal] or {};
                            bySlot[sl][cr][goal] = lad;
                            local c = { name = rec.Name, score = score, level = rec.Level or 0 };
                            lad[#lad + 1] = c;
                            if dup then lad[#lad + 1] = c; end   -- two copies may fill both paired slots
                        end
                    end
                end
            end
        end
        for sl, crafts in pairs(bySlot) do
            for cr, goals in pairs(crafts) do
                for goal, lad in pairs(goals) do
                    table.sort(lad, function(a, b)
                        if a.score ~= b.score then return a.score > b.score; end
                        return a.name < b.name;
                    end);
                    -- Ear/Ring split into DISJOINT ladders (mpBest pattern).
                    if sl == 'Ear' or sl == 'Ring' then
                        local l1, l2 = {}, {};
                        for i, c in ipairs(lad) do
                            local t = (i % 2 == 1) and l1 or l2;
                            if #t < CLADDER then t[#t + 1] = c; end
                        end
                        for suffix, l in pairs({ ['1'] = l1, ['2'] = l2 }) do
                            if #l > 0 then
                                local key = string.lower(sl) .. suffix;
                                craftBest[key] = craftBest[key] or {};
                                craftBest[key][cr] = craftBest[key][cr] or {};
                                craftBest[key][cr][goal] = l;
                            end
                        end
                    else
                        local l = {};
                        for i = 1, math.min(#lad, CLADDER) do l[i] = lad[i]; end
                        local key = string.lower(sl);
                        craftBest[key] = craftBest[key] or {};
                        craftBest[key][cr] = craftBest[key][cr] or {};
                        craftBest[key][cr][goal] = l;
                    end
                end
            end
        end
    end);
    -- HELM gathering ladders (docs/design/helm-gear.md): per SLOT, a best-first
    -- ladder of owned+in-bags gear carrying the catalog's HELM / Surveyor stats
    -- (Surveyor-major -- fewer "nothing" results; HELM-minor -- the break-roll
    -- rating, +7.3 per point on the 33% break check), PLUS the semantic hat map
    -- (WHICH category a hat doubles is not a catalog stat -- the id block
    -- 25557-25560 is one hat per category). Stat-driven like the craft
    -- ladders: new server gear lands on the next rescan, no table to edit.
    local helmBest, helmHats = {}, {};
    pcall(function()
        if type(deps.ownedList) ~= 'function' then return; end
        local lvl = mainLevel();
        local HLADDER = 4;
        local bySlot = {};   -- slot -> { {name, score, level, helm, surv}, ... }
        for _, rec in ipairs(deps.ownedList() or {}) do
            local st = (hasLScale and type(lscale.effective) == 'function')
                and lscale.effective(rec, lvl) or rec.Stats;
            local sl = tostring(rec.Slot or '');
            if type(st) == 'table' and rec.Name ~= nil and sl ~= ''
               and (not hasDispatch or type(dsp.canWear) ~= 'function' or dsp.canWear(rec, job, 99))
               and (type(deps.haveInBags) ~= 'function' or deps.haveInBags(rec)) then
                local helm = tonumber(st.HELM) or 0;
                local surv = tonumber(st.Surveyor) or 0;
                if helm > 0 or surv > 0 then
                    bySlot[sl] = bySlot[sl] or {};
                    local lad = bySlot[sl];
                    lad[#lad + 1] = { name = rec.Name, score = surv * 10 + helm,
                                      level = rec.Level or 0, helm = helm, surv = surv };
                end
            end
        end
        for sl, lad in pairs(bySlot) do
            table.sort(lad, function(a, b)
                if a.score ~= b.score then return a.score > b.score; end
                return a.name < b.name;
            end);
            local l = {};
            for i = 1, math.min(#lad, HLADDER) do l[i] = lad[i]; end
            helmBest[string.lower(sl)] = l;
        end
        -- Owned hats only; the engine falls back to the generic head ladder
        -- (another category's hat still carries Surveyor) when one is missing.
        for g, nm in pairs({ Harvesting = 'Harv. Sun Hat', Excavation = 'Excavators Shades',
                             Logging = 'Lumberjacks Beret', Mining = 'Miners Helmet' }) do
            local rec = usableRec(nm, job);
            if rec ~= nil and (type(deps.haveInBags) ~= 'function' or deps.haveInBags(rec)) then
                local st = type(rec.Stats) == 'table' and rec.Stats or {};
                helmHats[g] = { name = rec.Name, level = rec.Level or 0,
                                surv = tonumber(st.Surveyor) or 0 };
            end
        end
    end);
    -- Fishing ladders (docs/design/fishing-gear.md): per SLOT, best-first owned
    -- gear carrying the catalog's FishingSkill (Mod::FISH -- adds straight onto
    -- effective skill, server GetFishingSkill) or a fishdb gearBonus entry (the
    -- CatsEyeXI cx-mods the catalog drops; Brigands Eyepatch carries ONLY
    -- those). Score = FishingSkill-major, cx tiebreak (cx = Expert Angler:
    -- Fatigue Limit / Golden Arrow, identified 2026-07-18). Rings split into
    -- disjoint ladders like craft; Main carries fishing weapons (Halieutica);
    -- Range/Ammo are EXCLUDED -- rod and bait are fishstate picks, not ladders.
    local fishBest = {};
    pcall(function()
        if type(deps.ownedList) ~= 'function' then return; end
        local fcalc = require('dlac\\feature\\fishcalc');
        local lvl = mainLevel();
        local FLADDER = 4;
        local counts = (type(deps.ownedCounts) == 'function') and deps.ownedCounts() or nil;
        local bySlot = {};
        for _, rec in ipairs(deps.ownedList() or {}) do
            local st = (hasLScale and type(lscale.effective) == 'function')
                and lscale.effective(rec, lvl) or rec.Stats;
            local sl = tostring(rec.Slot or '');
            if type(st) == 'table' and rec.Name ~= nil and sl ~= ''
               and sl ~= 'Range' and sl ~= 'Ammo'
               and (not hasDispatch or type(dsp.canWear) ~= 'function' or dsp.canWear(rec, job, 99))
               and (type(deps.haveInBags) ~= 'function' or deps.haveInBags(rec)) then
                local fish = tonumber(st.FishingSkill) or 0;
                local bonus = (type(fcalc.bonusFor) == 'function') and fcalc.bonusFor(rec.Id) or nil;
                local score = fcalc.gearScore(fish, bonus);
                if score > 0 then
                    local dup = sl == 'Ring' and type(counts) == 'table'
                                and rec.Id ~= nil and (counts[rec.Id] or 0) >= 2;
                    bySlot[sl] = bySlot[sl] or {};
                    local lad = bySlot[sl];
                    local c = { name = rec.Name, score = score, level = rec.Level or 0, fish = fish };
                    lad[#lad + 1] = c;
                    if dup then lad[#lad + 1] = c; end   -- two copies may fill both rings
                end
            end
        end
        for sl, lad in pairs(bySlot) do
            table.sort(lad, function(a, b)
                if a.score ~= b.score then return a.score > b.score; end
                return a.name < b.name;
            end);
            if sl == 'Ring' then
                local l1, l2 = {}, {};
                for i, c in ipairs(lad) do
                    local t = (i % 2 == 1) and l1 or l2;
                    if #t < FLADDER then t[#t + 1] = c; end
                end
                if #l1 > 0 then fishBest.ring1 = l1; end
                if #l2 > 0 then fishBest.ring2 = l2; end
            else
                local l = {};
                for i = 1, math.min(#lad, FLADDER) do l[i] = lad[i]; end
                fishBest[string.lower(sl)] = l;
            end
        end
    end);
    -- The crafting GOAL persisted for the trigger-set path (the manual overlay
    -- reads craftstate.lua instead). Read it from craftwatch -- NOT from
    -- CRAFT_UI, which is declared LATER in this file: referencing it here made
    -- CRAFT_UI a nil global and threw, aborting autoCommit so the manifest
    -- never regenerated (hard rule 8 -- the fmtver-5 / no-filler bug).
    local goal = 'hq';
    pcall(function()
        local cw = require('dlac\\feature\\craftwatch');
        if type(cw.getGoal) == 'function' then goal = cw.getGoal(); end
    end);
    if goal ~= 'nq' and goal ~= 'skillup' then goal = 'hq'; end
    local L = {
        '-- dlac automation manifest -- written by the GUI (Automations tab).',
        '-- Tiered Iridescence: per-element staves (NQ +1 / HQ +2, own element only) and',
        '-- the best universal weapon (all elements). The engine picks the higher tier',
        '-- per cast; ties go to the universal. WHETHER it fires is decided by the set:',
        '-- a dlac:AutoStaff / dlac:AutoObi entry in its Main / Waist slot (Sets tab).',
        'return {',
        string.format('    fmtver = %d,', AUTO_FMT),   -- manifest schema: outdated -> auto-rescan
        string.format('    written = %q,', os.date('%Y-%m-%d %H:%M:%S')),
        string.format('    craftGoal = %q,', goal),    -- hq | nq | skillup (AutoCraft goal)
        string.format('    mpMerits = %d,', mpMerits), -- Max MP merit levels (0..15, 10 MP each) -- Oneiros threshold
        (oneirosGrip ~= nil)
            and string.format('    oneiros = { name = %q, level = %d },', oneirosGrip.Name, oneirosGrip.Level or 0)
            or  '    oneiros = false,',
        (uni ~= nil)
            and string.format('    universal = { name = %q, tier = %d, level = %d },', uni.name, uni.tier, uniLevel)
            or  '    universal = false,',
        (obiUni ~= nil)
            and string.format('    obiUniversal = { name = %q, level = %d },', obiUni, obiUniLevel)
            or  '    obiUniversal = false,',
        '    staff = {',
    };
    for _, el in ipairs(ELEMENTS8) do
        local s = staff[el];
        if s ~= nil then
            L[#L + 1] = string.format('        %s = { name = %q, tier = %d, level = %d },', el, s.name, s.tier, s.level);
        end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    obi = {';
    for _, el in ipairs(ELEMENTS8) do
        local o = obi[el];
        if o ~= nil then
            L[#L + 1] = string.format('        %s = { name = %q, level = %d },', el, o.name, o.level);
        end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    mp = {';
    local mpKeys = {};
    for k in pairs(mp) do mpKeys[#mpKeys + 1] = k; end
    table.sort(mpKeys);
    for _, k in ipairs(mpKeys) do
        L[#L + 1] = string.format('        [%q] = %d,', k, mp[k]);
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    mpBest = {';
    local mbKeys = {};
    for k in pairs(mpBest) do mbKeys[#mbKeys + 1] = k; end
    table.sort(mbKeys);
    for _, k in ipairs(mbKeys) do
        local rungs = {};
        for _, c in ipairs(mpBest[k]) do
            rungs[#rungs + 1] = string.format('{ name = %q, mp = %d, level = %d }', c.name, c.mp, c.level);
        end
        L[#L + 1] = string.format('        %s = { %s },', k, table.concat(rungs, ', '));
    end
    L[#L + 1] = '    },';
    -- craft ladders: slotKey -> craft -> goal ('hq'/'nq') -> best-first rungs
    L[#L + 1] = '    craft = {';
    local cbKeys = {};
    for k in pairs(craftBest) do cbKeys[#cbKeys + 1] = k; end
    table.sort(cbKeys);
    for _, k in ipairs(cbKeys) do
        L[#L + 1] = string.format('        %s = {', k);
        local crs = {};
        for cr in pairs(craftBest[k]) do crs[#crs + 1] = cr; end
        table.sort(crs);
        for _, cr in ipairs(crs) do
            local parts = {};
            for _, goal in ipairs({ 'hq', 'nq', 'skillup' }) do
                local lad = craftBest[k][cr][goal];
                if lad ~= nil then
                    local rungs = {};
                    for _, c in ipairs(lad) do
                        rungs[#rungs + 1] = string.format('{ name = %q, score = %d, level = %d }',
                            c.name, c.score, c.level);
                    end
                    parts[#parts + 1] = string.format('%s = { %s }', goal, table.concat(rungs, ', '));
                end
            end
            L[#L + 1] = string.format('            %s = { %s },', cr, table.concat(parts, ', '));
        end
        L[#L + 1] = '        },';
    end
    L[#L + 1] = '    },';
    -- helm ladders: slotKey -> best-first rungs (Surveyor-major), plus the
    -- owned-hat map keyed by category (engine: dlac:AutoHelm).
    L[#L + 1] = '    helm = {';
    L[#L + 1] = '        hats = {';
    for _, g in ipairs({ 'Harvesting', 'Excavation', 'Logging', 'Mining' }) do
        local h = helmHats[g];
        if h ~= nil then
            L[#L + 1] = string.format('            %s = { name = %q, level = %d, surv = %d },',
                g, h.name, h.level, h.surv);
        end
    end
    L[#L + 1] = '        },';
    local hbKeys = {};
    for k in pairs(helmBest) do hbKeys[#hbKeys + 1] = k; end
    table.sort(hbKeys);
    for _, k in ipairs(hbKeys) do
        local rungs = {};
        for _, c in ipairs(helmBest[k]) do
            rungs[#rungs + 1] = string.format('{ name = %q, score = %d, level = %d, helm = %d, surv = %d }',
                c.name, c.score, c.level, c.helm, c.surv);
        end
        L[#L + 1] = string.format('        %s = { %s },', k, table.concat(rungs, ', '));
    end
    L[#L + 1] = '    },';
    -- fish ladders: slotKey -> best-first rungs (engine: dlac:AutoFish;
    -- Range/Ammo deliberately absent -- rod and bait live in fishstate.lua).
    L[#L + 1] = '    fish = {';
    local fbKeys = {};
    for k in pairs(fishBest) do fbKeys[#fbKeys + 1] = k; end
    table.sort(fbKeys);
    for _, k in ipairs(fbKeys) do
        local rungs = {};
        for _, c in ipairs(fishBest[k]) do
            rungs[#rungs + 1] = string.format('{ name = %q, score = %d, level = %d, fish = %d }',
                c.name, c.score, c.level, c.fish);
        end
        L[#L + 1] = string.format('        %s = { %s },', k, table.concat(rungs, ', '));
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '};';
    L[#L + 1] = '';
    if writeFileText(p, table.concat(L, '\n')) then
        auto.data = nil; autoLoad();   -- re-read what we just wrote
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl triggers reload'); end);
        auto.status = string.format('staves %d/8, obis %d/8%s%s -- saved, live now.', nStaff, nObi,
            (uni ~= nil) and string.format(', universal: %s (Iridescence +%d)', uni.name, uni.tier) or '',
            (obiUni ~= nil) and (', obi: ' .. obiUni .. ' (all elements)') or '');
    else
        auto.status = 'could not write ' .. p;
    end
end

-- (Flag saves regenerate the manifest via autoCommit every time -- rescanning is 16
-- name lookups, and it guarantees the manifest format/tier data is never stale.)

-- Exported for gearui's auto-sync hook: regenerate the manifest on login / job change
-- (same cadence as the gear.lua auto-sync), so the Rescan button is a manual override,
-- not a required step. Safe no-op before init / login.
function M.rescanAutogear()
    if deps == nil then return; end
    pcall(autoCommit);
    -- Same cadence as the manifest rescan (login / job change): warn about
    -- trigger-referenced gear that is parked in storage. Signature-deduped in
    -- gearcheck, so an unchanged situation stays silent.
    pcall(function() require("dlac\\gear\\gearcheck").chatWarn(false); end);
end

-- Learned Max MP merit levels (meritwatch, s2c 0x08C -- the merit menu's own
-- data). Same clamp and persistence as the manual input: 0..10 (merit.cpp
-- cap[75]), manifest mpMerits, autoCommit hot-reload. Returns true when the
-- value CHANGED (meritwatch chats only then); safe headless (autoCommit
-- no-ops logged out, the value still parks in auto.data for the session).
function M.setMpMerits(n)
    n = math.floor(tonumber(n) or 0);
    if n < 0 then n = 0; elseif n > 10 then n = 10; end
    autoLoad();
    if type(auto.data) ~= 'table' then auto.data = {}; end
    if math.floor(tonumber(auto.data.mpMerits) or 0) == n and auto.data.mpMerits ~= nil then
        return false;
    end
    auto.data.mpMerits = n;
    auto._meritBuf = nil;              -- the detail-view input re-seeds itself
    pcall(autoCommit);
    return true;
end

-- The persisted Max MP merit levels, or nil when the manifest holds none yet
-- (fresh character: no zone-in learn and no manual input so far). /dl merits
-- reads this beside meritwatch's session mirror.
function M.getMpMerits()
    autoLoad();
    if type(auto.data) ~= 'table' or auto.data.mpMerits == nil then return nil; end
    return math.floor(tonumber(auto.data.mpMerits) or 0);
end

-- Is the on-disk manifest an older schema than this build writes? (craftwatch
-- uses this to force a regen before the engine reads stale craft ladders --
-- e.g. a fmtver-5 manifest lacks the fmtver-6 head/back skill-up fillers.)
function M.manifestStale()
    autoLoad();
    return (type(auto.data) ~= 'table') or (auto.data.fmtver ~= AUTO_FMT);
end
M.currentFmt = function() return AUTO_FMT; end

-- The Automations tab (its OWN main tab, right of Triggers -- rendered via
-- M.renderTab below): the manifest data + rescan. The ON/OFF
-- switches live per set (Sets tab -> Auto staff / Auto obi).
-- ---------------------------------------------------------------------------
-- Two levels: the LIST (name + KIND + a status that lights
-- up brighter the better the automation is covered; red = nothing applicable)
-- and a DETAIL box per automation (click a row; '< Automations' returns).
-- ---------------------------------------------------------------------------
local GREEN_OWNED = { 0.45, 0.90, 0.45, 1.0 };

-- status ramp, dim -> bright with coverage; 0 = red
local function levelColor(level, maxLevel)
    if level <= 0 then return { 1.00, 0.40, 0.35, 1.0 }; end
    local t = level / maxLevel;
    if t >= 0.999 then return { 0.35, 1.00, 0.45, 1.0 }; end
    if t >= 0.74  then return { 0.60, 0.90, 0.45, 1.0 }; end
    if t >= 0.49  then return { 0.85, 0.80, 0.35, 1.0 }; end
    return { 0.75, 0.62, 0.30, 1.0 };
end

local function owns(name) return ownedRec(name) ~= nil; end
local function usable(name) return usableRec(name, curJob()) ~= nil; end

-- Coverage: Iridescence 1 = any NQ elemental, 2 = any HQ elemental,
-- 3 = Iridal (+1 universal), 4 = any +2 universal. Obi: 1 elemental, 2 universal.
-- Job-aware (usable, not merely owned): the status light answers "what can THIS
-- job's automation actually do" -- an owned Foreshadow +1 must not light WHM up.
local function iridescenceLevel()
    local lv = 0;
    for _, el in ipairs(ELEMENTS8) do
        if usable(STAFF_NQ[el]) then lv = math.max(lv, 1); end
        if usable(STAFF_HQ[el]) then lv = math.max(lv, 2); end
    end
    for _, u in ipairs(UNIVERSAL) do
        if usable(u.name) then lv = math.max(lv, ((u.tier or 1) >= 2) and 4 or 3); end
    end
    return lv;
end
local function obiLevel()
    local lv = 0;
    for _, el in ipairs(ELEMENTS8) do if usable(OBI[el]) then lv = 1; break; end end
    for _, nm in ipairs(OBI_UNIVERSAL) do if usable(nm) then lv = 2; break; end end
    return lv;
end
local function oneirosLevel()
    return usable('Oneiros Grip') and 1 or 0;
end
local IRID_TXT = { [0] = 'nothing applicable', 'NQ staves', 'HQ staves', 'Iridal (+1)', 'universal +2' };
local OBI_TXT  = { [0] = 'nothing applicable', 'elemental obis', 'universal obi' };
local ONEIROS_TXT = { [0] = 'grip not owned', 'Oneiros Grip' };

-- One item row in a detail column: green = owned and equippable by this job,
-- red = owned but this JOB can't wear it (the automation skips it) OR owned
-- but parked in STORAGE (Henrik's ruling 2026-07-19: red, never dim-as-unowned
-- -- you own it, the automation just can't reach it), dim = not owned.
-- synergyNote (optional): mark this item green as SYNERGIZED-INTO-ARTISANS -- you
-- must have owned every guild torque/ring to synth the Artisans piece, so owning
-- Artisans implies you had them all (Henrik). The synergy branch stays ABOVE the
-- stored check on purpose ("keep the backlight"): an Artisans-implied piece keeps
-- its green even while a spare copy sits in storage -- its presence is irrelevant.
local function autoItemLine(name, synergyNote)
    local rec = (deps.lookupByName ~= nil) and deps.lookupByName(name) or nil;
    if type(deps.renderIcon) == 'function' then deps.renderIcon(rec and rec.Id or nil, 18); end
    local owned = owns(name);
    if owned and not usable(name) then
        imgui.TextColored(COL_ERR, esc(name));
        if imgui.IsItemHovered() then
            imgui.SetTooltip(string.format('Owned -- but %s cannot equip it, so the automation skips it on this job.',
                tostring(curJob() or 'this job')));
        end
        return;
    end
    if not owned and synergyNote ~= nil then           -- implied-owned via Artisans synergy
        imgui.TextColored(GREEN_OWNED, esc(name));
        if imgui.IsItemHovered() then imgui.SetTooltip(synergyNote); end
        return;
    end
    if not owned and _ocok and ocache.isStored(rec) then   -- owned somewhere, zero equippable copies
        imgui.TextColored(COL_ERR, esc(name));
        if imgui.IsItemHovered() then
            local where = ocache.whereText(rec);
            imgui.SetTooltip(string.format('Owned -- but parked in %s, so the automation cannot equip it.\nMove it to Inventory/Wardrobe, then Rescan.',
                (where ~= '') and where or 'storage'));
        end
        return;
    end
    imgui.TextColored(owned and GREEN_OWNED or COL_DIM, esc(name));
    -- The standard item card on hover, like every other gear surface.
    if rec ~= nil and imgui.IsItemHovered() and type(deps.itemTooltip) == 'function' then
        pcall(deps.itemTooltip, rec);
    end
end

local function autoColumn(title, names)
    imgui.BeginGroup();
    imgui.TextColored(COL_HEADER, title);
    for _, nm in ipairs(names) do autoItemLine(nm); end
    imgui.EndGroup();
end

-- AutoCraft panel (docs/design/craft-automation.md; layout per Henrik).
-- Names are catalog short names (the API stores them apostrophe-less); KI ids
-- from the server's own enum (scripts/enum/key_item.lua on the public repo).
-- ONE table on purpose: a cohesive craft-panel namespace (and it kept the
-- 200-local budget honest back in triggersui; no reason to explode it now).
local CRAFT_UI = {
    order   = { 'Woodworking', 'Smithing', 'Goldsmithing', 'Clothcraft',
                'Leathercraft', 'Bonecraft', 'Alchemy', 'Cooking' },
    -- Not acquirable on CatsEyeXI (yet) -- hidden from the craft-specific
    -- lists; delete an entry here the day the server makes one obtainable.
    unobtainable = { ['Joiners Ecu'] = true, ['Smythes Ecu'] = true, ['Toreutic Ecu'] = true,
                     ['Plaiters Ecu'] = true, ['Bevelers Ecu'] = true, ['Ossifiers Ecu'] = true,
                     ['Brewers Ecu'] = true, ['Chefs Ecu'] = true },
    torque  = { Woodworking = 'Carvers Torque', Smithing = 'Smithys Torque',
                Goldsmithing = 'Goldsm. Torque', Clothcraft = 'Weavers Torque',
                Leathercraft = 'Tanners Torque', Bonecraft = 'Bone. Torque',
                Alchemy = 'Alchemst. Torque', Cooking = 'Culin. Torque' },
    nqring  = { Woodworking = 'Carpenters Ring', Smithing = 'Smiths Ring',
                Goldsmithing = 'Goldsmiths Ring', Clothcraft = 'Tailors Ring',
                Leathercraft = 'Tanners Ring', Bonecraft = 'Bonecrafters Ring',
                Alchemy = 'Alchemists Ring', Cooking = 'Chefs Ring' },
    -- Guild-point key items per craft (ids from the server's own key_item enum;
    -- ownership read from craftwatch's 0x055 tracker). Desynth (purification/
    -- ensorcellment), recipe-support skills, and the Way-of-the reward path.
    guildKI = {
        Woodworking  = { {1985,'Wood Ensorcellment'},{1986,'Lumberjack'},{1987,'Boltmaker'},{1988,'Way of the Carpenter'} },
        Smithing     = { {1992,'Metal Purification'},{1993,'Metal Ensorcellment'},{1994,'Chainwork'},{1995,'Sheeting'},{1996,'Way of the Blacksmith'} },
        Goldsmithing = { {2000,'Gold Purification'},{2001,'Gold Ensorcellment'},{2002,'Clockmaking'},{2003,'Way of the Goldsmith'} },
        Clothcraft   = { {2008,'Cloth Purification'},{2009,'Cloth Ensorcellment'},{2010,'Spinning'},{2011,'Fletching'},{2012,'Way of the Weaver'} },
        Leathercraft = { {2016,'Leather Purification'},{2017,'Leather Ensorcellment'},{2018,'Tanning'},{2019,'Way of the Tanner'} },
        Bonecraft    = { {2024,'Bone Purification'},{2025,'Bone Ensorcellment'},{2026,'Filing'},{2027,'Way of the Boneworker'} },
        Alchemy      = { {2032,'Anima Synthesis'},{2033,'Alchemic Purification'},{2034,'Alchemic Ensorcellment'},{2035,'Trituration'},{2036,'Concoction'},{2037,'Iatrochemistry'},{2038,'Miasmal Counteragent Recipe'},{2039,'Way of the Alchemist'} },
        Cooking      = { {2040,'Raw Fish Handling'},{2041,'Noodle Kneading'},{2042,'Patissier'},{2043,'Stewpot Mastery'},{2044,'Way of the Culinarian'} },
    },
    universals = { 'Kupo Shield', 'Bonze Cape', 'Shapers Shawl', 'Midrass Helm +1' },
    txt = { [0] = 'nothing applicable', 'craft-specific gear', 'Artisans (NQ)', 'Artisans +1', 'Kupo Shield' },
    selected = 'Alchemy',
    _cache = {},   -- per-craft item lists (full-catalog walk: build on demand, never per frame)
    _tex = {},     -- craft glyph textures (assets/craft/<Craft>.png), false = load failed
};

-- Set-8 craft glyphs (Henrik's pick 2026-07-13: FFXIV class icons, Miner
-- standing in for Bonecraft; PNGs ship in assets/craft/). Loaded once via
-- D3DX (statustimers' pattern); nil -> the caller falls back to item icons.
function CRAFT_UI.texture(cr)
    local t = CRAFT_UI._tex[cr];
    if t ~= nil then return (t ~= false) and t or nil; end
    CRAFT_UI._tex[cr] = false;                           -- one attempt per craft
    pcall(function()
        local ffi = require('ffi');
        local d3d8lib = require('d3d8');
        pcall(ffi.cdef,
            'HRESULT __stdcall D3DXCreateTextureFromFileA(IDirect3DDevice8* pDevice, const char* pSrcFile, IDirect3DTexture8** ppTexture);');
        local dev = d3d8lib.get_device();
        local path = string.format('%saddons\\dlac\\assets\\craft\\%s.png', AshitaCore:GetInstallPath(), cr);
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileA(dev, path, ptr) == 0 then   -- S_OK
            CRAFT_UI._tex[cr] = d3d8lib.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
        end
    end);
    local t2 = CRAFT_UI._tex[cr];
    return (t2 ~= false) and t2 or nil;
end

function CRAFT_UI.level()
    local lv = 0;
    for _, cr in ipairs(CRAFT_UI.order) do
        if owns(CRAFT_UI.torque[cr]) or owns(CRAFT_UI.nqring[cr]) then lv = 1; break; end
    end
    if owns('Artisans Torque') or owns('Artisans Ring') then lv = math.max(lv, 2); end
    if owns('Artisans Torque +1') or owns('Artisans Ring +1') then lv = math.max(lv, 3); end
    if owns('Kupo Shield') then lv = 4; end
    return lv;
end

-- Craft-specific skill+ items for one craft, from the FULL catalog (owned or
-- not -- deps.allEquipList): any item carrying <craft>Skill, excluding the
-- all-8 universals (they live in the matrix above).
function CRAFT_UI.items(cr)
    if CRAFT_UI._cache[cr] ~= nil then return CRAFT_UI._cache[cr]; end
    local out = {};
    pcall(function()
        if type(deps.allEquipList) ~= 'function' then return; end
        for _, rec in ipairs(deps.allEquipList() or {}) do
            local st = rec.Stats;
            -- skip the craft's own torque (already in the matrix) and gear the
            -- server doesn't make obtainable
            if type(st) == 'table' and rec.Name ~= nil and rec.Name ~= CRAFT_UI.torque[cr]
               and not CRAFT_UI.unobtainable[rec.Name] then
                local v = tonumber(st[cr .. 'Skill']) or 0;
                if v > 0 then
                    local nAll = 0;
                    for _, c2 in ipairs(CRAFT_UI.order) do
                        if (tonumber(st[c2 .. 'Skill']) or 0) > 0 then nAll = nAll + 1; end
                    end
                    if nAll < 8 then out[#out + 1] = { name = rec.Name, skill = v }; end
                end
            end
        end
        table.sort(out, function(a, b)
            if a.skill ~= b.skill then return a.skill > b.skill; end
            return a.name < b.name;
        end);
    end);
    CRAFT_UI._cache[cr] = out;
    return out;
end

local MP_GRID = { 'main', 'sub', 'range', 'ammo', 'head', 'neck', 'ear1', 'ear2',
                  'body', 'hands', 'ring1', 'ring2', 'back', 'waist', 'legs', 'feet' };
local MP_EXEMPT = { main = true, sub = true, range = true };

-- Resolve a manifest battery ladder to the best rung wearable at `level`
-- (mirrors the engine's dispatch.mpPick; a legacy fmtver-1 single entry
-- counts as a one-rung ladder).
local function mpPickAt(cands, level)
    if type(cands) ~= 'table' then return nil; end
    if cands.name ~= nil then cands = { cands }; end
    for _, c in ipairs(cands) do
        if type(c) == 'table' and (tonumber(c.level) or 0) <= level then return c; end
    end
    return nil;
end

-- The automation LIST rows -- ONE builder for both surfaces: the Automations
-- tab below and gearui's Teleports quick menu (M.listRows). MaxMP is
-- deliberately NOT listed: still unofficial, pending more field
-- troubleshooting (/dl mode maxmp keeps working; its detail view and the
-- manifest mp data stay intact -- re-add the row here when it graduates).
local function buildAutoRows()
    local rows = {
        { key = 'iridescence', name = 'AutoIridescence', kind = 'slot automation (Main)',
          level = iridescenceLevel(), max = 4, txt = nil },
        { key = 'obi',         name = 'ElementalObi',    kind = 'slot automation (Waist)',
          level = obiLevel(),         max = 2, txt = nil },
        { key = 'oneiros',     name = 'Auto Oneiros Grip', kind = 'slot automation (Sub)',
          level = oneirosLevel(),     max = 1, txt = nil },
        { key = 'craft',       name = 'Auto Craft Set',  kind = 'craft-gear helper (manual pick)',
          level = CRAFT_UI.level(),   max = 4, txt = nil },
        { key = 'helm',        name = 'Auto HELM Set',   kind = 'gathering-gear helper (idle only)',
          level = 0,                  max = 4, txt = nil },
        { key = 'fish',        name = 'Auto Fish Set',   kind = 'fishing-gear helper (idle only)',
          level = 0,                  max = 4, txt = nil },
        -- AutoAmmo is appended LAST on purpose: rows[5]/rows[6] are read by
        -- index below (helm/fish) -- keep every existing index stable. (The
        -- combo branch appends its AutoAcc row before this one; the status
        -- patch below finds this row by KEY, so the index difference is fine.)
        { key = 'ammo',        name = 'AutoAmmo',        kind = 'slot automation (Ammo)',
          level = 0,                  max = 1, txt = nil },
    };
    rows[1].txt = IRID_TXT[rows[1].level];
    rows[2].txt = OBI_TXT[rows[2].level];
    rows[3].txt = ONEIROS_TXT[rows[3].level];
    rows[4].txt = CRAFT_UI.txt[rows[4].level];
    -- HELM coverage lives in helmui (own module; pcall-require, no upvalue).
    pcall(function()
        local helmui = require('dlac\\ui\\helmui');
        rows[5].max = helmui.maxLevel or 4;
        rows[5].level, rows[5].txt = helmui.status(deps);   -- label + HELM+/Surv+ totals
    end);
    -- Fishing coverage lives in fishui (same pattern).
    pcall(function()
        local fishui = require('dlac\\ui\\fishui');
        rows[6].max = fishui.maxLevel or 4;
        rows[6].level, rows[6].txt = fishui.status(deps);
    end);
    -- AutoAmmo status lives in ammoui (same pattern; found by key, not index --
    -- the row sits at a different index on main vs the combo branch).
    pcall(function()
        local ammoui = require('dlac\\ui\\ammoui');
        for _, r in ipairs(rows) do
            if r.key == 'ammo' then
                r.max = ammoui.maxLevel or 1;
                r.level, r.txt = ammoui.status(deps);
                break;
            end
        end
    end);
    return rows;
end

-- gearui's Teleports quick menu renders the SAME list with the SAME status
-- ramp -- one truth for "how covered is this automation", two surfaces.
-- Safe {} before init / logged out.
function M.listRows()
    if deps == nil then return {}; end
    local ok, rows = pcall(buildAutoRows);
    return (ok and type(rows) == 'table') and rows or {};
end
M.levelColor = levelColor;

-- Jump the Automations tab to one automation's DETAIL view (quick menu:
-- left-click = open the panel; gearui shows the window + selects the tab).
-- An unknown key lands on the list view instead of a blank detail.
local DETAIL_KEYS = { iridescence = true, obi = true, oneiros = true, craft = true,
                      helm = true, fish = true, ammo = true, maxmp = true };
function M.openDetail(key)
    auto.view = (DETAIL_KEYS[key] == true) and key or nil;
end

-- Last frame the guild-points section rendered -- a gap >1s means the panel
-- (or the AutoCraft section) just OPENED, which triggers one fresh GP fetch.
-- Declared BEFORE renderAutomations on purpose (hard rule 8: a forward
-- reference to a later local is a silent nil global).
local _gpSectionSeen = nil;

local function renderAutomations()
    autoLoad();
    -- Self-heal: an outdated-schema manifest (older dlac wrote it) regenerates
    -- itself the moment this tab renders -- no manual rescan after updates.
    if auto.data ~= nil and auto.data.fmtver ~= AUTO_FMT and not auto._healed then
        auto._healed = true;
        pcall(autoCommit);
    end

    if auto.view ~= nil then                            -- DETAIL views
        if imgui.Button('< Automations##autoback', { 0, 22 }) then auto.view = nil; end
        if auto.view == 'craft' then
            -- Header controls (Henrik: right side, same row as the back button):
            -- crafting-mode picker + the auto-craft toggle.
            local cwok, cw = pcall(require, 'dlac\\feature\\craftwatch');
            cwok = cwok and type(cw) == 'table';
            -- ONE goal variable (manifest craftGoal): adopt the saved value on
            -- first render, no mode-system round-trip, no chat.
            if CRAFT_UI.goal == nil then
                local saved = (type(auto.data) == 'table') and auto.data.craftGoal or nil;
                CRAFT_UI.goal = (saved == 'nq' or saved == 'skillup') and saved or 'hq';
            end
            local GOALS = {
                { 'hq', 'HQ', 'Prioritizes craft-skill gear to break HQ tiers (then HQ+ rate).' },
                { 'nq', 'NQ', 'Wears the anti-HQ guild rings to guarantee NQ when possible\n(materials you do NOT want HQ\'d).' },
                { 'skillup', 'Skill-Up', 'Prioritizes Synth Skill+ (skill-up rate) items over raw craft skill.' },
            };
            -- On/off switch + "Show craft bar" on the right (the goal now lives
            -- ONLY on the craft bar -- removed here per Henrik). The craft
            -- glyphs below equip on click.
            local winW = imgui.GetWindowWidth();
            local on = cwok and type(cw.isEnabled) == 'function' and cw.isEnabled();
            imgui.SameLine(math.max(180, math.floor(winW / 2) - 118));   -- centered (no right-edge clip)
            imgui.TextColored(COL_DIM, 'Auto craft set:');
            imgui.SameLine(0, 6);
            local cbok, craftbar = pcall(require, 'dlac\\ui\\craftbar');
            if cbok and type(craftbar) == 'table' and type(craftbar.onOffSwitch) == 'function' then
                if craftbar.onOffSwitch(on, 'panel') and cwok then cw.setEnabled(not on); end
            else
                if imgui.Button((on and 'ON' or 'OFF') .. '##craftpanelonoff', { 46, 22 }) and cwok then cw.setEnabled(not on); end
            end
            imgui.SameLine(0, 10);
            local barOn = cwok and (cw.barVisible == true);
            if imgui.Button((barOn and 'Hide bar' or 'Show bar') .. '##craftbartoggle', { 78, 22 }) and cwok then
                cw.barVisible = not barOn;
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('The floating craft bar: on/off, the craft glyphs, and the goal.\nAlso /dl craft bar.');
            end
        end
        imgui.Spacing();
        local availW = imgui.GetContentRegionAvail();
        if type(availW) ~= 'number' or availW < 400 then availW = 800; end

        if auto.view == 'iridescence' then
            imgui.TextColored(COL_HEADER, 'AutoIridescence');
            imgui.SameLine(0, 10); imgui.TextColored(COL_DIM, 'slot automation -- dlac:AutoIridescence in a set\'s Main slot');
            imgui.Spacing();
            local nq, hq, ir1, ir2 = {}, {}, {}, {};
            for _, el in ipairs(ELEMENTS8) do nq[#nq + 1] = STAFF_NQ[el]; hq[#hq + 1] = STAFF_HQ[el]; end
            for _, u in ipairs(UNIVERSAL) do
                if (u.tier or 1) >= 2 then ir2[#ir2 + 1] = u.name; else ir1[#ir1 + 1] = u.name; end
            end
            local colW = math.max(185, math.floor(availW / 4));
            autoColumn('Elemental NQ', nq);        imgui.SameLine(colW);
            autoColumn('Elemental HQ', hq);        imgui.SameLine(colW * 2);
            autoColumn('Iridescence +1', ir1);     imgui.SameLine(colW * 3);
            autoColumn('Iridescence +2', ir2);
            imgui.Spacing();
            imgui.TextColored(COL_DIM, 'Specific +2 weapons are preferred; Chatoyant is the +2 fallback. Green = owned.');
        elseif auto.view == 'obi' then
            imgui.TextColored(COL_HEADER, 'ElementalObi');
            imgui.SameLine(0, 10); imgui.TextColored(COL_DIM, 'slot automation -- dlac:ElementalObi in a set\'s Waist slot');
            imgui.Spacing();
            local elos = {};
            for _, el in ipairs(ELEMENTS8) do elos[#elos + 1] = OBI[el]; end
            local colW = math.max(200, math.floor(availW / 2));
            autoColumn('Elemental Obis', elos);    imgui.SameLine(colW);
            autoColumn('Universal Obi', OBI_UNIVERSAL);
            imgui.Spacing();
            imgui.TextColored(COL_DIM, 'Fires only when the day/weather bonus is positive. Green = owned.');
        elseif auto.view == 'craft' then
            imgui.TextColored(COL_HEADER, 'Auto Craft Set');
            imgui.SameLine(0, 10);
            imgui.TextColored(COL_DIM, 'pick a craft + goal (here or the floating bar) -> equips your best PIECES for it. It never crafts for you.');
            imgui.Spacing();
            -- Ownership matrix (Henrik's layout): NQ|HQ pair, rule, craft-
            -- specific column -- for torques and rings; universals third.
            local colW = math.max(240, math.floor(availW / 3));
            -- Owning an Artisans piece implies you owned every guild torque/ring
            -- (they synergize into it), so mark the rest green (Henrik).
            local haveArtT = owns('Artisans Torque') or owns('Artisans Torque +1');
            local haveArtR = owns('Artisans Ring') or owns('Artisans Ring +1');
            local synT = 'Green via synergy: you own an Artisans Torque, which requires\nevery guild torque -- so you had this one.';
            local synR = 'Green via synergy: you own an Artisans Ring, which requires\nevery guild ring -- so you had this one.';
            imgui.BeginGroup();
            imgui.TextColored(COL_HEADER, 'Torques');
            autoItemLine('Artisans Torque');
            autoItemLine('Artisans Torque +1');
            imgui.TextColored(COL_DIM, '- - - - - - - -');
            for _, cr in ipairs(CRAFT_UI.order) do autoItemLine(CRAFT_UI.torque[cr], haveArtT and synT or nil); end
            imgui.EndGroup();
            imgui.SameLine(colW);
            imgui.BeginGroup();
            imgui.TextColored(COL_HEADER, 'Rings');
            autoItemLine('Artisans Ring');
            autoItemLine('Artisans Ring +1');
            imgui.TextColored(COL_DIM, '- - - - - - - -');
            for _, cr in ipairs(CRAFT_UI.order) do autoItemLine(CRAFT_UI.nqring[cr], haveArtR and synR or nil); end
            imgui.EndGroup();
            imgui.SameLine(colW * 2);
            autoColumn('Universals', CRAFT_UI.universals);
            imgui.Spacing();
            imgui.Separator();
            imgui.Spacing();
            -- Craft selector: icons only, one row left-to-right (gold box =
            -- selected, the slot-grid pattern). Item icons stand in for the
            -- synth-skill glyphs until PNG assets land; the tooltip names the
            -- craft and guild for anyone unsure.
            -- Panel icons are ONLY a section switch (Henrik): clicking one just
            -- changes which craft's items are shown below. No label -- centered,
            -- self-explanatory (8 icons * 32 + 7 gaps * 14 = 354 wide).
            local rowW = 8 * 32 + 7 * 14;
            local indent = math.max(0, math.floor((availW - rowW) / 2));
            if indent > 0 then imgui.Dummy({ 0, 0 }); imgui.SameLine(indent); end
            for i, cr in ipairs(CRAFT_UI.order) do
                local sel = (CRAFT_UI.selected == cr);
                local tex = CRAFT_UI.texture(cr);
                local drew = false;
                if tex ~= nil then
                    local okT = pcall(function()
                        local ffi = require('ffi');
                        imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { 32, 32 },
                            { 0, 0 }, { 1, 1 }, sel and { 1, 1, 1, 1 } or { 1, 1, 1, 0.45 });
                    end);
                    if not okT then
                        okT = pcall(function()
                            local ffi = require('ffi');
                            imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { 32, 32 });
                        end);
                    end
                    drew = okT;
                end
                if not drew and type(deps.renderIcon) == 'function' then   -- glyph missing: item icon
                    local rec = (deps.lookupByName ~= nil) and deps.lookupByName(CRAFT_UI.torque[cr]) or nil;
                    deps.renderIcon(rec and rec.Id or nil, 32);
                end
                if imgui.IsItemClicked() then CRAFT_UI.selected = cr; end   -- view only
                if imgui.IsItemHovered() then imgui.SetTooltip(cr .. '  -- show this craft\'s items (set the active craft on the craft bar)'); end
                if i < #CRAFT_UI.order then imgui.SameLine(0, 14); end
            end
            imgui.Spacing();
            local selCr = CRAFT_UI.selected;
            -- Guild key items for this craft (ownership from the 0x055 tracker).
            local cw2, kiSynced = nil, false;
            pcall(function()
                cw2 = require('dlac\\feature\\craftwatch');
                kiSynced = (type(cw2.kiReady) == 'function') and cw2.kiReady() or ((cw2 and cw2.kiBlocksSeen or 0) > 0);
            end);
            -- Guild points for this craft (0x113-tracked). EVERY entry into
            -- this view (section idle >1s = you just came in) asks the server
            -- for a fresh copy -- the c2s 0x10F self-request, turn-in VERIFIED
            -- 2026-07-13 -- so a GP hand-in shows here without zoning. force
            -- = skip the 5s debounce (Henrik: refresh on each visit); its 1s
            -- floor still dedupes flicker. While the view stays open the gap
            -- never exceeds a frame, so it can't re-request.
            local gp, gpReady = nil, false;
            if cw2 ~= nil then
                if _gpSectionSeen == nil or (os.clock() - _gpSectionSeen) > 1.0 then
                    pcall(function() cw2.requestGuildPoints(true); end);
                end
                _gpSectionSeen = os.clock();
                pcall(function() gpReady = (type(cw2.gpReady) == 'function') and cw2.gpReady(); end);
                pcall(function() gp = cw2.guildPointsFor(selCr); end);
            end
            imgui.TextColored(COL_HEADER, 'Guild Points: ');
            imgui.SameLine(0, 4);
            if gpReady and gp ~= nil then
                imgui.TextColored({ 0.95, 0.85, 0.45, 1.0 }, tostring(gp));
            else
                imgui.TextColored(COL_DIM, gpReady and '0' or '(open the currency menu / zone once)');
            end
            imgui.Spacing();
            imgui.TextColored(COL_HEADER, 'Guild key items:');
            if not kiSynced then imgui.SameLine(0, 6); imgui.TextColored(COL_DIM, '(zone once to sync)'); end
            local kil = CRAFT_UI.guildKI[selCr] or {};
            for i, ki in ipairs(kil) do
                local has = false;
                if cw2 ~= nil then pcall(function() has = cw2.hasKeyItem(ki[1]) == true; end); end
                local col = (not kiSynced) and COL_DIM or (has and GREEN_OWNED or COL_ERR);
                local mark = (not kiSynced) and '?' or (has and '+' or 'x');
                imgui.TextColored(col, '[' .. mark .. '] ' .. ki[2]);
                -- two per row; +30% column width so longer names never overlap
                if i % 2 == 1 and i < #kil then imgui.SameLine(300); end
            end
            imgui.Spacing();
            local its = CRAFT_UI.items(selCr);
            if #its == 0 then
                imgui.TextColored(COL_DIM, 'No ' .. selCr .. '-specific skill+ items in the catalog.');
            else
                for _, it in ipairs(its) do
                    autoItemLine(it.name);
                    imgui.SameLine(0, 8);
                    imgui.TextColored(COL_DIM, string.format('(%s +%d)', selCr, it.skill));
                end
            end
            imgui.Spacing();
            imgui.TextColored(COL_DIM, 'Green = owned; red = owned but this job can\'t wear it; dim = not owned.');
        elseif auto.view == 'helm' then
            -- The whole panel lives in ui/helmui.lua (predates the extraction;
            -- a render-time pcall-require also dodges any load-order knot).
            local hok, helmui = pcall(require, 'dlac\\ui\\helmui');
            if hok and type(helmui) == 'table' and type(helmui.render) == 'function' then
                pcall(helmui.render, deps, availW);
            else
                imgui.TextColored(COL_ERR, 'helmui failed to load.');
            end
        elseif auto.view == 'fish' then
            -- Same pattern: the whole panel lives in ui/fishui.lua.
            local fok, fishui = pcall(require, 'dlac\\ui\\fishui');
            if fok and type(fishui) == 'table' and type(fishui.render) == 'function' then
                pcall(fishui.render, deps, availW);
            else
                imgui.TextColored(COL_ERR, 'fishui failed to load.');
            end
        elseif auto.view == 'ammo' then
            -- Same pattern: the whole panel lives in ui/ammoui.lua.
            local aok, ammoui = pcall(require, 'dlac\\ui\\ammoui');
            if aok and type(ammoui) == 'table' and type(ammoui.render) == 'function' then
                pcall(ammoui.render, deps, availW);
            else
                imgui.TextColored(COL_ERR, 'ammoui failed to load.');
            end
        elseif auto.view == 'oneiros' then
            imgui.TextColored(COL_HEADER, 'Auto Oneiros Grip');
            imgui.SameLine(0, 10); imgui.TextColored(COL_DIM, 'slot automation -- dlac:AutoOneiros in a set\'s Sub slot (needs a 2H main)');
            imgui.Spacing();
            autoItemLine('Oneiros Grip');
            imgui.Spacing();
            -- Merit input: merit allocations only cross the wire when the merit
            -- menu opens, so the client cannot read them passively -- this ONE
            -- number is yours to keep current. Persisted in the manifest and
            -- carried through every rescan.
            local saved = (type(auto.data) == 'table') and math.floor(tonumber(auto.data.mpMerits) or 0) or 0;
            if auto._meritBuf == nil then auto._meritBuf = { saved }; end
            imgui.PushItemWidth(110);
            if imgui.InputInt('Max MP merits##onmerits', auto._meritBuf) then
                local v = math.floor(tonumber(auto._meritBuf[1]) or 0);
                if v < 0 then v = 0; elseif v > 10 then v = 10; end
                auto._meritBuf[1] = v;
                if type(auto.data) ~= 'table' then auto.data = {}; end
                if auto.data.mpMerits ~= v then
                    auto.data.mpMerits = v;
                    pcall(autoCommit);       -- rewrite + hot-reload: the engine re-aims now
                end
            end
            imgui.PopItemWidth();
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Your Max MP merit LEVELS (menu: Merit Points > HP-MP). 10 MP each, 10\nusable at Lv75 (the menu\'s own cap). They count toward the latent\'s base\npool, so an unset value aims the threshold low (the grip stays off longer).\nTeaches itself: the server pushes the merit list at EVERY zone-in (and on\neach merit spend), so this syncs on its own -- no menu visit needed.');
            end
            imgui.SameLine(0, 10);
            imgui.TextColored(COL_DIM, 'auto-syncs at zone-in and on merit spends');
            imgui.Spacing();
            -- The live aim: base pool -> threshold -> where your MP sits now.
            local meritLv = (type(auto.data) == 'table') and math.floor(tonumber(auto.data.mpMerits) or 0) or 0;
            if meritLv < 0 then meritLv = 0; elseif meritLv > 10 then meritLv = 10; end   -- pre-clamp manifests
            local native = (hasNmp and type(nmp.self) == 'function') and nmp.self(0) or nil;
            if native == nil then
                imgui.TextColored(COL_DIM, 'Native MP unreadable (log in / zone once).');
            else
                local base = native + meritLv * 10;
                local thr  = math.floor(base * 50 / 100);   -- 50 = live truth (field-pinned); repo sql says 75
                imgui.Text(string.format('Base pool: %d native + %d merit = %d', native, meritLv * 10, base));
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Native = the server\'s race/job/sub formula for your CURRENT race, jobs\nand levels (gear never counts). Recomputed live -- job change, subjob\nchange and level sync re-aim the threshold by themselves.');
                end
                imgui.TextColored(COL_HEADER, string.format('Refresh +1 is live at MP <= %d', thr));
                local cur = nil;
                pcall(function() cur = tonumber(AshitaCore:GetMemoryManager():GetParty():GetMemberMP(0)); end);
                if cur ~= nil then
                    local active = (cur <= thr);
                    imgui.TextColored(active and GREEN_OWNED or COL_DIM,
                        string.format('Right now: MP %d -- %s', cur, active and 'ACTIVE (the grip equips)' or 'inactive (the Sub fallback is worn)'));
                end
            end
            imgui.Spacing();
            imgui.TextColored(COL_DIM, 'The latent compares your CURRENT MP against 50%% of the BASE pool -- the\nrace/job/sub formula plus merits; gear MP never moves the threshold. (50 is\nthe FIELD-MEASURED live rule -- tick break 357/358 on base 714; the public\nrepo claims 75. docs/server-questions.md #6.) Your NAKED on-screen max can\nread higher than the base: Max MP Boost traits (/SCH30+) and the grip\'s own\nMP+5 sit in the DISPLAYED max only -- do not raise the merit number to make\nBase match the screen. Add the dlac: entry to a set\'s Sub list via + Add;\nthe other items in the list are the fallback.');
        elseif auto.view == 'maxmp' then
            imgui.TextColored(COL_HEADER, 'MaxMP');
            imgui.SameLine(0, 10); imgui.TextColored(COL_DIM, 'set automation -- /dl mode maxmp; wears batteries at a full pool, releases as spent');
            imgui.Spacing();
            local mb = (type(auto.data) == 'table' and type(auto.data.mpBest) == 'table') and auto.data.mpBest or {};
            local lvl = mainLevel();
            local total = 0;
            for i, sl in ipairs(MP_GRID) do
                local c = mpPickAt(mb[sl], lvl);
                imgui.BeginChild('##mpb_' .. sl, { 40, 40 }, true, ImGuiWindowFlags_NoScrollbar or 0);
                if c ~= nil and type(deps.renderIcon) == 'function' then
                    local rec = (deps.lookupByName ~= nil) and deps.lookupByName(c.name) or nil;
                    deps.renderIcon(rec and rec.Id or nil, 30);
                end
                imgui.EndChild();
                if imgui.IsItemHovered() then
                    if MP_EXEMPT[sl] then
                        imgui.SetTooltip(sl .. ': weapons are exempt (TP preservation).');
                    elseif c ~= nil then
                        imgui.SetTooltip(string.format('%s: %s  (MP +%d)', sl, c.name, c.mp or 0));
                    else
                        imgui.SetTooltip(sl .. ': no MP gear owned for this slot.');
                    end
                end
                if c ~= nil then total = total + (c.mp or 0); end
                if i % 4 ~= 0 then imgui.SameLine(0, 4); end
            end
            imgui.Spacing();
            imgui.TextColored((total > 0) and GREEN_OWNED or COL_ERR,
                string.format('Best case: +%d Max MP', total));
            imgui.TextColored(COL_DIM, 'Battery data maintains itself (login, job change, any inventory change).');
        end
        return;
    end

    -- LIST view: the automation table FIRST, no explanations above it (field
    -- request) -- how-it-works lives in the tooltips and detail views. The
    -- rescan shove + status sit small under the table. Rows come from the
    -- shared builder (buildAutoRows -- gearui's Teleports quick menu shows
    -- the same list).
    local rows = buildAutoRows();
    -- Column headers, same fixed offsets as the rows.
    -- Offsets widened 2026-07-17 (field report: the HELM row's Kind ran into
    -- Status): Name 190->215, Kind 470->580 (~30% more -- the themed font
    -- runs ~9.5px/char and "gathering-gear helper (idle only)" is 33 chars).
    imgui.Dummy({ 0, 0 });
    imgui.SameLine(8);   imgui.TextColored(COL_HEADER, 'Name');
    imgui.SameLine(215); imgui.TextColored(COL_HEADER, 'Kind');
    imgui.SameLine(580); imgui.TextColored(COL_HEADER, 'Status');
    imgui.Separator();
    for _, r in ipairs(rows) do
        local col = levelColor(r.level, r.max);
        imgui.PushID('autorow_' .. r.key);
        if imgui.Selectable('##sel', false, ImGuiSelectableFlags_None, { 0, 20 }) then auto.view = r.key; end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Click for details. Slot automations go INSIDE a set (add the dlac: entry\nto the slot via + Add); set automations apply everywhere via their mode.');
        end
        imgui.SameLine(8);  imgui.TextColored(col, r.name);
        imgui.SameLine(215); imgui.TextColored(COL_DIM, r.kind);
        imgui.SameLine(580); imgui.TextColored(col, r.txt or '');
        imgui.PopID();
    end
    -- No rescan button, no status line: the scan runs itself (login, job
    -- change, any inventory change, schema self-heal) and each row already
    -- reports its own state -- extra chrome earned nothing (field request).
end

-- The Automations MAIN-tab entry point: gearui registers the tab and calls this.
-- Same guard ladder as triggersui.render; login gate via autoPath (the manifest
-- is per character -- nothing to show or write while logged out).
function M.renderTab(job, level)
    if not hasImgui then return; end
    if deps == nil then
        imgui.TextColored(COL_ERR, 'Automations tab not initialized (gearui deps missing).');
        return;
    end
    if autoPath() == nil then
        imgui.TextColored(COL_DIM, 'Log in to manage automations.');
        return;
    end
    pcall(renderAutomations);
end

return M;
