-- traits.lua -- bludex trait ladder (GENERATED 2026-08-04 by tools/generate_spells.py -- DO NOT EDIT)
-- category -> tiers: set spells whose trait.category matches; sum their weights;
-- highest tier with points <= total weight is active (server: blueutils.cpp CalculateTraits).
-- Values are base-LSB (public clone); CEXI may override in private submodules.

local M = { categories = {} }

M.categories[1] = { name = 'Beast Killer', traitId = 32, tiers = { { points = 2, mods = { { stat = 'BEAST_KILLER', value = 8 } } } } }
M.categories[2] = { name = 'Auto Regen', traitId = 9, tiers = { { points = 2, mods = { { stat = 'REGEN', value = 1 } } } } }
M.categories[3] = { name = 'Lizard Killer', traitId = 35, tiers = { { points = 2, mods = { { stat = 'LIZARD_KILLER', value = 8 } } } } }
M.categories[4] = { name = 'Clear Mind', traitId = 24, tiers = { { points = 2, mods = { { stat = 'CLEAR_MIND', value = 1 } } }, { points = 4, mods = { { stat = 'CLEAR_MIND', value = 2 } } }, { points = 6, mods = { { stat = 'CLEAR_MIND', value = 3 } } }, { points = 8, mods = { { stat = 'CLEAR_MIND', value = 4 } } } } }
M.categories[5] = { name = 'Resist Sleep', traitId = 48, tiers = { { points = 2, mods = { { stat = 'SLEEPRES', value = 2 } } } } }
M.categories[6] = { name = 'Magic Atk. Bonus', traitId = 5, tiers = { { points = 2, mods = { { stat = 'MATT', value = 20 } } } } }
M.categories[7] = { name = 'Undead Killer', traitId = 39, tiers = { { points = 2, mods = { { stat = 'UNDEAD_KILLER', value = 8 } } } } }
M.categories[8] = { name = 'Attack Bonus', traitId = 3, tiers = { { points = 2, mods = { { stat = 'ATT', value = 10 }, { stat = 'RATT', value = 10 } } } } }
M.categories[9] = { name = 'Rapid Shot', traitId = 11, tiers = { { points = 2, mods = { { stat = 'RAPID_SHOT', value = 10 } } } } }
M.categories[10] = { name = 'Max Mp Boost', traitId = 8, tiers = { { points = 2, mods = { { stat = 'MP', value = 10 } } }, { points = 4, mods = { { stat = 'MP', value = 30 } } } } }
M.categories[11] = { name = 'Defense Bonus', traitId = 4, tiers = { { points = 2, mods = { { stat = 'DEF', value = 10 } } } } }
M.categories[12] = { name = 'Plantoid Killer', traitId = 33, tiers = { { points = 2, mods = { { stat = 'PLANTOID_KILLER', value = 8 } } } } }
M.categories[13] = { name = 'Magic Def. Bonus', traitId = 6, tiers = { { points = 2, mods = { { stat = 'MDEF', value = 10 } } } } }
M.categories[14] = { name = 'Auto Refresh', traitId = 10, tiers = { { points = 8, mods = { { stat = 'REFRESH', value = 1 } } } } }
M.categories[15] = { name = 'Max Hp Boost', traitId = 7, tiers = { { points = 8, mods = { { stat = 'BASE_HP', value = 30 } } }, { points = 16, mods = { { stat = 'BASE_HP', value = 60 } } }, { points = 24, mods = { { stat = 'BASE_HP', value = 120 } } }, { points = 32, mods = { { stat = 'BASE_HP', value = 180 } } } } }
M.categories[16] = { name = 'Accuracy Bonus', traitId = 1, tiers = { { points = 2, mods = { { stat = 'ACC', value = 10 }, { stat = 'RACC', value = 10 } } } } }
M.categories[17] = { name = 'Conserve Mp', traitId = 13, tiers = { { points = 2, mods = { { stat = 'CONSERVE_MP', value = 25 } } } } }
M.categories[18] = { name = 'Evasion Bonus', traitId = 2, tiers = { { points = 2, mods = { { stat = 'EVA', value = 10 } } } } }
M.categories[19] = { name = 'Resist Gravity', traitId = 58, tiers = { { points = 2, mods = { { stat = 'GRAVITYRES', value = 2 } } } } }
M.categories[20] = { name = 'Store Tp', traitId = 14, tiers = { { points = 2, mods = { { stat = 'STORETP', value = 10 } } }, { points = 4, mods = { { stat = 'STORETP', value = 25 } } } } }
M.categories[21] = { name = 'Counter', traitId = 17, tiers = { { points = 2, mods = { { stat = 'COUNTER', value = 10 } } } } }
M.categories[22] = { name = 'Fast Cast', traitId = 12, tiers = { { points = 2, mods = { { stat = 'FASTCAST', value = 5 } } }, { points = 4, mods = { { stat = 'FASTCAST', value = 15 } } } } }
M.categories[23] = { name = 'Skillchain Bonus', traitId = 106, tiers = { { points = 2, mods = { { stat = 'SKILLCHAINBONUS', value = 8 } } } } }
M.categories[24] = { name = 'Double Attack', traitId = 15, tiers = { { points = 2, mods = { { stat = 'DOUBLE_ATTACK', value = 7 } } }, { points = 4, mods = { { stat = 'TRIPLE_ATTACK', value = 5 } } } } }
M.categories[25] = { name = 'Dual Wield', traitId = 18, tiers = { { points = 2, mods = { { stat = 'DUAL_WIELD', value = 10 } } }, { points = 4, mods = { { stat = 'DUAL_WIELD', value = 15 } } }, { points = 6, mods = { { stat = 'DUAL_WIELD', value = 25 } } } } }
M.categories[26] = { name = 'Zanshin', traitId = 70, tiers = { { points = 2, mods = { { stat = 'ZANSHIN', value = 15 } } } } }
M.categories[27] = { name = 'Mag. Burst Bonus', traitId = 110, tiers = { { points = 2, mods = { { stat = 'MAGIC_BURST_BONUS_CAPPED', value = 5 } } } } }
M.categories[28] = { name = 'Gilfinder', traitId = 20, tiers = { { points = 2, mods = { { stat = 'GILFINDER', value = 1 } } }, { points = 3, mods = { { stat = 'TREASURE_HUNTER', value = 1 } } } } }

-- Set-point budget law (server: blueutils.cpp GetTotalBlueMagicPoints):
--   base = clamp(((level-1)/10)*5 + 10, 0, 55)  -- level 75 => 45
--   + Assimilation merits  + Job-Point gift bonus
-- The summed bonus arrives on packet 0x063 (misc merit data) -- read it live;
-- never hardcode a total. Field facts (Henrik, 2026-08-04, CEXI custom):
--   assimilationPerMerit = 2 (stock LSB: 1); expected total at 75 ~= 80.
M.rules = {
    baseCap = 55,
    baseAt75 = 45,
    assimilationPerMerit = 2,  -- field (CEXI custom, stock = 1)
    expectedTotalAt75 = 80,    -- field: 79 observed with spells still to learn;
                               -- learning spells contributes points (CEXI custom)
    slotCount = 20,
}

return M
