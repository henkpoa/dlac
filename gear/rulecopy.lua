--[[
    dlac/rulecopy.lua -- the pure core behind "copy this rule to..." : one Trigger,
    landed in the JOB ENTRIES you tick.

    A trigger file is addressed by TWO coordinates -- profiles\<Profile>\triggers\<JOB>.lua
    -- and a copy varies one of them:

      * JOBS (the ask, and the main event): the same rule in other jobs of the profile
        you are in. Henrik, 2026-08-02: "I want to be able to copy the rule between the
        jobs. Have a list of jobs that we can mark to copy to (where it also checks if it
        has a similar rule already), also can't copy to itself... one button to select all
        jobs."
      * PROFILES: the same job entry in this character's other profiles.

    Both are the same question -- what would landing this rule THERE do? -- so one
    classifier answers both (M.rows), and the caller supplies the coordinate it varied.

    The sibling of a Blueprint, and deliberately not the same thing. A Blueprint is a
    LIBRARY entry: saved, named, kept forever, and stamped onto the ONE job you happen to
    be standing in. Reaching five jobs with it means five job changes. This is the
    one-shot SPREAD that Blueprints cannot do -- tick the jobs, they all have it.

    The copy travels as a Blueprint ENTRY ({ name, handler, rule }) on purpose: capture,
    detach, identical-rule detection and the stamp transform are all already written and
    pinned (blueprintsmodel, tests TGB*), and reusing them is what guarantees a copied
    rule is byte-for-byte the rule a Blueprint stamp would produce. This module adds the
    only thing that was missing -- the ANSWER PER TARGET.

    Pure: no ImGui, no Ashita, no file IO, no clock. The caller reads the target files,
    hands over the parsed data tables, and writes the results back (triggersui owns the
    backup->replace->verify ladder). Tests RC* drive the whole decision surface headless.
]]--

local M = {};

local _bpok, bp = pcall(require, 'dlac\\gear\\blueprintsmodel');
local hasBp = _bpok and type(bp) == 'table';

-- The one capability question: without the Blueprint core there is no capture, no
-- identical-rule test and no stamp, and a hand-rolled second copy of any of them is
-- exactly the parity hazard blueprintsmodel's header warns about. The UI hides the
-- button instead.
function M.usable() return hasBp; end

-- Per-target states. Only the copyable three are ever written to.
--   'source'     where the rule already lives (the job you are on / the active profile)
--                -- never a target, and never tickable: it already has the rule
--   'unreadable' its trigger file exists but does not parse -- REFUSED (never overwritten)
--   'create'     no trigger file there yet -- one is written
--   'dup'        an identical rule already sits in that handler -- allowed, warned (the
--                Blueprint double-stamp law: caught, never forbidden)
--   'add'        the ordinary case
local COPYABLE = { add = true, create = true, dup = true };
function M.copyable(state) return COPYABLE[state] == true; end

-- Capture the live rule as a detached { name, handler, rule } entry. Returns
-- entry | nil, why (a rule with no conditions or no action is not copyable).
function M.entryFor(handler, rule)
    if not hasBp then return nil, 'blueprintsmodel unavailable'; end
    return bp.makeEntry(handler, rule);
end

-- The set names this rule targets, in order, deduped -- what "include the set if it
-- isn't there" has to carry along. A rule with an inline `equip` payload names none,
-- which is why the tick can be a no-op rather than an error.
function M.setNames(entry)
    local out, seen = {}, {};
    local r = (type(entry) == 'table') and entry.rule or nil;
    local s = (type(r) == 'table') and r.set or nil;
    if type(s) == 'table' then
        for _, n in ipairs(s) do
            if type(n) == 'string' and n ~= '' and not seen[n] then
                seen[n] = true; out[#out + 1] = n;
            end
        end
    elseif type(s) == 'string' and s ~= '' then
        out[1] = s;
    end
    return out;
end

-- targets = { { name = 'BLM' | 'Solo', data = <parsed trigger model | nil>, err = <parse
-- error | nil>, source = <true for the one the rule came from> }, ... }
-- -> rows = { { name, state, err }, ... }, in a deterministic display order.
-- `data = nil` with no err means "no trigger file there yet" -> 'create'.
--
-- One classifier, both axes. A trigger file is addressed by (profile, job), so a copy
-- varies one of the two and the QUESTION is identical either way: what would landing
-- this rule there do? `order` (name -> rank, optional) puts a known list in its own
-- order -- jobs read in the game's order, not alphabetically -- and anything it does
-- not name sorts after, by name (profiles' JOB_ORDER pattern).
function M.rows(entry, targets, order)
    local out = {};
    for _, t in ipairs((type(targets) == 'table') and targets or {}) do
        if type(t) == 'table' and type(t.name) == 'string' and t.name ~= '' then
            local state;
            if t.source == true then state = 'source';
            elseif t.err ~= nil then state = 'unreadable';
            elseif type(t.data) ~= 'table' then state = 'create';
            elseif hasBp and bp.identicalExists(entry, t.data) then state = 'dup';
            else state = 'add'; end
            out[#out + 1] = { name = t.name, state = state, err = t.err };
        end
    end
    local rank = (type(order) == 'table') and order or {};
    table.sort(out, function(a, b)
        local ia, ib = rank[a.name], rank[b.name];
        if ia ~= nil and ib ~= nil then return ia < ib; end
        if ia ~= nil then return true; end
        if ib ~= nil then return false; end
        return a.name < b.name;
    end);
    return out;
end

-- What the "All" button ticks: everything writable that does NOT already hold an
-- identical rule. Henrik asked for the check by name ("where it also checks if it has
-- a similar rule already"), so the bulk button must not spend it -- one click across
-- 21 jobs is exactly where a silent duplicate would go unnoticed. A duplicate stays
-- reachable by ticking that row BY HAND: warn-but-allow, never warn-but-do-it-anyway.
function M.allNames(rows)
    local out = {};
    for _, r in ipairs((type(rows) == 'table') and rows or {}) do
        if type(r) == 'table' and M.copyable(r.state) and r.state ~= 'dup' then
            out[#out + 1] = r.name;
        end
    end
    return out;
end

-- How many rows the player has ticked that can actually be written, and how many of
-- those already hold an identical rule (the gold warning above the Copy button).
-- `marked` = a name -> truthy map.
function M.selection(rows, marked)
    local n, dups = 0, 0;
    for _, r in ipairs((type(rows) == 'table') and rows or {}) do
        if M.copyable(r.state) and (type(marked) == 'table') and marked[r.name] then
            n = n + 1;
            if r.state == 'dup' then dups = dups + 1; end
        end
    end
    return n, dups;
end

-- The stamp transform, one target's data in -> a NEW data table out (non-mutating and
-- detached, blueprintsmodel.stamp's contract). A missing file's `nil` starts an empty
-- job entry, which is what makes 'create' just another copy.
function M.applyTo(entry, data)
    if not hasBp then return data; end
    return bp.stamp(entry, (type(data) == 'table') and data or {});
end

-- Does this target already hold the rule? (The caller re-asks at WRITE time, because
-- the scan that built the rows may be seconds old and another session shares the disk.)
function M.holdsIdentical(entry, data)
    if not hasBp or type(data) ~= 'table' then return false; end
    return bp.identicalExists(entry, data);
end

local function join(list) table.sort(list); return table.concat(list, ', '); end

-- results = { { name, ok, dup, err }, ... } -> one status line, isErr. `where` names the
-- destination coordinate the copy varied ('Midcast rules in profile Default', 'WHM
-- Midcast'), so one receipt serves both axes.
-- Every outcome is NAMED: a copy that silently skipped a target reads as a copy that
-- worked everywhere, and the player would not find out until they switched to it.
function M.receipt(results, where)
    local done, dups, failed = {}, {}, {};
    -- Sets brought along ("include the set if it isn't there"): counted, and any
    -- that could not be brought named -- a rule that landed pointing at a set that
    -- did not follow it is the exact dud this option exists to prevent, so the
    -- receipt must not report the rule as copied and stay quiet about the set.
    local setsOk, setsBad = 0, {};
    for _, r in ipairs((type(results) == 'table') and results or {}) do
        if type(r) == 'table' and type(r.name) == 'string' then
            if r.ok ~= true then failed[#failed + 1] = r.name .. ' (' .. tostring(r.err or 'unknown error') .. ')';
            elseif r.dup == true then dups[#dups + 1] = r.name;
            else done[#done + 1] = r.name; end
            setsOk = setsOk + (tonumber(r.setsOk) or 0);
            for _, s in ipairs((type(r.setsBad) == 'table') and r.setsBad or {}) do
                setsBad[#setsBad + 1] = tostring(s);
            end
        end
    end
    if #done == 0 and #dups == 0 and #failed == 0 then
        return 'Nothing copied -- tick at least one destination.', true;
    end
    -- `where` leads, so the coordinate is stated even when EVERY destination failed
    -- (it used to ride the "Copied to" clause, which an all-failed copy never has --
    -- and "which list did I just fire?" is exactly the question then).
    local parts = {};
    if #done > 0 then parts[#parts + 1] = 'Copied to ' .. join(done) .. '.'; end
    if #dups > 0 then
        parts[#parts + 1] = string.format('%d already had an identical rule -- copied anyway: %s.', #dups, join(dups));
    end
    if #failed > 0 then parts[#parts + 1] = 'FAILED: ' .. join(failed) .. '.'; end
    if setsOk > 0 then
        parts[#parts + 1] = string.format('Brought %d missing set%s along.', setsOk, (setsOk == 1) and '' or 's');
    end
    if #setsBad > 0 then parts[#parts + 1] = 'Sets NOT brought: ' .. join(setsBad) .. '.'; end
    return tostring(where or '?') .. ': ' .. table.concat(parts, ' '), (#failed > 0 or #setsBad > 0);
end

return M;
