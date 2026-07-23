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

    NATIVE HOME (feature/native-engine): the dir is profiles.dataDir() -- the
    one storage-home authority -- so the whole watcher family follows the
    config move with no per-module changes. The inline composition below is
    only the fallback for a broken/missing profiles module (legacy home).

    Pure definitions at load; every AshitaCore touch happens at call time under
    pcall, so headless suites load this freely.
]]--

local M = {};

-- The dlac data dir for this character (mode-aware via profiles.dataDir()).
-- nil pre-login; callers retry on their next beat.
function M.charDir()
    local ok, prof = pcall(require, 'dlac\\profiles');
    if ok and type(prof) == 'table' and type(prof.dataDir) == 'function' then
        local ok2, d = pcall(prof.dataDir);
        if ok2 and d ~= nil then return d; end
    end
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
