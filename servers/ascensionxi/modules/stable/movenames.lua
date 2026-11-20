--[[
    AscensionXI companion moves whose client name is not a name (AXI-139).

    A pet's Ready move reaches PetAction rules under the name the client's
    monster-ability table gives it. Defensive Shell (the Uragnite's move, mob
    skill 4205 in the server's beastmaster catalog) is a custom move, and the
    client table holds "." for it. Nobody can write a rule against ".", so the
    pack supplies the name for that skill id.

    Henrik, 2026-11-20: the other three moves keep the client's own name --
    "??? Needles", "Berserk" and "Frogkick" -- so they need no entry here.

    The engine asks through the server pack service 'petMoveNames':
        nameOf(skillId, clientName) -> the name to use, or nil for "keep it".
]]--
local M = {};

M.NAMES = {
    [4205] = 'Defensive Shell',
};

function M.nameOf(skillId, clientName)
    return M.NAMES[tonumber(skillId) or -1];
end

return M;
