-- setmanager.lua — read/edit LuAshitacast dynamic sets inside <JOB>.lua files.
-- Used by the gearui Sets tab to COMMIT (write/replace) or DELETE a dynamic set,
-- preserving the rest of the file (comments, other sets, handlers) untouched.
--
-- A dynamic set lives in `sets.Dynamic.<SetName>` and is a map of slot -> ordered
-- list of gear refs; LuAshitacast's BuildDynamicSets picks the best-by-level and
-- flattens it to `sets.<SetName>`. We rewrite only the target set's block.
--
-- The GUI passes an ORDERED `slots` structure it already knows the paths for:
--   slots = {
--     { name = 'Main', items = {
--         { path = 'gear.Main.Club.MapleWand_1' },
--         { path = 'gear.Main.Club.YewWand_1', minLevel = 18 },
--         { path = 'gear.Body.IllusionistsGarb', minLevel = 61, maxLevel = 75 },
--     }},
--     { name = 'Head', items = { { path = 'gear.Head.PoetsCirclet' } }},
--     ...
--   }
-- `path` is rendered verbatim (the GUI builds it from the item's slot/category/key;
-- for Ring1/Ring2 -> gear.Ring.X, Ear1/Ear2 -> gear.Ear.X). min/maxLevel optional.

local M = {};

local loadstring = loadstring or load;   -- LuaJIT / Lua 5.5 compat

----------------------------------------------------------------------
-- file io
----------------------------------------------------------------------
local function readFile(p)
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end
local function writeFile(p, t)
    local f = io.open(p, 'w'); if f == nil then return false; end
    f:write(t); f:close(); return true;
end

-- LuaAshitacast's gState inside a profile, else the party manager (dlac addon context).
-- Returns the character's config dir, or nil if not logged in.
local function profileDir()
    local name, id;
    if gState ~= nil and gState.PlayerName ~= nil and gState.PlayerId ~= nil then
        name, id = gState.PlayerName, gState.PlayerId;
    else
        pcall(function()
            local party = AshitaCore:GetMemoryManager():GetParty();
            name = party:GetMemberName(0);
            id   = party:GetMemberServerId(0);
            if name == '' then name = nil; end
        end);
    end
    if name == nil or id == nil then return nil; end
    return string.format('%sconfig\\addons\\luashitacast\\%s_%u\\', AshitaCore:GetInstallPath(), name, id);
end
M.jobPath = function(job) local d = profileDir(); return d and (d .. job .. '.lua') or nil; end

----------------------------------------------------------------------
-- pure text helpers (offline-testable; no globals)
----------------------------------------------------------------------
local function splitLines(text)
    local nl = text:find('\r\n', 1, true) and '\r\n' or '\n';
    local lines, start = {}, 1;
    while true do
        local s, e = text:find(nl, start, true);
        if not s then lines[#lines + 1] = text:sub(start); break; end
        lines[#lines + 1] = text:sub(start, s - 1);
        start = e + 1;
    end
    return lines, nl;
end

local function renderItem(it)
    if it.minLevel == nil and it.maxLevel == nil then
        return string.rep(' ', 16) .. it.path .. ',';
    end
    local parts = { 'gear = ' .. it.path };
    if it.minLevel ~= nil then parts[#parts + 1] = 'minLevel = ' .. tostring(it.minLevel); end
    if it.maxLevel ~= nil then parts[#parts + 1] = 'maxLevel = ' .. tostring(it.maxLevel); end
    return string.rep(' ', 16) .. '{' .. table.concat(parts, ', ') .. '},';
end

-- returns an array of lines (no newline chars) for the whole set block at indent 8.
M.renderSetLines = function(setName, slots)
    local L = {};
    L[#L + 1] = string.rep(' ', 8) .. setName .. ' = {';
    for _, slot in ipairs(slots) do
        if slot.items and #slot.items > 0 then
            L[#L + 1] = string.rep(' ', 12) .. slot.name .. ' = {';
            for _, it in ipairs(slot.items) do L[#L + 1] = renderItem(it); end
            L[#L + 1] = string.rep(' ', 12) .. '},';
        end
    end
    L[#L + 1] = string.rep(' ', 8) .. '},';
    return L;
end

-- brace-aware scanner: from the '{' at byte index i, return the matching '}' byte
-- index, skipping Lua line/block comments and quoted strings. Robust to any
-- indentation or tabs (the line-indent heuristic broke on tab-indented files).
local function matchBrace(text, i)
    local n = #text; local depth = 0;
    while i <= n do
        local c = text:sub(i, i);
        if c == '-' and text:sub(i + 1, i + 1) == '-' then
            if text:sub(i + 2, i + 3) == '[[' then
                local e = text:find(']]', i + 4, true); i = e and e + 2 or n + 1;
            else
                local e = text:find('\n', i + 2, true); i = e or n + 1;
            end
        elseif c == '"' or c == "'" then
            local q = c; i = i + 1;
            while i <= n do
                local d = text:sub(i, i);
                if d == '\\' then i = i + 2;
                elseif d == q then i = i + 1; break;
                else i = i + 1; end
            end
        elseif c == '{' then depth = depth + 1; i = i + 1;
        elseif c == '}' then
            depth = depth - 1;
            if depth == 0 then return i; end
            i = i + 1;
        else i = i + 1; end
    end
    return nil;
end

local function byteToLine(text, idx)
    local _, n = text:sub(1, idx):gsub('\n', '');
    return n + 1;
end

-- Replace or insert a set. returns newText, 'replaced'|'inserted' | nil, errmsg
M.spliceSet = function(fileText, setName, slots)
    local lines, nl = splitLines(fileText);
    local ds, de = fileText:find('Dynamic%s*=%s*{');
    if not ds then return nil, 'could not locate sets.Dynamic block'; end
    local dynClose = matchBrace(fileText, de);
    if not dynClose then return nil, 'sets.Dynamic block is not closed'; end
    local block = M.renderSetLines(setName, slots);
    local pat = '%f[%w_]' .. setName:gsub('(%W)', '%%%1') .. '%s*=%s*{';
    local ss, se = fileText:find(pat, ds);
    local out = {};
    if ss and ss < dynClose then
        local setClose = matchBrace(fileText, se);
        if not setClose then return nil, 'set block not closed: ' .. setName; end
        local setOpenLine = byteToLine(fileText, se);
        local setCloseLine = byteToLine(fileText, setClose);
        for i = 1, setOpenLine - 1 do out[#out + 1] = lines[i]; end
        for _, b in ipairs(block) do out[#out + 1] = b; end
        for i = setCloseLine + 1, #lines do out[#out + 1] = lines[i]; end
        return table.concat(out, nl), 'replaced';
    else
        -- Insert as the FIRST set (right after the `Dynamic = {` line). The block's own
        -- trailing `},` then separates it from the next set. Appending at the end could
        -- instead follow a set whose final `}` lacks a comma -> parse error.
        local dynOpenLine = byteToLine(fileText, de);
        for i = 1, dynOpenLine do out[#out + 1] = lines[i]; end
        for _, b in ipairs(block) do out[#out + 1] = b; end
        for i = dynOpenLine + 1, #lines do out[#out + 1] = lines[i]; end
        return table.concat(out, nl), 'inserted';
    end
end

-- Delete a named set. returns newText, 'deleted' | nil, errmsg
M.deleteSetText = function(fileText, setName)
    local lines, nl = splitLines(fileText);
    local ds, de = fileText:find('Dynamic%s*=%s*{');
    if not ds then return nil, 'could not locate sets.Dynamic block'; end
    local dynClose = matchBrace(fileText, de);
    if not dynClose then return nil, 'sets.Dynamic block is not closed'; end
    local pat = '%f[%w_]' .. setName:gsub('(%W)', '%%%1') .. '%s*=%s*{';
    local ss, se = fileText:find(pat, ds);
    if not ss or ss > dynClose then return nil, 'set not found: ' .. tostring(setName); end
    local setClose = matchBrace(fileText, se);
    if not setClose then return nil, 'set block not closed: ' .. setName; end
    local setOpenLine = byteToLine(fileText, se);
    local setCloseLine = byteToLine(fileText, setClose);
    local out = {};
    for i = 1, setOpenLine - 1 do out[#out + 1] = lines[i]; end
    for i = setCloseLine + 1, #lines do out[#out + 1] = lines[i]; end
    return table.concat(out, nl), 'deleted';
end

----------------------------------------------------------------------
-- backup with rotation (keep newest maxN; default 20)
----------------------------------------------------------------------
local function backupWithRotation(srcText, job, maxN)
    maxN = maxN or 20;
    local dir = profileDir() .. 'backups\\';
    if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(dir); end
    local prefix = job .. '_set_';
    local path = dir .. prefix .. os.date('%Y%m%d_%H%M%S') .. '.lua';
    if not writeFile(path, srcText) then return nil, 'could not write backup'; end
    if ashita and ashita.fs and ashita.fs.get_dir then
        local ok, files = pcall(ashita.fs.get_dir, dir, '.*%.lua', false);
        if ok and type(files) == 'table' then
            local mine = {};
            for _, f in ipairs(files) do
                if type(f) == 'string' and f:sub(1, #prefix) == prefix then mine[#mine + 1] = f; end
            end
            table.sort(mine);                       -- timestamped -> chronological
            while #mine > maxN do
                os.remove(dir .. mine[1]); table.remove(mine, 1);
            end
        end
    end
    return path;
end
M._backupWithRotation = backupWithRotation;

----------------------------------------------------------------------
-- in-game commit / delete (backup -> splice -> syntax-check -> write)
----------------------------------------------------------------------
M.commitSet = function(job, setName, slots)
    local path = M.jobPath(job);
    if path == nil then return false, 'not logged in (no profile path)'; end
    local text = readFile(path);
    if not text then return false, 'could not read ' .. path; end
    local newText, action = M.spliceSet(text, setName, slots);
    if not newText then return false, action; end
    local chunk, cerr = loadstring(newText, '@' .. path);
    if not chunk then return false, 'edit would not parse: ' .. tostring(cerr) .. ' (file untouched)'; end
    local bpath, berr = backupWithRotation(text, job, 20);
    if not bpath then return false, berr; end
    if not writeFile(path, newText) then return false, 'write failed (backup: ' .. bpath .. ')'; end
    return true, action, bpath;
end

M.deleteSet = function(job, setName)
    local path = M.jobPath(job);
    if path == nil then return false, 'not logged in (no profile path)'; end
    local text = readFile(path);
    if not text then return false, 'could not read ' .. path; end
    local newText, action = M.deleteSetText(text, setName);
    if not newText then return false, action; end
    local chunk, cerr = loadstring(newText, '@' .. path);
    if not chunk then return false, 'delete would not parse: ' .. tostring(cerr) .. ' (file untouched)'; end
    local bpath, berr = backupWithRotation(text, job, 20);
    if not bpath then return false, berr; end
    if not writeFile(path, newText) then return false, 'write failed (backup: ' .. bpath .. ')'; end
    return true, action, bpath;
end

return M;
