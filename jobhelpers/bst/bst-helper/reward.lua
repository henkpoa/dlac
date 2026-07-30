--[[
    dlac/jobhelpers/bst/bst-helper/reward.lua -- the BST Helper's REWARD rule. The
    module's second standing behavior, and the one that SPENDS AN ITEM.

    THE SAME PATH, TWO REQUESTERS. `M.request(id)` is the whole act: pick the food
    off the Ladder, overlay the optional Reward set, open ONE Action sequence, let
    it verify the food WORN and fire. The Panel's "Reward now" button calls it, and
    so does the automatic rule below -- there is exactly one implementation, so
    "identical refusal behavior to the button" is true by construction rather than
    by a second set of tests agreeing with the first. The button stays: it is the
    field-test lever.

    THE RULE. While the module is acting and the pet sits BELOW the player's
    pet-HP% threshold (default 50), the rule requests that same sequence. It is
    driven by the pet vitals beat (S.pet.subscribe), which publishes presence /
    HP% / TP / name once per dispatch beat -- the module subscribes in its init
    hook, so the rule works with the Job Helpers tab closed.

    THE LOCKOUT is what keeps a sustained low-HP pet from becoming a stream of
    commands and chat lines. Every ATTEMPT arms it (fired, refused or aborted
    alike), and nothing is attempted again until the window elapses -- so a refusal
    costs at most one line per window, whatever the pet's bar does in between. Two
    states deliberately do NOT arm it, because nothing was attempted: a sequence
    already running (`busy`) and Reward still on cooldown (`recast`). Recast is
    also SILENT, which is exactly what the button does -- it greys out and says
    nothing.

    ONE REFUSAL IS QUIETER STILL: "you are not carrying any pet food" speaks ONCE
    PER ZONE. The lockout is a budget for how often the rule may speak, and it
    suits every refusal the world might resolve on its own -- but an empty bag is
    fixed by shopping, not by waiting thirty seconds, so a per-window line is
    thirty reminders of one thing the player already knows. Zoning re-arms it
    (you may have shopped), and so does carrying food again (running out later is
    real news).

    House shape: `decide(vitals, state)` is PURE -- vitals + state in, decision
    out, no services and no clock -- so the threshold, the lockout and every gate
    are headless checks (BRW*). `liveState` assembles that state from the module
    API; `onVitals` is the beat subscriber that joins the two.
]]--

local M = {};

-- The pet-HP% threshold. The rule fires STRICTLY BELOW it, so a pet sitting
-- exactly at the threshold never does -- "below 50" means below 50.
M.DEFAULT_THRESHOLD = 50;
M.MIN_THRESHOLD     = 1;    -- 0 would mean "never"; the rule switch is the off switch
M.MAX_THRESHOLD     = 99;   -- 100 would mean "always"; a full pet needs no Reward

-- The retry lockout, seconds. Sized to comfortably outlast one whole sequence
-- (the 4s verify window plus the post-fire hold) and to be the feature's "how
-- often may this speak" budget: a BST standing over a hurt pet with no food in
-- their bags hears about it twice a minute, not twice a second. FLAGGED for the
-- field round -- Reward's own recast (~90s on retail) means a real re-fire waits
-- far longer than this anyway, so the number only ever governs REFUSALS.
M.LOCKOUT_S = 30;

-- The action command and the verify window. FLAGGED for field verification: the
-- exact target token on CatsEyeXI (<me> vs <pet>) is confirmed in-game before this
-- ships -- the sequencer's verify-worn gate protects the GEAR either way, but a
-- wrong token means the command no-ops.
M.COMMAND        = '/ja "Reward" <me>';
M.VERIFY_TIMEOUT = 4;

-- The recast signature for the button's grey-out, as MODULE data -- it is a fact
-- about this job's ability, so it belongs to the module rather than to the recast
-- service's own table.
--
-- Both fields are given on purpose. `timerId` is the Pup-Helper reference port
-- (BST Reward is ability 103, and its recast timer id is 103 on retail/LSB) and it
-- WINS when present; `name` is the fallback path, resolved through the client's own
-- ability resource -- live memory, the top data authority (hard rule 9), so an
-- ability this server renumbered still resolves. FLAGGED: confirm the timer id in
-- the field before trusting the grey-out over the sequencer's own verify.
M.RECAST = { id = 103, timerId = 103, name = 'Reward', label = 'Reward' };

-- The module API table, handed over by init.
local _S = nil;

local _last          = nil;    -- the last automatic decision (the Panel reports it)
local _lastAttemptAt = nil;    -- the lockout clock: when the rule last ATTEMPTED
local _saidFoodIn    = nil;    -- the zone we last said "no pet food" in (see below)
local _saidFood      = false;

local function cfg()
    if type(_S) ~= 'table' then return nil; end
    return _S.cfg;
end

local function now()
    if type(_S) == 'table' and type(_S.now) == 'function' then return _S.now(); end
    return 0;
end

-- One loud line. Refusals are LOUD (hard rule 12): a silently skipped Reward is
-- indistinguishable from a broken one. Kept as an overridable seam so the suite can
-- read back the lines it produced.
M._emit = function(line)
    if type(_S) == 'table' and type(_S.say) == 'table' and type(_S.say.err) == 'function' then
        _S.say.err(line);
        return;
    end
    pcall(function() print('[dlac] ' .. tostring(line)); end);
end;

-- ---------------------------------------------------------------------------
-- the settings
-- ---------------------------------------------------------------------------

-- Is the automatic rule armed? Default OFF, and for the reason the Fight switch
-- is: this module ISSUES COMMANDS and this rule additionally CONSUMES AN ITEM, so
-- a freshly installed helper must never start spending a player's food on its own.
-- The player arms it; the row pill only ever silences.
function M.armed()
    local c = cfg();
    local v = nil;
    if c ~= nil then v = c.get('rewardArmed'); end
    return v == true;
end

function M.setArmed(on)
    local c = cfg();
    if c == nil then return false; end
    return c.set('rewardArmed', on == true);
end

-- Clamp a threshold to the usable band. An unreadable / absent value reads as the
-- default rather than as "never" -- the rule switch is the off switch.
function M.clampThreshold(v)
    local n = tonumber(v);
    if n == nil then return M.DEFAULT_THRESHOLD; end
    n = math.floor(n + 0.5);
    if n < M.MIN_THRESHOLD then return M.MIN_THRESHOLD; end
    if n > M.MAX_THRESHOLD then return M.MAX_THRESHOLD; end
    return n;
end

function M.threshold()
    local c = cfg();
    local v = nil;
    if c ~= nil then v = c.get('rewardThreshold'); end
    return M.clampThreshold(v);
end

-- Clamped on the way IN, so a whole slider DRAG costs one write per distinct
-- percent it crosses rather than one per frame: the store writes on mutation only,
-- and every frame of a drag inside the same percent rounds to the value already
-- stored.
function M.setThreshold(v)
    local c = cfg();
    if c == nil then return false; end
    return c.set('rewardThreshold', M.clampThreshold(v));
end

-- The optional Reward set, by name, or nil for "food only". Persisted because the
-- AUTOMATIC path has no Panel to read a session-only choice from: a set picked
-- once must still be worn by a Reward fired an hour later with the tab closed.
-- Stored as '' for none, so clearing it is an ordinary string write.
function M.setName()
    local c = cfg();
    local v = nil;
    if c ~= nil then v = c.get('rewardSet'); end
    if type(v) ~= 'string' or v == '' or v == 'None' then return nil; end
    return v;
end

function M.setSetName(name)
    local c = cfg();
    if c == nil then return false; end
    if type(name) ~= 'string' or name == 'None' then name = ''; end
    return c.set('rewardSet', name);
end

-- ---------------------------------------------------------------------------
-- the PURE decision -- vitals + state in, "request the sequence?" out
-- ---------------------------------------------------------------------------
--
-- vitals = the pet vitals record: { present, hpp, tp, name }
-- state  = {
--   armed         = <bool>,        -- the rule switch
--   threshold     = <number>,      -- pet HP%
--   active        = <bool>,        -- the module-activity predicate said "acting"
--   reason        = <'off'|'job'|'town'|'dead'|'zoning'|nil>,  -- why it is not
--   busy          = <bool>,        -- a sequence is already live
--   recastReady   = <true|false|nil>,   -- false ONLY when measured DOWN
--   lastAttemptAt = <number|nil>,  -- the lockout clock
--   lockout       = <number|nil>,  -- window seconds (defaults to M.LOCKOUT_S)
--   now           = <number>,
-- }
-- returns { act, reason, hpp, threshold, retryIn }
--
-- The gate order IS the reporting order: the Panel's "not acting" line is
-- whichever check held first, so the most specific true statement wins.
--
-- Three asymmetries, each deliberate:
--   * `active` must be POSITIVELY true. An unreadable world (headless, pre-login,
--     a job read that has not settled) is not permission to spend a player's food.
--   * `vitals.present` must be POSITIVELY true, and an unreadable HP% refuses.
--     Guessing a pet's HP is how a Reward gets fired at a healthy pet.
--   * `recastReady` blocks only on FALSE. Unknown reads READY, matching the recast
--     service's courtesy gate and the button's grey-out exactly.
function M.decide(vitals, state)
    state = (type(state) == 'table') and state or {};

    if state.armed ~= true then return { act = false, reason = 'off' }; end

    if state.active ~= true then
        return { act = false, reason = state.reason or 'inactive' };
    end

    local v = (type(vitals) == 'table') and vitals or {};
    if v.present ~= true then return { act = false, reason = 'no-pet' }; end

    local hpp = tonumber(v.hpp);
    if hpp == nil then return { act = false, reason = 'no-hp' }; end

    local th = M.clampThreshold(state.threshold);
    -- STRICTLY below: a pet at the threshold is not below it (AC1).
    if hpp >= th then
        return { act = false, reason = 'above', hpp = hpp, threshold = th };
    end

    -- The lockout: one attempt per window, so a sustained sub-threshold pet costs
    -- at most one command and one refusal line per window (AC2). A clock that went
    -- BACKWARDS accepts rather than muting for a whole window.
    local nowT    = tonumber(state.now) or 0;
    local lockout = tonumber(state.lockout) or M.LOCKOUT_S;
    local last    = tonumber(state.lastAttemptAt);
    if last ~= nil then
        local since = nowT - last;
        if since >= 0 and since < lockout then
            return { act = false, reason = 'lockout', hpp = hpp, threshold = th,
                     retryIn = lockout - since };
        end
    end

    -- Nothing below here ATTEMPTS anything, so neither arms the lockout.
    if state.busy == true then
        return { act = false, reason = 'busy', hpp = hpp, threshold = th };
    end
    if state.recastReady == false then
        return { act = false, reason = 'recast', hpp = hpp, threshold = th };
    end

    return { act = true, reason = nil, hpp = hpp, threshold = th };
end

-- A short human line for a decision -- the Panel's report. Deliberately NOT chat:
-- the rule evaluates every dispatch beat, and only an ATTEMPT is news.
local DECISION_TEXT = {
    ['off']      = 'the Reward rule is off',
    ['inactive'] = 'the helper is not acting',
    ['job']      = 'not on main-job BST',
    ['town']     = 'in town',
    ['dead']     = 'dead',
    ['zoning']   = 'zoning',
    ['no-pet']   = 'no pet out',
    ['no-hp']    = "your pet's HP could not be read",
    ['above']    = 'your pet is above the threshold',
    ['busy']     = 'another sequence is running',
    ['recast']   = 'Reward is still on cooldown',
};

function M.decisionText(d)
    if type(d) ~= 'table' then return 'nothing yet'; end
    if d.act == true then
        return string.format('asked for Reward at %s%% pet HP', tostring(d.hpp or '?'));
    end
    if d.reason == 'lockout' then
        return string.format('waiting out the retry lockout (%ds)',
            math.max(0, math.floor((tonumber(d.retryIn) or 0) + 0.5)));
    end
    return DECISION_TEXT[d.reason] or tostring(d.reason or 'held');
end

function M.lastDecision() return _last; end

-- Forget the lockout (job change / logout / test reset). The once-per-zone
-- food line resets with it: a job change is at least as good a reason to hear
-- it again as a zone change.
function M.resetLockout()
    _lastAttemptAt, _last = nil, nil;
    _saidFood, _saidFoodIn = false, nil;
end

function M.lockedUntil()
    if _lastAttemptAt == nil then return nil; end
    return _lastAttemptAt + M.LOCKOUT_S;
end

-- ---------------------------------------------------------------------------
-- the ACT -- one path, two requesters (the button and the rule)
-- ---------------------------------------------------------------------------

-- Build the Action sequence request: the optional Reward set overlaid, then the
-- chosen food forced into Ammo (food always wins the ammo slot).
--
-- `need` is the CONSUMED slot ALONE, and that is an ACCEPTED design ruling
-- (maintainer, at the #138 merge), not an oversight: Reward eats what is worn in
-- Ammo, so the food is the precondition and must verify; the Reward set dresses
-- BEST-EFFORT, so a senior claimant holding one of its slots costs that slot and
-- refuses nothing. It also composes with a player's own Reward-gear Trigger --
-- leave the set picker empty, claim the food only, and the trigger dresses the
-- rest at precast.
--
-- `module` and `order` are NOT set here: the module API fills them in from the
-- module's own identity, so this cannot request as somebody else or get its own
-- section priority wrong.
function M.buildRequest(foodName, setName)
    -- COPIED, never used in place: Ammo is forced below and the sequencer keeps
    -- this table for the life of the sequence, so it must be ours alone.
    local claim = {};
    if type(_S) == 'table' and type(_S.sets) == 'table' and type(_S.sets.slotsOf) == 'function' then
        local ok, slots = pcall(_S.sets.slotsOf, setName);
        if ok and type(slots) == 'table' then
            for slot, item in pairs(slots) do claim[slot] = item; end
        end
    end
    claim.Ammo = foodName;                  -- food union set; food owns Ammo
    return {
        label   = 'Reward',
        claim   = claim,
        need    = { Ammo = foodName },      -- the one slot that MUST verify worn
        command = M.COMMAND,
        timeout = M.VERIFY_TIMEOUT,
    };
end

-- THE ACT. Pick the food, refuse loudly if there is none, else open the sequence.
-- Returns { ok = <bool>, reason = <slug|nil> }; never throws.
--
-- Both requesters land here, so the refusal behavior the button shows IS the
-- refusal behavior the rule shows -- no food carried, a senior claimant holding
-- the Ammo slot (the sequencer's own loud refusal / verify-timeout abort), a
-- service that failed to load. The one difference is deliberate: the rule's CALLER
-- arms the lockout first, so those lines cost one per window.
function M.request()
    local S = _S;
    if type(S) ~= 'table' then return { ok = false, reason = 'service' }; end

    local pick = S.pet.food();
    if type(pick) ~= 'table' or pick.ok ~= true then
        -- ONCE PER ZONE (Henrik, 2026-07-30, off his own probe log: the line
        -- appeared mid-fight while he was busy proving something else).
        --
        -- The lockout is the wrong budget for THIS refusal. It is sized for "how
        -- often may this rule speak", and every other refusal it covers is
        -- something the world might fix on its own -- a cooldown ends, a pet
        -- heals. Carrying no pet food does not: it is fixed by opening your bags,
        -- which you cannot do usefully in the middle of the fight that is
        -- printing it, so a line every 30 seconds is thirty reminders of one
        -- thing you already know. A zone change is the natural moment it might
        -- have become false -- you stopped, you shopped, you came back.
        --
        -- The ZONE ITSELF is the latch, not a timer: an unreadable zone is a
        -- value like any other, so a headless or pre-login world gets one line
        -- and then silence, rather than one per window forever.
        local zone = nil;
        if type(S.player) == 'table' and type(S.player.zone) == 'function' then
            zone = S.player.zone();
        end
        if (not _saidFood) or _saidFoodIn ~= zone then
            _saidFood, _saidFoodIn = true, zone;
            M._emit('Reward: ' .. tostring(S.pet.foodRefusal(pick)));   -- loud refusal
        end
        return { ok = false, reason = 'food' };
    end
    -- Carrying food again re-arms the line, so the next time you run out you
    -- hear about it wherever you are standing.
    _saidFood, _saidFoodIn = false, nil;

    local res = S.act.request(M.buildRequest(pick.name, M.setName()));
    if type(res) == 'table' and res.ok ~= true then
        if res.reason == 'busy' then
            M._emit(string.format('Reward is busy -- %s is running a sequence.',
                tostring(res.holderLabel or res.holder or 'another helper')));
        end
        return { ok = false, reason = res.reason or 'refused' };
    end
    return { ok = true };
end

-- ---------------------------------------------------------------------------
-- live state + the vitals subscription
-- ---------------------------------------------------------------------------

-- Assemble the decision state from the live world. Every read is contained by the
-- module API; an unreadable one leaves its key nil, and `decide` knows which way
-- each nil goes.
function M.liveState(at)
    local S = _S;
    local st = {
        armed         = M.armed(),
        threshold     = M.threshold(),
        lastAttemptAt = _lastAttemptAt,
        lockout       = M.LOCKOUT_S,
        now           = tonumber(at) or now(),
    };
    if type(S) ~= 'table' then return st; end

    -- The module-activity predicate (pill, main job, town, dead, zoning) -- the
    -- ONE gate every Job helper consults; never a second copy of those rules.
    local act = S.me.acting();
    if type(act) == 'table' then
        st.active = (act.active == true);
        st.reason = act.reason;
    end

    st.busy = S.act.busy();

    -- Unknown reads READY: the courtesy gate never manufactures a "down" it did
    -- not measure, and the sequencer's verify-worn is the real safety net.
    local ready = S.ability.ready(M.RECAST);
    st.recastReady = ready;

    return st;
end

-- One vitals beat -> one decision -> at most one sequence request. Returns the
-- decision so the Panel (and the tests) can see WHY nothing happened.
function M.onVitals(vitals, S)
    if type(S) == 'table' then _S = S; end
    -- The beat's own stamp is the clock the lockout is measured against, so the
    -- decision and the vitals it read describe the same moment. Plain if, never
    -- `(x) and vitals.at or nil` -- the documented ternary trap.
    local at = nil;
    if type(vitals) == 'table' then at = tonumber(vitals.at); end
    local st = M.liveState(at);
    local d  = M.decide(vitals, st);
    d.at  = st.now;
    _last = d;
    if d.act ~= true then return d; end
    -- The lockout arms on the ATTEMPT, before the act -- fired, refused or
    -- aborted, the next try waits out the window (AC2).
    _lastAttemptAt = st.now;
    M.request();
    return d;
end

-- Subscribe to the pet vitals beat. Called from the module's init hook; the key is
-- namespaced by the framework (jobhelper:<id>:reward), so a reload replaces rather
-- than doubles.
function M.init(S)
    if type(S) ~= 'table' then return false; end
    _S = S;
    local ok = false;
    pcall(function()
        ok = S.pet.subscribe('reward', function(v) M.onVitals(v); end);
    end);
    return ok;
end

function M.id()
    if type(_S) ~= 'table' then return nil; end
    return _S.id;
end

return M;
