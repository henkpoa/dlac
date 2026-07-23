--[[
    dlac/feature/nativedata.lua -- LAC-parity gData providers for the ADDON
    state. feature/native-engine: dlac absorbing LuaAshitacast.

    Inside a LuaAshitacast profile, gData answers everything the dispatch
    engine asks about the world -- player, action, pet, environment, worn
    gear. The addon state used to carry a four-field stub (job + level and
    zero-stubs); with the native engine armed, the SAME questions need REAL
    answers in this state. This module ports LuaAshitacast data.lua's provider
    shapes -- field names, resolved strings, nil semantics -- backed by
    AshitaCore plus feature\equipengine's action/pet state.

    Scope rule: only the surface dispatch.lua actually consumes is ported
    (grep-verified 2026-07-23): GetPlayer (jobs/levels/MP/Status/IsMoving),
    GetAction (Name/Type/ActionType/Element/Skill/Id), GetActionTarget
    (.Index et al), GetPet, GetPetAction, GetEnvironment (Day/DayElement/
    Weather/WeatherElement), GetEquipment, GetAugment, GetElementalOpposition
    is dispatch-side already. Sig-scan-backed reads (vanatime, weather) come
    from LuaAshitacast state.lua's signatures, init'd lazily and cached; a
    failed scan degrades that provider to nil fields, never an error.

    Loaded by dlac.lua as the gData shim builder. Everything is call-time
    guarded; headless loads are inert.
]]--

local M = {};

local _engok, eng = pcall(require, 'dlac\\feature\\equipengine');
_engok = _engok and type(eng) == 'table';

-- ---------------------------------------------------------------------------
-- constants (LuaAshitacast constants.lua, the resolved-string tables the
-- ported providers need -- values verbatim)
-- ---------------------------------------------------------------------------

-- ResolveString parity: "indices are 1 higher than ingame due to lua indexing"
local function resolve(tbl, index)
    if type(index) ~= 'number' then return nil; end
    return tbl[index + 1];
end

M.ENTITY_STATUS = { [1]='Idle', [2]='Engaged', [3]='Dead', [4]='Dead', [5]='Zoning', [34]='Resting' };
M.SPELL_ELEMENTS = { [1]='Fire', [2]='Ice', [3]='Wind', [4]='Earth', [5]='Thunder',
                     [6]='Water', [7]='Light', [8]='Dark', [16]='Non-Elemental' };
M.SPELL_SKILLS = { [33]='Divine Magic', [34]='Healing Magic', [35]='Enhancing Magic',
                   [36]='Enfeebling Magic', [37]='Elemental Magic', [38]='Dark Magic',
                   [39]='Summoning', [40]='Ninjutsu', [41]='Singing', [44]='Blue Magic',
                   [45]='Geomancy' };
M.SPELL_TYPES = { [2]='White Magic', [3]='Black Magic', [4]='Summoning', [5]='Ninjutsu',
                  [6]='Bard Song', [7]='Blue Magic' };
M.ABILITY_TYPES = { [10]='Rune Enchantment', [102]='Ready', [173]='Blood Pact: Rage',
                    [174]='Blood Pact: Ward', [193]='Corsair Roll', [195]='Quick Draw' };
M.WEEK_DAY = { 'Firesday', 'Earthsday', 'Watersday', 'Windsday', 'Iceday',
               'Lightningday', 'Lightsday', 'Darksday' };
M.WEEK_DAY_ELEMENT = { 'Fire', 'Earth', 'Water', 'Wind', 'Ice', 'Thunder', 'Light', 'Dark' };
M.WEATHER = { [1]='Clear', [2]='Sunshine', [3]='Clouds', [4]='Fog',
              [5]='Fire', [6]='Fire x2', [7]='Water', [8]='Water x2',
              [9]='Earth', [10]='Earth x2', [11]='Wind', [12]='Wind x2',
              [13]='Ice', [14]='Ice x2', [15]='Thunder', [16]='Thunder x2',
              [17]='Light', [18]='Light x2', [19]='Dark', [20]='Dark x2' };
M.WEATHER_ELEMENT = { [1]='None', [2]='None', [3]='None', [4]='None',
                      [5]='Fire', [6]='Fire', [7]='Water', [8]='Water',
                      [9]='Earth', [10]='Earth', [11]='Wind', [12]='Wind',
                      [13]='Ice', [14]='Ice', [15]='Thunder', [16]='Thunder',
                      [17]='Light', [18]='Light', [19]='Dark', [20]='Dark' };
M.STORM_WEATHER = { [178]=4, [179]=12, [180]=10, [181]=8, [182]=14, [183]=6, [184]=16, [185]=18,
                    [589]=5, [590]=13, [591]=11, [592]=9, [593]=15, [594]=7, [595]=17, [596]=19 };
M.EQUIP_SLOT_NAMES = { 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Body', 'Hands', 'Legs',
                       'Feet', 'Neck', 'Waist', 'Ear1', 'Ear2', 'Ring1', 'Ring2', 'Back' };

-- ---------------------------------------------------------------------------
-- sig-scan-backed reads (vanatime + weather; LuaAshitacast state.lua sigs)
-- ---------------------------------------------------------------------------

local _sig = { done = false, vanatime = 0, weather = 0 };
local function ensureSigs()
    if _sig.done then return; end
    _sig.done = true;
    pcall(function()
        _sig.vanatime = ashita.memory.find('FFXiMain.dll', 0, 'B0015EC390518B4C24088D4424005068', 0, 0) or 0;
        _sig.weather  = ashita.memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0, 0) or 0;
    end);
end

-- Vana'diel timestamp { day, hour, minute } | nil on a failed scan.
function M.timestamp()
    ensureSigs();
    if _sig.vanatime == 0 then return nil; end
    local ts = nil;
    pcall(function()
        local ptr = ashita.memory.read_uint32(_sig.vanatime + 0x34);
        local raw = ashita.memory.read_uint32(ptr + 0x0C) + 92514960;
        ts = {
            day    = math.floor(raw / 3456),
            hour   = math.floor(raw / 144) % 24,
            minute = math.floor((raw % 144) / 2.4),
        };
    end);
    return ts;
end

-- Raw weather id | nil on a failed scan.
function M.rawWeather()
    ensureSigs();
    if _sig.weather == 0 then return nil; end
    local w = nil;
    pcall(function()
        local ptr = ashita.memory.read_uint32(_sig.weather + 0x02);
        w = ashita.memory.read_uint8(ptr + 0);
    end);
    return w;
end

-- ---------------------------------------------------------------------------
-- small shared reads
-- ---------------------------------------------------------------------------

local function jobAbbr(id)
    local s = nil;
    pcall(function()
        local raw = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', id);
        if type(raw) == 'string' then s = raw:gsub('%z+$', ''); end
    end);
    return s;
end

local function myIndex()
    local idx = 0;
    pcall(function() idx = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0); end);
    return idx;
end

local function entityAt(index)
    local t = nil;
    pcall(function()
        local ent = AshitaCore:GetMemoryManager():GetEntity();
        t = {
            Distance = math.sqrt(ent:GetDistance(index)),
            HPP      = ent:GetHPPercent(index),
            Id       = ent:GetServerId(index),
            Index    = index,
            Name     = ent:GetName(index),
            Status   = resolve(M.ENTITY_STATUS, ent:GetStatus(index)),
        };
    end);
    return t;
end

-- IsMoving: entity position sampled per call, "moved within the last 0.5s".
-- (LAC compares against the last outgoing chunk's 0x15 position; the entity
-- read gives the same answer without parsing packet floats.)
local _pos = { x = nil, y = nil, at = 0 };
local function isMoving()
    local moving = false;
    pcall(function()
        local ent = AshitaCore:GetMemoryManager():GetEntity();
        local idx = myIndex();
        local x, y = ent:GetLocalPositionX(idx), ent:GetLocalPositionY(idx);
        local now = os.clock();
        if _pos.x ~= nil and (x ~= _pos.x or y ~= _pos.y) then _pos.at = now; end
        _pos.x, _pos.y = x, y;
        moving = (now - _pos.at) < 0.5;
    end);
    return moving;
end

-- ---------------------------------------------------------------------------
-- the providers
-- ---------------------------------------------------------------------------

function M.GetPlayer()
    local t = { MainJob = '?', MainJobSync = 0, SubJob = nil, SubJobSync = 0,
                Status = nil, IsMoving = false };
    pcall(function()
        local mm = AshitaCore:GetMemoryManager();
        local pl, party = mm:GetPlayer(), mm:GetParty();
        local mainJob, subJob = pl:GetMainJob(), pl:GetSubJob();
        t.HP           = party:GetMemberHP(0);
        t.MaxHP        = pl:GetHPMax();
        t.HPP          = party:GetMemberHPPercent(0);
        t.MP           = party:GetMemberMP(0);
        t.MaxMP        = pl:GetMPMax();
        t.MPP          = party:GetMemberMPPercent(0);
        t.TP           = party:GetMemberTP(0);
        t.Name         = party:GetMemberName(0);
        t.MainJob      = jobAbbr(mainJob) or '?';
        t.MainJobLevel = pl:GetJobLevel(mainJob);
        t.MainJobSync  = pl:GetMainJobLevel();
        t.SubJob       = jobAbbr(subJob);
        t.SubJobLevel  = pl:GetJobLevel(subJob);
        t.SubJobSync   = pl:GetSubJobLevel();
        t.Status       = resolve(M.ENTITY_STATUS, mm:GetEntity():GetStatus(myIndex()));
        t.IsMoving     = isMoving();
    end);
    return t;
end

-- The in-flight action, LAC GetAction shape (nil when idle).
function M.GetAction()
    if not _engok then return nil; end
    local action = eng.state.action;
    if action == nil then return nil; end
    local t = { ActionType = action.Type };
    pcall(function()
        local res = action.Resource;
        if action.Type == 'Spell' and res ~= nil then
            t.CastTime = res.CastTime * 250;
            t.Element = resolve(M.SPELL_ELEMENTS, res.Element);
            t.Id = res.Index;
            t.MpCost = res.ManaCost;
            t.Name = res.Name[1];
            t.Recast = res.RecastDelay * 250;
            t.Skill = resolve(M.SPELL_SKILLS, res.Skill);
            t.Type = resolve(M.SPELL_TYPES, res.Type);
            local mm = AshitaCore:GetMemoryManager();
            t.MpAftercast = mm:GetParty():GetMemberMP(0) - t.MpCost;
            t.MppAftercast = (t.MpAftercast * 100) / mm:GetPlayer():GetMPMax();
        elseif action.Type == 'Weaponskill' and res ~= nil then
            t.Name = res.Name[1];
            t.Id = res.Id;
        elseif action.Type == 'Ability' and res ~= nil then
            t.Name = res.Name[1];
            t.Id = res.Id - 0x200;
            t.Type = M.ABILITY_TYPES[res.RecastTimerId] or 'Unknown';
        elseif action.Type == 'Ranged' then
            t.Name = 'Ranged';
            t.Id = 0;
        elseif action.Type == 'Item' and res ~= nil then
            t.CastTime = res.CastTime * 250;
            t.Id = res.Id;
            t.Name = res.Name[1];
            t.Recast = res.RecastDelay * 250;
        end
    end);
    return t;
end

function M.GetActionTarget()
    if not _engok then return nil; end
    local action = eng.state.action;
    if action == nil or action.Target == nil then return nil; end
    return entityAt(action.Target);
end

function M.GetPet()
    local pet = nil;
    pcall(function()
        local mm = AshitaCore:GetMemoryManager();
        local petIndex = mm:GetEntity():GetPetTargetIndex(myIndex());
        if petIndex == 0 or mm:GetEntity():GetHPPercent(petIndex) == 0 then return; end
        pet = entityAt(petIndex);
        pet.TP = mm:GetPlayer():GetPetTP();
    end);
    return pet;
end

function M.GetPetAction()
    if not _engok then return nil; end
    local action = eng.state.petAction;
    if action == nil then return nil; end
    if M.GetPet() == nil then return nil; end   -- LAC parity: petless = no pet action
    local t = { ActionType = action.Type };
    pcall(function()
        local res = action.Resource;
        if action.Type == 'Spell' and res ~= nil then
            t.CastTime = res.CastTime * 250;
            t.Element = resolve(M.SPELL_ELEMENTS, res.Element);
            t.Id = res.Index;
            t.MpCost = res.ManaCost;
            t.Name = res.Name[1];
            t.Recast = res.RecastDelay * 250;
            t.Skill = resolve(M.SPELL_SKILLS, res.Skill);
            t.Type = resolve(M.SPELL_TYPES, res.Type);
        elseif action.Type == 'Ability' and res ~= nil then
            t.Name = res.Name[1];
            t.Id = res.Id - 0x200;
            t.Type = M.ABILITY_TYPES[res.RecastTimerId] or 'Generic';
        elseif action.Type == 'MobSkill' then
            t.Id = action.Id;
            t.Name = action.Name;
        end
    end);
    return t;
end

function M.GetEnvironment()
    local t = {};
    pcall(function()
        local ts = M.timestamp();
        if ts ~= nil then
            t.Day        = M.WEEK_DAY[(ts.day % 8) + 1];
            t.DayElement = M.WEEK_DAY_ELEMENT[(ts.day % 8) + 1];
            t.Time       = ts.hour + (ts.minute / 100);
            t.Timestamp  = ts;
        end
        local weather = M.rawWeather();
        if weather ~= nil then
            t.RawWeather        = resolve(M.WEATHER, weather);
            t.RawWeatherElement = resolve(M.WEATHER_ELEMENT, weather);
            -- storm buffs override the zone weather (LAC parity)
            pcall(function()
                for _, buff in pairs(AshitaCore:GetMemoryManager():GetPlayer():GetBuffs()) do
                    if M.STORM_WEATHER[buff] ~= nil then weather = M.STORM_WEATHER[buff]; end
                end
            end);
            t.Weather        = resolve(M.WEATHER, weather);
            t.WeatherElement = resolve(M.WEATHER_ELEMENT, weather);
        end
        pcall(function()
            local zone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
            local nm = AshitaCore:GetResourceManager():GetString('zones.names', zone);
            if type(nm) == 'string' then t.Area = nm:gsub('%z+$', ''); end
        end);
    end);
    return t;
end

-- Worn gear by slot name, LAC GetEquipment shape (equipengine's trust-window
-- view, so a set just sent reads as worn).
function M.GetEquipment()
    local t = {};
    if not _engok then return t; end
    pcall(function()
        for i = 1, 16 do
            local item = eng.currentEquipView(i);
            if item ~= nil then
                local res = nil;
                pcall(function() res = AshitaCore:GetResourceManager():GetItemById(item.Id); end);
                t[M.EQUIP_SLOT_NAMES[i]] = {
                    Container = item.Container,
                    Item = { Id = item.Id, Index = item.Index, Count = item.Count },
                    Name = (res ~= nil) and res.Name[1] or item.Name,
                    Resource = res,
                };
            end
        end
    end);
    return t;
end

-- Augment view of an inventory item (header fields; per-stat strings come
-- from the richer augment machinery when wired). LAC parity: unaugmented
-- items answer { Type = 'Unaugmented' }.
function M.GetAugment(item)
    if not _engok or item == nil or item.Extra == nil then return { Type = 'Unaugmented' }; end
    local aug = nil;
    pcall(function() aug = eng.parseAugmentHeader(item.Extra); end);
    return aug or { Type = 'Unaugmented' };
end

-- The gData table dlac.lua installs as the addon-state shim. Compatibility
-- fields kept from the old stub: GetWeather/GetDay/GetElementalOpposition
-- (gearoptim's day/weather bonus display -- now LIVE instead of zero-stubbed).
function M.build()
    return {
        GetPlayer       = M.GetPlayer,
        GetAction       = M.GetAction,
        GetActionTarget = M.GetActionTarget,
        GetPet          = M.GetPet,
        GetPetAction    = M.GetPetAction,
        GetEnvironment  = M.GetEnvironment,
        GetEquipment    = M.GetEquipment,
        GetAugment      = M.GetAugment,
        GetWeather      = function() return M.rawWeather() or 0; end,
        GetDay          = function()
            local ts = M.timestamp();
            return (ts ~= nil) and (ts.day % 8) or 0;
        end,
        GetElementalOpposition = function() return nil; end,   -- dispatch carries the wheel itself
    };
end

return M;
