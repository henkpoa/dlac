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
-- module for MAX_WAIT.
local M = { MIN_GAP = 0.1, MAX_WAIT = 8 };
local ok, socket = pcall(require, 'socket');
-- Wall time, never frame count (uncapped FPS) or process CPU time.
M._clock = ok and socket.gettime or os.time;
M._send = function(packet)
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x1E0, packet);
    return true;
end;
local last, pending, answered;
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

function M.send(packet, why)
    local now = M._clock();
    if last and now - last < M.MIN_GAP then return false; end
    local op, seq = packet[5], packet[6] or 0;
    if pending then
        if now - pending.at >= M.MAX_WAIT then
            audit('expired', pending.op, pending.seq, pending.why, now);
            pending = nil;
        elseif pending.op ~= op or pending.seq ~= seq then
            return false;
        end
    end
    last = now;
    local sent, result = pcall(M._send, packet);
    if not sent or result == false then return false; end
    pending = { op = op, seq = seq, at = now, why = why };
    audit('enqueue', op, seq, why, now);
    pcall(function() require('dlac\\feature\\sendlog').note(0x1E0, why); end);
    return true;
end

-- Is the channel free for a NEW request right now (no reply awaited, gap spent)?
function M.idle()
    local now = M._clock();
    if last and now - last < M.MIN_GAP then return false; end
    return pending == nil or now - pending.at >= M.MAX_WAIT;
end

function M._reset() last, pending, answered = nil, nil, nil; end
return M;
