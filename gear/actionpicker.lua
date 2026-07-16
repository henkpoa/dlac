--[[
    dlac/actionpicker.lua -- the pure searchable spell/ability browse-list core
    (issue #26, G3; PRD #21, ADR 0009; advances #12).

    A Group is an untyped list of action names (spells / abilities), so the Groups tab
    wants to build membership from a searchable, job-filtered browse-list instead of only
    typing names. This module is the pure, ImGui-free, Ashita-free, file-IO-free core the
    headless suite pins (tests ACP*): the two helpers the issue names --

      buildList(job, spells, abilities) -> { { name, kind, level }, ... }
        the current job's LEARNABLE spells + abilities as ONE combined list, sorted by
        name (case-insensitive). `kind` is 'spell' or 'ability' (each entry says which);
        `level` is the job's acquisition level, carried for DISPLAY only -- the list is
        deliberately NOT gated to the player's current level (build-ahead: a set / group
        may reference an action you have not learned yet, HARD RULE 6 / ADR 0006).
        The spell + ability tables (data/spells.lua, data/abilities.lua) are INJECTED so
        the transform stays pure -- triggersui passes the required data files, the headless
        suite passes stub rows (the setimport.lua resolver-injection precedent).

      parseQuery(q) -> { term, ... }        comma-separated, lowercased, trimmed
      matches(entry, terms) -> bool         ALL terms must be a substring of the name
        the search-match predicate: 'stone, ii' narrows to names carrying BOTH. An empty
        query matches everything. `entry` may be a buildList row or a bare name string.

    Structured so an ordinary `name` trigger condition can adopt the SAME picker later
    (issue #12): buildList + the search predicate are the whole browse capability, with no
    Group-specific coupling. Addon-state only -- never seeded into LAC.

    Job keys are the CatsEyeXI abbreviations the picker DB uses (BLU / WHM / ...), exactly
    what gData's MainJob resolves to; buildList upper-cases the passed job before lookup.
]]--

local M = {};

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''));
end

-- Build the combined, job-filtered browse-list. `spells` / `abilities` are the picker-DB
-- row arrays ({ Name = 'Stone', Jobs = { BLM = 1, ... }, ... }); an entry belongs to the
-- job when its `Jobs` map names that job at ANY level (ungated -- the level is display
-- only). Returns a fresh array sorted case-insensitively by name, then kind, then level;
-- nil-safe (a nil / unknown job or missing data yields {}).
function M.buildList(job, spells, abilities)
    local out = {};
    local j = string.upper(trim(job));
    if j == '' or j == '?' or j == 'NON' then return out; end
    local function harvest(rows, kind)
        if type(rows) ~= 'table' then return; end
        for _, r in ipairs(rows) do
            if type(r) == 'table' and type(r.Name) == 'string' and type(r.Jobs) == 'table' then
                local lv = r.Jobs[j];
                if lv ~= nil then
                    out[#out + 1] = { name = r.Name, kind = kind, level = tonumber(lv) or 0 };
                end
            end
        end
    end
    harvest(spells, 'spell');
    harvest(abilities, 'ability');
    table.sort(out, function(a, b)
        local la, lb = string.lower(a.name), string.lower(b.name);
        if la ~= lb then return la < lb; end
        if a.kind ~= b.kind then return a.kind < b.kind; end     -- 'ability' before 'spell'
        return (a.level or 0) < (b.level or 0);
    end);
    return out;
end

-- Split a search box into lowercased, trimmed, comma-separated terms (empty terms
-- dropped). Mirrors gearui's item-search parse, minus the stat-alias canon (actions carry
-- no stats). An empty / whitespace query yields {} -> matches() returns true for all.
function M.parseQuery(q)
    local terms = {};
    for t in string.gmatch(tostring(q or ''), '[^,]+') do
        t = string.lower(trim(t));
        if t ~= '' then terms[#terms + 1] = t; end
    end
    return terms;
end

-- Is this entry shown under the parsed terms? ALL terms must be a plain (non-pattern)
-- substring of the entry name, case-insensitively. No terms = "show everything". `entry`
-- is a buildList row ({ name = ... }) or a bare name string. Never errors on odd input.
function M.matches(entry, terms)
    if type(terms) ~= 'table' or #terms == 0 then return true; end
    local name = (type(entry) == 'table') and entry.name or entry;
    name = string.lower(tostring(name or ''));
    for _, t in ipairs(terms) do
        if string.find(name, t, 1, true) == nil then return false; end
    end
    return true;
end

return M;
