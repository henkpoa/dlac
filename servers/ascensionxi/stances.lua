-- Planning bonuses from modules/custom/sql/artifact_gear.sql in the AXI
-- ascensionxi-03 checkout (2026-09-28). Add new jobs' stance gear here.
-- These are conditional DELTAS, never replacements for the catalog stats.
return {
    RDM = { -- Duelist's Focus / Duelist's Trance (latent 30000, power >= 2)
        [16829] = { Accuracy = 5, Attack = 5 }, -- Fencing Degen
        [12513] = { Accuracy = 6, Attack = 6 }, -- Warlock's Chapeau
        [12642] = { Accuracy = 5, Attack = 5 }, -- Warlock's Tabard
        [13965] = { Accuracy = 5, EnspellDamage = 2 }, -- Warlock's Gloves
        [14218] = { Accuracy = 4, Attack = 6 }, -- Warlock's Tights
        [14093] = { Accuracy = 6 }, -- Warlock's Boots
    },
    WAR = { -- Berserk (status-effect latent 13, effect 56)
        [16678] = { Attack = 10 }, -- Razor Axe
    },
};
