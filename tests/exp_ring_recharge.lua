-- lua tests/exp_ring_recharge.lua
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local vc = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\vaultclient');
local recharge = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\recharge');
local now, distance, sent, packet, commands, received, abandoned = 100, 2, 0, nil, 0, 0, 0;
recharge._clock = function() return now; end;
recharge._distance = function() return distance; end;
recharge._send = function(p) packet = p; sent = sent + 1; return true; end;
recharge._received = function() received = received + 1; end;
recharge._abandon = function() abandoned = abandoned + 1; end;
recharge._command = function() commands = commands + 1; end;
local ring = { id = 15762 };
local function p16(n) return string.char(n % 256, math.floor(n / 256)); end
local function reply(reason, near, id, req)
    req = req or packet;
    return string.char(0xE0, 0x09, 0, 0, recharge.OP, req[6], 0, 0)
        .. string.char(req[9], req[10], req[11], req[12]) .. p16(id or ring.id)
        .. string.char(reason or 0, near == false and 0 or 1);
end
local function check(text)
    local allowed, reason = recharge.check(ring);
    assert(not allowed and reason:find(text, 1, true), reason);
end
local function refresh(reason, near, id)
    recharge.refresh(); recharge.check(ring); recharge.pump(true);
    assert(recharge.onPacket(reply(reason, near, id)));
end

assert(dofile('servers/ascensionxi/features.lua').menu.teleports == true);
assert(vc.parseHello(p16(1) .. p16(16) .. string.rep('\0', 8)).expBandStatus == true);
assert(vc.parseHello(p16(1) .. p16(0) .. string.rep('\0', 8)).expBandStatus == false);
check('Waiting for Gear Vault status');
vc.limits = { expBandStatus = false };
check('does not yet support'); recharge.pump(true); assert(sent == 0);
vc.limits.expBandStatus = true;
check('Checking recharge eligibility'); recharge.pump(false); assert(sent == 0);
recharge.pump(true); assert(sent == 1 and #packet == 12);
local first = packet;
local good = reply(0);
assert(recharge.onPacket(good:sub(1, 15))); check('Checking');
assert(recharge.onPacket(good:sub(1, 8) .. '\0\0\0\0' .. good:sub(13))); check('Checking');
assert(received == 0, 'malformed/stale nonce must not free transport');
assert(recharge.onPacket(good .. string.rep('\0', 496)));
assert(recharge.check(ring)); assert(received == 1);
assert(recharge.recharge(ring)); assert(commands == 1);
assert(not recharge.recharge(ring) and commands == 1, 'double click cannot reuse ready status');
recharge.refresh(); recharge.check(ring); recharge.pump(true);
assert(sent == 1, 'reopening the menu cannot skip the post-command hold');
now = now + 2;

refresh(2, false); distance = 10;
check('weekly EXP band'); check('within 5 yalms');
assert(not recharge.recharge(ring) and commands == 1);
distance = 2;
refresh(0, false); check('within 5 yalms');
refresh(0); distance = 5.01; check('within 5 yalms');
distance = 5; assert(recharge.check(ring), 'five-yalm boundary included');
for code, text in pairs({ [1] = 'current activity', [3] = 'Unequip', [4] = 'fully charged',
    [5] = 'enough Conquest Points', [6] = 'Mog Wardrobe', [7] = 'could not check' }) do
    refresh(code); check(text);
end
refresh(0, true, 15761); check('another EXP band first');
assert(not recharge.check({ id = 28562 }), 'unsupported XP ring cannot recharge');
local sentBeforeUnsupported = sent;
recharge.refresh({ id = 28562 }); recharge.pump(true);
assert(sent == sentBeforeUnsupported, 'unsupported rings do not query the server');
refresh(0); now = now + 4; check('Checking');
recharge.pump(true); local old = packet;
recharge.reset(); recharge.onPacket(reply(0, true, ring.id, old)); check('Checking');
assert(abandoned > 0, 'zoning abandons pending request');
recharge.pump(true); now = now + 5; recharge.pump(true); check('did not answer');
recharge.refresh(); recharge.check(ring); recharge.pump(true);
recharge.onPacket(string.char(0xE0, 5, 0, 0, recharge.OP, packet[6], 7, 0));
check('The Deeper Room');

vc.mirror = { fresh = true, counts = { [15761] = 1, [15762] = 1, [15763] = 1 } };
local rows = { ring }; recharge.extendMenu(rows);
assert(#rows == 3 and rows[2].where == 'Gear Vault' and not rows[2].avail);
vc.mirror.fresh = false; rows = {}; recharge.extendMenu(rows); assert(#rows == 0);

-- Real context renderer: normal CEXI rows have no action, disabled AXI rows
-- stay inert, and only the enabled menu selection invokes the service.
local sp = require('dlac\\gear\\serverpack');
local drawn, opened, clicks, enabled = {}, 0, 0, false;
package.loaded.imgui = {
    IsItemHovered = function() return true; end, IsMouseClicked = function(n) return n == 1; end,
    OpenPopup = function() opened = opened + 1; end, BeginPopup = function() return true; end,
    EndPopup = function() end, CloseCurrentPopup = function() end,
    TextDisabled = function(s) drawn[#drawn + 1] = s; end,
    TextWrapped = function(s) drawn[#drawn + 1] = s; end,
    Selectable = function() clicks = clicks + 1; return true; end,
};
local ui = require('dlac\\ui\\rechargeui');
ui.render(ring, 'x1'); assert(opened == 0, 'CEXI has no recharge service');
sp.provide('expRingRecharge', {
    refresh = function() end,
    check = function() return enabled, 'weekly recharge used\nwithin 5 yalms'; end,
    recharge = function() commands = commands + 1; end,
});
ui.render(ring, 'x1'); assert(opened == 1 and clicks == 0 and commands == 1);
assert(drawn[1] == 'Recharge ring' and drawn[2]:find('within 5 yalms', 1, true));
enabled = true; ui.render(ring, 'x1'); assert(clicks == 1 and commands == 2);
print('EXP ring recharge: client eligibility, packets, storage and context menu passed');
