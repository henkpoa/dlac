-- traits.lua -- bludex trait ladder (GENERATED 2026-08-12 by tools/generate_spells.py -- DO NOT EDIT)
-- category -> tiers: set spells whose trait.category matches; sum their
-- trait points; the highest tier with points <= the total is active
-- (server: blueutils.cpp CalculateTraits).
--
-- THE SCALE IS bg-wiki's, NOT base-LSB's. Every ladder costs 8 trait points
-- per rung; a feeder spell pays 4 (6 for Skillchain/Mag. Burst/Gilfinder,
-- 8 for the lv99 spells, per-spell for Auto Refresh). base-LSB mixes that
-- scale with a legacy 1-unit one and ships only the FIRST rung of most
-- ladders -- see tools/generate_spells.py WIKI_LADDER for the whole story.
-- LSB still supplies the shape: which modifiers a ladder moves, and which
-- trait id owns each rung.
--
-- EACH TIER CARRIES ITS OWN traitId -- category 24 is Double Attack (15) at
-- 8 points and Triple Attack (16) at 16 -- and the id is what a job trait
-- suppresses. data/jobtraits.lua holds the other side of that collision.
--
-- confidence = 'verify' would mark rung values still wanting a field
-- reading. NO ladder carries it: every rung value is either bg-wiki's or
-- reconciles with the same trait's job ranks in sql/traits.sql, which the
-- generator checks on every run (blue and job move the SAME modifier).
-- Categories 201/202 are bludex-internal (never on the wire): base-LSB has
-- no blue_traits rows for Magic Eva./Magic Acc. Bonus. They are NOT 29/30 --
-- LSB already uses trait_category 29 for a real spell (Foul Waters).

local M = { categories = {}, traitNames = {} }

M.categories[1] = { name = 'Beast Killer', traitId = 32, tiers = { { points = 8, traitId = 32, mods = { { stat = 'BEAST_KILLER', value = 8 } } }, { points = 16, traitId = 32, mods = { { stat = 'BEAST_KILLER', value = 10 } } }, { points = 24, traitId = 32, mods = { { stat = 'BEAST_KILLER', value = 12 } } } } }
M.categories[2] = { name = 'Auto Regen', traitId = 9, tiers = { { points = 8, traitId = 9, mods = { { stat = 'REGEN', value = 1 } } } } }
M.categories[3] = { name = 'Lizard Killer', traitId = 35, tiers = { { points = 8, traitId = 35, mods = { { stat = 'LIZARD_KILLER', value = 8 } } }, { points = 16, traitId = 35, mods = { { stat = 'LIZARD_KILLER', value = 10 } } } } }
M.categories[4] = { name = 'Clear Mind', traitId = 24, tiers = { { points = 8, traitId = 24, mods = { { stat = 'CLEAR_MIND', value = 1 } } }, { points = 16, traitId = 24, mods = { { stat = 'CLEAR_MIND', value = 2 } } }, { points = 24, traitId = 24, mods = { { stat = 'CLEAR_MIND', value = 3 } } }, { points = 32, traitId = 24, mods = { { stat = 'CLEAR_MIND', value = 4 } } } } }
M.categories[5] = { name = 'Resist Sleep', traitId = 48, tiers = { { points = 8, traitId = 48, mods = { { stat = 'SLEEPRES', value = 10 } } }, { points = 16, traitId = 48, mods = { { stat = 'SLEEPRES', value = 15 } } } } }
M.categories[6] = { name = 'Magic Atk. Bonus', traitId = 5, tiers = { { points = 8, traitId = 5, mods = { { stat = 'MATT', value = 20 } } }, { points = 16, traitId = 5, mods = { { stat = 'MATT', value = 24 } } }, { points = 24, traitId = 5, mods = { { stat = 'MATT', value = 28 } } }, { points = 32, traitId = 5, mods = { { stat = 'MATT', value = 32 } } } } }
M.categories[7] = { name = 'Undead Killer', traitId = 39, tiers = { { points = 8, traitId = 39, mods = { { stat = 'UNDEAD_KILLER', value = 8 } } } } }
M.categories[8] = { name = 'Attack Bonus', traitId = 3, tiers = { { points = 8, traitId = 3, mods = { { stat = 'ATT', value = 10 }, { stat = 'RATT', value = 10 } } }, { points = 16, traitId = 3, mods = { { stat = 'ATT', value = 22 }, { stat = 'RATT', value = 22 } } }, { points = 24, traitId = 3, mods = { { stat = 'ATT', value = 35 }, { stat = 'RATT', value = 35 } } }, { points = 32, traitId = 3, mods = { { stat = 'ATT', value = 48 }, { stat = 'RATT', value = 48 } } } } }
M.categories[9] = { name = 'Rapid Shot', traitId = 11, tiers = { { points = 8, traitId = 11, mods = { { stat = 'RAPID_SHOT', value = 25 } } } } }
M.categories[10] = { name = 'Max Mp Boost', traitId = 8, tiers = { { points = 8, traitId = 8, mods = { { stat = 'MP', value = 10 } } }, { points = 16, traitId = 8, mods = { { stat = 'MP', value = 20 } } } } }
M.categories[11] = { name = 'Defense Bonus', traitId = 4, tiers = { { points = 8, traitId = 4, mods = { { stat = 'DEF', value = 10 } } }, { points = 16, traitId = 4, mods = { { stat = 'DEF', value = 22 } } }, { points = 24, traitId = 4, mods = { { stat = 'DEF', value = 35 } } }, { points = 32, traitId = 4, mods = { { stat = 'DEF', value = 48 } } } } }
M.categories[12] = { name = 'Plantoid Killer', traitId = 33, tiers = { { points = 8, traitId = 33, mods = { { stat = 'PLANTOID_KILLER', value = 8 } } } } }
M.categories[13] = { name = 'Magic Def. Bonus', traitId = 6, tiers = { { points = 8, traitId = 6, mods = { { stat = 'MDEF', value = 10 } } }, { points = 16, traitId = 6, mods = { { stat = 'MDEF', value = 12 } } }, { points = 24, traitId = 6, mods = { { stat = 'MDEF', value = 14 } } } } }
M.categories[14] = { name = 'Auto Refresh', traitId = 10, tiers = { { points = 8, traitId = 10, mods = { { stat = 'REFRESH', value = 1 } } } } }
M.categories[15] = { name = 'Max Hp Boost', traitId = 7, tiers = { { points = 8, traitId = 7, mods = { { stat = 'BASE_HP', value = 30 } } }, { points = 16, traitId = 7, mods = { { stat = 'BASE_HP', value = 60 } } }, { points = 24, traitId = 7, mods = { { stat = 'BASE_HP', value = 120 } } }, { points = 32, traitId = 7, mods = { { stat = 'BASE_HP', value = 180 } } } } }
M.categories[16] = { name = 'Accuracy Bonus', traitId = 1, tiers = { { points = 8, traitId = 1, mods = { { stat = 'ACC', value = 10 }, { stat = 'RACC', value = 10 } } }, { points = 16, traitId = 1, mods = { { stat = 'ACC', value = 22 }, { stat = 'RACC', value = 22 } } }, { points = 24, traitId = 1, mods = { { stat = 'ACC', value = 35 }, { stat = 'RACC', value = 35 } } }, { points = 32, traitId = 1, mods = { { stat = 'ACC', value = 48 }, { stat = 'RACC', value = 48 } } } } }
M.categories[17] = { name = 'Conserve Mp', traitId = 13, tiers = { { points = 8, traitId = 13, mods = { { stat = 'CONSERVE_MP', value = 25 } } }, { points = 16, traitId = 13, mods = { { stat = 'CONSERVE_MP', value = 28 } } }, { points = 24, traitId = 13, mods = { { stat = 'CONSERVE_MP', value = 31 } } } } }
M.categories[18] = { name = 'Evasion Bonus', traitId = 2, tiers = { { points = 8, traitId = 2, mods = { { stat = 'EVA', value = 10 } } }, { points = 16, traitId = 2, mods = { { stat = 'EVA', value = 22 } } }, { points = 24, traitId = 2, mods = { { stat = 'EVA', value = 35 } } } } }
M.categories[19] = { name = 'Resist Gravity', traitId = 58, tiers = { { points = 8, traitId = 58, mods = { { stat = 'GRAVITYRES', value = 10 } } } } }
M.categories[20] = { name = 'Store Tp', traitId = 14, tiers = { { points = 8, traitId = 14, mods = { { stat = 'STORETP', value = 10 } } }, { points = 16, traitId = 14, mods = { { stat = 'STORETP', value = 15 } } }, { points = 24, traitId = 14, mods = { { stat = 'STORETP', value = 20 } } } } }
M.categories[21] = { name = 'Counter', traitId = 17, tiers = { { points = 8, traitId = 17, mods = { { stat = 'COUNTER', value = 10 } } }, { points = 16, traitId = 17, mods = { { stat = 'COUNTER', value = 12 } } } } }
M.categories[22] = { name = 'Fast Cast', traitId = 12, tiers = { { points = 8, traitId = 12, mods = { { stat = 'FASTCAST', value = 5 } } }, { points = 16, traitId = 12, mods = { { stat = 'FASTCAST', value = 10 } } }, { points = 24, traitId = 12, mods = { { stat = 'FASTCAST', value = 15 } } } } }
M.categories[23] = { name = 'Skillchain Bonus', traitId = 106, tiers = { { points = 8, traitId = 106, mods = { { stat = 'SKILLCHAINBONUS', value = 8 } } }, { points = 16, traitId = 106, mods = { { stat = 'SKILLCHAINBONUS', value = 12 } } }, { points = 24, traitId = 106, mods = { { stat = 'SKILLCHAINBONUS', value = 16 } } } } }
M.categories[24] = { name = 'Double Attack', traitId = 15, tiers = { { points = 8, traitId = 15, mods = { { stat = 'DOUBLE_ATTACK', value = 7 } } }, { points = 16, traitId = 16, mods = { { stat = 'TRIPLE_ATTACK', value = 5 } } } } }
M.categories[25] = { name = 'Dual Wield', traitId = 18, tiers = { { points = 8, traitId = 18, mods = { { stat = 'DUAL_WIELD', value = 10 } } }, { points = 16, traitId = 18, mods = { { stat = 'DUAL_WIELD', value = 15 } } }, { points = 24, traitId = 18, mods = { { stat = 'DUAL_WIELD', value = 25 } } }, { points = 32, traitId = 18, mods = { { stat = 'DUAL_WIELD', value = 30 } } } } }
M.categories[26] = { name = 'Zanshin', traitId = 70, tiers = { { points = 8, traitId = 70, mods = { { stat = 'ZANSHIN', value = 15 } } } } }
M.categories[27] = { name = 'Mag. Burst Bonus', traitId = 110, tiers = { { points = 8, traitId = 110, mods = { { stat = 'MAGIC_BURST_BONUS_CAPPED', value = 5 } } }, { points = 16, traitId = 110, mods = { { stat = 'MAGIC_BURST_BONUS_CAPPED', value = 7 } } }, { points = 24, traitId = 110, mods = { { stat = 'MAGIC_BURST_BONUS_CAPPED', value = 9 } } } } }
M.categories[28] = { name = 'Gilfinder', traitId = 20, tiers = { { points = 8, traitId = 20, mods = { { stat = 'GILFINDER', value = 1 } } }, { points = 16, traitId = 19, mods = { { stat = 'TREASURE_HUNTER', value = 1 } } } } }
M.categories[201] = { name = 'Magic Eva. Bonus', traitId = 126, tiers = { { points = 8, traitId = 126, mods = { { stat = 'MEVA', value = 10 } } } } }
M.categories[202] = { name = 'Magic Acc. Bonus', traitId = 125, tiers = { { points = 8, traitId = 125, mods = { { stat = 'MACC', value = 10 } } } } }

-- each rung's OWN trait name (a ladder can change trait partway up)
M.traitNames[1] = 'Accuracy Bonus'
M.traitNames[2] = 'Evasion Bonus'
M.traitNames[3] = 'Attack Bonus'
M.traitNames[4] = 'Defense Bonus'
M.traitNames[5] = 'Magic Atk. Bonus'
M.traitNames[6] = 'Magic Def. Bonus'
M.traitNames[7] = 'Max Hp Boost'
M.traitNames[8] = 'Max Mp Boost'
M.traitNames[9] = 'Auto Regen'
M.traitNames[10] = 'Auto Refresh'
M.traitNames[11] = 'Rapid Shot'
M.traitNames[12] = 'Fast Cast'
M.traitNames[13] = 'Conserve Mp'
M.traitNames[14] = 'Store Tp'
M.traitNames[15] = 'Double Attack'
M.traitNames[16] = 'Triple Attack'
M.traitNames[17] = 'Counter'
M.traitNames[18] = 'Dual Wield'
M.traitNames[19] = 'Treasure Hunter'
M.traitNames[20] = 'Gilfinder'
M.traitNames[24] = 'Clear Mind'
M.traitNames[32] = 'Beast Killer'
M.traitNames[33] = 'Plantoid Killer'
M.traitNames[35] = 'Lizard Killer'
M.traitNames[39] = 'Undead Killer'
M.traitNames[48] = 'Resist Sleep'
M.traitNames[58] = 'Resist Gravity'
M.traitNames[70] = 'Zanshin'
M.traitNames[106] = 'Skillchain Bonus'
M.traitNames[110] = 'Mag. Burst Bonus'
M.traitNames[125] = 'Magic Acc. Bonus'
M.traitNames[126] = 'Magic Eva. Bonus'

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
