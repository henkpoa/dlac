-- ============================================================================
--  dlac profile template -- the clean / minimal way.
--  Copy this to <JOB>.lua (e.g. WAR.lua) next to your other profiles, fill in
--  your Dynamic sets, and you're done.
--
--  Only ONE require is needed: dlac\utils. Requiring it pulls in the gear
--  inventory (as utils.gear), every /dl command (scan, ui, best, weight, ...),
--  and the GUI -- all for you. (dlac needs no gcinclude or other framework.)
--
--  Migrating an EXISTING profile? Nothing forces you to change it: the old style
--  (require gear + utils yourself, keep local lastKnownLevel/SJLevel/SJ vars, and
--  call utils.rebuildSetsIfNeeded(player, sets, lastKnownLevel, ...)) still works
--  exactly as before. This template is just the shorter, boilerplate-free option.
-- ============================================================================

local profile = {};
local utils = require("dlac\\utils");   -- everything comes through this one require
local gear  = utils.gear;                    -- the shared gear inventory

-- Dynamic sets: each slot is a LIST -- dlac equips the best one for your level.
-- (You can still keep normal/static sets like Precast/Cure directly under `sets`.)
sets = {
    Dynamic = {
        Idle = {
            Main = { gear.Main.Staff.ChatoyantStaff },
            Body = { gear.Body.LinenRobe, { gear = gear.Body.SomeAF, minLevel = 61 } },
            -- ...one entry per slot; add as many candidates as you like...
        },
        -- Tp_Default = { ... },
        -- Resting    = { ... },
        -- Movement   = { ... },
    },

    -- Normal (static) sets are still fine here -- the GUI's Sets tab can even copy
    -- one of these into a Dynamic set to give you a head start when migrating.
    -- Precast = { Head = "Warlock's Chapeau" },
};
profile.Sets = sets;

-- dlac itself needs no OnLoad / OnUnload / HandleCommand. If you use a helper library
-- such as gcinclude (optional, not part of dlac), wire it in here as usual, e.g.:
--   profile.OnLoad        = function() gcinclude.Initialize(); end
--   profile.HandleCommand = function(args) gcinclude.HandleCommands(args); end

-- Your HandleDefault stays yours -- dlac only handles the rebuild. Call
-- `sets = utils.rebuildSets(sets)` first (it fetches the player and tracks your
-- level / subjob changes internally, so no local lastKnown* vars are needed), then
-- keep your own equip logic below exactly as any LuAshitacast profile.
profile.HandleDefault = function()
    sets = utils.rebuildSets(sets);

    local player = gData.GetPlayer();
    if     player.Status == 'Engaged' then gFunc.EquipSet(sets.Tp_Default);
    elseif player.Status == 'Resting' then gFunc.EquipSet(sets.Resting);
    elseif player.IsMoving == true    then gFunc.EquipSet(sets.Movement);
    else                                    gFunc.EquipSet(sets.Idle);
    end
end

-- Add the other handlers you need, same as any LuAshitacast profile:
-- profile.HandlePrecast     = function() ... end
-- profile.HandleMidcast     = function() ... end
-- profile.HandleWeaponskill = function() ... end

return profile;
