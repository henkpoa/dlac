table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local handlers, hidden, enabled = {}, false, true;
local begins, ends, style, clips, wraps, tooltips, colors = 0, 0, 0, 0, 0, 0, 0;
local throwClip, throwText, hovering = false, false, false;
local dl = setmetatable({
    PushClipRect = function() clips = clips + 1; end,
    PopClipRect = function() clips = clips - 1; end,
    AddRectFilled = function() if throwClip and clips > 0 then error('injected draw failure'); end end,
}, { __index = function() return function() end; end });
local flags, size;
package.loaded.imgui = {
    SetNextWindowPos = function() end,
    PushStyleVar = function() style = style + 1; end, PopStyleVar = function() style = style - 1; end,
    Begin = function(_, _, value) begins = begins + 1; flags = value; return true; end,
    End = function() ends = ends + 1; end,
    GetWindowPos = function() return 100, 200; end,
    GetWindowDrawList = function() return dl; end,
    GetCursorScreenPos = function() return 0, 0; end,
    CalcTextSize = function(text) return #text * 8, 16; end,
    GetColorU32 = function() return 1; end,
    IsItemHovered = function() return hovering; end,
    Dummy = function(value) size = value; end,
    BeginTooltip = function() tooltips = tooltips + 1; end, EndTooltip = function() tooltips = tooltips - 1; end,
    PushTextWrapPos = function() wraps = wraps + 1; end, PopTextWrapPos = function() wraps = wraps - 1; end,
    PushStyleColor = function() colors = colors + 1; end, PopStyleColor = function() colors = colors - 1; end,
    TextUnformatted = function() if throwText then error('injected tooltip failure'); end end,
};
ImGuiWindowFlags_NoMove = 4;
package.loaded['dlac\\ui\\filetex'] = {};
package.loaded['dlac\\feature\\gamehud'] = { hidden = function() return hidden; end };
local saved, messages = {}, {};
-- Capture the final output, keeping the production chatfmt helper in the path.
-- Replacing draw._say hid a missing chatfmt API in the original command tests.
local originalPrint = print;
print = function(msg) messages[#messages + 1] = msg; end;
package.loaded['dlac\\lib\\safewrite'] = { replaceLua = function(path, data)
    assert((loadstring or load)(data)); saved[path] = data; return true;
end };
local originalLoadfile = loadfile;
local currentPath = 'fixture-character-a.lua';
loadfile = function(path) if saved[path] then return (loadstring or load)(saved[path]); end return originalLoadfile(path); end;
ashita = { events = { register = function(_, name, fn) handlers[name] = fn; end } };
local draw = require('dlac\\servers\\ascensionxi\\modules\\stable\\draw');
local now = 100;
draw._path = function() return currentPath; end;
local g = { _clock = function() return now; end, recastChanged = function() end, pump = function() end,
    status = function() return { native = 29.5, wire = 30, period = 30 }; end };
draw.attach(g, function() return { charges = 1, nextSeconds = 15, periodSeconds = 30, time = now }; end,
    function() return enabled; end);
local function cmd(text)
    local e = { command = text }; handlers.dlac_bst_gauge_command(e); return e.blocked;
end
assert(not cmd('/dl gaugefoo') and not cmd('/dl gaugefix show'));
assert(cmd('/dl gauge lock')); draw.render(); assert(flags == 4 and begins == ends and style == 0);
local normalWidth = size[1]; assert(cmd('/dlac gauge scale 2')); draw.render(); assert(size[1] > normalWidth * 1.9);
assert(cmd('/dl gauge hide')); local before = begins; draw.render(); assert(begins == before);
currentPath = 'fixture-character-b.lua'; draw.render(); assert(draw._settings().shown and draw._settings().scale == 1);
currentPath = 'fixture-character-a.lua'; draw.render(); assert(not draw._settings().shown and draw._settings().scale == 2 and draw._settings().locked);
cmd('/dl gauge show'); hidden = true; before = begins; draw.render(); assert(begins == before, 'Scroll Lock suppresses drawing');
hidden = false; enabled = false; assert(not cmd('/dl gauge hide')); draw.render(); assert(begins == before);
enabled = true;
for _, command in ipairs({'/dl stable status', '/dlac stable status', '/dl gauge status', '/dlac gauge status'}) do
    local count = #messages;
    assert(cmd(command));
    assert(#messages == count + 1 and messages[#messages]:find('BST Ready: slot 102 29.500s', 1, true),
        'status must reach the actual chat formatter exactly once');
end
cmd('/dl gauge demo'); draw.render(); cmd('/dl gauge demo');
throwClip = true; handlers.dlac_bst_ready_gauge();
assert(begins == ends and style == 0 and clips == 0 and not draw._settings().shown, 'drawing errors must unwind the real paw renderer and window');
assert(messages[#messages]:find('BST gauge hidden after a drawing error:', 1, true), 'draw failures must report through the actual chat helper');
throwClip = false; cmd('/dl gauge show'); hovering, throwText = true, true; handlers.dlac_bst_ready_gauge();
assert(begins == ends and style == 0 and clips == 0 and wraps == 0 and colors == 0 and tooltips == 0,
    'tooltip errors must unwind nested stacks too');
loadfile = originalLoadfile;
print = originalPrint;
print('Stable gauge drawing: shared commands, character settings, scaling, Scroll Lock and balanced stacks under injected failures passed.');
