--[[
    dlac/modeslibrary.lua -- the pure Mode library core (ADR 0019; CONTEXT.md term
    "Mode library"; blueprintsmodel.lua is the structural precedent, deliberately
    mirrored function-for-function).

    A Mode library entry is a job-independent saved Mode kept in a per-character file
    OUTSIDE Profiles (<char>\dlac\modes.lua), addon-state only -- the engine never
    reads it.

      entry = { name = 'Weapon',              -- the Mode's name; IS its identity
                kind = 'cycle' | 'toggle',
                values = { 'Melee', ... },    -- cycles only, order = cycle order
                bind = '^F3' }                -- optional, raw Ashita /bind key string

    WHY THIS EXISTS: Modes live PER JOB ENTRY, and the Triggers tab only ever sees the
    current job's trigger file. Reusing one `DT` toggle across ten jobs meant retyping
    it ten times, or copy-pasting text with a job change between every hop. Same pain
    Blueprints solved for Triggers, same shape of answer.

    THE ONE STRUCTURAL DIFFERENCE FROM BLUEPRINTS, and the reason ADR 0019 exists: a
    `Modes` section is a MAP KEYED BY NAME, not an array. Blueprints can double-stamp
    and merely warn -- two identical rules in a handler list are harmless. Stamping a
    Mode whose name already exists is a genuine OVERWRITE. For a cycle that can strand
    every `Weapon:Caster`-style reference in the job's triggers AND in its set-entry
    mode gates, so stamping offers:

      * APPEND (the default, non-destructive) -- merge the incoming values onto the
        existing list, dedupe case-insensitively, keep the existing bind. No value ever
        disappears, so no reference can break.
      * OVERWRITE (opt-in, destructive) -- replace the values wholesale. The caller
        then strips references to the values that NO LONGER EXIST, and must show a
        pre-commit list first.

    PLAN vs APPLY: every mutation here is available as a `plan` (pure, describes what
    WOULD happen, including the exact list of dead values) and an `apply` (returns a
    NEW map, never mutating the caller's). The UI renders the plan as the pre-commit
    list and then applies the identical call -- so what the player is shown and what
    happens are computed by the same code, not by two descriptions that can drift.

    This module is PURE: no imgui, no Ashita, no file IO, no dispatch. The UI owns the
    file ladder and the ref-stripping (modeCondRefs / modeSetRefs both live over there);
    tests ML* pin everything below headlessly.
]]--

local M = {};

M.VERSION = 1;   -- library file format version (modes v1)

-- Mode names the ENGINE owns as implicit session state -- it writes these flags with
-- no `Modes` definition behind them (maxmp: dispatch's MP-band ladder; craft and
-- craftgoal: the crafting overlay's skill and NQ/HQ goal). A library entry taking one
-- of these names would collide with engine-owned state, so they are refused at capture
-- and at import rather than discovered in the field.
M.RESERVED = { maxmp = true, craft = true, craftgoal = true };

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''));
end

local function ci(a, b) return string.lower(tostring(a)) == string.lower(tostring(b)); end

local function deepcopy(v)
    if type(v) ~= 'table' then return v; end
    local out = {};
    for k, x in pairs(v) do out[k] = deepcopy(x); end
    return out;
end
M.deepcopy = deepcopy;

function M.isReserved(name)
    return M.RESERVED[string.lower(trim(name))] == true;
end

-- ---------------------------------------------------------------------------
-- Entry construction / sanitize.
--
-- The kind is DERIVED from the values, never trusted from the file: `values` present
-- and non-empty = cycle, otherwise toggle. That is exactly how the rest of dlac tests
-- it (`def.values ~= nil` is the sole cycle test in triggersui and dispatch), so a
-- hand-edited library claiming kind='cycle' with no values cannot produce a definition
-- the engine would read differently than this module does.
-- ---------------------------------------------------------------------------

-- Dedupe a value list case-insensitively, preserving first-seen order and spelling.
-- Blank entries are dropped. Returns nil when nothing survives (i.e. a toggle).
local function cleanValues(src)
    if type(src) ~= 'table' then return nil; end
    local out, seen = {}, {};
    for _, v in ipairs(src) do
        if type(v) == 'string' then
            local s = trim(v);
            local k = string.lower(s);
            if s ~= '' and not seen[k] then
                seen[k] = true;
                out[#out + 1] = s;
            end
        end
    end
    if #out == 0 then return nil; end
    return out;
end
M.cleanValues = cleanValues;

-- Build an entry. Returns entry | nil, err (err is player-facing).
-- A cycle needs at least TWO values -- one value is not a cycle, it is a constant, and
-- the mode builder enforces the same rule (`#modeUI.values >= 2`).
function M.makeEntry(name, values, bind)
    local nm = trim(name);
    if nm == '' then return nil, 'A mode needs a name.'; end
    if M.isReserved(nm) then
        return nil, string.format('"%s" is reserved -- dlac sets that mode itself.', nm);
    end
    local vals = cleanValues(values);
    if vals ~= nil and #vals < 2 then
        return nil, 'A cycle needs at least two values.';
    end
    local e = { name = nm, kind = (vals ~= nil) and 'cycle' or 'toggle' };
    if vals ~= nil then e.values = vals; end
    local b = trim(bind);
    if b ~= '' then e.bind = b; end
    return e;
end

-- A job's `Modes` map entry ({ values = {...}, bind = ... } | {}) -> a library entry.
-- Returns entry | nil, err.
function M.captureOne(name, def)
    if type(def) ~= 'table' then def = {}; end
    return M.makeEntry(name, def.values, def.bind);
end

-- Capture EVERY definition in a job's Modes map. Returns a list sorted by name
-- (deterministic -- hard rule 8) plus a list of {name, err} for the refused ones, so
-- the caller can say WHY a reserved name was skipped instead of silently dropping it.
function M.captureAll(modesMap)
    local out, refused = {}, {};
    if type(modesMap) ~= 'table' then return out, refused; end
    local names = {};
    for nm in pairs(modesMap) do
        if type(nm) == 'string' then names[#names + 1] = nm; end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b); end);
    for _, nm in ipairs(names) do
        local e, err = M.captureOne(nm, modesMap[nm]);
        if e ~= nil then out[#out + 1] = e;
        else refused[#refused + 1] = { name = nm, err = err }; end
    end
    return out, refused;
end

-- An entry -> the `Modes` map definition the trigger file stores. A bare toggle is
-- `{}` and NOT nil: an empty definition is load-bearing (it is what keeps a plain
-- UI-created toggle in the Modes list across a commit round-trip -- dispatch v72,
-- tests TM20-22). Dropping it un-lists the mode.
function M.toDef(entry)
    if type(entry) ~= 'table' then return nil; end
    local def = {};
    if type(entry.values) == 'table' and #entry.values > 0 then
        def.values = deepcopy(entry.values);
    end
    if type(entry.bind) == 'string' and trim(entry.bind) ~= '' then def.bind = entry.bind; end
    return def;
end

-- ---------------------------------------------------------------------------
-- Library CRUD (a plain array; order is display order).
-- ---------------------------------------------------------------------------

function M.fromRaw(raw)
    local out = {};
    if type(raw) ~= 'table' then return out; end
    local list = (type(raw.modes) == 'table') and raw.modes or raw;
    for _, e in ipairs(list) do
        if type(e) == 'table' then
            local entry = M.makeEntry(e.name, e.values, e.bind);
            if entry ~= nil then out[#out + 1] = entry; end
        end
    end
    return out;
end

function M.findEntryCI(list, name)
    if type(list) ~= 'table' then return nil; end
    for i, e in ipairs(list) do
        if type(e) == 'table' and type(e.name) == 'string' and ci(e.name, name) then return i; end
    end
    return nil;
end

-- Add (or replace by name). Returns ok, err. `replace` guards the collision: without
-- it an existing name is refused, because the library is keyed by name too.
function M.add(list, entry, replace)
    if type(list) ~= 'table' then return false, 'no library'; end
    if type(entry) ~= 'table' or type(entry.name) ~= 'string' then return false, 'no entry'; end
    local idx = M.findEntryCI(list, entry.name);
    if idx ~= nil then
        if replace ~= true then
            return false, string.format('"%s" is already in your library.', entry.name);
        end
        list[idx] = deepcopy(entry);
        return true;
    end
    list[#list + 1] = deepcopy(entry);
    return true;
end

function M.rename(list, i, name)
    local e = type(list) == 'table' and list[i] or nil;
    if e == nil then return false, 'no such mode'; end
    local nm = trim(name);
    if nm == '' then return false, 'Name cannot be empty.'; end
    if M.isReserved(nm) then
        return false, string.format('"%s" is reserved -- dlac sets that mode itself.', nm);
    end
    local other = M.findEntryCI(list, nm);
    if other ~= nil and other ~= i then
        return false, string.format('"%s" is already in your library.', nm);
    end
    e.name = nm;
    return true;
end

function M.remove(list, i)
    if type(list) ~= 'table' or list[i] == nil then return false, 'no such mode'; end
    table.remove(list, i);
    return true;
end

-- ---------------------------------------------------------------------------
-- THE STAMP -- plan and apply, computed by the same code.
--
-- plan(entry, modesMap, how) -> {
--     action  = 'create' | 'append' | 'overwrite' | 'rebind',
--     name    = the name as it will be stored (the EXISTING spelling wins on a
--               collision, so stamping 'weapon' onto 'Weapon' does not rename it),
--     kind    = 'cycle' | 'toggle',
--     before  = the existing value list (cycles),
--     after   = the resulting value list,
--     dead    = values present BEFORE and absent AFTER  <- what the caller strips
--     added   = values the stamp introduces (display only)
--     bindFrom / bindTo, bindChanged,
--     collides = was there an existing definition at all,
-- }
--
-- `how` is 'append' (default) or 'overwrite', and is IGNORED when there is nothing to
-- collide with or when either side is a toggle -- there are no values to merge, so
-- both modes do the same thing and `dead` is empty either way.
-- ---------------------------------------------------------------------------
function M.stampPlan(entry, modesMap, how)
    if type(entry) ~= 'table' or type(entry.name) ~= 'string' then return nil, 'no entry'; end
    how = (how == 'overwrite') and 'overwrite' or 'append';
    modesMap = (type(modesMap) == 'table') and modesMap or {};

    -- Find the existing definition case-insensitively and KEEP ITS SPELLING: the
    -- Modes map is keyed by name, so writing a differently-cased key would leave two
    -- entries for one mode and every existing reference pointing at the old one.
    local existingKey, existingDef = nil, nil;
    for k, v in pairs(modesMap) do
        if type(k) == 'string' and ci(k, entry.name) then existingKey, existingDef = k, v; break; end
    end

    local incoming = cleanValues(entry.values);
    local current  = (type(existingDef) == 'table') and cleanValues(existingDef.values) or nil;
    local plan = {
        name = existingKey or trim(entry.name),
        collides = (existingDef ~= nil),
        before = current and deepcopy(current) or nil,
        bindFrom = (type(existingDef) == 'table') and existingDef.bind or nil,
        dead = {}, added = {},
    };

    local after;
    if existingDef == nil then
        plan.action = 'create';
        after = incoming;
    elseif how == 'overwrite' then
        -- The destructive branch, and the only one that can produce dead values. Note
        -- `incoming` may be nil (a TOGGLE stamped over a CYCLE): that demotes the mode
        -- and every one of its values dies. The dead set below catches it, so the
        -- pre-commit list names them all -- it is not a special case, but it IS the
        -- most expensive single thing this feature can do.
        plan.action = 'overwrite';
        after = incoming;
    elseif current == nil then
        -- Existing is a toggle. Adopting values deletes nothing, so Append may do it.
        plan.action = 'append';
        after = incoming;
    elseif incoming == nil then
        -- A TOGGLE stamped onto a CYCLE under Append. Append's whole guarantee is that
        -- nothing is deleted, so the cycle KEEPS its values -- demoting it to a toggle
        -- here would silently kill every `Name:Value` reference, which is precisely
        -- what the player chose Append to avoid. Use Overwrite to demote on purpose.
        plan.action = 'append';
        after = current;
    else
        plan.action = 'append';
        local merged = {};
        for _, v in ipairs(current) do merged[#merged + 1] = v; end
        for _, v in ipairs(incoming) do merged[#merged + 1] = v; end
        after = cleanValues(merged);   -- dedupes, first spelling wins
    end
    plan.after = after and deepcopy(after) or nil;

    -- The dead set: present before, absent after. This is what the caller feeds to
    -- modeCondRefs / modeSetRefs as '<Name>:<Value>' to build the pre-commit list.
    if current ~= nil then
        local keep = {};
        for _, v in ipairs(after or {}) do keep[string.lower(v)] = true; end
        for _, v in ipairs(current) do
            if not keep[string.lower(v)] then plan.dead[#plan.dead + 1] = v; end
        end
    end
    if after ~= nil then
        local had = {};
        for _, v in ipairs(current or {}) do had[string.lower(v)] = true; end
        for _, v in ipairs(after) do
            if not had[string.lower(v)] then plan.added[#plan.added + 1] = v; end
        end
    end

    plan.kind = (after ~= nil) and 'cycle' or 'toggle';
    plan.bindTo = (type(entry.bind) == 'string' and trim(entry.bind) ~= '') and entry.bind or nil;
    -- Append is additive on the bind too: it never clobbers a keybind you already set.
    if plan.action == 'append' and plan.bindFrom ~= nil then plan.bindTo = plan.bindFrom; end
    plan.bindChanged = (plan.bindFrom ~= plan.bindTo);
    if plan.action == 'append' and plan.collides
       and #plan.added == 0 and not plan.bindChanged then
        plan.action = 'rebind';   -- nothing whatsoever would change; the UI says so
    end
    return plan;
end

-- Apply a stamp: returns a NEW Modes map (the caller's is never mutated, so a plan can
-- be previewed and abandoned). Returns map, plan.
function M.applyStamp(entry, modesMap, how)
    local plan = M.stampPlan(entry, modesMap, how);
    if plan == nil then return modesMap, nil; end
    local out = deepcopy(type(modesMap) == 'table' and modesMap or {});
    -- Drop any differently-cased duplicate key, then write the canonical one.
    for k in pairs(out) do
        if type(k) == 'string' and ci(k, plan.name) and k ~= plan.name then out[k] = nil; end
    end
    local def = {};
    if plan.after ~= nil then def.values = deepcopy(plan.after); end
    if plan.bindTo ~= nil then def.bind = plan.bindTo; end
    out[plan.name] = def;    -- `{}` for a bare toggle: an empty def is load-bearing
    return out, plan;
end

-- The '<Name>:<Value>' targets the caller strips for a plan. Exactly the spelling
-- modeCondRefs / modeSetRefs expect, and EMPTY unless values actually disappeared --
-- so an Append stamp can never trigger a strip.
function M.deadTargets(plan)
    local out = {};
    if type(plan) ~= 'table' then return out; end
    for _, v in ipairs(plan.dead or {}) do
        out[#out + 1] = tostring(plan.name) .. ':' .. tostring(v);
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- Serialize / parse. Deterministic (stable diffs); parse is SANDBOXED (the
-- blueprintsmodel / groupimport pattern: empty environment, text-only load), so a torn
-- or hostile file yields an error, never a crash or code execution.
-- ---------------------------------------------------------------------------
local function luaValue(v) return string.format('%q', tostring(v)); end

function M.serialize(list)
    local L = {
        '-- dlac Mode library -- job-independent saved Modes, per character (ADR 0019).',
        '-- Addon-state only: the engine never reads this file. Written by the dlac GUI',
        '-- (Triggers tab > Mode library); safe to hand-edit, but the GUI rewrites it.',
        'return {',
        '    version = ' .. tostring(M.VERSION) .. ',',
        '    modes = {',
    };
    for _, e in ipairs(type(list) == 'table' and list or {}) do
        if type(e) == 'table' and type(e.name) == 'string' then
            local parts = { 'name = ' .. luaValue(e.name) };
            parts[#parts + 1] = 'kind = ' .. luaValue((type(e.values) == 'table') and 'cycle' or 'toggle');
            if type(e.values) == 'table' and #e.values > 0 then
                local q = {};
                for _, v in ipairs(e.values) do q[#q + 1] = luaValue(v); end
                parts[#parts + 1] = 'values = { ' .. table.concat(q, ', ') .. ' }';
            end
            if type(e.bind) == 'string' and trim(e.bind) ~= '' then
                parts[#parts + 1] = 'bind = ' .. luaValue(e.bind);
            end
            L[#L + 1] = '        { ' .. table.concat(parts, ', ') .. ' },';
        end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '};';
    L[#L + 1] = '';
    return table.concat(L, '\n');
end

function M.serializeOne(entry) return M.serialize({ entry }); end

local function compile(code, env)
    if setfenv ~= nil then
        local f, err = (loadstring or load)(code, 'dlac-modes');
        if f == nil then return nil, err; end
        setfenv(f, env);
        return f;
    end
    return load(code, 'dlac-modes', 't', env);
end

function M.parse(text)
    if type(text) ~= 'string' or trim(text) == '' then return nil, 'empty input'; end
    local chunk, cerr = compile(text, {});
    if chunk == nil then return nil, 'does not parse: ' .. tostring(cerr); end
    local ok, ret = pcall(chunk);
    if not ok then return nil, 'errored on load: ' .. tostring(ret); end
    if type(ret) ~= 'table' then return nil, 'did not return a table'; end
    return M.fromRaw(ret), nil;
end

-- ---------------------------------------------------------------------------
-- Import (the paste sibling of groupimport.classify / .apply): parse, classify against
-- the existing library by NAME case-insensitively, then apply under an explicit
-- overwrite confirmation. Importing into the LIBRARY is never destructive to a job --
-- nothing is stamped until the player stamps it.
-- ---------------------------------------------------------------------------
function M.classifyImport(entries, existing)
    local created, collided = {}, {};
    if type(entries) == 'table' then
        for _, e in ipairs(entries) do
            if type(e) == 'table' and type(e.name) == 'string' then
                if M.findEntryCI(existing, e.name) ~= nil then collided[#collided + 1] = e.name;
                else created[#created + 1] = e.name; end
            end
        end
    end
    table.sort(created);
    table.sort(collided);
    return created, collided;
end

function M.previewImport(text, existing)
    local list, err = M.parse(text);
    if list == nil then return nil, err; end
    local created, collided = M.classifyImport(list, existing);
    return { entries = list, created = created, collided = collided }, nil;
end

function M.applyImport(existing, entries, overwrite)
    local created, updated, refused = 0, 0, 0;
    if type(existing) ~= 'table' or type(entries) ~= 'table' then
        return { created = 0, updated = 0, refused = 0 };
    end
    for _, e in ipairs(entries) do
        if type(e) == 'table' then
            local entry = M.makeEntry(e.name, e.values, e.bind);
            if entry == nil then
                refused = refused + 1;
            else
                local idx = M.findEntryCI(existing, entry.name);
                if idx ~= nil then
                    if overwrite == true then
                        -- keep the stored name spelling, adopt values + bind
                        entry.name = existing[idx].name;
                        existing[idx] = entry;
                        updated = updated + 1;
                    else
                        refused = refused + 1;
                    end
                else
                    existing[#existing + 1] = entry;
                    created = created + 1;
                end
            end
        end
    end
    return { created = created, updated = updated, refused = refused };
end

return M;
