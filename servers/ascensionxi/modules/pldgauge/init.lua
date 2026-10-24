--[[
    ascensionxi/pldgauge -- the Paladin Divine Guard gauge, as a server-pack
    module (ADR 0035). AscensionXI gives the Paladin two stances, Divine
    Guard and Divine Fury, and three points that shield blocks earn in
    Divine Guard and Palisade, Sacred Ward and Martyr's Grace spend (server
    documentation/custom/pld-divine-guard.md). The server decides every
    point; this module draws them, the White Mage gauge's frame with shields
    and crossed great swords.

    Passive by design: no tab, no Job helper row. The gauge shows by itself
    while the main job is PLD and a stance is up, and hides otherwise.

        /dl gauge            show or hide it (hidden also stops the requests)
        /dl gauge lock       stop it moving when dragged (unlock to move again)
        /dl gauge scale 1.5  size it (0.6 - 3)
        /dl gauge demo       play every state with no server (again to stop)
        /dl gauge status     the channel's state in chat

    `/dl gauge` is shared with the White Mage gauge: on a main Paladin this
    module answers it, on any other job whmgauge does (both handlers read
    the main job; see ownsCommand).

    This init owns only the Ashita glue: the shared 0x1E0 send gate, the tap
    on slot 2 of the 0xD0-0xDF partition (0xD2, 0xDA; the retail client has
    no handler for these frames), the zone and unload edges, the window, and
    a small settings file. Every rule runs headless in gauge.lua, wire.lua
    and draw.lua.
]]--

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui = try('imgui');

local base = 'dlac\\servers\\ascensionxi\\modules\\pldgauge\\';
local wire  = require(base .. 'wire');
local gauge = require(base .. 'gauge');
local draw  = require(base .. 'draw');
local demo  = require(base .. 'demo');

local transport = require('dlac\\servers\\ascensionxi\\transport');
gauge._clock    = transport._clock;
gauge._send     = function(packet) return transport.send(packet, 'pld gauge'); end;
gauge._received = transport.received;
gauge._abandon  = transport.abandon;
gauge._notePush = transport.notePush;
gauge._direct   = function(packet)
    AshitaCore:GetPacketManager():AddOutgoingPacket(wire.PKT, packet);
end;

local function mainJob()
    local job = nil;
    pcall(function() job = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
    return job;
end

-- The buff list only for a PLD: it is a 32-entry copy and a fresh table per
-- read, and no other job's gauge reads it.
local NO_BUFFS = {};
gauge._player = function()
    local out = nil;
    pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer();
        local job = p:GetMainJob();
        local buffs = NO_BUFFS;
        if job == wire.JOB_PLD then
            buffs = {};
            for _, id in pairs(p:GetBuffs() or {}) do
                if type(id) == 'number' and id > 0 and id < 1024 then buffs[id] = true; end
            end
        end
        out = { job = job, level = p:GetMainJobLevel(), buffs = buffs };
    end);
    return out;
end;

-- ---------------------------------------------------------------------------
-- Settings: <char>\dlac\pldgauge.lua -- shown, locked, scale, position.
-- ---------------------------------------------------------------------------
local cfg = { shown = true, locked = false, scale = 1.0, x = nil, y = nil };
local cfgPath, cfgLoaded, movedAt = nil, false, nil;

local function settingsPath()
    local ok, sf = pcall(require, 'dlac\\lib\\statefile');
    local dir = ok and type(sf) == 'table' and sf.charDir() or nil;
    return dir and (dir .. 'pldgauge.lua') or nil;
end

local function loadSettings()
    if cfgLoaded then return; end
    local path = settingsPath();
    if path == nil then return; end   -- before login: try again next frame
    cfgPath, cfgLoaded = path, true;
    local chunk = loadfile(path);
    if chunk == nil then return; end
    local ok, t = pcall(chunk);
    if not ok or type(t) ~= 'table' then return; end
    if type(t.shown) == 'boolean' then cfg.shown = t.shown; end
    if type(t.locked) == 'boolean' then cfg.locked = t.locked; end
    if type(t.scale) == 'number' then cfg.scale = math.max(0.6, math.min(3, t.scale)); end
    if type(t.x) == 'number' and type(t.y) == 'number' then cfg.x, cfg.y = t.x, t.y; end
end

local function saveSettings()
    if cfgPath == nil then return; end
    local f = io.open(cfgPath, 'w');
    if f == nil then return; end
    f:write(string.format('return { shown = %s, locked = %s, scale = %.2f, x = %s, y = %s };\n',
        tostring(cfg.shown), tostring(cfg.locked), cfg.scale,
        cfg.x and tostring(math.floor(cfg.x)) or 'nil', cfg.y and tostring(math.floor(cfg.y)) or 'nil'));
    f:close();
end

gauge._shown = function() return cfg.shown; end;

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

-- Text size in the game font; the binding answers numbers or a vector.
local function measure(text)
    local w, h = #tostring(text) * 7, 14;
    pcall(function()
        local a, b = imgui.CalcTextSize(text);
        if type(a) == 'table' then a, b = a[1] or a.x, a[2] or a.y; end
        if type(a) == 'number' and a > 0 then w = a; end
        if type(b) == 'number' and b > 0 then h = b; end
    end);
    return w, h;
end

local function flag(name) return rawget(_G, name) or 0; end

local _open = { true };
local function render()
    if imgui == nil then return; end
    loadSettings();
    local hidden = false;
    pcall(function() hidden = require('dlac\\feature\\gamehud').hidden(); end);
    if hidden then return; end
    local v = gauge.view();
    if v == nil then return; end

    local s = cfg.scale;
    local w, h = draw.size(s);
    if cfg.x ~= nil then
        imgui.SetNextWindowPos({ cfg.x, cfg.y }, flag('ImGuiCond_Once'));
    else
        imgui.SetNextWindowPos({ 420, 520 }, flag('ImGuiCond_FirstUseEver'));
    end
    local fl = flag('ImGuiWindowFlags_NoTitleBar') + flag('ImGuiWindowFlags_NoResize')
        + flag('ImGuiWindowFlags_NoScrollbar') + flag('ImGuiWindowFlags_NoScrollWithMouse')
        + flag('ImGuiWindowFlags_AlwaysAutoResize') + flag('ImGuiWindowFlags_NoFocusOnAppearing')
        + flag('ImGuiWindowFlags_NoNav') + flag('ImGuiWindowFlags_NoBackground')
        + flag('ImGuiWindowFlags_NoSavedSettings');
    if cfg.locked then fl = fl + flag('ImGuiWindowFlags_NoMove'); end
    _open[1] = true;
    local pushed = pcall(imgui.PushStyleVar, flag('ImGuiStyleVar_WindowPadding'), { 0, 0 });
    if imgui.Begin('##dlac_pldgauge', _open, fl) then
        local x, y = imgui.GetCursorScreenPos();
        if type(x) == 'table' then y = x[2] or x.y; x = x[1] or x.x; end
        imgui.Dummy({ w, h });
        local hovered = imgui.IsItemHovered();
        local ok, err = pcall(function()
            draw.panel(imgui.GetWindowDrawList(), imgui.GetColorU32, x, y, s, v, measure);
        end);
        if not ok then pcall(imgui.TextColored, { 1, 0.4, 0.4, 1 }, esc('gauge: ' .. tostring(err))); end
        if hovered then pcall(imgui.SetTooltip, esc(draw.tooltip(v))); end
        -- Remember where it was dragged; save once the drag settles.
        local px, py = imgui.GetWindowPos();
        if type(px) == 'table' then py = px[2] or px.y; px = px[1] or px.x; end
        if type(px) == 'number' and type(py) == 'number' then
            px, py = math.floor(px), math.floor(py);
            if cfg.x ~= px or cfg.y ~= py then
                cfg.x, cfg.y = px, py;
                movedAt = os.clock() + 1;
            end
        end
    end
    imgui.End();
    if pushed then pcall(imgui.PopStyleVar); end
    if movedAt ~= nil and os.clock() >= movedAt then movedAt = nil; saveSettings(); end
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------
local function say(msg)
    local ok, cf = pcall(require, 'dlac\\chatfmt');
    if ok and type(cf) == 'table' and type(cf.info) == 'function' then pcall(cf.info, msg); return; end
    print('[dlac] ' .. msg);
end

local stanceName = { [0] = 'none', [1] = 'Divine Guard', [2] = 'Divine Fury' };

local function command(args)
    local word, rest = args:match('^%s*(%S*)%s*(.-)%s*$');
    word = string.lower(word or '');
    loadSettings();
    if word == '' or word == 'show' or word == 'hide' or word == 'toggle' then
        if word == 'show' then cfg.shown = true; elseif word == 'hide' then cfg.shown = false;
        else cfg.shown = not cfg.shown; end
        saveSettings();
        say(cfg.shown and 'PLD gauge: shown while a stance is up.' or 'PLD gauge: hidden.');
    elseif word == 'lock' or word == 'unlock' then
        cfg.locked = word == 'lock';
        saveSettings();
        say(cfg.locked and 'PLD gauge: locked in place.' or 'PLD gauge: drag it to move it.');
    elseif word == 'scale' then
        local n = tonumber(rest);
        if n == nil then say(string.format('PLD gauge scale: %.2f', cfg.scale)); return; end
        cfg.scale = math.max(0.6, math.min(3, n));
        saveSettings();
        say(string.format('PLD gauge scale: %.2f', cfg.scale));
    elseif word == 'demo' then
        if gauge.demoOn() then
            gauge.setDemo(nil);
            say('PLD gauge demo off.');
        else
            gauge.setDemo(demo.make(gauge._clock));
            say('PLD gauge demo: Divine Guard, then Divine Fury, on a 40 second loop. /dl gauge demo stops it.');
        end
    elseif word == 'status' then
        local d = gauge.debugState();
        local st = d.state;
        say(string.format('PLD gauge: channel %s%s; %s', tostring(d.sub or 'idle'),
            d.dormant and ' (server has no gauge)' or '',
            st and string.format('stance %s, points %d, charge %d/%d, Palisade %d/%d, rev %d',
                stanceName[st.stance] or '?', st.points, st.charge, st.threshold, st.palisade, st.palisadeMax, st.rev)
            or 'no state yet'));
    else
        say('PLD gauge: /dl gauge [show|hide|lock|unlock|scale N|demo|status]');
    end
end

-- Does this module answer `/dl gauge` for a player whose main job is `job`?
-- Only a main Paladin's; whmgauge answers everyone else.
local function ownsCommand(job) return job == wire.JOB_PLD; end

pcall(function()
    require('dlac\\gear\\serverpack').provide('pldGauge', gauge);
end);

if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    pcall(function()
        ashita.events.register('command', 'dlac_axi_pldgauge_cmd', function(e)
            local raw = tostring(e.command or '');
            local args = raw:match('^/[dD][lL]%s+[gG][aA][uU][gG][eE](.*)$')
                or raw:match('^/[dD][lL][aA][cC]%s+[gG][aA][uU][gG][eE](.*)$');
            if args == nil then return; end
            if args ~= '' and not args:match('^%s') then return; end   -- /dl gauges...: not ours
            if not ownsCommand(mainJob()) then return; end            -- the White Mage gauge's
            e.blocked = true;
            command(args);
        end);
    end);

    pcall(function()
        ashita.events.register('packet_in', 'dlac_axi_pldgauge', function(e)
            if e.id == 0x00A then pcall(gauge.zoneIn); return; end
            if e.id == 0x00B then pcall(gauge.zoneOut); return; end
            if e.id ~= wire.PKT then return; end
            local data = e.data_modified or e.data;
            if type(data) ~= 'string' or #data < 8 then return; end
            if not wire.ours(data:byte(5)) then return; end
            -- Blocked first, malformed frames included.
            e.blocked = true;
            pcall(function() gauge.onFrame(wire.incoming(data)); end);
        end);
    end);

    pcall(function()
        ashita.events.register('d3d_present', 'dlac_axi_pldgauge_draw', function()
            pcall(render);
        end);
    end);

    pcall(function()
        ashita.events.register('unload', 'dlac_axi_pldgauge_unload', function()
            pcall(gauge.unload);
        end);
    end);
end

return {
    pump = function() gauge.pump(); end,
    ownsCommand = ownsCommand,
    _command = command,   -- the suite drives the commands without Ashita
    _render = render,     -- the suite drives the window through a stub imgui
};
