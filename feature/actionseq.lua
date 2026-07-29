--[[
    dlac/feature/actionseq.lua -- the ACTION SEQUENCE machinery (issue #138,
    PRD #135). CONTEXT.md vocabulary: an "Action sequence" is a request to dress
    slots, verify they landed, fire one action command, and release -- driven
    through the lifecycle

        claimed  ->  verified worn  ->  fired  ->  released
                  \-> refused(reason)   (a senior holder / lock / free equip took a needed slot)
                  \-> aborted(reason)   (the gear never landed inside the timeout)

    A request carries: the CLAIM (an optional named Set union specific items, as
    one { SlotKey = itemName } table), the slots that MUST verify worn, an action
    COMMAND, and a verify TIMEOUT. The service rides ONE shared Arbiter claimant
    row (JobHelper); while a sequence is claiming, that row's claim IS this
    request's claim, so the standing rank walk decides every contested slot. A
    senior claimant (ranked above JobHelper) that wins a needed slot is a REFUSAL,
    loud, and the action does NOT fire (never-fire-bare). Success is SILENT.
    Release drops the claim; the next arbitration restores gear (one claim, one
    send -- the standing law).

    ONE sequence is live at a time. A started sequence is NEVER preempted: a
    request arriving while one runs is refused, naming the holder. Two requests
    contending in the SAME resolution step resolve by the current job's module
    order (the tab's section order) -- arbitrateRequests -- and the loser is
    refused loudly.

    House shape: a PURE state machine -- request / tick / arbitrateRequests --
    that takes an injected io seam (worn / blocker / fire / release / emit) and a
    `now` clock, so the whole lifecycle drives headlessly (AC8: never-fire-bare,
    timeout abort, senior-claimant refusal, release, exactly one send). The live
    glue (`pump`) wires the gear oracle, the command bus and chatfmt.

    Pure at load; every AshitaCore/require touch is call-time under pcall.
]]--

local M = {};

-- Lifecycle states. 'claiming' = claim submitted, verifying worn / counting down
-- the timeout; 'firing' = verified, command sent once, gear held through the cast
-- until the short release settle elapses. 'idle' = nothing live.
local S_IDLE     = 'idle';
local S_CLAIMING = 'claiming';
local S_FIRING   = 'firing';

-- The live sequence (nil when idle) and the last finished outcome (for /dl why +
-- tests). _seq = { module, label, order, claim, need, command, timeout,
--                  startAt, fireAt, fired }.
local _seq  = nil;
local _last = nil;

-- How long (seconds) the claim is held AFTER the command fires, so the action
-- resolves against the verified gear before the claim releases and the next
-- arbitration restores. A request may override (req.hold).
local DEFAULT_HOLD = 0.4;

-- ---------------------------------------------------------------------------
-- helpers (pure)
-- ---------------------------------------------------------------------------

local function normItem(v)
    if v == nil then return nil; end
    return string.lower(tostring(v));
end

-- The set of slots a request must see WORN before it may fire. Defaults to the
-- whole claim when `need` is omitted (verify everything you asked for).
local function needSlots(req)
    if type(req) ~= 'table' then return {}; end
    if type(req.need) == 'table' then return req.need; end
    return (type(req.claim) == 'table') and req.claim or {};
end

-- ---------------------------------------------------------------------------
-- request arbitration -- SIMULTANEOUS contenders (AC6)
-- ---------------------------------------------------------------------------
--
-- Given a list of contending requests, the winner is the one with the HIGHEST
-- module order (the tab's section order); ties break by module id so the choice
-- is deterministic (no pairs()-order dependency -- hard rule 8). Returns
-- winner, losers. Pure; the loser-refusal chat is the caller's to emit, naming
-- the winner as the holder.
function M.arbitrateRequests(reqs)
    reqs = (type(reqs) == 'table') and reqs or {};
    local winner = nil;
    for _, r in ipairs(reqs) do
        if type(r) == 'table' then
            if winner == nil then
                winner = r;
            else
                local ro = tonumber(r.order) or 0;
                local wo = tonumber(winner.order) or 0;
                if ro > wo or (ro == wo and tostring(r.module or '') < tostring(winner.module or '')) then
                    winner = r;
                end
            end
        end
    end
    local losers = {};
    for _, r in ipairs(reqs) do
        if type(r) == 'table' and r ~= winner then losers[#losers + 1] = r; end
    end
    return winner, losers;
end

-- ---------------------------------------------------------------------------
-- request -- open a sequence
-- ---------------------------------------------------------------------------
--
-- req = { module, label, order, claim = { SlotKey = itemName },
--         need = { SlotKey = itemName } (optional -- defaults to claim),
--         command = '<chat command>', timeout = <seconds>, hold = <seconds?> }
-- Returns { ok = true } on accept, or { ok = false, reason = 'busy',
-- holder = <live module>, holderLabel = <live label> } when a sequence is
-- already live -- the started sequence is never preempted.
function M.request(req)
    if type(req) ~= 'table' then return { ok = false, reason = 'bad-request' }; end
    if _seq ~= nil then
        return { ok = false, reason = 'busy', holder = _seq.module, holderLabel = _seq.label };
    end
    _seq = {
        module  = req.module,
        label   = req.label or 'action',
        order   = tonumber(req.order) or 0,
        claim   = (type(req.claim) == 'table') and req.claim or {},
        need    = needSlots(req),
        command = req.command,
        timeout = tonumber(req.timeout) or 4,
        hold    = tonumber(req.hold) or DEFAULT_HOLD,
        startAt = nil,          -- stamped on the first tick (verify window opens then)
        fireAt  = nil,
        fired   = false,
    };
    return { ok = true };
end

-- ---------------------------------------------------------------------------
-- the tick -- advance the live sequence
-- ---------------------------------------------------------------------------
--
-- io = {
--   worn    = function(slot) -> itemName | nil,      -- the gear oracle read
--   blocker = function(slot) -> blockerName | nil,   -- a DEFINITIVE senior holder
--             / lock / free-equip on the slot (already display-labelled), else nil,
--   fire    = function(command),                     -- send the action command,
--   release = function(),                            -- drop the claim,
--   emit    = function(line),                        -- one-line chat (refusal/abort),
-- }
-- `now` is a monotonic clock in seconds. Returns the resulting state string.
local function finish(io, outcome, reason)
    -- release the claim (idempotent-safe: the caller's release just clears a flag)
    if type(io) == 'table' and type(io.release) == 'function' then pcall(io.release); end
    _last = { outcome = outcome, reason = reason,
              module = _seq and _seq.module or nil, label = _seq and _seq.label or nil };
    _seq = nil;
    return S_IDLE;
end

local function emit(io, line)
    if type(io) == 'table' and type(io.emit) == 'function' then pcall(io.emit, line); end
end

function M.tick(now, io)
    if _seq == nil then return S_IDLE; end
    now = tonumber(now) or 0;
    io = (type(io) == 'table') and io or {};
    local wornOf    = (type(io.worn) == 'function') and io.worn or function() return nil; end
    local blockerOf = (type(io.blocker) == 'function') and io.blocker or function() return nil; end

    if _seq.fired then
        -- FIRING: hold the verified gear through the cast, then release so the
        -- next arbitration restores. Success is SILENT.
        if _seq.fireAt ~= nil and (now - _seq.fireAt) >= _seq.hold then
            return finish(io, 'fired', nil);
        end
        return S_FIRING;
    end

    if _seq.startAt == nil then _seq.startAt = now; end   -- verify window opens now

    -- 1. A definitive blocker on any needed slot -> REFUSE, do NOT fire (AC2).
    for slot in pairs(_seq.need) do
        local b = blockerOf(slot);
        if b ~= nil and b ~= false and b ~= '' then
            emit(io, string.format('%s refused: %s held by %s.',
                tostring(_seq.label), tostring(slot), tostring(b)));
            return finish(io, 'refused', 'blocked:' .. tostring(slot));
        end
    end

    -- 2. Every needed slot verified worn -> FIRE (once), then hold (AC1). This
    --    is the ONLY place the command fires -- never-fire-bare.
    local allWorn = true;
    for slot, item in pairs(_seq.need) do
        if normItem(wornOf(slot)) ~= normItem(item) then allWorn = false; break; end
    end
    if allWorn then
        if not _seq.fired then
            _seq.fired = true;                     -- exactly one send: the guard is the latch
            _seq.fireAt = now;
            if _seq.command ~= nil and type(io.fire) == 'function' then
                pcall(io.fire, _seq.command);
            end
        end
        return S_FIRING;
    end

    -- 3. The gear never landed inside the timeout -> ABORT, nothing fired (AC3).
    if (now - _seq.startAt) >= _seq.timeout then
        emit(io, string.format('%s aborted: gear did not equip in time (verify timeout).',
            tostring(_seq.label)));
        return finish(io, 'aborted', 'timeout');
    end

    return S_CLAIMING;   -- keep waiting
end

-- ---------------------------------------------------------------------------
-- registry / status seams (the claimant row + /dl why consume these)
-- ---------------------------------------------------------------------------

-- The live claim table, or nil. The JobHelper CLAIMANTS row's `claim` returns
-- this; it is live through both claiming AND firing (the gear must stay worn
-- until release).
function M.claim()
    if _seq == nil then return nil; end
    return _seq.claim;
end

-- Is a sequence dressing slots right now? (The CLAIMANTS row's `active`.)
function M.active()
    return _seq ~= nil;
end

function M.state()
    if _seq == nil then return S_IDLE; end
    return _seq.fired and S_FIRING or S_CLAIMING;
end

-- The status text /dl why + the Priority tab show: the live module and act, or
-- 'idle'. Pure string; naming law -- the module id is the identity, the label is
-- the act.
function M.statusText()
    if _seq == nil then
        local l = _last;
        if type(l) == 'table' and l.outcome ~= nil then
            return string.format('idle (last: %s %s)', tostring(l.label or 'action'), tostring(l.outcome));
        end
        return 'idle';
    end
    return string.format('%s: %s (%s)', tostring(_seq.module or '?'),
        tostring(_seq.label or 'action'), M.state());
end

function M.lastOutcome() return _last; end

-- Cancel any live sequence without firing (job change / logout / test reset).
-- Releases through io when given one; otherwise just drops the claim.
function M.reset(io)
    if _seq ~= nil then
        _last = { outcome = 'cancelled', module = _seq.module, label = _seq.label };
        _seq = nil;
        if type(io) == 'table' and type(io.release) == 'function' then pcall(io.release); end
    else
        _last = nil;
    end
end

-- ---------------------------------------------------------------------------
-- live glue (Ashita only) -- the default io seam + the frame pump
-- ---------------------------------------------------------------------------

-- A monotonic seconds clock. os.clock is process CPU time on some builds; the
-- cmdqueue frame clock is the addon's steady tick, so prefer it, falling back to
-- os.clock. Injectable for tests.
M._now = function()
    local t = nil;
    pcall(function()
        local cq = require('dlac\\lib\\cmdqueue');
        if type(cq.frame) == 'function' then t = cq.frame() / 60.0; end   -- frames -> seconds (~60fps)
    end);
    if type(t) ~= 'number' then pcall(function() t = os.clock(); end); end
    return tonumber(t) or 0;
end

-- The worn-item-name read for a LAC SlotKey, through the engine's own worn
-- reader (dispatch exposes wornItemName as a twin of the oracle). nil = empty /
-- unreadable.
local function liveWorn(slot)
    local name = nil;
    pcall(function()
        local dsp = require('dlac\\dispatch');
        if type(dsp.wornName) == 'function' then name = dsp.wornName(slot); end
    end);
    return name;
end

-- A DEFINITIVE blocker on a slot: free equip (the ceiling writes nothing there)
-- or a slot lock (the veto holds what is worn). Both are read from the engine
-- and returned already display-labelled. A senior CLAIMANT winning the slot is
-- handled by the worn-mismatch -> timeout path today; naming it from the Arbiter
-- trace is a follow-on (see the PR notes). nil = no definitive blocker.
local function liveBlocker(slot)
    local b = nil;
    pcall(function()
        local dsp = require('dlac\\dispatch');
        local ls = string.lower(tostring(slot));
        if type(dsp.disabledOn) == 'function' and dsp.disabledOn(ls) then b = 'Free equip'; return; end
        if type(dsp.isLockedSlot) == 'function' and dsp.isLockedSlot(ls) then b = 'Locks'; return; end
    end);
    return b;
end

local function liveFire(command)
    pcall(function()
        AshitaCore:GetChatManager():QueueCommand(1, command);
    end);
end

local function liveEmit(line)
    local done = false;
    pcall(function()
        local cf = require('dlac\\chatfmt');
        if type(cf) == 'table' and type(cf.err) == 'function' then cf.err(line); done = true; end
    end);
    if not done then pcall(function() print('[dlac] ' .. tostring(line)); end); end
end

-- Release the claim: the sequencer stops being active, and the next Default
-- dispatch (the standing 0.4s tick) re-dresses the slots the claim held. Kicking
-- a Default here makes the restore immediate rather than waiting a tick.
local function liveRelease()
    -- nothing to clear here: M.claim()/M.active() already read _seq, which finish
    -- has set to nil by the time release runs. Kick a Default so the restore is
    -- not left to the next tick.
    pcall(function()
        local dsp = require('dlac\\dispatch');
        if type(dsp.kickDefault) == 'function' then dsp.kickDefault(); end
    end);
end

function M._liveIo()
    return { worn = liveWorn, blocker = liveBlocker, fire = liveFire,
             release = liveRelease, emit = liveEmit };
end

-- The frame pump: advance the live sequence against the live io. Called from
-- dlac.lua's d3d_present (guarded), like cmdqueue.tick. A no-op when idle.
function M.pump()
    if _seq == nil then return; end
    pcall(function() M.tick(M._now(), M._liveIo()); end);
end

return M;
