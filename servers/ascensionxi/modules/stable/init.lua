-- AscensionXI Stable. Gauge budget: one F6 per zone/job/level/merit change,
-- with bounded retries. Native 0x119 changes drive local recast reads.
-- Manual Stable management; combat remains in native job/pet menus.
local imgui = require('imgui');
local host = require('dlac\\ui\\uihost');
local transport = require('dlac\\servers\\ascensionxi\\transport');
local M = {};
local gauge = require('dlac\\servers\\ascensionxi\\modules\\stable\\gauge');
local wire = require('dlac\\servers\\ascensionxi\\modules\\stable\\wire');
local recast = require('dlac\\feature\\recast');
gauge._clock = function() return transport._clock(); end;
gauge._read = function() return recast.liveRemainingSeconds({ timerId = 102 }); end;
local catalog = require('dlac\\servers\\ascensionxi\\modules\\stable\\catalog');
local state, pending, habitats;
local notice = 'Open the Stable to load your companions.';
local names = {};
for id = 2, 135 do names[id] = { '' }; end
local nonce = (os.time() * 31) % 4294967295;
local attempted = false;
local gaugeDormant = false;
local zoning = false;
local frame, renderedFrame, refreshOnOpen = 0, nil, false;

local function isBST()
    local ok, job = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
    return ok and job == 9 and not zoning;
end

local function cooldownView()
    if not isBST() then return nil; end
    return gauge.view();
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
    BUSY = 'Finish your current interaction first.', NAME_LENGTH = 'Companions: 3-23 letters and spaces, with single spaces between words. Saved rosters: 3-15 letters.',
    NAME_FILTERED = 'That nickname is not allowed.', NAME_FILTER_UNAVAILABLE = 'Nickname checking is unavailable.',
    RELOAD = 'The save could not be confirmed. Refresh before trying again.',
    PRESET_EMPTY = 'Refresh to load your rosters.',
};

local function request(op, body)
    if op ~= 0xF0 and op ~= 0xF4 and not isBST() then return false; end
    -- Player actions take priority over gauge reads. Refresh can abandon a location read.
    if pending and (pending.op == 0xF6 or pending.op == 0xF4 and op == 0xF0) and op ~= 0xF6 then
        if pending.op == 0xF6 then gauge.periodChanged(); end
        transport.abandon(pending.op, pending.seq); pending = nil;
    end
    if pending then return false; end
    nonce = (nonce + 1) % 4294967295;
    local payload = p16(5) .. p16(0) .. p32(nonce) .. (body or '');
    local seq = (nonce % 255) + 1; -- Sequence zero belongs to unsolicited push frames.
    local packet = { 0, 0, 0, 0, op, seq, 0, 0 };
    for i = 1, #payload do packet[#packet + 1] = payload:byte(i); end
    pending = { op = op, seq = seq, nonce = nonce, packet = packet, attempts = 0 };
    if op == 0xF6 then pending.generation = gauge.requested(); end
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
    if count > 134 or captureCount > 134 or #body ~= 150 + count * 40 + captureCount * 8 then return nil; end
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
        local offset = 78 + index * 40;
        local id = u16(body, offset);
        if id < 2 or id > 135 or decoded.owned[id] then return nil; end
        decoded.owned[id] = { id = id, level = body:byte(offset + 3), dead = body:byte(offset + 4) ~= 0,
            hp = u32(body, offset + 4), mp = u32(body, offset + 8), tp = u16(body, offset + 12),
            name = readText(body:sub(offset + 17, offset + 40)) };
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
        local offset = 78 + count * 40 + index * 8;
        local token, id = u32(body, offset), u16(body, offset + 4);
        if token == 0 or tokens[token] or id < 2 or id > 135 then return nil; end
        tokens[token] = true;
        decoded.captures[#decoded.captures + 1] = { token = token, companion = id, item = u16(body, offset + 6) };
    end
    for index = 1, 3 do
        local offset = 78 + count * 40 + captureCount * 8 + (index - 1) * 24;
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
            gaugeDormant = status == wire.BAD_OP or status == wire.BAD_JOB or status == wire.BAD_VERSION;
            return true;
        end
        if op == 0xF4 and status ~= wire.BAD_JOB and status ~= wire.BAD_VERSION then
            habitats = { id = habitatId, error = 'Locations could not be loaded.' };
            notice = '';
            return true;
        end
        if status == wire.BAD_JOB or status == wire.BAD_VERSION then state = nil; habitats = nil; end
        notice = status == wire.BAD_OP and 'This server does not offer the Stable.' or
            status == wire.BAD_VERSION and 'Reload DLAC to update your Stable.' or
            status == wire.BAD_JOB and 'This Stable request is unavailable for your current job or server settings.' or
            'The Stable could not read that request. Refresh to retry.';
        return true;
    end
    local payload = data:sub(9);
    audit('bst-receive', op, seq, string.format('bytes=%d version=%d nonce=%.0f expected=%.0f',
        #data, #payload >= 2 and u16(payload, 0) or -1, #payload >= 8 and u32(payload, 4) or -1, pending.nonce));
    if #payload < 8 or u16(payload, 0) ~= 5 or u32(payload, 4) ~= pending.nonce then return true; end
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
        gauge.accept(u32(body, 0), period, pending.generation);
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
    if zoning then return; end
    if not renderedFrame or frame - renderedFrame > 1 then refreshOnOpen = true; end
    renderedFrame = frame;
    if not attempted or refreshOnOpen then
        if request(0xF0) then attempted, refreshOnOpen = true, false; end
    end
    view.render({ state = state, pending = pending and pending.op ~= 0xF6, pendingOp = pending and pending.op, notice = notice, names = names, habitats = habitats, cooldowns = cooldownView(),
        catalog = catalog, request = request, assign = assign, label = label, readOnly = not isBST(),
        editRoster = function(index, slot, id) request(0xF1, p32(state.revision) .. string.char(slot, index) .. p16(id)); end,
        preset = function(action, index, name) request(0xF5, p32(state.revision) .. string.char(action, index) .. p16(0) .. fixed(name or '', 16)); end,
        find = function(id) request(0xF4, p16(id) .. p16(0)); end,
        rename = function(id, name) request(0xF2, p32(state.revision) .. p16(id) .. p16(0) .. fixed(name, 24)); end,
        register = function(token) request(0xF3, p32(token)); end });
end

local function registerTab()
    host.register({ name = 'bststable', tabs = not zoning and { { label = 'Stable', render = render } } or {} });
end
pcall(function()
    local p = AshitaCore:GetMemoryManager():GetPlayer();
    gauge.context(p:GetMainJob(), p.GetMainJobLevel and p:GetMainJobLevel() or nil);
end);
registerTab();
ashita.events.register('packet_in', 'dlac_bst_stable', function(e)
    if e.id == 0x00A or e.id == 0x00B then
        if pending then transport.abandon(pending.op, pending.seq); end
        state, pending, habitats, attempted = nil, nil, nil, false;
        view.reset(true);
        gaugeDormant, zoning, renderedFrame = false, e.id == 0x00B, nil;
        gauge.zone(zoning);
        registerTab();
        notice = 'Open the Stable to load your companions.';
    elseif e.id == 0x119 then
        gauge.recastChanged(); -- Read memory in the next frame, after the client applies it.
    elseif e.id == 0x08C then
        gauge.periodChanged();
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
    frame = frame + 1;
    if zoning then return; end
    local job, level;
    pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer();
        job = p:GetMainJob();
        level = p.GetMainJobLevel and p:GetMainJobLevel() or nil;
    end);
    if gauge.context(job, level) then
        if pending then transport.abandon(pending.op, pending.seq); pending = nil; end
        state, habitats, attempted, renderedFrame, gaugeDormant = nil, nil, false, nil, false;
        registerTab();
    end
    gauge.pump();
    if not pending and not gaugeDormant and gauge.needsPeriod() then
        request(0xF6);
    end
    if not pending then return; end
    if pending.started and now - pending.started >= 9 then
        local timing = pending.op == 0xF6;
        local habitatId, op = pending.habitatId, pending.op;
        transport.abandon(pending.op, pending.seq);
        pending = nil;
        if timing then return; end
        if habitatId then
            habitats = { id = habitatId, error = 'Locations did not answer. Try again.' };
            notice = '';
        else
            notice = op == 0xF0 and 'The Stable did not answer. Refresh to retry.' or
                'The Stable did not answer. Refresh to check whether your change completed.';
        end
        return;
    end
    if pending.at and now - pending.at < 3 or pending.attempts >= 3 then return; end
    if transport.send(pending.packet, 'BST Stable') then
        pending.started = pending.started or now;
        pending.at, pending.attempts = now, pending.attempts + 1;
    end
end

local draw = require('dlac\\servers\\ascensionxi\\modules\\stable\\draw');
draw.attach(gauge, cooldownView, isBST);

-- Headless protocol checks use these same production decoders.
M._decodeState, M._onPacket = decodeState, onPacket;
M._cooldownView = cooldownView;
M._gauge = gauge;
M._request = request;
return M;
