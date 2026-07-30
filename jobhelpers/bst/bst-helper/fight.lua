--[[
    dlac/jobhelpers/bst/bst-helper/fight.lua -- the BST Helper's FIGHT switch.

    THREE WAYS, and nothing between them:
        off     -- the helper never issues a pet command
        attack  -- while you are ENGAGED and your pet stands IDLE, it is sent at
                   your current target. Once it fights, nothing more is issued.
        follow  -- `attack`, plus: a pet already fighting is re-sent when YOUR
                   battle target changes to a different mob.

    WHY A POLL, AND WHERE THE EDGES WENT (the field history, both rounds on
    2026-07-29). The edge-driven design failed two live rounds: the client sends
    0x0F-then-0x02 pairs on a fresh attack (round 1; fixed with (target,kind)
    debounce keys), and then the captured-entity confirm refused every send (round
    2). The FIELD-PROVEN shape on this server is Pup-Helper's: poll "am I engaged
    + is the pet idle + do I have a target", then issue. The pet-idle gate is
    simultaneously the spam brake AND the retry -- a command the server refused
    leaves the pet idle, so the next beat tries again; a command that took makes
    the pet non-idle, which stops the issuing. The GearSwap BST convention is the
    same shape (docs/reference/pet-handling-other-luas.md 4.2).

    What round 2 actually indicted was using the packet's captured entity as the
    command's TARGET -- not the edge decode, which was correct. So the edges are
    still here, and this rule still benefits from them: the combat state service
    (feature\combat, via S.combat) answers `targetChanged` from the RETARGET EDGE
    whenever one arrived, falling back to its own poll otherwise. That matters for
    `follow`: a poll alone cannot see an A->B->A switch inside one 0.4s beat, and
    cannot tell a real target change from an entity index the server recycled.
    The command still fires `<t>`, which resolves at execution against the same
    target the beat just read -- there is no captured entity for a confirm to
    disagree with.

    HEEL is the player's OPTION (Henrik's ruling, same day): with Respect Heel ON
    (the default) a send that TOOK is never repeated at that target -- pulling the
    pet back sticks until you switch targets or disengage; OFF, an idle pet keeps
    being re-sent while you are engaged, up to the cap.

    THE METRONOME is the combat beat (S.combat.subscribe -- 0.4s, the engine's own
    dispatch cadence). The PET is read at decision time (S.pet.get(), which reads
    the world now), so this rule is a combat rule that happens to check a pet,
    rather than a pet subscriber that happens to read combat -- which is what it
    had to be when the pet beat was the only per-beat publisher dlac shipped.

    RESTRAINT (the approved-envelope discipline): at most one command per RETRY_S
    at the same target, at most MAX_TRIES per (engagement, target) -- a command
    that never takes goes QUIET with a visible 'capped' reason in the Panel instead
    of machine-gunning. The counters reset when you disengage or move to a
    different target. Commands leave through S.cmd -- THE central auto-issue door.

    The DECISION is a pure function (pollDecide) -- state in, act/reason out -- so
    every rule is a headless test (BFT*).
]]--

local M = {};

-- The three ways, in switch order. `off` first: a player scanning the row reads
-- the safe state first, and it is the default.
M.MODES = { 'off', 'attack', 'follow' };

-- Player-facing labels (naming law: helpers name the RULE, never "Auto <x>").
M.MODE_LABEL = {
    off    = 'Off',
    attack = 'When I attack',
    follow = 'Follow my target',
};

M.MODE_HELP = {
    off    = 'The helper never sends your pet in. Pet commands stay entirely yours.',
    attack = 'While you are engaged, an idle pet is sent at your target. Once it fights, nothing more is issued.',
    follow = 'As above, and a pet already fighting is re-sent when your battle target changes --'
             .. ' so auto-target rolling to the next mob keeps your pet working.',
};

-- The action command. `<t>` resolves at execution against the target the beat
-- just read. FLAGGED for field verification: the exact CatsEyeXI spelling of the
-- pet command is confirmed in-game before this ships to players.
M.COMMAND = '/pet "Fight" <t>';

-- Pacing: at most one command per RETRY_S at the same target, at most MAX_TRIES
-- per (engagement, target) before going quiet with a 'capped' Panel reason (a
-- command that is not taking is news, not a machine gun).
M.RETRY_S   = 2.0;
M.MAX_TRIES = 3;

-- WHEN to start sending (Henrik's option 2026-07-29): 'drawn' = the moment you
-- engage (weapon drawn -- the default, the Pup shape); 'swing' = only once your
-- own auto-attack has actually swung this engagement (for early engages where you
-- draw at range and close in).
M.WHENS = { 'drawn', 'swing' };
M.WHEN_LABEL = {
    drawn = 'Weapon drawn',
    swing = 'First swing',
};
M.WHEN_HELP = {
    drawn = 'Your pet is sent as soon as you engage (draw your weapon) with a target.',
    swing = 'Your pet waits until your first auto-attack actually swings this engagement --'
            .. ' engage early and close in without sending it.',
};

-- The module API table, handed over by init. Every service, the clock, the config
-- store and the issue door arrive through it -- see feature\modapi.
local _S = nil;

local _last  = nil;      -- the last decision (what the Panel reports; no chat)
local _issue = nil;      -- per-engagement bookkeeping { target, at, tries, took }

-- ---------------------------------------------------------------------------
-- the mode (persisted in the module's own settings store)
-- ---------------------------------------------------------------------------

local function cfg()
    if type(_S) ~= 'table' then return nil; end
    return _S.cfg;
end

function M.isMode(m)
    for _, v in ipairs(M.MODES) do
        if v == m then return true; end
    end
    return false;
end

-- The live Fight mode. An unreachable store reads 'off' -- an action-performing
-- feature never defaults itself ON.
function M.mode()
    local c = cfg();
    -- Plain if, not `(c ~= nil) and c.get(..) or nil` -- the documented ternary
    -- trap (07-23 review lesson, and #138's own merge-time fix).
    local m = nil;
    if c ~= nil then m = c.get('fight'); end
    if not M.isMode(m) then return 'off'; end
    return m;
end

function M.setMode(m)
    if not M.isMode(m) then return false; end
    local c = cfg();
    if c == nil then return false; end
    return c.set('fight', m);
end

function M.isWhen(w)
    for _, v in ipairs(M.WHENS) do
        if v == w then return true; end
    end
    return false;
end

function M.when()
    local c = cfg();
    local w = nil;
    if c ~= nil then w = c.get('fightWhen'); end
    if not M.isWhen(w) then return 'drawn'; end
    return w;
end

function M.setWhen(w)
    if not M.isWhen(w) then return false; end
    local c = cfg();
    if c == nil then return false; end
    return c.set('fightWhen', w);
end

-- Respect Heel? ON (default): once a send TAKES for this (engagement, target),
-- the pet is never re-sent at it -- pulling it back with Heel sticks until you
-- switch targets or disengage. OFF: an idle pet keeps being re-sent, up to the cap.
function M.heelRespect()
    local c = cfg();
    local v = nil;
    if c ~= nil then v = c.get('fightHeel'); end
    if v == nil then return true; end
    return (v == true);
end

function M.setHeelRespect(on)
    local c = cfg();
    if c == nil then return false; end
    return c.set('fightHeel', on == true);
end

-- ---------------------------------------------------------------------------
-- the PURE decision -- poll state in, command decision out
-- ---------------------------------------------------------------------------
--
-- state = {
--   mode          = 'off'|'attack'|'follow',
--   active        = <bool>,        -- the module-activity predicate said "acting"
--   reason        = <slug|nil>,    -- why it is not
--   engaged       = <true|false|nil>,   -- player Status == Engaged
--   hasPet        = <true|false|nil>,   -- vitals.present
--   petIdle       = <true|false|nil>,   -- vitals.status == 'Idle' (nil = unreadable)
--   targetIndex   = <number|nil>,  -- the CURRENT battle target's entity index
--   targetChanged = <bool>,        -- edge-answered when an edge arrived, else polled
--   needSwing     = <bool>,        -- the 'swing' option is selected
--   swung         = <true|false|nil>,   -- my auto-attack has swung this engagement
--   heelRespect   = <bool>,
--   last          = { target, at, tries, took } | nil,   -- the issue bookkeeping
--   now           = <seconds>,
-- }
-- returns { act = <bool>, reason = <slug|nil>, targetIndex, command }
--
-- POSITIVE-TRUE discipline on every act gate (`active`, `engaged`, `hasPet`,
-- `petIdle`): an unreadable world is never permission to command a pet. The
-- pacing gates (`waiting`, `capped`) apply to the CURRENT target's history and
-- die with it -- a different target, or a fresh engagement, starts clean.
function M.pollDecide(state)
    state = (type(state) == 'table') and state or {};

    local mode = state.mode;
    if not M.isMode(mode) then mode = 'off'; end
    if mode == 'off' then return { act = false, reason = 'off' }; end

    if state.active ~= true then
        return { act = false, reason = state.reason or 'inactive' };
    end
    if state.engaged ~= true then return { act = false, reason = 'not-engaged' }; end
    -- The "Send when" option: 'swing' holds every send until the player's own
    -- auto-attack has swung this engagement (positive-true, like every gate).
    if state.needSwing == true and state.swung ~= true then
        return { act = false, reason = 'no-swing-yet' };
    end
    if state.hasPet  ~= true then return { act = false, reason = 'no-pet' }; end

    local tgt = tonumber(state.targetIndex) or 0;
    if tgt <= 0 then return { act = false, reason = 'no-target' }; end

    local last = nil;
    if type(state.last) == 'table' then last = state.last; end
    local now = tonumber(state.now) or 0;
    local sameTarget = (last ~= nil) and (last.target == tgt);
    -- Pacing gates apply only where we would otherwise ACT -- a busy pet must
    -- read 'pet-busy' (the command took), never 'waiting' (BFT24's lesson).
    local function paced()
        if not sameTarget then return nil; end
        local since = now - (tonumber(last.at) or 0);
        if since >= 0 and since < M.RETRY_S then return 'waiting'; end
        if (tonumber(last.tries) or 0) >= M.MAX_TRIES then return 'capped'; end
        return nil;
    end

    if state.petIdle == true then
        -- Respect Heel (the option): a send that TOOK for this same target is
        -- never repeated while the option is on -- an idle pet here means the
        -- PLAYER pulled it back, and the helper does not fight the player. A
        -- different target (or a fresh engagement) starts clean.
        if sameTarget and last.took == true and state.heelRespect == true then
            return { act = false, reason = 'heeled' };
        end
        local p = paced();
        if p ~= nil then return { act = false, reason = p }; end
        return { act = true, reason = nil, targetIndex = tgt, command = M.COMMAND };
    end
    if state.petIdle ~= false then
        return { act = false, reason = 'pet-state-unknown' };
    end

    -- The pet is fighting. follow: re-send when MY target moved to a different
    -- mob (works for a pet the player sent by hand too -- the change signal is
    -- the SERVICE's, not the issue history's).
    if mode == 'follow' and state.targetChanged == true then
        local p = paced();
        if p ~= nil then return { act = false, reason = p }; end
        return { act = true, reason = nil, targetIndex = tgt, command = M.COMMAND };
    end
    return { act = false, reason = 'pet-busy' };
end

-- A short human line for a decision (the Panel's report -- never chat: Fight
-- acts on every pull, and a line per pull is noise, not news).
local DECISION_TEXT = {
    ['off']               = 'Fight is off',
    ['inactive']          = 'the helper is not acting',
    ['job']               = 'not on main-job BST',
    ['town']              = 'in town',
    ['dead']              = 'dead',
    ['zoning']            = 'zoning',
    ['not-engaged']       = 'you are not engaged',
    ['no-swing-yet']      = 'waiting for your first swing',
    ['no-pet']            = 'no pet out',
    ['no-target']         = 'no battle target',
    ['waiting']           = 'sent -- waiting for the pet to take',
    ['capped']            = 'the command is not taking (capped -- check the pet command wording)',
    ['pet-busy']          = 'your pet is already fighting',
    ['heeled']            = 'pet pulled back -- respecting Heel until you switch targets',
    ['pet-state-unknown'] = 'pet state unreadable',
};

function M.decisionText(d)
    if type(d) ~= 'table' then return 'nothing yet'; end
    if d.act == true then
        local nm = d.targetName;
        if type(nm) == 'string' and nm ~= '' then return 'sent your pet at ' .. nm; end
        return 'sent your pet in';
    end
    return DECISION_TEXT[d.reason] or tostring(d.reason or 'held');
end

function M.lastDecision() return _last; end

-- Drop the per-engagement bookkeeping (disengage / mode off / test reset).
function M.resetIssues()
    _issue = nil;
end

-- ---------------------------------------------------------------------------
-- one beat -> one poll -> at most one command
-- ---------------------------------------------------------------------------
--
-- `c` is the combat beat record (feature\combat): { engaged, targetIndex,
-- targetName, targetChanged, changedBy, swung, at }. `pet` is the vitals record;
-- omitted, it is read now through S.pet.get(). Returns the decision so the Panel
-- (and the tests) can see WHY nothing happened.
function M.onBeat(c, pet, S)
    S = (type(S) == 'table') and S or _S;
    c = (type(c) == 'table') and c or {};

    local now = 0;
    if type(S) == 'table' and type(S.now) == 'function' then now = S.now(); end
    local st = { mode = M.mode(), now = now };

    -- The module-activity predicate (pill, main job, town, dead, zoning) -- the
    -- ONE gate every Job helper consults; never a second copy of the rules.
    if type(S) == 'table' and type(S.me) == 'table' and type(S.me.acting) == 'function' then
        local act = S.me.acting();
        if type(act) == 'table' then
            st.active = (act.active == true);
            st.reason = act.reason;
        end
    end

    st.heelRespect = M.heelRespect();
    st.needSwing   = (M.when() == 'swing');
    st.swung       = c.swung;
    st.engaged     = c.engaged;
    st.targetIndex = c.targetIndex;

    -- The pet, read at DECISION time. Two-state on purpose: "no pet" and "could
    -- not read" answer identically, and neither is permission to command one.
    if pet == nil and type(S) == 'table' and type(S.pet) == 'table'
       and type(S.pet.get) == 'function' then
        pet = S.pet.get();
    end
    if type(pet) == 'table' then
        st.hasPet = (pet.present == true);
        local s = pet.status;
        if type(s) == 'string' and s ~= '' then
            st.petIdle = (s == 'Idle');
        end
    end

    -- Disengaged (or switched off): the engagement bookkeeping dies with it.
    if st.engaged ~= true or st.mode == 'off' then
        M.resetIssues();
    else
        st.targetChanged = (c.targetChanged == true);
        local tgt = tonumber(st.targetIndex) or 0;
        -- The TOOK latch (the Respect-Heel option's memory): our send is on record
        -- for this target and the pet is now FIGHTING -- the command took. From
        -- here an idle pet at the same target means the player pulled it back.
        if tgt > 0 and _issue ~= nil and _issue.target == tgt and st.petIdle == false then
            _issue.took = true;
        end
        st.last = _issue;
    end

    local d = M.pollDecide(st);
    d.at = st.now;

    if d.act == true then
        local tgt = d.targetIndex;
        if _issue ~= nil and _issue.target == tgt then
            _issue.tries = (tonumber(_issue.tries) or 0) + 1;
            _issue.at = st.now;
        else
            _issue = { target = tgt, at = st.now, tries = 1 };
        end
        -- The name rides in WITH the beat -- captured from the packet when an edge
        -- answered, read off the entity otherwise. Display only; the command is
        -- `<t>`.
        d.targetName = c.targetName;
        if type(S) == 'table' and type(S.cmd) == 'function' then S.cmd(d.command); end
    end

    _last = d;
    return d;
end

-- Subscribe to the combat beat. Called from the module's init hook; the key is
-- namespaced by the framework (jobhelper:<id>:fight), so a reload replaces rather
-- than doubles and two modules can never collide on it.
function M.init(S)
    if type(S) ~= 'table' then return false; end
    _S = S;
    local ok = false;
    pcall(function()
        ok = S.combat.subscribe('fight', function(c) M.onBeat(c); end);
    end);
    return ok;
end

function M.id()
    if type(_S) ~= 'table' then return nil; end
    return _S.id;
end

return M;
