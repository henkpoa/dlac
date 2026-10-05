--[[
    ascensionxi/telemetry -- AscensionXI's combat telemetry and AutoAcc, as a
    server-pack module (ADR 0035). The server publishes, for the mob the
    player fights, the accuracy inputs dlac cannot see (server
    documentation/custom/combat-telemetry.md); autoacc.lua turns them into
    the AutoAcc decision core asks for through the serverpack service
    'autoacc' at the single equipment send (dispatch.lua).

    This init owns only the Ashita glue: the shared 0x1E0 transport seams, the
    packet tap that blocks the whole 0xC0-0xCF partition before anything
    decodes it (T7: the retail client has no handler for these frames), the
    zone and unload edges, the pump, and the service registration. Every
    rule runs headless in client.lua, autoacc.lua, formula.lua and wire.lua.
]]--

local base = 'dlac\\servers\\ascensionxi\\modules\\telemetry\\';
local wire = require(base .. 'wire');
local client = require(base .. 'client');
local autoacc = require(base .. 'autoacc');

local transport = require('dlac\\servers\\ascensionxi\\transport');
client._clock    = transport._clock;
client._send     = function(packet) return transport.send(packet, 'combat telemetry'); end;
client._received = transport.received;
client._abandon  = transport.abandon;
client._direct   = function(packet)
    AshitaCore:GetPacketManager():AddOutgoingPacket(wire.PKT, packet);
end;
client._onFrame  = function(frame) autoacc.noteFrame(frame); end;

autoacc._clock = transport._clock;
autoacc._want  = client.want;
autoacc._ask   = client.ask;

-- The model's view of the world. Everything below is guarded: headless,
-- there is no AshitaCore and the readers answer nil.
local oracle = require('dlac\\gear\\gearoracle');
local catalog = require('dlac\\gear\\catalogindex');

-- LSB augment extdata (server exdata/augment_standard.h): byte 0 is the
-- kind (0x02 augmented, 0x03 bundled), then five 16-bit augments. A
-- signature or charge timer alone is not an augment.
local function augmentedExtra(extra)
    if type(extra) ~= 'string' or #extra < 12 then return false; end
    local kind = extra:byte(1);
    if kind ~= 0x02 and kind ~= 0x03 then return false; end
    for i = 3, 12 do if extra:byte(i) ~= 0 then return true; end end
    return false;
end

-- The worn outfit the way the server hashes it (EquipRev): container,
-- slot-in-container and id per equip slot, and whether the copy is augmented.
autoacc._worn = function()
    local refs = {};
    for slot = 0, 15 do
        local w = oracle.wornItem(slot);
        if w ~= nil and w.id ~= nil and w.id ~= 0 and w.id ~= 65535 then
            local container, index = oracle.wornLocation(slot);
            refs[slot] = { container or 0, index or 0, w.id, augmentedExtra(w.extra) };
        end
    end
    return refs;
end;

-- Jobs, levels and buffs as the client sees them, and the battle target's
-- server id while engaged (the cursor target is the battle target unless the
-- player tabbed away; a mismatch only ever holds pieces on).
autoacc._player = function()
    local out = { buffs = {} };
    pcall(function()
        local mm = AshitaCore:GetMemoryManager();
        local p = mm:GetPlayer();
        out.mainJob, out.mainLevel = p:GetMainJob(), p:GetMainJobLevel();
        out.subJob, out.subLevel = p:GetSubJob(), p:GetSubJobLevel();
        for _, id in pairs(p:GetBuffs() or {}) do
            if type(id) == 'number' and id >= 0 and id < 1024 then out.buffs[id] = true; end
        end
        local me = mm:GetParty():GetMemberTargetIndex(0);
        local ent = mm:GetEntity();
        if me ~= nil and ent:GetStatus(me) == 1 then
            local index = mm:GetTarget():GetTargetIndex(0);
            if type(index) == 'number' and index > 0 then out.target = ent:GetServerId(index); end
        end
    end);
    return out;
end;

autoacc._record = function(itemId) return catalog.rawById(itemId); end;

autoacc._idOf = function(name)
    local rec = oracle.lookup(name);
    if type(rec) == 'table' and rec.Id ~= nil then return rec.Id; end
    local _, _, byName = catalog.flat();
    rec = byName[string.lower(tostring(name))];
    return (type(rec) == 'table') and rec.Id or nil;
end;

local _data = nil;
autoacc._data = function()
    if _data == nil then
        local function load(name)
            local ok, d = pcall(require, 'dlac\\data\\' .. name);
            return (ok and type(d) == 'table') and d or {};
        end
        _data = { gearsets = load('gearsets'), latentstats = load('latentstats'),
                  levelscaling = load('levelscaling'), itemscripts = load('itemscripts') };
    end
    return _data;
end;

-- T6: the os.time fallback ticks once a second; every timer here would lie.
if transport._clock == os.time then
    client.refuse('no socket.gettime: telemetry needs a wall clock finer than a second');
end

local _charId = nil;
client._charId = function() return _charId; end;

local monitor = require(base .. 'monitor');
monitor._client, monitor._autoacc = client, autoacc;

pcall(function()
    require('dlac\\gear\\serverpack').provide('autoacc', autoacc);
    require('dlac\\gear\\serverpack').provide('combatTelemetry', client);
    -- gearui's one floating-window site draws it (core never requires servers\).
    require('dlac\\gear\\serverpack').provide('autoaccMonitor', monitor);
end);

-- The Gear Helpers row and its panel, through the one helper registry.
pcall(function()
    local auto = require('dlac\\ui\\automationsui');
    if type(auto.registerHelper) ~= 'function' then return; end
    auto.registerHelper({
        key = 'autoacc',
        row = function()
            local r = { key = 'autoacc', name = 'AutoAcc', kind = 'gear rule (armour, hit cap)', level = 0, max = 1 };
            pcall(function() r.level, r.txt = monitor.status(); end);
            return r;
        end,
        panel = function() monitor.panel(); end,
    });
end);

-- /dl autoacc: the floating readout.
pcall(function()
    ashita.events.register('command', 'dlac_axi_autoacc_cmd', function(e)
        local raw = string.lower(tostring(e.command or ''));
        if raw:match('^/dl%s+autoacc%s*$') == nil and raw:match('^/dlac%s+autoacc%s*$') == nil then return; end
        e.blocked = true;
        monitor.toggle();
    end);
end);

-- The tap. Installed at load, before the first HELLO can go out.
pcall(function()
    ashita.events.register('packet_in', 'dlac_axi_combat_telemetry', function(e)
        if e.id == 0x00A then
            local d = e.data or '';
            if #d >= 8 then _charId = d:byte(5) + d:byte(6) * 256 + d:byte(7) * 65536 + d:byte(8) * 16777216; end
            pcall(client.zoneIn);
            pcall(autoacc.zoneIn);
            return;
        end
        if e.id == 0x00B then
            pcall(client.zoneOut);
            pcall(autoacc.zoneIn);
            return;
        end
        if e.id ~= wire.PKT then return; end
        local data = e.data_modified or e.data;
        if type(data) ~= 'string' or #data < 8 then return; end
        local op = data:byte(5);
        if op < wire.OP_FIRST or op > wire.OP_LAST then return; end
        -- Every frame of the partition is blocked first, malformed and
        -- unknown ops included, so no error below can let one through.
        e.blocked = true;
        pcall(function() client.onFrame(wire.incoming(data)); end);
    end);
end);

-- Unloading or reloading dlac: STOP with END_SESSION, straight to the packet
-- manager, so the server stops pushing frames nothing would block.
pcall(function()
    ashita.events.register('unload', 'dlac_axi_combat_telemetry_unload', function()
        pcall(client.unload);
    end);
end);

return {
    pump = function()
        client.pump();
        autoacc.pump();
    end,
};
