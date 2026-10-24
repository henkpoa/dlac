-- lua tests/ascensionxi_pldgauge.lua   (from the dlac repo root)
-- The AscensionXI Paladin Divine Guard gauge: the 0x1E0 slot-2 client (ops
-- 0xD2, 0xDA), its packet budget (one subscribe per zone, nothing more), the
-- points that carry over a stance swap, the Palisade buff check, the art
-- (drawn into a recording draw list), the shared /dl gauge command and the
-- demo loop. Server contract: ascensionxi repo,
-- documentation/custom/pld-divine-guard.md (modules/custom/lua/job_gauge_wire.lua).
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
local mounted, order = false, {};
for i, name in ipairs(sp.modules()) do
    order[name] = i;
    if name == 'pldgauge' then mounted = true; end
end
check(mounted, 'the AscensionXI pack mounts the pldgauge module');
check(order.whmgauge ~= nil and order.dncstatus ~= nil, 'beside the other two job gauge slots');

local handlers = {};
ashita = { events = { register = function(kind, name, callback) handlers[name] = { kind = kind, fn = callback }; end } };

-- A stub imgui, loaded the way every dlac file loads it (require, never a global).
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
local mod   = require('dlac\\servers\\ascensionxi\\modules\\pldgauge\\init');
local gauge = require('dlac\\servers\\ascensionxi\\modules\\pldgauge\\gauge');
local wire  = require('dlac\\servers\\ascensionxi\\modules\\pldgauge\\wire');
local draw  = require('dlac\\servers\\ascensionxi\\modules\\pldgauge\\draw');
local demo  = require('dlac\\servers\\ascensionxi\\modules\\pldgauge\\demo');
local transport = require('dlac\\servers\\ascensionxi\\transport');
check(sp.service('pldGauge') == gauge, 'the module provides the pldGauge service');
check(type(mod.pump) == 'function', 'the module hands its beat to the servermods pump');
check(transport.producerOf(0xD2) == 'pld gauge' and transport.producerOf(0xDA) == 'pld gauge',
      'the shared gate knows slot 2 as its own producer');
check(transport.producerOf(0xD0) == 'whm gauge' and transport.producerOf(0xD8) == 'whm gauge'
      and transport.producerOf(0xD1) == 'dnc status' and transport.producerOf(0xD9) == 'dnc status',
      'slots 0 and 1 keep their producers');

-- ---------------------------------------------------------------------------
-- wire
-- ---------------------------------------------------------------------------
local S0 = { stance = 1, points = 2, palisade = 17, palisadeMax = 30, flags = 0, charge = 50, threshold = 100, rev = 65535 };
-- The shared vector: the server suite (ascensionxi repo, the Divine Guard
-- xi_test suite) encodes these same 14 bytes.
local VECTOR = '01 07 01 02 11 1E 00 00 32 00 64 00 FF FF';
local function hex(s)
    local out = {};
    for i = 1, #s do out[#out + 1] = string.format('%02X', s:byte(i)); end
    return table.concat(out, ' ');
end
local bytes = wire.encodeState(S0);
check(hex(bytes) == VECTOR, 'STATE matches the server test vector: ' .. hex(bytes));
check(#bytes == wire.STATE_SIZE, 'STATE is 14 bytes');
local back = wire.state(bytes);
check(back.job == 7 and back.stance == 1 and back.points == 2 and back.palisade == 17 and back.palisadeMax == 30
      and back.flags == 0 and back.charge == 50 and back.threshold == 100 and back.rev == 65535, 'STATE round-trips');
check(wire.hasFlag(wire.state(wire.encodeState({ stance = 1, points = 3, palisadeMax = 30, flags = 1, charge = 100,
      threshold = 100, rev = 1 })).flags, wire.flag.CAPPED), 'CAPPED decodes');
check(wire.state(bytes:sub(1, 13)) == nil, 'a short STATE is refused');
check(wire.state('\2' .. bytes:sub(2)) == nil, 'another protocol is refused');
local bad = bytes:sub(1, 2) .. '\9\8' .. '\77\0' .. bytes:sub(7);
local clamped = wire.state(bad);
check(clamped.stance == 0 and clamped.points == 3 and clamped.palisadeMax == 30 and clamped.palisade == 30,
      'an out-of-range stance, points, cap and stacks clamp');
check(wire.newer(0, 65535) and wire.newer(5, 4) and not wire.newer(4, 5) and not wire.newer(7, 7),
      'rev comparison survives the wrap');
check(wire.ours(0xD2) and wire.ours(0xDA) and not wire.ours(0xD0) and not wire.ours(0xD8)
      and not wire.ours(0xD1) and not wire.ours(0xD9) and not wire.ours(0xD3), 'only slot 2 is ours');
local sub = wire.subscribe(300, true);
check(#sub == 12 and sub[5] == 0xD2 and sub[6] == 300 % 256 and sub[9] == 1 and sub[10] == 1,
      'SUBSCRIBE: op 0xD2, seq, protocol 1, mode 1');
check(wire.subscribe(1, false)[10] == 0, 'stop = mode 0');
local f = wire.incoming(wire.s2cFrame(0xDA, 0, 0, bytes) .. string.rep('\0', 400));
-- 4 + 4 + 14 bytes, padded to whole words: the payload carries 2 bytes of
-- padding, which the STATE decode ignores.
check(f.op == 0xDA and f.seq == 0 and #f.payload == 16 and f.payload:sub(1, 14) == bytes
      and wire.state(f.payload).rev == 65535, 'incoming trims to the declared size');

-- ---------------------------------------------------------------------------
-- gauge: requests
-- ---------------------------------------------------------------------------
local time, sent, last, direct = 1000, 0, nil, nil;
local received, abandoned = {}, {};
local player = { job = 1, level = 75, buffs = {} };
local shown = true;
gauge._clock    = function() return time; end;
gauge._send     = function(p) sent = sent + 1; last = p; return true; end;
gauge._received = function(op, seq) received[#received + 1] = { op, seq }; return true; end;
gauge._abandon  = function(op, seq) abandoned[#abandoned + 1] = { op, seq }; end;
gauge._direct   = function(p) direct = p; end;
gauge._player   = function() return player; end;
gauge._shown    = function() return shown; end;
gauge.setDemo(nil);
gauge.reset();

local GUARD, FURY, PALISADE = gauge.BUFF.GUARD, gauge.BUFF.FURY, gauge.BUFF.PALISADE;
check(GUARD == 654 and FURY == 655 and PALISADE == 478, 'the stance and Palisade buff icons the server sends');

local receive = assert(handlers.dlac_axi_pldgauge).fn;
local function deliver(data)
    local e = { id = 0x1E0, data = data .. string.rep('\0', 64) };
    receive(e);
    return e.blocked == true;
end
local function reply(seq, status, st)
    return deliver(wire.s2cFrame(0xD2, seq, status, st and wire.encodeState(st) or ''));
end
local function push(st) return deliver(wire.s2cFrame(0xDA, 0, 0, wire.encodeState(st))); end
local function zoneIn() receive({ id = 0x00A, data = string.rep('\0', 16) }); end
local function zoneOut() receive({ id = 0x00B, data = '' }); end
local function st(over)
    local base = { stance = 1, points = 0, palisade = 0, palisadeMax = 30, flags = 0, charge = 0, threshold = 100, rev = 1 };
    for k, val in pairs(over or {}) do base[k] = val; end
    return base;
end

zoneIn();
time = 1010; mod.pump(); mod.pump();
check(sent == 0, 'a Warrior never subscribes');
check(gauge.view() == nil, 'and draws nothing');

player = { job = 7, level = 75, buffs = {} };
zoneIn();
time = 1012; mod.pump();
check(sent == 0, 'nothing asked while the zone settles');
time = 1013.5; mod.pump(); mod.pump(); mod.pump();
check(sent == 1 and last[5] == 0xD2 and last[10] == 1, 'a PLD subscribes once the zone settles: one request');
local seq1 = last[6];
check(gauge.view() == nil, 'no stance up: nothing drawn even while subscribed');
player.buffs = { [GUARD] = true };
check(gauge.view() == nil, 'a stance up before the server has answered: still nothing drawn');
player.buffs = {};

check(not deliver('\0\0\0\0' .. string.char(0x80, 1, 0, 0)), 'another partition is left alone');
check(not deliver(wire.s2cFrame(0xD8, 0, 0, string.rep('\1', 16))), 'the White Mage slot is left to its tap');
check(not deliver(wire.s2cFrame(0xD9, 0, 0, string.rep('\1', 28))), 'the Dancer slot is left to its tap');
check(reply((seq1 + 1) % 256, 0, S0), 'a reply to another seq is still blocked');
check(gauge.debugState().sub == 'pending', 'but it does not answer the request');
local st1 = st({ points = 1, charge = 50, rev = 10 });
check(reply(seq1, 0, st1), 'the reply is blocked');
check(#received == 1 and received[1][1] == 0xD2 and received[1][2] == seq1, 'the reply frees the shared gate (T1)');
check(gauge.debugState().sub == 'live', 'subscribed');
time = 1100; for _ = 1, 50 do mod.pump(); end
check(sent == 1, 'no polling: a live subscription asks nothing more');

-- What is drawn.
player.buffs = { [GUARD] = true };
local v = gauge.view();
check(v ~= nil and v.stance == 1 and v.points == 1 and v.progress == 0.5 and v.agree, 'Divine Guard draws the server points and charge');
check(v.palisade == 0, 'no Palisade buff: no stacks');
push(st({ points = 0, palisade = 5, charge = 50, rev = 11 }));
check(gauge.view().palisade == 0, 'stacks from the server, but the client sees no Palisade buff: nothing counted');
player.buffs = { [GUARD] = true, [PALISADE] = true };
check(gauge.view().palisade == 5, 'with the buff up the stacks count');
player.buffs = { [GUARD] = true };
check(gauge.view().palisade == 0, 'Palisade ran out (or death took it): the big shield empties at once');
player.buffs = { [GUARD] = true, [PALISADE] = true };

-- Points carry over a stance swap: no trust rule to wait out.
push(st({ points = 2, palisade = 5, charge = 0, rev = 12 }));
check(gauge.view().points == 2, 'two points');
player.buffs = { [FURY] = true, [PALISADE] = true };
v = gauge.view();
check(v ~= nil and v.stance == 2 and v.points == 2 and not v.agree,
      'a switch to Divine Fury draws the carried points at once, before the server agrees');
push(st({ stance = 2, points = 2, palisade = 0, rev = 13 }));
v = gauge.view();
check(v.agree and v.points == 2 and v.palisade == 0, 'and the server agrees');
player.buffs = {};
check(gauge.view() == nil, 'no stance: nothing drawn');
player.buffs = { [GUARD] = true };

-- Pushes: newer revs only; each point gained bursts.
time = time + 1;   -- the earlier points' bursts are over
push(st({ points = 3, rev = 14 }));
v = gauge.view();
check(v.points == 3 and v.burst[3] ~= nil and v.burst[1] == nil, 'the new third point shows and bursts');
time = time + 1;
check(gauge.view().burst[3] == nil, 'the burst fades');
push(st({ points = 0, rev = 9 }));
check(gauge.view().points == 3, 'an older rev is ignored');
push(st({ points = 3, flags = 1, charge = 100, rev = 15 }));
v = gauge.view();
check(v.capped and v.progress == 1, 'capped: three points and a full bar');
push(st({ points = 2, charge = 100, rev = 16 }));
push(st({ points = 3, charge = 0, rev = 17 }));
check(gauge.view().burst[3] ~= nil, 'a point spent and refilled bursts again');

-- Zoning: the subscription dies with the zone; exactly one more request.
zoneOut();
time = time + 30; mod.pump();
check(sent == 1, 'nothing asked between zone-out and zone-in');
zoneIn();
check(gauge.view() ~= nil, 'the last state stays drawn across the zone line');
time = time + 2; mod.pump();
check(sent == 1, 'nothing while the new zone settles');
time = time + 2; mod.pump(); mod.pump();
check(sent == 2, 'one subscribe per zone');
local seq2 = last[6];
check(seq2 ~= seq1, 'with a fresh seq');
reply(seq2, 0, st1);

-- Unload: stop goes straight to the packet manager.
gauge.unload();
check(direct ~= nil and direct[5] == 0xD2 and direct[10] == 0, 'unload sends a stop when subscribed');

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
check(player.buffs[GUARD] and gauge.view() == nil, 'a silent server: nothing drawn, even with a state from before');
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

-- BAD_OP: dormant at once (an AscensionXI server before the Paladin slot).
gauge.reset();
zoneIn();
time = time + 4; mod.pump();
check(sent == 9, 'asks again after a reset');
reply(last[6], 1, nil);
check(gauge.debugState().dormant, 'BAD_OP: this server has no Paladin gauge');
check(gauge.view() == nil, 'and nothing is drawn');
zoneIn(); time = time + 10; mod.pump();
check(sent == 9, 'and nothing more is asked');

-- ---------------------------------------------------------------------------
-- the three slots side by side: every tap reads only what it should
-- ---------------------------------------------------------------------------
require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\init');
require('dlac\\servers\\ascensionxi\\modules\\dncstatus\\init');
local whm = require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\gauge');
local whmWire = require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\wire');
local whmTap = assert(handlers.dlac_axi_whmgauge).fn;
local dncTap = assert(handlers.dlac_axi_dncstatus).fn;
local function everyTap(data)
    local e = { id = 0x1E0, data = data .. string.rep('\0', 64) };
    whmTap(e); dncTap(e); receive(e);
    return e;
end
gauge.reset(); whm.reset();
local pldRev = st({ points = 2, rev = 40 });
local whmBefore = whm.debugState().state;
everyTap(wire.s2cFrame(0xDA, 0, 0, wire.encodeState(pldRev)));
check(whm.debugState().state == whmBefore, 'a Paladin push never reaches the White Mage gauge');
check(gauge.debugState().state ~= nil and gauge.debugState().state.points == 2, 'and lands in the Paladin gauge');
everyTap(whmWire.s2cFrame(0xD8, 0, 0, whmWire.encodeState({ stance = 1, tier = 3, flowers = { 3, 3, 3 }, flags = 0,
    boost = 0, charge = 0, threshold = 280, rev = 41 })));
check(gauge.debugState().state.points == 2 and gauge.debugState().state.rev == 40,
      'a White Mage push never reaches the Paladin gauge');

-- ---------------------------------------------------------------------------
-- /dl gauge: one command, answered by the main job's gauge
-- ---------------------------------------------------------------------------
check(mod.ownsCommand(7) and not mod.ownsCommand(3) and not mod.ownsCommand(nil),
      'the Paladin gauge answers /dl gauge only for a main Paladin');
local pldCmd = assert(handlers.dlac_axi_pldgauge_cmd).fn;
local whmCmd = assert(handlers.dlac_axi_whmgauge_cmd).fn;
local said = {};
local realPrint = print;
print = function(msg) said[#said + 1] = tostring(msg); end;
local function asJob(job, text)
    AshitaCore = { GetMemoryManager = function() return { GetPlayer = function()
        return { GetMainJob = function() return job; end }; end }; end };
    said = {};
    local e = { command = text };
    whmCmd(e); pldCmd(e);
    AshitaCore = nil;
    return e.blocked == true, table.concat(said, '\n');
end
local blocked, out = asJob(7, '/dl gauge status');
check(blocked and out:find('PLD gauge', 1, true) ~= nil and out:find('WHM gauge', 1, true) == nil,
      'a Paladin\'s /dl gauge status is the Paladin gauge\'s alone: ' .. out);
blocked, out = asJob(3, '/dl gauge status');
check(blocked and out:find('WHM gauge', 1, true) ~= nil and out:find('PLD gauge', 1, true) == nil,
      'a White Mage\'s is the White Mage gauge\'s alone: ' .. out);
blocked, out = asJob(nil, '/dl gauge status');
check(blocked and out:find('WHM gauge', 1, true) ~= nil and out:find('PLD gauge', 1, true) == nil,
      'an unknown job keeps the White Mage gauge\'s answer, as before');
blocked = asJob(7, '/dl gauges');
check(not blocked, '/dl gauges is nobody\'s');
print = realPrint;

-- ---------------------------------------------------------------------------
-- the window (init.lua's render, through the stub imgui)
-- ---------------------------------------------------------------------------
gauge._player = function() return player; end;
gauge.reset();
shown = true;
player = { job = 7, level = 75, buffs = {} };
ui.begins, ui.draws = 0, 0;
mod._render();
check(ui.begins == 0, 'no stance: no window');
player.buffs = { [GUARD] = true };
mod._render();
check(ui.begins == 0, 'a stance before the server has answered: no window');
zoneIn();
time = time + 4; mod.pump();
reply(last[6], 0, st1);
mod._render();
check(ui.begins == 1 and ui.name == '##dlac_pldgauge', 'Divine Guard opens the gauge window');
check(ui.draws > 20, 'and paints the gauge (' .. ui.draws .. ' draw calls)');
check(type(ui.dummy) == 'table' and ui.dummy[1] == draw.W and ui.dummy[2] == draw.H, 'reserving the panel at scale 1');
player.buffs = { [FURY] = true };
mod._render();
check(ui.begins == 2, 'Divine Fury opens it too');
player.job = 3;
mod._render();
check(ui.begins == 2, 'not on another job');
player.job, player.buffs = 7, {};

-- ---------------------------------------------------------------------------
-- draw
-- ---------------------------------------------------------------------------
-- Convex, clockwise in screen space: every turn has the same sign.
local function convex(pts)
    local sign = 0;
    for i = 1, #pts do
        local a, b, c = pts[i], pts[(i % #pts) + 1], pts[((i + 1) % #pts) + 1];
        local z = (b[1] - a[1]) * (c[2] - b[2]) - (b[2] - a[2]) * (c[1] - b[1]);
        if math.abs(z) > 1e-9 then
            local s = z > 0 and 1 or -1;
            if sign == 0 then sign = s; elseif s ~= sign then return false; end
        end
    end
    return true;
end
local shield = draw.shieldPoints(0, 0, 10);
check(#shield >= 8 and convex(shield), 'the shield outline is one convex polygon');
local minY, maxY = math.huge, -math.huge;
for _, p in ipairs(shield) do
    check(p[1] == p[1] and p[2] == p[2], 'no NaN in the shield');
    minY, maxY = math.min(minY, p[2]), math.max(maxY, p[2]);
end
check(math.abs(maxY - 10) < 1e-9 and minY >= -10, 'the point reaches the half height, the top stays inside');
local blade = draw.bladePoints(0, 0, -math.pi / 4, 30, 4);
check(#blade == 5 and convex(blade), 'a blade is a convex pentagon');

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
    local base = { stance = 1, level = 75, synced = true, agree = true, live = true, points = 2, charge = 50,
                   threshold = 100, progress = 0.5, capped = false, palisade = 12, palisadeMax = 30,
                   burst = {}, now = 12.5 };
    for k, val in pairs(over or {}) do base[k] = val; end
    return base;
end
local views = {
    viewOf(),
    viewOf({ points = 0, progress = 0, palisade = 0 }),
    viewOf({ points = 1, burst = { 0.3 }, progress = 0.9 }),
    viewOf({ points = 3, capped = true, progress = 1, palisade = 30 }),
    viewOf({ points = 3, progress = 0.4 }),
    viewOf({ stance = 2, points = 2, palisade = 0 }),
    viewOf({ stance = 2, points = 3, capped = true, progress = 1 }),
    viewOf({ stance = 2, points = 0, progress = 0.5 }),
};
for i, vv in ipairs(views) do
    calls = {};
    local ok, err = pcall(draw.panel, recorder(true), u32, 100, 200, 1.0, vv);
    check(ok, 'panel ' .. i .. ' paints: ' .. tostring(err));
    check((calls.PathFillConvex or 0) > 0, 'panel ' .. i .. ' fills its shapes with one path each');
    calls = {};
    ok, err = pcall(draw.panel, recorder(false), u32, 0, 0, 1.7, vv);
    check(ok and (calls.AddTriangleFilled or 0) > 0, 'panel ' .. i .. ' falls back to triangle fans');
    local tip = draw.tooltip(vv);
    check(type(tip) == 'string' and #tip > 10, 'panel ' .. i .. ' has hover text');
end
check(draw.tooltip(views[1]):find('Divine Guard', 1, true) ~= nil, 'Divine Guard names itself');
check(draw.tooltip(views[1]):find('+12%', 1, true) ~= nil, 'Palisade reads as block rate');
check(draw.tooltip(views[1]):find('Points: 2 / 3', 1, true) ~= nil, 'the points read out');
check(draw.tooltip(views[4]):find('full bar', 1, true) ~= nil, 'capped says why the bar waits');
check(draw.tooltip(views[6]):find('Divine Fury', 1, true) ~= nil and draw.tooltip(views[6]):find('Palisade', 1, true) == nil,
      'Divine Fury has no Palisade line');
local w, h = draw.size(1.5);
check(w == math.floor(draw.W * 1.5 + 0.5) and h == math.floor(draw.H * 1.5 + 0.5), 'size scales');
-- Everything stays inside the box at scale 1: slot glow and burst, bar, big shield ring.
local L = draw.layout();
for i = 1, 3 do
    local x, y = L.slots[i][1], L.slots[i][2];
    check(x - (draw.GLOW_R + 10) >= 0 and y - (draw.GLOW_R + 10) >= 0, 'slot ' .. i .. ' burst ring inside the box');
    check(y + draw.SLOT_R <= L.bar[2], 'slot ' .. i .. ' icon above the bar');
end
check(L.bar[3] < L.side[1] - draw.RING_R, 'the bar stops before the Palisade ring');
check(L.side[1] + draw.RING_R + 2 <= draw.W and L.side[2] + draw.RING_R + 2 <= draw.H
      and L.side[2] - draw.RING_R - 2 >= 0, 'the Palisade ring stays inside the box');

-- The count stays on the big shield and inside the panel, whatever the font.
for _, scale in ipairs({ 0.6, 1, 1.5, 3 }) do
    for _, fontH in ipairs({ 13, 16, 20 }) do
        local texts = {};
        local dl = setmetatable({ AddText = function(_, p, col, txt) texts[#texts + 1] = { p[1], p[2], txt }; end },
            { __index = function() return function() end; end });
        local measure = function(t) return #t * fontH * 0.5, fontH; end
        local _, ph = draw.size(scale);
        draw.panel(dl, u32, 0, 0, scale, viewOf({ palisade = 30 }), measure);
        check(#texts == 1 and texts[1][3] == '30', 'one label: the stack count');
        local cx = L.side[1] * scale;
        check(texts[1][2] >= 0 and texts[1][2] + fontH <= ph + 0.001,
              string.format('the count inside the panel at scale %.1f, font %d', scale, fontH));
        check(math.abs((texts[1][1] + #'30' * fontH * 0.25) - cx) < 0.5, 'and centred on the big shield');
        texts = {};
        draw.panel(dl, u32, 0, 0, scale, viewOf({ stance = 2 }), measure);
        check(#texts == 0, 'Divine Fury draws no count');
    end
end

-- ---------------------------------------------------------------------------
-- demo
-- ---------------------------------------------------------------------------
local dt = 0;
local src = demo.make(function() return dt; end);
gauge.reset();
gauge.setDemo(src);
local sawGuard, sawFury, sawCapped, sawPalisade, sawBurst, sawGrow = false, false, false, false, false, false;
for step = 0, 400 do
    dt = step * 0.1;
    time = dt;
    local d = src.at(dt);
    check(wire.state(wire.encodeState(d.state)) ~= nil, 'demo state ' .. step .. ' encodes');
    local vv = gauge.view();
    check(vv ~= nil, 'the demo always draws');
    calls = {};
    check(pcall(draw.panel, recorder(true), u32, 0, 0, 1, vv), 'demo frame ' .. step .. ' paints');
    if vv.stance == 1 then sawGuard = true; end
    if vv.stance == 2 and vv.points > 0 then sawFury = true; end
    if vv.capped then sawCapped = true; end
    if vv.palisade > 0 then sawPalisade = true; end
    if next(vv.burst) ~= nil then sawBurst = true; end
    if vv.points < 3 and vv.progress > 0 then sawGrow = true; end
end
check(sawGuard and sawFury and sawCapped and sawPalisade and sawBurst and sawGrow, 'the demo plays every state');
gauge.setDemo(nil);

-- Demo off over a live subscription: the demo overwrote the server's state,
-- so ask for it again rather than wait for a push that may not come.
time = 5000;
player = { job = 7, level = 75, buffs = { [GUARD] = true } };
gauge.reset();
mod.pump();
reply(last[6], 0, st1);
check(gauge.debugState().sub == 'live' and gauge.view() ~= nil, 'live and drawn before the demo');
local beforeOff = sent;
gauge.setDemo(src);
gauge.setDemo(nil);
check(gauge.view() == nil, 'demo off: nothing drawn until the server answers again');
mod.pump();
check(sent == beforeOff + 1 and last[5] == 0xD2 and last[10] == 1, 'demo off asks the server for its state again');
reply(last[6], 0, st1);
check(gauge.view() ~= nil, 'and draws once it has');

-- Every other job: read once a second, never asked.
gauge.reset();
local asked = 0;
gauge._player = function() asked = asked + 1; return { job = 1, level = 75, buffs = {} }; end;
local beforeJobs = sent;
for _ = 1, 60 do mod.pump(); end
check(asked == 1, 'a Warrior is read once, not once a frame (' .. asked .. ')');
time = time + gauge.JOB_RECHECK;
mod.pump(); mod.pump();
check(asked == 2, '...and again a second later');
check(sent == beforeJobs, 'and never asked the server for anything');
gauge._player = function() return player; end;

print(string.format('ascensionxi_pldgauge: %d checks passed', checks));
