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

    SEVERAL PINS PER SLOT (2026-08-03): a slot holds a LIST of pins, so Optical
    Hat can sit on TP_Default while Walahra Turban sits on Movement. The file
    grows a second shape for those slots and keeps the old one for the rest:

        return { ["Head"] = { { item = "Optical Hat",    scope = { "Default|mode=TP_Default" } },
                              { item = "Walahra Turban", scope = { "Default|moving=true" } } } }

    A one-pin slot is written EXACTLY as it always was -- same bytes, same
    reader path -- so nothing about the single-pin case changes, on disk or in
    an older engine copy. Only a slot that actually carries two pins takes the
    list form, and dispatch.pinOverlayFor reads both (it picks the entry whose
    trigger matched LAST in the dispatch's own hit order, All ranking lowest).

    'All' is exclusive on the way in: pinning All replaces every pin on that
    slot (Henrik's rule). Pinning a trigger replaces only the pins that already
    claimed one of the SAME triggers -- one item per trigger per slot -- so an
    All pin left underneath keeps acting as the fallback for every dispatch its
    scoped siblings do not cover.
]]--

local M = {};

-- slot label -> LIST of { item = <name>, scope = 'All' | { <scope key>, ... } }
M.pins = {};

local _loadedFor = nil;   -- the <char>\dlac\ dir this table was cleared for

-- <char>\dlac\ dir: the one addon-side copy (lib\statefile). nil pre-login.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir
    or function() return nil; end;

local function pinStatePath()
    local dir = charDir();
    return dir and (dir .. 'pinstate.lua') or nil;
end

-- THE shape reader. A slot's value may be any of the four shapes this contract
-- has ever produced -- a bare name, one { item, scope } entry, a LIST of those,
-- or a list of bare names -- and every caller here goes through this function so
-- none of them has to know which. Always returns an array (never nil), and never
-- the caller's own table when it had to build one.
function M.entriesOf(v)
    if type(v) == 'string' then return { { item = v, scope = 'All' } }; end
    if type(v) ~= 'table' then return {}; end
    if type(v.item) == 'string' then return { v }; end     -- the single-pin shape
    local out = {};
    for _, e in ipairs(v) do
        if type(e) == 'string' then out[#out + 1] = { item = e, scope = 'All' };
        elseif type(e) == 'table' and type(e.item) == 'string' then out[#out + 1] = e; end
    end
    return out;
end

-- Same, minus the entries the engine would refuse anyway (no name / an empty
-- one). What actually gets written and counted.
local function liveEntries(v)
    local out = {};
    for _, e in ipairs(M.entriesOf(v)) do
        if type(e.item) == 'string' and e.item ~= '' then out[#out + 1] = e; end
    end
    return out;
end

local function entryText(e)
    local scope;
    if type(e.scope) == 'table' then
        local parts = {};
        for _, lbl in ipairs(e.scope) do parts[#parts + 1] = string.format('%q', tostring(lbl)); end
        scope = '{ ' .. table.concat(parts, ', ') .. ' }';
    else
        scope = '"All"';
    end
    return string.format('{ item = %q, scope = %s }', tostring(e.item), scope);
end

-- Serialize the pin table to the engine's file format. Pure (takes the table,
-- returns text) so the tests can check the format without a character or disk.
-- Slots are emitted in sorted order: a stable file means dispatch's raw-text
-- compare skips the re-parse when nothing actually changed.
--
-- A slot with ONE pin is written in the original single-entry shape, byte for
-- byte -- so the common case produces exactly the file it always did and an
-- older engine copy reads it unchanged. Only a slot carrying two or more pins
-- takes the list shape.
function M.serialize(pins)
    local slots, lists = {}, {};
    for slot, p in pairs(pins or {}) do
        local es = liveEntries(p);
        if #es > 0 then
            slots[#slots + 1] = slot;
            lists[slot] = es;
        end
    end
    table.sort(slots);
    if #slots == 0 then return 'return { }\n'; end
    local out = { 'return {\n' };
    for _, slot in ipairs(slots) do
        local es = lists[slot];
        if #es == 1 then
            out[#out + 1] = string.format('  [%q] = %s,\n', tostring(slot), entryText(es[1]));
        else
            local parts = {};
            for _, e in ipairs(es) do parts[#parts + 1] = entryText(e); end
            out[#out + 1] = string.format('  [%q] = { %s },\n',
                tostring(slot), table.concat(parts, ', '));
        end
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

-- Does this entry claim any of the scope keys in `keys` (a set)? An All entry
-- claims none of them: it is the fallback, not a competitor for a trigger.
local function claimsAny(e, keys)
    if type(e.scope) ~= 'table' then return false; end
    for _, k in ipairs(e.scope) do
        if keys[tostring(k)] then return true; end
    end
    return false;
end

-- scope: 'All' (default) or a list of scope keys (dispatch.pinScopeKey).
--
-- All REPLACES the slot whole (Henrik's rule: "if ALL is selected, just
-- overwrite all of them and only have all"). A scoped pin replaces only the
-- pins already holding one of the same triggers -- one item per trigger per
-- slot -- and leaves the others, which is the whole point: Optical Hat on
-- TP_Default and Walahra Turban on Movement, both live at once.
function M.setPin(slot, item, scope)
    if type(slot) ~= 'string' or type(item) ~= 'string' or item == '' then return false; end
    M.loadPinState();
    if type(scope) == 'table' and #scope == 0 then scope = 'All'; end
    if scope == nil or type(scope) ~= 'table' then
        M.pins[slot] = { { item = item, scope = 'All' } };
        save();
        return true;
    end
    local keys = {};
    for _, k in ipairs(scope) do keys[tostring(k)] = true; end
    local kept = {};
    for _, e in ipairs(M.entriesOf(M.pins[slot])) do
        if not claimsAny(e, keys) then kept[#kept + 1] = e; end
    end
    kept[#kept + 1] = { item = item, scope = scope };
    M.pins[slot] = kept;
    save();
    return true;
end

-- Every pin on the slot.
function M.clearPin(slot)
    if type(slot) ~= 'string' then return false; end
    M.loadPinState();
    if M.pins[slot] == nil then return false; end
    M.pins[slot] = nil;
    save();
    return true;
end

-- ONE pin on the slot, by its index in pinsOf(slot) -- the "clear this trigger's
-- mapping, keep the rest" half. The slot goes away entirely when its last pin
-- does, so an empty list never reaches the file (or pinStateOn, which reads a
-- non-empty table as "armed").
function M.clearPinAt(slot, idx)
    if type(slot) ~= 'string' then return false; end
    M.loadPinState();
    local list = M.entriesOf(M.pins[slot]);
    idx = tonumber(idx);
    if idx == nil or list[idx] == nil then return false; end
    table.remove(list, idx);
    M.pins[slot] = (#list > 0) and list or nil;
    save();
    return true;
end

function M.clearAll()
    M.loadPinState();
    M.pins = {};
    save();
    return true;
end

-- The slot's pins, in the order they were set (always an array, possibly empty).
function M.pinsOf(slot)
    M.loadPinState();
    return M.entriesOf(M.pins[slot]);
end

-- The FIRST pin on the slot. Kept for callers that only ever want "is there
-- something here and what is it" -- pinsOf is the one that sees them all.
function M.pinOf(slot)
    return M.pinsOf(slot)[1];
end

function M.isPinned(slot)
    return M.pinsOf(slot)[1] ~= nil;
end

-- Does an ALL pin hold this slot? The difference the grid paints: an All pin is
-- worn on every dispatch, a scoped one only when its trigger fires.
function M.hasAllPin(slot)
    for _, e in ipairs(M.pinsOf(slot)) do
        if type(e.scope) ~= 'table' then return true; end
    end
    return false;
end

-- Total pins across every slot (two pins on one Head count as two): what the
-- "Remove all N pins" row and the Priority list's pin count report.
function M.count()
    M.loadPinState();
    local n = 0;
    for _, v in pairs(M.pins) do n = n + #M.entriesOf(v); end
    return n;
end

-- Slots holding at least one pin.
function M.slotCount()
    M.loadPinState();
    local n = 0;
    for _, v in pairs(M.pins) do
        if M.entriesOf(v)[1] ~= nil then n = n + 1; end
    end
    return n;
end

-- A short human label for ONE pin's scope: "All" or "Fast Cast +1".
function M.entryScopeLabel(e)
    if type(e) ~= 'table' or type(e.scope) ~= 'table' then return 'All'; end
    local n = #e.scope;
    if n == 0 then return 'All'; end
    if n == 1 then return tostring(e.scope[1]); end
    return string.format('%s +%d', tostring(e.scope[1]), n - 1);
end

-- ... and for the SLOT: the one pin's label, or how many are stacked on it.
function M.scopeLabel(slot)
    local list = M.pinsOf(slot);
    if list[1] == nil then return nil; end
    if #list == 1 then return M.entryScopeLabel(list[1]); end
    return string.format('%d pins', #list);
end

return M;
