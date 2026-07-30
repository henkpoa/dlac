--[[
    dlac/feature/combat.lua -- the COMBAT STATE service. ONE question, in the
    Central-services shape:

        "What is my combat situation right now, and what just changed?"

        combat.get()                 -> the record, read NOW
        combat.subscribe(who, cb)    -> the same record, pushed once per beat
        combat.onEdge(who, cb)       -> the raw engage/retarget edge, as it happens
        combat.lastEdge()            -> the last accepted edge, or nil

    The record:
        { engaged, targetIndex, targetName, targetChanged, changedBy, swung, at }

    WHY THIS EXISTS, and it is worth the paragraph. dlac had TWO half-answers to
    "what is happening in this fight" and a module had to know which half to ask:

      * feature\engagewatch -- the packet EDGES (0x01A cat 0x02 engage / 0x0F
        retarget), decoded from the client's own outgoing action, entity captured
        FROM the packet, per-target debounced. Precise about the moment.
      * a POLL, which the BST Fight switch grew privately (2026-07-29) after the
        edge-driven design failed two live rounds -- and which rode the PET vitals
        beat for its metronome, because that was the only per-beat publisher dlac
        shipped. A combat feature clocked by the pet service.

    Both halves are right about different things, and the field history says so
    precisely. What failed in round 2 was NOT the edge decode -- it was using the
    packet's captured entity as the command's TARGET; the fix was to fire `<t>`
    and let it resolve at execution. What the poll bought, and edges cannot, is
    the RETRY: a refused command leaves the pet idle, so the next beat tries
    again, where an edge fires once and a server refusal is simply lost.

    So this service publishes BOTH, and a consumer never chooses:

      * the BEAT carries the state a standing rule gates on (engaged? target?
        have I swung?) -- and the retry it needs comes free with the beat;
      * `targetChanged` is answered by the EDGE when one arrived (authoritative:
        the retarget packet IS the target changing, and it carries the server id,
        which survives an entity slot being reused) and by the poll otherwise
        (`changedBy` says which). A poll alone cannot see an A->B->A switch inside
        one beat, and cannot tell a real change from a recycled index. That is the
        precision the edges were built for, and it is now free to every consumer.

    THE ENTITY IS NEVER RE-DERIVED FOR A COMMAND. `targetIndex`/`targetName` are
    for DISPLAY and for change detection. Issue `<t>` and let the client resolve
    it -- the round-2 lesson, encoded here so no consumer relearns it.

    THE CADENCE is TICK_S (0.4s, the engine's own dispatch beat), and the service
    reads nothing at all while nobody is subscribed -- so it is free on every job
    that has no combat helper installed. `get()` has no cache: it reads now.

    House shape: a PURE core -- `fromReads` -- takes injected reads, the previous
    target and this beat's edges and answers with no AshitaCore, so every rule
    drives headlessly (tests CBT*). The live reads and the engagewatch bridge are
    the thin glue.

    Pure at load; every AshitaCore / require touch is call-time under pcall.
]]--

local M = {};

-- The publish cadence, seconds -- the petvitals twin, and for the same reason:
-- the engine's Default dispatch already runs every 0.4s, and a combat subscriber
-- beating faster would be measuring the same memory twice for no one.
M.TICK_S = 0.4;

-- ---------------------------------------------------------------------------
-- the pure core -- reads + history in, the record out
-- ---------------------------------------------------------------------------
--
-- reads = {                       -- each read is the VALUE or a FUNCTION for it
--   engaged = <true|false|nil>,   -- nil = unreadable, and it STAYS nil
--   target  = <index|nil>,
--   nameOf  = function(index) -> name|nil,
--   swung   = <true|false|nil>,
-- }
-- prevTarget = the last beat's targetIndex (nil on the first beat / after reset)
-- edges      = { <engagewatch edge>, .. } accepted since the last beat
--
-- returns { engaged, targetIndex, targetName, targetChanged, changedBy, swung }
--
-- UNREADABLE STAYS UNREADABLE. `engaged` and `swung` ride through as nil rather
-- than as false: every consumer of this record issues a command off the answer,
-- and each has to decide for itself which way its own nil goes (the positive-true
-- discipline). A service that flattened nil to false would be making that call
-- for them, invisibly.
function M.fromReads(reads, prevTarget, edges)
    reads = (type(reads) == 'table') and reads or {};

    -- A read is a FUNCTION or a value, and both are answered here. The live
    -- table (M.reads) is functions; a test injects plain values. Called under
    -- pcall, exactly as `nameOf` is below and as petvitals reads its own pet --
    -- a read that throws is an unreadable one, which is nil, not a crash.
    local function readOf(v)
        if type(v) ~= 'function' then return v; end
        local ok, r = pcall(v);
        if not ok then return nil; end
        return r;
    end

    local out = { engaged = readOf(reads.engaged), swung = readOf(reads.swung) };

    local tgt = tonumber(readOf(reads.target));
    if tgt ~= nil and tgt > 0 then out.targetIndex = tgt; end

    if out.targetIndex ~= nil and type(reads.nameOf) == 'function' then
        local ok, nm = pcall(reads.nameOf, out.targetIndex);
        if ok and type(nm) == 'string' and nm ~= '' then out.targetName = nm; end
    end

    -- The change signal, EDGE first. A retarget edge is the client saying "my
    -- battle target is now this entity" -- it cannot be confused with an entity
    -- slot being reused, and it survives two switches inside one beat.
    local byEdge = false;
    for _, e in ipairs((type(edges) == 'table') and edges or {}) do
        if type(e) == 'table' and e.kind == 'retarget' then byEdge = true; break; end
    end
    if byEdge then
        out.targetChanged, out.changedBy = true, 'edge';
    elseif out.targetIndex ~= nil and prevTarget ~= nil and prevTarget ~= out.targetIndex then
        -- The poll's own witness: a target we had, and a different one now.
        out.targetChanged, out.changedBy = true, 'poll';
    else
        out.targetChanged = false;
    end

    return out;
end

-- ---------------------------------------------------------------------------
-- live reads (injectable as a whole -- the fight.reads / location.reader shape)
-- ---------------------------------------------------------------------------

M.reads = {};

-- Am I ENGAGED right now? true / false / nil (unreadable). The one status read
-- is dlac's own gData provider (nativedata resolves the string).
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
-- (distance / geocompass / LAC data.lua: GetTarget():GetTargetIndex(0)).
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

-- The entity display name for an index, trimmed, or nil (the entwatch idiom --
-- GetName pads with whitespace and NULs).
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

-- Has MY auto-attack swung this engagement? The edge service owns the 0x028
-- watch and the my-id compare; this is the one read of its answer.
M.reads.swung = function()
    local s = nil;
    pcall(function()
        local ew = require('dlac\\feature\\engagewatch');
        if type(ew) == 'table' and type(ew.swungThisEngagement) == 'function' then
            s = (ew.swungThisEngagement() == true);
        end
    end);
    return s;
end;

-- A monotonic seconds clock -- the cmdqueue frame counter (the addon's steady
-- tick) falling back to os.clock. The petvitals / actionseq twin.
M._now = function()
    local t = nil;
    pcall(function()
        local cq = require('dlac\\lib\\cmdqueue');
        if type(cq) == 'table' and type(cq.frame) == 'function' then t = cq.frame() / 60.0; end
    end);
    if type(t) ~= 'number' then pcall(function() t = os.clock(); end); end
    return tonumber(t) or 0;
end;

-- THE exported question. `reads` overrides the whole read table (tests). Reads
-- the world NOW and answers; no cache, no beat, no stamp.
--
-- Deliberately answers `targetChanged = false`: "changed since when?" has no
-- meaning outside the beat that measured it. A caller that needs the change
-- signal subscribes.
function M.get(reads)
    return M.fromReads((type(reads) == 'table') and reads or M.reads, nil, nil);
end

-- ---------------------------------------------------------------------------
-- the engagewatch BRIDGE -- edges accumulate, the beat drains them
-- ---------------------------------------------------------------------------
--
-- The edges are already decoded, debounced and entity-named by engagewatch (the
-- ONE decoder of the two battle edges -- this service never opens a second
-- reader for them, hard rule 7.3). We simply collect the accepted ones between
-- beats, so the beat can answer `targetChanged` from the authoritative source.
--
-- Bounded, because a pump that stopped running must not grow the inbox without
-- bound -- oldest dropped, exactly like engagewatch's own queue.
M.INBOX_MAX = 8;

local _inbox    = {};     -- edges accepted since the last beat
local _bridged  = false;  -- have we subscribed to engagewatch yet?
local _edgeSubs = {};     -- who -> cb   (passthrough consumers)

-- Note one edge. Public so a test can feed the bridge with no engagewatch.
function M.noteEdge(edge)
    if type(edge) ~= 'table' then return false; end
    if #_inbox >= M.INBOX_MAX then table.remove(_inbox, 1); end
    _inbox[#_inbox + 1] = edge;
    for _, cb in pairs(_edgeSubs) do pcall(cb, edge); end
    return true;
end

-- Attach to engagewatch, once. Idempotent (engagewatch keys subscriptions by
-- name, so a reload replaces rather than doubles). Contained: no engagewatch
-- means no edge half, and the poll half still answers -- which is exactly the
-- degradation the two-witness design is for.
function M._bridge()
    if _bridged then return true; end
    pcall(function()
        local ew = require('dlac\\feature\\engagewatch');
        if type(ew) ~= 'table' or type(ew.subscribe) ~= 'function' then return; end
        _bridged = ew.subscribe('dlac-combat', function(e) M.noteEdge(e); end);
    end);
    return _bridged;
end

-- The last accepted edge -- engagewatch's own answer, passed through so a
-- consumer never needs to require it directly.
function M.lastEdge()
    local e = nil;
    pcall(function()
        local ew = require('dlac\\feature\\engagewatch');
        if type(ew) == 'table' and type(ew.lastEdge) == 'function' then e = ew.lastEdge(); end
    end);
    return e;
end

-- Subscribe to the RAW edges (event-shaped), for a rule that reacts to the
-- moment rather than gating on the state. cb(edge) is pcall'd.
function M.onEdge(who, cb)
    if type(who) ~= 'string' or who == '' then return false; end
    if type(cb) ~= 'function' then return false; end
    _edgeSubs[who] = cb;
    M._bridge();
    return true;
end

function M.offEdge(who)
    if type(who) ~= 'string' then return false; end
    _edgeSubs[who] = nil;
    return true;
end

function M.edgeSubscriberCount()
    local n = 0;
    for _ in pairs(_edgeSubs) do n = n + 1; end
    return n;
end

-- ---------------------------------------------------------------------------
-- subscribers + the frame pump
-- ---------------------------------------------------------------------------

local _subs   = {};    -- who -> cb
local _last   = nil;   -- the last PUBLISHED record
local _lastAt = nil;   -- when it was published (the throttle's clock)
local _prevT  = nil;   -- the last beat's targetIndex (the poll's change witness)

-- Subscribe to the per-beat record. `who` names the consumer so a module can
-- drop its own subscription wholesale (the entwatch / petvitals contract).
-- cb(state) is pcall'd -- one throwing consumer never costs another its beat.
function M.subscribe(who, cb)
    if type(who) ~= 'string' or who == '' then return false; end
    if type(cb) ~= 'function' then return false; end
    _subs[who] = cb;
    M._bridge();
    return true;
end

function M.unsubscribe(who)
    if type(who) ~= 'string' then return false; end
    _subs[who] = nil;
    return true;
end

function M.subscriberCount()
    local n = 0;
    for _ in pairs(_subs) do n = n + 1; end
    return n;
end

-- The last PUBLISHED record, or nil before the first beat. Deliberately not the
-- answer to "what is my combat situation" -- that is get(), which reads now.
function M.last() return _last; end

-- Drop the published record and the change history (job change / logout / test
-- reset). Subscribers survive a reset(false); reset(true) drops them too.
function M.reset(dropSubs)
    _last, _lastAt, _prevT = nil, nil, nil;
    _inbox = {};
    if dropSubs == true then _subs = {}; _edgeSubs = {}; end
end

-- One beat: read the world, drain this beat's edges, publish. Returns the
-- published record, or nil when the beat was skipped (nobody listening, or
-- inside the throttle window). `now` / `reads` are the test seams.
--
-- A clock that went BACKWARDS publishes rather than muting for a whole window
-- (the engagewatch debounce rule).
function M.pump(now, reads)
    if M.subscriberCount() == 0 then return nil; end
    now = tonumber(now) or M._now();
    if _lastAt ~= nil then
        local since = now - _lastAt;
        if since >= 0 and since < M.TICK_S then return nil; end
    end
    _lastAt = now;

    local edges = _inbox;
    _inbox = {};

    local st = M.fromReads((type(reads) == 'table') and reads or M.reads, _prevT, edges);
    st.at = now;

    -- Remember the target for the NEXT beat's poll witness. Only a target we
    -- actually read is remembered -- a beat with no target must not make the
    -- following beat look like a change.
    if st.targetIndex ~= nil then _prevT = st.targetIndex; end
    -- Disengaged: the engagement's history dies with it, so the first target of
    -- the next fight is never "a change" from the last fight's mob.
    if st.engaged ~= true then _prevT = nil; end

    _last = st;
    for _, cb in pairs(_subs) do pcall(cb, st); end
    return st;
end

return M;
