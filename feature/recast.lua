--[[
    dlac/feature/recast.lua -- the ability recast READINESS service (issue #138,
    PRD #135). ONE question: is a job ability off cooldown right now?

    dlac never read a LIVE ability recast before this: nativedata carries the
    STATIC RecastDelay off the resource, and useitem reads ITEM charge timers,
    but no code asked "how long until I can use this ability again?" (the Central
    Services table lists it as a to-build service). The Action sequencer needs it
    so the "Reward now" button GRAYS OUT while Reward is down (PRD; acceptance
    criterion 7) rather than firing a command the client will silently reject.

    House shape (the ammowatch / fishcalc split): a PURE core -- `readyFor`,
    `remainingFor` -- that takes an injected recast READER and answers with no
    AshitaCore, so the one-question tests drive it headlessly; and a thin live
    reader (`liveRemaining`) that scans the client's ability-recast table under
    pcall. A bad / pre-login read is UNKNOWN, and unknown reads READY -- the
    buff-cache discipline (hard rule 11): a recast we cannot see must not be the
    reason a player cannot press a button. The sequencer's own worn-verify +
    timeout is the real safety net; this gate is a courtesy, not a lock.

    The recast SIGNATURE (which ability maps to which client recast slot) is
    ported by hand from the approved Pup-Helper reference addon
    (docs/reference/pet-handling-other-luas.md: BST Reward is ability id 103).
    The slot id below is FLAGGED for field verification -- see M.REWARD.
]]--

local M = {};

-- Ability signatures ported from the Pup-Helper reference. `id` is the game
-- ability id (Windower/Selindrile key their recast check on it); `timerId` is
-- the client ability-recast SLOT id the live reader matches on. BST Reward is
-- ability 103; its recast timer id is the same 103 on retail/LSB and is what the
-- reference reads. FLAGGED: confirm the timer id in the field on CatsEyeXI (a
-- server can renumber recast timers) before trusting the gray-out over the
-- sequencer's own verify.
M.REWARD = { id = 103, timerId = 103, label = 'Reward' };

-- The two SUMMON methods (issue #141). Neither carries a hardcoded timer id,
-- and that is deliberate: the Pup-Helper reference only ever named Reward's, and
-- hard rule 9 puts LIVE GAME MEMORY above every other source -- so these resolve
-- their recast slot by NAME through the client's own ability resource
-- (M.timerIdFor), and a resolution that fails answers UNKNOWN, which reads
-- READY. The courtesy gate never manufactures a "down" it did not measure; the
-- sequencer's verify-worn is the real safety net, and a command the client
-- rejects costs nothing (Bestial Loyalty does not even consume the jug).
M.CALL_BEAST      = { name = 'Call Beast',      label = 'Call Beast' };
M.BESTIAL_LOYALTY = { name = 'Bestial Loyalty', label = 'Bestial Loyalty' };

-- The recast clock unit. The client stores ability recast as an integer count
-- of QUARTER-SECONDS (the /4 convention shared with nativedata's RecastDelay,
-- which multiplies resource delay by 250ms). liveRemaining converts to whole
-- seconds so the pure core always speaks seconds -- the unit the tests and the
-- sequencer timeout use.
local QUARTERS_PER_SEC = 4;

-- ---------------------------------------------------------------------------
-- pure core -- reader injected, no AshitaCore
-- ---------------------------------------------------------------------------
--
-- `reader` answers one thing: given an ability signature, the whole seconds of
-- recast REMAINING, or nil when it cannot tell (no client, ability not on any
-- slot, pre-login). It is the single seam the tests replace.

-- Remaining recast in whole seconds, or nil when unknown. Pure; `reader` is the
-- only side of the world it touches.
function M.remainingFor(sig, reader)
    if type(sig) ~= 'table' then return nil; end
    if type(reader) ~= 'function' then return nil; end
    local ok, secs = pcall(reader, sig);
    if not ok then return nil; end
    if type(secs) ~= 'number' then return nil; end
    if secs < 0 then secs = 0; end
    return secs;
end

-- Is the ability READY (off cooldown) right now? Unknown reads READY (see the
-- header rationale): the gate never manufactures a "down" it did not measure.
-- Returns ready(bool), remaining(number|nil) so a caller can both gate AND show
-- the countdown ("Reward: 12s") without asking twice.
function M.readyFor(sig, reader)
    local rem = M.remainingFor(sig, reader);
    if rem == nil then return true, nil; end        -- unknown -> ready (courtesy gate)
    return rem <= 0, rem;
end

-- ---------------------------------------------------------------------------
-- live reader (Ashita only) -- the default recast scan
-- ---------------------------------------------------------------------------
--
-- Scan the client's 32 ability-recast slots for the one whose timer id matches
-- the signature, and return its remaining seconds. Every touch is under pcall
-- and any surprise (missing manager, an API shape this install does not carry)
-- returns nil = UNKNOWN, never a throw. Injectable as a whole (M._recastMgr) so
-- a live-path test can feed a fake manager without a game.
M._recastMgr = function()
    local mgr = nil;
    pcall(function() mgr = AshitaCore:GetMemoryManager():GetRecast(); end);
    return mgr;
end

-- The recast TIMER SLOT id for a signature. A declared `timerId` wins (the
-- Pup-Helper port); otherwise the ability's own resource record is asked BY
-- NAME -- live memory, the top data authority, so an ability whose slot id this
-- server renumbered still resolves. Memoized per signature; nil = unknown.
--
-- Both binding shapes are PROBED, never assumed (hard rule 2 -- presence proves
-- nothing here): the resource-string table the buff pickers already use, and
-- the object accessor. `M._abilityRes` is the one seam a test replaces.
M._abilityRes = function(name)
    local rec = nil;
    pcall(function()
        local resx = AshitaCore:GetResourceManager();
        if resx == nil or type(resx.GetAbilityByName) ~= 'function' then return; end
        rec = resx:GetAbilityByName(name, 0);
    end);
    return rec;
end;

function M.timerIdFor(sig)
    if type(sig) ~= 'table' then return nil; end
    if tonumber(sig.timerId) ~= nil then return tonumber(sig.timerId); end
    if sig._resolved ~= nil then
        if sig._resolved == false then return nil; end
        return sig._resolved;
    end
    local tid = nil;
    if type(sig.name) == 'string' and sig.name ~= '' then
        local rec = M._abilityRes(sig.name);
        if type(rec) == 'table' then tid = tonumber(rec.RecastTimerId) or tonumber(rec.TimerId); end
    end
    -- Cache the answer, INCLUDING the failure -- but only as `false`, so a
    -- pre-login miss is retried the next time something asks (never latch a
    -- question you could not answer -- hard rule 11).
    if tid ~= nil then sig._resolved = tid; end
    return tid;
end

-- The whole-seconds remaining for `sig` off the live client, or nil (unknown).
-- The ability-recast table is 32 slots (0..31); each slot has a timer id and a
-- remaining count. We find the slot carrying our timer id and convert its count
-- to seconds. A slot the ability is not on (ready) is simply absent -> nil ->
-- readyFor reads it as ready, which it is.
function M.liveRemaining(sig)
    if type(sig) ~= 'table' then return nil; end
    local want = M.timerIdFor(sig);
    if want == nil then return nil; end          -- unresolvable slot -> unknown -> ready
    if want ~= sig.timerId then sig = { timerId = want }; end
    local mgr = M._recastMgr();
    if mgr == nil then return nil; end
    local rem = nil;
    pcall(function()
        for i = 0, 31 do
            local tid = nil;
            if type(mgr.GetAbilityTimerId) == 'function' then tid = mgr:GetAbilityTimerId(i); end
            if tid == sig.timerId then
                local q = 0;
                if type(mgr.GetAbilityTimer) == 'function' then q = mgr:GetAbilityTimer(i) or 0; end
                rem = math.floor((tonumber(q) or 0) / QUARTERS_PER_SEC + 0.5);
                return;
            end
        end
    end);
    return rem;
end

-- The one-liner the button uses: is Reward ready? (ready, remaining) with the
-- live reader wired. A caller override (`reader`) keeps it drivable in a test.
function M.rewardReady(reader)
    return M.readyFor(M.REWARD, reader or M.liveRemaining);
end

-- The two summon methods (issue #141), same shape, same courtesy gate.
function M.callBeastReady(reader)
    return M.readyFor(M.CALL_BEAST, reader or M.liveRemaining);
end

function M.bestialLoyaltyReady(reader)
    return M.readyFor(M.BESTIAL_LOYALTY, reader or M.liveRemaining);
end

return M;
