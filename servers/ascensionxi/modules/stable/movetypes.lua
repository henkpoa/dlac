--[[
    What each AscensionXI companion Ready move does (AXI-155).

    A PetAction rule can ask readyType = Physical / Magic / Breath / Effect /
    Buff / Heal, so ONE rule gears every physical move instead of a rule per
    move per companion. The client knows none of this -- a monster ability is
    a name and nothing else -- so this is the server's own answer: all 152
    moves in modules/custom/lua/beastmaster_catalog.lua, each typed by what
    its script does (scripts/actions/mobskills/<script>.lua and the companion
    overrides in modules/custom/lua/beastmaster_moves.lua), AscensionXI main
    4887de3a, 2026-11-22. The counts agree with the "kind" column of the
    server's client/sources/beastmaster/ready-scaling.json.

        Physical  the move deals physical damage. The four ranged moves
                  (Leaf Dagger, Needleshot, Sharp Sting, Stone Throw) are here
                  too (Henrik, 2026-11-22), and so is Random Needles, whose
                  damage is a fixed roll.
        Magic     magic damage, the drains (Blood Drain, Digest, Drainkiss)
                  and Final Sting.
        Breath    breath damage.
        Effect    lands a status effect or removes TP and deals no damage.
        Buff      a buff on the companion itself.
        Heal      heals the companion.

    Keyed by the mob skill id the pet's action packet carries, so a move the
    client spells oddly ("??? Needles", ".") needs nothing special. The engine
    asks through the server pack service 'petMoveTypes':
        typeOf(skillId, name) -> the type, or nil for a move not listed.
]]--
local M = {};

M.TYPES = {
    -- Physical (59)
    [3863] = 'Physical',  -- Big Scissors
    [3853] = 'Physical',  -- Blockhead
    [3854] = 'Physical',  -- Brain Crush
    [3911] = 'Physical',  -- Chomp Rush
    [3850] = 'Physical',  -- Claw Cyclone
    [291] = 'Physical',   -- Claw Storm
    [460] = 'Physical',   -- Cross Attack
    [3892] = 'Physical',  -- Cyclotail
    [353] = 'Physical',   -- Death Scissors
    [3894] = 'Physical',  -- Double Claw
    [294] = 'Physical',   -- Eye Scratch
    [431] = 'Physical',   -- Fluid Spread
    [432] = 'Physical',   -- Fluid Toss
    [3840] = 'Physical',  -- Foot Kick
    [3868] = 'Physical',  -- Frog Kick
    [424] = 'Physical',   -- Full-force Blow
    [3895] = 'Physical',  -- Grapple
    [3843] = 'Physical',  -- Head Butt
    [622] = 'Physical',   -- Helldive
    [395] = 'Physical',   -- Jet Stream
    [3857] = 'Physical',  -- Lamb Chop
    [3846] = 'Physical',  -- Leaf Dagger
    [350] = 'Physical',   -- Mandible Bite
    [3885] = 'Physical',  -- Mandibular Bite
    [3866] = 'Physical',  -- Needleshot
    [3891] = 'Physical',  -- Nimble Snap
    [3871] = 'Physical',  -- Numbshroom
    [507] = 'Physical',   -- Painful Whip
    [506] = 'Physical',   -- Palsynyxis
    [1699] = 'Physical',  -- Pecking Flurry
    [351] = 'Physical',   -- Poison Sting
    [3875] = 'Physical',  -- Power Attack
    [3870] = 'Physical',  -- Queasyshroom
    [3867] = 'Physical',  -- Random Needles
    [3849] = 'Physical',  -- Razor Fang
    [3877] = 'Physical',  -- Rhino Attack
    [3910] = 'Physical',  -- Ripper Fang
    [452] = 'Physical',   -- Screwdriver
    [3909] = 'Physical',  -- Scythe Tail
    [3872] = 'Physical',  -- Shakeshroom
    [334] = 'Physical',   -- Sharp Sting
    [3859] = 'Physical',  -- Sheep Charge
    [810] = 'Physical',   -- Sickle Slash
    [3938] = 'Physical',  -- Somersault
    [290] = 'Physical',   -- Spinning Claw
    [3897] = 'Physical',  -- Spinning Top
    [3905] = 'Physical',  -- Spiral Spin
    [687] = 'Physical',   -- Sprout Smack
    [685] = 'Physical',   -- Sprout Spin
    [281] = 'Physical',   -- Stomping
    [289] = 'Physical',   -- Stone Throw
    [3900] = 'Physical',  -- Suction
    [3904] = 'Physical',  -- Sudden Lunge
    [3851] = 'Physical',  -- Tail Blow
    [456] = 'Physical',   -- Tentacle
    [288] = 'Physical',   -- Vicious Claw
    [3842] = 'Physical',  -- Whirl Claws
    [3845] = 'Physical',  -- Wild Oats
    [354] = 'Physical',   -- Wild Rage
    -- Magic (24)
    [3907] = 'Magic',     -- Acid Mist
    [811] = 'Magic',      -- Acid Spray
    [450] = 'Magic',      -- Aqua Ball
    [394] = 'Magic',      -- Blood Drain
    [423] = 'Magic',      -- Brain Drain
    [3914] = 'Magic',     -- Corrosive Ooze
    [3880] = 'Magic',     -- Cursed Sphere
    [437] = 'Magic',      -- Death Ray
    [433] = 'Magic',      -- Digest
    [3901] = 'Magic',     -- Drainkiss
    [3841] = 'Magic',     -- Dust Cloud
    [355] = 'Magic',      -- Earth Pounder
    [336] = 'Magic',      -- Final Sting
    [3852] = 'Magic',     -- Fireball
    [425] = 'Magic',      -- Gastric Bomb
    [458] = 'Magic',      -- Ink Jet
    [462] = 'Magic',      -- Maelstrom
    [3913] = 'Magic',     -- Purulent Ooze
    [426] = 'Magic',      -- Sandspin
    [427] = 'Magic',      -- Tremors
    [3881] = 'Magic',     -- Venom
    [463] = 'Magic',      -- Whirlwind
    [1720] = 'Magic',     -- Wind Shear
    [623] = 'Magic',      -- Wing Cutter
    -- Breath (10)
    [3861] = 'Breath',    -- Bubble Shower
    [349] = 'Breath',     -- Cold Breath
    [1718] = 'Breath',    -- Crosswind
    [3874] = 'Breath',    -- Dark Spore
    [376] = 'Breath',     -- Foul Breath
    [348] = 'Breath',     -- Numbing Breath
    [345] = 'Breath',     -- Poison Breath
    [416] = 'Breath',     -- Sand Breath
    [3873] = 'Breath',    -- Silence Gas
    [451] = 'Breath',     -- Splash Breath
    -- Effect (38)
    [292] = 'Effect',     -- Blank Gaze
    [3899] = 'Effect',    -- Blaster
    [3898] = 'Effect',    -- Chaotic Eye
    [284] = 'Effect',     -- Cold Stare
    [3844] = 'Effect',    -- Dream Flower
    [1701] = 'Effect',    -- Feather Tickle
    [3896] = 'Effect',    -- Filamented Hold
    [2183] = 'Effect',    -- Fuscous Ooze
    [504] = 'Effect',     -- Gas Shell
    [3889] = 'Effect',    -- Geist Wall
    [3887] = 'Effect',    -- Gloeosuccus
    [438] = 'Effect',     -- Hex Eye
    [3876] = 'Effect',    -- Hi-Freq Field
    [3855] = 'Effect',    -- Infrasonics
    [3924] = 'Effect',    -- Intimidate
    [3906] = 'Effect',    -- Noisome Powder
    [3890] = 'Effect',    -- Numbing Noise
    [1721] = 'Effect',    -- Obfuscate
    [3888] = 'Effect',    -- Palsy Pollen
    [3848] = 'Effect',    -- Roar
    [275] = 'Effect',     -- Sandblast
    [276] = 'Effect',     -- Sandpit
    [3847] = 'Effect',    -- Scream
    [3860] = 'Effect',    -- Sheep Song
    [686] = 'Effect',     -- Slumber Powder
    [393] = 'Effect',     -- Sonic Boom
    [280] = 'Effect',     -- Sonic Wave
    [3886] = 'Effect',    -- Soporific
    [429] = 'Effect',     -- Sound Vacuum
    [812] = 'Effect',     -- Spider Web
    [3879] = 'Effect',    -- Spoil
    [3869] = 'Effect',    -- Spore
    [344] = 'Effect',     -- Sticky Thread
    [508] = 'Effect',     -- Suctorial Tentacle
    [3908] = 'Effect',    -- TP Drainkiss
    [3893] = 'Effect',    -- Toxic Spit
    [392] = 'Effect',     -- Ultrasonics
    [3884] = 'Effect',    -- Venom Spray
    -- Buff (16)
    [3862] = 'Buff',      -- Bubble Curtain
    [346] = 'Buff',       -- Cocoon
    [4205] = 'Buff',      -- Defensive Shell
    [286] = 'Buff',       -- Dhalmel Berserk
    [459] = 'Buff',       -- Hard Membrane
    [3865] = 'Buff',      -- Metallic Body
    [3858] = 'Buff',      -- Rage
    [418] = 'Buff',       -- Regeneration
    [3878] = 'Buff',      -- Rhino Guard
    [3864] = 'Buff',      -- Scissor Guard
    [3856] = 'Buff',      -- Secretion
    [356] = 'Buff',       -- Sharp Strike
    [454] = 'Buff',       -- Water Shield
    [3926] = 'Buff',      -- Water Wall
    [285] = 'Buff',       -- Whistle
    [1722] = 'Buff',      -- Zephyr Mantle
    -- Heal (5)
    [440] = 'Heal',       -- Catharsis
    [287] = 'Heal',       -- Healing Breeze
    [295] = 'Heal',       -- Magic Fruit
    [335] = 'Heal',       -- Pollen
    [3903] = 'Heal',      -- Wild Carrot
};

function M.typeOf(skillId, name)
    return M.TYPES[tonumber(skillId) or -1];
end

return M;
