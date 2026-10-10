-- Shared 0x1E0 send gate: vault pages, edits, retries, HELM and ascension
-- polls all spend the same budget. Callers retain pending work when send
-- returns false.
--
-- ONE request awaits a reply at a time. The server drops a second 0x1E0 that
-- reaches it within 50 ms of the last one it accepted, and everything
-- injected during one client flush rides ONE datagram -- so a request that
-- waits for the previous reply can never share its datagram. That rule keeps
-- frames apart; MIN_GAP is only a margin after the reply. It was 0.35 s until
-- 2026-09-30 and cost two thirds of every chained read in the field logs
-- (docs/design/gear-vault-live-sync.md).
--
-- The AutoAcc transport rules this gate follows (ascensionxi-combat-
-- telemetry-autoacc.md): T1 -- only the reply to THE pending request frees
-- the slot and restarts the gap; a frame nobody is waiting for (a late
-- duplicate, a second frame of a multi-frame reply, another addon's reply)
-- changes nothing. T2 -- server pushes never come through received() at all
-- (the vault client routes them past it; notePush only logs them). T3 -- a
-- caller that gave up abandons its request instead of holding every other
-- module for MAX_WAIT. T4 -- fair turns: the module that has waited longest
-- sends next (the "line", below).
--
-- Another addon on 0x1E0 (Nexus) spends the same 50 ms server budget: a
-- request of ours that lands right behind one of its packets is dropped.
-- The 2026-10-01 field round lost a login LAYOUT_LIST2 that way (one
-- "Rate-limiting packet GP_CLI_COMMAND_VOID_STORAGE", a 2.5 s retry). Nexus
-- already waits LISTEN_GAP after any 0x1E0 that is not its own; this gate
-- now does the same: FOREIGN_GAP after one it did not send.
--
-- STALE_WAIT is how long a module keeps its place in line without asking
-- again. The slowest asker retries a refused request every 0.35 s (HELM,
-- digging, ascension); the vault and the EXP band check ask every frame.
-- 1 s is nearly three of those retries, so a frame hitch does not cost a
-- module its place, while a module that stopped asking (its panel closed)
-- holds the others back for at most 1 s.
local M = { MIN_GAP = 0.1, MAX_WAIT = 8, FOREIGN_GAP = 0.3, STALE_WAIT = 1.0 };
local unpack = table.unpack or unpack;
local ok, socket = pcall(require, 'socket');
-- Wall time, never frame count (uncapped FPS) or process CPU time.
M._clock = ok and socket.gettime or os.time;
M._send = function(packet)
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x1E0, packet);
    return true;
end;
local last, pending, answered;
local recent = {};   -- our last few frames, from the op byte on (the header is the client's)
local foreignAt;     -- when another addon's 0x1E0 last went out
-- T4: producer -> { who, since = start of its wait (false: not waiting),
-- at = its latest try, said = this wait's yield line is written }
local line = {};
M._audit = function(event, op, seq, why, now)
    local root = require('dlac\\profiles').dataDir();
    if not root then return; end
    local dir = root .. 'debug\\';
    if ashita and ashita.fs then ashita.fs.create_directory(dir); end
    local path = dir .. 'gear-vault-wire.log';
    local f = io.open(path, 'a');
    if not f then return; end
    if (f:seek('end') or 0) > 2 * 1024 * 1024 then
        f:close(); os.remove(path .. '.previous'); os.rename(path, path .. '.previous');
        f = io.open(path, 'a'); if not f then return; end
    end
    f:write(string.format('%s %.6f %s op=%02X seq=%d %s\n',
        os.date('%Y-%m-%d %H:%M:%S'), now, event, op or 0, seq or 0, why or ''));
    f:close();
end;
local function audit(event, op, seq, why, now)
    if M._audit then pcall(M._audit, event, op, seq, why, now); end
end

-- An inbound frame in a caller's band. Returns true when it answered THE
-- pending request (T1); anything else is logged and changes no timing.
function M.received(op, seq)
    local now = M._clock();
    if pending and pending.op == op and pending.seq == seq then
        audit('reply', op, seq, pending.why, now);
        answered = { op = op, seq = seq, why = pending.why };
        pending = nil;
        last = now;   -- measured AFTER the server saw the preceding request
        return true;
    end
    if answered and answered.op == op and answered.seq == seq then
        audit('frame', op, seq, answered.why, now);   -- a later frame of the same reply
    else
        audit('stray', op, seq, nil, now);
    end
    return false;
end

-- T2: a server push (seq 0, an op no client sends) is logged, never matched.
function M.notePush(op, why)
    audit('push', op, 0, why, M._clock());
end

-- T3: the caller gave up on this request (retries spent, cancelled): free the
-- slot now. A reply that still arrives later is a stray and changes nothing.
function M.abandon(op, seq)
    if pending and pending.op == op and pending.seq == seq then
        audit('abandon', op, seq, pending.why, M._clock());
        pending = nil;
    end
end

-- Every 0x1E0 the client sends (packet_out): one we did not send holds our
-- next send for FOREIGN_GAP. Ours are recognised by their bytes after the
-- 4-byte header, as Nexus recognises its own.
function M.noteOutgoing(id, data)
    if id ~= 0x1E0 or type(data) ~= 'string' then return; end
    local body = data:sub(5);
    for i = #recent, 1, -1 do
        if body:sub(1, #recent[i]) == recent[i] then return; end
    end
    foreignAt = M._clock();
    audit('foreign', data:byte(5), data:byte(6), nil, foreignAt);
end

local function foreignQuiet(now)
    return foreignAt == nil or now - foreignAt >= M.FOREIGN_GAP;
end

-- T4: which producer (module) is asking. A module is known by the op
-- partition its packet uses (packet[5]; the server's channel registry
-- assigns the partitions). The EXP band check (0x4C) sits inside the vault's
-- band but is its own module with its own pending request, so it takes its
-- own turns. Any other op is a producer of its own.
function M.producerOf(op)
    if type(op) ~= 'number' then return 'unknown'; end
    if op == 0x4C then return 'EXP band'; end
    if op >= 0x40 and op <= 0x7F then return 'vault'; end
    if op == 0x80 then return 'HELM'; end
    if op == 0x81 then return 'digging'; end
    if op >= 0xA0 and op <= 0xAF then return 'ascension'; end
    if op >= 0xC0 and op <= 0xCF then return 'telemetry'; end
    if op >= 0xD0 and op <= 0xDF then return 'whm gauge'; end
    return op;
end

local function nameOf(who)
    return type(who) == 'number' and string.format('op %02X', who) or tostring(who);
end

-- T4, the line. Each module asks on its own clock (the vault every frame,
-- HELM, digging and ascension 0.35 s after a refusal), so "whoever asks
-- first once the gap is spent" let the vault's paging hold the others back.
-- Now a refused NEW request puts its module in line, and when the gap and
-- the slot allow a new request, only the module that has waited longest,
-- among those still asking, may send it. The others get the same false a
-- busy slot gives them.

-- In line: refused since `since`, not granted yet, and still asking.
local function live(turn, now)
    return turn.since ~= false and now - turn.at < M.STALE_WAIT;
end

-- A NEW request joins its module's place in line: the wait counts from its
-- first refusal, or starts again at the back when the module had stopped
-- asking. A retry of THE pending request holds the slot already, so it never
-- waits its turn and never joins the line: nil.
local function queue(op, seq, now)
    if pending ~= nil and pending.op == op and pending.seq == seq and now - pending.at < M.MAX_WAIT then
        return nil;
    end
    local who = M.producerOf(op);
    local turn = line[who];
    if turn == nil then
        turn = { who = who, since = false, at = 0, said = false };
        line[who] = turn;
    end
    if not live(turn, now) then turn.since, turn.said = now, false; end
    turn.at = now;
    return turn;
end

-- The front of the line, when it is not `turn`: the producer still asking
-- that began to wait earliest, and before `since`. Equal waits go to
-- whichever asks first.
local function aheadOf(turn, since, now)
    local front;
    for _, t in pairs(line) do
        if t ~= turn and live(t, now) and t.since < since and (front == nil or t.since < front.since) then
            front = t;
        end
    end
    return front;
end

function M.send(packet, why)
    local now = M._clock();
    local op, seq = packet[5], packet[6] or 0;
    local turn = queue(op, seq, now);
    if last and now - last < M.MIN_GAP then return false; end
    if not foreignQuiet(now) then return false; end
    if pending then
        if now - pending.at >= M.MAX_WAIT then
            audit('expired', pending.op, pending.seq, pending.why, now);
            pending = nil;
        elseif pending.op ~= op or pending.seq ~= seq then
            return false;
        end
    end
    if turn ~= nil then
        local front = aheadOf(turn, turn.since, now);
        if front ~= nil then
            if not turn.said then
                turn.said = true;
                audit('yield', op, seq, tostring(why) .. ' -- behind ' .. nameOf(front.who), now);
            end
            return false;
        end
        -- Its turn, whatever the packet manager does with the frame: a module
        -- whose sends always fail must not stay first in line for ever.
        turn.since = false;
    end
    last = now;
    -- Remembered BEFORE the send: Ashita runs packet_out inside
    -- AddOutgoingPacket, so noteOutgoing sees the frame before _send returns
    -- (the first build of this marked every one of our own sends foreign).
    recent[#recent + 1] = string.char(unpack(packet, 5));
    if #recent > 8 then table.remove(recent, 1); end
    local sent, result = pcall(M._send, packet);
    if not sent or result == false then table.remove(recent); return false; end
    pending = { op = op, seq = seq, at = now, why = why };
    audit('enqueue', op, seq, why, now);
    pcall(function() require('dlac\\feature\\sendlog').note(0x1E0, why); end);
    return true;
end

-- Would a NEW request go right now: no reply awaited, the gap spent, and
-- nobody ahead in line (T4)? `op`, a packet's op byte, asks for that module,
-- whose own wait counts; without it the answer is for a module not waiting,
-- which every module still waiting is ahead of.
function M.idle(op)
    local now = M._clock();
    if last and now - last < M.MIN_GAP then return false; end
    local turn = op ~= nil and line[M.producerOf(op)] or nil;
    local since = (turn ~= nil and live(turn, now)) and turn.since or now;
    if aheadOf(turn, since, now) ~= nil then return false; end
    if not foreignQuiet(now) then return false; end
    return pending == nil or now - pending.at >= M.MAX_WAIT;
end

function M._reset() last, pending, answered, foreignAt = nil, nil, nil, nil; recent = {}; line = {}; end

-- In game only (the suites drive noteOutgoing directly).
if ashita ~= nil and ashita.events ~= nil then
    pcall(ashita.events.register, 'packet_out', 'dlac_axi_transport_foreign', function(e)
        pcall(M.noteOutgoing, e.id, e.data_modified or e.data);
    end);
end
return M;
