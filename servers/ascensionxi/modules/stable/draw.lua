-- Floating Ready window. Reuses the Stable paw drawing and standard gauge commands.
local imgui = require('imgui');
local view = require('dlac\\servers\\ascensionxi\\modules\\stable\\view');
local M = {};
local cfg, path, movedAt, demoAt;
local gauge, current, isBST;
local open = { true };
local function defaults() return { shown = true, locked = false, scale = 1 }; end
cfg = defaults();
local function flag(name) return rawget(_G, name) or 0; end
M._path = function()
    local dir = require('dlac\\lib\\statefile').charDir();
    return dir and dir .. 'bstgauge.lua';
end;
M._say = function(text) require('dlac\\chatfmt').msg(text); end;

local function loadSettings()
    local nextPath = M._path();
    if not nextPath or nextPath == path then return; end
    path, cfg, movedAt, demoAt = nextPath, defaults(), nil, nil;
    local chunk = loadfile(path);
    local ok, saved = pcall(chunk or function() end);
    if not ok or type(saved) ~= 'table' then return; end
    for _, key in ipairs({ 'shown', 'locked' }) do
        if type(saved[key]) == 'boolean' then cfg[key] = saved[key]; end
    end
    if type(saved.scale) == 'number' then cfg.scale = math.max(0.6, math.min(3, saved.scale)); end
    if type(saved.x) == 'number' and type(saved.y) == 'number' then cfg.x, cfg.y = saved.x, saved.y; end
end

local function saveSettings()
    if not path then return; end
    local original;
    local f = io.open(path, 'r');
    if f then original = f:read('*a'); f:close(); end
    local text = string.format('return { shown=%s, locked=%s, scale=%.2f, x=%s, y=%s };\n',
        tostring(cfg.shown), tostring(cfg.locked), cfg.scale, tostring(cfg.x), tostring(cfg.y));
    local ok, err = require('dlac\\lib\\safewrite').replaceLua(path, text, { origText = original });
    if not ok then M._say('BST gauge settings could not be saved: ' .. tostring(err)); end
end

function M.command(args)
    loadSettings();
    local word, rest = args:match('^%s*(%S*)%s*(.-)%s*$');
    word = (word or ''):lower();
    if word == '' or word == 'toggle' then cfg.shown = not cfg.shown;
    elseif word == 'show' or word == 'hide' then cfg.shown = word == 'show';
    elseif word == 'lock' or word == 'unlock' then cfg.locked = word == 'lock';
    elseif word == 'scale' then
        local value = tonumber(rest);
        if value and value == value then cfg.scale = math.max(0.6, math.min(3, value)); end
    elseif word == 'demo' then
        if demoAt then demoAt = nil; else demoAt = gauge._clock(); end
    elseif word == 'status' then
        gauge.recastChanged(); gauge.pump();
        local status = gauge.status();
        local function seconds(value) return value and string.format('%.3fs', value) or 'unknown'; end
        M._say('BST Ready: slot 102 ' .. seconds(status.native) .. ', last F6 (elapsed) ' .. seconds(status.wire)
            .. ', period ' .. seconds(status.period) .. '. Native packets round up to whole seconds.');
        return;
    else M._say('BST gauge: /dl gauge [show|hide|lock|unlock|scale N|demo|status]'); return; end
    saveSettings();
    M._say(string.format('BST gauge: %s, %s, scale %.2f%s.', cfg.shown and 'shown' or 'hidden',
        cfg.locked and 'locked' or 'unlocked', cfg.scale, demoAt and ', demo' or ''));
end

function M.render()
    if not isBST() then return; end
    loadSettings();
    if not cfg.shown or require('dlac\\feature\\gamehud').hidden() then return; end
    local clocks = current();
    if demoAt then
        local elapsed = (gauge._clock() - demoAt) % 12;
        clocks = { charges = math.floor(elapsed / 3), nextSeconds = 3 - elapsed % 3, periodSeconds = 3, time = gauge._clock() };
    end
    if not clocks then return; end
    imgui.SetNextWindowPos({ cfg.x or 420, cfg.y or 520 }, flag('ImGuiCond_Once'));
    local flags = flag('ImGuiWindowFlags_AlwaysAutoResize') + flag('ImGuiWindowFlags_NoTitleBar')
        + flag('ImGuiWindowFlags_NoFocusOnAppearing') + flag('ImGuiWindowFlags_NoBackground')
        + flag('ImGuiWindowFlags_NoScrollbar') + flag('ImGuiWindowFlags_NoSavedSettings')
        + (cfg.locked and flag('ImGuiWindowFlags_NoMove') or 0);
    imgui.PushStyleVar(flag('ImGuiStyleVar_WindowPadding'), { 0, 0 });
    local began = false;
    local ok, err = pcall(function()
        local visible = imgui.Begin('BST Ready##charges', open, flags);
        began = true;
        if visible then
            view.charges(clocks, cfg.scale);
            local x, y = imgui.GetWindowPos();
            if type(x) == 'table' then y = x[2] or x.y; x = x[1] or x.x; end
            if type(x) == 'number' and type(y) == 'number' then
                x, y = math.floor(x), math.floor(y);
                if cfg.x ~= x or cfg.y ~= y then cfg.x, cfg.y, movedAt = x, y, gauge._clock() + 1; end
            end
        end
    end);
    if began then imgui.End(); end
    imgui.PopStyleVar();
    if not ok then error(err); end
    if movedAt and gauge._clock() >= movedAt then movedAt = nil; saveSettings(); end
end

function M.attach(core, reader, enabled)
    gauge, current, isBST = core, reader, enabled;
    pcall(function() require('dlac\\gear\\serverpack').provide('bstGauge', core); end);
    ashita.events.register('d3d_present', 'dlac_bst_ready_gauge', function()
        local ok, err = pcall(M.render);
        if not ok then
            -- Contain a broken renderer once instead of corrupting the stack every frame.
            cfg.shown = false;
            pcall(M._say, 'BST gauge hidden after a drawing error: ' .. tostring(err));
        end
    end);
    ashita.events.register('command', 'dlac_bst_gauge_command', function(e)
        if not isBST() then return; end
        local raw = tostring(e.command or ''):lower();
        local args = raw:match('^/dl%s+gauge(.*)$') or raw:match('^/dlac%s+gauge(.*)$');
        if args and args ~= '' and not args:match('^%s') then return; end
        if raw == '/dl stable status' or raw == '/dlac stable status' then args = 'status'; end
        if args == nil then return; end
        e.blocked = true;
        M.command(args);
    end);
    ashita.events.register('unload', 'dlac_bst_gauge_unload', function() if movedAt then saveSettings(); end end);
end

M._settings = function() return cfg; end;
return M;
