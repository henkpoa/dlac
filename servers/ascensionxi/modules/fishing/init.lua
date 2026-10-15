-- AscensionXI fishing (docs/reference/ascensionxi-fishing.md). The server
-- reports Fishing points, the skill in tenths, the wardrobe slots bought from
-- Fennella and the guild rank (op 0x83); the fishing tables in
-- data/fishdb.lua carry the rest, Fennella's shelf and the +10 hook rule
-- included. `moveCatches` arms feature/fishstorage, the Mog Case / Satchel
-- mover for what you reel in.
local status = require('dlac\\servers\\ascensionxi\\modules\\fishing\\status');
local M = {
    status = status,
    moveCatches = true,
};

require('dlac\\gear\\serverpack').provide('fishing', M);

local transport = require('dlac\\servers\\ascensionxi\\transport');
status._clock = transport._clock;
status._send = function(packet) return transport.send(packet, 'fishing status'); end;
status._received = transport.received;

-- What can move the numbers: a reel (0x110 mode 3, RequestEndMiniGame -- a
-- landed fish banks its points before the reply leaves the server) and an
-- event option (0x05B: Fennella's shelf, her trade-up confirm).
M.REEL_MODE = 3;
function M.onOutgoing(id, data)
    if id == 0x110 and type(data) == 'string' and #data >= 15 and data:byte(15) == M.REEL_MODE then
        status.markStale();
    elseif id == 0x05B then
        status.markStale();
    end
end

if ashita and ashita.events and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_in', 'dlac_axi_fishing_status', function(e)
        if e.id == 0x00A or e.id == 0x00B then status.reset(true); return; end
        if e.id == status.PKT and status.onPacket(e.data) then e.blocked = true; end
    end);
    ashita.events.register('packet_out', 'dlac_axi_fishing_events', function(e)
        if e.blocked or (e.id ~= 0x110 and e.id ~= 0x05B) then return; end
        pcall(M.onOutgoing, e.id, type(e.data_modified) == 'string' and #e.data_modified > 0
            and e.data_modified or e.data);
    end);
end

return M;
