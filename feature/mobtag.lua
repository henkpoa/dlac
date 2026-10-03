-- Personal hostile-action history for the current zone. This is an observed tag, not a
-- server Treasure Hunter level or an enmity/claim test. All server packs share it.
-- Network handlers only queue bytes; decoding and memory reads run in pump().
local M = {};
local tags, queue = {}, {};
local owner, zone = nil, nil;
M.QUEUE_MAX = 256;

-- Positive result messages, including landed zero-damage hits, debuffs, drains,
-- dispels and targeted abilities such as Provoke. Unknown messages, misses,
-- shadows, parries, resists, no-effect results, heals and starts never tag.
-- Packet layout: Windower/Lua addons/libs/packets/fields.lua (incoming 0x028).
-- Messages: LandSandBoat/server scripts/enum/msg.lua.
local SUCCESS_MESSAGES = {
    [1]=true, [2]=true, [67]=true, [110]=true, [185]=true, [187]=true,
    [227]=true, [252]=true, [264]=true, [317]=true, [352]=true,
    [353]=true, [522]=true, [576]=true, [577]=true,
    -- Hostile effects (primary and AoE secondary result messages).
    [127]=true, [142]=true, [144]=true, [203]=true, [225]=true, [226]=true,
    [228]=true, [236]=true, [237]=true, [242]=true, [243]=true,
    [267]=true, [268]=true, [271]=true, [277]=true, [320]=true,
    [329]=true, [330]=true, [331]=true, [332]=true, [333]=true, [334]=true,
    [335]=true, [341]=true, [362]=true, [369]=true, [370]=true,
    [379]=true, [430]=true, [431]=true, [453]=true, [454]=true, [533]=true,
    [593]=true, [594]=true, [595]=true, [596]=true, [597]=true, [598]=true,
    [599]=true, [608]=true, [672]=true,
    -- Completed targeted JAs, successful steal/mug/charm and dispels.
    [100]=true, [101]=true, [119]=true, [123]=true, [125]=true, [129]=true,
    [136]=true, [321]=true, [418]=true,
};
local COMPLETE = { [1]=true, [2]=true, [3]=true, [4]=true, [6]=true, [14]=true, [15]=true };

local function bits(data, pos, size)
    if pos + size > #data * 8 then return nil; end
    local value = 0;
    for i = 0, size - 1 do
        local p = pos + i;
        value = value + (math.floor(data:byte(math.floor(p / 8) + 1) / 2 ^ (p % 8)) % 2) * 2 ^ i;
    end
    return value;
end

-- Pure, bounds-checked decoder. Reject the whole packet if ANY target is torn;
-- otherwise later targets in an AoE could be silently skipped or misidentified.
function M.decodeAction(data)
    if type(data) ~= 'string' or #data < 19 then return nil; end
    local actor, count, category = bits(data, 40, 32), bits(data, 72, 10), bits(data, 82, 4);
    if actor == 0 or not COMPLETE[category] or count == 0 then return nil; end
    local pos, hits = 150, {};
    local function read(n)
        local v = bits(data, pos, n);
        pos = pos + n;
        return v;
    end
    for _ = 1, count do
        local id, actions = read(32), read(4);
        if actions == nil or actions == 0 then return nil; end
        local hit = false;
        for _ = 1, actions do
            -- reaction(5), animation(12), effect(4), stagger(3), knockback(3), param(17)
            read(27); read(17);
            local message = read(10);
            read(31); -- message modifier / flags
            local added = read(1);
            if added == nil then return nil; end
            if added == 1 then read(37); end
            local spikes = read(1);
            if spikes == nil then return nil; end
            if spikes == 1 and read(34) == nil then return nil; end
            if SUCCESS_MESSAGES[message] then hit = true; end
        end
        if id > 0 and hit then hits[#hits + 1] = id; end
    end
    return { actor = actor, targets = hits };
end

-- Only the HP/status mask authorizes reading those bytes. Position-only
-- updates contain zeroes there and must never look like deaths.
function M.decodeRemoval(data)
    if type(data) ~= 'string' or #data < 11 then return nil; end
    local id, mask = bits(data, 32, 32), data:byte(11);
    if id == 0 then return nil; end
    if math.floor(mask / 32) % 2 == 1 then return id; end
    if math.floor(mask / 4) % 2 == 1 and #data >= 32 then
        local hp, status = data:byte(31), data:byte(32);
        if hp == 0 or status == 2 or status == 3 then return id; end
    end
    return nil;
end

function M.reset()
    tags, queue, owner, zone = {}, {}, nil, nil;
end

function M.onPacket(id, data)
    if id ~= 0x028 and id ~= 0x00E and id ~= 0x00A and id ~= 0x00B then return; end
    -- Lost history must fail toward re-tagging, never toward stale TH removal.
    if #queue >= M.QUEUE_MAX then queue = { { id = 0x00B } }; end
    queue[#queue + 1] = { id = id, data = data };
end

M.readIdentity = function()
    local party = AshitaCore:GetMemoryManager():GetParty();
    return party:GetMemberServerId(0), party:GetMemberZone(0);
end;

function M.pump()
    local ok, me, z = pcall(M.readIdentity);
    if not ok or type(me) ~= 'number' or me <= 0 or type(z) ~= 'number' or z <= 0 then
        M.reset(); return;
    end
    if me ~= owner or z ~= zone then tags = {}; end
    owner, zone = me, z;
    local pending = queue;
    queue = {};
    for _, e in ipairs(pending) do
        if e.id == 0x00A or e.id == 0x00B then
            tags = {};
        elseif e.id == 0x00E then
            local id = M.decodeRemoval(e.data);
            if id ~= nil then tags[id] = nil; end
        elseif e.id == 0x028 then
            local action = M.decodeAction(e.data);
            if action ~= nil and action.actor == me then
                for _, id in ipairs(action.targets) do
                    if id ~= me then tags[id] = true; end
                end
            end
        end
    end
end

-- nil means no readable living monster target. It matches neither polarity.
-- Target identity comes from the current entity, never its display name/index
-- alone: identical names and reused target slots must not share a tag.
M.readTarget = function()
    local mm = AshitaCore:GetMemoryManager();
    local index = mm:GetTarget():GetTargetIndex(0);
    if type(index) ~= 'number' or index <= 0 then return nil; end
    local ent = mm:GetEntity();
    local flags = ent:GetSpawnFlags(index);
    if type(flags) ~= 'number' or math.floor(flags / 16) % 2 ~= 1 then return nil; end
    local hp, status = ent:GetHPPercent(index), ent:GetStatus(index);
    if type(hp) ~= 'number' or hp <= 0 or status == nil or status == 2 or status == 3 then return nil; end
    return ent:GetServerId(index);
end;

function M.current()
    M.pump(); -- also current when dispatch runs before the frame pump
    if owner == nil then return nil; end
    local ok, id = pcall(M.readTarget);
    if not ok or type(id) ~= 'number' or id <= 0 then return nil; end
    return tags[id] == true;
end

pcall(function()
    ashita.events.register('packet_in', 'dlac-mobtag-in', function(e)
        if e.injected == true or e.blocked == true then return; end
        M.onPacket(e.id, e.data);
    end);
end);

return M;
