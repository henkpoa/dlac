-- Config, live inventory, and click-initiated runs. Re-plan before EACH move,
-- then wait for the acknowledged quantity to appear in memory before continuing.
local base = 'dlac\\servers\\ascensionxi\\modules\\voidrestock\\';
local model = require(base .. 'model');
local client = require(base .. 'client');
local statefile = require('dlac\\lib\\statefile');
local safe = require('dlac\\lib\\safewrite');
local watch = require('dlac\\lib\\entwatch');
local jobs = require('dlac\\gear\\jobgate').JOBS;
local oracle = require('dlac\\gear\\gearoracle');
local M = { config = model.normalize({}), message = '', client = client };
local root, job, run, loadError, wasNear, settling;
M._clock = client._clock;
M._context = function()
    local j;
    pcall(function() j = jobs[AshitaCore:GetMemoryManager():GetPlayer():GetMainJob()]; end);
    return statefile.charDir(), j;
end;
M.near = function()
    local nearest;
    for _, name in ipairs({ 'Void Storage', 'Void Coffer' }) do
        watch.watch('voidrestock', name);
        local d = watch.nearest(name);
        if d ~= nil and (nearest == nil or d < nearest) then nearest = d; end
    end
    return nearest ~= nil and nearest <= 5;
end;
function M.item(id)
    local out;
    pcall(function()
        local r = AshitaCore:GetResourceManager():GetItemById(id);
        if r then
            local rec = oracle.lookup(id);
            local slots = tonumber(r.Slots);
            local allowed = rec and rec.Slot and rec.Slot == 'Ammo'
                or (not (rec and rec.Slot) and (slots == 0 or slots == 8));
            out = { id = id, name = r.Name[1] or ('Item ' .. tostring(id)),
                stack = math.max(1, tonumber(r.StackSize) or 1), restockable = allowed == true };
        end
    end);
    return out or { id = id, name = 'Item ' .. tostring(id), stack = 1, restockable = false };
end
M.inventory = function()
    local counts, free = {}, 0;
    local ok = pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local max = inv:GetContainerCountMax(0);
        if not max or max < 1 then error('Inventory unavailable'); end
        for slot = 1, max do
            local item = inv:GetContainerItem(0, slot);
            local id, n = item and tonumber(item.Id) or 0, item and tonumber(item.Count) or 0;
            if id and id > 0 and n and n > 0 then counts[id] = (counts[id] or 0) + n;
            else free = free + 1; end
        end
    end);
    if ok then return counts, free; end
    return nil;
end;
local function read(path)
    local f = io.open(path, 'rb'); if not f then return nil; end
    local text = f:read('*a'); f:close(); return text;
end
local function decode(text)
    local chunk, err;
    if setfenv then chunk, err = loadstring(text); if chunk then setfenv(chunk, {}); end
    else chunk, err = load(text, 'void-restock', 't', {}); end
    if not chunk then return nil, err; end
    local ok, data = pcall(chunk);
    if not ok or type(data) ~= 'table' then return nil, 'Expected a config table'; end
    return model.normalize(data);
end
function M.stop(why)
    run = nil;
    M.message = why or 'Stopped. Any request already sent may still complete.';
end
function M.syncContext()
    local r, j = M._context();
    if r ~= root then
        root, job, run, loadError, wasNear, settling = r, j, nil, nil, false, nil;
        client.reset(); M.config = model.normalize({}); M.message = '';
        if root then
            local text = read(root .. 'void-restock.lua');
            -- Reuse an existing E-Box list on first use; never edit its file.
            if not text then text = read(root .. 'restock.lua'); end
            if text then
                local config, err = decode(text);
                if config then M.config = config;
                else loadError = err; M.message = 'Could not read restock settings: ' .. tostring(err); end
            end
        end
    elseif j ~= job then
        job = j; M.stop('Job changed; restock stopped.');
    end
    return root ~= nil and job ~= nil and not loadError;
end
function M.job() return job; end
function M.busy() return run ~= nil or settling ~= nil or client.busy(); end
function M.save(config)
    if not M.syncContext() then return false; end
    M.stop('');
    local path = root .. 'void-restock.lua';
    local original = read(path);
    if original then
        local dir = root .. 'backups/';
        pcall(function() ashita.fs.create_directory(dir); end);
        -- Five rotating backups; every replacement uses the same verified
        -- writer as the live file. A backup failure leaves live config intact.
        for i = 5, 1, -1 do
            local old = i == 1 and original or read(dir .. 'void-restock-' .. (i - 1) .. '.lua');
            if old then
                local backupPath = dir .. 'void-restock-' .. i .. '.lua';
                local backed, err = safe.replaceLua(backupPath, old, { origText = read(backupPath) });
                if not backed then M.message = 'Save failed: backup: ' .. tostring(err); return false; end
            end
        end
    end
    local text = model.serialize(config);
    local ok, err = safe.replaceLua(path, text, { origText = original,
        validate = function() return decode(text) ~= nil; end });
    if not ok then M.message = 'Save failed: ' .. tostring(err); return false; end
    M.config = model.normalize(config); M.message = 'Restock targets saved.';
    return true;
end
function M.plan()
    local counts, free = M.inventory();
    if not counts or not job then return nil; end
    local entries = {};
    for _, e in ipairs(model.effective(M.config, job)) do
        if M.item(e.id).restockable then entries[#entries + 1] = e; end
    end
    return model.plan(entries, counts, client.counts, free,
        function(id) return M.item(id).stack; end), counts;
end
function M.start(kind)
    if not M.syncContext() or M.busy() or not M.near() or not client.fresh then return false; end
    if kind ~= 'fetch' and kind ~= 'store' then return false; end
    run = { kind = kind, seen = {}, moved = 0, at = M._clock() };
    M.message = kind == 'store' and 'Storing listed surplus...' or 'Fetching shortfall...';
    return true;
end
function M.tick()
    if not M.syncContext() then return; end
    local near = M.near();
    if not near and wasNear then
        M.stop('Left Void Storage; restock stopped.'); client.reset(); settling = nil;
    end
    if near and not wasNear and not client.busy() then client.refresh(); end
    wasNear = near;
    if not near then return; end
    client.tick();
    if client.busy() then return; end
    if not run and not settling then return; end
    if not client.fresh then settling = nil; M.stop(client.message); return; end
    local plan, counts = M.plan();
    if not plan then settling = nil; M.stop('Inventory unavailable; stopped.'); return; end
    if settling then
        if (counts[settling.id] or 0) ~= settling.count then
            if M._clock() - settling.at > 4 then
                settling = nil; client.fresh = false;
                M.stop('Inventory did not settle as expected; stopped. Refresh stock before retrying.');
            end
            return;
        end
        settling = nil;
    end
    if not run then return; end
    local nextMove;
    for _, e in ipairs(plan[run.kind]) do if not run.seen[e.id] then nextMove = e; break; end end
    if not nextMove then
        M.stop(string.format('Done: %d units %s.', run.moved, run.kind == 'store' and 'stored' or 'fetched'));
        return;
    end
    if M._clock() - run.at > 30 then M.stop('Storage channel busy; stopped.'); return; end
    local active, id, qty = run, nextMove.id, nextMove.qty;
    local before = counts[id] or 0;
    local sent = client.move(run.kind, id, qty, function(reply, err)
        -- Even after Stop, let an in-flight reply settle before another run.
        if reply and reply.moved > 0 then
            settling = { id = id, count = before + (active.kind == 'store' and -reply.moved or reply.moved), at = M._clock() };
        end
        if run ~= active then return; end
        if not reply then M.stop(err); return; end
        if reply.moved ~= qty or reply.reason ~= 0 then
            M.stop(string.format('%s: %d/%d moved. %s. Stopped.', M.item(id).name,
                reply.moved, qty, client.reasons[reply.reason] or 'Server refused'));
            return;
        end
        run.moved = run.moved + reply.moved;
        run.at = M._clock();
    end);
    if sent then active.seen[id] = true; end
end
function M.zone()
    M.stop('Zone changed; restock stopped.'); client.reset(); wasNear, settling = false, nil;
end
return M;
