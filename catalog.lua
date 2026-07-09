-- catalog.lua -- full CatsEyeXI equipment reference (crawled from the live API).
-- Rebuild/extend with: python tools/apicrawl.py
return {
    Main = {
        HandToHand = {
            AdamanSainti = {
                Name = "Adaman Sainti",
                Level = 70,
                Id = 18745,
                Jobs = {"PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 18,
                    Delay = 531,
                    Accuracy = 2,
                    Evasion = 1,
                }
            },
            Birdbanes = {
                Name = "Birdbanes",
                Level = 54,
                Id = 18767,
                Jobs = {"WAR", "MNK", "RDM", "DRK", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 14,
                    Delay = 564,
                }
            },
            BlurredClaws = {
                Name = "Blurred Claws",
                Level = 75,
                Id = 20525,
                Jobs = {"MNK", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 18,
                    Delay = 576,
                    STR = 7,
                    VIT = 7,
                    Accuracy = 10,
                }
            },
            BlurredClaws_1 = {
                Name = "Blurred Claws +1",
                Level = 75,
                Id = 20526,
                Jobs = {"MNK", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 19,
                    Delay = 571,
                    STR = 8,
                    VIT = 8,
                    Accuracy = 12,
                }
            },
            BuzbazSainti = {
                Name = "Buzbaz Sainti",
                Level = 75,
                Id = 18791,
                Jobs = {"PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 18,
                    Delay = 531,
                }
            },
            BuzbazSainti_1 = {
                Name = "Buzbaz Sainti +1",
                Level = 75,
                Id = 18792,
                Jobs = {"PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 19,
                    Delay = 529,
                }
            },
            CatBaghnakhs = {
                Name = "Cat Baghnakhs",
                Level = 1,
                Id = 16405,
                Jobs = {"WAR", "MNK", "RDM", "THF", "DRK", "BST", "NIN", "PUP", "DNC"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 2,
                    Delay = 540,
                }
            },
            CatBaghnakhs_1 = {
                Name = "Cat Baghnakhs +1",
                Level = 1,
                Id = 17476,
                Jobs = {"WAR", "MNK", "RDM", "THF", "DRK", "BST", "NIN", "PUP", "DNC"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 3,
                    Delay = 531,
                }
            },
            Claws = {
                Name = "Claws",
                Level = 30,
                Id = 16411,
                Jobs = {"WAR", "MNK", "DRK", "BST", "NIN", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 7,
                    Delay = 546,
                }
            },
            Claws_1 = {
                Name = "Claws +1",
                Level = 30,
                Id = 16445,
                Jobs = {"WAR", "MNK", "DRK", "BST", "NIN", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 8,
                    Delay = 541,
                }
            },
            FedBaghnakhs = {
                Name = "Fed. Baghnakhs",
                Level = 15,
                Id = 17498,
                Jobs = {"WAR", "MNK", "RDM", "THF", "DRK", "BST", "NIN", "PUP", "DNC"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 5,
                    Delay = 528,
                    Accuracy = 2,
                }
            },
            HepatizonBaghnakhs = {
                Name = "Hepatizon Baghnakhs",
                Level = 72,
                Id = 21511,
                Jobs = {"WAR", "MNK", "RDM", "THF", "DRK", "BST", "NIN", "PUP", "DNC"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 21,
                    Delay = 570,
                    STR = 6,
                    VIT = 6,
                    Accuracy = 10,
                }
            },
            HepatizonBaghnakhs_1 = {
                Name = "Hepatizon Baghnakhs +1",
                Level = 72,
                Id = 21512,
                Jobs = {"WAR", "MNK", "RDM", "THF", "DRK", "BST", "NIN", "PUP", "DNC"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 22,
                    Delay = 561,
                    STR = 8,
                    VIT = 8,
                    Accuracy = 15,
                }
            },
            Manoples = {
                Name = "Manoples",
                Level = 74,
                Id = 16423,
                Jobs = {"WAR", "MNK", "BST", "NIN", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 20,
                    Delay = 602,
                    VIT = 2,
                }
            },
            Maochinoli = {
                Name = "Maochinoli",
                Level = 75,
                Id = 20543,
                Jobs = {"MNK", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 18,
                    Delay = 576,
                    STR = 3,
                    DEX = 3,
                    Attack = 5,
                    Evasion = 5,
                    StoreTP = 3,
                }
            },
            MarathBaghnakhs = {
                Name = "Marath Baghnakhs",
                Level = 73,
                Id = 18789,
                Jobs = {"WAR", "MNK", "RDM", "THF", "DRK", "BST", "NIN", "PUP", "DNC"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 17,
                    Delay = 540,
                    STR = 2,
                    DEX = 2,
                    Accuracy = 3,
                    Attack = 8,
                }
            },
            MetasomaKatars = {
                Name = "Metasoma Katars",
                Level = 69,
                Id = 18784,
                Jobs = {"WAR", "MNK", "RDM", "DRK", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 17,
                    Delay = 564,
                    Attack = 5,
                }
            },
            Nyepel = {
                Name = "Nyepel",
                Level = 75,
                Id = 20534,
                Jobs = {"MNK"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 20,
                    Delay = 561,
                    HP = 35,
                    STR = 4,
                    VIT = 4,
                    Attack = 8,
                    StoreTP = 5,
                    Enmity = 4,
                    Counter = 6,
                }
            },
            Ohrmazd = {
                Name = "Ohrmazd",
                Level = 75,
                Id = 20530,
                Jobs = {"MNK", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 30,
                    Delay = 576,
                    STR = 10,
                    Accuracy = 20,
                    Counter = 10,
                }
            },
            Ohtas = {
                Name = "Ohtas",
                Level = 75,
                Id = 20535,
                Jobs = {"PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 20,
                    Delay = 564,
                    HP = 20,
                    DEX = 4,
                    AGI = 4,
                    Accuracy = 8,
                    Enmity = -4,
                }
            },
            Patas_1 = {
                Name = "Patas +1",
                Level = 48,
                Id = 16696,
                Jobs = {"WAR", "MNK", "BST", "NIN", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 15,
                    Delay = 566,
                }
            },
            Persuasion = {
                Name = "Persuasion",
                Level = 20,
                Id = 21510,
                Jobs = {"MNK", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 12,
                    Delay = 576,
                    STR = 3,
                    Accuracy = 5,
                }
            },
            Persuasion_1 = {
                Name = "Persuasion +1",
                Level = 50,
                Id = 20531,
                Jobs = {"MNK", "PUP"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 20,
                    Delay = 576,
                    STR = 5,
                    Accuracy = 8,
                    Counter = 5,
                }
            },
            ShivajiBaghnakhs = {
                Name = "Shivaji Baghnakhs",
                Level = 73,
                Id = 18790,
                Jobs = {"WAR", "MNK", "RDM", "THF", "DRK", "BST", "NIN", "PUP", "DNC"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 18,
                    Delay = 537,
                    STR = 3,
                    DEX = 3,
                    Accuracy = 4,
                    Attack = 9,
                }
            },
            TropicalPunches = {
                Name = "Tropical Punches",
                Level = 10,
                Id = 17493,
                Jobs = {"MNK"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 1,
                    Delay = 480,
                    Accuracy = 10,
                }
            },
            TrpPunches_1 = {
                Name = "Trp. Punches +1",
                Level = 10,
                Id = 17494,
                Jobs = {"MNK"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 2,
                    Delay = 480,
                    Accuracy = 12,
                }
            },
            WinBaghnakhs = {
                Name = "Win. Baghnakhs",
                Level = 15,
                Id = 17497,
                Jobs = {"WAR", "MNK", "RDM", "THF", "DRK", "BST", "NIN", "PUP", "DNC"},
                OneHanded = true,
                Type = "HandToHand",
                Stats = {
                    DMG = 4,
                    Delay = 537,
                    Accuracy = 1,
                }
            },
        },
        Dagger = {
            AdamanKris = {
                Name = "Adaman Kris",
                Level = 70,
                Id = 16461,
                Jobs = {"BLM", "SMN", "SCH", "GEO"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 23,
                    Delay = 192,
                    MP = 10,
                    DEX = 2,
                    VIT = 2,
                    INT = 2,
                }
            },
            ArchersKnife = {
                Name = "Archers Knife",
                Level = 28,
                Id = 16755,
                Jobs = {"WAR", "THF", "PLD", "DRK", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 11,
                    Delay = 195,
                    AGI = 1,
                    RangedAccuracy = 10,
                }
            },
            Atoyac = {
                Name = "Atoyac",
                Level = 75,
                Id = 20630,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "NIN", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 33,
                    Delay = 200,
                    DEX = 3,
                    AGI = 3,
                    Evasion = 3,
                    SubtleBlow = 5,
                }
            },
            Beestinger = {
                Name = "Beestinger",
                Level = 7,
                Id = 16486,
                Jobs = {"RDM", "THF", "BRD", "RNG", "NIN"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 4,
                    Delay = 150,
                    DEX = 1,
                    AGI = 1,
                }
            },
            BerylliumKris = {
                Name = "Beryllium Kris",
                Level = 72,
                Id = 21556,
                Jobs = {"BLM", "SMN", "SCH", "GEO"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 39,
                    Delay = 192,
                    MP = 25,
                    STR = 6,
                    DEX = 6,
                    Accuracy = 10,
                }
            },
            BerylliumKris_1 = {
                Name = "Beryllium Kris +1",
                Level = 72,
                Id = 21557,
                Jobs = {"BLM", "SMN", "SCH", "GEO"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 45,
                    Delay = 187,
                    MP = 30,
                    STR = 8,
                    DEX = 8,
                    Accuracy = 15,
                }
            },
            BronzeDagger_1 = {
                Name = "Bronze Dagger +1",
                Level = 1,
                Id = 16492,
                Jobs = {"WAR", "BLM", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "SMN", "SCH", "GEO"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 4,
                    Delay = 178,
                }
            },
            Bushwhacker = {
                Name = "Bushwhacker",
                Level = 20,
                Id = 21566,
                Jobs = {"THF", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 14,
                    Delay = 200,
                    DEX = 4,
                    CHR = 4,
                    CriticalHitRate = 3,
                }
            },
            DecurionsDagger = {
                Name = "Decurions Dagger",
                Level = 20,
                Id = 16745,
                Jobs = {"WAR", "BLM", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "SMN", "SCH", "GEO"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 10,
                    Delay = 178,
                    Accuracy = 2,
                }
            },
            GorkhaliKukri = {
                Name = "Gorkhali Kukri",
                Level = 73,
                Id = 19788,
                Jobs = {"WAR", "THF", "DRK", "RNG", "NIN", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 32,
                    Delay = 200,
                    DEF = 10,
                    HP = 10,
                    MagicDefenseBonus = 2,
                }
            },
            Gully = {
                Name = "Gully",
                Level = 72,
                Id = 16470,
                Jobs = {"WAR", "THF", "PLD", "DRK", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 29,
                    Delay = 205,
                    HP = 10,
                    DEX = 2,
                    VIT = 2,
                }
            },
            HawkersKnife = {
                Name = "Hawkers Knife",
                Level = 30,
                Id = 17630,
                Jobs = {"BST", "RNG"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 12,
                    Delay = 195,
                    AGI = 2,
                    CHR = 2,
                    RangedAccuracy = 11,
                }
            },
            HawkersKnife_1 = {
                Name = "Hawkers Knife +1",
                Level = 30,
                Id = 17631,
                Jobs = {"BST", "RNG"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 13,
                    Delay = 190,
                    AGI = 3,
                    CHR = 3,
                    RangedAccuracy = 12,
                }
            },
            Hornetneedle = {
                Name = "Hornetneedle",
                Level = 48,
                Id = 17980,
                Jobs = {"RDM", "THF", "BRD", "RNG", "NIN"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 16,
                    Delay = 150,
                    DEX = 1,
                    AGI = 1,
                }
            },
            Ipetam = {
                Name = "Ipetam",
                Level = 75,
                Id = 20616,
                Jobs = {"THF", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 38,
                    Delay = 200,
                    DEX = 10,
                    CHR = 10,
                    TripleAttack = 3,
                    CriticalHitRate = 9,
                    CurePotency = 10,
                }
            },
            JacksKnife = {
                Name = "Jacks Knife",
                Level = 8,
                Id = 20615,
                Jobs = {"BRD", "RNG", "COR", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 7,
                    Delay = 175,
                    AGI = 2,
                    CHR = 2,
                }
            },
            Knife = {
                Name = "Knife",
                Level = 13,
                Id = 16466,
                Jobs = {"WAR", "THF", "PLD", "DRK", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 8,
                    Delay = 195,
                }
            },
            Machismo = {
                Name = "Machismo",
                Level = 75,
                Id = 19118,
                Jobs = {"RDM", "THF", "BST", "BRD", "RNG", "NIN", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 34,
                    Delay = 196,
                }
            },
            MahakalisKukri = {
                Name = "Mahakalis Kukri",
                Level = 73,
                Id = 19789,
                Jobs = {"WAR", "THF", "DRK", "RNG", "NIN", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 33,
                    Delay = 194,
                    DEF = 15,
                    HP = 15,
                    MagicDefenseBonus = 3,
                }
            },
            Malevolence = {
                Name = "Malevolence",
                Level = 75,
                Id = 20595,
                Jobs = {"BLM", "SMN", "SCH", "GEO"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 33,
                    Delay = 201,
                    INT = 9,
                    MagicAttackBonus = 9,
                }
            },
            MaraudersKnife = {
                Name = "Marauders Knife",
                Level = 40,
                Id = 16764,
                Jobs = {"THF"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 15,
                    Delay = 195,
                    DEX = 2,
                    AGI = 2,
                }
            },
            MercenarysKnife = {
                Name = "Mercenarys Knife",
                Level = 20,
                Id = 16746,
                Jobs = {"WAR", "THF", "PLD", "DRK", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 11,
                    Delay = 190,
                    Accuracy = 2,
                }
            },
            MercurialKris = {
                Name = "Mercurial Kris",
                Level = 50,
                Id = 18020,
                Jobs = {"WAR", "THF", "PLD", "DRK", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 8,
                    Delay = 192,
                }
            },
            Misericorde = {
                Name = "Misericorde",
                Level = 71,
                Id = 16452,
                Jobs = {"WAR", "BLM", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "SMN", "SCH", "GEO"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 27,
                    Delay = 183,
                    MP = 10,
                    DEX = 2,
                    VIT = 2,
                    MND = 2,
                }
            },
            MrcCptKukri = {
                Name = "Mrc.Cpt. Kukri",
                Level = 30,
                Id = 16747,
                Jobs = {"WAR", "THF", "DRK", "RNG", "NIN", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 13,
                    Delay = 194,
                    Accuracy = 3,
                }
            },
            OneirosKnife = {
                Name = "Oneiros Knife",
                Level = 75,
                Id = 19141,
                Jobs = {"RDM", "THF", "BRD", "RNG", "NIN", "COR"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 38,
                    Delay = 150,
                    AGI = 6,
                }
            },
            ParryingKnife = {
                Name = "Parrying Knife",
                Level = 25,
                Id = 16754,
                Jobs = {"WAR", "THF", "PLD", "DRK", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 11,
                    Delay = 195,
                }
            },
            Polyhymnia = {
                Name = "Polyhymnia",
                Level = 75,
                Id = 20619,
                Jobs = {"DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 35,
                    Delay = 194,
                    HP = 20,
                    DEX = 4,
                    AGI = 4,
                    Accuracy = 8,
                    Evasion = 5,
                    Enmity = 4,
                }
            },
            RangingKnife = {
                Name = "Ranging Knife",
                Level = 24,
                Id = 19119,
                Jobs = {"WAR", "THF", "PLD", "DRK", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 7,
                    Delay = 195,
                    RangedAccuracy = 6,
                }
            },
            RangingKnife_1 = {
                Name = "Ranging Knife +1",
                Level = 24,
                Id = 19127,
                Jobs = {"WAR", "THF", "PLD", "DRK", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 8,
                    Delay = 190,
                    RangedAccuracy = 7,
                }
            },
            RylSqrDagger = {
                Name = "Ryl.Sqr. Dagger",
                Level = 30,
                Id = 16744,
                Jobs = {"WAR", "BLM", "RDM", "THF", "PLD", "BRD", "NIN", "SCH", "GEO"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 12,
                    Delay = 181,
                    Accuracy = 3,
                }
            },
            Sandung = {
                Name = "Sandung",
                Level = 75,
                Id = 20618,
                Jobs = {"THF"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 35,
                    Delay = 200,
                    HP = 15,
                    DEX = 4,
                    AGI = 4,
                    Accuracy = 8,
                    Evasion = 5,
                    Enmity = 4,
                    TripleAttack = 1,
                }
            },
            TamingSari = {
                Name = "Taming Sari",
                Level = 75,
                Id = 20596,
                Jobs = {"THF", "BRD", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 29,
                    Delay = 211,
                    STR = 3,
                    DEX = 7,
                    SubtleBlow = 8,
                }
            },
            TerrapinTraitor = {
                Name = "Terrapin Traitor",
                Level = 20,
                Id = 20597,
                Jobs = {"THF", "BRD", "RNG", "COR", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 5,
                    Delay = 201,
                }
            },
            ThiefsKnife = {
                Name = "Thiefs Knife",
                Level = 70,
                Id = 16480,
                Jobs = {"THF"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 28,
                    Delay = 194,
                }
            },
            ThugsJambiya = {
                Name = "Thugs Jambiya",
                Level = 30,
                Id = 19105,
                Jobs = {"WAR", "THF", "PLD", "DRK", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
                OneHanded = true,
                Type = "Dagger",
                Stats = {
                    DMG = 13,
                    Delay = 201,
                    DEX = 1,
                }
            },
        },
        Sword = {
            AdamanKilij = {
                Name = "Adaman Kilij",
                Level = 73,
                Id = 17727,
                Jobs = {"BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 41,
                    Delay = 236,
                    MP = 15,
                    DEX = 2,
                    VIT = 2,
                }
            },
            Anelace = {
                Name = "Anelace",
                Level = 72,
                Id = 16547,
                Jobs = {"WAR", "RDM", "PLD", "DRK", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 39,
                    Delay = 233,
                    HP = 10,
                    DEX = 2,
                    VIT = 2,
                }
            },
            AnthosXiphos = {
                Name = "Anthos Xiphos",
                Level = 25,
                Id = 17750,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "NIN", "DRG", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 17,
                    Delay = 228,
                    STR = 1,
                }
            },
            Apaisante = {
                Name = "Apaisante",
                Level = 73,
                Id = 18910,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "NIN", "DRG", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 40,
                    Delay = 228,
                    MP = 15,
                    MND = 3,
                }
            },
            Apaisante_1 = {
                Name = "Apaisante +1",
                Level = 73,
                Id = 18911,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "NIN", "DRG", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 41,
                    Delay = 222,
                    MP = 20,
                    MND = 4,
                }
            },
            BeeSpatha = {
                Name = "Bee Spatha",
                Level = 11,
                Id = 16572,
                Jobs = {"WAR", "RDM", "PLD", "DRK", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 13,
                    Delay = 233,
                }
            },
            BeeSpatha_1 = {
                Name = "Bee Spatha +1",
                Level = 11,
                Id = 16611,
                Jobs = {"WAR", "RDM", "PLD", "DRK", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 14,
                    Delay = 227,
                    Accuracy = 2,
                }
            },
            Bilbo_1 = {
                Name = "Bilbo +1",
                Level = 13,
                Id = 16632,
                Jobs = {"WAR", "BLM", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "NIN", "DRG", "COR", "DNC", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 12,
                    Delay = 220,
                }
            },
            BrassXiphos = {
                Name = "Brass Xiphos",
                Level = 13,
                Id = 16531,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "NIN", "DRG", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 12,
                    Delay = 228,
                }
            },
            BrassXiphos_1 = {
                Name = "Brass Xiphos +1",
                Level = 13,
                Id = 16802,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "NIN", "DRG", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 13,
                    Delay = 222,
                }
            },
            Brilliance = {
                Name = "Brilliance",
                Level = 75,
                Id = 20705,
                Jobs = {"WAR", "PLD", "DRK"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 48,
                    Delay = 228,
                    HPP = 5,
                    MND = 10,
                    Enmity = 5,
                    CurePotency = 15,
                }
            },
            ClaidheamhSoluis = {
                Name = "Claidheamh Soluis",
                Level = 75,
                Id = 20718,
                Jobs = {"PLD", "BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 52,
                    Delay = 240,
                    DEF = 20,
                    STR = 10,
                    VIT = 10,
                    Accuracy = 20,
                    StoreTP = 7,
                    CurePotency = 10,
                }
            },
            Concordia = {
                Name = "Concordia",
                Level = 75,
                Id = 17765,
                Jobs = {"WAR", "PLD", "DRK", "SAM", "BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 46,
                    Delay = 268,
                }
            },
            CrimsonBlade = {
                Name = "Crimson Blade",
                Level = 49,
                Id = 16822,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BRD", "RNG", "NIN", "DRG", "BLU", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 28,
                    Delay = 231,
                    MP = 10,
                    INT = 5,
                }
            },
            Degen = {
                Name = "Degen",
                Level = 20,
                Id = 16517,
                Jobs = {"WAR", "RDM", "PLD", "BRD", "DRG", "COR", "DNC"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 14,
                    Delay = 224,
                }
            },
            Degen_1 = {
                Name = "Degen +1",
                Level = 20,
                Id = 16633,
                Jobs = {"WAR", "RDM", "PLD", "BRD", "DRG", "COR", "DNC"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 15,
                    Delay = 218,
                }
            },
            Egeking = {
                Name = "Egeking",
                Level = 75,
                Id = 20720,
                Jobs = {"RDM"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 43,
                    Delay = 236,
                    HP = 15,
                    MP = 15,
                    STR = 4,
                    MND = 4,
                    Accuracy = 8,
                    MagicAccuracy = 4,
                    MagicAttackBonus = 4,
                    Enmity = -4,
                }
            },
            EradicatorsKilij = {
                Name = "Eradicators Kilij",
                Level = 75,
                Id = 18915,
                Jobs = {"BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 43,
                    Delay = 229,
                    MP = 35,
                    DEX = 3,
                    VIT = 3,
                }
            },
            Excalipoor = {
                Name = "Excalipoor",
                Level = 1,
                Id = 20713,
                Jobs = {"All"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 1,
                    Delay = 240,
                }
            },
            Fleuret = {
                Name = "Fleuret",
                Level = 30,
                Id = 16524,
                Jobs = {"RDM", "DRG"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 18,
                    Delay = 221,
                }
            },
            Fleuret_1 = {
                Name = "Fleuret +1",
                Level = 30,
                Id = 16803,
                Jobs = {"RDM", "DRG"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 19,
                    Delay = 215,
                }
            },
            HepatizonRapier = {
                Name = "Hepatizon Rapier",
                Level = 72,
                Id = 21610,
                Jobs = {"WAR", "RDM", "PLD", "BRD", "DRG", "COR", "DNC"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 40,
                    Delay = 224,
                    STR = 3,
                    MND = 3,
                    Accuracy = 10,
                    MagicAttackBonus = 10,
                }
            },
            HepatizonRapier_1 = {
                Name = "Hepatizon Rapier +1",
                Level = 72,
                Id = 21611,
                Jobs = {"WAR", "RDM", "PLD", "BRD", "DRG", "COR", "DNC"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 41,
                    Delay = 218,
                    STR = 8,
                    MND = 8,
                    Accuracy = 15,
                    MagicAttackBonus = 15,
                }
            },
            ImmortalsScimitar = {
                Name = "Immortals Scimitar",
                Level = 40,
                Id = 17717,
                Jobs = {"BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 26,
                    Delay = 236,
                    MP = 10,
                    STR = 1,
                    INT = 1,
                }
            },
            IronSword_1 = {
                Name = "Iron Sword +1",
                Level = 18,
                Id = 16626,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BRD", "RNG", "NIN", "DRG", "BLU", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 15,
                    Delay = 225,
                }
            },
            Joyeuse = {
                Name = "Joyeuse",
                Level = 70,
                Id = 17652,
                Jobs = {"WAR", "RDM", "PLD", "BRD", "DRG", "BLU", "COR", "DNC"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 35,
                    Delay = 224,
                }
            },
            Kaskara = {
                Name = "Kaskara",
                Level = 71,
                Id = 16579,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 44,
                    Delay = 264,
                    HP = 10,
                    DEX = 2,
                    VIT = 2,
                }
            },
            KillersKilij = {
                Name = "Killers Kilij",
                Level = 75,
                Id = 18914,
                Jobs = {"BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 42,
                    Delay = 236,
                    MP = 30,
                    DEX = 2,
                    VIT = 2,
                }
            },
            KingdomSword = {
                Name = "Kingdom Sword",
                Level = 15,
                Id = 17679,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "NIN", "DRG", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 12,
                    Delay = 216,
                    HP = 6,
                }
            },
            Koboto = {
                Name = "Koboto",
                Level = 74,
                Id = 20699,
                Jobs = {"WAR", "THF", "DRK", "BST", "RNG", "SAM"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 47,
                    Delay = 240,
                    Attack = 15,
                    Evasion = 10,
                    DualWield = 5,
                }
            },
            Koggelmander = {
                Name = "Koggelmander",
                Level = 72,
                Id = 17759,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "NIN", "DRG", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 43,
                    Delay = 224,
                    STR = 4,
                    DEX = 4,
                }
            },
            Mimesis = {
                Name = "Mimesis",
                Level = 75,
                Id = 20721,
                Jobs = {"BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 43,
                    Delay = 236,
                    HP = 15,
                    MP = 15,
                    STR = 6,
                    INT = 6,
                    MND = 6,
                    Accuracy = 8,
                    MagicAccuracy = 4,
                    MagicAttackBonus = 4,
                    Enmity = 4,
                    FastCast = 5,
                }
            },
            Nadrs = {
                Name = "Nadrs",
                Level = 24,
                Id = 17650,
                Jobs = {"WAR", "THF", "DRK", "SAM", "BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 18,
                    Delay = 236,
                }
            },
            OnionSword = {
                Name = "Onion Sword",
                Level = 1,
                Id = 16534,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "NIN", "DRG", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 5,
                    Delay = 228,
                }
            },
            Sapara = {
                Name = "Sapara",
                Level = 7,
                Id = 16551,
                Jobs = {"WAR", "THF", "DRK", "SAM", "BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 9,
                    Delay = 236,
                }
            },
            Sapara_1 = {
                Name = "Sapara +1",
                Level = 7,
                Id = 16801,
                Jobs = {"WAR", "THF", "DRK", "SAM", "BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 10,
                    Delay = 230,
                }
            },
            SeiryusSword = {
                Name = "Seiryus Sword",
                Level = 74,
                Id = 17659,
                Jobs = {"WAR", "THF", "DRK", "BST", "RNG", "SAM"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 45,
                    Delay = 240,
                    Evasion = 5,
                }
            },
            SinghKilij = {
                Name = "Singh Kilij",
                Level = 60,
                Id = 17723,
                Jobs = {"BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 37,
                    Delay = 236,
                    MP = 20,
                }
            },
            SteelKilij = {
                Name = "Steel Kilij",
                Level = 30,
                Id = 17739,
                Jobs = {"BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 21,
                    Delay = 236,
                    MP = 10,
                }
            },
            SteelKilij_1 = {
                Name = "Steel Kilij +1",
                Level = 30,
                Id = 17740,
                Jobs = {"BLU"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 22,
                    Delay = 229,
                    MP = 15,
                }
            },
            Stormblade = {
                Name = "Stormblade",
                Level = 70,
                Id = 21915,
                Jobs = {"WAR", "THF", "DRK", "BST", "BLU", "COR"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 39,
                    Delay = 236,
                    INT = 3,
                }
            },
            Talekeeper = {
                Name = "Talekeeper",
                Level = 75,
                Id = 18903,
                Jobs = {"WAR", "RDM", "PLD", "BRD", "DRG", "COR", "DNC"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 42,
                    Delay = 224,
                    HP = 30,
                    MP = 30,
                    STR = 5,
                }
            },
            Vampirism = {
                Name = "Vampirism",
                Level = 75,
                Id = 20706,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BRD", "RNG", "NIN", "DRG", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 41,
                    Delay = 240,
                    HP = 45,
                    Attack = 8,
                    MagicAttackBonus = 8,
                }
            },
            Verdun = {
                Name = "Verdun",
                Level = 73,
                Id = 16520,
                Jobs = {"WAR", "RDM", "PLD", "BRD", "DRG", "COR", "DNC"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 36,
                    Delay = 224,
                    MP = 18,
                }
            },
            WaxSword_1 = {
                Name = "Wax Sword +1",
                Level = 1,
                Id = 16610,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BRD", "RNG", "NIN", "DRG", "BLU", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 7,
                    Delay = 218,
                    Accuracy = 2,
                }
            },
            WisWizAnelace = {
                Name = "Wis.Wiz. Anelace",
                Level = 55,
                Id = 16809,
                Jobs = {"WAR", "RDM", "PLD", "DRK", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 34,
                    Delay = 226,
                    Attack = 14,
                }
            },
            Xiutleato = {
                Name = "Xiutleato",
                Level = 75,
                Id = 20731,
                Jobs = {"WAR", "RDM", "PLD", "BLU", "COR", "RUN"},
                OneHanded = true,
                Type = "Sword",
                Stats = {
                    DMG = 41,
                    Delay = 240,
                    STR = 3,
                    VIT = 3,
                    MagicAccuracy = 2,
                }
            },
        },
        GreatSword = {
            Aettir = {
                Name = "Aettir",
                Level = 75,
                Id = 20761,
                Jobs = {"RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 85,
                    Delay = 480,
                    HP = 20,
                    MP = 15,
                    DEX = 4,
                    AGI = 4,
                    Accuracy = 8,
                    Enmity = 5,
                }
            },
            Bahadur = {
                Name = "Bahadur",
                Level = 73,
                Id = 19151,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 84,
                    Delay = 489,
                    HP = 10,
                    DEX = 2,
                    VIT = 2,
                }
            },
            BarbariansSword = {
                Name = "Barbarians Sword",
                Level = 24,
                Id = 16935,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 37,
                    Delay = 444,
                    Accuracy = -5,
                    Attack = 15,
                }
            },
            BeorcSword = {
                Name = "Beorc Sword",
                Level = 40,
                Id = 20776,
                Jobs = {"RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 56,
                    Delay = 480,
                    MagicAttackBonus = 2,
                }
            },
            BerylliumSword = {
                Name = "Beryllium Sword",
                Level = 72,
                Id = 21659,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 84,
                    Delay = 444,
                    MP = 25,
                    STR = 8,
                    INT = 8,
                    Accuracy = 10,
                }
            },
            BerylliumSword_1 = {
                Name = "Beryllium Sword +1",
                Level = 72,
                Id = 21660,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 85,
                    Delay = 431,
                    MP = 30,
                    STR = 12,
                    INT = 12,
                    Accuracy = 15,
                }
            },
            Bitterness = {
                Name = "Bitterness",
                Level = 20,
                Id = 21665,
                Jobs = {"DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 38,
                    Delay = 480,
                    MP = 9,
                    STR = 3,
                    INT = 3,
                    Attack = 13,
                    Enmity = 3,
                }
            },
            Claymore_1 = {
                Name = "Claymore +1",
                Level = 10,
                Id = 16638,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 23,
                    Delay = 431,
                }
            },
            Epeolatry = {
                Name = "Epeolatry",
                Level = 75,
                Id = 20753,
                Jobs = {"RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 98,
                    Delay = 489,
                    Enmity = 10,
                }
            },
            Etourdissante = {
                Name = "Etourdissante",
                Level = 73,
                Id = 19177,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 83,
                    Delay = 456,
                    DEX = 3,
                    INT = 3,
                    Enmity = 1,
                    DoubleAttack = 1,
                }
            },
            Etourdissante_1 = {
                Name = "Etourdissante +1",
                Level = 73,
                Id = 19178,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 84,
                    Delay = 443,
                    DEX = 4,
                    INT = 4,
                    Enmity = 2,
                    DoubleAttack = 2,
                }
            },
            Flamberge = {
                Name = "Flamberge",
                Level = 69,
                Id = 16596,
                Jobs = {"PLD", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 80,
                    Delay = 480,
                    MND = 2,
                    Attack = 5,
                }
            },
            Galatyn = {
                Name = "Galatyn",
                Level = 75,
                Id = 19159,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 85,
                    Delay = 494,
                }
            },
            GustSword = {
                Name = "Gust Sword",
                Level = 41,
                Id = 18368,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 55,
                    Delay = 456,
                }
            },
            GustSword_1 = {
                Name = "Gust Sword +1",
                Level = 41,
                Id = 18369,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 56,
                    Delay = 443,
                }
            },
            Kaquljaan = {
                Name = "Kaquljaan",
                Level = 75,
                Id = 20768,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 83,
                    Delay = 480,
                    STR = 3,
                    DEX = 3,
                    Attack = 5,
                    MagicAccuracy = 4,
                    MagicAttackBonus = 5,
                    DoubleAttack = 2,
                }
            },
            Macbain = {
                Name = "Macbain",
                Level = 75,
                Id = 20759,
                Jobs = {"DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 95,
                    Delay = 480,
                    MP = 27,
                    STR = 10,
                    INT = 10,
                    Attack = 20,
                    MagicAccuracy = 20,
                    Enmity = 10,
                    Refresh = 2,
                    FastCast = 10,
                }
            },
            MrcGreatsword = {
                Name = "Mrc. Greatsword",
                Level = 20,
                Id = 16930,
                Jobs = {"WAR", "PLD", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 33,
                    Delay = 431,
                    Attack = 7,
                }
            },
            SowiloClaymore = {
                Name = "Sowilo Claymore",
                Level = 1,
                Id = 20781,
                Jobs = {"RUN"},
                OneHanded = false,
                Type = "GreatSword",
                Stats = {
                    DMG = 15,
                    Delay = 444,
                    HP = 5,
                }
            },
        },
        Axe = {
            Arktoi = {
                Name = "Arktoi",
                Level = 75,
                Id = 20811,
                Jobs = {"BST"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 48,
                    Delay = 276,
                    HP = 20,
                    STR = 5,
                    CHR = 5,
                    Attack = 10,
                    Enmity = -5,
                }
            },
            BastokanAxe = {
                Name = "Bastokan Axe",
                Level = 15,
                Id = 17929,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 14,
                    Delay = 268,
                    Accuracy = 1,
                }
            },
            BerylliumPick = {
                Name = "Beryllium Pick",
                Level = 72,
                Id = 21708,
                Jobs = {"WAR", "DRK", "BST", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 49,
                    Delay = 312,
                    HP = 25,
                    STR = 6,
                    VIT = 6,
                    Accuracy = 8,
                    Attack = 8,
                }
            },
            BerylliumPick_1 = {
                Name = "Beryllium Pick +1",
                Level = 72,
                Id = 21709,
                Jobs = {"WAR", "DRK", "BST", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 50,
                    Delay = 303,
                    HP = 30,
                    STR = 8,
                    VIT = 8,
                    Accuracy = 12,
                    Attack = 12,
                }
            },
            BrassAxe = {
                Name = "Brass Axe",
                Level = 8,
                Id = 16641,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 12,
                    Delay = 276,
                }
            },
            Breidox = {
                Name = "Breidox",
                Level = 73,
                Id = 18543,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 47,
                    Delay = 288,
                    HP = 5,
                    STR = 3,
                    Enmity = 3,
                }
            },
            Breidox_1 = {
                Name = "Breidox +1",
                Level = 73,
                Id = 18544,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 48,
                    Delay = 280,
                    HP = 10,
                    STR = 4,
                    Enmity = 4,
                }
            },
            BronzeAxe = {
                Name = "Bronze Axe",
                Level = 1,
                Id = 16640,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 8,
                    Delay = 276,
                }
            },
            FellingAxe = {
                Name = "Felling Axe",
                Level = 13,
                Id = 17967,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 13,
                    Delay = 276,
                    RangedAccuracy = 4,
                }
            },
            Hatxiik = {
                Name = "Hatxiik",
                Level = 75,
                Id = 20820,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 46,
                    Delay = 288,
                    STR = 3,
                    VIT = 3,
                    DoubleAttack = 2,
                }
            },
            Hunahpu = {
                Name = "Hunahpu",
                Level = 75,
                Id = 20826,
                Jobs = {"BST"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 46,
                    Delay = 288,
                    STR = 3,
                    DEX = 3,
                }
            },
            Kumbhakarna = {
                Name = "Kumbhakarna",
                Level = 75,
                Id = 20809,
                Jobs = {"WAR", "BST"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 58,
                    Delay = 276,
                    STR = 10,
                    Attack = 20,
                    DoubleAttack = 5,
                }
            },
            LightAxe = {
                Name = "Light Axe",
                Level = 11,
                Id = 16667,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 14,
                    Delay = 260,
                }
            },
            MilitaryPick = {
                Name = "Military Pick",
                Level = 28,
                Id = 17940,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 24,
                    Delay = 260,
                    Accuracy = 1,
                }
            },
            Nadziak = {
                Name = "Nadziak",
                Level = 68,
                Id = 16653,
                Jobs = {"WAR", "DRK", "BST", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 46,
                    Delay = 312,
                    HP = 10,
                    DEX = 2,
                    VIT = 2,
                }
            },
            Purgation = {
                Name = "Purgation",
                Level = 75,
                Id = 20796,
                Jobs = {"WAR", "DRK", "BST"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 50,
                    Delay = 288,
                    Accuracy = 12,
                    DoubleAttack = 3,
                }
            },
            Tabarzin = {
                Name = "Tabarzin",
                Level = 71,
                Id = 16659,
                Jobs = {"WAR", "DRK", "BST", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 49,
                    Delay = 288,
                    HP = 10,
                    DEX = 2,
                    VIT = 2,
                }
            },
            TjukurrpaAxe = {
                Name = "Tjukurrpa Axe",
                Level = 75,
                Id = 18541,
                Jobs = {"BST"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 46,
                    Delay = 288,
                }
            },
            VikingAxe = {
                Name = "Viking Axe",
                Level = 48,
                Id = 16676,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 36,
                    Delay = 276,
                    Accuracy = 10,
                    Evasion = -10,
                }
            },
            WarriorsAxe = {
                Name = "Warriors Axe",
                Level = 32,
                Id = 16673,
                Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 25,
                    Delay = 276,
                    STR = 1,
                    DEX = 1,
                }
            },
            Woodlander = {
                Name = "Woodlander",
                Level = 20,
                Id = 21712,
                Jobs = {"WAR", "BST"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 24,
                    Delay = 276,
                    Attack = 5,
                }
            },
            Woodlander_1 = {
                Name = "Woodlander +1",
                Level = 50,
                Id = 20810,
                Jobs = {"WAR", "BST"},
                OneHanded = true,
                Type = "Axe",
                Stats = {
                    DMG = 40,
                    Delay = 276,
                    Attack = 15,
                }
            },
        },
        GreatAxe = {
            Bhuj = {
                Name = "Bhuj",
                Level = 71,
                Id = 16707,
                Jobs = {"WAR", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 89,
                    Delay = 504,
                    HP = 10,
                    DEX = 2,
                    VIT = 2,
                }
            },
            ByakkosAxe = {
                Name = "Byakkos Axe",
                Level = 74,
                Id = 18198,
                Jobs = {"WAR", "DRK"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 94,
                    Delay = 504,
                    Attack = 5,
                }
            },
            Firnaxe = {
                Name = "Firnaxe",
                Level = 73,
                Id = 18522,
                Jobs = {"WAR", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 93,
                    Delay = 504,
                    HP = 10,
                    VIT = 4,
                    Accuracy = 4,
                }
            },
            Firnaxe_1 = {
                Name = "Firnaxe +1",
                Level = 73,
                Id = 18523,
                Jobs = {"WAR", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 94,
                    Delay = 489,
                    HP = 15,
                    VIT = 5,
                    Accuracy = 5,
                }
            },
            Greataxe = {
                Name = "Greataxe",
                Level = 12,
                Id = 16705,
                Jobs = {"WAR", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 30,
                    Delay = 504,
                }
            },
            Greataxe_1 = {
                Name = "Greataxe +1",
                Level = 12,
                Id = 16717,
                Jobs = {"WAR", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 31,
                    Delay = 489,
                }
            },
            HellfireAxe = {
                Name = "Hellfire Axe",
                Level = 8,
                Id = 16713,
                Jobs = {"WAR", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 24,
                    Delay = 489,
                }
            },
            HugeMothAxe = {
                Name = "Huge Moth Axe",
                Level = 39,
                Id = 16721,
                Jobs = {"WAR", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 59,
                    Delay = 504,
                    STR = 2,
                }
            },
            Ixtab = {
                Name = "Ixtab",
                Level = 75,
                Id = 20872,
                Jobs = {"WAR", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 93,
                    Delay = 504,
                    STR = 3,
                    VIT = 3,
                    StoreTP = 5,
                }
            },
            Jokushuono = {
                Name = "Jokushuono",
                Level = 74,
                Id = 20846,
                Jobs = {"WAR", "DRK"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 98,
                    Delay = 504,
                    Attack = 15,
                    CriticalHitRate = 5,
                }
            },
            MilitaryAxe = {
                Name = "Military Axe",
                Level = 28,
                Id = 18212,
                Jobs = {"WAR", "DRK"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 46,
                    Delay = 474,
                    AGI = 1,
                }
            },
            Minos = {
                Name = "Minos",
                Level = 75,
                Id = 20860,
                Jobs = {"WAR"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 95,
                    Delay = 504,
                    HP = 20,
                    VIT = 6,
                    Attack = 8,
                    Enmity = 4,
                    DoubleAttack = 3,
                }
            },
            Neckchopper = {
                Name = "Neckchopper",
                Level = 20,
                Id = 16714,
                Jobs = {"WAR", "DRK", "RUN"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 39,
                    Delay = 489,
                    Accuracy = 5,
                }
            },
            OneirosAxe = {
                Name = "Oneiros Axe",
                Level = 75,
                Id = 18519,
                Jobs = {"WAR"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 96,
                    Delay = 589,
                    HP = 50,
                    VIT = 5,
                    Accuracy = 5,
                    Enmity = 5,
                }
            },
            Reikiono = {
                Name = "Reikiono",
                Level = 75,
                Id = 20842,
                Jobs = {"WAR"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 104,
                    Delay = 504,
                    TripleAttack = 4,
                }
            },
            Savagery = {
                Name = "Savagery +",
                Level = 50,
                Id = 20859,
                Jobs = {"WAR"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 56,
                    Delay = 504,
                    VIT = 8,
                    Accuracy = 8,
                    Enmity = 5,
                }
            },
            Savagery_2 = {
                Name = "Savagery",
                Level = 20,
                Id = 21769,
                Jobs = {"WAR"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 45,
                    Delay = 504,
                    VIT = 4,
                    Accuracy = 5,
                    Enmity = 3,
                }
            },
            Svarga = {
                Name = "Svarga",
                Level = 75,
                Id = 20857,
                Jobs = {"WAR"},
                OneHanded = false,
                Type = "GreatAxe",
                Stats = {
                    DMG = 80,
                    Delay = 504,
                    VIT = 10,
                    Accuracy = 20,
                    Enmity = 10,
                    CurePotency = 15,
                }
            },
        },
        Scythe = {
            BahamutZaghnal = {
                Name = "Bahamut Zaghnal",
                Level = 75,
                Id = 18061,
                Jobs = {"WAR", "BLM", "DRK", "BST"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 24,
                    Delay = 480,
                    Accuracy = 5,
                    Attack = 5,
                }
            },
            BronzeZaghnal = {
                Name = "Bronze Zaghnal",
                Level = 1,
                Id = 16768,
                Jobs = {"WAR", "DRK", "BST"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 14,
                    Delay = 480,
                }
            },
            Cronus = {
                Name = "Cronus",
                Level = 75,
                Id = 20904,
                Jobs = {"DRK"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 99,
                    Delay = 528,
                    HP = 15,
                    MP = 15,
                    STR = 4,
                    INT = 4,
                    Attack = 12,
                    MagicAccuracy = 6,
                    Enmity = -4,
                    Refresh = 1,
                }
            },
            Foreshadow = {
                Name = "Foreshadow",
                Level = 20,
                Id = 21822,
                Jobs = {"BLM", "DRK"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 43,
                    Delay = 528,
                    STR = 3,
                    INT = 5,
                    HMP = 5,
                }
            },
            Foreshadow_1 = {
                Name = "Foreshadow +1",
                Level = 50,
                Id = 20903,
                Jobs = {"BLM", "DRK"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 82,
                    Delay = 528,
                    STR = 5,
                    INT = 8,
                    HMP = 10,
                }
            },
            Inanna = {
                Name = "Inanna",
                Level = 75,
                Id = 20901,
                Jobs = {"BLM", "DRK"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 105,
                    Delay = 528,
                    STR = 10,
                    INT = 10,
                    HMP = 15,
                }
            },
            LgnScythe = {
                Name = "Lgn. Scythe",
                Level = 10,
                Id = 16780,
                Jobs = {"WAR", "DRK", "BST"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 27,
                    Delay = 495,
                    STR = 2,
                    VIT = -1,
                }
            },
            MaliyaSickle = {
                Name = "Maliya Sickle",
                Level = 72,
                Id = 21815,
                Jobs = {"WAR", "BLM", "DRK", "BST"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 92,
                    Delay = 501,
                    STR = 10,
                    MND = 10,
                    Accuracy = 10,
                    StoreTP = 5,
                }
            },
            MaliyaSickle_1 = {
                Name = "Maliya Sickle +1",
                Level = 72,
                Id = 21816,
                Jobs = {"WAR", "BLM", "DRK", "BST"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 93,
                    Delay = 490,
                    STR = 12,
                    MND = 12,
                    Accuracy = 15,
                    StoreTP = 8,
                }
            },
            Plantreaper = {
                Name = "Plantreaper",
                Level = 14,
                Id = 16783,
                Jobs = {"WAR", "DRK", "BST"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 30,
                    Delay = 480,
                }
            },
            Serpette = {
                Name = "Serpette",
                Level = 12,
                Id = 18956,
                Jobs = {"DRK"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 32,
                    Delay = 528,
                }
            },
            Serpette_1 = {
                Name = "Serpette +1",
                Level = 12,
                Id = 18959,
                Jobs = {"DRK"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 33,
                    Delay = 513,
                }
            },
            SuzakusScythe = {
                Name = "Suzakus Scythe",
                Level = 74,
                Id = 18043,
                Jobs = {"WAR", "DRK", "BST"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 88,
                    Delay = 480,
                    Accuracy = 5,
                }
            },
            Xbalanque = {
                Name = "Xbalanque",
                Level = 75,
                Id = 20917,
                Jobs = {"WAR", "BLM", "DRK", "BST"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 93,
                    Delay = 528,
                    STR = 3,
                    DEX = 3,
                    Attack = 5,
                    MagicAccuracy = 4,
                    DoubleAttack = 2,
                }
            },
            Yhatdhara = {
                Name = "Yhatdhara",
                Level = 73,
                Id = 18561,
                Jobs = {"WAR", "DRK", "BST"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 87,
                    Delay = 480,
                    INT = 3,
                    CHR = 3,
                    Attack = 5,
                    StoreTP = 2,
                }
            },
            Yhatdhara_1 = {
                Name = "Yhatdhara +1",
                Level = 73,
                Id = 18562,
                Jobs = {"WAR", "DRK", "BST"},
                OneHanded = false,
                Type = "Scythe",
                Stats = {
                    DMG = 88,
                    Delay = 466,
                    INT = 4,
                    CHR = 4,
                    Attack = 6,
                    StoreTP = 3,
                }
            },
        },
        Polearm = {
            Areadbhar = {
                Name = "Areadbhar",
                Level = 75,
                Id = 20948,
                Jobs = {"DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 94,
                    Delay = 492,
                    HP = 20,
                    STR = 4,
                    VIT = 4,
                    Attack = 8,
                    Enmity = -4,
                }
            },
            BrassSpear = {
                Name = "Brass Spear",
                Level = 14,
                Id = 16834,
                Jobs = {"WAR", "PLD", "SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 25,
                    Delay = 396,
                }
            },
            BrassSpear_1 = {
                Name = "Brass Spear +1",
                Level = 14,
                Id = 16864,
                Jobs = {"WAR", "PLD", "SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 26,
                    Delay = 385,
                }
            },
            BronzeSpear_1 = {
                Name = "Bronze Spear +1",
                Level = 7,
                Id = 16859,
                Jobs = {"WAR", "PLD", "SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 17,
                    Delay = 385,
                }
            },
            ExaltedSpear = {
                Name = "Exalted Spear",
                Level = 72,
                Id = 21869,
                Jobs = {"WAR", "PLD", "SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 73,
                    Delay = 396,
                    HP = 25,
                    STR = 8,
                    MND = 8,
                    Accuracy = 10,
                    Attack = 10,
                }
            },
            ExaltedSpear_1 = {
                Name = "Exalted Spear +1",
                Level = 72,
                Id = 21870,
                Jobs = {"WAR", "PLD", "SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 74,
                    Delay = 385,
                    HP = 30,
                    STR = 12,
                    MND = 12,
                    Accuracy = 15,
                    Attack = 15,
                }
            },
            Harpoon = {
                Name = "Harpoon",
                Level = 1,
                Id = 16832,
                Jobs = {"WAR", "PLD", "SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 8,
                    Delay = 396,
                }
            },
            Heartpiercer = {
                Name = "Heartpiercer",
                Level = 20,
                Id = 21864,
                Jobs = {"DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 40,
                    Delay = 492,
                    STR = 3,
                    DEX = 3,
                    Attack = 6,
                    StoreTP = 3,
                }
            },
            Heartpiercer_1 = {
                Name = "Heartpiercer +1",
                Level = 50,
                Id = 20947,
                Jobs = {"DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 80,
                    Delay = 492,
                    STR = 5,
                    DEX = 5,
                    Attack = 8,
                    StoreTP = 5,
                }
            },
            IceLance = {
                Name = "Ice Lance",
                Level = 74,
                Id = 16861,
                Jobs = {"DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 89,
                    Delay = 492,
                }
            },
            Kuakuakait = {
                Name = "Kuakuakait",
                Level = 75,
                Id = 20958,
                Jobs = {"PLD", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 92,
                    Delay = 492,
                    STR = 3,
                    VIT = 3,
                    Haste = 1,
                }
            },
            MythrilLance_1 = {
                Name = "Mythril Lance +1",
                Level = 48,
                Id = 16877,
                Jobs = {"DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 70,
                    Delay = 478,
                }
            },
            Olyndicus = {
                Name = "Olyndicus",
                Level = 75,
                Id = 20946,
                Jobs = {"DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 103,
                    Delay = 492,
                    STR = 10,
                    DEX = 10,
                    Attack = 20,
                    StoreTP = 8,
                }
            },
            OneirosLance = {
                Name = "Oneiros Lance",
                Level = 75,
                Id = 19790,
                Jobs = {"DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 96,
                    Delay = 492,
                    HP = 50,
                    VIT = 5,
                    Enmity = 5,
                }
            },
            OxTongue = {
                Name = "Ox Tongue",
                Level = 71,
                Id = 16840,
                Jobs = {"WAR", "PLD", "SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 70,
                    Delay = 396,
                    HP = 10,
                    DEX = 2,
                    VIT = 2,
                }
            },
            Pike = {
                Name = "Pike",
                Level = 11,
                Id = 19305,
                Jobs = {"DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 28,
                    Delay = 492,
                }
            },
            Rosschinder = {
                Name = "Rosschinder",
                Level = 73,
                Id = 19796,
                Jobs = {"WAR", "PLD", "SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 70,
                    Delay = 396,
                    HP = 30,
                    STR = 3,
                    DEX = 3,
                    Counter = 6,
                }
            },
            Rosschinder_1 = {
                Name = "Rosschinder +1",
                Level = 73,
                Id = 19797,
                Jobs = {"WAR", "PLD", "SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 71,
                    Delay = 385,
                    HP = 40,
                    STR = 4,
                    DEX = 4,
                    Counter = 8,
                }
            },
            RylSprSpear = {
                Name = "Ryl.Spr. Spear",
                Level = 18,
                Id = 16852,
                Jobs = {"WAR", "PLD", "SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 28,
                    Delay = 396,
                }
            },
            Sarissa = {
                Name = "Sarissa",
                Level = 75,
                Id = 19304,
                Jobs = {"DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 96,
                    Delay = 507,
                }
            },
            Tomoe = {
                Name = "Tomoe",
                Level = 72,
                Id = 18126,
                Jobs = {"SAM", "DRG"},
                OneHanded = false,
                Type = "Polearm",
                Stats = {
                    DMG = 86,
                    Delay = 480,
                    Accuracy = 5,
                    Attack = 5,
                    SubtleBlow = 5,
                }
            },
        },
        Katana = {
            Aisa = {
                Name = "Aisa",
                Level = 73,
                Id = 19299,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 38,
                    Delay = 227,
                    DEX = 2,
                    INT = 2,
                    MagicAccuracy = 4,
                }
            },
            Aisa_1 = {
                Name = "Aisa +1",
                Level = 73,
                Id = 19300,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 39,
                    Delay = 222,
                    DEX = 3,
                    INT = 3,
                    MagicAccuracy = 6,
                }
            },
            Debahocho = {
                Name = "Debahocho",
                Level = 1,
                Id = 21923,
                Jobs = {"All"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 1,
                    Delay = 227,
                }
            },
            Gassan = {
                Name = "Gassan",
                Level = 15,
                Id = 18412,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 12,
                    Delay = 227,
                    AGI = 1,
                }
            },
            Hikage = {
                Name = "Hikage",
                Level = 20,
                Id = 21912,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 15,
                    Delay = 227,
                    DEX = 4,
                    INT = 4,
                    Attack = 5,
                    RangedAttack = 5,
                    MagicAttackBonus = 3,
                }
            },
            Izuna = {
                Name = "Izuna",
                Level = 75,
                Id = 20989,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 44,
                    Delay = 227,
                    DEX = 10,
                    INT = 10,
                    Attack = 20,
                    RangedAttack = 20,
                    MagicAttackBonus = 10,
                }
            },
            MujinTanto = {
                Name = "Mujin Tanto",
                Level = 75,
                Id = 19295,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 27,
                    Delay = 222,
                    Enmity = 3,
                    SubtleBlow = 5,
                    FastCast = 2,
                }
            },
            Nagi = {
                Name = "Nagi",
                Level = 99,
                Id = 21907,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 142,
                    Delay = 227,
                    MagicAccuracy = 40,
                    Enmity = 40,
                }
            },
            Niokiyotsuna = {
                Name = "Niokiyotsuna",
                Level = 38,
                Id = 17794,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 19,
                    Delay = 227,
                    DoubleAttack = 1,
                }
            },
            Ochu = {
                Name = "Ochu",
                Level = 75,
                Id = 20978,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 40,
                    Delay = 227,
                    STR = 4,
                    DEX = 4,
                    Accuracy = 8,
                    RangedAccuracy = 8,
                    SubtleBlow = 8,
                }
            },
            Shigi = {
                Name = "Shigi",
                Level = 75,
                Id = 20994,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 32,
                    Delay = 190,
                    HP = 20,
                    DEX = 6,
                    Attack = 8,
                    RangedAttack = 8,
                    MagicAttackBonus = 8,
                    StoreTP = 5,
                    Enmity = 4,
                    FastCast = 5,
                }
            },
            ShinobiGatana = {
                Name = "Shinobi-gatana",
                Level = 13,
                Id = 16919,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 11,
                    Delay = 227,
                }
            },
            Suzume = {
                Name = "Suzume",
                Level = 19,
                Id = 16917,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 11,
                    Delay = 190,
                }
            },
            Taikogane = {
                Name = "Taikogane",
                Level = 75,
                Id = 20992,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 36,
                    Delay = 227,
                    DEX = 3,
                    AGI = 3,
                    Evasion = 3,
                    CriticalHitRate = 2,
                }
            },
            Wakizashi = {
                Name = "Wakizashi",
                Level = 7,
                Id = 16900,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 8,
                    Delay = 227,
                }
            },
            Yoiyami = {
                Name = "Yoiyami",
                Level = 30,
                Id = 21905,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 12,
                    Delay = 120,
                    DEX = 3,
                    Attack = 5,
                    DualWield = 3,
                }
            },
            Yoto_1 = {
                Name = "Yoto +1",
                Level = 46,
                Id = 17768,
                Jobs = {"NIN"},
                OneHanded = true,
                Type = "Katana",
                Stats = {
                    DMG = 26,
                    Delay = 227,
                }
            },
        },
        GreatKatana = {
            Azukinagamitsu = {
                Name = "Azukinagamitsu",
                Level = 75,
                Id = 21047,
                Jobs = {"SAM", "NIN"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 81,
                    Delay = 450,
                    STR = 3,
                    DEX = 3,
                }
            },
            FutsunoMitama = {
                Name = "Futsuno Mitama",
                Level = 75,
                Id = 17810,
                Jobs = {"SAM"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 84,
                    Delay = 480,
                    DEX = 8,
                    StoreTP = 8,
                }
            },
            Giritachi = {
                Name = "Giritachi",
                Level = 20,
                Id = 21976,
                Jobs = {"SAM"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 40,
                    Delay = 450,
                    STR = 3,
                    AGI = 3,
                    Attack = 8,
                    StoreTP = 5,
                }
            },
            Giritachi_1 = {
                Name = "Giritachi +1",
                Level = 50,
                Id = 21038,
                Jobs = {"SAM"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 52,
                    Delay = 450,
                    STR = 5,
                    AGI = 5,
                    Attack = 12,
                    StoreTP = 8,
                }
            },
            Katayama = {
                Name = "Katayama",
                Level = 10,
                Id = 17811,
                Jobs = {"SAM"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 28,
                    Delay = 450,
                    STR = 1,
                    DEX = 1,
                }
            },
            Kazaridachi = {
                Name = "Kazaridachi",
                Level = 67,
                Id = 16972,
                Jobs = {"SAM"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 76,
                    Delay = 450,
                    CHR = 2,
                }
            },
            KikuIchimonji = {
                Name = "Kiku-ichimonji",
                Level = 51,
                Id = 17802,
                Jobs = {"SAM"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 66,
                    Delay = 450,
                }
            },
            Kurikaranotachi = {
                Name = "Kurikaranotachi",
                Level = 75,
                Id = 21039,
                Jobs = {"SAM"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 82,
                    Delay = 450,
                    HP = 20,
                    STR = 4,
                    AGI = 4,
                    Attack = 8,
                    RangedAttack = 8,
                    Enmity = -4,
                }
            },
            Mutsunokami = {
                Name = "Mutsunokami",
                Level = 1,
                Id = 21977,
                Jobs = {"All"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 1,
                    Delay = 450,
                }
            },
            Nenekirimaru = {
                Name = "Nenekirimaru",
                Level = 75,
                Id = 21037,
                Jobs = {"SAM"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 65,
                    Delay = 450,
                    STR = 10,
                    AGI = 10,
                    Attack = 20,
                    RangedAttack = 20,
                    StoreTP = 10,
                }
            },
            Sasanuki = {
                Name = "Sasanuki",
                Level = 73,
                Id = 18462,
                Jobs = {"SAM", "NIN"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 73,
                    Delay = 420,
                    STR = 4,
                    Accuracy = 3,
                }
            },
            Sasanuki_1 = {
                Name = "Sasanuki +1",
                Level = 73,
                Id = 18463,
                Jobs = {"SAM", "NIN"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 74,
                    Delay = 407,
                    STR = 5,
                    Accuracy = 4,
                }
            },
            Tachi = {
                Name = "Tachi",
                Level = 8,
                Id = 16966,
                Jobs = {"SAM"},
                OneHanded = false,
                Type = "GreatKatana",
                Stats = {
                    DMG = 21,
                    Delay = 450,
                }
            },
        },
        Club = {
            AshClub_1 = {
                Name = "Ash Club +1",
                Level = 1,
                Id = 17137,
                Jobs = {"All"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 5,
                    Delay = 257,
                }
            },
            BerylliumMace = {
                Name = "Beryllium Mace",
                Level = 72,
                Id = 22023,
                Jobs = {"WAR", "WHM", "PLD", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 44,
                    Delay = 300,
                    MP = 25,
                    STR = 6,
                    MND = 6,
                    Accuracy = 8,
                    Attack = 8,
                    CurePotency = 5,
                }
            },
            BerylliumMace_1 = {
                Name = "Beryllium Mace +1",
                Level = 72,
                Id = 22024,
                Jobs = {"WAR", "WHM", "PLD", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 45,
                    Delay = 291,
                    MP = 30,
                    STR = 8,
                    MND = 8,
                    Accuracy = 12,
                    Attack = 12,
                    CurePotency = 8,
                }
            },
            BlurredRod = {
                Name = "Blurred Rod",
                Level = 75,
                Id = 21093,
                Jobs = {"WAR", "MNK", "WHM", "BLM", "PLD", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 39,
                    Delay = 288,
                    INT = 7,
                    MND = 7,
                    Accuracy = 10,
                    MagicAccuracy = 10,
                }
            },
            BlurredRod_1 = {
                Name = "Blurred Rod +1",
                Level = 75,
                Id = 21094,
                Jobs = {"WAR", "MNK", "WHM", "BLM", "PLD", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 40,
                    Delay = 280,
                    INT = 8,
                    MND = 8,
                    Accuracy = 12,
                    MagicAccuracy = 12,
                }
            },
            BrassHammer = {
                Name = "Brass Hammer",
                Level = 12,
                Id = 17043,
                Jobs = {"WHM", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 13,
                    Delay = 324,
                }
            },
            BrassHammer_1 = {
                Name = "Brass Hammer +1",
                Level = 12,
                Id = 17149,
                Jobs = {"WHM", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 14,
                    Delay = 315,
                }
            },
            Buzdygan = {
                Name = "Buzdygan",
                Level = 71,
                Id = 17038,
                Jobs = {"WAR", "WHM", "PLD", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 34,
                    Delay = 300,
                    MP = 10,
                    DEX = 2,
                    VIT = 2,
                }
            },
            DarksteelMace = {
                Name = "Darksteel Mace",
                Level = 57,
                Id = 17037,
                Jobs = {"WAR", "WHM", "PLD", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 32,
                    Delay = 315,
                }
            },
            DarksteelMace_1 = {
                Name = "Darksteel Mace +1",
                Level = 57,
                Id = 17428,
                Jobs = {"WAR", "WHM", "PLD", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 33,
                    Delay = 306,
                }
            },
            DecurionsHammer = {
                Name = "Decurions Hammer",
                Level = 18,
                Id = 17048,
                Jobs = {"WHM", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 16,
                    Delay = 324,
                }
            },
            Divinity = {
                Name = "Divinity",
                Level = 75,
                Id = 21088,
                Jobs = {"WHM", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 52,
                    Delay = 340,
                    STR = 5,
                    MND = 8,
                    MagicAttackBonus = 12,
                }
            },
            DowsersWand = {
                Name = "Dowsers Wand",
                Level = 40,
                Id = 21124,
                Jobs = {"GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 15,
                    Delay = 216,
                    INT = 2,
                    MagicAccuracy = 2,
                }
            },
            EremitesWand = {
                Name = "Eremites Wand",
                Level = 28,
                Id = 17441,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 9,
                    Delay = 216,
                    MP = 5,
                    INT = 2,
                    MND = 2,
                }
            },
            EremitesWand_1 = {
                Name = "Eremites Wand +1",
                Level = 28,
                Id = 17442,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 10,
                    Delay = 210,
                    MP = 6,
                    INT = 2,
                    MND = 2,
                }
            },
            Idris = {
                Name = "Idris",
                Level = 75,
                Id = 21070,
                Jobs = {"GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 52,
                    Delay = 280,
                    MagicAccuracy = 10,
                    MagicAttackBonus = 10,
                }
            },
            KrakenClub = {
                Name = "Kraken Club",
                Level = 63,
                Id = 17440,
                Jobs = {"WAR", "MNK", "WHM", "BLM", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "SMN"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 11,
                    Delay = 264,
                }
            },
            KrakenClub_1 = {
                Name = "Kraken Club +1",
                Level = 63,
                Id = 21104,
                Jobs = {"All"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 12,
                    Delay = 264,
                }
            },
            MapleWand = {
                Name = "Maple Wand",
                Level = 1,
                Id = 17049,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 3,
                    Delay = 216,
                    INT = 1,
                    MND = 1,
                }
            },
            MapleWand_1 = {
                Name = "Maple Wand +1",
                Level = 1,
                Id = 17087,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 4,
                    Delay = 210,
                    INT = 2,
                    MND = 2,
                }
            },
            MoblinMallet = {
                Name = "Moblin Mallet",
                Level = 70,
                Id = 21102,
                Jobs = {"MNK", "WHM", "BLM", "SMN", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 9,
                    Delay = 340,
                    HP = 50,
                }
            },
            MoepapaMace = {
                Name = "Moepapa Mace",
                Level = 75,
                Id = 17069,
                Jobs = {"WAR", "WHM", "PLD", "BLU", "GEO", "RUN"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 45,
                    Delay = 300,
                    MND = 8,
                    Accuracy = 8,
                }
            },
            Nehushtan = {
                Name = "Nehushtan",
                Level = 75,
                Id = 21105,
                Jobs = {"WHM", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 50,
                    Delay = 340,
                    STR = 10,
                    MND = 10,
                    Attack = 20,
                    Refresh = 1,
                    HMP = 15,
                }
            },
            PilgrimsWand = {
                Name = "Pilgrims Wand",
                Level = 10,
                Id = 18394,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 6,
                    Delay = 216,
                    HMP = 2,
                }
            },
            Scepter = {
                Name = "Scepter",
                Level = 72,
                Id = 17064,
                Jobs = {"WHM", "BLM", "SMN", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 26,
                    Delay = 288,
                    HP = 24,
                    DEX = 2,
                    VIT = 2,
                }
            },
            Sindri = {
                Name = "Sindri",
                Level = 75,
                Id = 21110,
                Jobs = {"WHM"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 49,
                    Delay = 324,
                    MP = 15,
                    MND = 6,
                    Accuracy = 8,
                    MagicAccuracy = 4,
                    Enmity = -4,
                    DoubleAttack = 3,
                }
            },
            SolidWand = {
                Name = "Solid Wand",
                Level = 32,
                Id = 17141,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 11,
                    Delay = 210,
                    INT = 5,
                    MND = 5,
                }
            },
            Tamaxchi = {
                Name = "Tamaxchi",
                Level = 75,
                Id = 21125,
                Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 31,
                    Delay = 216,
                    INT = 3,
                    MND = 3,
                    MagicAccuracy = 2,
                    MagicAttackBonus = 5,
                    CurePotency = 10,
                }
            },
            VejovisWand = {
                Name = "Vejovis Wand",
                Level = 73,
                Id = 18884,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 32,
                    Delay = 216,
                    MP = 10,
                    VIT = 3,
                    Accuracy = 3,
                }
            },
            VejovisWand_1 = {
                Name = "Vejovis Wand +1",
                Level = 73,
                Id = 18885,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 33,
                    Delay = 210,
                    MP = 15,
                    VIT = 4,
                    Accuracy = 4,
                }
            },
            WildCudgel = {
                Name = "Wild Cudgel",
                Level = 11,
                Id = 17412,
                Jobs = {"All"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 7,
                    Delay = 264,
                    HP = 20,
                    MP = -20,
                }
            },
            WillowWand = {
                Name = "Willow Wand",
                Level = 9,
                Id = 17050,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 5,
                    Delay = 216,
                    INT = 2,
                    MND = 2,
                }
            },
            WillowWand_1 = {
                Name = "Willow Wand +1",
                Level = 9,
                Id = 17138,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 6,
                    Delay = 210,
                    INT = 3,
                    MND = 3,
                }
            },
            YewWand = {
                Name = "Yew Wand",
                Level = 18,
                Id = 17051,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 7,
                    Delay = 216,
                    INT = 3,
                    MND = 3,
                }
            },
            YewWand_1 = {
                Name = "Yew Wand +1",
                Level = 18,
                Id = 17140,
                Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
                OneHanded = true,
                Type = "Club",
                Stats = {
                    DMG = 8,
                    Delay = 210,
                    INT = 4,
                    MND = 4,
                }
            },
        },
        Staff = {
            AshPole = {
                Name = "Ash Pole",
                Level = 5,
                Id = 17095,
                Jobs = {"MNK", "WHM", "BLM", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 11,
                    Delay = 402,
                }
            },
            AshPole_1 = {
                Name = "Ash Pole +1",
                Level = 5,
                Id = 17122,
                Jobs = {"MNK", "WHM", "BLM", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 12,
                    Delay = 390,
                }
            },
            AstarothCane = {
                Name = "Astaroth Cane",
                Level = 27,
                Id = 18604,
                Jobs = {"WAR", "MNK", "WHM", "BLM", "RDM", "BST", "BRD", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 14,
                    Delay = 366,
                    INT = 2,
                    MagicAccuracy = 3,
                }
            },
            BahamutsStaff = {
                Name = "Bahamuts Staff",
                Level = 75,
                Id = 17598,
                Jobs = {"SMN"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 55,
                    Delay = 366,
                    MP = 30,
                }
            },
            BaqilStaff = {
                Name = "Baqil Staff",
                Level = 75,
                Id = 21186,
                Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 57,
                    Delay = 402,
                    MP = 10,
                    INT = 3,
                    MND = 3,
                    Accuracy = 6,
                    MagicAccuracy = 4,
                }
            },
            ChatoyantStaff = {
                Name = "Chatoyant Staff",
                Level = 51,
                Id = 18633,
                Jobs = {"All"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 35,
                    Delay = 356,
                    STR = 5,
                    DEX = 5,
                    VIT = 5,
                    AGI = 5,
                    INT = 5,
                    MND = 5,
                    CHR = 5,
                    CurePotency = 10,
                    HMP = 10,
                }
            },
            ChtonicStaff = {
                Name = "Chtonic Staff",
                Level = 75,
                Id = 18623,
                Jobs = {"All"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 45,
                    Delay = 356,
                }
            },
            Coeus = {
                Name = "Coeus",
                Level = 75,
                Id = 21175,
                Jobs = {"SCH"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 58,
                    Delay = 366,
                    MP = 40,
                    INT = 8,
                    Enmity = -4,
                    ConserveMP = 8,
                }
            },
            ExaltedStaff = {
                Name = "Exalted Staff",
                Level = 72,
                Id = 22078,
                Jobs = {"MNK", "WHM", "PLD", "DRG"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 59,
                    Delay = 412,
                    MP = 25,
                    STR = 8,
                    INT = 8,
                    Accuracy = 10,
                    Attack = 10,
                }
            },
            ExaltedStaff_1 = {
                Name = "Exalted Staff +1",
                Level = 72,
                Id = 22079,
                Jobs = {"MNK", "WHM", "PLD", "DRG"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 60,
                    Delay = 399,
                    MP = 30,
                    STR = 12,
                    INT = 12,
                    Accuracy = 15,
                    Attack = 15,
                }
            },
            FletePole = {
                Name = "Flete Pole",
                Level = 73,
                Id = 18628,
                Jobs = {"MNK", "WHM", "BLM", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 66,
                    Delay = 402,
                    Attack = 7,
                    Haste = 1,
                }
            },
            FletePole_1 = {
                Name = "Flete Pole +1",
                Level = 73,
                Id = 18629,
                Jobs = {"MNK", "WHM", "BLM", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 67,
                    Delay = 390,
                    Attack = 8,
                    Haste = 2,
                }
            },
            GelongStaff = {
                Name = "Gelong Staff",
                Level = 10,
                Id = 17594,
                Jobs = {"All"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 14,
                    Delay = 390,
                    HHP = 4,
                }
            },
            Gridarvor = {
                Name = "Gridarvor",
                Level = 75,
                Id = 21174,
                Jobs = {"SMN"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 60,
                    Delay = 366,
                    MP = 35,
                    INT = 6,
                    MND = 6,
                    Accuracy = 8,
                    Enmity = -4,
                    DoubleAttack = 3,
                }
            },
            HollyStaff = {
                Name = "Holly Staff",
                Level = 11,
                Id = 17089,
                Jobs = {"WAR", "MNK", "WHM", "BLM", "RDM", "BST", "BRD", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 10,
                    Delay = 366,
                    HP = 4,
                    MP = 4,
                }
            },
            HollyStaff_1 = {
                Name = "Holly Staff +1",
                Level = 11,
                Id = 17125,
                Jobs = {"WAR", "MNK", "WHM", "BLM", "RDM", "BST", "BRD", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 11,
                    Delay = 356,
                    HP = 5,
                    MP = 5,
                }
            },
            IronSplitter = {
                Name = "Iron-splitter",
                Level = 72,
                Id = 17569,
                Jobs = {"MNK", "WHM", "PLD", "DRG"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 64,
                    Delay = 412,
                    DEX = 2,
                    HHP = 3,
                }
            },
            Kaladanda = {
                Name = "Kaladanda",
                Level = 75,
                Id = 21173,
                Jobs = {"BLM"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 58,
                    Delay = 366,
                    MP = 20,
                    STR = 6,
                    DEX = 6,
                    VIT = 6,
                    AGI = 6,
                    INT = 6,
                    MND = 6,
                    CHR = 6,
                    Attack = 8,
                }
            },
            Keraunos = {
                Name = "Keraunos",
                Level = 75,
                Id = 21169,
                Jobs = {"BLM", "SCH"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 40,
                    Delay = 402,
                    INT = 10,
                    MND = 10,
                    Accuracy = 20,
                    MagicAttackBonus = 10,
                    Enmity = -10,
                    CurePotency = 10,
                    HMP = 15,
                }
            },
            KirinsPole = {
                Name = "Kirins Pole",
                Level = 75,
                Id = 17567,
                Jobs = {"MNK", "WHM", "BLM", "PLD", "DRG", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 60,
                    Delay = 402,
                    HP = 20,
                    MP = 20,
                    INT = 10,
                    MND = 10,
                }
            },
            Majestas = {
                Name = "Majestas",
                Level = 75,
                Id = 18603,
                Jobs = {"MNK", "WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 42,
                    Delay = 412,
                }
            },
            MercenarysPole = {
                Name = "Mercenarys Pole",
                Level = 18,
                Id = 17103,
                Jobs = {"MNK", "WHM", "BLM", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 22,
                    Delay = 402,
                }
            },
            MonsterSigna = {
                Name = "Monster Signa",
                Level = 17,
                Id = 17132,
                Jobs = {"WAR", "MNK", "WHM", "BLM", "RDM", "BST", "BRD", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 12,
                    Delay = 366,
                    HP = 5,
                    MP = 5,
                    VIT = -5,
                    CHR = 8,
                }
            },
            NumenStaff = {
                Name = "Numen Staff",
                Level = 75,
                Id = 18624,
                Jobs = {"WAR", "MNK", "WHM", "BLM", "RDM", "BST", "BRD", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 51,
                    Delay = 366,
                    MP = 25,
                    HMP = 11,
                }
            },
            PassaddhiStaff = {
                Name = "Passaddhi Staff",
                Level = 39,
                Id = 18606,
                Jobs = {"WAR", "MNK", "WHM", "BLM", "RDM", "BST", "BRD", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 15,
                    Delay = 366,
                    MND = 1,
                    MagicAccuracy = 3,
                }
            },
            PassaddhiStaff_1 = {
                Name = "Passaddhi Staff +1",
                Level = 39,
                Id = 18615,
                Jobs = {"WAR", "MNK", "WHM", "BLM", "RDM", "BST", "BRD", "SMN", "SCH", "GEO"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 16,
                    Delay = 356,
                    MND = 2,
                    MagicAccuracy = 4,
                }
            },
            PlutosStaff = {
                Name = "Plutos Staff",
                Level = 51,
                Id = 17560,
                Jobs = {"All"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 35,
                    Delay = 356,
                    STR = 2,
                    DEX = 2,
                    VIT = 2,
                    AGI = 2,
                    INT = 2,
                    MND = 2,
                    CHR = 2,
                    HMP = 10,
                }
            },
            TerrasStaff = {
                Name = "Terras Staff",
                Level = 51,
                Id = 17552,
                Jobs = {"All"},
                OneHanded = false,
                Type = "Staff",
                Stats = {
                    DMG = 35,
                    Delay = 356,
                    VIT = 5,
                }
            },
        },
    },
    Sub = {
        Adamas = {
            Name = "Adamas",
            Level = 75,
            Id = 10806,
            Jobs = {"PLD"},
            Type = "Sub",
            Stats = {
                DEF = 28,
                MP = 50,
                Enmity = -15,
                CurePotency = 15,
            }
        },
        Aspis = {
            Name = "Aspis",
            Level = 9,
            Id = 12299,
            Jobs = {"WAR", "RDM", "PLD", "BST", "SAM"},
            Type = "Sub",
            Stats = {
                DEF = 3,
            }
        },
        Aspis_1 = {
            Name = "Aspis +1",
            Level = 9,
            Id = 12325,
            Jobs = {"WAR", "RDM", "PLD", "BST", "SAM"},
            Type = "Sub",
            Stats = {
                DEF = 4,
            }
        },
        BrassGrip = {
            Name = "Brass Grip",
            Level = 30,
            Id = 19009,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                DEX = 1,
            }
        },
        BrassGrip_1 = {
            Name = "Brass Grip +1",
            Level = 30,
            Id = 19010,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                DEX = 2,
            }
        },
        Clipeus = {
            Name = "Clipeus",
            Level = 9,
            Id = 12371,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Sub",
            Stats = {
                DEF = 5,
                Evasion = 1,
            }
        },
        DagdasShield = {
            Name = "Dagdas Shield",
            Level = 70,
            Id = 16202,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Sub",
            Stats = {
                DEF = 20,
                Enmity = 2,
                CurePotency = 5,
            }
        },
        DecurionsShield = {
            Name = "Decurions Shield",
            Level = 20,
            Id = 12337,
            Jobs = {"WAR", "RDM", "PLD", "BST", "SAM"},
            Type = "Sub",
            Stats = {
                DEF = 6,
            }
        },
        FurtiveGrip = {
            Name = "Furtive Grip",
            Level = 75,
            Id = 18817,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                SubtleBlow = 5,
            }
        },
        GattaStrap = {
            Name = "Gatta Strap",
            Level = 74,
            Id = 18806,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                STR = 3,
                DEX = 3,
                Attack = 3,
            }
        },
        GattaStrap_1 = {
            Name = "Gatta Strap +1",
            Level = 74,
            Id = 18807,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                STR = 4,
                DEX = 4,
                Attack = 4,
            }
        },
        GenbusShield = {
            Name = "Genbus Shield",
            Level = 74,
            Id = 12296,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Sub",
            Stats = {
                DEF = 24,
                Evasion = 10,
            }
        },
        GenmeiShield = {
            Name = "Genmei Shield",
            Level = 74,
            Id = 27645,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Sub",
            Stats = {
                DEF = 30,
                Evasion = 12,
                CurePotency = 8,
            }
        },
        KupoShield = {
            Name = "Kupo Shield",
            Level = 1,
            Id = 26406,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
            }
        },
        MythrilGrip_1 = {
            Name = "Mythril Grip +1",
            Level = 55,
            Id = 19014,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                STR = 2,
                VIT = 2,
                Accuracy = 2,
            }
        },
        NephGrip = {
            Name = "Neph. Grip",
            Level = 8,
            Id = 22198,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                MP = 6,
                INT = 1,
            }
        },
        OneirosGrip = {
            Name = "Oneiros Grip",
            Level = 75,
            Id = 18811,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                HP = 5,
                MP = 5,
                Regen = 1,
            }
        },
        OrcishAxegrip = {
            Name = "Orcish Axegrip",
            Level = 20,
            Id = 20844,
            Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                HP = 12,
            }
        },
        OssaGrip = {
            Name = "Ossa Grip",
            Level = 75,
            Id = 18812,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
            }
        },
        Pelte = {
            Name = "Pelte",
            Level = 8,
            Id = 16185,
            Jobs = {"WHM", "BLM", "RDM", "PLD", "DRK", "SMN", "BLU", "SCH", "GEO", "RUN"},
            Type = "Sub",
            Stats = {
                DEF = 1,
                MP = 5,
            }
        },
        Priwen = {
            Name = "Priwen",
            Level = 75,
            Id = 28648,
            Jobs = {"PLD"},
            Type = "Sub",
            Stats = {
                DEF = 30,
                HP = 20,
                Regen = 1,
            }
        },
        RaptorStrap = {
            Name = "Raptor Strap",
            Level = 55,
            Id = 19015,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                HP = 10,
                MP = 5,
                MND = 1,
            }
        },
        SentinelShield = {
            Name = "Sentinel Shield",
            Level = 50,
            Id = 16168,
            Jobs = {"WAR", "RDM", "PLD", "BST", "SAM"},
            Type = "Sub",
            Stats = {
                DEF = 10,
                STR = 3,
                Haste = 1,
            }
        },
        Svalinn = {
            Name = "Svalinn",
            Level = 75,
            Id = 27627,
            Jobs = {"WAR"},
            Type = "Sub",
            Stats = {
                DEF = 40,
                VIT = 10,
                Accuracy = 20,
                Enmity = 10,
            }
        },
        TenaxStrap = {
            Name = "Tenax Strap",
            Level = 5,
            Id = 19043,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                Attack = 1,
            }
        },
        ThunderGrip = {
            Name = "Thunder Grip",
            Level = 70,
            Id = 19035,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
            }
        },
        TortoiseShield = {
            Name = "Tortoise Shield",
            Level = 30,
            Id = 12374,
            Jobs = {"WHM", "BLM", "RDM", "PLD", "DRK", "SMN", "BLU", "SCH", "GEO", "RUN"},
            Type = "Sub",
            Stats = {
                INT = 1,
                MND = 1,
            }
        },
        VerseStrap = {
            Name = "Verse Strap",
            Level = 74,
            Id = 18808,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                MND = 2,
                Enmity = -2,
                CurePotency = 2,
            }
        },
        VerseStrap_1 = {
            Name = "Verse Strap +1",
            Level = 74,
            Id = 18809,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                MND = 3,
                Enmity = -3,
                CurePotency = 3,
            }
        },
        WaterGrip = {
            Name = "Water Grip",
            Level = 70,
            Id = 19032,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
            }
        },
        WizzanGrip = {
            Name = "Wizzan Grip",
            Level = 75,
            Id = 18816,
            Jobs = {"All"},
            Type = "Sub",
            Stats = {
                DMG = 1,
                Delay = 999,
                INT = 2,
                ConserveMP = 1,
            }
        },
    },
    Range = {
        Archery = {
            AifesBow = {
                Name = "Aifes Bow",
                Level = 75,
                Id = 19738,
                Jobs = {"RDM", "RNG"},
                Type = "Archery",
                Stats = {
                    DMG = 79,
                    Delay = 540,
                    MP = 15,
                    RangedAccuracy = 12,
                    Enmity = -6,
                    SubtleBlow = 8,
                }
            },
            AjjubBow = {
                Name = "Ajjub Bow",
                Level = 75,
                Id = 21233,
                Jobs = {"RNG", "SAM"},
                Type = "Archery",
                Stats = {
                    DMG = 76,
                    Delay = 540,
                    AGI = 6,
                    RangedAccuracy = 5,
                    RangedAttack = 5,
                }
            },
            ExaltedBow = {
                Name = "Exalted Bow",
                Level = 72,
                Id = 22125,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "RNG", "SAM", "NIN"},
                Type = "Archery",
                Stats = {
                    DMG = 48,
                    Delay = 360,
                    MP = 25,
                    AGI = 3,
                    MND = 3,
                    RangedAccuracy = 15,
                    RangedAttack = 15,
                }
            },
            ExaltedBow_1 = {
                Name = "Exalted Bow +1",
                Level = 72,
                Id = 22126,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "RNG", "SAM", "NIN"},
                Type = "Archery",
                Stats = {
                    DMG = 49,
                    Delay = 351,
                    MP = 30,
                    AGI = 4,
                    MND = 4,
                    RangedAccuracy = 18,
                    RangedAttack = 18,
                }
            },
            GreatBow = {
                Name = "Great Bow",
                Level = 30,
                Id = 17162,
                Jobs = {"WAR", "PLD", "DRK", "RNG", "SAM"},
                Type = "Archery",
                Stats = {
                    DMG = 43,
                    Delay = 540,
                }
            },
            HuntersLongbow = {
                Name = "Hunters Longbow",
                Level = 12,
                Id = 17183,
                Jobs = {"RNG"},
                Type = "Archery",
                Stats = {
                    DMG = 27,
                    Delay = 490,
                    STR = 1,
                    AGI = 1,
                    RangedAccuracy = 2,
                    RangedAttack = 5,
                }
            },
            Longbow_1 = {
                Name = "Longbow +1",
                Level = 5,
                Id = 17177,
                Jobs = {"WAR", "PLD", "DRK", "RNG", "SAM"},
                Type = "Archery",
                Stats = {
                    DMG = 18,
                    Delay = 524,
                    RangedAccuracy = 2,
                    RangedAttack = 3,
                }
            },
            Nurigomeyumi = {
                Name = "Nurigomeyumi",
                Level = 73,
                Id = 19786,
                Jobs = {"RNG", "SAM"},
                Type = "Archery",
                Stats = {
                    DMG = 76,
                    Delay = 600,
                    STR = 1,
                    RangedAccuracy = 11,
                    RangedAttack = 5,
                }
            },
            Nurigomeyumi_1 = {
                Name = "Nurigomeyumi +1",
                Level = 73,
                Id = 19787,
                Jobs = {"RNG", "SAM"},
                Type = "Archery",
                Stats = {
                    DMG = 77,
                    Delay = 582,
                    STR = 2,
                    RangedAccuracy = 12,
                    RangedAttack = 6,
                }
            },
            Phaosphaelia = {
                Name = "Phaosphaelia",
                Level = 75,
                Id = 21224,
                Jobs = {"RNG"},
                Type = "Archery",
                Stats = {
                    DMG = 90,
                    Delay = 540,
                    AGI = 10,
                    RangedAccuracy = 10,
                    RangedAttack = 30,
                    Enmity = -10,
                    CriticalHitRate = 10,
                    DualWield = 5,
                }
            },
            PowerBow_1 = {
                Name = "Power Bow +1",
                Level = 16,
                Id = 17178,
                Jobs = {"WAR", "PLD", "DRK", "RNG", "SAM"},
                Type = "Archery",
                Stats = {
                    DMG = 31,
                    Delay = 524,
                    RangedAccuracy = 2,
                    RangedAttack = 9,
                }
            },
            SelfBow_1 = {
                Name = "Self Bow +1",
                Level = 7,
                Id = 17176,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "RNG", "SAM", "NIN"},
                Type = "Archery",
                Stats = {
                    DMG = 15,
                    Delay = 441,
                    RangedAccuracy = 3,
                }
            },
            Shortbow_1 = {
                Name = "Shortbow +1",
                Level = 1,
                Id = 17175,
                Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "RNG", "SAM", "NIN"},
                Type = "Archery",
                Stats = {
                    DMG = 6,
                    Delay = 351,
                    RangedAccuracy = 3,
                }
            },
        },
        Marksmanship = {
            AlmogavarBow = {
                Name = "Almogavar Bow",
                Level = 20,
                Id = 17211,
                Jobs = {"WAR", "THF", "DRK", "RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 15,
                    Delay = 288,
                    RangedAttack = 4,
                }
            },
            ArcaneArbalest = {
                Name = "Arcane Arbalest",
                Level = 50,
                Id = 21479,
                Jobs = {"WAR", "THF", "DRK", "RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 32,
                    Delay = 288,
                    INT = 4,
                    MND = 4,
                    Attack = 3,
                    RangedAccuracy = 5,
                }
            },
            Atetepeyorg = {
                Name = "Atetepeyorg",
                Level = 75,
                Id = 21253,
                Jobs = {"THF", "RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 48,
                    Delay = 432,
                    AGI = 3,
                    MND = 3,
                    RangedAccuracy = 5,
                    MagicAccuracy = 5,
                    MagicAttackBonus = 5,
                    Enmity = -5,
                }
            },
            BanditsGun = {
                Name = "Bandits Gun",
                Level = 15,
                Id = 17257,
                Jobs = {"THF", "RNG", "NIN", "COR"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 14,
                    Delay = 600,
                }
            },
            BlurredCrossbow = {
                Name = "Blurred Crossbow",
                Level = 75,
                Id = 21480,
                Jobs = {"THF", "RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 43,
                    Delay = 288,
                    AGI = 7,
                    MND = 7,
                    RangedAccuracy = 15,
                    RangedAttack = 5,
                }
            },
            Crossbow = {
                Name = "Crossbow",
                Level = 12,
                Id = 17217,
                Jobs = {"WAR", "THF", "DRK", "RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 12,
                    Delay = 288,
                }
            },
            Crossbow_1 = {
                Name = "Crossbow +1",
                Level = 12,
                Id = 17225,
                Jobs = {"WAR", "THF", "DRK", "RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 13,
                    Delay = 280,
                    RangedAttack = 6,
                }
            },
            Culverin = {
                Name = "Culverin",
                Level = 73,
                Id = 17252,
                Jobs = {"THF", "RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 50,
                    Delay = 760,
                    RangedAccuracy = -10,
                    RangedAttack = 18,
                }
            },
            Deathlocke = {
                Name = "Deathlocke",
                Level = 75,
                Id = 21278,
                Jobs = {"COR"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 35,
                    Delay = 480,
                    HP = 15,
                    MP = 15,
                    AGI = 6,
                    RangedAccuracy = 8,
                    MagicAccuracy = 5,
                    MagicAttackBonus = 5,
                    StoreTP = 5,
                    Enmity = -4,
                }
            },
            Doomsday = {
                Name = "Doomsday",
                Level = 75,
                Id = 21476,
                Jobs = {"RNG", "COR"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 56,
                    Delay = 600,
                    STR = 10,
                    AGI = 10,
                    RangedAttack = 20,
                    MagicAttackBonus = 15,
                    Haste = 4,
                    StoreTP = 10,
                }
            },
            Firefly = {
                Name = "Firefly",
                Level = 5,
                Id = 19221,
                Jobs = {"THF", "RNG", "NIN", "COR"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 11,
                    Delay = 600,
                    AGI = 1,
                }
            },
            Insurance = {
                Name = "Insurance",
                Level = 20,
                Id = 22144,
                Jobs = {"RNG", "COR"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 20,
                    Delay = 600,
                    AGI = 3,
                    RangedAttack = 10,
                    MagicAttackBonus = 5,
                    StoreTP = 3,
                }
            },
            Insurance_1 = {
                Name = "Insurance +1",
                Level = 50,
                Id = 21275,
                Jobs = {"RNG", "COR"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 38,
                    Delay = 600,
                    AGI = 5,
                    RangedAttack = 15,
                    MagicAttackBonus = 10,
                    Haste = 2,
                    StoreTP = 5,
                }
            },
            LgnCrossbow = {
                Name = "Lgn. Crossbow",
                Level = 10,
                Id = 17223,
                Jobs = {"WAR", "THF", "DRK", "RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 10,
                    Delay = 288,
                }
            },
            LightCrossbow_1 = {
                Name = "Light Crossbow +1",
                Level = 1,
                Id = 17228,
                Jobs = {"WAR", "DRK", "RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 7,
                    Delay = 280,
                    RangedAttack = 3,
                }
            },
            Lionsquall = {
                Name = "Lionsquall",
                Level = 75,
                Id = 21277,
                Jobs = {"RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 42,
                    Delay = 600,
                    HP = 20,
                    AGI = 6,
                    RangedAttack = 15,
                    MagicAttackBonus = 8,
                    StoreTP = 5,
                    Enmity = -4,
                }
            },
            Opprimo = {
                Name = "Opprimo",
                Level = 73,
                Id = 19743,
                Jobs = {"RNG", "COR"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 38,
                    Delay = 600,
                    MP = 15,
                    AGI = 2,
                    RangedAccuracy = 4,
                    Enmity = -2,
                }
            },
            Opprimo_1 = {
                Name = "Opprimo +1",
                Level = 73,
                Id = 19744,
                Jobs = {"RNG", "COR"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 39,
                    Delay = 582,
                    MP = 20,
                    AGI = 3,
                    RangedAccuracy = 5,
                    Enmity = -3,
                }
            },
            PlatoonGun = {
                Name = "Platoon Gun",
                Level = 20,
                Id = 17271,
                Jobs = {"THF", "RNG", "NIN", "COR"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 15,
                    Delay = 600,
                }
            },
            Zamburak_1 = {
                Name = "Zamburak +1",
                Level = 30,
                Id = 17229,
                Jobs = {"WAR", "THF", "DRK", "RNG"},
                Type = "Marksmanship",
                Stats = {
                    DMG = 20,
                    Delay = 280,
                    RangedAttack = 9,
                }
            },
        },
        Throwing = {
            Rogetsurin = {
                Name = "Rogetsurin",
                Level = 15,
                Id = 18246,
                Jobs = {"THF", "NIN", "BLU", "DNC"},
                Type = "Throwing",
                Stats = {
                    DMG = 9,
                    Delay = 286,
                    AGI = 1,
                }
            },
        },
        StringInstrument = {
            AngelLyre = {
                Name = "Angel Lyre",
                Level = 71,
                Id = 17840,
                Jobs = {"BRD"},
                Type = "StringInstrument",
                Stats = {
                    Delay = 240,
                    Haste = 2,
                }
            },
            MilitaryHarp = {
                Name = "Military Harp",
                Level = 33,
                Id = 17839,
                Jobs = {"BRD"},
                Type = "StringInstrument",
                Stats = {
                    Delay = 240,
                }
            },
            OneirosHarp = {
                Name = "Oneiros Harp",
                Level = 75,
                Id = 17358,
                Jobs = {"BRD"},
                Type = "StringInstrument",
                Stats = {
                    Delay = 240,
                    Regen = 1,
                }
            },
            RoseHarp = {
                Name = "Rose Harp",
                Level = 36,
                Id = 17355,
                Jobs = {"BRD"},
                Type = "StringInstrument",
                Stats = {
                    Delay = 240,
                }
            },
            RoseHarp_1 = {
                Name = "Rose Harp +1",
                Level = 36,
                Id = 17376,
                Jobs = {"BRD"},
                Type = "StringInstrument",
                Stats = {
                    Delay = 240,
                }
            },
            Terpander = {
                Name = "Terpander",
                Level = 75,
                Id = 21407,
                Jobs = {"BRD"},
                Type = "StringInstrument",
                Stats = {
                    Delay = 999,
                    HP = 15,
                    MP = 15,
                    Enmity = -4,
                }
            },
        },
        WindInstrument = {
            Cornette_1 = {
                Name = "Cornette +1",
                Level = 4,
                Id = 17369,
                Jobs = {"BRD"},
                Type = "WindInstrument",
                Stats = {
                    Delay = 240,
                }
            },
            Gjallarhorn = {
                Name = "Gjallarhorn",
                Level = 75,
                Id = 18342,
                Jobs = {"BRD"},
                Type = "WindInstrument",
                Stats = {
                    Delay = 240,
                    CHR = 4,
                }
            },
            Linos = {
                Name = "Linos",
                Level = 75,
                Id = 21404,
                Jobs = {"BRD"},
                Type = "WindInstrument",
                Stats = {
                    Delay = 240,
                    MPP = 10,
                    DEX = 10,
                    CHR = 10,
                    Accuracy = 20,
                    Haste = 4,
                }
            },
            MarysHorn = {
                Name = "Marys Horn",
                Level = 14,
                Id = 17366,
                Jobs = {"BRD"},
                Type = "WindInstrument",
                Stats = {
                    Delay = 240,
                }
            },
            Rouser = {
                Name = "Rouser",
                Level = 20,
                Id = 22296,
                Jobs = {"BRD"},
                Type = "WindInstrument",
                Stats = {
                    Delay = 240,
                    DEX = 3,
                    CHR = 3,
                    Haste = 1,
                }
            },
            RylSprHorn = {
                Name = "Ryl.Spr. Horn",
                Level = 20,
                Id = 17367,
                Jobs = {"BRD"},
                Type = "WindInstrument",
                Stats = {
                    Delay = 240,
                    CHR = 3,
                }
            },
            Traversiere_2 = {
                Name = "Traversiere +2",
                Level = 32,
                Id = 17845,
                Jobs = {"BRD"},
                Type = "WindInstrument",
                Stats = {
                    Delay = 240,
                    MP = 10,
                }
            },
        },
        Handbell = {
            Dunna = {
                Name = "Dunna",
                Level = 75,
                Id = 21372,
                Jobs = {"GEO"},
                Type = "Handbell",
                Stats = {
                    Delay = 999,
                    MP = 25,
                    INT = 4,
                    Enmity = -4,
                }
            },
            FiliaeBell = {
                Name = "Filiae Bell",
                Level = 40,
                Id = 21461,
                Jobs = {"GEO"},
                Type = "Handbell",
                Stats = {
                    Delay = 999,
                    MP = 15,
                    MND = 1,
                }
            },
            MatreBell = {
                Name = "Matre Bell",
                Level = 1,
                Id = 21460,
                Jobs = {"GEO"},
                Type = "Handbell",
                Stats = {
                    Delay = 999,
                    MP = 5,
                }
            },
            NepoteBell = {
                Name = "Nepote Bell",
                Level = 75,
                Id = 21463,
                Jobs = {"GEO"},
                Type = "Handbell",
                Stats = {
                    Delay = 999,
                    MP = 20,
                    INT = 2,
                }
            },
        },
        FishingRod = {
            LuShangsFRod = {
                Name = "Lu Shangs F. Rod",
                Level = 1,
                Id = 17386,
                Jobs = {"All"},
                Type = "FishingRod",
                Stats = {
                    Delay = 240,
                }
            },
        },
    },
    Ammo = {
        AcidBolt = {
            Name = "Acid Bolt",
            Level = 15,
            Id = 18148,
            Jobs = {"WAR", "THF", "DRK", "RNG"},
            Type = "Ammo",
            Stats = {
                DMG = 21,
                Delay = 192,
            }
        },
        AnimikiiBullet = {
            Name = "Animikii Bullet",
            Level = 75,
            Id = 21334,
            Jobs = {"RNG", "COR"},
            Type = "Ammo",
            Stats = {
                DMG = 80,
                Delay = 240,
                RangedAccuracy = 25,
                MagicAccuracy = 10,
                MagicAttackBonus = 5,
            }
        },
        BismuthBullet = {
            Name = "Bismuth Bullet",
            Level = 70,
            Id = 21333,
            Jobs = {"RNG", "COR"},
            Type = "Ammo",
            Stats = {
                DMG = 88,
                Delay = 240,
                RangedAccuracy = 5,
                RangedAttack = 5,
            }
        },
        BlindBolt = {
            Name = "Blind Bolt",
            Level = 10,
            Id = 18150,
            Jobs = {"WAR", "THF", "DRK", "RNG"},
            Type = "Ammo",
            Stats = {
                DMG = 18,
                Delay = 192,
            }
        },
        BoneArrow = {
            Name = "Bone Arrow",
            Level = 7,
            Id = 17319,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "RNG", "SAM", "NIN"},
            Type = "Ammo",
            Stats = {
                DMG = 9,
                Delay = 120,
            }
        },
        BronzeBullet = {
            Name = "Bronze Bullet",
            Level = 1,
            Id = 17343,
            Jobs = {"All"},
            Type = "Ammo",
            Stats = {
                DMG = 3,
                Delay = 240,
            }
        },
        Bullet = {
            Name = "Bullet",
            Level = 22,
            Id = 17340,
            Jobs = {"THF", "RNG", "NIN", "COR"},
            Type = "Ammo",
            Stats = {
                DMG = 46,
                Delay = 240,
            }
        },
        Cinderstone = {
            Name = "Cinderstone",
            Level = 60,
            Id = 21385,
            Jobs = {"WAR", "MNK", "THF", "DRK", "NIN", "DRG", "RUN"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                HP = 20,
                STR = 4,
                Enmity = 2,
            }
        },
        CorsairBullet = {
            Name = "Corsair Bullet",
            Level = 61,
            Id = 18235,
            Jobs = {"COR"},
            Type = "Ammo",
            Stats = {
                DMG = 57,
                Delay = 240,
                RangedAccuracy = 25,
            }
        },
        CrossbowBolt = {
            Name = "Crossbow Bolt",
            Level = 1,
            Id = 17336,
            Jobs = {"All"},
            Type = "Ammo",
            Stats = {
                DMG = 10,
                Delay = 192,
            }
        },
        DemonryCore = {
            Name = "Demonry Core",
            Level = 75,
            Id = 19764,
            Jobs = {"MNK", "RDM", "THF", "BST", "RNG", "NIN", "DRG", "COR", "PUP", "DNC", "RUN"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                DEX = 2,
            }
        },
        DemonryStone = {
            Name = "Demonry Stone",
            Level = 75,
            Id = 19765,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                MP = 15,
                MagicDefenseBonus = 1,
            }
        },
        FurysEdge = {
            Name = "Furys Edge",
            Level = 75,
            Id = 22280,
            Jobs = {"WAR"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                STR = 4,
                VIT = 6,
                DoubleAttack = 2,
            }
        },
        HolyBolt = {
            Name = "Holy Bolt",
            Level = 30,
            Id = 18153,
            Jobs = {"WAR", "DRK", "RNG"},
            Type = "Ammo",
            Stats = {
                DMG = 32,
                Delay = 192,
            }
        },
        IronBullet = {
            Name = "Iron Bullet",
            Level = 50,
            Id = 17312,
            Jobs = {"THF", "RNG", "NIN", "COR"},
            Type = "Ammo",
            Stats = {
                DMG = 55,
                Delay = 240,
            }
        },
        JinxAmpulla = {
            Name = "Jinx Ampulla",
            Level = 75,
            Id = 19245,
            Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "SCH", "GEO"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                HP = -15,
            }
        },
        LivingBullet = {
            Name = "Living Bullet",
            Level = 75,
            Id = 21326,
            Jobs = {"COR"},
            Type = "Ammo",
            Stats = {
                DMG = 77,
                Delay = 240,
                MagicAccuracy = 10,
                MagicAttackBonus = 15,
            }
        },
        LizardLure = {
            Name = "Lizard Lure",
            Level = 1,
            Id = 17401,
            Jobs = {"All"},
            Type = "Ammo",
            Stats = {
                Delay = 240,
            }
        },
        ManaAmpulla = {
            Name = "Mana Ampulla",
            Level = 70,
            Id = 19780,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                MP = 15,
                MND = 1,
                HMP = 1,
            }
        },
        MorionTathlum = {
            Name = "Morion Tathlum",
            Level = 25,
            Id = 18136,
            Jobs = {"All"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                MP = 3,
                INT = 1,
            }
        },
        OneirosCluster = {
            Name = "Oneiros Cluster",
            Level = 75,
            Id = 19763,
            Jobs = {"THF", "BST", "RNG", "DNC", "RUN"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                Attack = -3,
                Haste = 1,
            }
        },
        OneirosPebble = {
            Name = "Oneiros Pebble",
            Level = 75,
            Id = 19767,
            Jobs = {"WAR", "RDM", "PLD", "BST", "SAM", "DRG", "BLU", "RUN"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                VIT = 3,
                Accuracy = 3,
            }
        },
        OneirosTathlum = {
            Name = "Oneiros Tathlum",
            Level = 75,
            Id = 19762,
            Jobs = {"WAR", "DRK", "BST", "RNG", "RUN"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
            }
        },
        PhtmTathlum = {
            Name = "Phtm. Tathlum",
            Level = 66,
            Id = 18140,
            Jobs = {"All"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                MP = 10,
                INT = 2,
            }
        },
        PotestasBomblet = {
            Name = "Potestas Bomblet",
            Level = 70,
            Id = 19779,
            Jobs = {"MNK", "THF", "SAM", "DRG", "PUP", "DNC", "RUN"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                Attack = 5,
            }
        },
        QuellingBolt = {
            Name = "Quelling Bolt",
            Level = 75,
            Id = 21311,
            Jobs = {"RNG"},
            Type = "Ammo",
            Stats = {
                DMG = 64,
                Delay = 192,
                RangedAccuracy = 10,
                RangedAttack = 10,
                MagicAccuracy = 10,
                MagicAttackBonus = 10,
            }
        },
        SavageShiv = {
            Name = "Savage Shiv",
            Level = 60,
            Id = 20891,
            Jobs = {"WAR", "DRK", "SAM", "RUN"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                STR = 2,
                Accuracy = -3,
                Haste = 1,
            }
        },
        ShrimpLure = {
            Name = "Shrimp Lure",
            Level = 1,
            Id = 17402,
            Jobs = {"All"},
            Type = "Ammo",
            Stats = {
                Delay = 240,
            }
        },
        SteelBullet = {
            Name = "Steel Bullet",
            Level = 66,
            Id = 18723,
            Jobs = {"RNG", "COR"},
            Type = "Ammo",
            Stats = {
                DMG = 70,
                Delay = 240,
            }
        },
        TalonTathlum = {
            Name = "Talon Tathlum",
            Level = 50,
            Id = 19270,
            Jobs = {"WHM", "BLM", "SMN", "BLU", "SCH", "GEO"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                MP = 15,
                STR = 2,
                DEX = 2,
            }
        },
        TinBullet = {
            Name = "Tin Bullet",
            Level = 11,
            Id = 19229,
            Jobs = {"THF", "RNG", "NIN", "COR"},
            Type = "Ammo",
            Stats = {
                DMG = 32,
                Delay = 240,
            }
        },
        VerthandisGem = {
            Name = "Verthandis Gem",
            Level = 75,
            Id = 19244,
            Jobs = {"All"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                HP = 30,
                CHR = 1,
            }
        },
        Yetshila = {
            Name = "Yetshila",
            Level = 75,
            Id = 21378,
            Jobs = {"RDM", "THF", "NIN", "RUN"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                DEX = 1,
                CriticalHitRate = 1,
            }
        },
        Yetshila_1 = {
            Name = "Yetshila +1",
            Level = 75,
            Id = 21379,
            Jobs = {"RDM", "THF", "NIN", "RUN"},
            Type = "Ammo",
            Stats = {
                Delay = 999,
                DEX = 2,
                CriticalHitRate = 2,
            }
        },
        YoruShuriken = {
            Name = "Yoru Shuriken",
            Level = 75,
            Id = 22999,
            Jobs = {"NIN"},
            Type = "Ammo",
            Stats = {
                DMG = 85,
                Delay = 192,
                Accuracy = 8,
                RangedAccuracy = 8,
                MagicAccuracy = 8,
            }
        },
    },
    Head = {
        AbsBurgeonet_1 = {
            Name = "Abs. Burgeonet +1",
            Level = 75,
            Id = 15252,
            Jobs = {"DRK"},
            Type = "Head",
            Stats = {
                DEF = 28,
                HP = 30,
                VIT = 8,
                Attack = 12,
            }
        },
        AbtalTurban = {
            Name = "Abtal Turban",
            Level = 59,
            Id = 16067,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM"},
            Type = "Head",
            Stats = {
                DEF = 20,
                HP = 10,
                STR = 4,
                AGI = 4,
            }
        },
        AcesHelm = {
            Name = "Aces Helm",
            Level = 74,
            Id = 15223,
            Jobs = {"DRK", "SAM", "DRG"},
            Type = "Head",
            Stats = {
                DEF = 28,
                STR = 4,
                Accuracy = 7,
                Evasion = -7,
                Haste = 4,
            }
        },
        AcroHelm = {
            Name = "Acro Helm",
            Level = 75,
            Id = 26734,
            Jobs = {"WAR", "PLD", "DRK", "SAM", "DRG", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 33,
                HP = 10,
                MP = 10,
                STR = 5,
                MagicDefenseBonus = 2,
                StoreTP = 4,
            }
        },
        AcubensHelm = {
            Name = "Acubens Helm",
            Level = 75,
            Id = 11502,
            Jobs = {"MNK", "THF", "BST", "RNG", "NIN", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 28,
                Accuracy = -10,
                Haste = 6,
            }
        },
        AdamanCelata = {
            Name = "Adaman Celata",
            Level = 73,
            Id = 12429,
            Jobs = {"WAR", "DRK", "BST"},
            Type = "Head",
            Stats = {
                DEF = 30,
                HP = -20,
                Accuracy = 5,
                Attack = 8,
                Evasion = -8,
            }
        },
        AdhemarBonnet = {
            Name = "Adhemar Bonnet",
            Level = 75,
            Id = 25613,
            Jobs = {"THF"},
            Type = "Head",
            Stats = {
                DEF = 27,
                HP = 20,
                DEX = 6,
                AGI = 6,
                RangedAccuracy = 9,
                RangedAttack = 9,
                CriticalHitRate = 3,
            }
        },
        AgwusCap = {
            Name = "Agwus Cap",
            Level = 75,
            Id = 23759,
            Jobs = {"BLU"},
            Type = "Head",
            Stats = {
                DEF = 26,
                MP = 20,
                INT = 6,
                MND = 6,
                MagicAttackBonus = 6,
            }
        },
        AkinjiKhud = {
            Name = "Akinji Khud",
            Level = 55,
            Id = 16068,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 22,
                HP = -5,
                Attack = 3,
                RangedAttack = 2,
            }
        },
        AmalricCoif = {
            Name = "Amalric Coif",
            Level = 75,
            Id = 25615,
            Jobs = {"GEO"},
            Type = "Head",
            Stats = {
                DEF = 19,
                MP = 25,
                VIT = 7,
                MND = 7,
                Refresh = 1,
            }
        },
        AresMask = {
            Name = "Ares Mask",
            Level = 75,
            Id = 16084,
            Jobs = {"WAR", "PLD", "DRK", "DRG", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 28,
                HPP = 2,
                MPP = 2,
                Accuracy = 12,
                Attack = 12,
                Evasion = -12,
            }
        },
        ArguteMBoard_1 = {
            Name = "Argute M.Board +1",
            Level = 75,
            Id = 11481,
            Jobs = {"SCH"},
            Type = "Head",
            Stats = {
                DEF = 17,
                HP = 12,
                MP = 12,
                MND = 6,
            }
        },
        ArmadaCelata = {
            Name = "Armada Celata",
            Level = 73,
            Id = 13924,
            Jobs = {"WAR", "DRK", "BST"},
            Type = "Head",
            Stats = {
                DEF = 31,
                HP = -21,
                Accuracy = 6,
                Attack = 9,
                Evasion = -9,
            }
        },
        AsnBonnet_1 = {
            Name = "Asn. Bonnet +1",
            Level = 75,
            Id = 15250,
            Jobs = {"THF"},
            Type = "Head",
            Stats = {
                DEF = 25,
                HP = 16,
                DEX = 6,
                Enmity = 3,
            }
        },
        BaguaGalero = {
            Name = "Bagua Galero",
            Level = 75,
            Id = 26664,
            Jobs = {"GEO"},
            Type = "Head",
            Stats = {
                DEF = 25,
                MP = 25,
                INT = 3,
                MND = 3,
            }
        },
        BaguaGalero_1 = {
            Name = "Bagua Galero +1",
            Level = 75,
            Id = 26665,
            Jobs = {"GEO"},
            Type = "Head",
            Stats = {
                DEF = 26,
                MP = 30,
                INT = 5,
                MND = 5,
            }
        },
        BahamutsMask = {
            Name = "Bahamuts Mask",
            Level = 75,
            Id = 15264,
            Jobs = {"PLD", "DRK", "SAM", "DRG", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 32,
                Accuracy = 4,
                Haste = 4,
                Enmity = 8,
            }
        },
        BeastHelm = {
            Name = "Beast Helm",
            Level = 56,
            Id = 12517,
            Jobs = {"BST"},
            Type = "Head",
            Stats = {
                DEF = 22,
                HP = 15,
                INT = 5,
            }
        },
        BeetleMask = {
            Name = "Beetle Mask",
            Level = 21,
            Id = 12455,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 9,
            }
        },
        BeetleMask_1 = {
            Name = "Beetle Mask +1",
            Level = 21,
            Id = 13827,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 10,
                Evasion = 1,
            }
        },
        BlackSallet = {
            Name = "Black Sallet",
            Level = 71,
            Id = 13887,
            Jobs = {"DRK"},
            Type = "Head",
            Stats = {
                DEF = 22,
                Accuracy = 5,
                Attack = 9,
            }
        },
        BloodMask = {
            Name = "Blood Mask",
            Level = 73,
            Id = 13909,
            Jobs = {"RDM", "PLD", "DRK", "RNG", "DRG", "BLU", "COR", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 35,
                HP = 22,
                MP = 22,
                Regen = 1,
            }
        },
        BoneMask = {
            Name = "Bone Mask",
            Level = 16,
            Id = 12454,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 7,
            }
        },
        BrdRoundlet_1 = {
            Name = "Brd. Roundlet +1",
            Level = 75,
            Id = 15254,
            Jobs = {"BRD"},
            Type = "Head",
            Stats = {
                DEF = 20,
                HP = 13,
                CHR = 6,
                Enmity = -4,
            }
        },
        BstHelm_1 = {
            Name = "Bst. Helm +1",
            Level = 74,
            Id = 15233,
            Jobs = {"BST"},
            Type = "Head",
            Stats = {
                DEF = 26,
                HP = 15,
                INT = 8,
                MND = 8,
            }
        },
        BunzisHat = {
            Name = "Bunzis Hat",
            Level = 75,
            Id = 23760,
            Jobs = {"WHM"},
            Type = "Head",
            Stats = {
                DEF = 27,
                MP = 25,
                MND = 10,
                Refresh = 1,
            }
        },
        ChironicHat = {
            Name = "Chironic Hat",
            Level = 75,
            Id = 25644,
            Jobs = {"SMN"},
            Type = "Head",
            Stats = {
                DEF = 21,
                MP = 20,
                Enmity = -5,
            }
        },
        ChlRoundlet_1 = {
            Name = "Chl. Roundlet +1",
            Level = 74,
            Id = 15234,
            Jobs = {"BRD"},
            Type = "Head",
            Stats = {
                DEF = 19,
                HP = 11,
                MND = 6,
                CHR = 6,
                Enmity = -2,
            }
        },
        ChoralRoundlet = {
            Name = "Choral Roundlet",
            Level = 54,
            Id = 13857,
            Jobs = {"BRD"},
            Type = "Head",
            Stats = {
                DEF = 15,
                HP = 11,
                MND = 3,
                Enmity = -1,
            }
        },
        ChsBurgeonet_1 = {
            Name = "Chs. Burgeonet +1",
            Level = 74,
            Id = 15232,
            Jobs = {"DRK"},
            Type = "Head",
            Stats = {
                DEF = 27,
                HP = 12,
                MP = 12,
                STR = 7,
            }
        },
        CircesHat = {
            Name = "Circes Hat",
            Level = 30,
            Id = 11494,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 8,
                MP = 6,
                MND = 2,
            }
        },
        ClrCap_1 = {
            Name = "Clr. Cap +1",
            Level = 75,
            Id = 15247,
            Jobs = {"WHM"},
            Type = "Head",
            Stats = {
                DEF = 25,
                MP = 25,
                VIT = 5,
                Enmity = -5,
            }
        },
        CocoonBand = {
            Name = "Cocoon Band",
            Level = 71,
            Id = 11823,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                DEF = 65,
                Haste = -5,
            }
        },
        CommTricorne_1 = {
            Name = "Comm. Tricorne +1",
            Level = 75,
            Id = 11469,
            Jobs = {"COR"},
            Type = "Head",
            Stats = {
                DEF = 25,
                HP = 12,
                RangedAttack = 10,
            }
        },
        ConquerorsHelm = {
            Name = "Conquerors Helm",
            Level = 70,
            Id = 27779,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "DRG"},
            Type = "Head",
            Stats = {
                DEF = 36,
                HP = 25,
                STR = 8,
                Haste = 4,
                DoubleAttack = 2,
            }
        },
        CorTricorne_1 = {
            Name = "Cor. Tricorne +1",
            Level = 74,
            Id = 11467,
            Jobs = {"COR"},
            Type = "Head",
            Stats = {
                DEF = 23,
                HP = 13,
                STR = 4,
                AGI = 4,
                RangedAccuracy = 9,
            }
        },
        CrimsonMask = {
            Name = "Crimson Mask",
            Level = 73,
            Id = 13908,
            Jobs = {"RDM", "PLD", "DRK", "RNG", "DRG", "BLU", "COR", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 34,
                HP = 20,
                MP = 20,
                Regen = 1,
            }
        },
        DampeningTam = {
            Name = "Dampening Tam",
            Level = 75,
            Id = 25630,
            Jobs = {"MNK", "THF", "RNG", "NIN", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 22,
                HP = 15,
                STR = 2,
                DEX = 4,
                Accuracy = 5,
                Haste = 5,
            }
        },
        DancersTiara_1 = {
            Name = "Dancers Tiara +1",
            Level = 74,
            Id = 11475,
            Jobs = {"DNC"},
            Type = "Head",
            Stats = {
                DEF = 19,
                HP = 15,
                DEX = 4,
                CHR = 4,
                Enmity = -2,
            }
        },
        DemonHelm = {
            Name = "Demon Helm",
            Level = 73,
            Id = 13922,
            Jobs = {"BLM", "DRK", "BRD"},
            Type = "Head",
            Stats = {
                DEF = 25,
                INT = 5,
                MND = -5,
            }
        },
        DianaCorona = {
            Name = "Diana Corona",
            Level = 64,
            Id = 11486,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 20,
                MagicAccuracy = 4,
            }
        },
        DinoHelm = {
            Name = "Dino Helm",
            Level = 48,
            Id = 13835,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 19,
            }
        },
        DlsChapeau_1 = {
            Name = "Dls. Chapeau +1",
            Level = 75,
            Id = 15249,
            Jobs = {"RDM"},
            Type = "Head",
            Stats = {
                DEF = 25,
                HP = 14,
                MP = 14,
                MND = 3,
                Refresh = 1,
            }
        },
        DobsonBandana = {
            Name = "Dobson Bandana",
            Level = 39,
            Id = 15183,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                AGI = 3,
                Evasion = 5,
            }
        },
        DragonCap = {
            Name = "Dragon Cap",
            Level = 73,
            Id = 13936,
            Jobs = {"THF"},
            Type = "Head",
            Stats = {
                DEF = 24,
                AGI = 4,
                Enmity = 1,
                SubtleBlow = 3,
            }
        },
        DragonCap_1 = {
            Name = "Dragon Cap +1",
            Level = 73,
            Id = 13937,
            Jobs = {"THF"},
            Type = "Head",
            Stats = {
                DEF = 25,
                AGI = 5,
                Enmity = 2,
                SubtleBlow = 4,
            }
        },
        DragonMask = {
            Name = "Dragon Mask",
            Level = 68,
            Id = 12436,
            Jobs = {"DRG"},
            Type = "Head",
            Stats = {
                DEF = 23,
                HP = 10,
            }
        },
        DragonMask_1 = {
            Name = "Dragon Mask +1",
            Level = 68,
            Id = 13860,
            Jobs = {"DRG"},
            Type = "Head",
            Stats = {
                DEF = 24,
                HP = 12,
            }
        },
        DrnArmet_1 = {
            Name = "Drn. Armet +1",
            Level = 74,
            Id = 15238,
            Jobs = {"DRG"},
            Type = "Head",
            Stats = {
                DEF = 25,
                HP = 12,
                VIT = 8,
                MND = 8,
            }
        },
        DuelistsChapeau = {
            Name = "Duelists Chapeau",
            Level = 75,
            Id = 15076,
            Jobs = {"RDM"},
            Type = "Head",
            Stats = {
                DEF = 24,
                MP = 14,
                Refresh = 1,
            }
        },
        DuxVisor = {
            Name = "Dux Visor",
            Level = 70,
            Id = 10434,
            Jobs = {"RUN"},
            Type = "Head",
            Stats = {
                DEF = 27,
                VIT = 5,
                Accuracy = 8,
                Enmity = 3,
            }
        },
        DuxVisor_1 = {
            Name = "Dux Visor +1",
            Level = 70,
            Id = 10435,
            Jobs = {"RUN"},
            Type = "Head",
            Stats = {
                DEF = 28,
                VIT = 6,
                Accuracy = 9,
                Enmity = 4,
            }
        },
        Eisenschaller = {
            Name = "Eisenschaller",
            Level = 29,
            Id = 15167,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Head",
            Stats = {
                DEF = 13,
                AGI = 1,
            }
        },
        EmperorHairpin = {
            Name = "Emperor Hairpin",
            Level = 24,
            Id = 12486,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                HP = -15,
                DEX = 3,
                AGI = 3,
                Evasion = 10,
            }
        },
        EntrancingRibbon = {
            Name = "Entrancing Ribbon",
            Level = 11,
            Id = 15218,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 5,
                CHR = 2,
            }
        },
        EruditeCap = {
            Name = "Erudite Cap",
            Level = 70,
            Id = 27767,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 25,
                MP = 30,
                VIT = 3,
                INT = 5,
                MagicAccuracy = 5,
            }
        },
        EtoileTiara_1 = {
            Name = "Etoile Tiara +1",
            Level = 75,
            Id = 11479,
            Jobs = {"DNC"},
            Type = "Head",
            Stats = {
                DEF = 19,
                HP = 20,
                STR = 5,
                Attack = 7,
            }
        },
        EvkHorn_1 = {
            Name = "Evk. Horn +1",
            Level = 74,
            Id = 15239,
            Jobs = {"SMN"},
            Type = "Head",
            Stats = {
                DEF = 15,
                MP = 25,
                INT = 6,
                MND = 6,
            }
        },
        Faceguard = {
            Name = "Faceguard",
            Level = 10,
            Id = 12432,
            Jobs = {"WAR", "RDM", "PLD", "DRK", "BST", "RNG", "SAM", "DRG", "BLU", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 5,
            }
        },
        Faceguard_1 = {
            Name = "Faceguard +1",
            Level = 10,
            Id = 12487,
            Jobs = {"WAR", "RDM", "PLD", "DRK", "BST", "RNG", "SAM", "DRG", "BLU", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 6,
            }
        },
        FoundersCorona = {
            Name = "Founders Corona",
            Level = 75,
            Id = 27764,
            Jobs = {"PLD"},
            Type = "Head",
            Stats = {
                DEF = 31,
                HP = 25,
                MP = 20,
                Haste = 5,
                StoreTP = 5,
                Enmity = 5,
            }
        },
        FtrMask_1 = {
            Name = "Ftr. Mask +1",
            Level = 74,
            Id = 15225,
            Jobs = {"WAR"},
            Type = "Head",
            Stats = {
                DEF = 28,
                HP = 15,
                DEX = 5,
                VIT = 5,
                Enmity = 1,
                HHP = 1,
            }
        },
        FuBandeau_1 = {
            Name = "Fu. Bandeau +1",
            Level = 75,
            Id = 26667,
            Jobs = {"RUN"},
            Type = "Head",
            Stats = {
                DEF = 29,
                HP = 18,
                MP = 18,
                STR = 7,
                Haste = 4,
            }
        },
        FungusHat = {
            Name = "Fungus Hat",
            Level = 14,
            Id = 12485,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 6,
            }
        },
        FutharkBandeau = {
            Name = "Futhark Bandeau",
            Level = 75,
            Id = 26666,
            Jobs = {"RUN"},
            Type = "Head",
            Stats = {
                DEF = 28,
                HP = 11,
                MP = 11,
                STR = 6,
                Haste = 3,
            }
        },
        GamblersChapeau = {
            Name = "Gamblers Chapeau",
            Level = 20,
            Id = 27780,
            Jobs = {"WHM", "BLM", "RDM", "DRK", "BRD", "SMN", "BLU", "COR", "SCH", "GEO", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 9,
                MP = 20,
                INT = 3,
            }
        },
        GarishCrown = {
            Name = "Garish Crown",
            Level = 30,
            Id = 15164,
            Jobs = {"MNK", "RDM", "PLD", "BRD", "RNG", "BLU", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 11,
            }
        },
        GarrisonSallet = {
            Name = "Garrison Sallet",
            Level = 19,
            Id = 15147,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                DEF = 5,
                MND = 1,
                CHR = 1,
            }
        },
        GarrisonSallet_1 = {
            Name = "Garrison Sallet +1",
            Level = 20,
            Id = 25567,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                DEF = 8,
                HP = 6,
                MND = 2,
                CHR = 2,
            }
        },
        GenbusKabuto = {
            Name = "Genbus Kabuto",
            Level = 75,
            Id = 12434,
            Jobs = {"WAR", "MNK", "BST", "BRD", "RNG", "SAM", "NIN"},
            Type = "Head",
            Stats = {
                DEF = 35,
                HP = 50,
                VIT = 15,
            }
        },
        GenieTiara = {
            Name = "Genie Tiara",
            Level = 73,
            Id = 15160,
            Jobs = {"BLM"},
            Type = "Head",
            Stats = {
                DEF = 21,
                Evasion = 11,
            }
        },
        GenmeiKabuto = {
            Name = "Genmei Kabuto",
            Level = 75,
            Id = 25629,
            Jobs = {"WAR", "MNK", "BST", "BRD", "RNG", "SAM", "NIN"},
            Type = "Head",
            Stats = {
                DEF = 38,
                HP = 75,
                VIT = 18,
                Attack = 5,
                Haste = 4,
            }
        },
        GeomancyGalero = {
            Name = "Geomancy Galero",
            Level = 75,
            Id = 27786,
            Jobs = {"GEO"},
            Type = "Head",
            Stats = {
                DEF = 22,
                MP = 25,
                INT = 5,
            }
        },
        GletisMask = {
            Name = "Gletis Mask",
            Level = 75,
            Id = 23756,
            Jobs = {"DRK"},
            Type = "Head",
            Stats = {
                DEF = 30,
                HP = 30,
                STR = 5,
                INT = 5,
                Haste = 5,
                Enmity = 5,
            }
        },
        GltCoronet_1 = {
            Name = "Glt. Coronet +1",
            Level = 74,
            Id = 15231,
            Jobs = {"PLD"},
            Type = "Head",
            Stats = {
                DEF = 28,
                HP = 12,
                MND = 6,
                Enmity = 3,
            }
        },
        HachimanJinpachi = {
            Name = "Hachiman Jinpachi",
            Level = 70,
            Id = 15188,
            Jobs = {"SAM"},
            Type = "Head",
            Stats = {
                DEF = 26,
                STR = 3,
            }
        },
        HecatombCap = {
            Name = "Hecatomb Cap",
            Level = 73,
            Id = 13927,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 33,
                HP = 12,
                STR = 11,
                DEX = 5,
                Haste = -9,
            }
        },
        HecatombCap_1 = {
            Name = "Hecatomb Cap +1",
            Level = 73,
            Id = 13928,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 34,
                HP = 14,
                STR = 12,
                DEX = 6,
                Haste = -11,
            }
        },
        HeliosBand = {
            Name = "Helios Band",
            Level = 75,
            Id = 26737,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 26,
                MP = 15,
                INT = 4,
                MND = 4,
                CHR = 4,
                MagicAccuracy = 3,
            }
        },
        HerculeanHelm = {
            Name = "Herculean Helm",
            Level = 75,
            Id = 25642,
            Jobs = {"RNG"},
            Type = "Head",
            Stats = {
                DEF = 27,
                HP = 25,
                STR = 5,
                DEX = 5,
                Haste = 5,
                DoubleAttack = 3,
            }
        },
        HeroicHairpin = {
            Name = "Heroic Hairpin",
            Level = 30,
            Id = 10893,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                HP = 15,
                Haste = 2,
                DualWield = 3,
            }
        },
        HlrCap_1 = {
            Name = "Hlr. Cap +1",
            Level = 74,
            Id = 15227,
            Jobs = {"WHM"},
            Type = "Head",
            Stats = {
                DEF = 21,
                MP = 28,
                MND = 7,
                Enmity = -1,
                HMP = 1,
            }
        },
        HmnJinpachi_1 = {
            Name = "Hmn. Jinpachi +1",
            Level = 70,
            Id = 15187,
            Jobs = {"SAM"},
            Type = "Head",
            Stats = {
                DEF = 27,
                STR = 4,
            }
        },
        HomamZucchetto = {
            Name = "Homam Zucchetto",
            Level = 75,
            Id = 15240,
            Jobs = {"THF", "PLD", "DRK", "DRG", "BLU", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 26,
                HP = 22,
                MP = 22,
                Accuracy = 4,
                MagicAccuracy = 4,
                Haste = 3,
            }
        },
        HtrBeret_1 = {
            Name = "Htr. Beret +1",
            Level = 74,
            Id = 15235,
            Jobs = {"RNG"},
            Type = "Head",
            Stats = {
                DEF = 24,
                HP = 13,
                AGI = 4,
                INT = 4,
                RangedAttack = 5,
            }
        },
        IgqiraTiara = {
            Name = "Igqira Tiara",
            Level = 73,
            Id = 15159,
            Jobs = {"BLM"},
            Type = "Head",
            Stats = {
                DEF = 20,
                Evasion = 10,
            }
        },
        IkengasHat = {
            Name = "Ikengas Hat",
            Level = 75,
            Id = 23755,
            Jobs = {"COR"},
            Type = "Head",
            Stats = {
                DEF = 27,
                HP = 20,
                DEX = 5,
                AGI = 5,
                MagicAttackBonus = 5,
                StoreTP = 5,
            }
        },
        IronRamSallet = {
            Name = "Iron Ram Sallet",
            Level = 68,
            Id = 16146,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Head",
            Stats = {
                DEF = 29,
                HP = 20,
                MagicDefenseBonus = 3,
                Enmity = 5,
            }
        },
        JaridahKhud = {
            Name = "Jaridah Khud",
            Level = 55,
            Id = 16063,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 21,
                HP = -5,
                Attack = 2,
                RangedAttack = 1,
            }
        },
        JumalikHelm = {
            Name = "Jumalik Helm",
            Level = 75,
            Id = 25603,
            Jobs = {"WAR", "PLD", "DRK", "BST", "DRG", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 35,
                HP = 25,
                MP = 15,
                VIT = 8,
                MagicAttackBonus = 9,
                Haste = 5,
            }
        },
        KaiserSchaller = {
            Name = "Kaiser Schaller",
            Level = 73,
            Id = 13911,
            Jobs = {"WAR", "PLD"},
            Type = "Head",
            Stats = {
                DEF = 41,
                HP = 32,
                STR = -6,
                DEX = -6,
                VIT = 11,
                CHR = 11,
            }
        },
        Kampfschaller = {
            Name = "Kampfschaller",
            Level = 29,
            Id = 15171,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Head",
            Stats = {
                DEF = 14,
                AGI = 2,
            }
        },
        KhimairaBonnet = {
            Name = "Khimaira Bonnet",
            Level = 71,
            Id = 16104,
            Jobs = {"BST"},
            Type = "Head",
            Stats = {
                DEF = 26,
                HP = 8,
                MP = 8,
                Enmity = -3,
            }
        },
        KhthoniosHelm = {
            Name = "Khthonios Helm",
            Level = 75,
            Id = 11821,
            Jobs = {"WAR", "BLM", "THF", "DRK", "BST", "RNG", "NIN", "DRG", "PUP", "DNC", "SCH"},
            Type = "Head",
            Stats = {
                DEF = 29,
                HP = 14,
                STR = 7,
                INT = 7,
            }
        },
        KhthoniosMask = {
            Name = "Khthonios Mask",
            Level = 75,
            Id = 11820,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 23,
                Attack = 14,
                MagicDefenseBonus = 4,
                Haste = 4,
                StoreTP = 4,
            }
        },
        KingsArmet = {
            Name = "Kings Armet",
            Level = 70,
            Id = 15193,
            Jobs = {"PLD"},
            Type = "Head",
            Stats = {
                DEF = 27,
                HP = 15,
                VIT = 3,
                Enmity = 3,
            }
        },
        KoenigSchaller = {
            Name = "Koenig Schaller",
            Level = 73,
            Id = 12421,
            Jobs = {"WAR", "PLD"},
            Type = "Head",
            Stats = {
                DEF = 40,
                HP = 30,
                STR = -5,
                DEX = -5,
                VIT = 10,
                CHR = 10,
            }
        },
        KogHatsuburi_1 = {
            Name = "Kog. Hatsuburi +1",
            Level = 75,
            Id = 15257,
            Jobs = {"NIN"},
            Type = "Head",
            Stats = {
                DEF = 23,
                HP = 27,
            }
        },
        LeatherBandana = {
            Name = "Leather Bandana",
            Level = 7,
            Id = 12440,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 3,
            }
        },
        LeonineMask = {
            Name = "Leonine Mask",
            Level = 75,
            Id = 16151,
            Jobs = {"WAR", "MNK", "THF", "BST", "NIN", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 28,
                STR = 3,
                AGI = 3,
                CriticalHitRate = 3,
            }
        },
        LordsArmet = {
            Name = "Lords Armet",
            Level = 70,
            Id = 15189,
            Jobs = {"PLD"},
            Type = "Head",
            Stats = {
                DEF = 26,
                VIT = 2,
                Enmity = 2,
            }
        },
        LthBandana_1 = {
            Name = "Lth. Bandana +1",
            Level = 7,
            Id = 12542,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 4,
            }
        },
        MagusKeffiyeh_1 = {
            Name = "Magus Keffiyeh +1",
            Level = 74,
            Id = 11464,
            Jobs = {"BLU"},
            Type = "Head",
            Stats = {
                DEF = 24,
                MP = 25,
                INT = 5,
                MND = 5,
            }
        },
        MalignanceChapeau = {
            Name = "Malignance Chapeau",
            Level = 75,
            Id = 23732,
            Jobs = {"RDM"},
            Type = "Head",
            Stats = {
                DEF = 27,
                MP = 25,
                INT = 6,
                MND = 6,
                ConserveMP = 5,
            }
        },
        MarduksTiara = {
            Name = "Marduks Tiara",
            Level = 75,
            Id = 16096,
            Jobs = {"WHM", "BRD", "SMN", "SCH"},
            Type = "Head",
            Stats = {
                DEF = 17,
                MPP = 4,
                MND = 3,
                CHR = 3,
                Enmity = -3,
            }
        },
        MelCrown_1 = {
            Name = "Mel. Crown +1",
            Level = 75,
            Id = 15246,
            Jobs = {"MNK"},
            Type = "Head",
            Stats = {
                DEF = 24,
                HPP = 5,
                STR = 6,
                Enmity = -4,
                SubtleBlow = 6,
            }
        },
        MerlinicHood = {
            Name = "Merlinic Hood",
            Level = 75,
            Id = 25643,
            Jobs = {"SCH"},
            Type = "Head",
            Stats = {
                DEF = 19,
                MP = 25,
                MagicAccuracy = 5,
                CurePotency = 10,
            }
        },
        MidrassHelm_1 = {
            Name = "Midrass Helm +1",
            Level = 1,
            Id = 25637,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
            }
        },
        MinersHelmet = {
            Name = "Miners Helmet",
            Level = 1,
            Id = 25560,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                DEF = 1,
            }
        },
        MirageKeffiyeh_1 = {
            Name = "Mirage Keffiyeh +1",
            Level = 75,
            Id = 11466,
            Jobs = {"BLU"},
            Type = "Head",
            Stats = {
                DEF = 25,
                HP = 15,
                VIT = 4,
            }
        },
        MonsterHelm = {
            Name = "Monster Helm",
            Level = 71,
            Id = 15080,
            Jobs = {"BST"},
            Type = "Head",
            Stats = {
                DEF = 26,
                HP = 19,
                CHR = 4,
            }
        },
        MorrigansCoron = {
            Name = "Morrigans Coron.",
            Level = 75,
            Id = 16100,
            Jobs = {"BLM", "RDM", "BLU", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 15,
                MP = 20,
                STR = 4,
                INT = 4,
                MND = 4,
                Accuracy = 5,
                MagicAccuracy = 5,
            }
        },
        MpacasCap = {
            Name = "Mpacas Cap",
            Level = 75,
            Id = 23758,
            Jobs = {"NIN"},
            Type = "Head",
            Stats = {
                DEF = 25,
                HP = 25,
                DEX = 6,
                AGI = 6,
                MagicEvasion = 10,
                Haste = 5,
            }
        },
        MstHelm_1 = {
            Name = "Mst. Helm +1",
            Level = 75,
            Id = 15253,
            Jobs = {"BST"},
            Type = "Head",
            Stats = {
                DEF = 27,
                HP = 19,
                MP = 19,
                CHR = 5,
            }
        },
        MynKabuto_1 = {
            Name = "Myn. Kabuto +1",
            Level = 74,
            Id = 15236,
            Jobs = {"SAM"},
            Type = "Head",
            Stats = {
                DEF = 25,
                HP = 13,
                STR = 5,
                MND = 5,
            }
        },
        MyochinKabuto = {
            Name = "Myochin Kabuto",
            Level = 60,
            Id = 13868,
            Jobs = {"SAM"},
            Type = "Head",
            Stats = {
                DEF = 20,
                HP = 10,
                MND = 5,
            }
        },
        MythrilSallet = {
            Name = "Mythril Sallet",
            Level = 49,
            Id = 12417,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Head",
            Stats = {
                DEF = 20,
            }
        },
        MythrilSallet_1 = {
            Name = "Mythril Sallet +1",
            Level = 49,
            Id = 13847,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Head",
            Stats = {
                DEF = 21,
                INT = 2,
            }
        },
        NagaSomen = {
            Name = "Naga Somen",
            Level = 75,
            Id = 26793,
            Jobs = {"MNK"},
            Type = "Head",
            Stats = {
                DEF = 26,
                HPP = 5,
                DEX = 5,
                AGI = 5,
                Haste = 5,
                Enmity = 5,
            }
        },
        NashiraTurban = {
            Name = "Nashira Turban",
            Level = 75,
            Id = 15241,
            Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 19,
                MagicAccuracy = 5,
                Haste = 2,
                Enmity = -5,
            }
        },
        NinHatsuburi_1 = {
            Name = "Nin. Hatsuburi +1",
            Level = 74,
            Id = 15237,
            Jobs = {"NIN"},
            Type = "Head",
            Stats = {
                DEF = 22,
                HP = 10,
                AGI = 8,
                CHR = 8,
                Evasion = 8,
            }
        },
        NoblesRibbon = {
            Name = "Nobles Ribbon",
            Level = 14,
            Id = 13833,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                CHR = 3,
            }
        },
        NoctBeret = {
            Name = "Noct Beret",
            Level = 30,
            Id = 15161,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Head",
            Stats = {
                DEF = 9,
                AGI = 1,
            }
        },
        NoctBeret_1 = {
            Name = "Noct Beret +1",
            Level = 30,
            Id = 15172,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Head",
            Stats = {
                DEF = 10,
                AGI = 2,
            }
        },
        OdysseanHelm = {
            Name = "Odyssean Helm",
            Level = 75,
            Id = 25640,
            Jobs = {"DRG"},
            Type = "Head",
            Stats = {
                DEF = 25,
                HP = 15,
                MP = 20,
                STR = 6,
                DEX = 6,
                Attack = 5,
                DoubleAttack = 3,
            }
        },
        OneirosBarbut = {
            Name = "Oneiros Barbut",
            Level = 75,
            Id = 11817,
            Jobs = {"WAR", "PLD"},
            Type = "Head",
            Stats = {
                DEF = 30,
                VIT = 9,
                Evasion = -14,
                MovementSpeed = -12,
            }
        },
        OneirosCoif = {
            Name = "Oneiros Coif",
            Level = 75,
            Id = 11819,
            Jobs = {"RNG", "SAM"},
            Type = "Head",
            Stats = {
                DEF = 23,
                STR = 4,
                RangedAttack = 10,
                Enmity = 3,
            }
        },
        OneirosHeadgear = {
            Name = "Oneiros Headgear",
            Level = 75,
            Id = 11818,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "PUP", "SCH", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 25,
                MP = 50,
                INT = 6,
                MagicAccuracy = 6,
                MagicAttackBonus = 6,
            }
        },
        OneirosHelm = {
            Name = "Oneiros Helm",
            Level = 75,
            Id = 11816,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 28,
                DEX = 9,
                DoubleAttack = -3,
                TripleAttack = -3,
            }
        },
        OnyxSallet = {
            Name = "Onyx Sallet",
            Level = 71,
            Id = 13888,
            Jobs = {"DRK"},
            Type = "Head",
            Stats = {
                DEF = 23,
                Accuracy = 6,
                Attack = 11,
            }
        },
        OpticalHat = {
            Name = "Optical Hat",
            Level = 70,
            Id = 13915,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                Accuracy = 10,
                RangedAccuracy = 10,
                Evasion = 10,
            }
        },
        PantinTaj_1 = {
            Name = "Pantin Taj +1",
            Level = 75,
            Id = 11472,
            Jobs = {"PUP"},
            Type = "Head",
            Stats = {
                DEF = 20,
                HP = 12,
                STR = 4,
                AGI = 4,
                Regen = 1,
            }
        },
        PoetsCirclet = {
            Name = "Poets Circlet",
            Level = 12,
            Id = 12473,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 5,
            }
        },
        PupTaj = {
            Name = "Pup. Taj",
            Level = 60,
            Id = 15267,
            Jobs = {"PUP"},
            Type = "Head",
            Stats = {
                DEF = 15,
                HP = 10,
                DEX = 3,
                MND = 3,
            }
        },
        PuppetryTaj_1 = {
            Name = "Puppetry Taj +1",
            Level = 74,
            Id = 11470,
            Jobs = {"PUP"},
            Type = "Head",
            Stats = {
                DEF = 16,
                HP = 15,
                DEX = 5,
                VIT = 5,
                MND = 5,
            }
        },
        PursuersBeret = {
            Name = "Pursuers Beret",
            Level = 75,
            Id = 26795,
            Jobs = {"BRD"},
            Type = "Head",
            Stats = {
                DEF = 22,
                MP = 25,
                CHR = 3,
                Haste = 5,
                Enmity = -5,
                DoubleAttack = 3,
            }
        },
        RaptorHelm = {
            Name = "Raptor Helm",
            Level = 48,
            Id = 12444,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 18,
            }
        },
        RawhideMask = {
            Name = "Rawhide Mask",
            Level = 75,
            Id = 26794,
            Jobs = {"DNC"},
            Type = "Head",
            Stats = {
                DEF = 21,
                HP = 25,
                DEX = 5,
                Accuracy = 10,
                Attack = 10,
                DoubleAttack = 3,
            }
        },
        RogBonnet_1 = {
            Name = "Rog. Bonnet +1",
            Level = 74,
            Id = 15230,
            Jobs = {"THF"},
            Type = "Head",
            Stats = {
                DEF = 24,
                HP = 13,
                DEX = 3,
                RangedAccuracy = 8,
                Evasion = 10,
            }
        },
        RoguesBonnet = {
            Name = "Rogues Bonnet",
            Level = 54,
            Id = 12514,
            Jobs = {"THF"},
            Type = "Head",
            Stats = {
                DEF = 23,
                HP = 13,
                INT = 5,
            }
        },
        RubiousCrown = {
            Name = "Rubious Crown",
            Level = 30,
            Id = 15168,
            Jobs = {"MNK", "RDM", "PLD", "BRD", "RNG", "BLU", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 12,
            }
        },
        RuneistBandeau = {
            Name = "Runeist Bandeau",
            Level = 75,
            Id = 27787,
            Jobs = {"RUN"},
            Type = "Head",
            Stats = {
                DEF = 27,
                HP = 21,
                DEX = 5,
                Regen = 3,
            }
        },
        RyuoSomen = {
            Name = "Ryuo Somen",
            Level = 75,
            Id = 25611,
            Jobs = {"SAM"},
            Type = "Head",
            Stats = {
                DEF = 28,
                HP = 25,
                DEX = 5,
                AGI = 5,
                Haste = 5,
            }
        },
        SakpatasHelm = {
            Name = "Sakpatas Helm",
            Level = 75,
            Id = 23757,
            Jobs = {"WAR"},
            Type = "Head",
            Stats = {
                DEF = 31,
                HP = 25,
                DEX = 5,
                VIT = 5,
                Haste = 5,
            }
        },
        SaoKabuto_1 = {
            Name = "Sao. Kabuto +1",
            Level = 75,
            Id = 15256,
            Jobs = {"SAM"},
            Type = "Head",
            Stats = {
                DEF = 26,
                HP = 20,
                Accuracy = 12,
                RangedAccuracy = 7,
                Enmity = 1,
            }
        },
        SchMBoard_1 = {
            Name = "Sch. M.Board +1",
            Level = 74,
            Id = 11477,
            Jobs = {"SCH"},
            Type = "Head",
            Stats = {
                DEF = 16,
                MP = 20,
                INT = 5,
                Enmity = -1,
            }
        },
        ScholarsMBoard = {
            Name = "Scholars M.Board",
            Level = 60,
            Id = 16140,
            Jobs = {"SCH"},
            Type = "Head",
            Stats = {
                DEF = 15,
                MP = 15,
                INT = 4,
            }
        },
        SctBeret_1 = {
            Name = "Sct. Beret +1",
            Level = 75,
            Id = 15255,
            Jobs = {"RNG"},
            Type = "Head",
            Stats = {
                DEF = 25,
                HP = 15,
                MND = 5,
                Enmity = -4,
            }
        },
        SeersCrown = {
            Name = "Seers Crown",
            Level = 29,
            Id = 15163,
            Jobs = {"WHM", "BLM", "SMN", "PUP", "SCH", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 4,
                INT = 2,
            }
        },
        SeersCrown_1 = {
            Name = "Seers Crown +1",
            Level = 29,
            Id = 15166,
            Jobs = {"WHM", "BLM", "SMN", "PUP", "SCH", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 5,
                INT = 3,
            }
        },
        ShadeTiara = {
            Name = "Shade Tiara",
            Level = 25,
            Id = 15165,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 10,
            }
        },
        ShadeTiara_1 = {
            Name = "Shade Tiara +1",
            Level = 25,
            Id = 15169,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 11,
                Evasion = 1,
            }
        },
        ShadowHat = {
            Name = "Shadow Hat",
            Level = 75,
            Id = 16115,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 18,
                MP = 35,
                MagicAccuracy = 5,
                Enmity = -3,
            }
        },
        ShadowHelm = {
            Name = "Shadow Helm",
            Level = 75,
            Id = 16113,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Head",
            Stats = {
                DEF = 35,
                HP = 15,
                MP = 15,
                DEX = 4,
                Accuracy = 2,
                Attack = 9,
            }
        },
        ShadowMask = {
            Name = "Shadow Mask",
            Level = 62,
            Id = 13912,
            Jobs = {"WAR", "RDM", "PLD", "DRK", "BST", "RNG", "SAM", "DRG", "BLU", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 20,
                MP = 10,
                STR = 2,
                VIT = -2,
            }
        },
        ShairTurban = {
            Name = "Shair Turban",
            Level = 72,
            Id = 15153,
            Jobs = {"BRD"},
            Type = "Head",
            Stats = {
                DEF = 17,
                MP = 9,
                CHR = 3,
                Haste = 1,
            }
        },
        SheikhTurban = {
            Name = "Sheikh Turban",
            Level = 72,
            Id = 15154,
            Jobs = {"BRD"},
            Type = "Head",
            Stats = {
                DEF = 18,
                MP = 10,
                CHR = 4,
                Haste = 2,
            }
        },
        ShinobiHachigane = {
            Name = "Shinobi Hachigane",
            Level = 49,
            Id = 12460,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Head",
            Stats = {
                DEF = 17,
            }
        },
        ShnHachigane_1 = {
            Name = "Shn. Hachigane +1",
            Level = 49,
            Id = 13844,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Head",
            Stats = {
                DEF = 18,
            }
        },
        ShrZnrKabuto = {
            Name = "Shr.Znr.Kabuto",
            Level = 73,
            Id = 13934,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Head",
            Stats = {
                DEF = 20,
                HP = -25,
                STR = 5,
                Accuracy = 5,
            }
        },
        ShrZnrKabuto_1 = {
            Name = "Shr.Znr.Kabuto +1",
            Level = 73,
            Id = 13935,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Head",
            Stats = {
                DEF = 21,
                HP = -30,
                STR = 6,
                Accuracy = 6,
            }
        },
        SipahiTurban = {
            Name = "Sipahi Turban",
            Level = 59,
            Id = 16061,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM"},
            Type = "Head",
            Stats = {
                DEF = 19,
                HP = 8,
                STR = 3,
                AGI = 3,
            }
        },
        SkadisVisor = {
            Name = "Skadis Visor",
            Level = 75,
            Id = 16088,
            Jobs = {"THF", "BST", "RNG", "COR", "DNC"},
            Type = "Head",
            Stats = {
                DEF = 15,
                DEX = 4,
                AGI = 4,
                Attack = 6,
                RangedAttack = 6,
                Haste = 3,
            }
        },
        SmnHorn_1 = {
            Name = "Smn. Horn +1",
            Level = 75,
            Id = 15259,
            Jobs = {"SMN"},
            Type = "Head",
            Stats = {
                DEF = 19,
                MP = 30,
                INT = 4,
            }
        },
        SoilHachimaki = {
            Name = "Soil Hachimaki",
            Level = 29,
            Id = 12458,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Head",
            Stats = {
                DEF = 10,
            }
        },
        SoilHachimaki_1 = {
            Name = "Soil Hachimaki +1",
            Level = 29,
            Id = 12539,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Head",
            Stats = {
                DEF = 11,
            }
        },
        SrcPetasos_1 = {
            Name = "Src. Petasos +1",
            Level = 75,
            Id = 15248,
            Jobs = {"BLM"},
            Type = "Head",
            Stats = {
                DEF = 24,
                MP = 29,
                Enmity = -3,
            }
        },
        StoutBonnet = {
            Name = "Stout Bonnet",
            Level = 71,
            Id = 16105,
            Jobs = {"BST"},
            Type = "Head",
            Stats = {
                DEF = 27,
                HP = 9,
                MP = 9,
                Enmity = -5,
            }
        },
        TaeonChapeau = {
            Name = "Taeon Chapeau",
            Level = 75,
            Id = 26735,
            Jobs = {"MNK", "THF", "BST", "RNG", "NIN", "COR", "PUP", "DNC"},
            Type = "Head",
            Stats = {
                DEF = 30,
                STR = 3,
                AGI = 3,
                CHR = 6,
                Haste = 2,
                TripleAttack = 1,
                FastCast = 2,
            }
        },
        ThurandautChapeau = {
            Name = "Thurandaut Chapeau",
            Level = 75,
            Id = 27784,
            Jobs = {"PUP"},
            Type = "Head",
            Stats = {
                DEF = 22,
                HP = 15,
                DEX = 5,
                Haste = 5,
            }
        },
        TplCrown_1 = {
            Name = "Tpl. Crown +1",
            Level = 74,
            Id = 15226,
            Jobs = {"MNK"},
            Type = "Head",
            Stats = {
                DEF = 23,
                HP = 16,
                MND = 8,
                HHP = 1,
            }
        },
        UkuxkajCap = {
            Name = "Ukuxkaj Cap",
            Level = 75,
            Id = 27766,
            Jobs = {"MNK", "THF", "RNG", "NIN", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 23,
                HP = 25,
                Attack = 9,
                Haste = 5,
            }
        },
        UnicornCap = {
            Name = "Unicorn Cap",
            Level = 74,
            Id = 15209,
            Jobs = {"WAR"},
            Type = "Head",
            Stats = {
                DEF = 35,
                HP = 36,
                Accuracy = 6,
            }
        },
        UnicornCap_1 = {
            Name = "Unicorn Cap +1",
            Level = 74,
            Id = 15210,
            Jobs = {"WAR"},
            Type = "Head",
            Stats = {
                DEF = 37,
                HP = 40,
                Accuracy = 7,
            }
        },
        UsukaneSomen = {
            Name = "Usukane Somen",
            Level = 75,
            Id = 16092,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Head",
            Stats = {
                DEF = 20,
                STR = 3,
                AGI = 3,
                Accuracy = 7,
                Evasion = 7,
                Haste = 3,
            }
        },
        ValkyriesHat = {
            Name = "Valkyries Hat",
            Level = 75,
            Id = 16116,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 19,
                MP = 40,
                MagicAccuracy = 6,
                Enmity = -4,
            }
        },
        ValkyriesHelm = {
            Name = "Valkyries Helm",
            Level = 75,
            Id = 16114,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Head",
            Stats = {
                DEF = 36,
                HP = 17,
                MP = 17,
                DEX = 5,
                Accuracy = 3,
                Attack = 10,
            }
        },
        ValorousMask = {
            Name = "Valorous Mask",
            Level = 75,
            Id = 25641,
            Jobs = {"BST"},
            Type = "Head",
            Stats = {
                DEF = 29,
                HP = 25,
                VIT = 6,
                MND = 6,
                Haste = 5,
                Enmity = -5,
            }
        },
        VanyaHood = {
            Name = "Vanya Hood",
            Level = 75,
            Id = 26797,
            Jobs = {"BLM"},
            Type = "Head",
            Stats = {
                DEF = 26,
                MP = 15,
                MND = 5,
                Enmity = -5,
            }
        },
        VlrCoronet_1 = {
            Name = "Vlr. Coronet +1",
            Level = 75,
            Id = 15251,
            Jobs = {"PLD"},
            Type = "Head",
            Stats = {
                DEF = 29,
                HP = 18,
                MP = 18,
                Enmity = 4,
            }
        },
        VoyagerSallet = {
            Name = "Voyager Sallet",
            Level = 41,
            Id = 15184,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                STR = 3,
                DEX = 4,
            }
        },
        WalahraTurban = {
            Name = "Walahra Turban",
            Level = 75,
            Id = 15270,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                HP = 30,
                MP = 30,
                Haste = 5,
            }
        },
        WarMask_1 = {
            Name = "War. Mask +1",
            Level = 75,
            Id = 15245,
            Jobs = {"WAR"},
            Type = "Head",
            Stats = {
                DEF = 29,
                DEX = 6,
                Enmity = 1,
            }
        },
        WarlocksChapeau = {
            Name = "Warlocks Chapeau",
            Level = 60,
            Id = 12513,
            Jobs = {"RDM"},
            Type = "Head",
            Stats = {
                DEF = 23,
                MP = 20,
                INT = 3,
                FastCast = 10,
            }
        },
        WiseCap = {
            Name = "Wise Cap",
            Level = 72,
            Id = 15190,
            Jobs = {"RDM"},
            Type = "Head",
            Stats = {
                DEF = 24,
                MP = 13,
                Accuracy = 2,
                RangedAccuracy = 3,
                MagicAccuracy = 5,
            }
        },
        WiseCap_1 = {
            Name = "Wise Cap +1",
            Level = 72,
            Id = 15191,
            Jobs = {"RDM"},
            Type = "Head",
            Stats = {
                DEF = 25,
                MP = 15,
                Accuracy = 3,
                RangedAccuracy = 4,
                MagicAccuracy = 6,
            }
        },
        WivreMask = {
            Name = "Wivre Mask",
            Level = 65,
            Id = 16130,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 20,
                STR = 2,
                VIT = 2,
                Evasion = 10,
            }
        },
        WivreMask_1 = {
            Name = "Wivre Mask +1",
            Level = 65,
            Id = 16131,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 21,
                STR = 3,
                VIT = 3,
                Evasion = 11,
            }
        },
        WizardsPetasos = {
            Name = "Wizards Petasos",
            Level = 60,
            Id = 13856,
            Jobs = {"BLM"},
            Type = "Head",
            Stats = {
                DEF = 20,
                MP = 25,
                INT = 4,
                Enmity = -4,
            }
        },
        WlkChapeau_1 = {
            Name = "Wlk. Chapeau +1",
            Level = 74,
            Id = 15229,
            Jobs = {"RDM"},
            Type = "Head",
            Stats = {
                DEF = 24,
                MP = 25,
                INT = 5,
                FastCast = 10,
            }
        },
        WoolHat = {
            Name = "Wool Hat",
            Level = 28,
            Id = 12474,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 9,
            }
        },
        WoolHat_1 = {
            Name = "Wool Hat +1",
            Level = 28,
            Id = 12479,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Head",
            Stats = {
                DEF = 10,
            }
        },
        WymArmet_1 = {
            Name = "Wym. Armet +1",
            Level = 75,
            Id = 15258,
            Jobs = {"DRG"},
            Type = "Head",
            Stats = {
                DEF = 26,
                HP = 16,
                STR = 5,
                Attack = 2,
            }
        },
        WyvernHelm = {
            Name = "Wyvern Helm",
            Level = 75,
            Id = 13920,
            Jobs = {"DRK", "BST", "RNG", "SAM", "DRG"},
            Type = "Head",
            Stats = {
                DEF = 30,
                HP = 30,
                STR = 5,
            }
        },
        WzdPetasos_1 = {
            Name = "Wzd. Petasos +1",
            Level = 74,
            Id = 15228,
            Jobs = {"BLM"},
            Type = "Head",
            Stats = {
                DEF = 20,
                MP = 30,
                INT = 5,
                Enmity = -4,
                HMP = 1,
            }
        },
        YagudoCrown = {
            Name = "Yagudo Crown",
            Level = 75,
            Id = 26702,
            Jobs = {"All"},
            Type = "Head",
            Stats = {
                DEF = 24,
                HP = 15,
                MP = 15,
                DEX = 3,
                Evasion = 3,
                Haste = 5,
            }
        },
        YashaJinpachi = {
            Name = "Yasha Jinpachi",
            Level = 71,
            Id = 12490,
            Jobs = {"NIN"},
            Type = "Head",
            Stats = {
                DEF = 22,
                INT = 7,
                Enmity = 2,
            }
        },
        YashaJinpachi_1 = {
            Name = "Yasha Jinpachi +1",
            Level = 71,
            Id = 15192,
            Jobs = {"NIN"},
            Type = "Head",
            Stats = {
                DEF = 23,
                INT = 8,
                Enmity = 3,
            }
        },
        ZenithCrown = {
            Name = "Zenith Crown",
            Level = 73,
            Id = 13876,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 30,
                INT = 3,
                MND = 3,
            }
        },
        ZenithCrown_1 = {
            Name = "Zenith Crown +1",
            Level = 73,
            Id = 13877,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Head",
            Stats = {
                DEF = 31,
                INT = 4,
                MND = 4,
            }
        },
    },
    Neck = {
        AifesMedal = {
            Name = "Aifes Medal",
            Level = 75,
            Id = 10942,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                INT = 6,
                MND = 6,
            }
        },
        AjariNecklace = {
            Name = "Ajari Necklace",
            Level = 58,
            Id = 13175,
            Jobs = {"WHM", "SMN"},
            Type = "Neck",
            Stats = {
                AGI = 2,
                MND = 6,
            }
        },
        ArmigersLace = {
            Name = "Armigers Lace",
            Level = 9,
            Id = 16296,
            Jobs = {"WAR", "RDM", "PLD", "DRK", "BST", "RNG", "SAM", "DRG", "BLU", "RUN"},
            Type = "Neck",
            Stats = {
                STR = 1,
                VIT = 1,
            }
        },
        ArtisansTorque = {
            Name = "Artisans Torque",
            Level = 1,
            Id = 10394,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
            }
        },
        BacklashTorque = {
            Name = "Backlash Torque",
            Level = 75,
            Id = 11586,
            Jobs = {"WAR", "MNK", "WHM", "BLM", "THF", "DRK", "BST", "BRD", "RNG", "NIN", "DRG", "SMN"},
            Type = "Neck",
            Stats = {
                Attack = 8,
                Counter = 1,
            }
        },
        BeastWhistle = {
            Name = "Beast Whistle",
            Level = 24,
            Id = 13110,
            Jobs = {"BST"},
            Type = "Neck",
            Stats = {
                VIT = 2,
                CHR = 2,
            }
        },
        BeguilingCollar = {
            Name = "Beguiling Collar",
            Level = 75,
            Id = 11585,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                HP = 20,
                MP = 20,
                Enmity = -3,
            }
        },
        BirdWhistle = {
            Name = "Bird Whistle",
            Level = 15,
            Id = 13072,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                HP = 5,
                CHR = 3,
            }
        },
        BlackNeckerchief = {
            Name = "Black Neckerchief",
            Level = 20,
            Id = 13113,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Neck",
            Stats = {
                DEF = 2,
                INT = 1,
            }
        },
        BloodbeadGorget = {
            Name = "Bloodbead Gorget",
            Level = 70,
            Id = 16302,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                HP = 60,
            }
        },
        BuffoonsCollar = {
            Name = "Buffoons Collar",
            Level = 5,
            Id = 16281,
            Jobs = {"PUP"},
            Type = "Neck",
            Stats = {
                HP = 3,
            }
        },
        CharmingVial = {
            Name = "Charming Vial",
            Level = 8,
            Id = 27516,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                DEF = 2,
                MP = 8,
                INT = 2,
                CHR = 2,
            }
        },
        ChivalrousChain = {
            Name = "Chivalrous Chain",
            Level = 60,
            Id = 15523,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                DEF = 4,
                STR = 3,
                Accuracy = 5,
                StoreTP = 1,
            }
        },
        ChocoboTorque = {
            Name = "Chocobo Torque",
            Level = 30,
            Id = 10924,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
            }
        },
        ChocoboWhistle = {
            Name = "Chocobo Whistle",
            Level = 20,
            Id = 15533,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
            }
        },
        CloudHairpin = {
            Name = "Cloud Hairpin",
            Level = 75,
            Id = 28350,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
            }
        },
        CombatantsTorque = {
            Name = "Combatants Torque",
            Level = 73,
            Id = 26015,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                STR = 5,
                DEX = 5,
                VIT = 5,
                AGI = 5,
                INT = 5,
                MND = 5,
                CHR = 5,
            }
        },
        EnfeeblingTorque = {
            Name = "Enfeebling Torque",
            Level = 65,
            Id = 13155,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
            }
        },
        FangNecklace = {
            Name = "Fang Necklace",
            Level = 21,
            Id = 13076,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                STR = 2,
                DEX = 2,
                MND = -4,
            }
        },
        FieldTorque = {
            Name = "Field Torque",
            Level = 65,
            Id = 10926,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
            }
        },
        FortitudeTorque = {
            Name = "Fortitude Torque",
            Level = 73,
            Id = 15511,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                VIT = 5,
            }
        },
        FotiaGorget = {
            Name = "Fotia Gorget",
            Level = 72,
            Id = 27510,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
            }
        },
        FylgjaTorque_1 = {
            Name = "Fylgja Torque +1",
            Level = 75,
            Id = 11580,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "PUP", "SCH", "GEO"},
            Type = "Neck",
            Stats = {
                HP = 12,
                Enmity = -2,
                CurePotency = 3,
            }
        },
        GnoleTorque = {
            Name = "Gnole Torque",
            Level = 72,
            Id = 16283,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                MND = 5,
                HMP = 3,
            }
        },
        GuardingTorque = {
            Name = "Guarding Torque",
            Level = 65,
            Id = 13151,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                HP = 7,
            }
        },
        HaltingStole = {
            Name = "Halting Stole",
            Level = 75,
            Id = 16306,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                DEX = 3,
            }
        },
        HolyPhial = {
            Name = "Holy Phial",
            Level = 26,
            Id = 13073,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                DEF = 3,
                MP = 9,
                MND = 3,
            }
        },
        HopeTorque = {
            Name = "Hope Torque",
            Level = 73,
            Id = 15509,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                AGI = 5,
            }
        },
        IncantersTorque = {
            Name = "Incanters Torque",
            Level = 75,
            Id = 26016,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
            }
        },
        JokushuChain = {
            Name = "Jokushu Chain",
            Level = 75,
            Id = 27525,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
            Type = "Neck",
            Stats = {
            }
        },
        JusticeBadge = {
            Name = "Justice Badge",
            Level = 7,
            Id = 13093,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                DEF = 1,
                MND = 3,
            }
        },
        JusticeTorque = {
            Name = "Justice Torque",
            Level = 73,
            Id = 15508,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                STR = 5,
            }
        },
        LeatherGorget = {
            Name = "Leather Gorget",
            Level = 7,
            Id = 13081,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Neck",
            Stats = {
                DEF = 1,
            }
        },
        LmgMedallion = {
            Name = "Lmg. Medallion",
            Level = 75,
            Id = 11583,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                INT = 4,
            }
        },
        LmgMedallion_1 = {
            Name = "Lmg. Medallion +1",
            Level = 75,
            Id = 11584,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                INT = 5,
            }
        },
        LoveTorque = {
            Name = "Love Torque",
            Level = 73,
            Id = 15514,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                DEX = 5,
            }
        },
        LoxoScarf = {
            Name = "Loxo Scarf",
            Level = 70,
            Id = 28384,
            Jobs = {"MNK", "RDM", "THF", "BST", "RNG", "NIN", "DRG", "COR", "PUP", "DNC", "RUN"},
            Type = "Neck",
            Stats = {
                AGI = 4,
                RangedAccuracy = 8,
                Enmity = -2,
            }
        },
        MarrowGorget = {
            Name = "Marrow Gorget",
            Level = 8,
            Id = 39043,
            Jobs = {"BST", "SMN", "PUP", "GEO"},
            Type = "Neck",
            Stats = {
                Accuracy = 2,
            }
        },
        MoepapaMedal = {
            Name = "Moepapa Medal",
            Level = 75,
            Id = 10943,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                DEX = 6,
                AGI = 6,
            }
        },
        MoepapaPendant = {
            Name = "Moepapa Pendant",
            Level = 75,
            Id = 10940,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
            Type = "Neck",
            Stats = {
                INT = 8,
                Enmity = -5,
            }
        },
        MujinNecklace = {
            Name = "Mujin Necklace",
            Level = 75,
            Id = 10933,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Neck",
            Stats = {
                STR = 5,
            }
        },
        NyxGorget = {
            Name = "Nyx Gorget",
            Level = 75,
            Id = 11587,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                DEF = 2,
            }
        },
        OneirosTorque = {
            Name = "Oneiros Torque",
            Level = 75,
            Id = 10932,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Neck",
            Stats = {
                Evasion = 5,
            }
        },
        PeacockCharm = {
            Name = "Peacock Charm",
            Level = 33,
            Id = 13056,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                Accuracy = 10,
                RangedAccuracy = 10,
            }
        },
        PegasusCollar = {
            Name = "Pegasus Collar",
            Level = 20,
            Id = 28610,
            Jobs = {"BRD", "COR"},
            Type = "Neck",
            Stats = {
                DEF = 3,
                AGI = 3,
                CHR = 3,
                MovementSpeed = 12,
            }
        },
        PhilomathStole = {
            Name = "Philomath Stole",
            Level = 61,
            Id = 13176,
            Jobs = {"BLM", "RDM", "BRD", "BLU", "PUP"},
            Type = "Neck",
            Stats = {
                INT = 3,
            }
        },
        PileChain = {
            Name = "Pile Chain",
            Level = 3,
            Id = 16279,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                HP = 3,
                Accuracy = 1,
            }
        },
        PortusCollar = {
            Name = "Portus Collar",
            Level = 74,
            Id = 10944,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Neck",
            Stats = {
                Accuracy = 2,
                DoubleAttack = 2,
            }
        },
        PrudenceTorque = {
            Name = "Prudence Torque",
            Level = 73,
            Id = 15510,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                INT = 5,
            }
        },
        RabbitCharm = {
            Name = "Rabbit Charm",
            Level = 7,
            Id = 13112,
            Jobs = {"THF"},
            Type = "Neck",
            Stats = {
                DEF = 1,
                DEX = 1,
                AGI = 1,
            }
        },
        RangersNecklace = {
            Name = "Rangers Necklace",
            Level = 14,
            Id = 13117,
            Jobs = {"RNG"},
            Type = "Neck",
            Stats = {
                RangedAccuracy = 5,
                RangedAttack = 5,
            }
        },
        RepellingCollar = {
            Name = "Repelling Collar",
            Level = 75,
            Id = 16307,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
            }
        },
        SnipersCollar = {
            Name = "Snipers Collar",
            Level = 69,
            Id = 15517,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                RangedAccuracy = 6,
                RangedAttack = 5,
                Enmity = -1,
                SubtleBlow = 1,
            }
        },
        SpikeNecklace = {
            Name = "Spike Necklace",
            Level = 21,
            Id = 13061,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                STR = 3,
                DEX = 3,
                MND = -6,
            }
        },
        TimelessOcarina = {
            Name = "Timeless Ocarina",
            Level = 70,
            Id = 28388,
            Jobs = {"BRD"},
            Type = "Neck",
            Stats = {
                MP = 25,
                STR = 5,
                CHR = 5,
            }
        },
        TjukurrpaMedal = {
            Name = "Tjukurrpa Medal",
            Level = 75,
            Id = 10941,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                STR = 6,
                VIT = 6,
            }
        },
        WarloqsLocket = {
            Name = "Warloqs Locket",
            Level = 70,
            Id = 28614,
            Jobs = {"WHM", "BLM", "RDM", "SMN", "SCH", "GEO"},
            Type = "Neck",
            Stats = {
                INT = 4,
                MND = 4,
            }
        },
        WindTorque = {
            Name = "Wind Torque",
            Level = 65,
            Id = 13161,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
            }
        },
        WingPendant = {
            Name = "Wing Pendant",
            Level = 7,
            Id = 13183,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                AGI = 1,
            }
        },
        WivreGorget = {
            Name = "Wivre Gorget",
            Level = 70,
            Id = 16265,
            Jobs = {"All"},
            Type = "Neck",
            Stats = {
                DEF = 8,
                Accuracy = 5,
                RangedAccuracy = 5,
            }
        },
    },
    Ear = {
        AltdorfsEarring = {
            Name = "Altdorfs Earring",
            Level = 60,
            Id = 16035,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                RangedAccuracy = 1,
            }
        },
        ApollosEarring = {
            Name = "Apollos Earring",
            Level = 75,
            Id = 11692,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                HP = 20,
                Enmity = -3,
                CurePotency = 3,
            }
        },
        AquaEarring = {
            Name = "Aqua Earring",
            Level = 75,
            Id = 11683,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MND = 2,
                MagicAccuracy = 2,
            }
        },
        AquilosEarring = {
            Name = "Aquilos Earring",
            Level = 75,
            Id = 11690,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                INT = 3,
            }
        },
        AssaultEarring = {
            Name = "Assault Earring",
            Level = 58,
            Id = 13403,
            Jobs = {"WAR", "PLD", "DRK", "BST", "DRG"},
            Type = "Ear",
            Stats = {
                DEF = -3,
                Accuracy = 2,
                Attack = 5,
                Evasion = -2,
            }
        },
        AustersEarring = {
            Name = "Austers Earring",
            Level = 75,
            Id = 11689,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                AGI = 3,
                RangedAccuracy = 3,
            }
        },
        BanditsEarring = {
            Name = "Bandits Earring",
            Level = 60,
            Id = 28513,
            Jobs = {"THF", "BRD", "NIN", "DNC", "RUN"},
            Type = "Ear",
            Stats = {
                Enmity = 2,
            }
        },
        BoneEarring = {
            Name = "Bone Earring",
            Level = 16,
            Id = 13321,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                Attack = 1,
                Evasion = -1,
            }
        },
        BrachyuraEarring = {
            Name = "Brachyura Earring",
            Level = 70,
            Id = 11039,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MP = 15,
            }
        },
        BreezeEarring = {
            Name = "Breeze Earring",
            Level = 75,
            Id = 11681,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                AGI = 2,
                RangedAccuracy = 2,
            }
        },
        BrutalEarring = {
            Name = "Brutal Earring",
            Level = 75,
            Id = 14813,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                StoreTP = 1,
                DoubleAttack = 5,
            }
        },
        Bushinomimi = {
            Name = "Bushinomimi",
            Level = 72,
            Id = 14743,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                STR = 2,
            }
        },
        CassEarring = {
            Name = "Cass. Earring",
            Level = 60,
            Id = 16038,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MP = 5,
            }
        },
        ChoreiaEarring = {
            Name = "Choreia Earring",
            Level = 75,
            Id = 16055,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
            }
        },
        CunningEarring = {
            Name = "Cunning Earring",
            Level = 29,
            Id = 14760,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                INT = 1,
            }
        },
        CuratesEarring = {
            Name = "Curates Earring",
            Level = 30,
            Id = 11051,
            Jobs = {"WHM", "RDM", "SMN", "SCH", "GEO"},
            Type = "Ear",
            Stats = {
                MP = 10,
                MND = 1,
                CurePotency = 2,
            }
        },
        DarknessEarring = {
            Name = "Darkness Earring",
            Level = 75,
            Id = 11685,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MP = 25,
                Enmity = 2,
                HMP = 2,
            }
        },
        DodgeEarring = {
            Name = "Dodge Earring",
            Level = 29,
            Id = 13366,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                Evasion = 3,
            }
        },
        DragonkinEarring = {
            Name = "Dragonkin Earring",
            Level = 72,
            Id = 11038,
            Jobs = {"WAR", "PLD", "DRK", "BST", "DRG"},
            Type = "Ear",
            Stats = {
                Attack = 5,
            }
        },
        DuchyEarring = {
            Name = "Duchy Earring",
            Level = 30,
            Id = 16042,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
            }
        },
        EmberpearlEarring = {
            Name = "Emberpearl Earring",
            Level = 75,
            Id = 28612,
            Jobs = {"WAR", "MNK", "WHM", "RDM", "PLD", "DRK", "BST", "RNG", "SAM", "DRG", "BLU", "COR", "GEO", "RUN"},
            Type = "Ear",
            Stats = {
                STR = 2,
                MND = 2,
            }
        },
        EvaderEarring = {
            Name = "Evader Earring",
            Level = 72,
            Id = 11060,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                Attack = -6,
                Evasion = 6,
            }
        },
        EvaderEarring_1 = {
            Name = "Evader Earring +1",
            Level = 72,
            Id = 11061,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                Attack = -7,
                Evasion = 7,
            }
        },
        FederationEarring = {
            Name = "Federation Earring",
            Level = 20,
            Id = 16041,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
            }
        },
        FlameEarring = {
            Name = "Flame Earring",
            Level = 75,
            Id = 11678,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                STR = 2,
                Attack = 2,
            }
        },
        GenmeiEarring = {
            Name = "Genmei Earring",
            Level = 75,
            Id = 27539,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                DEF = 3,
                Counter = 2,
            }
        },
        GhillieEarring = {
            Name = "Ghillie Earring",
            Level = 72,
            Id = 11056,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                Accuracy = 2,
                RangedAccuracy = 2,
                Evasion = -5,
            }
        },
        GhillieEarring_1 = {
            Name = "Ghillie Earring +1",
            Level = 72,
            Id = 11057,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                Accuracy = 3,
                RangedAccuracy = 3,
                Evasion = -5,
            }
        },
        GuignolEarring = {
            Name = "Guignol Earring",
            Level = 69,
            Id = 15999,
            Jobs = {"PUP"},
            Type = "Ear",
            Stats = {
            }
        },
        HelenussEarring = {
            Name = "Helenuss Earring",
            Level = 60,
            Id = 16037,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                HP = 5,
            }
        },
        HirudineaEarring = {
            Name = "Hirudinea Earring",
            Level = 75,
            Id = 16054,
            Jobs = {"BLM", "DRK", "SCH", "GEO"},
            Type = "Ear",
            Stats = {
                HP = -5,
                MP = -5,
            }
        },
        IncubusEarring_1 = {
            Name = "Incubus Earring +1",
            Level = 75,
            Id = 16053,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Ear",
            Stats = {
                MagicAccuracy = 3,
                Enmity = 1,
            }
        },
        JupitersEarring = {
            Name = "Jupiters Earring",
            Level = 75,
            Id = 11687,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                DEX = 3,
                Accuracy = 3,
            }
        },
        KingdomEarring = {
            Name = "Kingdom Earring",
            Level = 20,
            Id = 16039,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
            }
        },
        LightEarring = {
            Name = "Light Earring",
            Level = 75,
            Id = 11684,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                HP = 15,
                Enmity = -2,
                CurePotency = 2,
            }
        },
        LiminusEarring = {
            Name = "Liminus Earring",
            Level = 70,
            Id = 11041,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MP = 10,
            }
        },
        LoquacEarring = {
            Name = "Loquac. Earring",
            Level = 75,
            Id = 14812,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MP = 30,
                FastCast = 2,
            }
        },
        LuminousEarring = {
            Name = "Luminous Earring",
            Level = 75,
            Id = 28613,
            Jobs = {"MNK", "RDM", "THF", "BST", "BRD", "NIN", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Ear",
            Stats = {
                Accuracy = 3,
                Attack = 4,
                SubtleBlow = 2,
            }
        },
        MegascoEarring = {
            Name = "Megasco Earring",
            Level = 75,
            Id = 28488,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                HP = -10,
                Accuracy = 2,
                Evasion = 6,
            }
        },
        MhauraEarring = {
            Name = "Mhaura Earring",
            Level = 25,
            Id = 16044,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
            }
        },
        MoldaviteEarring = {
            Name = "Moldavite Earring",
            Level = 47,
            Id = 14724,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MagicAttackBonus = 5,
            }
        },
        MorionEarring = {
            Name = "Morion Earring",
            Level = 30,
            Id = 14720,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MP = 4,
                INT = 1,
            }
        },
        MujinStud = {
            Name = "Mujin Stud",
            Level = 75,
            Id = 11032,
            Jobs = {"MNK", "WHM", "RDM", "THF", "BST", "BRD", "RNG", "SAM", "NIN", "BLU", "COR", "DNC", "RUN"},
            Type = "Ear",
            Stats = {
                MagicDefenseBonus = 2,
                SubtleBlow = 4,
            }
        },
        MusicalEarring = {
            Name = "Musical Earring",
            Level = 70,
            Id = 15961,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                Evasion = 5,
            }
        },
        NashmauEarring = {
            Name = "Nashmau Earring",
            Level = 50,
            Id = 16050,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
            }
        },
        NeptunesEarring = {
            Name = "Neptunes Earring",
            Level = 75,
            Id = 11691,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MND = 3,
                MagicAccuracy = 3,
            }
        },
        NorgEarring = {
            Name = "Norg Earring",
            Level = 40,
            Id = 16047,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
            }
        },
        NovioEarring = {
            Name = "Novio Earring",
            Level = 75,
            Id = 14808,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MagicAttackBonus = 7,
            }
        },
        OneirosEarring = {
            Name = "Oneiros Earring",
            Level = 75,
            Id = 11030,
            Jobs = {"WAR", "MNK", "THF", "PLD", "DRK", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "PUP", "RUN"},
            Type = "Ear",
            Stats = {
                HP = 15,
                VIT = 3,
            }
        },
        OneirosPearl = {
            Name = "Oneiros Pearl",
            Level = 75,
            Id = 11031,
            Jobs = {"RDM", "THF", "RNG", "SAM", "NIN", "COR"},
            Type = "Ear",
            Stats = {
                RangedAttack = 3,
                Enmity = -2,
            }
        },
        OpticalEarring = {
            Name = "Optical Earring",
            Level = 10,
            Id = 14803,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                DEF = 1,
                Accuracy = 1,
                Attack = -2,
            }
        },
        OutlawsEarring = {
            Name = "Outlaws Earring",
            Level = 50,
            Id = 28539,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MP = 15,
                DEX = 2,
                MND = 2,
            }
        },
        PagondasEarring = {
            Name = "Pagondas Earring",
            Level = 75,
            Id = 16056,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                DEF = 10,
            }
        },
        PigeonEarring = {
            Name = "Pigeon Earring",
            Level = 33,
            Id = 14722,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                HP = 20,
            }
        },
        PigeonEarring_1 = {
            Name = "Pigeon Earring +1",
            Level = 33,
            Id = 14723,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                HP = 25,
            }
        },
        PlutosEarring = {
            Name = "Plutos Earring",
            Level = 75,
            Id = 11693,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                MP = 20,
                Enmity = 3,
                HMP = 3,
            }
        },
        RabaoEarring = {
            Name = "Rabao Earring",
            Level = 30,
            Id = 16045,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
            }
        },
        SelbinaEarring = {
            Name = "Selbina Earring",
            Level = 25,
            Id = 16043,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
            }
        },
        SnowEarring = {
            Name = "Snow Earring",
            Level = 75,
            Id = 11682,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                INT = 2,
            }
        },
        SoilEarring = {
            Name = "Soil Earring",
            Level = 75,
            Id = 11680,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                VIT = 2,
            }
        },
        Suppanomimi = {
            Name = "Suppanomimi",
            Level = 72,
            Id = 14739,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                AGI = 2,
                DualWield = 5,
            }
        },
        TerminusEarring = {
            Name = "Terminus Earring",
            Level = 70,
            Id = 11040,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                HP = 10,
            }
        },
        TerrasEarring = {
            Name = "Terras Earring",
            Level = 75,
            Id = 11688,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                VIT = 3,
            }
        },
        ThunderEarring = {
            Name = "Thunder Earring",
            Level = 75,
            Id = 11679,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                DEX = 2,
                Accuracy = 2,
            }
        },
        TribalEarring = {
            Name = "Tribal Earring",
            Level = 20,
            Id = 28343,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                DEF = 1,
                VIT = 1,
            }
        },
        VulcansEarring = {
            Name = "Vulcans Earring",
            Level = 75,
            Id = 11686,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                STR = 3,
                Attack = 3,
            }
        },
        WildernessEarring = {
            Name = "Wilderness Earring",
            Level = 45,
            Id = 28490,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                Accuracy = 1,
            }
        },
        WilhelmsEarring = {
            Name = "Wilhelms Earring",
            Level = 60,
            Id = 16036,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                RangedAttack = 1,
            }
        },
        WingEarring = {
            Name = "Wing Earring",
            Level = 35,
            Id = 13322,
            Jobs = {"All"},
            Type = "Ear",
            Stats = {
                AGI = 2,
            }
        },
    },
    Body = {
        AbsCuirass_1 = {
            Name = "Abs. Cuirass +1",
            Level = 75,
            Id = 14507,
            Jobs = {"DRK"},
            Type = "Body",
            Stats = {
                DEF = 50,
                HP = 27,
                MND = 4,
                Accuracy = 12,
                MagicAttackBonus = 10,
            }
        },
        AcroSurcoat = {
            Name = "Acro Surcoat",
            Level = 75,
            Id = 26892,
            Jobs = {"WAR", "PLD", "DRK", "SAM", "DRG", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 53,
                HP = 15,
                MP = 15,
                STR = 10,
                VIT = 10,
                Accuracy = 5,
                Haste = 1,
                Enmity = 8,
                DoubleAttack = 2,
            }
        },
        AdamanHauberk = {
            Name = "Adaman Hauberk",
            Level = 73,
            Id = 12557,
            Jobs = {"WAR", "DRK", "BST"},
            Type = "Body",
            Stats = {
                DEF = 53,
                STR = 10,
                DEX = 10,
                Accuracy = 15,
                Attack = 15,
                Evasion = -10,
            }
        },
        AdhemarJacket = {
            Name = "Adhemar Jacket",
            Level = 75,
            Id = 25686,
            Jobs = {"THF"},
            Type = "Body",
            Stats = {
                DEF = 49,
                HP = 30,
                Attack = 10,
                Haste = 3,
                Enmity = 5,
            }
        },
        AegasDoublet = {
            Name = "Aegas Doublet",
            Level = 32,
            Id = 11338,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "RNG", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 21,
                SubtleBlow = 3,
            }
        },
        AgwusRobe = {
            Name = "Agwus Robe",
            Level = 75,
            Id = 23766,
            Jobs = {"BLU"},
            Type = "Body",
            Stats = {
                DEF = 47,
                MP = 50,
                STR = 10,
                DEX = 10,
                Refresh = 1,
            }
        },
        Aketon = {
            Name = "Aketon",
            Level = 60,
            Id = 13742,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 39,
                HP = 10,
                AGI = 5,
                Evasion = 5,
            }
        },
        AmalricDoublet = {
            Name = "Amalric Doublet",
            Level = 75,
            Id = 25688,
            Jobs = {"GEO"},
            Type = "Body",
            Stats = {
                DEF = 41,
                HP = 50,
                MP = 50,
                INT = 10,
                MND = 10,
                MagicAttackBonus = 6,
                Haste = 5,
            }
        },
        AnglersTunica = {
            Name = "Anglers Tunica",
            Level = 15,
            Id = 13809,
            Jobs = {"All"},
            Type = "Body",
            Stats = {
                DEF = 12,
            }
        },
        AntaresHarness = {
            Name = "Antares Harness",
            Level = 71,
            Id = 11287,
            Jobs = {"WAR", "MNK", "RDM", "THF", "DRK", "BRD", "NIN", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 50,
                HP = 15,
                DEX = 8,
                AGI = 8,
                Accuracy = 8,
                Evasion = 8,
            }
        },
        AresCuirass = {
            Name = "Ares Cuirass",
            Level = 75,
            Id = 14546,
            Jobs = {"WAR", "PLD", "DRK", "DRG", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 55,
                HPP = 3,
                MPP = 3,
                STR = 12,
                VIT = 12,
                Attack = 24,
                Refresh = 1,
            }
        },
        ArguteGown = {
            Name = "Argute Gown",
            Level = 74,
            Id = 11307,
            Jobs = {"SCH"},
            Type = "Body",
            Stats = {
                DEF = 38,
                HP = 15,
                MP = 15,
                MagicDefenseBonus = 5,
            }
        },
        ArguteGown_1 = {
            Name = "Argute Gown +1",
            Level = 75,
            Id = 11308,
            Jobs = {"SCH"},
            Type = "Body",
            Stats = {
                DEF = 39,
                HP = 17,
                MP = 17,
                MagicDefenseBonus = 6,
            }
        },
        ArhatsGi = {
            Name = "Arhats Gi",
            Level = 64,
            Id = 13795,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 38,
                Enmity = 3,
            }
        },
        ArhatsGi_1 = {
            Name = "Arhats Gi +1",
            Level = 64,
            Id = 13802,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 39,
                Enmity = 4,
            }
        },
        ArmadaHauberk = {
            Name = "Armada Hauberk",
            Level = 73,
            Id = 14371,
            Jobs = {"WAR", "DRK", "BST"},
            Type = "Body",
            Stats = {
                DEF = 54,
                STR = 11,
                DEX = 11,
                Accuracy = 16,
                Attack = 16,
                Evasion = -11,
            }
        },
        AsnVest_1 = {
            Name = "Asn. Vest +1",
            Level = 75,
            Id = 14505,
            Jobs = {"THF"},
            Type = "Body",
            Stats = {
                DEF = 46,
                HP = 22,
                AGI = 5,
                Enmity = 5,
                CriticalHitRate = 1,
            }
        },
        AssaultJerkin = {
            Name = "Assault Jerkin",
            Level = 67,
            Id = 13805,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 42,
                HPP = -1,
                Accuracy = 3,
                Attack = 18,
            }
        },
        BaguaTunic = {
            Name = "Bagua Tunic",
            Level = 75,
            Id = 26840,
            Jobs = {"GEO"},
            Type = "Body",
            Stats = {
                DEF = 43,
                HP = 15,
                MP = 15,
                MagicAttackBonus = 5,
            }
        },
        BaguaTunic_1 = {
            Name = "Bagua Tunic +1",
            Level = 75,
            Id = 26841,
            Jobs = {"GEO"},
            Type = "Body",
            Stats = {
                DEF = 44,
                HP = 20,
                MP = 20,
                MagicAttackBonus = 6,
            }
        },
        BeastJackcoat = {
            Name = "Beast Jackcoat",
            Level = 58,
            Id = 12646,
            Jobs = {"BST"},
            Type = "Body",
            Stats = {
                DEF = 44,
                HP = 20,
                VIT = 3,
            }
        },
        BeetleHarness = {
            Name = "Beetle Harness",
            Level = 21,
            Id = 12583,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 17,
            }
        },
        BeetleHarness_1 = {
            Name = "Beetle Harness +1",
            Level = 21,
            Id = 13717,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 18,
                Evasion = 1,
            }
        },
        BlackCloak = {
            Name = "Black Cloak",
            Level = 68,
            Id = 13779,
            Jobs = {"BLM"},
            Type = "Body",
            Stats = {
                DEF = 60,
                INT = 4,
                Refresh = 1,
            }
        },
        BlessedBliaut = {
            Name = "Blessed Bliaut",
            Level = 70,
            Id = 14436,
            Jobs = {"WHM"},
            Type = "Body",
            Stats = {
                DEF = 41,
                MPP = 7,
                MND = 5,
                Enmity = -5,
            }
        },
        BlessedBliaut_1 = {
            Name = "Blessed Bliaut +1",
            Level = 70,
            Id = 14438,
            Jobs = {"WHM"},
            Type = "Body",
            Stats = {
                DEF = 42,
                MPP = 8,
                MND = 6,
                Enmity = -6,
            }
        },
        BloodScaleMail = {
            Name = "Blood Scale Mail",
            Level = 73,
            Id = 14368,
            Jobs = {"RDM", "PLD", "DRK", "RNG", "DRG", "BLU", "COR", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 53,
                HP = 42,
                MP = 42,
                INT = 11,
                MND = 11,
            }
        },
        BloodyAketon = {
            Name = "Bloody Aketon",
            Level = 70,
            Id = 13772,
            Jobs = {"MNK", "RDM", "THF", "BST", "RNG", "DRG", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 40,
                HP = 20,
                AGI = 6,
            }
        },
        BlueCotehardie = {
            Name = "Blue Cotehardie",
            Level = 69,
            Id = 13775,
            Jobs = {"RDM", "THF", "RNG", "NIN", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 43,
                STR = 4,
                DEX = 3,
                VIT = -3,
                AGI = 4,
                INT = 3,
                MND = -4,
                CHR = -4,
            }
        },
        BrdJstcorps_1 = {
            Name = "Brd. Jstcorps +1",
            Level = 75,
            Id = 14509,
            Jobs = {"BRD"},
            Type = "Body",
            Stats = {
                DEF = 46,
                HP = 19,
                Attack = 20,
            }
        },
        BstJackcoat_1 = {
            Name = "Bst. Jackcoat +1",
            Level = 74,
            Id = 14481,
            Jobs = {"BST"},
            Type = "Body",
            Stats = {
                DEF = 49,
                HP = 20,
                VIT = 6,
            }
        },
        BunzisRobe = {
            Name = "Bunzis Robe",
            Level = 75,
            Id = 23767,
            Jobs = {"WHM"},
            Type = "Body",
            Stats = {
                DEF = 45,
                MP = 50,
                STR = 10,
                VIT = 10,
            }
        },
        Byrnie = {
            Name = "Byrnie",
            Level = 60,
            Id = 13740,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 46,
                HP = 25,
                STR = 3,
                DEX = -3,
                VIT = 3,
                AGI = -3,
                INT = -3,
                MND = -3,
                CHR = -3,
                Attack = 20,
            }
        },
        Chasuble = {
            Name = "Chasuble",
            Level = 72,
            Id = 14440,
            Jobs = {"RDM"},
            Type = "Body",
            Stats = {
                DEF = 43,
                MP = 20,
                Accuracy = 5,
                MagicAccuracy = 5,
                Enmity = -2,
            }
        },
        Chasuble_1 = {
            Name = "Chasuble +1",
            Level = 72,
            Id = 14441,
            Jobs = {"RDM"},
            Type = "Body",
            Stats = {
                DEF = 44,
                MP = 25,
                Accuracy = 6,
                MagicAccuracy = 6,
                Enmity = -3,
            }
        },
        ChironicDoublet = {
            Name = "Chironic Doublet",
            Level = 75,
            Id = 25720,
            Jobs = {"SMN"},
            Type = "Body",
            Stats = {
                DEF = 41,
                MP = 50,
                VIT = 5,
                MND = 5,
                Refresh = 1,
            }
        },
        ChlJstcorps_1 = {
            Name = "Chl. Jstcorps +1",
            Level = 74,
            Id = 14482,
            Jobs = {"BRD"},
            Type = "Body",
            Stats = {
                DEF = 45,
                HP = 20,
                VIT = 10,
                CHR = 10,
                Enmity = -3,
            }
        },
        ChoralJstcorps = {
            Name = "Choral Jstcorps",
            Level = 58,
            Id = 12647,
            Jobs = {"BRD"},
            Type = "Body",
            Stats = {
                DEF = 38,
                HP = 13,
                VIT = 3,
                Enmity = -1,
            }
        },
        ChsCuirass_1 = {
            Name = "Chs. Cuirass +1",
            Level = 74,
            Id = 14480,
            Jobs = {"DRK"},
            Type = "Body",
            Stats = {
                DEF = 49,
                HP = 20,
                MP = 20,
                STR = 7,
                VIT = 7,
                Attack = 10,
            }
        },
        ClericsBliaut = {
            Name = "Clerics Bliaut",
            Level = 74,
            Id = 15089,
            Jobs = {"WHM"},
            Type = "Body",
            Stats = {
                DEF = 42,
                MP = 24,
                Enmity = -2,
                Refresh = 1,
            }
        },
        ClrBliaut_1 = {
            Name = "Clr. Bliaut +1",
            Level = 75,
            Id = 14502,
            Jobs = {"WHM"},
            Type = "Body",
            Stats = {
                DEF = 43,
                MP = 29,
                Enmity = -3,
                Refresh = 1,
            }
        },
        CoarseBreastplate = {
            Name = "Coarse Breastplate",
            Level = 8,
            Id = 27739,
            Jobs = {"WAR", "PLD", "DRK", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 14,
                Evasion = -3,
            }
        },
        CommFrac_1 = {
            Name = "Comm. Frac +1",
            Level = 75,
            Id = 11296,
            Jobs = {"COR"},
            Type = "Body",
            Stats = {
                DEF = 46,
                STR = 3,
                Accuracy = 10,
                RangedAttack = 10,
            }
        },
        CorsairsFrac_1 = {
            Name = "Corsairs Frac +1",
            Level = 74,
            Id = 11294,
            Jobs = {"COR"},
            Type = "Body",
            Stats = {
                DEF = 43,
                HP = 20,
                DEX = 5,
                AGI = 5,
                RangedAccuracy = 10,
                RangedAttack = 5,
            }
        },
        CottonDoublet = {
            Name = "Cotton Doublet",
            Level = 23,
            Id = 12593,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 17,
            }
        },
        CrmScaleMail = {
            Name = "Crm. Scale Mail",
            Level = 73,
            Id = 14367,
            Jobs = {"RDM", "PLD", "DRK", "RNG", "DRG", "BLU", "COR", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 52,
                HP = 40,
                MP = 40,
                INT = 10,
                MND = 10,
            }
        },
        Dalmatica = {
            Name = "Dalmatica",
            Level = 73,
            Id = 13787,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 45,
                MagicDefenseBonus = 5,
                Refresh = 1,
            }
        },
        Dalmatica_1 = {
            Name = "Dalmatica +1",
            Level = 73,
            Id = 13788,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 46,
                MagicDefenseBonus = 6,
                Refresh = 1,
            }
        },
        DinoJerkin = {
            Name = "Dino Jerkin",
            Level = 48,
            Id = 13727,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 36,
            }
        },
        DivineBreastplate = {
            Name = "Divine Breastplate",
            Level = 40,
            Id = 13813,
            Jobs = {"WHM"},
            Type = "Body",
            Stats = {
                DEF = 50,
            }
        },
        DlsTabard_1 = {
            Name = "Dls. Tabard +1",
            Level = 75,
            Id = 14504,
            Jobs = {"RDM"},
            Type = "Body",
            Stats = {
                DEF = 46,
                MP = 30,
                AGI = 4,
                FastCast = 10,
            }
        },
        DncCasaque_1 = {
            Name = "Dnc. Casaque +1",
            Level = 74,
            Id = 11302,
            Jobs = {"DNC"},
            Type = "Body",
            Stats = {
                DEF = 39,
                HP = 25,
                STR = 5,
                DEX = 5,
                Enmity = -2,
            }
        },
        Doublet = {
            Name = "Doublet",
            Level = 11,
            Id = 12592,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 10,
            }
        },
        Doublet_1 = {
            Name = "Doublet +1",
            Level = 11,
            Id = 12591,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 11,
            }
        },
        DragonHarness = {
            Name = "Dragon Harness",
            Level = 73,
            Id = 14389,
            Jobs = {"THF"},
            Type = "Body",
            Stats = {
                DEF = 44,
                DEX = 6,
                AGI = 6,
                Attack = 10,
                SubtleBlow = 10,
            }
        },
        DragonHarness_1 = {
            Name = "Dragon Harness +1",
            Level = 73,
            Id = 14390,
            Jobs = {"THF"},
            Type = "Body",
            Stats = {
                DEF = 45,
                DEX = 7,
                AGI = 7,
                Attack = 12,
                SubtleBlow = 12,
            }
        },
        DragonMail = {
            Name = "Dragon Mail",
            Level = 70,
            Id = 12564,
            Jobs = {"DRG"},
            Type = "Body",
            Stats = {
                DEF = 47,
                HP = 12,
            }
        },
        DragonMail_1 = {
            Name = "Dragon Mail +1",
            Level = 70,
            Id = 13762,
            Jobs = {"DRG"},
            Type = "Body",
            Stats = {
                DEF = 48,
                HP = 14,
            }
        },
        DrnMail_1 = {
            Name = "Drn. Mail +1",
            Level = 74,
            Id = 14486,
            Jobs = {"DRG"},
            Type = "Body",
            Stats = {
                DEF = 49,
                HP = 15,
                STR = 6,
                VIT = 6,
                Attack = 7,
            }
        },
        DruidsRobe = {
            Name = "Druids Robe",
            Level = 8,
            Id = 28167,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 10,
                MP = 5,
            }
        },
        DuelistsTabard = {
            Name = "Duelists Tabard",
            Level = 74,
            Id = 15091,
            Jobs = {"RDM"},
            Type = "Body",
            Stats = {
                DEF = 45,
                MP = 24,
                AGI = 4,
                FastCast = 10,
            }
        },
        DuxScaleMail = {
            Name = "Dux Scale Mail",
            Level = 70,
            Id = 10272,
            Jobs = {"RUN"},
            Type = "Body",
            Stats = {
                DEF = 51,
                STR = 9,
                VIT = 9,
                Attack = 15,
                Enmity = 6,
            }
        },
        DuxScaleMail_1 = {
            Name = "Dux Scale Mail +1",
            Level = 70,
            Id = 10273,
            Jobs = {"RUN"},
            Type = "Body",
            Stats = {
                DEF = 52,
                STR = 10,
                VIT = 10,
                Attack = 16,
                Enmity = 7,
            }
        },
        Eisenbrust = {
            Name = "Eisenbrust",
            Level = 29,
            Id = 14431,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Body",
            Stats = {
                DEF = 24,
                AGI = 2,
            }
        },
        ErrantHpl = {
            Name = "Errant Hpl.",
            Level = 72,
            Id = 14380,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 42,
                STR = -7,
                DEX = -7,
                VIT = -7,
                AGI = -7,
                INT = 10,
                MND = 10,
                CHR = 10,
                Enmity = -3,
                HMP = 5,
            }
        },
        EtoileCasaque_1 = {
            Name = "Etoile Casaque +1",
            Level = 75,
            Id = 11306,
            Jobs = {"DNC"},
            Type = "Body",
            Stats = {
                DEF = 40,
                DEX = 4,
                Accuracy = 12,
                Attack = 14,
            }
        },
        EvkDoublet_1 = {
            Name = "Evk. Doublet +1",
            Level = 74,
            Id = 14487,
            Jobs = {"SMN"},
            Type = "Body",
            Stats = {
                DEF = 35,
                MP = 45,
                HMP = 5,
            }
        },
        FaerieTunic = {
            Name = "Faerie Tunic",
            Level = 27,
            Id = 13731,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 22,
                HP = 6,
            }
        },
        FieldTunica = {
            Name = "Field Tunica",
            Level = 1,
            Id = 14374,
            Jobs = {"All"},
            Type = "Body",
            Stats = {
                DEF = 2,
            }
        },
        FtrLorica_1 = {
            Name = "Ftr. Lorica +1",
            Level = 74,
            Id = 14473,
            Jobs = {"WAR"},
            Type = "Body",
            Stats = {
                DEF = 50,
                HP = 20,
                VIT = 7,
                Attack = 10,
                Enmity = 8,
            }
        },
        FutharkCoat = {
            Name = "Futhark Coat",
            Level = 75,
            Id = 26842,
            Jobs = {"RUN"},
            Type = "Body",
            Stats = {
                DEF = 52,
                HP = 15,
                MP = 15,
                STR = 7,
                VIT = 7,
                MagicEvasion = 9,
            }
        },
        FutharkCoat_1 = {
            Name = "Futhark Coat +1",
            Level = 75,
            Id = 26843,
            Jobs = {"RUN"},
            Type = "Body",
            Stats = {
                DEF = 53,
                HP = 22,
                MP = 22,
                STR = 8,
                VIT = 8,
                MagicEvasion = 10,
            }
        },
        GarishTunic = {
            Name = "Garish Tunic",
            Level = 30,
            Id = 14425,
            Jobs = {"MNK", "RDM", "PLD", "BRD", "RNG", "BLU", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 19,
            }
        },
        GarrisonTunica = {
            Name = "Garrison Tunica",
            Level = 18,
            Id = 13818,
            Jobs = {"All"},
            Type = "Body",
            Stats = {
                DEF = 15,
                DEX = 1,
                CHR = 1,
            }
        },
        GarrisonTunica_1 = {
            Name = "Garrison Tunica +1",
            Level = 20,
            Id = 26543,
            Jobs = {"All"},
            Type = "Body",
            Stats = {
                DEF = 18,
                MP = 10,
                DEX = 2,
                CHR = 2,
            }
        },
        GenieWeskit = {
            Name = "Genie Weskit",
            Level = 73,
            Id = 14421,
            Jobs = {"BLM"},
            Type = "Body",
            Stats = {
                DEF = 36,
                MagicAttackBonus = 7,
                ConserveMP = 2,
            }
        },
        GeomancyTunic = {
            Name = "Geomancy Tunic",
            Level = 75,
            Id = 27926,
            Jobs = {"GEO"},
            Type = "Body",
            Stats = {
                DEF = 40,
                MP = 35,
                HMP = 5,
            }
        },
        GletisCuirass = {
            Name = "Gletis Cuirass",
            Level = 75,
            Id = 23763,
            Jobs = {"DRK"},
            Type = "Body",
            Stats = {
                DEF = 52,
                HP = 50,
                STR = 10,
                DEX = 10,
                Accuracy = 15,
                Attack = 15,
                Refresh = 1,
            }
        },
        GltSurcoat_1 = {
            Name = "Glt. Surcoat +1",
            Level = 74,
            Id = 14479,
            Jobs = {"PLD"},
            Type = "Body",
            Stats = {
                DEF = 55,
                HP = 20,
                VIT = 6,
                Enmity = 2,
            }
        },
        GreatDoublet = {
            Name = "Great Doublet",
            Level = 23,
            Id = 12669,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 18,
            }
        },
        HachimanDomaru = {
            Name = "Hachiman Domaru",
            Level = 70,
            Id = 14437,
            Jobs = {"SAM"},
            Type = "Body",
            Stats = {
                DEF = 47,
                STR = 8,
                StoreTP = 6,
            }
        },
        Haubergeon = {
            Name = "Haubergeon",
            Level = 59,
            Id = 12555,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 45,
                STR = 5,
                DEX = 5,
                AGI = -5,
                Accuracy = 10,
                Attack = 10,
                Evasion = -20,
            }
        },
        Haubergeon_1 = {
            Name = "Haubergeon +1",
            Level = 59,
            Id = 13735,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 46,
                STR = 6,
                DEX = 6,
                AGI = -5,
                Accuracy = 12,
                Attack = 12,
                Evasion = -20,
            }
        },
        HctHarness_1 = {
            Name = "Hct. Harness +1",
            Level = 73,
            Id = 14379,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 51,
                HP = 18,
                STR = 13,
                Accuracy = 11,
                Haste = -15,
            }
        },
        HecatombHarness = {
            Name = "Hecatomb Harness",
            Level = 73,
            Id = 14378,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 50,
                HP = 16,
                STR = 12,
                Accuracy = 10,
                Haste = -13,
            }
        },
        HeliosJacket = {
            Name = "Helios Jacket",
            Level = 75,
            Id = 26895,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 43,
                HP = 15,
                MP = 15,
                INT = 10,
                MND = 10,
                CHR = 10,
                Haste = 1,
                Enmity = -8,
            }
        },
        HerculeanVest = {
            Name = "Herculean Vest",
            Level = 75,
            Id = 25718,
            Jobs = {"RNG"},
            Type = "Body",
            Stats = {
                DEF = 48,
                HP = 45,
                DEX = 6,
                AGI = 6,
                RangedAccuracy = 12,
                RangedAttack = 12,
            }
        },
        HlrBliaut_1 = {
            Name = "Hlr. Bliaut +1",
            Level = 74,
            Id = 14475,
            Jobs = {"WHM"},
            Type = "Body",
            Stats = {
                DEF = 40,
                MP = 35,
                Enmity = -4,
                HMP = 5,
            }
        },
        HmnDomaru_1 = {
            Name = "Hmn. Domaru +1",
            Level = 70,
            Id = 14439,
            Jobs = {"SAM"},
            Type = "Body",
            Stats = {
                DEF = 48,
                STR = 9,
                StoreTP = 7,
            }
        },
        HolyBreastplate = {
            Name = "Holy Breastplate",
            Level = 40,
            Id = 13812,
            Jobs = {"WHM"},
            Type = "Body",
            Stats = {
                DEF = 45,
            }
        },
        HomamCorazza = {
            Name = "Homam Corazza",
            Level = 75,
            Id = 14488,
            Jobs = {"THF", "PLD", "DRK", "DRG", "BLU", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 49,
                HP = 28,
                MP = 28,
                Accuracy = 15,
                TripleAttack = 1,
            }
        },
        HtrJerkin_1 = {
            Name = "Htr. Jerkin +1",
            Level = 74,
            Id = 14483,
            Jobs = {"RNG"},
            Type = "Body",
            Stats = {
                DEF = 45,
                HP = 20,
                VIT = 4,
                AGI = 4,
                RangedAccuracy = 10,
            }
        },
        IgqiraWeskit = {
            Name = "Igqira Weskit",
            Level = 73,
            Id = 14420,
            Jobs = {"BLM"},
            Type = "Body",
            Stats = {
                DEF = 35,
                MagicAttackBonus = 6,
                ConserveMP = 2,
            }
        },
        IkengasVest = {
            Name = "Ikengas Vest",
            Level = 75,
            Id = 23762,
            Jobs = {"COR"},
            Type = "Body",
            Stats = {
                DEF = 48,
                HP = 35,
                DEX = 5,
                AGI = 5,
                RangedAccuracy = 12,
                RangedAttack = 12,
                MagicAccuracy = 5,
            }
        },
        IllusionistsGarb = {
            Name = "Illusionists Garb",
            Level = 30,
            Id = 10467,
            Jobs = {"WHM", "BLM", "RDM", "SCH", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 19,
                MP = 15,
                INT = 2,
                MND = 2,
                MagicAttackBonus = 4,
            }
        },
        IronRamHauberk = {
            Name = "Iron Ram Hauberk",
            Level = 68,
            Id = 14588,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Body",
            Stats = {
                DEF = 50,
                HP = 32,
                MagicDefenseBonus = 5,
                Enmity = 6,
            }
        },
        JujitsuGi = {
            Name = "Jujitsu Gi",
            Level = 40,
            Id = 13728,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 27,
                Accuracy = 4,
            }
        },
        JumalikMail = {
            Name = "Jumalik Mail",
            Level = 75,
            Id = 26972,
            Jobs = {"WAR", "PLD", "DRK", "BST", "DRG", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 58,
                HP = 35,
                MP = 25,
                DEX = 8,
                Attack = 20,
                Haste = 1,
                CurePotency = 9,
            }
        },
        KaiserCuirass = {
            Name = "Kaiser Cuirass",
            Level = 73,
            Id = 14370,
            Jobs = {"WAR", "PLD"},
            Type = "Body",
            Stats = {
                DEF = 66,
                HP = 62,
                STR = -11,
                DEX = -11,
                VIT = 21,
                CHR = 21,
            }
        },
        Kampfbrust = {
            Name = "Kampfbrust",
            Level = 29,
            Id = 14435,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Body",
            Stats = {
                DEF = 25,
                AGI = 3,
            }
        },
        Kenpogi = {
            Name = "Kenpogi",
            Level = 8,
            Id = 12584,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 8,
            }
        },
        Kenpogi_1 = {
            Name = "Kenpogi +1",
            Level = 8,
            Id = 12668,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 9,
                DEX = 1,
            }
        },
        KhimairaJacket = {
            Name = "Khimaira Jacket",
            Level = 71,
            Id = 14566,
            Jobs = {"BST"},
            Type = "Body",
            Stats = {
                DEF = 45,
                HP = 21,
                MP = 21,
                DEX = 4,
                VIT = 4,
                CHR = 4,
                Enmity = -2,
            }
        },
        KingsCuirass = {
            Name = "Kings Cuirass",
            Level = 70,
            Id = 13758,
            Jobs = {"PLD"},
            Type = "Body",
            Stats = {
                DEF = 50,
                VIT = 6,
                CHR = 1,
            }
        },
        KirinsOsode = {
            Name = "Kirins Osode",
            Level = 75,
            Id = 12562,
            Jobs = {"WAR", "MNK", "BST", "BRD", "RNG", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 52,
                MP = 30,
                STR = 10,
                DEX = 10,
                VIT = 10,
                AGI = 10,
                INT = 10,
                MND = 10,
                CHR = 10,
            }
        },
        KoenigCuirass = {
            Name = "Koenig Cuirass",
            Level = 73,
            Id = 12549,
            Jobs = {"WAR", "PLD"},
            Type = "Body",
            Stats = {
                DEF = 65,
                HP = 60,
                STR = -10,
                DEX = -10,
                VIT = 20,
                CHR = 20,
            }
        },
        KogChainmail_1 = {
            Name = "Kog. Chainmail +1",
            Level = 75,
            Id = 14512,
            Jobs = {"NIN"},
            Type = "Body",
            Stats = {
                DEF = 47,
                Accuracy = 12,
                Attack = 16,
                RangedAccuracy = 10,
                RangedAttack = 10,
            }
        },
        Kyudogi = {
            Name = "Kyudogi",
            Level = 70,
            Id = 14539,
            Jobs = {"RNG", "SAM"},
            Type = "Body",
            Stats = {
                DEF = 42,
                RangedAccuracy = 7,
                RangedAttack = 7,
                Evasion = 7,
            }
        },
        LeatherVest = {
            Name = "Leather Vest",
            Level = 7,
            Id = 12568,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 7,
            }
        },
        LeatherVest_1 = {
            Name = "Leather Vest +1",
            Level = 7,
            Id = 12599,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 9,
            }
        },
        LinenRobe = {
            Name = "Linen Robe",
            Level = 12,
            Id = 12601,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 10,
            }
        },
        LinenRobe_1 = {
            Name = "Linen Robe +1",
            Level = 12,
            Id = 12626,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 11,
            }
        },
        LordsCuirass = {
            Name = "Lords Cuirass",
            Level = 70,
            Id = 13757,
            Jobs = {"PLD"},
            Type = "Body",
            Stats = {
                DEF = 49,
                VIT = 5,
                CHR = 1,
            }
        },
        MagusJubbah = {
            Name = "Magus Jubbah",
            Level = 58,
            Id = 14521,
            Jobs = {"BLU"},
            Type = "Body",
            Stats = {
                DEF = 44,
                HP = 12,
                MP = 12,
                STR = 3,
                DEX = 3,
            }
        },
        MagusJubbah_1 = {
            Name = "Magus Jubbah +1",
            Level = 74,
            Id = 11291,
            Jobs = {"BLU"},
            Type = "Body",
            Stats = {
                DEF = 45,
                HP = 17,
                MP = 17,
                STR = 5,
                DEX = 5,
                HMP = 1,
                HHP = 1,
            }
        },
        MalignanceTabard = {
            Name = "Malignance Tabard",
            Level = 75,
            Id = 23733,
            Jobs = {"RDM"},
            Type = "Body",
            Stats = {
                DEF = 48,
                MP = 50,
                Accuracy = 12,
                Attack = 12,
            }
        },
        MarduksJubbah = {
            Name = "Marduks Jubbah",
            Level = 75,
            Id = 14558,
            Jobs = {"WHM", "BRD", "SMN", "SCH"},
            Type = "Body",
            Stats = {
                DEF = 40,
                HPP = 3,
                MPP = 3,
                MND = 12,
                CHR = 12,
                Refresh = 1,
                FastCast = 5,
            }
        },
        MelCyclas_1 = {
            Name = "Mel. Cyclas +1",
            Level = 75,
            Id = 14501,
            Jobs = {"MNK"},
            Type = "Body",
            Stats = {
                DEF = 45,
                HPP = 6,
                VIT = 6,
                Regen = 1,
                HHP = 6,
            }
        },
        MerlinicJubbah = {
            Name = "Merlinic Jubbah",
            Level = 75,
            Id = 25719,
            Jobs = {"SCH"},
            Type = "Body",
            Stats = {
                DEF = 41,
                HP = 30,
                MP = 30,
                INT = 5,
                MND = 5,
                MagicAccuracy = 10,
            }
        },
        MinstrelsCoat = {
            Name = "Minstrels Coat",
            Level = 62,
            Id = 13804,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 40,
                HP = 15,
                Evasion = 3,
            }
        },
        MirageJubbah_1 = {
            Name = "Mirage Jubbah +1",
            Level = 75,
            Id = 11293,
            Jobs = {"BLU"},
            Type = "Body",
            Stats = {
                DEF = 46,
                MP = 20,
                Accuracy = 12,
                Enmity = -3,
                Refresh = 1,
            }
        },
        MorrigansRobe = {
            Name = "Morrigans Robe",
            Level = 75,
            Id = 14562,
            Jobs = {"BLM", "RDM", "BLU", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 38,
                STR = 8,
                INT = 8,
                MND = 8,
                Accuracy = 5,
                Attack = 5,
                MagicAttackBonus = 5,
                Refresh = 1,
            }
        },
        MpacasDoublet = {
            Name = "Mpacas Doublet",
            Level = 75,
            Id = 23765,
            Jobs = {"NIN"},
            Type = "Body",
            Stats = {
                DEF = 49,
                HP = 50,
                Accuracy = 10,
                Enmity = 5,
            }
        },
        MrcCptDoublet = {
            Name = "Mrc.Cpt. Doublet",
            Level = 30,
            Id = 12598,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 20,
                DEX = 1,
                AGI = 1,
            }
        },
        MstJackcoat_1 = {
            Name = "Mst. Jackcoat +1",
            Level = 75,
            Id = 14508,
            Jobs = {"BST"},
            Type = "Body",
            Stats = {
                DEF = 50,
                HP = 21,
                INT = 7,
            }
        },
        MtlBreastplate = {
            Name = "Mtl. Breastplate",
            Level = 49,
            Id = 12545,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Body",
            Stats = {
                DEF = 39,
            }
        },
        MtlBrstplate_1 = {
            Name = "Mtl. Brstplate +1",
            Level = 49,
            Id = 13737,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Body",
            Stats = {
                DEF = 40,
                INT = 1,
            }
        },
        MynDomaru_1 = {
            Name = "Myn. Domaru +1",
            Level = 74,
            Id = 14484,
            Jobs = {"SAM"},
            Type = "Body",
            Stats = {
                DEF = 50,
                HP = 10,
                STR = 6,
                VIT = 6,
                Accuracy = 12,
            }
        },
        NagaSamue = {
            Name = "Naga Samue",
            Level = 75,
            Id = 26949,
            Jobs = {"MNK"},
            Type = "Body",
            Stats = {
                DEF = 47,
                HPP = 5,
                Accuracy = 15,
                Attack = 15,
                Enmity = 5,
                Regen = 1,
            }
        },
        NashiraManteel = {
            Name = "Nashira Manteel",
            Level = 75,
            Id = 14489,
            Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 41,
                MagicAccuracy = 5,
                Haste = 3,
            }
        },
        NinChainmail_1 = {
            Name = "Nin. Chainmail +1",
            Level = 74,
            Id = 14485,
            Jobs = {"NIN"},
            Type = "Body",
            Stats = {
                DEF = 46,
                HP = 15,
                DEX = 5,
                VIT = 5,
                DualWield = 5,
            }
        },
        NoctDoublet = {
            Name = "Noct Doublet",
            Level = 30,
            Id = 14422,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Body",
            Stats = {
                DEF = 18,
                RangedAccuracy = 2,
            }
        },
        NoctDoublet_1 = {
            Name = "Noct Doublet +1",
            Level = 30,
            Id = 14434,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Body",
            Stats = {
                DEF = 19,
                RangedAccuracy = 3,
            }
        },
        PantinTobe_1 = {
            Name = "Pantin Tobe +1",
            Level = 75,
            Id = 11299,
            Jobs = {"PUP"},
            Type = "Body",
            Stats = {
                DEF = 46,
                HP = 15,
                Accuracy = 12,
                SubtleBlow = 5,
            }
        },
        PlainTunica = {
            Name = "Plain Tunica",
            Level = 30,
            Id = 26533,
            Jobs = {"All"},
            Type = "Body",
            Stats = {
                DEF = 18,
            }
        },
        Plastron = {
            Name = "Plastron",
            Level = 71,
            Id = 14382,
            Jobs = {"DRK"},
            Type = "Body",
            Stats = {
                DEF = 40,
                STR = 8,
                Attack = 16,
                Refresh = 1,
            }
        },
        Plastron_1 = {
            Name = "Plastron +1",
            Level = 71,
            Id = 14383,
            Jobs = {"DRK"},
            Type = "Body",
            Stats = {
                DEF = 41,
                STR = 9,
                Attack = 18,
                Refresh = 1,
            }
        },
        PowerGi = {
            Name = "Power Gi",
            Level = 13,
            Id = 12590,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 12,
                STR = 1,
            }
        },
        PupTobe = {
            Name = "Pup. Tobe",
            Level = 58,
            Id = 14523,
            Jobs = {"PUP"},
            Type = "Body",
            Stats = {
                DEF = 36,
                HP = 12,
                Accuracy = 5,
            }
        },
        PupTobe_1 = {
            Name = "Pup. Tobe +1",
            Level = 74,
            Id = 11297,
            Jobs = {"PUP"},
            Type = "Body",
            Stats = {
                DEF = 37,
                HP = 17,
                Accuracy = 5,
                Attack = 5,
            }
        },
        PursuersDoublet = {
            Name = "Pursuers Doublet",
            Level = 75,
            Id = 26951,
            Jobs = {"BRD"},
            Type = "Body",
            Stats = {
                DEF = 48,
                HP = 30,
                MP = 30,
                DEX = 5,
                AGI = 5,
                Accuracy = 12,
                Attack = 12,
            }
        },
        RaptorJerkin = {
            Name = "Raptor Jerkin",
            Level = 48,
            Id = 12572,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 35,
            }
        },
        RawhideVest = {
            Name = "Rawhide Vest",
            Level = 75,
            Id = 26950,
            Jobs = {"DNC"},
            Type = "Body",
            Stats = {
                DEF = 42,
                HP = 30,
                DEX = 10,
                AGI = 10,
                Attack = 10,
                Haste = 5,
            }
        },
        ReikiOsode = {
            Name = "Reiki Osode",
            Level = 75,
            Id = 25702,
            Jobs = {"WAR", "MNK", "BST", "BRD", "RNG", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 54,
                MP = 50,
                STR = 12,
                DEX = 12,
                VIT = 12,
                AGI = 12,
                INT = 12,
                MND = 12,
                CHR = 12,
                DoubleAttack = 4,
            }
        },
        ReverendMail = {
            Name = "Reverend Mail",
            Level = 75,
            Id = 14469,
            Jobs = {"WHM"},
            Type = "Body",
            Stats = {
                DEF = 50,
                MP = -25,
                MND = -5,
                Accuracy = 10,
                Evasion = 10,
            }
        },
        Robe = {
            Name = "Robe",
            Level = 1,
            Id = 12600,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 3,
            }
        },
        Robe_1 = {
            Name = "Robe +1",
            Level = 1,
            Id = 12615,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 4,
            }
        },
        RogVest_1 = {
            Name = "Rog. Vest +1",
            Level = 74,
            Id = 14478,
            Jobs = {"THF"},
            Type = "Body",
            Stats = {
                DEF = 45,
                HP = 20,
                STR = 6,
                Accuracy = 10,
            }
        },
        RoyalCloak = {
            Name = "Royal Cloak",
            Level = 59,
            Id = 13749,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 47,
                MP = 20,
                MPP = 1,
                Evasion = -10,
                Refresh = 1,
            }
        },
        RubiousTunic = {
            Name = "Rubious Tunic",
            Level = 30,
            Id = 14432,
            Jobs = {"MNK", "RDM", "PLD", "BRD", "RNG", "BLU", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 20,
            }
        },
        RuneistCoat = {
            Name = "Runeist Coat",
            Level = 75,
            Id = 27927,
            Jobs = {"RUN"},
            Type = "Body",
            Stats = {
                DEF = 50,
                HP = 20,
                MP = 20,
                STR = 5,
                VIT = 5,
            }
        },
        RylFtmTunic = {
            Name = "Ryl.Ftm. Tunic",
            Level = 10,
            Id = 13718,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 12,
                AGI = 1,
                INT = 1,
            }
        },
        RylFtmVest = {
            Name = "Ryl.Ftm. Vest",
            Level = 10,
            Id = 12630,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 10,
            }
        },
        RyuoDomaru = {
            Name = "Ryuo Domaru",
            Level = 75,
            Id = 25684,
            Jobs = {"SAM"},
            Type = "Body",
            Stats = {
                DEF = 53,
                HP = 50,
                STR = 5,
                VIT = 5,
                Accuracy = 12,
                Attack = 12,
            }
        },
        SakpatasPlate = {
            Name = "Sakpatas Plate",
            Level = 75,
            Id = 23764,
            Jobs = {"WAR"},
            Type = "Body",
            Stats = {
                DEF = 53,
                HP = 50,
                HPP = 5,
                Accuracy = 12,
                Attack = 12,
                Enmity = 5,
            }
        },
        SalutaryRobe = {
            Name = "Salutary Robe",
            Level = 40,
            Id = 11340,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 21,
                HP = 4,
                MP = 4,
                HMP = 1,
            }
        },
        SalutaryRobe_1 = {
            Name = "Salutary Robe +1",
            Level = 40,
            Id = 11348,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 22,
                HP = 5,
                MP = 5,
                HMP = 2,
            }
        },
        SamnuhaCoat = {
            Name = "Samnuha Coat",
            Level = 75,
            Id = 26973,
            Jobs = {"MNK", "THF", "RNG", "NIN", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 45,
                HP = 40,
                DEX = 5,
                AGI = 5,
                Accuracy = 10,
                MagicAttackBonus = 10,
                Evasion = 5,
                Haste = 2,
            }
        },
        SaoDomaru_1 = {
            Name = "Sao. Domaru +1",
            Level = 75,
            Id = 14511,
            Jobs = {"SAM"},
            Type = "Body",
            Stats = {
                DEF = 51,
                HP = 34,
                VIT = 7,
                StoreTP = 5,
                Enmity = 1,
            }
        },
        ScaleMail = {
            Name = "Scale Mail",
            Level = 10,
            Id = 12560,
            Jobs = {"WAR", "RDM", "PLD", "DRK", "BST", "RNG", "SAM", "DRG", "BLU", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 11,
            }
        },
        ScholarsGown = {
            Name = "Scholars Gown",
            Level = 58,
            Id = 14580,
            Jobs = {"SCH"},
            Type = "Body",
            Stats = {
                DEF = 38,
                MP = 13,
                INT = 1,
                MND = 1,
            }
        },
        ScholarsGown_1 = {
            Name = "Scholars Gown +1",
            Level = 74,
            Id = 11304,
            Jobs = {"SCH"},
            Type = "Body",
            Stats = {
                DEF = 39,
                MP = 18,
                INT = 3,
                MND = 3,
                HMP = 5,
            }
        },
        ScorpionHarness = {
            Name = "Scorpion Harness",
            Level = 57,
            Id = 12579,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 40,
                HP = 15,
                Accuracy = 10,
                Evasion = 10,
            }
        },
        ScpHarness_1 = {
            Name = "Scp. Harness +1",
            Level = 57,
            Id = 13734,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 41,
                HP = 20,
                Accuracy = 12,
                Evasion = 12,
            }
        },
        SctJerkin_1 = {
            Name = "Sct. Jerkin +1",
            Level = 75,
            Id = 14510,
            Jobs = {"RNG"},
            Type = "Body",
            Stats = {
                DEF = 46,
                HP = 23,
                DEX = 5,
                Enmity = -4,
            }
        },
        SeersTunic = {
            Name = "Seers Tunic",
            Level = 29,
            Id = 14424,
            Jobs = {"WHM", "BLM", "SMN", "PUP", "SCH", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 18,
                MP = 8,
                HMP = 1,
            }
        },
        SeersTunic_1 = {
            Name = "Seers Tunic +1",
            Level = 29,
            Id = 14427,
            Jobs = {"WHM", "BLM", "SMN", "PUP", "SCH", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 19,
                MP = 9,
                HMP = 1,
            }
        },
        ShadeHarness = {
            Name = "Shade Harness",
            Level = 25,
            Id = 14426,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 19,
            }
        },
        ShadeHarness_1 = {
            Name = "Shade Harness +1",
            Level = 25,
            Id = 14433,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 20,
                Evasion = 1,
            }
        },
        ShadowBrstplate = {
            Name = "Shadow Brstplate",
            Level = 75,
            Id = 14573,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Body",
            Stats = {
                DEF = 55,
                STR = 10,
                DEX = -3,
                VIT = 10,
                AGI = -3,
                INT = -3,
                MND = -3,
                CHR = -3,
                Accuracy = 5,
                Attack = 25,
                Regen = 2,
            }
        },
        ShadowCoat = {
            Name = "Shadow Coat",
            Level = 75,
            Id = 14575,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 38,
                MagicAccuracy = 10,
                Enmity = -4,
            }
        },
        ShadowLordShirt = {
            Name = "Shadow Lord Shirt",
            Level = 1,
            Id = 26517,
            Jobs = {"All"},
            Type = "Body",
            Stats = {
                DEF = 1,
            }
        },
        ShairManteel = {
            Name = "Shair Manteel",
            Level = 72,
            Id = 14414,
            Jobs = {"BRD"},
            Type = "Body",
            Stats = {
                DEF = 42,
                MP = 14,
                CHR = 7,
                Haste = 2,
            }
        },
        ShamansCloak = {
            Name = "Shamans Cloak",
            Level = 56,
            Id = 13803,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 43,
                MP = 25,
                INT = 4,
            }
        },
        SheikhManteel = {
            Name = "Sheikh Manteel",
            Level = 72,
            Id = 14415,
            Jobs = {"BRD"},
            Type = "Body",
            Stats = {
                DEF = 43,
                MP = 16,
                CHR = 8,
                Haste = 3,
            }
        },
        ShinobiGi = {
            Name = "Shinobi Gi",
            Level = 49,
            Id = 12588,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 33,
            }
        },
        ShinobiGi_1 = {
            Name = "Shinobi Gi +1",
            Level = 49,
            Id = 13733,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 34,
                Evasion = 3,
            }
        },
        ShuraTogi = {
            Name = "Shura Togi",
            Level = 73,
            Id = 14387,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 40,
                HP = -50,
                Accuracy = 10,
                Attack = 20,
            }
        },
        ShuraTogi_1 = {
            Name = "Shura Togi +1",
            Level = 73,
            Id = 14388,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Body",
            Stats = {
                DEF = 41,
                HP = -55,
                Accuracy = 11,
                Attack = 22,
            }
        },
        SkadisCuirie = {
            Name = "Skadis Cuirie",
            Level = 75,
            Id = 14550,
            Jobs = {"THF", "BST", "RNG", "COR", "DNC"},
            Type = "Body",
            Stats = {
                DEF = 40,
                DEX = 8,
                AGI = 8,
                CHR = 8,
                Accuracy = 10,
                Attack = 5,
                RangedAccuracy = 10,
                RangedAttack = 5,
                Evasion = -10,
            }
        },
        SmnDoublet_1 = {
            Name = "Smn. Doublet +1",
            Level = 75,
            Id = 14514,
            Jobs = {"SMN"},
            Type = "Body",
            Stats = {
                DEF = 39,
                MP = 20,
            }
        },
        SoilGi = {
            Name = "Soil Gi",
            Level = 29,
            Id = 12586,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Body",
            Stats = {
                DEF = 20,
            }
        },
        SoilGi_1 = {
            Name = "Soil Gi +1",
            Level = 29,
            Id = 12671,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Body",
            Stats = {
                DEF = 21,
            }
        },
        SolidMail = {
            Name = "Solid Mail",
            Level = 10,
            Id = 12661,
            Jobs = {"WAR", "RDM", "PLD", "DRK", "BST", "RNG", "SAM", "DRG", "BLU", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 12,
            }
        },
        SorcerersCoat = {
            Name = "Sorcerers Coat",
            Level = 74,
            Id = 15090,
            Jobs = {"BLM"},
            Type = "Body",
            Stats = {
                DEF = 41,
                MP = 12,
                Enmity = -2,
                Refresh = 1,
            }
        },
        SrcCoat_1 = {
            Name = "Src. Coat +1",
            Level = 75,
            Id = 14503,
            Jobs = {"BLM"},
            Type = "Body",
            Stats = {
                DEF = 42,
                HP = 12,
                MP = 12,
                Enmity = -2,
                Refresh = 1,
            }
        },
        SteamScaleMail = {
            Name = "Steam Scale Mail",
            Level = 27,
            Id = 12567,
            Jobs = {"WAR", "RDM", "PLD", "DRK", "BST", "RNG", "SAM", "DRG", "BLU", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 23,
            }
        },
        StoutJacket = {
            Name = "Stout Jacket",
            Level = 71,
            Id = 14567,
            Jobs = {"BST"},
            Type = "Body",
            Stats = {
                DEF = 46,
                HP = 22,
                MP = 22,
                DEX = 5,
                VIT = 5,
                CHR = 5,
                Enmity = -3,
            }
        },
        TaeonTabard = {
            Name = "Taeon Tabard",
            Level = 75,
            Id = 26893,
            Jobs = {"MNK", "THF", "BST", "RNG", "NIN", "COR", "PUP", "DNC"},
            Type = "Body",
            Stats = {
                DEF = 47,
                HP = 15,
                MP = 15,
                DEX = 10,
                AGI = 10,
                Evasion = 8,
                Haste = 1,
                FastCast = 3,
            }
        },
        TartarusPlatemail = {
            Name = "Tartarus Platemail",
            Level = 75,
            Id = 26944,
            Jobs = {"All"},
            Type = "Body",
            Stats = {
                DEF = 48,
                HP = 10,
                MP = 10,
            }
        },
        ThrkBreastplate = {
            Name = "Thrk. Breastplate",
            Level = 61,
            Id = 11343,
            Jobs = {"DRG"},
            Type = "Body",
            Stats = {
                DEF = 39,
                STR = 3,
                DEX = 3,
                AGI = -3,
                Accuracy = 7,
                Attack = 7,
            }
        },
        ThurandautTabard = {
            Name = "Thurandaut Tabard",
            Level = 75,
            Id = 27924,
            Jobs = {"PUP"},
            Type = "Body",
            Stats = {
                DEF = 48,
                HP = 50,
                STR = 10,
                DEX = 10,
                DoubleAttack = 3,
            }
        },
        TidalTalisman = {
            Name = "Tidal Talisman",
            Level = 1,
            Id = 11290,
            Jobs = {"All"},
            Type = "Body",
            Stats = {
                DEF = 2,
            }
        },
        TplCyclas_1 = {
            Name = "Tpl. Cyclas +1",
            Level = 74,
            Id = 14474,
            Jobs = {"MNK"},
            Type = "Body",
            Stats = {
                DEF = 44,
                HP = 20,
                STR = 6,
                VIT = 6,
                Accuracy = 5,
            }
        },
        UcnHarness_1 = {
            Name = "Ucn. Harness +1",
            Level = 74,
            Id = 14449,
            Jobs = {"WAR"},
            Type = "Body",
            Stats = {
                DEF = 59,
                HP = 52,
                Regen = 1,
            }
        },
        UnicornHarness = {
            Name = "Unicorn Harness",
            Level = 74,
            Id = 14448,
            Jobs = {"WAR"},
            Type = "Body",
            Stats = {
                DEF = 56,
                HP = 48,
                Regen = 1,
            }
        },
        UsukaneHaramaki = {
            Name = "Usukane Haramaki",
            Level = 75,
            Id = 14554,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Body",
            Stats = {
                DEF = 40,
                STR = 8,
                DEX = 8,
                INT = 8,
                Accuracy = 12,
                Evasion = 12,
                StoreTP = 6,
            }
        },
        ValkBreastplate = {
            Name = "Valk. Breastplate",
            Level = 75,
            Id = 14574,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Body",
            Stats = {
                DEF = 56,
                STR = 11,
                DEX = -4,
                VIT = 11,
                AGI = -4,
                INT = -4,
                MND = -4,
                CHR = -4,
                Accuracy = 6,
                Attack = 26,
                Regen = 2,
            }
        },
        ValkyriesCoat = {
            Name = "Valkyries Coat",
            Level = 75,
            Id = 14576,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Body",
            Stats = {
                DEF = 39,
                MagicAccuracy = 11,
                Enmity = -5,
            }
        },
        ValorousMail = {
            Name = "Valorous Mail",
            Level = 75,
            Id = 25717,
            Jobs = {"BST"},
            Type = "Body",
            Stats = {
                DEF = 52,
                HP = 40,
                Accuracy = 12,
                Attack = 12,
            }
        },
        VanyaRobe = {
            Name = "Vanya Robe",
            Level = 75,
            Id = 26953,
            Jobs = {"BLM"},
            Type = "Body",
            Stats = {
                DEF = 44,
                MP = 30,
                INT = 5,
                MND = 5,
                MagicAccuracy = 5,
                MagicAttackBonus = 5,
            }
        },
        VermillionCloak = {
            Name = "Vermillion Cloak",
            Level = 59,
            Id = 13748,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 46,
                MP = 10,
                MPP = 1,
                Evasion = -10,
                Refresh = 1,
            }
        },
        VlrSurcoat_1 = {
            Name = "Vlr. Surcoat +1",
            Level = 75,
            Id = 14506,
            Jobs = {"PLD"},
            Type = "Body",
            Stats = {
                DEF = 56,
                HP = 30,
                DEX = 3,
                Enmity = 5,
            }
        },
        WarLorica_1 = {
            Name = "War. Lorica +1",
            Level = 75,
            Id = 14500,
            Jobs = {"WAR"},
            Type = "Body",
            Stats = {
                DEF = 51,
                HP = 30,
                Attack = 12,
                Enmity = 4,
            }
        },
        WarlocksTabard = {
            Name = "Warlocks Tabard",
            Level = 58,
            Id = 12642,
            Jobs = {"RDM"},
            Type = "Body",
            Stats = {
                DEF = 44,
                MP = 14,
                CHR = 5,
            }
        },
        WhiteCloak = {
            Name = "White Cloak",
            Level = 50,
            Id = 12611,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 39,
                MND = 2,
            }
        },
        WhiteCloak_1 = {
            Name = "White Cloak +1",
            Level = 50,
            Id = 12651,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Body",
            Stats = {
                DEF = 40,
                MND = 3,
            }
        },
        WizardsCoat = {
            Name = "Wizards Coat",
            Level = 58,
            Id = 12641,
            Jobs = {"BLM"},
            Type = "Body",
            Stats = {
                DEF = 38,
                MP = 16,
                VIT = 5,
                Enmity = -3,
            }
        },
        WlkTabard_1 = {
            Name = "Wlk. Tabard +1",
            Level = 74,
            Id = 14477,
            Jobs = {"RDM"},
            Type = "Body",
            Stats = {
                DEF = 44,
                MP = 34,
                HMP = 5,
            }
        },
        WymMail_1 = {
            Name = "Wym. Mail +1",
            Level = 75,
            Id = 14513,
            Jobs = {"DRG"},
            Type = "Body",
            Stats = {
                DEF = 50,
                HP = 33,
                Haste = 2,
            }
        },
        WyvernMail = {
            Name = "Wyvern Mail",
            Level = 50,
            Id = 14405,
            Jobs = {"DRG"},
            Type = "Body",
            Stats = {
                DEF = 36,
            }
        },
        WzdCoat_1 = {
            Name = "Wzd. Coat +1",
            Level = 74,
            Id = 14476,
            Jobs = {"BLM"},
            Type = "Body",
            Stats = {
                DEF = 38,
                MP = 36,
                Enmity = -5,
                HMP = 5,
            }
        },
        YashaSamue = {
            Name = "Yasha Samue",
            Level = 71,
            Id = 12618,
            Jobs = {"NIN"},
            Type = "Body",
            Stats = {
                DEF = 43,
                INT = 3,
                Enmity = 4,
            }
        },
        YashaSamue_1 = {
            Name = "Yasha Samue +1",
            Level = 71,
            Id = 14442,
            Jobs = {"NIN"},
            Type = "Body",
            Stats = {
                DEF = 44,
                INT = 4,
                Enmity = 5,
            }
        },
        YinyangRobe = {
            Name = "Yinyang Robe",
            Level = 71,
            Id = 14468,
            Jobs = {"SMN"},
            Type = "Body",
            Stats = {
                DEF = 43,
                MP = 25,
                Refresh = 1,
            }
        },
    },
    Hands = {
        AbsGauntlets_1 = {
            Name = "Abs. Gauntlets +1",
            Level = 75,
            Id = 14916,
            Jobs = {"DRK"},
            Type = "Hands",
            Stats = {
                DEF = 21,
                MP = 20,
                DEX = 5,
                INT = 9,
            }
        },
        AcroGauntlets = {
            Name = "Acro Gauntlets",
            Level = 75,
            Id = 27046,
            Jobs = {"WAR", "PLD", "DRK", "SAM", "DRG", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 24,
                HP = 20,
                STR = 6,
                VIT = 6,
                MagicAccuracy = 5,
                MagicDefenseBonus = 1,
                Haste = 1,
                StoreTP = 2,
            }
        },
        AdamanMufflers = {
            Name = "Adaman Mufflers",
            Level = 73,
            Id = 12685,
            Jobs = {"WAR", "DRK", "BST"},
            Type = "Hands",
            Stats = {
                DEF = 22,
                INT = -10,
                Accuracy = 4,
                Attack = 10,
                Evasion = -4,
            }
        },
        AdhemarWristbands = {
            Name = "Adhemar Wristbands",
            Level = 75,
            Id = 27117,
            Jobs = {"THF"},
            Type = "Hands",
            Stats = {
                DEF = 19,
                HP = 25,
                Accuracy = 10,
                Attack = 10,
                Haste = 3,
            }
        },
        AgwusGages = {
            Name = "Agwus Gages",
            Level = 75,
            Id = 23773,
            Jobs = {"BLU"},
            Type = "Hands",
            Stats = {
                DEF = 19,
                MP = 25,
                STR = 5,
                Accuracy = 10,
                Haste = 5,
                DoubleAttack = 2,
            }
        },
        AlucinorMitts = {
            Name = "Alucinor Mitts",
            Level = 74,
            Id = 11924,
            Jobs = {"WAR", "MNK", "RDM", "THF", "DRK", "BRD", "NIN", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 25,
                MP = 25,
                DEX = 5,
                Haste = 3,
            }
        },
        AmalricGages = {
            Name = "Amalric Gages",
            Level = 75,
            Id = 27119,
            Jobs = {"GEO"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                HP = 25,
                VIT = 4,
                CHR = 4,
                Regen = 1,
            }
        },
        AnglersGloves = {
            Name = "Anglers Gloves",
            Level = 15,
            Id = 14071,
            Jobs = {"All"},
            Type = "Hands",
            Stats = {
                DEF = 3,
            }
        },
        AresGauntlets = {
            Name = "Ares Gauntlets",
            Level = 75,
            Id = 14961,
            Jobs = {"WAR", "PLD", "DRK", "DRG", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                HPP = 1,
                MPP = 1,
                STR = 4,
                VIT = 4,
                Accuracy = 10,
            }
        },
        ArguteBracers = {
            Name = "Argute Bracers",
            Level = 71,
            Id = 15040,
            Jobs = {"SCH"},
            Type = "Hands",
            Stats = {
                DEF = 14,
                MP = 20,
                INT = 3,
                MND = 3,
                Enmity = -2,
            }
        },
        ArguteBracers_1 = {
            Name = "Argute Bracers +1",
            Level = 75,
            Id = 15041,
            Jobs = {"SCH"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                MP = 20,
                INT = 4,
                MND = 4,
                Enmity = -3,
            }
        },
        ArmadaMufflers = {
            Name = "Armada Mufflers",
            Level = 73,
            Id = 14816,
            Jobs = {"WAR", "DRK", "BST"},
            Type = "Hands",
            Stats = {
                DEF = 23,
                INT = -11,
                Accuracy = 5,
                Attack = 11,
                Evasion = -5,
            }
        },
        AsnArmlets_1 = {
            Name = "Asn. Armlets +1",
            Level = 75,
            Id = 14914,
            Jobs = {"THF"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                HP = 26,
                CHR = 5,
                Enmity = 4,
            }
        },
        AvestaBangles = {
            Name = "Avesta Bangles",
            Level = 75,
            Id = 11919,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                MagicAccuracy = 6,
            }
        },
        AxemastersGauntlets = {
            Name = "Axemasters Gauntlets",
            Level = 30,
            Id = 10515,
            Jobs = {"WAR", "DRK", "BST", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 12,
                Haste = 2,
            }
        },
        BaguaMitaines = {
            Name = "Bagua Mitaines",
            Level = 75,
            Id = 27016,
            Jobs = {"GEO"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                MP = 21,
                Refresh = 1,
            }
        },
        BaguaMitaines_1 = {
            Name = "Bagua Mitaines +1",
            Level = 75,
            Id = 27017,
            Jobs = {"GEO"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                MP = 26,
                Refresh = 1,
                Regen = 1,
            }
        },
        BattleGloves = {
            Name = "Battle Gloves",
            Level = 14,
            Id = 12799,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 4,
                Accuracy = 3,
                Evasion = 3,
            }
        },
        BeastGloves = {
            Name = "Beast Gloves",
            Level = 54,
            Id = 13969,
            Jobs = {"BST"},
            Type = "Hands",
            Stats = {
                DEF = 12,
                HP = 11,
                DEX = 3,
            }
        },
        BeetleMittens = {
            Name = "Beetle Mittens",
            Level = 21,
            Id = 12711,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 6,
            }
        },
        BeetleMittens_1 = {
            Name = "Beetle Mittens +1",
            Level = 21,
            Id = 12789,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 7,
                Evasion = 1,
            }
        },
        BlackGadlings = {
            Name = "Black Gadlings",
            Level = 71,
            Id = 14010,
            Jobs = {"DRK"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                STR = 4,
                Attack = 8,
            }
        },
        BlackMitts = {
            Name = "Black Mitts",
            Level = 50,
            Id = 12739,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 10,
            }
        },
        BlessedMitts = {
            Name = "Blessed Mitts",
            Level = 70,
            Id = 14875,
            Jobs = {"WHM"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                MP = 15,
                MND = 7,
                Haste = 5,
                Enmity = -3,
            }
        },
        BlessedMitts_1 = {
            Name = "Blessed Mitts +1",
            Level = 70,
            Id = 14877,
            Jobs = {"WHM"},
            Type = "Hands",
            Stats = {
                DEF = 19,
                MP = 18,
                MND = 8,
                Haste = 6,
                Enmity = -4,
            }
        },
        BloodFngGnt = {
            Name = "Blood Fng. Gnt.",
            Level = 73,
            Id = 14059,
            Jobs = {"RDM", "PLD", "DRK", "RNG", "DRG", "BLU", "COR", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 27,
                HP = 22,
                MP = 22,
                RangedAccuracy = 11,
                RangedAttack = 11,
            }
        },
        BrassMittens = {
            Name = "Brass Mittens",
            Level = 11,
            Id = 12705,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 3,
            }
        },
        BrassMittens_1 = {
            Name = "Brass Mittens +1",
            Level = 11,
            Id = 12770,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 4,
            }
        },
        BrdCuffs_1 = {
            Name = "Brd. Cuffs +1",
            Level = 75,
            Id = 14918,
            Jobs = {"BRD"},
            Type = "Hands",
            Stats = {
                DEF = 19,
                HP = 16,
                Evasion = 5,
                Enmity = -4,
            }
        },
        BrictasCuffs = {
            Name = "Brictas Cuffs",
            Level = 74,
            Id = 15057,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                MND = 5,
                CHR = 5,
                MagicAccuracy = 5,
                Enmity = -2,
            }
        },
        BstGloves_1 = {
            Name = "Bst. Gloves +1",
            Level = 74,
            Id = 14898,
            Jobs = {"BST"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                HP = 11,
                DEX = 5,
                CHR = 5,
            }
        },
        BunzisGloves = {
            Name = "Bunzis Gloves",
            Level = 75,
            Id = 23774,
            Jobs = {"WHM"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                MP = 15,
                MagicAccuracy = 6,
                CurePotency = 3,
                ConserveMP = 3,
            }
        },
        CarbuncleMitts = {
            Name = "Carbuncle Mitts",
            Level = 20,
            Id = 14062,
            Jobs = {"SMN"},
            Type = "Hands",
            Stats = {
                DEF = 5,
                MP = 14,
            }
        },
        ChironicGloves = {
            Name = "Chironic Gloves",
            Level = 75,
            Id = 27142,
            Jobs = {"SMN"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                MP = 25,
                VIT = 3,
                MND = 3,
                MagicEvasion = 3,
                MagicDefenseBonus = 3,
                Regen = 1,
            }
        },
        ChlCuffs_1 = {
            Name = "Chl. Cuffs +1",
            Level = 74,
            Id = 14899,
            Jobs = {"BRD"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                HP = 14,
                VIT = 7,
                CHR = 7,
                Enmity = -1,
            }
        },
        ChoralCuffs = {
            Name = "Choral Cuffs",
            Level = 60,
            Id = 13970,
            Jobs = {"BRD"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                HP = 14,
                CHR = 4,
                Enmity = -1,
            }
        },
        ChsGauntlets_1 = {
            Name = "Chs. Gauntlets +1",
            Level = 74,
            Id = 14897,
            Jobs = {"DRK"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                HP = 11,
                MP = 11,
                STR = 6,
                DEX = 6,
                Accuracy = 3,
            }
        },
        ClrMitts_1 = {
            Name = "Clr. Mitts +1",
            Level = 75,
            Id = 14911,
            Jobs = {"WHM"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                HP = 20,
                MP = 20,
                Enmity = -4,
            }
        },
        CommGants_1 = {
            Name = "Comm. Gants +1",
            Level = 75,
            Id = 15029,
            Jobs = {"COR"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                HP = 15,
                AGI = 3,
                RangedAccuracy = 5,
            }
        },
        CorsairsGants_1 = {
            Name = "Corsairs Gants +1",
            Level = 74,
            Id = 15027,
            Jobs = {"COR"},
            Type = "Hands",
            Stats = {
                DEF = 12,
                HP = 15,
                DEX = 5,
                MND = 5,
                Evasion = 3,
            }
        },
        CottonTekko = {
            Name = "Cotton Tekko",
            Level = 18,
            Id = 12713,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Hands",
            Stats = {
                DEF = 5,
            }
        },
        CottonTekko_1 = {
            Name = "Cotton Tekko +1",
            Level = 18,
            Id = 12777,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Hands",
            Stats = {
                DEF = 6,
            }
        },
        CrimsonFngGnt = {
            Name = "Crimson Fng. Gnt.",
            Level = 73,
            Id = 14058,
            Jobs = {"RDM", "PLD", "DRK", "RNG", "DRG", "BLU", "COR", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 26,
                HP = 20,
                MP = 20,
                RangedAccuracy = 10,
                RangedAttack = 10,
            }
        },
        DinoGloves = {
            Name = "Dino Gloves",
            Level = 48,
            Id = 12795,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 13,
            }
        },
        DlsGloves_1 = {
            Name = "Dls. Gloves +1",
            Level = 75,
            Id = 14913,
            Jobs = {"RDM"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                MP = 23,
                INT = 5,
                MagicDefenseBonus = 2,
            }
        },
        DncBangles_1 = {
            Name = "Dnc. Bangles +1",
            Level = 74,
            Id = 15035,
            Jobs = {"DNC"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                HP = 17,
                DEX = 4,
                AGI = 4,
                Attack = 5,
            }
        },
        DragonFGnt_1 = {
            Name = "Dragon F. Gnt. +1",
            Level = 68,
            Id = 13991,
            Jobs = {"DRG"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                HP = 10,
            }
        },
        DragonFngGnt = {
            Name = "Dragon Fng. Gnt.",
            Level = 68,
            Id = 12692,
            Jobs = {"DRG"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                HP = 8,
            }
        },
        DragonMittens = {
            Name = "Dragon Mittens",
            Level = 73,
            Id = 14823,
            Jobs = {"THF"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                AGI = 4,
                Attack = 2,
                Enmity = 2,
                SubtleBlow = 2,
            }
        },
        DragonMittens_1 = {
            Name = "Dragon Mittens +1",
            Level = 73,
            Id = 14824,
            Jobs = {"THF"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                AGI = 5,
                Attack = 3,
                Enmity = 3,
                SubtleBlow = 3,
            }
        },
        DrnFngGnt_1 = {
            Name = "Drn. Fng. Gnt. +1",
            Level = 74,
            Id = 14903,
            Jobs = {"DRG"},
            Type = "Hands",
            Stats = {
                DEF = 19,
                HP = 11,
                STR = 5,
                DEX = 5,
            }
        },
        DuelistsGloves = {
            Name = "Duelists Gloves",
            Level = 72,
            Id = 15106,
            Jobs = {"RDM"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                MP = 18,
                INT = 4,
                MagicDefenseBonus = 2,
            }
        },
        DuxFingerGauntlets = {
            Name = "Dux Finger Gauntlets",
            Level = 70,
            Id = 10316,
            Jobs = {"RUN"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                STR = 4,
                Accuracy = 10,
                Enmity = 4,
            }
        },
        DuxFingerGauntlets_1 = {
            Name = "Dux Finger Gauntlets +1",
            Level = 70,
            Id = 10317,
            Jobs = {"RUN"},
            Type = "Hands",
            Stats = {
                DEF = 21,
                STR = 5,
                Accuracy = 11,
                Enmity = 5,
            }
        },
        Eisenhentzes = {
            Name = "Eisenhentzes",
            Level = 29,
            Id = 14860,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Hands",
            Stats = {
                DEF = 9,
                VIT = 1,
            }
        },
        EtoileBangles_1 = {
            Name = "Etoile Bangles +1",
            Level = 75,
            Id = 15039,
            Jobs = {"DNC"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                HP = 15,
                VIT = 4,
                AGI = 4,
                Attack = 5,
                Evasion = 5,
                Enmity = 3,
            }
        },
        EvkBracers_1 = {
            Name = "Evk. Bracers +1",
            Level = 74,
            Id = 14904,
            Jobs = {"SMN"},
            Type = "Hands",
            Stats = {
                DEF = 11,
                MP = 19,
            }
        },
        FieldGloves = {
            Name = "Field Gloves",
            Level = 1,
            Id = 14817,
            Jobs = {"All"},
            Type = "Hands",
            Stats = {
                DEF = 1,
            }
        },
        FineGloves = {
            Name = "Fine Gloves",
            Level = 17,
            Id = 12785,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 6,
            }
        },
        FloralGauntlets = {
            Name = "Floral Gauntlets",
            Level = 75,
            Id = 27137,
            Jobs = {"THF", "RNG", "NIN", "COR"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                HP = 25,
                STR = 4,
                DEX = 4,
                Haste = 2,
                DualWield = 5,
            }
        },
        FoundersGauntlets = {
            Name = "Founders Gauntlets",
            Level = 75,
            Id = 28049,
            Jobs = {"PLD"},
            Type = "Hands",
            Stats = {
                DEF = 25,
                HP = 20,
                MP = 15,
                VIT = 3,
                MND = 3,
                MagicEvasion = 3,
                MagicDefenseBonus = 3,
                Regen = 1,
            }
        },
        FtrMufflers_1 = {
            Name = "Ftr. Mufflers +1",
            Level = 74,
            Id = 14890,
            Jobs = {"WAR"},
            Type = "Hands",
            Stats = {
                DEF = 22,
                HP = 13,
                STR = 6,
                Enmity = 3,
            }
        },
        FutharkMitons = {
            Name = "Futhark Mitons",
            Level = 75,
            Id = 27018,
            Jobs = {"RUN"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                HP = 17,
                DEX = 7,
            }
        },
        FutharkMitons_1 = {
            Name = "Futhark Mitons +1",
            Level = 75,
            Id = 27019,
            Jobs = {"RUN"},
            Type = "Hands",
            Stats = {
                DEF = 21,
                HP = 24,
                DEX = 8,
            }
        },
        GarishMitts = {
            Name = "Garish Mitts",
            Level = 30,
            Id = 14857,
            Jobs = {"MNK", "RDM", "PLD", "BRD", "RNG", "BLU", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 9,
            }
        },
        GarrisonGloves = {
            Name = "Garrison Gloves",
            Level = 20,
            Id = 14841,
            Jobs = {"All"},
            Type = "Hands",
            Stats = {
                DEF = 4,
                VIT = 1,
                INT = 1,
            }
        },
        GarrisonGloves_1 = {
            Name = "Garrison Gloves +1",
            Level = 20,
            Id = 25994,
            Jobs = {"All"},
            Type = "Hands",
            Stats = {
                DEF = 6,
                MP = 5,
                VIT = 2,
                INT = 2,
                HHP = 2,
            }
        },
        GenieManillas = {
            Name = "Genie Manillas",
            Level = 73,
            Id = 14853,
            Jobs = {"BLM"},
            Type = "Hands",
            Stats = {
                DEF = 12,
                MagicAttackBonus = 3,
            }
        },
        GeomancyMitaines = {
            Name = "Geomancy Mitaines",
            Level = 75,
            Id = 28066,
            Jobs = {"GEO"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                MP = 16,
                INT = 3,
                MND = 4,
            }
        },
        GletisGauntlets = {
            Name = "Gletis Gauntlets",
            Level = 75,
            Id = 23770,
            Jobs = {"DRK"},
            Type = "Hands",
            Stats = {
                DEF = 23,
                HP = 30,
                AGI = 5,
                Haste = 3,
                StoreTP = 3,
                Enmity = 3,
            }
        },
        Gloves = {
            Name = "Gloves",
            Level = 11,
            Id = 12720,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 3,
            }
        },
        Gloves_1 = {
            Name = "Gloves +1",
            Level = 11,
            Id = 12773,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 4,
            }
        },
        GltGauntlets_1 = {
            Name = "Glt. Gauntlets +1",
            Level = 74,
            Id = 14896,
            Jobs = {"PLD"},
            Type = "Hands",
            Stats = {
                DEF = 22,
                HP = 11,
                DEX = 6,
                VIT = 3,
                Enmity = 2,
            }
        },
        GuerillaGloves = {
            Name = "Guerilla Gloves",
            Level = 13,
            Id = 15052,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 3,
                HP = 4,
                Accuracy = 2,
            }
        },
        HachimanKote = {
            Name = "Hachiman Kote",
            Level = 70,
            Id = 14876,
            Jobs = {"SAM"},
            Type = "Hands",
            Stats = {
                DEF = 19,
                STR = 4,
                StoreTP = 8,
            }
        },
        HachimanKote_1 = {
            Name = "Hachiman Kote +1",
            Level = 70,
            Id = 14878,
            Jobs = {"SAM"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                STR = 5,
                StoreTP = 9,
            }
        },
        HctMittens_1 = {
            Name = "Hct. Mittens +1",
            Level = 73,
            Id = 14077,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 26,
                HP = 10,
                STR = 8,
                DEX = 5,
                Haste = -7,
            }
        },
        HecatombMittens = {
            Name = "Hecatomb Mittens",
            Level = 73,
            Id = 14076,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 25,
                HP = 8,
                STR = 7,
                DEX = 4,
                Haste = -5,
            }
        },
        HeliosGloves = {
            Name = "Helios Gloves",
            Level = 75,
            Id = 27049,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 19,
                MP = 20,
                MND = 6,
                CHR = 6,
                Attack = 5,
                MagicEvasion = 2,
                Haste = 1,
            }
        },
        HerculeanGloves = {
            Name = "Herculean Gloves",
            Level = 75,
            Id = 27140,
            Jobs = {"RNG"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                HP = 20,
                VIT = 3,
                MND = 3,
                MagicDefenseBonus = 3,
                Haste = 3,
                Regen = 1,
            }
        },
        HlrMitts_1 = {
            Name = "Hlr. Mitts +1",
            Level = 74,
            Id = 14892,
            Jobs = {"WHM"},
            Type = "Hands",
            Stats = {
                DEF = 14,
                MP = 15,
                STR = 7,
                MND = 7,
                Enmity = -4,
            }
        },
        HomamManopolas = {
            Name = "Homam Manopolas",
            Level = 75,
            Id = 14905,
            Jobs = {"THF", "PLD", "DRK", "DRG", "BLU", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                HP = 20,
                MP = 20,
                Accuracy = 4,
                Haste = 3,
                Enmity = 3,
            }
        },
        HoshikazuTekko = {
            Name = "Hoshikazu Tekko",
            Level = 15,
            Id = 14970,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Hands",
            Stats = {
                DEF = 4,
                Accuracy = 1,
            }
        },
        HtrBracers_1 = {
            Name = "Htr. Bracers +1",
            Level = 74,
            Id = 14900,
            Jobs = {"RNG"},
            Type = "Hands",
            Stats = {
                DEF = 14,
                HP = 10,
                DEX = 6,
                AGI = 6,
            }
        },
        IRDastanas = {
            Name = "I.R. Dastanas",
            Level = 68,
            Id = 15009,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Hands",
            Stats = {
                DEF = 22,
                HP = 20,
                MagicDefenseBonus = 2,
                Enmity = 4,
            }
        },
        IgqiraManillas = {
            Name = "Igqira Manillas",
            Level = 73,
            Id = 14852,
            Jobs = {"BLM"},
            Type = "Hands",
            Stats = {
                DEF = 11,
                MagicAttackBonus = 2,
            }
        },
        IkengasGloves = {
            Name = "Ikengas Gloves",
            Level = 75,
            Id = 23769,
            Jobs = {"COR"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                HP = 20,
                MagicEvasion = 3,
                MagicDefenseBonus = 3,
            }
        },
        KaiserHandschuhs = {
            Name = "Kaiser Handschuhs",
            Level = 73,
            Id = 14061,
            Jobs = {"WAR", "PLD"},
            Type = "Hands",
            Stats = {
                DEF = 31,
                HP = 22,
                STR = -6,
                DEX = -6,
                VIT = 11,
                CHR = 11,
            }
        },
        Kampfhentzes = {
            Name = "Kampfhentzes",
            Level = 29,
            Id = 14863,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Hands",
            Stats = {
                DEF = 10,
                VIT = 2,
            }
        },
        KhimairaWrist = {
            Name = "Khimaira Wrist.",
            Level = 71,
            Id = 14981,
            Jobs = {"BST"},
            Type = "Hands",
            Stats = {
                DEF = 14,
                HP = 13,
                MP = 13,
                Accuracy = 4,
                Evasion = 4,
                Enmity = -1,
            }
        },
        KhthoniosGloves = {
            Name = "Khthonios Gloves",
            Level = 75,
            Id = 11918,
            Jobs = {"WAR", "PLD", "DRK", "RNG", "SAM", "COR"},
            Type = "Hands",
            Stats = {
                DEF = 23,
                AGI = 6,
                RangedAttack = 8,
                Enmity = -3,
            }
        },
        KingsGauntlets = {
            Name = "Kings Gauntlets",
            Level = 70,
            Id = 14883,
            Jobs = {"PLD"},
            Type = "Hands",
            Stats = {
                DEF = 19,
                HP = 20,
                VIT = 3,
                Enmity = 3,
            }
        },
        KngHandschuhs = {
            Name = "Kng. Handschuhs",
            Level = 73,
            Id = 12677,
            Jobs = {"WAR", "PLD"},
            Type = "Hands",
            Stats = {
                DEF = 30,
                HP = 20,
                STR = -5,
                DEX = -5,
                VIT = 10,
                CHR = 10,
            }
        },
        KoboKote = {
            Name = "Kobo Kote",
            Level = 75,
            Id = 27133,
            Jobs = {"WAR", "MNK", "BST", "BRD", "RNG", "SAM", "NIN"},
            Type = "Hands",
            Stats = {
                DEF = 28,
                HP = 60,
                AGI = 18,
                RangedAccuracy = 15,
                Evasion = 5,
                StoreTP = 6,
                CriticalHitRate = 4,
            }
        },
        KogTekko_1 = {
            Name = "Kog. Tekko +1",
            Level = 75,
            Id = 14921,
            Jobs = {"NIN"},
            Type = "Hands",
            Stats = {
                DEF = 19,
            }
        },
        LeatherGloves = {
            Name = "Leather Gloves",
            Level = 7,
            Id = 12696,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 2,
            }
        },
        LeatherGloves_1 = {
            Name = "Leather Gloves +1",
            Level = 7,
            Id = 12784,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 3,
            }
        },
        LinenCuffs = {
            Name = "Linen Cuffs",
            Level = 12,
            Id = 12729,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 3,
            }
        },
        LinenCuffs_1 = {
            Name = "Linen Cuffs +1",
            Level = 12,
            Id = 12778,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 4,
                STR = 1,
            }
        },
        LizardGloves = {
            Name = "Lizard Gloves",
            Level = 17,
            Id = 12697,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 5,
            }
        },
        LordsGauntlets = {
            Name = "Lords Gauntlets",
            Level = 70,
            Id = 14879,
            Jobs = {"PLD"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                VIT = 2,
                Enmity = 2,
            }
        },
        MagBazubands_1 = {
            Name = "Mag. Bazubands +1",
            Level = 74,
            Id = 15024,
            Jobs = {"BLU"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                MP = 20,
                STR = 3,
                INT = 3,
            }
        },
        MagesMitts = {
            Name = "Mages Mitts",
            Level = 50,
            Id = 12794,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 11,
                INT = 1,
            }
        },
        MagusBazubands = {
            Name = "Magus Bazubands",
            Level = 56,
            Id = 14928,
            Jobs = {"BLU"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                MP = 15,
            }
        },
        MalignanceGloves = {
            Name = "Malignance Gloves",
            Level = 75,
            Id = 23734,
            Jobs = {"RDM"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                MP = 15,
                VIT = 3,
                MND = 3,
                MagicEvasion = 3,
                MagicDefenseBonus = 3,
                Regen = 1,
            }
        },
        MarduksDastanas = {
            Name = "Marduks Dastanas",
            Level = 75,
            Id = 14973,
            Jobs = {"WHM", "BRD", "SMN", "SCH"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                MPP = 2,
                MND = 6,
                CHR = 6,
                Enmity = -4,
                Regen = 1,
            }
        },
        MelGloves_1 = {
            Name = "Mel. Gloves +1",
            Level = 75,
            Id = 14910,
            Jobs = {"MNK"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                HPP = 3,
                Attack = 18,
                SubtleBlow = 5,
            }
        },
        MelacoMittens = {
            Name = "Melaco Mittens",
            Level = 72,
            Id = 11920,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                MND = 3,
            }
        },
        MerlinicDastanas = {
            Name = "Merlinic Dastanas",
            Level = 75,
            Id = 27141,
            Jobs = {"SCH"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                HP = 25,
                INT = 3,
                Enmity = -5,
            }
        },
        MorrigansCuffs = {
            Name = "Morrigans Cuffs",
            Level = 75,
            Id = 14977,
            Jobs = {"BLM", "RDM", "BLU", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 21,
                MP = 25,
                Accuracy = 5,
                Attack = 5,
                MagicAccuracy = 5,
                MagicAttackBonus = 5,
            }
        },
        MpacasGloves = {
            Name = "Mpacas Gloves",
            Level = 75,
            Id = 23772,
            Jobs = {"NIN"},
            Type = "Hands",
            Stats = {
                DEF = 21,
                HP = 25,
                STR = 6,
                AGI = 6,
                Haste = 3,
            }
        },
        MrgBazubands_1 = {
            Name = "Mrg. Bazubands +1",
            Level = 75,
            Id = 15026,
            Jobs = {"BLU"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                HP = 12,
                MP = 12,
                DEX = 6,
                MND = 6,
                Evasion = 5,
            }
        },
        MstGloves_1 = {
            Name = "Mst. Gloves +1",
            Level = 75,
            Id = 14917,
            Jobs = {"BST"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                HP = 20,
                AGI = 5,
            }
        },
        MynKote_1 = {
            Name = "Myn. Kote +1",
            Level = 74,
            Id = 14901,
            Jobs = {"SAM"},
            Type = "Hands",
            Stats = {
                DEF = 21,
                HP = 15,
                STR = 7,
                DEX = 7,
                Enmity = 2,
            }
        },
        MythrilGauntlets = {
            Name = "Mythril Gauntlets",
            Level = 49,
            Id = 12673,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Hands",
            Stats = {
                DEF = 13,
            }
        },
        MythrilGnt_1 = {
            Name = "Mythril Gnt. +1",
            Level = 49,
            Id = 13958,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Hands",
            Stats = {
                DEF = 14,
                INT = 1,
            }
        },
        NagaTekko = {
            Name = "Naga Tekko",
            Level = 75,
            Id = 27099,
            Jobs = {"MNK"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                HPP = 3,
                DEX = 3,
                AGI = 3,
                Accuracy = 5,
                Counter = 3,
            }
        },
        NashiraGages = {
            Name = "Nashira Gages",
            Level = 75,
            Id = 14906,
            Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                MagicAccuracy = 3,
                Haste = 1,
                Enmity = -4,
            }
        },
        NinTekko_1 = {
            Name = "Nin. Tekko +1",
            Level = 74,
            Id = 14902,
            Jobs = {"NIN"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                HP = 13,
                STR = 6,
                DEX = 6,
                RangedAccuracy = 20,
                RangedAttack = 20,
            }
        },
        NoctGloves = {
            Name = "Noct Gloves",
            Level = 30,
            Id = 14854,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Hands",
            Stats = {
                DEF = 5,
                RangedAccuracy = 1,
            }
        },
        NoctGloves_1 = {
            Name = "Noct Gloves +1",
            Level = 30,
            Id = 14865,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Hands",
            Stats = {
                DEF = 6,
                RangedAccuracy = 2,
            }
        },
        OchiudosKote = {
            Name = "Ochiudos Kote",
            Level = 34,
            Id = 13952,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Hands",
            Stats = {
                DEF = 8,
                Attack = 20,
                Evasion = -5,
            }
        },
        OdysseanGauntlets = {
            Name = "Odyssean Gauntlets",
            Level = 75,
            Id = 27138,
            Jobs = {"DRG"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                HP = 15,
                MP = 20,
                VIT = 6,
                MND = 6,
                Haste = 5,
                Regen = 1,
            }
        },
        OgreGloves = {
            Name = "Ogre Gloves",
            Level = 70,
            Id = 13706,
            Jobs = {"RDM", "BST"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                MP = 12,
                STR = 6,
                DEX = -3,
            }
        },
        OgreGloves_1 = {
            Name = "Ogre Gloves +1",
            Level = 70,
            Id = 14057,
            Jobs = {"RDM", "BST"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                MP = 14,
                STR = 7,
                DEX = -4,
            }
        },
        OnyxGadlings = {
            Name = "Onyx Gadlings",
            Level = 71,
            Id = 14011,
            Jobs = {"DRK"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                STR = 5,
                Attack = 10,
            }
        },
        OraclesGloves = {
            Name = "Oracles Gloves",
            Level = 72,
            Id = 15022,
            Jobs = {"WHM", "BLM", "BRD", "SMN", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                HP = 15,
                MP = 25,
                HMP = 2,
            }
        },
        PantinDastanas_1 = {
            Name = "Pantin Dastanas +1",
            Level = 75,
            Id = 15032,
            Jobs = {"PUP"},
            Type = "Hands",
            Stats = {
                DEF = 19,
                HP = 25,
                DEX = 3,
                CHR = 3,
                Haste = 3,
            }
        },
        PlainGloves = {
            Name = "Plain Gloves",
            Level = 30,
            Id = 25984,
            Jobs = {"All"},
            Type = "Hands",
            Stats = {
                DEF = 7,
            }
        },
        PupDastanas = {
            Name = "Pup. Dastanas",
            Level = 56,
            Id = 14930,
            Jobs = {"PUP"},
            Type = "Hands",
            Stats = {
                DEF = 12,
                HP = 13,
                AGI = 3,
            }
        },
        PupDastanas_1 = {
            Name = "Pup. Dastanas +1",
            Level = 74,
            Id = 15030,
            Jobs = {"PUP"},
            Type = "Hands",
            Stats = {
                DEF = 13,
                HP = 18,
                STR = 5,
                AGI = 5,
            }
        },
        PursuersCuffs = {
            Name = "Pursuers Cuffs",
            Level = 75,
            Id = 27101,
            Jobs = {"BRD"},
            Type = "Hands",
            Stats = {
                DEF = 21,
                HP = 15,
                MP = 15,
                VIT = 3,
                MND = 3,
                MagicEvasion = 3,
                MagicDefenseBonus = 3,
                StoreTP = 5,
                Regen = 1,
            }
        },
        RaptorGloves = {
            Name = "Raptor Gloves",
            Level = 48,
            Id = 12700,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 12,
            }
        },
        RawhideGloves = {
            Name = "Rawhide Gloves",
            Level = 75,
            Id = 27100,
            Jobs = {"DNC"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                HP = 20,
                VIT = 10,
                Accuracy = 5,
                Attack = 5,
                Haste = 3,
            }
        },
        RogArmlets_1 = {
            Name = "Rog. Armlets +1",
            Level = 74,
            Id = 14895,
            Jobs = {"THF"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                HP = 10,
                DEX = 3,
            }
        },
        RubiousMitts = {
            Name = "Rubious Mitts",
            Level = 30,
            Id = 14861,
            Jobs = {"MNK", "RDM", "PLD", "BRD", "RNG", "BLU", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 10,
            }
        },
        RuneistMitons = {
            Name = "Runeist Mitons",
            Level = 75,
            Id = 28067,
            Jobs = {"RUN"},
            Type = "Hands",
            Stats = {
                DEF = 21,
                MP = 22,
                DEX = 3,
                VIT = 3,
                Refresh = 1,
            }
        },
        RylFtmGloves = {
            Name = "Ryl.Ftm. Gloves",
            Level = 10,
            Id = 12753,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 3,
                Attack = 3,
            }
        },
        RyuoTekko = {
            Name = "Ryuo Tekko",
            Level = 75,
            Id = 27115,
            Jobs = {"SAM"},
            Type = "Hands",
            Stats = {
                DEF = 24,
                HP = 20,
                VIT = 3,
                MND = 3,
                MagicEvasion = 3,
                MagicDefenseBonus = 3,
                Regen = 1,
            }
        },
        SakpatasGauntlets = {
            Name = "Sakpatas Gauntlets",
            Level = 75,
            Id = 23771,
            Jobs = {"WAR"},
            Type = "Hands",
            Stats = {
                DEF = 25,
                STR = 5,
                Haste = 3,
                Enmity = 3,
            }
        },
        SaoKote_1 = {
            Name = "Sao. Kote +1",
            Level = 75,
            Id = 14920,
            Jobs = {"SAM"},
            Type = "Hands",
            Stats = {
                DEF = 22,
                HP = 20,
                Attack = 12,
                Enmity = 1,
            }
        },
        SaotomeKote = {
            Name = "Saotome Kote",
            Level = 73,
            Id = 15113,
            Jobs = {"SAM"},
            Type = "Hands",
            Stats = {
                DEF = 21,
                HP = 10,
                Attack = 10,
                Enmity = 1,
            }
        },
        SchBracers_1 = {
            Name = "Sch. Bracers +1",
            Level = 74,
            Id = 15037,
            Jobs = {"SCH"},
            Type = "Hands",
            Stats = {
                DEF = 14,
                MP = 20,
                MND = 5,
                Enmity = -3,
            }
        },
        ScholarsBracers = {
            Name = "Scholars Bracers",
            Level = 52,
            Id = 15004,
            Jobs = {"SCH"},
            Type = "Hands",
            Stats = {
                DEF = 13,
                MP = 15,
                MND = 3,
                Enmity = -2,
            }
        },
        SctBracers_1 = {
            Name = "Sct. Bracers +1",
            Level = 75,
            Id = 14919,
            Jobs = {"RNG"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                HP = 13,
                AGI = 6,
                Evasion = 9,
                Enmity = -2,
            }
        },
        SeersMitts = {
            Name = "Seers Mitts",
            Level = 29,
            Id = 14856,
            Jobs = {"WHM", "BLM", "SMN", "PUP", "SCH", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 5,
                INT = 1,
                MND = 1,
            }
        },
        SeersMitts_1 = {
            Name = "Seers Mitts +1",
            Level = 29,
            Id = 14859,
            Jobs = {"WHM", "BLM", "SMN", "PUP", "SCH", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 6,
                INT = 2,
                MND = 2,
            }
        },
        SeiryusKote = {
            Name = "Seiryus Kote",
            Level = 75,
            Id = 12690,
            Jobs = {"WAR", "MNK", "BST", "BRD", "RNG", "SAM", "NIN"},
            Type = "Hands",
            Stats = {
                DEF = 26,
                HP = 50,
                AGI = 15,
                RangedAccuracy = 10,
            }
        },
        ShadeMittens = {
            Name = "Shade Mittens",
            Level = 25,
            Id = 14858,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 7,
            }
        },
        ShadeMittens_1 = {
            Name = "Shade Mittens +1",
            Level = 25,
            Id = 14862,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 8,
                Evasion = 1,
            }
        },
        ShadowCuffs = {
            Name = "Shadow Cuffs",
            Level = 75,
            Id = 14997,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 14,
                INT = 5,
                MagicAccuracy = 3,
                Enmity = -1,
            }
        },
        ShadowGauntlets = {
            Name = "Shadow Gauntlets",
            Level = 75,
            Id = 14995,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Hands",
            Stats = {
                DEF = 23,
                HP = 18,
                MP = 18,
                CHR = 4,
                Accuracy = 3,
                Attack = 5,
            }
        },
        ShairGages = {
            Name = "Shair Gages",
            Level = 72,
            Id = 14846,
            Jobs = {"BRD"},
            Type = "Hands",
            Stats = {
                DEF = 19,
                MP = 12,
                CHR = 5,
            }
        },
        SheikhGages = {
            Name = "Sheikh Gages",
            Level = 72,
            Id = 14847,
            Jobs = {"BRD"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                MP = 14,
                CHR = 6,
            }
        },
        ShinobiTekko = {
            Name = "Shinobi Tekko",
            Level = 49,
            Id = 12716,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Hands",
            Stats = {
                DEF = 11,
            }
        },
        ShinobiTekko_1 = {
            Name = "Shinobi Tekko +1",
            Level = 49,
            Id = 13955,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Hands",
            Stats = {
                DEF = 12,
                DEX = 1,
            }
        },
        ShuraKote = {
            Name = "Shura Kote",
            Level = 73,
            Id = 14821,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                HP = -20,
                Accuracy = 4,
            }
        },
        ShuraKote_1 = {
            Name = "Shura Kote +1",
            Level = 73,
            Id = 14822,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                HP = -25,
                Accuracy = 5,
            }
        },
        SilkCuffs = {
            Name = "Silk Cuffs",
            Level = 53,
            Id = 12732,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 11,
            }
        },
        SilkCuffs_1 = {
            Name = "Silk Cuffs +1",
            Level = 53,
            Id = 13954,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 12,
                MND = 3,
            }
        },
        SkadisBazubands = {
            Name = "Skadis Bazubands",
            Level = 75,
            Id = 14965,
            Jobs = {"THF", "BST", "RNG", "COR", "DNC"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                STR = 5,
                AGI = 5,
                Attack = 10,
                RangedAttack = 10,
            }
        },
        SmnBracers_1 = {
            Name = "Smn. Bracers +1",
            Level = 75,
            Id = 14923,
            Jobs = {"SMN"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                MP = 30,
            }
        },
        SoilTekko = {
            Name = "Soil Tekko",
            Level = 29,
            Id = 12714,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Hands",
            Stats = {
                DEF = 7,
            }
        },
        SoilTekko_1 = {
            Name = "Soil Tekko +1",
            Level = 29,
            Id = 12781,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Hands",
            Stats = {
                DEF = 8,
            }
        },
        SrcGloves_1 = {
            Name = "Src. Gloves +1",
            Level = 75,
            Id = 14912,
            Jobs = {"BLM"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                MP = 24,
                Enmity = -3,
            }
        },
        StoutWristbands = {
            Name = "Stout Wristbands",
            Level = 71,
            Id = 14982,
            Jobs = {"BST"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                HP = 14,
                MP = 14,
                Accuracy = 5,
                Evasion = 5,
                Enmity = -2,
            }
        },
        TaeonGloves = {
            Name = "Taeon Gloves",
            Level = 75,
            Id = 27047,
            Jobs = {"MNK", "THF", "BST", "RNG", "NIN", "COR", "PUP", "DNC"},
            Type = "Hands",
            Stats = {
                DEF = 23,
                HP = 10,
                MP = 10,
                STR = 3,
                DEX = 3,
                VIT = 3,
                AGI = 3,
                INT = 3,
                MND = 3,
                CHR = 3,
                Haste = 1,
                SubtleBlow = 5,
            }
        },
        ThurandautGloves = {
            Name = "Thurandaut Gloves",
            Level = 75,
            Id = 28064,
            Jobs = {"PUP"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                HP = 20,
                STR = 5,
                VIT = 5,
                Accuracy = 6,
                Attack = 6,
                Haste = 3,
            }
        },
        TjukurrpaGauntlets = {
            Name = "Tjukurrpa Gauntlets",
            Level = 75,
            Id = 11923,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Hands",
            Stats = {
                DEF = 30,
                HP = 30,
                MP = 30,
                Accuracy = 5,
                Enmity = 3,
            }
        },
        TplGloves_1 = {
            Name = "Tpl. Gloves +1",
            Level = 74,
            Id = 14891,
            Jobs = {"MNK"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                HP = 14,
                STR = 6,
                SubtleBlow = 4,
            }
        },
        UcnMittens_1 = {
            Name = "Ucn. Mittens +1",
            Level = 74,
            Id = 14056,
            Jobs = {"WAR"},
            Type = "Hands",
            Stats = {
                DEF = 28,
                HP = 28,
                Attack = 9,
                RangedAttack = 9,
            }
        },
        UnicornMittens = {
            Name = "Unicorn Mittens",
            Level = 74,
            Id = 14055,
            Jobs = {"WAR"},
            Type = "Hands",
            Stats = {
                DEF = 26,
                HP = 24,
                Attack = 8,
                RangedAttack = 8,
            }
        },
        UsukaneGote = {
            Name = "Usukane Gote",
            Level = 75,
            Id = 14969,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                Accuracy = 10,
                Evasion = 10,
                SubtleBlow = 5,
                Counter = 2,
            }
        },
        ValkGauntlets = {
            Name = "Valk. Gauntlets",
            Level = 75,
            Id = 14996,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Hands",
            Stats = {
                DEF = 24,
                HP = 20,
                MP = 20,
                CHR = 5,
                Accuracy = 4,
                Attack = 6,
            }
        },
        ValkyriesCuffs = {
            Name = "Valkyries Cuffs",
            Level = 75,
            Id = 14998,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 15,
                INT = 6,
                MagicAccuracy = 4,
                Enmity = -2,
            }
        },
        ValorousMitts = {
            Name = "Valorous Mitts",
            Level = 75,
            Id = 27139,
            Jobs = {"BST"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                HP = 25,
                VIT = 3,
                MND = 3,
                Enmity = -3,
                Regen = 1,
            }
        },
        VanyaCuffs = {
            Name = "Vanya Cuffs",
            Level = 75,
            Id = 27103,
            Jobs = {"BLM"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                MP = 15,
                STR = 6,
                DEX = 6,
                Accuracy = 12,
                Attack = 12,
                Haste = 3,
                Enmity = -3,
            }
        },
        VenomVambraces = {
            Name = "Venom Vambraces",
            Level = 60,
            Id = 39100,
            Jobs = {"WAR", "MNK", "THF", "BST", "NIN", "PUP", "DNC"},
            Type = "Hands",
            Stats = {
                DEF = 14,
                DEX = 3,
                Haste = 2,
            }
        },
        ViciousMufflers = {
            Name = "Vicious Mufflers",
            Level = 70,
            Id = 15013,
            Jobs = {"BLM", "DRK", "SCH", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 18,
                MagicAttackBonus = 5,
            }
        },
        VlrGauntlets_1 = {
            Name = "Vlr. Gauntlets +1",
            Level = 75,
            Id = 14915,
            Jobs = {"PLD"},
            Type = "Hands",
            Stats = {
                DEF = 23,
                HP = 16,
                VIT = 6,
                Enmity = 4,
            }
        },
        WarMufflers_1 = {
            Name = "War. Mufflers +1",
            Level = 75,
            Id = 14909,
            Jobs = {"WAR"},
            Type = "Hands",
            Stats = {
                DEF = 23,
                HP = 20,
                VIT = 6,
                Attack = 14,
                Enmity = 2,
            }
        },
        WhiteMitts = {
            Name = "White Mitts",
            Level = 20,
            Id = 12737,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 4,
            }
        },
        WiseGloves = {
            Name = "Wise Gloves",
            Level = 72,
            Id = 14880,
            Jobs = {"RDM"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                MND = 4,
                Accuracy = 3,
                RangedAccuracy = 2,
                Enmity = -2,
            }
        },
        WiseGloves_1 = {
            Name = "Wise Gloves +1",
            Level = 72,
            Id = 14881,
            Jobs = {"RDM"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                MND = 5,
                Accuracy = 4,
                RangedAccuracy = 3,
                Enmity = -3,
            }
        },
        WizardsGloves = {
            Name = "Wizards Gloves",
            Level = 54,
            Id = 13964,
            Jobs = {"BLM"},
            Type = "Hands",
            Stats = {
                DEF = 13,
                MP = 12,
                CHR = 3,
                Enmity = -1,
            }
        },
        WlkGloves_1 = {
            Name = "Wlk. Gloves +1",
            Level = 74,
            Id = 14894,
            Jobs = {"RDM"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                MP = 17,
                DEX = 6,
                INT = 2,
                MND = 2,
            }
        },
        WymFngGnt_1 = {
            Name = "Wym. Fng. Gnt. +1",
            Level = 75,
            Id = 14922,
            Jobs = {"DRG"},
            Type = "Hands",
            Stats = {
                DEF = 20,
                HP = 16,
                MP = 16,
                AGI = 4,
                Accuracy = 7,
            }
        },
        WzdGloves_1 = {
            Name = "Wzd. Gloves +1",
            Level = 74,
            Id = 14893,
            Jobs = {"BLM"},
            Type = "Hands",
            Stats = {
                DEF = 13,
                MP = 17,
                INT = 3,
                CHR = 3,
                Enmity = -2,
            }
        },
        YashaTekko = {
            Name = "Yasha Tekko",
            Level = 71,
            Id = 13957,
            Jobs = {"NIN"},
            Type = "Hands",
            Stats = {
                DEF = 16,
                Enmity = 2,
            }
        },
        YashaTekko_1 = {
            Name = "Yasha Tekko +1",
            Level = 71,
            Id = 14882,
            Jobs = {"NIN"},
            Type = "Hands",
            Stats = {
                DEF = 17,
                Enmity = 3,
            }
        },
        ZealotsMitts = {
            Name = "Zealots Mitts",
            Level = 11,
            Id = 12798,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Hands",
            Stats = {
                DEF = 3,
                MP = 5,
                INT = -2,
                MND = 3,
            }
        },
        ZenithMitts = {
            Name = "Zenith Mitts",
            Level = 73,
            Id = 14006,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 23,
                MagicAttackBonus = 5,
            }
        },
        ZenithMitts_1 = {
            Name = "Zenith Mitts +1",
            Level = 73,
            Id = 14007,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Hands",
            Stats = {
                DEF = 24,
                MagicAttackBonus = 6,
            }
        },
    },
    Ring = {
        AifesAnnulet = {
            Name = "Aifes Annulet",
            Level = 75,
            Id = 10759,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                INT = 5,
            }
        },
        AifesRing = {
            Name = "Aifes Ring",
            Level = 75,
            Id = 10758,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                STR = 5,
            }
        },
        AlchemistsRing = {
            Name = "Alchemists Ring",
            Level = 1,
            Id = 15825,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        AlertRing = {
            Name = "Alert Ring",
            Level = 75,
            Id = 11635,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Accuracy = -3,
                Evasion = 6,
            }
        },
        ArchersRing = {
            Name = "Archers Ring",
            Level = 30,
            Id = 13514,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Accuracy = 2,
                RangedAccuracy = 2,
            }
        },
        AsceticsRing = {
            Name = "Ascetics Ring",
            Level = 1,
            Id = 13440,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MND = 1,
            }
        },
        AstralRing = {
            Name = "Astral Ring",
            Level = 10,
            Id = 13548,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        BastokanRing = {
            Name = "Bastokan Ring",
            Level = 1,
            Id = 13497,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                HP = 3,
                DEX = 1,
                VIT = 1,
            }
        },
        BlobnagRing = {
            Name = "Blobnag Ring",
            Level = 75,
            Id = 11631,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                AGI = 6,
                RangedAccuracy = 3,
            }
        },
        BrassRing = {
            Name = "Brass Ring",
            Level = 7,
            Id = 13465,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                HP = 2,
                MP = -2,
            }
        },
        BreezeRing = {
            Name = "Breeze Ring",
            Level = 74,
            Id = 14636,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 3,
                VIT = 2,
                AGI = 5,
                INT = -2,
            }
        },
        CarbRing = {
            Name = "Carb. Ring",
            Level = 75,
            Id = 27576,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                HP = 20,
                MP = 20,
                CHR = 6,
            }
        },
        CarbRing_1 = {
            Name = "Carb. Ring +1",
            Level = 75,
            Id = 27577,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                HP = 30,
                MP = 30,
                CHR = 8,
            }
        },
        ChaplainsRing = {
            Name = "Chaplains Ring",
            Level = 30,
            Id = 10787,
            Jobs = {"WHM", "BLU", "SCH", "GEO"},
            Type = "Ring",
            Stats = {
                MP = 15,
                MND = 3,
                Accuracy = 4,
            }
        },
        CorneusRing = {
            Name = "Corneus Ring",
            Level = 75,
            Id = 11630,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                VIT = 6,
                Enmity = 2,
            }
        },
        CourageRing = {
            Name = "Courage Ring",
            Level = 14,
            Id = 13522,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                STR = 2,
            }
        },
        CraftmastersRing = {
            Name = "Craftmasters Ring",
            Level = 1,
            Id = 28586,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        DarkRing = {
            Name = "Dark Ring",
            Level = 74,
            Id = 14644,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 3,
                HP = -20,
                MP = 20,
                STR = 1,
                DEX = 1,
                VIT = 1,
                AGI = 1,
                INT = 1,
                MND = 1,
                CHR = 1,
            }
        },
        DefendingRing = {
            Name = "Defending Ring",
            Level = 70,
            Id = 13566,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        DemRing = {
            Name = "Dem Ring",
            Level = 65,
            Id = 14662,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        DemonryRing = {
            Name = "Demonry Ring",
            Level = 75,
            Id = 11673,
            Jobs = {"MNK", "THF", "DRK", "BST", "SAM", "DRG", "DNC", "RUN"},
            Type = "Ring",
            Stats = {
                Attack = 5,
            }
        },
        DragonRing = {
            Name = "Dragon Ring",
            Level = 73,
            Id = 13467,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 1,
                Accuracy = -10,
                RangedAccuracy = 10,
            }
        },
        EidolonRing = {
            Name = "Eidolon Ring",
            Level = 75,
            Id = 26188,
            Jobs = {"SMN"},
            Type = "Ring",
            Stats = {
                MP = 40,
            }
        },
        EmporoxsRing = {
            Name = "Emporoxs Ring",
            Level = 1,
            Id = 28470,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 2,
                VIT = 1,
            }
        },
        EmpressBand = {
            Name = "Empress Band",
            Level = 1,
            Id = 15762,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        EshmunsRing = {
            Name = "Eshmuns Ring",
            Level = 73,
            Id = 10793,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 5,
            }
        },
        FenrirRing = {
            Name = "Fenrir Ring",
            Level = 75,
            Id = 27578,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MP = 40,
                HMP = 3,
            }
        },
        FenrirRing_1 = {
            Name = "Fenrir Ring +1",
            Level = 75,
            Id = 27579,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MP = 50,
                HMP = 5,
                HHP = 5,
            }
        },
        FlameRing = {
            Name = "Flame Ring",
            Level = 74,
            Id = 14630,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 3,
                STR = 5,
                INT = 2,
                MND = -2,
            }
        },
        GaldrRing = {
            Name = "Galdr Ring",
            Level = 75,
            Id = 11633,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                INT = 6,
                MagicAttackBonus = 1,
            }
        },
        GarudaRing = {
            Name = "Garuda Ring",
            Level = 75,
            Id = 27572,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                AGI = 6,
            }
        },
        GarudaRing_1 = {
            Name = "Garuda Ring +1",
            Level = 75,
            Id = 27573,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                AGI = 8,
                RangedAccuracy = 3,
            }
        },
        HermitsRing = {
            Name = "Hermits Ring",
            Level = 1,
            Id = 13475,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                INT = 1,
            }
        },
        HibernalRing = {
            Name = "Hibernal Ring",
            Level = 75,
            Id = 28575,
            Jobs = {"BLM", "BRD", "SCH", "GEO"},
            Type = "Ring",
            Stats = {
                MP = 25,
                INT = 5,
                FastCast = 2,
            }
        },
        HopeRing = {
            Name = "Hope Ring",
            Level = 14,
            Id = 13528,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                CHR = 2,
            }
        },
        HornRing = {
            Name = "Horn Ring",
            Level = 35,
            Id = 13459,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Accuracy = -4,
                RangedAccuracy = 4,
            }
        },
        IfritRing = {
            Name = "Ifrit Ring",
            Level = 75,
            Id = 27564,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                STR = 6,
            }
        },
        IfritRing_1 = {
            Name = "Ifrit Ring +1",
            Level = 75,
            Id = 27565,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                STR = 8,
                Attack = 3,
            }
        },
        JaegerRing = {
            Name = "Jaeger Ring",
            Level = 35,
            Id = 14669,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Accuracy = 4,
                RangedAccuracy = 4,
            }
        },
        JalzahnsRing = {
            Name = "Jalzahns Ring",
            Level = 50,
            Id = 15809,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                RangedAccuracy = 6,
                RangedAttack = 6,
            }
        },
        JellyRing = {
            Name = "Jelly Ring",
            Level = 63,
            Id = 13303,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        KarkaRing = {
            Name = "Karka Ring",
            Level = 75,
            Id = 11632,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MND = 6,
                MagicAccuracy = 1,
            }
        },
        KnowledgeRing = {
            Name = "Knowledge Ring",
            Level = 14,
            Id = 13523,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                INT = 2,
            }
        },
        KushasRing = {
            Name = "Kushas Ring",
            Level = 55,
            Id = 15851,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        LavasRing = {
            Name = "Lavas Ring",
            Level = 55,
            Id = 15850,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        LeatherRing = {
            Name = "Leather Ring",
            Level = 14,
            Id = 13469,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 1,
            }
        },
        LeatherRing_1 = {
            Name = "Leather Ring +1",
            Level = 14,
            Id = 13499,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 2,
            }
        },
        LeviaRing = {
            Name = "Levia. Ring",
            Level = 75,
            Id = 27566,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MND = 6,
            }
        },
        LeviaRing_1 = {
            Name = "Levia. Ring +1",
            Level = 75,
            Id = 27567,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MND = 8,
                MagicAccuracy = 3,
            }
        },
        MarssRing = {
            Name = "Marss Ring",
            Level = 75,
            Id = 15548,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = -8,
                Accuracy = 8,
                Attack = 8,
                Evasion = -8,
            }
        },
        MoepapaAnnulet = {
            Name = "Moepapa Annulet",
            Level = 75,
            Id = 10755,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                STR = 5,
            }
        },
        MoepapaRing = {
            Name = "Moepapa Ring",
            Level = 75,
            Id = 10754,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                AGI = 5,
            }
        },
        MujinBand = {
            Name = "Mujin Band",
            Level = 75,
            Id = 11672,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEX = 4,
            }
        },
        OneirosAnnulet = {
            Name = "Oneiros Annulet",
            Level = 75,
            Id = 11670,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                AGI = -5,
                Accuracy = 8,
            }
        },
        OneirosRing = {
            Name = "Oneiros Ring",
            Level = 75,
            Id = 11671,
            Jobs = {"WAR", "MNK", "THF", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
            Type = "Ring",
            Stats = {
                Accuracy = 3,
            }
        },
        PortusAnnulet = {
            Name = "Portus Annulet",
            Level = 74,
            Id = 10761,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Accuracy = 6,
            }
        },
        PortusRing = {
            Name = "Portus Ring",
            Level = 74,
            Id = 10760,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                VIT = 4,
            }
        },
        ProuesseRing = {
            Name = "Prouesse Ring",
            Level = 65,
            Id = 11677,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                HP = 10,
                MP = 10,
            }
        },
        RajasRing = {
            Name = "Rajas Ring",
            Level = 30,
            Id = 15543,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                STR = 2,
                DEX = 2,
                StoreTP = 5,
                SubtleBlow = 5,
            }
        },
        RamuhRing = {
            Name = "Ramuh Ring",
            Level = 75,
            Id = 27568,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEX = 6,
            }
        },
        RamuhRing_1 = {
            Name = "Ramuh Ring +1",
            Level = 75,
            Id = 27569,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEX = 8,
                Accuracy = 3,
            }
        },
        ResolutionRing = {
            Name = "Resolution Ring",
            Level = 30,
            Id = 28568,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        SaidaRing = {
            Name = "Saida Ring",
            Level = 73,
            Id = 10792,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 4,
            }
        },
        SanDOrianRing = {
            Name = "San D'Orian Ring",
            Level = 1,
            Id = 13495,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 2,
                STR = 1,
                MND = 1,
            }
        },
        SardonyxRing = {
            Name = "Sardonyx Ring",
            Level = 14,
            Id = 13444,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                STR = 1,
            }
        },
        ScorpionRing_1 = {
            Name = "Scorpion Ring +1",
            Level = 55,
            Id = 13513,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Accuracy = -6,
                RangedAccuracy = 8,
            }
        },
        SetaeRing = {
            Name = "Setae Ring",
            Level = 75,
            Id = 28529,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                HP = 15,
                MP = 15,
            }
        },
        ShikareeRing = {
            Name = "Shikaree Ring",
            Level = 30,
            Id = 15551,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Accuracy = 2,
                RangedAccuracy = 2,
            }
        },
        ShivaRing = {
            Name = "Shiva Ring",
            Level = 75,
            Id = 27574,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                INT = 6,
            }
        },
        ShivaRing_1 = {
            Name = "Shiva Ring +1",
            Level = 75,
            Id = 27575,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                INT = 8,
                MagicAttackBonus = 3,
            }
        },
        ShukuyuRing = {
            Name = "Shukuyu Ring",
            Level = 75,
            Id = 26161,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Attack = 5,
                MagicEvasion = 3,
                DualWield = 3,
            }
        },
        SmithsRing = {
            Name = "Smiths Ring",
            Level = 1,
            Id = 15820,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        SnowRing = {
            Name = "Snow Ring",
            Level = 74,
            Id = 14640,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 3,
                STR = -2,
                AGI = 2,
                INT = 5,
            }
        },
        StarRing = {
            Name = "Star Ring",
            Level = 72,
            Id = 15805,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MP = 20,
                MND = 4,
                HMP = 1,
            }
        },
        StrigoiRing = {
            Name = "Strigoi Ring",
            Level = 75,
            Id = 11628,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                STR = 6,
                Attack = 3,
            }
        },
        SuccorRing = {
            Name = "Succor Ring",
            Level = 75,
            Id = 15859,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MP = 30,
            }
        },
        TamasRing = {
            Name = "Tamas Ring",
            Level = 30,
            Id = 15545,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MP = 15,
                INT = 2,
                MND = 2,
                Enmity = -3,
            }
        },
        TannersRing = {
            Name = "Tanners Ring",
            Level = 1,
            Id = 15823,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        TavnazianRing = {
            Name = "Tavnazian Ring",
            Level = 60,
            Id = 14672,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        ThunderRing = {
            Name = "Thunder Ring",
            Level = 74,
            Id = 14638,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 3,
                DEX = 5,
                VIT = -2,
                MND = 2,
            }
        },
        TitanRing = {
            Name = "Titan Ring",
            Level = 75,
            Id = 27570,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                VIT = 6,
            }
        },
        TitanRing_1 = {
            Name = "Titan Ring +1",
            Level = 75,
            Id = 27571,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 8,
                VIT = 8,
            }
        },
        TitaniumBand = {
            Name = "Titanium Band",
            Level = 70,
            Id = 28577,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEF = 5,
                HP = 65,
                Enmity = 2,
            }
        },
        TjukurrpaAnnulet = {
            Name = "Tjukurrpa Annulet",
            Level = 75,
            Id = 10757,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MND = 5,
            }
        },
        TjukurrpaRing = {
            Name = "Tjukurrpa Ring",
            Level = 75,
            Id = 10756,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEX = 5,
            }
        },
        UlthalamsRing = {
            Name = "Ulthalams Ring",
            Level = 50,
            Id = 15808,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Accuracy = 4,
                Attack = 4,
            }
        },
        UmbralRing = {
            Name = "Umbral Ring",
            Level = 75,
            Id = 11674,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        VeelaRing = {
            Name = "Veela Ring",
            Level = 75,
            Id = 11634,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                CHR = 6,
                Enmity = -2,
            }
        },
        VentureRing = {
            Name = "Venture Ring",
            Level = 1,
            Id = 10870,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        WarpRing = {
            Name = "Warp Ring",
            Level = 1,
            Id = 28540,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
            }
        },
        WindurstianRing = {
            Name = "Windurstian Ring",
            Level = 1,
            Id = 13496,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                MP = 3,
                AGI = 1,
                INT = 1,
            }
        },
        YacurunaRing = {
            Name = "Yacuruna Ring",
            Level = 73,
            Id = 28544,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Accuracy = 7,
            }
        },
        YacurunaRing_1 = {
            Name = "Yacuruna Ring +1",
            Level = 73,
            Id = 28545,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                Accuracy = 8,
            }
        },
        ZilantRing = {
            Name = "Zilant Ring",
            Level = 75,
            Id = 11629,
            Jobs = {"All"},
            Type = "Ring",
            Stats = {
                DEX = 6,
                Accuracy = 3,
            }
        },
    },
    Back = {
        AbyssCape = {
            Name = "Abyss Cape",
            Level = 70,
            Id = 15479,
            Jobs = {"DRK"},
            Type = "Back",
            Stats = {
                DEF = 6,
                Accuracy = 7,
                MagicAccuracy = 7,
            }
        },
        AifesMantle = {
            Name = "Aifes Mantle",
            Level = 75,
            Id = 10983,
            Jobs = {"All"},
            Type = "Back",
            Stats = {
                DEF = 7,
                AGI = 4,
                Accuracy = 4,
                StoreTP = 2,
            }
        },
        AssassinsCape = {
            Name = "Assassins Cape",
            Level = 70,
            Id = 15480,
            Jobs = {"THF"},
            Type = "Back",
            Stats = {
                DEF = 7,
                DEX = 4,
                AGI = 4,
                Enmity = 5,
            }
        },
        AstuteCape = {
            Name = "Astute Cape",
            Level = 73,
            Id = 15473,
            Jobs = {"All"},
            Type = "Back",
            Stats = {
                MP = 25,
            }
        },
        BardsCape = {
            Name = "Bards Cape",
            Level = 70,
            Id = 15482,
            Jobs = {"BRD"},
            Type = "Back",
            Stats = {
                DEF = 6,
                CHR = 7,
                Accuracy = 7,
                Evasion = 7,
            }
        },
        BlackCape_1 = {
            Name = "Black Cape +1",
            Level = 32,
            Id = 13610,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 4,
                INT = 3,
            }
        },
        BlueCape = {
            Name = "Blue Cape",
            Level = 68,
            Id = 13578,
            Jobs = {"WHM", "BLM", "BRD", "RNG", "SMN", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 6,
                MP = 15,
            }
        },
        BondCape = {
            Name = "Bond Cape",
            Level = 75,
            Id = 11576,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 7,
                MP = 15,
                MND = 3,
            }
        },
        BonzeCape = {
            Name = "Bonze Cape",
            Level = 25,
            Id = 13614,
            Jobs = {"All"},
            Type = "Back",
            Stats = {
                DEF = 2,
                MP = 3,
                INT = 1,
            }
        },
        BruisersCloak = {
            Name = "Bruisers Cloak",
            Level = 30,
            Id = 10993,
            Jobs = {"MNK", "PUP"},
            Type = "Back",
            Stats = {
                DEF = 3,
                STR = 2,
                Haste = 2,
            }
        },
        Cape = {
            Name = "Cape",
            Level = 7,
            Id = 13583,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 1,
            }
        },
        Cape_1 = {
            Name = "Cape +1",
            Level = 7,
            Id = 13605,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 2,
            }
        },
        ChargerMantle = {
            Name = "Charger Mantle",
            Level = 70,
            Id = 15475,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 7,
                Attack = 20,
                RangedAccuracy = -10,
                RangedAttack = -10,
            }
        },
        CottonCape = {
            Name = "Cotton Cape",
            Level = 18,
            Id = 13584,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 2,
            }
        },
        CottonCape_1 = {
            Name = "Cotton Cape +1",
            Level = 18,
            Id = 13601,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 3,
            }
        },
        CuchulainsMantle = {
            Name = "Cuchulains Mantle",
            Level = 74,
            Id = 16241,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 8,
                STR = 4,
                DEX = 4,
                Accuracy = 5,
            }
        },
        CvlMantle = {
            Name = "Cvl. Mantle",
            Level = 37,
            Id = 13635,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 8,
                VIT = 2,
                Evasion = -10,
            }
        },
        CvlMantle_1 = {
            Name = "Cvl. Mantle +1",
            Level = 37,
            Id = 13636,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 9,
                VIT = 3,
                Evasion = -10,
            }
        },
        DewSilkCape_1 = {
            Name = "Dew Silk Cape +1",
            Level = 75,
            Id = 27599,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 8,
                MND = 6,
                Enmity = -3,
                CurePotency = 3,
            }
        },
        EarthMantle = {
            Name = "Earth Mantle",
            Level = 40,
            Id = 13623,
            Jobs = {"WAR", "PLD", "DRK", "BST", "DRG"},
            Type = "Back",
            Stats = {
                DEF = 6,
                VIT = 1,
            }
        },
        EtoileCape = {
            Name = "Etoile Cape",
            Level = 70,
            Id = 16248,
            Jobs = {"DNC"},
            Type = "Back",
            Stats = {
                DEF = 5,
                DEX = 5,
                CHR = 5,
                Accuracy = 5,
                Evasion = 5,
            }
        },
        ExilesCloak = {
            Name = "Exiles Cloak",
            Level = 50,
            Id = 11008,
            Jobs = {"All"},
            Type = "Back",
            Stats = {
                DEF = 4,
                HP = 15,
                CHR = -3,
                Attack = 3,
            }
        },
        FedArmyMantle = {
            Name = "Fed. Army Mantle",
            Level = 55,
            Id = 13581,
            Jobs = {"All"},
            Type = "Back",
            Stats = {
                DEF = 6,
                MP = 6,
                AGI = 2,
                INT = 2,
            }
        },
        FidelityMantle = {
            Name = "Fidelity Mantle",
            Level = 30,
            Id = 11531,
            Jobs = {"All"},
            Type = "Back",
            Stats = {
            }
        },
        GrapevineCape = {
            Name = "Grapevine Cape",
            Level = 75,
            Id = 11575,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 7,
                INT = 3,
                MND = 3,
            }
        },
        HierarchsMantle = {
            Name = "Hierarchs Mantle",
            Level = 60,
            Id = 28640,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 7,
                MP = 15,
                MND = 3,
            }
        },
        HuntersShawl = {
            Name = "Hunters Shawl",
            Level = 30,
            Id = 10992,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Back",
            Stats = {
                DEF = 3,
                STR = 2,
                AGI = 2,
                RangedAccuracy = 3,
                RangedAttack = 3,
            }
        },
        LizardMantle = {
            Name = "Lizard Mantle",
            Level = 17,
            Id = 13592,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 2,
            }
        },
        LizardMantle_1 = {
            Name = "Lizard Mantle +1",
            Level = 17,
            Id = 13608,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 3,
            }
        },
        MeleeCape = {
            Name = "Melee Cape",
            Level = 70,
            Id = 15478,
            Jobs = {"MNK"},
            Type = "Back",
            Stats = {
                DEF = 8,
                VIT = 5,
                MND = 5,
                HHP = 5,
            }
        },
        MercifulCape = {
            Name = "Merciful Cape",
            Level = 73,
            Id = 15471,
            Jobs = {"All"},
            Type = "Back",
            Stats = {
                MP = 25,
            }
        },
        MirageMantle = {
            Name = "Mirage Mantle",
            Level = 70,
            Id = 16244,
            Jobs = {"BLU"},
            Type = "Back",
            Stats = {
                DEF = 6,
                MP = 20,
                Accuracy = 7,
                MagicAccuracy = 3,
            }
        },
        MistSilkCape = {
            Name = "Mist Silk Cape",
            Level = 10,
            Id = 13607,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 3,
                MND = 1,
            }
        },
        MujinMantle = {
            Name = "Mujin Mantle",
            Level = 75,
            Id = 10974,
            Jobs = {"WAR", "MNK", "THF", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "COR", "PUP", "DNC"},
            Type = "Back",
            Stats = {
                DEF = 9,
                Accuracy = 5,
                Evasion = 5,
                MagicEvasion = 5,
            }
        },
        NexusCape = {
            Name = "Nexus Cape",
            Level = 30,
            Id = 11538,
            Jobs = {"All"},
            Type = "Back",
            Stats = {
            }
        },
        NomadsMantle = {
            Name = "Nomads Mantle",
            Level = 24,
            Id = 13631,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 2,
                AGI = 1,
                Evasion = 3,
            }
        },
        NomadsMantle_1 = {
            Name = "Nomads Mantle +1",
            Level = 24,
            Id = 13632,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 3,
                AGI = 2,
                Evasion = 3,
            }
        },
        OneirosCape = {
            Name = "Oneiros Cape",
            Level = 75,
            Id = 10973,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 8,
                MagicAccuracy = 4,
            }
        },
        OneirosCappa = {
            Name = "Oneiros Cappa",
            Level = 75,
            Id = 10972,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 14,
                VIT = 5,
            }
        },
        PantinCape = {
            Name = "Pantin Cape",
            Level = 70,
            Id = 16245,
            Jobs = {"PUP"},
            Type = "Back",
            Stats = {
                DEF = 6,
                DEX = 5,
                Attack = 15,
            }
        },
        PincerMantle = {
            Name = "Pincer Mantle",
            Level = 75,
            Id = 23995,
            Jobs = {"BST", "DRG", "PUP"},
            Type = "Back",
            Stats = {
                DEF = 8,
            }
        },
        RainbowCape = {
            Name = "Rainbow Cape",
            Level = 71,
            Id = 13587,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 7,
                HP = 9,
                MP = 9,
                INT = 3,
                MND = 3,
                CHR = 3,
            }
        },
        RamMantle = {
            Name = "Ram Mantle",
            Level = 36,
            Id = 13570,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 5,
            }
        },
        RamMantle_1 = {
            Name = "Ram Mantle +1",
            Level = 36,
            Id = 13575,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 6,
            }
        },
        RancorousMantle = {
            Name = "Rancorous Mantle",
            Level = 72,
            Id = 10991,
            Jobs = {"All"},
            Type = "Back",
            Stats = {
                DEF = 7,
                Attack = 8,
                CriticalHitRate = 2,
            }
        },
        SnipersShroud = {
            Name = "Snipers Shroud",
            Level = 8,
            Id = 28028,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Back",
            Stats = {
                DEF = 2,
                STR = 1,
                RangedAttack = 1,
            }
        },
        SummonersCape = {
            Name = "Summoners Cape",
            Level = 70,
            Id = 15484,
            Jobs = {"SMN"},
            Type = "Back",
            Stats = {
                DEF = 6,
                HP = 30,
                MP = 30,
                Enmity = -1,
            }
        },
        SwithCape_1 = {
            Name = "Swith Cape +1",
            Level = 69,
            Id = 11001,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 7,
                HP = -25,
                MND = 4,
                CHR = 4,
                FastCast = 2,
            }
        },
        TjukurrpaMantle = {
            Name = "Tjukurrpa Mantle",
            Level = 75,
            Id = 10984,
            Jobs = {"THF", "RNG", "NIN", "COR"},
            Type = "Back",
            Stats = {
                DEF = 9,
                AGI = 3,
                MagicAttackBonus = 3,
                Enmity = 3,
            }
        },
        TravelersMantle = {
            Name = "Travelers Mantle",
            Level = 12,
            Id = 13613,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Back",
            Stats = {
                DEF = 1,
                Evasion = 3,
            }
        },
        TundraMantle = {
            Name = "Tundra Mantle",
            Level = 39,
            Id = 13625,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "RNG", "NIN", "SMN", "BLU", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 4,
                MP = 5,
            }
        },
        UmbralCape = {
            Name = "Umbral Cape",
            Level = 75,
            Id = 10975,
            Jobs = {"All"},
            Type = "Back",
            Stats = {
                DEF = 17,
            }
        },
        ValorCape = {
            Name = "Valor Cape",
            Level = 70,
            Id = 15481,
            Jobs = {"PLD"},
            Type = "Back",
            Stats = {
                DEF = 16,
                HP = 40,
                VIT = 6,
                Enmity = 3,
            }
        },
        VeelaCape = {
            Name = "Veela Cape",
            Level = 75,
            Id = 11544,
            Jobs = {"WHM", "BLM", "BRD", "SMN", "PUP", "SCH", "GEO"},
            Type = "Back",
            Stats = {
                DEF = 5,
                MP = 10,
                FastCast = 1,
            }
        },
    },
    Waist = {
        ArguteBelt = {
            Name = "Argute Belt",
            Level = 70,
            Id = 15925,
            Jobs = {"SCH"},
            Type = "Waist",
            Stats = {
                DEF = 6,
                MP = 20,
                INT = 5,
                MND = 5,
                MagicAccuracy = 2,
                MagicDefenseBonus = 2,
            }
        },
        BobcatBelt = {
            Name = "Bobcat Belt",
            Level = 75,
            Id = 15948,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 6,
                STR = 8,
                Attack = -6,
                StoreTP = -6,
            }
        },
        BrownBelt = {
            Name = "Brown Belt",
            Level = 40,
            Id = 13202,
            Jobs = {"MNK"},
            Type = "Waist",
            Stats = {
                DEF = 3,
                STR = 5,
                Haste = 8,
            }
        },
        ChampionBelt = {
            Name = "Champion Belt",
            Level = 70,
            Id = 28442,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 5,
                VIT = 4,
                Attack = 16,
            }
        },
        ClericsBelt = {
            Name = "Clerics Belt",
            Level = 70,
            Id = 15872,
            Jobs = {"WHM"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                MP = 40,
                MND = 6,
                HMP = 3,
            }
        },
        CommodoreBelt = {
            Name = "Commodore Belt",
            Level = 70,
            Id = 15920,
            Jobs = {"COR"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                STR = 4,
                RangedAccuracy = 8,
                RangedAttack = 5,
            }
        },
        DemonrySash = {
            Name = "Demonry Sash",
            Level = 75,
            Id = 11777,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
            Type = "Waist",
            Stats = {
                DEF = 5,
                MND = 3,
                CHR = 3,
                MagicAccuracy = 3,
            }
        },
        DuelistsBelt = {
            Name = "Duelists Belt",
            Level = 70,
            Id = 15873,
            Jobs = {"RDM"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                INT = 4,
                MND = 4,
                HMP = 4,
                HHP = 4,
            }
        },
        FatalityBelt = {
            Name = "Fatality Belt",
            Level = 75,
            Id = 15955,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 7,
                DEX = 4,
                Accuracy = 4,
            }
        },
        FieldRope = {
            Name = "Field Rope",
            Level = 65,
            Id = 11769,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
            }
        },
        FierceBelt = {
            Name = "Fierce Belt",
            Level = 75,
            Id = 15954,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                Attack = 15,
            }
        },
        ForceBelt = {
            Name = "Force Belt",
            Level = 27,
            Id = 13222,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 3,
                HP = 3,
                MP = 3,
            }
        },
        FriarsRope = {
            Name = "Friars Rope",
            Level = 14,
            Id = 13211,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 2,
                MP = 5,
                MND = 1,
            }
        },
        GriotBelt = {
            Name = "Griot Belt",
            Level = 28,
            Id = 15939,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 1,
                HP = 1,
                MP = 1,
                CHR = 1,
            }
        },
        GriotBelt_1 = {
            Name = "Griot Belt +1",
            Level = 28,
            Id = 15947,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 2,
                HP = 2,
                MP = 2,
                CHR = 2,
            }
        },
        HachirinNoObi = {
            Name = "Hachirin-no-obi",
            Level = 71,
            Id = 28419,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 7,
            }
        },
        HeadlongBelt = {
            Name = "Headlong Belt",
            Level = 44,
            Id = 15941,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                Attack = 4,
                Haste = 3,
            }
        },
        HekoObi = {
            Name = "Heko Obi",
            Level = 8,
            Id = 13204,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 1,
            }
        },
        HekoObi_1 = {
            Name = "Heko Obi +1",
            Level = 8,
            Id = 13190,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 2,
            }
        },
        KoboObi = {
            Name = "Kobo Obi",
            Level = 75,
            Id = 26320,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Waist",
            Stats = {
                DEF = 6,
                MP = 25,
            }
        },
        KogaSarashi = {
            Name = "Koga Sarashi",
            Level = 70,
            Id = 15877,
            Jobs = {"NIN"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                MagicAccuracy = 2,
                Evasion = 4,
                Haste = 4,
            }
        },
        LeatherBelt = {
            Name = "Leather Belt",
            Level = 7,
            Id = 13192,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 1,
            }
        },
        LeatherBelt_1 = {
            Name = "Leather Belt +1",
            Level = 7,
            Id = 13210,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 2,
            }
        },
        LizardBelt = {
            Name = "Lizard Belt",
            Level = 17,
            Id = 13193,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 2,
            }
        },
        LizardBelt_1 = {
            Name = "Lizard Belt +1",
            Level = 17,
            Id = 13191,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 3,
            }
        },
        MarchingBelt = {
            Name = "Marching Belt",
            Level = 75,
            Id = 15953,
            Jobs = {"BRD"},
            Type = "Waist",
            Stats = {
                DEF = 3,
            }
        },
        MaridBelt = {
            Name = "Marid Belt",
            Level = 71,
            Id = 15890,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 7,
                HP = 22,
                DEX = 2,
                VIT = 5,
                HHP = 1,
            }
        },
        MaridBelt_1 = {
            Name = "Marid Belt +1",
            Level = 71,
            Id = 15893,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 8,
                HP = 24,
                DEX = 3,
                VIT = 5,
                HHP = 2,
            }
        },
        MoepapaStone = {
            Name = "Moepapa Stone",
            Level = 75,
            Id = 10817,
            Jobs = {"BST", "DRG", "SMN", "PUP"},
            Type = "Waist",
            Stats = {
                DEF = 5,
                CHR = 5,
                Haste = 5,
            }
        },
        MonsterBelt = {
            Name = "Monster Belt",
            Level = 70,
            Id = 15875,
            Jobs = {"BST"},
            Type = "Waist",
            Stats = {
                DEF = 5,
                CHR = 6,
                Accuracy = 7,
                Enmity = -3,
            }
        },
        MrcCptBelt = {
            Name = "Mrc.Cpt. Belt",
            Level = 30,
            Id = 13221,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 3,
                DEX = 1,
                VIT = 1,
                AGI = 1,
                INT = 1,
                MND = 1,
                CHR = 1,
            }
        },
        MujinObi = {
            Name = "Mujin Obi",
            Level = 75,
            Id = 11776,
            Jobs = {"WHM", "BLM", "RDM", "PLD", "DRK", "SMN", "BLU", "SCH", "GEO", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                MP = 30,
            }
        },
        NinurtasSash = {
            Name = "Ninurtas Sash",
            Level = 75,
            Id = 15458,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 6,
                Attack = 6,
                Haste = 6,
                SubtleBlow = 6,
            }
        },
        OneirosBelt = {
            Name = "Oneiros Belt",
            Level = 75,
            Id = 11773,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 8,
                HP = 45,
                STR = 3,
            }
        },
        OneirosCest = {
            Name = "Oneiros Cest",
            Level = 75,
            Id = 11774,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 5,
                Accuracy = 9,
                Haste = 3,
                StoreTP = 3,
            }
        },
        OneirosRope = {
            Name = "Oneiros Rope",
            Level = 75,
            Id = 11775,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                StoreTP = 2,
            }
        },
        OneirosSash = {
            Name = "Oneiros Sash",
            Level = 75,
            Id = 11772,
            Jobs = {"WHM", "BLM", "RDM", "SMN", "SCH", "GEO"},
            Type = "Waist",
            Stats = {
                DEF = 5,
                HP = 20,
                MP = 20,
                MagicAttackBonus = 4,
                ConserveMP = 4,
            }
        },
        PlateBelt = {
            Name = "Plate Belt",
            Level = 12,
            Id = 13227,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Waist",
            Stats = {
                DEF = 2,
            }
        },
        PurpleBelt = {
            Name = "Purple Belt",
            Level = 18,
            Id = 13201,
            Jobs = {"MNK"},
            Type = "Waist",
            Stats = {
                DEF = 2,
                STR = 3,
                Haste = 4,
            }
        },
        PythiaSash = {
            Name = "Pythia Sash",
            Level = 75,
            Id = 15949,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                MND = 5,
                Enmity = -4,
                ConserveMP = 4,
            }
        },
        PythiaSash_1 = {
            Name = "Pythia Sash +1",
            Level = 75,
            Id = 15950,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                MND = 6,
                Enmity = -4,
                ConserveMP = 5,
            }
        },
        RylKgtBelt = {
            Name = "Ryl.Kgt. Belt",
            Level = 50,
            Id = 13220,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 5,
                STR = 2,
                DEX = 2,
                AGI = 2,
                INT = 2,
                MND = 2,
                CHR = 2,
            }
        },
        SalireBelt = {
            Name = "Salire Belt",
            Level = 75,
            Id = 28425,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                MP = 25,
                MND = 5,
                MagicAccuracy = 4,
                MagicAttackBonus = 4,
            }
        },
        SaoKoshiAte = {
            Name = "Sao. Koshi-ate",
            Level = 70,
            Id = 15879,
            Jobs = {"SAM"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                DEX = 5,
                Accuracy = 7,
                RangedAccuracy = 7,
            }
        },
        ScoutsBelt = {
            Name = "Scouts Belt",
            Level = 70,
            Id = 15876,
            Jobs = {"RNG"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                AGI = 5,
                RangedAccuracy = 7,
                RangedAttack = 7,
            }
        },
        ShamansBelt = {
            Name = "Shamans Belt",
            Level = 28,
            Id = 13228,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 2,
                MP = 5,
                INT = 1,
            }
        },
        SilverObi = {
            Name = "Silver Obi",
            Level = 20,
            Id = 13205,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 2,
            }
        },
        SilverObi_1 = {
            Name = "Silver Obi +1",
            Level = 20,
            Id = 13224,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 3,
            }
        },
        SorcerersBelt = {
            Name = "Sorcerers Belt",
            Level = 70,
            Id = 15874,
            Jobs = {"BLM"},
            Type = "Waist",
            Stats = {
                DEF = 4,
                HP = 20,
                INT = 6,
            }
        },
        SpeedBelt = {
            Name = "Speed Belt",
            Level = 55,
            Id = 13189,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                Haste = 6,
            }
        },
        TiltBelt = {
            Name = "Tilt Belt",
            Level = 40,
            Id = 15286,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                DEF = 3,
                Accuracy = 5,
                Evasion = -5,
            }
        },
        TjukurrpaBelt = {
            Name = "Tjukurrpa Belt",
            Level = 75,
            Id = 10818,
            Jobs = {"WAR", "MNK", "THF", "BST", "NIN", "DRG", "BLU", "PUP", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 5,
                STR = 5,
                DoubleAttack = 1,
            }
        },
        VirtuosoBelt = {
            Name = "Virtuoso Belt",
            Level = 54,
            Id = 15943,
            Jobs = {"All"},
            Type = "Waist",
            Stats = {
                Accuracy = 12,
                Attack = 4,
            }
        },
        WarriorsBelt_1 = {
            Name = "Warriors Belt +1",
            Level = 15,
            Id = 13240,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 2,
                HP = 4,
                VIT = 3,
            }
        },
        WarriorsStone = {
            Name = "Warriors Stone",
            Level = 70,
            Id = 15871,
            Jobs = {"WAR"},
            Type = "Waist",
            Stats = {
                DEF = 5,
                STR = 5,
                Accuracy = 7,
            }
        },
        WarwolfBelt = {
            Name = "Warwolf Belt",
            Level = 71,
            Id = 15294,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Waist",
            Stats = {
                DEF = 6,
                STR = 5,
                DEX = 5,
                VIT = 5,
                Enmity = 3,
            }
        },
        WhiteBelt = {
            Name = "White Belt",
            Level = 1,
            Id = 13184,
            Jobs = {"MNK"},
            Type = "Waist",
            Stats = {
                STR = 1,
            }
        },
        WyrmBelt = {
            Name = "Wyrm Belt",
            Level = 70,
            Id = 15878,
            Jobs = {"DRG"},
            Type = "Waist",
            Stats = {
                DEF = 5,
                VIT = 5,
                Accuracy = 7,
                Attack = 7,
            }
        },
    },
    Legs = {
        AbsFlanchard_1 = {
            Name = "Abs. Flanchard +1",
            Level = 75,
            Id = 15587,
            Jobs = {"DRK"},
            Type = "Legs",
            Stats = {
                DEF = 39,
                HP = 18,
                MP = 18,
                MND = 5,
                MagicDefenseBonus = 5,
            }
        },
        AbtalZerehs = {
            Name = "Abtal Zerehs",
            Level = 59,
            Id = 15607,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM"},
            Type = "Legs",
            Stats = {
                DEF = 25,
                HP = 24,
                STR = 3,
                AGI = 4,
            }
        },
        AcroBreeches = {
            Name = "Acro Breeches",
            Level = 75,
            Id = 27233,
            Jobs = {"WAR", "PLD", "DRK", "SAM", "DRG", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 41,
                HP = 10,
                MP = 10,
                STR = 3,
                VIT = 3,
                INT = 3,
                Accuracy = 5,
            }
        },
        AdamanBreeches = {
            Name = "Adaman Breeches",
            Level = 73,
            Id = 12813,
            Jobs = {"WAR", "DRK", "BST"},
            Type = "Legs",
            Stats = {
                DEF = 37,
                MP = -20,
                VIT = -10,
                Accuracy = 6,
                Attack = 6,
                Evasion = -6,
            }
        },
        AdhemarKecks = {
            Name = "Adhemar Kecks",
            Level = 75,
            Id = 27302,
            Jobs = {"THF"},
            Type = "Legs",
            Stats = {
                DEF = 37,
                HP = 30,
                DEX = 4,
                AGI = 4,
                Haste = 4,
                Enmity = 5,
                DualWield = 3,
            }
        },
        AgwusSlops = {
            Name = "Agwus Slops",
            Level = 75,
            Id = 23780,
            Jobs = {"BLU"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                MP = 15,
                DEX = 5,
                Attack = 15,
                Haste = 3,
                Regen = 3,
                DualWield = 3,
            }
        },
        AmalricSlops = {
            Name = "Amalric Slops",
            Level = 75,
            Id = 27304,
            Jobs = {"GEO"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                MP = 25,
                INT = 5,
            }
        },
        AnglersHose = {
            Name = "Anglers Hose",
            Level = 15,
            Id = 14293,
            Jobs = {"All"},
            Type = "Legs",
            Stats = {
                DEF = 8,
            }
        },
        AresFlanchard = {
            Name = "Ares Flanchard",
            Level = 75,
            Id = 15625,
            Jobs = {"WAR", "PLD", "DRK", "DRG", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 35,
                HPP = 2,
                MPP = 2,
                STR = 6,
                DEX = 6,
                INT = -3,
                MND = -3,
                DoubleAttack = 2,
            }
        },
        ArgutePants = {
            Name = "Argute Pants",
            Level = 73,
            Id = 16362,
            Jobs = {"SCH"},
            Type = "Legs",
            Stats = {
                DEF = 27,
                HP = 15,
                MP = 15,
                INT = 5,
                Enmity = -2,
            }
        },
        ArgutePants_1 = {
            Name = "Argute Pants +1",
            Level = 75,
            Id = 16363,
            Jobs = {"SCH"},
            Type = "Legs",
            Stats = {
                DEF = 28,
                HP = 17,
                MP = 17,
                INT = 6,
                Enmity = -3,
            }
        },
        ArmadaBreeches = {
            Name = "Armada Breeches",
            Level = 73,
            Id = 14296,
            Jobs = {"WAR", "DRK", "BST"},
            Type = "Legs",
            Stats = {
                DEF = 38,
                MP = -21,
                VIT = -11,
                Accuracy = 7,
                Attack = 7,
                Evasion = -7,
            }
        },
        AsnCulottes_1 = {
            Name = "Asn. Culottes +1",
            Level = 75,
            Id = 15585,
            Jobs = {"THF"},
            Type = "Legs",
            Stats = {
                DEF = 35,
                HP = 25,
                Enmity = 5,
            }
        },
        BaguaPants = {
            Name = "Bagua Pants",
            Level = 75,
            Id = 27192,
            Jobs = {"GEO"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                MP = 20,
                INT = 5,
                MND = 3,
            }
        },
        BaguaPants_1 = {
            Name = "Bagua Pants +1",
            Level = 75,
            Id = 27193,
            Jobs = {"GEO"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                MP = 25,
                INT = 7,
                MND = 4,
            }
        },
        BahamutsHose = {
            Name = "Bahamuts Hose",
            Level = 75,
            Id = 15599,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                DEX = 6,
                Accuracy = 6,
            }
        },
        BahramCuisses = {
            Name = "Bahram Cuisses",
            Level = 73,
            Id = 16376,
            Jobs = {"WAR", "PLD", "DRK", "BST", "DRG"},
            Type = "Legs",
            Stats = {
                DEF = 36,
                STR = 5,
                Accuracy = 12,
                Evasion = -4,
                Haste = -10,
            }
        },
        BeastTrousers = {
            Name = "Beast Trousers",
            Level = 60,
            Id = 14222,
            Jobs = {"BST"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                HP = 15,
                CHR = 4,
            }
        },
        BeetleSubligar = {
            Name = "Beetle Subligar",
            Level = 21,
            Id = 12835,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 12,
            }
        },
        BeetleSubligar_1 = {
            Name = "Beetle Subligar +1",
            Level = 21,
            Id = 12913,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 13,
                Evasion = 1,
            }
        },
        BlackCuisses = {
            Name = "Black Cuisses",
            Level = 71,
            Id = 15400,
            Jobs = {"DRK"},
            Type = "Legs",
            Stats = {
                DEF = 29,
                STR = 4,
                Attack = 14,
            }
        },
        BlessedTrousers = {
            Name = "Blessed Trousers",
            Level = 70,
            Id = 15391,
            Jobs = {"WHM"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                MP = 25,
                MND = 6,
                Haste = 3,
                Enmity = -5,
            }
        },
        BloodCuisses = {
            Name = "Blood Cuisses",
            Level = 73,
            Id = 14281,
            Jobs = {"RDM", "PLD", "DRK", "RNG", "DRG", "BLU", "COR", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 44,
                HP = 27,
                MP = 27,
                MovementSpeed = 18,
            }
        },
        BlsTrousers_1 = {
            Name = "Bls. Trousers +1",
            Level = 70,
            Id = 15393,
            Jobs = {"WHM"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                MP = 30,
                MND = 7,
                Haste = 4,
                Enmity = -6,
            }
        },
        Brais = {
            Name = "Brais",
            Level = 11,
            Id = 12848,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 7,
            }
        },
        Brais_1 = {
            Name = "Brais +1",
            Level = 11,
            Id = 12896,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 8,
            }
        },
        BravosSubligar = {
            Name = "Bravos Subligar",
            Level = 47,
            Id = 15373,
            Jobs = {"THF"},
            Type = "Legs",
            Stats = {
                DEF = 20,
                RangedAccuracy = 3,
                Haste = 2,
            }
        },
        BrdCannions_1 = {
            Name = "Brd. Cannions +1",
            Level = 75,
            Id = 15589,
            Jobs = {"BRD"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                HP = 26,
                MP = 42,
            }
        },
        BstTrousers_1 = {
            Name = "Bst. Trousers +1",
            Level = 74,
            Id = 15569,
            Jobs = {"BST"},
            Type = "Legs",
            Stats = {
                DEF = 34,
                HP = 15,
                STR = 6,
                CHR = 6,
            }
        },
        BunzisPants = {
            Name = "Bunzis Pants",
            Level = 75,
            Id = 23781,
            Jobs = {"WHM"},
            Type = "Legs",
            Stats = {
                DEF = 34,
                MP = 25,
                VIT = 5,
                INT = 5,
                HMP = 3,
            }
        },
        ByakkosHaidate = {
            Name = "Byakkos Haidate",
            Level = 75,
            Id = 12818,
            Jobs = {"WAR", "MNK", "BST", "BRD", "RNG", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 42,
                DEX = 15,
                Haste = 5,
            }
        },
        ChainHose = {
            Name = "Chain Hose",
            Level = 24,
            Id = 12808,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 16,
            }
        },
        ChironicHose = {
            Name = "Chironic Hose",
            Level = 75,
            Id = 25844,
            Jobs = {"SMN"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                MP = 20,
                Enmity = -3,
                HMP = 3,
            }
        },
        ChlCannions_1 = {
            Name = "Chl. Cannions +1",
            Level = 74,
            Id = 15570,
            Jobs = {"BRD"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                HP = 12,
                STR = 8,
                DEX = 8,
                Enmity = -2,
            }
        },
        ChoralCannions = {
            Name = "Choral Cannions",
            Level = 56,
            Id = 14223,
            Jobs = {"BRD"},
            Type = "Legs",
            Stats = {
                DEF = 27,
                HP = 12,
                STR = 5,
                Enmity = -1,
            }
        },
        ChsFlanchard_1 = {
            Name = "Chs. Flanchard +1",
            Level = 74,
            Id = 15568,
            Jobs = {"DRK"},
            Type = "Legs",
            Stats = {
                DEF = 38,
                HP = 15,
                MP = 15,
                DEX = 5,
                INT = 5,
                Evasion = 5,
            }
        },
        ClericsPantaln = {
            Name = "Clerics Pantaln.",
            Level = 73,
            Id = 15119,
            Jobs = {"WHM"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                MP = 17,
                Enmity = -2,
            }
        },
        CommTrews_1 = {
            Name = "Comm. Trews +1",
            Level = 75,
            Id = 16350,
            Jobs = {"COR"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                HP = 22,
                STR = 3,
                AGI = 3,
                Attack = 7,
                Evasion = 7,
            }
        },
        CorCulottes_1 = {
            Name = "Cor. Culottes +1",
            Level = 74,
            Id = 16348,
            Jobs = {"COR"},
            Type = "Legs",
            Stats = {
                DEF = 29,
                HP = 25,
                AGI = 5,
                INT = 5,
                Enmity = -4,
            }
        },
        CrimsonCuisses = {
            Name = "Crimson Cuisses",
            Level = 73,
            Id = 14280,
            Jobs = {"RDM", "PLD", "DRK", "RNG", "DRG", "BLU", "COR", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 43,
                HP = 25,
                MP = 25,
                MovementSpeed = 12,
            }
        },
        DancersTights_1 = {
            Name = "Dancers Tights +1",
            Level = 74,
            Id = 16357,
            Jobs = {"DNC"},
            Type = "Legs",
            Stats = {
                DEF = 29,
                HP = 15,
                VIT = 5,
                CHR = 5,
                Accuracy = 5,
                Attack = 5,
                Enmity = -1,
            }
        },
        DinoTrousers = {
            Name = "Dino Trousers",
            Level = 48,
            Id = 12919,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 26,
            }
        },
        DlsTights_1 = {
            Name = "Dls. Tights +1",
            Level = 75,
            Id = 15584,
            Jobs = {"RDM"},
            Type = "Legs",
            Stats = {
                DEF = 34,
                MP = 16,
                DEX = 6,
            }
        },
        DragonCuisses = {
            Name = "Dragon Cuisses",
            Level = 69,
            Id = 12820,
            Jobs = {"DRG"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                HP = 11,
            }
        },
        DragonCuisses_1 = {
            Name = "Dragon Cuisses +1",
            Level = 69,
            Id = 14231,
            Jobs = {"DRG"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                HP = 13,
            }
        },
        DragonSubligar = {
            Name = "Dragon Subligar",
            Level = 73,
            Id = 14305,
            Jobs = {"THF"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                DEX = 4,
                Enmity = 2,
                SubtleBlow = 5,
            }
        },
        DrnBrais_1 = {
            Name = "Drn. Brais +1",
            Level = 74,
            Id = 15574,
            Jobs = {"DRG"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                HP = 15,
                Accuracy = 9,
            }
        },
        DrnSubligar_1 = {
            Name = "Drn. Subligar +1",
            Level = 73,
            Id = 14306,
            Jobs = {"THF"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                DEX = 5,
                Enmity = 3,
                SubtleBlow = 6,
            }
        },
        DstBreeches = {
            Name = "Dst. Breeches",
            Level = 59,
            Id = 12811,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 33,
            }
        },
        DstBreeches_1 = {
            Name = "Dst. Breeches +1",
            Level = 59,
            Id = 14209,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 34,
            }
        },
        DuelistsTights = {
            Name = "Duelists Tights",
            Level = 73,
            Id = 15121,
            Jobs = {"RDM"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                MP = 16,
                DEX = 5,
            }
        },
        DuxCuisses = {
            Name = "Dux Cuisses",
            Level = 70,
            Id = 10346,
            Jobs = {"RUN"},
            Type = "Legs",
            Stats = {
                DEF = 40,
                STR = 7,
                Attack = 11,
                Enmity = 5,
            }
        },
        DuxCuisses_1 = {
            Name = "Dux Cuisses +1",
            Level = 70,
            Id = 10347,
            Jobs = {"RUN"},
            Type = "Legs",
            Stats = {
                DEF = 41,
                STR = 8,
                Attack = 12,
                Enmity = 6,
            }
        },
        Eisendiechlings = {
            Name = "Eisendiechlings",
            Level = 29,
            Id = 14329,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Legs",
            Stats = {
                DEF = 17,
                VIT = 1,
                AGI = 1,
            }
        },
        EnticersPants = {
            Name = "Enticers Pants",
            Level = 73,
            Id = 27323,
            Jobs = {"BST", "BRD", "SMN", "PUP", "GEO"},
            Type = "Legs",
            Stats = {
                DEF = 40,
                MP = 38,
                Attack = 8,
                Haste = 3,
                SubtleBlow = 4,
                Counter = 2,
            }
        },
        EtoileTights_1 = {
            Name = "Etoile Tights +1",
            Level = 75,
            Id = 16361,
            Jobs = {"DNC"},
            Type = "Legs",
            Stats = {
                DEF = 29,
                STR = 4,
                CHR = 4,
                Haste = 3,
            }
        },
        EvkSpats_1 = {
            Name = "Evk. Spats +1",
            Level = 74,
            Id = 15575,
            Jobs = {"SMN"},
            Type = "Legs",
            Stats = {
                DEF = 25,
                MP = 22,
                Enmity = -3,
            }
        },
        FieldHose = {
            Name = "Field Hose",
            Level = 1,
            Id = 14297,
            Jobs = {"All"},
            Type = "Legs",
            Stats = {
                DEF = 1,
            }
        },
        FoundersHose = {
            Name = "Founders Hose",
            Level = 75,
            Id = 28191,
            Jobs = {"PLD"},
            Type = "Legs",
            Stats = {
                DEF = 46,
                HP = 20,
                MP = 15,
                STR = 5,
                DEX = 5,
                Haste = 5,
                DoubleAttack = 3,
            }
        },
        FtrCuisses_1 = {
            Name = "Ftr. Cuisses +1",
            Level = 74,
            Id = 15561,
            Jobs = {"WAR"},
            Type = "Legs",
            Stats = {
                DEF = 39,
                HP = 15,
                Accuracy = 5,
                Evasion = 5,
                Enmity = 3,
                HHP = 2,
            }
        },
        FutharkTrousers = {
            Name = "Futhark Trousers",
            Level = 75,
            Id = 27194,
            Jobs = {"RUN"},
            Type = "Legs",
            Stats = {
                DEF = 41,
                HP = 20,
                MP = 20,
                DEX = 7,
                VIT = 7,
                FastCast = 10,
            }
        },
        FutharkTrousers_1 = {
            Name = "Futhark Trousers +1",
            Level = 75,
            Id = 27195,
            Jobs = {"RUN"},
            Type = "Legs",
            Stats = {
                DEF = 42,
                HP = 27,
                MP = 27,
                DEX = 8,
                VIT = 8,
                FastCast = 10,
            }
        },
        GarishSlacks = {
            Name = "Garish Slacks",
            Level = 30,
            Id = 14326,
            Jobs = {"MNK", "RDM", "PLD", "BRD", "RNG", "BLU", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 15,
            }
        },
        GarrisonHose = {
            Name = "Garrison Hose",
            Level = 20,
            Id = 14314,
            Jobs = {"All"},
            Type = "Legs",
            Stats = {
                DEF = 9,
                STR = 1,
                DEX = 1,
            }
        },
        GarrisonHose_1 = {
            Name = "Garrison Hose +1",
            Level = 20,
            Id = 25907,
            Jobs = {"All"},
            Type = "Legs",
            Stats = {
                DEF = 12,
                HP = 8,
                STR = 2,
                DEX = 2,
            }
        },
        GenieLappas = {
            Name = "Genie Lappas",
            Level = 73,
            Id = 14322,
            Jobs = {"BLM"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                Evasion = 11,
            }
        },
        GeomancyPants = {
            Name = "Geomancy Pants",
            Level = 75,
            Id = 28206,
            Jobs = {"GEO"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                MP = 20,
                FastCast = 10,
            }
        },
        GletisBreeches = {
            Name = "Gletis Breeches",
            Level = 75,
            Id = 23777,
            Jobs = {"DRK"},
            Type = "Legs",
            Stats = {
                DEF = 41,
                HP = 15,
                MP = 15,
                DEX = 5,
                INT = 5,
                Enmity = 5,
            }
        },
        GltBreeches_1 = {
            Name = "Glt. Breeches +1",
            Level = 74,
            Id = 15567,
            Jobs = {"PLD"},
            Type = "Legs",
            Stats = {
                DEF = 43,
                HP = 20,
                AGI = 4,
                Enmity = 2,
            }
        },
        HachimanHakama = {
            Name = "Hachiman Hakama",
            Level = 70,
            Id = 15392,
            Jobs = {"SAM"},
            Type = "Legs",
            Stats = {
                DEF = 36,
                StoreTP = 3,
            }
        },
        HailstoneHose = {
            Name = "Hailstone Hose",
            Level = 75,
            Id = 28166,
            Jobs = {"THF", "RNG", "NIN", "COR"},
            Type = "Legs",
            Stats = {
                HP = 25,
                RangedAttack = 10,
                MagicAttackBonus = 5,
                Haste = 3,
            }
        },
        HctSubligar_1 = {
            Name = "Hct. Subligar +1",
            Level = 73,
            Id = 14309,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 43,
                HP = 17,
                DEX = 9,
                Attack = 22,
                Haste = -14,
            }
        },
        HecatombSubligar = {
            Name = "Hecatomb Subligar",
            Level = 73,
            Id = 14308,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 42,
                HP = 15,
                DEX = 8,
                Attack = 20,
                Haste = -12,
            }
        },
        HeliosSpats = {
            Name = "Helios Spats",
            Level = 75,
            Id = 27236,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Legs",
            Stats = {
                DEF = 36,
                MP = 20,
                STR = 3,
                INT = 3,
                MND = 3,
                MagicAccuracy = 5,
                FastCast = 3,
            }
        },
        HerculeanTrousers = {
            Name = "Herculean Trousers",
            Level = 75,
            Id = 25842,
            Jobs = {"RNG"},
            Type = "Legs",
            Stats = {
                DEF = 35,
                HP = 25,
                RangedAccuracy = 6,
                StoreTP = 6,
            }
        },
        HerdersSubligar = {
            Name = "Herders Subligar",
            Level = 25,
            Id = 16368,
            Jobs = {"BST", "DRG", "SMN", "PUP"},
            Type = "Legs",
            Stats = {
                DEF = 8,
            }
        },
        HlrPantaln_1 = {
            Name = "Hlr. Pantaln. +1",
            Level = 74,
            Id = 15563,
            Jobs = {"WHM"},
            Type = "Legs",
            Stats = {
                DEF = 28,
                MP = 30,
                VIT = 5,
                Enmity = -2,
            }
        },
        HmnHakama_1 = {
            Name = "Hmn. Hakama +1",
            Level = 70,
            Id = 15394,
            Jobs = {"SAM"},
            Type = "Legs",
            Stats = {
                DEF = 37,
                StoreTP = 4,
            }
        },
        HomamCosciales = {
            Name = "Homam Cosciales",
            Level = 75,
            Id = 15576,
            Jobs = {"THF", "PLD", "DRK", "DRG", "BLU", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 35,
                HP = 26,
                MP = 26,
                Accuracy = 3,
                Haste = 3,
                FastCast = 5,
            }
        },
        HtrBraccae_1 = {
            Name = "Htr. Braccae +1",
            Level = 74,
            Id = 15571,
            Jobs = {"RNG"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                HP = 15,
                AGI = 5,
                MND = 5,
                Enmity = -3,
            }
        },
        HumeSlacks = {
            Name = "Hume Slacks",
            Level = 1,
            Id = 12883,
            Jobs = {"All"},
            Type = "Legs",
            Stats = {
                DEF = 2,
            }
        },
        IgqiraLappas = {
            Name = "Igqira Lappas",
            Level = 73,
            Id = 14321,
            Jobs = {"BLM"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                Evasion = 10,
            }
        },
        IkengasTrousers = {
            Name = "Ikengas Trousers",
            Level = 75,
            Id = 23776,
            Jobs = {"COR"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                HP = 30,
                Enmity = -5,
                Regen = 1,
            }
        },
        IronRamHose = {
            Name = "Iron Ram Hose",
            Level = 68,
            Id = 16315,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Legs",
            Stats = {
                DEF = 36,
                HP = 28,
                MagicDefenseBonus = 4,
                Enmity = 4,
            }
        },
        JetSeraweels = {
            Name = "Jet Seraweels",
            Level = 72,
            Id = 15613,
            Jobs = {"WHM", "BLM", "RDM", "PLD", "DRK", "SMN", "BLU", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 34,
                MP = 15,
                INT = 7,
                MND = 7,
                Enmity = -4,
            }
        },
        JokushuHaidate = {
            Name = "Jokushu Haidate",
            Level = 75,
            Id = 27318,
            Jobs = {"WAR", "MNK", "BST", "BRD", "RNG", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 44,
                DEX = 18,
                Haste = 5,
                StoreTP = 5,
            }
        },
        JujitsuSitabaki = {
            Name = "Jujitsu Sitabaki",
            Level = 37,
            Id = 12923,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 18,
                DEX = 1,
                VIT = 1,
            }
        },
        KaiserDiechlings = {
            Name = "Kaiser Diechlings",
            Level = 73,
            Id = 14283,
            Jobs = {"WAR", "PLD"},
            Type = "Legs",
            Stats = {
                DEF = 46,
                HP = 42,
                STR = -6,
                DEX = -6,
                VIT = 11,
                CHR = 11,
                Evasion = 11,
            }
        },
        Kampfdiechlings = {
            Name = "Kampfdiechlings",
            Level = 29,
            Id = 14332,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Legs",
            Stats = {
                DEF = 18,
                VIT = 2,
                AGI = 2,
            }
        },
        KhimairaKecks = {
            Name = "Khimaira Kecks",
            Level = 71,
            Id = 15645,
            Jobs = {"BST"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                HP = 15,
                MP = 15,
                Enmity = -4,
            }
        },
        KingsCuisses = {
            Name = "Kings Cuisses",
            Level = 70,
            Id = 15399,
            Jobs = {"PLD"},
            Type = "Legs",
            Stats = {
                DEF = 39,
                HP = 12,
                VIT = 3,
                Enmity = 3,
            }
        },
        KoenigDiechlings = {
            Name = "Koenig Diechlings",
            Level = 73,
            Id = 12805,
            Jobs = {"WAR", "PLD"},
            Type = "Legs",
            Stats = {
                DEF = 45,
                HP = 40,
                STR = -5,
                DEX = -5,
                VIT = 10,
                CHR = 10,
                Evasion = 10,
            }
        },
        KogHakama_1 = {
            Name = "Kog. Hakama +1",
            Level = 75,
            Id = 15592,
            Jobs = {"NIN"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                HP = 40,
                DualWield = 5,
            }
        },
        LeatherTrousers = {
            Name = "Leather Trousers",
            Level = 7,
            Id = 12824,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 5,
            }
        },
        LinenSlops = {
            Name = "Linen Slops",
            Level = 12,
            Id = 12857,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 7,
            }
        },
        LinenSlops_1 = {
            Name = "Linen Slops +1",
            Level = 12,
            Id = 12901,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 8,
            }
        },
        LordsCuisses = {
            Name = "Lords Cuisses",
            Level = 70,
            Id = 15395,
            Jobs = {"PLD"},
            Type = "Legs",
            Stats = {
                DEF = 38,
                VIT = 2,
                Enmity = 2,
            }
        },
        LthTrousers_1 = {
            Name = "Lth. Trousers +1",
            Level = 7,
            Id = 12908,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 6,
            }
        },
        MagesSlops = {
            Name = "Mages Slops",
            Level = 38,
            Id = 12918,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 18,
                MP = 2,
            }
        },
        MagusShalwar_1 = {
            Name = "Magus Shalwar +1",
            Level = 74,
            Id = 16345,
            Jobs = {"BLU"},
            Type = "Legs",
            Stats = {
                DEF = 34,
                HP = 25,
                DEX = 5,
                VIT = 5,
                AGI = 5,
            }
        },
        MalignanceTights = {
            Name = "Malignance Tights",
            Level = 75,
            Id = 23735,
            Jobs = {"RDM"},
            Type = "Legs",
            Stats = {
                DEF = 36,
                MP = 25,
                DEX = 5,
                AGI = 5,
                Haste = 5,
                StoreTP = 5,
            }
        },
        MarduksShalwar = {
            Name = "Marduks Shalwar",
            Level = 75,
            Id = 15637,
            Jobs = {"WHM", "BRD", "SMN", "SCH"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                MPP = 3,
                CHR = 10,
                Enmity = -4,
            }
        },
        MelHose_1 = {
            Name = "Mel. Hose +1",
            Level = 75,
            Id = 15581,
            Jobs = {"MNK"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                HPP = 6,
                AGI = 5,
                SubtleBlow = 6,
            }
        },
        MerlinicShalwar = {
            Name = "Merlinic Shalwar",
            Level = 75,
            Id = 25843,
            Jobs = {"SCH"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                MP = 25,
                INT = 3,
                MND = 3,
                MagicAttackBonus = 6,
            }
        },
        MirageShalwar_1 = {
            Name = "Mirage Shalwar +1",
            Level = 75,
            Id = 16347,
            Jobs = {"BLU"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                HP = 15,
                MP = 15,
                STR = 3,
                Accuracy = 5,
                MagicAccuracy = 5,
            }
        },
        MorrigansSlops = {
            Name = "Morrigans Slops",
            Level = 75,
            Id = 15641,
            Jobs = {"BLM", "RDM", "BLU", "GEO"},
            Type = "Legs",
            Stats = {
                DEF = 27,
                MP = 25,
                STR = 3,
                INT = 10,
                MND = 10,
                Enmity = -2,
            }
        },
        MpacasHose = {
            Name = "Mpacas Hose",
            Level = 75,
            Id = 23779,
            Jobs = {"NIN"},
            Type = "Legs",
            Stats = {
                DEF = 34,
                HP = 25,
                MagicAccuracy = 6,
                Haste = 5,
            }
        },
        MstTrousers_1 = {
            Name = "Mst. Trousers +1",
            Level = 75,
            Id = 15588,
            Jobs = {"BST"},
            Type = "Legs",
            Stats = {
                DEF = 35,
                HP = 17,
                DEX = 5,
                HHP = 4,
            }
        },
        MynHaidate_1 = {
            Name = "Myn. Haidate +1",
            Level = 74,
            Id = 15572,
            Jobs = {"SAM"},
            Type = "Legs",
            Stats = {
                DEF = 40,
                HP = 15,
                STR = 5,
                VIT = 5,
                StoreTP = 4,
            }
        },
        MythrilCuisses = {
            Name = "Mythril Cuisses",
            Level = 49,
            Id = 12801,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Legs",
            Stats = {
                DEF = 28,
            }
        },
        MythrilCuisses_1 = {
            Name = "Mythril Cuisses +1",
            Level = 49,
            Id = 14211,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Legs",
            Stats = {
                DEF = 29,
                INT = 1,
            }
        },
        NagaHakama = {
            Name = "Naga Hakama",
            Level = 75,
            Id = 27284,
            Jobs = {"MNK"},
            Type = "Legs",
            Stats = {
                DEF = 34,
                HPP = 5,
                Haste = 5,
            }
        },
        NashiraSeraweels = {
            Name = "Nashira Seraweels",
            Level = 75,
            Id = 15577,
            Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "GEO"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                MagicAccuracy = 3,
                Haste = 2,
            }
        },
        NinHakama_1 = {
            Name = "Nin. Hakama +1",
            Level = 74,
            Id = 15573,
            Jobs = {"NIN"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                Accuracy = 5,
                RangedAccuracy = 10,
            }
        },
        NoctBrais = {
            Name = "Noct Brais",
            Level = 30,
            Id = 14323,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Legs",
            Stats = {
                DEF = 12,
                DEX = 1,
                RangedAccuracy = 1,
            }
        },
        NoctBrais_1 = {
            Name = "Noct Brais +1",
            Level = 30,
            Id = 14333,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Legs",
            Stats = {
                DEF = 13,
                DEX = 2,
                RangedAccuracy = 2,
            }
        },
        OdysseanCuisses = {
            Name = "Odyssean Cuisses",
            Level = 75,
            Id = 25840,
            Jobs = {"DRG"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                HP = 15,
                MP = 25,
                Attack = 10,
                Haste = 5,
            }
        },
        OnyxCuisses = {
            Name = "Onyx Cuisses",
            Level = 71,
            Id = 15401,
            Jobs = {"DRK"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                STR = 5,
                Attack = 16,
            }
        },
        PhlTrousers = {
            Name = "Phl. Trousers",
            Level = 15,
            Id = 16367,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 10,
                STR = 1,
            }
        },
        PlainHose_1 = {
            Name = "Plain Hose +1",
            Level = 40,
            Id = 25898,
            Jobs = {"All"},
            Type = "Legs",
            Stats = {
                DEF = 18,
            }
        },
        PtnChuridars_1 = {
            Name = "Ptn. Churidars +1",
            Level = 75,
            Id = 16353,
            Jobs = {"PUP"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                HP = 13,
                STR = 2,
                VIT = 2,
                Accuracy = 7,
            }
        },
        PupChuridars = {
            Name = "Pup. Churidars",
            Level = 52,
            Id = 15602,
            Jobs = {"PUP"},
            Type = "Legs",
            Stats = {
                DEF = 25,
                HP = 11,
                CHR = 3,
            }
        },
        PupChuridars_1 = {
            Name = "Pup. Churidars +1",
            Level = 74,
            Id = 16351,
            Jobs = {"PUP"},
            Type = "Legs",
            Stats = {
                DEF = 26,
                HP = 16,
                DEX = 5,
                CHR = 5,
            }
        },
        PursuersPants = {
            Name = "Pursuers Pants",
            Level = 75,
            Id = 27286,
            Jobs = {"BRD"},
            Type = "Legs",
            Stats = {
                DEF = 34,
                HP = 15,
                MP = 15,
                Haste = 5,
                StoreTP = 5,
            }
        },
        RaptorTrousers = {
            Name = "Raptor Trousers",
            Level = 48,
            Id = 12828,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 25,
            }
        },
        RawhideTrousers = {
            Name = "Rawhide Trousers",
            Level = 75,
            Id = 27285,
            Jobs = {"DNC"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                HP = 15,
                STR = 5,
                AGI = 5,
                Accuracy = 5,
                Haste = 3,
                Enmity = -5,
            }
        },
        RepublicSubligar = {
            Name = "Republic Subligar",
            Level = 25,
            Id = 14260,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 13,
                VIT = 1,
                Attack = 5,
                RangedAttack = 5,
            }
        },
        RogCulottes_1 = {
            Name = "Rog. Culottes +1",
            Level = 74,
            Id = 15566,
            Jobs = {"THF"},
            Type = "Legs",
            Stats = {
                DEF = 34,
                HP = 15,
                DEX = 2,
                AGI = 4,
            }
        },
        RoguesCulottes = {
            Name = "Rogues Culottes",
            Level = 56,
            Id = 14219,
            Jobs = {"THF"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                HP = 15,
                AGI = 4,
            }
        },
        RubiousSlacks = {
            Name = "Rubious Slacks",
            Level = 30,
            Id = 14330,
            Jobs = {"MNK", "RDM", "PLD", "BRD", "RNG", "BLU", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 16,
            }
        },
        RuneistTrousers = {
            Name = "Runeist Trousers",
            Level = 75,
            Id = 28207,
            Jobs = {"RUN"},
            Type = "Legs",
            Stats = {
                DEF = 40,
                HP = 15,
                MP = 15,
                STR = 7,
                Enmity = 5,
            }
        },
        RyuoHakama = {
            Name = "Ryuo Hakama",
            Level = 75,
            Id = 27300,
            Jobs = {"SAM"},
            Type = "Legs",
            Stats = {
                DEF = 43,
                HP = 25,
                STR = 5,
                DEX = 5,
                StoreTP = 5,
            }
        },
        SakpatasCuisses = {
            Name = "Sakpatas Cuisses",
            Level = 75,
            Id = 23778,
            Jobs = {"WAR"},
            Type = "Legs",
            Stats = {
                DEF = 42,
                DEX = 5,
                VIT = 5,
                Haste = 5,
            }
        },
        SamnuhaTights = {
            Name = "Samnuha Tights",
            Level = 75,
            Id = 27295,
            Jobs = {"MNK", "THF", "RNG", "NIN", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 42,
                HP = 35,
                STR = 3,
                Accuracy = -5,
                Evasion = -5,
                Haste = 6,
                StoreTP = 2,
            }
        },
        SaoHaidate_1 = {
            Name = "Sao. Haidate +1",
            Level = 75,
            Id = 15591,
            Jobs = {"SAM"},
            Type = "Legs",
            Stats = {
                DEF = 41,
                HP = 33,
                AGI = 4,
                Enmity = 1,
            }
        },
        ScaleCuisses = {
            Name = "Scale Cuisses",
            Level = 10,
            Id = 12816,
            Jobs = {"WAR", "RDM", "PLD", "DRK", "BST", "RNG", "SAM", "DRG", "BLU", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 7,
            }
        },
        ScholarsPants = {
            Name = "Scholars Pants",
            Level = 56,
            Id = 16311,
            Jobs = {"SCH"},
            Type = "Legs",
            Stats = {
                DEF = 27,
                MP = 20,
                Enmity = -1,
            }
        },
        ScholarsPants_1 = {
            Name = "Scholars Pants +1",
            Level = 74,
            Id = 16359,
            Jobs = {"SCH"},
            Type = "Legs",
            Stats = {
                DEF = 28,
                MP = 25,
                VIT = 3,
                MND = 3,
                Enmity = -2,
            }
        },
        SctBraccae_1 = {
            Name = "Sct. Braccae +1",
            Level = 75,
            Id = 15590,
            Jobs = {"RNG"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                HP = 18,
                RangedAccuracy = 9,
                Enmity = -3,
            }
        },
        SeersSlacks = {
            Name = "Seers Slacks",
            Level = 29,
            Id = 14325,
            Jobs = {"WHM", "BLM", "SMN", "PUP", "SCH", "GEO"},
            Type = "Legs",
            Stats = {
                DEF = 12,
                MP = 9,
                INT = 1,
            }
        },
        SeersSlacks_1 = {
            Name = "Seers Slacks +1",
            Level = 29,
            Id = 14328,
            Jobs = {"WHM", "BLM", "SMN", "PUP", "SCH", "GEO"},
            Type = "Legs",
            Stats = {
                DEF = 13,
                MP = 10,
                INT = 1,
            }
        },
        ShadeTights = {
            Name = "Shade Tights",
            Level = 25,
            Id = 14327,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 14,
            }
        },
        ShadeTights_1 = {
            Name = "Shade Tights +1",
            Level = 25,
            Id = 14331,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 15,
                Evasion = 1,
            }
        },
        ShadowCuishes = {
            Name = "Shadow Cuishes",
            Level = 75,
            Id = 15655,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Legs",
            Stats = {
                DEF = 40,
                HP = 25,
                MP = 25,
                INT = 4,
                MND = 4,
                Accuracy = 5,
                Attack = 9,
            }
        },
        ShadowTrews = {
            Name = "Shadow Trews",
            Level = 75,
            Id = 15657,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Legs",
            Stats = {
                DEF = 28,
                MagicAccuracy = 4,
                MagicAttackBonus = 4,
                Enmity = -2,
            }
        },
        ShairSeraweels = {
            Name = "Shair Seraweels",
            Level = 72,
            Id = 14315,
            Jobs = {"BRD"},
            Type = "Legs",
            Stats = {
                DEF = 37,
                HPP = 2,
                MPP = 1,
                CHR = 8,
            }
        },
        SheikhSeraweels = {
            Name = "Sheikh Seraweels",
            Level = 72,
            Id = 14316,
            Jobs = {"BRD"},
            Type = "Legs",
            Stats = {
                DEF = 38,
                HPP = 3,
                MPP = 2,
                CHR = 9,
            }
        },
        ShinobiHakama = {
            Name = "Shinobi Hakama",
            Level = 49,
            Id = 12844,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 23,
            }
        },
        ShnHakama_1 = {
            Name = "Shn. Hakama +1",
            Level = 49,
            Id = 12925,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 24,
                AGI = 1,
            }
        },
        ShuraHaidate = {
            Name = "Shura Haidate",
            Level = 73,
            Id = 14303,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                HP = -35,
                STR = 5,
                Accuracy = 7,
            }
        },
        ShuraHaidate_1 = {
            Name = "Shura Haidate +1",
            Level = 73,
            Id = 14304,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                HP = -40,
                STR = 6,
                Accuracy = 8,
            }
        },
        SilverHose = {
            Name = "Silver Hose",
            Level = 36,
            Id = 12809,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 20,
            }
        },
        SilverHose_1 = {
            Name = "Silver Hose +1",
            Level = 36,
            Id = 12894,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "NIN"},
            Type = "Legs",
            Stats = {
                DEF = 21,
            }
        },
        SipahiZerehs = {
            Name = "Sipahi Zerehs",
            Level = 59,
            Id = 15603,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM"},
            Type = "Legs",
            Stats = {
                DEF = 24,
                HP = 22,
                STR = 2,
                AGI = 3,
            }
        },
        SkadisChausses = {
            Name = "Skadis Chausses",
            Level = 75,
            Id = 15629,
            Jobs = {"THF", "BST", "RNG", "COR", "DNC"},
            Type = "Legs",
            Stats = {
                DEF = 28,
                Accuracy = 4,
                Attack = 5,
                RangedAccuracy = 4,
                RangedAttack = 5,
                Haste = 2,
                StoreTP = 7,
            }
        },
        Slacks = {
            Name = "Slacks",
            Level = 8,
            Id = 12864,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 5,
            }
        },
        Slacks_1 = {
            Name = "Slacks +1",
            Level = 8,
            Id = 12898,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 6,
            }
        },
        SmnSpats_1 = {
            Name = "Smn. Spats +1",
            Level = 75,
            Id = 15594,
            Jobs = {"SMN"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                MP = 25,
            }
        },
        SoilSitabaki = {
            Name = "Soil Sitabaki",
            Level = 29,
            Id = 12842,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Legs",
            Stats = {
                DEF = 14,
            }
        },
        SoilSitabaki_1 = {
            Name = "Soil Sitabaki +1",
            Level = 29,
            Id = 12905,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Legs",
            Stats = {
                DEF = 15,
            }
        },
        SolidCuisses = {
            Name = "Solid Cuisses",
            Level = 10,
            Id = 12863,
            Jobs = {"WAR", "RDM", "PLD", "DRK", "BST", "RNG", "SAM", "DRG", "BLU", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 8,
            }
        },
        SrcTonban_1 = {
            Name = "Src. Tonban +1",
            Level = 75,
            Id = 15583,
            Jobs = {"BLM"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                MP = 20,
                INT = 3,
                Enmity = -3,
            }
        },
        SthiraTrousers = {
            Name = "Sthira Trousers",
            Level = 71,
            Id = 10578,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                AGI = 6,
                Attack = 6,
            }
        },
        StoutKecks = {
            Name = "Stout Kecks",
            Level = 71,
            Id = 15646,
            Jobs = {"BST"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                HP = 16,
                MP = 16,
                Enmity = -5,
            }
        },
        TaeonTights = {
            Name = "Taeon Tights",
            Level = 75,
            Id = 27234,
            Jobs = {"MNK", "THF", "BST", "RNG", "NIN", "COR", "PUP", "DNC"},
            Type = "Legs",
            Stats = {
                DEF = 38,
                HP = 20,
                STR = 3,
                DEX = 3,
                INT = 3,
                RangedAccuracy = 5,
                Haste = 4,
            }
        },
        ThurandautTights = {
            Name = "Thurandaut Tights",
            Level = 75,
            Id = 28204,
            Jobs = {"PUP"},
            Type = "Legs",
            Stats = {
                DEF = 35,
                HP = 15,
                VIT = 5,
                AGI = 5,
                Accuracy = 6,
                Attack = 6,
            }
        },
        TplHose_1 = {
            Name = "Tpl. Hose +1",
            Level = 74,
            Id = 15562,
            Jobs = {"MNK"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                HP = 18,
                MND = 4,
                Counter = 3,
            }
        },
        UcnSubligar_1 = {
            Name = "Ucn. Subligar +1",
            Level = 74,
            Id = 15407,
            Jobs = {"WAR"},
            Type = "Legs",
            Stats = {
                DEF = 51,
                HP = 46,
                DEX = 5,
            }
        },
        UnicornSubligar = {
            Name = "Unicorn Subligar",
            Level = 74,
            Id = 15406,
            Jobs = {"WAR"},
            Type = "Legs",
            Stats = {
                DEF = 49,
                HP = 42,
                DEX = 4,
            }
        },
        UrjaTrousers = {
            Name = "Urja Trousers",
            Level = 71,
            Id = 10577,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                AGI = 5,
                Attack = 5,
            }
        },
        UsukaneHizayoroi = {
            Name = "Usukane Hizayoroi",
            Level = 75,
            Id = 15633,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Legs",
            Stats = {
                DEF = 30,
                STR = 5,
                DEX = 5,
                Attack = 10,
                Haste = 3,
            }
        },
        ValkyriesCuishes = {
            Name = "Valkyries Cuishes",
            Level = 75,
            Id = 15656,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Legs",
            Stats = {
                DEF = 41,
                HP = 27,
                MP = 27,
                INT = 5,
                MND = 5,
                Accuracy = 6,
                Attack = 10,
            }
        },
        ValkyriesTrews = {
            Name = "Valkyries Trews",
            Level = 75,
            Id = 15658,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Legs",
            Stats = {
                DEF = 29,
                MagicAccuracy = 5,
                MagicAttackBonus = 5,
                Enmity = -3,
            }
        },
        ValorousHose = {
            Name = "Valorous Hose",
            Level = 75,
            Id = 25841,
            Jobs = {"BST"},
            Type = "Legs",
            Stats = {
                DEF = 37,
                HP = 25,
                DEX = 6,
                AGI = 6,
                Haste = 5,
            }
        },
        VanyaSlops = {
            Name = "Vanya Slops",
            Level = 75,
            Id = 27288,
            Jobs = {"BLM"},
            Type = "Legs",
            Stats = {
                DEF = 22,
                MP = 20,
                Haste = 5,
                StoreTP = 5,
            }
        },
        VelvetSlops = {
            Name = "Velvet Slops",
            Level = 38,
            Id = 12859,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 17,
            }
        },
        VendorsSlops = {
            Name = "Vendors Slops",
            Level = 71,
            Id = 15618,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 39,
                HP = 25,
                MP = 25,
                MND = 2,
                Accuracy = 3,
            }
        },
        VlrBreeches_1 = {
            Name = "Vlr. Breeches +1",
            Level = 75,
            Id = 15586,
            Jobs = {"PLD"},
            Type = "Legs",
            Stats = {
                DEF = 44,
                HP = 20,
                STR = 6,
                Enmity = 4,
            }
        },
        WarCuisses_1 = {
            Name = "War. Cuisses +1",
            Level = 75,
            Id = 15580,
            Jobs = {"WAR"},
            Type = "Legs",
            Stats = {
                DEF = 40,
                STR = 6,
                Enmity = 4,
                DoubleAttack = 1,
            }
        },
        WarlocksTights = {
            Name = "Warlocks Tights",
            Level = 56,
            Id = 14218,
            Jobs = {"RDM"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                MP = 13,
                MND = 3,
            }
        },
        WhiteSlacks = {
            Name = "White Slacks",
            Level = 50,
            Id = 12867,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 21,
            }
        },
        WhiteSlacks_1 = {
            Name = "White Slacks +1",
            Level = 50,
            Id = 12926,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 22,
                MND = 1,
            }
        },
        WiseBraconi = {
            Name = "Wise Braconi",
            Level = 72,
            Id = 15396,
            Jobs = {"RDM"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                MP = 17,
                Accuracy = 1,
                MagicAccuracy = 2,
                Enmity = -4,
            }
        },
        WiseBraconi_1 = {
            Name = "Wise Braconi +1",
            Level = 72,
            Id = 15397,
            Jobs = {"RDM"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                MP = 20,
                Accuracy = 2,
                MagicAccuracy = 3,
                Enmity = -5,
            }
        },
        WizardsTonban = {
            Name = "Wizards Tonban",
            Level = 56,
            Id = 14217,
            Jobs = {"BLM"},
            Type = "Legs",
            Stats = {
                DEF = 27,
                MP = 14,
                Evasion = 5,
                Enmity = -1,
            }
        },
        WlkTights_1 = {
            Name = "Wlk. Tights +1",
            Level = 74,
            Id = 15565,
            Jobs = {"RDM"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                MP = 18,
                MND = 5,
            }
        },
        WoolSlops = {
            Name = "Wool Slops",
            Level = 28,
            Id = 12858,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "THF", "DRK", "BRD", "RNG", "SMN", "BLU", "COR", "PUP", "DNC", "SCH", "GEO", "RUN"},
            Type = "Legs",
            Stats = {
                DEF = 13,
            }
        },
        WymBrais_1 = {
            Name = "Wym. Brais +1",
            Level = 75,
            Id = 15593,
            Jobs = {"DRG"},
            Type = "Legs",
            Stats = {
                DEF = 33,
                HP = 13,
                DEX = 6,
            }
        },
        WzdTonban_1 = {
            Name = "Wzd. Tonban +1",
            Level = 74,
            Id = 15564,
            Jobs = {"BLM"},
            Type = "Legs",
            Stats = {
                DEF = 27,
                MP = 19,
                Enmity = -2,
                HMP = 1,
            }
        },
        YashaHakama = {
            Name = "Yasha Hakama",
            Level = 71,
            Id = 12847,
            Jobs = {"NIN"},
            Type = "Legs",
            Stats = {
                DEF = 31,
                HP = 25,
                INT = 2,
                Enmity = 2,
            }
        },
        YashaHakama_1 = {
            Name = "Yasha Hakama +1",
            Level = 71,
            Id = 15398,
            Jobs = {"NIN"},
            Type = "Legs",
            Stats = {
                DEF = 32,
                HP = 30,
                INT = 3,
                Enmity = 3,
            }
        },
        ZenithSlacks = {
            Name = "Zenith Slacks",
            Level = 73,
            Id = 14247,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Legs",
            Stats = {
                DEF = 40,
                MND = 4,
                CHR = 4,
                Evasion = -3,
            }
        },
        ZenithSlacks_1 = {
            Name = "Zenith Slacks +1",
            Level = 73,
            Id = 14248,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Legs",
            Stats = {
                DEF = 41,
                MND = 5,
                CHR = 5,
                Evasion = -4,
            }
        },
    },
    Feet = {
        AbsSollerets_1 = {
            Name = "Abs. Sollerets +1",
            Level = 75,
            Id = 15672,
            Jobs = {"DRK"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                MP = 12,
                Accuracy = 2,
            }
        },
        AcroLeggings = {
            Name = "Acro Leggings",
            Level = 75,
            Id = 27403,
            Jobs = {"WAR", "PLD", "DRK", "SAM", "DRG", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 23,
                AGI = 5,
                MND = 5,
                CHR = 5,
                DoubleAttack = 2,
            }
        },
        AdamanSollerets = {
            Name = "Adaman Sollerets",
            Level = 73,
            Id = 12941,
            Jobs = {"WAR", "DRK", "BST"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                MND = -10,
                Accuracy = 3,
                Attack = 5,
                Evasion = -3,
            }
        },
        AdhemarGamashes = {
            Name = "Adhemar Gamashes",
            Level = 75,
            Id = 27473,
            Jobs = {"THF"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                HP = 20,
                STR = 5,
                VIT = 5,
                Enmity = 3,
                TripleAttack = 2,
                DualWield = 1,
            }
        },
        AgronasLeggings = {
            Name = "Agronas Leggings",
            Level = 75,
            Id = 14162,
            Jobs = {"MNK", "THF", "BST", "RNG", "NIN", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                STR = 4,
                Accuracy = 3,
                Haste = -4,
                DoubleAttack = 2,
            }
        },
        AgwusPigaches = {
            Name = "Agwus Pigaches",
            Level = 75,
            Id = 23787,
            Jobs = {"BLU"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                MP = 20,
                INT = 4,
                MND = 4,
                MagicAccuracy = 6,
                HMP = 3,
            }
        },
        AifesPumps = {
            Name = "Aifes Pumps",
            Level = 75,
            Id = 11461,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "PUP", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                MP = 20,
                MND = 7,
                MagicAccuracy = -4,
                Enmity = -5,
                ConserveMP = 4,
            }
        },
        AmalricNails = {
            Name = "Amalric Nails",
            Level = 75,
            Id = 27475,
            Jobs = {"GEO"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                HP = 25,
                CHR = 5,
                MagicDefenseBonus = 3,
            }
        },
        AnglersBoots = {
            Name = "Anglers Boots",
            Level = 15,
            Id = 14172,
            Jobs = {"All"},
            Type = "Feet",
            Stats = {
                DEF = 3,
            }
        },
        AreionBoots = {
            Name = "Areion Boots",
            Level = 20,
            Id = 10647,
            Jobs = {"THF", "RNG"},
            Type = "Feet",
            Stats = {
                DEF = 4,
                AGI = 3,
                Accuracy = 2,
                MovementSpeed = 19,
            }
        },
        AreionBoots_1 = {
            Name = "Areion Boots +1",
            Level = 20,
            Id = 10648,
            Jobs = {"THF", "RNG"},
            Type = "Feet",
            Stats = {
                DEF = 5,
                AGI = 4,
                Accuracy = 3,
                MovementSpeed = 20,
            }
        },
        AresSollerets = {
            Name = "Ares Sollerets",
            Level = 75,
            Id = 15711,
            Jobs = {"WAR", "PLD", "DRK", "DRG", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HPP = 2,
                MPP = 2,
                VIT = 3,
                AGI = 3,
                Accuracy = 7,
                Attack = 7,
                Evasion = -7,
            }
        },
        ArguteLoafers = {
            Name = "Argute Loafers",
            Level = 72,
            Id = 11398,
            Jobs = {"SCH"},
            Type = "Feet",
            Stats = {
                DEF = 13,
                MP = 20,
            }
        },
        ArguteLoafers_1 = {
            Name = "Argute Loafers +1",
            Level = 75,
            Id = 11399,
            Jobs = {"SCH"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                MP = 25,
            }
        },
        ArmadaSollerets = {
            Name = "Armada Sollerets",
            Level = 73,
            Id = 14175,
            Jobs = {"WAR", "DRK", "BST"},
            Type = "Feet",
            Stats = {
                DEF = 19,
                MND = -11,
                Accuracy = 4,
                Attack = 6,
                Evasion = -4,
            }
        },
        AsnPoulaines_1 = {
            Name = "Asn. Poulaines +1",
            Level = 75,
            Id = 15670,
            Jobs = {"THF"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                HP = 15,
                CHR = 6,
                Enmity = 3,
                TripleAttack = 1,
            }
        },
        AurumSabatons = {
            Name = "Aurum Sabatons",
            Level = 72,
            Id = 11376,
            Jobs = {"WAR", "PLD", "DRK", "BST", "DRG"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                DEX = 3,
                Accuracy = 5,
                Attack = 5,
                Evasion = -5,
                Haste = 2,
            }
        },
        AvocatPigaches = {
            Name = "Avocat Pigaches",
            Level = 72,
            Id = 11366,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                Enmity = -3,
                HMP = 3,
            }
        },
        BaguaSandals = {
            Name = "Bagua Sandals",
            Level = 75,
            Id = 27368,
            Jobs = {"GEO"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                MP = 18,
                MND = 3,
            }
        },
        BaguaSandals_1 = {
            Name = "Bagua Sandals +1",
            Level = 75,
            Id = 27369,
            Jobs = {"GEO"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                MP = 23,
                MND = 4,
            }
        },
        BattleBoots = {
            Name = "Battle Boots",
            Level = 59,
            Id = 12980,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 11,
                Evasion = 1,
            }
        },
        BattleBoots_1 = {
            Name = "Battle Boots +1",
            Level = 59,
            Id = 14104,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 12,
                Evasion = 3,
            }
        },
        BeastGaiters = {
            Name = "Beast Gaiters",
            Level = 52,
            Id = 14097,
            Jobs = {"BST"},
            Type = "Feet",
            Stats = {
                DEF = 10,
                HP = 11,
                AGI = 3,
            }
        },
        BeetleLeggings = {
            Name = "Beetle Leggings",
            Level = 21,
            Id = 12967,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 5,
            }
        },
        BlackSollerets = {
            Name = "Black Sollerets",
            Level = 71,
            Id = 15339,
            Jobs = {"DRK"},
            Type = "Feet",
            Stats = {
                DEF = 13,
                STR = 3,
                Attack = 8,
            }
        },
        BlessedPumps = {
            Name = "Blessed Pumps",
            Level = 70,
            Id = 15329,
            Jobs = {"WHM"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                MP = 17,
                MND = 3,
                Haste = 2,
                Enmity = -4,
            }
        },
        BlessedPumps_1 = {
            Name = "Blessed Pumps +1",
            Level = 70,
            Id = 15331,
            Jobs = {"WHM"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                MP = 20,
                MND = 4,
                Haste = 3,
                Enmity = -5,
            }
        },
        BloodGreaves = {
            Name = "Blood Greaves",
            Level = 73,
            Id = 14161,
            Jobs = {"RDM", "PLD", "DRK", "RNG", "DRG", "BLU", "COR", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 25,
                HP = 17,
                MP = 17,
                DEX = 4,
                AGI = 4,
            }
        },
        BrdSlippers_1 = {
            Name = "Brd. Slippers +1",
            Level = 75,
            Id = 15674,
            Jobs = {"BRD"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                HP = 12,
                Enmity = -3,
            }
        },
        BstGaiters_1 = {
            Name = "Bst. Gaiters +1",
            Level = 74,
            Id = 15360,
            Jobs = {"BST"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                HP = 11,
                AGI = 5,
                CHR = 5,
            }
        },
        BtlLeggings_1 = {
            Name = "Btl. Leggings +1",
            Level = 21,
            Id = 13043,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 6,
                Evasion = 1,
            }
        },
        BunzisSabots = {
            Name = "Bunzis Sabots",
            Level = 75,
            Id = 23788,
            Jobs = {"WHM"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                MP = 15,
                INT = 5,
                MND = 5,
                FastCast = 2,
                HHP = 3,
            }
        },
        ChironicSlippers = {
            Name = "Chironic Slippers",
            Level = 75,
            Id = 27498,
            Jobs = {"SMN"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                MP = 15,
                Enmity = -2,
            }
        },
        ChlSlippers_1 = {
            Name = "Chl. Slippers +1",
            Level = 74,
            Id = 15361,
            Jobs = {"BRD"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                HP = 10,
                DEX = 5,
                AGI = 5,
                Evasion = 5,
                HMP = 2,
                HHP = 2,
            }
        },
        ChoralSlippers = {
            Name = "Choral Slippers",
            Level = 52,
            Id = 14098,
            Jobs = {"BRD"},
            Type = "Feet",
            Stats = {
                DEF = 10,
                HP = 10,
                AGI = 3,
                Evasion = 5,
            }
        },
        ChsSollerets_1 = {
            Name = "Chs. Sollerets +1",
            Level = 74,
            Id = 15359,
            Jobs = {"DRK"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                HP = 15,
                MP = 15,
                STR = 5,
                MND = 5,
            }
        },
        ClrDuckbills_1 = {
            Name = "Clr. Duckbills +1",
            Level = 75,
            Id = 15667,
            Jobs = {"WHM"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                MP = 18,
                MND = 6,
                Enmity = -2,
            }
        },
        CommBottes_1 = {
            Name = "Comm. Bottes +1",
            Level = 75,
            Id = 11386,
            Jobs = {"COR"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                HP = 12,
                DEX = 3,
                INT = 3,
                Accuracy = 7,
                Enmity = -4,
            }
        },
        CorBottes_1 = {
            Name = "Cor. Bottes +1",
            Level = 74,
            Id = 11384,
            Jobs = {"COR"},
            Type = "Feet",
            Stats = {
                DEF = 12,
                HP = 15,
                STR = 5,
                AGI = 5,
                Accuracy = 4,
                RangedAccuracy = 4,
            }
        },
        CottonGaiters = {
            Name = "Cotton Gaiters",
            Level = 23,
            Id = 12977,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 5,
            }
        },
        CriersGaiters = {
            Name = "Criers Gaiters",
            Level = 70,
            Id = 27456,
            Jobs = {"MNK", "WHM", "BLM", "SMN", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                MP = 12,
                Evasion = 8,
                MovementSpeed = 18,
            }
        },
        CrimsonGreaves = {
            Name = "Crimson Greaves",
            Level = 73,
            Id = 14160,
            Jobs = {"RDM", "PLD", "DRK", "RNG", "DRG", "BLU", "COR", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 24,
                HP = 15,
                MP = 15,
                DEX = 3,
                AGI = 3,
            }
        },
        DancersShoes_1 = {
            Name = "Dancers Shoes +1",
            Level = 74,
            Id = 11393,
            Jobs = {"DNC"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                HP = 12,
                STR = 3,
                AGI = 3,
                Attack = 5,
                Evasion = 5,
            }
        },
        DinoLedelsens = {
            Name = "Dino Ledelsens",
            Level = 48,
            Id = 13049,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 11,
            }
        },
        DlsBoots_1 = {
            Name = "Dls. Boots +1",
            Level = 75,
            Id = 15669,
            Jobs = {"RDM"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                MP = 15,
                MND = 5,
                MagicAttackBonus = 5,
            }
        },
        DragonGreaves = {
            Name = "Dragon Greaves",
            Level = 68,
            Id = 12948,
            Jobs = {"DRG"},
            Type = "Feet",
            Stats = {
                DEF = 13,
                HP = 9,
            }
        },
        DragonLeggings = {
            Name = "Dragon Leggings",
            Level = 73,
            Id = 14186,
            Jobs = {"THF"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                DEX = 3,
                AGI = 3,
                Attack = 2,
                Enmity = 1,
            }
        },
        DrgGreaves_1 = {
            Name = "Drg. Greaves +1",
            Level = 68,
            Id = 14107,
            Jobs = {"DRG"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                HP = 11,
            }
        },
        DrnGreaves_1 = {
            Name = "Drn. Greaves +1",
            Level = 74,
            Id = 15365,
            Jobs = {"DRG"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                HP = 12,
                DEX = 5,
                AGI = 5,
            }
        },
        DrnLeggings_1 = {
            Name = "Drn. Leggings +1",
            Level = 73,
            Id = 14187,
            Jobs = {"THF"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                DEX = 4,
                AGI = 4,
                Attack = 3,
                Enmity = 2,
            }
        },
        DuelistsBoots = {
            Name = "Duelists Boots",
            Level = 71,
            Id = 15136,
            Jobs = {"RDM"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                MP = 15,
                MND = 4,
                MagicAttackBonus = 4,
            }
        },
        DuxGreaves = {
            Name = "Dux Greaves",
            Level = 70,
            Id = 10363,
            Jobs = {"RUN"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                VIT = 5,
                Accuracy = 9,
                Enmity = 4,
            }
        },
        DuxGreaves_1 = {
            Name = "Dux Greaves +1",
            Level = 70,
            Id = 10364,
            Jobs = {"RUN"},
            Type = "Feet",
            Stats = {
                DEF = 21,
                VIT = 6,
                Accuracy = 10,
                Enmity = 5,
            }
        },
        Eisenschuhs = {
            Name = "Eisenschuhs",
            Level = 29,
            Id = 15317,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Feet",
            Stats = {
                DEF = 8,
                VIT = 2,
            }
        },
        EnkidusLeggings = {
            Name = "Enkidus Leggings",
            Level = 72,
            Id = 11378,
            Jobs = {"MNK", "THF", "RNG", "SAM", "NIN", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 23,
                DEX = 3,
                AGI = 3,
                Attack = 4,
                RangedAttack = 4,
                Haste = 2,
                SubtleBlow = 2,
            }
        },
        EtoileShoes_1 = {
            Name = "Etoile Shoes +1",
            Level = 75,
            Id = 11397,
            Jobs = {"DNC"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                HP = 20,
                DEX = 4,
                Accuracy = 5,
            }
        },
        EvkPigaches_1 = {
            Name = "Evk. Pigaches +1",
            Level = 74,
            Id = 15366,
            Jobs = {"SMN"},
            Type = "Feet",
            Stats = {
                DEF = 10,
                MP = 25,
            }
        },
        EvokersBoots = {
            Name = "Evokers Boots",
            Level = 71,
            Id = 15325,
            Jobs = {"SMN"},
            Type = "Feet",
            Stats = {
                DEF = 11,
                MP = 20,
                MND = 2,
                Enmity = -2,
            }
        },
        FieldBoots = {
            Name = "Field Boots",
            Level = 1,
            Id = 14176,
            Jobs = {"All"},
            Type = "Feet",
            Stats = {
                DEF = 1,
            }
        },
        FoundersGreaves = {
            Name = "Founders Greaves",
            Level = 75,
            Id = 28330,
            Jobs = {"PLD"},
            Type = "Feet",
            Stats = {
                DEF = 22,
                HP = 15,
                MP = 10,
                Haste = 3,
                StoreTP = 3,
                CriticalHitRate = 3,
            }
        },
        FtrCalligae_1 = {
            Name = "Ftr. Calligae +1",
            Level = 74,
            Id = 15352,
            Jobs = {"WAR"},
            Type = "Feet",
            Stats = {
                DEF = 19,
                HP = 12,
                VIT = 3,
                AGI = 3,
                Enmity = 1,
                DoubleAttack = 1,
            }
        },
        FumaKyahan = {
            Name = "Fuma Kyahan",
            Level = 39,
            Id = 13054,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Feet",
            Stats = {
                DEF = 7,
                Haste = 3,
            }
        },
        FutharkBoots = {
            Name = "Futhark Boots",
            Level = 75,
            Id = 27370,
            Jobs = {"RUN"},
            Type = "Feet",
            Stats = {
                DEF = 19,
                MP = 21,
                STR = 5,
                DEX = 5,
                Haste = 4,
            }
        },
        FutharkBoots_1 = {
            Name = "Futhark Boots +1",
            Level = 75,
            Id = 27371,
            Jobs = {"RUN"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                MP = 28,
                STR = 6,
                DEX = 6,
                Haste = 4,
            }
        },
        GarishPumps = {
            Name = "Garish Pumps",
            Level = 30,
            Id = 15314,
            Jobs = {"MNK", "RDM", "PLD", "BRD", "RNG", "BLU", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 7,
            }
        },
        GarrisonBoots = {
            Name = "Garrison Boots",
            Level = 18,
            Id = 14206,
            Jobs = {"All"},
            Type = "Feet",
            Stats = {
                DEF = 4,
                INT = 1,
                MND = 1,
            }
        },
        GarrisonBoots_1 = {
            Name = "Garrison Boots +1",
            Level = 20,
            Id = 25974,
            Jobs = {"All"},
            Type = "Feet",
            Stats = {
                DEF = 6,
                HP = 5,
                INT = 2,
                MND = 2,
                HMP = 2,
            }
        },
        GenieHuaraches = {
            Name = "Genie Huaraches",
            Level = 73,
            Id = 15310,
            Jobs = {"BLM"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                Enmity = 3,
                ConserveMP = 5,
            }
        },
        GeomancySandals = {
            Name = "Geomancy Sandals",
            Level = 75,
            Id = 28346,
            Jobs = {"GEO"},
            Type = "Feet",
            Stats = {
                DEF = 12,
                MP = 15,
                AGI = 5,
                CHR = 5,
                MovementSpeed = 12,
            }
        },
        GletisBoots = {
            Name = "Gletis Boots",
            Level = 75,
            Id = 23784,
            Jobs = {"DRK"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HP = 5,
                MP = 5,
                STR = 3,
                INT = 3,
                Enmity = 300,
                DoubleAttack = 3,
                FastCast = 3,
            }
        },
        GltLeggings_1 = {
            Name = "Glt. Leggings +1",
            Level = 74,
            Id = 15358,
            Jobs = {"PLD"},
            Type = "Feet",
            Stats = {
                DEF = 19,
                HP = 20,
                CHR = 5,
            }
        },
        GreatGaiters = {
            Name = "Great Gaiters",
            Level = 23,
            Id = 13032,
            Jobs = {"MNK", "WHM", "RDM", "THF", "PLD", "BST", "BRD", "DRG", "SMN", "BLU", "COR", "PUP", "DNC", "GEO", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 6,
            }
        },
        Greaves = {
            Name = "Greaves",
            Level = 24,
            Id = 12936,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "NIN"},
            Type = "Feet",
            Stats = {
                DEF = 6,
            }
        },
        Greaves_1 = {
            Name = "Greaves +1",
            Level = 24,
            Id = 13025,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "NIN"},
            Type = "Feet",
            Stats = {
                DEF = 7,
            }
        },
        HctLeggings = {
            Name = "Hct. Leggings",
            Level = 73,
            Id = 14180,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 22,
                HP = 7,
                STR = 6,
                DEX = 3,
                Haste = -4,
            }
        },
        HctLeggings_1 = {
            Name = "Hct. Leggings +1",
            Level = 73,
            Id = 14181,
            Jobs = {"WAR", "THF", "PLD", "DRK", "BST", "BRD", "DRG", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 23,
                HP = 9,
                STR = 7,
                DEX = 4,
                Haste = -6,
            }
        },
        HeliosBoots = {
            Name = "Helios Boots",
            Level = 75,
            Id = 27406,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                AGI = 5,
                INT = 5,
                CHR = 5,
                ConserveMP = 3,
            }
        },
        HeraldsGaiters = {
            Name = "Heralds Gaiters",
            Level = 70,
            Id = 15322,
            Jobs = {"MNK", "WHM", "BLM", "SMN", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                MP = 12,
                Evasion = 8,
                MovementSpeed = 18,
            }
        },
        HerculeanBoots = {
            Name = "Herculean Boots",
            Level = 75,
            Id = 27496,
            Jobs = {"RNG"},
            Type = "Feet",
            Stats = {
                DEF = 19,
                HP = 15,
                DEX = 3,
                AGI = 3,
                Enmity = -3,
            }
        },
        HermesSandals = {
            Name = "Hermes Sandals",
            Level = 70,
            Id = 11379,
            Jobs = {"WAR", "MNK", "COR", "PUP", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                HP = 12,
                Evasion = 5,
                Enmity = 3,
                MovementSpeed = 18,
            }
        },
        HermesSandals_1 = {
            Name = "Hermes Sandals +1",
            Level = 70,
            Id = 11380,
            Jobs = {"WAR", "MNK", "COR", "PUP", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                HP = 14,
                Evasion = 6,
                Enmity = 4,
                MovementSpeed = 19,
            }
        },
        HlrDuckbills_1 = {
            Name = "Hlr. Duckbills +1",
            Level = 74,
            Id = 15354,
            Jobs = {"WHM"},
            Type = "Feet",
            Stats = {
                DEF = 12,
                MP = 15,
                AGI = 5,
                INT = 5,
                HMP = 1,
            }
        },
        HmnSuneAte = {
            Name = "Hmn. Sune-ate",
            Level = 70,
            Id = 15330,
            Jobs = {"SAM"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                STR = 2,
                StoreTP = 5,
            }
        },
        HmnSuneAte_1 = {
            Name = "Hmn. Sune-ate +1",
            Level = 70,
            Id = 15332,
            Jobs = {"SAM"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                STR = 3,
                StoreTP = 6,
            }
        },
        HomamGambieras = {
            Name = "Homam Gambieras",
            Level = 75,
            Id = 15661,
            Jobs = {"THF", "PLD", "DRK", "DRG", "BLU", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                HP = 31,
                MP = 31,
                Accuracy = 6,
                RangedAccuracy = 6,
                Haste = 3,
            }
        },
        HtrSocks_1 = {
            Name = "Htr. Socks +1",
            Level = 74,
            Id = 15362,
            Jobs = {"RNG"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                HP = 10,
                DEX = 6,
                AGI = 6,
                Evasion = 5,
            }
        },
        IgqiraHuaraches = {
            Name = "Igqira Huaraches",
            Level = 73,
            Id = 15309,
            Jobs = {"BLM"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                Enmity = 2,
                ConserveMP = 4,
            }
        },
        IkengasClogs = {
            Name = "Ikengas Clogs",
            Level = 75,
            Id = 23783,
            Jobs = {"COR"},
            Type = "Feet",
            Stats = {
                DEF = 19,
                HP = 20,
                STR = 3,
                INT = 3,
                MagicAttackBonus = 3,
                StoreTP = 3,
            }
        },
        IronRamGreaves = {
            Name = "Iron Ram Greaves",
            Level = 68,
            Id = 15755,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                HP = 19,
                MagicDefenseBonus = 3,
                Enmity = 3,
            }
        },
        KaiserSchuhs = {
            Name = "Kaiser Schuhs",
            Level = 73,
            Id = 14163,
            Jobs = {"WAR", "PLD"},
            Type = "Feet",
            Stats = {
                DEF = 26,
                HP = 22,
                STR = -6,
                DEX = -6,
                VIT = 11,
                CHR = 11,
            }
        },
        Kampfschuhs = {
            Name = "Kampfschuhs",
            Level = 29,
            Id = 15321,
            Jobs = {"WAR", "PLD", "DRK", "DRG"},
            Type = "Feet",
            Stats = {
                DEF = 9,
                VIT = 3,
            }
        },
        KhimairaGamash = {
            Name = "Khimaira Gamash.",
            Level = 71,
            Id = 15731,
            Jobs = {"BST"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                HP = 7,
                MP = 7,
                Accuracy = 5,
                Attack = 5,
                Enmity = -1,
            }
        },
        KingsSabatons = {
            Name = "Kings Sabatons",
            Level = 70,
            Id = 15337,
            Jobs = {"PLD"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                HP = 10,
                VIT = 2,
                CHR = 2,
                HMP = 4,
            }
        },
        KoenigSchuhs = {
            Name = "Koenig Schuhs",
            Level = 73,
            Id = 12933,
            Jobs = {"WAR", "PLD"},
            Type = "Feet",
            Stats = {
                DEF = 25,
                HP = 20,
                STR = -5,
                DEX = -5,
                VIT = 10,
                CHR = 10,
            }
        },
        KogKyahan_1 = {
            Name = "Kog. Kyahan +1",
            Level = 75,
            Id = 15677,
            Jobs = {"NIN"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                VIT = 8,
            }
        },
        LeapingBoots = {
            Name = "Leaping Boots",
            Level = 7,
            Id = 13014,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 3,
                DEX = 3,
                AGI = 3,
            }
        },
        LightSoleas = {
            Name = "Light Soleas",
            Level = 13,
            Id = 13052,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 4,
                Evasion = 3,
            }
        },
        LordsSabatons = {
            Name = "Lords Sabatons",
            Level = 70,
            Id = 15333,
            Jobs = {"PLD"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                VIT = 1,
                CHR = 1,
                HMP = 3,
            }
        },
        MagesSandals = {
            Name = "Mages Sandals",
            Level = 20,
            Id = 13048,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 5,
                MP = 3,
                AGI = 1,
            }
        },
        MagusCharuqs_1 = {
            Name = "Magus Charuqs +1",
            Level = 74,
            Id = 11381,
            Jobs = {"BLU"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                HP = 18,
                MP = 18,
                Accuracy = 3,
                Enmity = -5,
            }
        },
        MalignanceBoots = {
            Name = "Malignance Boots",
            Level = 75,
            Id = 23736,
            Jobs = {"RDM"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                MP = 15,
                Haste = 3,
                FastCast = 3,
            }
        },
        MarduksCrackows = {
            Name = "Marduks Crackows",
            Level = 75,
            Id = 15723,
            Jobs = {"WHM", "BRD", "SMN", "SCH"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                MPP = 3,
                MND = 10,
                Enmity = -4,
            }
        },
        MediumsSabots = {
            Name = "Mediums Sabots",
            Level = 75,
            Id = 27493,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                MP = 20,
                STR = 3,
                MND = 8,
                CurePotency = 4,
            }
        },
        MelGaiters_1 = {
            Name = "Mel. Gaiters +1",
            Level = 75,
            Id = 15666,
            Jobs = {"MNK"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                HPP = 4,
                DEX = 5,
            }
        },
        MerlinicCrackows = {
            Name = "Merlinic Crackows",
            Level = 75,
            Id = 27497,
            Jobs = {"SCH"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                HP = 25,
                MND = 3,
                Enmity = -3,
            }
        },
        MettleLeggings = {
            Name = "Mettle Leggings",
            Level = 17,
            Id = 11407,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 5,
                STR = 1,
            }
        },
        MirageCharuqs_1 = {
            Name = "Mirage Charuqs +1",
            Level = 75,
            Id = 11383,
            Jobs = {"BLU"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                MP = 15,
                AGI = 4,
                INT = 4,
                Attack = 5,
                Enmity = -2,
            }
        },
        Moccasins = {
            Name = "Moccasins",
            Level = 50,
            Id = 12995,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 8,
            }
        },
        Moccasins_1 = {
            Name = "Moccasins +1",
            Level = 50,
            Id = 13050,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 9,
            }
        },
        MorrigansPgch = {
            Name = "Morrigans Pgch.",
            Level = 75,
            Id = 15727,
            Jobs = {"BLM", "RDM", "BLU", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                MP = 20,
                STR = 3,
                INT = 3,
                MND = 10,
                Enmity = -2,
            }
        },
        MpacasBoots = {
            Name = "Mpacas Boots",
            Level = 75,
            Id = 23786,
            Jobs = {"NIN"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                HP = 20,
                STR = 6,
                VIT = 6,
                Accuracy = 6,
                Attack = 6,
                Haste = 3,
            }
        },
        MstGaiters_1 = {
            Name = "Mst. Gaiters +1",
            Level = 75,
            Id = 15673,
            Jobs = {"BST"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                HP = 13,
                VIT = 5,
            }
        },
        MtlLeggings_1 = {
            Name = "Mtl. Leggings +1",
            Level = 49,
            Id = 14086,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Feet",
            Stats = {
                DEF = 12,
                INT = 1,
            }
        },
        MttLeggings_1 = {
            Name = "Mtt. Leggings +1",
            Level = 17,
            Id = 11412,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 6,
                STR = 1,
                Attack = 2,
            }
        },
        MynSuneAte_1 = {
            Name = "Myn. Sune-ate +1",
            Level = 74,
            Id = 15363,
            Jobs = {"SAM"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                HP = 20,
                Attack = 8,
                Enmity = 5,
            }
        },
        MythrilLeggings = {
            Name = "Mythril Leggings",
            Level = 49,
            Id = 12929,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Feet",
            Stats = {
                DEF = 11,
            }
        },
        NagaKyahan = {
            Name = "Naga Kyahan",
            Level = 75,
            Id = 27459,
            Jobs = {"MNK"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                HPP = 3,
                Accuracy = 6,
                Attack = 6,
                Haste = 3,
                Enmity = 3,
            }
        },
        NashiraCrackows = {
            Name = "Nashira Crackows",
            Level = 75,
            Id = 15662,
            Jobs = {"WHM", "BLM", "RDM", "SMN", "BLU", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 13,
                MagicAccuracy = 2,
                Haste = 1,
            }
        },
        NinKyahan_1 = {
            Name = "Nin. Kyahan +1",
            Level = 74,
            Id = 15364,
            Jobs = {"NIN"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                HP = 12,
                AGI = 6,
                INT = 6,
            }
        },
        NoctGaiters = {
            Name = "Noct Gaiters",
            Level = 30,
            Id = 15311,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Feet",
            Stats = {
                DEF = 4,
                DEX = 1,
            }
        },
        NoctGaiters_1 = {
            Name = "Noct Gaiters +1",
            Level = 30,
            Id = 14207,
            Jobs = {"THF", "RNG", "COR"},
            Type = "Feet",
            Stats = {
                DEF = 5,
                DEX = 2,
            }
        },
        OdysseanGreaves = {
            Name = "Odyssean Greaves",
            Level = 75,
            Id = 27494,
            Jobs = {"DRG"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HP = 10,
                MP = 10,
                VIT = 3,
                MND = 3,
                MagicEvasion = 3,
                MagicDefenseBonus = 3,
                Haste = 3,
            }
        },
        OnyxSollerets = {
            Name = "Onyx Sollerets",
            Level = 71,
            Id = 15340,
            Jobs = {"DRK"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                STR = 4,
                Attack = 10,
            }
        },
        OraclesPigaches = {
            Name = "Oracles Pigaches",
            Level = 72,
            Id = 11377,
            Jobs = {"WHM", "BLM", "BRD", "SMN", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 13,
                HP = 15,
                MP = 25,
                HMP = 2,
            }
        },
        PlainBoots_1 = {
            Name = "Plain Boots +1",
            Level = 40,
            Id = 25965,
            Jobs = {"All"},
            Type = "Feet",
            Stats = {
                DEF = 8,
            }
        },
        PtnBabouches_1 = {
            Name = "Ptn. Babouches +1",
            Level = 75,
            Id = 11389,
            Jobs = {"PUP"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                HP = 22,
                INT = 3,
                MND = 3,
                Attack = 5,
            }
        },
        PupBabouches = {
            Name = "Pup. Babouches",
            Level = 54,
            Id = 15686,
            Jobs = {"PUP"},
            Type = "Feet",
            Stats = {
                DEF = 11,
                HP = 9,
                STR = 3,
            }
        },
        PupBabouches_1 = {
            Name = "Pup. Babouches +1",
            Level = 74,
            Id = 11387,
            Jobs = {"PUP"},
            Type = "Feet",
            Stats = {
                DEF = 12,
                HP = 19,
                STR = 5,
                Accuracy = 5,
                Evasion = 5,
            }
        },
        PursuersGaiters = {
            Name = "Pursuers Gaiters",
            Level = 75,
            Id = 27461,
            Jobs = {"BRD"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                HP = 10,
                MP = 10,
                MND = 3,
                CHR = 3,
                Haste = 3,
            }
        },
        RaptorLedelsens = {
            Name = "Raptor Ledelsens",
            Level = 48,
            Id = 12956,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 10,
            }
        },
        RawhideBoots = {
            Name = "Rawhide Boots",
            Level = 75,
            Id = 27460,
            Jobs = {"DNC"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HP = 25,
                STR = 5,
                VIT = 5,
                DualWield = 1,
            }
        },
        RogPoulaines_1 = {
            Name = "Rog. Poulaines +1",
            Level = 74,
            Id = 15357,
            Jobs = {"THF"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                DEX = 3,
                RangedAccuracy = 5,
            }
        },
        RoguesPoulaines = {
            Name = "Rogues Poulaines",
            Level = 60,
            Id = 14094,
            Jobs = {"THF"},
            Type = "Feet",
            Stats = {
                DEF = 13,
                HP = 12,
                DEX = 3,
            }
        },
        RostrumPumps = {
            Name = "Rostrum Pumps",
            Level = 75,
            Id = 15350,
            Jobs = {"WHM", "BLM", "BRD", "SMN", "PUP", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HP = -30,
                MP = 30,
                INT = 3,
                MND = 3,
                FastCast = 3,
            }
        },
        RubiousPumps = {
            Name = "Rubious Pumps",
            Level = 30,
            Id = 15318,
            Jobs = {"MNK", "RDM", "PLD", "BRD", "RNG", "BLU", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 8,
            }
        },
        RuneistBottes = {
            Name = "Runeist Bottes",
            Level = 75,
            Id = 28347,
            Jobs = {"RUN"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                HP = 18,
                VIT = 6,
                MagicDefenseBonus = 2,
            }
        },
        RuthlessGreaves = {
            Name = "Ruthless Greaves",
            Level = 75,
            Id = 28305,
            Jobs = {"WAR", "PLD", "DRK", "BST", "SAM", "DRG"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HP = 35,
                STR = 5,
                Haste = 4,
                TripleAttack = 1,
            }
        },
        RyugaSuneAte = {
            Name = "Ryuga Sune-ate",
            Level = 75,
            Id = 11456,
            Jobs = {"MNK", "THF", "DRK", "BST", "SAM", "NIN", "DRG", "PUP", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HP = 30,
                VIT = 7,
                Accuracy = 4,
                Evasion = 4,
                Haste = 3,
            }
        },
        RyuoSuneAte = {
            Name = "Ryuo Sune-ate",
            Level = 75,
            Id = 27471,
            Jobs = {"SAM"},
            Type = "Feet",
            Stats = {
                DEF = 21,
                HP = 15,
                DEX = 3,
                AGI = 3,
                Haste = 3,
            }
        },
        SakpatasLeggings = {
            Name = "Sakpatas Leggings",
            Level = 75,
            Id = 23785,
            Jobs = {"WAR"},
            Type = "Feet",
            Stats = {
                DEF = 22,
                HP = 25,
                STR = 3,
                Haste = 3,
                Enmity = 5,
                TripleAttack = 1,
            }
        },
        Sandals = {
            Name = "Sandals",
            Level = 20,
            Id = 12993,
            Jobs = {"MNK", "WHM", "BLM", "RDM", "PLD", "BRD", "RNG", "SMN", "BLU", "PUP", "SCH", "GEO", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 4,
            }
        },
        SaoSuneAte_1 = {
            Name = "Sao. Sune-ate +1",
            Level = 75,
            Id = 15676,
            Jobs = {"SAM"},
            Type = "Feet",
            Stats = {
                DEF = 19,
                HP = 23,
                DEX = 6,
                Attack = 10,
                Enmity = 1,
            }
        },
        SchLoafers_1 = {
            Name = "Sch. Loafers +1",
            Level = 74,
            Id = 11395,
            Jobs = {"SCH"},
            Type = "Feet",
            Stats = {
                DEF = 11,
                MP = 20,
                AGI = 3,
                INT = 3,
                Enmity = -2,
            }
        },
        ScholarsLoafers = {
            Name = "Scholars Loafers",
            Level = 54,
            Id = 15748,
            Jobs = {"SCH"},
            Type = "Feet",
            Stats = {
                DEF = 10,
                MP = 15,
                Enmity = -2,
            }
        },
        SctSocks_1 = {
            Name = "Sct. Socks +1",
            Level = 75,
            Id = 15675,
            Jobs = {"RNG"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                HP = 12,
                VIT = 5,
                RangedAttack = 12,
                Enmity = -4,
            }
        },
        SeersPumps = {
            Name = "Seers Pumps",
            Level = 29,
            Id = 15313,
            Jobs = {"WHM", "BLM", "SMN", "PUP", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 6,
                MP = 4,
                MND = 1,
            }
        },
        SeersPumps_1 = {
            Name = "Seers Pumps +1",
            Level = 29,
            Id = 15316,
            Jobs = {"WHM", "BLM", "SMN", "PUP", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 7,
                MP = 5,
                MND = 2,
            }
        },
        SetantasLed = {
            Name = "Setantas Led.",
            Level = 74,
            Id = 11410,
            Jobs = {"MNK", "THF", "RNG", "BLU", "COR", "PUP", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 19,
                STR = 3,
                DEX = 4,
                Accuracy = 3,
                Evasion = 3,
                Haste = 2,
            }
        },
        ShadeLeggings = {
            Name = "Shade Leggings",
            Level = 25,
            Id = 15315,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 6,
            }
        },
        ShadeLeggings_1 = {
            Name = "Shade Leggings +1",
            Level = 25,
            Id = 15319,
            Jobs = {"WAR", "MNK", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 7,
                Evasion = 1,
            }
        },
        ShadowClogs = {
            Name = "Shadow Clogs",
            Level = 75,
            Id = 15742,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 11,
                MND = 5,
                CHR = 5,
                MagicAccuracy = 2,
                Enmity = -2,
            }
        },
        ShadowSabatons = {
            Name = "Shadow Sabatons",
            Level = 75,
            Id = 15740,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HP = 15,
                MP = 15,
                AGI = 4,
                Accuracy = 1,
                Attack = 8,
            }
        },
        ShairCrackows = {
            Name = "Shair Crackows",
            Level = 72,
            Id = 15303,
            Jobs = {"BRD"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                MP = 11,
                CHR = 4,
                Haste = 1,
            }
        },
        SheikhCrackows = {
            Name = "Sheikh Crackows",
            Level = 72,
            Id = 15304,
            Jobs = {"BRD"},
            Type = "Feet",
            Stats = {
                DEF = 19,
                MP = 12,
                CHR = 5,
                Haste = 2,
            }
        },
        ShinobiKyahan = {
            Name = "Shinobi Kyahan",
            Level = 49,
            Id = 12972,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Feet",
            Stats = {
                DEF = 9,
            }
        },
        ShnKyahan_1 = {
            Name = "Shn. Kyahan +1",
            Level = 49,
            Id = 14082,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Feet",
            Stats = {
                DEF = 10,
                AGI = 1,
            }
        },
        ShrSuneAte_1 = {
            Name = "Shr. Sune-ate +1",
            Level = 73,
            Id = 14185,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                HP = -25,
                Accuracy = 5,
            }
        },
        ShrewdPumps = {
            Name = "Shrewd Pumps",
            Level = 74,
            Id = 11411,
            Jobs = {"WHM", "BLM", "RDM", "PLD", "DRK", "SMN", "BLU", "SCH", "GEO", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                MagicAttackBonus = 3,
                ConserveMP = 2,
            }
        },
        ShukuyuSuneAte = {
            Name = "Shukuyu Sune-ate",
            Level = 75,
            Id = 27489,
            Jobs = {"WAR", "MNK", "BST", "BRD", "RNG", "SAM", "NIN"},
            Type = "Feet",
            Stats = {
                DEF = 32,
                MND = 18,
                MagicDefenseBonus = 5,
                Haste = 3,
                FastCast = 5,
            }
        },
        ShuraSuneAte = {
            Name = "Shura Sune-ate",
            Level = 73,
            Id = 14184,
            Jobs = {"MNK", "SAM", "NIN"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                HP = -20,
                Accuracy = 4,
            }
        },
        SkadisJambeaux = {
            Name = "Skadis Jambeaux",
            Level = 75,
            Id = 15715,
            Jobs = {"THF", "BST", "RNG", "COR", "DNC"},
            Type = "Feet",
            Stats = {
                DEF = 16,
                STR = 3,
                VIT = 3,
                Accuracy = 5,
                RangedAccuracy = 5,
                Evasion = -5,
                MovementSpeed = 19,
            }
        },
        SmnPigaches_1 = {
            Name = "Smn. Pigaches +1",
            Level = 75,
            Id = 15679,
            Jobs = {"SMN"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                MP = 25,
            }
        },
        SoilKyahan = {
            Name = "Soil Kyahan",
            Level = 29,
            Id = 12970,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Feet",
            Stats = {
                DEF = 6,
            }
        },
        SoilKyahan_1 = {
            Name = "Soil Kyahan +1",
            Level = 29,
            Id = 13035,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Feet",
            Stats = {
                DEF = 7,
            }
        },
        SrcSabots_1 = {
            Name = "Src. Sabots +1",
            Level = 75,
            Id = 15668,
            Jobs = {"BLM"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                MP = 18,
                INT = 3,
                Enmity = -2,
                ConserveMP = 5,
            }
        },
        StoutGamashes = {
            Name = "Stout Gamashes",
            Level = 71,
            Id = 15732,
            Jobs = {"BST"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                HP = 8,
                MP = 8,
                Accuracy = 6,
                Attack = 6,
                Enmity = -2,
            }
        },
        StriderBoots = {
            Name = "Strider Boots",
            Level = 20,
            Id = 14080,
            Jobs = {"THF", "RNG"},
            Type = "Feet",
            Stats = {
                DEF = 4,
                AGI = 2,
                MovementSpeed = 18,
            }
        },
        SuzakusSuneAte = {
            Name = "Suzakus Sune-ate",
            Level = 75,
            Id = 12946,
            Jobs = {"WAR", "MNK", "BST", "BRD", "RNG", "SAM", "NIN"},
            Type = "Feet",
            Stats = {
                DEF = 30,
                MND = 15,
            }
        },
        TaeonBoots = {
            Name = "Taeon Boots",
            Level = 75,
            Id = 27404,
            Jobs = {"MNK", "THF", "BST", "RNG", "NIN", "COR", "PUP", "DNC"},
            Type = "Feet",
            Stats = {
                DEF = 22,
                DEX = 5,
                AGI = 5,
                CHR = 5,
                Evasion = 5,
                DualWield = 2,
            }
        },
        ThurandautBoots = {
            Name = "Thurandaut Boots",
            Level = 75,
            Id = 28344,
            Jobs = {"PUP"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HP = 15,
                STR = 3,
                Regen = 1,
            }
        },
        TplGaiters_1 = {
            Name = "Tpl. Gaiters +1",
            Level = 74,
            Id = 15353,
            Jobs = {"MNK"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                HP = 12,
                DEX = 5,
                MND = 5,
                Evasion = 10,
            }
        },
        TrotterBoots = {
            Name = "Trotter Boots",
            Level = 20,
            Id = 15736,
            Jobs = {"THF", "RNG"},
            Type = "Feet",
            Stats = {
                DEF = 4,
                AGI = 2,
                MovementSpeed = 18,
            }
        },
        UcnLeggings_1 = {
            Name = "Ucn. Leggings +1",
            Level = 74,
            Id = 15346,
            Jobs = {"WAR"},
            Type = "Feet",
            Stats = {
                DEF = 26,
                HP = 34,
                STR = 4,
            }
        },
        UkuxkajBoots = {
            Name = "Ukuxkaj Boots",
            Level = 75,
            Id = 28331,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 18,
                HP = 10,
                MP = 13,
                INT = 5,
                MagicAttackBonus = 4,
            }
        },
        UnicornLeggings = {
            Name = "Unicorn Leggings",
            Level = 74,
            Id = 15345,
            Jobs = {"WAR"},
            Type = "Feet",
            Stats = {
                DEF = 24,
                HP = 30,
                STR = 3,
            }
        },
        UsukaneSuneAte = {
            Name = "Usukane Sune-ate",
            Level = 75,
            Id = 15719,
            Jobs = {"MNK", "SAM", "NIN", "PUP"},
            Type = "Feet",
            Stats = {
                DEF = 22,
                Accuracy = 7,
                Attack = 7,
                Haste = 2,
                StoreTP = 7,
                Enmity = 5,
            }
        },
        ValkSabatons = {
            Name = "Valk. Sabatons",
            Level = 75,
            Id = 15741,
            Jobs = {"WAR", "PLD", "DRK"},
            Type = "Feet",
            Stats = {
                DEF = 21,
                HP = 17,
                MP = 17,
                AGI = 5,
                Accuracy = 2,
                Attack = 9,
            }
        },
        ValkyriesClogs = {
            Name = "Valkyries Clogs",
            Level = 75,
            Id = 15743,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 12,
                MND = 6,
                CHR = 6,
                MagicAccuracy = 3,
                Enmity = -3,
            }
        },
        ValorousGreaves = {
            Name = "Valorous Greaves",
            Level = 75,
            Id = 27495,
            Jobs = {"BST"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                HP = 20,
                DEX = 3,
                AGI = 3,
                Haste = 3,
                StoreTP = 3,
            }
        },
        VanyaClogs = {
            Name = "Vanya Clogs",
            Level = 75,
            Id = 27463,
            Jobs = {"BLM"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                MP = 15,
                VIT = 3,
                MND = 3,
                MagicEvasion = 3,
                MagicDefenseBonus = 3,
            }
        },
        VlrLeggings_1 = {
            Name = "Vlr. Leggings +1",
            Level = 75,
            Id = 15671,
            Jobs = {"PLD"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HP = 18,
                MND = 4,
                Enmity = 2,
            }
        },
        WarCalligae_1 = {
            Name = "War. Calligae +1",
            Level = 75,
            Id = 15665,
            Jobs = {"WAR"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                HP = 15,
                AGI = 6,
                Enmity = 1,
            }
        },
        WingedBoots = {
            Name = "Winged Boots",
            Level = 24,
            Id = 14132,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 5,
                DEX = 3,
                AGI = 3,
            }
        },
        WingedBoots_1 = {
            Name = "Winged Boots +1",
            Level = 24,
            Id = 14133,
            Jobs = {"WAR", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG", "SAM", "NIN", "DRG", "BLU", "COR", "DNC", "RUN"},
            Type = "Feet",
            Stats = {
                DEF = 6,
                DEX = 3,
                AGI = 3,
            }
        },
        WisePigaches = {
            Name = "Wise Pigaches",
            Level = 72,
            Id = 15334,
            Jobs = {"RDM"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                INT = 4,
                Accuracy = 2,
                RangedAccuracy = 3,
                Enmity = -1,
            }
        },
        WisePigaches_1 = {
            Name = "Wise Pigaches +1",
            Level = 72,
            Id = 15335,
            Jobs = {"RDM"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                INT = 5,
                Accuracy = 3,
                RangedAccuracy = 4,
                Enmity = -2,
            }
        },
        WlkBoots_1 = {
            Name = "Wlk. Boots +1",
            Level = 74,
            Id = 15356,
            Jobs = {"RDM"},
            Type = "Feet",
            Stats = {
                DEF = 15,
                MP = 16,
                AGI = 3,
                INT = 3,
                MND = 3,
            }
        },
        WymGreaves_1 = {
            Name = "Wym. Greaves +1",
            Level = 75,
            Id = 15678,
            Jobs = {"DRG"},
            Type = "Feet",
            Stats = {
                DEF = 17,
                HP = 10,
                VIT = 5,
            }
        },
        WzdSabots_1 = {
            Name = "Wzd. Sabots +1",
            Level = 74,
            Id = 15355,
            Jobs = {"BLM"},
            Type = "Feet",
            Stats = {
                DEF = 11,
                MP = 15,
                AGI = 5,
                MND = 5,
                HMP = 1,
            }
        },
        YashaSuneAte = {
            Name = "Yasha Sune-ate",
            Level = 71,
            Id = 13002,
            Jobs = {"NIN"},
            Type = "Feet",
            Stats = {
                DEF = 13,
                HP = 10,
                INT = 3,
                Enmity = 2,
            }
        },
        YigitCrackows = {
            Name = "Yigit Crackows",
            Level = 72,
            Id = 15690,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "BLU", "SCH", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 11,
                INT = 3,
                MND = 3,
                MagicAttackBonus = 2,
                Evasion = 5,
            }
        },
        YshSuneAte_1 = {
            Name = "Ysh. Sune-ate +1",
            Level = 71,
            Id = 15336,
            Jobs = {"NIN"},
            Type = "Feet",
            Stats = {
                DEF = 14,
                HP = 12,
                INT = 4,
                Enmity = 3,
            }
        },
        ZenithPumps = {
            Name = "Zenith Pumps",
            Level = 73,
            Id = 14123,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 20,
                INT = 2,
                CHR = 2,
            }
        },
        ZenithPumps_1 = {
            Name = "Zenith Pumps +1",
            Level = 73,
            Id = 14124,
            Jobs = {"WHM", "BLM", "RDM", "BRD", "SMN", "GEO"},
            Type = "Feet",
            Stats = {
                DEF = 21,
                INT = 3,
                CHR = 3,
            }
        },
    },
}
