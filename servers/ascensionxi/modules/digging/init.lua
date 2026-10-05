-- AscensionXI Chocobo Digging (docs/reference/ascensionxi-digging.md).
-- The server reports skill, rank and allowance (the !digging numbers), so the
-- dig rank here is exact and dlac's CatsEye rank guessing stays off: our
-- three-second zone wait would read as Expert in the first-dig timing.
-- Digs use Gysahl Greens from the inventory first, then from Void Storage.
local status = require('dlac\\servers\\ascensionxi\\modules\\digging\\status');
local M = {
    status = status,
    exactRank = true,
    voidGreens = true,
};

require('dlac\\gear\\serverpack').provide('digging', M);

local transport = require('dlac\\servers\\ascensionxi\\transport');
status._clock = transport._clock;
status._send = function(packet) return transport.send(packet, 'digging status'); end;
status._received = transport.received;

if ashita and ashita.events and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_in', 'dlac_axi_digging_status', function(e)
        if e.id == 0x00A or e.id == 0x00B then status.reset(true); return; end
        if e.id == status.PKT and status.onPacket(e.data) then e.blocked = true; end
    end);
end

return M;
