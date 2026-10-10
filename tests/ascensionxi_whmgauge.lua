-- lua tests/ascensionxi_whmgauge.lua   (from the dlac repo root)
-- The AscensionXI White Mage flower gauge: the 0x1E0 ops 0xD0-0xDF client,
-- its packet budget (one subscribe per zone, nothing more), the stance trust
-- rule, the art (drawn into a recording draw list) and the demo loop.
-- Server contract: ascensionxi repo, documentation/custom/whm-flower-gauge.md.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);

local checks = 0;
local function check(cond, msg)
    checks = checks + 1;
    if not cond then error('FAIL: ' .. msg, 2); end
end

local sp = require('dlac\\gear\\serverpack');
sp._configLoader = function() return { server = 'ascensionxi' }; end;
sp.init();
local mounted = false;
for _, name in ipairs(sp.modules()) do if name == 'whmgauge' then mounted = true; end end
check(mounted, 'the AscensionXI pack mounts the whmgauge module');

local handlers = {};
ashita = { events = { register = function(kind, name, callback) handlers[name] = { kind = kind, fn = callback }; end } };

-- A stub imgui, loaded the way every dlac file loads it (require, never a
-- global): the first field round drew nothing because init.lua read a global.
local ui = { begins = 0, draws = 0, dummy = nil };
local stubDl = setmetatable({}, { __index = function() return function() ui.draws = ui.draws + 1; end; end });
package.loaded['imgui'] = {
    SetNextWindowPos = function() end,
    PushStyleVar = function() end,
    PopStyleVar = function() end,
    Begin = function(name) ui.begins = ui.begins + 1; ui.name = name; return true; end,
    End = function() end,
    GetCursorScreenPos = function() return 100, 200; end,
    Dummy = function(size) ui.dummy = size; end,
    IsItemHovered = function() return false; end,
    GetWindowDrawList = function() return stubDl; end,
    GetColorU32 = function() return 0xFFFFFFFF; end,
    SetTooltip = function() end,
    TextColored = function() end,
    GetWindowPos = function() return 100, 200; end,
};
local mod   = require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\init');
local gauge = require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\gauge');
local wire  = require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\wire');
local draw  = require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\draw');
local demo  = require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\demo');
local transport = require('dlac\\servers\\ascensionxi\\transport');
check(sp.service('whmGauge') == gauge, 'the module provides the whmGauge service');
check(type(mod.pump) == 'function', 'the module hands its beat to the servermods pump');
check(transport.producerOf(0xD0) == 'whm gauge' and transport.producerOf(0xD8) == 'whm gauge',
      'the shared gate knows the partition as its own producer');

-- ---------------------------------------------------------------------------
-- wire
-- ---------------------------------------------------------------------------
local S0 = { stance = 1, tier = 2, flowers = { 1, 2, 0 }, flags = 0x02 + 0x08, boost = 2,
             charge = 123, threshold = 280, rev = 65535 };
-- The shared vector: the server suite (ascensionxi repo,
-- scripts/tests/jobs/whm/flowers.lua WF-02) encodes these same 16 bytes.
local VECTOR = '01 03 01 02 01 02 00 0A 02 00 7B 00 18 01 FF FF';
local function hex(s)
    local out = {};
    for i = 1, #s do out[#out + 1] = string.format('%02X', s:byte(i)); end
    return table.concat(out, ' ');
end
local bytes = wire.encodeState(S0);
check(hex(bytes) == VECTOR, 'STATE matches the server test vector: ' .. hex(bytes));
check(#bytes == wire.STATE_SIZE, 'STATE is 16 bytes');
local back = wire.state(bytes);
check(back.stance == 1 and back.tier == 2 and back.flowers[1] == 1 and back.flowers[2] == 2
      and back.flowers[3] == 0 and back.boost == 2 and back.charge == 123 and back.threshold == 280
      and back.rev == 65535 and back.job == 3, 'STATE round-trips');
check(wire.hasFlag(back.flags, wire.flag.BOOST) and wire.hasFlag(back.flags, wire.flag.SEAL_READY)
      and not wire.hasFlag(back.flags, wire.flag.DARK_BANISH), 'flags decode bit by bit');
check(wire.state(bytes:sub(1, 15)) == nil, 'a short STATE is refused');
check(wire.state('\2' .. bytes:sub(2)) == nil, 'another protocol is refused');
local bad = bytes:sub(1, 2) .. '\9\7' .. '\4\200\3' .. bytes:sub(8);
local clamped = wire.state(bad);
check(clamped.stance == 0 and clamped.tier == 0 and clamped.flowers[1] == 0 and clamped.flowers[2] == 0
      and clamped.flowers[3] == 3, 'out-of-range stance and tiers clamp to nothing');
check(wire.newer(0, 65535) and wire.newer(5, 4) and not wire.newer(4, 5) and not wire.newer(7, 7),
      'rev comparison survives the wrap');
local sub = wire.subscribe(300, true);
check(#sub == 12 and sub[5] == 0xD0 and sub[6] == 300 % 256 and sub[9] == 1 and sub[10] == 1,
      'SUBSCRIBE: op 0xD0, seq, protocol 1, mode 1');
check(wire.subscribe(1, false)[10] == 0, 'stop = mode 0');
local f = wire.incoming(wire.s2cFrame(0xD8, 0, 0, bytes) .. string.rep('\0', 400));
check(f.op == 0xD8 and f.seq == 0 and #f.payload == 16 and f.payload == bytes,
      'incoming trims to the declared size');

-- ---------------------------------------------------------------------------
-- gauge: requests
-- ---------------------------------------------------------------------------
local time, sent, last, direct = 1000, 0, nil, nil;
local received, abandoned = {}, {};
local player = { job = 1, level = 75, buffs = {} };
local sealRem = 0;
local shown = true;
gauge._clock    = function() return time; end;
gauge._send     = function(p) sent = sent + 1; last = p; return true; end;
gauge._received = function(op, seq) received[#received + 1] = { op, seq }; return true; end;
gauge._abandon  = function(op, seq) abandoned[#abandoned + 1] = { op, seq }; end;
gauge._direct   = function(p) direct = p; end;
gauge._player   = function() return player; end;
gauge._seal     = function() return sealRem; end;
gauge._shown    = function() return shown; end;
gauge.setDemo(nil);
gauge.reset();

local receive = assert(handlers.dlac_axi_whmgauge).fn;
local function deliver(data)
    local e = { id = 0x1E0, data = data .. string.rep('\0', 64) };
    receive(e);
    return e.blocked == true;
end
local function reply(seq, status, st)
    return deliver(wire.s2cFrame(0xD0, seq, status, st and wire.encodeState(st) or ''));
end
local function push(st) return deliver(wire.s2cFrame(0xD8, 0, 0, wire.encodeState(st))); end
local function zoneIn() receive({ id = 0x00A, data = string.rep('\0', 16) }); end
local function zoneOut() receive({ id = 0x00B, data = '' }); end

zoneIn();
time = 1010; mod.pump(); mod.pump();
check(sent == 0, 'a Warrior never subscribes');
check(gauge.view() == nil, 'and draws nothing');

player = { job = 3, level = 75, buffs = {} };
zoneIn();
time = 1012; mod.pump();
check(sent == 0, 'nothing asked while the zone settles');
time = 1013.5; mod.pump(); mod.pump(); mod.pump();
check(sent == 1 and last[5] == 0xD0 and last[10] == 1, 'a WHM subscribes once the zone settles: one request');
local seq1 = last[6];
check(gauge.view() == nil, 'no stance up: nothing drawn even while subscribed');

check(not deliver('\0\0\0\0' .. string.char(0x80, 1, 0, 0)), 'another partition is left alone');
check(reply((seq1 + 1) % 256, 0, S0), 'a reply to another seq is still blocked');
check(gauge.debugState().sub == 'pending', 'but it does not answer the request');
local st1 = { stance = 1, tier = 3, flowers = { 0, 0, 0 }, flags = 0, boost = 0, charge = 40, threshold = 280, rev = 10 };
check(reply(seq1, 0, st1), 'the reply is blocked');
check(#received == 1 and received[1][1] == 0xD0 and received[1][2] == seq1, 'the reply frees the shared gate (T1)');
check(gauge.debugState().sub == 'live', 'subscribed');
time = 1100; for _ = 1, 50 do mod.pump(); end
check(sent == 1, 'no polling: a live subscription asks nothing more');

-- Stance trust.
player.buffs = { [417] = true };
local v = gauge.view();
check(v ~= nil and v.stance == 1 and v.synced and math.abs(v.progress - 40 / 280) < 1e-9, 'Solace draws the server charge');
check(v.seal ~= nil and v.seal.ready and not v.seal.active, 'Divine Seal reads ready off the client recast');
sealRem = 75;
v = gauge.view();
check(not v.seal.ready and v.seal.remaining == 75, 'and counts down while it recasts');
player.buffs = { [417] = true, [78] = true };
check(gauge.view().seal.active, 'the Divine Seal buff lights the bloom');
player.buffs = { [418] = true };
v = gauge.view();
check(v.stance == 2 and not v.synced and v.flowers[1] == 0 and v.charge == 0 and v.seal == nil,
      'a switch to Misery draws an EMPTY gauge until the server agrees');
player.buffs = { [417] = true };

-- Pushes: newer revs only; a flower lighting bursts.
check(push({ stance = 1, tier = 3, flowers = { 3, 0, 0 }, flags = 0, boost = 0, charge = 0, threshold = 280, rev = 11 }),
      'a push is blocked');
v = gauge.view();
check(v.flowers[1] == 3 and v.burst[1] ~= nil, 'the new flower shows and bursts');
time = time + 1;
check(gauge.view().burst[1] == nil, 'the burst fades');
push({ stance = 1, tier = 3, flowers = { 0, 0, 0 }, flags = 0, boost = 0, charge = 0, threshold = 280, rev = 9 });
check(gauge.view().flowers[1] == 3, 'an older rev is ignored');
push({ stance = 2, tier = 2, flowers = { 2, 0, 0 }, flags = 1, boost = 0, charge = 500, threshold = 1000, rev = 12 });
check(not gauge.view().synced, 'the server moving to Misery while the client sees Solace: not trusted');
player.buffs = { [418] = true };
v = gauge.view();
check(v.synced and v.dark and v.flowers[1] == 2 and v.progress == 0.5, 'until the client sees Misery too');
player.level = 10;
player.buffs = { [417] = true };
push({ stance = 1, tier = 0, flowers = { 0, 0, 0 }, flags = 0, boost = 0, charge = 0, threshold = 0, rev = 13 });
check(gauge.view().seal == nil, 'no Divine Seal bloom below level 15');
player.level = 75;

-- Zoning: the subscription dies with the zone; exactly one more request.
zoneOut();
time = time + 30; mod.pump();
check(sent == 1, 'nothing asked between zone-out and zone-in');
zoneIn();
time = time + 2; mod.pump();
check(sent == 1, 'nothing while the new zone settles');
time = time + 2; mod.pump(); mod.pump();
check(sent == 2, 'one subscribe per zone');
local seq2 = last[6];
check(seq2 ~= seq1, 'with a fresh seq');
reply(seq2, 0, st1);

-- Unload: stop goes straight to the packet manager.
gauge.unload();
check(direct ~= nil and direct[5] == 0xD0 and direct[10] == 0, 'unload sends a stop when subscribed');

-- Hidden: no request at all.
shown = false;
zoneIn();
time = time + 10; mod.pump();
check(sent == 2, 'a hidden gauge never asks');
check(gauge.view() == nil, 'and never draws');
shown = true;
mod.pump();
check(sent == 3, 'shown again: it asks');

-- Silence: back off, then stop for the session.
local function silentRound(expectSends)
    for _ = 1, 400 do time = time + 0.5; mod.pump(); end
    check(sent == expectSends, 'silent server: ' .. expectSends .. ' requests');
end
silentRound(6);   -- the first, then 5, 15 and 60 seconds later
check(gauge.debugState().dormant, 'three misses after the first: dormant');
check(#abandoned >= 4, 'each miss frees the shared gate (T3)');
zoneIn();
silentRound(6);
check(sent == 6, 'dormant survives zoning');

-- BUSY: asked again two seconds later, not dormant.
gauge.reset();
zoneIn();
time = time + 4; mod.pump();
check(sent == 7, 'asks after a reset');
reply(last[6], 3, nil);
check(not gauge.debugState().dormant and gauge.debugState().sub == nil, 'BUSY is not dormant');
time = time + 1; mod.pump();
check(sent == 7, 'BUSY waits');
time = time + 1.5; mod.pump();
check(sent == 8, 'then asks again');
reply(last[6], 0, st1);
check(gauge.debugState().sub == 'live', 'and subscribes');

-- BAD_OP: dormant at once.
gauge.reset();
zoneIn();
time = time + 4; mod.pump();
check(sent == 9, 'asks again after a reset');
reply(last[6], 1, nil);
check(gauge.debugState().dormant, 'BAD_OP: this server has no gauge');
zoneIn(); time = time + 10; mod.pump();
check(sent == 9, 'and nothing more is asked');

-- ---------------------------------------------------------------------------
-- the window (init.lua's render, through the stub imgui)
-- ---------------------------------------------------------------------------
gauge.reset();
shown = true;
player = { job = 3, level = 75, buffs = {} };
ui.begins, ui.draws = 0, 0;
mod._render();
check(ui.begins == 0, 'no stance: no window');
player.buffs = { [417] = true };
mod._render();
check(ui.begins == 1 and ui.name == '##dlac_whmgauge', 'Afflatus Solace opens the gauge window');
check(ui.draws > 20, 'and paints the gauge (' .. ui.draws .. ' draw calls)');
check(type(ui.dummy) == 'table' and ui.dummy[1] == draw.W and ui.dummy[2] == draw.H, 'reserving the panel at scale 1');
player.buffs = { [418] = true };
mod._render();
check(ui.begins == 2, 'Afflatus Misery opens it too');
player.job = 1;
mod._render();
check(ui.begins == 2, 'not on another job');
player.job, player.buffs = 3, {};

-- ---------------------------------------------------------------------------
-- draw
-- ---------------------------------------------------------------------------
local pts = draw.petalPoints(0, 0, 0, 10, 6, 6);
check(#pts == 12, 'a petal outline has 2n points');
local maxX = 0;
for _, p in ipairs(pts) do
    check(p[1] == p[1] and p[2] == p[2], 'no NaN in a petal');
    if p[1] > maxX then maxX = p[1]; end
end
check(math.abs(maxX - 10) < 1e-9, 'the tip reaches the petal length');

local calls = {};
local function recorder(withPath)
    local dl = {};
    for _, name in ipairs({ 'AddTriangleFilled', 'AddCircleFilled', 'AddCircle', 'AddLine', 'AddRectFilled',
                            'AddRect', 'AddText', 'PathLineTo', 'PathClear' }) do
        dl[name] = function(self, ...) calls[name] = (calls[name] or 0) + 1; end;
    end
    if withPath then dl.PathFillConvex = function() calls.PathFillConvex = (calls.PathFillConvex or 0) + 1; end; end
    return dl;
end
local function u32(c)
    check(type(c) == 'table' and #c == 4, 'a colour is {r,g,b,a}');
    for i = 1, 4 do check(c[i] == c[i] and c[i] >= -1e-9 and c[i] <= 1 + 1e-9, 'colour channel in 0-1'); end
    return 0xFFFFFFFF;
end
local function viewOf(over)
    local base = { stance = 1, level = 75, synced = true, live = true, tier = 3, flowers = { 1, 2, 3 },
                   charge = 50, threshold = 280, progress = 50 / 280, boost = 0, boosting = false,
                   dark = false, capped = false, burst = {}, now = 12.5,
                   seal = { remaining = 0, ready = true, active = false } };
    for k, val in pairs(over or {}) do base[k] = val; end
    return base;
end
local views = {
    viewOf(),
    viewOf({ flowers = { 2, 0, 0 }, burst = { 0.3 } }),
    viewOf({ flowers = { 0, 0, 0 }, progress = 0.9, seal = { remaining = 61, ready = false, active = false } }),
    viewOf({ seal = { remaining = 0, ready = true, active = true }, boosting = true, boost = 3 }),
    viewOf({ seal = { remaining = nil, ready = false, active = false }, synced = false, flowers = { 0, 0, 0 } }),
    viewOf({ stance = 2, seal = nil, dark = true, capped = true }),
    viewOf({ stance = 2, seal = nil, dark = false, flowers = { 3, 0, 0 }, progress = 0.4 }),
};
for i, vv in ipairs(views) do
    calls = {};
    local ok, err = pcall(draw.panel, recorder(true), u32, 100, 200, 1.0, vv);
    check(ok, 'panel ' .. i .. ' paints: ' .. tostring(err));
    check((calls.PathFillConvex or 0) > 0, 'panel ' .. i .. ' fills petals with one path each');
    calls = {};
    ok, err = pcall(draw.panel, recorder(false), u32, 0, 0, 1.7, vv);
    check(ok and (calls.AddTriangleFilled or 0) > 0, 'panel ' .. i .. ' falls back to triangle fans');
    local tip = draw.tooltip(vv);
    check(type(tip) == 'string' and #tip > 10, 'panel ' .. i .. ' has hover text');
end
check(draw.tooltip(views[4]):find('+150%', 1, true) ~= nil, 'the boost reads in percent');
check(draw.tooltip(views[3]):find('1:01', 1, true) ~= nil, 'the recast reads as a clock');
check(draw.tooltip(views[6]):find('dark', 1, true) ~= nil, 'Misery names the Banish element');
local w, h = draw.size(1.5);
check(w == math.floor(draw.W * 1.5 + 0.5) and h == math.floor(draw.H * 1.5 + 0.5), 'size scales');
-- Everything stays inside the box at scale 1: slot glow, bar, bloom ring.
local L = draw.layout();
for i = 1, 3 do
    local x, y = L.slots[i][1], L.slots[i][2];
    check(x - draw.TIER[3].glow >= 0 and y - draw.TIER[3].glow >= 0, 'slot ' .. i .. ' glow inside the box');
end
check(L.bar[3] < L.side[1] - 25, 'the bar stops before the bloom');
check(L.side[1] + 27 <= draw.W and L.side[2] + 27 <= draw.H, 'the bloom glow stays inside the box');

-- ---------------------------------------------------------------------------
-- demo
-- ---------------------------------------------------------------------------
local dt = 0;
local src = demo.make(function() return dt; end);
gauge.reset();
gauge.setDemo(src);
local sawSolace, sawMisery, sawBoost, sawCapped, sawSealActive, sawRecast = false, false, false, false, false, false;
for step = 0, 480 do
    dt = step * 0.1;
    time = dt;
    local d = src.at(dt);
    check(wire.state(wire.encodeState(d.state)) ~= nil, 'demo state ' .. step .. ' encodes');
    local vv = gauge.view();
    check(vv ~= nil, 'the demo always draws');
    calls = {};
    check(pcall(draw.panel, recorder(true), u32, 0, 0, 1, vv), 'demo frame ' .. step .. ' paints');
    if vv.stance == 1 then sawSolace = true; end
    if vv.stance == 2 then sawMisery = true; end
    if vv.boosting then sawBoost = true; end
    if vv.capped then sawCapped = true; end
    if vv.seal and vv.seal.active then sawSealActive = true; end
    if vv.seal and (vv.seal.remaining or 0) > 0 then sawRecast = true; end
end
check(sawSolace and sawMisery and sawBoost and sawCapped and sawSealActive and sawRecast,
      'the demo plays every state');
gauge.setDemo(nil);

print(string.format('ascensionxi_whmgauge: %d checks passed', checks));
