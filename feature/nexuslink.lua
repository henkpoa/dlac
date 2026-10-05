--[[
    dlac/feature/nexuslink.lua -- crafting gear for the recipe Nexus is about to synth.

    Nexus is AscensionXI's crafting window. It starts synths itself, quickly,
    and the server rolls a synth's break and HQ the moment the synth arrives:
    gear put on after that counts from the next synth only (craftwatch's TIMING
    TRUTH). So dlac cannot find the recipe out in time by watching; Nexus tells
    it first. Before every synth Nexus names the crafts the recipe needs, dlac
    puts on the best owned pieces for it (feature\craftpick: weakest craft
    first) and says "ready", and only then does Nexus send the synth.

    THE CONVERSATION rides Ashita's plugin_event bus: both addons live in this
    client and nothing here reaches the server. Messages are plain
    "key=value;key=value" text, never code.
      Nexus -> 'nexus_craft'
        op=hello                       Nexus loaded: who is listening?
        op=next;seq=N;crafts=Smithing:30,Woodworking:60;recipe=R;result=I;desynth=0|1
                                       the next synth needs these crafts
      dlac -> 'dlac_craft'
        op=hello;v=1;follow=1|0        dlac is here (the answer to hello, and at load)
        op=ready;seq=N;state=S         gear for synth N is settled:
                                         worn     every picked piece is on
                                         partial  some piece never went on (a Lock,
                                                  Free equip, a refused equip...)
                                         none     no craft gear for this recipe
                                         off      /dl craft nexus off
                                         cleared  the lock ended while Nexus waited
        op=bye                         dlac unloaded
    Nexus waits for `ready` only when dlac has said hello, and never longer than
    its own few seconds, so a client without dlac crafts exactly as before.

    THE LOCK (owner, 2026-10-04): "lock the crafting gear until the person moves
    or until Nexus says something else that needs changing". The picks stay on
    across synths and across Nexus runs. A new recipe whose picks are the same
    keeps the lock and is answered at once (the gear is already on, nothing to
    wait for); different picks replace it. Moving more than MOVE_YALMS, zoning,
    engaging, dying, a job change or /dl craft nexus off ends it, and the
    engine's normal gear returns on its next dispatch.

    The ENGINE reads the lock through M.lockState() (dispatch.lua's Craft row,
    required lazily like extclaim): the picks ride the existing Craft claimant,
    so Locks, Free equip, Claim Priority and /dl why treat them like any
    craft gear. Nothing is written to disk; the lock is session state.

    Pure core (parse / format / crafts / handle) under the live edge at the
    bottom; tests\nexuscraft.lua drives it headless (NL*).
]]--

local M = {};

local craftpick = require('dlac\\feature\\craftpick');

M.EVENT_IN   = 'nexus_craft';
M.EVENT_OUT  = 'dlac_craft';
M.PROTOCOL   = 1;
M.CONFIRM_S  = 2.5;    -- a new lock that never fully lands is answered 'partial' after this
M.MOVE_YALMS = 0.5;    -- moving farther than this from where the lock began ends it
M.WATCH_S    = 0.25;   -- how often the lock checks position and status
M.INBOX_MAX  = 16;     -- messages kept between two frames; more are dropped

M._inbox    = {};
M._lock     = nil;     -- { picks, state, req, key, info, at, pos, job, settled }
M._pending  = nil;     -- { seq, deadline }
M._hello    = false;   -- dlac's own hello went out this session
M._watchAt  = 0;
M._lastNote = nil;     -- why the last lock ended (status text)

-- ---------------------------------------------------------------------------
-- pure core
-- ---------------------------------------------------------------------------

local CRAFT_NAME = {};
for _, c in ipairs(craftpick.CRAFTS) do CRAFT_NAME[string.lower(c)] = c; end

-- "k=v;k=v" -> { k = v } (strings), or nil when it is not a message.
function M.parse(raw)
    if type(raw) ~= 'string' or raw == '' or #raw > 2048 then return nil; end
    local t = {};
    for k, v in raw:gmatch('([%w_]+)=([^;]*)') do t[k] = v; end
    if type(t.op) ~= 'string' or t.op == '' then return nil; end
    return t;
end

-- { k = v } -> "k=v;k=v", keys sorted so a message reads the same every time.
function M.format(t)
    local ks, parts = {}, {};
    for k in pairs(t) do ks[#ks + 1] = tostring(k); end
    table.sort(ks, function(a, b)
        if a == 'op' then return b ~= 'op'; end
        if b == 'op' then return false; end
        return a < b;
    end);
    for _, k in ipairs(ks) do
        local v = t[k];
        if type(v) == 'boolean' then v = v and 1 or 0; end
        parts[#parts + 1] = k .. '=' .. (tostring(v):gsub('[;=]', ''));
    end
    return table.concat(parts, ';');
end

-- "Smithing:30,Woodworking:60" -> { Smithing = 30, Woodworking = 60 }. Unknown
-- craft names and levels outside 1..150 are skipped.
function M.crafts(s)
    local req = {};
    for name, lv in tostring(s or ''):gmatch('([%a]+):(%d+)') do
        local c = CRAFT_NAME[string.lower(name)];
        local n = tonumber(lv);
        if c ~= nil and n ~= nil and n >= 1 and n <= 150 then req[c] = n; end
    end
    return req;
end

-- The requirement map back as text, in craft order (status lines, tests).
function M.craftsText(req, sep)
    local parts = {};
    for _, c in ipairs(craftpick.CRAFTS) do
        if req ~= nil and req[c] ~= nil then parts[#parts + 1] = c .. ' ' .. tostring(req[c]); end
    end
    return table.concat(parts, sep or ' + ');
end

-- The live reads, behind one table the suite replaces.
M._io = {};

local function io_(name, ...)
    local f = M._io[name];
    if type(f) ~= 'function' then return nil; end
    local ok, v = pcall(f, ...);
    if ok then return v; end
    return nil;
end

local function emit(t)
    local s = M.format(t);
    local b = {};
    for i = 1, #s do b[i] = string.byte(s, i); end
    pcall(function() M._raise(M.EVENT_OUT, b); end);
end
M._emit = emit;

local function reply(seq, state)
    emit({ op = 'ready', seq = seq, state = state });
end

local function hello()
    emit({ op = 'hello', v = M.PROTOCOL, follow = (io_('follow') ~= false) });
    M._hello = true;
end

-- End the lock: the engine's normal gear comes back on its next dispatch. A
-- synth Nexus is still waiting for is answered so it does not sit out its
-- timeout.
function M.clear(why)
    if M._lock ~= nil then M._lastNote = why; end
    M._lock = nil;
    if M._pending ~= nil then
        reply(M._pending.seq, 'cleared');
        M._pending = nil;
    end
end

-- The slots whose picked piece is not on yet.
function M.missing(picks)
    local out = {};
    for _, slot in ipairs(craftpick.SLOT_ORDER) do
        local want = picks[slot];
        if want ~= nil then
            local worn = io_('wornName', slot);
            if type(worn) ~= 'string' or string.lower(worn) ~= string.lower(want) then
                out[#out + 1] = slot;
            end
        end
    end
    return out;
end

-- One `next` message: pick, lock, and start waiting for the gear.
function M.handleNext(msg, now)
    local seq = tonumber(msg.seq) or 0;
    if M._pending ~= nil then                     -- a newer synth replaces an unanswered one
        reply(M._pending.seq, 'cleared');
        M._pending = nil;
    end
    if io_('follow') == false then
        M.clear('off');
        reply(seq, 'off');
        return;
    end
    local req = M.crafts(msg.crafts);
    if next(req) == nil then reply(seq, 'none'); return; end
    local skills = {};
    for c in pairs(req) do skills[c] = io_('skill', c); end
    local picks, info = craftpick.pick(io_('items') or {}, req, skills,
        { goal = io_('goal'), level = io_('level') });
    if next(picks) == nil then
        M.clear('no gear');
        reply(seq, 'none');
        return;
    end
    local lock = M._lock;
    if lock ~= nil and craftpick.samePicks(lock.picks, picks) then
        lock.req, lock.info = req, info;          -- same pieces: the lock stands
    else
        M._lock = {
            picks = picks,
            -- The table the engine's Craft row reads (dispatch craftRowState):
            -- built once per lock so a dispatch allocates nothing for it.
            state = { enabled = true, craft = 'Nexus', nexus = picks },
            req = req, info = info, at = now,
            pos = io_('position'), job = io_('job'),
            settled = false,
        };
        M._lastNote = nil;
    end
    M._pending = { seq = seq, deadline = now + M.CONFIRM_S };
end

-- Answer the waiting synth once its gear is on (or once it is clear it never
-- will be). A lock that was settled once answers at once from then on: the
-- pieces it could put on are on, and waiting again would only slow every synth.
function M.checkPending(now)
    local p = M._pending;
    if p == nil then return; end
    local lock = M._lock;
    if lock == nil then reply(p.seq, 'cleared'); M._pending = nil; return; end
    local miss = M.missing(lock.picks);
    if #miss == 0 then
        lock.settled = true;
        reply(p.seq, 'worn');
        M._pending = nil;
    elseif lock.settled or now >= p.deadline then
        lock.settled = true;
        reply(p.seq, 'partial');
        M._pending = nil;
    end
end

-- Has the player moved, zoned, engaged, died or changed job since the lock?
function M.watch(now)
    local lock = M._lock;
    if lock == nil or now < M._watchAt then return; end
    M._watchAt = now + M.WATCH_S;
    local st = io_('status');
    if st == 'Engaged' or st == 'Dead' then M.clear(string.lower(st)); return; end
    local job = io_('job');
    if lock.job ~= nil and job ~= nil and job ~= lock.job then M.clear('job change'); return; end
    local pos = io_('position');
    if pos == nil then return; end                -- unreadable (zoning): decide next time
    if lock.pos == nil then lock.pos = pos; return; end
    if pos.zone ~= lock.pos.zone then M.clear('zoned'); return; end
    local dx, dy, dz = pos.x - lock.pos.x, pos.y - lock.pos.y, (pos.z or 0) - (lock.pos.z or 0);
    if dx * dx + dy * dy + dz * dz > M.MOVE_YALMS * M.MOVE_YALMS then M.clear('moved'); end
end

-- The frame beat (dlac.lua's d3d_present): handle what arrived, answer, watch.
function M._pump(now)
    now = now or M._clock();
    if not M._hello then hello(); end
    if #M._inbox > 0 then
        local box = M._inbox;
        M._inbox = {};
        for _, msg in ipairs(box) do
            if msg.op == 'hello' then hello();
            elseif msg.op == 'next' then M.handleNext(msg, now); end
        end
    end
    M.checkPending(now);
    M.watch(now);
end

-- The plugin_event door: keep the message for the frame, do nothing else here.
function M._onEvent(e)
    local name = nil;
    pcall(function() name = e.name; end);
    if tostring(name or '') ~= M.EVENT_IN then return; end
    local raw = nil;
    pcall(function() raw = e.data; end);
    local msg = M.parse(raw);
    if msg == nil or #M._inbox >= M.INBOX_MAX then return; end
    M._inbox[#M._inbox + 1] = msg;
end

-- What the engine's Craft row wears: the lock's claim state, or nil.
function M.lockState()
    local lock = M._lock;
    return lock and lock.state or nil;
end

-- One line for /dl craft and /dl craft nexus.
function M.statusText()
    local lock = M._lock;
    if lock == nil then
        if M._lastNote ~= nil then return 'no gear locked (the last lock ended: ' .. M._lastNote .. ')'; end
        return 'no recipe from Nexus yet';
    end
    local n = 0;
    for _ in pairs(lock.picks) do n = n + 1; end
    local weak = '';
    if lock.info ~= nil and lock.info.weakest ~= nil then
        local m = lock.info.margins[lock.info.weakest];
        weak = string.format(', weakest %s %s%d', lock.info.weakest, (m or 0) >= 0 and '+' or '', m or 0);
    end
    return string.format('%d piece%s locked for %s%s, until you move',
        n, n == 1 and '' or 's', M.craftsText(lock.req), weak);
end

-- ---------------------------------------------------------------------------
-- The live edge. Everything below touches Ashita; everything above does not.
-- ---------------------------------------------------------------------------

M._raise = function(name, bytes) AshitaCore:GetPluginManager():RaiseEvent(name, bytes); end
M._clock = function() return os.clock(); end

local function req(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

M._io.follow = function()
    local cw = req('dlac\\feature\\craftwatch');
    return cw == nil or cw.getFollowNexus() ~= false;
end
M._io.goal = function()
    local cw = req('dlac\\feature\\craftwatch');
    return cw and cw.getGoal() or 'hq';
end
M._io.skill = function(craft)
    local cw = req('dlac\\feature\\craftwatch');
    local info = cw and cw.craftSkillInfo(craft) or nil;
    return info and info.skill or nil;
end
-- The level the engine gears at: the /dl set level override, then the
-- sync-aware main level (feature\modapi's S.player.level, same rule).
M._io.level = function()
    local ovr = rawget(_G, 'staticMainLevel');
    if type(ovr) == 'number' and ovr > 0 then return ovr; end
    local p = gData.GetPlayer();
    local lv = p and tonumber(p.MainJobSync) or nil;
    if lv ~= nil and lv > 0 then return lv; end
    return nil;
end
M._io.job = function()
    local p = gData.GetPlayer();
    return p and p.MainJob or nil;
end
M._io.status = function()
    local p = gData.GetPlayer();
    return p and p.Status or nil;
end
-- The craft pieces from the gear-helper manifest, rescanned first when the
-- manifest on disk is older than this build (it then lacks craftItems).
M._io.items = function()
    local au = req('dlac\\ui\\automationsui');
    if au == nil then return nil; end
    if au.manifestStale() then au.rescanAutogear(); end
    return au.craftItems();
end
M._io.wornName = function(slot)
    local dsp = req('dlac\\dispatch');
    return dsp and dsp.wornName(slot) or nil;
end
M._io.position = function()
    local mm = AshitaCore:GetMemoryManager();
    local idx = mm:GetParty():GetMemberTargetIndex(0);
    if idx == nil or idx == 0 then return nil; end
    local ent = mm:GetEntity();
    local x, y, z = ent:GetLocalPositionX(idx), ent:GetLocalPositionY(idx), ent:GetLocalPositionZ(idx);
    if x == nil or y == nil then return nil; end
    local loc = req('dlac\\feature\\location');
    local zone = loc and loc.zoneId() or nil;
    if zone == nil then return nil; end
    return { x = x, y = y, z = z, zone = zone };
end

-- Live registration: the inbound door and the goodbye. The frame beat is
-- dlac.lua's (the extclaim pattern), so this module is listening from the
-- first frame. (Headless: no ashita, tests drive M._onEvent / M._pump.)
pcall(function()
    ashita.events.register('plugin_event', 'dlac_nexuslink', function(e)
        pcall(M._onEvent, e);
    end);
    ashita.events.register('unload', 'dlac_nexuslink_unload', function()
        pcall(emit, { op = 'bye' });
    end);
end);

return M;
