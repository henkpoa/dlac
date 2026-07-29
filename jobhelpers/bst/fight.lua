--[[
    dlac/jobhelpers/bst/fight.lua -- the BST Helper's FIGHT switch (issue #139,
    PRD #135 user stories 12-17). The module's first real behavior: send the pet
    at what the player just attacked, and -- optionally -- keep sending it as the
    target rolls.

    THREE WAYS, and nothing between them:
        off     -- the helper never issues a pet command
        attack  -- ENGAGE edges only: you attack a mob, the pet goes in once.
                   A mid-fight target change does nothing.
        follow  -- ENGAGE and RETARGET edges: auto-target rolling to the next mob
                   re-sends the pet.

    It is edge-driven, and ONLY edge-driven. Every send traces to one outgoing
    action packet the player's own client sent (feature\engagewatch), which is
    what makes the rest of the promises true for free:

      * HEEL IS RESPECTED. Nothing here polls "is the pet idle?" and nothing
        re-fires on a timer, so a pulled-back pet stays back until the player
        attacks or changes target again. There is no pet-idle gate to fight with.
      * FIRE AND FORGET. A server refusal (out of range, pet busy) is not
        retried -- the next real edge is the next attempt, per the PRD.
      * NO SAME-TARGET SPAM. The 5-second per-target debounce lives in the edge
        service, so packet stutter never reaches this module at all.
      * JUG AND CHARMED PETS ARE THE SAME. Nothing here reads the pet's name,
        family or origin -- only that a pet EXISTS. A charmed pet is a pet.

    THE TARGET IS THE PACKET'S TARGET. `/pet "Fight" <t>` is the only way to send
    a pet at a specific entity from a chat command, and `<t>` resolves at
    EXECUTION time -- one more auto-target roll and the pet goes at the wrong mob.
    So the captured entity is CONFIRMED against the live target before the command
    is issued: a positive mismatch cancels the send. An UNREADABLE target does not
    (a read we cannot make must not silently disable the feature) -- see
    `targetConfirms`.

    House shape: `decide(edge, state)` is the pure decision -- edge + state in,
    command decision out, no AshitaCore, no clock -- so every rule above is a
    headless test (BFT*). `liveState` assembles that state from the module
    activity predicate, the pet read and the target read; `onEdge` is the
    engagewatch subscriber that joins the two and fires.
]]--

local M = {};

-- The three ways, in switch order. `off` first: a player scanning the row reads
-- the safe state first, and it is the default (see config.DEFAULTS.fight).
M.MODES = { 'off', 'attack', 'follow' };

-- Player-facing labels, PROPOSED pending the maintainer's sign-off (naming law:
-- helpers name the RULE, never "Auto <activity>"). They are the issue's own
-- words for the switch.
M.MODE_LABEL = {
    off    = 'Off',
    attack = 'When I attack',
    follow = 'Follow my target',
};

M.MODE_HELP = {
    off    = 'The helper never sends your pet in. Pet commands stay entirely yours.',
    attack = 'Attacking a mob sends your pet at THAT mob, once. Changing target mid-fight does nothing.',
    follow = 'Attacking sends your pet in, and it is re-sent whenever your battle target changes --'
             .. ' so auto-target rolling to the next mob keeps your pet working.',
};

-- The action command. `<t>` is the only token that names an arbitrary monster,
-- and it is safe here because the captured entity is confirmed against the live
-- target first (see the header + targetConfirms). FLAGGED for field verification
-- alongside the Reward token: the exact CatsEyeXI spelling of the pet command is
-- confirmed in-game before this ships to players.
M.COMMAND = '/pet "Fight" <t>';

-- This module's folder name -- the loader assigns identity FROM the folder, so
-- this is the id the activity predicate is asked about. Same fallback the Panel
-- already uses; `init(id)` overrides it if the folder is ever renamed.
local DEFAULT_ID = 'bst';

local _id   = DEFAULT_ID;
local _last = nil;        -- the last decision (what the Panel reports; no chat)

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
-- the PURE decision -- edge + state in, command decision out
-- ---------------------------------------------------------------------------
--
-- state = {
--   mode     = 'off'|'attack'|'follow',
--   active   = <bool>,          -- the module-activity predicate said "acting"
--   reason   = <'off'|'job'|'town'|'dead'|'zoning'|nil>,   -- why it is not
--   hasPet   = <true|false|nil>,   -- nil = the pet read could not be made
--   targetOk = <true|false|nil>,   -- false ONLY on a positive target mismatch
-- }
-- returns { act = <bool>, reason = <slug|nil>, command = <string|nil>,
--           target = <the edge|nil> }
--
-- Two deliberate asymmetries, and they point opposite ways on purpose:
--   * `active` must be POSITIVELY true. An unreadable world (headless, pre-login,
--     a job read that has not settled) is not permission to command a pet.
--   * `hasPet` must be POSITIVELY true, for the same reason and because AC4 is
--     literal: no pet means no command is ever ISSUED, not merely refused by the
--     client. This is the one place the module departs from the buff-cache
--     "unknown never flips behavior" discipline, because here the unknown-reads-
--     as-yes branch is the one that acts.
--   * `targetOk` only blocks on FALSE. Unknown keeps the send, because the edge
--     itself already named the entity and the confirm is a second opinion.
function M.decide(edge, state)
    state = (type(state) == 'table') and state or {};

    local mode = state.mode;
    if not M.isMode(mode) then mode = 'off'; end
    if mode == 'off' then return { act = false, reason = 'off' }; end

    if type(edge) ~= 'table' or (edge.kind ~= 'engage' and edge.kind ~= 'retarget') then
        return { act = false, reason = 'no-edge' };
    end

    if state.active ~= true then
        return { act = false, reason = state.reason or 'inactive' };
    end

    -- 'attack' hears ENGAGE edges only: a mid-fight target change does nothing.
    if edge.kind == 'retarget' and mode ~= 'follow' then
        return { act = false, reason = 'mode' };
    end

    if state.hasPet ~= true then return { act = false, reason = 'no-pet' }; end

    if state.targetOk == false then return { act = false, reason = 'target-moved' }; end

    return { act = true, reason = nil, command = M.COMMAND, target = edge };
end

-- A short human line for a decision (the Panel's "last edge" report -- never
-- chat: Fight fires on every pull, and a line per pull is noise, not news).
local DECISION_TEXT = {
    ['off']          = 'Fight is off',
    ['no-edge']      = 'not an attack or target change',
    ['inactive']     = 'the helper is not acting',
    ['job']          = 'not on main-job BST',
    ['town']         = 'in town',
    ['dead']         = 'dead',
    ['zoning']       = 'zoning',
    ['mode']         = 'target changed (Fight is set to "' .. M.MODE_LABEL.attack .. '")',
    ['no-pet']       = 'no pet out',
    ['target-moved'] = 'your target moved on before the command could go',
};

function M.decisionText(d)
    if type(d) ~= 'table' then return 'nothing yet'; end
    if d.act == true then
        local nm = (type(d.target) == 'table') and d.target.name or nil;
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

-- Is a pet out RIGHT NOW? Asked of the PET VITALS central service (issue #140),
-- which owns the one pet read and the "dead pet = no pet" law -- this module
-- carried its own GetPetTargetIndex/GetHPPercent pair until that service landed,
-- and a second implementation of a centralized answer is exactly what the
-- Central-services rule forbids. `present` is two-state there (no pet and an
-- unreadable pet decide alike), which is what `decide` already wanted: only a
-- POSITIVE true is permission to command a pet.
--
-- Jug and charmed pets answer identically: the pet target index is the pet
-- target index, whatever put it there -- which is exactly why Fight needs no
-- pet-type test anywhere.
M.reads.pet = function()
    local has = nil;
    pcall(function()
        local pv = require('dlac\\feature\\petvitals');
        if type(pv) ~= 'table' or type(pv.get) ~= 'function' then return; end
        local v = pv.get();
        if type(v) == 'table' then has = (v.present == true); end
    end);
    return has;
end;

-- The client's CURRENT main target as { index, serverId }, or nil when it cannot
-- be read (headless, no target, an Ashita build without the target manager).
M.reads.target = function()
    local t = nil;
    pcall(function()
        local tgt = AshitaCore:GetMemoryManager():GetTarget();
        if tgt == nil then return; end
        local idx = tgt:GetTargetIndex(0);
        local sid = tgt:GetServerId(0);
        if type(idx) ~= 'number' and type(sid) ~= 'number' then return; end
        t = { index = idx, serverId = sid };
    end);
    return t;
end;

-- Does the live target still name the entity the PACKET captured?
--   true  -- confirmed, same entity
--   false -- a positive contradiction: the target is a DIFFERENT entity
--   nil   -- cannot tell (no read, no ids to compare)
-- Server id wins when both sides carry one; the entity index is the fallback.
-- Pure: `cur` is passed in.
function M.targetConfirms(edge, cur)
    if type(edge) ~= 'table' or type(cur) ~= 'table' then return nil; end
    local esid, csid = tonumber(edge.serverId) or 0, tonumber(cur.serverId) or 0;
    if esid > 0 and csid > 0 then return esid == csid; end
    local eidx, cidx = tonumber(edge.index) or 0, tonumber(cur.index) or 0;
    if eidx > 0 and cidx > 0 then return eidx == cidx; end
    return nil;
end

-- Assemble the decision state from the live world. `reads` overrides the whole
-- read table (tests); `id` overrides the module id.
function M.liveState(edge, reads, id)
    reads = (type(reads) == 'table') and reads or M.reads;
    local st = { mode = M.mode() };

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

    if type(reads.pet) == 'function' then
        local ok, has = pcall(reads.pet);
        if ok then st.hasPet = has; end
    end

    if type(reads.target) == 'function' then
        local ok, cur = pcall(reads.target);
        if ok then st.targetOk = M.targetConfirms(edge, cur); end
    end

    return st;
end

-- ---------------------------------------------------------------------------
-- firing + the engagewatch subscription
-- ---------------------------------------------------------------------------

-- Send the command through the central command queue (lib\cmdqueue -- "queue a
-- chat/game command safely"), which drains one frame later on the MAIN thread.
-- Falls back to a direct QueueCommand only if the queue is unreachable.
M._fire = function(command)
    local queued = false;
    pcall(function()
        local cq = require('dlac\\lib\\cmdqueue');
        if type(cq) == 'table' and type(cq.enqueue) == 'function' then
            cq.enqueue(0, command);
            queued = true;
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

-- One accepted edge -> one decision -> at most one command. Returns the decision
-- so the caller (and the tests) can see WHY nothing happened. Never throws: the
-- subscriber contract is pcall'd by engagewatch, but a Panel reading _last must
-- never find a half-built record either.
function M.onEdge(edge, reads, id)
    local d = M.decide(edge, M.liveState(edge, reads, id));
    d.at = (type(edge) == 'table') and edge.at or nil;
    _last = d;
    if d.act ~= true then return d; end
    M._fire(d.command);
    return d;
end

-- Subscribe to the engage/target edge service. Called from the module's init
-- hook; idempotent (engagewatch keys subscriptions by name, so a reload replaces
-- rather than doubles).
function M.init(id)
    if type(id) == 'string' and id ~= '' then _id = id; end
    local ok = false;
    pcall(function()
        local ew = require('dlac\\feature\\engagewatch');
        if type(ew) ~= 'table' or type(ew.subscribe) ~= 'function' then return; end
        ok = ew.subscribe('jobhelper:' .. _id, function(edge) M.onEdge(edge); end);
    end);
    return ok;
end

function M.id() return _id; end

return M;
