--[[
    dlac/jobhelpers/bst/bst-helper/resummon.lua -- the BST Helper's RESUMMON rule.
    The module's third standing behavior, and the one that spends the most
    expensive item it will ever touch.

    DEATH ONLY, AND DEATH IS CONFIRMED. The rule reads ONE signal: the pet vitals
    service's classified pet-loss edge (S.pet.onLoss -- subscribed in the module's
    init hook, so it works with the Job Helpers tab closed). Everything the
    classifier could not PROVE was a death is nothing to this rule: a Leave, a zone
    line, a logout and an unexplained vanish all land in the same place, which is
    silence. And of the deaths, only a JUG pet's counts -- a charmed pet's death,
    like charm loss, triggers nothing at all, because charm play stays fully manual.
    Jug-vs-charm is decided by NAME, through the module's own jug roster (jugs.lua)
    handed to the service as its name authority: the service owns the RULE, the
    module owns the LIST.

    THE ACT is an Action sequence, exactly like Reward's: claim the configured jug
    into Ammo, verify it WORN, fire the summon, release. Both methods need the jug
    worn -- the server reads the ammo slot for the species -- which is the whole
    reason a sequence is involved and not a bare command.

    THE BINARY CHOICE. Call Beast or Bestial Loyalty, plus "use the other if mine is
    on cooldown" (default on). Only Call Beast earns Beast Raising bonuses; it
    CONSUMES the jug, Loyalty does not. Nothing here reads a "better" method: the
    player's pick is the intent, and the checkbox only decides what happens when
    that pick is down.

    THE QUEUE. When the method(s) the checkbox allows are all on recast, the
    resummon does not die -- it QUEUES, and fires the moment one readies. It is
    cancelled by zoning, an observed Leave, logging out, a pet appearing any other
    way, and by disarming the rule. It is deliberately NOT cancelled by time:
    Bestial Loyalty's recast is measured in minutes, and a queue that expired before
    the ability it is waiting for would be a queue that never worked.

    House shape: `decideLoss(edge, state)` and `queueDecide(state)` are PURE -- edge
    + state in, decision out, no services and no clock -- so every rule above is a
    headless check (BRS*). `liveState` assembles that state from the module API;
    `onLoss` / `onVitals` are the subscribers that join them.
]]--

local M = {};

-- The two methods, in switch order. `call` first: it is the default, and it is the
-- one that earns the raising bonuses.
M.METHODS = { 'call', 'loyalty' };

-- Player-facing labels: the ABILITY names, because that is what the player reads
-- on their own menu and what the refusal lines have to name (naming law -- the
-- helper names the rule, the act names the ability). PROPOSED.
M.METHOD_LABEL = {
    call    = 'Call Beast',
    loyalty = 'Bestial Loyalty',
};

-- The action commands. FLAGGED for field verification alongside Reward's: the
-- exact target token on CatsEyeXI (<me> vs none) is confirmed in-game before this
-- ships. The sequencer's verify-worn gate protects the JUG either way -- a wrong
-- token means the command no-ops, never that gear moves wrongly.
M.METHOD_COMMAND = {
    call    = '/ja "Call Beast" <me>',
    loyalty = '/ja "Bestial Loyalty" <me>',
};

-- The recast signatures, as MODULE data (facts about this job's abilities).
-- Neither carries a hardcoded timer id, and that is deliberate: the Pup-Helper
-- reference only ever named Reward's, and hard rule 9 puts LIVE GAME MEMORY above
-- every other source -- so these resolve their recast slot by NAME through the
-- client's own ability resource, and a resolution that fails answers UNKNOWN,
-- which reads READY. The courtesy gate never manufactures a "down" it did not
-- measure; the sequencer's verify-worn is the real safety net, and a command the
-- client rejects costs nothing (Bestial Loyalty does not even consume the jug).
M.RECAST = {
    call    = { name = 'Call Beast',      label = 'Call Beast' },
    loyalty = { name = 'Bestial Loyalty', label = 'Bestial Loyalty' },
};

M.VERIFY_TIMEOUT = 4;

-- The module API table, handed over by init.
local _S = nil;

local _last   = nil;    -- the last decision (the Panel reports it)
local _queued = nil;    -- { jug, method, fallback, at } while a resummon waits

local function cfg()
    if type(_S) ~= 'table' then return nil; end
    return _S.cfg;
end

local function now()
    if type(_S) == 'table' and type(_S.now) == 'function' then return _S.now(); end
    return 0;
end

local function jugsMod()
    if type(_S) ~= 'table' or type(_S.sibling) ~= 'function' then return nil; end
    return _S.sibling('jugs');
end

-- One loud line. Refusals are LOUD (hard rule 12): a resummon that silently did
-- not happen is indistinguishable from a broken one, and this is the rule a player
-- is least able to check for themselves -- they are dead or busy. Kept as an
-- overridable seam so the suite can read the lines it produced.
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

-- Is the rule armed? Default OFF, for the reason Fight and Reward are: this act
-- issues a command AND (via Call Beast) consumes an item, so a freshly dropped-in
-- helper never starts spending a player's jugs on its own.
function M.armed()
    local c = cfg();
    local v = nil;
    if c ~= nil then v = c.get('resummonArmed'); end
    return v == true;
end

function M.setArmed(on)
    -- Disarming drops a pending resummon on the spot: the switch that silences a
    -- helper must silence the act it already decided to make. UNCONDITIONALLY and
    -- FIRST -- a store that could not be reached (pre-login, a torn file) must not
    -- be the reason a queued jug spend survives the off switch.
    if on ~= true then M.clearQueue(); end
    local c = cfg();
    if c == nil then return false; end
    return c.set('resummonArmed', on == true);
end

-- The configured jug, by item name, or nil for "none picked". Nil is a REFUSAL
-- case, never a default: nothing here picks a jug for the player.
function M.jug()
    local c = cfg();
    local v = nil;
    if c ~= nil then v = c.get('resummonJug'); end
    if type(v) ~= 'string' or v == '' or v == 'None' then return nil; end
    return v;
end

function M.setJug(name)
    local c = cfg();
    if c == nil then return false; end
    if type(name) ~= 'string' or name == 'None' then name = ''; end
    return c.set('resummonJug', name);
end

function M.isMethod(m)
    for _, v in ipairs(M.METHODS) do
        if v == m then return true; end
    end
    return false;
end

-- The chosen method. An unreadable / absent store reads 'call' -- the default that
-- earns the raising bonuses, and the one every BST has.
function M.method()
    local c = cfg();
    local m = nil;
    if c ~= nil then m = c.get('resummonMethod'); end
    if not M.isMethod(m) then return 'call'; end
    return m;
end

function M.setMethod(m)
    if not M.isMethod(m) then return false; end
    local c = cfg();
    if c == nil then return false; end
    return c.set('resummonMethod', m);
end

-- "Use the other if mine is on cooldown". Default ON; an unreadable store reads
-- ON, because this flag can only ever change WHICH ready ability is used, never
-- whether one is.
function M.fallback()
    local c = cfg();
    local v = nil;
    if c ~= nil then v = c.get('resummonFallback'); end
    if v == nil then return true; end
    return v == true;
end

function M.setFallback(on)
    local c = cfg();
    if c == nil then return false; end
    return c.set('resummonFallback', on == true);
end

-- ---------------------------------------------------------------------------
-- method resolution -- PURE, and shared by the loss decision and the queue tick
-- ---------------------------------------------------------------------------
--
-- Which method may fire right now? `chosen` is the player's pick, `fallback` the
-- checkbox, and readiness is TRUE / FALSE / nil where nil means "could not
-- measure" -- and unknown reads READY, matching the recast service's courtesy gate
-- exactly (it never manufactures a "down" it did not see).
--
-- Returns the method to use, or nil when everything allowed is down.
function M.pickMethod(chosen, fallback, callReady, loyaltyReady)
    if not M.isMethod(chosen) then chosen = 'call'; end
    local ready = { call = (callReady ~= false), loyalty = (loyaltyReady ~= false) };
    if ready[chosen] then return chosen; end
    if fallback ~= true then return nil; end          -- checkbox off: the pick or nothing
    local other = (chosen == 'call') and 'loyalty' or 'call';
    if ready[other] then return other; end
    return nil;
end

-- ---------------------------------------------------------------------------
-- the PURE decision -- a loss edge + state in, "summon?" out
-- ---------------------------------------------------------------------------
--
-- edge  = the pet-loss edge { lost, kind, confirmed, pet, name, hpp }
-- state = {
--   armed        = <bool>,          -- the rule switch
--   active       = <bool>,          -- the module-activity predicate said "acting"
--   reason       = <'off'|'job'|'town'|'dead'|'zoning'|nil>,   -- why it is not
--   jug          = <item name|nil>, -- the configured jug
--   method       = 'call'|'loyalty',
--   fallback     = <bool>,
--   stock        = <number|nil>,    -- how many of that jug are in the bags
--   callReady    = <true|false|nil>,     -- false ONLY when measured DOWN
--   loyaltyReady = <true|false|nil>,
--   busy         = <bool>,          -- a sequence is already live
--   now          = <number>,
-- }
-- returns { act, method, queue, reason, jug, loud }
--
-- The gate order IS the reporting order, and it is a funnel from "should I care at
-- all" down to "can I do it". `loud` marks the two reasons that earn a chat line --
-- no jug configured, and none in the bags -- because those are the only ones where
-- the player has to DO something.
--
-- Positive-true discipline throughout: `armed`, `active`, `edge.confirmed` and
-- `pet == 'jug'` must all be affirmatively true. An unreadable world is never
-- permission to spend a jug.
function M.decideLoss(edge, state)
    state = (type(state) == 'table') and state or {};
    local e = (type(edge) == 'table') and edge or {};

    if state.armed ~= true then return { act = false, reason = 'off' }; end
    if state.active ~= true then
        return { act = false, reason = state.reason or 'inactive' };
    end

    -- 1. Was anything lost, and was it a DEATH we can prove?
    if e.lost ~= true then return { act = false, reason = 'no-loss' }; end
    if e.kind ~= 'death' then
        -- 'leave' / 'zone' / 'logout' / 'unknown' -- each its own honest reason.
        return { act = false, reason = e.kind or 'unknown' };
    end
    if e.confirmed ~= true then return { act = false, reason = 'unconfirmed' }; end

    -- 2. Was it MY JUG PET? A charmed pet's death is charm play, and charm play is
    --    entirely the player's.
    if e.pet ~= 'jug' then
        return { act = false, reason = (e.pet == 'charm') and 'charm' or 'not-jug' };
    end

    -- 3. Can it be paid for? Both of these are LOUD: they name something the
    --    player has to fix, and a silent skip here reads as a broken helper.
    local jug = state.jug;
    if type(jug) ~= 'string' or jug == '' then
        return { act = false, reason = 'no-jug', loud = true };
    end
    local stock = tonumber(state.stock);
    if stock == nil or stock <= 0 then
        return { act = false, reason = 'no-stock', loud = true, jug = jug };
    end

    -- 4. Is the sequencer free? A live sequence is never preempted, and this one
    --    can wait -- so it QUEUES rather than being dropped.
    if state.busy == true then
        return { act = false, queue = true, reason = 'busy', jug = jug };
    end

    -- 5. Which ability? Nothing allowed and ready means QUEUE, not refuse.
    local m = M.pickMethod(state.method, state.fallback, state.callReady, state.loyaltyReady);
    if m == nil then
        return { act = false, queue = true, reason = 'recast', jug = jug };
    end
    return { act = true, method = m, jug = jug };
end

-- ---------------------------------------------------------------------------
-- the PURE queue tick -- "fire it yet, or drop it?"
-- ---------------------------------------------------------------------------
--
-- state adds, on top of decideLoss's:
--   queued     = { jug, method, fallback } | nil
--   petPresent = <true|false|nil>   -- a pet is out again, by ANY route
--   zoning / logout / leave = <true|false|nil>   -- the observed cancels
--
-- returns { fire, method, cancel = <reason|nil>, reason, jug, loud }
--
-- CANCELS FIRST, and they are absolute: a pet that appeared any other way (you
-- summoned by hand, someone charmed you one, a raise landed it), zoning, an
-- observed Leave, logging out, and the rule being switched off. Only then the
-- holds -- inactive, busy, still on recast -- which simply wait.
function M.queueDecide(state)
    state = (type(state) == 'table') and state or {};
    local q = (type(state.queued) == 'table') and state.queued or nil;
    if q == nil then return { fire = false, reason = 'none' }; end

    if state.petPresent == true then return { fire = false, cancel = 'pet-appeared' }; end
    if state.zoning     == true then return { fire = false, cancel = 'zone' }; end
    if state.logout     == true then return { fire = false, cancel = 'logout' }; end
    if state.leave      == true then return { fire = false, cancel = 'leave' }; end
    if state.armed      ~= true then return { fire = false, cancel = 'off' }; end

    -- The JUG is read LIVE, not off the queue record: a player who changes the
    -- picker while a resummon waits has changed their mind, and the act itself
    -- re-reads the setting too -- so deciding on a remembered jug would be deciding
    -- on one thing and spending another. The queue remembers the INTENT (the method
    -- pick and its checkbox); the jug is a setting.
    --
    -- It can also go away entirely while the queue waits (traded, or spent by the
    -- player's own macro). Out of jug at fire time is the same loud refusal it is
    -- at death time -- and it CANCELS, because a queue waiting on stock is waiting
    -- on nothing this rule can see change.
    local jug = state.jug;
    local stock = tonumber(state.stock);
    if type(jug) ~= 'string' or jug == '' then
        return { fire = false, cancel = 'no-jug', loud = true };
    end
    if stock == nil or stock <= 0 then
        return { fire = false, cancel = 'no-stock', loud = true, jug = jug };
    end

    if state.active ~= true then
        return { fire = false, reason = state.reason or 'inactive', jug = jug };
    end
    if state.busy == true then return { fire = false, reason = 'busy', jug = jug }; end

    local m = M.pickMethod(q.method, q.fallback, state.callReady, state.loyaltyReady);
    if m == nil then return { fire = false, reason = 'recast', jug = jug }; end
    return { fire = true, method = m, jug = jug };
end

-- ---------------------------------------------------------------------------
-- reporting (the Panel's line -- never chat, except the two loud refusals)
-- ---------------------------------------------------------------------------

local DECISION_TEXT = {
    ['off']         = 'the Resummon rule is off',
    ['inactive']    = 'the helper is not acting',
    ['job']         = 'not on main-job BST',
    ['town']        = 'in town',
    ['dead']        = 'dead',
    ['zoning']      = 'zoning',
    ['no-loss']     = 'your pet is still with you',
    ['leave']       = 'you dismissed your pet -- nothing to resummon',
    ['zone']        = 'your pet was left behind by zoning',
    ['logout']      = 'your pet went away with a logout',
    ['unknown']     = 'your pet went away and nothing confirmed a death',
    ['unconfirmed'] = 'nothing confirmed a death',
    ['charm']       = 'that was a charmed pet -- charm stays yours',
    ['not-jug']     = 'that pet was not a jug pet',
    ['no-jug']      = 'no jug is picked',
    ['no-stock']    = 'you are out of that jug',
    ['busy']        = 'another sequence is running',
    ['recast']      = 'both summons are on cooldown',
    ['pet-appeared'] = 'a pet came out another way',
    ['none']        = 'nothing queued',
};

function M.decisionText(d)
    if type(d) ~= 'table' then return 'nothing yet'; end
    if d.act == true or d.fire == true then
        return string.format('summoned with %s', tostring(M.METHOD_LABEL[d.method] or d.method));
    end
    if d.cancel ~= nil then
        return string.format('the queued resummon was cancelled -- %s',
            DECISION_TEXT[d.cancel] or tostring(d.cancel));
    end
    if d.queue == true then
        return string.format('queued -- %s', DECISION_TEXT[d.reason] or tostring(d.reason));
    end
    return DECISION_TEXT[d.reason] or tostring(d.reason or 'held');
end

-- The LOUD line for a refusal that names something the player must fix. Pure; the
-- caller emits it.
function M.refusalLine(d)
    if type(d) ~= 'table' then return 'Resummon refused.'; end
    local why = d.reason or d.cancel;
    if why == 'no-jug' then
        return 'Resummon: no jug is picked -- choose one in the BST Helper panel.';
    end
    if why == 'no-stock' then
        return string.format('Resummon: you are out of %s -- both Call Beast and Bestial Loyalty need one equipped.',
            tostring(d.jug or 'that jug'));
    end
    return 'Resummon refused: ' .. tostring(M.decisionText(d)) .. '.';
end

function M.lastDecision() return _last; end

function M.queued() return _queued; end

function M.clearQueue() _queued = nil; end

-- Forget everything session-shaped (job change / logout / test reset).
function M.reset()
    _queued, _last = nil, nil;
end

-- ---------------------------------------------------------------------------
-- the ACT -- one Action sequence, the jug worn before the ability fires
-- ---------------------------------------------------------------------------

-- Build the Action sequence request. The claim is the jug ALONE, and the same slot
-- is what must verify WORN: both methods read the ammo slot for the species, so
-- the jug is the act's PRECONDITION, not its costume. No optional set rides along
-- -- a summon has no "summon+" gear to wear, and every extra claimed slot is one
-- more chance for a senior claimant to refuse the whole sequence.
--
-- `module` and `order` are filled in by the module API from the module's own
-- identity.
function M.buildRequest(jugName, method)
    if not M.isMethod(method) then method = 'call'; end
    return {
        label   = M.METHOD_LABEL[method],
        claim   = { Ammo = jugName },
        need    = { Ammo = jugName },
        command = M.METHOD_COMMAND[method],
        timeout = M.VERIFY_TIMEOUT,
    };
end

-- THE ACT. Open the sequence for `method` with the configured jug. Returns
-- { ok = <bool>, reason = <slug|nil> }; never throws. Every refusal the sequencer
-- itself raises (a senior claimant on Ammo, a verify timeout) is its own loud line
-- -- this one only speaks for what it can see first.
function M.request(method)
    local S = _S;
    if type(S) ~= 'table' then return { ok = false, reason = 'service' }; end
    local jug = M.jug();
    if jug == nil then
        M._emit(M.refusalLine({ reason = 'no-jug' }));
        return { ok = false, reason = 'no-jug' };
    end
    local res = S.act.request(M.buildRequest(jug, method));
    if type(res) == 'table' and res.ok ~= true then
        if res.reason == 'busy' then
            M._emit(string.format('Resummon is busy -- %s is running a sequence.',
                tostring(res.holderLabel or res.holder or 'another helper')));
        end
        return { ok = false, reason = res.reason or 'refused' };
    end
    return { ok = true };
end

-- ---------------------------------------------------------------------------
-- live state + the subscriptions
-- ---------------------------------------------------------------------------

-- Assemble the decision state from the live world. Every read is contained by the
-- module API; an unreadable one leaves its key nil, and the two deciders know which
-- way each nil goes.
function M.liveState(at)
    local S = _S;
    local jug = M.jug();
    local st = {
        armed    = M.armed(),
        jug      = jug,
        method   = M.method(),
        fallback = M.fallback(),
        now      = tonumber(at) or now(),
        queued   = _queued,
    };
    if type(S) ~= 'table' then return st; end

    -- How many of the jug can be EQUIPPED right now. 0 when it cannot answer: a
    -- jug it cannot see is a jug not carried, which refuses rather than firing
    -- Call Beast bare.
    if jug ~= nil then st.stock = S.item.own(jug); end

    -- The module-activity predicate -- the ONE gate every Job helper consults.
    local act = S.me.acting();
    if type(act) == 'table' then
        st.active = (act.active == true);
        st.reason = act.reason;
    end

    st.busy = S.act.busy();

    -- Unknown reads READY (the courtesy gate).
    st.callReady    = S.ability.ready(M.RECAST.call);
    st.loyaltyReady = S.ability.ready(M.RECAST.loyalty);

    -- The three OBSERVED cancels (the queue tick's, not the loss decision's) come
    -- from the same signals and world reads that classified the death, so the queue
    -- and the classifier can never disagree about whether you zoned.
    local sig = S.pet.signals(st.now);
    if type(sig) == 'table' and sig.leave ~= nil then st.leave = true; end
    st.zoning = S.player.zoning();
    st.logout = S.player.loggingOut();

    return st;
end

-- One classified loss edge -> one decision -> at most one sequence request (or one
-- queued resummon). Returns the decision so the Panel (and the tests) can see WHY
-- nothing happened. Never throws.
function M.onLoss(edge)
    local at = nil;
    if type(edge) == 'table' then at = tonumber(edge.at); end
    local st = M.liveState(at);
    local d  = M.decideLoss(edge, st);
    d.at = st.now;
    _last = d;

    if d.loud == true then M._emit(M.refusalLine(d)); end

    if d.queue == true then
        -- Remember the PICK and the checkbox, not the resolved method: which
        -- ability ends up firing is re-decided when the queue ticks, against
        -- whatever is ready then.
        _queued = { jug = d.jug, method = st.method, fallback = st.fallback, at = st.now };
        return d;
    end
    if d.act ~= true then return d; end

    -- A standing queue cannot survive an act: two resummons for one pet is the one
    -- way this rule could spend a jug it was never asked to. (In practice the queue
    -- is already gone -- a new loss edge needs a pet to have come back, and that
    -- cancels it -- but "in practice" is not a guarantee.)
    _queued = nil;
    M.request(d.method);
    return d;
end

-- One vitals beat -> the queue tick. Runs on the SAME beat the loss edge rides, so
-- a queued resummon is re-tested every 0.4s and fires within one beat of the recast
-- coming up. A no-op with nothing queued, which is almost always.
function M.onVitals(vitals)
    if _queued == nil then return nil; end
    local at = nil;
    if type(vitals) == 'table' then at = tonumber(vitals.at); end
    local st = M.liveState(at);
    st.queued = _queued;
    -- "A pet appearing any other way" -- the beat's own answer, and the one read
    -- liveState cannot make for itself.
    if type(vitals) == 'table' then st.petPresent = (vitals.present == true); end

    local d = M.queueDecide(st);
    d.at = st.now;
    _last = d;

    if d.cancel ~= nil then
        if d.loud == true then M._emit(M.refusalLine(d)); end
        _queued = nil;
        return d;
    end
    if d.fire ~= true then return d; end

    _queued = nil;                       -- the queue is spent whatever happens next
    M.request(d.method);
    return d;
end

-- Subscribe to BOTH halves of the pet vitals service: the classified loss edge (the
-- trigger) and the per-beat vitals (the queue tick + the "a pet appeared" cancel).
--
-- It also hands the service the module's NAME AUTHORITY, which is what makes the
-- classifier able to tell a jug pet from a charmed one at all -- the list is the
-- module's data, the classification is the service's rule.
function M.init(S)
    if type(S) ~= 'table' then return false; end
    _S = S;
    local ok = false;
    pcall(function()
        S.pet.nameAuthority(function(name)
            local jugs = jugsMod();
            if jugs == nil then return nil; end
            -- The player's own configured jug maps to a pet that counts too, so a
            -- jug the roster has not caught up with still resummons.
            return jugs.isJugPet(name, jugs.petFor(M.jug()));
        end);
        ok = S.pet.onLoss('resummon', function(e) M.onLoss(e); end);
        S.pet.subscribe('resummonq', function(v) M.onVitals(v); end);
    end);
    return ok;
end

function M.id()
    if type(_S) ~= 'table' then return nil; end
    return _S.id;
end

return M;
