--[[
    dlac/profiles.lua -- the profile storage layer.

    A PROFILE is a named bundle of dlac-owned per-job data; one job's slice of
    it (the files below sharing one <JOB> name) is a JOB ENTRY:
        <char>\dlac\profiles\<Name>\sets\<JOB>.lua        committed Dynamic sets
        <char>\dlac\profiles\<Name>\triggers\<JOB>.lua    trigger rules
        <char>\dlac\profiles\<Name>\lockstyles\<JOB>.lua  lockstyle boxes (v41)
    The ACTIVE pointer lives in <char>\dlac\profile.lua (return { active = 'Name' }).
    LAC keeps auto-loading <JOB>.lua on a job change -- that file is (or becomes) a
    thin shim; the ENGINE resolves "active profile + current job" and installs the
    right data. So the profile picks the FOLDER and the job picks the FILE in it.

    Compatibility rule (one rule, everywhere):
      * READS  fall back per file: profile path first, else the legacy location
        (sets.Dynamic inside <JOB>.lua; dlac\triggers\<JOB>.lua). Unmigrated
        characters behave exactly as before.
      * WRITES always land in profile storage (creating 'Default' on first use).
        dlac never writes a <JOB>.lua again -- except the one-time opt-in
        migration, which backs the file up first and says so loudly.

    This module is loaded from BOTH Lua states (it is seeded to <char>\dlac\ next
    to utils/dispatch by dlac.lua), and headlessly by tests\run_tests.lua -- so
    every AshitaCore / fs touch happens at CALL time behind pcall, never at load.

    STORAGE HOMES (feature/native-engine): "<char>\dlac\" above describes the
    LEGACY home inside LuaAshitacast's config tree. When the native-engine flag
    is on (config\addons\dlac\engine.lua), the same tree lives under dlac's own
    root instead -- config\addons\dlac\<Name>_<Id>\ -- with no extra dlac\
    level. M.dataDir() / M.charRoot() / M.storageRoot() are the one seam; no
    other module composes these roots by hand.
]]--

local M = {};

M.JOBS = { 'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG',
           'SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN' };

-- The per-job file kinds a JOB ENTRY is made of (one folder per kind inside a
-- profile). Everything that copies/clones/renames/deletes/exports job entries
-- iterates THIS list, so a new kind rides the whole machinery at once.
M.KINDS = { 'sets', 'triggers', 'lockstyles' };

-- Verified-move safety net for the deleters (lib\safewrite: copy, read-back
-- verify, only then remove). Guarded: pure definitions, loads in both states;
-- if it is ever missing the DELETERS REFUSE rather than degrade -- nothing in
-- this module may remove a file without the verified copy.
local _swok, sw = pcall(require, 'dlac\\lib\\safewrite');
_swok = _swok and type(sw) == 'table';

-- ---------------------------------------------------------------------------
-- paths
-- ---------------------------------------------------------------------------

-- Character identity: LuaAshitacast's gState inside a profile, else the party
-- manager (addon state). name, id -- or nil, nil pre-login.
local function charIdentity()
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
    if name == nil or id == nil then return nil, nil; end
    return name, id;
end

-- '<Name>_<Id>' -- the per-character folder name, identical under both roots.
function M.charFolder()
    local name, id = charIdentity();
    if name == nil then return nil; end
    return string.format('%s_%u', name, id);
end

-- LuaAshitacast's per-char config home:
-- <install>\config\addons\luashitacast\<Name>_<id>\, or nil pre-login.
local function charBase()
    local cf = M.charFolder();
    if cf == nil then return nil; end
    local ok, p = pcall(function()
        return AshitaCore:GetInstallPath() .. 'config\\addons\\luashitacast\\' .. cf .. '\\';
    end);
    return ok and p or nil;
end
M.charBase = charBase;

-- ---------------------------------------------------------------------------
-- the native-engine storage home (feature/native-engine)
--
-- dlac's OWN config root -- config\addons\dlac\ -- replaces the piggyback on
-- LuaAshitacast's config tree when the NATIVE ENGINE flag is on. The flag is
-- one install-wide file (engine.lua under the native root: `return { native =
-- true }`), read throttled by BOTH Lua states, so the two can never disagree
-- about where storage lives. Layout under the native root:
--     config\addons\dlac\engine.lua                     the flag file
--     config\addons\dlac\<Name>_<Id>\profile.lua        the active pointer
--     config\addons\dlac\<Name>_<Id>\profiles\...       (no extra dlac\ level:
--     config\addons\dlac\<Name>_<Id>\gear.lua            this whole tree IS dlac's)
--     config\addons\dlac\<Name>_<Id>\backups\...
--     config\addons\dlac\dlac-exports\                  friend-share files
-- Every dlac-owned path composes off M.dataDir() / M.charRoot() below, so the
-- flag is the ONE seam the storage move rides. LAC-only concepts (job-file
-- shims, seeded engine copies) stay on charBase() unconditionally -- they only
-- mean anything when LuaAshitacast is the equip engine.
-- ---------------------------------------------------------------------------

function M.nativeRoot()
    local ok, p = pcall(function()
        return AshitaCore:GetInstallPath() .. 'config\\addons\\dlac\\';
    end);
    return ok and p or nil;
end

function M.engineFlagPath()
    local r = M.nativeRoot(); return r and (r .. 'engine.lua') or nil;
end

-- Pure flag-text parse (offline-tested): the file must load, return a table,
-- and carry native == true exactly. Anything else -- absent, damaged, partial,
-- truthy-but-not-true -- reads as OFF: the failure mode of a broken flag file
-- is the battle-tested LAC path, never a half-native limbo.
function M.parseEngineFlag(text)
    if type(text) ~= 'string' then return false; end
    local chunk = (loadstring or load)(text);
    if chunk == nil then return false; end
    if setfenv ~= nil then setfenv(chunk, {}); end   -- data file: runs against nothing
    local ok, t = pcall(chunk);
    return ok == true and type(t) == 'table' and t.native == true;
end

-- Throttled flag read (the activeName pattern: the other state -- or the user's
-- editor -- may rewrite it at any time, so a plain cache would go stale).
-- (Self-contained reader: this block sits above the module's shared readFile
-- local on purpose -- path authorities first, helpers after.)
local _nat = { at = -1, on = false };
function M.nativeMode()
    local now = os.time();
    if _nat.at == now then return _nat.on; end
    _nat.at = now;
    local on = false;
    pcall(function()
        local p = M.engineFlagPath();
        if p == nil then return; end
        local f = io.open(p, 'r');
        if f == nil then return; end
        local text = f:read('*a'); f:close();
        on = M.parseEngineFlag(text);
    end);
    _nat.on = on;
    return on;
end
function M.invalidateNative() _nat.at = -1; end

-- Write the flag file. true | nil, why. (The caller owns the user guidance --
-- flipping modes only takes effect for code that composes paths AFTER the
-- throttle window, and the engine command tells the user to reload.)
function M.setNativeMode(on)
    local p = M.engineFlagPath();
    if p == nil then return nil, 'not available'; end
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(M.nativeRoot()); end
    end);
    local text = '-- dlac engine flag -- written by /dl engine native on|off (hand edits are fine).\n'
        .. '-- native = true: dlac equips gear itself and stores data under config\\addons\\dlac\\.\n'
        .. '-- native = false (or file absent): LuaAshitacast equips; storage stays under its tree.\n'
        .. string.format('return { native = %s };\n', on == true and 'true' or 'false');
    local f = io.open(p, 'w');
    if f == nil then
        -- io.open never creates directories, and a FRESH install has no
        -- config\addons\dlac\ yet (field 2026-07-23, Henrik's sim -- the
        -- ashita.fs attempt above is not enough everywhere). Shell mkdir is
        -- the belt (the seedGearFile pattern), then one retry.
        pcall(function() os.execute('mkdir "' .. (M.nativeRoot():gsub('\\+$', '')) .. '" 2>nul'); end);
        f = io.open(p, 'w');
    end
    if f == nil then return nil, 'could not write ' .. p; end
    f:write(text); f:close();
    M.invalidateNative();
    return true;
end

-- This character's home under the native root.
function M.nativeCharBase()
    local r, cf = M.nativeRoot(), M.charFolder();
    if r == nil or cf == nil then return nil; end
    return r .. cf .. '\\';
end

-- The per-char home dlac-owned NON-dlac\ paths (backups\) compose off.
function M.charRoot()
    if M.nativeMode() then return M.nativeCharBase(); end
    return charBase();
end

-- THE dlac data home: profiles\, profile.lua pointer, gear.lua, modestate,
-- watcher state files, debug handoffs... -- everything dlac reads and writes
-- about a character lives under this one directory.
function M.dataDir()
    if M.nativeMode() then return M.nativeCharBase(); end
    local b = charBase();
    return b and (b .. 'dlac\\') or nil;
end

function M.pointerPath()
    local d = M.dataDir(); return d and (d .. 'profile.lua') or nil;
end
function M.profilesRoot()
    local d = M.dataDir(); return d and (d .. 'profiles\\') or nil;
end
function M.profileDir(name)
    local r = M.profilesRoot(); return r and (r .. name .. '\\') or nil;
end
function M.setsPath(job, name)
    local d = M.profileDir(name or M.activeName()); return d and (d .. 'sets\\' .. job .. '.lua') or nil;
end
function M.triggersPath(job, name)
    local d = M.profileDir(name or M.activeName()); return d and (d .. 'triggers\\' .. job .. '.lua') or nil;
end
function M.legacyTriggersPath(job)
    local d = M.dataDir(); return d and (d .. 'triggers\\' .. job .. '.lua') or nil;
end
-- Lockstyle boxes are PER JOB ENTRY (v41): this is where writes land. Reads
-- resolve through readLockstylesPath below.
function M.lockstylesPath(job, name)
    local d = M.profileDir(name or M.activeName()); return d and (d .. 'lockstyles\\' .. job .. '.lua') or nil;
end
-- The two read-fallback tiers lockstyle boxes have lived in before:
-- v40 kept ONE file per profile; before that, one global file per character.
function M.profileLockstylesPath(name)
    local d = M.profileDir(name or M.activeName()); return d and (d .. 'lockstyles.lua') or nil;
end
function M.legacyLockstylesPath()
    local d = M.dataDir(); return d and (d .. 'lockstyles.lua') or nil;
end
function M.jobFilePath(job)
    local b = charBase(); return b and (b .. job .. '.lua') or nil;
end
-- The migration backup home. backups\ is the established dlac backup dir
-- (setmanager rotation, gearimport); pre-profiles\ holds the ORIGINALS --
-- written once, never overwritten, and the Sets tab's "Copy from static"
-- keeps reading statics out of them forever.
function M.backupPath(job)
    local b = M.charRoot(); return b and (b .. 'backups\\pre-profiles\\' .. job .. '.lua') or nil;
end
function M.triggerBackupPath(job)
    local b = M.charRoot(); return b and (b .. 'backups\\pre-profiles\\triggers\\' .. job .. '.lua') or nil;
end
-- Re-migration safety copies: when a once-migrated job file holds logic AGAIN
-- (restored / hand-edited after the first migration), the live file is still
-- re-shimmed -- the FIRST backup stays untouched (it is the statics truth the
-- Sets tab imports from), and the current text lands in a stamped copy here.
function M.reshimBackupPath(job)
    local b = M.charRoot(); return b and (b .. 'backups\\pre-profiles\\' .. job .. '-' .. os.date('%Y%m%d_%H%M%S') .. '.lua') or nil;
end

local function readFile(p)
    if p == nil then return nil; end
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end
local function writeFile(p, t)
    if p == nil then return false; end
    local f = io.open(p, 'w'); if f == nil then return false; end
    f:write(t); f:close(); return true;
end
M._readFile = readFile;

-- The lockstyles file to LOAD for one job entry: the job's own file when it
-- exists, else the v40 per-profile file, else the pre-profile global
-- dlac\lockstyles.lua (each tier shipped a day apart -- existing boxes keep
-- appearing). nil when none exists or pre-login. The GUI and the engine
-- ('/dl ls apply') both resolve through here, so the two states can never
-- disagree on which file is live. Writes never come through here: they land
-- on lockstylesPath(job), and every save serializes ALL boxes, so older-tier
-- boxes migrate whole into the job entry on the first write.
function M.readLockstylesPath(job, name)
    local pj = M.lockstylesPath(job, name);
    if readFile(pj) ~= nil then return pj; end
    local pp = M.profileLockstylesPath(name);
    if readFile(pp) ~= nil then return pp; end
    local lp = M.legacyLockstylesPath();
    if readFile(lp) ~= nil then return lp; end
    return nil;
end

local function ensureDir(p)
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then ashita.fs.create_directory(p); end
    end);
end

-- mkdir -p for a path RELATIVE to base: creates each level of rel's directory
-- chain under base (rel itself is a file path; only its parents are created).
local function ensureDirChain(base, rel)
    local acc = base;
    for part in rel:gmatch('([^\\]+)\\') do
        acc = acc .. part .. '\\';
        ensureDir(acc);
    end
end

-- Create the whole storage skeleton for a profile (+ the pointer if absent, so
-- storageExists() flips true the moment anything profile-shaped is created).
function M.ensureStorage(name)
    name = name or M.activeName();
    local d = M.dataDir(); if d == nil then return false; end
    if M.nativeMode() then ensureDir(M.nativeRoot()); end   -- parent of the char home
    ensureDir(d);
    ensureDir(d .. 'profiles\\');
    ensureDir(d .. 'profiles\\' .. name .. '\\');
    for _, kind in ipairs(M.KINDS) do
        ensureDir(d .. 'profiles\\' .. name .. '\\' .. kind .. '\\');
    end
    if readFile(M.pointerPath()) == nil then M.setActive(name); end
    return true;
end

-- ---------------------------------------------------------------------------
-- active profile pointer
-- ---------------------------------------------------------------------------

-- Profile names travel through chat commands and become folder names: keep them
-- to one word of [A-Za-z0-9_-]. Returns the name or nil.
function M.sanitizeName(name)
    if type(name) ~= 'string' then return nil; end
    return name:match('^[%w_%-]+$');
end

-- Throttled to one disk read per second (the lock-mirror pattern): the OTHER Lua
-- state may rewrite the pointer at any time, so a plain cache would go stale.
local _act = { at = -1, name = nil };
function M.activeName()
    local now = os.time();
    if _act.at == now and _act.name ~= nil then return _act.name; end
    _act.at = now;
    local nm = 'Default';
    pcall(function()
        local p = M.pointerPath();
        if p == nil then return; end   -- loadfile(nil) reads STDIN -- hangs headless runs
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' and M.sanitizeName(t.active) then nm = t.active; end
    end);
    _act.name = nm;
    return nm;
end
function M.invalidate() _act.at = -1; _act.name = nil; end

function M.setActive(name)
    name = M.sanitizeName(name);
    if name == nil then return false, 'bad profile name (letters/digits/_/- only)'; end
    local p = M.pointerPath();
    if p == nil then return false, 'not logged in'; end
    local b = charBase();
    ensureDir(b .. 'dlac\\');
    local ok = writeFile(p, string.format(
        '-- dlac active profile pointer -- written by /dl profile use (hand edits are fine).\nreturn { active = %q };\n', name));
    M.invalidate();
    return ok, ok and nil or ('could not write ' .. p);
end

-- Storage exists iff the pointer file does. Every creator (ensureStorage, migrate,
-- first commit) writes the pointer, so this stays a single deterministic signal.
-- A hand-dropped profiles\ folder becomes live via /dl profile use <name>.
function M.storageExists()
    return readFile(M.pointerPath()) ~= nil;
end

-- ashita.fs.get_dir FIELD SEMANTICS (screenshot-verified 2026-07-13): the mask
-- is a REGEX, not a Lua pattern -- '.*%.lua' matches NOTHING (the '%' is
-- literal), which is why profile file lists came back empty; and the third
-- argument means RECURSIVE -- true returns relative paths of files AND
-- directories ('Default\sets\BLU.lua'), which is how the whole subtree got
-- listed as "profiles". So: always mask '.*', never recurse, filter Lua-side.
local function rawList(path)
    if path == nil then return nil; end
    local out = nil;
    pcall(function()
        if not (ashita and ashita.fs and ashita.fs.get_dir) then return; end
        local ok, t = pcall(ashita.fs.get_dir, path, '.*', false);
        if ok and type(t) == 'table' then out = t; end
    end);
    return out;
end

-- Best-effort name listing (files and dirs MIXED -- get_dir does not say
-- which; callers filter by shape). Shell `dir /b /ad` fallback is dirs-only.
local function listDirs(path)
    if path == nil then return nil; end
    local out = rawList(path);
    if out ~= nil then
        local acc = {};
        for _, d in ipairs(out) do
            if type(d) == 'string' and d ~= '.' and d ~= '..' then acc[#acc + 1] = d; end
        end
        out = acc;
    else
        pcall(function()
            local p = io.popen('dir /b /ad "' .. path .. '" 2>nul');
            if p == nil then return; end
            local acc = {};
            for line in p:lines() do
                line = line:gsub('%s+$', '');
                if line ~= '' then acc[#acc + 1] = line; end
            end
            p:close();
            out = acc;
        end);
    end
    if out ~= nil then table.sort(out); end
    return out;
end
M._listDirs = listDirs;   -- injectable: the first-run scan's listing seam (tests NO43+ drive nil/{}/content)

-- Best-effort *.lua basenames in a directory (get_dir file mode is the
-- field-proven setmanager pattern; `dir /b` popen fallback). nil when both
-- APIs fail; {} when the directory is empty/missing.
local function listLuaFiles(path)
    if path == nil then return nil; end
    local out = nil;
    do
        local raw = rawList(path);   -- mask must be '.*' (regex); filter here
        if raw ~= nil then
            out = {};
            for _, f in ipairs(raw) do
                if type(f) == 'string' then
                    local b = f:match('^(.+)%.lua$');
                    if b ~= nil then out[#out + 1] = b; end
                end
            end
        end
    end
    if out == nil then
        pcall(function()
            local p = io.popen('dir /b "' .. path .. '*.lua" 2>nul');
            if p == nil then return; end
            local acc = {};
            for line in p:lines() do
                local b = line:gsub('%s+$', ''):match('^(.+)%.lua$');
                if b ~= nil then acc[#acc + 1] = b; end
            end
            p:close();
            out = acc;
        end);
    end
    return out;
end

-- Best-effort list of THIS character's profile folder names (nil when no
-- listing API works -- callers should fall back to naming the active profile).
function M.listProfiles()
    return listDirs(M.profilesRoot());
end

-- ---------------------------------------------------------------------------
-- cross-character browsing + import (the Profiles menu)
--
-- Every character on the install has its own <Name>_<ServerId> folder under
-- config\addons\luashitacast\ -- that folder IS the account/character axis.
-- A dlac profile is just files, so import = copy a profile's per-job files
-- from another character's storage into this character's, under a new name.
-- ---------------------------------------------------------------------------

function M.lacRoot()
    local ok, p = pcall(function()
        return AshitaCore:GetInstallPath() .. 'config\\addons\\luashitacast\\';
    end);
    return ok and p or nil;
end

-- The root character folders live under in the ACTIVE storage home. Native
-- mode browses config\addons\dlac\; legacy mode browses LuaAshitacast's tree.
-- (Cross-char browse/import works within the active home -- each character's
-- data arrives there via the auto-migration, so post-flip everything is here.)
function M.storageRoot()
    if M.nativeMode() then return M.nativeRoot(); end
    return M.lacRoot();
end

-- A character's dlac DATA home under the active root. The native layout has no
-- extra dlac\ level (the whole tree is dlac's); the legacy layout nests one.
function M.charDataDirAt(charFolder)
    local root = M.storageRoot();
    if root == nil or charFolder == nil then return nil; end
    if M.nativeMode() then return root .. charFolder .. '\\'; end
    return root .. charFolder .. '\\dlac\\';
end

-- Character folders (<Name>_<Id>), current one first, rest alphabetical.
function M.listCharFolders()
    local root = M.storageRoot();
    local dirs = listDirs(root);
    if dirs == nil then return nil; end
    local cur = M.charFolder();
    local out = {};
    for _, d in ipairs(dirs) do
        if d:match('^%a+_%d+$') then   -- STRICTLY <CharName>_<ServerId>; nothing else qualifies
            if d == cur then table.insert(out, 1, d); else out[#out + 1] = d; end
        end
    end
    return out, cur;
end

function M.currentCharFolder()
    return M.charFolder();
end

-- ---------------------------------------------------------------------------
-- Native-first onboarding (ADR 0015 ruling 4)
--
-- A FRESH install (no Engine flag AND no legacy dlac data on the whole install)
-- is born native: the flag is written native=true on first run, storage lives
-- in dlac's own root, and no LuaAshitacast tree is ever created. An existing
-- user is NEVER auto-flipped -- legacy data present, or a flag already on disk,
-- means current behavior EXACTLY (a flag is honored, never rewritten by boot).
-- The decision is a pure seam (firstRunAction, headless-tested); firstRunInit
-- runs it once, writes the flag only for the fresh case, and is idempotent.
-- ---------------------------------------------------------------------------

-- The flag file as one of three states -- 'native' | 'legacy' | 'absent'. A
-- present-but-broken file reads as 'legacy' (present): a fresh-install write
-- must never clobber a file the user already has, so anything on disk is
-- honored (parseEngineFlag decides its VALUE; existence alone decides 'absent').
function M.engineFlagState()
    local p = M.engineFlagPath();
    if p == nil then return 'absent'; end
    local f = io.open(p, 'r');
    if f == nil then return 'absent'; end
    local text = f:read('*a'); f:close();
    return M.parseEngineFlag(text) and 'native' or 'legacy';
end

-- Any character on this install with LEGACY dlac data under LuaAshitacast's tree
-- (config\addons\luashitacast\<char>\dlac\)? Returns present, scanned, evidence
-- (the first matching char folder -- the loud boot line names it). scanned is
-- false only when the listing APIs genuinely failed -- the caller must NOT treat
-- "couldn't tell" as "fresh" (an existing legacy user would be wrongly flipped).
-- FIELD 2026-07-23 (Henrik's fresh-install sim): in-game, ashita.fs.get_dir
-- returns nil for a MISSING directory -- the same shape as an API failure --
-- while the headless popen fallback returns {} (the tests masked the field
-- behavior). A nil root listing is now DISAMBIGUATED by listing the PARENT
-- (config\addons\): luashitacast\ absent there is a definite "no legacy data
-- anywhere" -- exactly the fresh install -- not a can't-tell.
-- M._listDirs / M._legacyProbe are the injectable seams (headless: NO43+).
function M.legacyDataPresent()
    local root = M.lacRoot();
    if root == nil then return false, false, nil; end   -- install path unknown -> can't tell
    local dirs = M._listDirs(root);
    if dirs == nil then
        local parent = M._listDirs((root:gsub('luashitacast\\+$', '')));
        if parent ~= nil then
            for _, d in ipairs(parent) do
                if type(d) == 'string' and d:lower() == 'luashitacast' then
                    return false, false, nil;   -- root exists but will not list -> genuinely can't tell
                end
            end
            return false, true, nil;   -- no luashitacast\ under config\addons\ -> definite fresh
        end
        return false, false, nil;      -- both listings failed -> can't tell
    end
    for _, d in ipairs(dirs) do
        if d:match('^%a+_%d+$') then
            if M._legacyProbe(root .. d .. '\\dlac\\') then return true, true, d; end
        end
    end
    return false, true, nil;   -- scanned, none found -> fresh
end
-- The per-char probe: does this <char>\dlac\ hold real legacy data? profile.lua
-- (the storage pointer every creator writes) or gear.lua (a pre-storage-move
-- user's scan). Injectable for the headless matrix.
function M._legacyProbe(dd)
    return readFile(dd .. 'profile.lua') ~= nil or readFile(dd .. 'gear.lua') ~= nil;
end

-- PURE first-run decision (headless-tested). flagState in {'native','legacy',
-- 'absent'}; legacyPresent boolean. Returns the boot action:
--   'respect'      -> a flag is already on disk: honor it, never rewrite
--   'legacy'       -> no flag but legacy data present: stay legacy, write nothing
--   'write-native' -> no flag, no legacy data: fresh install -> born native
function M.firstRunAction(flagState, legacyPresent)
    if flagState ~= 'absent' then return 'respect'; end
    if legacyPresent then return 'legacy'; end
    return 'write-native';
end

-- Boot seam: run the decision once and, for a FRESH install ONLY, arm the Engine
-- flag native. Idempotent -- a written flag makes engineFlagState() ~= 'absent'
-- forever after, so re-runs return 'respect'. Returns the action, or nil when it
-- could not decide yet (listing not available / flag write failed) so the caller
-- retries on the next beat rather than latching a half-answer -- and HOLDS ALL
-- STORAGE WRITERS meanwhile (dlac.lua maintainStorage): an undecided beat must
-- stay INERT, or dlac seeds the legacy home and then reads its own files as
-- "existing legacy user" (Henrik's 2026-07-23 fresh-install sim -- the
-- self-manufactured-evidence bug). A RESOLVED decision is silent (the player
-- is not told about first runs or engines); the two FAILURE modes warn once --
-- silence has no author, and a broken boot should name its own domino.
local _firstRun = { done = false, action = nil, warned = false };
function M.firstRunInit()
    if _firstRun.done then return _firstRun.action; end
    local flagState = M.engineFlagState();
    local present = true;
    if flagState == 'absent' then
        local ok;
        present, ok = M.legacyDataPresent();
        if not ok then
            if not _firstRun.warned then
                _firstRun.warned = true;
                pcall(function() print('[dlac] first-run: cannot scan for legacy data yet (listing unavailable)'
                    .. ' -- deciding nothing, WRITING nothing, retrying each beat.'); end);
            end
            return nil;   -- not latched -- retry next beat, all writers held
        end
    end
    local action = M.firstRunAction(flagState, present);
    if action == 'write-native' then
        local okw, whyw = M.setNativeMode(true);
        if okw ~= true then
            if not _firstRun.warned then
                _firstRun.warned = true;
                pcall(function() print('[dlac] first-run: FRESH install detected but the engine flag could not be'
                    .. ' written (' .. tostring(whyw) .. ') -- staying inert, retrying each beat.'); end);
            end
            return nil;   -- not latched -- retry next beat, all writers held
        end
    end
    _firstRun.done = true; _firstRun.action = action;
    -- A RESOLVED decision is SILENT (Henrik, 07-23, after the field confirm:
    -- the general player must not be told it is a first run or which engine
    -- runs -- things just work). The legacy nudge lives in the GUI (banner +
    -- Migrate button), not chat. Only the two FAILURE warns above speak, and
    -- only when something is genuinely broken -- those stay: silence has no
    -- author, and they are invisible to a healthy install by construction.
    return action;
end
function M._resetFirstRun() _firstRun.done = false; _firstRun.action = nil; _firstRun.warned = false; end   -- headless test seam

-- The LAC-alive polite ask, gated to ONCE per session (ADR 0015 ruling 4). PURE
-- gate: fed the live "is LuaAshitacast alive?" reading, it returns true the FIRST
-- time that is true and latches, so the ask fires exactly once. The coexistence
-- tripwire stays the hard backstop; this is the gentle first word.
local _asked = false;
function M.shouldAskUnloadLac(lacAlive)
    if _asked then return false; end
    if lacAlive ~= true then return false; end
    _asked = true;
    return true;
end
function M._resetAskGate() _asked = false; end   -- headless test seam

function M.profileDirAt(charFolder, name)
    local d = M.charDataDirAt(charFolder);
    if d == nil or name == nil then return nil; end
    return d .. 'profiles\\' .. name .. '\\';
end

function M.listProfilesAt(charFolder)
    local d = M.charDataDirAt(charFolder);
    if d == nil then return nil; end
    local names = listDirs(d .. 'profiles\\');
    if names == nil then return nil; end
    -- get_dir mixes files into the listing: only sanitize-clean names can be
    -- profile FOLDERS (a stray file has a dot; sanitize rejects it).
    local out = {};
    for _, n in ipairs(names) do
        if M.sanitizeName(n) ~= nil then out[#out + 1] = n; end
    end
    return out;
end

-- Which jobs a profile carries (deterministic 22-job probe, no listing API):
-- array of { job, sets = bool, trig = bool, ls = bool }, only jobs with at
-- least one file.
function M.profileJobsAt(charFolder, name)
    local dir = M.profileDirAt(charFolder, name);
    if dir == nil then return {}; end
    local out = {};
    for _, job in ipairs(M.JOBS) do
        local s = readFile(dir .. 'sets\\' .. job .. '.lua') ~= nil;
        local t = readFile(dir .. 'triggers\\' .. job .. '.lua') ~= nil;
        local l = readFile(dir .. 'lockstyles\\' .. job .. '.lua') ~= nil;
        if s or t or l then out[#out + 1] = { job = job, sets = s, trig = t, ls = l }; end
    end
    return out;
end

-- Copy every per-job file from one profile dir to another. Never overwrites.
local function copyJobFiles(srcDir, dstDir)
    if srcDir == nil or dstDir == nil then return 0; end
    local copied = 0;
    for _, job in ipairs(M.JOBS) do
        for _, kind in ipairs(M.KINDS) do
            local t = readFile(srcDir .. kind .. '\\' .. job .. '.lua');
            local dp = dstDir .. kind .. '\\' .. job .. '.lua';
            if t ~= nil and readFile(dp) == nil then
                if writeFile(dp, t) then copied = copied + 1; end
            end
        end
    end
    return copied;
end

-- Does this character's profile <name> already hold any files? (66-file probe.)
local function profileHasFiles(name)
    for _, job in ipairs(M.JOBS) do
        if M.hasSetsFile(job, name) or M.hasTriggersFile(job, name)
           or readFile(M.lockstylesPath(job, name)) ~= nil then return true; end
    end
    return false;
end

-- Every per-job file a profile holds, by ACTUAL listing (not the 22-job
-- probe): includes dormant non-job-named files (e.g. a "BLU-old" archive), so
-- the browser shows what is really there. Array of { name, sets, trig, ls },
-- known jobs first (JOBS order), the rest alphabetical.
local JOB_ORDER = {};
for i, j in ipairs(M.JOBS) do JOB_ORDER[j] = i; end
function M.listProfileFilesAt(charFolder, name)
    local dir = M.profileDirAt(charFolder, name);
    if dir == nil then return {}; end
    local map = {};
    for _, b in ipairs(listLuaFiles(dir .. 'sets\\') or {}) do
        map[b] = map[b] or { name = b }; map[b].sets = true;
    end
    for _, b in ipairs(listLuaFiles(dir .. 'triggers\\') or {}) do
        map[b] = map[b] or { name = b }; map[b].trig = true;
    end
    for _, b in ipairs(listLuaFiles(dir .. 'lockstyles\\') or {}) do
        map[b] = map[b] or { name = b }; map[b].ls = true;
    end
    local out = {};
    for _, e in pairs(map) do out[#out + 1] = e; end
    table.sort(out, function(a, b)
        local ja, jb = JOB_ORDER[a.name], JOB_ORDER[b.name];
        if ja ~= nil and jb ~= nil then return ja < jb; end
        if ja ~= nil then return true; end
        if jb ~= nil then return false; end
        return a.name < b.name;
    end);
    return out;
end

function M.profileHasFilesAt(charFolder, name)
    return #M.listProfileFilesAt(charFolder, name) > 0;
end

-- Does a listProfileFilesAt entry carry this kind? One authority for the
-- flag-name mapping (clone and delete both filter through it).
local function entryHasKind(e, kind)
    return (kind == 'sets' and e.sets) or (kind == 'triggers' and e.trig)
        or (kind == 'lockstyles' and e.ls);
end

-- Storage skeleton on an ARBITRARY character (clone-to target). Does NOT touch
-- their active pointer -- the profile goes live only when they `use` it.
local function ensureStorageAt(charFolder, name)
    local d = M.charDataDirAt(charFolder);
    if d == nil or name == nil then return false; end
    if M.nativeMode() then ensureDir(M.nativeRoot()); end
    ensureDir(d);
    ensureDir(d .. 'profiles\\');
    ensureDir(d .. 'profiles\\' .. name .. '\\');
    for _, kind in ipairs(M.KINDS) do
        ensureDir(d .. 'profiles\\' .. name .. '\\' .. kind .. '\\');
    end
    return true;
end

-- Does a profile NAME already exist under a character -- as a folder (even an
-- empty one) or as files? The create/clone collision authority.
function M.profileNameExistsAt(charFolder, name)
    local existing = M.listProfilesAt(charFolder);
    if existing ~= nil then
        for _, n in ipairs(existing) do
            if n == name then return true; end
        end
    end
    return M.profileHasFilesAt(charFolder, name);
end

-- Create an EMPTY profile under any character. Refuses existing names.
-- true, nil | nil, why.
function M.createProfileAt(charFolder, name)
    name = M.sanitizeName(name);
    if name == nil then return nil, 'bad name (letters/digits/_/- only)'; end
    if charFolder == nil then return nil, 'bad character'; end
    if M.profileNameExistsAt(charFolder, name) then
        return nil, 'name collision: "' .. name .. '" already exists there';
    end
    if not ensureStorageAt(charFolder, name) then return nil, 'could not create storage'; end
    return true, nil;
end

-- Clone a whole profile to any character (including this one, under a new
-- name). Refuses a destination that already has files. copiedCount | nil, why.
function M.cloneProfileTo(srcCharFolder, srcName, dstCharFolder, dstName)
    dstName = M.sanitizeName(dstName);
    if dstName == nil then return nil, 'bad target name (letters/digits/_/- only)'; end
    local srcDir = M.profileDirAt(srcCharFolder, srcName);
    local dstDir = M.profileDirAt(dstCharFolder, dstName);
    if srcDir == nil or dstDir == nil then return nil, 'bad source/destination'; end
    if srcCharFolder == dstCharFolder and srcName == dstName then return nil, 'source and destination are the same profile'; end
    if M.profileHasFilesAt(dstCharFolder, dstName) then
        return nil, 'name collision: "' .. dstName .. '" already has files on that character';
    end
    if not ensureStorageAt(dstCharFolder, dstName) then return nil, 'could not create storage'; end
    local n = 0;
    for _, e in ipairs(M.listProfileFilesAt(srcCharFolder, srcName)) do
        for _, kind in ipairs(M.KINDS) do
            if entryHasKind(e, kind) then
                local t = readFile(srcDir .. kind .. '\\' .. e.name .. '.lua');
                local dp = dstDir .. kind .. '\\' .. e.name .. '.lua';
                if t ~= nil and readFile(dp) == nil and writeFile(dp, t) then n = n + 1; end
            end
        end
    end
    if n == 0 then return nil, 'nothing copied (source profile empty or unreadable)'; end
    return n, nil;
end

-- Is a per-job (or dormant) name taken inside a destination profile?
function M.jobNameTakenAt(charFolder, profName, name)
    local dir = M.profileDirAt(charFolder, profName);
    if dir == nil or name == nil then return false; end
    for _, kind in ipairs(M.KINDS) do
        if readFile(dir .. kind .. '\\' .. name .. '.lua') ~= nil then return true; end
    end
    return false;
end

-- Clone ONE job's data (sets + triggers) into any character/profile under
-- dstName. dstName must be a real job abbr to be LIVE there; any other
-- sanitized name is copied as a dormant archive (the engine only reads
-- <JOB>.lua). Refuses when dstName is taken. copiedCount | nil, why.
function M.copyJobTo(srcCharFolder, srcProf, job, dstCharFolder, dstProf, dstName)
    dstName = M.sanitizeName(dstName);
    if dstName == nil then return nil, 'bad name (letters/digits/_/- only)'; end
    dstProf = M.sanitizeName(dstProf);
    if dstProf == nil then return nil, 'bad profile name (letters/digits/_/- only)'; end
    local srcDir = M.profileDirAt(srcCharFolder, srcProf);
    local dstDir = M.profileDirAt(dstCharFolder, dstProf);
    if srcDir == nil or dstDir == nil then return nil, 'bad source/destination'; end
    if srcCharFolder == dstCharFolder and srcProf == dstProf and job == dstName then
        return nil, 'source and destination are the same file';
    end
    if M.jobNameTakenAt(dstCharFolder, dstProf, dstName) then
        return nil, 'name collision: "' .. dstName .. '" already exists in that profile';
    end
    if not ensureStorageAt(dstCharFolder, dstProf) then return nil, 'could not create storage'; end
    local n = 0;
    for _, kind in ipairs(M.KINDS) do
        local t = readFile(srcDir .. kind .. '\\' .. job .. '.lua');
        if t ~= nil then
            local dp = dstDir .. kind .. '\\' .. dstName .. '.lua';
            if readFile(dp) == nil and writeFile(dp, t) then n = n + 1; end
        end
    end
    if n == 0 then return nil, 'nothing copied (no files for ' .. tostring(job) .. ')'; end
    return n, nil;
end

-- Rename one of THIS character's profiles (folder rename; repoints the active
-- pointer when the renamed profile is the active one). true | nil, why.
function M.renameProfile(oldName, newName)
    newName = M.sanitizeName(newName);
    if newName == nil then return nil, 'bad name (letters/digits/_/- only)'; end
    if oldName == newName then return nil, 'same name'; end
    local root = M.profilesRoot();
    if root == nil then return nil, 'not logged in'; end
    local cur = M.currentCharFolder();
    if M.profileHasFilesAt(cur, newName) then
        return nil, 'name collision: "' .. newName .. '" already has files';
    end
    local ok, oerr = os.rename(root .. oldName, root .. newName);
    if not ok then return nil, 'rename failed: ' .. tostring(oerr); end
    if M.activeName() == oldName then M.setActive(newName); end
    return true, nil;
end

-- Rename one job entry (sets + triggers together) inside any character's
-- profile. Renaming AWAY from a job abbr makes it dormant (a backup slot);
-- renaming a dormant copy TO a job abbr revives it. renamedCount | nil, why.
function M.renameJobAt(charFolder, profName, oldName, newName)
    newName = M.sanitizeName(newName);
    if newName == nil then return nil, 'bad name (letters/digits/_/- only)'; end
    if oldName == newName then return nil, 'same name'; end
    if M.jobNameTakenAt(charFolder, profName, newName) then
        return nil, 'name collision: "' .. newName .. '" already exists in that profile';
    end
    local dir = M.profileDirAt(charFolder, profName);
    if dir == nil then return nil, 'bad profile'; end
    local n = 0;
    for _, kind in ipairs(M.KINDS) do
        local sp = dir .. kind .. '\\' .. oldName .. '.lua';
        if readFile(sp) ~= nil then
            if os.rename(sp, dir .. kind .. '\\' .. newName .. '.lua') then n = n + 1; end
        end
    end
    if n == 0 then return nil, 'nothing renamed (no files for ' .. tostring(oldName) .. ')'; end
    return n, nil;
end

-- Delete a whole profile -- but "never delete backups" is the house rule, so
-- every file is FIRST copied (and read back verified) into that character's
-- backups\deleted-profiles\<prof>-<stamp>\; only verified files are removed.
-- The current character's ACTIVE profile is refused outright. Empty dirs are
-- swept best-effort (rmdir refuses non-empty, so unknown files keep the
-- profile visible instead of being destroyed). deletedCount, backupDir | nil, why.
function M.deleteProfileAt(charFolder, profName)
    if charFolder == nil or profName == nil then return nil, 'bad args'; end
    if not _swok then return nil, 'safewrite module unavailable -- deletion refused'; end
    if charFolder == M.currentCharFolder() and profName == M.activeName() then
        return nil, 'that is the ACTIVE profile -- switch first (/dl profile use <other>)';
    end
    local root = M.storageRoot();
    local dir = M.profileDirAt(charFolder, profName);
    if root == nil or dir == nil then return nil, 'bad profile'; end
    local files = M.listProfileFilesAt(charFolder, profName);
    if #files == 0 then
        -- nothing inside: just sweep the (empty) folders
        for _, kind in ipairs(M.KINDS) do
            pcall(os.execute, 'rmdir "' .. dir .. kind .. '" 2>nul');
        end
        pcall(os.execute, 'rmdir "' .. dir:sub(1, -2) .. '" 2>nul');
        return 0, '(profile was empty -- no safety copy needed)';
    end
    local bdir = root .. charFolder .. '\\backups\\deleted-profiles\\' .. profName .. '-' .. os.date('%Y%m%d_%H%M%S') .. '\\';
    ensureDir(root .. charFolder .. '\\backups\\');
    ensureDir(root .. charFolder .. '\\backups\\deleted-profiles\\');
    ensureDir(bdir);
    for _, kind in ipairs(M.KINDS) do
        ensureDir(bdir .. kind .. '\\');
    end
    local removed, failed = 0, 0;
    for _, e in ipairs(files) do
        for _, kind in ipairs(M.KINDS) do
            if entryHasKind(e, kind) then
                local sp = dir .. kind .. '\\' .. e.name .. '.lua';
                local bp = bdir .. kind .. '\\' .. e.name .. '.lua';
                if sw.verifiedMove(sp, bp) then
                    removed = removed + 1;
                else
                    failed = failed + 1;
                end
            end
        end
    end
    for _, kind in ipairs(M.KINDS) do
        pcall(os.execute, 'rmdir "' .. dir .. kind .. '" 2>nul');
    end
    pcall(os.execute, 'rmdir "' .. dir:sub(1, -2) .. '" 2>nul');
    if failed > 0 then
        return nil, string.format('%d file(s) could not be verified+removed -- the rest are safe in %s', failed, bdir);
    end
    return removed, bdir;
end

-- Delete ONE job entry (sets + triggers together) from any character's
-- profile. Same house rule as profile deletion: flat, verified safety copies
-- land in that character's backups\deleted-jobs\ BEFORE anything is removed.
-- removedCount, backupDir | nil, why.
function M.deleteJobAt(charFolder, profName, name)
    if charFolder == nil or profName == nil or name == nil then return nil, 'bad args'; end
    if not _swok then return nil, 'safewrite module unavailable -- deletion refused'; end
    local root = M.storageRoot();
    local dir = M.profileDirAt(charFolder, profName);
    if root == nil or dir == nil then return nil, 'bad profile'; end
    local bdir = root .. charFolder .. '\\backups\\deleted-jobs\\';
    ensureDir(root .. charFolder .. '\\backups\\');
    ensureDir(bdir);
    local stamp = os.date('%Y%m%d_%H%M%S');
    local removed, failed = 0, 0;
    for _, kind in ipairs(M.KINDS) do
        local sp = dir .. kind .. '\\' .. name .. '.lua';
        local bp = bdir .. profName .. '-' .. name .. '-' .. stamp .. '-' .. kind .. '.lua';
        -- a missing kind file is a skip (a job entry rarely has all kinds),
        -- never a failure -- only a real copy/verify/remove problem counts
        local mok, _, missing = sw.verifiedMove(sp, bp);
        if mok then removed = removed + 1;
        elseif not missing then failed = failed + 1; end
    end
    if failed > 0 then return nil, string.format('%d file(s) could not be verified+removed', failed); end
    if removed == 0 then return nil, 'nothing to delete (no files for ' .. tostring(name) .. ')'; end
    return removed, bdir;
end

-- ---------------------------------------------------------------------------
-- per-job export / import (friend sharing)
--
-- One file = one job's dlac data (sets + triggers), verbatim, %q-encoded in a
-- plain `return {...}` Lua file. Files live in the install-wide
-- config\addons\luashitacast\dlac-exports\ -- send the file; the friend drops
-- it into THEIR dlac-exports\ and imports it from the Profiles menu (choosing
-- character / profile / name, collision-gated like everything else).
-- ---------------------------------------------------------------------------

function M.exportsDir()
    local root = M.storageRoot();
    return root and (root .. 'dlac-exports\\') or nil;
end

-- The OTHER home's exports dir (nil when it equals the active one): native
-- mode keeps seeing files friends dropped in the old LuaAshitacast location,
-- so a mode flip never hides a shared export.
function M.legacyExportsDir()
    if not M.nativeMode() then return nil; end
    local root = M.lacRoot();
    return root and (root .. 'dlac-exports\\') or nil;
end

-- Pure text builders (offline-tested round trip). The lockstyles and weights
-- fields are optional and still "job-export v1": readers that predate them
-- ignore the keys (weights = a gearweights-format fragment, 2026-07-19).
function M.buildExportText(job, profName, from, setsText, trigText, lsText, weightsText)
    local parts = {
        '-- dlac job export -- ' .. tostring(job) .. ' from profile "' .. tostring(profName) .. '" (' .. tostring(from) .. ')',
        '-- Import: drop this file into config\\addons\\luashitacast\\dlac-exports\\ and use the dlac Profiles menu.',
        'return {',
        '    dlac    = "job-export v1",',
        string.format('    job     = %q,', tostring(job)),
        string.format('    profile = %q,', tostring(profName)),
        string.format('    from    = %q,', tostring(from)),
    };
    if setsText ~= nil then parts[#parts + 1] = string.format('    sets     = %q,', setsText); end
    if trigText ~= nil then parts[#parts + 1] = string.format('    triggers = %q,', trigText); end
    if lsText ~= nil then parts[#parts + 1] = string.format('    lockstyles = %q,', lsText); end
    if weightsText ~= nil then parts[#parts + 1] = string.format('    weights = %q,', weightsText); end
    parts[#parts + 1] = '};';
    return table.concat(parts, '\n') .. '\n';
end

function M.parseExportText(text)
    if type(text) ~= 'string' then return nil, 'no text'; end
    local chunk = (loadstring or load)(text);
    if chunk == nil then return nil, 'file does not parse'; end
    if setfenv ~= nil then setfenv(chunk, {}); end   -- data file: runs against nothing
    local ok, t = pcall(chunk);
    if not ok or type(t) ~= 'table' or t.dlac ~= 'job-export v1' or type(t.job) ~= 'string'
       or (type(t.sets) ~= 'string' and type(t.triggers) ~= 'string' and type(t.lockstyles) ~= 'string'
           and type(t.weights) ~= 'string') then
        return nil, 'not a dlac job export';
    end
    return t, nil;
end

-- Resolve one export basename to the file's text: the active home first, the
-- legacy home second (native mode only) -- see legacyExportsDir.
local function readExportText(fileBase)
    local ed = M.exportsDir();
    local t = ed and readFile(ed .. tostring(fileBase) .. '.lua') or nil;
    if t ~= nil then return t; end
    local led = M.legacyExportsDir();
    return led and readFile(led .. tostring(fileBase) .. '.lua') or nil;
end

-- Parsed meta of one dlac-exports file (the import side's reader; the
-- Profiles menu uses it to hand the weights payload to gearoptim).
function M.readExportFile(fileBase)
    if M.exportsDir() == nil then return nil, 'not available'; end
    return M.parseExportText(readExportText(fileBase));
end

-- Write <exportsDir>\<Job>-<Profile>-<Char>-<stamp>.lua. path | nil, why.
-- `payloads` (optional) = pre-built texts { sets, triggers, lockstyles,
-- weights } from the selective export (gear/profileexport.lua); absent, the
-- three profile files travel verbatim -- the original everything export.
function M.exportJob(charFolder, profName, job, payloads)
    local dir = M.profileDirAt(charFolder, profName);
    local ed = M.exportsDir();
    if dir == nil or ed == nil then return nil, 'not available (log in first?)'; end
    local setsText, trigText, lsText, wText;
    if type(payloads) == 'table' then
        setsText, trigText, lsText, wText = payloads.sets, payloads.triggers, payloads.lockstyles, payloads.weights;
    else
        setsText = readFile(dir .. 'sets\\' .. job .. '.lua');
        trigText = readFile(dir .. 'triggers\\' .. job .. '.lua');
        lsText   = readFile(dir .. 'lockstyles\\' .. job .. '.lua');
    end
    if setsText == nil and trigText == nil and lsText == nil and wText == nil then return nil, 'nothing to export (no files for ' .. tostring(job) .. ')'; end
    ensureDir(ed);
    local short = charFolder:match('^(.-)_%d+$') or charFolder;
    local path = ed .. string.format('%s-%s-%s-%s.lua', job, profName, short, os.date('%Y%m%d_%H%M%S'));
    local text = M.buildExportText(job, profName, short, setsText, trigText, lsText, wText);
    if not writeFile(path, text) or readFile(path) ~= text then return nil, 'could not write ' .. path; end
    return path, nil;
end

-- Valid export files in dlac-exports\: { file, job, profile, from, sets, trig, ls }.
-- Native mode merges the legacy home's files in (active home wins a name tie).
function M.listExports()
    local ed = M.exportsDir();
    if ed == nil then return nil; end
    local files = listLuaFiles(ed);
    if files == nil then return nil; end
    local seen = {};
    for _, b in ipairs(files) do seen[b] = true; end
    local led = M.legacyExportsDir();
    if led ~= nil then
        for _, b in ipairs(listLuaFiles(led) or {}) do
            if not seen[b] then seen[b] = true; files[#files + 1] = b; end
        end
    end
    local out = {};
    for _, b in ipairs(files) do
        local meta = M.parseExportText(readExportText(b));
        if meta ~= nil then
            out[#out + 1] = { file = b, job = meta.job, profile = meta.profile, from = meta.from,
                              sets = type(meta.sets) == 'string', trig = type(meta.triggers) == 'string',
                              ls = type(meta.lockstyles) == 'string', wts = type(meta.weights) == 'string' };
        end
    end
    return out;
end

-- Raw text of one dlac-exports file (the Profiles menu's "view text" button,
-- Henrik 2026-07-20: copy the whole export to the clipboard and paste it to
-- a friend -- no file hunting). Returns text | nil, why.
function M.readExportRaw(fileBase)
    local ed = M.exportsDir();
    if ed == nil then return nil, 'not available'; end
    local base = tostring(fileBase or '');
    if base == '' or base:find('[/\\]') ~= nil or base:find('%.%.', 1, true) ~= nil then
        return nil, 'bad file name';
    end
    local text = readExportText(base);
    if text == nil then return nil, 'no such export: ' .. base; end
    return text, nil;
end

-- Delete one export file from dlac-exports\ (the Profiles menu's x button;
-- Henrik 2026-07-20). Only the shared file goes -- profiles imported from it
-- keep their copies. Returns true | nil, why.
function M.deleteExport(fileBase)
    local ed = M.exportsDir();
    if ed == nil then return nil, 'not available'; end
    local base = tostring(fileBase or '');
    if base == '' or base:find('[/\\]') ~= nil or base:find('%.%.', 1, true) ~= nil then
        return nil, 'bad file name';
    end
    local path = ed .. base .. '.lua';
    if readFile(path) == nil then return nil, 'no such export: ' .. base; end
    if os.remove(path) == nil and readFile(path) ~= nil then
        return nil, 'could not delete ' .. path;
    end
    return true;
end

-- Apply a PARSED export (parseExportText's meta) into dstCharFolder/dstProf
-- under dstName -- the shared core of the file import AND the paste import
-- (Henrik 2026-07-20: "Import from text"). Collision handling, same round
-- ("having to rename back and forth is annoying"):
--   opts.overwrite  = true   -> an existing job of that name is replaced;
--   opts.backupName = 'Old'  -> the existing files are RENAMED to that name
--                               first (a dormant archive in the same profile,
--                               revivable via Rename); without it they still
--                               get deleteJobAt's verified safety copies in
--                               backups\deleted-jobs\ before removal.
-- Payloads are parse-checked before anything is touched. Returns
-- n, nil | nil, why, isCollision -- isCollision=true when ONLY the name
-- collision stopped it, so callers can offer Overwrite instead of a dead end.
function M.importJobMeta(meta, dstCharFolder, dstProf, dstName, opts)
    if type(meta) ~= 'table' then return nil, 'not a dlac job export'; end
    dstName = M.sanitizeName(dstName);
    if dstName == nil then return nil, 'bad name (letters/digits/_/- only)'; end
    dstProf = M.sanitizeName(dstProf);
    if dstProf == nil then return nil, 'bad profile name (letters/digits/_/- only)'; end
    if type(meta.sets) == 'string' and (loadstring or load)(meta.sets) == nil then
        return nil, 'export is damaged: sets payload does not parse';
    end
    if type(meta.triggers) == 'string' and (loadstring or load)(meta.triggers) == nil then
        return nil, 'export is damaged: triggers payload does not parse';
    end
    if type(meta.lockstyles) == 'string' and (loadstring or load)(meta.lockstyles) == nil then
        return nil, 'export is damaged: lockstyles payload does not parse';
    end
    opts = (type(opts) == 'table') and opts or {};
    if M.jobNameTakenAt(dstCharFolder, dstProf, dstName) then
        if opts.overwrite ~= true then
            return nil, 'name collision: "' .. dstName .. '" already exists in that profile', true;
        end
        if opts.backupName ~= nil then
            local bn = M.sanitizeName(opts.backupName);
            if bn == nil then return nil, 'bad backup name (letters/digits/_/- only)'; end
            if bn == dstName then return nil, 'the backup name must differ from the imported name'; end
            local rn, rerr = M.renameJobAt(dstCharFolder, dstProf, dstName, bn);
            if rn == nil then return nil, 'could not keep the old job: ' .. tostring(rerr); end
        else
            local dn, derr = M.deleteJobAt(dstCharFolder, dstProf, dstName);
            if dn == nil then return nil, 'could not clear the old job: ' .. tostring(derr); end
        end
    end
    if not ensureStorageAt(dstCharFolder, dstProf) then return nil, 'could not create storage'; end
    local dstDir = M.profileDirAt(dstCharFolder, dstProf);
    local n = 0;
    if type(meta.sets) == 'string' and readFile(dstDir .. 'sets\\' .. dstName .. '.lua') == nil
       and writeFile(dstDir .. 'sets\\' .. dstName .. '.lua', meta.sets) then n = n + 1; end
    if type(meta.triggers) == 'string' and readFile(dstDir .. 'triggers\\' .. dstName .. '.lua') == nil
       and writeFile(dstDir .. 'triggers\\' .. dstName .. '.lua', meta.triggers) then n = n + 1; end
    if type(meta.lockstyles) == 'string' and readFile(dstDir .. 'lockstyles\\' .. dstName .. '.lua') == nil
       and writeFile(dstDir .. 'lockstyles\\' .. dstName .. '.lua', meta.lockstyles) then n = n + 1; end
    if n == 0 then return nil, 'nothing imported'; end
    return n, nil;
end

-- Import an export file into any character/profile under dstName -- a thin
-- read+parse shell over importJobMeta (same opts / same returns).
function M.importJobFile(fileBase, dstCharFolder, dstProf, dstName, opts)
    if M.exportsDir() == nil then return nil, 'not available'; end
    local meta, merr = M.parseExportText(readExportText(fileBase));
    if meta == nil then return nil, merr; end
    return M.importJobMeta(meta, dstCharFolder, dstProf, dstName, opts);
end

-- Import another character's profile into THIS character under dstName.
-- Refuses to pour into a profile that already has files (no silent merges).
-- Returns copiedCount, nil | nil, why.
function M.importProfile(srcCharFolder, srcName, dstName)
    dstName = M.sanitizeName(dstName);
    if dstName == nil then return nil, 'bad target name (letters/digits/_/- only)'; end
    if charBase() == nil then return nil, 'not logged in'; end
    local srcDir = M.profileDirAt(srcCharFolder, srcName);
    if srcDir == nil then return nil, 'bad source'; end
    if profileHasFiles(dstName) then return nil, 'profile "' .. dstName .. '" already has files here -- pick another name'; end
    if not M.ensureStorage(dstName) then return nil, 'could not create storage'; end
    local n = copyJobFiles(srcDir, M.profileDir(dstName));
    if n == 0 then return nil, 'nothing copied (source profile empty or unreadable)'; end
    return n, nil;
end

-- Copy every per-job sets/triggers file from one profile to another (the
-- export/import primitive: a profile is just these files). Deterministic 22-job
-- probe -- no directory listing API needed. Never overwrites dst files.
function M.cloneProfile(src, dst)
    src, dst = M.sanitizeName(src), M.sanitizeName(dst);
    if src == nil or dst == nil then return nil, 'bad profile name'; end
    if not M.ensureStorage(dst) then return nil, 'not logged in'; end
    local copied = 0;
    for _, job in ipairs(M.JOBS) do
        for _, kind in ipairs(M.KINDS) do
            local sp = M.profileDir(src) .. kind .. '\\' .. job .. '.lua';
            local dp = M.profileDir(dst) .. kind .. '\\' .. job .. '.lua';
            local t = readFile(sp);
            if t ~= nil and readFile(dp) == nil then
                if writeFile(dp, t) then copied = copied + 1; end
            end
        end
    end
    return copied, nil;
end

-- ---------------------------------------------------------------------------
-- the profile sets file
--
-- Same shape as the block dlac used to commit into <JOB>.lua, so setmanager's
-- field-proven spliceSet/deleteSetText scanners work on it UNCHANGED:
--     local sets = { Dynamic = { <Name> = { <Slot> = { entries } } } };
--     return sets;
-- ---------------------------------------------------------------------------

local SETS_HEADER = '-- dlac profile sets -- committed by the Sets tab; hand edits are fine.\n'
    .. '-- Loaded for the ACTIVE profile (dlac\\profile.lua); gear refs resolve via your gear.lua.\n';

-- Wrap a 'Dynamic = { ... }' block (extractDynamicText output, or a fresh empty
-- one) into a complete profile sets file. Pure text; offline-tested.
function M.frameSetsText(dynText)
    if type(dynText) ~= 'string' or dynText == '' then dynText = 'Dynamic = {\n    }'; end
    return SETS_HEADER .. 'local sets = {\n    ' .. dynText .. ',\n};\nreturn sets;\n';
end

-- The four base sets the starter trigger rules target, EMPTY. Every sets file
-- dlac seeds starts from this (fresh Setup, and a migration that found no
-- Dynamic block) so a new job never complains about missing trigger targets
-- before the player builds anything (Henrik, 2026-07-17).
M.starterDynText = 'Dynamic = {\n'
    .. '        Idle       = {},\n'
    .. '        Tp_Default = {},\n'
    .. '        Resting    = {},\n'
    .. '        Movement   = {},\n'
    .. '    }';

-- Missing-gear-safe view of the gear inventory for LOADING a sets file. A
-- shared/imported profile references items the reader may not own: a missing
-- ITEM must resolve to nil (a ladder hole -- BuildDynamicSets iterates with
-- pairs, so the next rung the reader DOES own is picked), and a missing
-- weapon CATEGORY (gear.Main.Club on a char who never scanned a club) must
-- NOT error the whole chunk away. Present tables pass through REAL, so
-- resolved entries stay identity-shared with gear.lua / NameToObject.
local EMPTYCAT = setmetatable({}, { __newindex = function() end });   -- reads nil, writes ignored
local function wrapGearForRead(gearT)
    local catProxy = setmetatable({}, {
        __index = function(t, slot)   -- per-slot proxies, built once
            local real = gearT[slot];
            if type(real) ~= 'table' then return EMPTYCAT; end
            local p = setmetatable({}, {
                __index = function(_, k)
                    local v = real[k];
                    if v ~= nil then return v; end
                    -- Only Main/Range nest by weapon category (gear.Main.Club.X);
                    -- everything else (Sub included) stores items flat, where a
                    -- missing key must be a nil LADDER HOLE, not a table.
                    return (slot == 'Main' or slot == 'Range') and EMPTYCAT or nil;
                end,
            });
            rawset(t, slot, p);
            return p;
        end,
    });
    return catProxy;
end
M._wrapGear = wrapGearForRead;   -- exported for the offline tests

-- Load the profile sets file and return its Dynamic table (name -> set), or
-- nil + why. `gear` is provided from THIS state's gear inventory (wrapped
-- missing-safe, see above), so entries point into the same tables everything
-- else uses (LAC state: <char>\dlac\ copy; addon state: the preloaded char
-- gear; tests: the stub).
function M.readSetsFile(job, name)
    local p = M.setsPath(job, name);
    if p == nil then return nil, 'not logged in'; end
    local chunk = loadfile(p);
    if chunk == nil then return nil, 'no profile sets file'; end
    local gok, gearT = pcall(require, 'dlac\\gear');
    local env = setmetatable({ gear = wrapGearForRead((gok and type(gearT) == 'table') and gearT or {}) },
                             { __index = function(_, k) return rawget(_G, k); end });
    if setfenv ~= nil then setfenv(chunk, env); end
    local ok, ret = pcall(chunk);
    local s = (ok and type(ret) == 'table') and ret or rawget(env, 'sets');
    if type(s) == 'table' and type(s.Dynamic) == 'table' then return s.Dynamic, nil; end
    return nil, ok and ('no Dynamic table in ' .. p) or ('error running ' .. p .. ': ' .. tostring(ret));
end

function M.hasSetsFile(job, name)
    return readFile(M.setsPath(job, name)) ~= nil;
end
function M.hasTriggersFile(job, name)
    return readFile(M.triggersPath(job, name)) ~= nil;
end

-- ---------------------------------------------------------------------------
-- pure text helpers (offline-tested)
-- ---------------------------------------------------------------------------

-- Brace-aware scanner: from the '{' at byte i, the matching '}' index, skipping
-- comments and strings. COPIED from setmanager.lua (addon-state module -- the
-- LAC state can't require it); keep the two in sync.
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

-- The whole 'Dynamic = { ... }' block out of a job file, VERBATIM -- byte-for-byte
-- is the migration's "your dynamic sets survive" guarantee (comments, wrappers,
-- minLevel gates and all). nil + why when the file has no block.
function M.extractDynamicText(text)
    if type(text) ~= 'string' then return nil, 'no file text'; end
    local ds, de = text:find('Dynamic%s*=%s*{');
    if ds == nil then return nil, 'no sets.Dynamic block'; end
    local close = matchBrace(text, de);
    if close == nil then return nil, 'sets.Dynamic block is not closed'; end
    return text:sub(ds, close), nil;
end

-- ---------------------------------------------------------------------------
-- the clean job-file shim
-- ---------------------------------------------------------------------------

-- Marker line: migration and Setup recognize a shim by it and never touch the
-- file again. Keep the prefix stable forever; bump the (vN) on shape changes.
M.SHIM_MARKER = '-- dlac profile shim';

M.BOOT_LINE = [[package.path = package.path .. ';' .. AshitaCore:GetInstallPath() .. 'addons\\?.lua';  -- dlac: use the dlac addon library]];

-- The shim body. Mirrors gearui's STARTER_PROFILE (OnLoad/Packer kept so
-- /lac addset still works) minus any set data: the engine installs the active
-- profile's sets over the empty scaffold at load / job change / profile switch.
local SHIM_BODY = [[
-- dlac profile shim (v1) -- managed by dlac. Do not keep data here:
--   sets     live in  <char>\dlac\profiles\<active>\sets\<JOB>.lua      (Sets tab)
--   triggers live in  <char>\dlac\profiles\<active>\triggers\<JOB>.lua  (Triggers tab)
-- Your original file (if you migrated) is in <char>\backups\pre-profiles\.
local profile = {};
local utils = require("dlac\\utils");   -- everything comes through this one require
local gear  = utils.gear;               -- the shared gear inventory
local sets = {
    Dynamic = {},                       -- filled by the engine from the active dlac profile
};
profile.Sets = sets;

profile.Packer = {
};

profile.OnLoad = function()
    gSettings.AllowAddSet = true;
end

profile.OnUnload = function()
end

profile.HandleCommand = function(args)
end

-- All equip logic is data: utils.dispatch reads the active profile's trigger file
-- (hot-reloaded -- edit triggers in the dlac GUI or the file; no /lac reload needed).
profile.HandleDefault = function()
    sets = utils.rebuildSets(sets);
    utils.dispatch('Default');
end

profile.HandleAbility     = function() utils.dispatch('Ability');     end
profile.HandleItem        = function() utils.dispatch('Item');        end
profile.HandlePrecast     = function() utils.dispatch('Precast');     end
profile.HandleMidcast     = function() utils.dispatch('Midcast');     end
profile.HandlePreshot     = function() utils.dispatch('Preshot');     end
profile.HandleMidshot     = function() utils.dispatch('Midshot');     end
profile.HandleWeaponskill = function() utils.dispatch('Weaponskill'); end

return profile;
]];

function M.shimFileText()
    return M.BOOT_LINE .. '\n' .. SHIM_BODY;
end

function M.isCleanShim(text)
    return type(text) == 'string' and text:find(M.SHIM_MARKER, 1, true) ~= nil;
end

-- ---------------------------------------------------------------------------
-- migration
-- ---------------------------------------------------------------------------

-- Pure planner: given per-job facts, decide what would happen. files is a list of
--   { job, text, hasBackup, hasProfileSets, hasLegacyTrig, hasProfileTrig }
-- Returns a list of { job, action = 'skip'|'migrate', reason, dynText|nil,
-- reshim|nil, notes = {...} }.
--
-- THE SETUP STANDARD (Henrik, 2026-07-17): a job file that holds logic is NEVER
-- left live -- the only file dlac ever leaves in charge is the clean shim. Old
-- handler code running underneath dlac's dispatch was the old convert-in-place
-- model, and it produced equip conflicts nobody can support at install scale.
-- So the ONLY skip is "already a clean shim". A file that was migrated before
-- and holds logic again (restored / hand-edited) is re-shimmed too: the FIRST
-- backup is the pre-profiles truth and is never overwritten -- the current text
-- goes to a stamped side copy instead (reshim = true).
function M.planMigration(files)
    local plan = {};
    for _, f in ipairs(files) do
        local e = { job = f.job, notes = {} };
        if M.isCleanShim(f.text) then
            e.action, e.reason = 'skip', 'already a clean dlac shim';
        else
            e.action = 'migrate';
            if f.hasBackup then
                e.reshim = true;
                e.notes[#e.notes + 1] = 'first backup exists and stays UNTOUCHED -- the current file text is saved as a stamped copy next to it';
            end
            local dyn, derr = M.extractDynamicText(f.text);
            if f.hasProfileSets then
                e.notes[#e.notes + 1] = 'profile sets file already exists -- kept as-is (job file\'s Dynamic block NOT imported over it)';
            elseif dyn ~= nil then
                e.dynText = dyn;
                e.notes[#e.notes + 1] = 'dynamic sets move into the profile verbatim';
            else
                e.notes[#e.notes + 1] = 'no dynamic sets to import (' .. tostring(derr) .. ') -- profile sets file starts with the four empty base sets';
            end
            if f.hasLegacyTrig and not f.hasProfileTrig then
                e.notes[#e.notes + 1] = 'trigger file moves into the profile (original kept in backups\\pre-profiles\\triggers\\)';
            elseif f.hasLegacyTrig and f.hasProfileTrig then
                e.notes[#e.notes + 1] = 'profile trigger file already exists -- legacy one left in place, IGNORED from now on';
            end
            e.notes[#e.notes + 1] = 'the job file is rewritten as a clean dlac shim (original -> backups\\pre-profiles\\)';
        end
        plan[#plan + 1] = e;
    end
    return plan;
end

-- ---------------------------------------------------------------------------
-- native-home storage migration (feature/native-engine)
--
-- Moving to the native engine moves storage from LuaAshitacast's config tree
-- into config\addons\dlac\. The move is a COPY -- the legacy files stay put
-- untouched, so flipping back to LAC mode finds everything exactly where it
-- was. Never overwrites: a file already present in the native home wins (it
-- may hold newer native-mode edits). Two subtrees ride:
--     <char>\dlac\**      ->  <nativeRoot>\<char>\**          (the data home)
--     <char>\backups\**   ->  <nativeRoot>\<char>\backups\**  (pre-profiles
--                              statics: "Copy from static" keeps working)
-- ---------------------------------------------------------------------------

-- Pure planner: which relative paths need copying. srcRels = array of relpaths
-- ('profiles\\Default\\sets\\WHM.lua'); dstHas = set of relpaths already in the
-- native home. Rejects absolute paths and '..' outright (walker output is
-- trusted, but the rule is cheap and the tests pin it). Returns copy list,
-- skip list -- both sorted for deterministic reporting.
function M.planEngineCopy(srcRels, dstHas)
    local copy, skip = {}, {};
    for _, rel in ipairs(srcRels or {}) do
        if type(rel) == 'string' and rel ~= ''
           and rel:find('%.%.') == nil and rel:match('^[%a]:') == nil and rel:sub(1, 1) ~= '\\' then
            if dstHas ~= nil and dstHas[rel] then skip[#skip + 1] = rel;
            else copy[#copy + 1] = rel; end
        end
    end
    table.sort(copy); table.sort(skip);
    return copy, skip;
end

-- Recursive file listing under dir, as base-relative paths. Uses the same two
-- listing APIs the rest of this module rides (get_dir non-recursive + `dir /b`
-- popen fallbacks), walking directories level by level. Depth-capped: nothing
-- dlac stores nests deeper than profiles\<Name>\<kind>\<JOB>.lua.
local function listFilesRecursive(dir, prefix, depth, acc)
    if depth > 6 or dir == nil then return acc; end
    -- files at this level: names with an extension shape (listDirs mixes files
    -- and dirs; a dot separates the two populations in every tree dlac owns)
    for _, e in ipairs(listDirs(dir) or {}) do
        if e:find('%.') ~= nil then
            acc[#acc + 1] = prefix .. e;
        else
            listFilesRecursive(dir .. e .. '\\', prefix .. e .. '\\', depth + 1, acc);
        end
    end
    return acc;
end

local function readFileB(p)
    if p == nil then return nil; end
    local f = io.open(p, 'rb'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end
local function writeFileB(p, t)
    if p == nil then return false; end
    local f = io.open(p, 'wb'); if f == nil then return false; end
    f:write(t); f:close(); return true;
end

-- Copy one subtree (never overwrite, byte-verify every write). Returns
-- copied, skipped, failed.
local function copyTree(srcBase, dstBase)
    local rels = listFilesRecursive(srcBase, '', 0, {});
    local dstHas = {};
    for _, rel in ipairs(rels) do
        if readFileB(dstBase .. rel) ~= nil then dstHas[rel] = true; end
    end
    local copy, skip = M.planEngineCopy(rels, dstHas);
    local done, failed = 0, 0;
    for _, rel in ipairs(copy) do
        local bytes = readFileB(srcBase .. rel);
        if bytes == nil then
            failed = failed + 1;
        else
            ensureDirChain(dstBase, rel);
            if writeFileB(dstBase .. rel, bytes) and readFileB(dstBase .. rel) == bytes then
                done = done + 1;
            else
                failed = failed + 1;
            end
        end
    end
    return done, #skip, failed;
end

-- The storage migration for THIS character. Copies the legacy dlac data home
-- and backups\ into the native home. Safe to re-run any time (idempotent:
-- existing native files are skipped). Returns copied, skipped, failed -- or
-- nil, why. Works regardless of the current mode flag (so the engine command
-- can migrate BEFORE flipping native on).
function M.engineMigrateStorage()
    local b = charBase();
    local nb = M.nativeCharBase();
    if b == nil or nb == nil then return nil, 'not logged in'; end
    ensureDir(M.nativeRoot());
    ensureDir(nb);
    local d1, s1, f1 = copyTree(b .. 'dlac\\', nb);
    ensureDir(nb .. 'backups\\');
    local d2, s2, f2 = copyTree(b .. 'backups\\', nb .. 'backups\\');
    return d1 + d2, s1 + s2, f1 + f2;
end

-- Auto-migration: when native mode is ON but this character's native home is
-- still empty (no active-profile pointer) while the legacy home has one, run
-- the copy -- so every character on the install migrates itself the first time
-- it logs in after the flip, and characters created later are simply born
-- native. Cheap when settled (two file probes). Returns true when it ran.
function M.engineAutoMigrate(say)
    if not M.nativeMode() then return false; end
    local b = charBase();
    local nb = M.nativeCharBase();
    if b == nil or nb == nil then return false; end
    if readFileB(nb .. 'profile.lua') ~= nil then return false; end   -- already migrated (or born native)
    if readFileB(b .. 'dlac\\profile.lua') == nil and readFileB(b .. 'dlac\\gear.lua') == nil then
        return false;   -- nothing legacy to bring over
    end
    local done, skipped, failed = M.engineMigrateStorage();
    if say ~= nil and done ~= nil then
        say(string.format('[dlac] native storage: migrated %d file(s) from the LuaAshitacast tree (%d already here, %d failed).',
            done, skipped, failed));
    end
    return true;
end

-- Gather per-job facts from disk for every <JOB>.lua that exists.
local function migrationFacts(name)
    local files = {};
    for _, job in ipairs(M.JOBS) do
        local text = readFile(M.jobFilePath(job));
        if text ~= nil then
            files[#files + 1] = {
                job = job, text = text,
                hasBackup      = readFile(M.backupPath(job)) ~= nil,
                hasProfileSets = M.hasSetsFile(job, name),
                hasLegacyTrig  = readFile(M.legacyTriggersPath(job)) ~= nil,
                hasProfileTrig = M.hasTriggersFile(job, name),
            };
        end
    end
    return files;
end

-- The current plan against the real char folder, for DISPLAY (the GUI Setup
-- popup renders it before asking for a Commit). nil, why when not logged in.
function M.currentPlan(name)
    if charBase() == nil then return nil, 'not logged in'; end
    return M.planMigration(migrationFacts(name or 'Default'));
end

-- The migration itself. execute=false prints the full plan and touches NOTHING;
-- execute=true does the work file by file, each step verified before the next
-- (backup is read back and compared before the original is ever rewritten).
-- Returns migratedCount, skippedCount, failedCount.
function M.migrate(execute, say)
    say = say or print;
    local name = 'Default';   -- migration always lands in Default; switch/clone after
    if charBase() == nil then say('[dlac] profile migrate: log in first.'); return 0, 0, 0; end
    local files = migrationFacts(name);
    if #files == 0 then say('[dlac] profile migrate: no <JOB>.lua files found.'); return 0, 0, 0; end
    local plan = M.planMigration(files);

    if not execute then
        say('[dlac] profile migration PLAN (dry run -- nothing was touched):');
        for _, e in ipairs(plan) do
            if e.action == 'skip' then
                say(string.format('[dlac]   %s: skip -- %s', e.job, e.reason));
            else
                say(string.format('[dlac]   %s: migrate', e.job));
                for _, n in ipairs(e.notes) do say('[dlac]       - ' .. n); end
            end
        end
        say('[dlac] run  /dl profile migrate go  to execute. Every original lands in backups\\pre-profiles\\ first.');
        return 0, 0, 0;
    end

    M.ensureStorage(name);
    local b = M.charRoot();   -- backups follow the active storage home
    ensureDir(b .. 'backups\\');
    ensureDir(b .. 'backups\\pre-profiles\\');
    ensureDir(b .. 'backups\\pre-profiles\\triggers\\');

    local done, skipped, failed = 0, 0, 0;
    for i, e in ipairs(plan) do
        local f = files[i];
        if e.action == 'skip' then
            skipped = skipped + 1;
            say(string.format('[dlac] %s: skipped -- %s', e.job, e.reason));
        else
            local okAll = true;
            -- 1) backup the original, read it back, compare. NOTHING is rewritten
            --    until this byte-identical copy is proven on disk. A re-migration
            --    (reshim) never overwrites the first backup: the current text goes
            --    to a stamped copy -- unless it IS the first backup, byte for byte,
            --    in which case there is nothing new to save.
            local bp = M.backupPath(e.job);
            if e.reshim then
                bp = (readFile(bp) ~= f.text) and M.reshimBackupPath(e.job) or nil;
            end
            if bp ~= nil and (not writeFile(bp, f.text) or readFile(bp) ~= f.text) then
                say(string.format('[dlac] %s: FAILED -- could not verify backup at %s; file untouched.', e.job, tostring(bp)));
                okAll = false;
            end
            -- 2) profile sets file (only when absent; verbatim Dynamic block --
            --    or, when the old file had none, the four empty base sets the
            --    starter triggers target, so nothing complains out of the box).
            if okAll and not f.hasProfileSets then
                local framed = M.frameSetsText(e.dynText or M.starterDynText);
                local lok = (loadstring or load)(framed);
                if lok == nil then
                    say(string.format('[dlac] %s: FAILED -- framed sets file would not parse; file untouched (backup kept).', e.job));
                    okAll = false;
                elseif not writeFile(M.setsPath(e.job, name), framed) then
                    say(string.format('[dlac] %s: FAILED -- could not write profile sets file; job file untouched.', e.job));
                    okAll = false;
                end
            end
            -- 3) trigger file: copy -> verify -> backup -> remove legacy.
            if okAll and f.hasLegacyTrig and not f.hasProfileTrig then
                local ttext = readFile(M.legacyTriggersPath(e.job));
                if ttext ~= nil and writeFile(M.triggersPath(e.job, name), ttext)
                   and readFile(M.triggersPath(e.job, name)) == ttext
                   and writeFile(M.triggerBackupPath(e.job), ttext) then
                    pcall(os.remove, M.legacyTriggersPath(e.job));
                else
                    say(string.format('[dlac] %s: trigger move failed -- legacy trigger file left in place (still read as fallback).', e.job));
                end
            end
            -- 4) the job file becomes the clean shim. LAST, so any failure above
            --    leaves the original fully in charge.
            if okAll then
                if writeFile(M.jobFilePath(e.job), M.shimFileText()) then
                    done = done + 1;
                    say(string.format('[dlac] %s: MIGRATED -- original: backups\\pre-profiles\\%s.lua; sets: dlac\\profiles\\%s\\sets\\%s.lua; %s.lua is now a clean shim.',
                        e.job, e.job, name, e.job, e.job));
                else
                    failed = failed + 1;
                    say(string.format('[dlac] %s: FAILED -- could not rewrite %s.lua (backup + profile files are in place).', e.job, e.job));
                end
            else
                failed = failed + 1;
            end
        end
    end
    say(string.format('[dlac] profile migration done: %d migrated, %d skipped, %d failed. Statics from your old files stay available to "Copy from" via backups\\pre-profiles\\.',
        done, skipped, failed));
    return done, skipped, failed;
end

return M;
