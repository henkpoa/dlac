-- ============================================================================
--  dlac profile template -- the clean / minimal way.
--  Copy this to <JOB>.lua (e.g. WAR.lua) next to your other profiles -- or just
--  click the GUI's Setup button, which writes this (plus a starter trigger file)
--  for you.
--
--  Only ONE require is needed: dlac\utils. Requiring it pulls in the gear
--  inventory (as utils.gear), the trigger dispatch engine, every /dl command
--  (scan, ui, best, weight, mode, why, ...), and the GUI -- all for you.
--
--  There is NO equip logic in this file. Each handler ends with
--  utils.dispatch('<Handler>'), and the engine reads your per-job trigger data
--  from  <char>\dlac\triggers\<JOB>.lua  (edited in the GUI's Triggers tab, or
--  by hand -- it hot-reloads, so no /lac reload after a trigger edit).
--  See docs/design/trigger-system.md for the rule shape and conditions.
--
--  Migrating an EXISTING profile? Nothing forces you to change it: keep your
--  hand-written handler code and just add the utils.dispatch(...) call as the
--  LAST line of each handler -- dispatch runs last, so trigger-driven gear
--  overlays whatever your own code equipped (per-slot, later wins).
-- ============================================================================

local profile = {};
local utils = require("dlac\\utils");   -- everything comes through this one require
local gear  = utils.gear;               -- the shared gear inventory

-- Dynamic sets: each slot is a LIST -- dlac equips the best one for your level.
-- Build these in the GUI (Sets tab); Triggers decide WHEN each set is worn.
sets = {
    Dynamic = {
        Idle       = {},
        Tp_Default = {},
        Resting    = {},
        Movement   = {},
    },

    -- Normal (static) sets are still fine here -- the GUI's Sets tab can even copy
    -- one of these into a Dynamic set to give you a head start when migrating.
    -- Precast = { Head = "Warlock's Chapeau" },
};
profile.Sets = sets;

-- All equip logic is data: utils.dispatch reads <char>\dlac\triggers\<JOB>.lua.
profile.HandleDefault = function()
    sets = utils.rebuildSets(sets);     -- level-scaling rebuild (as before)
    utils.dispatch('Default');          -- status/mode triggers (Engaged, DT, ...)
end

profile.HandleAbility     = function() utils.dispatch('Ability');     end
profile.HandleItem        = function() utils.dispatch('Item');        end
profile.HandlePrecast     = function() utils.dispatch('Precast');     end
profile.HandleMidcast     = function() utils.dispatch('Midcast');     end
profile.HandlePreshot     = function() utils.dispatch('Preshot');     end
profile.HandleMidshot     = function() utils.dispatch('Midshot');     end
profile.HandleWeaponskill = function() utils.dispatch('Weaponskill'); end

return profile;
