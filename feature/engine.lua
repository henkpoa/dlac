--[[
    dlac/feature/engine.lua -- the '/dl engine' command surface.
    feature/native-engine: dlac absorbing LuaAshitacast.

    The user-facing door for the engine flip:
        /dl engine                    the status readout (mode, storage home,
                                      migration state, tripwire)
        /dl engine native on          migrate storage (copy, legacy stays) +
                                      write the flag + print the checklist
        /dl engine native off         write the flag off + print the way back
        /dl engine migrate            re-run the storage copy by hand
                                      (idempotent -- existing files win)

    The flag itself lives in config\addons\dlac\engine.lua (profiles.lua is
    the authority); a flip only fully applies after /addon reload dlac -- and
    NATIVE ON requires LuaAshitacast unloaded (two engines both blocking
    action packets is the coexistence hazard equipengine's tripwire disarms
    on). This module prints those steps rather than automating them: the
    user should see the two-command flip, not feel a magic reload.
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
    local on = false;
    pcall(function() on = p.nativeMode(); end);
    say('engine: ' .. (on and 'NATIVE (dlac equips gear itself)' or 'LAC (LuaAshitacast equips; dlac drives it)'));
    pcall(function() say('engine: flag file ' .. tostring(p.engineFlagPath())); end);
    pcall(function()
        local d = p.dataDir();
        say('engine: storage home ' .. tostring(d or '(pre-login)'));
    end);
    pcall(function()
        local nb = p.nativeCharBase();
        if nb == nil then return; end
        local f = io.open(nb .. 'profile.lua', 'r');
        if f ~= nil then f:close(); say('engine: native storage MIGRATED (pointer present).');
        else say('engine: native storage not migrated yet' .. (on and ' -- auto-migration runs on login' or '') .. '.'); end
    end);
    local e = engine();
    if e ~= nil then
        if e.state.tripped then
            warn('engine: TRIPWIRE FIRED this session -- another equip engine re-injected an action packet (LuaAshitacast still loaded?). Interception is disarmed; unload luashitacast and /addon reload dlac.');
        elseif on then
            local armed = false;
            pcall(function() armed = e.nativeOn(); end);
            say('engine: interception ' .. (armed and 'ARMED (this state)' or 'not armed in this state'));
        end
    end
    if on then
        say('engine: native mode needs LuaAshitacast UNLOADED (/addon unload luashitacast).');
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
    local p = prof();
    if p == nil then warn('engine: profiles module unavailable.'); return; end
    if on then
        -- migrate FIRST (idempotent; never overwrites), then flip
        migrate();
        local ok, err = p.setNativeMode(true);
        if ok ~= true then warn('engine: could not write the flag: ' .. tostring(err)); return; end
        say('engine: NATIVE mode flagged ON. To board it:');
        say('engine:   1.  /addon unload luashitacast');
        say('engine:   2.  /addon reload dlac');
        say('engine: flip back any time with /dl engine native off (legacy files never moved).');
    else
        local ok, err = p.setNativeMode(false);
        if ok ~= true then warn('engine: could not write the flag: ' .. tostring(err)); return; end
        say('engine: native mode flagged OFF. To board LAC mode:');
        say('engine:   1.  /addon load luashitacast');
        say('engine:   2.  /addon reload dlac');
        say('engine: note -- edits made IN native mode live in config\\addons\\dlac\\ and are not copied back.');
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
