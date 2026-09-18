-- Standalone dlacprobe drop-in. Observe only the HELM partition; never inject,
-- block, or modify packets. The host supplies a line writer to start().
local M = {};
function M.describe(direction, e)
    if e.id ~= 0x1E0 then return nil; end
    local raw = e.data;
    local modified = e.data_modified;
    local data = type(modified) == 'string' and #modified >= 8 and modified or raw;
    if type(data) ~= 'string' or #data < 8 then return nil; end
    local op, seq, status, flags = data:byte(5, 8);
    if op < 0x80 or op > 0x8F then return nil; end
    local function hex(s)
        if type(s) ~= 'string' then return '<absent>'; end
        local out = {};
        for i = 1, math.min(#s, 64) do out[#out + 1] = string.format('%02X', s:byte(i)); end
        return table.concat(out, ' ');
    end
    local line = string.format('%s len=%d op=%02X seq=%d status=%d flags=%d blocked=%s bytes=%s',
        direction, #data, op, seq, status, flags, tostring(e.blocked), hex(data));
    if type(raw) == 'string' and raw ~= data then line = line .. ' original=' .. hex(raw); end
    return line;
end
function M.start(write)
    for _, direction in ipairs({ 'in', 'out' }) do
        local label = direction;
        ashita.events.register('packet_' .. label, 'dlacprobe_helm_' .. label, function(e)
            local line = M.describe(label, e);
            if line then write(line); end
        end);
    end
end
return M;
