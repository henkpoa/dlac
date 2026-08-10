--[[
    bludex/lib/blusetsimport.lua -- one-way import of `blusets` spell lists
    (config/addons/blusets/<name>.txt -- one spell name per line, blank line
    = empty slot) into bludex saved sets. Imports land as FLAT sets -- the
    faithful shape: blusets has no notion of level, and under the kinds
    model (docs/set-types-plan.md) a flat set is first-class, nothing waits
    on an adopt to convert it.

    parse() is pure given the book; everything touching AshitaCore or the
    filesystem is guarded, so the module loads headless (smoke test).
    A name collision SKIPS the file -- imports never clobber a bludex set.
]]--

local ROOT = (...):sub(1, -#('lib\\blusetsimport') - 1);
local setmodel = require(ROOT .. 'lib\\setmodel');

local M = {};

-- One blusets line -> a real spell id. The book covers the 136 BLU spells;
-- anything else falls through to the client's resource manager (the id is
-- kept as an honest '#id' cell, same as Read current), then to nil = unknown.
local function toId(name, book)
    local id = book.byName[book.norm(name)];
    if id ~= nil then return id; end
    local ok, sp = pcall(function()
        return AshitaCore:GetResourceManager():GetSpellByName(name, 0);
    end);
    if ok and sp ~= nil then return sp.Index; end
    return nil;
end

-- lines (slot order, blusets writes 20) -> ids{20}, unknown{names}.
function M.parse(lines, book)
    local ids, unknown = {}, {};
    for i = 1, 20 do ids[i] = 0; end
    for i = 1, math.min(#lines, 20) do
        local name = tostring(lines[i]):gsub('^%s+', ''):gsub('%s+$', '');
        if name ~= '' then
            local id = toId(name, book);
            if id ~= nil then
                ids[i] = id;
            else
                unknown[#unknown + 1] = name;
            end
        end
    end
    return ids, unknown;
end

local function dir()
    local ok, p = pcall(function()
        return string.format('%s\\config\\addons\\blusets\\', AshitaCore:GetInstallPath());
    end);
    return ok and p or nil;
end

-- Every saved blusets list: { { name, path }, ... } sorted by name.
function M.scan()
    local base = dir();
    if base == nil then return {}; end
    local ok, files = pcall(function()
        return ashita.fs.get_dir(base, '.*.txt', true);
    end);
    if not ok or files == nil then return {}; end
    local out = {};
    for _, f in ipairs(files) do
        out[#out + 1] = { name = (f:gsub('%.txt$', '')), path = base .. f };
    end
    table.sort(out, function(a, b) return a.name < b.name; end);
    return out;
end

local function readLines(path)
    local f = io.open(path, 'r');
    if f == nil then return nil; end
    local lines = {};
    for line in f:lines() do lines[#lines + 1] = line; end
    f:close();
    return lines;
end

-- Import every blusets list (or just `only`, matched by file name) into
-- cfg.sets. Returns a summary:
--   { found = n,                 -- blusets files seen (0 = nothing to import)
--     imported = {names},        -- added to cfg.sets (caller saves)
--     skipped = {names},         -- name already exists as a bludex set
--     unknown = {'Set: Spell'} } -- lines no id could be found for
function M.importAll(cfg, book, only)
    local res = { found = 0, imported = {}, skipped = {}, unknown = {} };
    local want = only and only ~= '' and book.norm((only:gsub('%.txt$', ''))) or nil;
    local have = {};
    for _, entry in ipairs(cfg.sets) do have[book.norm(entry.name)] = true; end
    for _, f in ipairs(M.scan()) do
        if want == nil or book.norm(f.name) == want then
            res.found = res.found + 1;
            if have[book.norm(f.name)] then
                res.skipped[#res.skipped + 1] = f.name;
            else
                local lines = readLines(f.path);
                if lines ~= nil then
                    local ids, unknown = M.parse(lines, book);
                    local set = setmodel.new(f.name, 'flat');
                    for i = 1, 20 do set.ids[i] = ids[i] or 0; end
                    table.insert(cfg.sets, set);
                    have[book.norm(f.name)] = true;
                    res.imported[#res.imported + 1] = f.name;
                    for _, u in ipairs(unknown) do
                        res.unknown[#res.unknown + 1] = f.name .. ': ' .. u;
                    end
                end
            end
        end
    end
    return res;
end

-- The one-line summary the UI note wears; the command prints richer lines.
function M.describe(res)
    if res.found == 0 then
        return 'No blusets spell lists found (config/addons/blusets/*.txt).';
    end
    local parts = { string.format('Imported %d set%s', #res.imported,
        #res.imported == 1 and '' or 's') };
    if #res.skipped > 0 then
        parts[#parts + 1] = string.format('%d skipped (name exists)', #res.skipped);
    end
    if #res.unknown > 0 then
        parts[#parts + 1] = string.format('%d unknown spell name%s', #res.unknown,
            #res.unknown == 1 and '' or 's');
    end
    return table.concat(parts, '; ') .. '.';
end

return M;
