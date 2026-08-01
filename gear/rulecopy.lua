--[[
    dlac/rulecopy.lua -- the pure core behind "copy this rule to..." : one Trigger,
    copied into the SAME job entry of other Profiles of this character.

    The sibling of a Blueprint, and deliberately not the same thing. A Blueprint is a
    LIBRARY entry -- job-independent, kept forever, stamped when you want it. This is a
    one-shot SPREAD: the rule you are looking at, landed in the profiles you tick, right
    now. Henrik, 2026-08-02: "I know we have blue prints, but would be nice if that would
    open up a window where you can mark all or any of the dlac profiles you want to copy
    that trigger rule to."

    The copy travels as a Blueprint ENTRY ({ name, handler, rule }) on purpose: capture,
    detach, identical-rule detection and the stamp transform are all already written and
    pinned (blueprintsmodel, tests TGB*), and reusing them is what guarantees a copied
    rule is byte-for-byte the rule a Blueprint stamp would produce. This module adds the
    only thing that was missing -- the ANSWER PER TARGET: what would copying do to that
    profile, and what did it do.

    Job axis: none. A profile holds one trigger file PER JOB, and the rule being copied
    belongs to the job the tab is on, so it lands in <that job>.lua in every target. The
    cross-JOB move is what a Blueprint is for; this is the cross-PROFILE one.

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
--   'source'     the profile the rule already lives in (the active one) -- never a target
--   'unreadable' its trigger file exists but does not parse -- REFUSED (never overwritten)
--   'create'     no trigger file for this job yet -- one is written
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

-- The rule in its ONE canonical spelling (the serializer's form) -- what the popup
-- shows so the player can see exactly what is about to travel. '' when unavailable.
function M.ruleText(entry, prettyKey)
    if not hasBp or type(entry) ~= 'table' then return ''; end
    local out = '';
    pcall(function() out = bp.emitRule(entry.rule, prettyKey); end);
    return out;
end

-- targets = { { name = 'Solo', data = <parsed trigger model | nil>, err = <parse error |
-- nil>, source = <true for the profile the rule came from> }, ... }
-- -> rows = { { name, state, err }, ... }, sorted by name (deterministic display).
-- `data = nil` with no err means "no trigger file for this job yet" -> 'create'.
function M.rows(entry, targets)
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
    table.sort(out, function(a, b) return a.name < b.name; end);
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

-- results = { { name, ok, dup, err }, ... } -> one status line, isErr.
-- Every outcome is NAMED: a copy that silently skipped a profile reads as a copy that
-- worked everywhere, and the player would not find out until they switched to it.
function M.receipt(results, job, handler)
    local done, dups, failed = {}, {}, {};
    for _, r in ipairs((type(results) == 'table') and results or {}) do
        if type(r) == 'table' and type(r.name) == 'string' then
            if r.ok ~= true then failed[#failed + 1] = r.name .. ' (' .. tostring(r.err or 'unknown error') .. ')';
            elseif r.dup == true then dups[#dups + 1] = r.name;
            else done[#done + 1] = r.name; end
        end
    end
    if #done == 0 and #dups == 0 and #failed == 0 then
        return 'Nothing copied -- tick at least one profile.', true;
    end
    local where = string.format(' (%s %s)', tostring(job or '?'), tostring(handler or '?'));
    local parts = {};
    if #done > 0 then parts[#parts + 1] = 'Copied to ' .. join(done) .. where .. '.'; end
    if #dups > 0 then
        parts[#parts + 1] = string.format('%d already had an identical rule -- copied anyway: %s.', #dups, join(dups));
    end
    if #failed > 0 then parts[#parts + 1] = 'FAILED: ' .. join(failed) .. '.'; end
    return table.concat(parts, ' '), (#failed > 0);
end

return M;
