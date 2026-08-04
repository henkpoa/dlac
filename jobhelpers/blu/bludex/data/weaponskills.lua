-- weaponskills.lua -- weaponskill skillchain properties (GENERATED 2026-08-04
-- by tools/generate_weaponskills.py -- DO NOT EDIT). Source: the public
-- CatsEyeXI clone's sql/weapon_skills.sql (= base-LSB). tag= quest (the
-- WSNM quest skills) | relic | mythic | empyrean | merit (the skills the
-- AEONIC weapons empower); no tag = a plain skill-up weaponskill.

local M = { ws = {} }

-- weapon display order for the chooser (Sword first -- BLU's weapon)
M.weapons = { 'Sword', 'Dagger', 'Club', 'Hand-to-Hand', 'Great Sword', 'Axe', 'Great Axe', 'Scythe', 'Polearm', 'Katana', 'Great Katana', 'Staff', 'Archery', 'Marksmanship' }

M.ws[#M.ws + 1] = { name = 'Fast Blade', weapon = 'Sword', lvl = 5, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Burning Blade', weapon = 'Sword', lvl = 30, sc = { 'Liquefaction' } }
M.ws[#M.ws + 1] = { name = 'Red Lotus Blade', weapon = 'Sword', lvl = 50, sc = { 'Liquefaction', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Flat Blade', weapon = 'Sword', lvl = 75, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Shining Blade', weapon = 'Sword', lvl = 100, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Seraph Blade', weapon = 'Sword', lvl = 125, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Circle Blade', weapon = 'Sword', lvl = 150, sc = { 'Reverberation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Vorpal Blade', weapon = 'Sword', lvl = 200, sc = { 'Scission', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Swift Blade', weapon = 'Sword', lvl = 225, sc = { 'Gravitation' } }
M.ws[#M.ws + 1] = { name = 'Savage Blade', weapon = 'Sword', lvl = 240, sc = { 'Fragmentation', 'Scission' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Requiescat', weapon = 'Sword', lvl = 357, sc = { 'Gravitation', 'Scission' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Death Blossom', weapon = 'Sword', lvl = 0, sc = { 'Fragmentation', 'Distortion' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Atonement', weapon = 'Sword', lvl = 0, sc = { 'Fusion', 'Reverberation' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Expiacion', weapon = 'Sword', lvl = 0, sc = { 'Distortion', 'Scission' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Chant du Cygne', weapon = 'Sword', lvl = 0, sc = { 'Light', 'Distortion' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Knights of Round', weapon = 'Sword', lvl = 0, sc = { 'Light', 'Fusion' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Wasp Sting', weapon = 'Dagger', lvl = 5, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Gust Slash', weapon = 'Dagger', lvl = 40, sc = { 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Shadowstitch', weapon = 'Dagger', lvl = 70, sc = { 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Viper Bite', weapon = 'Dagger', lvl = 100, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Cyclone', weapon = 'Dagger', lvl = 125, sc = { 'Detonation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Dancing Edge', weapon = 'Dagger', lvl = 200, sc = { 'Scission', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Shark Bite', weapon = 'Dagger', lvl = 225, sc = { 'Fragmentation' } }
M.ws[#M.ws + 1] = { name = 'Evisceration', weapon = 'Dagger', lvl = 230, sc = { 'Gravitation', 'Transfixion' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Aeolian Edge', weapon = 'Dagger', lvl = 290, sc = { 'Scission', 'Detonation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Exenterator', weapon = 'Dagger', lvl = 357, sc = { 'Fragmentation', 'Scission' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Mandalic Stab', weapon = 'Dagger', lvl = 0, sc = { 'Fusion', 'Compression' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Mordant Rime', weapon = 'Dagger', lvl = 0, sc = { 'Fragmentation', 'Distortion' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Pyrrhic Kleos', weapon = 'Dagger', lvl = 0, sc = { 'Distortion', 'Scission' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Rudra\'s Storm', weapon = 'Dagger', lvl = 0, sc = { 'Darkness', 'Distortion' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Mercy Stroke', weapon = 'Dagger', lvl = 0, sc = { 'Darkness', 'Gravitation' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Shining Strike', weapon = 'Club', lvl = 5, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Seraph Strike', weapon = 'Club', lvl = 40, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Brainshaker', weapon = 'Club', lvl = 70, sc = { 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Skullbreaker', weapon = 'Club', lvl = 150, sc = { 'Induration', 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'True Strike', weapon = 'Club', lvl = 175, sc = { 'Detonation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Judgment', weapon = 'Club', lvl = 200, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Hexa Strike', weapon = 'Club', lvl = 220, sc = { 'Fusion' } }
M.ws[#M.ws + 1] = { name = 'Black Halo', weapon = 'Club', lvl = 230, sc = { 'Fragmentation', 'Compression' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Flash Nova', weapon = 'Club', lvl = 290, sc = { 'Induration', 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Realmrazer', weapon = 'Club', lvl = 357, sc = { 'Fusion', 'Impaction' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Randgrith', weapon = 'Club', lvl = 0, sc = { 'Light', 'Fragmentation' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Combo', weapon = 'Hand-to-Hand', lvl = 5, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Shoulder Tackle', weapon = 'Hand-to-Hand', lvl = 40, sc = { 'Reverberation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'One Inch Punch', weapon = 'Hand-to-Hand', lvl = 75, sc = { 'Compression' } }
M.ws[#M.ws + 1] = { name = 'Backhand Blow', weapon = 'Hand-to-Hand', lvl = 100, sc = { 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Raging Fists', weapon = 'Hand-to-Hand', lvl = 125, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Spinning Attack', weapon = 'Hand-to-Hand', lvl = 150, sc = { 'Liquefaction', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Howling Fist', weapon = 'Hand-to-Hand', lvl = 200, sc = { 'Transfixion', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Dragon Kick', weapon = 'Hand-to-Hand', lvl = 225, sc = { 'Fragmentation' } }
M.ws[#M.ws + 1] = { name = 'Asuran Fists', weapon = 'Hand-to-Hand', lvl = 250, sc = { 'Gravitation', 'Liquefaction' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Tornado Kick', weapon = 'Hand-to-Hand', lvl = 300, sc = { 'Induration', 'Impaction', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Shijin Spiral', weapon = 'Hand-to-Hand', lvl = 357, sc = { 'Fusion', 'Reverberation' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Ascetic\'s Fury', weapon = 'Hand-to-Hand', lvl = 0, sc = { 'Fusion', 'Transfixion' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Stringing Pummel', weapon = 'Hand-to-Hand', lvl = 0, sc = { 'Gravitation', 'Liquefaction' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Victory Smite', weapon = 'Hand-to-Hand', lvl = 0, sc = { 'Light', 'Fragmentation' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Final Heaven', weapon = 'Hand-to-Hand', lvl = 0, sc = { 'Light', 'Fusion' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Hard Slash', weapon = 'Great Sword', lvl = 5, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Power Slash', weapon = 'Great Sword', lvl = 30, sc = { 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Frostbite', weapon = 'Great Sword', lvl = 70, sc = { 'Induration' } }
M.ws[#M.ws + 1] = { name = 'Freezebite', weapon = 'Great Sword', lvl = 100, sc = { 'Induration', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Shockwave', weapon = 'Great Sword', lvl = 150, sc = { 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Crescent Moon', weapon = 'Great Sword', lvl = 175, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Sickle Moon', weapon = 'Great Sword', lvl = 200, sc = { 'Scission', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Spinning Slash', weapon = 'Great Sword', lvl = 225, sc = { 'Fragmentation' } }
M.ws[#M.ws + 1] = { name = 'Ground Strike', weapon = 'Great Sword', lvl = 250, sc = { 'Fragmentation', 'Distortion' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Herculean Slash', weapon = 'Great Sword', lvl = 290, sc = { 'Induration', 'Impaction', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Resolution', weapon = 'Great Sword', lvl = 357, sc = { 'Fragmentation', 'Scission' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Torcleaver', weapon = 'Great Sword', lvl = 0, sc = { 'Light', 'Distortion' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Dimidiation', weapon = 'Great Sword', lvl = 0, sc = { 'Light', 'Fragmentation' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Scourge', weapon = 'Great Sword', lvl = 0, sc = { 'Light', 'Fusion' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Raging Axe', weapon = 'Axe', lvl = 5, sc = { 'Detonation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Smash Axe', weapon = 'Axe', lvl = 40, sc = { 'Induration', 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Gale Axe', weapon = 'Axe', lvl = 70, sc = { 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Avalanche Axe', weapon = 'Axe', lvl = 100, sc = { 'Scission', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Spinning Axe', weapon = 'Axe', lvl = 150, sc = { 'Liquefaction', 'Scission', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Rampage', weapon = 'Axe', lvl = 175, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Calamity', weapon = 'Axe', lvl = 200, sc = { 'Scission', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Mistral Axe', weapon = 'Axe', lvl = 225, sc = { 'Fusion' } }
M.ws[#M.ws + 1] = { name = 'Decimation', weapon = 'Axe', lvl = 240, sc = { 'Fusion', 'Reverberation' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Bora Axe', weapon = 'Axe', lvl = 290, sc = { 'Scission', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Ruinator', weapon = 'Axe', lvl = 357, sc = { 'Distortion', 'Detonation' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Primal Rend', weapon = 'Axe', lvl = 0, sc = { 'Gravitation', 'Reverberation' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Cloudsplitter', weapon = 'Axe', lvl = 0, sc = { 'Darkness', 'Fragmentation' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Onslaught', weapon = 'Axe', lvl = 0, sc = { 'Darkness', 'Gravitation' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Shield Break', weapon = 'Great Axe', lvl = 5, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Iron Tempest', weapon = 'Great Axe', lvl = 40, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Sturmwind', weapon = 'Great Axe', lvl = 70, sc = { 'Reverberation', 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Armor Break', weapon = 'Great Axe', lvl = 100, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Keen Edge', weapon = 'Great Axe', lvl = 150, sc = { 'Compression' } }
M.ws[#M.ws + 1] = { name = 'Weapon Break', weapon = 'Great Axe', lvl = 175, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Raging Rush', weapon = 'Great Axe', lvl = 200, sc = { 'Induration', 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Full Break', weapon = 'Great Axe', lvl = 225, sc = { 'Distortion' } }
M.ws[#M.ws + 1] = { name = 'Steel Cyclone', weapon = 'Great Axe', lvl = 240, sc = { 'Distortion', 'Detonation' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Fell Cleave', weapon = 'Great Axe', lvl = 300, sc = { 'Scission', 'Detonation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Upheaval', weapon = 'Great Axe', lvl = 357, sc = { 'Fusion', 'Compression' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'King\'s Justice', weapon = 'Great Axe', lvl = 0, sc = { 'Fragmentation', 'Scission' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Ukko\'s Fury', weapon = 'Great Axe', lvl = 0, sc = { 'Light', 'Fragmentation' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Metatron Torment', weapon = 'Great Axe', lvl = 0, sc = { 'Light', 'Fusion' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Slice', weapon = 'Scythe', lvl = 5, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Dark Harvest', weapon = 'Scythe', lvl = 30, sc = { 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Shadow of Death', weapon = 'Scythe', lvl = 70, sc = { 'Induration', 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Nightmare Scythe', weapon = 'Scythe', lvl = 100, sc = { 'Compression', 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Spinning Scythe', weapon = 'Scythe', lvl = 125, sc = { 'Reverberation', 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Vorpal Scythe', weapon = 'Scythe', lvl = 150, sc = { 'Transfixion', 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Guillotine', weapon = 'Scythe', lvl = 200, sc = { 'Induration' } }
M.ws[#M.ws + 1] = { name = 'Cross Reaper', weapon = 'Scythe', lvl = 225, sc = { 'Distortion' } }
M.ws[#M.ws + 1] = { name = 'Spiral Hell', weapon = 'Scythe', lvl = 240, sc = { 'Distortion', 'Scission' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Infernal Scythe', weapon = 'Scythe', lvl = 300, sc = { 'Compression', 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Entropy', weapon = 'Scythe', lvl = 357, sc = { 'Gravitation', 'Reverberation' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Insurgency', weapon = 'Scythe', lvl = 0, sc = { 'Fusion', 'Compression' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Quietus', weapon = 'Scythe', lvl = 0, sc = { 'Darkness', 'Distortion' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Catastrophe', weapon = 'Scythe', lvl = 0, sc = { 'Darkness', 'Gravitation' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Double Thrust', weapon = 'Polearm', lvl = 5, sc = { 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Thunder Thrust', weapon = 'Polearm', lvl = 30, sc = { 'Transfixion', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Raiden Thrust', weapon = 'Polearm', lvl = 70, sc = { 'Transfixion', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Leg Sweep', weapon = 'Polearm', lvl = 100, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Penta Thrust', weapon = 'Polearm', lvl = 150, sc = { 'Compression' } }
M.ws[#M.ws + 1] = { name = 'Vorpal Thrust', weapon = 'Polearm', lvl = 175, sc = { 'Reverberation', 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Skewer', weapon = 'Polearm', lvl = 200, sc = { 'Transfixion', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Wheeling Thrust', weapon = 'Polearm', lvl = 225, sc = { 'Fusion' } }
M.ws[#M.ws + 1] = { name = 'Impulse Drive', weapon = 'Polearm', lvl = 240, sc = { 'Gravitation', 'Induration' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Sonic Thrust', weapon = 'Polearm', lvl = 300, sc = { 'Transfixion', 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Stardiver', weapon = 'Polearm', lvl = 357, sc = { 'Gravitation', 'Transfixion' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Drakesbane', weapon = 'Polearm', lvl = 0, sc = { 'Fusion', 'Transfixion' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Camlann\'s Torment', weapon = 'Polearm', lvl = 0, sc = { 'Light', 'Fragmentation' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Geirskogul', weapon = 'Polearm', lvl = 0, sc = { 'Light', 'Distortion' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Blade: Rin', weapon = 'Katana', lvl = 5, sc = { 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Blade: Retsu', weapon = 'Katana', lvl = 30, sc = { 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Blade: Teki', weapon = 'Katana', lvl = 70, sc = { 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Blade: To', weapon = 'Katana', lvl = 100, sc = { 'Induration', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Blade: Chi', weapon = 'Katana', lvl = 150, sc = { 'Transfixion', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Blade: Ei', weapon = 'Katana', lvl = 175, sc = { 'Compression' } }
M.ws[#M.ws + 1] = { name = 'Blade: Jin', weapon = 'Katana', lvl = 200, sc = { 'Detonation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Blade: Ten', weapon = 'Katana', lvl = 225, sc = { 'Gravitation' } }
M.ws[#M.ws + 1] = { name = 'Blade: Ku', weapon = 'Katana', lvl = 250, sc = { 'Gravitation', 'Transfixion' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Blade: Yu', weapon = 'Katana', lvl = 290, sc = { 'Reverberation', 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Blade: Shun', weapon = 'Katana', lvl = 357, sc = { 'Fusion', 'Impaction' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Blade: Kamu', weapon = 'Katana', lvl = 0, sc = { 'Fragmentation', 'Compression' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Blade: Hi', weapon = 'Katana', lvl = 0, sc = { 'Darkness', 'Gravitation' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Blade: Metsu', weapon = 'Katana', lvl = 0, sc = { 'Darkness', 'Fragmentation' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Tachi: Enpi', weapon = 'Great Katana', lvl = 5, sc = { 'Transfixion', 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Tachi: Hobaku', weapon = 'Great Katana', lvl = 30, sc = { 'Induration' } }
M.ws[#M.ws + 1] = { name = 'Tachi: Goten', weapon = 'Great Katana', lvl = 70, sc = { 'Transfixion', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Tachi: Kagero', weapon = 'Great Katana', lvl = 100, sc = { 'Liquefaction' } }
M.ws[#M.ws + 1] = { name = 'Tachi: Jinpu', weapon = 'Great Katana', lvl = 150, sc = { 'Scission', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Tachi: Koki', weapon = 'Great Katana', lvl = 175, sc = { 'Reverberation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Tachi: Yukikaze', weapon = 'Great Katana', lvl = 200, sc = { 'Induration', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Tachi: Gekko', weapon = 'Great Katana', lvl = 225, sc = { 'Distortion', 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Tachi: Kasha', weapon = 'Great Katana', lvl = 250, sc = { 'Fusion', 'Compression' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Tachi: Ageha', weapon = 'Great Katana', lvl = 300, sc = { 'Compression', 'Scission' } }
M.ws[#M.ws + 1] = { name = 'Tachi: Shoha', weapon = 'Great Katana', lvl = 357, sc = { 'Fragmentation', 'Compression' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Tachi: Rana', weapon = 'Great Katana', lvl = 0, sc = { 'Gravitation', 'Induration' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Tachi: Fudo', weapon = 'Great Katana', lvl = 0, sc = { 'Light', 'Distortion' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Tachi: Kaiten', weapon = 'Great Katana', lvl = 0, sc = { 'Light', 'Fragmentation' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Heavy Swing', weapon = 'Staff', lvl = 5, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Rock Crusher', weapon = 'Staff', lvl = 40, sc = { 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Earth Crusher', weapon = 'Staff', lvl = 70, sc = { 'Detonation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Starburst', weapon = 'Staff', lvl = 100, sc = { 'Compression', 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Sunburst', weapon = 'Staff', lvl = 150, sc = { 'Compression', 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Shell Crusher', weapon = 'Staff', lvl = 175, sc = { 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Full Swing', weapon = 'Staff', lvl = 200, sc = { 'Liquefaction', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Retribution', weapon = 'Staff', lvl = 230, sc = { 'Gravitation', 'Reverberation' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Cataclysm', weapon = 'Staff', lvl = 290, sc = { 'Compression', 'Reverberation' } }
M.ws[#M.ws + 1] = { name = 'Shattersoul', weapon = 'Staff', lvl = 357, sc = { 'Gravitation', 'Induration' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Vidohunir', weapon = 'Staff', lvl = 0, sc = { 'Fragmentation', 'Distortion' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Garland of Bliss', weapon = 'Staff', lvl = 0, sc = { 'Fusion', 'Reverberation' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Omniscience', weapon = 'Staff', lvl = 0, sc = { 'Gravitation', 'Transfixion' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Gate of Tartarus', weapon = 'Staff', lvl = 0, sc = { 'Darkness', 'Distortion' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Flaming Arrow', weapon = 'Archery', lvl = 5, sc = { 'Liquefaction', 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Piercing Arrow', weapon = 'Archery', lvl = 40, sc = { 'Reverberation', 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Dulling Arrow', weapon = 'Archery', lvl = 80, sc = { 'Liquefaction', 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Sidewinder', weapon = 'Archery', lvl = 175, sc = { 'Reverberation', 'Transfixion', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Blast Arrow', weapon = 'Archery', lvl = 200, sc = { 'Induration', 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Arching Arrow', weapon = 'Archery', lvl = 225, sc = { 'Fusion' } }
M.ws[#M.ws + 1] = { name = 'Empyreal Arrow', weapon = 'Archery', lvl = 250, sc = { 'Fusion', 'Transfixion' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Refulgent Arrow', weapon = 'Archery', lvl = 290, sc = { 'Reverberation', 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Apex Arrow', weapon = 'Archery', lvl = 357, sc = { 'Fragmentation', 'Transfixion' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Jishnu\'s Radiance', weapon = 'Archery', lvl = 0, sc = { 'Light', 'Fusion' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Namas Arrow', weapon = 'Archery', lvl = 0, sc = { 'Light', 'Distortion' }, tag = 'relic' }
M.ws[#M.ws + 1] = { name = 'Hot Shot', weapon = 'Marksmanship', lvl = 5, sc = { 'Liquefaction', 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Split Shot', weapon = 'Marksmanship', lvl = 40, sc = { 'Reverberation', 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Sniper Shot', weapon = 'Marksmanship', lvl = 80, sc = { 'Liquefaction', 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Slug Shot', weapon = 'Marksmanship', lvl = 175, sc = { 'Reverberation', 'Transfixion', 'Detonation' } }
M.ws[#M.ws + 1] = { name = 'Blast Shot', weapon = 'Marksmanship', lvl = 200, sc = { 'Induration', 'Transfixion' } }
M.ws[#M.ws + 1] = { name = 'Heavy Shot', weapon = 'Marksmanship', lvl = 225, sc = { 'Fusion' } }
M.ws[#M.ws + 1] = { name = 'Detonator', weapon = 'Marksmanship', lvl = 250, sc = { 'Fusion', 'Transfixion' }, tag = 'quest' }
M.ws[#M.ws + 1] = { name = 'Numbing Shot', weapon = 'Marksmanship', lvl = 290, sc = { 'Induration', 'Detonation', 'Impaction' } }
M.ws[#M.ws + 1] = { name = 'Last Stand', weapon = 'Marksmanship', lvl = 357, sc = { 'Fusion', 'Reverberation' }, tag = 'merit' }
M.ws[#M.ws + 1] = { name = 'Trueflight', weapon = 'Marksmanship', lvl = 0, sc = { 'Fragmentation', 'Scission' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Leaden Salute', weapon = 'Marksmanship', lvl = 0, sc = { 'Gravitation', 'Transfixion' }, tag = 'mythic' }
M.ws[#M.ws + 1] = { name = 'Wildfire', weapon = 'Marksmanship', lvl = 0, sc = { 'Darkness', 'Gravitation' }, tag = 'empyrean' }
M.ws[#M.ws + 1] = { name = 'Coronach', weapon = 'Marksmanship', lvl = 0, sc = { 'Darkness', 'Fragmentation' }, tag = 'relic' }

return M
