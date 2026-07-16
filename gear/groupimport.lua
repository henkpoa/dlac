--[[
    dlac/groupimport.lua -- the pure "Import Lua Table(s)" transform (issue #30, G4; PRD #21, ADR 0009).

    The fast path for a player who already keeps their spells grouped in a Lua table (by stat
    scaling, by role, ...): paste the `Name = T{...}` assignments and bulk-create one Group per
    top-level key, each holding the key's string array as its members. It is the import sibling of
    the Groups tab's one-at-a-time CRUD (groupsmodel.lua) and of setimport.lua's "Copy from
    static" transform -- same shape: the pure, ImGui-free / Ashita-free / file-IO-free core the
    headless suite pins (tests TGI*), with the UI shell (the paste box, the collision
    confirmation, the summary) living in triggersui.

      parse(text) -> ( groups { name -> { member, ... }, ... } | nil, errors { string, ... } )

    Rules (issue #30):
      - `T` is IDENTITY: `T{...}` (Windower / LuaAshitacast typed table) and plain `{...}` both
        work; the `T` is optional.
      - FLAT ONLY. Each value must be an array of strings. A value that is a nested table, has
        named fields, or holds a non-string element causes THAT key to be skipped with a reported
        reason -- the other keys still import (no all-or-nothing failure on one bad key).
      - Accept either bare `Key = {...}, ...` lines (the common paste) OR a whole
        `{ Key = {...}, ... }` table. Trailing commas are tolerated.

    Parsing is SANDBOXED (the hardened pattern of profilesets.sandboxSets / the setmanager
    loaders): the pasted text is evaluated in a minimal environment -- `T = identity` and nothing
    else, no `os` / `io` / globals -- as a text chunk only, so malformed input yields an error, it
    never crashes the UI or executes anything. Addon-state only; never seeded into LAC.
]]--

local M = {};

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''));
end
local function ci(a, b) return string.lower(tostring(a)) == string.lower(tostring(b)); end

-- Find the STORED spelling of `name` in an existing groups map (case-insensitive), else nil --
-- mirrors groupsmodel.findName so a collision decision matches the engine's M.groupMatch.
local function findCI(existing, name)
    if type(existing) ~= 'table' then return nil; end
    for nm in pairs(existing) do
        if type(nm) == 'string' and ci(nm, name) then return nm; end
    end
    return nil;
end

-- Compile `code` under the sandbox env. Portable across LuaJIT/5.1 (setfenv) and 5.2+/5.4
-- (load's env arg); the test suite runs on 5.4, the addon on LuaJIT. 't' mode = text only
-- (no bytecode), so a paste can never smuggle in a precompiled chunk.
local function compile(code, env)
    if setfenv ~= nil then                              -- LuaJIT / 5.1
        local f, err = (loadstring or load)(code, 'dlac-group-import');
        if f == nil then return nil, err; end
        setfenv(f, env);
        return f;
    end
    return load(code, 'dlac-group-import', 't', env);   -- 5.2+ (Ashita is LuaJIT; tests are 5.4)
end

-- A minimal, hardened environment. `T` is the only visible name; it is identity, so `T{...}`
-- collapses to `{...}`. No metatable -> every other global (os, io, require, ...) reads nil, so a
-- hostile paste (`os.execute(...)`) errors at eval and is reported, never run.
local function makeEnv()
    return { T = function(t) return t; end };
end

-- Evaluate the pasted text into a name->value table. Two accepted shapes: a whole
-- `{ Key = {...}, ... }` table, or bare `Key = {...}, ...` lines (wrapped in braces). We try the
-- shape the leading character suggests first, then the other, so a leading comment or an
-- unexpected wrapping still resolves. Returns (table | nil, errString).
local function evalTable(text)
    local trimmed = (text:gsub('^%s+', ''));
    local braced = 'return {\n' .. text .. '\n}';       -- bare assignments -> a table constructor
    local whole  = 'return ' .. text;                   -- an already-braced table
    -- The leading char picks the likely shape; the other is a fallback for odd wrapping (e.g. a
    -- leading comment). When BOTH fail we report the PRIMARY form's error -- the fallback's
    -- "<eof> expected" would mask the real "unterminated table" / sandbox-blocked-global message.
    local forms = (trimmed:sub(1, 1) == '{') and { whole, braced } or { braced, whole };
    local primaryErr = 'empty input';
    for i, code in ipairs(forms) do
        local chunk, cerr = compile(code, makeEnv());
        local err;
        if chunk ~= nil then
            local ok, ret = pcall(chunk);
            if ok and type(ret) == 'table' then return ret, nil; end
            err = ok and 'the text did not evaluate to a table' or tostring(ret);
        else
            err = tostring(cerr);
        end
        if i == 1 then primaryErr = err; end
    end
    return nil, primaryErr;
end

-- Turn one group's value into an ordered member list, or (nil, reason) when it is not a flat
-- array of strings. Named fields (a map), a nested table element, or a non-string element each
-- reject the WHOLE key -- flat-only, per the issue. Blank / whitespace members are dropped;
-- order is preserved (ipairs). An empty list is legal (a group you are still filling).
local function toMembers(val)
    for k, v in pairs(val) do
        if type(k) ~= 'number' then
            return nil, 'has named fields (each group must be a plain list of action names)';
        elseif type(v) == 'table' then
            return nil, 'contains a nested table (groups must be flat -- a list of names)';
        elseif type(v) ~= 'string' then
            return nil, 'contains a non-string value (' .. type(v) .. ')';
        end
    end
    local members = {};
    for _, v in ipairs(val) do
        local t = trim(v);
        if t ~= '' then members[#members + 1] = t; end
    end
    return members;
end

-- The pure transform. Returns (groups, errors): groups is a name->member-array map (nil only on a
-- total parse failure), errors is an array of player-facing strings -- one per skipped key, or a
-- single message when nothing could be parsed. Errors are sorted for a stable, deterministic
-- display (pairs() order is undefined -- hard rule 8).
function M.parse(text)
    if type(text) ~= 'string' or trim(text) == '' then
        return nil, { 'Nothing to import -- paste some  Name = { ... }  lines first.' };
    end
    local root, evalErr = evalTable(text);
    if type(root) ~= 'table' then
        return nil, { 'Could not parse the pasted text: ' .. tostring(evalErr) };
    end

    local groups, errors = {}, {};
    for k, v in pairs(root) do
        if type(k) ~= 'string' or trim(k) == '' then
            errors[#errors + 1] = 'Skipped an unnamed entry (every group needs a  Name = {...}).';
        elseif type(v) ~= 'table' then
            errors[#errors + 1] = string.format('"%s" skipped: its value is not a list (use  %s = T{...}  or  {...}).', tostring(k), tostring(k));
        else
            local members, reason = toMembers(v);
            if members == nil then
                errors[#errors + 1] = string.format('"%s" skipped: %s.', k, reason);
            else
                groups[trim(k)] = members;
            end
        end
    end
    table.sort(errors);
    return groups, errors;
end

-- Split parsed groups into the names that would be CREATED vs the names that COLLIDE with an
-- existing group (case-insensitive) and would be OVERWRITTEN. Both lists carry the IMPORTED
-- spelling and are sorted. The caller surfaces collisions and requires confirmation before apply
-- (no silent clobber -- parity with "Copy from static").
function M.classify(groups, existing)
    local created, overwritten = {}, {};
    if type(groups) == 'table' then
        for name in pairs(groups) do
            if findCI(existing, name) ~= nil then overwritten[#overwritten + 1] = name;
            else created[#created + 1] = name; end
        end
    end
    table.sort(created);
    table.sort(overwritten);
    return created, overwritten;
end

-- Write the parsed groups into `existing` (mutated in place). A collision replaces the members
-- under the EXISTING stored spelling (you are overwriting THAT group); a new name is created
-- under its imported spelling. Returns a summary { created, updated, members } for the report.
function M.apply(existing, groups)
    local created, updated, members = 0, 0, 0;
    if type(existing) ~= 'table' or type(groups) ~= 'table' then
        return { created = 0, updated = 0, members = 0 };
    end
    for name, mem in pairs(groups) do
        local stored = findCI(existing, name);
        if stored ~= nil then
            existing[stored] = mem;
            updated = updated + 1;
        else
            existing[trim(name)] = mem;
            created = created + 1;
        end
        members = members + #mem;
    end
    return { created = created, updated = updated, members = members };
end

-- Exposed for the auto-import scanner (groupscan.lua): the flat-string-array heuristic and the
-- sandboxed text->table evaluator, so the "is this a group?" rule and the safe eval live in
-- exactly one place instead of being re-implemented by the scanner.
M.membersOf = toMembers;
M.evalTable = evalTable;

return M;
