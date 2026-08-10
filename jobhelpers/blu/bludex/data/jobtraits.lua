-- jobtraits.lua -- job traits that COLLIDE with blue traits (GENERATED 2026-08-10
--                  by tools/generate_spells.py -- DO NOT EDIT)
-- Source: sql/traits.sql, filtered to the 32 trait ids blue magic can also
-- grant. A job trait SUPPRESSES the blue one outright, at any tier
-- (blueutils.cpp CalculateTraits: "Player has the real job trait, making
-- them ineligible" -- the TODO beside it is why the stronger-blue case does
-- not exist). Job traits are added first (charutils.cpp BuildingCharTraitsTable),
-- main job at your main level then sub job at your sub level.
--
-- BASE-LSB (public clone): CatsEyeXI may override these in the private
-- submodules. The live 0x0AC trait bit is the referee -- see lib/traitsource.lua.
-- content_tag is carried for the record only: CEXI runs RESTRICT_CONTENT = 0,
-- so every row here is live.

local M = { jobs = {}, codes = {}, names = {} }

M.codes[1] = 'WAR'; M.names[1] = 'Warrior'
M.codes[2] = 'MNK'; M.names[2] = 'Monk'
M.codes[3] = 'WHM'; M.names[3] = 'White Mage'
M.codes[4] = 'BLM'; M.names[4] = 'Black Mage'
M.codes[5] = 'RDM'; M.names[5] = 'Red Mage'
M.codes[6] = 'THF'; M.names[6] = 'Thief'
M.codes[7] = 'PLD'; M.names[7] = 'Paladin'
M.codes[8] = 'DRK'; M.names[8] = 'Dark Knight'
M.codes[9] = 'BST'; M.names[9] = 'Beastmaster'
M.codes[10] = 'BRD'; M.names[10] = 'Bard'
M.codes[11] = 'RNG'; M.names[11] = 'Ranger'
M.codes[12] = 'SAM'; M.names[12] = 'Samurai'
M.codes[13] = 'NIN'; M.names[13] = 'Ninja'
M.codes[14] = 'DRG'; M.names[14] = 'Dragoon'
M.codes[15] = 'SMN'; M.names[15] = 'Summoner'
M.codes[16] = 'BLU'; M.names[16] = 'Blue Mage'
M.codes[17] = 'COR'; M.names[17] = 'Corsair'
M.codes[18] = 'PUP'; M.names[18] = 'Puppetmaster'
M.codes[19] = 'DNC'; M.names[19] = 'Dancer'
M.codes[20] = 'SCH'; M.names[20] = 'Scholar'
M.codes[21] = 'GEO'; M.names[21] = 'Geomancer'
M.codes[22] = 'RUN'; M.names[22] = 'Rune Fencer'
M.codes[23] = 'MON'; M.names[23] = 'MON'

-- Warrior
M.jobs[1] = {
    [3] = { { level = 30, rank = 1, mods = { { stat = 'ATT', value = 10 }, { stat = 'RATT', value = 10 } } }, { level = 65, rank = 2, tag = 'ROV', mods = { { stat = 'ATT', value = 22 }, { stat = 'RATT', value = 22 } } }, { level = 90, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'ATT', value = 35 }, { stat = 'RATT', value = 35 } } } },   -- Attack Bonus
    [4] = { { level = 10, rank = 1, mods = { { stat = 'DEF', value = 10 } } }, { level = 45, rank = 2, tag = 'ROV', mods = { { stat = 'DEF', value = 22 } } }, { level = 86, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'DEF', value = 35 } } } },   -- Defense Bonus
    [7] = { { level = 30, rank = 1, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 30 } } }, { level = 50, rank = 2, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 60 } } }, { level = 70, rank = 3, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 120 } } }, { level = 90, rank = 4, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 180 } } } },   -- Max Hp Boost
    [15] = { { level = 25, rank = 1, mods = { { stat = 'DOUBLE_ATTACK', value = 10 } } }, { level = 50, rank = 2, tag = 'ROV', mods = { { stat = 'DOUBLE_ATTACK', value = 12 } } }, { level = 75, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'DOUBLE_ATTACK', value = 14 } } }, { level = 85, rank = 4, tag = 'ROV', mods = { { stat = 'DOUBLE_ATTACK', value = 16 } } }, { level = 99, rank = 5, tag = 'ROV', mods = { { stat = 'DOUBLE_ATTACK', value = 18 } } } },   -- Double Attack
}
-- Monk
M.jobs[2] = {
    [7] = { { level = 15, rank = 1, mods = { { stat = 'BASE_HP', value = 30 } } }, { level = 25, rank = 2, mods = { { stat = 'BASE_HP', value = 60 } } }, { level = 35, rank = 3, mods = { { stat = 'BASE_HP', value = 120 } } }, { level = 45, rank = 4, mods = { { stat = 'BASE_HP', value = 180 } } }, { level = 55, rank = 5, mods = { { stat = 'BASE_HP', value = 240 } } }, { level = 65, rank = 6, mods = { { stat = 'BASE_HP', value = 280 } } } },   -- Max Hp Boost
    [17] = { { level = 10, rank = 1, mods = { { stat = 'COUNTER', value = 10 } } }, { level = 81, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'COUNTER', value = 12 } } } },   -- Counter
    [106] = { { level = 85, rank = 1, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 8 } } }, { level = 95, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 12 } } } },   -- Skillchain Bonus
}
-- White Mage
M.jobs[3] = {
    [6] = { { level = 10, rank = 1, mods = { { stat = 'MDEF', value = 10 } } }, { level = 30, rank = 2, mods = { { stat = 'MDEF', value = 12 } } }, { level = 50, rank = 3, mods = { { stat = 'MDEF', value = 14 } } }, { level = 70, rank = 4, mods = { { stat = 'MDEF', value = 16 } } }, { level = 81, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'MDEF', value = 18 } } }, { level = 91, rank = 6, tag = 'ABYSSEA', mods = { { stat = 'MDEF', value = 20 } } } },   -- Magic Def. Bonus
    [9] = { { level = 25, rank = 1, mods = { { stat = 'REGEN', value = 1 } } }, { level = 76, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'REGEN', value = 2 } } } },   -- Auto Regen
    [24] = { { level = 20, rank = 1, mods = { { stat = 'MPHEAL', value = 3 } } }, { level = 35, rank = 2, mods = { { stat = 'MPHEAL', value = 6 } } }, { level = 50, rank = 3, mods = { { stat = 'MPHEAL', value = 9 }, { stat = 'CLEAR_MIND', value = 1 } } }, { level = 65, rank = 4, mods = { { stat = 'MPHEAL', value = 12 } } }, { level = 80, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'MPHEAL', value = 15 }, { stat = 'CLEAR_MIND', value = 2 } } }, { level = 96, rank = 6, tag = 'ABYSSEA', mods = { { stat = 'MPHEAL', value = 18 }, { stat = 'CLEAR_MIND', value = 3 } } } },   -- Clear Mind
}
-- Black Mage
M.jobs[4] = {
    [5] = { { level = 10, rank = 1, mods = { { stat = 'MATT', value = 20 } } }, { level = 30, rank = 2, mods = { { stat = 'MATT', value = 24 } } }, { level = 50, rank = 3, mods = { { stat = 'MATT', value = 28 } } }, { level = 70, rank = 4, mods = { { stat = 'MATT', value = 32 } } }, { level = 81, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'MATT', value = 36 } } }, { level = 91, rank = 6, tag = 'ABYSSEA', mods = { { stat = 'MATT', value = 40 } } } },   -- Magic Atk. Bonus
    [13] = { { level = 20, rank = 1, mods = { { stat = 'CONSERVE_MP', value = 25 } } }, { level = 76, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'CONSERVE_MP', value = 28 } } }, { level = 86, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'CONSERVE_MP', value = 31 } } } },   -- Conserve Mp
    [24] = { { level = 15, rank = 1, mods = { { stat = 'MPHEAL', value = 3 } } }, { level = 30, rank = 2, mods = { { stat = 'MPHEAL', value = 6 } } }, { level = 45, rank = 3, mods = { { stat = 'MPHEAL', value = 9 }, { stat = 'CLEAR_MIND', value = 1 } } }, { level = 60, rank = 4, mods = { { stat = 'MPHEAL', value = 12 } } }, { level = 75, rank = 5, mods = { { stat = 'MPHEAL', value = 15 }, { stat = 'CLEAR_MIND', value = 2 } } }, { level = 96, rank = 6, tag = 'ABYSSEA', mods = { { stat = 'MPHEAL', value = 18 }, { stat = 'CLEAR_MIND', value = 3 } } } },   -- Clear Mind
    [110] = { { level = 45, rank = 1, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_UNCAPPED', value = 5 } } }, { level = 58, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_UNCAPPED', value = 7 } } }, { level = 71, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_UNCAPPED', value = 9 } } }, { level = 84, rank = 4, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_UNCAPPED', value = 11 } } }, { level = 97, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_UNCAPPED', value = 13 } } } },   -- Mag. Burst Bonus
}
-- Red Mage
M.jobs[5] = {
    [5] = { { level = 20, rank = 1, mods = { { stat = 'MATT', value = 20 } } }, { level = 40, rank = 2, mods = { { stat = 'MATT', value = 24 } } }, { level = 86, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'MATT', value = 28 } } } },   -- Magic Atk. Bonus
    [6] = { { level = 25, rank = 1, mods = { { stat = 'MDEF', value = 10 } } }, { level = 45, rank = 2, mods = { { stat = 'MDEF', value = 12 } } }, { level = 96, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'MDEF', value = 14 } } } },   -- Magic Def. Bonus
    [12] = { { level = 15, rank = 1, mods = { { stat = 'FASTCAST', value = 10 } } }, { level = 35, rank = 2, mods = { { stat = 'FASTCAST', value = 15 } } }, { level = 55, rank = 3, mods = { { stat = 'FASTCAST', value = 20 } } }, { level = 76, rank = 4, tag = 'ABYSSEA', mods = { { stat = 'FASTCAST', value = 25 } } }, { level = 89, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'FASTCAST', value = 30 } } } },   -- Fast Cast
    [24] = { { level = 31, rank = 1, mods = { { stat = 'MPHEAL', value = 3 } } }, { level = 53, rank = 2, mods = { { stat = 'MPHEAL', value = 6 } } }, { level = 75, rank = 3, mods = { { stat = 'MPHEAL', value = 9 }, { stat = 'CLEAR_MIND', value = 1 } } }, { level = 91, rank = 4, tag = 'ABYSSEA', mods = { { stat = 'MPHEAL', value = 12 }, { stat = 'CLEAR_MIND', value = 1 } } } },   -- Clear Mind
    [110] = { { level = 85, rank = 1, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_UNCAPPED', value = 5 } } }, { level = 95, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_UNCAPPED', value = 7 } } } },   -- Mag. Burst Bonus
}
-- Thief
M.jobs[6] = {
    [2] = { { level = 10, rank = 1, mods = { { stat = 'EVA', value = 10 } } }, { level = 30, rank = 2, mods = { { stat = 'EVA', value = 22 } } }, { level = 50, rank = 3, mods = { { stat = 'EVA', value = 35 } } }, { level = 70, rank = 4, mods = { { stat = 'EVA', value = 48 } } }, { level = 76, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'EVA', value = 60 } } }, { level = 88, rank = 6, tag = 'ABYSSEA', mods = { { stat = 'EVA', value = 72 } } } },   -- Evasion Bonus
    [16] = { { level = 55, rank = 1, mods = { { stat = 'TRIPLE_ATTACK', value = 5 } } }, { level = 95, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'TRIPLE_ATTACK', value = 6 } } } },   -- Triple Attack
    [18] = { { level = 83, rank = 1, tag = 'ABYSSEA', mods = { { stat = 'DUAL_WIELD', value = 10 } } }, { level = 90, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'DUAL_WIELD', value = 15 } } }, { level = 98, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'DUAL_WIELD', value = 25 } } } },   -- Dual Wield
    [19] = { { level = 15, rank = 1, mods = { { stat = 'TREASURE_HUNTER', value = 1 } } } },   -- Treasure Hunter
    [20] = { { level = 5, rank = 1, mods = { { stat = 'GILFINDER', value = 1 } } }, { level = 90, rank = 2, mods = { { stat = 'GILFINDER', value = 2 } } } },   -- Gilfinder
    [58] = { { level = 20, rank = 1, mods = { { stat = 'GRAVITYRES', value = 10 } } }, { level = 40, rank = 2, mods = { { stat = 'GRAVITYRES', value = 15 } } }, { level = 66, rank = 3, mods = { { stat = 'GRAVITYRES', value = 20 } } }, { level = 75, rank = 4, mods = { { stat = 'GRAVITYRES', value = 25 } } }, { level = 81, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'GRAVITYRES', value = 30 } } } },   -- Resist Gravity
}
-- Paladin
M.jobs[7] = {
    [4] = { { level = 10, rank = 1, mods = { { stat = 'DEF', value = 10 } } }, { level = 30, rank = 2, mods = { { stat = 'DEF', value = 22 } } }, { level = 50, rank = 3, mods = { { stat = 'DEF', value = 35 } } }, { level = 70, rank = 4, mods = { { stat = 'DEF', value = 48 } } }, { level = 76, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'DEF', value = 60 } } }, { level = 91, rank = 6, tag = 'ABYSSEA', mods = { { stat = 'DEF', value = 72 } } } },   -- Defense Bonus
    [7] = { { level = 45, rank = 1, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 30 } } }, { level = 85, rank = 2, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 60 } } } },   -- Max Hp Boost
    [10] = { { level = 35, rank = 1, tag = 'TOAU', mods = { { stat = 'REFRESH', value = 1 } } } },   -- Auto Refresh
    [39] = { { level = 5, rank = 1, mods = { { stat = 'UNDEAD_KILLER', value = 8 } } }, { level = 86, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'UNDEAD_KILLER', value = 10 } } } },   -- Undead Killer
    [48] = { { level = 20, rank = 1, mods = { { stat = 'SLEEPRES', value = 10 } } }, { level = 40, rank = 2, mods = { { stat = 'SLEEPRES', value = 15 } } }, { level = 60, rank = 3, mods = { { stat = 'SLEEPRES', value = 20 } } }, { level = 75, rank = 4, mods = { { stat = 'SLEEPRES', value = 25 } } }, { level = 81, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'SLEEPRES', value = 30 } } } },   -- Resist Sleep
}
-- Dark Knight
M.jobs[8] = {
    [3] = { { level = 10, rank = 1, mods = { { stat = 'ATT', value = 10 }, { stat = 'RATT', value = 10 } } }, { level = 30, rank = 2, mods = { { stat = 'ATT', value = 22 }, { stat = 'RATT', value = 22 } } }, { level = 50, rank = 3, mods = { { stat = 'ATT', value = 35 }, { stat = 'RATT', value = 35 } } }, { level = 70, rank = 4, mods = { { stat = 'ATT', value = 48 }, { stat = 'RATT', value = 48 } } }, { level = 76, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'ATT', value = 60 }, { stat = 'RATT', value = 60 } } }, { level = 83, rank = 6, tag = 'ROV', mods = { { stat = 'ATT', value = 72 }, { stat = 'RATT', value = 72 } } }, { level = 91, rank = 7, tag = 'ABYSSEA', mods = { { stat = 'ATT', value = 84 }, { stat = 'RATT', value = 84 } } }, { level = 99, rank = 8, tag = 'ROV', mods = { { stat = 'ATT', value = 96 }, { stat = 'RATT', value = 96 } } } },   -- Attack Bonus
}
-- Beastmaster
M.jobs[9] = {
    [32] = { { level = 70, rank = 1, mods = { { stat = 'BEAST_KILLER', value = 8 } } }, { level = 94, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'BEAST_KILLER', value = 10 } } } },   -- Beast Killer
    [33] = { { level = 60, rank = 1, mods = { { stat = 'PLANTOID_KILLER', value = 8 } } }, { level = 91, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'PLANTOID_KILLER', value = 10 } } } },   -- Plantoid Killer
    [35] = { { level = 40, rank = 1, mods = { { stat = 'LIZARD_KILLER', value = 8 } } }, { level = 85, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'LIZARD_KILLER', value = 10 } } } },   -- Lizard Killer
}
-- Ranger
M.jobs[11] = {
    [1] = { { level = 10, rank = 1, mods = { { stat = 'ACC', value = 10 }, { stat = 'RACC', value = 10 } } }, { level = 30, rank = 2, mods = { { stat = 'ACC', value = 22 }, { stat = 'RACC', value = 22 } } }, { level = 50, rank = 3, mods = { { stat = 'ACC', value = 35 }, { stat = 'RACC', value = 35 } } }, { level = 70, rank = 4, mods = { { stat = 'ACC', value = 48 }, { stat = 'RACC', value = 48 } } }, { level = 86, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'ACC', value = 60 }, { stat = 'RACC', value = 60 } } }, { level = 96, rank = 6, tag = 'ABYSSEA', mods = { { stat = 'ACC', value = 73 }, { stat = 'RACC', value = 73 } } } },   -- Accuracy Bonus
    [11] = { { level = 15, rank = 1, mods = { { stat = 'RAPID_SHOT', value = 25 } } }, { level = 71, rank = 2, tag = 'SOA', mods = { { stat = 'RAPID_SHOT', value = 30 } } } },   -- Rapid Shot
}
-- Samurai
M.jobs[12] = {
    [14] = { { level = 10, rank = 1, mods = { { stat = 'STORETP', value = 10 } } }, { level = 30, rank = 2, mods = { { stat = 'STORETP', value = 15 } } }, { level = 50, rank = 3, mods = { { stat = 'STORETP', value = 20 } } }, { level = 70, rank = 4, mods = { { stat = 'STORETP', value = 25 } } }, { level = 90, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'STORETP', value = 30 } } } },   -- Store Tp
    [70] = { { level = 20, rank = 1, tag = 'COP', mods = { { stat = 'ZANSHIN', value = 15 } } }, { level = 35, rank = 2, tag = 'COP', mods = { { stat = 'ZANSHIN', value = 25 } } }, { level = 50, rank = 3, tag = 'COP', mods = { { stat = 'ZANSHIN', value = 35 } } }, { level = 75, rank = 4, tag = 'COP', mods = { { stat = 'ZANSHIN', value = 45 } } }, { level = 95, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'ZANSHIN', value = 50 } } } },   -- Zanshin
    [106] = { { level = 78, rank = 1, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 8 } } }, { level = 88, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 12 } } }, { level = 98, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 16 } } } },   -- Skillchain Bonus
}
-- Ninja
M.jobs[13] = {
    [7] = { { level = 20, rank = 1, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 30 } } }, { level = 40, rank = 2, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 60 } } }, { level = 60, rank = 3, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 120 } } }, { level = 80, rank = 4, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 180 } } }, { level = 99, rank = 5, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 240 } } } },   -- Max Hp Boost
    [18] = { { level = 10, rank = 1, mods = { { stat = 'DUAL_WIELD', value = 10 } } }, { level = 25, rank = 2, mods = { { stat = 'DUAL_WIELD', value = 15 } } }, { level = 45, rank = 3, mods = { { stat = 'DUAL_WIELD', value = 25 } } }, { level = 65, rank = 4, mods = { { stat = 'DUAL_WIELD', value = 30 } } }, { level = 85, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'DUAL_WIELD', value = 35 } } } },   -- Dual Wield
    [106] = { { level = 85, rank = 1, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 8 } } }, { level = 95, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 12 } } } },   -- Skillchain Bonus
    [110] = { { level = 80, rank = 1, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_UNCAPPED', value = 5 } } }, { level = 90, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_CAPPED', value = 7 } } } },   -- Mag. Burst Bonus
}
-- Dragoon
M.jobs[14] = {
    [1] = { { level = 30, rank = 1, mods = { { stat = 'ACC', value = 10 }, { stat = 'RACC', value = 10 } } }, { level = 60, rank = 2, tag = 'TOAU', mods = { { stat = 'ACC', value = 22 }, { stat = 'RACC', value = 22 } } }, { level = 76, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'ACC', value = 35 }, { stat = 'RACC', value = 35 } } } },   -- Accuracy Bonus
    [3] = { { level = 10, rank = 1, mods = { { stat = 'ATT', value = 10 }, { stat = 'RATT', value = 10 } } }, { level = 91, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'ATT', value = 22 }, { stat = 'RATT', value = 22 } } } },   -- Attack Bonus
}
-- Summoner
M.jobs[15] = {
    [8] = { { level = 10, rank = 1, mods = { { stat = 'BASE_MP', value = 10 } } }, { level = 30, rank = 2, mods = { { stat = 'BASE_MP', value = 20 } } }, { level = 50, rank = 3, mods = { { stat = 'BASE_MP', value = 40 } } }, { level = 70, rank = 4, mods = { { stat = 'BASE_MP', value = 60 } } }, { level = 76, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'BASE_MP', value = 80 } } }, { level = 96, rank = 6, tag = 'ABYSSEA', mods = { { stat = 'BASE_MP', value = 100 } } } },   -- Max Mp Boost
    [10] = { { level = 25, rank = 1, mods = { { stat = 'REFRESH', value = 1 } } }, { level = 90, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'REFRESH', value = 2 } } } },   -- Auto Refresh
    [24] = { { level = 15, rank = 1, mods = { { stat = 'MPHEAL', value = 3 } } }, { level = 30, rank = 2, mods = { { stat = 'MPHEAL', value = 6 } } }, { level = 45, rank = 3, mods = { { stat = 'MPHEAL', value = 9 }, { stat = 'CLEAR_MIND', value = 1 } } }, { level = 60, rank = 4, mods = { { stat = 'MPHEAL', value = 12 } } }, { level = 70, rank = 5, mods = { { stat = 'MPHEAL', value = 15 }, { stat = 'CLEAR_MIND', value = 2 } } }, { level = 91, rank = 6, tag = 'ABYSSEA', mods = { { stat = 'MPHEAL', value = 18 }, { stat = 'CLEAR_MIND', value = 3 } } } },   -- Clear Mind
}
-- Corsair
M.jobs[17] = {
    [11] = { { level = 15, rank = 1, tag = 'TOAU', mods = { { stat = 'RAPID_SHOT', value = 25 } } }, { level = 91, rank = 2, tag = 'SOA', mods = { { stat = 'RAPID_SHOT', value = 30 } } } },   -- Rapid Shot
}
-- Puppetmaster
M.jobs[18] = {
    [2] = { { level = 20, rank = 1, tag = 'TOAU', mods = { { stat = 'EVA', value = 10 } } }, { level = 40, rank = 2, tag = 'TOAU', mods = { { stat = 'EVA', value = 22 } } }, { level = 60, rank = 3, tag = 'TOAU', mods = { { stat = 'EVA', value = 35 } } }, { level = 76, rank = 4, tag = 'TOAU', mods = { { stat = 'EVA', value = 48 } } } },   -- Evasion Bonus
}
-- Dancer
M.jobs[19] = {
    [1] = { { level = 30, rank = 1, tag = 'WOTG', mods = { { stat = 'ACC', value = 10 }, { stat = 'RACC', value = 10 } } }, { level = 60, rank = 2, tag = 'WOTG', mods = { { stat = 'ACC', value = 22 }, { stat = 'RACC', value = 22 } } }, { level = 76, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'ACC', value = 35 }, { stat = 'RACC', value = 35 } } } },   -- Accuracy Bonus
    [2] = { { level = 15, rank = 1, tag = 'WOTG', mods = { { stat = 'EVA', value = 10 } } }, { level = 45, rank = 2, tag = 'WOTG', mods = { { stat = 'EVA', value = 22 } } }, { level = 75, rank = 3, tag = 'WOTG', mods = { { stat = 'EVA', value = 35 } } }, { level = 86, rank = 4, tag = 'ABYSSEA', mods = { { stat = 'EVA', value = 48 } } } },   -- Evasion Bonus
    [18] = { { level = 20, rank = 1, tag = 'ABYSSEA', mods = { { stat = 'DUAL_WIELD', value = 10 } } }, { level = 40, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'DUAL_WIELD', value = 15 } } }, { level = 60, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'DUAL_WIELD', value = 25 } } }, { level = 80, rank = 4, tag = 'ABYSSEA', mods = { { stat = 'DUAL_WIELD', value = 30 } } } },   -- Dual Wield
    [106] = { { level = 45, rank = 1, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 8 } } }, { level = 58, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 12 } } }, { level = 71, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 16 } } }, { level = 84, rank = 4, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 20 } } }, { level = 97, rank = 4, tag = 'ABYSSEA', mods = { { stat = 'SKILLCHAINBONUS', value = 23 } } } },   -- Skillchain Bonus
}
-- Scholar
M.jobs[20] = {
    [8] = { { level = 30, rank = 1, tag = 'WOTG', mods = { { stat = 'BASE_MP', value = 10 } } }, { level = 88, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'BASE_MP', value = 20 } } } },   -- Max Mp Boost
    [13] = { { level = 25, rank = 1, tag = 'WOTG', mods = { { stat = 'CONSERVE_MP', value = 25 } } } },   -- Conserve Mp
    [24] = { { level = 20, rank = 1, tag = 'WOTG', mods = { { stat = 'MPHEAL', value = 3 } } }, { level = 35, rank = 2, tag = 'WOTG', mods = { { stat = 'MPHEAL', value = 6 } } }, { level = 50, rank = 3, tag = 'WOTG', mods = { { stat = 'MPHEAL', value = 9 }, { stat = 'CLEAR_MIND', value = 1 } } }, { level = 65, rank = 4, tag = 'WOTG', mods = { { stat = 'MPHEAL', value = 12 } } }, { level = 76, rank = 5, tag = 'ABYSSEA', mods = { { stat = 'MPHEAL', value = 15 }, { stat = 'CLEAR_MIND', value = 2 } } }, { level = 96, rank = 6, tag = 'ABYSSEA', mods = { { stat = 'MPHEAL', value = 18 }, { stat = 'CLEAR_MIND', value = 3 } } } },   -- Clear Mind
    [110] = { { level = 79, rank = 1, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_CAPPED', value = 5 } } }, { level = 89, rank = 2, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_CAPPED', value = 7 } } }, { level = 99, rank = 3, tag = 'ABYSSEA', mods = { { stat = 'MAGIC_BURST_BONUS_CAPPED', value = 9 } } } },   -- Mag. Burst Bonus
}
-- Geomancer
M.jobs[21] = {
    [8] = { { level = 30, rank = 1, tag = 'SOA', mods = { { stat = 'BASE_MP', value = 10 } } }, { level = 60, rank = 2, tag = 'SOA', mods = { { stat = 'BASE_MP', value = 20 } } }, { level = 90, rank = 3, tag = 'SOA', mods = { { stat = 'BASE_MP', value = 40 } } } },   -- Max Mp Boost
    [13] = { { level = 10, rank = 1, tag = 'SOA', mods = { { stat = 'CONSERVE_MP', value = 25 } } }, { level = 25, rank = 2, tag = 'SOA', mods = { { stat = 'CONSERVE_MP', value = 28 } } }, { level = 40, rank = 3, tag = 'SOA', mods = { { stat = 'CONSERVE_MP', value = 31 } } }, { level = 55, rank = 4, tag = 'SOA', mods = { { stat = 'CONSERVE_MP', value = 34 } } }, { level = 70, rank = 5, tag = 'SOA', mods = { { stat = 'CONSERVE_MP', value = 37 } } }, { level = 85, rank = 6, tag = 'SOA', mods = { { stat = 'CONSERVE_MP', value = 40 } } }, { level = 99, rank = 7, tag = 'SOA', mods = { { stat = 'CONSERVE_MP', value = 43 } } } },   -- Conserve Mp
    [24] = { { level = 20, rank = 1, tag = 'SOA', mods = { { stat = 'MPHEAL', value = 3 } } }, { level = 40, rank = 2, tag = 'SOA', mods = { { stat = 'MPHEAL', value = 6 } } }, { level = 60, rank = 3, tag = 'SOA', mods = { { stat = 'MPHEAL', value = 9 }, { stat = 'CLEAR_MIND', value = 1 } } }, { level = 80, rank = 4, tag = 'SOA', mods = { { stat = 'MPHEAL', value = 12 } } }, { level = 99, rank = 5, tag = 'SOA', mods = { { stat = 'MPHEAL', value = 15 }, { stat = 'CLEAR_MIND', value = 2 } } } },   -- Clear Mind
}
-- Rune Fencer
M.jobs[22] = {
    [1] = { { level = 50, rank = 1, tag = 'SOA', mods = { { stat = 'ACC', value = 10 }, { stat = 'RACC', value = 10 } } }, { level = 70, rank = 2, tag = 'SOA', mods = { { stat = 'ACC', value = 22 }, { stat = 'RACC', value = 22 } } }, { level = 90, rank = 3, tag = 'SOA', mods = { { stat = 'ACC', value = 35 }, { stat = 'RACC', value = 35 } } } },   -- Accuracy Bonus
    [6] = { { level = 10, rank = 1, tag = 'SOA', mods = { { stat = 'MDEF', value = 10 } } }, { level = 30, rank = 2, tag = 'SOA', mods = { { stat = 'MDEF', value = 12 } } }, { level = 50, rank = 3, tag = 'SOA', mods = { { stat = 'MDEF', value = 14 } } }, { level = 70, rank = 4, tag = 'SOA', mods = { { stat = 'MDEF', value = 16 } } }, { level = 76, rank = 5, tag = 'SOA', mods = { { stat = 'MDEF', value = 18 } } }, { level = 91, rank = 6, tag = 'SOA', mods = { { stat = 'MDEF', value = 20 } } }, { level = 99, rank = 7, tag = 'SOA', mods = { { stat = 'MDEF', value = 22 } } } },   -- Magic Def. Bonus
    [7] = { { level = 20, rank = 1, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 30 } } }, { level = 40, rank = 2, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 60 } } }, { level = 60, rank = 3, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 120 } } }, { level = 80, rank = 4, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 180 } } }, { level = 99, rank = 5, tag = 'SOA', mods = { { stat = 'BASE_HP', value = 240 } } } },   -- Max Hp Boost
    [9] = { { level = 35, rank = 1, tag = 'SOA', mods = { { stat = 'REGEN', value = 1 } } }, { level = 65, rank = 2, tag = 'SOA', mods = { { stat = 'REGEN', value = 2 } } }, { level = 95, rank = 3, tag = 'SOA', mods = { { stat = 'REGEN', value = 3 } } } },   -- Auto Regen
}

return M
