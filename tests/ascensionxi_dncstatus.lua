-- lua tests/ascensionxi_dncstatus.lua   (from the dlac repo root)
-- The AscensionXI Dancer status: slot 1 of the 0x1E0 job gauge partition
-- (0xD1, 0xD9), its packet budget (one subscribe per zone, only on demand),
-- the view that joins the client's own buffs with the server's facts, and
-- the DNC Status Job helper that draws it.
-- Server contract: ascensionxi repo, documentation/custom/dnc-status.md.
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
for _, name in ipairs(sp.modules()) do if name == 'dncstatus' then mounted = true; end end
check(mounted, 'the AscensionXI pack mounts the dncstatus module');

local handlers = {};
ashita = { events = { register = function(kind, name, callback) handlers[name] = { kind = kind, fn = callback }; end } };
package.loaded['imgui'] = setmetatable({}, { __index = function() return function() end; end });

local mod    = require('dlac\\servers\\ascensionxi\\modules\\dncstatus\\init');
local status = require('dlac\\servers\\ascensionxi\\modules\\dncstatus\\status');
local wire   = require('dlac\\servers\\ascensionxi\\modules\\dncstatus\\wire');
local transport = require('dlac\\servers\\ascensionxi\\transport');
local svc = sp.service('dncStatus');
check(type(svc) == 'table' and svc.view == status.view and svc.want == status.want,
      'the module provides the dncStatus service');
check(type(mod.pump) == 'function', 'the module hands its beat to the servermods pump');
check(transport.producerOf(0xD1) == 'dnc status' and transport.producerOf(0xD9) == 'dnc status',
      'the shared gate knows slot 1 as its own producer');
check(transport.producerOf(0xD0) == 'whm gauge' and transport.producerOf(0xD8) == 'whm gauge',
      'and slot 0 is still the White Mage gauge');

-- ---------------------------------------------------------------------------
-- wire
-- ---------------------------------------------------------------------------
local S0 = { memory = 5 + 2 * 16, target = 291, levels = { 4, 2, 0, 0 }, seconds = { 72, 45, 0, 0 },
             prices = { 600, 900, 1200 }, base = 1, perStack = 3, rev = 258 };
-- The shared vector: the server suite (ascensionxi repo, job_gauge_wire's
-- tests) encodes these same 28 bytes.
local VECTOR = '01 13 25 00 23 01 04 02 00 00 48 00 2D 00 00 00 00 00 58 02 84 03 B0 04 01 03 02 01';
local function hex(s)
    local out = {};
    for i = 1, #s do out[#out + 1] = string.format('%02X', s:byte(i)); end
    return table.concat(out, ' ');
end
local bytes = wire.encodeState(S0);
check(hex(bytes) == VECTOR, 'STATE matches the server test vector: ' .. hex(bytes));
check(#bytes == wire.STATE_SIZE, 'STATE is 28 bytes');
local back = wire.state(bytes);
check(back.job == 19 and back.memory == 37 and back.target == 291 and back.rev == 258, 'STATE round-trips');
check(back.memoryLevels[1] == 5 and back.memoryLevels[2] == 2 and back.memoryLevels[3] == 0
      and back.memoryLevels[4] == 0, 'the memory unpacks four bits per Step, Quickstep lowest');
check(back.levels[1] == 4 and back.levels[2] == 2 and back.seconds[1] == 72 and back.seconds[2] == 45
      and back.seconds[3] == 0, 'the Dazes and their seconds');
check(back.prices[1] == 600 and back.prices[2] == 900 and back.prices[3] == 1200
      and back.base == 1 and back.perStack == 3, 'the prices and the caps');
check(wire.state(bytes:sub(1, 27)) == nil, 'a short STATE is refused');
check(wire.state('\2' .. bytes:sub(2)) == nil, 'another protocol is refused');
local wild = wire.state(wire.encodeState({ levels = { 200, 0, 0, 0 }, seconds = { 9, 30, 0, 0 } }));
check(wild.levels[1] == 15 and wild.seconds[2] == 0, 'a wild level is clamped; a level-0 Daze has no seconds');
local m = wire.memoryLevels(0xFEDC);
check(m[1] == 0xC and m[2] == 0xD and m[3] == 0xE and m[4] == 0xF, 'every nibble of the memory');
check(wire.ours(0xD1) and wire.ours(0xD9) and not wire.ours(0xD0) and not wire.ours(0xD8)
      and not wire.ours(0xC1) and not wire.ours(0xE1), 'slot 1 of 0xD0-0xDF only');
local sub = wire.subscribe(300, true);
check(#sub == 12 and sub[5] == 0xD1 and sub[6] == 300 % 256 and sub[9] == 1 and sub[10] == 1,
      'SUBSCRIBE: op 0xD1, seq, proto 1, mode 1');
check(wire.subscribe(1, false)[10] == 0, 'stop = mode 0');
local f = wire.incoming(wire.s2cFrame(0xD9, 0, 0, bytes) .. string.rep('\0', 32));
check(f.op == 0xD9 and f.seq == 0 and #f.payload == 28 and f.payload == bytes,
      'incoming() reads a frame and trims it to the header size');
check(wire.newer(0, 65535) and wire.newer(5, 4) and not wire.newer(4, 5) and not wire.newer(7, 7),
      'rev comparison survives the wrap');

-- ---------------------------------------------------------------------------
-- status: requests
-- ---------------------------------------------------------------------------
local time, sent, last, direct = 1000, 0, nil, nil;
local received, abandoned = {}, {};
local player = { job = 1, level = 75, tp = 1000, buffs = {}, timers = {} };
local names = { [291] = 'Goblin Smithy' };
status._clock      = function() return time; end;
status._send       = function(p) sent = sent + 1; last = p; return true; end;
status._received   = function(op, seq) received[#received + 1] = { op, seq }; return true; end;
status._abandon    = function(op, seq) abandoned[#abandoned + 1] = { op, seq }; end;
status._direct     = function(p) direct = p; end;
status._player     = function() return player; end;
status._entityName = function(i) return names[i]; end;
status.reset();

local receive = assert(handlers.dlac_axi_dncstatus).fn;
local function deliver(data)
    local e = { id = 0x1E0, data = data .. string.rep('\0', 64) };
    receive(e);
    return e.blocked == true;
end
local function reply(seq, st, code)
    return deliver(wire.s2cFrame(0xD1, seq, code or 0, st and wire.encodeState(st) or ''));
end
local function push(st) return deliver(wire.s2cFrame(0xD9, 0, 0, wire.encodeState(st))); end
local function zoneIn() receive({ id = 0x00A, data = string.rep('\0', 16) }); end
local function zoneOut() receive({ id = 0x00B, data = '' }); end
local function frame(n) for _ = 1, n or 1 do mod.pump(); end end

zoneIn();
time = 1010; frame(2);
check(sent == 0, 'a Warrior never subscribes');
status.want(); frame();
check(sent == 0, 'even when a surface asks');
check(status.view() == nil and select(2, status.view()) == 'job', 'and the view says why');
player.job = 19;
time = 1100; frame(2);
check(sent == 0, 'a Dancer with nothing showing the status asks nothing');
zoneIn();
time = 1101; status.want(); frame();
check(sent == 0, 'nothing asked while the zone settles');
time = 1103.5; status.want(); frame(3);
check(sent == 1 and last[5] == 0xD1 and last[10] == 1, 'a Dancer whose status is showing subscribes once');
local seq1 = last[6];
check(select(2, status.view()) == 'waiting', 'nothing drawn before the server answers');
check(not deliver('\0\0\0\0' .. string.char(0x80, 1, 0, 0)), 'another partition is left alone');
check(not deliver(wire.s2cFrame(0xD0, seq1, 0, '')), 'the White Mage slot is left alone');
check(reply((seq1 + 1) % 256, S0), 'a reply to another seq is still blocked');
check(status.debugState().sub == 'pending', 'but it does not answer the request');
check(reply(seq1, S0), 'the reply is blocked');
check(#received == 1 and received[1][1] == 0xD1 and received[1][2] == seq1, 'the reply frees the shared gate (T1)');
check(status.debugState().sub == 'live', 'subscribed');
time = 1200; status.want(); frame(5);
check(sent == 1, 'no polling: a live subscription asks nothing more');

-- ---------------------------------------------------------------------------
-- status: the view
-- ---------------------------------------------------------------------------
time = 2000;
push({ memory = 5 + 2 * 16, target = 0, prices = { 600, 900, 1200 }, base = 1, perStack = 3, rev = 300 });
player.buffs = { [472] = true };
player.timers = { [472] = 47 };
local v = status.view();
check(v ~= nil and v.learnt and v.stacks == 0 and v.cap == 1, 'no stacks: Perpetual Step puts on 1 level');
check(v.memory ~= nil and #v.memory.steps == 2 and v.memory.remaining == 47, 'the memory: two Steps, the buff timer');
check(v.memory.steps[1].name == 'Quickstep' and v.memory.steps[1].level == 5 and v.memory.steps[1].applies == 1
      and v.memory.steps[2].name == 'Box Step' and v.memory.steps[2].applies == 1, 'each capped at 1');
check(v.rhythm.stacks == 0 and v.rhythm.cost == 600 and not v.rhythm.refresh and not v.rhythm.short,
      'the first stack costs 600, and 1000 TP covers it');
check(v.target == nil, 'not fighting: no target');

player.buffs = { [472] = true, [634] = true };
player.timers = { [472] = 47, [634] = 31 };
v = status.view();
check(v.stacks == 2 and v.cap == 7 and v.memory.steps[1].applies == 5 and v.memory.steps[2].applies == 2,
      'two stacks (icon 634): up to 7, never above the memory');
check(v.rhythm.cost == 1200 and v.rhythm.remaining == 31 and v.rhythm.short == true,
      'the third stack costs 1200, more than the 1000 TP held; its timer is the client\'s');
player.tp = 1200;
check(status.view().rhythm.short == false, 'enough TP is not flagged');
player.buffs = { [472] = true, [635] = true };
v = status.view();
check(v.stacks == 3 and v.cap == 10 and v.rhythm.refresh and v.rhythm.cost == 1200, 'three stacks: a refresh at 1200');
player.buffs = { [472] = true, [624] = true, [376] = true };
v = status.view();
check(v.stacks == 1 and v.trance and v.cap == nil and v.memory.steps[1].applies == 5,
      'Trance puts on the whole memory');
player.buffs, player.timers = {}, {};
v = status.view();
check(v.memory ~= nil and v.memory.remaining == nil,
      'the memory follows the server: a renumbered icon costs only the timer');
player.level = 29;
check(not status.view().learnt, 'below 30 neither ability exists');
player.level = 75;

time = 3000;
push({ memory = 0, target = 291, levels = { 4, 2, 0, 0 }, seconds = { 72, 45, 0, 0 },
       prices = { 600, 900, 1200 }, base = 1, perStack = 3, rev = 301 });
v = status.view();
check(v.memory == nil, 'a zero memory: nothing remembered');
check(v.target ~= nil and v.target.name == 'Goblin Smithy' and #v.target.steps == 2,
      'the target: named from the client, two Steps');
check(v.target.steps[1].name == 'Quickstep' and v.target.steps[1].level == 4 and v.target.steps[1].remaining == 72,
      'Quickstep 4, 72 seconds');
time = 3030;
v = status.view();
check(v.target.steps[1].remaining == 42 and v.target.steps[2].remaining == 15, 'the client counts the seconds down');
time = 3045.5;
v = status.view();
check(#v.target.steps == 1 and v.target.steps[1].name == 'Quickstep', 'a Daze that runs out leaves the list');
names[291] = nil;
check(status.view().target.name == nil, 'an unnamed target is still a target');
names[291] = 'Goblin Smithy';

push({ memory = 37, target = 291, levels = { 9, 0, 0, 0 }, seconds = { 10, 0, 0, 0 },
       prices = { 600, 900, 1200 }, base = 1, perStack = 3, rev = 300 });
check(status.view().memory == nil, 'an older push is ignored');
push({ memory = 37, target = 0, prices = { 600, 900, 1200 }, base = 1, perStack = 3, rev = 302 });
check(status.view().target == nil and status.view().memory ~= nil, 'a newer one replaces the state');

-- ---------------------------------------------------------------------------
-- status: zones, refusals, silence, unload
-- ---------------------------------------------------------------------------
local before = sent;
zoneOut();
check(status.debugState().sub == nil, 'a zone-out ends the subscription');
zoneIn();
check(select(2, status.view()) == 'waiting', 'the old zone\'s state is dropped at zone-in');
time = time + 1; status.want(); frame();
check(sent == before, 'and nothing asked while the new zone settles');
time = time + 3; frame();
check(sent == before, 'nothing asked when nothing is showing the status');
status.want(); frame();
check(sent == before + 1, 'one subscribe per zone, once it is wanted again');
reply(last[6], nil, 3);
check(status.debugState().sub == nil, 'BUSY: ask again shortly');
time = time + 1; status.want(); frame();
check(sent == before + 1, 'not before two seconds');
time = time + 1.5; status.want(); frame();
check(sent == before + 2, 'then once more');
reply(last[6], S0);
check(status.debugState().sub == 'live', 'and the answer is taken');

status.unload();
check(direct ~= nil and direct[5] == 0xD1 and direct[10] == 0, 'unload sends a stop when live');

status.reset();
status._clock = function() return time; end;
before = sent;
status.want(); frame();
check(sent == before + 1, 'a fresh session asks at once');
reply(last[6], nil, 1);
check(status.debugState().dormant and select(2, status.view()) == 'unsupported',
      'BAD_OP: a server without the Dancer slot');
time = time + 100; status.want(); frame(3);
check(sent == before + 1, 'and asks it nothing more this session');
direct = nil;
status.unload();
check(direct == nil, 'nor sends a stop');

status.reset();
before = sent;
status.want(); frame();
check(sent == before + 1, 'silence: the first try');
for i, wait in ipairs({ 5, 15, 60 }) do
    time = time + 5; status.want(); frame();          -- the reply wait runs out
    time = time + wait - 0.1; status.want(); frame();
    check(sent == before + i, 'silence: not before ' .. wait .. ' seconds');
    time = time + 0.2; status.want(); frame();
    check(sent == before + i + 1, 'silence: try again after ' .. wait .. ' seconds');
end
time = time + 5; status.want(); frame();
check(status.debugState().dormant, 'then stops asking for the session');
time = time + 100; status.want(); frame(3);
check(sent == before + 4, 'and asks nothing more');

-- The White Mage gauge shares the partition: each module reads only its slot.
status.reset();
require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\init');
local whm = require('dlac\\servers\\ascensionxi\\modules\\whmgauge\\gauge');
local whmTap = assert(handlers.dlac_axi_whmgauge).fn;
local e = { id = 0x1E0, data = wire.s2cFrame(0xD9, 0, 0, wire.encodeState(S0)) .. string.rep('\0', 64) };
whmTap(e);
receive(e);
check(whm.debugState().state == nil, 'a Dancer frame never reaches the White Mage gauge');
check(status.debugState().state ~= nil, 'and still reaches the Dancer status');

-- ---------------------------------------------------------------------------
-- the Job helper
-- ---------------------------------------------------------------------------
local jh = require('dlac\\feature\\jobhelpers');
local helper = require('dlac\\jobhelpers\\dnc\\dnc-status\\init');
local rec = jh._validate('dnc-status', helper);
check(rec ~= nil and rec.servers ~= nil and rec.servers[1] == 'ascensionxi', 'the helper is a valid module, built for AscensionXI');
check(jh.forServer(rec.servers, 'ascensionxi') and not jh.forServer(rec.servers, 'cexi')
      and not jh.forServer(rec.servers, nil), 'so it loads on AscensionXI only');
check(type(helper.window) == 'function' and helper.commands == nil and helper.open == nil,
      'a window and no actions: it never acts');
local cfgVals = {};
local defaults = helper.config.defaults;
local S = {
    cfg = {
        get = function(k) if cfgVals[k] ~= nil then return cfgVals[k]; end return defaults[k]; end,
        set = function(k, val) cfgVals[k] = val; return true; end,
    },
    server = { service = function(name) return sp.service(name); end },
};
local ma = require('dlac\\feature\\modapi');
local realS = ma.build({ id = 'dnc-status', job = 'dnc', label = 'DNC Status', jobs = { 'DNC' } });
check(realS.server.service('dncStatus') == svc and realS.server.service('nope') == nil,
      'S.server.service reaches a pack service, nil for none');

local drawn = {};
local function text(s) drawn[#drawn + 1] = s; end
local ui = {
    COL = { head = 'head', dim = 'dim', ok = 'ok', warn = 'warn', err = 'err', lit = 'lit' },
    text = function(col, s) text(col .. ':' .. s); end,
    dim = function(s) text('dim:' .. s); end,
    ok = function(s) text('ok:' .. s); end,
    warn = function(s) text('warn:' .. s); end,
    err = function(s) text('err:' .. s); end,
    sameLine = function() end, space = function() end,
    section = function(label, tip, body) body(); end,
    toggle = function() return nil; end,
};
local function has(s)
    for _, d in ipairs(drawn) do if d:find(s, 1, true) then return true; end end
    return false;
end
local win = { begins = 0, flags = nil };
_G.ImGuiWindowFlags_NoMove = 4;
local imguiStub = {
    SetNextWindowPos = function() end,
    Begin = function(name, open, fl) win.begins = win.begins + 1; win.flags = fl; return true; end,
    End = function() end,
    GetWindowPos = function() return 60, 360; end,
};
local hudHidden = false;
package.loaded['dlac\\feature\\gamehud'] = { hidden = function() return hudHidden; end };
local ctx = { ui = ui, S = S, imgui = imguiStub };

status.reset();
player = { job = 19, level = 75, tp = 300, buffs = {}, timers = {} };
drawn = {};
helper.panel(ctx);
check(has('dim:Waiting for the server.'), 'the panel says it is waiting before the first state');
check(status.debugState().wanted, 'and the open panel is demand');
time = time + 1; status.want(); frame();
reply(last[6], { memory = 0, target = 0, prices = { 600, 900, 1200 }, base = 1, perStack = 3, rev = 1 });
win.begins = 0;
helper.window(ctx);
check(win.begins == 0, 'in town (no memory, no stacks, no fight) the window stays away');
drawn = {};
helper.panel(ctx);
check(has('dim:  Nothing remembered') and has('head:Unbroken Rhythm 0/3') and has('dim:Not fighting'),
      'the panel shows every switched-on section, empty ones included');
check(has('warn:  Next stack 600 TP'), 'and the next stack\'s price, orange when TP is short');

push({ memory = 5 + 2 * 16, target = 291, levels = { 4, 0, 0, 0 }, seconds = { 75, 0, 0, 0 },
       prices = { 600, 900, 1200 }, base = 1, perStack = 3, rev = 2 });
player.buffs = { [472] = true, [624] = true };
player.timers = { [472] = 50, [624] = 20 };
player.tp = 2000;
drawn = {};
helper.window(ctx);
check(win.begins == 1, 'a fight brings the window');
check(has('ok:  Quickstep 5') and has('dim:puts on 4') and has('ok:  Box Step 2'),
      'the memory, and what one stack lets it put on');
check(has('head:Unbroken Rhythm 1/3') and has('dim:20s') and has('dim:  Next stack 900 TP'),
      'the stacks, the drop timer, the next price');
check(has('head:Goblin Smithy') and has('ok:  Quickstep 4') and has('dim:1:15'), 'the target and its Steps');
check(win.flags % 8 < 4, 'not locked: the window can be dragged');
cfgVals.locked = true;
helper.window(ctx);
check(win.flags % 8 >= 4, 'locked: NoMove');
cfgVals.targetEffects = false;
drawn = {};
helper.window(ctx);
check(not has('Goblin Smithy') and has('Perpetual Step'), 'a section switched off is not drawn');
cfgVals.window = false;
win.begins = 0;
helper.window(ctx);
check(win.begins == 0, 'the window switched off draws nothing');
cfgVals.window, cfgVals.targetEffects = nil, nil;
hudHidden = true;
helper.window(ctx);
check(win.begins == 0, 'and nothing while the game HUD is hidden');
hudHidden = false;
player.job = 1;
helper.window(ctx);
check(win.begins == 0, 'nor on another job');
player.job = 19;
local wantedBefore = status.debugState().wanted;
cfgVals.rememberedSteps, cfgVals.rhythm, cfgVals.targetEffects = false, false, false;
time = time + 10;
helper.window(ctx);
check(wantedBefore and not status.debugState().wanted, 'every section off: no demand at all');
cfgVals = {};

local noServer = { ui = ui, S = { cfg = S.cfg, server = { service = function() return nil; end } }, imgui = imguiStub };
drawn = {};
helper.panel(noServer);
check(has('dim:This server does not send Dancer status.'), 'without the pack service the panel says so');
win.begins = 0;
helper.window(noServer);
check(win.begins == 0, 'and draws no window');

-- The loader: a module built for another server is skipped quietly.
local skipped, failed, inits = {}, { total = 0, failed = {} }, 0;
jh.loadAll({
    names = { 'dnc-status', 'plain' },
    loadModule = function(id)
        if id == 'plain' then
            return true, { api = jh.API, label = 'P', jobs = { 'BST' }, panel = function() end };
        end
        return true, helper;
    end,
    ledger = failed, emit = function() end, server = 'cexi', skipped = skipped,
});
check(jh.count() == 1 and jh.list()[1].id == 'plain', 'on CatsEyeXI the DNC Status helper does not load');
check(#skipped == 1 and skipped[1].id == 'dnc-status' and #failed.failed == 0, 'and is listed as skipped, not failed');

print(string.format('ascensionxi_dncstatus: %d checks passed', checks));
