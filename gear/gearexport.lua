--[[
    dlac/gearexport.lua — /dl export: dump everything dlac knows about the
    character's owned gear to <char>\dlac\gearexport.json, for EXTERNAL tools
    (built for a friend's damage simulator; the schema is tool-agnostic).

    One JSON object: a meta header (character/job/time/notes) + a flat `items`
    array. Per item: identity (name/id/slot/type/level/jobs), oneHanded, the
    owned copy count (ownedcache totals -- the same bag scan set building
    trusts; 0 = listed in gear.lua but not currently in your bags), stats, and
    the owned copies' augments (readable string per copy + decoded stat deltas
    of the FIRST augmented copy -- that is all augments.lua tracks per id).

    Stats come from the owned record with catalog gap-fill -- the same
    precedence as gearui's enrichGearFromCatalog (owned overrides, catalog
    fills) but READ-ONLY: the shared gear table is never mutated here, so an
    export can run before the GUI ever opened. Values are display units
    (DT = -5 is -5%); keys are dlac's statdefs vocabulary (PDT/MDT/DT/MDMG/...).

    Addon state only (augments need the live inventory). The builders and the
    JSON encoder are pure and exported for the headless suite (Y-tests).
]]--

local M = {};

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local print = (_cfok and type(_cfmt.print) == 'function') and _cfmt.print or print;
local function printerr(s) if _cfok then _cfmt.err(s); else print('[dlac] ' .. s); end end

local gok, gear = pcall(require, 'dlac\\gear');
if not gok or type(gear) ~= 'table' then gear = {}; end
-- Owned-gear record rules: the enrichment precedence lives ONCE (gearrecord),
-- so an export before the GUI ever opened matches one after (same heal, same merge).
local grec = require('dlac\\gear\\gearrecord');
-- The catalog id-index comes from THE one walker (gear\catalogindex, issue #71):
-- gearexport's private nested walk is retired, so exactly one catalog walk remains
-- in the codebase (the acknowledged tech-debt cleanup from architecture.md).
local _ciok, catindex = pcall(require, 'dlac\\gear\\catalogindex');
_ciok = _ciok and type(catindex) == 'table';
local haok, aug = pcall(require, 'dlac\\feature\\augments');
haok = haok and type(aug) == 'table';
local hook, ownedc = pcall(require, 'dlac\\gear\\ownedcache');
hook = hook and type(ownedc) == 'table';

-- The gear table's slot categories, in equipment order (also the export order).
-- Ear/Ring each cover BOTH equipment slots; NameToObject is deliberately not
-- walked (it aliases the same records and would double every item).
M.SLOT_ORDER = { 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck', 'Ear', 'Body',
                 'Hands', 'Ring', 'Back', 'Waist', 'Legs', 'Feet' };

-- ---------------------------------------------------------------------------
-- JSON encoder (pure). Deterministic: object keys sorted, so re-exports diff
-- cleanly. Pretty-printed (2-space) EXCEPT scalar-only arrays, which stay on
-- one line (Jobs lists would otherwise stretch the file 15 lines per item).
-- ---------------------------------------------------------------------------
local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
              ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' };
local function jstr(s)
    return '"' .. string.gsub(s, '[%z\1-\31"\\]', function(c)
        return ESC[c] or string.format('\\u%04x', string.byte(c));
    end) .. '"';
end

local function jnum(v)
    if v ~= v or v == math.huge or v == -math.huge then return 'null'; end
    if math.floor(v) == v and math.abs(v) < 2 ^ 53 then return string.format('%.0f', v); end
    return tostring(v);
end

local function isArray(t)
    local n = 0;
    for _ in pairs(t) do n = n + 1; end
    if n == 0 then return false, 0; end
    for i = 1, n do if t[i] == nil then return false, 0; end end
    return true, n;
end

local function encode(v, ind)
    local tv = type(v);
    if tv == 'string' then return jstr(v); end
    if tv == 'number' then return jnum(v); end
    if tv == 'boolean' then return tostring(v); end
    if tv ~= 'table' then return 'null'; end

    local arr, n = isArray(v);
    if arr then
        local scalarOnly = true;
        for i = 1, n do if type(v[i]) == 'table' then scalarOnly = false; break; end end
        local parts = {};
        if scalarOnly then
            for i = 1, n do parts[#parts + 1] = encode(v[i], ind); end
            return '[' .. table.concat(parts, ', ') .. ']';
        end
        local pad, pad2 = string.rep(' ', ind), string.rep(' ', ind + 2);
        for i = 1, n do parts[#parts + 1] = pad2 .. encode(v[i], ind + 2); end
        return '[\n' .. table.concat(parts, ',\n') .. '\n' .. pad .. ']';
    end

    local keys = {};
    for k in pairs(v) do keys[#keys + 1] = tostring(k); end
    if #keys == 0 then return '{}'; end
    table.sort(keys);
    local pad, pad2 = string.rep(' ', ind), string.rep(' ', ind + 2);
    local parts = {};
    for _, k in ipairs(keys) do
        parts[#parts + 1] = pad2 .. jstr(k) .. ': ' .. encode(v[k], ind + 2);
    end
    return '{\n' .. table.concat(parts, ',\n') .. '\n' .. pad .. '}';
end

function M.jsonEncode(v) return encode(v, 0); end

-- ---------------------------------------------------------------------------
-- Export builders (pure).
-- ---------------------------------------------------------------------------

local function itemEntry(slot, rec, catRec, augs, augStats, counts)
    local e = {
        name  = rec.Name,
        id    = rec.Id,
        slot  = slot,
        -- The record rule, not `rec.Type or cat.Type`: a legacy spelling heals to
        -- the catalog key here exactly as the GUI's enrich heals it in memory.
        type  = grec.healType(rec.Type, (catRec ~= nil) and catRec.Type or nil),
        level = rec.Level or (catRec ~= nil and catRec.Level or nil),
        jobs  = rec.Jobs or (catRec ~= nil and catRec.Jobs or nil),
    };
    local oh = rec.OneHanded;
    if oh == nil and catRec ~= nil then oh = catRec.OneHanded; end
    -- Same record rule as enrich//dl fix: H2H pins false (the catalog's flag
    -- lies there -- see gearrecord.healOneHanded), so exports never carry it.
    oh = grec.healOneHanded(e.type, oh);
    if oh ~= nil then e.oneHanded = oh; end
    if counts ~= nil and rec.Id ~= nil then e.count = counts[rec.Id] or 0; end
    e.stats = grec.mergedStats(rec, catRec);
    if rec.Id ~= nil then
        local a = (augs ~= nil) and augs[rec.Id] or nil;
        if type(a) == 'table' and #a > 0 then e.augments = a; end
        local d = (augStats ~= nil) and augStats[rec.Id] or nil;
        if type(d) == 'table' and next(d) ~= nil then e.augmentStats = d; end
    end
    return e;
end

-- The full export object: meta keys at the root + the items array. Slot
-- categories hold records directly (armor) OR type buckets of records
-- (weapons) -- a record is anything with a string Name. `counts` is the
-- owned-anywhere map (id -> n) or nil when no live scan was possible --
-- nil OMITS every count (unknown is not 0).
function M.buildExport(gearTbl, catalogById, augs, augStats, counts, meta)
    local items = {};
    for _, slot in ipairs(M.SLOT_ORDER) do
        local cat = (type(gearTbl) == 'table') and gearTbl[slot] or nil;
        if type(cat) == 'table' then
            local slotItems = {};
            local function collect(t)
                for _, v in pairs(t) do
                    if type(v) == 'table' then
                        if type(v.Name) == 'string' then
                            local catRec = (v.Id ~= nil) and catalogById[v.Id] or nil;
                            slotItems[#slotItems + 1] = itemEntry(slot, v, catRec, augs, augStats, counts);
                        else
                            collect(v);
                        end
                    end
                end
            end
            collect(cat);
            table.sort(slotItems, function(a, b)
                local an, bn = string.lower(a.name), string.lower(b.name);
                if an ~= bn then return an < bn; end
                return (a.id or 0) < (b.id or 0);
            end);
            for _, e in ipairs(slotItems) do items[#items + 1] = e; end
        end
    end

    local exp = {
        format        = 'dlac-gear-export',
        formatVersion = 1,
        items         = items,
        itemCount     = #items,
        notes = {
            'stats are display units (DT = -5 means -5%); keys follow dlac statdefs vocabulary (PDT/MDT/DT/MDMG/MAB/MACC/...)',
            'slot Ear/Ring covers both equipment slots of that kind',
            'count = copies owned anywhere right now (2+ = dual-wieldable; 0 = listed but not currently in the bags); absent when no live bag scan was possible',
            'augments = readable summary per owned augmented copy; augmentStats = decoded stat deltas of the first augmented copy',
            'stats already include nothing from augments; add augmentStats on top when simulating the owned copy',
        },
    };
    if type(meta) == 'table' then
        for k, v in pairs(meta) do exp[k] = v; end
    end
    return exp;
end

-- ---------------------------------------------------------------------------
-- Live export (addon state): gather inputs, encode, write.
-- ---------------------------------------------------------------------------
local function charDirAndName()
    local name, id;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        name = party:GetMemberName(0);
        id   = party:GetMemberServerId(0);
        if name == '' then name = nil; end
    end);
    if name == nil or id == nil then return nil, nil; end
    return string.format('%sconfig\\addons\\luashitacast\\%s_%u\\dlac\\',
        AshitaCore:GetInstallPath(), name, id), name;
end

function M.export()
    local dir, cname = charDirAndName();
    if dir == nil then return false, 'not logged in (no character folder yet)'; end

    local byId = _ciok and catindex.rawIndex() or {};
    local augs, augStats;
    if haok then
        pcall(function() augs = aug.ownedAugments(); end);
        pcall(function() augStats = aug.ownedAugStats(); end);
    end
    -- Owned-anywhere copy counts, fresh (the ~4s heartbeat cache may predate a
    -- bag move; an export should reflect NOW). Empty scan = unknown -> omit.
    local counts;
    if hook then
        pcall(function()
            ownedc.resetCache();
            local t = ownedc.totals();
            if type(t) == 'table' and next(t) ~= nil then counts = t; end
        end);
    end

    local meta = { character = cname, server = 'CatsEyeXI',
                   exportedAt = os.date('!%Y-%m-%dT%H:%M:%SZ') };
    pcall(function()
        local p = gData.GetPlayer();
        meta.job, meta.jobLevel = p.MainJob, p.MainJobSync;
        meta.subJob, meta.subJobLevel = p.SubJob, p.SubJobSync;
    end);

    local exp = M.buildExport(gear, byId, augs, augStats, counts, meta);
    local path = dir .. 'gearexport.json';
    local f = io.open(path, 'w');
    if f == nil then return false, 'could not write ' .. path; end
    f:write(M.jsonEncode(exp));
    f:write('\n');
    f:close();

    local nAug = 0;
    for _, e in ipairs(exp.items) do if e.augments ~= nil then nAug = nAug + 1; end end
    return true, path, exp.itemCount, nAug;
end

-- ---------------------------------------------------------------------------
-- Command hook:  /dl (or /dlac) export
-- Additive: only this sub is handled/blocked; everything else falls through.
-- ---------------------------------------------------------------------------
local function argStart(raw)
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then return 7; end
    if raw == '/dl'   or string.sub(raw, 1, 4) == '/dl '   then return 5; end
    return nil;
end

ashita.events.register('command', 'dlac-export', function(e)
    local rawLower = string.lower(e.command);
    local start = argStart(rawLower);
    if start == nil then return; end
    local args = {};
    for a in string.gmatch(string.sub(e.command, start), '%S+') do args[#args + 1] = a; end
    if (args[1] and string.lower(args[1])) ~= 'export' then return; end
    e.blocked = true;

    local ok, pathOrErr, n, nAug = M.export();
    if not ok then
        printerr('export: ' .. tostring(pathOrErr));
        return;
    end
    print(string.format('[dlac] exported %d items (%d with augments) for external tools:', n, nAug));
    print('[dlac]   ' .. pathOrErr);
end);

return M;
