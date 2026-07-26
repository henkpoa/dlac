--[[
    dlac/triggermodel.lua -- the pure Trigger edit-model core: raw trigger-file table ->
    the Triggers-tab edit model (canonical handler keys, lowercased condition keys).

    THE WIPE CONTRACT (why this module exists): Commit serializes the WHOLE model back
    to the file via dispatch.serializeTriggers, so any section this translation does not
    carry gets silently erased on the next Commit -- that bug shipped once (the
    SetOptions/Modes wipe). Every section the serializer can emit (handler rule lists,
    Modes, Groups) must survive fromRaw; tests TM* pin the full round-trip headless,
    which the old in-triggersui copy of this code never had.

    Pure and injected like groupsmodel: no ImGui, no Ashita, no file IO. The one
    dispatch dependency -- canonEvent, the handler-key canonicalizer -- is passed IN
    (triggersui hands over dispatch.canonEvent), so this module never drags the engine
    in and the headless suite drives it with the real function. Groups sanitizing stays
    delegated to groupsmodel (its tested home, tests TGM*); guarded so a missing module
    only loses the feature, exactly as triggersui behaved.

    (Legacy SetOptions sections are dropped deliberately: automation is a virtual SLOT
    entry now -- dlac:AutoStaff / dlac:AutoObi inside the set, ADR 0004 4th revision.)

    Addon-state only -- never seeded into LAC.
]]--

local M = {};

local _gmok, gm = pcall(require, 'dlac\\gear\\groupsmodel');
local hasGroups = _gmok and type(gm) == 'table';

-- The trigger-cases version guard key (issue #126): a serialization artifact
-- (dispatch stamps it into the body of any rule with a `cases` list). Stripped on
-- load so it never re-emits stale, then re-stamped by the serializer when cases
-- are present. Bare local -- this pure module drags in nothing from the engine.
local CASES_GUARD = 'hascases';

-- One raw condition map -> lowercased-key copy, guard stripped.
local function condMap(map)
    local out = {};
    for ck, cv in pairs(map or {}) do
        local lk = string.lower(tostring(ck));
        if lk ~= CASES_GUARD then out[lk] = cv; end
    end
    return out;
end

-- Raw whenAny -> list of lowercased condition maps, empties dropped.
local function anyList(raw)
    local out = nil;
    if type(raw) == 'table' then
        for _, e in ipairs(raw) do
            if type(e) == 'table' then
                local ne = condMap(e);
                if next(ne) ~= nil then out = out or {}; out[#out + 1] = ne; end
            end
        end
    end
    return out;
end

-- Raw trigger-file table -> edit model. `canonEvent` maps a file key to the canonical
-- handler name (dispatch.canonEvent) or nil; without it the handler sections are
-- unreachable (dropped), but Modes/Groups still carry -- same degraded behavior the
-- Triggers tab always had when the dispatch module was unavailable.
function M.fromRaw(raw, canonEvent)
    local data = {};
    if type(raw) ~= 'table' then return data; end
    local canon = (type(canonEvent) == 'function') and canonEvent or nil;
    for k, v in pairs(raw) do
        local ev = (canon ~= nil) and canon(k) or nil;
        if ev ~= nil and type(v) == 'table' then
            local list = data[ev] or {};
            for _, r in ipairs(v) do
                if type(r) == 'table' and type(r.when) == 'table'
                   and (r.set ~= nil or type(r.equip) == 'table') then
                    local when = condMap(r.when);
                    -- v54 OR group: carried through the model or Commit WIPES it
                    -- (the SetOptions/Modes lesson).
                    local whenAny = anyList(r.whenAny or r.whenany);
                    -- cases (issue #126): the second tier, carried VERBATIM or
                    -- Commit WIPES it (the same SetOptions/Modes wipe lesson). The
                    -- engine's normalize is the validator; the model just mirrors
                    -- the file's shape so a round-trip preserves it.
                    local cases = nil;
                    if type(r.cases) == 'table' then
                        for _, c in ipairs(r.cases) do
                            if type(c) == 'table' then
                                local op = (c.op == '|' or c.operator == '|') and '|'
                                        or ((c.op == '&' or c.operator == '&') and '&' or nil);
                                if op ~= nil then
                                    local cw = condMap(c.when);
                                    local cwAny = anyList(c.whenAny or c.whenany);
                                    if next(cw) ~= nil or (cwAny ~= nil and #cwAny > 0) then
                                        cases = cases or {};
                                        cases[#cases + 1] = { op = op, when = cw, whenAny = cwAny };
                                    end
                                end
                            end
                        end
                    end
                    -- set: 'Name' or an ORDERED list (multi-set rule); the model
                    -- mirrors the file (string when single, array when several).
                    local sv = nil;
                    if type(r.set) == 'table' then
                        for _, sn in ipairs(r.set) do
                            if type(sn) == 'string' and sn ~= '' then sv = sv or {}; sv[#sv + 1] = sn; end
                        end
                        if sv ~= nil and #sv == 1 then sv = sv[1]; end
                    elseif r.set ~= nil then
                        sv = tostring(r.set);
                    end
                    list[#list + 1] = {
                        when = when,
                        whenAny = whenAny,
                        cases = cases,
                        set = sv,
                        equip = (type(r.equip) == 'table') and r.equip or nil,
                        priority = tonumber(r.priority),
                    };
                end
            end
            data[ev] = list;
        end
    end
    -- Modes section (cycle definitions + keybinds): carried through so Commit
    -- round-trips it (same lesson as the SetOptions wipe).
    local md = raw.Modes or raw.modes;
    if type(md) == 'table' then
        local copy = {};
        for nm, def in pairs(md) do
            if type(nm) == 'string' and type(def) == 'table' then
                local e = {};
                local src = (type(def.values) == 'table') and def.values or def;
                for _, v in ipairs(src) do
                    if type(v) == 'string' then e.values = e.values or {}; e.values[#e.values + 1] = v; end
                end
                if type(def.bind) == 'string' then e.bind = def.bind; end
                -- an EMPTY e is a bare toggle -- a real definition (dropping
                -- it un-listed plain UI-created toggles, 2026-07-20)
                copy[nm] = e;
            end
        end
        if next(copy) ~= nil then data.Modes = copy; end
    end
    -- Groups section (ADR 0009): named action-name lists per Job entry, beside
    -- Modes. Carried through so Commit round-trips it (same SetOptions/Modes wipe
    -- lesson). The sanitize lives in groupsmodel so both halves share one home.
    if hasGroups then
        local gr = gm.fromRaw(raw);
        if next(gr) ~= nil then data.Groups = gr; end
    end
    return data;
end

return M;
