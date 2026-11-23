-- Planning bonuses from modules/custom/sql/artifact_gear.sql in the AXI
-- ascensionxi-03 checkout (2026-09-28), the Duelist's pieces from
-- relic_armor.sql (AXI #1022, main b55f2d3416), the Rekindled Rapiers from
-- rekindled_rapier_stances.sql (AXI #1058) and Paladin's pieces from
-- pld_gear.sql (AXI #1061, main 5add37d501), the Awakened Rapier from
-- gear_awakened.sql (AXI #1324) and Samurai's pieces from sam_af_relic.sql
-- (AXI #1374, #1380, main 73f4aa1b14). Add new jobs' stance gear here.
-- These are conditional DELTAS, never replacements for the catalog stats.
-- Each job's tables are keyed by the Set Type id that plans with them:
-- 'stance' (the job's main stance), 'composure' (Red Mage's support stance),
-- 'divineguard' and 'divinefury' (Paladin's two), 'hasso' and 'seigan'
-- (Samurai's two). `label` names the stance in
-- the Sets tab's Set Type menu, which offers a type only on jobs that have
-- its table.
-- tests/stance_sets.lua holds RDM to the pack's latent 30000 and 30001 rows
-- and PLD to its latent 30002 rows, and SAM to the status-effect latent rows
-- on Hasso (effect 353) and Seigan (354).
-- `gates` lists the job's stances as the buff bar names them -- the Stance
-- Gates the Sets tab's Behaviour popup offers (2026-11-03): a piece gated on
-- one is worn only while it is on you. Each is a status name in the AXI
-- client DAT: Composure 419, Duelist's Focus 520, Duelist's Trance 521
-- (client/sources/rdm-abilities), Afflatus Solace 417, Afflatus Misery 418,
-- Divine Guard 654, Divine Fury 655 (client/sources/pld-divine-guard),
-- Hasso 353, Seigan 354.
return {
    WHM = {
        gates = { 'Afflatus Solace', 'Afflatus Misery' },
    },
    RDM = {
        gates = { 'Composure', "Duelist's Focus", "Duelist's Trance" },
        stance = { -- Duelist's Focus / Duelist's Trance (latent 30000, power >= 2)
            label = 'Duelist Stance',
            [16829] = { Accuracy = 5, Attack = 5 }, -- Fencing Degen
            [19978] = { EnhancingMagicSkill = 4, EnspellDamage = 2 }, -- Rekindled Rapier
            [19987] = { EnhancingMagicSkill = 4, EnspellDamage = 3 }, -- Rkndl. Rapier +1
            [19994] = { EnhancingMagicSkill = 5, EnspellDamage = 4 }, -- Rkndl. Rapier +2
            [20027] = { EnhancingMagicSkill = 6, EnspellDamage = 5 }, -- Awakened Rapier
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
            [20027] = { INT = 7, MND = 7 }, -- Awakened Rapier
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
        gates = { 'Divine Guard', 'Divine Fury' },
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
    SAM = {
        gates = { 'Hasso', 'Seigan' },
        hasso = { -- Hasso (status-effect latent 13, effect 353; AXI #1374)
            label = 'Hasso',
            [13868] = { Zanshin = 2 }, -- Myochin Kabuto
            [13781] = { Attack = 5 }, -- Myochin Domaru
            [13972] = { Accuracy = 3 }, -- Myochin Kote
            [14225] = { StoreTP = 2 }, -- Myochin Haidate
            [14100] = { Zanshin = 3 }, -- Myochin Sune-Ate
            [15083] = { MeditateDuration = 4, Zanshin = 3 }, -- Saotome Kabuto
            [15098] = { SAMChainTPBonus = 50, StoreTP = 3 }, -- Saotome Domaru
            [15113] = { Accuracy = 4 }, -- Saotome Kote
            [15128] = { Zanshin = 3 }, -- Saotome Haidate
            [15143] = { Attack = 5 }, -- Saotome Sune-Ate
            [23297] = { Haste = 3 }, -- Kasuga Haidate +2 (level 99, above the cap)
        },
        seigan = { -- Seigan (status-effect latent 13, effect 354; AXI #1374, #1380)
            label = 'Seigan',
            [13868] = { Enmity = 2 }, -- Myochin Kabuto
            [13781] = { HP = 30 }, -- Myochin Domaru
            [13972] = { Enmity = 2 }, -- Myochin Kote
            [14225] = { ParryingSkill = 5 }, -- Myochin Haidate
            [14100] = { Enmity = 3 }, -- Myochin Sune-Ate
            [15083] = { Enmity = 3, ThirdEyeCounterDamage = 15 }, -- Saotome Kabuto
            [15098] = { Enmity = 2, HP = 40, SAMSeiganCounterTP = 50 }, -- Saotome Domaru
            [15113] = { Enmity = 2 }, -- Saotome Kote
            [15128] = { Enmity = 1, ParryingSkill = 8 }, -- Saotome Haidate
            [15143] = { Enmity = 2 }, -- Saotome Sune-Ate
            [23096] = { Counter = 16 }, -- Kasuga Kabuto +2 (level 99, above the cap)
        },
    },
    WAR = {
        stance = { -- Berserk (status-effect latent 13, effect 56)
            label = 'Berserk',
            [16678] = { Attack = 10 }, -- Razor Axe
        },
    },
};
