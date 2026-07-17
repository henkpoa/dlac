-- ============================================================================
--  dlac profile template -- the clean / minimal way (the "shim").
--  This is what the GUI's Setup button writes for a fresh job, and what
--  /dl profile migrate rewrites an old file into (after backing it up to
--  backups\pre-profiles\). You should never need to copy it by hand.
--
--  There is NO data and NO equip logic in this file, and dlac never edits it:
--    sets     live in  <char>\dlac\profiles\<active>\sets\<JOB>.lua      (Sets tab)
--    triggers live in  <char>\dlac\profiles\<active>\triggers\<JOB>.lua  (Triggers tab)
--    the active profile is picked in <char>\dlac\profile.lua (/dl profile use <name>)
--
--  How the auto-load composes: LuaAshitacast keeps loading <JOB>.lua on every
--  job change -- the engine then installs "active profile + current job" over
--  it (no /lac reload; see dispatch.lua's profile auto-install). The profile
--  picks the FOLDER, the job picks the FILE inside it.
--
--  Migrating an EXISTING profile? Run Setup: THE STANDARD (2026-07-17) is that
--  the live <JOB>.lua is ALWAYS this clean shim -- your old file is verified
--  into backups\pre-profiles\ first and never stays live (two equip logics in
--  one file fight over slots; the conflicts are unsupportable). Your old static
--  sets, _Priority lists and group tables stay one click away: Sets tab "Copy
--  from" and the Groups box's "Scan my Lua" read the backup forever. (Experts
--  CAN still hand-wire utils.dispatch('<Handler>') as the last line of their
--  own handlers -- the engine runs it, but the GUI flags the file as
--  non-standard and Setup will offer to re-shim it.)
-- ============================================================================

-- dlac profile shim (v1) -- managed by dlac. Do not keep data here.
local profile = {};
local utils = require("dlac\\utils");   -- everything comes through this one require
local gear  = utils.gear;               -- the shared gear inventory
local sets = {
    Dynamic = {},                       -- filled by the engine from the active dlac profile
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

-- All equip logic is data: utils.dispatch reads the active profile's trigger file
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
