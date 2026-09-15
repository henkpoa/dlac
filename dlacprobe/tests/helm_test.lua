local probe = assert(loadfile('dlacprobe/helm.lua'))();
local function frame(op, status)
    return string.rep('\0', 4) .. string.char(op, 42, status, 0) .. string.rep('\0', 20);
end
assert(probe.describe('in', { id = 0x062, data = frame(0x80, 0) }) == nil);
assert(probe.describe('in', { id = 0x1E0, data = frame(0x40, 0) }) == nil);
assert(probe.describe('in', { id = 0x1E0, data = '' }) == nil);
local event = { id = 0x1E0, data = frame(0x80, 0), blocked = false };
assert(probe.describe('in', event):find('len=28 op=80 seq=42 status=0', 1, true));
event.data_modified = frame(0x80, 2);
assert(probe.describe('in', event):find('status=2', 1, true));
assert(probe.describe('in', event):find('original=', 1, true));
local handlers, lines = {}, {};
ashita = { events = { register = function(kind, _, callback) handlers[kind] = callback; end } };
probe.start(function(line) lines[#lines + 1] = line; end);
handlers.packet_in(event); handlers.packet_out(event);
assert(lines[1]:sub(1, 2) == 'in' and lines[2]:sub(1, 3) == 'out');
assert(event.blocked == false and event.data == frame(0x80, 0));
print('OK -- HELM probe filters, records both directions and leaves packets unchanged');
