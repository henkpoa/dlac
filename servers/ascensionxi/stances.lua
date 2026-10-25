-- Planning bonuses from modules/custom/sql/artifact_gear.sql in the AXI
-- ascensionxi-03 checkout (2026-09-28), the Duelist's pieces from
-- relic_armor.sql (AXI #1022, main b55f2d3416), the Rekindled Rapiers from
-- rekindled_rapier_stances.sql (AXI #1058) and Paladin's pieces from
-- pld_gear.sql (AXI #1061, main 5add37d501). Add new jobs' stance gear here.
-- These are conditional DELTAS, never replacements for the catalog stats.
-- Each job's tables are keyed by the Set Type id that plans with them:
-- 'stance' (the job's main stance), 'composure' (Red Mage's support stance),
-- 'divineguard' and 'divinefury' (Paladin's two). `label` names the stance in
-- the Sets tab's Set Type menu, which offers a type only on jobs that have
-- its table.
-- tests/stance_sets.lua holds RDM to the pack's latent 30000 and 30001 rows
-- and PLD to its latent 30002 rows.
return {
    RDM = {
        stance = { -- Duelist's Focus / Duelist's Trance (latent 30000, power >= 2)
            label = 'Duelist Stance',
            [16829] = { Accuracy = 5, Attack = 5 }, -- Fencing Degen
            [19978] = { EnhancingMagicSkill = 4, EnspellDamage = 2 }, -- Rekindled Rapier
            [19987] = { EnhancingMagicSkill = 4, EnspellDamage = 3 }, -- Rkndl. Rapier +1
            [19994] = { EnhancingMagicSkill = 5, EnspellDamage = 4 }, -- Rkndl. Rapier +2
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
            [19978] = { INT = 4, MND = 4 }, -- Rekindled Rapier
            [19987] = { INT = 5, MND = 5 }, -- Rkndl. Rapier +1
            [19994] = { INT = 6, MND = 6 }, -- Rkndl. Rapier +2
            [12642] = { EnfeeblingMagicSkill = 15 }, -- Warlock's Tabard
            [14218] = { HealingMagicSkill = 10 }, -- Warlock's Tights
            [14093] = { ConserveMP = 3 }, -- Warlock's Boots
            [15076] = { EnfeeblingMagicSkill = 15 }, -- Duelist's Chapeau
            [15091] = { HealingMagicSkill = 10 }, -- Duelist's Tabard
            [15121] = { INT = 5 }, -- Duelist's Tights
            [15136] = { ConserveMP = 5 }, -- Duelist's Boots
        },
    },
    PLD = {
        divineguard = { -- Divine Guard (latent 30002, power 1; AXI #1061)
            label = 'Divine Guard',
            [12515] = { CoverDuration = 5, CoverMagicRanged = 1, Enmity = 2, VIT = 3 }, -- Gallant Coronet
            [12644] = { Enmity = 2, ShieldSkill = 5, VIT = 4 }, -- Gallant Surcoat
            [13967] = { AGI = 3, Enmity = 2, VIT = 3 }, -- Gallant Gauntlets
            [14220] = { AGI = 3, Enmity = 2 }, -- Gallant Breeches
            [14095] = { ShieldSkill = 2 }, -- Gallant Leggings
            [15078] = { RampartDuration = 15 }, -- Valor Coronet
            [15093] = { Enmity = 4 }, -- Valor Surcoat
            [15108] = { Enmity = 3, ShieldBash = 10, VIT = 5 }, -- Valor Gauntlets
            [15123] = { Enmity = 3, SpellInterruptionRateDown = 10, VIT = 5 }, -- Valor Breeches
            [15138] = { Enmity = 1, SentinelEffect = 10 }, -- Valor Leggings
        },
        divinefury = { -- Divine Fury (latent 30002, power 2; AXI #1061)
            label = 'Divine Fury',
            [12515] = { Accuracy = 4, STR = 3 }, -- Gallant Coronet
            [12644] = { Accuracy = 6, STR = 5 }, -- Gallant Surcoat
            [13967] = { DEX = 3, STR = 3 }, -- Gallant Gauntlets
            [14220] = { Attack = 6, DEX = 3 }, -- Gallant Breeches
            [14095] = { Accuracy = 2, Attack = 2 }, -- Gallant Leggings
            [15078] = { PaladinLightDuration = 15, SkillchainDamage = 5 }, -- Valor Coronet
            [15093] = { DEX = 3 }, -- Valor Surcoat
            [15108] = { Accuracy = 4, Haste = 2 }, -- Valor Gauntlets
            [15123] = { Accuracy = 5, STR = 5 }, -- Valor Breeches
            [15138] = { Accuracy = 3, Haste = 1 }, -- Valor Leggings
        },
    },
    WAR = {
        stance = { -- Berserk (status-effect latent 13, effect 56)
            label = 'Berserk',
            [16678] = { Attack = 10 }, -- Razor Axe
        },
    },
};
