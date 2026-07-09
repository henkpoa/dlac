local gear = require("dlac\\gear");

-- Gear auto-import reader (Piece #1). Loaded here so every profile gets the
-- `/dl scan` command. Guarded so a problem in it can never break profile load.
local _giok, _gierr = pcall(require, "dlac\\gearimport");
if not _giok then
    print('[dlac] gearimport failed to load: ' .. tostring(_gierr));
end

-- Gear browser UI (ImGui). Loaded here so every profile gets the `/dl ui`
-- command. Same guarded load so a UI problem can never break profile load.
local _guiok, _guierr = pcall(require, "dlac\\gearui");
if not _guiok then
    print('[dlac] gearui failed to load: ' .. tostring(_guierr));
end

-- Set optimizer: stat weights (/dl weight), best-set (/dl best), MP tools
-- (/dl mp, /dl maxmp). Guarded load, same as the others.
local _goptok, _gopterr = pcall(require, "dlac\\gearoptim");
if not _goptok then
    print('[dlac] gearoptim failed to load: ' .. tostring(_gopterr));
end

-- Dynamic-set editor: the gearui Sets tab commits/deletes sets back into <JOB>.lua
-- through this. Loaded here too so load errors surface early. Guarded.
local _smok, _smerr = pcall(require, "dlac\\setmanager");
if not _smok then
    print('[dlac] setmanager failed to load: ' .. tostring(_smerr));
end

-- Load the LAC framework include (gcinclude) as a global if the profile hasn't
-- already, so a migrated profile only needs `require("dlac\\utils")`. Guarded:
-- only when gFunc exists and gcinclude isn't already set (old profiles set it
-- themselves, so they are unaffected).
if rawget(_G, 'gcinclude') == nil and rawget(_G, 'gFunc') ~= nil and gFunc.LoadFile ~= nil then
    local _gcok, _gc = pcall(gFunc.LoadFile, 'dlac\\gcinclude.lua');
    if _gcok and _gc ~= nil then _G.gcinclude = _gc; end
end

staticMainLevel = 0; -- This will override your in-game level for testing purposes
staticSubLevel = 0; -- This will override your in-game sub job level for testing purposes

local M = {}

-- Re-export the gear inventory so a migrated profile needs only one require:
--   local utils = require("dlac\\utils"); local gear = utils.gear;
M.gear = gear;


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
        
        -- Iterate over each gear slot within the set
        for slotName, slotTable in pairs(setTable) do
            local maxSlotLevel = 0;
            local bestGear = nil;
            

            -- Find the highest-level eligible piece for the slot
            for _, gearVar in pairs(slotTable) do
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
                    -- Sub-slot Logic
                    if currentMain == nil or currentMain == '' then
                        -- Skip if Main weapon is not yet processed (or empty main hand slot)
                        goto continue_sub_slot
                    elseif currentMain.OneHanded == false and gearObject.Type == "Grip" then
                        -- 2H weapon + Grip is acceptable
                        bestGear = gearObject
                    elseif currentMain.OneHanded == true and gearObject.Type == "Shield" then
                        -- 1H weapon + Shield is acceptable
                        bestGear = gearObject
                    elseif currentMain.OneHanded == true and gearObject.OneHanded == true and isDW == true then
                        -- 1H weapon + 1H weapon (DW is active)
                        
                        -- Checks for same weapon name (using correct casing for property lookup)
                        if currentMain.Name == gearObject.Name and gearObject.InBothHands == true then
                            bestGear = gearObject
                        elseif currentMain.Name ~= gearObject.Name then
                            bestGear = gearObject
                        end
                    end
                    
                    ::continue_sub_slot:: -- Renamed the label for clarity
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
    elseif sub_command == "recalc" then
        sets = M.BuildDynamicSets(sets);
    elseif sub_command == "test" then
        M.Test();
    elseif sub_command == "reload" or sub_command == "r" then
        AshitaCore:GetChatManager():QueueCommand(1, '/addon reload luashitacast');
    end
end);






return M;