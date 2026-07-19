--[[
    dlac/weightimport.lua -- the pure "Import Weights" transform: the weights sibling of
    groupimport.lua's "Import Lua Table(s)" (Henrik 2026-07-19: groups can be imported,
    weights could not -- data insights had to be retyped stat by stat).

    Paste `Name = { Stat = pts, ... }` assignments and bulk-create one NAMED weight
    profile ("Saved Sets" in the weights editor's copy-from menu) per top-level key.
    The flow after import is the existing one: bind a set in the weights editor, then
    copy from... > Saved Sets > <Name> -- so imported tunings attach to any set (and
    through the set, to its triggers) without retyping.

      parse(text)     -> ( profiles { name -> { Stat -> {perUnit, cap|nil} } } | nil,
                           errors { string, ... } )
      parsePrio(text) -> ( lists { name -> ordered { {stat, cap|nil}, ... } } | nil,
                           errors )                       -- the Priority tab's twin
      classify(profiles, existingNames) -> created {names}, overwritten {names}
      renderPoints(named) / renderPrio(prioNamed) -> text  -- EXPORT: emits exactly
                           the text the matching parser accepts (round-trip pinned)

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

-- ---------------------------------------------------------------------------
-- PRIORITY lists (2026-07-19 round 2): the Priority tab's ordered "Saved
-- Lists" get the same import. Order IS the data, so the paste shape is an
-- ARRAY -- each entry a stat name or a capped pair:
--     Debuff = { 'MACC', 'BlueMagicSkill', { 'INT', 60 } },
-- ({ stat = 'INT', cap = 60 } is accepted too.) Entries normalize to the
-- store's { stat, cap|nil } rows; gearoptim.importNamedPrio applies.
-- ---------------------------------------------------------------------------

-- Normalize one pasted priority entry, or (nil, reason).
local function toPrioEntry(v)
    if type(v) == 'string' then
        if trim(v) == '' then return nil, 'has a blank stat name'; end
        return { stat = trim(v) };
    end
    if type(v) == 'table' then
        local stat = v.stat or v[1];
        if type(stat) ~= 'string' or trim(stat) == '' then
            return nil, 'has an entry without a stat name (use \'Stat\' or {\'Stat\', cap})';
        end
        local cap = tonumber(v.cap or v[2]);
        if cap ~= nil and cap <= 0 then cap = nil; end
        return { stat = trim(stat), cap = cap };
    end
    return nil, 'has an entry that is neither a stat name nor a {\'Stat\', cap} pair';
end

-- Turn one profile's value into an ordered entry list, or (nil, reason).
local function toPrioList(val)
    for k in pairs(val) do
        if type(k) ~= 'number' then
            return nil, 'has named fields (a priority list is ORDERED: \'Stat\' entries, top first)';
        end
    end
    local out = {};
    for _, v in ipairs(val) do
        local e, why = toPrioEntry(v);
        if e == nil then return nil, why; end
        out[#out + 1] = e;
    end
    if #out == 0 then return nil, 'is empty (a priority list needs at least one stat)'; end
    return out;
end

-- The priority-list twin of M.parse. Same contract: (lists, errors).
function M.parsePrio(text)
    if not hasEval then
        return nil, { 'weights import unavailable (groupimport.evalTable missing)' };
    end
    if type(text) ~= 'string' or trim(text) == '' then
        return nil, { 'Nothing to import -- paste some  Name = { \'Stat\', ... }  lines first.' };
    end
    local root, evalErr = gimp.evalTable(text);
    if type(root) ~= 'table' then
        return nil, { 'Could not parse the pasted text: ' .. tostring(evalErr) };
    end
    local lists, errors = {}, {};
    for k, v in pairs(root) do
        if type(k) ~= 'string' or trim(k) == '' then
            errors[#errors + 1] = 'Skipped an unnamed entry (every list needs a  Name = {...}).';
        elseif type(v) ~= 'table' then
            errors[#errors + 1] = string.format('"%s" skipped: its value is not a list (use  %s = { \'Stat\', ... }).', tostring(k), tostring(k));
        else
            local list, reason = toPrioList(v);
            if list == nil then
                errors[#errors + 1] = string.format('"%s" skipped: %s.', k, reason);
            else
                lists[trim(k)] = list;
            end
        end
    end
    table.sort(errors);
    return lists, errors;
end

-- ---------------------------------------------------------------------------
-- EXPORT: the named stores rendered back into the exact text the importers
-- accept -- the round trip is the contract (pinned by tests WX*). Sorted
-- names; point rows sorted heaviest-first (the shape a human writes them in).
-- ---------------------------------------------------------------------------

local LUA_KEYWORD = {
    ['and'] = true, ['break'] = true, ['do'] = true, ['else'] = true, ['elseif'] = true,
    ['end'] = true, ['false'] = true, ['for'] = true, ['function'] = true, ['goto'] = true,
    ['if'] = true, ['in'] = true, ['local'] = true, ['nil'] = true, ['not'] = true,
    ['or'] = true, ['repeat'] = true, ['return'] = true, ['then'] = true, ['true'] = true,
    ['until'] = true, ['while'] = true,
};
local function key(name)
    if name:match('^[%a_][%w_]*$') ~= nil and not LUA_KEYWORD[name] then return name; end
    return string.format('[%q]', name);
end
local function sortedNames(t)
    local names = {};
    for n in pairs(t) do names[#names + 1] = n; end
    table.sort(names);
    return names;
end

-- named ( name -> { Stat -> {perUnit, cap|nil} } ) -> importable text.
function M.renderPoints(named)
    local L = {};
    for _, name in ipairs(sortedNames(named or {})) do
        local wmap = named[name];
        local stats = {};
        for s, w in pairs(wmap) do
            if type(s) == 'string' and type(w) == 'table' and type(w.perUnit) == 'number' then
                stats[#stats + 1] = { s = s, w = w };
            end
        end
        table.sort(stats, function(a, b)
            if a.w.perUnit ~= b.w.perUnit then return a.w.perUnit > b.w.perUnit; end
            return a.s < b.s;
        end);
        L[#L + 1] = key(name) .. ' = {';
        for _, e in ipairs(stats) do
            if type(e.w.cap) == 'number' then
                L[#L + 1] = string.format('    %s = { %s, %s },', key(e.s), tostring(e.w.perUnit), tostring(e.w.cap));
            else
                L[#L + 1] = string.format('    %s = %s,', key(e.s), tostring(e.w.perUnit));
            end
        end
        L[#L + 1] = '},';
    end
    return table.concat(L, '\n');
end

-- prioNamed ( name -> ordered { {stat, cap|nil}, ... } ) -> importable text.
function M.renderPrio(prioNamed)
    local L = {};
    for _, name in ipairs(sortedNames(prioNamed or {})) do
        local parts = {};
        for _, e in ipairs(prioNamed[name]) do
            if type(e) == 'table' and type(e.stat) == 'string' then
                if type(e.cap) == 'number' then
                    parts[#parts + 1] = string.format('{ %q, %s }', e.stat, tostring(e.cap));
                else
                    parts[#parts + 1] = string.format('%q', e.stat);
                end
            end
        end
        L[#L + 1] = string.format('%s = { %s },', key(name), table.concat(parts, ', '));
    end
    return table.concat(L, '\n');
end

-- Split parsed profiles into created vs overwritten names, both sorted. `existing`
-- is the current named-store name list (array) or map; matching is EXACT (the
-- named store's own semantics). The caller confirms overwrites before applying.
-- Shared by BOTH importers (points profiles and priority lists have the same
-- name->value outer shape).
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
