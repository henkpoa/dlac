-- Planning bonuses from modules/custom/sql/artifact_gear.sql in the AXI
-- ascensionxi-03 checkout (2026-09-28), and the Duelist's pieces from
-- relic_armor.sql (AXI #1022, main b55f2d3416). Add new jobs' stance gear here.
-- These are conditional DELTAS, never replacements for the catalog stats.
-- Each job's tables are keyed by the Set Type id that plans with them:
-- 'stance' (the job's main stance) and 'composure' (Red Mage's support
-- stance). `label` names the stance in the Sets tab's Set Type menu, which
-- offers a type only on jobs that have its table.
-- tests/stance_sets.lua holds RDM to the pack's latent 30000 and 30001 rows.
return {
    RDM = {
        stance = { -- Duelist's Focus / Duelist's Trance (latent 30000, power >= 2)
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
        composure = { -- plain Composure only (latent 30001, power 1; AXI #1022)
            label = 'Composure',
            [12642] = { EnfeeblingMagicSkill = 15 }, -- Warlock's Tabard
            [14218] = { HealingMagicSkill = 10 }, -- Warlock's Tights
            [14093] = { ConserveMP = 3 }, -- Warlock's Boots
            [15076] = { EnfeeblingMagicSkill = 15 }, -- Duelist's Chapeau
            [15091] = { HealingMagicSkill = 10 }, -- Duelist's Tabard
            [15121] = { INT = 5 }, -- Duelist's Tights
            [15136] = { ConserveMP = 5 }, -- Duelist's Boots
        },
    },
    WAR = {
        stance = { -- Berserk (status-effect latent 13, effect 56)
            label = 'Berserk',
            [16678] = { Attack = 10 }, -- Razor Axe
        },
    },
};
