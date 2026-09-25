--[[
    ascensionxi/ascension -- AscensionXI's ascension counts as a server-pack
    module (ADR 0035). status.lua is the whole feature (the 0x1E0 op 0xA0
    client); this init wires it to the shared 0x1E0 send gate and the packet
    stream, hands its beat to the servermods pump, and provides 'prestige' --
    the service gear\jobgate folds over raw job levels. AscensionXI's server
    treats a job with an ascension as level 75 for lockstyle, which is the
    rule that fold already applies for CatsEyeXI's prestige.
]]--

local status = require('dlac\\servers\\ascensionxi\\modules\\ascension\\status');

pcall(function()
    require('dlac\\gear\\serverpack').provide('prestige', status);
end);

local transport = require('dlac\\servers\\ascensionxi\\transport');
status._clock    = transport._clock;
status._send     = function(packet) return transport.send(packet, 'ascension status'); end;
status._received = transport.received;

local _jgok, jobgate = pcall(require, 'dlac\\gear\\jobgate');
if _jgok and type(jobgate) == 'table' then
    status._levels = function() return jobgate.reader(); end;
end

status.reset();

if ashita and ashita.events and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_in', 'dlac_axi_ascension_status', function(e)
        if e.id == 0x00A then
            local data = e.data or '';
            local id = (#data >= 8) and (data:byte(5) + data:byte(6) * 256 + data:byte(7) * 65536 + data:byte(8) * 16777216) or nil;
            status.zoneIn(id);
            return;
        end
        if e.id == 0x00B then status.zoneOut(); return; end
        if e.id == status.PKT and status.onPacket(e.data) then e.blocked = true; end
    end);
end

return {
    pump = function() status.touch(); end,
};
