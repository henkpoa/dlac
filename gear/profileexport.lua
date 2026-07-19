--[[
    dlac/profileexport.lua -- the SELECTIVE job export's payload builder (Henrik
    2026-07-19: "when we click export... open a box, to select what we want").

    The Profiles menu's export form collects choices; this module turns them into
    the payload texts profiles.exportJob bundles into the ONE existing file format
    (job-export v1 -- new keys are optional, old readers ignore them). No new file
    formats and no new serializers: every transform routes through the established
    reader/writer for that data --

      sets w/o equipment  profiles.frameSetsText + setmanager.renderKey
                          (set names survive as EMPTY shells -- an empty set is a
                          legal trigger target; the receiver auto-builds their own
                          gear, which rarely aligns between characters anyway)
      triggers filtering  dispatch.readTriggersRaw -> drop unselected sections ->
                          dispatch.serializeTriggers (the wipe-contract serializer)
      stat weights        gearoptim.renderJobWeightsTextAt (the gearweights
                          renderer, filtered to '<JOB>|...' keys)

      buildPayloads(charFolder, profName, job, opts)
          -> { sets?, triggers?, lockstyles?, weights? } | nil, why
      opts = { sets, equipment, triggers, groups, modes, weights, lockstyles }
             (booleans; weights additionally requires opts.sets -- enforced by the
              form's greying AND here, belt and suspenders)

    filterTriggersRaw and stripEquipment are exposed pure for the headless suite.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local prof     = try('dlac\\profiles');
local dispatch = try('dlac\\dispatch');
local setmgr   = try('dlac\\gear\\setmanager');
local optim    = try('dlac\\gear\\gearoptim');

local function readFile(p)
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end

-- Sandbox-run a sets-file text and return its table (the hardened STUB-env
-- pattern of profilesets.sandboxSets: gear refs resolve to a self-indexing
-- stub, unknown globals too, nothing real is reachable). nil on any failure.
local function sandboxRun(text)
    local STUB; STUB = setmetatable({}, {
        __index = function() return STUB; end,
        __call = function() return STUB; end,
        __concat = function() return ''; end,
        __tostring = function() return ''; end,
    });
    local env = setmetatable({}, {
        __index = function() return STUB; end,
        __newindex = function(t, k, v) rawset(t, k, v); end,
    });
    local chunk;
    if setfenv ~= nil then                               -- LuaJIT / 5.1
        chunk = (loadstring or load)(text, 'dlac-export-sets');
        if chunk == nil then return nil; end
        setfenv(chunk, env);
    else                                                 -- 5.2+ (headless tests)
        chunk = load(text, 'dlac-export-sets', 't', env);
        if chunk == nil then return nil; end
    end
    local ok, res = pcall(chunk);
    if not ok then return nil; end
    return res;
end

-- Sets file text -> the same sets as EMPTY shells (names only, no gear),
-- framed exactly like every profile sets file. Pure given the text.
function M.stripEquipment(setsText)
    if prof == nil or setmgr == nil then return nil, 'profiles/setmanager unavailable'; end
    local res = sandboxRun(setsText);
    local dyn = (type(res) == 'table') and res.Dynamic or nil;
    if type(dyn) ~= 'table' then return nil, 'no sets.Dynamic block in the sets file'; end
    local names = {};
    for nm in pairs(dyn) do
        if type(nm) == 'string' and nm ~= '' then names[#names + 1] = nm; end
    end
    table.sort(names);
    local L = { 'Dynamic = {' };
    for _, nm in ipairs(names) do
        L[#L + 1] = '        ' .. setmgr.renderKey(nm) .. ' = {},';
    end
    L[#L + 1] = '    }';
    return prof.frameSetsText(table.concat(L, '\n'));
end

-- Raw trigger-file table -> only the selected sections, handler keys
-- canonicalized (defensive: the file is GUI-written, but a hand-edit must
-- filter correctly or not at all). Returns out, entryCount.
function M.filterTriggersRaw(raw, keep, canonEvent)
    local out, n = {}, 0;
    if type(raw) ~= 'table' then return out, 0; end
    if keep.triggers then
        for k, v in pairs(raw) do
            local ev = (type(canonEvent) == 'function') and canonEvent(k) or nil;
            if ev ~= nil and type(v) == 'table' and #v > 0 then
                out[ev] = v;
                n = n + #v;
            end
        end
    end
    if keep.groups then
        local gr = raw.Groups or raw.groups;
        if type(gr) == 'table' and next(gr) ~= nil then out.Groups = gr; n = n + 1; end
    end
    if keep.modes then
        local md = raw.Modes or raw.modes;
        if type(md) == 'table' and next(md) ~= nil then out.Modes = md; n = n + 1; end
    end
    return out, n;
end

-- ---------------------------------------------------------------------------
-- Dependency analysis (Henrik 2026-07-19 round 2): a rule with a dangling
-- reference never fires on the receiver -- a `group`/`mode` condition matches
-- against nothing (groupMatch/modeActive return false), a `set = 'Name'`
-- action points at a set that isn't there, and a mode-gated set rung goes
-- inert. No crash, just silent dead data. The export form uses these to
-- DISABLE a selection that would ship such dead references.
--
-- A trigger with an EMPTY condition (fires on anything) still depends on its
-- SET: that is the whole point of the rule (Henrik). Set NAMES travel even as
-- empty shells, so ticking Sets -- gear or not -- satisfies it.
-- ---------------------------------------------------------------------------

-- Which references one rule carries: group/mode conditions (when + whenAny)
-- and whether its action names a set (vs an inline equip).
local function ruleRefs(r, refs)
    local function scan(map)
        for k in pairs(map or {}) do
            local lk = string.lower(tostring(k));
            if lk == 'mode' then refs.modes = true;
            elseif lk == 'group' then refs.groups = true; end
        end
    end
    scan(r.when);
    local anyList = r.whenAny or r.whenany;
    if type(anyList) == 'table' then
        for _, e in ipairs(anyList) do
            if type(e) == 'table' then scan(e); end
        end
    end
    if r.set ~= nil then refs.sets = true; end   -- a named-set action (inline equip carries no set dep)
end

-- Pure: what a raw trigger table's handler rules reference.
-- Returns { modes = bool, groups = bool, sets = bool }.
function M.triggerRefs(raw, canonEvent)
    local refs = { modes = false, groups = false, sets = false };
    if type(raw) ~= 'table' then return refs; end
    for k, v in pairs(raw) do
        local ev = (type(canonEvent) == 'function') and canonEvent(k) or nil;
        if ev ~= nil and type(v) == 'table' then
            for _, r in ipairs(v) do
                if type(r) == 'table' then ruleRefs(r, refs); end
            end
        end
    end
    return refs;
end

-- Pure: does any set item carry a mode gate? (Only equipment references modes
-- -- an empty shell has no rungs, so this dep exists only when gear travels.)
function M.setsUseModes(setsText)
    local res = sandboxRun(setsText);
    local dyn = (type(res) == 'table') and res.Dynamic or nil;
    if type(dyn) ~= 'table' then return false; end
    for _, set in pairs(dyn) do
        if type(set) == 'table' then
            for _, slotList in pairs(set) do
                if type(slotList) == 'table' then
                    for _, it in ipairs(slotList) do
                        if type(it) == 'table' and it.mode ~= nil then return true; end
                    end
                end
            end
        end
    end
    return false;
end

-- File-reading wrapper for the export form: what this job's data references.
-- All-false when unreadable (no file = no dependency).
function M.analyzeJob(charFolder, profName, job, dirOverride)
    local deps = { trigModes = false, trigGroups = false, trigSets = false, setModes = false };
    if prof == nil then return deps; end
    local dir = dirOverride or prof.profileDirAt(charFolder, profName);
    if dir == nil then return deps; end
    if dispatch ~= nil then
        local raw = dispatch.readTriggersRaw(dir .. 'triggers\\' .. job .. '.lua');
        if raw ~= nil then
            local r = M.triggerRefs(raw, dispatch.canonEvent);
            deps.trigModes, deps.trigGroups, deps.trigSets = r.modes, r.groups, r.sets;
        end
    end
    local t = readFile(dir .. 'sets\\' .. job .. '.lua');
    if t ~= nil then deps.setModes = M.setsUseModes(t); end
    return deps;
end

-- The assembly. Missing source files are skipped silently (same rule as the
-- verbatim export); only "every selected thing came up empty" is an error.
-- `dirOverride` (tests only) bypasses the profile-path resolution.
function M.buildPayloads(charFolder, profName, job, opts, dirOverride)
    if prof == nil then return nil, 'profiles.lua unavailable'; end
    if type(opts) ~= 'table' then return nil, 'no export choices'; end
    local dir = dirOverride or prof.profileDirAt(charFolder, profName);
    if dir == nil then return nil, 'not available (log in first?)'; end

    local p = {};
    if opts.sets then
        local t = readFile(dir .. 'sets\\' .. job .. '.lua');
        if t ~= nil then
            if opts.equipment then
                p.sets = t;
            else
                local shell, why = M.stripEquipment(t);
                if shell == nil then return nil, 'sets: ' .. tostring(why); end
                p.sets = shell;
            end
        end
    end

    if opts.triggers and opts.groups and opts.modes then
        p.triggers = readFile(dir .. 'triggers\\' .. job .. '.lua');   -- everything: verbatim
    elseif opts.triggers or opts.groups or opts.modes then
        if dispatch == nil then return nil, 'triggers: dispatch unavailable for filtering'; end
        local raw = dispatch.readTriggersRaw(dir .. 'triggers\\' .. job .. '.lua');
        if raw ~= nil then
            local out, n = M.filterTriggersRaw(raw, opts, dispatch.canonEvent);
            if n > 0 then p.triggers = dispatch.serializeTriggers(out); end
        end
    end

    if opts.lockstyles then
        p.lockstyles = readFile(dir .. 'lockstyles\\' .. job .. '.lua');
    end

    if opts.weights and opts.sets and optim ~= nil then
        p.weights = (optim.renderJobWeightsTextAt(charFolder, job));   -- nil when none stored
    end

    if p.sets == nil and p.triggers == nil and p.lockstyles == nil and p.weights == nil then
        return nil, 'nothing to export with those choices (no matching files for ' .. tostring(job) .. ')';
    end
    return p;
end

return M;
