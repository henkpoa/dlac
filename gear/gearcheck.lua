-- gearcheck.lua -- trigger-gear availability audit (addon side only).
--
-- Answers: "does every set my triggers reference actually have its pieces in an
-- equippable bag right now?" A weapon parked in the Mog Safe silently breaks a
-- HandleDefault set at the worst moment -- this warns instead:
--   set Tp_Default in HandleDefault uses Kraken Club in Main -- it is in
--   Mog Safe, please retrieve if needed.
--
-- Wiring: triggersui configures deps (setsRoot / lookupByName / trigger model)
-- and renders the "Gear warnings" section; chat warnings fire on job change
-- (automationsui.rescanAutogear -- the manifest-rescan cadence) and after a
-- gearmove move; /dl gearcheck runs it on demand.
--
-- The automatic report speaks ONCE PER MAIN JOB (2026-08-01): the cadence that
-- calls it is the auto-sync one, which also fires ~5s after every inventory
-- change, so the signature dedup alone let the same advice come back all
-- session -- every time a piece moved, the availability counts moved with it.
-- One main job = one report; a sub job change is deliberately not a re-arm, and
-- /dl gearcheck (force) always answers. The whole thing is a Setting:
-- "Warn about gear in storage" / /dl gearwarn, reaching us through deps.
-- Pure data module: no imgui here, headless-testable.

local M = {};

local deps = nil;   -- { setsRoot = fn, lookupByName = fn, model = fn -> (model, job),
                    --   candidatesFor = fn|nil (the engine's ladder door, stage 5),
                    --   warnEnabled = fn|nil (the Setting), mainJob = fn|nil (test seam) }
function M.configure(d) deps = d; end

-- chat output through chatfmt when present (addon-side), plain print otherwise
local _cfok, _cfmt = pcall(require, "dlac\\chatfmt");
_cfok = _cfok and type(_cfmt) == 'table';
local function sayWarn(s) if _cfok and _cfmt.warn then _cfmt.warn(s); else print('[dlac] ' .. s); end end
local function sayInfo(s) if _cfok and _cfmt.msg  then _cfmt.msg(s);  else print('[dlac] ' .. s); end end

-- Equippable containers (Inventory + Wardrobes) -- the oracle's list (issue #70),
-- indexed as a set for the membership tests below.
local EQUIPPABLE = {};
for _, cid in ipairs(require("dlac\\gear\\gearoracle").equipBags()) do EQUIPPABLE[cid] = true; end

local function ownedInfo()
    local ok, gi = pcall(require, "dlac\\gear\\gearimport");
    if not ok or type(gi) ~= 'table' or type(gi.ownedSplit) ~= 'function' then return nil, nil; end
    local ok2, split = pcall(gi.ownedSplit);
    if not ok2 or type(split) ~= 'table' then return nil, nil; end
    return split, gi;
end

-- "Mog Safe, Storage x2" -- only the NON-equippable locations (where to retrieve from)
local function storedWhere(split, gi, id)
    local parts = {};
    pcall(function()
        local w = split.where and split.where[id];
        if type(w) ~= 'table' then return; end
        for cid, n in pairs(w) do
            if not EQUIPPABLE[cid] then
                local nm = (type(gi.containerName) == 'function') and gi.containerName(cid)
                           or ('container ' .. tostring(cid));
                parts[#parts + 1] = nm .. ((n > 1) and (' x' .. n) or '');
            end
        end
        table.sort(parts);
    end);
    return table.concat(parts, ', ');
end

local function setContents(name)
    local S = nil;
    pcall(function() S = deps.setsRoot(); end);
    if type(S) ~= 'table' then return nil; end
    if type(S.Dynamic) == 'table' and type(S.Dynamic[name]) == 'table' then return S.Dynamic[name]; end
    if type(S[name]) == 'table' then return S[name]; end
    return nil;
end

-- The ladder door (ADR 0027, stage 5): when the engine's on-demand ladder
-- answers (dispatch.candidatesFor via deps), a named set audits each slot's
-- HEAD rung -- the piece the set will actually ask for at the current level,
-- wrapper entries included -- instead of walking raw store entries (which
-- silently skipped list-valued slots and audited level-ineligible singles).
-- Returns slot -> head name, or nil when the door has no answer (pre-login,
-- no engine store, headless) -- the raw walk stays as the degraded path.
local function ladderHeads(setName, contents)
    if deps == nil or type(deps.candidatesFor) ~= 'function' then return nil; end
    local out, any = {}, false;
    for slot in pairs(contents) do
        local lad = nil;
        pcall(function() lad = deps.candidatesFor(setName, slot); end);
        if type(lad) == 'table' then
            any = true;
            local head = (type(lad.items) == 'table') and lad.items[1] or nil;
            if head ~= nil and type(head.name) == 'string' then out[slot] = head.name; end
        end
    end
    if any then return out; end
    return nil;
end

local function entryName(v)
    if type(v) == 'string' then return v; end
    if type(v) == 'table' and type(v.Name) == 'string' then return v.Name; end
    return nil;
end

-- One slot-map audit: append warnings for pieces that are not equippable right now.
-- ctx = { set = display name, handlers = 'HandleDefault, HandleMidcast' }
local function auditSlotMap(contents, ctx, split, gi, out)
    local need = {};                       -- lower(name) -> { name, slots, need }
    for slot, v in pairs(contents) do
        local nm = entryName(v);
        if nm ~= nil then
            if nm:sub(1, 5) == 'dlac:' then
                nm = nm:match('|(.+)$');   -- virtual entry: audit only its fallback item
            end
            if nm ~= nil and nm ~= '' then
                local key = nm:lower();
                local e = need[key] or { name = nm, slots = {}, need = 0 };
                e.need = e.need + 1;
                e.slots[#e.slots + 1] = tostring(slot);
                need[key] = e;
            end
        end
    end
    for _, e in pairs(need) do
        table.sort(e.slots);
        local rec = nil;
        pcall(function() rec = deps.lookupByName(e.name); end);
        local id = (type(rec) == 'table') and rec.Id or nil;
        if id == nil then
            out[#out + 1] = { kind = 'unknown', set = ctx.set, handlers = ctx.handlers,
                              item = e.name, slots = e.slots };
        else
            local avail = split.avail[id] or 0;
            local total = split.total[id] or 0;
            if avail < e.need then
                out[#out + 1] = {
                    kind = (total >= e.need) and 'stored' or 'missing',
                    set = ctx.set, handlers = ctx.handlers, item = e.name,
                    slots = e.slots, need = e.need, avail = avail, total = total,
                    where = storedWhere(split, gi, id),
                };
            end
        end
    end
end

-- Full audit -> array of warning records (empty = all good / nothing to check),
-- plus whether the audit could actually RUN. The second value exists because
-- "nothing to warn about" and "no trigger model / no bags yet" both come back as
-- an empty list, and the once-per-job gate below must not be armed by the second
-- (pre-login and mid-zone are exactly when the cadence fires first).
function M.audit()
    local out = {};
    if deps == nil then return out, false; end
    local model = nil;
    pcall(function() model = deps.model(); end);
    if type(model) ~= 'table' then return out, false; end
    local split, gi = ownedInfo();
    if split == nil then return out, false; end

    -- Collect every set reference (dedup across rules, remembering the handlers)
    -- and every inline equip table.
    local used = {};                       -- setName -> { [handler] = true }
    local inline = {};                     -- { handler, idx, equip }
    for h, rules in pairs(model) do
        if h ~= 'Modes' and type(rules) == 'table' then
            for i, r in ipairs(rules) do
                if type(r) == 'table' then
                    if r.set ~= nil then
                        -- string or ORDERED LIST (multi-set rule): audit every name
                        local snames = (type(r.set) == 'table') and r.set or { r.set };
                        for _, sn in ipairs(snames) do
                            if type(sn) == 'string' then
                                local u = used[sn] or {};
                                u[h] = true;
                                used[sn] = u;
                            end
                        end
                    end
                    if type(r.equip) == 'table' then
                        inline[#inline + 1] = { handler = h, idx = i, equip = r.equip };
                    end
                end
            end
        end
    end

    local names = {};
    for nm in pairs(used) do names[#names + 1] = nm; end
    table.sort(names);
    for _, nm in ipairs(names) do
        local hs = {};
        for h in pairs(used[nm]) do hs[#hs + 1] = h; end
        table.sort(hs);
        local ctx = { set = nm, handlers = table.concat(hs, ', ') };
        local contents = setContents(nm);
        if contents == nil then
            out[#out + 1] = { kind = 'noset', set = nm, handlers = ctx.handlers };
        else
            auditSlotMap(ladderHeads(nm, contents) or contents, ctx, split, gi, out);
        end
    end
    for _, iv in ipairs(inline) do
        auditSlotMap(iv.equip, { set = '(inline rule #' .. iv.idx .. ')',
                                 handlers = iv.handler }, split, gi, out);
    end
    return out, true;
end

-- Cached audit for per-frame UI use (ownedSplit is a full bag walk).
local _cache, _cacheAt = nil, -1;
function M.auditCached(maxAge)
    local now = os.clock();
    if _cache ~= nil and (now - _cacheAt) < (maxAge or 2) then return _cache; end
    _cache = M.audit();
    _cacheAt = now;
    return _cache;
end
function M.invalidate() _cache = nil; end

-- Human sentence for one warning (shared by chat + the Triggers-tab panel).
function M.describe(w)
    local slots = table.concat(w.slots or {}, ', ');
    if w.kind == 'noset' then
        return ('trigger in %s references set "%s" which does not exist.')
            :format(w.handlers, w.set);
    elseif w.kind == 'unknown' then
        return ('set %s in %s uses "%s" in %s -- not in the gear library (typo, or run /dl sync).')
            :format(w.set, w.handlers, w.item, slots);
    elseif w.kind == 'missing' then
        local owned = (w.total or 0) > 0
            and (' (only %d owned%s)'):format(w.total, (w.where ~= '') and (', in ' .. w.where) or '')
            or '';
        return ('set %s in %s uses %s in %s -- you do not own %s%s.')
            :format(w.set, w.handlers, w.item, slots, (w.need or 1) > 1 and 'enough' or 'it', owned);
    else -- stored
        if (w.need or 1) > 1 and (w.avail or 0) > 0 then
            return ('set %s in %s uses %s in %s -- only %d of %d equippable (%d in %s), please retrieve if needed.')
                :format(w.set, w.handlers, w.item, slots, w.avail, w.need,
                        w.need - w.avail, (w.where ~= '') and w.where or 'storage');
        end
        return ('set %s in %s uses %s in %s -- it is in %s, please retrieve if needed.')
            :format(w.set, w.handlers, w.item, slots, (w.where ~= '') and w.where or 'storage');
    end
end

-- The Setting: "Warn about gear in storage" (/dl gearwarn), owned by syncflags
-- and handed down through deps -- gearcheck never reaches into the ui tree.
-- Unwired reads as ON, which is both the long-standing behavior and what the
-- headless tests exercise. Gates the AUTOMATIC report only: /dl gearcheck is an
-- explicit question and always gets an answer.
local function warnEnabled()
    if deps == nil or type(deps.warnEnabled) ~= 'function' then return true; end
    local on = true;
    pcall(function() on = (deps.warnEnabled() ~= false); end);
    return on;
end

-- The current MAIN job id, or nil when it cannot be read (pre-login, character
-- select, mid-zone -- all of which read 0). Sub job is deliberately not part of
-- this: the audit is main-job scoped, so /BLU under a new sub is the same audit.
local function mainJobId()
    local j = nil;
    if deps ~= nil and type(deps.mainJob) == 'function' then
        pcall(function() j = deps.mainJob(); end);
    else
        pcall(function() j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
    end
    if type(j) ~= 'number' or j == 0 then return nil; end
    return j;
end

-- Chat report. force=false speaks at most ONCE per main job (the cadence that
-- calls it also fires on every inventory settle); when the job cannot be read it
-- falls back to the older signature dedup, so headless and pre-login callers
-- still can't spam. force=true always answers.
local _lastSig, _warnedJob = nil, nil;
function M.chatWarn(force)
    force = (force == true);
    if not force and not warnEnabled() then return; end
    local job = mainJobId();
    if not force and job ~= nil and job == _warnedJob then return; end

    local warns, ran = M.audit();
    _cache, _cacheAt = warns, os.clock();       -- keep the UI cache in step
    local keys = {};
    for _, w in ipairs(warns) do
        keys[#keys + 1] = (w.kind or '?') .. '|' .. tostring(w.set) .. '|' .. tostring(w.item);
    end
    local sig = table.concat(keys, ';');
    if not force then
        -- An audit that could not run says nothing and arms nothing: the gate
        -- must not be spent on the empty answer login hands us.
        if not ran then return; end
        if job == nil and sig == _lastSig then return; end
    end
    _lastSig = sig;
    -- Told for this main job -- including on a forced run, so a manual check is
    -- not followed by the same lines from the next auto-sync.
    if ran and job ~= nil then _warnedJob = job; end
    if #warns == 0 then
        if force then sayInfo('trigger gear check: everything your triggers reference is equippable.'); end
        return;
    end
    sayWarn(('trigger gear check: %d warning(s):'):format(#warns));
    for _, w in ipairs(warns) do sayWarn('  ' .. M.describe(w)); end
end

-- Re-arm the once-per-main-job gate (the next automatic report speaks again).
-- Used by /dl gearwarn on -- turning the warnings back on should not leave you
-- waiting for a job change to hear them -- and by the tests.
function M.rearm() _warnedJob = nil; _lastSig = nil; end

ashita.events.register('command', 'dlac-gearcheck-cmd', function(e)
    pcall(function()
        local raw = string.lower(e.command or '');
        local a, b = raw:match('^/dl%s+(%S+)%s*(%S*)');
        if a == nil then
            local d = raw:match('^/dlac%s+(%S+)');
            a = d;
        end
        if a ~= 'gearcheck' then return; end
        e.blocked = true;
        M.chatWarn(true);
    end);
end);

return M;
