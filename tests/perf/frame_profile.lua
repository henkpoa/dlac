--[[
    tests/perf/frame_profile.lua -- dlac's FRAME BUDGET, measured headless.

    Field report 2026-10-13: players see dlac stutter (TrueFPS frame graphs
    spike; unloading dlac removes it). This harness boots the WHOLE addon --
    dlac.lua, every module, the active server pack -- against a fake Ashita,
    a COPY of a real character folder and a virtual clock, then drives frames
    and packets the way the game does. Per registered handler it measures:
      * wall time (os.clock is 1 ms here; sums over many calls are unbiased),
      * Lua heap allocation (GC stopped while a handler runs),
      * file-system operations (open/loadfile/mkdir/dir listing, by path),
      * AshitaCore API calls (by method) -- each one is a real C++ crossing
        in game, nearly free here, so COUNT them.
    and per frame: the dlac total, so periodic spikes show with their period.

    Run from the dlac addon root:
        lua tests\perf\frame_profile.lua [key=value ...]
    Keys (defaults in `opt` below):
        char=<Name_Id folder under config\addons\dlac>   job=<WHM|3>
        seconds  warm (unmeasured lead-in)  fps  chunk (s between outgoing
        chunks)  inbound (pkts/s)  bags (filler gear pieces spread over the
        wardrobes)  combat=1 (engaged, melee rounds, a spell every `cast` s)
        sites=1 (who calls GetContainerItem/GetItemById/GetEquippedItem;
        allsites=1: every AshitaCore method)
        sample=1 (instruction sampling: WHERE the Lua time goes)
        alloc=1 (allocation sampling: WHERE the garbage comes from)
        scratch=<dir> (default %TEMP%\dlac-perf)
    The fake API is nearly free, so read its CALL COUNTS as the in-game cost
    and its milliseconds as Lua-side only. Windows only (robocopy, cmd).
    NOTHING here writes outside the scratch dir: the fake install root maps
    config\addons\dlac\ onto a fresh copy of the character folder, and every
    other write is sunk into the scratch dir and counted.
]]--

local REAL_CLOCK, REAL_TIME, REAL_OPEN = os.clock, os.time, io.open;
local REAL_LOADFILE, REAL_REMOVE, REAL_RENAME = loadfile, os.remove, os.rename;
local unpack = table.unpack or unpack;

-- ---------------------------------------------------------------------------
-- options
-- ---------------------------------------------------------------------------
local opt = { char = 'Mindlor_1', job = nil, seconds = 60, fps = 60, chunk = 0.25,
              inbound = 30, bags = 0, combat = 0, sample = 0, warm = 15, scratch = nil,
              top = 25, spikes = 12, cast = 4 };
for _, a in ipairs({ ... }) do
    local k, v = a:match('^([%w_]+)=(.*)$');
    if k ~= nil then opt[k] = tonumber(v) or v; end
end

local JOBS = { WAR = 1, MNK = 2, WHM = 3, BLM = 4, RDM = 5, THF = 6, PLD = 7, DRK = 8, BST = 9, BRD = 10,
               RNG = 11, SAM = 12, NIN = 13, DRG = 14, SMN = 15, BLU = 16, COR = 17, PUP = 18, DNC = 19,
               SCH = 20, GEO = 21, RUN = 22 };
local JOB_ABBR = {};
for k, v in pairs(JOBS) do JOB_ABBR[v] = k; end

-- ---------------------------------------------------------------------------
-- paths: a fake install root, mapped onto the scratch dir / the repo
-- ---------------------------------------------------------------------------
local REPO = (function()
    local p = io.popen('cd'); local d = p:read('*l'); p:close(); return d;
end)();
local INSTALL = REPO:gsub('\\addons\\dlac$', '');
local SCRATCH = opt.scratch or ((os.getenv('TEMP') or '.') .. '\\dlac-perf');
local FAKE = 'Z:\\FAKEASHITA\\';
local CHARNAME, CHARID = tostring(opt.char):match('^(.-)_(%d+)$');
assert(CHARNAME ~= nil, 'char= must be a <Name>_<Id> folder name');
CHARID = tonumber(CHARID);

local function sh(cmd) os.execute(cmd .. ' >nul 2>nul'); end
sh(string.format('rmdir /S /Q "%s"', SCRATCH));
sh(string.format('mkdir "%s\\config\\addons\\dlac"', SCRATCH));
sh(string.format('robocopy "%s\\config\\addons\\dlac\\%s" "%s\\config\\addons\\dlac\\%s" /MIR /NFL /NDL /NJH /NJS /NP',
    INSTALL, opt.char, SCRATCH, opt.char));
sh(string.format('copy /Y "%s\\config\\addons\\dlac\\server.lua" "%s\\config\\addons\\dlac\\server.lua"', INSTALL, SCRATCH));
for _, d in ipairs({ 'addon-debug', 'install', 'stray' }) do sh(string.format('mkdir "%s\\%s"', SCRATCH, d)); end
-- A field report's state on top of the copy (2026-10-13, Abraxis):
-- overlay=<dir> copies a folder of character files over it, and
-- flags=arbmon:true,gearfloat:false sets uiflags keys in it.
if opt.overlay ~= nil then
    sh(string.format('robocopy "%s" "%s\\config\\addons\\dlac\\%s" /E /NFL /NDL /NJH /NJS /NP', opt.overlay, SCRATCH, opt.char));
end
if opt.flags ~= nil then
    local p = SCRATCH .. '\\config\\addons\\dlac\\' .. opt.char .. '\\uiflags.lua';
    local f = REAL_OPEN(p, 'rb');
    local s = (f ~= nil) and f:read('*a') or '';
    if f ~= nil then f:close(); end
    for k, v in tostring(opt.flags):gmatch('([%w_]+):([^,]+)') do
        s = s:gsub('(%f[%w_]' .. k .. ' = )[^,}]+', '%1' .. v);
    end
    f = assert(REAL_OPEN(p, 'wb'));
    f:write(s);
    f:close();
end

local MAP = {
    { FAKE .. 'config\\addons\\dlac\\', SCRATCH .. '\\config\\addons\\dlac\\', true },
    { FAKE .. 'addons\\dlac\\debug\\',  SCRATCH .. '\\addon-debug\\', true },
    { FAKE .. 'addons\\dlac\\',         REPO .. '\\', false },   -- reads only
    { FAKE,                             SCRATCH .. '\\install\\', true },
};
local function remap(p, write)
    if type(p) ~= 'string' then return p; end
    local lp = p:gsub('/', '\\');
    local low = lp:lower();
    for _, m in ipairs(MAP) do
        if low:sub(1, #m[1]) == m[1]:lower() then
            if write and not m[3] then
                return SCRATCH .. '\\stray\\' .. lp:sub(#m[1] + 1):gsub('[\\:]', '_'), true;
            end
            return m[2] .. lp:sub(#m[1] + 1), false;
        end
    end
    if write then return SCRATCH .. '\\stray\\' .. lp:gsub('[\\:]', '_'), true; end
    return lp, false;
end

-- ---------------------------------------------------------------------------
-- virtual clock (os.clock / os.time / socket.gettime all ride it)
-- ---------------------------------------------------------------------------
local VT = 1000.0;
local T0 = REAL_TIME();
os.clock = function() return VT; end
os.time = function(t) if t ~= nil then return REAL_TIME(t); end return T0 + math.floor(VT - 1000); end
package.loaded['socket'] = { gettime = function() return T0 + (VT - 1000); end };

-- ---------------------------------------------------------------------------
-- attribution: whatever handler runs now gets every counter below
-- ---------------------------------------------------------------------------
local CUR = nil;        -- the running handler's record
local OVER = 0;         -- seconds the harness spent emulating (subtracted)
local IO = {};          -- kind -> count (whole run)
local IOPATH = {};      -- kind|path -> count
local API = {};         -- 'Mgr:Method' -> count (whole run)
local SITES = {};       -- sites=1: 'Mgr:Method <- caller chain' -> count
local MEASURING = false;

local function shortPath(p)
    p = tostring(p):gsub('^' .. FAKE:gsub('%p', '%%%0'), '');
    return (p:gsub('config\\addons\\dlac\\' .. opt.char:gsub('%p', '%%%0') .. '\\', '<char>\\'));
end
local function ioNote(kind, path)
    IO[kind] = (IO[kind] or 0) + 1;
    local k = kind .. '  ' .. shortPath(path);
    if MEASURING then IOPATH[k] = (IOPATH[k] or 0) + 1; end
    if CUR ~= nil then
        CUR.io = CUR.io + 1;
        CUR.ioBy[kind] = (CUR.ioBy[kind] or 0) + 1;
        if MEASURING then CUR.ioPath[k] = (CUR.ioPath[k] or 0) + 1; end
    end
end

-- file proxy: counts bytes written, forwards everything
local function wrapFile(f, path, kind)
    if f == nil then return nil; end
    local P = {};
    local mt = { __index = function(_, k)
        local v = f[k];
        if type(v) == 'function' then
            return function(self, ...)
                if k == 'write' and CUR ~= nil then
                    for _, s in ipairs({ ... }) do CUR.bytes = CUR.bytes + #tostring(s); end
                end
                return v(f, ...);
            end
        end
        return v;
    end };
    return setmetatable(P, mt);
end

io.open = function(p, mode)
    mode = mode or 'r';
    local write = mode:find('[wa+]') ~= nil;
    local rp = remap(p, write);
    ioNote(write and ('open.' .. mode:sub(1, 1)) or 'open.r', p);
    local f, err = REAL_OPEN(rp, mode);
    if f == nil then return nil, err; end
    return wrapFile(f, p, mode);
end
loadfile = function(p, ...)
    if p == nil then return nil, 'harness: loadfile(nil) refused'; end
    ioNote('loadfile', p);
    return REAL_LOADFILE((remap(p, false)), ...);
end
dofile = function(p)
    ioNote('dofile', p);
    local f = assert(REAL_LOADFILE((remap(p, false))));
    return f();
end
os.remove = function(p) ioNote('remove', p); return REAL_REMOVE((remap(p, true))); end
os.rename = function(a, b) ioNote('rename', a); return REAL_RENAME((remap(a, true)), (remap(b, true))); end
local REAL_EXECUTE, REAL_POPEN = os.execute, io.popen;
os.execute = function(cmd) ioNote('os.execute', cmd); return true, 'exit', 0; end
io.popen = function(cmd)
    ioNote('io.popen', cmd);
    return { read = function() return nil; end, lines = function() return function() return nil; end; end,
             close = function() return true; end };
end

local _madeDirs = {};
local function mkdirReal(p)
    local rp = remap(p, true);
    if _madeDirs[rp] then return true; end
    _madeDirs[rp] = true;
    local t0 = REAL_CLOCK();
    REAL_EXECUTE('mkdir "' .. rp:gsub('\\+$', '') .. '" >nul 2>nul');
    OVER = OVER + (REAL_CLOCK() - t0);
    return true;
end
local _dirCache = {};
local function listDir(p)
    local rp = remap(p, false):gsub('\\+$', '');
    local hit = _dirCache[rp];
    if hit ~= nil then return hit; end
    local t0 = REAL_CLOCK();
    local out = {};
    local h = REAL_POPEN('dir /b "' .. rp .. '" 2>nul');
    if h ~= nil then for line in h:lines() do out[#out + 1] = line; end h:close(); end
    OVER = OVER + (REAL_CLOCK() - t0);
    _dirCache[rp] = out;
    return out;
end

-- ---------------------------------------------------------------------------
-- require resolution: dlac\X -> .\X.lua (the smoke_ui pattern)
-- ---------------------------------------------------------------------------
table.insert(package.searchers, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel == nil then return nil; end
    local chunk = REAL_LOADFILE((rel:gsub('\\', '/')) .. '.lua');
    if chunk == nil then return nil; end
    return chunk;
end);
package.loaded['common'] = true;
package.loaded['bit'] = {
    band = function(a, b, ...) local r = (a & b); for _, x in ipairs({ ... }) do r = r & x; end return r; end,
    bor  = function(a, b, ...) local r = (a | (b or 0)); for _, x in ipairs({ ... }) do r = r | x; end return r; end,
    bxor = function(a, b) return a ~ b; end,
    bnot = function(a) return ~a; end,
    lshift = function(a, n) return (a << n) & 0xFFFFFFFF; end,
    rshift = function(a, n) return (a & 0xFFFFFFFF) >> n; end,
    arshift = function(a, n) return a >> n; end,
    tobit = function(a) return a; end,
};
bit = package.loaded['bit'];

-- ---------------------------------------------------------------------------
-- the fake world
-- ---------------------------------------------------------------------------
local W = {
    job = JOBS[tostring(opt.job or ''):upper()] or tonumber(opt.job) or nil,
    level = 75, sub = 4, sublevel = 37, zone = (opt.combat == 1) and 102 or 230,
    hp = 1200, hpmax = 1200, mp = 900, mpmax = 900, tp = 0,
    status = (opt.combat == 1) and 1 or 0,
    bags = {}, equipped = {}, target = 0, frame = 0,
};
for s = 0, 15 do W.equipped[s] = 0; end
-- The job: the char's modestate __job when not given.
if W.job == nil then
    local f = REAL_LOADFILE(SCRATCH .. '\\config\\addons\\dlac\\' .. opt.char .. '\\modestate.lua');
    local ok, t = pcall(f or function() return {}; end);
    W.job = (ok and type(t) == 'table' and tonumber(t.__job)) or 3;
end

-- Item resources from the active pack's catalog (what GetItemById answers).
local SLOTBITS = { Main = 1, Sub = 2, Range = 4, Ammo = 8, Head = 16, Body = 32, Hands = 64, Legs = 128,
                   Feet = 256, Neck = 512, Waist = 1024, Ear = 6144, Ear1 = 6144, Ear2 = 6144,
                   Ring = 24576, Ring1 = 24576, Ring2 = 24576, Back = 32768 };
local RES = {};
local CATALOG_IDS = {};
do
    local packFlag = REAL_LOADFILE(SCRATCH .. '\\config\\addons\\dlac\\server.lua');
    local pack = 'ascensionxi';
    if packFlag ~= nil then local ok, t = pcall(packFlag); if ok and type(t) == 'table' then pack = t.server or pack; end end
    local cat = REAL_LOADFILE('servers/' .. pack .. '/data/catalog.lua');
    cat = cat and cat() or {};
    local function jobMask(jobs)
        local m = 0;
        for _, j in ipairs(jobs or {}) do local id = JOBS[j]; if id then m = m | (1 << id); end end
        return m;
    end
    local function walk(t, slot)
        for k, v in pairs(t) do
            if type(v) == 'table' then
                if v.Id ~= nil and v.Name ~= nil then
                    local id = tonumber(v.Id);
                    if id ~= nil and RES[id] == nil then
                        RES[id] = { Id = id, name = v.Name, Level = tonumber(v.Level) or 1,
                                    Jobs = jobMask(v.Jobs), Slots = SLOTBITS[slot] or 0, Flags = 0x0800,
                                    Type = 4, StackSize = 1, ItemLevel = 0, Races = 0x1FE,
                                    Skill = 0, Damage = 0, Delay = 0 };
                        CATALOG_IDS[#CATALOG_IDS + 1] = id;
                    end
                else
                    walk(v, slot);
                end
            end
        end
    end
    for slot, t in pairs(cat) do if type(t) == 'table' then walk(t, slot); end end
    table.sort(CATALOG_IDS);
end
local RES_MT = {};
local function resProxy(id)
    local r = RES[id];
    if r == nil then return nil; end
    -- Ashita's IItem: Name/LogName* are arrays the binding builds per access.
    return setmetatable({}, { __index = function(_, k)
        if k == 'Name' or k == 'LogNameSingular' or k == 'LogNamePlural' or k == 'Description' then
            return { r.name, r.name, r.name };
        end
        return r[k];
    end });
end

-- Bags: the character's gear.lua pieces, then `bags` filler pieces.
local EXTRA0 = string.rep('\0', 28);
local function bag(c) local b = W.bags[c]; if b == nil then b = {}; W.bags[c] = b; end return b; end
local BAGS = { 8, 10, 11, 12, 13, 14, 15, 16, 0 };
local function place(id)
    if RES[id] == nil then
        RES[id] = { Id = id, name = 'Item ' .. id, Level = 1, Jobs = 0x7FFFFE, Slots = 0, Flags = 0, Type = 1,
                    StackSize = 12, ItemLevel = 0, Races = 0x1FE, Skill = 0, Damage = 0, Delay = 0 };
    end
    for _, c in ipairs(BAGS) do
        local b = bag(c);
        if #b < 80 then b[#b + 1] = { Id = id, Count = 1, Flags = 0, Price = 0, Extra = EXTRA0, Index = #b + 1 }; return true; end
    end
    return false;
end
do
    local gf = REAL_LOADFILE(SCRATCH .. '\\config\\addons\\dlac\\' .. opt.char .. '\\gear.lua');
    local env = {};
    local g = nil;
    if gf ~= nil then
        local ok, r = pcall(gf);
        g = (ok and type(r) == 'table') and r or rawget(_G, 'gear');
        _G.gear = nil;
    end
    local seen = {};
    local function walk(t)
        for _, v in pairs(t) do
            if type(v) == 'table' then
                if v.Id ~= nil and v.Name ~= nil then
                    local id = tonumber(v.Id);
                    if id ~= nil and not seen[id] then seen[id] = true; place(id); end
                else walk(v); end
            end
        end
    end
    if type(g) == 'table' then walk(g); end
    local n, i = tonumber(opt.bags) or 0, 1;
    while n > 0 and i <= #CATALOG_IDS do
        local id = CATALOG_IDS[(i * 7919) % #CATALOG_IDS + 1];
        if not seen[id] then seen[id] = true; if not place(id) then break; end n = n - 1; end
        i = i + 1;
    end
    -- inventory clutter: crystals, food, ninja tools -- non-gear stacks
    local clutter = { 4096, 4097, 4098, 4099, 4100, 4101, 4102, 4103, 4112, 4116, 4148, 4150, 5680, 4509 };
    for _, id in ipairs(clutter) do
        local b = bag(0);
        if #b < 80 then
            if RES[id] == nil then
                RES[id] = { Id = id, name = 'Clutter ' .. id, Level = 1, Jobs = 0, Slots = 0, Flags = 0, Type = 1,
                            StackSize = 12, ItemLevel = 0, Races = 0, Skill = 0, Damage = 0, Delay = 0 };
            end
            b[#b + 1] = { Id = id, Count = 12, Flags = 0, Price = 0, Extra = EXTRA0, Index = #b + 1 };
        end
    end
end
local function bagCount()
    local n = 0;
    for _, b in pairs(W.bags) do n = n + #b; end
    return n;
end

-- Entities: a populated zone (mobs/NPCs low, PCs from 0x400).
local ENT = {};
local ME = 0x400 + 3;
for i = 1, 260 do
    ENT[i] = { name = 'Mob' .. i, status = 0, sid = 0x01000000 + i, hpp = 100, x = i % 50, y = 0, z = i % 40,
               dist = 10 + (i % 40), type = 2, render = 0x200, spawn = 0x10 };
end
for i = 0x400, 0x400 + 40 do
    ENT[i] = { name = (i == ME) and CHARNAME or ('Pc' .. i), status = 0, sid = (i == ME) and CHARID or (0x2000 + i),
               hpp = 100, x = 0, y = 0, z = 0, dist = (i == ME) and 0 or 20, type = 0, render = 0x200, spawn = 0x01 };
end
if opt.combat == 1 then W.target = 17; ENT[17].status = 1; ENT[17].dist = 3; ENT[ME].status = 1; end

-- ---------------------------------------------------------------------------
-- AshitaCore: counted fake objects
-- ---------------------------------------------------------------------------
local function fakeObject(tag, methods)
    local cache = {};
    return setmetatable({}, { __index = function(_, k)
        local w = cache[k];
        if w == nil then
            local f = methods[k];
            local key = tag .. ':' .. tostring(k);
            w = function(self, ...)
                API[key] = (API[key] or 0) + 1;
                if CUR ~= nil then
                    CUR.api = CUR.api + 1;
                    CUR.apiBy[key] = (CUR.apiBy[key] or 0) + 1;
                end
                -- sites=1: WHO calls the heavy methods (a 3-deep caller chain).
                if opt.sites == 1 and MEASURING and (opt.allsites == 1 or k == 'GetContainerItem'
                        or k == 'GetItemById' or k == 'GetEquippedItem') then
                    local parts = {};
                    for lvl = 2, 4 do
                        local info = debug.getinfo(lvl, 'Sl');
                        if info == nil then break; end
                        parts[#parts + 1] = info.short_src:gsub('^.*[\\/]', '') .. ':' .. tostring(info.currentline);
                    end
                    local sk = key .. '  <-  ' .. table.concat(parts, ' < ');
                    SITES[sk] = (SITES[sk] or 0) + 1;
                end
                if f ~= nil then return f(...); end
                return 0;
            end
            cache[k] = w;
        end
        return w;
    end });
end

local OUTQ = {};           -- injected packets this frame
local SENT = {};           -- id -> count of dlac's injected packets
local QCMD = {};           -- command -> count
local deliverOut;          -- forward

local function itemAt(c, i)
    local b = W.bags[c];
    local it = b and b[i] or nil;
    return it;
end
-- What the server sends back for an equip, as its flushEquipChanges does
-- (src/map/entities/char_entity.cpp): an EQUIP_LIST (0x050) for the slot, then
-- an ITEM_LIST (0x01F) re-flagging each piece put on or taken off. Delivered
-- the next frame, like a reply.
local INQ = {};
local function reply(id, size, writes)
    local b = {};
    for i = 1, size do b[i] = 0; end
    local h = id | ((size // 4) << 9);
    b[1], b[2] = h & 0xFF, h >> 8;
    for off, v in pairs(writes) do b[off + 1] = v & 0xFF; end
    local s = {};
    for i = 1, size do s[i] = string.char(b[i]); end
    INQ[#INQ + 1] = { id = id, data = table.concat(s) };
end
local function itemListReply(c, i, flag)
    local it = itemAt(c, i);
    if it == nil then return; end
    reply(0x01F, 0x10, { [0x08] = it.Id & 0xFF, [0x09] = it.Id >> 8, [0x0A] = c, [0x0B] = i, [0x0C] = flag });
end
local function applyEquip(index, slot, container)
    if slot == nil or slot > 15 then return; end
    local old = W.equipped[slot] or 0;
    if index == 0 then
        W.equipped[slot] = 0;
        reply(0x050, 8, { [0x04] = 0, [0x05] = slot, [0x06] = 0 });
    elseif itemAt(container, index) ~= nil then
        W.equipped[slot] = container * 256 + index;
        reply(0x050, 8, { [0x04] = index, [0x05] = slot, [0x06] = container });
        itemListReply(container, index, 5);
    else
        return;
    end
    if old ~= 0 and old ~= W.equipped[slot] then itemListReply(old // 256, old % 256, 0); end
end

local buffs = {};
for i = 1, 32 do buffs[i] = -1; end
if opt.combat == 1 then buffs[1] = 251; buffs[2] = 43; end   -- Food, Refresh

local player = fakeObject('Player', {
    GetMainJob = function() return W.job; end, GetMainJobLevel = function() return W.level; end,
    GetSubJob = function() return W.sub; end, GetSubJobLevel = function() return W.sublevel; end,
    GetJobLevel = function(j) return (j == W.job) and W.level or 30; end,
    GetBuffs = function() local t = {}; for i = 1, 32 do t[i] = buffs[i]; end return t; end,
    GetStatusTimers = function() local t = {}; for i = 1, 32 do t[i] = 0; end return t; end,
    GetIsZoning = function() return 0; end, GetLoginStatus = function() return 2; end,
    GetHPMax = function() return W.hpmax; end, GetMPMax = function() return W.mpmax; end,
    GetPetTP = function() return 0; end, GetRace = function() return 1; end,
    GetCraftSkill = function(i) return fakeObject('CraftSkill', { GetSkill = function() return 0; end,
        GetRank = function() return 0; end, IsCapped = function() return false; end }); end,
    GetCombatSkill = function(i) return fakeObject('CombatSkill', { GetSkill = function() return 200; end,
        IsCapped = function() return false; end }); end,
    GetMaxSkill = function() return 200; end,
});
local inventory = fakeObject('Inventory', {
    GetContainerItem = function(c, i)
        local it = itemAt(c, i);
        if it == nil then
            if i >= 0 and i <= 80 then return { Id = 0, Count = 0, Flags = 0, Price = 0, Extra = EXTRA0, Index = i }; end
            return nil;
        end
        return setmetatable({}, { __index = it });   -- the binding wraps a pointer per call
    end,
    GetContainerCountMax = function(c) if c == 0 or c == 8 or (c >= 10 and c <= 16) or (c >= 1 and c <= 7) then return 80; end return 0; end,
    GetContainerCount = function(c) local b = W.bags[c]; return b and #b or 0; end,
    GetEquippedItem = function(s) return { Index = W.equipped[s] or 0, Slot = s }; end,
});
local party = fakeObject('Party', {
    GetMemberName = function(i) return (i == 0) and CHARNAME or ''; end,
    GetMemberServerId = function(i) return (i == 0) and CHARID or 0; end,
    GetMemberTargetIndex = function(i) return (i == 0) and ME or 0; end,
    GetMemberZone = function(i) return (i == 0) and W.zone or 0; end,
    GetMemberIsActive = function(i) return (i == 0) and 1 or 0; end,
    GetMemberHP = function(i) return (i == 0) and W.hp or 0; end,
    GetMemberMP = function(i) return (i == 0) and W.mp or 0; end,
    GetMemberTP = function(i) return (i == 0) and W.tp or 0; end,
    GetMemberHPPercent = function(i) return (i == 0) and 100 or 0; end,
    GetMemberMPPercent = function(i) return (i == 0) and 100 or 0; end,
    GetMemberMainJob = function(i) return (i == 0) and W.job or 0; end,
    GetMemberMainJobLevel = function(i) return (i == 0) and W.level or 0; end,
});
local entity = fakeObject('Entity', {
    GetName = function(i) local e = ENT[i]; return e and e.name or ''; end,
    GetStatus = function(i) local e = ENT[i]; return e and e.status or 0; end,
    GetServerId = function(i) local e = ENT[i]; return e and e.sid or 0; end,
    GetHPPercent = function(i) local e = ENT[i]; return e and e.hpp or 0; end,
    GetDistance = function(i) local e = ENT[i]; return e and (e.dist * e.dist) or 0; end,
    GetLocalPositionX = function(i) local e = ENT[i]; return e and e.x or 0; end,
    GetLocalPositionY = function(i) local e = ENT[i]; return e and e.y or 0; end,
    GetLocalPositionZ = function(i) local e = ENT[i]; return e and e.z or 0; end,
    GetLocalPositionYaw = function(i) return 0; end,
    GetRenderFlags0 = function(i) local e = ENT[i]; return e and e.render or 0; end,
    GetRenderFlags4 = function(i) return 0; end,
    GetSpawnFlags = function(i) local e = ENT[i]; return e and e.spawn or 0; end,
    GetPetTargetIndex = function(i) return 0; end,
    GetType = function(i) local e = ENT[i]; return e and e.type or 0; end,
    GetRawEntity = function(i) return ENT[i] and {} or nil; end,
    GetActorPointer = function(i) return ENT[i] and 1 or 0; end,
});
local target = fakeObject('Target', {
    GetTargetIndex = function(i) return (i == 0) and W.target or 0; end,
    GetIsSubTargetActive = function() return 0; end,
});
local recast = fakeObject('Recast', {});
local memmgr = fakeObject('MemoryManager', {
    GetPlayer = function() return player; end, GetInventory = function() return inventory; end,
    GetParty = function() return party; end, GetEntity = function() return entity; end,
    GetTarget = function() return target; end, GetRecast = function() return recast; end,
    GetCastBar = function() return fakeObject('CastBar', {}); end,
    GetAutoFollow = function() return fakeObject('AutoFollow', {}); end,
});
local resmgr = fakeObject('ResourceManager', {
    GetItemById = function(id) return resProxy(id); end,
    GetItemByName = function(name, lang) return nil; end,
    GetString = function(t, i)
        if t == 'jobs.names_abbr' then return JOB_ABBR[tonumber(i) or 0] or 'NON'; end
        if t == 'jobs.names' then return (JOB_ABBR[tonumber(i) or 0] or 'None') .. ' (job)'; end
        if t == 'zones.names' then return (tonumber(i) == 230) and "Southern San d'Oria" or ('Zone ' .. tostring(i)); end
        if t == 'buffs.names' then return 'Buff ' .. tostring(i); end
        return tostring(t) .. ' ' .. tostring(i);
    end,
    GetSpellById = function(id) return { Name = { 'Spell' .. id, 'Spell' .. id }, CastTime = 8, Element = 0, Skill = 33, Type = 1, Index = id }; end,
    GetAbilityById = function(id) return { Name = { 'Ability' .. id, 'Ability' .. id }, Element = 0, Type = 1, Id = id }; end,
    GetSpellByName = function() return nil; end, GetAbilityByName = function() return nil; end,
    GetStatusIconByIndex = function() return nil; end,
});
local chatmgr = fakeObject('ChatManager', {
    QueueCommand = function(mode, cmd)
        local k = tostring(cmd):match('^(%S+)') or '?';
        QCMD[k] = (QCMD[k] or 0) + 1;
    end,
    AddChatMessage = function() end,
});
local packetmgr = fakeObject('PacketManager', {
    AddOutgoingPacket = function(id, bytes)
        SENT[id] = (SENT[id] or 0) + 1;
        if id == 0x50 then
            applyEquip(bytes[5], bytes[6], bytes[7]);
        elseif id == 0x51 then
            local n = bytes[5] or 0;
            for k = 1, n do
                local off = 4 + k * 4 + 1;
                applyEquip(bytes[off], bytes[off + 1], bytes[off + 2]);
            end
        end
        OUTQ[#OUTQ + 1] = { id = id, bytes = bytes };
    end,
    AddIncomingPacket = function() end,
});
local pluginmgr = fakeObject('PluginManager', { IsLoaded = function() return false; end });
local pointermgr = fakeObject('PointerManager', { Get = function() return 0; end });
local configmgr = fakeObject('ConfigurationManager', {
    GetString = function() return nil; end, GetBool = function() return false; end,
});
local inputmgr = fakeObject('InputManager', { GetKeyboard = function() return fakeObject('Keyboard', {}); end });

AshitaCore = fakeObject('AshitaCore', {
    GetInstallPath = function() return FAKE; end,
    GetMemoryManager = function() return memmgr; end,
    GetResourceManager = function() return resmgr; end,
    GetChatManager = function() return chatmgr; end,
    GetPacketManager = function() return packetmgr; end,
    GetPluginManager = function() return pluginmgr; end,
    GetPointerManager = function() return pointermgr; end,
    GetConfigurationManager = function() return configmgr; end,
    GetInputManager = function() return inputmgr; end,
    GetFontManager = function() return fakeObject('FontManager', {}); end,
    GetPrimitiveManager = function() return fakeObject('PrimitiveManager', {}); end,
});

-- ---------------------------------------------------------------------------
-- ashita.* (events recorded in registration order; fs emulated + counted)
-- ---------------------------------------------------------------------------
local HANDLERS = {};      -- event -> { {name, fn, rec}, ... } in registration order
local RECS = {};          -- 'event/name' -> record
local function rec(evt, name)
    local key = evt .. '/' .. name;
    local r = RECS[key];
    if r == nil then
        r = { key = key, calls = 0, ms = 0, maxms = 0, kb = 0, maxkb = 0, io = 0, ioBy = {}, ioPath = {},
              api = 0, apiBy = {}, bytes = 0, errors = 0, lastErr = nil, hist = {}, fhist = {} };
        RECS[key] = r;
    end
    return r;
end
local TASKS = {};
ashita = {
    events = {
        register = function(evt, name, fn)
            local list = HANDLERS[evt]; if list == nil then list = {}; HANDLERS[evt] = list; end
            for i, h in ipairs(list) do if h.name == name then table.remove(list, i); break; end end
            list[#list + 1] = { name = name, fn = fn, rec = rec(evt, name) };
        end,
        unregister = function(evt, name)
            local list = HANDLERS[evt]; if list == nil then return; end
            for i, h in ipairs(list) do if h.name == name then table.remove(list, i); return; end end
        end,
    },
    fs = {
        create_directory = function(p) ioNote('fs.create_directory', p); return mkdirReal(p); end,
        get_dir = function(p, mask, rec) ioNote('fs.get_dir', p); return listDir(p); end,
        exists = function(p)
            ioNote('fs.exists', p);
            local f = REAL_OPEN((remap(p, false)), 'r');
            if f ~= nil then f:close(); return true; end
            return #listDir(p) > 0;
        end,
    },
    memory = setmetatable({ find = function() return 0; end }, { __index = function() return function() return 0; end; end }),
    tasks = { once = function(delay, fn) TASKS[#TASKS + 1] = { at = VT + (tonumber(delay) or 0), fn = fn }; end },
    bits = { unpack_be = function(data, byteOff, bitOff, len)
        local v = 0;
        for b = 0, len - 1 do
            local pos = byteOff * 8 + bitOff + b;
            local byte = (type(data) == 'string') and (data:byte(math.floor(pos / 8) + 1) or 0)
                         or (data[math.floor(pos / 8) + 1] or 0);
            local bitv = (byte >> (7 - pos % 8)) & 1;
            v = (v << 1) | bitv;
        end
        return v;
    end },
    time = { clock = function() return { ms = math.floor(VT * 1000), s = math.floor(VT) }; end },
};
addon = {};

-- ---------------------------------------------------------------------------
-- imgui: permissive. Windows open (bodies run); widgets never clicked.
-- ---------------------------------------------------------------------------
local function noop() end
local drawlist = setmetatable({}, { __index = function() return noop; end });
local STYLE = setmetatable({ ItemSpacing = { 8, 4 }, FramePadding = { 4, 3 }, WindowPadding = { 8, 8 },
    ItemInnerSpacing = { 4, 4 }, ScrollbarSize = 14, IndentSpacing = 21, Alpha = 1, WindowRounding = 0,
    FrameRounding = 0, Colors = setmetatable({}, { __index = function() return { 1, 1, 1, 1 }; end }) },
    { __index = function() return 0; end });
local IMGUI_FN = {
    Begin = function() return true; end,
    BeginChild = function() return true; end,
    BeginGroup = noop, EndGroup = noop, End = noop, EndChild = noop,
    CalcTextSize = function(s) s = tostring(s or ''); return #s * 7, 13; end,
    GetWindowPos = function() return 100, 100; end, GetWindowSize = function() return 420, 300; end,
    GetWindowWidth = function() return 420; end, GetWindowHeight = function() return 300; end,
    GetContentRegionAvail = function() return 400, 280; end, GetContentRegionMax = function() return 400, 280; end,
    GetWindowContentRegionMax = function() return 400, 280; end, GetWindowContentRegionMin = function() return 0, 0; end,
    GetCursorPos = function() return 8, 8; end, GetCursorPosX = function() return 8; end, GetCursorPosY = function() return 8; end,
    GetCursorScreenPos = function() return 108, 108; end, GetCursorStartPos = function() return 8, 8; end,
    GetItemRectMin = function() return 100, 100; end, GetItemRectMax = function() return 140, 120; end,
    GetItemRectSize = function() return 40, 20; end,
    GetWindowDrawList = function() return drawlist; end, GetForegroundDrawList = function() return drawlist; end,
    GetBackgroundDrawList = function() return drawlist; end,
    GetStyle = function() return STYLE; end,
    GetIO = function() return { DisplaySize = { 1920, 1080 }, KeyCtrl = false, KeyShift = false, KeyAlt = false,
        MousePos = { 0, 0 }, Framerate = 60, DeltaTime = 1 / 60, MouseDown = { false, false, false },
        FontGlobalScale = 1 }; end,
    GetFontSize = function() return 13; end, GetTextLineHeight = function() return 13; end,
    GetTextLineHeightWithSpacing = function() return 17; end, GetFrameHeight = function() return 19; end,
    GetFrameHeightWithSpacing = function() return 23; end,
    GetColorU32 = function() return 0xFFFFFFFF; end,
    GetTime = function() return VT; end, GetFrameCount = function() return W.frame; end,
    GetMainViewport = function() return { Pos = { 0, 0 }, Size = { 1920, 1080 }, WorkPos = { 0, 0 }, WorkSize = { 1920, 1080 } }; end,
    GetVersion = function() return '1.89.0'; end,
    GetScrollY = function() return 0; end, GetScrollMaxY = function() return 0; end,
    GetMousePos = function() return 0, 0; end,
};
imgui = setmetatable({}, { __index = function(_, k)
    local f = IMGUI_FN[k];
    if f ~= nil then return f; end
    if type(k) == 'string' and k:match('^ImGui') then return 0; end
    return function() return false; end;
end });
-- ImGui enum globals (ImGuiWindowFlags_*, ImGuiCol_*, ...) read as 0.
setmetatable(_G, { __index = function(_, k)
    if type(k) == 'string' and k:match('^ImGui') then return 0; end
    return nil;
end });

-- ---------------------------------------------------------------------------
-- running handlers, measured
-- ---------------------------------------------------------------------------
local FRAME = nil;        -- per-frame accumulator while measuring
local SAMPLE_EVERY = 1000;
-- One sample: the first frame up the stack that is dlac's (the fake API's
-- own lines are the harness, not the addon), by line AND by function.
-- sample=1 weighs each sample as 1 (instructions); alloc=1 weighs it by the
-- KB allocated since the previous sample (GC is stopped, so the delta is
-- exactly what the interval allocated).
local _lastKb = 0;
local function sampler()
    if CUR == nil then return; end
    local w = 1;
    if opt.alloc == 1 then
        local kb = collectgarbage('count');
        w = kb - _lastKb;
        _lastKb = kb;
        if w <= 0 then return; end
    end
    for lvl = 2, 12 do
        local info = debug.getinfo(lvl, 'Sln');
        if info == nil then return; end
        if not info.short_src:find('frame_profile', 1, true) and info.what ~= 'C' then
            local src = info.short_src:gsub('^.*[\\/](%w+[\\/][%w_]+%.lua)$', '%1');
            local k = src .. ':' .. tostring(info.currentline);
            CUR.hist[k] = (CUR.hist[k] or 0) + w;
            local fk = src .. ':' .. tostring(info.linedefined) .. ' ' .. tostring(info.name or '?');
            CUR.fhist[fk] = (CUR.fhist[fk] or 0) + w;
            if opt.alloc == 1 then _lastKb = collectgarbage('count'); end
            return;
        end
    end
end
local function runHandler(h, e)
    local r = h.rec;
    local prev = CUR;
    CUR = r;
    local kb0 = collectgarbage('count');
    local over0 = OVER;
    local t0 = REAL_CLOCK();
    local sampling = (opt.sample == 1 or opt.alloc == 1) and MEASURING;
    if sampling then _lastKb = collectgarbage('count'); debug.sethook(sampler, '', (opt.alloc == 1) and 100 or SAMPLE_EVERY); end
    local ok, err = pcall(h.fn, e);
    if sampling then sampler(); debug.sethook(); end
    local ms = ((REAL_CLOCK() - t0) - (OVER - over0)) * 1000;
    local kb = collectgarbage('count') - kb0;
    CUR = prev;
    if ms < 0 then ms = 0; end
    if MEASURING then
        r.calls = r.calls + 1;
        r.ms = r.ms + ms;
        if ms > r.maxms then r.maxms = ms; end
        r.kb = r.kb + kb;
        if kb > r.maxkb then r.maxkb = kb; end
        if FRAME ~= nil then
            FRAME.ms = FRAME.ms + ms;
            FRAME.kb = FRAME.kb + kb;
            if ms >= 0.999 then FRAME.who[#FRAME.who + 1] = string.format('%s %.0fms', r.key, ms); end
        end
    end
    if not ok then
        r.errors = r.errors + 1;
        if r.lastErr == nil then r.lastErr = tostring(err); end
    end
    return ok;
end
local function fire(evt, e)
    local list = HANDLERS[evt];
    if list == nil then return; end
    -- copy: a handler may (un)register mid-walk
    local snap = {};
    for i, h in ipairs(list) do snap[i] = h; end
    for _, h in ipairs(snap) do runHandler(h, e); end
end

-- packets
local function bytesToString(bytes)
    if type(bytes) == 'string' then return bytes; end
    local out = {};
    for i = 1, #bytes do out[i] = string.char((bytes[i] or 0) & 0xFF); end
    return table.concat(out);
end
local function packetEvent(id, data, injected)
    return { id = id, size = #data, data = data, data_raw = 1, data_modified = data, data_modified_raw = 1,
             chunk_data = data, chunk_data_raw = 1, chunk_size = #data, injected = injected or false,
             blocked = false };
end
deliverOut = function()
    local guard = 0;
    while #OUTQ > 0 and guard < 64 do
        guard = guard + 1;
        local p = table.remove(OUTQ, 1);
        fire('packet_out', packetEvent(p.id, bytesToString(p.bytes), true));
    end
end
local _outSeq = 0;
local function outgoingChunk()
    _outSeq = (_outSeq + 1) % 65536;
    local d = string.char(0x15, 0x10, _outSeq & 0xFF, _outSeq >> 8) .. string.rep('\0', 28);
    fire('packet_out', packetEvent(0x015, d, false));
    deliverOut();
end
local INBOUND = { { 0x00E, 0x60 }, { 0x00E, 0x60 }, { 0x00E, 0x60 }, { 0x00D, 0x9C }, { 0x00D, 0x9C },
                  { 0x017, 0x40 }, { 0x063, 0xC4 }, { 0x076, 0x48 }, { 0x037, 0x60 }, { 0x0DF, 0x24 } };
local _inAcc, _inN = 0, 0;
local function inboundFor(dt)
    _inAcc = _inAcc + (tonumber(opt.inbound) or 0) * dt;
    while _inAcc >= 1 do
        _inAcc = _inAcc - 1;
        _inN = _inN + 1;
        local spec = INBOUND[(_inN % #INBOUND) + 1];
        fire('packet_in', packetEvent(spec[1], string.char(spec[1] & 0xFF, spec[2] // 4, 0, 0) .. string.rep('\0', spec[2] - 4), false));
    end
end
-- Bit writer, LSB-first within bytes (equipengine.bitsAt's inverse -- the
-- run_tests EQE packStr).
local function packBits(len, writes)
    local b = {};
    for i = 1, len do b[i] = 0; end
    for _, w in ipairs(writes) do
        for i = 0, w[2] - 1 do
            if (w[3] >> i) & 1 == 1 then
                local pos = w[1] + i;
                local bi = pos // 8 + 1;
                b[bi] = b[bi] | (1 << (pos % 8));
            end
        end
    end
    return b;
end
-- 0x028 from `actorId`: actionType 1 = a melee round, 4 = a spell finished.
local function actionPacket(actorId, actionType)
    local b = packBits(0x40, { { 0, 8, 0x28 }, { 0x05 * 8, 32, actorId }, { 10 * 8 + 2, 4, actionType or 1 } });
    return bytesToString(b);
end
-- The player's own outgoing 0x01A: a spell (category 3) at the battle target.
local _castSync = 0;
local function castChunk(spellId, targetIndex)
    local w = 0x1A + (28 // 4) * 512;
    _castSync = _castSync + 1;   -- the header's sync counter: a NEW action, not a re-send
    local b = { w & 0xFF, w >> 8 };
    for i = 3, 28 do b[i] = 0; end
    b[3], b[4] = _castSync & 0xFF, (_castSync >> 8) & 0xFF;
    b[9], b[10] = targetIndex & 0xFF, targetIndex >> 8;
    b[11], b[12] = 3, 0;
    b[13], b[14] = spellId & 0xFF, spellId >> 8;
    return bytesToString(b);
end

-- ---------------------------------------------------------------------------
-- boot dlac.lua (measured as one block)
-- ---------------------------------------------------------------------------
collectgarbage('stop');
local bootRec = rec('boot', 'dlac.lua');
local okBoot, bootErr;
do
    CUR = bootRec;
    MEASURING = true;
    local kb0, t0 = collectgarbage('count'), REAL_CLOCK();
    local chunk, lerr = REAL_LOADFILE('dlac.lua');
    if chunk == nil then print('dlac.lua will not load: ' .. tostring(lerr)); os.exit(1); end
    okBoot, bootErr = pcall(chunk);
    bootRec.ms = (REAL_CLOCK() - t0 - OVER) * 1000;
    bootRec.kb = collectgarbage('count') - kb0;
    bootRec.calls = 1;
    CUR = nil;
    MEASURING = false;
end
collectgarbage('collect');
local heapAfterBoot = collectgarbage('count');
collectgarbage('stop');

-- ---------------------------------------------------------------------------
-- the frame loop
-- ---------------------------------------------------------------------------
local FRAMES = {};
local dt = 1 / opt.fps;
local nFrames = math.floor(opt.seconds * opt.fps);
local nWarm = math.floor((tonumber(opt.warm) or 0) * opt.fps);
local nextChunk = VT + (tonumber(opt.chunk) or 0.25);
local nextSwing = VT + 2.6;
local nextCast, castDoneAt = VT + 3.0, nil;
local measuredFrames = 0;
local GC_LIMIT_KB = 400 * 1024;
for f = 1, nWarm + nFrames do
    VT = VT + dt;
    W.frame = f;
    MEASURING = (f > nWarm);
    -- perf=<s>: run dlac's own /dl perf through the whole addon (its report
    -- lands in <scratch>\addon-debug\dlac-perf-<Name>-<when>.txt).
    if f == nWarm + 1 and opt.perf ~= nil then
        fire('command', { command = '/dl perf ' .. tostring(opt.perf), blocked = false });
    end
    FRAME = MEASURING and { ms = 0, kb = 0, who = {}, at = VT, f = f - nWarm } or nil;
    -- tasks
    if #TASKS > 0 then
        local due = {};
        for i = #TASKS, 1, -1 do if TASKS[i].at <= VT then due[#due + 1] = table.remove(TASKS, i); end end
        for _, t in ipairs(due) do
            CUR = rec('ashita.tasks', 'once'); pcall(t.fn); CUR = nil;
        end
    end
    if #INQ > 0 then
        local due = INQ;
        INQ = {};
        for _, p in ipairs(due) do fire('packet_in', packetEvent(p.id, p.data, false)); end
    end
    inboundFor(dt);
    if opt.combat == 1 and VT >= nextSwing then
        nextSwing = VT + 2.6;
        fire('packet_in', packetEvent(0x028, actionPacket(CHARID, 1), false));
        W.tp = (W.tp + 120) % 3000;
    end
    -- combat: a spell every `cast` seconds (Precast + Midcast swaps), its
    -- completion 2.5s later (the Default that swaps back = aftercast).
    if opt.combat == 1 and (tonumber(opt.cast) or 0) > 0 then
        if VT >= nextCast then
            nextCast = VT + opt.cast;
            castDoneAt = VT + 2.5;
            fire('packet_out', packetEvent(0x01A, castChunk(1, W.target), false));
            deliverOut();
        elseif castDoneAt ~= nil and VT >= castDoneAt then
            castDoneAt = nil;
            fire('packet_in', packetEvent(0x028, actionPacket(CHARID, 4), false));
        end
    end
    if VT >= nextChunk then
        nextChunk = VT + (tonumber(opt.chunk) or 0.25);
        outgoingChunk();
    end
    fire('d3d_present', nil);
    deliverOut();
    if FRAME ~= nil then
        FRAMES[#FRAMES + 1] = FRAME;
        measuredFrames = measuredFrames + 1;
    end
    if collectgarbage('count') > heapAfterBoot + GC_LIMIT_KB then
        collectgarbage('collect'); collectgarbage('stop');
    end
end
MEASURING = false;

-- ---------------------------------------------------------------------------
-- report
-- ---------------------------------------------------------------------------
local secs = measuredFrames / opt.fps;
local function pct(sorted, p)
    if #sorted == 0 then return 0; end
    local i = math.max(1, math.min(#sorted, math.ceil(p * #sorted)));
    return sorted[i];
end
print(string.format('dlac frame profile -- char %s, job %d, %d bag items, %s, %ds @ %d fps (+%ds warm-up), chunk every %.2fs, %d inbound/s',
    opt.char, W.job, bagCount(), (opt.combat == 1) and 'COMBAT' or 'idle', opt.seconds, opt.fps, opt.warm,
    opt.chunk, opt.inbound));
print(string.format('boot: %s  %.0f ms, %.1f MB allocated, heap after boot %.1f MB',
    okBoot and 'ok' or ('FAILED: ' .. tostring(bootErr)), bootRec.ms, bootRec.kb / 1024, heapAfterBoot / 1024));

local fms, fkb = {}, {};
local over = { [2] = 0, [4] = 0, [8] = 0, [16] = 0 };
local totalMs, totalKb = 0, 0;
for _, fr in ipairs(FRAMES) do
    fms[#fms + 1] = fr.ms; fkb[#fkb + 1] = fr.kb;
    totalMs, totalKb = totalMs + fr.ms, totalKb + fr.kb;
    for t in pairs(over) do if fr.ms >= t then over[t] = over[t] + 1; end end
end
table.sort(fms); table.sort(fkb);
print(string.format('per frame (dlac total): mean %.3f ms, p50 %.0f, p90 %.0f, p99 %.0f, max %.0f ms | alloc mean %.1f KB/frame (%.0f KB/s), max %.0f KB',
    totalMs / math.max(1, #FRAMES), pct(fms, 0.5), pct(fms, 0.9), pct(fms, 0.99), pct(fms, 1.0),
    totalKb / math.max(1, #FRAMES), totalKb / math.max(1, secs), pct(fkb, 1.0)));
print(string.format('frames >=2ms: %d  >=4ms: %d  >=8ms: %d  >=16ms: %d   (of %d)', over[2], over[4], over[8], over[16], #FRAMES));

-- per handler
local list = {};
for _, r in pairs(RECS) do if r.calls > 0 and r.key ~= 'boot/dlac.lua' then list[#list + 1] = r; end end
table.sort(list, function(a, b) return a.ms > b.ms; end);
print('');
print(string.format('%-46s %7s %8s %8s %8s %9s %7s %8s %6s', 'handler (by total time)', 'calls', 'ms/s', 'avg us', 'max ms',
    'KB/s', 'io/s', 'api/call', 'errs'));
for i, r in ipairs(list) do
    if i > opt.top then break; end
    print(string.format('%-46s %7d %8.3f %8.1f %8.0f %9.1f %7.2f %8.1f %6d', r.key:sub(1, 46), r.calls, r.ms / secs,
        r.ms * 1000 / r.calls, r.maxms, r.kb / secs, r.io / secs, r.api / r.calls, r.errors));
end
print('');
print('handler errors (first message):');
local anyErr = false;
for _, r in pairs(RECS) do
    if r.errors > 0 then anyErr = true; print(string.format('  %s x%d: %s', r.key, r.errors, tostring(r.lastErr):sub(1, 200))); end
end
if not anyErr then print('  none'); end

-- file system
print('');
print('file-system ops during measurement (per second, by path):');
local iol = {};
for k, n in pairs(IOPATH) do iol[#iol + 1] = { k = k, n = n }; end
table.sort(iol, function(a, b) return a.n > b.n; end);
for i, e in ipairs(iol) do
    if i > 30 then break; end
    print(string.format('  %8.2f/s  %s', e.n / secs, e.k));
end
if #iol == 0 then print('  none'); end
print('io by handler:');
for _, r in ipairs(list) do
    if r.io > 0 then
        local parts = {};
        for k, n in pairs(r.ioBy) do parts[#parts + 1] = string.format('%s %.2f/s', k, n / secs); end
        table.sort(parts);
        print(string.format('  %-44s %s', r.key:sub(1, 44), table.concat(parts, ', ')));
        local pl = {};
        for k, n in pairs(r.ioPath) do pl[#pl + 1] = { k = k, n = n }; end
        table.sort(pl, function(a, b) return a.n > b.n; end);
        for i, e in ipairs(pl) do
            if i > 8 then break; end
            print(string.format('      %6.2f/s  %s', e.n / secs, e.k));
        end
    end
end

-- API
print('');
print('AshitaCore calls during measurement (per second):');
local apiTotal = 0;
for _, r in ipairs(list) do apiTotal = apiTotal + r.api; end
print(string.format('  total %.0f calls/s', apiTotal / secs));
for _, r in ipairs(list) do
    if r.api / secs >= 10 then
        local parts = {};
        for k, n in pairs(r.apiBy) do parts[#parts + 1] = { k = k, n = n }; end
        table.sort(parts, function(a, b) return a.n > b.n; end);
        local s = {};
        for i, p in ipairs(parts) do if i > 6 then break; end s[#s + 1] = string.format('%s %.0f', p.k, p.n / secs); end
        print(string.format('  %-44s %8.0f/s  %s', r.key:sub(1, 44), r.api / secs, table.concat(s, ', ')));
    end
end

if opt.sites == 1 then
    print('');
    print('heavy API call sites (per second):');
    local sl = {};
    for k, n in pairs(SITES) do sl[#sl + 1] = { k = k, n = n }; end
    table.sort(sl, function(a, b) return a.n > b.n; end);
    for i, e in ipairs(sl) do
        if i > 20 then break; end
        print(string.format('  %8.0f/s  %s', e.n / secs, e.k));
    end
end

-- what dlac sent
print('');
local sp = {};
for id, n in pairs(SENT) do sp[#sp + 1] = string.format('0x%03X x%d', id, n); end
table.sort(sp);
print('packets dlac injected (whole run): ' .. (#sp > 0 and table.concat(sp, ', ') or 'none'));
local qc = {};
for c, n in pairs(QCMD) do qc[#qc + 1] = string.format('%s x%d', c, n); end
table.sort(qc);
print('commands dlac queued (whole run): ' .. (#qc > 0 and table.concat(qc, ', ') or 'none'));

-- spikes
print('');
print('worst frames:');
local byMs = {};
for _, fr in ipairs(FRAMES) do byMs[#byMs + 1] = fr; end
table.sort(byMs, function(a, b) return a.ms > b.ms; end);
for i, fr in ipairs(byMs) do
    if i > opt.spikes or fr.ms < 1 then break; end
    print(string.format('  frame %5d (t=%7.2fs) %5.0f ms %7.0f KB  %s', fr.f, fr.f / opt.fps, fr.ms, fr.kb, table.concat(fr.who, '; ')));
end
-- periodicity of the >=2ms frames
local idx = {};
for _, fr in ipairs(FRAMES) do if fr.ms >= 2 then idx[#idx + 1] = fr.f; end end
if #idx > 2 then
    local gaps = {};
    for i = 2, #idx do local g = idx[i] - idx[i - 1]; gaps[g] = (gaps[g] or 0) + 1; end
    local gl = {};
    for g, n in pairs(gaps) do gl[#gl + 1] = { g = g, n = n }; end
    table.sort(gl, function(a, b) return a.n > b.n; end);
    local s = {};
    for i, e in ipairs(gl) do if i > 6 then break; end s[#s + 1] = string.format('%d frames (%.2fs) x%d', e.g, e.g / opt.fps, e.n); end
    print('gaps between >=2ms frames: ' .. table.concat(s, ', '));
end

-- sampling profile
if opt.sample == 1 or opt.alloc == 1 then
    print('');
    if opt.alloc == 1 then
        print('ALLOCATION samples (KB, attributed per 100 VM instructions), top lines per heavy handler:');
        table.sort(list, function(a, b) return a.kb > b.kb; end);
    else
        print(string.format('instruction samples (1 per %d VM instructions), top lines per heavy handler:', SAMPLE_EVERY));
    end
    for i, r in ipairs(list) do
        if i > 8 then break; end
        local hl = {};
        local tot = 0;
        for k, n in pairs(r.hist) do hl[#hl + 1] = { k = k, n = n }; tot = tot + n; end
        if tot > 0 then
            table.sort(hl, function(a, b) return a.n > b.n; end);
            if opt.alloc == 1 then
                print(string.format('  %s  (%.0f KB sampled, %.1f KB/call)', r.key, tot, tot / r.calls));
            else
                print(string.format('  %s  (%d samples = %.1fM instr, %.0f instr/call)', r.key, tot, tot * SAMPLE_EVERY / 1e6,
                    tot * SAMPLE_EVERY / r.calls));
            end
            for j, e in ipairs(hl) do
                if j > 12 then break; end
                print(string.format('      %8.0f  %s', e.n, e.k));
            end
            local fl = {};
            for k, n in pairs(r.fhist) do fl[#fl + 1] = { k = k, n = n }; end
            table.sort(fl, function(a, b) return a.n > b.n; end);
            print('    by function:');
            for j, e in ipairs(fl) do
                if j > 10 then break; end
                print(string.format('      %8.0f  %s', e.n, e.k));
            end
        end
    end
end
