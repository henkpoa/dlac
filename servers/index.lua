--[[
    dlac/servers/index.lua -- the shipped server packs, in fallback order
    (ADR 0035). A tracked list, not a directory scan: adding a pack is a
    commit, and gear\serverpack.lua pcall-requires each id's manifest --
    an id whose manifest will not load simply is not a pack.
]]--
return { 'cexi' };
