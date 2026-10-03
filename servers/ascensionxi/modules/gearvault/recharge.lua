-- Read-only EXP band preflight (0x1E0 / 0x4C, HELLO capability 16).
-- Only an explicit click sends the existing !vault charge_exp_band command.
local vc = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\vaultclient');
local transport = require('dlac\\servers\\ascensionxi\\transport');
local M = { OP = 0x4C };
M._clock = transport._clock;
M._send = function(packet) return transport.send(packet, 'EXP band status'); end;
M._received = transport.received;
M._abandon = transport.abandon;
M._command = function() AshitaCore:GetChatManager():QueueCommand(1, '/say !vault charge_exp_band'); end;
M._distance = function()
    local watch = require('dlac\\lib\\entwatch');
    watch.watch('expRingRecharge', 'Gear Vault');
    return watch.nearest('Gear Vault');
end;

local bands = {
    [15761] = { name = 'Chariot Band', label = 'Chariot', rate = 50 },
    [15762] = { name = 'Empress Band', label = 'Empress', rate = 100 },
    [15763] = { name = 'Emperor Band', label = 'Emperor', rate = 200 },
};
local reasons = {
    [1] = 'Finish your current activity before recharging the ring.',
    [2] = 'Your weekly EXP band purchase or recharge allowance has already been used. Wait for the next conquest tally.',
    [3] = 'Unequip your EXP band and finish using it before recharging.',
    [4] = 'Your EXP band is already fully charged.',
    [5] = 'You do not have enough Conquest Points to recharge your EXP band.',
    [6] = 'Put the band in your Gear Vault or a Mog Wardrobe to recharge it.',
    [7] = 'The server could not check recharge eligibility. Try again shortly.',
};
local snapshot, pending, due, demand, failure;
local actionUntil = 0;
local token = os.time() % 4294967296;
local function u16(data, i) return data:byte(i) + data:byte(i + 1) * 256; end
local function u32(data, i) return u16(data, i) + u16(data, i + 2) * 65536; end
local function p32(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256);
end

function M.reset()
    if pending then M._abandon(M.OP, pending.token % 256); end
    snapshot, pending, due, demand, failure = nil, nil, nil, nil, nil;
end

function M.refresh(row)
    M.reset();
    if row and not bands[row.id] then return; end
    demand = M._clock();
    due = math.max(demand, actionUntil);
end

function M.pump(ready)
    local now = M._clock();
    if pending and now - pending.at >= 5 then
        M._abandon(M.OP, pending.token % 256);
        pending, snapshot = nil, nil;
        failure, due = 'The server did not answer the recharge check. Try again shortly.', now + 5;
    end
    if not ready or vc.zoning() or not vc.limits or not vc.limits.expBandStatus
        or pending or not demand or now - demand > 0.5 or (due and now < due) then return; end
    token = (token + 1) % 4294967296;
    if M._send(vc.buildFrame(M.OP, token % 256, p32(token))) then
        pending = { token = token, at = now };
        due = now + 2;
    end
end

-- Consume only this op. Validate the full nonce before releasing the shared
-- transport slot; another addon's reply or a late pre-zone frame is not ours.
function M.onPacket(data)
    if type(data) ~= 'string' or #data < 8 or data:byte(5) ~= M.OP then return false; end
    if not pending or data:byte(6) ~= pending.token % 256 then return true; end
    local size = math.floor(u16(data, 1) / 512) * 4;
    if #data < size or data:byte(8) ~= 0 then return true; end
    local code = data:byte(7);
    if code == 0 then
        if size ~= 16 or u32(data, 9) ~= pending.token or data:byte(15) > 7 or data:byte(16) > 1 then return true; end
        snapshot = { itemId = u16(data, 13), reason = data:byte(15), near = data:byte(16) == 1, at = M._clock() };
        failure = nil;
    elseif size == 8 then
        snapshot = nil;
        failure = code == 7 and 'Complete The Deeper Room to unlock Gear Vault recharge.'
            or ((code == 1 or code == 6) and 'This server does not yet support recharge status.'
            or 'The server could not check recharge eligibility. Try again shortly.');
        due = M._clock() + 5;
    else return true; end
    M._received(M.OP, pending.token % 256);
    pending = nil;
    return true;
end

function M.check(row)
    local band = bands[row.id];
    if not band then return false, 'Only Chariot, Empress and Emperor Bands can be recharged at the Gear Vault.'; end
    local now = M._clock();
    demand = now;
    local why = {};
    if vc.zoning() then return false, 'Wait until zoning finishes.'; end
    if now < actionUntil then return false, 'Waiting for the recharge result...'; end
    if vc.state() == 'unattuned' then
        why[#why + 1] = 'Complete The Deeper Room to unlock Gear Vault recharge.';
    elseif not vc.limits then
        why[#why + 1] = 'Waiting for Gear Vault status.';
    elseif not vc.limits.expBandStatus then
        why[#why + 1] = 'This server does not yet support recharge status.';
    elseif not snapshot or now - snapshot.at > 3 then
        why[#why + 1] = failure or 'Checking recharge eligibility...';
    elseif snapshot.reason ~= 0 then
        why[#why + 1] = reasons[snapshot.reason];
    elseif snapshot.itemId ~= row.id then
        why[#why + 1] = 'The vault command would recharge another EXP band first.';
    end
    -- A live distance check closes the gap between a status reply and walking
    -- away. The server's 3D range check is also required before enabling.
    local distance = M._distance();
    if not distance or distance > 5 or (snapshot and not snapshot.near) then
        why[#why + 1] = 'Move within 5 yalms of a Gear Vault to recharge the ring.';
    end
    if #why > 0 then return false, table.concat(why, '\n'); end
    return true, string.format('Recharge missing charges for %d Conquest Points each. Uses your weekly EXP band allowance.', band.rate);
end

function M.recharge(row)
    local allowed = M.check(row);
    if not allowed then return false; end
    M._command();
    -- Never permit a second click against the successful preflight. Give the
    -- chat command time to settle before another read can enable the action.
    M.reset();
    actionUntil = M._clock() + 2;
    due = actionUntil;
    return true;
end

function M.extendMenu(rows)
    if not vc.mirror.fresh then return; end
    local have = {};
    for _, row in ipairs(rows) do have[row.id or 0] = true; end
    for _, id in ipairs({ 15761, 15762, 15763 }) do
        local band = bands[id];
        if not have[id] and (vc.mirror.counts[id] or 0) > 0 then
            rows[#rows + 1] = { id = id, name = band.name, label = band.label, grp = 'xp',
                owned = true, avail = false, where = 'Gear Vault', rem = 0, maxch = 0 };
        end
    end
end

return M;
