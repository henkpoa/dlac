--[[
    dlac/lib/safewrite.lua -- the safe file-replacement ladder, written ONCE.

    Three verbs, each protecting a file a player cannot afford to lose:

      timestampBackup(dir, prefix, text)  -> backupPath | nil, err
          dir\prefix<YYYYMMDD_HHMMSS>.lua, creating dir (guarded ashita.fs).

      replaceLua(path, newText, opts)     -> true | nil, err
          The atomic-with-restore ladder both gearimport writers used to carry
          as private near-copies: parse newText -> write .tmp -> loadfile ->
          optional opts.validate(chunk, tmpPath) (e.g. sandbox-RUN the file and
          check what it defines -- catches runtime errors a parse can't) ->
          remove target -> rename tmp in -> post-write loadfile check -> restore
          opts.origText on any late failure. The caller does its backup FIRST
          (timestampBackup) and owns all messaging.

      verifiedMove(src, dst)              -> true | nil, err, missing
          Copy + read-back-verify + remove -- the "never delete without a
          verified safety copy" house rule (profiles' deleters). `missing` is
          true when src was unreadable, so callers can distinguish "nothing
          there" from a real failure.

    DELIBERATELY NOT HERE: setmanager's rotated set backups (keep-newest-20 via
    backupWithRotation) -- a different, deliberate policy on a different file
    class, already factored inside setmanager and pinned by its tests. One
    adapter is a hypothetical seam; if a third rotated-backup consumer ever
    appears, lift it then.

    Pure definitions at load (no Ashita/file touches until called), so the
    module is requirable from BOTH Lua states and the headless suite (tests SW*).
]]--

local M = {};

local function readFile(p)
    if p == nil then return nil; end
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end
local function writeFile(p, t)
    local f = io.open(p, 'w'); if f == nil then return false; end
    f:write(t); f:close(); return true;
end

-- dir\prefix<stamp>.lua. Creates dir when ashita.fs is reachable (guarded --
-- headless runs just write into an existing dir).
function M.timestampBackup(dir, prefix, text)
    if dir == nil or text == nil then return nil, 'bad args'; end
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(dir); end
    end);
    local path = dir .. (prefix or '') .. os.date('%Y%m%d_%H%M%S') .. '.lua';
    if not writeFile(path, text) then return nil, 'could not write backup'; end
    return path;
end

-- Replace a live Lua file, restoring opts.origText if anything fails after the
-- old file is gone. opts = { origText = current content (enables restore),
-- validate = fn(chunk, tmpPath) -> ok, err  (extra validation beyond parse;
-- the chunk is loadfile(tmp), never yet run) }.
function M.replaceLua(path, newText, opts)
    opts = opts or {};
    if path == nil or type(newText) ~= 'string' then return nil, 'bad args'; end
    if (loadstring or load)(newText) == nil then return nil, 'result would not parse'; end
    local tmp = path .. '.tmp';
    if not writeFile(tmp, newText) then return nil, 'could not write temp file'; end
    local chunk = loadfile(tmp);
    if chunk == nil then os.remove(tmp); return nil, 'temp failed to parse'; end
    if type(opts.validate) == 'function' then
        local vok, verr = opts.validate(chunk, tmp);
        if not vok then
            os.remove(tmp);
            return nil, 'would error on load: ' .. tostring(verr);
        end
    end
    os.remove(path);
    if not os.rename(tmp, path) then
        if opts.origText ~= nil then writeFile(path, opts.origText); end
        os.remove(tmp);
        return nil, 'rename failed' .. (opts.origText ~= nil and '; restored' or '');
    end
    if loadfile(path) == nil then
        if opts.origText ~= nil then writeFile(path, opts.origText); end
        return nil, 'post-write check failed' .. (opts.origText ~= nil and '; restored' or '');
    end
    return true;
end

-- Copy src -> dst, verify the copy byte-identical by reading it back, and only
-- then remove src. A failed remove reports where the intact copy lives.
function M.verifiedMove(src, dst)
    local t = readFile(src);
    if t == nil then return nil, 'source unreadable', true; end
    if not writeFile(dst, t) then return nil, 'copy failed'; end
    if readFile(dst) ~= t then return nil, 'copy verify failed'; end
    if not os.remove(src) then return nil, 'remove failed (copy kept at ' .. dst .. ')'; end
    return true;
end

return M;
