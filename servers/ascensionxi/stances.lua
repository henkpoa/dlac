-- Planning bonuses from modules/custom/sql/artifact_gear.sql in the AXI
-- ascensionxi-03 checkout (2026-09-28), and the Duelist's pieces from
-- relic_armor.sql (AXI #1022, main b55f2d3416). Add new jobs' stance gear here.
-- These are conditional DELTAS, never replacements for the catalog stats.
-- `label` names the job's stance in the Sets tab's Set Type menu.
-- tests/stance_sets.lua holds RDM to the pack's latent 30000 rows.
return {
    RDM = { -- Duelist's Focus / Duelist's Trance (latent 30000, power >= 2)
        label = 'Duelist Stance',
        [16829] = { Accuracy = 5, Attack = 5 }, -- Fencing Degen
        [12513] = { Accuracy = 6, Attack = 6 }, -- Warlock's Chapeau
        [12642] = { Accuracy = 5, Attack = 5 }, -- Warlock's Tabard
        [13965] = { Accuracy = 5, EnspellDamage = 2 }, -- Warlock's Gloves
        [14218] = { Accuracy = 4, Attack = 6 }, -- Warlock's Tights
        [14093] = { Accuracy = 6 }, -- Warlock's Boots
        [15076] = { EnhancingMagicSkill = 15 }, -- Duelist's Chapeau
        [15091] = { ElementalMagicSkill = 10 }, -- Duelist's Tabard
        [15121] = { ElementalMagicSkill = 10 }, -- Duelist's Tights
        [15136] = { MagicAttackBonus = 4 }, -- Duelist's Boots
    },
    WAR = { -- Berserk (status-effect latent 13, effect 56)
        label = 'Berserk',
        [16678] = { Attack = 10 }, -- Razor Axe
    },
};
