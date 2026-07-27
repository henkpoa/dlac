--[[
    dlac/feature/engine.lua -- the '/dl engine' command surface.

    STATUS-ONLY since the purge, Phase 2 (Henrik's ruling): dlac is the
    engine, always -- there is no flip left to perform.
        /dl engine                    the status readout (storage home,
                                      migration state, tripwire, armed)
        /dl engine migrate            re-run the legacy storage copy by hand
                                      (idempotent -- existing files win; the
                                      kept migrate carrier)
    '/dl engine native on|off' answers with the truth instead of flipping:
    on = already and always native; off = refused loudly (the legacy engine
    is gone -- an old engine.lua flag on disk is retired in place, ignored).
]]--

local M = {};

local _cfok, cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(cfmt) == 'table';
local function say(s)  if _cfok then cfmt.msg(s); else print('[dlac] ' .. s); end end
local function warn(s) if _cfok then cfmt.err(s); else print('[dlac] ' .. s); end end

local function prof()
    local ok, p = pcall(require, 'dlac\\profiles');
    return (ok and type(p) == 'table') and p or nil;
end

local function engine()
    local ok, e = pcall(require, 'dlac\\feature\\equipengine');
    return (ok and type(e) == 'table') and e or nil;
end

-- The status readout. Facts only, one line each -- absence is a diagnosis
-- (the /dl check house rule).
local function status()
    local p = prof();
    if p == nil then warn('engine: profiles module unavailable.'); return; end
    say('engine: NATIVE (dlac equips gear itself -- the only engine since the purge).');
    pcall(function()
        local d = p.dataDir();
        say('engine: storage home ' .. tostring(d or '(pre-login)'));
    end);
    pcall(function()
        local nb = p.nativeCharBase();
        if nb == nil then return; end
        local f = io.open(nb .. 'profile.lua', 'r');
        if f ~= nil then f:close(); say('engine: storage MIGRATED (pointer present).');
        else say('engine: storage not migrated yet -- auto-migration runs on login.'); end
    end);
    local e = engine();
    if e ~= nil then
        if e.state.tripped then
            warn('engine: TRIPWIRE FIRED this session -- another equip engine re-injected an action packet. Interception is disarmed; unload the other engine and /addon reload dlac.');
        else
            local armed = false;
            pcall(function() armed = e.nativeOn(); end);
            say('engine: interception ' .. (armed and 'ARMED (this state)' or 'not armed in this state'));
        end
    end
end

local function migrate()
    local p = prof();
    if p == nil then warn('engine: profiles module unavailable.'); return; end
    local done, skipped, failed = p.engineMigrateStorage();
    if done == nil then
        warn('engine migrate: ' .. tostring(skipped));   -- second return = why
        return;
    end
    say(string.format('engine migrate: %d file(s) copied, %d already in the native home, %d failed. Legacy files stay untouched.',
        done, skipped, failed));
end

local function setNative(on)
    if on then
        say('engine: already native -- dlac has been the only engine since the purge; there is nothing to turn on.');
    else
        warn('engine: refused -- the legacy (LuaAshitacast-hosted) engine no longer exists, so there is nothing to switch to. dlac equips natively, always.');
    end
end

pcall(function()
    ashita.events.register('command', 'dlac-engine-cmd', function(e)
        local cmd = string.lower(tostring(e.command or ''));
        local args = {};
        for a in string.gmatch(cmd, '%S+') do args[#args + 1] = a; end
        if args[1] ~= '/dl' and args[1] ~= '/dlac' then return; end
        if args[2] ~= 'engine' then return; end
        e.blocked = true;
        local sub = args[3];
        if sub == nil then status(); return; end
        if sub == 'migrate' then migrate(); return; end
        if sub == 'native' then
            local v = args[4];
            if v == 'on' then setNative(true); return; end
            if v == 'off' then setNative(false); return; end
            warn('usage: /dl engine native on|off');
            return;
        end
        warn('usage: /dl engine [native on|off | migrate]');
    end);
end);

return M;
