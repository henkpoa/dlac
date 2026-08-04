--[[
    bludex/lib/config.lua -- the settings shape, shared by every host of the
    bludex library: the standalone addon (bludex.lua) and any embedding addon
    (e.g. dlac's BLU helper). One definition so the two can never drift.

    Headless-safe: uses Ashita's global T{} when present, plain tables when
    not (smoke test).
]]--

local M = {};

local function TT(t)
    if type(T) == 'function' or (type(T) == 'table' and getmetatable(T) and getmetatable(T).__call) then
        return T(t);
    end
    return t;
end

-- The full default tree. Call fresh per settings.load -- the settings lib
-- mutates what it is given.
function M.defaults()
    return TT{
        sets = TT{ },             -- { { name = s, ids = {20 real ids} }, ... }
        budgetOverride = 0,       -- shown when the live budget is unavailable
        applyDelay = 1.1,         -- seconds between set-spell packets
        applyMode = 'safe',       -- 'safe' (client-paced) | 'fast' (injected)
        autoRestore = false,      -- re-add spells stripped by level changes
        lastApplied = TT{ },      -- { ids = {20} } -- the auto-restore target
        activeSetName = '',       -- last selected saved set, reloaded at startup
        codexDensity = 'normal',  -- codex list size: 'big' | 'normal' | 'compact'
    };
end

return M;
