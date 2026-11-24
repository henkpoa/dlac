table.insert(package.loaders or package.searchers, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\','/')) .. '.lua'); end
end);
local checks = 0;
local function check(c, message) checks=checks+1; assert(c,message); end
local base = 'dlac\\servers\\ascensionxi\\modules\\rnggauge\\';
local wire, gauge, draw = require(base..'wire'),require(base..'gauge'),require(base..'draw');
local now, sent, stopped, player, shown = 0, {}, {}, {job=11,level=20,id=1}, true;
gauge._clock=function() return now; end;
gauge._player=function() return player; end;
gauge._shown=function() return shown; end;
gauge._send=function(p) sent[#sent+1]=p; return true; end;
gauge._direct=function(p) stopped[#stopped+1]=p; end;
local function reset() now=0; sent={}; stopped={}; shown=true; player={job=11,level=20,id=1}; gauge.reset(); end
local function subscribe()
    gauge.pump(); now=3; gauge.pump();
    check(#sent==1,'one subscribe after settle');
    gauge.onFrame({op=0xD3,seq=sent[1][6],status=0,payload=wire.encodeState({enabled=true,rev=1})});
end
local function push(phase,left,total,rev)
    gauge.onFrame({op=0xDB,seq=0,status=0,payload=wire.encodeState({enabled=true,phase=phase,remaining=left,total=total,rev=rev})});
end
local vector=wire.encodeState({enabled=true,phase=2,remaining=2300,total=4300,rev=65535});
local hex={}; for i=1,#vector do hex[i]=string.format('%02X',vector:byte(i)); end
check(table.concat(hex,' ')=='01 0B 01 02 FC 08 00 00 CC 10 00 00 FF FF','shared server vector');
check(wire.state(vector).remaining==2300,'decode milliseconds');
check(wire.state(wire.encodeState({enabled=true,remaining=70000,total=80000})).remaining==70000,'long recovery cannot wrap');
check(wire.state('')==nil,'reject short state');
check(wire.state(string.char(2)..vector:sub(2))==nil,'reject other protocol');
check(wire.state(wire.encodeState({remaining=2,total=1}))==nil,'reject impossible fill');
check(wire.newer(0,65535) and not wire.newer(65535,0),'revision wrap');
reset(); subscribe();
check(gauge.view().progress==1,'idle starts full');
push(1,4300,4300,2); now=4;
check(gauge.view().progress==0 and gauge.view().phase==1,'aim does not pretend to be cooldown');
push(2,2300,2300,3); now=5.15;
check(math.abs(gauge.view().progress-0.5)<0.0001,'local clock smoothly fills half recovery');
for i=1,2000 do gauge.pump(); gauge.view(); end
check(#sent==1,'render and idle frames never poll server');
push(2,9000,9000,2);
check(gauge.view().remaining<2,'old push cannot rewind cooldown');
now=6.31; check(gauge.view().phase==0 and gauge.view().progress==1,'full without another request');
check(gauge.view().flash>0,'completion has brief visual pulse');
push(2,1900,1900,4); check(gauge.view().progress==0,'melee recovery restarts fill');
shown=false; gauge.pump(); check(gauge.view()==nil and #stopped==1,'hide stops subscription');
shown=true; now=8; gauge.pump(); check(#sent==2,'show resubscribes once');
gauge.zoneOut(); push(2,5000,5000,99); check(gauge.view()==nil,'zone discards late frames');
gauge.zoneIn(); now=11; gauge.pump(); check(#sent==3,'zone subscribes once after settling');
reset(); player.job=6; gauge.pump(); now=10; gauge.pump(); check(#sent==0,'other jobs never subscribe');
player.job=11; player.level=19; gauge.pump(); now=20; gauge.pump(); check(#sent==0,'RNG19 never subscribes');
reset(); subscribe(); player.job=6; gauge.pump(); check(gauge.view()==nil and #stopped==1,'job change stops and hides');
reset(); gauge.pump(); now=3; gauge.pump();
gauge.onFrame({op=0xD3,seq=sent[1][6],status=1}); now=1000; gauge.pump();
check(#sent==1 and gauge.view()==nil,'old servers stop silently');
reset(); gauge.pump(); now=3; gauge.pump();
gauge.onFrame({op=0xD3,seq=sent[1][6],status=3}); now=4; gauge.pump(); check(#sent==1,'busy backs off');
now=5; gauge.pump(); check(#sent==2,'busy retries after two seconds');
reset(); gauge.pump();
for i=1,400 do now=i; gauge.pump(); end
check(#sent==4 and gauge.debugState().dormant,'silent server bounded retries');

local text, calls = {}, 0;
local dl=setmetatable({}, {__index=function(_,method) return function(_, ...)
    calls=calls+1;
    if method=='AddText' then text[#text+1]=select(3,...); end
end end});
for _,scale in ipairs({0.6,1,1.5,3}) do
    for _,phase in ipairs({0,1,2}) do
        draw.panel(dl,function(c) return c; end,10,20,scale,
            {phase=phase,progress=phase==0 and 1 or 0.5,remaining=phase==2 and 1.2 or 0,flash=0.5,now=5},
            function(s) return #s*7,14; end);
    end
end
check(calls>100,'real renderer executes at supported scales');
for _,s in ipairs(text) do check(s=='1.2','gauge only draws countdown, no ready label'); end
local handlers={}; ashita={events={register=function(kind,name,fn) handlers[name]=fn; end}};
local sp=require('dlac\\gear\\serverpack'); sp._configLoader=function() return {server='ascensionxi'}; end; sp.init();
local mod=require(base..'init');
check(sp.service('rngGauge')==gauge,'service available to shared gauge command');
check(mod.ownsCommand(11) and not mod.ownsCommand(7),'command only belongs to RNG');
check(require('dlac\\servers\\ascensionxi\\transport').producerOf(0xD3)=='rng gauge','transport slot ownership');
local mounted=false; for _,m in ipairs(sp.modules()) do mounted=mounted or m=='rnggauge'; end
check(mounted,'AXI mounts gauge');
local cexi=dofile('servers/cexi/manifest.lua').modules;
for _,m in ipairs(cexi) do check(m~='rnggauge','CatsEye never mounts gauge'); end
local packet={id=0x1E0,data=string.char(0xE0,0x0D,0,0,0xDB,0,0,0)..vector..'\0\0'};
handlers.dlac_axi_rnggauge(packet); check(packet.blocked,'custom packet blocked from retail client');
print(string.format('Ranger gauge: %d checks passed',checks));
