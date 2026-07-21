--[[
    dlac/setimport.lua -- the pure "Copy from static" transform (issue #15, ADR 0008).

    "Copy from static" fills the dynamic set the player currently has selected with a
    chosen static (non-Dynamic) set's slots, keeping the target set's name. The UI shell
    (refuse-without-target, overwrite confirmation, chat warnings) lives in gearui; the
    part with no ImGui in it lives here so the headless suite can pin the behaviour:

      importStaticSet(staticSet, slotLabels, resolve) ->
        { working = { slotLabel -> { entry, ... } }, notBestFirst = { slotLabel, ... },
          slotCount = <#slots with >=1 resolved candidate> }

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

-- staticSet  : the source set table (slotLabel -> element | ordered list of elements)
-- slotLabels : ordered array of slot descriptors -- either { label = 'Main', ... } (the
--              Sets tab's EQUIP_SLOTS) or plain label strings
-- resolve    : function(elem) -> working entry ({ rec = { Level = N, ... }, ... }) or nil
--              (nil = unowned/unknown -> the candidate is dropped)
function M.importStaticSet(staticSet, slotLabels, resolve)
    local working, notBestFirst, slotCount = {}, {}, 0;
    if type(staticSet) ~= 'table' or type(slotLabels) ~= 'table'
       or type(resolve) ~= 'function' then
        return { working = working, notBestFirst = notBestFirst, slotCount = 0 };
    end
    for _, sl in ipairs(slotLabels) do
        local label = (type(sl) == 'table') and sl.label or sl;
        local slotVal = (label ~= nil) and staticSet[label] or nil;
        if slotVal ~= nil then
            -- List (_Priority / Dynamic) vs single element (a plain static slot): a
            -- gear.lua record is a table with no [1], so { slotVal } wraps it as a
            -- one-candidate list. Either way the ORDER is carried verbatim.
            local elems = (type(slotVal) == 'table' and slotVal[1] ~= nil) and slotVal or { slotVal };
            local items = {};
            for _, elem in ipairs(elems) do
                local it = resolve(elem);
                if it ~= nil then items[#items + 1] = it; end
            end
            if #items > 0 then
                working[label] = items;
                slotCount = slotCount + 1;
                if not M.isBestFirst(items) then notBestFirst[#notBestFirst + 1] = label; end
            end
        end
    end
    return { working = working, notBestFirst = notBestFirst, slotCount = slotCount };
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

return M;
