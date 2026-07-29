--[[
    dlac/feature/engagewatch.lua -- the ENGAGE / TARGET EDGE service (issue #139,
    PRD #135). ONE question, in the Central-services shape:

        "Did I just engage something, or roll my target onto something else --
         and exactly WHICH entity?"

        engagewatch.lastEdge()        -> { kind, index, serverId, name, at } | nil
        engagewatch.subscribe(who,cb) -> push the same record as it happens

    A dlac EDGE is one outgoing action packet the player's own client sent:

        0x01A category 0x02  ->  'engage'    (you attacked something)
        0x01A category 0x0F  ->  'retarget'  (your battle target changed while
                                              engaged -- auto-target rolling to
                                              the next mob is exactly this)

    The entity is taken FROM THE PACKET (UniqueNo u32 @0x04 = server id,
    ActIndex u16 @0x08 = entity index), never re-derived at consumption time from
    "what am I targeting now" -- that read has already moved on by the time a
    subscriber acts, and sending a pet at the wrong mob is the failure this
    service exists to prevent.

    Per-TARGET DEBOUNCE (M.DEBOUNCE_S, 5s): the client re-sends 0x01A on lag and
    a target can stutter, so the same entity notifies at most once per window
    while a DIFFERENT entity notifies immediately. That is the whole spam story --
    subscribers are fire-and-forget and never retry (PRD: "a server refusal is not
    retried until the next real edge").

    THREADING (the chocowatch rule, paid for by the dlacprobe crash): the
    packet_out handler runs on the NETWORK thread, so it does the bare minimum --
    decode three integers and append to a queue. Everything else (debounce, the
    entity-name read, the subscriber callbacks) runs on the MAIN thread in
    M.pump(), which dlac.lua calls from d3d_present beside the Action sequencer's.

    House shape: pure cores -- decode / targetKey / debounceCore -- take bytes and
    numbers and answer with no AshitaCore, so the recorded-byte replays and the
    debounce drive headlessly (tests EDG*). The live reads (entity name) and the
    packet registration are injectable / guarded at the bottom.

    NOTE on the reference implementation: the field-proven decode of these two
    edges is `accwatch.lua`'s `/dl acc` engage watch (history.md, "ACC calculator
    -> acc watch": *"Every engage (0x01A action 0x02) AND battle-target switch
    (action 0x0F, auto-target)"*), which ships live on the parked
    `feature/autoacc` branch pending GM approval; its inert, byte-identical dev
    copy sits at `share/mob-stats/accwatch.lua` as REFERENCE ONLY (never loaded).
    THIS module is the one live shared implementation: when autoacc lands,
    accwatch subscribes here rather than carrying a second copy.
]]--

local M = {};

-- The outgoing action packet and the two categories that are edges. Named
-- constants because a bare 0x0F in a consumer is unreadable; the byte offsets
-- are the TWIN of feature\equipengine's parseAction (target @0x08, category
-- @0x0A) -- the same packet, read for a different question.
M.PKT_ACTION   = 0x01A;
M.CAT_ENGAGE   = 0x02;
M.CAT_RETARGET = 0x0F;

-- The per-target debounce window, seconds (PRD: "a 5-second same-target
-- debounce"). Same entity inside the window: silent. Different entity: fires.
M.DEBOUNCE_S = 5.0;

-- The network thread only ever appends here, and the main-thread pump drains it
-- every frame; the cap exists so a pump that stopped running (a torn frame, an
-- unloaded UI) can never grow the queue without bound. Oldest is dropped.
M.QUEUE_MAX = 8;

-- ---------------------------------------------------------------------------
-- pure byte readers (little-endian, the FFXI packing)
-- ---------------------------------------------------------------------------
--
-- Local rather than borrowed from equipengine on purpose: this is a packet
-- WATCHER (the chocowatch / fishwatch / craftwatch pattern -- each owns its
-- readers) and a central service must not drag the timing engine in behind it.
-- Past the end reads as zeros, so a short/torn packet decodes to nothing real.

local function u16at(str, byteOff)
    local a = string.byte(str, byteOff + 1) or 0;
    local b = string.byte(str, byteOff + 2) or 0;
    return a + b * 256;
end

local function u32at(str, byteOff)
    return u16at(str, byteOff) + u16at(str, byteOff + 2) * 65536;
end

M._u16at = u16at;   -- test seams (the replay fixtures assert the readers too)
M._u32at = u32at;

-- ---------------------------------------------------------------------------
-- the pure decode: recorded bytes -> an edge, or nil
-- ---------------------------------------------------------------------------
--
-- GP_CLI_COMMAND_ACTION (outgoing 0x01A), 16 bytes:
--   0x00 u16 id|size   0x02 u16 sync
--   0x04 u32 UniqueNo  -- the target's SERVER id (stable across index reuse)
--   0x08 u16 ActIndex  -- the target's ENTITY index
--   0x0A u16 Category  -- 0x02 engage / 0x0F change target
--   0x0C u16 Param
-- Anything shorter than 0x0C bytes cannot carry a category: nil, never a guess.
function M.decode(data)
    if type(data) ~= 'string' or #data < 12 then return nil; end
    local cat = u16at(data, 0x0A);
    -- Plain if/else, never `(x) and 'a' or nil` -- the documented ternary trap.
    local kind = nil;
    if cat == M.CAT_ENGAGE then
        kind = 'engage';
    elseif cat == M.CAT_RETARGET then
        kind = 'retarget';
    end
    if kind == nil then return nil; end
    return {
        kind     = kind,
        category = cat,
        index    = u16at(data, 0x08),
        serverId = u32at(data, 0x04),
    };
end

-- The debounce KEY for an edge: the server id when the packet carried one (it
-- survives entity-slot reuse), else the entity index. nil when the packet named
-- NO entity -- a target cleared to nothing is not an edge any consumer can act
-- on, and it must never take a debounce slot.
function M.targetKey(edge)
    if type(edge) ~= 'table' then return nil; end
    local sid = tonumber(edge.serverId) or 0;
    if sid > 0 then return 'id:' .. string.format('%d', sid); end
    local idx = tonumber(edge.index) or 0;
    if idx > 0 then return 'ix:' .. string.format('%d', idx); end
    return nil;
end

-- Pure debounce: given the edge, the clock and the seen-table, may this edge
-- notify? Returns accepted(bool), key. A clock that went BACKWARDS (os.clock
-- across a reset) accepts rather than muting for a whole window.
--
-- The key is the TARGET ALONE, not (target, kind) -- the PRD says "a per-target
-- debounce", and this is that, literally. ONE consequence is worth knowing
-- before the field round: a retarget edge onto a mob mutes an ENGAGE edge on the
-- same mob for the rest of the window, so a player in "When I attack" who lets
-- auto-target roll onto a mob and then disengages and re-engages it inside 5
-- seconds gets no send. Keying on (target, kind) would close that and would
-- still swallow all real stutter (a client re-send is a byte-identical packet,
-- so always the same kind) -- flagged for the maintainer rather than taken
-- unilaterally, because the debounce shape is the design record's call.
function M.debounceCore(edge, now, seen, window)
    local key = M.targetKey(edge);
    if key == nil then return false, nil; end
    now = tonumber(now) or 0;
    window = tonumber(window) or M.DEBOUNCE_S;
    local last = tonumber((type(seen) == 'table') and seen[key] or nil);
    if last ~= nil then
        local since = now - last;
        if since >= 0 and since < window then return false, key; end
    end
    return true, key;
end

-- ---------------------------------------------------------------------------
-- state (the queue, the debounce table, the subscribers, the answer)
-- ---------------------------------------------------------------------------

local _queue = {};    -- edges stashed by the packet handler (network thread)
local _seen  = {};    -- [targetKey] = clock of the last ACCEPTED edge
local _subs  = {};    -- who -> cb
local _last  = nil;   -- the last ACCEPTED edge (what lastEdge() answers)

-- Subscribe to accepted edges. `who` names the consumer so a module can drop its
-- own subscription wholesale (the entwatch contract). cb(edge) is pcall'd -- a
-- throwing subscriber never costs another subscriber its notification.
function M.subscribe(who, cb)
    if type(who) ~= 'string' or who == '' then return false; end
    if type(cb) ~= 'function' then return false; end
    _subs[who] = cb;
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

-- The one exported question. nil until the first accepted edge this session.
function M.lastEdge() return _last; end

-- Drop everything (job change / logout / test reset). Subscribers survive a
-- reset(false); reset(true) drops them too.
function M.reset(dropSubs)
    _queue, _seen, _last = {}, {}, nil;
    if dropSubs == true then _subs = {}; end
end

-- ---------------------------------------------------------------------------
-- the network-thread half: decode + stash, nothing else
-- ---------------------------------------------------------------------------
--
-- No chat, no file IO, no entity reads, no callbacks -- the chocowatch rule.
-- Returns the stashed edge (tests read it), nil when the packet is not an edge.
function M.onPacket(data, now)
    local edge = M.decode(data);
    if edge == nil then return nil; end
    edge.at = tonumber(now) or 0;
    if #_queue >= M.QUEUE_MAX then table.remove(_queue, 1); end
    _queue[#_queue + 1] = edge;
    return edge;
end

-- ---------------------------------------------------------------------------
-- the main-thread half: debounce, name, notify
-- ---------------------------------------------------------------------------

-- The entity display name for an index, trimmed (GetName pads with whitespace --
-- the entwatch idiom) or nil. Injectable as a whole so the pump drives headless.
M._nameOf = function(index)
    local nm = nil;
    pcall(function()
        nm = AshitaCore:GetMemoryManager():GetEntity():GetName(index);
    end);
    if type(nm) ~= 'string' then return nil; end
    nm = (nm:gsub('%z', ''):gsub('%s+$', ''));
    if nm == '' then return nil; end
    return nm;
end;

-- Forget debounce entries far older than the window, so a long session's table
-- stays the size of "mobs fought recently" rather than "mobs fought".
function M._prune(now)
    now = tonumber(now) or 0;
    local horizon = M.DEBOUNCE_S * 4;
    for key, at in pairs(_seen) do
        if type(at) ~= 'number' or (now - at) > horizon then _seen[key] = nil; end
    end
end

local function notify(edge)
    for _, cb in pairs(_subs) do pcall(cb, edge); end
end

-- Drain the stash: debounce each edge, resolve its entity name, publish it and
-- notify. `now` overrides the per-edge packet stamp (tests); `nameOf` overrides
-- the entity read. Returns how many edges were ACCEPTED (0 = all debounced /
-- nothing queued), so a caller can cheaply tell "nothing happened".
function M.pump(now, nameOf)
    if #_queue == 0 then return 0; end
    local q = _queue;
    _queue = {};
    local reader = (type(nameOf) == 'function') and nameOf or M._nameOf;
    local accepted, latest = 0, nil;
    for _, edge in ipairs(q) do
        -- The debounce measures PACKET cadence, so it uses the stamp the network
        -- thread took, not the frame the pump happens to run on.
        local t = tonumber(now) or tonumber(edge.at) or 0;
        local ok, key = M.debounceCore(edge, t, _seen, M.DEBOUNCE_S);
        if ok and key ~= nil then
            _seen[key] = t;
            edge.at = t;
            edge.name = reader(edge.index);
            _last = edge;
            accepted = accepted + 1;
            latest = t;
            notify(edge);
        end
    end
    M._prune(latest or tonumber(now) or 0);
    return accepted;
end

-- ---------------------------------------------------------------------------
-- Ashita glue, guarded (headless: nothing registers, the pure halves ARE the
-- module -- the entwatch/chocowatch shape)
-- ---------------------------------------------------------------------------

pcall(function()
    ashita.events.register('packet_out', 'dlac-engagewatch-out', function(e)
        if e.id ~= M.PKT_ACTION then return; end
        -- Bare read + append. An INJECTED action packet is deliberately not
        -- filtered out: another addon engaging on the player's behalf is still a
        -- real edge, and a duplicate of our own is what the debounce is for.
        pcall(function() M.onPacket(e.data, os.clock()); end);
    end);
end);

return M;
