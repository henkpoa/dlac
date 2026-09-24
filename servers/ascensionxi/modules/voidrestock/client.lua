-- Void Storage protocol v1 (server void_storage.lua): ops 0x00..0x05.
-- All traffic shares AscensionXI's transport gate with Gear Vault and HELM.
-- Moves are never retried: an unanswered mutation has an unknown outcome.
local transport = require('dlac\\servers\\ascensionxi\\transport');
local M = { counts = {}, fresh = false, message = 'Visit Void Storage to refresh stock.' };
M._clock, M._send, M._received = transport._clock, transport.send, transport.received;
local pending, page, proto, seq = nil, nil, nil, os.time() % 256;
local statusText = { [1] = 'Unsupported request', [2] = 'Malformed request', [3] = 'Busy',
    [4] = 'Move closer to Void Storage', [5] = 'Void Storage unavailable',
    [6] = 'Unsupported protocol', [7] = 'Void Storage is not unlocked' };
M.reasons = { [0] = 'OK', [1] = 'Not storable', [2] = 'Storage tier locked',
    [3] = 'Not held or item busy', [4] = 'No stored stock', [5] = 'Inventory full',
    [6] = 'Unknown item', [7] = 'Duplicate scroll sold by Void Storage', [8] = 'Rare item already held' };
local function u16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256; end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536; end
local function w16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function frame(op, token, body)
    local p = { 0, 0, 0, 0, op, token, 0, 0 };
    for i = 1, #body do p[#p + 1] = body:byte(i); end
    while #p % 4 ~= 0 do p[#p + 1] = 0; end
    return p;
end
function M.busy() return pending ~= nil or page ~= nil; end
function M.reset()
    pending, page, proto = nil, nil, nil;
    M.counts, M.fresh, M.tierMask = {}, false, nil;
    M.message = 'Visit Void Storage to refresh stock.';
end
local function fail(why)
    local cb = pending and pending.done;
    pending, page, M.fresh = nil, nil, false;
    M.message = why;
    if cb then cb(nil, why); end
end
local function send(op, body, done)
    local nextSeq = (seq + 1) % 256;
    if M._send(frame(op, nextSeq, body), 'Void Restock') == false then return false; end
    seq = nextSeq;
    pending = { op = op, seq = seq, at = M._clock(), done = done };
    return true;
end
function M.refresh()
    if M.busy() then return false; end
    proto = nil; -- Refresh also re-reads KI unlocks, not just item balances.
    M.fresh, page = false, { cursor = 0, counts = {}, at = M._clock() };
    M.message = 'Refreshing Void Storage...';
    return true;
end
function M.move(kind, id, qty, done)
    if M.busy() or not M.fresh or not proto then return false; end
    if (kind ~= 'store' and kind ~= 'fetch') or type(id) ~= 'number' or id < 1 or id >= 65535
        or id ~= math.floor(id) or type(qty) ~= 'number' or qty < 1 or qty > 65535
        or qty ~= math.floor(qty) then return false; end
    -- Exactly ONE explicit item. An empty DEPOSIT means sweep-all on the
    -- server and must never be used by the list-based helper.
    if not send(kind == 'store' and 1 or 2, w16(1) .. w16(0) .. w16(id) .. w16(qty), done) then return false; end
    pending.id, pending.qty, pending.kind = id, qty, kind;
    return true;
end
function M.tick()
    if pending then
        if M._clock() - pending.at >= 6 then fail('No reply; stopped. Refresh stock before trying again.'); end
        return;
    end
    if page then
        if M._clock() - page.at > 30 then fail('Storage refresh timed out. Try Refresh stock again.'); return; end
        if not proto then send(0, w16(1) .. w16(0));
        else send(4, w16(page.cursor) .. w16(65535)); end
    end
end
function M.onPacket(data)
    if type(data) ~= 'string' or #data < 8 then return false; end
    local op, token, status, flags = data:byte(5, 8);
    if op > 5 then return false; end -- never consume Gear Vault / HELM
    if not pending or op ~= pending.op or token ~= pending.seq then return true; end
    local size = math.floor(u16(data, 0) / 512) * 4;
    if size < 8 or size > #data then fail('Invalid Void Storage reply; stopped.'); return true; end
    local body = data:sub(9, size);
    if status ~= 0 then
        M._received(op, token); fail(statusText[status] or 'Void Storage refused the request'); return true;
    end
    if op == 0 then
        if #body < 12 or u16(body, 0) ~= 1 or body:byte(9) < 1 or body:byte(10) < 1 or flags ~= 0 then
            fail('Invalid Void Storage handshake'); return true;
        end
        M.tierMask = u32(body, 4);
        proto = true; pending = nil;
    elseif op == 4 then
        if not page or #body < 4 then fail('Invalid storage page'); return true; end
        local count = u16(body, 0);
        if count > 61 or #body < 4 + count * 8 or flags > 1 then fail('Invalid storage page'); return true; end
        for i = 0, count - 1 do
            local id = u16(body, 4 + i * 8);
            if id <= page.cursor or id >= 65535 then fail('Invalid storage cursor'); return true; end
            page.cursor = id; page.counts[id] = u32(body, 8 + i * 8);
        end
        if flags == 1 and count == 0 then fail('Empty continuation page'); return true; end
        pending = nil;
        if flags == 0 then
            M.counts, M.fresh, page = page.counts, true, nil;
            M.message = 'Void Storage stock refreshed.';
        end
    else
        -- One requested item => one ACK entry, no continuation. The moved
        -- count is authoritative; a partial/refusal stops the caller's batch.
        if #body < 16 or u16(body, 0) ~= 1 or flags ~= 0
            or u16(body, 8) ~= pending.id or u16(body, 10) ~= pending.qty
            or u16(body, 12) > pending.qty then fail('Invalid move reply; refresh before retrying.'); return true; end
        local moved, reason, cb = u16(body, 12), u16(body, 14), pending.done;
        local id, kind = pending.id, pending.kind;
        local count = M.counts[id] or 0;
        if kind == 'fetch' then M.counts[id] = math.max(0, count - moved);
        elseif reason ~= 7 then M.counts[id] = count + moved; end
        pending = nil;
        M._received(op, token);
        if cb then cb({ moved = moved, reason = reason, gil = u32(body, 4) }); end
        return true;
    end
    M._received(op, token);
    return true;
end
return M;
