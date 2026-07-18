--[[
    dlac/lib/statefile.lua -- the ADDON-SIDE half of the statefile seam (v70).

    The four watchers (craftwatch / helmwatch / fishwatch / pinwatch) each
    carried their own copy of the <char>\dlac\ dir resolution ("craftwatch's
    kiCharDir pattern", copied with the comment saying so). The path truth
    lives here now; the watchers keep their own serializers and write sites.

    The ENGINE'S half stays dispatch-local on purpose (charDir + ensureStateFile
    in dispatch.lua): the two Lua states share the FILES, not the code -- the
    LAC-state engine reads gState first and self-swaps on version moves, and
    keeping its reader in the one seeded file keeps the handshake in one place.

    Pure definitions at load; every AshitaCore touch happens at call time under
    pcall, so headless suites load this freely.
]]--

local M = {};

-- <char>\dlac\ via the party manager (addon state -- no gState here).
-- nil pre-login; callers retry on their next beat.
function M.charDir()
    local dir = nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name, id = party:GetMemberName(0), party:GetMemberServerId(0);
        if name == nil or name == '' or id == nil then return; end
        dir = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\dlac\\',
            AshitaCore:GetInstallPath(), name, id);
    end);
    return dir;
end

return M;
