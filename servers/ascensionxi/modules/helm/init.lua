-- Source verified against AscensionXI a1e543095b, 2026-09-14.
-- Prices/quests are pack facts; core consumes the gathering service.
local points = require('dlac\\servers\\ascensionxi\\modules\\helm\\status');
local skills = require('dlac\\servers\\ascensionxi\\modules\\helm\\skills');
local M = {
    points = points,
    skills = skills,
    sharedGear = true,
    vendor = 'Helmsley, Lower Jeuno',
    upgradeCost = 10000,
    rows = {
        { field = 'Field Cap', fieldId = 26550, worker = 'Worker Cap', workerId = 26551,
          reserved = 'Worker Cap +1', reservedId = 26556, cost = 2500 },
        { field = 'Field Tunica', fieldId = 14374, worker = 'Worker Tunica', workerId = 14375,
          reserved = 'Worker Tunica +1', reservedId = 26552, quest = 'Rock Bottom',
          guide = 'Level 10: speak to Bumbrak in Bastok Mines. He gives 50 pickaxes. Mine successfully 10 times (Zeruhn Mines is suggested), then return to him.' },
        { field = 'Field Gloves', fieldId = 14817, worker = 'Worker Gloves', workerId = 14818,
          reserved = 'Worker Gloves +1', reservedId = 26553, cost = 2500 },
        { field = 'Field Hose', fieldId = 14297, worker = 'Worker Hose', workerId = 14298,
          reserved = 'Worker Hose +1', reservedId = 26554, quest = 'Branch Manager',
          guide = "Level 10: speak to Ferdinaux in Northern San d'Oria. He gives 50 hatchets. Log successfully 10 times (East Ronfaure is suggested), then return to him." },
        { field = 'Field Boots', fieldId = 14176, worker = 'Worker Boots', workerId = 14177,
          reserved = 'Worker Boots +1', reservedId = 26555, quest = 'Grass Roots',
          guide = 'Level 10: speak to Mimu-Bumimu in Port Windurst. She gives 50 sickles. Harvest successfully 10 times (West Sarutabaruta is suggested), then return to her.' },
    },
};

require('dlac\\gear\\serverpack').provide('gathering', M);

points._send = function(packet)
    AshitaCore:GetPacketManager():AddOutgoingPacket(points.PKT, packet);
    require('dlac\\feature\\sendlog').note(points.PKT, 'HELM status');
    return true;
end;

if ashita and ashita.events and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_in', 'dlac_axi_helm_points', function(e)
        if e.id == 0x00A or e.id == 0x00B then points.reset(true); return; end
        if e.id == points.PKT and points.onPacket(e.data) then e.blocked = true; end
    end);
end

return M;
