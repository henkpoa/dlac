--[[
    vanaheim/gearvault -- the Gear Vault integration's mount (ADR 0035 pack
    module; design: docs/design/gear-vault-integration.md). Slice 1: the
    0x1E0 wire client + the read-only vault MIRROR, published to core as the
    serverpack service 'gearvault' -- which is how vaulted gear becomes an
    ownership tier (GV5) without core ever requiring a servers\ path.

    This init owns only the Ashita glue: the packet_in tap (0x1E0 frames to
    the client, 0x00A as the zone probe trigger), the outgoing `!vault` chat
    watch, the module pump (per the servermods contract), the `/dl vault`
    status command, and the service registration. Every rule and every byte
    lives in vaultclient.lua, which runs headless.
]]--

local base = 'dlac\\servers\\vanaheim\\modules\\gearvault\\';

local vc = require(base .. 'vaultclient');

-- Production seams -----------------------------------------------------------

vc._send = function(p)
    pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(vc.PKT, p); end);
    pcall(function() require('dlac\\feature\\sendlog').note(vc.PKT, 'gear vault'); end);
end;

vc._say = function(msg)
    local ok, cf = pcall(require, 'dlac\\chatfmt');
    if ok and type(cf) == 'table' and type(cf.print) == 'function' then
        cf.print('[dlac] ' .. tostring(msg));
    else
        print('[dlac] ' .. tostring(msg));
    end
end;

-- A fresh mirror changes ownership answers NOW, not at the next ~4s
-- availability heartbeat.
vc._onFresh = function()
    pcall(function() require('dlac\\gear\\ownedcache').resetCache(); end);
end;

-- The service core consults (gearimport's vault fold, prune's guard, and
-- slice 2's tab). counts()/rows() hand out the live tables -- consumers
-- read, never write (the ownedcache _splitOverride discipline).
pcall(function()
    require('dlac\\gear\\serverpack').provide('gearvault', {
        counts     = function() return vc.mirror.counts; end,
        rows       = function() return vc.mirror.rows; end,
        vaultCount = function() return vc.mirror.vaultCount; end,
        fresh      = function() return vc.mirror.fresh == true; end,
        state      = vc.state,
        refresh    = vc.refresh,
        statusLine = vc.statusLine,
    });
end);

-- Ashita glue (all guarded: headless there is no ashita global) ---------------

pcall(function()
    ashita.events.register('packet_in', 'dlac_gearvault_packet_in', function(e)
        if e.id == 0x00A then
            vc.noteZoneIn();
            return;
        end
        if e.id ~= vc.PKT then return; end
        local ok, consumed = pcall(function()
            return vc.onFrame(vc.parseFrame(e.data_modified or e.data));
        end);
        -- The retail client has no idea what 0x1E0 is: block every vault-
        -- partition frame we recognised so it never reaches the game.
        if ok and consumed == true then e.blocked = true; end
    end);
end);

-- `!vault ...` in the player's own chat may mutate the store (the chat skin
-- shares the service with our packets) -- resync after it settles. Watch the
-- OUTGOING command, the eboxclient's `!box` idiom.
pcall(function()
    ashita.events.register('command', 'dlac_gearvault_chatwatch', function(e)
        local raw = string.lower(tostring(e.command or ''));
        if raw:match('^/?!vault') or raw:match('^!vault') then
            vc.noteVaultChat();
        end
    end);
end);

-- `/dl vault` -- the slice-1 field probe: state, mirrored count, and a
-- `sync` verb to force a refresh. Registered here like every module command
-- (the giftbox pattern); gearui's /dl dispatch never learns vault words.
pcall(function()
    ashita.events.register('command', 'dlac_gearvault_cmd', function(e)
        local raw = string.lower(tostring(e.command or ''));
        local rest = raw:match('^/dl%s+vault%s*(.*)$');
        if rest == nil then return; end
        e.blocked = true;
        if rest:match('^sync') then
            vc.refresh();
            vc._say('gear vault: sync requested.');
        else
            vc._say(vc.statusLine());
        end
    end);
end);

-- THE TAB (slice 2): registered on the uihost like any first-party module,
-- so it renders under gearui's tabGuard (a broken tab costs itself, never
-- the frame). It exists only where this pack mounts, and shows through the
-- gear-only surface default because featuregate never hides a label it
-- cannot name (ADR 0037).
pcall(function()
    local vui  = require(base .. 'vaultui');
    local uhost = require('dlac\\ui\\uihost');
    uhost.register({
        name = 'gearvault',
        tabs = { { label = 'Gear Vault', render = function(j, lv) vui.render(j, lv); end } },
    });
end);

-- The module contract's beat: feed the client readiness + the main-job edge.
local function mainJob()
    local j = nil;
    pcall(function() j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
    return j;
end

return {
    pump = function()
        local j = mainJob();
        local ready = (type(j) == 'number' and j ~= 0);
        if ready then vc.noteJob(j); end
        vc.pump(ready);
    end,
};
