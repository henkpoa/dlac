-- AscensionXI DLAC Stable module for local companion playtests.
-- Manual Stable management; combat remains in native job/pet menus.
local imgui = require('imgui');
local host = require('dlac\\ui\\uihost');
local transport = require('dlac\\servers\\ascensionxi\\transport');
local M = {};
local catalog = require('dlac\\servers\\ascensionxi\\modules\\stable\\catalog');
local state, pending, habitats;
local notice = 'Open the Stable to load your companions.';
local names = {};
for id = 2, 135 do names[id] = { '' }; end
local nonce = (os.time() * 31) % 4294967295;
local attempted = false;
local clocks, clocksAt, gaugeDue, gaugeDormant = nil, 0, 0, false;
local zoning = false;
local gaugeOpen = { true };

local function isBST()
    local ok, job = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
    return ok and job == 9 and not zoning;
end

local function cooldownView()
    if not clocks or transport._clock() - clocksAt > 6 or not isBST() then return nil; end
    local left = math.max(0, clocks.readyMs / 1000 - (transport._clock() - clocksAt));
    local period = clocks.periodMs / 1000;
    local missing = math.min(3, math.ceil(left / period));
    return { charges = 3 - missing, nextSeconds = missing > 0 and left - (missing - 1) * period or 0,
        periodSeconds = period, time = transport._clock() };
end

local function u16(s, offset) return s:byte(offset + 1) + s:byte(offset + 2) * 256; end
local function u32(s, offset) return u16(s, offset) + u16(s, offset + 2) * 65536; end
local function p16(n) return string.char(n % 256, math.floor(n / 256) % 256); end
local function p32(n) return p16(n % 65536) .. p16(math.floor(n / 65536) % 65536); end
local function fixed(s, size) return s:sub(1, size - 1) .. string.rep('\0', size - math.min(#s, size - 1)); end
local function readText(s) return s:match('^([^%z]*)'); end

local function audit(event, op, seq, detail)
    if transport._audit then pcall(transport._audit, event, op, seq, detail, transport._clock()); end
end

local messages = {
    OK = 'Stable updated.', UNCHANGED = 'That slot already has this companion.',
    STALE = 'Your Stable changed. Review the refreshed roster and try again.',
    STABLE = 'Stand near a Stable Master to register or change your roster.',
    IN_ROSTER = 'That companion already occupies a roster slot.', NOT_OWNED = 'Register that companion first.',
    OWNED = 'That form is already registered.', JUG_IN_INVENTORY = 'Move the filled jug into your inventory.',
    INVALID_TOKEN = 'This capture jug is unavailable. Refresh your Stable.',
    BUSY = 'Finish your current interaction first.', NAME_LENGTH = 'Use 3-15 letters without spaces or punctuation.',
    NAME_FILTERED = 'That nickname is not allowed.', NAME_FILTER_UNAVAILABLE = 'Nickname checking is unavailable.',
    RELOAD = 'The save could not be confirmed. Refresh before trying again.',
    PRESET_EMPTY = 'Refresh to load your rosters.',
};

local function request(op, body)
    -- Player actions take priority over gauge reads. Refresh can abandon a location read.
    if pending and (pending.op == 0xF6 or pending.op == 0xF4 and op == 0xF0) and op ~= 0xF6 then
        transport.abandon(pending.op, pending.seq); pending = nil;
    end
    if pending then return false; end
    nonce = (nonce + 1) % 4294967295;
    local payload = p16(4) .. p16(0) .. p32(nonce) .. (body or '');
    local seq = (nonce % 255) + 1; -- Sequence zero belongs to unsolicited push frames.
    local packet = { 0, 0, 0, 0, op, seq, 0, 0 };
    for i = 1, #payload do packet[#packet + 1] = payload:byte(i); end
    pending = { op = op, seq = seq, nonce = nonce, packet = packet, attempts = 0, at = 0, started = transport._clock() };
    if op == 0xF4 then
        pending.habitatId = u16(body, 0);
        habitats = { id = pending.habitatId, loading = true };
    end
    if op ~= 0xF6 then notice = 'Loading...'; end
    return true;
end

local function decodeState(body)
    if #body < 78 then return nil; end
    local count, captureCount = u16(body, 74), u16(body, 76);
    if count > 134 or captureCount > 134 or #body ~= 150 + count * 32 + captureCount * 8 then return nil; end
    local decoded = { revision = u32(body, 32), active = body:byte(37), activeRoster = body:byte(38), roster = {}, owned = {}, captures = {}, discovered = {}, presets = {},
        callSeconds = u32(body, 44), readySeconds = u32(body, 48), reviveSeconds = u32(body, 52), result = readText(body:sub(1, 32)) };
    if decoded.active > 3 or decoded.activeRoster > 3 or body:byte(74) ~= 0 then return nil; end
    for slot = 1, 3 do decoded.roster[slot] = u16(body, 36 + slot * 2); end
    for id = 2, 135 do
        local index = id - 2;
        local bits = body:byte(57 + math.floor(index / 8));
        decoded.discovered[id] = math.floor(bits / 2 ^ (index % 8)) % 2 == 1;
    end
    for index = 0, count - 1 do
        local offset = 78 + index * 32;
        local id = u16(body, offset);
        if id < 2 or id > 135 or decoded.owned[id] then return nil; end
        decoded.owned[id] = { id = id, level = body:byte(offset + 3), dead = body:byte(offset + 4) ~= 0,
            hp = u32(body, offset + 4), mp = u32(body, offset + 8), tp = u16(body, offset + 12),
            name = readText(body:sub(offset + 17, offset + 32)) };
    end
    local assigned = {};
    for _, id in ipairs(decoded.roster) do
        if id ~= 0 then
            if not decoded.owned[id] or assigned[id] then return nil; end
            assigned[id] = true;
        end
    end
    local tokens = {};
    for index = 0, captureCount - 1 do
        local offset = 78 + count * 32 + index * 8;
        local token, id = u32(body, offset), u16(body, offset + 4);
        if token == 0 or tokens[token] or id < 2 or id > 135 then return nil; end
        tokens[token] = true;
        decoded.captures[#decoded.captures + 1] = { token = token, companion = id, item = u16(body, offset + 6) };
    end
    for index = 1, 3 do
        local offset = 78 + count * 32 + captureCount * 8 + (index - 1) * 24;
        local name = readText(body:sub(offset + 1, offset + 16));
        local roster, seen = {}, {};
        if u16(body, offset + 22) ~= 0 then return nil; end
        for slot = 1, 3 do
            local id = u16(body, offset + 14 + slot * 2);
            if id ~= 0 and (id < 2 or id > 135 or seen[id] or name == '') then return nil; end
            seen[id], roster[slot] = true, id;
        end
        if name ~= '' then decoded.presets[index] = { name = name, roster = roster }; end
    end
    return decoded;
end

local function assemble(payload)
    if #payload < 16 then return nil; end
    local index, count, size, total = u16(payload, 8), u16(payload, 10), u16(payload, 12), u16(payload, 14);
    if total > 16384 or total < 1 or count ~= math.ceil(total / 448) or index < 1 or index > count or
        size ~= math.min(448, total - (index - 1) * 448) or #payload < 16 + size or #payload > 19 + size then return nil; end
    if payload:sub(17 + size):find('[^%z]') then return nil; end
    if pending.total and pending.total ~= total then return nil; end
    pending.total = total;
    pending.parts = pending.parts or {};
    local part = payload:sub(17, 16 + size);
    if pending.parts[index] and pending.parts[index] ~= part then return nil; end
    pending.parts[index] = part;
    for i = 1, count do if not pending.parts[i] then return nil; end end
    return table.concat(pending.parts);
end

local function onPacket(data)
    if #data < 8 then return false; end
    local op, seq, status = data:byte(5, 7);
    if op < 0xF0 or op > 0xF6 then return false; end
    audit('bst-frame', op, seq, string.format('bytes=%d status=%d pending=%d/%d', #data, status,
        pending and pending.op or 0, pending and pending.seq or 0));
    if not pending or op ~= pending.op or seq ~= pending.seq then return true; end
    if status ~= 0 then
        transport.received(op, seq);
        local habitatId = pending.habitatId;
        pending = nil;
        if op == 0xF6 then
            clocks = nil;
            gaugeDormant = status == 1 or status == 5 or status == 6;
            gaugeDue = transport._clock() + 30;
            return true;
        end
        if op == 0xF4 and status ~= 5 and status ~= 6 then
            habitats = { id = habitatId, error = 'Locations could not be loaded.' };
            notice = '';
            return true;
        end
        if status == 5 or status == 6 then state = nil; habitats = nil; end
        notice = status == 6 and 'Reload DLAC to update your Stable.' or status == 5 and 'The Stable is available to main-job Beastmasters.' or 'The Stable could not read that request. Refresh to retry.';
        return true;
    end
    local payload = data:sub(9);
    audit('bst-receive', op, seq, string.format('bytes=%d version=%d nonce=%.0f expected=%.0f',
        #data, #payload >= 2 and u16(payload, 0) or -1, #payload >= 8 and u32(payload, 4) or -1, pending.nonce));
    if #payload < 8 or u16(payload, 0) ~= 4 or u32(payload, 4) ~= pending.nonce then return true; end
    local body = assemble(payload);
    if not body then
        audit('bst-page', op, seq, #payload >= 16 and string.format('index=%d pages=%d size=%d total=%d bytes=%d',
            u16(payload, 8), u16(payload, 10), u16(payload, 12), u16(payload, 14), #payload) or 'short header');
        return true;
    end
    if op == 0xF6 then
        if #body ~= 12 then return true; end
        local period = u32(body, 4);
        if period < 25000 or period > 30000 then return true; end
        clocks = { readyMs = u32(body, 0), periodMs = period, callMs = u32(body, 8) };
        clocksAt, gaugeDue = transport._clock(), transport._clock() + 2;
    elseif op == 0xF4 then
        if #body < 4 then return true; end
        local id, count = u16(body, 0), u16(body, 2);
        if not catalog[id] or id ~= pending.habitatId then return true; end
        local rows = {};
        for row in body:sub(5):gmatch('([^\n]+)\n') do rows[#rows + 1] = row; end
        if #rows ~= count then return true; end
        habitats = { id = id, rows = rows };
        notice = '';
    else
        local decoded = decodeState(body);
        if not decoded then audit('bst-state', op, seq, string.format('invalid body bytes=%d', #body)); return true; end
        state = decoded;
        for id = 2, 135 do names[id][1] = state.owned[id] and state.owned[id].name or ''; end
        notice = messages[state.result] or 'The Stable could not complete that request. Refresh and try again.';
    end
    transport.received(op, seq);
    pending = nil;
    return true;
end

local function label(id)
    local pet = state and state.owned[id];
    if id == 0 or not catalog[math.floor(id / 2)] then return 'Empty'; end
    return (pet and pet.name ~= '' and pet.name or catalog[math.floor(id / 2)].name) .. (id % 2 == 1 and ' (shiny)' or '');
end

local function assign(slot, id)
    request(0xF1, p32(state.revision) .. string.char(slot, 0) .. p16(id));
end

local view = require('dlac\\servers\\ascensionxi\\modules\\stable\\view');
local function render()
    if not attempted then attempted = true; request(0xF0); end
    view.render({ state = state, pending = pending and pending.op ~= 0xF6, pendingOp = pending and pending.op, notice = notice, names = names, habitats = habitats, cooldowns = cooldownView(),
        catalog = catalog, request = request, assign = assign, label = label,
        editRoster = function(index, slot, id) request(0xF1, p32(state.revision) .. string.char(slot, index) .. p16(id)); end,
        preset = function(action, index, name) request(0xF5, p32(state.revision) .. string.char(action, index) .. p16(0) .. fixed(name or '', 16)); end,
        find = function(id) request(0xF4, p16(id) .. p16(0)); end,
        rename = function(id, name) request(0xF2, p32(state.revision) .. p16(id) .. p16(0) .. fixed(name, 16)); end,
        register = function(token) request(0xF3, p32(token)); end });
end

host.register({ name = 'bststable', tabs = { { label = 'Stable', render = render } } });
ashita.events.register('packet_in', 'dlac_bst_stable', function(e)
    if e.id == 0x00A or e.id == 0x00B then
        if pending then transport.abandon(pending.op, pending.seq); end
        state, pending, habitats, attempted = nil, nil, nil, false;
        view.reset();
        clocks, gaugeDue, gaugeDormant, zoning = nil, transport._clock() + 3, false, e.id == 0x00B;
        notice = 'Open the Stable to load your companions.';
    elseif e.id == 0x119 then
        gaugeDue = math.min(gaugeDue, transport._clock() + 0.1);
    elseif e.id == 0x1E0 then
        -- Ashita's strings can hold the whole 512-byte backing buffer.
        -- Only e.size bytes belong to this packet, including native padding.
        local data = e.data_modified or e.data or '';
        local size = e.size or #data;
        if type(size) == 'number' and size >= 8 and size <= #data and size % 4 == 0 and
            onPacket(data:sub(1, size)) then
            e.blocked = true;
        end
    end
end);

function M.pump()
    local now = transport._clock();
    if not pending and now >= gaugeDue then
        if isBST() then
            if not gaugeDormant then request(0xF6); end
        else
            clocks, gaugeDormant = nil, false;
        end
        gaugeDue = now + 2;
    end
    if not pending then return; end
    if now - pending.started >= 9 then
        local gauge = pending.op == 0xF6;
        local habitatId, op = pending.habitatId, pending.op;
        transport.abandon(pending.op, pending.seq);
        pending = nil;
        if gauge then clocks, gaugeDue = nil, now + 30; return; end
        if habitatId then
            habitats = { id = habitatId, error = 'Locations did not answer. Try again.' };
            notice = '';
        else
            notice = op == 0xF0 and 'The Stable did not answer. Refresh to retry.' or
                'The Stable did not answer. Refresh to check whether your change completed.';
        end
        return;
    end
    if pending.at ~= 0 and now - pending.at < 3 or pending.attempts >= 3 then return; end
    if transport.send(pending.packet, 'BST Stable') then
        pending.at, pending.attempts = now, pending.attempts + 1;
    end
end

ashita.events.register('d3d_present', 'dlac_bst_ready_gauge', function()
    local current = cooldownView();
    if not current then return; end
    imgui.SetNextWindowPos({ 420, 520 }, ImGuiCond_FirstUseEver);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    local flags = (ImGuiWindowFlags_AlwaysAutoResize or 0) + (ImGuiWindowFlags_NoTitleBar or 0) + (ImGuiWindowFlags_NoFocusOnAppearing or 0) + (ImGuiWindowFlags_NoBackground or 0) + (ImGuiWindowFlags_NoScrollbar or 0);
    if imgui.Begin('BST Ready##charges', gaugeOpen, flags) then
        view.charges(current);
    end
    imgui.End();
    imgui.PopStyleVar();
end);

-- Headless protocol checks use these same production decoders.
M._decodeState, M._onPacket = decodeState, onPacket;
M._cooldownView = cooldownView;
return M;
