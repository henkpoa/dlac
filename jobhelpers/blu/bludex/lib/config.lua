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
        -- Saved sets, KIND-shaped (setsModelVer 4, docs/set-types-plan.md):
        --   { kind='levels',   name, ids (the base build),
        --                      builds={{level,ids}..}, rule? }   -- 'Flat'
        --   { kind='timeline', name, builtFor, chains, ids mirror, backups }
        -- host.adoptCfg stamps a missing kind by shape; 'flat' folds into
        -- the merged kind (v4); nothing else converts.
        sets = TT{ },
        newSetKind = 'levels',    -- the type the New chooser offers first
                                  -- ('levels' = the merged flat kind | 'timeline')
        budgetOverride = 0,       -- shown when the live budget is unavailable
        applyDelay = 1.1,         -- seconds between set-spell packets
        applyMode = 'safe',       -- 'safe' (client-paced) | 'fast' (injected)
        replan = 'manual',        -- level change: 'auto' re-applies the plan
                                  -- for the new level (may UNSET); 'manual'
                                  -- nudges and waits for the click
        autoRestore = false,      -- RETIRED (pre-timeline adds-only restore);
                                  -- kept one release so old files read clean
        lastApplied = TT{ },      -- { ids = {20}, level = n } -- what the last
                                  -- apply sent, and the level it was FOR
        lastAppliedSet = '',      -- and its set BY NAME ('' = an unsaved
                                  -- draft): the FOLLOWED set -- the one
                                  -- whose kind and rule the level-change
                                  -- watcher obeys (docs/set-types-plan.md 5)
        pendingSync = TT{ },      -- { ids = {20}, need = n, waiting = {ids} }
                                  -- the tail an apply made UNDER A SYNC had
                                  -- refused by the game, and the level that
                                  -- would take it. host.finishPending comes
                                  -- back for it and clears this; applying
                                  -- anything else retires it. Persisted, so
                                  -- the promise survives a reload mid-sync.
                                  -- READ IT VIA host.pendingPromise: while
                                  -- this is still the default it is a T{},
                                  -- and T{} carries table helpers as fields
                                  -- (a `count` key here cost a crash on the
                                  -- first frame, field 2026-08-10). Never
                                  -- name a field after a table method.
        activeSetName = '',       -- last selected saved set, reloaded at startup
        tooltipDelay = 0.5,       -- seconds the cursor must rest before a tooltip
        codexDensity = 'normal',  -- codex list size: 'big'|'medium'|'normal'|'compact'
        traitsDensity = 'normal', -- traits spell-row size, same four choices
        setsLayout = 'grid',      -- RETIRED (the grid is gone); kept one release
        -- Set model version: 4 = flat+levels merged (3 was three kinds, 2
        -- timeline chains).
        -- Bumped when the stored meaning changes; adoptCfg migrates older
        -- shapes in place.
        setsModelVer = 4,
        -- The point budget: cap = base(level) + learnedBonus + merits, with
        -- merits counting only at level 75. Bumped when the meaning changes,
        -- so readings taken under older rules are discarded, not reused.
        capModelVer = 3,
        capLearnedBonus = -1,     -- points from spells learned (Boruko); -1 = unknown
        capMeritPoints = -1,      -- Assimilation points; -1 = unknown
    };
end

return M;
