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

return M;
