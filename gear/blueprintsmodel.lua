--[[
    dlac/blueprintsmodel.lua -- the pure Blueprints core (issue #65, slice 1; PRD #64; CONTEXT.md
    term "Blueprint", ADR 0009 the structural precedent).

    A Blueprint is a job-independent saved Trigger kept in a per-character library file OUTSIDE
    Profiles (<char>\dlac\blueprints.lua), addon-state only -- the engine never reads it.

      entry = { name = 'Sleep protection',   -- editable display name (default derived from the rule)
                handler = 'Midcast',          -- which Handler the rule belongs to
                rule = { when = {...}, whenAny = {...}?, set = 'X' | {...} | equip = {...}, priority = n? } }

    The rule is the ordinary trigger edit-model rule VERBATIM (lowercased condition keys, a `set`
    string or ordered list OR an inline `equip` payload, an optional numeric priority) -- exactly
    what triggermodel.fromRaw produces and dispatch.serializeTriggers emits, so a stamped rule is an
    ordinary Trigger forever after. Detached both ways: this module deep-copies on stamp and on
    save, so editing a Blueprint never retro-edits stamped Triggers, and vice versa.

    This is the pure, ImGui-free / Ashita-free / file-IO-free core the headless suite pins (tests
    TGB*): library CRUD, default-name derivation, the stamp transform (entry + a job's trigger data
    table in -> new data table out), priority carry-over, identical-rule detection, and a
    deterministic serialize/parse round-trip. triggersui draws the section + the Save-as-Blueprint
    button and owns the file IO (the backup->temp->validate->swap ladder). The one dispatch touch --
    the handler-key canonicalizer / the pretty-key map -- is INJECTED, so this module never drags
    the engine in and never gets seeded into LAC.

    The rule emitter here is a deliberate, self-contained mirror of dispatch.serializeTriggers' per-
    rule form (issue #65 forbids any engine/dispatch change) -- same sorted-condition, list-literal,
    sorted-equip output, so the library file, the identical-rule canonical form, and (slice 2) the
    shareable text all render a rule ONE way.
]]--

local M = {};

M.VERSION = 1;   -- library file format version (blueprints v1)

-- Canonical LuaAshitacast handlers a Blueprint's rule may target (dispatch's EVENTS).
local HANDLERS = { 'Default', 'Precast', 'Midcast', 'Ability', 'Item', 'Weaponskill', 'Preshot', 'Midshot', 'PetAction' };
local HANDLER_SET = {};
for _, h in ipairs(HANDLERS) do HANDLER_SET[string.lower(h)] = h; end
M.HANDLERS = HANDLERS;

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''));
end

-- Deep copy a plain data value (tables only; no metatables, no cycles -- rule tables are
-- acyclic data). The detachment guarantee lives HERE: stamp and save copy so the library
-- entry and the stamped/edited Trigger never share a table.
local function deepcopy(v)
    if type(v) ~= 'table' then return v; end
    local out = {};
    for k, x in pairs(v) do out[k] = deepcopy(x); end
    return out;
end
M.deepcopy = deepcopy;

-- ---------------------------------------------------------------------------
-- Rule sanitize + the self-contained per-rule emitter (mirrors serializeTriggers).
-- ---------------------------------------------------------------------------

-- Sanitize a raw rule table into the edit-model shape: lowercased condition keys, a `set`
-- string or ordered list, an inline `equip` map, an optional numeric priority. Returns nil
-- when the rule has no conditions or no action (it would be garbage). whenAny entries are
-- single- or multi-key maps, order preserved (an OR list).
local function sanitizeRule(r)
    if type(r) ~= 'table' or type(r.when) ~= 'table' then return nil; end
    local when = {};
    for ck, cv in pairs(r.when) do when[string.lower(tostring(ck))] = cv; end
    local whenAny = nil;
    local rawAny = r.whenAny or r.whenany;
    if type(rawAny) == 'table' then
        for _, e in ipairs(rawAny) do
            if type(e) == 'table' then
                local ne = {};
                for ck, cv in pairs(e) do ne[string.lower(tostring(ck))] = cv; end
                if next(ne) ~= nil then whenAny = whenAny or {}; whenAny[#whenAny + 1] = ne; end
            end
        end
    end
    -- action: a `set` (string or ordered list) OR an inline `equip` payload.
    local sv, equip = nil, nil;
    if type(r.set) == 'table' then
        for _, sn in ipairs(r.set) do
            if type(sn) == 'string' and sn ~= '' then sv = sv or {}; sv[#sv + 1] = sn; end
        end
        if sv ~= nil and #sv == 1 then sv = sv[1]; end
    elseif r.set ~= nil then
        sv = tostring(r.set);
    end
    if sv == nil and type(r.equip) == 'table' then
        equip = {};
        for slot, item in pairs(r.equip) do
            if type(slot) == 'string' and item ~= nil then equip[slot] = tostring(item); end
        end
        if next(equip) == nil then equip = nil; end
    end
    if sv == nil and equip == nil then return nil; end       -- no action -> not a real rule
    local rule = { when = when };
    if whenAny ~= nil then rule.whenAny = whenAny; end
    if sv ~= nil then rule.set = sv; else rule.equip = equip; end
    if tonumber(r.priority) ~= nil then rule.priority = tonumber(r.priority); end
    return rule;
end
M.sanitizeRule = sanitizeRule;

local function luaValue(v)
    if type(v) == 'string' then return string.format('%q', v); end
    return tostring(v);
end

-- A condition value may be a scalar OR a LIST (OR): `mode`/`group` accept { 'A', 'B' }.
local function condLiteral(v)
    if type(v) ~= 'table' then return luaValue(v); end
    local q = {};
    for _, x in ipairs(v) do q[#q + 1] = luaValue(x); end
    return '{ ' .. table.concat(q, ', ') .. ' }';
end

-- The per-rule body ("when = { ... }, whenAny = { ... }, set/equip = ..., priority = n"),
-- byte-identical to dispatch.serializeTriggers' emitter: conditions sorted, list literals,
-- equip slots sorted, priority only when set. `prettyKey` (dispatch.PRETTY_KEY, optional) maps
-- a lowercased key to its display case; without it the raw key is used. This ONE form is the
-- canonical spelling for the file, the identical-rule test, and the shareable text.
function M.emitRule(rule, prettyKey)
    prettyKey = (type(prettyKey) == 'table') and prettyKey or {};
    local conds = {};
    for k, v in pairs(rule.when or {}) do
        local lk = string.lower(tostring(k));
        conds[#conds + 1] = (prettyKey[lk] or tostring(k)) .. ' = ' .. condLiteral(v);
    end
    table.sort(conds);
    local anyStr = '';
    if type(rule.whenAny) == 'table' and #rule.whenAny > 0 then
        local groups = {};
        for _, entry in ipairs(rule.whenAny) do
            local ec = {};
            for k, v in pairs(entry) do
                local lk = string.lower(tostring(k));
                ec[#ec + 1] = (prettyKey[lk] or tostring(k)) .. ' = ' .. condLiteral(v);
            end
            table.sort(ec);
            groups[#groups + 1] = '{ ' .. table.concat(ec, ', ') .. ' }';
        end
        anyStr = ', whenAny = { ' .. table.concat(groups, ', ') .. ' }';
    end
    local action;
    if type(rule.set) == 'table' then
        local q = {};
        for _, sn in ipairs(rule.set) do q[#q + 1] = luaValue(tostring(sn)); end
        action = 'set = { ' .. table.concat(q, ', ') .. ' }';
    elseif rule.set ~= nil then
        action = 'set = ' .. luaValue(tostring(rule.set));
    else
        local slots = {};
        for slot, item in pairs(rule.equip or {}) do
            slots[#slots + 1] = tostring(slot) .. ' = ' .. luaValue(tostring(item));
        end
        table.sort(slots);
        action = 'equip = { ' .. table.concat(slots, ', ') .. ' }';
    end
    local prio = (tonumber(rule.priority) ~= nil) and (', priority = ' .. tostring(rule.priority)) or '';
    return string.format('when = { %s }%s, %s%s', table.concat(conds, ', '), anyStr, action, prio);
end

-- Two rules are IDENTICAL when their canonical emitted form matches -- same conditions
-- (order-insensitive on the & leg), same OR list (order preserved), same action, same
-- priority. Used by the stamp warning (double-stamp caught, not forbidden).
function M.rulesEqual(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return false; end
    return M.emitRule(a) == M.emitRule(b);
end

-- ---------------------------------------------------------------------------
-- Default display name -- a readable summary of the rule's condition (PRD story 5:
-- "Sleep or Lullaby" reads better than raw conditions). The player edits it after.
-- ---------------------------------------------------------------------------

-- One condition -> a short phrase. A flag (v == true) shows its key; a valued condition
-- shows the value (a buff name, a spell name, a skill); a list joins with '/'.
local function condPhrase(k, v)
    local lk = string.lower(tostring(k));
    if v == true then return lk; end
    if type(v) == 'table' then
        local parts = {};
        for _, x in ipairs(v) do parts[#parts + 1] = tostring(x); end
        return table.concat(parts, '/');
    end
    return tostring(v);
end

-- Derive a default name from a rule: the & leg's values joined with ' + ', then the | leg's
-- OR values joined with ' or ' (the sleep rule's whenAny = Sleep/Lullaby -> "Sleep or Lullaby").
function M.defaultName(rule)
    if type(rule) ~= 'table' then return 'New Blueprint'; end
    local andParts = {};
    for k, v in pairs(rule.when or {}) do
        if k ~= 'any' then andParts[#andParts + 1] = condPhrase(k, v); end
    end
    table.sort(andParts);
    local orParts = {};
    for _, e in ipairs(rule.whenAny or {}) do
        local one = {};
        for k, v in pairs(e) do one[#one + 1] = condPhrase(k, v); end
        table.sort(one);
        if #one > 0 then orParts[#orParts + 1] = table.concat(one, ' + '); end
    end
    local segs = {};
    if #andParts > 0 then segs[#segs + 1] = table.concat(andParts, ' + '); end
    if #orParts > 0 then segs[#segs + 1] = table.concat(orParts, ' or '); end
    local name = table.concat(segs, ' + ');
    if trim(name) == '' then name = 'Any'; end
    return name;
end

-- ---------------------------------------------------------------------------
-- Library CRUD (a plain array of entries; order is display order).
-- ---------------------------------------------------------------------------

-- Sanitize a raw library-file table into the model list. Tolerates { version, blueprints = {...} }
-- OR a bare array of entries. Drops entries without a valid handler or a real rule -- the
-- serialize/round-trip contract: what fromRaw keeps is exactly what serialize re-emits.
function M.fromRaw(raw)
    local out = {};
    if type(raw) ~= 'table' then return out; end
    local list = (type(raw.blueprints) == 'table') and raw.blueprints or raw;
    for _, e in ipairs(list) do
        if type(e) == 'table' then
            local handler = HANDLER_SET[string.lower(tostring(e.handler or ''))];
            local rule = sanitizeRule(e.rule);
            if handler ~= nil and rule ~= nil then
                local name = (type(e.name) == 'string' and trim(e.name) ~= '') and trim(e.name)
                             or M.defaultName(rule);
                out[#out + 1] = { name = name, handler = handler, rule = rule };
            end
        end
    end
    return out;
end

-- Build a library entry from a handler + a rule (the Save-as-Blueprint capture). The rule is
-- deep-copied and sanitized so the Blueprint is detached from the live trigger it came from.
-- `name` is optional (defaults to the derived summary). Returns entry | nil, err.
function M.makeEntry(handler, rule, name)
    local h = HANDLER_SET[string.lower(tostring(handler or ''))];
    if h == nil then return nil, 'unknown handler'; end
    local r = sanitizeRule(deepcopy(rule));
    if r == nil then return nil, 'the rule has no conditions or no action'; end
    local nm = (type(name) == 'string' and trim(name) ~= '') and trim(name) or M.defaultName(r);
    return { name = nm, handler = h, rule = r };
end

-- Append a captured rule to the library. Returns ok, err (err is a player-facing reason).
function M.add(list, handler, rule, name)
    if type(list) ~= 'table' then return false, 'no library'; end
    local entry, err = M.makeEntry(handler, rule, name);
    if entry == nil then return false, err; end
    list[#list + 1] = entry;
    return true;
end

-- Rename entry #i (blank name is refused -- a Blueprint always has a display name). ok, err.
function M.rename(list, i, name)
    local e = type(list) == 'table' and list[i] or nil;
    if e == nil then return false, 'no such blueprint'; end
    if trim(name) == '' then return false, 'Name cannot be empty.'; end
    e.name = trim(name);
    return true;
end

-- Delete entry #i. ok, err.
function M.remove(list, i)
    if type(list) ~= 'table' or list[i] == nil then return false, 'no such blueprint'; end
    table.remove(list, i);
    return true;
end

-- ---------------------------------------------------------------------------
-- The stamp transform: entry + a job's trigger data table -> a NEW data table with the
-- rule appended to the entry's Handler section. Pure (non-mutating): deep-copies the whole
-- data and the rule, so the caller's live model is untouched until it adopts the result, and
-- the stamped Trigger shares no table with the library entry (detached). Dangling set / Mode /
-- Group references stamp verbatim -- the existing missing-reference surfacing covers them.
-- ---------------------------------------------------------------------------
function M.stamp(entry, data)
    if type(entry) ~= 'table' or type(entry.rule) ~= 'table' then return data; end
    local handler = HANDLER_SET[string.lower(tostring(entry.handler or ''))];
    if handler == nil then return data; end
    local out = deepcopy(type(data) == 'table' and data or {});
    out[handler] = out[handler] or {};
    out[handler][#out[handler] + 1] = deepcopy(entry.rule);
    return out;
end

-- Does the entry's Handler section in `data` already hold an identical rule? (Warn-but-allow:
-- double-stamping is caught, never forbidden.) Returns true/false.
function M.identicalExists(entry, data)
    if type(entry) ~= 'table' or type(data) ~= 'table' then return false; end
    local handler = HANDLER_SET[string.lower(tostring(entry.handler or ''))];
    if handler == nil then return false; end
    for _, r in ipairs(data[handler] or {}) do
        if M.rulesEqual(r, entry.rule) then return true; end
    end
    return false;
end

-- ---------------------------------------------------------------------------
-- Serialize / parse -- the library file (blueprints v1). Deterministic (stable diffs);
-- parse is SANDBOXED (the profilesets.sandboxSets / groupimport pattern: empty environment,
-- text-only load), so a torn or hostile file yields an error, never a crash or code execution.
-- ---------------------------------------------------------------------------
function M.serialize(list, prettyKey)
    local L = {
        '-- dlac Blueprints -- a per-character library of reusable trigger rules (issue #65).',
        '-- Addon-state only: the LuaAshitacast engine never reads this file. Written by the',
        '-- dlac GUI (Triggers tab > Blueprints); safe to hand-edit, but the GUI rewrites it.',
        'return {',
        '    version = ' .. tostring(M.VERSION) .. ',',
        '    blueprints = {',
    };
    for _, e in ipairs(type(list) == 'table' and list or {}) do
        if type(e) == 'table' and type(e.rule) == 'table' then
            local handler = HANDLER_SET[string.lower(tostring(e.handler or ''))];
            if handler ~= nil then
                L[#L + 1] = string.format('        { name = %s, handler = %s, rule = { %s } },',
                    luaValue(tostring(e.name or M.defaultName(e.rule))),
                    luaValue(handler), M.emitRule(e.rule, prettyKey));
            end
        end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '};';
    L[#L + 1] = '';
    return table.concat(L, '\n');
end

-- Compile `code` under the sandbox env (portable across LuaJIT/5.1 setfenv and 5.2+/5.4 load;
-- 't' mode = text only, never bytecode). groupimport's exact shape.
local function compile(code, env)
    if setfenv ~= nil then
        local f, err = (loadstring or load)(code, 'dlac-blueprints');
        if f == nil then return nil, err; end
        setfenv(f, env);
        return f;
    end
    return load(code, 'dlac-blueprints', 't', env);
end

-- Parse library-file text -> ( list | nil, err ). The env is empty (no os/io/require/globals),
-- so a hostile file errors at eval and is reported, never run.
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
-- Text sharing (issue #66, slice 2). "View text" per Blueprint and section-level
-- "Copy all" both reuse M.serialize: a shareable blob is the SAME `blueprints v1`
-- format, ALWAYS list-shaped (one entry or many) -- one entry for View text, the
-- whole library for Copy all. So there is nothing new to render; the sharing text
-- IS the library file text.
--
-- Import is the paste sibling of groupimport.classify / .apply (issue #30): parse the
-- pasted blob (the SAME hardened sandbox as M.parse), classify each entry against the
-- existing library by NAME case-insensitively (created vs collide), then apply under an
-- explicit overwrite confirmation (no silent clobber). A friend's Blueprint that names a
-- set/Mode/Group the importer lacks imports cleanly -- the warnings happen at STAMP time
-- (slice 1 behavior), never here.
-- ---------------------------------------------------------------------------

local function ci(a, b) return string.lower(tostring(a)) == string.lower(tostring(b)); end

-- The library index of the entry whose display name matches `name` case-insensitively,
-- else nil. Mirrors the Groups-import collision rule (findCI) -- the name is the identity
-- for import purposes, even though the library is an ordered array, not a keyed map.
local function findEntryCI(list, name)
    if type(list) ~= 'table' then return nil; end
    for i, e in ipairs(list) do
        if type(e) == 'table' and type(e.name) == 'string' and ci(e.name, name) then return i; end
    end
    return nil;
end
M.findEntryCI = findEntryCI;

-- Serialize ONE library entry as a one-entry shareable blob (View text). A thin wrapper on
-- M.serialize so a single Blueprint and the whole library render the SAME way (list-shaped).
function M.serializeOne(entry, prettyKey)
    return M.serialize({ entry }, prettyKey);
end

-- Split parsed import entries into the names that would be CREATED vs the names that COLLIDE
-- with an existing Blueprint (case-insensitive) and would be OVERWRITTEN. Both lists carry the
-- IMPORTED spelling and are sorted (deterministic display -- hard rule 8). The caller surfaces
-- collisions and requires confirmation before apply (the Groups-import precedent).
function M.classifyImport(entries, existing)
    local created, collided = {}, {};
    if type(entries) == 'table' then
        for _, e in ipairs(entries) do
            if type(e) == 'table' and type(e.name) == 'string' then
                if findEntryCI(existing, e.name) ~= nil then collided[#collided + 1] = e.name;
                else created[#created + 1] = e.name; end
            end
        end
    end
    table.sort(created);
    table.sort(collided);
    return created, collided;
end

-- Parse pasted text + classify against the existing library in one call (the live-preview
-- seam the UI draws before commit). Returns ( preview | nil, err ):
--   preview = { entries = { entry, ... }, created = { name, ... }, collided = { name, ... } }
-- entries carries each entry's name/handler/rule (the UI lists them with emitRule); nil+err on
-- a parse failure (a torn or hostile blob -- the sandbox never executes it).
function M.previewImport(text, existing)
    local list, err = M.parse(text);
    if list == nil then return nil, err; end
    local created, collided = M.classifyImport(list, existing);
    return { entries = list, created = created, collided = collided }, nil;
end

-- Merge parsed import entries into `existing` (mutated in place). A collision (case-insensitive
-- name) is OVERWRITTEN only when `overwrite` is true -- the existing entry keeps its stored name
-- spelling but adopts the imported handler + rule; otherwise it is REFUSED (skipped). A new name
-- is appended. Each adopted rule is re-sanitized + deep-copied (makeEntry), so the library shares
-- no table with the parsed blob (detached). Returns { created, updated, refused }.
function M.applyImport(existing, entries, overwrite)
    local created, updated, refused = 0, 0, 0;
    if type(existing) ~= 'table' or type(entries) ~= 'table' then
        return { created = 0, updated = 0, refused = 0 };
    end
    for _, e in ipairs(entries) do
        if type(e) == 'table' then
            local entry = M.makeEntry(e.handler, e.rule, e.name);
            if entry ~= nil then
                local idx = findEntryCI(existing, entry.name);
                if idx ~= nil then
                    if overwrite == true then
                        -- Overwrite THAT Blueprint: keep the stored name, adopt handler + rule.
                        existing[idx] = { name = existing[idx].name, handler = entry.handler, rule = entry.rule };
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
