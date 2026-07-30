--[[
    dlac/feature/keybinds.lua -- THE keybind registry. One question, in the
    Central-services shape:

        "Who holds this key, and with what?"

        keybinds.register(owner, key, command, label) -> ok, info
        keybinds.holder(key)                          -> { owner, label, command } | nil
        keybinds.syncGroup(prefix, entries)           -> the whole-group diff
        keybinds.release(owner) / releaseGroup(prefix)
        keybinds.list()                               -> every live bind, sorted

    WHY IT EXISTS. dlac issued binds from two places that could not see each
    other: the Modes loader (dispatch, per job trigger file) and the addon's own
    CTRL+K. The loader's `_boundKeys` was a DEDUPE MAP, not a registry -- it
    stopped `/bind` spam and could not answer "is this key taken", by whom, or
    with what. So a second feature wanting a key had no way to ask, and a mode
    from the job you just left kept its key forever (nothing ever released one).
    Henrik's ruling, 2026-07-30: "If a bind exists, it needs to be able to tell
    where and with what and block them from binding over it."

    BLOCKING IS THE POINT HERE, and it is not the sandbox-shaped gating this
    project rejects (ADR 0028): a key is a genuinely EXCLUSIVE resource -- two
    owners cannot both have F9, the second simply silently destroys the first.
    Refusing the second and NAMING the holder is the only outcome that leaves
    the player able to fix it. Nothing is hidden and nothing is de-powered: the
    player re-types the key on either side and it lands.

    OWNERSHIP IS A STRING, and by convention a namespaced one -- 'mode:weapon',
    'jobhelper:bst-helper:summon', 'dlac:ui'. The namespace is what makes
    `releaseGroup('mode:')` mean "drop every mode bind", which is how a job
    change stops leaving its keys behind.

    SYNCGROUP is what a per-job owner actually wants: hand it the whole group as
    it should be RIGHT NOW and it works out the difference -- releases what is
    gone, registers what is new, leaves what is unchanged completely alone. That
    last part matters as much as the other two: the trigger loader re-parses on
    every '/dl triggers reload' (the automations rescan pings one after every
    inventory sync), and re-issuing an unchanged bind was a field-reported
    /bind storm.

    Pure at load; every AshitaCore touch is call-time behind the M.io seam, so
    the whole registry drives headlessly.
]]--

local M = {};

M.VERSION = 1;

-- owner -> { key = <normalized>, raw = <as the author typed it>, command, label }
local _byOwner = {};
-- normalized key -> owner
local _byKey = {};
-- owner\031key -> true, so one collision is reported once and not once per reload
local _told = {};

-- ---------------------------------------------------------------------------
-- the io seam (injected wholesale by the tests -- the fight.reads idiom)
-- ---------------------------------------------------------------------------

M.io = {};

M.io.bind = function(key, command)
    pcall(function()
        AshitaCore:GetChatManager():QueueCommand(-1, ('/bind %s %s'):format(key, command));
    end);
end;

M.io.unbind = function(key)
    pcall(function()
        AshitaCore:GetChatManager():QueueCommand(-1, ('/unbind %s'):format(key));
    end);
end;

-- One loud line. A refused bind is exactly the case where silence reads as a
-- broken feature -- the player pressed a key and something else happened.
M.say = function(line)
    local said = false;
    pcall(function()
        local cf = require('dlac\\chatfmt');
        if type(cf) == 'table' and type(cf.warn) == 'function' then cf.warn(line); said = true; end
    end);
    if not said then pcall(function() print('[dlac] ' .. tostring(line)); end); end
end;

-- ---------------------------------------------------------------------------
-- the key itself
-- ---------------------------------------------------------------------------

-- Ashita's own bind syntax, canonicalised for COMPARISON only: whitespace off
-- both ends, lowercased. The modifier sigils (^ ctrl, ! alt, @ win, # apps) are
-- already distinct characters; it is the key name that arrives in whatever case
-- the author typed, and '^F3' and '^f3' are one physical key. The RAW string is
-- kept beside it and is what gets issued, so nothing is retyped for the client.
function M.normalize(key)
    if type(key) ~= 'string' then return nil; end
    local k = (key:gsub('^%s+', ''):gsub('%s+$', ''));
    if k == '' then return nil; end
    return string.lower(k);
end

-- Who holds this key? nil when nobody does.
function M.holder(key)
    local k = M.normalize(key);
    if k == nil then return nil; end
    local owner = _byKey[k];
    if owner == nil then return nil; end
    local rec = _byOwner[owner];
    if rec == nil then return nil; end
    return { owner = owner, key = rec.key, raw = rec.raw, command = rec.command, label = rec.label };
end

-- What is this owner holding? nil when nothing.
function M.heldBy(owner)
    if type(owner) ~= 'string' then return nil; end
    local rec = _byOwner[owner];
    if rec == nil then return nil; end
    return { owner = owner, key = rec.key, raw = rec.raw, command = rec.command, label = rec.label };
end

-- The player-facing name for a bind, for the collision line and /dl binds.
local function nameOf(rec, owner)
    if type(rec) == 'table' and type(rec.label) == 'string' and rec.label ~= '' then return rec.label; end
    return tostring(owner);
end

-- ---------------------------------------------------------------------------
-- register / release
-- ---------------------------------------------------------------------------

-- Claim a key for an owner.
--
-- Returns ok, info where info is one of:
--   { changed = true }            -- bound (or moved to a new key / command)
--   { unchanged = true }          -- already exactly this; NOTHING was issued
--   { taken = <holder> }          -- refused: somebody else has that key
--   { reason = 'bad-key' | 'bad-owner' | 'bad-command' }
--
-- An owner holds at most ONE key: registering a second moves it, releasing the
-- first, because that is what "change my keybind" means everywhere in the GUI.
function M.register(owner, key, command, label)
    if type(owner) ~= 'string' or owner == '' then return false, { reason = 'bad-owner' }; end
    if type(command) ~= 'string' or command == '' then return false, { reason = 'bad-command' }; end
    local k = M.normalize(key);
    if k == nil then return false, { reason = 'bad-key' }; end

    local mine = _byOwner[owner];
    if mine ~= nil and mine.key == k and mine.command == command then
        return true, { unchanged = true };          -- the /bind storm guard
    end

    local other = _byKey[k];
    if other ~= nil and other ~= owner then
        local held = M.holder(k);
        local tag = owner .. '\031' .. k;
        if not _told[tag] then
            _told[tag] = true;
            M.say(('%s cannot take %s -- %s already has it (%s). Pick another key.'):format(
                label or owner, tostring(key), nameOf(held, other), tostring(held and held.command or '?')));
        end
        return false, { taken = held };
    end

    if mine ~= nil and mine.key ~= k then M.io.unbind(mine.raw or mine.key); _byKey[mine.key] = nil; end
    _byOwner[owner] = { key = k, raw = (key:gsub('^%s+', ''):gsub('%s+$', '')),
                        command = command, label = label };
    _byKey[k] = owner;
    _told[owner .. '\031' .. k] = nil;
    M.io.bind(_byOwner[owner].raw, command);
    return true, { changed = true };
end

-- Drop an owner's key. Returns true when one was actually held.
function M.release(owner)
    if type(owner) ~= 'string' then return false; end
    local rec = _byOwner[owner];
    if rec == nil then return false; end
    _byOwner[owner] = nil;
    if _byKey[rec.key] == owner then _byKey[rec.key] = nil; end
    _told[owner .. '\031' .. rec.key] = nil;
    M.io.unbind(rec.raw or rec.key);
    return true;
end

-- Drop every owner whose id starts with `prefix` ('mode:', 'jobhelper:').
-- Returns how many were dropped. This is what a job change calls.
function M.releaseGroup(prefix)
    if type(prefix) ~= 'string' or prefix == '' then return 0; end
    local doomed = {};
    for owner in pairs(_byOwner) do
        if owner:sub(1, #prefix) == prefix then doomed[#doomed + 1] = owner; end
    end
    table.sort(doomed);                       -- explicit order, never pairs()
    local n = 0;
    for _, owner in ipairs(doomed) do
        if M.release(owner) then n = n + 1; end
    end
    return n;
end

-- THE per-job door: "here is this group, entire, as it should be right now".
--
-- entries = { { owner = <id>, key = <string>, command = <string>, label = <s> }, .. }
--
-- Releases every owner in the group that the list does not mention, registers
-- or moves the rest, and leaves an unchanged bind completely untouched (no
-- /unbind + /bind churn). Returns { bound, released, unchanged, refused = { .. } }.
function M.syncGroup(prefix, entries)
    local out = { bound = 0, released = 0, unchanged = 0, refused = {} };
    if type(prefix) ~= 'string' or prefix == '' then return out; end
    entries = (type(entries) == 'table') and entries or {};

    local want = {};
    for _, e in ipairs(entries) do
        if type(e) == 'table' and type(e.owner) == 'string' then want[e.owner] = true; end
    end

    local doomed = {};
    for owner in pairs(_byOwner) do
        if owner:sub(1, #prefix) == prefix and not want[owner] then doomed[#doomed + 1] = owner; end
    end
    table.sort(doomed);
    for _, owner in ipairs(doomed) do
        if M.release(owner) then out.released = out.released + 1; end
    end

    for _, e in ipairs(entries) do
        if type(e) == 'table' then
            local ok, info = M.register(e.owner, e.key, e.command, e.label);
            if ok and type(info) == 'table' and info.unchanged == true then
                out.unchanged = out.unchanged + 1;
            elseif ok then
                out.bound = out.bound + 1;
            else
                out.refused[#out.refused + 1] = { owner = e.owner, key = e.key,
                                                  taken = (type(info) == 'table') and info.taken or nil };
            end
        end
    end
    return out;
end

-- Every live bind, sorted by key -- /dl binds, and the collision hint a picker
-- shows beside its key field.
function M.list()
    local rows = {};
    for owner, rec in pairs(_byOwner) do
        rows[#rows + 1] = { owner = owner, key = rec.key, raw = rec.raw,
                            command = rec.command, label = nameOf(rec, owner) };
    end
    table.sort(rows, function(a, b)
        if a.key ~= b.key then return a.key < b.key; end
        return a.owner < b.owner;
    end);
    return rows;
end

function M.count()
    local n = 0;
    for _ in pairs(_byOwner) do n = n + 1; end
    return n;
end

-- Drop everything WITHOUT unbinding (test reset / addon unload, where the keys
-- are released by their own path).
function M.forget()
    _byOwner, _byKey, _told = {}, {}, {};
end

-- Release everything, keys included (addon unload).
function M.releaseAll()
    local owners = {};
    for owner in pairs(_byOwner) do owners[#owners + 1] = owner; end
    table.sort(owners);
    for _, owner in ipairs(owners) do M.release(owner); end
end

-- ---------------------------------------------------------------------------
-- /dl binds -- the answer to "what has my keyboard got on it?"
-- ---------------------------------------------------------------------------

function M.report()
    local rows = M.list();
    if #rows == 0 then
        M.say('no keys are bound by dlac right now.');
        return rows;
    end
    pcall(function()
        local cf = require('dlac\\chatfmt');
        local line = (type(cf) == 'table' and type(cf.msg) == 'function') and cf.msg
                     or function(s) print('[dlac] ' .. s); end;
        line(('dlac holds %d key%s:'):format(#rows, (#rows == 1) and '' or 's'));
        for _, r in ipairs(rows) do
            line(('  %-10s %s  ->  %s'):format(r.raw or r.key, r.label, r.command));
        end
    end);
    return rows;
end

pcall(function()
    ashita.events.register('command', 'dlac-keybinds', function(e)
        local args = e.command:args();
        if #args < 2 or args[1]:lower() ~= '/dl' then return; end
        local sub = args[2]:lower();
        if sub ~= 'binds' and sub ~= 'bind' then return; end
        e.blocked = true;
        pcall(M.report);
    end);
end);

return M;
