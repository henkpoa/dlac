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
-- (rescanAutogear) and after a gearmove move; /dl gearcheck runs it on demand.
-- Pure data module: no imgui here, headless-testable.

local M = {};

local deps = nil;   -- { setsRoot = fn, lookupByName = fn, model = fn -> (model, job) }
function M.configure(d) deps = d; end

-- chat output through chatfmt when present (addon-side), plain print otherwise
local _cfok, _cfmt = pcall(require, "dlac\\chatfmt");
_cfok = _cfok and type(_cfmt) == 'table';
local function sayWarn(s) if _cfok and _cfmt.warn then _cfmt.warn(s); else print('[dlac] ' .. s); end end
local function sayInfo(s) if _cfok and _cfmt.msg  then _cfmt.msg(s);  else print('[dlac] ' .. s); end end

-- Equippable containers (matches gearimport's AVAIL_SET: Inventory + Wardrobes).
local EQUIPPABLE = { [0] = true, [8] = true, [10] = true, [11] = true, [12] = true,
                     [13] = true, [14] = true, [15] = true, [16] = true };

local function ownedInfo()
    local ok, gi = pcall(require, "dlac\\gearimport");
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

-- Full audit -> array of warning records (empty = all good / nothing to check).
function M.audit()
    local out = {};
    if deps == nil then return out; end
    local model = nil;
    pcall(function() model = deps.model(); end);
    if type(model) ~= 'table' then return out; end
    local split, gi = ownedInfo();
    if split == nil then return out; end

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
            auditSlotMap(contents, ctx, split, gi, out);
        end
    end
    for _, iv in ipairs(inline) do
        auditSlotMap(iv.equip, { set = '(inline rule #' .. iv.idx .. ')',
                                 handlers = iv.handler }, split, gi, out);
    end
    return out;
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

-- Chat report. force=false is signature-deduped: repeat states stay silent
-- (job-change and post-move hooks can call freely without spam).
local _lastSig = nil;
function M.chatWarn(force)
    local warns = M.audit();
    _cache, _cacheAt = warns, os.clock();       -- keep the UI cache in step
    local keys = {};
    for _, w in ipairs(warns) do
        keys[#keys + 1] = (w.kind or '?') .. '|' .. tostring(w.set) .. '|' .. tostring(w.item);
    end
    local sig = table.concat(keys, ';');
    if not force and sig == _lastSig then return; end
    _lastSig = sig;
    if #warns == 0 then
        if force then sayInfo('trigger gear check: everything your triggers reference is equippable.'); end
        return;
    end
    sayWarn(('trigger gear check: %d warning(s):'):format(#warns));
    for _, w in ipairs(warns) do sayWarn('  ' .. M.describe(w)); end
end

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
