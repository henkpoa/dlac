--[[
    dlac/weightimport.lua -- the pure "Import Weights" transform: the weights sibling of
    groupimport.lua's "Import Lua Table(s)" (Henrik 2026-07-19: groups can be imported,
    weights could not -- data insights had to be retyped stat by stat).

    Paste `Name = { Stat = pts, ... }` assignments and bulk-create one NAMED weight
    profile ("Saved Sets" in the weights editor's copy-from menu) per top-level key.
    The flow after import is the existing one: bind a set in the weights editor, then
    copy from... > Saved Sets > <Name> -- so imported tunings attach to any set (and
    through the set, to its triggers) without retyping.

      parse(text) -> ( profiles { name -> { Stat -> {perUnit, cap|nil} } } | nil,
                       errors { string, ... } )
      classify(profiles, existingNames) -> created {names}, overwritten {names}

    Rules (mirroring groupimport where the shapes correspond):
      - `T` is identity; `T{...}` and `{...}` both work. Bare `Key = {...}` lines or a
        whole braced table both parse (groupimport.evalTable does the sandboxed eval --
        one hardened loader, not two).
      - Each profile is a FLAT map of  Stat = <weight>. A weight is:
            12                  -- perUnit only
            { 12, 60 }          -- perUnit, cap
            { perUnit = 12, cap = 60 }   -- explicit fields (pts= accepted for perUnit=)
        Anything else skips THAT profile with a reported reason; other keys still land.
      - A profile with no valid stat rows is skipped (an empty tuning scores nothing --
        it is a paste mistake, not data).
      - Stat spellings are NOT resolved here (pure module, no catalog); the applier
        (gearoptim.importNamedWeights) canonicalizes via canonStat, so ACC/Acc/Accuracy
        all land on the catalog spelling.
      - Collision matching is EXACT-name, like the named store itself (saveNamedWeights /
        copyWeightsFromNamed are exact; groups are CI because groupsmodel matches CI).

    Application lives in gearoptim (M.importNamedWeights) so the named store's
    invariants (lazy load-before-mutate, canonStat, persistence via saveWeights) stay in
    one place; this module never touches storage.
]]--

local M = {};

-- The sandboxed text->table evaluator, shared with the groups import (one hardened
-- loader). Guarded: headless callers seed package.loaded; a missing module turns
-- every parse into a reported error instead of a crash.
local _giok, gimp = pcall(require, 'dlac\\gear\\groupimport');
local hasEval = _giok and type(gimp) == 'table' and type(gimp.evalTable) == 'function';

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''));
end

-- Normalize one pasted weight value into { perUnit, cap|nil }, or (nil, reason).
local function toWeight(v)
    if type(v) == 'number' then return { perUnit = v }; end
    if type(v) == 'table' then
        local per = tonumber(v.perUnit or v.pts or v[1]);
        if per == nil then return nil, 'needs a points number first (pts, {pts, cap}, or {perUnit=..., cap=...})'; end
        local cap = tonumber(v.cap or v[2]);
        if cap ~= nil and cap <= 0 then cap = nil; end   -- 0/negative cap = uncapped
        return { perUnit = per, cap = cap };
    end
    return nil, 'is not a number or a {pts, cap} table';
end

-- Turn one profile's value into a Stat -> weight map, or (nil, reason).
local function toStatmap(val)
    local out, n = {}, 0;
    for k, v in pairs(val) do
        if type(k) ~= 'number' then   -- list entries checked below (clearer message)
            if type(k) ~= 'string' or trim(k) == '' then
                return nil, 'has an unnamed stat row (every row must be  Stat = pts)';
            end
            local w, why = toWeight(v);
            if w == nil then
                return nil, string.format('stat "%s" %s', trim(k), why);
            end
            out[trim(k)] = w;
            n = n + 1;
        else
            return nil, 'has list entries (weights are  Stat = pts  rows, not a list)';
        end
    end
    if n == 0 then return nil, 'has no stat rows (an empty tuning scores nothing)'; end
    return out;
end

-- The pure transform. Returns (profiles, errors) -- profiles nil only on a total
-- parse failure; errors sorted for a stable display (pairs() order is undefined).
function M.parse(text)
    if not hasEval then
        return nil, { 'weights import unavailable (groupimport.evalTable missing)' };
    end
    if type(text) ~= 'string' or trim(text) == '' then
        return nil, { 'Nothing to import -- paste some  Name = { Stat = pts, ... }  lines first.' };
    end
    local root, evalErr = gimp.evalTable(text);
    if type(root) ~= 'table' then
        return nil, { 'Could not parse the pasted text: ' .. tostring(evalErr) };
    end

    local profiles, errors = {}, {};
    for k, v in pairs(root) do
        if type(k) ~= 'string' or trim(k) == '' then
            errors[#errors + 1] = 'Skipped an unnamed entry (every profile needs a  Name = {...}).';
        elseif type(v) ~= 'table' then
            errors[#errors + 1] = string.format('"%s" skipped: its value is not a table (use  %s = { Stat = pts, ... }).', tostring(k), tostring(k));
        else
            local statmap, reason = toStatmap(v);
            if statmap == nil then
                errors[#errors + 1] = string.format('"%s" skipped: %s.', k, reason);
            else
                profiles[trim(k)] = statmap;
            end
        end
    end
    table.sort(errors);
    return profiles, errors;
end

-- Split parsed profiles into created vs overwritten names, both sorted. `existing`
-- is the current named-store name list (array) or map; matching is EXACT (the
-- named store's own semantics). The caller confirms overwrites before applying.
function M.classify(profiles, existing)
    local have = {};
    if type(existing) == 'table' then
        for k, v in pairs(existing) do
            if type(k) == 'number' and type(v) == 'string' then have[v] = true;
            elseif type(k) == 'string' then have[k] = true; end
        end
    end
    local created, overwritten = {}, {};
    if type(profiles) == 'table' then
        for name in pairs(profiles) do
            if have[name] then overwritten[#overwritten + 1] = name;
            else created[#created + 1] = name; end
        end
    end
    table.sort(created);
    table.sort(overwritten);
    return created, overwritten;
end

return M;
