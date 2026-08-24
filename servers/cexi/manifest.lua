--[[
    dlac/servers/cexi/manifest.lua -- the CatsEyeXI server pack (ADR 0035).

    THE declaration of what this server is: its identity, level cap, the
    capabilities its modules light up, the constants its mechanics were
    field-calibrated to, and the data files the pack ships (each mounted
    into the virtual dlac\data\ namespace by gear\serverpack.lua).

    Provenance notes stay in the individual data files' headers; this file
    is the contract, not the changelog.
]]--
return {
    fmt  = 1,
    id   = 'cexi',
    name = 'CatsEyeXI',

    maxLevel = 75,

    -- Capabilities: a key absent here does not exist anywhere in dlac.
    caps = {
        -- the 0x1A4 custom-protocol family
        ebox      = true,   -- Ephemeral Box store (Crystal Warriors)
        prestige  = true,   -- job-reset tiers -> level-gate waiver
        ventures  = true,   -- Venture Point economy (!ventures, VP shops)
        -- world rules
        gamemodes = true,   -- CW / Wings / ACE name-icon game modes
        giftbox   = true,   -- the goblin box / trove / tacklebox families
        disfavour = true,   -- the NM lottery bad-luck-protection curve
        -- server behaviour rulings (field-verified on CEXI)
        wearMainJobOnly  = true,   -- equip eligibility never widens via sub
        apostropheBridge = true,   -- the API drops possessive apostrophes
    },

    -- Server-tuned constants. A converted call site falls back to its
    -- historical hardcoded value when a key is absent, so an older pack
    -- never breaks a newer dlac.
    const = {
        augFormat          = 'cexi',  -- the private-augment extdata signature
        catalogMin         = 10000,   -- /dl check truncation tripwire (~14.9k shipped)
        oneirosMpPct       = 50,      -- Oneiros latent threshold (live v67 truth)
        meritMaxMpCap      = 10,      -- merit.cpp cap[75]
        mpPlayerMultiplier = 1.0,     -- settings/default/map.lua
        mpSjDivisor        = 2.0,
        moonOffset         = 68,      -- moon::get_phase epoch (feature\vanamoon)
        teleWait           = 34,      -- item_usable useDelay 30 + margin (feature\useitem)
    },

    -- The pack's modules (servers\cexi\modules\<name>\init.lua), mounted by
    -- feature\servermods in THIS order -- which is also the tray order
    -- (ebox's crates above giftbox's volatile row: the Store-under-cursor
    -- ruling) and the Gear Helpers row order. gamemode first: it provides
    -- the service the ebox module's gates read.
    modules = { 'gamemode', 'prestige', 'ebox', 'giftbox' },

    -- The data files this pack ships under servers\cexi\data\ -- the mount
    -- list for the virtual dlac\data\ namespace. A file not named here
    -- does not resolve.
    files = {
        'catalog', 'crafts', 'nmdata', 'nmdrops', 'latentstats',
        'levelscaling', 'fooddb', 'fishdb', 'spells', 'abilities',
        'digdata', 'gearsets', 'petmods', 'zones', 'itembundles',
    },
};
