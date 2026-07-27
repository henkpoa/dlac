--[[
    dlac/feature/wishlist.lua -- gear you MEAN to own (ADR 0026).

    A Wishlist entry is an ENTITY: keyed by item Id, it exists on its own, and
    dlac never creates or deletes one behind your back. It carries one free-text
    note and any number of LINKS -- "this is for WHM", "this is for WHM/Idle".

    The two halves that make this file safe to trust:

      * LINKS ARE INTENTIONS, stored here, never revoked. You may link a piece to
        a set you have not put it in -- that is the point: the set stays clean
        while the intention is recorded. Whether the piece is ACTUALLY in that
        set is read live from the set file by the UI (wishlistui.linkFacts) and
        shown beside the link. The two are allowed to disagree.
      * OWNERSHIP IS A FACT, never stored. M.isOwned reads the bags by Id
        (ownedcache) every time, so an entry can never claim you still have
        something you sold. There is nothing to reconcile because there is
        nothing cached to go stale.

    ENGINE SEAM (the other reason this module exists). utils.BuildDynamicSets
    cannot resolve a wishlisted name against gear.lua -- correctly: it skips the
    entry, so the slot's real best-by-level pick wins and an unowned piece can
    never shadow gear you own. But warnMissingGear then prints "typo, or not yet
    indexed" for a name you put there ON PURPOSE, once per commit, forever.
    utils asks M.isWished(name) and stays quiet for names on this list. That is
    why the file read below must NOT drag in the GUI: ownedcache/gearimport are
    required lazily, at call time, only on the paths that need bags.

    File format (<char>\dlac\wishlist.lua) -- id-keyed, name carried because the
    engine has no catalog to look one up in:
        return {
          [13795] = { name = "Arhats Gi", note = "Sky drop",
                      links = { { job = "WHM", set = "Idle" }, { job = "RDM" } } },
        }

    Pure seams for the headless suite (tests WL*): normName, serialize, fromRaw,
    addLinkTo, sameLink. They take plain values and return plain values -- no
    imgui, no Ashita, no disk.
]]--

local M = {};

M.VERSION = 1;

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

local _sfile = try('dlac\\lib\\statefile');
local _safe  = try('dlac\\lib\\safewrite');

-- ---------------------------------------------------------------------------
-- Pure helpers
-- ---------------------------------------------------------------------------

-- The comparison key for an item NAME. Lowercase kills the "Solid wand" vs
-- "Solid Wand" spread that hand-written and migrated sets carry; dropping the
-- apostrophe bridges the API's spelling to the client's -- the catalog says
-- "Arhats Gi" where gear.lua says "Arhat's Gi" (and, inconsistently, the API
-- KEEPS the one in "San D'Orian"), so the strip has to happen on BOTH sides of
-- every comparison, never as a one-way fix-up.
--
-- utils.resolveGearName carries the same two-line transform inline rather than
-- requiring this module: it runs in the engine's rebuild path, which must not
-- gain a load-time dependency on a feature module. Change one, change the other.
function M.normName(s)
    if type(s) ~= 'string' then return ''; end
    return (string.gsub(string.lower(s), "'", ""));
end

-- Two links are the same when they name the same job AND the same set. A
-- job-only link ("RDM, figure it out later") is NOT the same as RDM/Nuke -- it
-- is a coarser wish that stands on its own.
function M.sameLink(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return false; end
    return tostring(a.job or '') == tostring(b.job or '')
       and tostring(a.set or '') == tostring(b.set or '');
end

-- Append a link to a list unless an identical one is already there. Returns the
-- list and whether anything changed -- pure, so the dedupe rule is testable
-- without a character or disk.
function M.addLinkTo(links, job, set)
    links = (type(links) == 'table') and links or {};
    if type(job) ~= 'string' or job == '' then return links, false; end
    local want = { job = job, set = (type(set) == 'string' and set ~= '') and set or nil };
    for _, l in ipairs(links) do
        if M.sameLink(l, want) then return links, false; end
    end
    links[#links + 1] = want;
    return links, true;
end

-- Normalize a parsed file (or any caller's table) into the shape the rest of
-- this module assumes. Anything malformed is DROPPED rather than repaired: a
-- half-understood entry that silences a warning is worse than no entry.
function M.fromRaw(t)
    local out = {};
    if type(t) ~= 'table' then return out; end
    for id, e in pairs(t) do
        local nid = tonumber(id);
        if nid ~= nil and type(e) == 'table' and type(e.name) == 'string' and e.name ~= '' then
            local links = {};
            if type(e.links) == 'table' then
                for _, l in ipairs(e.links) do
                    if type(l) == 'table' and type(l.job) == 'string' and l.job ~= '' then
                        M.addLinkTo(links, l.job, l.set);
                    end
                end
            end
            out[nid] = {
                id    = nid,
                name  = e.name,
                note  = (type(e.note) == 'string') and e.note or '',
                links = links,
            };
        end
    end
    return out;
end

-- Serialize to the file format. Ids ascending and links in list order, so a
-- file with nothing changed is byte-identical -- the engine's raw-text compare
-- then skips the re-parse (the pinwatch/profilesets watch idiom).
function M.serialize(entries)
    local ids = {};
    for id, e in pairs(entries or {}) do
        if tonumber(id) ~= nil and type(e) == 'table' and type(e.name) == 'string' then
            ids[#ids + 1] = tonumber(id);
        end
    end
    table.sort(ids);
    if #ids == 0 then return 'return { }\n'; end
    local out = { 'return {\n' };
    for _, id in ipairs(ids) do
        local e = entries[id] or entries[tostring(id)];
        local parts = {};
        for _, l in ipairs(e.links or {}) do
            parts[#parts + 1] = (l.set ~= nil and l.set ~= '')
                and string.format('{ job = %q, set = %q }', tostring(l.job), tostring(l.set))
                or  string.format('{ job = %q }', tostring(l.job));
        end
        out[#out + 1] = string.format('  [%d] = { name = %q, note = %q, links = { %s } },\n',
            id, tostring(e.name), tostring(e.note or ''), table.concat(parts, ', '));
    end
    out[#out + 1] = '}\n';
    return table.concat(out);
end

-- ---------------------------------------------------------------------------
-- Disk
-- ---------------------------------------------------------------------------

M.entries = {};            -- [id] -> { id, name, note, links }

local _loadedFrom = nil;   -- the path M.entries mirrors (nil = never loaded)
local _watchRaw   = nil;   -- last bytes seen, for the content-keyed re-read
local _watchAt    = -1;    -- frame/clock guard so the engine seam is not a disk hammer

function M.path()
    local dir = (_sfile ~= nil) and _sfile.charDir() or nil;
    return dir and (dir .. 'wishlist.lua') or nil;
end

local function readAll(p)
    if p == nil then return nil; end
    local f = io.open(p, 'r');
    if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end

-- Read the file if we have not, or if its BYTES changed since we last looked.
-- Content-keyed rather than time-keyed: a commit rewrites the file in place and
-- an mtime at one-second resolution can miss that (the profilesets lesson).
-- Cheap by design -- the throttle means the engine's per-flatten call costs one
-- stat-sized read at most once a second.
function M.load(force)
    local p = M.path();
    if p == nil then return M.entries; end       -- pre-login: nothing to read yet
    local now = os.time();
    if not force and _loadedFrom == p and now == _watchAt then return M.entries; end
    _watchAt = now;
    local raw = readAll(p);
    if raw == nil then                            -- no file = nothing wishlisted
        if _loadedFrom ~= p then M.entries = {}; _watchRaw = nil; _loadedFrom = p; end
        return M.entries;
    end
    if not force and _loadedFrom == p and raw == _watchRaw then return M.entries; end
    _watchRaw, _loadedFrom = raw, p;
    local chunk = (loadstring or load)(raw, '@' .. p);   -- 5.1 vs 5.4 (WSL CI parity)
    local ok, t = pcall(function() return chunk and chunk() or nil; end);
    M.entries = (ok and type(t) == 'table') and M.fromRaw(t) or {};
    return M.entries;
end

function M.save()
    local p = M.path();
    if p == nil then return false, 'not logged in (no character folder yet)'; end
    local text = M.serialize(M.entries);
    local ok = false;
    if _safe ~= nil and type(_safe.replaceLua) == 'function' then
        ok = _safe.replaceLua(p, text) and true or false;
    end
    if not ok then                                -- plain write fallback
        local f = io.open(p, 'w');
        if f == nil then return false, 'could not write ' .. p; end
        f:write(text); f:close();
        ok = true;
    end
    -- Keep the watch in step with what we just wrote, so the next load() does
    -- not re-parse our own bytes.
    _watchRaw, _loadedFrom, _watchAt = text, p, os.time();
    return ok;
end

-- ---------------------------------------------------------------------------
-- Entries
-- ---------------------------------------------------------------------------

function M.get(id)
    id = tonumber(id);
    if id == nil then return nil; end
    M.load();
    return M.entries[id];
end

-- Add (or return the existing entry). Idempotent by Id -- adding the same piece
-- twice from two surfaces must never produce two rows.
function M.add(id, name)
    id = tonumber(id);
    if id == nil or type(name) ~= 'string' or name == '' then return nil, false; end
    M.load();
    local e = M.entries[id];
    if e ~= nil then return e, false; end
    e = { id = id, name = name, note = '', links = {} };
    M.entries[id] = e;
    M.save();
    return e, true;
end

function M.remove(id)
    id = tonumber(id);
    if id == nil then return false; end
    M.load();
    if M.entries[id] == nil then return false; end
    M.entries[id] = nil;
    M.save();
    return true;
end

function M.setNote(id, note)
    local e = M.get(id);
    if e == nil then return false; end
    e.note = (type(note) == 'string') and note or '';
    M.save();
    return true;
end

function M.addLink(id, job, set)
    local e = M.get(id);
    if e == nil then return false; end
    local _, changed = M.addLinkTo(e.links, job, set);
    if changed then M.save(); end
    return changed;
end

function M.removeLink(id, job, set)
    local e = M.get(id);
    if e == nil then return false; end
    local want = { job = job, set = set };
    for i, l in ipairs(e.links) do
        if M.sameLink(l, want) then
            table.remove(e.links, i);
            M.save();
            return true;
        end
    end
    return false;
end

function M.hasLink(id, job, set)
    local e = M.get(id);
    if e == nil then return false; end
    local want = { job = job, set = set };
    for _, l in ipairs(e.links) do if M.sameLink(l, want) then return true; end end
    return false;
end

function M.count()
    M.load();
    local n = 0;
    for _ in pairs(M.entries) do n = n + 1; end
    return n;
end

-- Every entry as an array. Unsorted on purpose: the window owns display order
-- (owned-first, then slot), and it needs the catalog to know a slot at all.
function M.list()
    M.load();
    local out = {};
    for _, e in pairs(M.entries) do out[#out + 1] = e; end
    return out;
end

-- ---------------------------------------------------------------------------
-- Ownership -- read, never stored (ADR 0026)
-- ---------------------------------------------------------------------------

-- ownedcache is required HERE, lazily, and not at the top of the file: the
-- engine seam below must be reachable without dragging the bag scanner into a
-- rebuild that has no use for it.
function M.isOwned(id)
    id = tonumber(id);
    if id == nil then return false; end
    local oc = try('dlac\\gear\\ownedcache');
    if oc == nil or type(oc.totals) ~= 'function' then return false; end
    local ok, t = pcall(oc.totals);
    if not ok or type(t) ~= 'table' then return false; end
    return (t[id] or 0) >= 1;
end

-- Which entries just FLIPPED into owned since the last call. Session-only state
-- (a fresh login re-seeds silently on the first call) -- the point is to notice
-- the moment, not to keep a history. Returns an array of entries; the first
-- call after a load primes and reports nothing, so logging in wearing your
-- wishlist does not spray chat.
local _seenOwned, _primed = {}, false;
function M.newlyOwned()
    M.load();
    local fresh = {};
    for id, e in pairs(M.entries) do
        local own = M.isOwned(id);
        if own and _primed and not _seenOwned[id] then fresh[#fresh + 1] = e; end
        _seenOwned[id] = own or nil;
    end
    _primed = true;
    return fresh;
end

function M._resetSeen() _seenOwned, _primed = {}, false; end   -- test seam

-- ---------------------------------------------------------------------------
-- Engine seam
-- ---------------------------------------------------------------------------

-- Is this set-entry name one the player deliberately put on the wishlist?
-- utils.warnMissingGear asks before printing "typo, or not yet indexed": a
-- wishlisted name is an INTENTION, and warning about it every commit would
-- read as a bug dlac introduced. A name that is neither resolvable nor
-- wishlisted is still a typo and still warns.
--
-- Fails CLOSED-to-warning on purpose: no file, no character, a parse error --
-- every one of them answers false, so the old behaviour is exactly preserved
-- and the warning can never be lost to a broken wishlist.
function M.isWished(name)
    if type(name) ~= 'string' or name == '' then return false; end
    local ok = pcall(M.load);
    if not ok then return false; end
    local want = M.normName(name);
    for _, e in pairs(M.entries) do
        if M.normName(e.name) == want then return true; end
    end
    return false;
end

-- Test seam: drop every cached fact so a suite can point the module at a fresh
-- fixture without a process restart.
function M._reset()
    M.entries, _loadedFrom, _watchRaw, _watchAt = {}, nil, nil, -1;
    M._resetSeen();
end

return M;
