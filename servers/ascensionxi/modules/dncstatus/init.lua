--[[
    ascensionxi/dncstatus -- the Dancer status channel, as a server-pack
    module (ADR 0035). AscensionXI gives the Dancer Perpetual Step (it
    remembers the Steps on the party's last kills) and Unbroken Rhythm
    (TP-bought stacks that raise how much of that memory Perpetual Step puts
    back). Server documentation/custom/perpetual-step.md, unbroken-rhythm.md
    and dnc-status.md.

    This module draws nothing. It provides the `dncStatus` service that the
    DNC Status Job helper (jobhelpers\dnc\dnc-status) reads through
    S.server.service:

        service.want()     the helper is showing the status (every frame)
        service.view()     status.view(): the joined view, or nil and why
        service.debug()    the channel's state, for /dl dnc

    This init owns only the Ashita glue: the shared 0x1E0 send gate, the tap
    on slot 1 of the 0xD0-0xDF partition (the retail client has no handler
    for these frames), the client reads (job, level, TP, buffs and their
    timers, entity names), the zone and unload edges, and `/dl dnc` (the
    channel's state in chat). Every rule runs headless in status.lua and
    wire.lua.
]]--

local base = 'dlac\\servers\\ascensionxi\\modules\\dncstatus\\';
local wire   = require(base .. 'wire');
local status = require(base .. 'status');

local transport = require('dlac\\servers\\ascensionxi\\transport');
status._clock    = transport._clock;
status._send     = function(packet) return transport.send(packet, 'dnc status'); end;
status._received = transport.received;
status._abandon  = transport.abandon;
status._notePush = transport.notePush;
status._direct   = function(packet)
    AshitaCore:GetPacketManager():AddOutgoingPacket(wire.PKT, packet);
end;

-- A status timer's seconds left: foodwatch owns THE decode of the client's
-- raw timer values (sixtieths since the Vana'diel epoch, wrapping), so this
-- module asks it rather than carrying a second copy.
local function secondsLeft(raw)
    local out = nil;
    pcall(function()
        local fw = require('dlac\\feature\\foodwatch');
        out = fw._remaining(raw, os.time());
    end);
    return out;
end

-- The player read is reused for 0.1 s: the window and the panel can both ask
-- in one frame.
local cache, cacheAt = nil, nil;
status._player = function()
    local now = transport._clock();
    if cacheAt ~= nil and now - cacheAt < 0.1 and now >= cacheAt then return cache; end
    local out = nil;
    pcall(function()
        local mm = AshitaCore:GetMemoryManager();
        local p = mm:GetPlayer();
        local ids = p:GetBuffs();
        local ts = nil;
        pcall(function() ts = p:GetStatusTimers(); end);
        local buffs, timers = {}, {};
        if ids ~= nil then
            for i = 0, 32 do
                local id = ids[i];
                if type(id) == 'number' and id > 0 and id < 1024 then
                    buffs[id] = true;
                    if ts ~= nil and ts[i] ~= nil and timers[id] == nil then
                        timers[id] = secondsLeft(ts[i]);
                    end
                end
            end
        end
        local tp = nil;
        pcall(function() tp = mm:GetParty():GetMemberTP(0); end);
        out = { job = p:GetMainJob(), level = p:GetMainJobLevel(), tp = tp, buffs = buffs, timers = timers };
    end);
    cache, cacheAt = out, now;
    return out;
end;

status._entityName = function(index)
    local name = nil;
    pcall(function()
        local n = AshitaCore:GetMemoryManager():GetEntity():GetName(index);
        if type(n) == 'string' and n ~= '' then name = n; end
    end);
    return name;
end;

local service = {
    want  = status.want,
    view  = status.view,
    debug = status.debugState,
};

pcall(function()
    require('dlac\\gear\\serverpack').provide('dncStatus', service);
end);

local function say(msg)
    local ok, cf = pcall(require, 'dlac\\chatfmt');
    if ok and type(cf) == 'table' and type(cf.info) == 'function' then pcall(cf.info, msg); return; end
    print('[dlac] ' .. msg);
end

local function report()
    local d = status.debugState();
    local st = d.state;
    local channel = tostring(d.sub or 'idle');
    if d.dormant then channel = channel .. ' (this server sends no Dancer status)'; end
    if d.sub == nil and not d.dormant then
        channel = channel .. (d.wanted and ' (asks after the zone settles)' or ' (nothing is showing it)');
    end
    local detail = 'no state yet';
    if st ~= nil then
        local m = st.memoryLevels;
        detail = string.format('memory %d/%d/%d/%d, target %d, dazes %d/%d/%d/%d, prices %d/%d/%d, rev %d',
            m[1], m[2], m[3], m[4], st.target, st.levels[1], st.levels[2], st.levels[3], st.levels[4],
            st.prices[1], st.prices[2], st.prices[3], st.rev);
    end
    say(string.format('DNC status: channel %s; %s', channel, detail));
end

if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    pcall(function()
        ashita.events.register('command', 'dlac_axi_dncstatus_cmd', function(e)
            local raw = tostring(e.command or '');
            local args = raw:match('^/[dD][lL]%s+[dD][nN][cC](.*)$')
                or raw:match('^/[dD][lL][aA][cC]%s+[dD][nN][cC](.*)$');
            if args == nil then return; end
            if args ~= '' and not args:match('^%s') then return; end   -- /dl dncfoo: not ours
            e.blocked = true;
            report();
        end);
    end);

    pcall(function()
        ashita.events.register('packet_in', 'dlac_axi_dncstatus', function(e)
            if e.id == 0x00A then pcall(status.zoneIn); return; end
            if e.id == 0x00B then pcall(status.zoneOut); return; end
            if e.id ~= wire.PKT then return; end
            local data = e.data_modified or e.data;
            if type(data) ~= 'string' or #data < 8 then return; end
            if not wire.ours(data:byte(5)) then return; end
            -- Blocked first, malformed frames included.
            e.blocked = true;
            pcall(function() status.onFrame(wire.incoming(data)); end);
        end);
    end);

    pcall(function()
        ashita.events.register('unload', 'dlac_axi_dncstatus_unload', function()
            pcall(status.unload);
        end);
    end);
end

return {
    pump = function() status.pump(); end,
};
