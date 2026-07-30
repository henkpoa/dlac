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

-- The recast clock unit: the client stores ability recast in JIFFIES -- 1/60th
-- of a second. liveRemaining converts to whole seconds so the pure core always
-- speaks seconds, the unit the tests and the sequencer timeout use.
--
-- This was /4 until 2026-07-30 (a quarter-second guess borrowed from
-- nativedata's RecastDelay, which is a RESOURCE field and a different unit
-- entirely), and it was wrong by 15x: a 20-minute Bestial Loyalty read as five
-- hours. It never flipped ready/down -- both are positive -- but every countdown
-- dlac has ever shown was fifteen times too big.
--
-- The unit is settled by two independent addons on this disk, neither of them
-- guessing: `timers\recasts.lua` builds its comparison baseline as
-- `60 * (90 + reduction)` with the comment "Multiplying by 60 to get the same
-- format as timer is stored in", and Rune-Actually-Helper divides by 60 with the
-- comment "jiffies -> seconds".
local JIFFIES_PER_SEC = 60;

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
-- The name INDEX the by-name lookup takes is not one number: dlac already
-- hedges `GetItemByName(name, 2) or GetItemByName(name, 0)` in two places
-- because one index alone did not answer. Abilities got the single `0` and,
-- from the shape of the 2026-07-30 field report, that is the read that failed:
-- an unresolvable slot answers UNKNOWN, unknown reads READY, and the Resummon
-- rule fired Bestial Loyalty into its own cooldown while its fallback sat unused.
local NAME_INDEXES = { 0, 2, 1 };

-- ...and when NO index answers, the whole ability table is walked ONCE and
-- indexed by name. That is the pattern the proven sibling addons use from the
-- other direction (Rune-Actually-Helper: "GetAbilityByTimerId can hand back nil
-- for a shared id... we scan every ability"), and it is the read that cannot be
-- defeated by an index convention. Latched only when it produced something --
-- never latch a question you could not answer (hard rule 11) -- and throttled,
-- because the caller is a Panel that renders every frame.
local _byName = nil;
local _scanAt = nil;
M.SCAN_THROTTLE_S = 5.0;
M.SCAN_MAX_ID     = 2048;

local function now()
    local t = nil;
    pcall(function() t = os.clock(); end);
    return tonumber(t) or 0;
end

-- READ A FIELD OFF A RESOURCE OBJECT. Guarded on `~= nil`, NEVER on
-- `type(x) == 'table'`, and that distinction is this whole file's field bug.
--
-- Ashita's resource objects are not Lua tables -- they index with `.` and answer
-- `userdata` to `type()`. Every working reader in dlac and in the proven sibling
-- addons already knew it and checks nil: `nativedata` (`elseif action.Type ==
-- 'Ability' and res ~= nil then ... res.RecastTimerId`), `dispatch`'s item
-- lookup (`if r ~= nil then id = tonumber(r.Id)`), Rune-Actually-Helper
-- (`if cand ~= nil and cand.RecastTimerId == id`). This file was the one place
-- that type-checked, so the by-NAME resolution never once returned a slot --
-- since the day it was written. Reward was unaffected and hid it: Reward
-- declares `timerId = 103` and never takes the name path at all, which is why
-- its countdown always worked while both summons read UNKNOWN, and UNKNOWN
-- reads READY (field 2026-07-30: the Resummon rule firing into a cooldown).
--
-- pcall'd because indexing an unexpected object is the caller's problem to
-- survive, not to crash on.
-- A REAL seam (called as M._field, not as an upvalue): a test cannot fabricate
-- userdata carrying fields in stock Lua, so proving "the guard admits a
-- non-table" needs the read itself to be replaceable. Same idiom as
-- M._abilityRes / M._recastMgr.
M._field = function(obj, key)
    if obj == nil then return nil; end
    local v = nil;
    pcall(function() v = obj[key]; end);
    return v;
end;
local function field(obj, key) return M._field(obj, key); end

local function scanAbilities()
    if _byName ~= nil then return _byName; end
    local at = now();
    if _scanAt ~= nil and (at - _scanAt) >= 0 and (at - _scanAt) < M.SCAN_THROTTLE_S then
        return nil;
    end
    _scanAt = at;
    local found = nil;
    pcall(function()
        local resx = AshitaCore:GetResourceManager();
        if resx == nil or type(resx.GetAbilityById) ~= 'function' then return; end
        local map = {};
        local n = 0;
        for id = 0, M.SCAN_MAX_ID do
            local rec = resx:GetAbilityById(id);
            if rec ~= nil then
                local nm = field(rec, 'Name');
                if type(nm) == 'string' then
                    if nm ~= '' then map[string.lower(nm)] = rec; n = n + 1; end
                elseif nm ~= nil then
                    -- The name is itself a resource-side list (Name[1] is the
                    -- English one in every reader on this disk); read it the
                    -- same guarded way rather than assuming it is a Lua table.
                    for i = 1, 4 do
                        local s = field(nm, i);
                        if type(s) == 'string' and s ~= '' then
                            map[string.lower(s)] = rec; n = n + 1;
                        end
                    end
                end
            end
        end
        if n > 0 then found = map; end
    end);
    if found ~= nil then _byName = found; end
    return found;
end

M._abilityRes = function(name)
    if type(name) ~= 'string' or name == '' then return nil; end
    local rec = nil;
    pcall(function()
        local resx = AshitaCore:GetResourceManager();
        if resx == nil or type(resx.GetAbilityByName) ~= 'function' then return; end
        for _, idx in ipairs(NAME_INDEXES) do
            local r = resx:GetAbilityByName(name, idx);
            if r ~= nil then rec = r; return; end
        end
    end);
    if rec ~= nil then return rec; end
    local map = scanAbilities();
    if type(map) == 'table' then return map[string.lower(name)]; end
    return nil;
end;

-- Drop the scanned index (a test reset; also the honest answer to a resource
-- table that has only just become readable).
function M.forgetAbilities() _byName, _scanAt = nil, nil; end

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
        -- `~= nil`, never a type check: see `field` above -- this ONE guard is
        -- why no ability ever resolved its recast slot by name.
        if rec ~= nil then
            tid = tonumber(field(rec, 'RecastTimerId')) or tonumber(field(rec, 'TimerId'));
        end
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
-- to seconds.
--
-- READY AND UNKNOWN ARE DIFFERENT ANSWERS, and until 2026-07-30 this returned
-- nil for both -- an ability whose slot we resolved and found idle (ready, and
-- we know it) and one whose slot we could not resolve at all (we know nothing).
-- Every caller that only wanted to grey out a button was right not to care. The
-- one that had to CHOOSE between two abilities could not tell "up" from "no
-- idea", which is how the Resummon rule preferred an unmeasurable Bestial
-- Loyalty over a Call Beast it could see was ready. So:
--     0   = resolved, no slot holds it -> READY, measured
--     >0  = resolved and counting down -> DOWN, measured
--     nil = could not resolve / no client -> UNKNOWN
-- readyFor still answers `true` for 0 and for nil; the REMAINING it hands back
-- beside it is what separates them.
function M.liveRemaining(sig)
    if type(sig) ~= 'table' then return nil; end
    local want = M.timerIdFor(sig);
    if want == nil then return nil; end          -- unresolvable slot -> unknown
    if want ~= sig.timerId then sig = { timerId = want }; end
    local mgr = M._recastMgr();
    if mgr == nil then return nil; end
    -- Resolved, so whatever we find is a MEASUREMENT: an ability on no slot is
    -- idle, which is 0 seconds remaining, not "no idea".
    local rem = 0;
    pcall(function()
        for i = 0, 31 do
            local tid = nil;
            if type(mgr.GetAbilityTimerId) == 'function' then tid = mgr:GetAbilityTimerId(i); end
            if tid == sig.timerId then
                local q = 0;
                if type(mgr.GetAbilityTimer) == 'function' then q = mgr:GetAbilityTimer(i) or 0; end
                rem = math.floor((tonumber(q) or 0) / JIFFIES_PER_SEC + 0.5);
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
