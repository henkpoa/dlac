--[[
    dlac/feature/pinwatch.lua

    PINNED slots -- "equip item, lock slot so nothing removes equipped item"
    (Henrik, 07-15). The addon-state half of the v44 pin overlay: this module owns
    the pin table and WRITES <char>\dlac\pinstate.lua; the dispatch ENGINE reads
    that file and wears the pinned names at top priority on every dispatch
    (dispatch.pinOverlay). Exactly the craftwatch/craftstate contract -- no
    commands, no locks, no fighting the engine.

    Why an overlay and not /dl lock: a lock only makes the engine ignore the slot,
    so anything else that strips the piece wins -- and the lock state leaks when a
    session ends abnormally (LAC forgets /lac disable on reload). The engine
    recomputes a pin from this file every dispatch: nothing to restore, nothing to
    leak, and unpinning silently returns the slot to the normal set.

    Pins are SESSION-ONLY. loadPinState clears the file on load, the way
    craftwatch refuses to restore `enabled` -- no gear glued on at login from a
    pin you set last Tuesday. The clear must reach DISK, not just this table: the
    engine reads the file from LAC's own Lua state on its own schedule, so a stale
    file would dress you at login with nothing in the addon aware of it.

    File format (read by dispatch.ensurePinState):
        return { ["Ring1"] = { item = "Rajas Ring", scope = "All" },
                 ["Head"]  = { item = "Uk'uxkaj Cap", scope = { "Fast Cast" } } }
]]--

local M = {};

-- slot label -> { item = <name>, scope = 'All' | { <trigger label>, ... } }
M.pins = {};

local _loadedFor = nil;   -- the <char>\dlac\ dir this table was cleared for

local function charDir()
    local dir = nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name, id = party:GetMemberName(0), party:GetMemberServerId(0);
        if name == nil or name == '' or id == nil then return; end
        dir = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\dlac\\',
            AshitaCore:GetInstallPath(), name, id);
    end);
    return dir;
end

local function pinStatePath()
    local dir = charDir();
    return dir and (dir .. 'pinstate.lua') or nil;
end

-- Serialize the pin table to the engine's file format. Pure (takes the table,
-- returns text) so the tests can check the format without a character or disk.
-- Slots are emitted in sorted order: a stable file means dispatch's raw-text
-- compare skips the re-parse when nothing actually changed.
function M.serialize(pins)
    local slots = {};
    for slot, p in pairs(pins or {}) do
        if type(p) == 'table' and type(p.item) == 'string' and p.item ~= '' then
            slots[#slots + 1] = slot;
        end
    end
    table.sort(slots);
    if #slots == 0 then return 'return { }\n'; end
    local out = { 'return {\n' };
    for _, slot in ipairs(slots) do
        local p = pins[slot];
        local scope;
        if type(p.scope) == 'table' then
            local parts = {};
            for _, lbl in ipairs(p.scope) do parts[#parts + 1] = string.format('%q', tostring(lbl)); end
            scope = '{ ' .. table.concat(parts, ', ') .. ' }';
        else
            scope = '"All"';
        end
        out[#out + 1] = string.format('  [%q] = { item = %q, scope = %s },\n',
            tostring(slot), tostring(p.item), scope);
    end
    out[#out + 1] = '}\n';
    return table.concat(out);
end

local function save()
    pcall(function()
        local p = pinStatePath();
        if p == nil then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(M.serialize(M.pins));
        f:close();
    end);
end
M._save = save;   -- test seam

-- Load = CLEAR. Pins are session-only, and the clear has to hit disk before the
-- engine's next read (see the header).
--
-- Keyed on the CHARACTER DIR, not a one-shot boolean: an Ashita addon survives a
-- logout, so with a plain `if _loaded then return` the next character to log in
-- would keep this table AND never get their own pinstate.lua cleared -- last
-- session's pins would force gear on them at login, which is the exact thing
-- session-only pins exist to prevent. Re-keying also stops character A's pins
-- from being saved into character B's file on the next mutation.
function M.loadPinState()
    local dir = charDir();
    if dir == nil then return; end         -- pre-login: retry next call
    if _loadedFor == dir then return; end
    _loadedFor = dir;
    M.pins = {};
    save();
end

-- --------------------------------------------------------------------------
-- Mutators. Every one re-writes the whole file; the engine picks the change up
-- within one dispatch tick (its reader is throttled to 1 check/sec).
-- --------------------------------------------------------------------------

-- scope: 'All' (default) or a list of trigger labels.
function M.setPin(slot, item, scope)
    if type(slot) ~= 'string' or type(item) ~= 'string' or item == '' then return false; end
    M.loadPinState();
    if type(scope) == 'table' and #scope == 0 then scope = 'All'; end
    M.pins[slot] = { item = item, scope = scope or 'All' };
    save();
    return true;
end

function M.clearPin(slot)
    if type(slot) ~= 'string' then return false; end
    M.loadPinState();
    if M.pins[slot] == nil then return false; end
    M.pins[slot] = nil;
    save();
    return true;
end

function M.clearAll()
    M.loadPinState();
    M.pins = {};
    save();
    return true;
end

function M.pinOf(slot)
    M.loadPinState();
    return M.pins[slot];
end

function M.isPinned(slot)
    M.loadPinState();
    return M.pins[slot] ~= nil;
end

function M.count()
    M.loadPinState();
    local n = 0;
    for _ in pairs(M.pins) do n = n + 1; end
    return n;
end

-- A short human label for the pin's scope: "All" or "Fast Cast +1".
function M.scopeLabel(slot)
    local p = M.pinOf(slot);
    if p == nil then return nil; end
    if type(p.scope) ~= 'table' then return 'All'; end
    local n = #p.scope;
    if n == 0 then return 'All'; end
    if n == 1 then return tostring(p.scope[1]); end
    return string.format('%s +%d', tostring(p.scope[1]), n - 1);
end

return M;
