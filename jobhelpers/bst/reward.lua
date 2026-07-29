--[[
    dlac/jobhelpers/bst/reward.lua -- the BST Helper's REWARD rule (issue #140,
    PRD #135 user stories 18-24). The module's second standing behavior, and the
    one that SPENDS AN ITEM.

    THE SAME PATH, TWO REQUESTERS. `M.request(id)` is the whole act: pick the
    food off the Ladder, overlay the optional Reward set, open ONE Action
    sequence, let it verify the food WORN and fire. The Panel's "Reward now"
    button calls it, and so does the automatic rule below -- there is exactly one
    implementation, so "identical refusal behavior to the button" is true by
    construction rather than by a second set of tests agreeing with the first.
    The button stays: it is the field-test lever.

    THE RULE. While the module is acting and the pet sits BELOW the player's
    pet-HP% threshold (default 50), the rule requests that same sequence. It is
    driven by the pet vitals service (feature\petvitals), which publishes
    presence / HP% / TP / name once per dispatch beat -- the module subscribes in
    its init hook, so the rule works with the Job Helpers tab closed.

    THE LOCKOUT is what keeps a sustained low-HP pet from becoming a stream of
    commands and chat lines. Every ATTEMPT arms it (fired, refused or aborted
    alike), and nothing is attempted again until the window elapses -- so a
    refusal costs at most one line per window, whatever the pet's bar does in
    between. Two states deliberately do NOT arm it, because nothing was
    attempted: a sequence already running (`busy`) and Reward still on cooldown
    (`recast`). Recast is also SILENT, which is exactly what the button does --
    it grays out and says nothing.

    House shape: `decide(vitals, state)` is PURE -- vitals + state in, decision
    out, no AshitaCore and no clock -- so the threshold, the lockout and every
    gate are headless checks (BRW*). `liveState` assembles that state from the
    module activity predicate, the config, the sequencer and the recast service;
    `onVitals` is the petvitals subscriber that joins the two.
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

-- The action command and the verify window (moved here from init.lua with the
-- rest of the act, so the button and the rule cannot drift apart). FLAGGED for
-- field verification: the exact target token on CatsEyeXI (<me> vs <pet>) is
-- confirmed in-game before this ships -- the sequencer's verify-worn gate
-- protects the GEAR either way, but a wrong token means the command no-ops.
M.COMMAND        = '/ja "Reward" <me>';
M.VERIFY_TIMEOUT = 4;

-- The module's folder name -- the loader assigns identity FROM the folder, so
-- this is only the fallback for the paths that run without a render ctx.
local DEFAULT_ID = 'bst';

local _id            = DEFAULT_ID;
local _last          = nil;    -- the last automatic decision (the Panel reports it)
local _lastAttemptAt = nil;    -- the lockout clock: when the rule last ATTEMPTED

-- ---------------------------------------------------------------------------
-- helpers (all contained -- a missing service degrades, never throws)
-- ---------------------------------------------------------------------------

local function req(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- One loud line. Refusals are LOUD (hard rule 12): a silently skipped Reward is
-- indistinguishable from a broken one.
M._emit = function(line)
    local done = false;
    local cf = req('dlac\\chatfmt');
    if cf ~= nil and type(cf.err) == 'function' then pcall(cf.err, line); done = true; end
    if not done then pcall(function() print('[dlac] ' .. tostring(line)); end); end
end;

-- The same monotonic clock the sequencer uses (cmdqueue frames -> seconds,
-- falling back to os.clock). Injectable for tests.
M._now = function()
    local t = nil;
    pcall(function()
        local cq = require('dlac\\lib\\cmdqueue');
        if type(cq) == 'table' and type(cq.frame) == 'function' then t = cq.frame() / 60.0; end
    end);
    if type(t) ~= 'number' then pcall(function() t = os.clock(); end); end
    return tonumber(t) or 0;
end;

local function cfg() return req('dlac\\jobhelpers\\bst\\config'); end

-- ---------------------------------------------------------------------------
-- the settings (persisted in the module's OWN per-character config file)
-- ---------------------------------------------------------------------------

-- Is the automatic rule armed? Default OFF, and for the reason the Fight switch
-- is: this module ISSUES COMMANDS and this rule additionally CONSUMES AN ITEM,
-- so a freshly installed helper must never start spending a player's food on its
-- own. The player arms it; the row pill only ever silences.
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

-- Clamp a threshold to the usable band. An unreadable / absent value reads as
-- the default rather than as "never" -- the rule switch is the off switch.
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
-- percent it crosses rather than one per frame: the config store writes on
-- mutation only, and every frame of a drag inside the same percent rounds to the
-- value already stored.
function M.setThreshold(v)
    local c = cfg();
    if c == nil then return false; end
    return c.set('rewardThreshold', M.clampThreshold(v));
end

-- The optional Reward set, by name, or nil for "food only". Persisted because
-- the AUTOMATIC path has no Panel to read a session-only choice from: a set
-- picked once must still be worn by a Reward fired an hour later with the tab
-- closed. Stored as '' for none, so clearing it is an ordinary string write.
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
-- vitals = feature\petvitals record: { present, hpp, tp, name }
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
--   * `active` must be POSITIVELY true. An unreadable world (headless,
--     pre-login, a job read that has not settled) is not permission to spend a
--     player's food -- the #139 rule, and it binds harder here because this act
--     consumes an item.
--   * `vitals.present` must be POSITIVELY true, and an unreadable HP% refuses.
--     Guessing a pet's HP is how a Reward gets fired at a healthy pet.
--   * `recastReady` blocks only on FALSE. Unknown reads READY, matching the
--     recast service's courtesy gate and the button's gray-out exactly.
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

    -- The lockout: one attempt per window, so a sustained sub-threshold pet
    -- costs at most one command and one refusal line per window (AC2). A clock
    -- that went BACKWARDS accepts rather than muting for a whole window (the
    -- engagewatch debounce rule).
    local now     = tonumber(state.now) or 0;
    local lockout = tonumber(state.lockout) or M.LOCKOUT_S;
    local last    = tonumber(state.lastAttemptAt);
    if last ~= nil then
        local since = now - last;
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

-- A short human line for a decision -- the Panel's report. Deliberately NOT
-- chat: the rule evaluates every dispatch beat, and only an ATTEMPT is news.
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

-- Forget the lockout (job change / logout / test reset).
function M.resetLockout() _lastAttemptAt = nil; _last = nil; end

function M.lockedUntil()
    if _lastAttemptAt == nil then return nil; end
    return _lastAttemptAt + M.LOCKOUT_S;
end

-- ---------------------------------------------------------------------------
-- the ACT -- one path, two requesters (the button and the rule)
-- ---------------------------------------------------------------------------

-- The player's current main job, or nil.
local function playerJob()
    local j = nil;
    pcall(function() j = gData.GetPlayer().MainJob; end);
    if type(j) ~= 'string' or j == '' or j == '?' then return nil; end
    return j;
end

-- This module's priority among the current job's section (the tab's section
-- order). Higher wins a simultaneous contention (actionseq.arbitrateRequests);
-- top-of-section is highest, so order = (count - index + 1). Defaults to 1.
function M.sectionOrder(id)
    local order = 1;
    pcall(function()
        local jh = req('dlac\\feature\\jobhelpers');
        local job = playerJob();
        if jh == nil or job == nil then return; end
        local ids = jh.idsForJob(job);
        for i, n in ipairs(ids) do
            if n == id then order = (#ids - i + 1); return; end
        end
    end);
    return order;
end

-- The named Reward sets available to pick from -- the job entry's static Sets
-- (Idle, Reward, ...). Never the Dynamic build sets.
function M.setNames()
    local out = {};
    pcall(function()
        local ps = req('dlac\\gear\\profilesets');
        if ps == nil or type(ps.staticSetNames) ~= 'function' then return; end
        out = ps.staticSetNames() or {};
    end);
    return out;
end

-- Pull a slot -> item-name map from a named set (best-effort: strings and the
-- common wrapper shapes). Missing / unreadable -> empty (food-only claim).
function M.setSlots(name)
    local slots = {};
    if type(name) ~= 'string' or name == '' or name == 'None' then return slots; end
    pcall(function()
        local ps = req('dlac\\gear\\profilesets');
        if ps == nil or type(ps.getSetsRoot) ~= 'function' then return; end
        local root = ps.getSetsRoot();
        local set = (type(root) == 'table') and root[name] or nil;
        if type(set) ~= 'table' then return; end
        for slot, v in pairs(set) do
            local item = nil;
            if type(v) == 'string' then item = v;
            elseif type(v) == 'table' then item = v.Name or v.name or v.item; end
            if type(item) == 'string' and item ~= '' then slots[slot] = item; end
        end
    end);
    return slots;
end

-- Build the Action sequence request: the optional Reward set overlaid, then the
-- chosen food forced into Ammo (food always wins the ammo slot -- the union the
-- PRD names).
--
-- `need` is the CONSUMED slot ALONE, and that is an ACCEPTED design ruling
-- (maintainer, at the #138 merge), not an oversight: Reward eats what is worn in
-- Ammo, so the food is the precondition and must verify; the Reward set dresses
-- BEST-EFFORT, so a senior claimant holding one of its slots costs that slot and
-- refuses nothing. It also composes with a player's own Reward-gear Trigger --
-- leave the set picker empty, claim the food only, and the trigger dresses the
-- rest at precast.
function M.buildRequest(id, foodName, setName)
    local claim = M.setSlots(setName);
    claim.Ammo = foodName;                  -- food ∪ set; food owns Ammo
    return {
        module  = id,
        label   = 'Reward',
        order   = M.sectionOrder(id),
        claim   = claim,
        need    = { Ammo = foodName },      -- the one slot that MUST verify worn
        command = M.COMMAND,
        timeout = M.VERIFY_TIMEOUT,
    };
end

-- THE ACT. Pick the food, refuse loudly if there is none, else open the
-- sequence. Returns { ok = <bool>, reason = <slug|nil> }; never throws.
--
-- Both requesters land here, so the refusal behavior the button shows IS the
-- refusal behavior the rule shows -- no food carried, a senior claimant holding
-- the Ammo slot (the sequencer's own loud refusal / verify-timeout abort), a
-- service that failed to load. The one difference is deliberate: the rule's
-- CALLER arms the lockout first, so those lines cost one per window.
function M.request(id)
    id = (type(id) == 'string' and id ~= '') and id or _id;
    local petfood   = req('dlac\\feature\\petfood');
    local actionseq = req('dlac\\feature\\actionseq');
    if petfood == nil or actionseq == nil then
        M._emit('Reward unavailable: a required service failed to load.');
        return { ok = false, reason = 'service' };
    end
    local pick = petfood.choose();
    if not pick.ok then
        M._emit('Reward: ' .. petfood.refusalLine(pick));       -- loud refusal
        return { ok = false, reason = 'food' };
    end
    local res = actionseq.request(M.buildRequest(id, pick.name, M.setName()));
    if type(res) == 'table' and res.ok ~= true then
        if res.reason == 'busy' then
            M._emit(string.format('Reward is busy -- %s is running a sequence.',
                tostring(res.holderLabel or res.holder or 'another helper')));
        end
        return { ok = false, reason = res.reason or 'refused' };
    end
    -- Kick one Default so the claim applies now rather than on the next 0.4s
    -- tick (the same explicit re-dispatch a mode flip does). The pump then reads
    -- the worn food and fires. Contained: the tick is the fallback.
    pcall(function()
        local dsp = req('dlac\\dispatch');
        if dsp ~= nil and type(dsp.kickDefault) == 'function' then dsp.kickDefault(); end
    end);
    return { ok = true };
end

-- ---------------------------------------------------------------------------
-- live state + the petvitals subscription
-- ---------------------------------------------------------------------------

-- Assemble the decision state from the live world. Every read is contained; an
-- unreadable one leaves its key nil, and `decide` knows which way each nil goes.
function M.liveState(id, now)
    local st = {
        armed         = M.armed(),
        threshold     = M.threshold(),
        lastAttemptAt = _lastAttemptAt,
        lockout       = M.LOCKOUT_S,
        now           = tonumber(now) or M._now(),
    };

    -- The module-activity predicate (pill, main job, town, dead, zoning) -- the
    -- ONE gate every Job helper consults; never a second copy of those rules.
    pcall(function()
        local jh = require('dlac\\feature\\jobhelpers');
        if type(jh) ~= 'table' or type(jh.activity) ~= 'function' then return; end
        local act = jh.activity(id or _id);
        if type(act) ~= 'table' then return; end
        st.active = (act.active == true);
        st.reason = act.reason;
    end);

    pcall(function()
        local as = require('dlac\\feature\\actionseq');
        if type(as) == 'table' and type(as.active) == 'function' then st.busy = as.active(); end
    end);

    pcall(function()
        local rc = require('dlac\\feature\\recast');
        if type(rc) ~= 'table' or type(rc.rewardReady) ~= 'function' then return; end
        local ready = rc.rewardReady();
        st.recastReady = ready;
    end);

    return st;
end

-- One vitals beat -> one decision -> at most one sequence request. Returns the
-- decision so the Panel (and the tests) can see WHY nothing happened. Never
-- throws: petvitals pcalls its subscribers, but a Panel reading _last must never
-- find a half-built record either.
function M.onVitals(vitals, id)
    -- The beat's own stamp is the clock the lockout is measured against, so the
    -- decision and the vitals it read describe the same moment. Plain if, never
    -- `(x) and vitals.at or nil` -- the documented ternary trap.
    local at = nil;
    if type(vitals) == 'table' then at = tonumber(vitals.at); end
    local st = M.liveState(id, at);
    local d  = M.decide(vitals, st);
    d.at  = st.now;
    _last = d;
    if d.act ~= true then return d; end
    -- The lockout arms on the ATTEMPT, before the act -- fired, refused or
    -- aborted, the next try waits out the window (AC2).
    _lastAttemptAt = st.now;
    M.request(id or _id);
    return d;
end

-- Subscribe to the pet vitals service. Called from the module's init hook;
-- idempotent (petvitals keys subscriptions by name, so a reload replaces rather
-- than doubles).
function M.init(id)
    if type(id) == 'string' and id ~= '' then _id = id; end
    local ok = false;
    pcall(function()
        local pv = require('dlac\\feature\\petvitals');
        if type(pv) ~= 'table' or type(pv.subscribe) ~= 'function' then return; end
        ok = pv.subscribe('jobhelper:' .. _id .. ':reward', function(v) M.onVitals(v); end);
    end);
    return ok;
end

function M.id() return _id; end

return M;
