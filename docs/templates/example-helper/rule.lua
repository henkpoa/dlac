--[[
    example-helper/rule.lua -- ONE standing behavior, in the house shape.

    The shape is worth copying even when your rule is nothing like this one, because
    it is what makes a rule testable and reviewable:

        decide(signal, state)   PURE. Signal + state in, decision out. No services,
                                no clock, no world. Every acceptance criterion of
                                your rule is one check against a synthetic state.
        liveState()             Assembles that state from the module API. All the
                                contained reads live here and nowhere else.
        onBeat(signal)          Joins the two: one signal -> one decision -> at most
                                one act.
        init(S)                 Subscribes. Called from your init.lua hook.

    Keeping `decide` pure is the whole trick. It means every rule below -- "an
    unreadable world is not permission", "one attempt per window", "busy is a hold,
    not a failure" -- is provable in a test that runs in milliseconds with no game.
]]--

local M = {};

-- The retry lockout: after any ATTEMPT -- fired, refused or aborted alike -- the
-- rule holds for this long before it may try again.
--
-- It is not politeness, it is necessary. A rule reads a STATE, and a state
-- persists: you are still engaged on the next beat, so without a budget one
-- condition becomes a stream of commands and a stream of chat lines. (guide 7.2)
M.LOCKOUT_S = 60;

-- CHANGE ME: what you do, and the ability whose cooldown gates it.
M.COMMAND = '/ja "Divine Seal" <me>';
M.ABILITY = 'Divine Seal';

-- The module API, handed over by init. Everything -- the clock, the settings, the
-- activity gate, the command door -- arrives through it.
local _S = nil;

local _last          = nil;    -- the last decision, for the Panel
local _lastAttemptAt = nil;    -- the lockout clock

-- ---------------------------------------------------------------------------
-- settings
-- ---------------------------------------------------------------------------
--
-- Read through S.cfg, which serves your declared DEFAULT when there is no file yet
-- and pre-login -- so you never branch on "not logged in". A write pre-login
-- returns false rather than being cached, and is retried the next time.

function M.armed()
    if type(_S) ~= 'table' or _S.cfg == nil then return false; end
    return _S.cfg.get('armed') == true;
end

function M.setArmed(on)
    if type(_S) ~= 'table' or _S.cfg == nil then return false; end
    return _S.cfg.set('armed', on == true);
end

function M.lockout()
    if type(_S) ~= 'table' or _S.cfg == nil then return M.LOCKOUT_S; end
    return tonumber(_S.cfg.get('lockout')) or M.LOCKOUT_S;
end

-- ---------------------------------------------------------------------------
-- the PURE decision
-- ---------------------------------------------------------------------------
--
-- combat = the combat beat: { engaged, targetIndex, targetName, targetChanged, swung }
-- state  = { armed, active, reason, busy, ready, firedThisFight,
--            lastAttemptAt, lockout, now }
-- returns { act = <bool>, reason = <slug|nil> }
--
-- POSITIVE-TRUE on every act gate. `state.active ~= true` and `combat.engaged ~=
-- true` both hold -- note that this is NOT the same as checking for false: an
-- unreadable world answers nil, and a read you could not make is never permission
-- to issue a command. Getting this backwards is the single most common way a helper
-- misbehaves, so the codebase writes it this way every time. (guide 6.6)
--
-- The GATE ORDER is the REPORTING order: the Panel shows whichever check held
-- first, so the most specific true statement wins.
function M.decide(combat, state)
    state  = (type(state) == 'table') and state or {};
    combat = (type(combat) == 'table') and combat or {};

    if state.armed  ~= true then return { act = false, reason = 'off' }; end
    if state.active ~= true then
        return { act = false, reason = state.reason or 'inactive' };
    end
    if combat.engaged ~= true then return { act = false, reason = 'not-engaged' }; end
    if state.firedThisFight == true then return { act = false, reason = 'done' }; end

    -- The lockout. A clock that went BACKWARDS accepts rather than muting for a
    -- whole window -- os.clock can reset, and a rule that goes silent for a minute
    -- because of it is worse than one that acts once more than it meant to.
    local now  = tonumber(state.now) or 0;
    local win  = tonumber(state.lockout) or M.LOCKOUT_S;
    local last = tonumber(state.lastAttemptAt);
    if last ~= nil then
        local since = now - last;
        if since >= 0 and since < win then
            return { act = false, reason = 'lockout', retryIn = win - since };
        end
    end

    -- NOTHING BELOW HERE ATTEMPTS ANYTHING, so neither of these arms the lockout --
    -- they are holds, and a hold that tried nothing must not spend the budget.
    -- `busy` means another module is mid-act; that is the correct outcome, not a
    -- failure. `ready == false` is a measured cooldown; unknown reads READY.
    if state.busy  == true  then return { act = false, reason = 'busy' }; end
    if state.ready == false then return { act = false, reason = 'cooldown' }; end

    return { act = true };
end

-- The Panel's dim "Last:" line. One short sentence per reason, in the player's
-- words -- never a slug, and never a stack trace.
local TEXT = {
    ['off']         = 'the rule is off',
    ['inactive']    = 'the helper is not acting',
    ['job']         = 'not on the right job',
    ['town']        = 'in town',
    ['dead']        = 'dead',
    ['zoning']      = 'zoning',
    ['not-engaged'] = 'you are not engaged',
    ['done']        = 'already used this fight',
    ['busy']        = 'another helper is mid-act',
    ['cooldown']    = 'the ability is still on cooldown',
};

function M.decisionText(d)
    if type(d) ~= 'table' then return 'nothing yet'; end
    if d.act == true then return 'used it'; end
    if d.reason == 'lockout' then
        return string.format('waiting out the lockout (%ds)',
            math.max(0, math.floor((tonumber(d.retryIn) or 0) + 0.5)));
    end
    return TEXT[d.reason] or tostring(d.reason or 'held');
end

function M.lastDecision() return _last; end

-- What the Panel prints, or nil before the first beat.
function M.lastLine()
    if _last == nil then return nil; end
    return M.decisionText(_last);
end

function M.reset() _last, _lastAttemptAt = nil, nil; end

-- ---------------------------------------------------------------------------
-- live state + the beat
-- ---------------------------------------------------------------------------

local _firedThisFight = false;

-- Every read is one call on the module API, and each one is already contained --
-- an unavailable service leaves its key nil, and `decide` knows which way each nil
-- goes. This is the only function in the file that touches the world.
function M.liveState(at)
    local S = _S;
    local st = {
        armed         = M.armed(),
        lockout       = M.lockout(),
        lastAttemptAt = _lastAttemptAt,
        firedThisFight = _firedThisFight,
        now           = 0,
    };
    if type(S) ~= 'table' then return st; end
    st.now = tonumber(at) or S.now();

    local act = S.me.acting();          -- { active, reason, label }
    if type(act) == 'table' then
        st.active = (act.active == true);
        st.reason = act.reason;
    end
    st.busy  = S.act.busy();
    st.ready = S.ability.ready(M.ABILITY);
    return st;
end

-- One combat beat -> one decision -> at most one command.
function M.onBeat(combat)
    local at = nil;
    if type(combat) == 'table' then at = tonumber(combat.at); end

    -- Disengaging clears the once-per-fight latch. Doing this from the beat, rather
    -- than from a separate "fight ended" signal, is why the latch cannot get stuck.
    if type(combat) == 'table' and combat.engaged ~= true then _firedThisFight = false; end

    local st = M.liveState(at);
    local d  = M.decide(combat, st);
    d.at  = st.now;
    _last = d;
    if d.act ~= true then return d; end

    -- The lockout arms on the ATTEMPT, before the act -- fired or refused, the next
    -- try waits out the window.
    _lastAttemptAt   = st.now;
    _firedThisFight  = true;

    -- A command that needs nothing WORN goes through the command door. If your act
    -- needs gear or ammo on first -- food eaten from the Ammo slot, a jug read for
    -- its species -- use S.act.request instead and let the sequencer verify it
    -- landed before anything fires. Never equip anything yourself. (guide 6.1, 7.1)
    _S.cmd(M.COMMAND);
    return d;
end

-- Subscribe. The key you pass is namespaced by the framework
-- (jobhelper:<your-id>:beat), so a reload replaces rather than doubles and two
-- modules can never collide on it.
--
-- Pick the signal your rule actually asks about: a rule that reads a STATE ("am I
-- engaged", "is my pet hurt") wants a beat; a rule that reacts to a MOMENT wants
-- S.combat.onEdge. (guide 6.2, 6.3)
function M.init(S)
    if type(S) ~= 'table' then return false; end
    _S = S;
    local ok = false;
    pcall(function()
        ok = S.combat.subscribe('beat', function(c) M.onBeat(c); end);
    end);
    return ok;
end

return M;
