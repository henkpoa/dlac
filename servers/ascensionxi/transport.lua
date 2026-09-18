-- Shared 0x1E0 send gate: vault pages, edits, retries and HELM polls all
-- spend the same interval. Callers retain pending work when send returns false.
local M = { MIN_GAP = 0.35, MAX_WAIT = 8 };
local ok, socket = pcall(require, 'socket');
-- Wall time, never frame count (uncapped FPS) or process CPU time.
M._clock = ok and socket.gettime or os.time;
M._send = function(packet)
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x1E0, packet);
    return true;
end;
local last, pending;
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
function M.received(op, seq)
    local now = M._clock();
    last = now; -- measured AFTER the server saw the preceding request
    audit('reply', op, seq, pending and pending.why, now);
    if pending and pending.op == op and pending.seq == seq then pending = nil; end
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
function M._reset() last, pending = nil, nil; end
return M;
