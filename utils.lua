local gear = require("dlac\\gear");

-- utils is the lean, profile-side rebuild engine (BuildDynamicSets + level scaling),
-- required by your <JOB>.lua in HandleDefault. The GUI / import / optimizer / setmanager
-- modules are loaded by the dlac ADDON (dlac.lua), NOT here -- so requiring utils from a
-- profile never double-loads the GUI when the dlac addon is also running.

-- (gcinclude is a LuaAshitacast-side config include, not part of dlac. Profiles that
-- use it load it from their own LAC setup -- dlac neither bundles nor loads it.)

staticMainLevel = 0; -- This will override your in-game level for testing purposes
staticSubLevel = 0; -- This will override your in-game sub job level for testing purposes

local M = {}

-- Colored [dlac] chat output (chatfmt): the shadowed `print` re-heads
-- "[dlac] ..."-prefixed lines with the colored header; plain when unavailable.
local _cfmtok, _cfmt = pcall(require, 'dlac\\chatfmt');
local print = (_cfmtok and type(_cfmt) == 'table' and type(_cfmt.print) == 'function') and _cfmt.print or print;

-- Re-export the gear inventory so a migrated profile needs only one require:
--   local utils = require("dlac\\utils"); local gear = utils.gear;
M.gear = gear;

-- The trigger dispatch engine (docs/design/trigger-system.md). Profiles call
-- utils.dispatch('<Handler>') as the LAST line of each Handle* function; the engine
-- reads <char>\dlac\triggers\<JOB>.lua and equips every matching rule. Guarded so a
-- missing/broken dispatch.lua degrades to a no-op and can never break profile loading.
local _dok, _dispatch = pcall(require, "dlac\\dispatch");
if _dok and type(_dispatch) == 'table' and type(_dispatch.dispatch) == 'function' then
    M.dispatchModule = _dispatch;   -- direct access (modes, traces) for advanced use
    M.dispatch = function(event) pcall(_dispatch.dispatch, event); end
    -- THE central equip-eligibility check lives in dispatch (loadable from both
    -- Lua states); re-exported here so profiles and addon modules share ONE rule.
    M.jobCanEquip = _dispatch.jobCanEquip;
    M.canWear     = _dispatch.canWear;
else
    M.dispatch = function() end;
end


-- Remove all your gear, each key value pair represent what your base MP is without gear with that SJ.
-- Oneiros Grip unfortunately only activates based off of your base MP, which differ depending on SJ.
-- For example, if you're a Hume WHM75/BLM37, my base MP is 752.
-- This would make Oneiros Grip latent effect acivate AT half (376) or lower MP.

BaseMPLevel75 = {
    
}

function M.ChecDayAndWeatherBonus(spell)
    local weather = gData.GetWeather();
    local day = gData.GetDay();

    local weatherBonus = false;
    local dayBonus = false;

    if weather == spell.Element or weather == gData.GetElementalOpposition(spell.Element) then
        weatherBonus = true;
    end

    if day == spell.Element or day == gData.GetElementalOpposition(spell.Element) then
        dayBonus = true;
    end

    return dayBonus, weatherBonus;
end

function M.determineLevels()
    local player = gData.GetPlayer();
    local mainLevel = 0;
    local subLevel = 0;

    if staticMainLevel ~= nil and staticMainLevel > 0 then
        mainLevel = staticMainLevel;
    else
        mainLevel = player.MainJobSync;
    end

    if staticSubLevel ~= nil and staticSubLevel > 0 then
        subLevel = staticSubLevel;
    else
        subLevel = player.SubJobSync;
    end

    return mainLevel, subLevel;
end

function M.checkRebuildNeeded(player, lastLevel, lastSJLevel, lastSJ)
    currentLevel, currentSJLevel = M.determineLevels();

    local currentSJ = player.SubJob;
    local shouldRebuild = false;

    if lastLevel ~= currentLevel or lastSJLevel ~= currentSJLevel or lastSJ ~= currentSJ then
        shouldRebuild = true;
    end
    
    -- Return everything needed to update the main file's state
    return shouldRebuild, currentLevel, currentSJLevel, currentSJ;
end

-- If you want a single wrapper function, you can create M.rebuildSetsIfNeeded:
function M.rebuildSetsIfNeeded(player, sets, lastLevel, lastSJLevel, lastSJ)
    -- This function encapsulates the rebuild check and the building logic
    local shouldRebuild, newLevel, newSJLevel, newSJ = M.checkRebuildNeeded(player, lastLevel, lastSJLevel, lastSJ);
    
    if shouldRebuild then
        sets = M.BuildDynamicSets(sets);
    end
    
    -- Return the updated data (sets, and the new 'last known' state)
    return sets, newLevel, newSJLevel, newSJ;
end

-- === Simplified one-call API (recommended for new / migrating profiles) ===
-- Module-level rebuild state, so a profile no longer needs its own local
-- lastKnownLevel / lastKnownSJLevel / lastKnownSJ bookkeeping. utils is required
-- once and cached, so this persists across HandleDefault calls.
local _lastLevel, _lastSJLevel, _lastSJ = 0, 0, nil;

-- Call `sets = utils.rebuildSets(sets)` at the top of HandleDefault. Fetches the
-- player and manages rebuild state internally; returns the (possibly rebuilt) sets.
local _lastModesRev = nil;
function M.rebuildSets(sets)
    local player = gData.GetPlayer();
    if player == nil then return sets; end
    local shouldRebuild, newLevel, newSJLevel, newSJ = M.checkRebuildNeeded(player, _lastLevel, _lastSJLevel, _lastSJ);
    -- Mode flips must re-flatten too: mode-gated entries pick differently, and
    -- level/sub-job alone would leave the flattened sets stale forever.
    local mrev = (M.dispatchModule ~= nil) and M.dispatchModule.modesRev or nil;
    if mrev ~= nil and mrev ~= _lastModesRev then
        shouldRebuild = true;
        _lastModesRev = mrev;
    end
    if shouldRebuild then
        sets = M.BuildDynamicSets(sets);
        _lastLevel, _lastSJLevel, _lastSJ = newLevel, newSJLevel, newSJ;
    end
    return sets;
end

function M.isDualWieldAvailable(mj, mjLevel, sj, sjLevel)
    -- Plan A: ask the game whether the character HAS the Dual Wield trait right now.
    -- The CatsEyeXI server computes each character's trait list from its own
    -- sql/traits.sql (main job + sub job, and BLU via blue-magic trait sets) and
    -- ships that bitmask to the client in packet 0x0AC (GP_SERV_COMMAND_COMMAND_DATA
    -- copies m_TraitList into CommandDataTbl.Traits alongside WeaponSkills /
    -- JobAbilities / PetAbilities). Ashita's Player:HasAbility() indexes that same
    -- command table, where job traits start at id 1536 (0x600) and Dual Wield is
    -- id 1554 = 1536 + trait_id 18 (server repo: documentation/player_abilities.txt
    -- "1554  Dual Wield  Job Trait"; sql/traits.sql keeps every Dual Wield tier on
    -- trait_id 18, so one bit covers all tiers). Trusting this bit means CatsEyeXI's
    -- custom job balance can never desync us -- e.g. their THF gets Dual Wield at
    -- level 83 (Abyssea-tagged), so the old hardcoded THF>=20 row below over-promised
    -- on this server.
    local ok, hasDW = pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer();
        if p == nil then return nil; end
        local job = p:GetMainJob();
        if type(job) ~= 'number' or job < 1 or job > 22 then
            return nil; -- char select / zoning: player block not populated yet
        end
        return p:HasAbility(1554) == true; -- 1554 = Dual Wield trait (any tier)
    end);
    if ok and type(hasDW) == 'boolean' then
        return hasDW;
    end

    -- Fallback (memory unavailable or player not ready): legacy job/level table.
    local THFDWLevel = 20;
    local NINDWLevel = 10;
    local DNCDWLevel = 20;

    if (mj == "THF" and mjLevel >= THFDWLevel) or (sj == "THF" and sjLevel >= THFDWLevel) then
        return true;
    elseif (mj == "NIN" and mjLevel >= NINDWLevel) or (sj == "NIN" and sjLevel >= NINDWLevel) then
        return true;
    elseif (mj == "DNC" and mjLevel >= DNCDWLevel) or (sj == "DNC" and sjLevel >= DNCDWLevel) then
        return true;
    end
    return false;
end

-- Grip vs shield for a Sub-only record. Hand-authored gear.lua says Type="Grip" /
-- "Shield"; the catalog labels BOTH just Type="Sub", so those classify by name --
-- every grip/strap is named "* Grip" / "* Strap". nil = not a Sub-only item.
function M.classifySub(rec)
    local t = rec.Type;
    if t == 'Grip' or t == 'Shield' then return t; end
    if t == 'Sub' then
        local n = string.lower(tostring(rec.Name or ''));
        if n:find('grip', 1, true) ~= nil or n:find('strap', 1, true) ~= nil then return 'Grip'; end
        return 'Shield';
    end
    return nil;
end

-- Sub-slot pairing rule, shared by the rebuild engine and the GUI set builder.
--
-- >>> HARD RULE (Henrik, 2026-07-12 -- reverted THREE times before this; do not
-- >>> "fix" it back. See docs/adr/0006 addendum + HANDOFF hard rule 6.)
-- ctx.building == true means COMPOSING A SET -- a plan, not an equip. While
-- building, the Sub list must NEVER adapt to the Main pick, the Dual Wield
-- trait, or any other live game state: every Sub-capable item (shield, grip,
-- ONE-HANDED weapon) is offered, always -- even with a 2H main planned, even
-- with NO Main planned, even without DW. Sets feed TRIGGERS (e.g. a dual-wield
-- set for when DW is up); gating the builder on today's main/DW makes exactly
-- those sets impossible to compose. The only building-time exclusions are
-- physical impossibilities: a 2H weapon never fits the Sub slot, and a
-- same-name off-hand needs a provable second copy (a copy count >= 2 --
-- that's item identity, not game state).
--
-- Equip-time (ctx.building falsy) keeps the strict pairing: 2H main -> Grip
-- only; 1H main -> Shield always, a 1H weapon only while ctx.dw (the engine
-- makes this call per cast; the list's shield is the fallback).
function M.subSlotAllowed(subRec, mainRec, ctx)
    if type(subRec) ~= 'table' then return false; end
    ctx = ctx or {};
    -- Same-name second copy: best of ctx.copies (live bag count -- the GUI
    -- passes ownedcache) and the record's scanned Count (the gear.lua fact,
    -- and the ONLY source in the LAC state, which has no bag scanner).
    -- Replaces the legacy InBothHands flag (removed 2026-07-13).
    local function twoCopies()
        local n = tonumber(ctx.copies) or 0;
        local fc = tonumber(subRec.Count) or 0;
        return ((fc > n) and fc or n) >= 2;
    end
    local kind = M.classifySub(subRec);
    if ctx.building == true then
        if kind ~= nil then return true; end               -- shield / grip: always offered
        if subRec.OneHanded ~= true then return false; end -- 2H or metadata-less: never an off-hand
        if type(mainRec) == 'table' and subRec.Name == mainRec.Name then
            return twoCopies();
        end
        return true;                                        -- 1H weapon: ALWAYS offered
    end
    if type(mainRec) ~= 'table' then return false; end
    if mainRec.OneHanded == false then
        return kind == 'Grip';
    end
    if mainRec.OneHanded ~= true then return false; end
    if kind == 'Shield' then return true; end
    if kind ~= nil then return false; end                 -- a grip on a 1H main
    if subRec.OneHanded ~= true then return false; end    -- 2H / metadata-less: no off-hand
    if ctx.dw ~= true then return false; end
    if subRec.Name == mainRec.Name then
        return twoCopies();
    end
    return true;
end

-- Resolve a set-entry NAME to its gear.lua record. Exact match first, then
-- case-insensitive: hand-written / static-migrated sets say "Solid wand" while
-- the client names in gear.lua read "Solid Wand" -- a rebuild must not fail on
-- caps. The lowercase index is built lazily once per Lua state (gear.lua is
-- static until a LAC reload rebuilds this state anyway; tests use _resetNameIndex).
local _lcIndex = nil;
local function resolveGearName(name)
    local hit = gear.NameToObject[name];
    if hit ~= nil then return hit; end
    if _lcIndex == nil then
        _lcIndex = {};
        for k, v in pairs(gear.NameToObject) do
            if type(k) == 'string' then _lcIndex[string.lower(k)] = v; end
        end
    end
    return _lcIndex[string.lower(name)];
end
function M._resetNameIndex() _lcIndex = nil; end
M.resolveGearName = resolveGearName;   -- the house name->record resolver (dispatch's
                                       -- craft Sub guard pairs records through it)

-- One warning per unique missing name per state: a commit hot-swap rebuilds
-- EVERY dynamic set, and per-occurrence prints flooded the chat log (field
-- case: 30+ lines from three migrated SMN sets).
local _warnedMissing = {};
local function warnMissingGear(name)
    if _warnedMissing[name] then return; end
    _warnedMissing[name] = true;
    print('[dlac] set entry "' .. tostring(name) .. '" is not in the gear table -- typo, or not yet indexed (/dl sync).');
end

function M.BuildDynamicSets(sets)
    local player = gData.GetPlayer();
    
    -- Safety check for player data
    if not player then return sets end

    mjLevel, sjLevel = M.determineLevels();

    local mj = player.MainJob;
    local sj = player.SubJob;
    
    local isDW = M.isDualWieldAvailable(mj, mjLevel, sj, sjLevel);
    
    -- Iterate over each dynamic set
    for setName, setTable in pairs(sets.Dynamic) do
        local currentSet = {};
        local currentMain = nil; -- Nil for proper checks
        
        -- Iterate over each gear slot within the set. Main MUST resolve before Sub
        -- (the pairing rule reads currentMain), and pairs() order is undefined -- so
        -- walk Main first, then the rest.
        local slotNames = {};
        if setTable.Main ~= nil then slotNames[#slotNames + 1] = 'Main'; end
        for slotName in pairs(setTable) do
            if slotName ~= 'Main' then slotNames[#slotNames + 1] = slotName; end
        end
        for _, slotName in ipairs(slotNames) do
            local slotTable = setTable[slotName];
            local slotRank, slotLevel = -1, -1;   -- winning entry's tier + item level
            local slotVirtual = nil;
            local slotAcc = nil;                  -- winning AutoAcc candidate { name, prio, acc }
            local slotAccRank, slotAccLevel = -1, -1;

            -- Evaluate one list entry; maybe promote it to the slot's pick. wantMode
            -- selects the pass: true = only entries whose `mode` condition is ACTIVE
            -- right now; false = only unconditional entries. An active mode-gated
            -- entry therefore OUTRANKS every unconditional one (specific beats
            -- generic, same philosophy as trigger specificity); an INACTIVE one is
            -- excluded outright.
            -- wantAuto splits the POOL: entries typed as a Type automation
            -- (autoType = 'AutoAcc') compete only among themselves for the slot's
            -- AutoAcc pick; everything else is the normal pick -- which becomes
            -- the AutoAcc marker's fallback (worn while the piece is released).
            local function evalEntry(gearVar, wantMode, wantAuto)
                -- Virtual slot entry ('dlac:AutoStaff' / 'dlac:AutoObi'), bare OR
                -- wrapped -- the Sets tab commits a GATED virtual in wrapper form
                -- ({ gear = 'dlac:AutoIridescence', mode = 'Weapon:Caster' }). The
                -- dispatch engine resolves it at equip time (ADR 0004). A wrapped
                -- virtual honours its mode gate like any entry (field case: only
                -- bare strings were recognised, so WHM's Caster-gated marker
                -- flattened to NOTHING). Remember it, but KEEP evaluating the
                -- slot's real items -- the normal best-by-level pick becomes the
                -- FALLBACK when the virtual can't resolve (e.g. every iridescence
                -- weapon / obi is above your current level).
                local virt, vmode = nil, nil;
                if type(gearVar) == "string" then
                    virt = gearVar;
                elseif type(gearVar) == "table" and type(gearVar.gear) == "string" then
                    virt, vmode = gearVar.gear, gearVar.mode;
                end
                if virt ~= nil and string.lower(string.sub(virt, 1, 5)) == "dlac:" then
                    if vmode ~= nil then
                        if not wantMode then return; end   -- gated: the mode pass only
                        local dsp = M.dispatchModule;
                        if dsp == nil or type(dsp.modeActive) ~= 'function'
                           or dsp.modeActive(vmode) ~= true then return; end
                    end
                    -- A marker is a ladder RUNG at the level of the lowest item
                    -- it can resolve to (dispatch.virtualMinLevel), not a Lv0
                    -- wildcard: below that level it is SKIPPED, so the slot's
                    -- real best-by-level pick owns the flattened set outright
                    -- (Henrik's field case: a leveling WHM's set showed
                    -- dlac:AutoIridescence while actually wearing Pilgrim's
                    -- Wand -- the marker is a Lv51 rung, his Chatoyant Staff).
                    -- nil (no manifest / legacy shapes) keeps always-adopt.
                    local dsp = M.dispatchModule;
                    if dsp ~= nil and type(dsp.virtualMinLevel) == 'function' then
                        local vok, vlv = pcall(dsp.virtualMinLevel, virt);
                        if vok and type(vlv) == 'number' and vlv > mjLevel then return; end
                    end
                    slotVirtual = virt;
                    return;
                end

                local maxLevel = 75; -- If you have passed the max level for the slot, set high so it won't be limiting if it's not specified.
                local minLevel = 0;
                local gearVarObject = gearVar;

                -- Wrapper form { gear = <ref>, minLevel/maxLevel/mode, ... }: build a
                -- COPY of the gear object with the wrapper's fields applied on top --
                -- individualize augments, override attributes, gate on level or mode.
                -- e.g. {gear = gear.Main.Sword.Excalibur, maxLevel = 50}
                -- (The old in-place merge mutated the SHARED gear.lua record, so one
                -- item wrapped differently in two sets leaked fields between them.)
                if type(gearVarObject) == "table" and gearVarObject.gear ~= nil and gearVarObject.Name == nil then
                    local ref = gearVarObject.gear;
                    if type(ref) == "string" then ref = resolveGearName(ref); end
                    local merged = {};
                    if type(ref) == "table" then
                        for k, v in pairs(ref) do merged[k] = v; end
                    end
                    for k, v in pairs(gearVarObject) do
                        if k ~= "gear" then merged[k] = v; end
                    end
                    gearVarObject = merged;
                end

                local gearObject;
                if type(gearVarObject) == "string" then
                    gearObject = resolveGearName(gearVarObject);
                    if gearObject == nil then
                        warnMissingGear(gearVarObject);
                        return;
                    end
                else
                    gearObject = gearVarObject;
                end

                -- Typed entries belong to the auto pass only, untyped to the
                -- normal pass only (see evalEntry doc above).
                local isAuto = type(gearObject.autoType) == "string"
                           and string.lower(gearObject.autoType) == "autoacc";
                if isAuto ~= (wantAuto == true) then return; end

                -- Mode-gated entry vs the current pass (see evalEntry doc above).
                if gearObject.mode ~= nil then
                    if not wantMode then return; end
                    local dsp = M.dispatchModule;
                    if dsp == nil or type(dsp.modeActive) ~= 'function'
                       or dsp.modeActive(gearObject.mode) ~= true then return; end
                elseif wantMode then
                    return;
                end

                if gearObject.maxLevel ~= nil then
                    maxLevel = gearObject.maxLevel;
                end

                if gearObject.minLevel ~= nil then
                    minLevel = gearObject.minLevel;
                end

                -- Seems like when loading in, it can't parse items properly at times, so this check will avoid errors.
                if gearObject.Level == nil then
                    return;
                end

                -- if gear level is over Main job level, ignore.
                if gearObject.Level > mjLevel then
                    return;
                end

                -- if Main Job level is over the slot's defined max level, ignore.
                if mjLevel > maxLevel then
                    return;
                end

                -- if Main Job level is under the slot's defined min level, ignore.
                if mjLevel < minLevel then
                    return;
                end

                -- RANKING. An entry with an explicit level RANGE that is live right
                -- now OUTRANKS every unbounded entry: a range is an instruction
                -- ("wear THIS from 20 to 51"), not a hint -- the old item-level
                -- comparison let any higher-level unbounded piece steal the window
                -- (field case: Garrison Tunica +1 ranged 20-51 lost to Druid's Robe
                -- at 50). Within the same tier the highest item level wins; on an
                -- exact tie the EARLIER list entry keeps the slot.
                local rank = (gearObject.minLevel ~= nil or gearObject.maxLevel ~= nil) and 1 or 0;
                if wantAuto then
                    -- AutoAcc candidates rank among themselves with the same tier
                    -- rules; between two eligible candidates the HIGHER-LEVELED
                    -- item wins the slot (Henrik's rule, 2026-07-14).
                    if rank < slotAccRank then return; end
                    if rank == slotAccRank and gearObject.Level <= slotAccLevel then return; end
                    if slotName == "Sub"
                       and not M.subSlotAllowed(gearObject, currentMain, { dw = isDW }) then
                        return;
                    end
                    slotAccRank, slotAccLevel = rank, gearObject.Level;
                    slotAcc = { name = gearObject.Name,
                                prio = math.floor(tonumber(gearObject.removePrio) or 1),
                                acc  = math.floor(tonumber(gearObject.acc) or 0) };
                    return;
                end
                if rank < slotRank then return; end
                if rank == slotRank and gearObject.Level <= slotLevel then return; end

                if slotName == "Sub" then
                    -- Sub-slot pairing (shared rule, equip-time): DW decides whether a
                    -- 1H off-hand is legal; the list's shield/grip is the fallback.
                    if not M.subSlotAllowed(gearObject, currentMain, { dw = isDW }) then
                        return;
                    end
                end
                slotRank, slotLevel = rank, gearObject.Level;
                currentSet[slotName] = gearObject.Name;
                -- Store reference to the main hand item for sub slot logic
                if slotName == "Main" then
                    currentMain = gearObject;
                end
            end

            -- Pass 1: mode-gated entries whose mode is active. Pass 2 (only when
            -- pass 1 picked nothing): the unconditional entries -- the fallback rank.
            for _, gearVar in pairs(slotTable) do evalEntry(gearVar, true, false); end
            if currentSet[slotName] == nil then
                for _, gearVar in pairs(slotTable) do evalEntry(gearVar, false, false); end
            end
            -- Same two passes for the AutoAcc pool: typed entries pick their own
            -- winner; the normal pick above stays intact as the fallback.
            for _, gearVar in pairs(slotTable) do evalEntry(gearVar, true, true); end
            if slotAcc == nil then
                for _, gearVar in pairs(slotTable) do evalEntry(gearVar, false, true); end
            end

            -- Compose the virtual with its fallback: 'dlac:AutoStaff|<bestName>'. The
            -- engine tries the virtual first and equips the fallback when it can't
            -- resolve; with no fallback the slot is left untouched at resolve time.
            if slotVirtual ~= nil then
                if currentSet[slotName] ~= nil then
                    currentSet[slotName] = slotVirtual .. '|' .. currentSet[slotName];
                else
                    currentSet[slotName] = slotVirtual;
                end
                -- A Main STAFF MARKER always resolves to a two-handed staff, so the
                -- Sub pairing must treat it as one -- otherwise currentMain stays
                -- nil and 'no main -> no sub' vetoes the grip that belongs with it
                -- (field case: a Weapon:Caster grip sat unequipped under
                -- dlac:AutoIridescence).
                if slotName == 'Main' then
                    local lv = string.lower(slotVirtual);
                    if string.sub(lv, 1, 14) == 'dlac:autostaff'
                       or string.sub(lv, 1, 21) == 'dlac:autoiridescence' then
                        currentMain = { Name = slotVirtual, Type = 'Staff', OneHanded = false, Level = 0 };
                    end
                end
            elseif slotAcc ~= nil then
                -- Type automation (AutoAcc): compose the marker the engine budgets
                -- with at equip time. Name goes LAST in the marker half so the
                -- parser survives any item name; prio/acc are baked here because
                -- the seeded engine state has no catalog to look them up in.
                -- 'dlac:AutoAcc:<removePrio>:<acc>:<Name>|<fallback>'
                local mk = string.format('dlac:AutoAcc:%d:%d:%s', slotAcc.prio, slotAcc.acc, slotAcc.name);
                if currentSet[slotName] ~= nil then
                    currentSet[slotName] = mk .. '|' .. currentSet[slotName];
                else
                    currentSet[slotName] = mk;
                end
            end
        end

        -- (Reserved slots -- a Body that takes Head away, like the Ryl.Ftm. Tunic --
        -- are resolved by the ENGINE at equip time, not here. The ffxi-lac original
        -- stripped Head during the build, keyed off a hand-authored
        -- CannotEquipHeadgear flag; both halves were wrong for dlac. Building is the
        -- wrong altitude: sets overlay, so a Head this set owns is perfectly legal
        -- under a higher-priority trigger that swaps the Body out -- stripping it
        -- here would lose it. And the flag was never a dlac field, so the check was
        -- dead code that always read nil. See dispatch.reservedDrops / ADR 0006.)
        sets[setName] = currentSet;
    end
    return sets;
end

STORAGES = {
    [9] = { id=8, name='Wardrobe' },
    [11]= { id=10, name='Wardrobe 2' },
    [12]= { id=11, name='Wardrobe 3' },
    [13]= { id=12, name='Wardrobe 4' },
    [14]= { id=13, name='Wardrobe 5' },
    [15]= { id=14, name='Wardrobe 6' },
    [16]= { id=15, name='Wardrobe 7' },
    [17]= { id=16, name='Wardrobe 8' }
};

M.Test = function()
    print ("Running Tests...");
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    local resources = AshitaCore:GetResourceManager();
    for k,v in pairs(STORAGES) do
        local itemEntry = inventory:GetItem(v.id, j);
        print (itemEntry);
        break
    end
end


ashita.events.register('command', 'dlac', function (e)
    local raw_command = string.lower(e.command);
    local prefix = "/dlac";
    local shortPrefix = "/dl";
    local args = {};
    local start_index = 0;

    -- If the command does not start with the prefix, ignore it.
    if string.sub(raw_command, 1, #prefix) == prefix then
        start_index = #prefix + 2
    elseif string.sub(raw_command, 1, #shortPrefix) == shortPrefix then
        start_index = #shortPrefix + 2
    else
        return;
    end

    -- Get starting index for arguments.
    

    -- Fetch out the string starting from the start index, so we can parse the actual arguments while ignoring prefix.
    local raw_args_string = string.sub(raw_command, start_index)

    -- Loop through and split arguments by spaces and insert into args table.
    for arg in string.gmatch(raw_args_string, "[^%s]+") do
                table.insert(args, arg)
    end
    
    -- Simple check to see if there is even a sub-command present before I try to use it.
    if args[1] == nil then return; end

    sub_command = args[1];

    if sub_command == "set" then
        if args[2] == nil then return; end

        set_command = args[2];

        if set_command == "level" then
            if args[3] == nil then return; end

            local level_type = args[3];

            if level_type == "main" or "sub" then
                if args[4] == nil then return; end

                local new_level = tonumber(args[4]);

                if new_level == nil then return; end

                if level_type == "main" then
                    staticMainLevel = new_level;
                    print("Main job level set to " .. tostring(staticMainLevel) .. ".");
                elseif level_type == "sub" then
                    staticSubLevel = new_level;
                    print("Sub job level set to " .. tostring(staticSubLevel) .. ".");
                end
            end
        end
    elseif sub_command == "dw" then
        -- Field probe for the Dual Wield trait bit (docs/reference/catseyexi-jobs.md):
        -- shows the raw HasAbility(1554) answer next to what the engine concludes.
        local bit = 'n/a';
        pcall(function()
            local p = AshitaCore:GetMemoryManager():GetPlayer();
            if p ~= nil then bit = tostring(p:HasAbility(1554)); end
        end);
        local mj, sj, mlv, slv = '?', '?', 0, 0;
        pcall(function()
            local p = gData.GetPlayer();
            mj = p.MainJob or '?'; sj = p.SubJob or '?';
            mlv, slv = M.determineLevels();
        end);
        print(string.format('[dlac] DW probe: HasAbility(1554)=%s  %s%s/%s%s  -> isDualWieldAvailable=%s',
            bit, tostring(mj), tostring(mlv), tostring(sj), tostring(slv),
            tostring(M.isDualWieldAvailable(mj, mlv, sj, slv))));
    elseif sub_command == "recalc" then
        sets = M.BuildDynamicSets(sets);
    elseif sub_command == "test" then
        M.Test();
    elseif sub_command == "reload" or sub_command == "r" then
        AshitaCore:GetChatManager():QueueCommand(1, '/addon reload luashitacast');
    end
end);






return M;