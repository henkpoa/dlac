--[[
    dlac/jobhelpers/bst/fight.lua -- the BST Helper's FIGHT switch (issue #139;
    POLL rewrite 2026-07-29 after two field rounds).

    THREE WAYS, and nothing between them:
        off     -- the helper never issues a pet command
        attack  -- while you are ENGAGED and your pet stands IDLE, it is sent at
                   your current target. Once it fights, nothing more is issued.
        follow  -- `attack`, plus: a pet already fighting is re-sent when YOUR
                   battle target changes to a different mob.

    WHY A POLL AND NOT PACKET EDGES (the field history, both on 2026-07-29): the
    edge design failed two live rounds -- the client sends 0x0F-then-0x02 pairs
    on a fresh attack (round 1; fixed with (target,kind) debounce keys) and the
    captured-entity confirm still refused every send (round 2). The FIELD-PROVEN
    shape on this server is Pup-Helper's: poll "am I engaged + is the pet idle +
    do I have a target", then issue. The pet-idle gate is simultaneously the
    spam brake AND the retry: a command the server refused leaves the pet idle,
    so the next beat tries again; a command that took makes the pet non-idle,
    which stops the issuing. The GearSwap BST convention is the same shape
    (docs/reference/pet-handling-other-luas.md section 4.2: `pet.status ==
    'Idle' and player.target.type == 'MONSTER'` -> `/pet Fight`). Heel still
    holds where it matters: a heeled pet is idle, so while you STAY engaged
    with a target the poll will re-send it (capped below); pull back and
    disengage -- or drop the target -- and nothing fires.

    THE METRONOME is the pet vitals beat (feature\petvitals.subscribe, 0.4s --
    the engine's own dispatch cadence): no new frame wiring, and the vitals
    record (present + status) arrives with the tick. The DECISION is a pure
    function (pollDecide) -- state in, act/reason out -- so every rule is a
    headless test (BFT*).

    RESTRAINT (the approved-envelope discipline): at most one command per
    RETRY_S at the same target, at most MAX_TRIES per (engagement, target) -- a
    command that never takes goes QUIET with a visible 'capped' reason in the
    Panel instead of machine-gunning. The counters reset when you disengage or
    move to a different target. Commands leave through lib\cmdqueue.issue --
    THE central auto-issue door -- and `<t>` resolves at execution against the
    same target the poll just read (self-consistent; there is no captured
    entity for a confirm to disagree with).
]]--

local M = {};

-- The three ways, in switch order. `off` first: a player scanning the row reads
-- the safe state first, and it is the default (see config.DEFAULTS.fight).
M.MODES = { 'off', 'attack', 'follow' };

-- Player-facing labels (signed off 2026-07-29; naming law: helpers name the
-- RULE, never "Auto <activity>").
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

-- The action command. `<t>` resolves at execution against the target the poll
-- just read. FLAGGED for field verification: the exact CatsEyeXI spelling of
-- the pet command is confirmed in-game before this ships to players.
M.COMMAND = '/pet "Fight" <t>';

-- Pacing: at most one command per RETRY_S at the same target, at most
-- MAX_TRIES per (engagement, target) before going quiet with a 'capped'
-- Panel reason (a command that is not taking is news, not a machine gun).
M.RETRY_S   = 2.0;
M.MAX_TRIES = 3;

-- This module's folder name -- the loader assigns identity FROM the folder;
-- `init(id)` overrides if the folder is ever renamed.
local DEFAULT_ID = 'bst';

local _id   = DEFAULT_ID;
local _last = nil;        -- the last decision (what the Panel reports; no chat)

-- Per-engagement issue bookkeeping (reset on disengage / mode off):
local _issue = nil;       -- { target = <index>, at = <sec>, tries = <n> }
local _prevTarget = nil;  -- last polled target index (the follow change signal)

-- ---------------------------------------------------------------------------
-- the mode (persisted in the module's own config file)
-- ---------------------------------------------------------------------------

local function cfg()
    local c = nil;
    pcall(function() c = require('dlac\\jobhelpers\\bst\\config'); end);
    return (type(c) == 'table') and c or nil;
end

function M.isMode(m)
    for _, v in ipairs(M.MODES) do
        if v == m then return true; end
    end
    return false;
end

-- The live Fight mode. An unreadable / absent config reads 'off' -- an
-- action-performing feature never defaults itself ON.
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
--   targetChanged = <bool>,        -- the polled target differs from the last poll's
--   last          = { target, at, tries } | nil,   -- the issue bookkeeping
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
        local p = paced();
        if p ~= nil then return { act = false, reason = p }; end
        return { act = true, reason = nil, targetIndex = tgt, command = M.COMMAND };
    end
    if state.petIdle ~= false then
        return { act = false, reason = 'pet-state-unknown' };
    end

    -- The pet is fighting. follow: re-send when MY target moved to a different
    -- mob (works for a pet the player sent by hand too -- the change signal is
    -- the POLL's, not the issue history's).
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
    ['no-pet']            = 'no pet out',
    ['no-target']         = 'no battle target',
    ['waiting']           = 'sent -- waiting for the pet to take',
    ['capped']            = 'the command is not taking (capped -- check the pet command wording)',
    ['pet-busy']          = 'your pet is already fighting',
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

-- ---------------------------------------------------------------------------
-- live reads (injectable as a whole -- the location.reader precedent)
-- ---------------------------------------------------------------------------

M.reads = {};

-- Is the player ENGAGED right now? true / false / nil (unreadable). The one
-- status read is dlac's own gData provider (nativedata resolves the string).
M.reads.engaged = function()
    local e = nil;
    pcall(function()
        local g = rawget(_G, 'gData');
        if type(g) ~= 'table' or type(g.GetPlayer) ~= 'function' then return; end
        local p = g.GetPlayer();
        if type(p) ~= 'table' or type(p.Status) ~= 'string' then return; end
        e = (p.Status == 'Engaged');
    end);
    return e;
end;

-- The CURRENT battle target's entity index, or nil. The sibling-proven idiom
-- (distance/geocompass/LAC data.lua: GetTarget():GetTargetIndex(0)).
M.reads.target = function()
    local idx = nil;
    pcall(function()
        local tgt = AshitaCore:GetMemoryManager():GetTarget();
        if tgt == nil then return; end
        local i = tgt:GetTargetIndex(0);
        if type(i) == 'number' and i > 0 then idx = i; end
    end);
    return idx;
end;

-- The entity display name for an index, trimmed, or nil (the entwatch idiom).
M.reads.nameOf = function(index)
    local nm = nil;
    pcall(function()
        nm = AshitaCore:GetMemoryManager():GetEntity():GetName(index);
    end);
    if type(nm) ~= 'string' then return nil; end
    nm = (nm:gsub('%z', ''):gsub('%s+$', ''));
    if nm == '' then return nil; end
    return nm;
end;

-- The same monotonic clock the sequencer/reward use (cmdqueue frames ->
-- seconds; os.clock when the queue is unreachable -- headless).
M._now = function()
    local t = nil;
    pcall(function()
        local cq = require('dlac\\lib\\cmdqueue');
        if type(cq) == 'table' and type(cq.frame) == 'function' then
            t = cq.frame() / 60.0;
        end
    end);
    if t == nil then pcall(function() t = os.clock(); end); end
    return tonumber(t) or 0;
end;

-- ---------------------------------------------------------------------------
-- firing + the vitals-beat glue
-- ---------------------------------------------------------------------------

-- THE central issue door (lib\cmdqueue.issue -- Henrik's ruling 2026-07-29:
-- every auto-issued command goes through the ONE reusable function). Falls
-- back to a direct QueueCommand only if the queue is unreachable.
M._fire = function(command)
    local queued = false;
    pcall(function()
        local cq = require('dlac\\lib\\cmdqueue');
        if type(cq) == 'table' and type(cq.issue) == 'function' then
            queued = (cq.issue(command) == true);
        end
    end);
    if queued then return true; end
    local sent = false;
    pcall(function()
        AshitaCore:GetChatManager():QueueCommand(1, command);
        sent = true;
    end);
    return sent;
end;

-- Drop the per-engagement bookkeeping (disengage / mode off / test reset).
function M.resetIssues()
    _issue, _prevTarget = nil, nil;
end

-- One vitals beat -> one poll -> at most one command. `vitals` is the petvitals
-- record; `reads`/`id` are injectable (tests). Returns the decision so the
-- Panel (and the tests) can see WHY nothing happened.
function M.onBeat(vitals, reads, id)
    reads = (type(reads) == 'table') and reads or M.reads;
    local st = { mode = M.mode(), now = M._now() };

    -- The module-activity predicate (pill, main job, town, dead, zoning) --
    -- the ONE gate every Job helper consults; never a second copy of the rules.
    pcall(function()
        local jh = require('dlac\\feature\\jobhelpers');
        if type(jh) ~= 'table' or type(jh.activity) ~= 'function' then return; end
        local act = jh.activity(id or _id);
        if type(act) ~= 'table' then return; end
        st.active = (act.active == true);
        st.reason = act.reason;
    end);

    if type(vitals) == 'table' then
        st.hasPet = (vitals.present == true);
        local s = vitals.status;
        if type(s) == 'string' and s ~= '' then
            st.petIdle = (s == 'Idle');
        end
    end

    if type(reads.engaged) == 'function' then
        local ok, e = pcall(reads.engaged);
        if ok then st.engaged = e; end
    end
    if type(reads.target) == 'function' then
        local ok, t = pcall(reads.target);
        if ok then st.targetIndex = t; end
    end

    -- Disengaged (or switched off): the engagement bookkeeping dies with it.
    if st.engaged ~= true or st.mode == 'off' then
        M.resetIssues();
    else
        local tgt = tonumber(st.targetIndex) or 0;
        if tgt > 0 then
            st.targetChanged = (_prevTarget ~= nil and _prevTarget ~= tgt);
            _prevTarget = tgt;
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
        if type(reads.nameOf) == 'function' then
            local ok, nm = pcall(reads.nameOf, tgt);
            if ok then d.targetName = nm; end
        end
        M._fire(d.command);
    end

    _last = d;
    return d;
end

-- Subscribe to the pet vitals beat (feature\petvitals -- the 0.4s metronome).
-- Called from the module's init hook; idempotent (petvitals keys subscriptions
-- by name, so a reload replaces rather than doubles).
function M.init(id)
    if type(id) == 'string' and id ~= '' then _id = id; end
    local ok = false;
    pcall(function()
        local pv = require('dlac\\feature\\petvitals');
        if type(pv) ~= 'table' or type(pv.subscribe) ~= 'function' then return; end
        ok = pv.subscribe('jobhelper:' .. _id .. ':fight', function(v) M.onBeat(v); end);
    end);
    return ok;
end

function M.id() return _id; end

return M;
