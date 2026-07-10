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
function M.rebuildSets(sets)
    local player = gData.GetPlayer();
    if player == nil then return sets; end
    local shouldRebuild, newLevel, newSJLevel, newSJ = M.checkRebuildNeeded(player, _lastLevel, _lastSJLevel, _lastSJ);
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

-- Sub-slot pairing rule, shared by the rebuild engine and the GUI set builder.
--   2H main -> Grip only.  1H main -> Shield always; a 1H weapon when ctx.dw (the
--   Dual Wield trait is up) OR ctx.building (composing a set -- a plan, not an
--   equip: the builder admits the weapon and BuildDynamicSets makes the equip-time
--   call, falling back to the list's shield). A same-name off-hand needs a provable
--   second copy: InBothHands on the record, or ctx.copies >= 2 (owned count).
function M.subSlotAllowed(subRec, mainRec, ctx)
    if type(subRec) ~= 'table' or type(mainRec) ~= 'table' then return false; end
    ctx = ctx or {};
    if mainRec.OneHanded == false then
        return subRec.Type == 'Grip';
    end
    if mainRec.OneHanded ~= true then return false; end
    if subRec.Type == 'Shield' then return true; end
    if subRec.OneHanded ~= true or subRec.Type == 'Grip' then return false; end
    if ctx.dw ~= true and ctx.building ~= true then return false; end
    if subRec.Name == mainRec.Name then
        if subRec.InBothHands == true then return true; end
        return (tonumber(ctx.copies) or 0) >= 2;
    end
    return true;
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
            local maxSlotLevel = 0;
            local bestGear = nil;
            local slotVirtual = nil;

            -- Find the highest-level eligible piece for the slot
            for _, gearVar in pairs(slotTable) do
                -- Virtual slot entry ('dlac:AutoStaff' / 'dlac:AutoObi'): the dispatch
                -- engine resolves it at equip time (ADR 0004). Remember it, but KEEP
                -- evaluating the slot's real items -- the normal best-by-level pick
                -- becomes the FALLBACK when the virtual can't resolve (e.g. every
                -- iridescence weapon / obi is above your current level).
                if type(gearVar) == "string" and string.lower(string.sub(gearVar, 1, 5)) == "dlac:" then
                    slotVirtual = gearVar;
                    goto continue;
                end

                local maxLevel = 75; -- If you have passed the max level for the slot, set high so it won't be limiting if it's not specified.
                local minLevel = 0;
                local gearVarObject = gearVar;

                -- The point of this is to be able to set own parameters with a table on a gear.
                -- Now you can individualize gear stats (augments) and may set new attributes if needed, or overwrite.
                -- e.g. {gear = gear.Main.Sword.Excalibur, maxLevel = 50}

                if gearVarObject.gear ~= nil then
                    tempGearVar = gearVarObject.gear;
                    -- gearVar.gear = nil; -- Remove gear property to avoid confusion, also avoid looping over it.

                    -- Here we loop over all the table properties and overwrite or add properties to tempGearVar as needed.
                    for gearProp, gearValue in pairs(gearVarObject) do
                        tempGearVar[gearProp] = gearValue;
                    end

                    -- Once this is done, we have our own newly built gear object we will interract with as normally.
                    gearVarObject = tempGearVar;
                end

                if type(gearVarObject) == "string" then
                    if gear.NameToObject[gearVarObject] ~= nil then
                        gearObject = gear.NameToObject[gearVarObject]
                    else
                        print ("Unable to find " .. tostring(gearVarObject) .. " in gear table.")
                    end
                else
                    gearObject = gearVarObject
                end


                
                if gearObject.maxLevel ~= nil then
                    maxLevel = gearObject.maxLevel;
                end

                if gearObject.minLevel ~= nil then
                    minLevel = gearObject.minLevel;
                end

                -- Seems like when loading in, it can't parse items properly at times, so this check will avoid errors.
                -- Maybe there's a bug correlated to this, so will have to troubleshoot further to see what creates this.
                if gearObject.Level == nil then
                    goto continue;
                end

                -- if gear level is over Main job level, ignore.
                if gearObject.Level > mjLevel then
                    goto continue;
                end

                -- if gear level is under current selected slot's max level, ignore.
                if gearObject.Level < maxSlotLevel and minLevel < maxSlotLevel then
                    goto continue;
                end
                -- if Main Job level is over the slot's defined max level, ignore.
                if mjLevel > maxLevel then
                    goto continue;
                end

                -- if Main Job level is under the slot's defined min level, ignore.
                if mjLevel < minLevel then
                    goto continue;
                end

                    
                if slotName == "Sub" then
                    -- Sub-slot pairing (shared rule, equip-time): DW decides whether a
                    -- 1H off-hand is legal; the list's shield/grip is the fallback.
                    if M.subSlotAllowed(gearObject, currentMain, { dw = isDW }) then
                        bestGear = gearObject
                    end
                else
                    -- All other slots (Main, Head, Body, etc.)
                    bestGear = gearObject
                end
                
                -- If we found a valid piece, update the best gear for this set
                if bestGear ~= nil then
                    maxSlotLevel = bestGear.Level;
                    currentSet[slotName] = bestGear.Name;
                    
                    -- Store reference to the main hand item for sub slot logic
                    if slotName == "Main" then
                        currentMain = gearObject;
                    end
                end
                ::continue::
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
            end
        end

        -- After processing the whole set, check if body piece prevents headgear and remove headgear if necessary
        if gear.NameToObject[currentSet.Body] ~= nil then
            bodyGearObject = gear.NameToObject[currentSet.Body]
            if bodyGearObject.CannotEquipHeadgear ~= nil and bodyGearObject.CannotEquipHeadgear == true then
                if currentSet.Head ~= nil then
                    -- print ("Removing headgear from " .. setName .. " because body piece cannot equip headgear.");
                    currentSet.Head = nil;
                end
            end
        end
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