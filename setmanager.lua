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
    if it.minLevel == nil and it.maxLevel == nil and it.mode == nil then
        return string.rep(' ', 16) .. it.path .. ',';   -- no rules -> bare gear ref
    end
    local parts = { 'gear = ' .. it.path };
    if it.minLevel ~= nil then parts[#parts + 1] = 'minLevel = ' .. tostring(it.minLevel); end
    if it.maxLevel ~= nil then parts[#parts + 1] = 'maxLevel = ' .. tostring(it.maxLevel); end
    if it.mode ~= nil then
        if type(it.mode) == 'table' then                 -- list = OR: any active mode
            local qs = {};
            for _, m in ipairs(it.mode) do qs[#qs + 1] = string.format('%q', tostring(m)); end
            parts[#parts + 1] = 'mode = { ' .. table.concat(qs, ', ') .. ' }';
        else
            parts[#parts + 1] = string.format('mode = %q', tostring(it.mode));
        end
    end
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
-- Handler shims (trigger dispatch, ADR 0002): analyze & repair <JOB>.lua.
-- Pure text functions (offline-testable) + a safe file wrapper below.
--
-- Setup uses these to CONVERT any player's existing profile in place:
--   * detect the profile table (`return <var>`) and the dlac utils require var
--   * for each handler: exists? has utils.dispatch('<H>')? is it the LAST statement?
--   * repair: insert the require if absent, APPEND the dispatch call at the end of
--     an existing handler (the player's own logic always runs first -- never edited,
--     never removed), create missing handlers whole, move only OUR standalone
--     dispatch line when it isn't last. Idempotent: a healthy file is untouched.
----------------------------------------------------------------------
M.HANDLERS = { 'Default', 'Precast', 'Midcast', 'Ability', 'Item', 'Weaponskill', 'Preshot', 'Midshot' };

-- From byte index i inside a function body (depth 1), return the byte index of the
-- matching `end` keyword. Token-walks the source, skipping comments and strings, and
-- counting block keywords: function/if/do/repeat open; end/until close. (for/while
-- don't open -- their `do` does; elseif/else/then are neutral.)
local function findFunctionEnd(text, i)
    local n = #text;
    local depth = 1;
    while i <= n do
        local c = text:sub(i, i);
        if c == '-' and text:sub(i + 1, i + 1) == '-' then
            local eq = text:match('^%[(=*)%[', i + 2);
            if eq ~= nil then                                   -- block comment --[[ / --[==[
                local close = ']' .. eq .. ']';
                local e = text:find(close, i + 4 + #eq, true);
                i = e and (e + #close) or (n + 1);
            else                                                -- line comment
                local e = text:find('\n', i + 2, true);
                i = e or (n + 1);
            end
        elseif c == '"' or c == "'" then
            local q = c; i = i + 1;
            while i <= n do
                local d = text:sub(i, i);
                if d == '\\' then i = i + 2;
                elseif d == q then i = i + 1; break;
                else i = i + 1; end
            end
        elseif c == '[' and text:match('^%[(=*)%[', i) ~= nil then   -- long string
            local eq = text:match('^%[(=*)%[', i);
            local close = ']' .. eq .. ']';
            local e = text:find(close, i + 2 + #eq, true);
            i = e and (e + #close) or (n + 1);
        elseif c:match('[%a_]') then
            local word = text:match('^[%w_]+', i);
            if word == 'function' or word == 'if' or word == 'do' or word == 'repeat' then
                depth = depth + 1;
            elseif word == 'end' or word == 'until' then
                depth = depth - 1;
                if depth == 0 then return i; end
            end
            i = i + #word;
        else
            i = i + 1;
        end
    end
    return nil;
end

-- Find pat, skipping matches that sit inside a line comment. A commented-out
-- definition ("-- profile.HandleX = function()") is dead code: matching it made
-- findFunctionEnd start inside the comment and walk to EOF -> 'unparsable',
-- which blocked Setup on profiles with old handlers commented out.
local function findUncommented(text, pat, init)
    local s, e = text:find(pat, init);
    while s ~= nil do
        local ls = s;
        while ls > 1 and text:sub(ls - 1, ls - 1) ~= '\n' do ls = ls - 1; end
        if text:sub(ls, s - 1):find('%-%-') == nil then return s, e; end
        s, e = text:find(pat, e + 1);
    end
    return nil;
end

-- Locate a handler definition. Handles both styles:
--   <p>.Handle<h> = function (...)      and      function <p>.Handle<h>(...)
-- Returns defStart, bodyStart (byte after the parameter list's ')'), or nil.
local function findHandler(text, pVar, h)
    local pat = '%f[%w_]' .. pVar .. '%.Handle' .. h .. '%s*=%s*function%s*%(';
    local s, e = findUncommented(text, pat);
    if s == nil then
        pat = 'function%s+' .. pVar .. '%.Handle' .. h .. '%s*%(';
        s, e = findUncommented(text, pat);
    end
    if s == nil then return nil; end
    local pe = text:find(')', e - 1, true);
    if pe == nil then return nil; end
    return s, pe + 1;
end

-- The dispatch-call pattern for handler h with utils var U (used for find/verify).
local function dispatchPat(U, h)
    return '%f[%w_]' .. U .. '%.dispatch%s*%(%s*[\'"]' .. h .. '[\'"]%s*%)%s*;?';
end

-- Analyze the shim state of a profile text. Returns:
--   { profileVar, utilsVar, handlers = { [h] = 'ok'|'missing'|'noshim'|'notlast'|'unparsable' },
--     healthy = bool, warnings = { ... } }
M.analyzeShims = function(text)
    local res = { handlers = {}, healthy = true, warnings = {} };
    res.profileVar = text:match('return%s+([%a_][%w_]*)%s*;?%s*$') or 'profile';
    res.utilsVar   = text:match('local%s+([%a_][%w_]*)%s*=%s*require%s*%(?%s*[\'"]dlac\\\\utils[\'"]');
    local U = res.utilsVar or 'utils';
    for _, h in ipairs(M.HANDLERS) do
        local defS, bodyS = findHandler(text, res.profileVar, h);
        local st;
        if defS == nil then
            st = 'missing';
        else
            local endPos = findFunctionEnd(text, bodyS);
            if endPos == nil then
                st = 'unparsable';
            else
                local body = text:sub(bodyS, endPos - 1);
                local ds, de = body:find(dispatchPat(U, h));
                if ds == nil then
                    st = 'noshim';
                else
                    local lastE = de;                         -- find the LAST occurrence
                    while true do
                        local _, e2 = body:find(dispatchPat(U, h), lastE + 1);
                        if e2 == nil then break; end
                        lastE = e2;
                    end
                    -- "last statement": nothing but whitespace/comments/semicolons after it
                    local tail = body:sub(lastE + 1);
                    tail = tail:gsub('%-%-%[%[.-%]%]', ''):gsub('%-%-[^\n]*', ''):gsub('[%s;]+', '');
                    st = (tail == '') and 'ok' or 'notlast';
                end
                if h == 'Default' and st ~= 'missing' and not body:find('rebuildSets', 1, true) then
                    res.warnings[#res.warnings + 1] =
                        'HandleDefault does not call utils.rebuildSets(sets) -- Dynamic sets will not level-scale';
                end
            end
        end
        res.handlers[h] = st;
        if st ~= 'ok' then res.healthy = false; end
    end
    return res;
end

-- Indentation of the line that byte position p sits on.
local function lineIndentAt(text, p)
    local ls = p;
    while ls > 1 and text:sub(ls - 1, ls - 1) ~= '\n' do ls = ls - 1; end
    local indent = text:sub(ls, p - 1):match('^%s*') or '';
    local aloneOnLine = (text:sub(ls, p - 1):match('^%s*$') ~= nil);
    return ls, indent, aloneOnLine;
end

-- Repair a profile text. Returns newText, report{ requireAdded, created={h}, appended={h},
-- moved={h}, warnings={..} }. newText == text when nothing needed doing.
M.repairShimsText = function(text)
    local report = { requireAdded = false, created = {}, appended = {}, moved = {}, warnings = {} };

    local pVar = text:match('return%s+([%a_][%w_]*)%s*;?%s*$');
    if pVar == nil then
        report.warnings[#report.warnings + 1] = 'no trailing `return <profile>` found -- cannot wire this file';
        return text, report;
    end

    -- Ensure the dlac utils require exists; insert one (with a collision-safe var) if not.
    local U = text:match('local%s+([%a_][%w_]*)%s*=%s*require%s*%(?%s*[\'"]dlac\\\\utils[\'"]');
    if U == nil then
        U = 'dlacUtils';
        local boot = 'local ' .. U .. ' = require("dlac\\\\utils");  -- dlac: trigger dispatch library\n';
        -- after the package.path bootstrap if present, else at the very top
        local bs, be = text:find('package%.path[^\n]*\n');
        if bs ~= nil then
            text = text:sub(1, be) .. boot .. text:sub(be + 1);
        else
            text = boot .. text;
        end
        report.requireAdded = true;
    end

    for _, h in ipairs(M.HANDLERS) do
        local defS, bodyS = findHandler(text, pVar, h);
        local stmt = U .. ".dispatch('" .. h .. "');";
        if defS == nil then
            -- create the whole handler right before the trailing `return <p>`
            local rs = text:find('return%s+' .. pVar .. '%s*;?%s*$');
            if rs == nil then
                report.warnings[#report.warnings + 1] = 'could not find `return ' .. pVar .. '` to add Handle' .. h;
            else
                local shim = pVar .. '.Handle' .. h .. ' = function() ' .. stmt .. ' end  -- dlac: added by Setup\n\n';
                text = text:sub(1, rs - 1) .. shim .. text:sub(rs);
                report.created[#report.created + 1] = h;
            end
        else
            local endPos = findFunctionEnd(text, bodyS);
            if endPos == nil then
                report.warnings[#report.warnings + 1] = 'Handle' .. h .. ' could not be parsed -- left untouched';
            else
                local body = text:sub(bodyS, endPos - 1);
                local ds, de = body:find(dispatchPat(U, h));
                local needAppend = false;
                if ds == nil then
                    needAppend = true;
                else
                    local lastS, lastE = ds, de;
                    while true do
                        local s2, e2 = body:find(dispatchPat(U, h), lastE + 1);
                        if s2 == nil then break; end
                        lastS, lastE = s2, e2;
                    end
                    local tail = body:sub(lastE + 1);
                    tail = tail:gsub('%-%-%[%[.-%]%]', ''):gsub('%-%-[^\n]*', ''):gsub('[%s;]+', '');
                    if tail ~= '' then
                        -- not last: relocate only if OUR call sits alone on its line
                        -- (never touch a dispatch embedded in the player's own logic)
                        local als, ale = bodyS + lastS - 1, bodyS + lastE - 1;
                        local ls, _, alone = lineIndentAt(text, als);
                        local restOfLine = text:sub(ale + 1, (text:find('\n', ale, true) or #text));
                        if alone and restOfLine:gsub('%-%-[^\n]*', ''):gsub('[%s;\n]+', '') == '' then
                            local le = text:find('\n', ale, true);
                            text = text:sub(1, ls - 1) .. text:sub((le or ale) + 1);
                            needAppend = true;
                            report.moved[#report.moved + 1] = h;
                        else
                            report.warnings[#report.warnings + 1] =
                                'Handle' .. h .. ": dispatch('" .. h .. "') is not the last statement -- move it to the end by hand";
                        end
                    end
                end
                if needAppend then
                    -- re-find (positions may have shifted if we removed a line above)
                    defS, bodyS = findHandler(text, pVar, h);
                    endPos = bodyS and findFunctionEnd(text, bodyS) or nil;
                    if endPos ~= nil then
                        local ls, indent, alone = lineIndentAt(text, endPos);
                        if alone then
                            text = text:sub(1, ls - 1) .. indent .. '    ' .. stmt .. '  -- dlac: added by Setup\n' .. text:sub(ls);
                        else       -- one-liner: `... end` on a shared line
                            text = text:sub(1, endPos - 1) .. stmt .. ' ' .. text:sub(endPos);
                        end
                        if ds == nil then report.appended[#report.appended + 1] = h; end
                    end
                end
            end
        end
    end
    return text, report;
end

----------------------------------------------------------------------
-- backup with rotation (keep newest maxN; default 20)
----------------------------------------------------------------------
local function backupWithRotation(srcText, job, maxN, tag)
    maxN = maxN or 20;
    local dir = profileDir() .. 'backups\\';
    if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(dir); end
    local prefix = job .. '_' .. (tag or 'set') .. '_';
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

-- Shim-repair file wrapper: analyze -> repair -> parse-check -> backup -> write (same
-- rails as commitSet). Returns ok, report|errmsg, backupPath|nil. No-op when healthy.
-- (Lives below backupWithRotation on purpose -- it closes over that local.)
M.repairShims = function(job)
    local path = M.jobPath(job);
    if path == nil then return false, 'not logged in (no profile path)'; end
    local text = readFile(path);
    if text == nil then return false, 'could not read ' .. path; end
    local newText, report = M.repairShimsText(text);
    if newText == text then return true, report, nil; end   -- healthy already (or only warnings)
    local chunk, cerr = loadstring(newText, '@' .. path);
    if chunk == nil then return false, 'repair would not parse: ' .. tostring(cerr) .. ' (file untouched)'; end
    local bpath, berr = backupWithRotation(text, job, 20, 'shim');
    if bpath == nil then return false, berr; end
    if not writeFile(path, newText) then return false, 'write failed (backup: ' .. bpath .. ')'; end
    return true, report, bpath;
end

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
