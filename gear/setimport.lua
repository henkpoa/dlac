--[[
    dlac/setimport.lua -- the pure "Copy from static" transform (issue #15, ADR 0008).

    "Copy from static" fills the dynamic set the player currently has selected with a
    chosen static (non-Dynamic) set's slots, keeping the target set's name. The UI shell
    (refuse-without-target, overwrite confirmation, chat warnings) lives in gearui; the
    part with no ImGui in it lives here so the headless suite can pin the behaviour:

      importStaticSet(staticSet, slotLabels, resolve) ->
        { working = { slotLabel -> { entry, ... } }, notBestFirst = { slotLabel, ... },
          slotCount = <#slots with >=1 resolved candidate>,
          missing = { 'Item Name', ... }, missingCount = <#candidates dropped> }

    MISSING GEAR IS NEVER A REFUSAL (Henrik 2026-07-31). A candidate the resolver
    cannot place is skipped and the set imports without it -- that was always true
    per-candidate, but it was SILENT, and a set where nothing resolved used to be
    refused outright ("nothing to copy"), which reads as "the import is broken"
    when the honest answer is "you don't own this gear yet". So the drops are now
    COUNTED and NAMED: `missing` is the distinct item names in first-seen order
    (nil for a candidate too broken to name -- a MISSING sentinel has no readable
    Name), `missingCount` is every dropped candidate including those. The caller
    imports regardless and says what was left out.

    FULL-REPLACE: only slots the static defines (and that resolve to >=1 owned/known
    candidate) appear in `working`; every other slot is absent, so the caller drops the
    rest. Candidate ORDER is carried verbatim -- an ordered _Priority list keeps its order
    (ADR 0008: dlac keeps its highest-item-Level pick rather than reproducing LAC's
    first-in-list). `notBestFirst` names the slots whose candidate order is NOT best-first
    (highest item-Level first) -- the one case dlac's selection diverges from LAC's, which
    the caller surfaces as a per-slot warning. A level-descending list imports silently.

    Addon-state only -- never seeded into LAC. No Ashita, no ImGui, no file I/O: the
    resolver is injected (gearui passes its resolveSetItem; tests pass a stub over owned
    records), which is what keeps this a pure function.
]]--

local M = {};

-- Best-first = the candidate item-Levels are non-increasing (highest first). Only
-- entries with a numeric rec.Level participate; a virtual entry (dlac:*, Level 0, taken
-- outright at equip time) is skipped rather than treated as a Level-0 candidate, so it
-- never spuriously trips the warning. Equal Levels keep list order (ties, not a
-- divergence). A single-candidate (or empty) list is trivially best-first.
function M.isBestFirst(items)
    if type(items) ~= 'table' then return true; end
    local prev = nil;
    for _, it in ipairs(items) do
        local rec = it and it.rec;
        if type(rec) == 'table' and rec.Virtual ~= true and type(rec.Level) == 'number' then
            if prev ~= nil and rec.Level > prev then return false; end
            prev = rec.Level;
        end
    end
    return true;
end

-- The player-facing NAME of a set element, or nil when it has none. Every source
-- shape is read TYPED, never merely non-nil: profilesets' MISSING sentinel and
-- its require STUB answer EVERY key with themselves by construction, so
-- `elem.Name` on one is a TABLE, not a string -- the same lesson resolveSetItem
-- learned when string.lower() on a sentinel took a whole set down.
local function elemName(elem)
    if type(elem) == 'string' then return elem; end
    if type(elem) ~= 'table' then return nil; end
    if type(elem.Name) == 'string' then return elem.Name; end
    local g = elem.gear;                    -- { gear = ref, minLevel, ... } wrapper
    if type(g) == 'string' then return g; end
    if type(g) == 'table' and type(g.Name) == 'string' then return g.Name; end
    return nil;
end
M.elemName = elemName;

-- staticSet  : the source set table (slotLabel -> element | ordered list of elements)
-- slotLabels : ordered array of slot descriptors -- either { label = 'Main', ... } (the
--              Sets tab's EQUIP_SLOTS) or plain label strings
-- resolve    : function(elem) -> working entry ({ rec = { Level = N, ... }, ... }) or nil
--              (nil = unowned/unknown -> the candidate is dropped, counted and named)
function M.importStaticSet(staticSet, slotLabels, resolve)
    local working, notBestFirst, slotCount = {}, {}, 0;
    local missing, missingSeen, missingCount = {}, {}, 0;
    local function dropped(elem)
        missingCount = missingCount + 1;
        local nm = elemName(elem);
        if nm == nil then return; end               -- unnameable: counted, not listed
        local k = string.lower(nm);
        if missingSeen[k] then return; end          -- distinct names, first-seen order
        missingSeen[k] = true;
        missing[#missing + 1] = nm;
    end
    if type(staticSet) ~= 'table' or type(slotLabels) ~= 'table'
       or type(resolve) ~= 'function' then
        return { working = working, notBestFirst = notBestFirst, slotCount = 0,
                 missing = missing, missingCount = 0 };
    end
    for _, sl in ipairs(slotLabels) do
        local label = (type(sl) == 'table') and sl.label or sl;
        local slotVal = (label ~= nil) and staticSet[label] or nil;
        -- An EMPTY list is "this slot has no candidates", not a candidate that
        -- failed -- wrapping it as { {} } below would resolve to nil and inflate
        -- the missing count with a piece nobody ever named. A gear record always
        -- has keys, so `next` separates the two safely.
        if type(slotVal) == 'table' and next(slotVal) == nil then slotVal = nil; end
        if slotVal ~= nil then
            -- List (_Priority / Dynamic) vs single element (a plain static slot): a
            -- gear.lua record is a table with no [1], so { slotVal } wraps it as a
            -- one-candidate list. Either way the ORDER is carried verbatim.
            local elems = (type(slotVal) == 'table' and slotVal[1] ~= nil) and slotVal or { slotVal };
            local items = {};
            for _, elem in ipairs(elems) do
                -- Per CANDIDATE, not per set: an import reads files nobody has
                -- validated in years, and one entry the resolver chokes on used to
                -- take the whole set with it -- reported as "no owned/known gear",
                -- indistinguishable from an empty set (hard rule 12). A candidate
                -- that cannot be resolved is skipped, counted and named.
                local ok, it = pcall(resolve, elem);
                if ok and it ~= nil then items[#items + 1] = it;
                else dropped(elem); end
            end
            if #items > 0 then
                working[label] = items;
                slotCount = slotCount + 1;
                if not M.isBestFirst(items) then notBestFirst[#notBestFirst + 1] = label; end
            end
        end
    end
    return { working = working, notBestFirst = notBestFirst, slotCount = slotCount,
             missing = missing, missingCount = missingCount };
end

-- The missing list as ONE player-facing clause, capped so a set of 15 unowned
-- pieces does not print a paragraph. nil when nothing was dropped.
--   missing      : distinct names (importStaticSet's `missing`)
--   missingCount : total dropped candidates, names or not
function M.missingNote(missing, missingCount, cap)
    local n = tonumber(missingCount) or 0;
    if n <= 0 then return nil; end
    cap = tonumber(cap) or 10;
    local names = (type(missing) == 'table') and missing or {};
    if #names == 0 then
        return string.format('%d piece%s skipped -- not in your gear.lua', n, (n == 1) and '' or 's');
    end
    local shown = {};
    for i = 1, math.min(#names, cap) do shown[i] = names[i]; end
    local tail = (#names > cap) and string.format(' (+%d more)', #names - cap) or '';
    return string.format('%d piece%s skipped -- you do not own: %s%s',
        n, (n == 1) and '' or 's', table.concat(shown, ', '), tail);
end

-- The "Copy from" picker's LEGACY column. One old FFXI-LAC job file holds BOTH
-- kinds of source: LuaAshitacast's static sets at the root, and dlac's own
-- `sets.Dynamic` block from before the profile storage layer -- and the same name
-- can appear in both (a static you later rebuilt as a Dynamic set, in the file
-- that predates the split). Henrik's ruling 2026-07-28: the DYNAMIC one wins, so
-- such a name imports as what it grew INTO, never as the static it grew out of.
-- Case-insensitive, like every other set-name rule here (the Sets tab compares
-- via string.lower), and sorted by name so the picker reads alphabetically.
--
-- ASHITACAST (acNames, 2026-07-31) is a THIRD kind and gets its OWN name space:
-- it comes from a different engine's file entirely (config\legacyac\<Char>_<JOB>
-- .xml), so an "Idle" there and an "Idle" in the old FFXI-LAC job file are two
-- unrelated sets that merely share a name -- deduping them would silently hide
-- one. The dedupe that DOES apply above exists because those two sources are the
-- same file. Ashitacast names dedupe only against each other.
--
--   staticNames / lacNames / acNames : arrays of set-name strings
--   -> ordered array of { name = 'Idle', kind = 'lac'|'static'|'ac' }
function M.mergeLegacySources(staticNames, lacNames, acNames)
    local out = {};
    local function add(names, kind, taken)
        if type(names) ~= 'table' then return; end
        for _, nm in ipairs(names) do
            local s = tostring(nm);
            local lk = string.lower(s);
            if not taken[lk] then
                taken[lk] = true;
                out[#out + 1] = { name = s, kind = kind };
            end
        end
    end
    local jobFileNames = {};       -- the ONE old job file's name space
    add(lacNames, 'lac', jobFileNames);          -- dynamics claim their names first...
    add(staticNames, 'static', jobFileNames);    -- ...statics only fill what is left
    add(acNames, 'ac', {});                      -- a different file: its own name space
    table.sort(out, function(a, b)
        local la, lb = string.lower(a.name), string.lower(b.name);
        if la ~= lb then return la < lb; end
        if a.name ~= b.name then return a.name < b.name; end
        return a.kind < b.kind;    -- one spelling, two files: still a total order
    end);
    return out;
end

-- "Copy from" -> "New set(s)" mode: pick the DESTINATION name for each source in a
-- migrate-many batch. Each new set is kept under its SOURCE name; a name that already
-- exists among the dynamic sets -- OR one already claimed earlier in this same batch --
-- gains a '_Copy' suffix (then '_Copy2', '_Copy3', ... if that too is taken) so an import
-- is never silently merged into an existing set. Case-insensitive, matching the Sets tab's
-- own duplicate rule (rename compares via string.lower). Pure: no ImGui, no file I/O.
--
--   sources  : ordered array of { name = 'Idle', kind = 'static'|'dynamic' } (or bare
--              name strings) -- ORDER is preserved, so in-batch collisions resolve
--              top-to-bottom, matching what the picker shows.
--   existing : array of the current dynamic set-name strings
--   -> ordered array of { name, kind, finalName, renamed = <bool> }
function M.resolveNewSetNames(sources, existing)
    local taken = {};   -- lowercased name -> true
    if type(existing) == 'table' then
        for _, nm in ipairs(existing) do taken[string.lower(tostring(nm))] = true; end
    end
    local out = {};
    if type(sources) ~= 'table' then return out; end
    for _, s in ipairs(sources) do
        local base = tostring((type(s) == 'table') and s.name or s);
        local final, renamed = base, false;
        if taken[string.lower(final)] then
            renamed = true;
            final = base .. '_Copy';
            local n = 2;
            while taken[string.lower(final)] do
                final = base .. '_Copy' .. n;
                n = n + 1;
            end
        end
        taken[string.lower(final)] = true;
        out[#out + 1] = {
            name = base,
            kind = (type(s) == 'table') and s.kind or nil,
            finalName = final,
            renamed = renamed,
        };
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- "Copy to" (Henrik 2026-10-14: "copy that set to other jobs ... so it's easy to
-- bring general sets to every job you have"). ONE set, written into each job the
-- player ticks, under the same name. The shell -- the job list, the writes, the
-- chat lines -- is ui\setcopyto; what has no ImGui and no file I/O lives here.
-- ---------------------------------------------------------------------------

-- The slot label of a slot descriptor ({ label = 'Main' } or a bare string).
local function labelOf(sl) return (type(sl) == 'table') and sl.label or sl; end

-- The set as ONE target job receives it. A piece that job cannot wear is LEFT OUT
-- and named: copied as it is, it would sit in the set as a candidate the flatten
-- still picks (BuildDynamicSets ranks by level and never asks about jobs) and the
-- server then refuses -- the slot keeps whatever was worn, and nothing says why.
-- Copy from's law for gear you do not own, applied to gear the job cannot wear:
-- never a refusal, always said.
--   working    : the Sets tab's working model (slotLabel -> { entry, ... })
--   slotLabels : the slot order to walk (EQUIP_SLOTS, or plain label strings)
--   canWear    : function(rec) -> bool, the TARGET job's gate. A throw or a
--                non-false answer KEEPS the piece -- fail open, the way
--                jobCanEquip treats a record with no job list.
-- Virtual entries (dlac:AutoStaff, dlac:AutoObi, ...) are always kept: the engine
-- resolves them for the job it is on, at equip time. Candidate ORDER is kept, and
-- a slot left with nothing is absent.
-- -> { working, dropped = { 'Name', ... } (distinct, first seen first),
--      droppedCount = <every entry left out>, slotCount = <slots kept> }
function M.workingForJob(working, slotLabels, canWear)
    local out, dropped, seen, droppedCount, slotCount = {}, {}, {}, 0, 0;
    if type(working) ~= 'table' or type(slotLabels) ~= 'table' then
        return { working = out, dropped = dropped, droppedCount = 0, slotCount = 0 };
    end
    for _, sl in ipairs(slotLabels) do
        local label = labelOf(sl);
        local list = (label ~= nil) and working[label] or nil;
        if type(list) == 'table' then
            local kept = {};
            for _, it in ipairs(list) do
                local rec = (type(it) == 'table') and it.rec or nil;
                local keep = true;
                if type(rec) == 'table' and rec.Virtual ~= true and type(canWear) == 'function' then
                    local ok, yes = pcall(canWear, rec);
                    keep = not (ok and yes == false);
                end
                if keep then
                    kept[#kept + 1] = it;
                else
                    droppedCount = droppedCount + 1;
                    local nm = (type(rec.Name) == 'string') and rec.Name or nil;
                    if nm ~= nil and not seen[string.lower(nm)] then
                        seen[string.lower(nm)] = true;
                        dropped[#dropped + 1] = nm;
                    end
                end
            end
            if #kept > 0 then
                out[label] = kept;
                slotCount = slotCount + 1;
            end
        end
    end
    return { working = out, dropped = dropped, droppedCount = droppedCount, slotCount = slotCount };
end

-- The Mode gates a working set carries: the distinct gate strings ('DT',
-- 'Weapon:Melee'), first seen first, and how many entries carry one. Modes live
-- PER JOB ENTRY, so a gated piece copied to a job without that Mode never equips
-- there -- the copy says so instead of guessing which jobs have which Modes.
-- An entry's `mode` is one string or a list of them.
-- -> gates = { 'DT', ... }, count
function M.modeGates(working, slotLabels)
    local gates, seen, count = {}, {}, 0;
    if type(working) ~= 'table' or type(slotLabels) ~= 'table' then return gates, 0; end
    local function add(m)
        local s = tostring(m);
        if s ~= '' and not seen[s] then seen[s] = true; gates[#gates + 1] = s; end
    end
    for _, sl in ipairs(slotLabels) do
        local list = working[labelOf(sl)];
        if type(list) == 'table' then
            for _, it in ipairs(list) do
                local m = (type(it) == 'table') and it.mode or nil;
                if type(m) == 'string' and m ~= '' then
                    count = count + 1; add(m);
                elseif type(m) == 'table' and m[1] ~= nil then
                    count = count + 1;
                    for _, x in ipairs(m) do add(x); end
                end
            end
        end
    end
    return gates, count;
end

-- Every job's left-out pieces pooled into ONE chat clause: each piece once, with
-- the jobs it was left out of, in the order the jobs were written. Twenty jobs
-- must not print twenty lines.
--   perJob : ordered { { job = 'WAR', dropped = { 'Name', ... } }, ... }
--   cap    : pieces named before '(+N more)' (default 8)
-- -> 'Hlr. Bliaut +1 (WAR, MNK), Cobra Cape (THF)', <distinct pieces>
--    or nil, 0 when nothing was left out anywhere
function M.copyToDropNote(perJob, cap)
    cap = tonumber(cap) or 8;
    local order, jobsOf = {}, {};
    for _, pj in ipairs((type(perJob) == 'table') and perJob or {}) do
        for _, nm in ipairs((type(pj) == 'table' and type(pj.dropped) == 'table') and pj.dropped or {}) do
            local s = tostring(nm);
            if jobsOf[s] == nil then jobsOf[s] = {}; order[#order + 1] = s; end
            local js = jobsOf[s];
            js[#js + 1] = tostring(pj.job);
        end
    end
    if #order == 0 then return nil, 0; end
    local parts = {};
    for i = 1, math.min(#order, cap) do
        parts[i] = string.format('%s (%s)', order[i], table.concat(jobsOf[order[i]], ', '));
    end
    local tail = (#order > cap) and string.format(' (+%d more)', #order - cap) or '';
    return table.concat(parts, ', ') .. tail, #order;
end

-- The receipt for the Sets tab's status line.
--   setName : the copied set
--   results : ordered { { job, ok, replaced, empty, err }, ... } -- one per ticked job
--   leftOut : distinct pieces left out anywhere (copyToDropNote's second value)
--   dirty   : the copy carried edits the source set has not committed yet
-- -> text, isErr (an error only when NOTHING landed)
function M.copyToReceipt(setName, results, leftOut, dirty)
    local okJobs, replaced, empty, failed = {}, {}, {}, {};
    for _, r in ipairs((type(results) == 'table') and results or {}) do
        if r.ok then
            okJobs[#okJobs + 1] = tostring(r.job);
            if r.replaced then replaced[#replaced + 1] = tostring(r.job); end
            if r.empty then empty[#empty + 1] = tostring(r.job); end
        else
            failed[#failed + 1] = string.format('%s (%s)', tostring(r.job), tostring(r.err or 'unknown'));
        end
    end
    local name = tostring(setName);
    local text;
    if #okJobs == 0 then
        text = string.format('Nothing copied -- "%s" could not be written anywhere.', name);
    else
        text = string.format('Copied "%s" to %s.', name, table.concat(okJobs, ', '));
    end
    if #replaced > 0 then
        text = text .. string.format('  Replaced the "%s" already on %s (backed up first).', name, table.concat(replaced, ', '));
    end
    leftOut = tonumber(leftOut) or 0;
    if leftOut > 0 then
        text = text .. string.format('  %d piece%s left out where the job cannot wear %s -- see chat.',
            leftOut, (leftOut == 1) and '' or 's', (leftOut == 1) and 'it' or 'them');
    end
    if #empty > 0 then
        text = text .. string.format('  EMPTY on %s: none of it is wearable there.', table.concat(empty, ', '));
    end
    if dirty == true and #okJobs > 0 then
        text = text .. '  Your uncommitted edits went with it.';
    end
    if #failed > 0 then
        text = text .. '  FAILED: ' .. table.concat(failed, '; ') .. '.';
    end
    return text, (#okJobs == 0);
end

return M;
